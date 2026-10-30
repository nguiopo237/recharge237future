import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../report/report_service.dart' show ReportConfig;
import '../server/firestore_backoff.dart';
import 'loyalty_rules.dart';
import 'redemption_rules.dart';
import 'referral_rules.dart';

/// [FIDÉLITÉ 31/10/2026] Crédit des points de fidélité — LOT 1 : le gain, le
/// porte-monnaie et le journal. Aucun point n'est encore dépensé ici.
///
/// POURQUOI ICI ET PAS DANS LE CLIENT : c'est exactement ce que la version
/// cliente de la fidélité ne pouvait pas faire (cf. `loyalty_service.dart`
/// côté application : « pas de cashback, le client ne peut rien arbitrer en
/// sécurité »). Le téléphone serveur, lui, tourne jour et nuit, possède les
/// droits admin et voit les commandes réellement LIVRÉES. C'est donc lui qui
/// transforme une vente en points, dans une transaction Firestore atomique.
///
/// POURQUOI UN BALAYEUR ET PAS UN APPEL DANS CHAQUE GESTIONNAIRE USSD : le
/// statut de livraison est écrit à une bonne dizaine d'endroits (MTN crédit,
/// MTN Boost, activation de forfait, interactions P2P, actions manuelles de
/// l'admin, relecture de SMS...). Brancher chacun d'eux serait fragile : il
/// suffirait d'en oublier un pour perdre définitivement les points d'un
/// client. Le balayeur relit les commandes récentes encore sans marqueur
/// `loyalty` et les crédite — un seul point de passage, aucun oubli possible,
/// et une commande livrée par un chemin inattendu est rattrapée au passage
/// suivant (au plus 10 minutes plus tard).
///
/// IDEMPOTENCE À TROIS NIVEAUX, comme pour la relance des forfaits :
///   1. le document de commande porte `loyalty` (points crédités) ;
///   2. le journal du client est écrit sous l'IDENTIFIANT de la commande :
///      un doublon est impossible même si le marqueur était perdu ;
///   3. tout se fait DANS UNE SEULE TRANSACTION, donc deux téléphones
///      serveurs ne peuvent pas créditer deux fois.
///
/// COÛT EN QUOTA (plan gratuit) : une requête bornée à 3 h de commandes,
/// toutes les 10 minutes, et seulement 2 lectures + 3 écritures par commande
/// réellement créditée.
class LoyaltyService {
  LoyaltyService._();
  static final LoyaltyService instance = LoyaltyService._();

  static const String _collConfig = 'app_config';
  static const String _docLoyalty = 'loyalty';
  static const String _docReport = 'report';
  static const String _collLoyalty = 'loyalty';
  static const String _collStats = 'loyalty_stats';
  static const String _collTransact = 'Transact';

  /// [PARRAINAGE 31/10/2026] Relation de parrainage PAYANT, écrite par le
  /// filleul au moment où il saisit un code, avec l'UID DU FILLEUL comme
  /// identifiant de document.
  ///
  /// L'identifiant déterministe est ce qui rend le paiement sûr : dans la
  /// transaction de crédit, une simple lecture de document suffit à savoir
  /// s'il y a un parrain à payer (une requête ne serait pas possible dans
  /// une transaction, et coûterait un balayage complet).
  static const String _collParrainages = 'parrainages';
  static const String _docReferral = 'referral';

  /// [CONVERSION 31/10/2026] Demandes de conversion de points écrites par le
  /// client, servies par ce service : `{uid, montant, operateur, numero,
  /// statut}`. Aucune écriture client ne peut créditer quoi que ce soit — la
  /// collection est en lecture seule pour lui une fois créée.
  static const String _collRedemptions = 'loyalty_redemptions';

  /// Fenêtre relue à chaque passage. Assez large pour rattraper un téléphone
  /// resté hors ligne, assez courte pour ne pas relire la journée entière.
  static const Duration _fenetre = Duration(hours: 3);

  /// Cadence : un client qui vient de recharger voit ses points en quelques
  /// minutes, sans marteler la base.
  static const Duration _periode = Duration(minutes: 10);

  /// [CONVERSION 31/10/2026] Cadence des conversions : une minute. Un client
  /// qui demande à convertir attend devant son écran ; dix minutes seraient
  /// perçues comme une panne. Une requête bornée à 5 documents par minute
  /// reste négligeable en lecture, même sur le plan gratuit.
  static const Duration _periodeConversions = Duration(minutes: 1);

  Timer? _timer;
  Timer? _conversionsTimer;
  String _deviceId = '';
  LoyaltyConfig _config = const LoyaltyConfig();
  RedemptionConfig _redemption = const RedemptionConfig();
  ReferralConfig _referral = const ReferralConfig();
  Map<String, double> _commissions = const <String, double>{};

  /// [KILL SWITCH 31/10/2026] `app_config/services_status.programme_fidelite`.
  /// Lu au plus toutes les 5 minutes : couper le programme depuis la console
  /// prend effet en moins de 10 minutes (cadence du balayeur), sans
  /// redémarrer l'application serveur.
  bool _killSwitch = true;
  DateTime? _killLuLe;

  LoyaltyConfig get config => _config;
  ReferralConfig get referralConfig => _referral;
  Map<String, double> get commissions => _commissions;

  /// Taux en vigueur, pour l'affichage et le bilan Telegram.
  Map<String, LoyaltyRate> get taux =>
      tousLesTaux(commissions: _commissions, config: _config);

  Future<void> start(String deviceId) async {
    if (_timer != null && _deviceId == deviceId) return;
    _deviceId = deviceId;
    await rechargerConfig();
    _timer?.cancel();
    _timer = Timer.periodic(_periode, (_) => sweep());
    if (_config.actif) {
      final Map<String, LoyaltyRate> t = taux;
      debugPrint('[Fidélité] actif — ${t.isEmpty ? 'aucun taux configuré' : t.entries.map((MapEntry<String, LoyaltyRate> e) => '${e.key}: ${e.value.description}').join(' · ')}');
      // [MARGE 31/10/2026] Verrou des 40 % : on le CONTRÔLE à chaque
      // démarrage, plutôt que de le supposer. Une violation (taux mal saisi)
      // apparaît dans les journaux, pas sur les bénéfices.
      final List<String> violations = verifierPlancher(
        commissions: _commissions,
        config: _config,
      );
      if (violations.isNotEmpty) {
        debugPrint('[Fidélité] ⚠️ PLANCHER VIOLÉ : ${violations.join(' ; ')}');
      }
      final List<String> plafonnes = t.values
          .where((LoyaltyRate r) => r.plafonne)
          .map((LoyaltyRate r) => r.operateur)
          .toList();
      if (plafonnes.isNotEmpty) {
        debugPrint('[Fidélité] barème ramené au plafond des 40 % pour : '
            '${plafonnes.join(', ')}');
      }
    } else {
      debugPrint('[Fidélité] désactivé par app_config/loyalty');
    }
    // Rattrapage au démarrage : un téléphone éteint à l'heure du dernier
    // passage crédite ce qui lui reste dans la fenêtre.
    await sweep();

    // [CONVERSION 31/10/2026] File des conversions : cadence courte, et un
    // premier passage immédiat pour servir ce qui attendait un redémarrage.
    _conversionsTimer?.cancel();
    _conversionsTimer = Timer.periodic(
        _periodeConversions, (_) => sweepRedemptions());
    await sweepRedemptions();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _conversionsTimer?.cancel();
    _conversionsTimer = null;
  }

  /// Relit `app_config/loyalty` (réglages du programme) ET
  /// `app_config/report` (taux de commission par opérateur — la source de
  /// vérité de la marge, déjà utilisée par le bilan comptable : on ne crée
  /// pas un second endroit où saisir les mêmes taux).
  Future<void> rechargerConfig() async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> doc = await FirebaseFirestore
          .instance
          .collection(_collConfig)
          .doc(_docLoyalty)
          .get()
          .timeout(const Duration(seconds: 10));
      _config = LoyaltyConfig.fromMap(doc.data());
      // [CONVERSION 31/10/2026] Même document, autres clés : un seul endroit
      // où régler le programme.
      _redemption = RedemptionConfig.fromMap(doc.data());
    } catch (e) {
      debugPrint('[Fidélité] config par défaut : $e');
    }
    try {
      final DocumentSnapshot<Map<String, dynamic>> doc = await FirebaseFirestore
          .instance
          .collection(_collConfig)
          .doc(_docReport)
          .get()
          .timeout(const Duration(seconds: 10));
      _commissions = ReportConfig.fromMap(doc.data()).commissions;
      if (_commissions.isEmpty) {
        debugPrint('[Fidélité] aucune commission dans app_config/report : '
            'aucun point ne sera distribué.');
      }
    } catch (e) {
      debugPrint('[Fidélité] commissions illisibles : $e');
    }
    try {
      final DocumentSnapshot<Map<String, dynamic>> doc = await FirebaseFirestore
          .instance
          .collection(_collConfig)
          .doc(_docReferral)
          .get()
          .timeout(const Duration(seconds: 10));
      _referral = ReferralConfig.fromMap(doc.data());
      debugPrint('[Parrainage] ${_referral.actif ? 'actif' : 'coupé'} — '
          'max ${_referral.maxParJour}/jour, '
          'bonus filleul ${_referral.bonusFilleul ? 'oui' : 'non'}');
    } catch (e) {
      debugPrint('[Parrainage] config par défaut : $e');
    }
  }

  // ── Le job ───────────────────────────────────────────────────────────────

  /// Crédite les points des commandes livrées qui ne l'ont pas encore été et
  /// rend le nombre de commandes créditées. Appelable à la main (commande à
  /// distance de l'admin).
  Future<int> sweep() async {
    if (!_config.actif || _deviceId.isEmpty) return 0;
    if (!await _serviceActif()) return 0;
    if (FirestoreBackoff.instance.enPause) return 0;

    final DateTime depuis = DateTime.now().subtract(_fenetre);
    QuerySnapshot<Map<String, dynamic>> snap;
    try {
      snap = await FirebaseFirestore.instance
          .collection(_collTransact)
          .where('heure', isGreaterThanOrEqualTo: _iso(depuis.toUtc()))
          .limit(300)
          .get()
          .timeout(const Duration(seconds: 25));
      FirestoreBackoff.instance.succes();
    } catch (e) {
      if (FirestoreBackoff.estTransitoire(e)) {
        FirestoreBackoff.instance.echec(e);
      } else {
        debugPrint('[Fidélité] lecture des commandes refusée : $e');
      }
      return 0;
    }

    int creditees = 0;
    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in snap.docs) {
      if (FirestoreBackoff.instance.enPause) break;
      final Map<String, dynamic> d = doc.data();

      // Une seule décision, pure et testée : tout le reste (transaction,
      // marqueurs) ne fait qu'exécuter ce verdict.
      final DecisionCredit decision = decisionCredit(
        commande: d,
        commissions: _commissions,
        config: _config,
      );
      if (!decision.crediter) continue;

      final String uid = (d['idphone'] ?? '').toString().trim();
      final bool ok = await _crediter(
        commande: doc.reference,
        uid: uid,
        points: decision.points,
        montant: montantLisible(d['amount']) ?? 0,
        operateur: (d['operateur_cible'] ?? '').toString().trim().toLowerCase(),
        rate: decision.taux!,
        offre: (d['retry'] ?? '').toString(),
      );
      if (ok) {
        creditees++;
        debugPrint('[Fidélité] +${decision.points} pts → $uid');
      }
    }

    if (creditees > 0) {
      debugPrint('[Fidélité] $creditees commande(s) créditée(s) '
          'sur ${snap.size} relue(s)');
    }
    return creditees;
  }

  /// Interrupteur du programme côté admin (`services_status`).
  ///
  /// En cas d'échec de lecture, on garde la dernière valeur connue (et
  /// `true` au premier démarrage) : une panne de configuration ne doit pas
  /// arrêter de créditer des points légitimes — c'est le même choix que
  /// côté client, et il est borné par le plafond des 40 %.
  Future<bool> _serviceActif() async {
    final DateTime? dernier = _killLuLe;
    if (dernier != null &&
        DateTime.now().difference(dernier) < const Duration(minutes: 5)) {
      return _killSwitch;
    }
    try {
      final DocumentSnapshot<Map<String, dynamic>> doc =
          await FirebaseFirestore.instance
              .collection(_collConfig)
              .doc('services_status')
              .get()
              .timeout(const Duration(seconds: 8));
      final Object? v = doc.data()?['programme_fidelite'];
      final bool actif = v is bool
          ? v
          : (v is String ? v.trim().toLowerCase() != 'false' : true);
      if (!actif && _killSwitch) {
        debugPrint('[Fidélité] programme coupé par l\'admin '
            '(app_config/services_status)');
      }
      _killSwitch = actif;
    } catch (e) {
      debugPrint('[Fidélité] interrupteur illisible, dernière valeur '
          'conservée ($_killSwitch) : $e');
    }
    _killLuLe = DateTime.now();
    return _killSwitch;
  }

  /// Écriture atomique : solde + journal + marqueur de commande + parrainage
  /// éventuel + statistique du jour, ensemble ou pas du tout.
  ///
  /// [PARRAINAGE 31/10/2026 — LOT 2] La récompense est payée ICI, dans la
  /// même transaction que le crédit normal, et seulement si cette commande
  /// est le PREMIER achat éligible du filleul (`commandesEligibles == 0`
  /// avant crédit). Deux téléphones serveurs ne peuvent donc pas payer deux
  /// fois le même filleul, et un filleul qui recharge dix fois ne rapporte
  /// rien de plus : la récompense est attachée à la commande, pas à une date.
  ///
  /// COÛT EN LECTURES : le document `parrainages/{filleul}` est lu au plus
  /// une fois par VIE de client (ensuite `statut` n'est plus `en_attente`),
  /// et les autres lectures n'ont lieu que pour un filleul non encore traité.
  Future<bool> _crediter({
    required DocumentReference<Map<String, dynamic>> commande,
    required String uid,
    required int points,
    required int montant,
    required String operateur,
    required LoyaltyRate rate,
    required String offre,
  }) async {
    final FirebaseFirestore db = FirebaseFirestore.instance;
    final DocumentReference<Map<String, dynamic>> portefeuille =
        db.collection(_collLoyalty).doc(uid);
    // L'identifiant de la commande comme identifiant de journal : deux
    // crédits de la même commande ne peuvent pas coexister, même si le
    // marqueur de la commande était perdu.
    final DocumentReference<Map<String, dynamic>> journal =
        portefeuille.collection('journal').doc(commande.id);
    final DateTime maintenant = DateTime.now();
    final DocumentReference<Map<String, dynamic>> stats =
        db.collection(_collStats).doc(_cle(maintenant));
    // Relation de parrainage du client qui vient d'acheter (document dont
    // l'identifiant EST son uid).
    final DocumentReference<Map<String, dynamic>> lien =
        db.collection(_collParrainages).doc(uid);

    try {
      return await db.runTransaction<bool>((Transaction tx) async {
        // ══ LECTURES (toutes avant la moindre écriture, exigence Firestore) ═
        final DocumentSnapshot<Map<String, dynamic>> c = await tx.get(commande);
        final Map<String, dynamic>? cd = c.data();
        if (cd == null) return false;
        if (cd['loyalty'] != null) return false;

        final DocumentSnapshot<Map<String, dynamic>> j = await tx.get(journal);
        if (j.exists) return false;

        final DocumentSnapshot<Map<String, dynamic>> w =
            await tx.get(portefeuille);
        final Map<String, dynamic>? wd = w.data();
        final int solde = (wd?['solde'] as num?)?.toInt() ?? 0;
        final int gagnes = (wd?['gagnesTotal'] as num?)?.toInt() ?? 0;
        final int utilises = (wd?['utilisesTotal'] as num?)?.toInt() ?? 0;
        final int commandes = (wd?['commandesEligibles'] as num?)?.toInt() ?? 0;
        final bool premierAchat = commandes == 0;

        // ── Parrainage : uniquement sur le premier achat éligible ───────────
        DecisionParrainage? decision;
        DocumentSnapshot<Map<String, dynamic>>? portefeuilleParrain;
        bool lienEnAttente = false;
        String parrain = '';
        if (premierAchat) {
          final DocumentSnapshot<Map<String, dynamic>> ref = await tx.get(lien);
          final Map<String, dynamic>? rd = ref.data();
          if (rd != null) {
            parrain = (rd['parrainUid'] ?? '').toString().trim();
            lienEnAttente = (rd['statut'] ?? 'en_attente').toString() == 'en_attente';
          }
          if (lienEnAttente) {
            final Map<String, dynamic>? pf =
                (await tx.get(db.collection('users').doc(uid))).data();
            final Map<String, dynamic>? pp = parrain.isEmpty
                ? null
                : (await tx.get(db.collection('users').doc(parrain))).data();
            // Boucle A→B→A : le parrain est-il lui-même filleul du filleul ?
            final bool croise = parrain.isNotEmpty &&
                (await tx.get(db.collection(_collParrainages).doc(parrain)))
                        .data()?['parrainUid'] ==
                    uid;
            portefeuilleParrain = parrain.isEmpty
                ? null
                : await tx.get(db.collection(_collLoyalty).doc(parrain));
            final Map<String, dynamic>? pw = portefeuilleParrain?.data();
            final String cle = _cle(maintenant);
            // Compteur quotidien remis à zéro au changement de jour, sans
            // écriture de nettoyage : la clé du jour est stockée à côté.
            final int dejaAujourdhui =
                (pw?['parrainagesJourCle'] ?? '') == cle
                    ? ((pw?['parrainagesJour'] as num?)?.toInt() ?? 0)
                    : 0;

            decision = decisionParrainage(
              base: points,
              rate: rate,
              config: _referral,
              contexte: ContexteParrainage(
                filleulUid: uid,
                parrainUid: parrain,
                telephoneFilleul:
                    (pf?['phoneNumber'] ?? pf?['phone'])?.toString(),
                telephoneParrain:
                    (pp?['phoneNumber'] ?? pp?['phone'])?.toString(),
                appareilFilleul: pf?['deviceSerial']?.toString(),
                appareilParrain: pp?['deviceSerial']?.toString(),
                dejaRecompense: rd?['rewarded'] == true,
                premierAchatEligible: premierAchat,
                recompensesParrainAujourdhui: dejaAujourdhui,
                recompensesParrainTotal:
                    (pw?['parrainagesTotal'] as num?)?.toInt() ?? 0,
                parrainEstFilleulDuFilleul: croise,
              ),
            );
            if (!decision.recompenser) {
              debugPrint('[Parrainage] refusé ($uid → $parrain) : '
                  '${decision.motif}');
            }
          }
        }

        final int extraFilleul = decision?.pointsFilleulExtra ?? 0;
        final int pointsParrain = decision?.pointsParrain ?? 0;
        final bool paye = extraFilleul > 0 || pointsParrain > 0;

        // ══ ÉCRITURES ═══════════════════════════════════════════════════════
        tx.set(
          portefeuille,
          <String, dynamic>{
            'uid': uid,
            'solde': solde + points + extraFilleul,
            'gagnesTotal': gagnes + points + extraFilleul,
            'utilisesTotal': utilises,
            'commandesEligibles': commandes + 1,
            'derniereActivite': FieldValue.serverTimestamp(),
            // Expiration glissante : chaque nouvelle commande éligible
            // repousse l'échéance des points.
            'expireLe': Timestamp.fromDate(_expiration(maintenant)),
            if (!w.exists) 'creeLe': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        tx.set(journal, <String, dynamic>{
          'delta': points,
          'motif': 'recharge',
          'orderId': commande.id,
          'montant': montant,
          'operateur': operateur,
          'offre': offre,
          'taux': rate.pointsParTranche,
          'margeConserveePct': rate.margeConserveePct,
          'soldeApres': solde + points + extraFilleul,
          'at': FieldValue.serverTimestamp(),
        });

        // Le bonus du filleul est un mouvement SÉPARÉ : le client comprend
        // « +10 recharge » et « +10 parrainage » plutôt qu'un total opaque.
        if (extraFilleul > 0) {
          tx.set(journal.parent.doc('${commande.id}_parrainage'),
              <String, dynamic>{
            'delta': extraFilleul,
            'motif': 'parrainage',
            'orderId': commande.id,
            'montant': montant,
            'operateur': operateur,
            'parrain': parrain,
            'soldeApres': solde + points + extraFilleul,
            'at': FieldValue.serverTimestamp(),
          });
        }

        // ── Côté parrain : points + compteurs de plafond ─────────────────
        if (paye && portefeuilleParrain != null) {
          final Map<String, dynamic>? pw = portefeuilleParrain.data();
          final int pSolde = (pw?['solde'] as num?)?.toInt() ?? 0;
          final int pGagnes = (pw?['gagnesTotal'] as num?)?.toInt() ?? 0;
          final int pUtilises = (pw?['utilisesTotal'] as num?)?.toInt() ?? 0;
          final int pCommandes =
              (pw?['commandesEligibles'] as num?)?.toInt() ?? 0;
          final int pTotal =
              (pw?['parrainagesTotal'] as num?)?.toInt() ?? 0;
          final String cle = _cle(maintenant);
          final bool memeJour = (pw?['parrainagesJourCle'] ?? '') == cle;
          final int pJour =
              memeJour ? ((pw?['parrainagesJour'] as num?)?.toInt() ?? 0) : 0;

          tx.set(
            portefeuilleParrain.reference,
            <String, dynamic>{
              'uid': parrain,
              'solde': pSolde + pointsParrain,
              'gagnesTotal': pGagnes + pointsParrain,
              'utilisesTotal': pUtilises,
              'commandesEligibles': pCommandes,
              // Compteurs anti-abus : lus puis incrémentés DANS la même
              // transaction, donc le plafond des 5/jour ne peut pas être
              // dépassé par deux téléphones serveurs simultanés.
              'parrainagesTotal': pTotal + 1,
              'parrainagesJour': pJour + 1,
              'parrainagesJourCle': cle,
              'derniereActivite': FieldValue.serverTimestamp(),
              if (portefeuilleParrain.exists != true)
                'creeLe': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
          tx.set(
            portefeuilleParrain.reference.collection('journal').doc(commande.id),
            <String, dynamic>{
              'delta': pointsParrain,
              'motif': 'parrainage',
              'filleul': uid,
              'orderId': commande.id,
              'montant': montant,
              'soldeApres': pSolde + pointsParrain,
              'at': FieldValue.serverTimestamp(),
            },
          );
        }

        // La relation est CLOSE dans tous les cas : récompensée ou refusée,
        // elle ne sera plus jamais relue (aucun coût les fois suivantes).
        if (lienEnAttente) {
          tx.update(lien, paye
              ? <String, dynamic>{
                  'statut': 'recompense',
                  'rewarded': true,
                  'rewardedAt': FieldValue.serverTimestamp(),
                  'pointsParrain': pointsParrain,
                  'pointsFilleul': extraFilleul,
                  'orderId': commande.id,
                }
              : <String, dynamic>{
                  'statut': 'refuse',
                  'motif': decision?.motif ?? 'inconnu',
                  'verifieLe': FieldValue.serverTimestamp(),
                });
        }

        // Marqueur sur la commande : c'est lui qui évite de la relire au
        // passage suivant.
        tx.update(commande, <String, dynamic>{
          'loyalty': points,
          'loyalty_at': FieldValue.serverTimestamp(),
          if (paye)
            'parrainage': <String, dynamic>{
              'parrain': pointsParrain,
              'filleul': extraFilleul,
              'parrainUid': parrain,
            },
        });

        // Statistique du jour : lue par le bilan Telegram (1 lecture) pour
        // que l'admin voit chaque jour ce que le programme coûte — points de
        // fidélité ET parrainage séparément.
        tx.set(
          stats,
          <String, dynamic>{
            'jour': _cle(maintenant),
            'points': FieldValue.increment(points + extraFilleul),
            'pointsParrainage': FieldValue.increment(pointsParrain),
            'commandes': FieldValue.increment(1),
            'volume': FieldValue.increment(montant),
          },
          SetOptions(merge: true),
        );

        if (paye) {
          debugPrint('[Parrainage] récompensé : $uid → $parrain '
              '(+$extraFilleul au filleul, +$pointsParrain au parrain)');
        }

        return true;
      }).timeout(const Duration(seconds: 20));
    } catch (e) {
      if (FirestoreBackoff.estTransitoire(e)) {
        FirestoreBackoff.instance.echec(e);
      } else {
        debugPrint('[Fidélité] crédit impossible (${commande.id}) : $e');
      }
      return false;
    }
  }

  // ── Conversions de points (lot 3) ────────────────────────────────────────

  /// Sert les demandes de conversion en attente et rend le nombre de demandes
  /// traitées (acceptées ou refusées).
  ///
  /// POURQUOI UNE DEMANDE ET PAS UN DÉBIT DIRECT DEPUIS LE CLIENT : les points
  /// valent de l'argent. Si le client pouvait débiter son propre solde, il
  /// pourrait aussi créer la recharge correspondante sans que personne ne
  /// vérifie quoi que ce soit. Ici, le client écrit une INTENTION ; le serveur
  /// vérifie le palier, le solde et les plafonds, débite les points ET crée la
  /// commande dans la même transaction.
  Future<int> sweepRedemptions() async {
    if (!_config.actif || !_redemption.actif || _deviceId.isEmpty) return 0;
    if (!await _serviceActif()) return 0;
    if (FirestoreBackoff.instance.enPause) return 0;

    QuerySnapshot<Map<String, dynamic>> snap;
    try {
      snap = await FirebaseFirestore.instance
          .collection(_collRedemptions)
          .where('statut', isEqualTo: 'en_attente')
          .limit(5)
          .get()
          .timeout(const Duration(seconds: 20));
      FirestoreBackoff.instance.succes();
    } catch (e) {
      if (FirestoreBackoff.estTransitoire(e)) {
        FirestoreBackoff.instance.echec(e);
      } else {
        debugPrint('[Conversion] file des demandes illisible : $e');
      }
      return 0;
    }

    int traitees = 0;
    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in snap.docs) {
      if (FirestoreBackoff.instance.enPause) break;
      if (await _traiterRedemption(doc.id, doc.data())) traitees++;
    }
    if (traitees > 0) {
      debugPrint('[Conversion] $traitees demande(s) traitée(s)');
    }
    return traitees;
  }

  /// Traite UNE demande : débit des points, journal, et création de la
  /// commande de recharge — tout ensemble, ou rien.
  ///
  /// L'identifiant de la demande sert aussi d'identifiant de commande : le
  /// client peut suivre exactement la même référence qu'il vient de créer, et
  /// aucune commande ne peut être produite deux fois.
  Future<bool> _traiterRedemption(
      String id, Map<String, dynamic> donnees) async {
    final FirebaseFirestore db = FirebaseFirestore.instance;
    final String uid = (donnees['uid'] ?? '').toString().trim();
    final String operateur =
        (donnees['operateur'] ?? '').toString().trim().toLowerCase();
    final String numero =
        (donnees['numero'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
    if (uid.isEmpty || operateur.isEmpty || numero.isEmpty) {
      // Demande incomplète : on la refuse proprement plutôt que de la laisser
      // tourner éternellement dans la file.
      await FirebaseFirestore.instance
          .collection(_collRedemptions)
          .doc(id)
          .update(<String, dynamic>{
        'statut': 'refuse',
        'motif': 'demande incomplète (compte, opérateur ou numéro manquant)',
        'verifieLe': FieldValue.serverTimestamp(),
      });
      return false;
    }

    final DocumentReference<Map<String, dynamic>> demande =
        db.collection(_collRedemptions).doc(id);
    final DocumentReference<Map<String, dynamic>> portefeuille =
        db.collection(_collLoyalty).doc(uid);
    // Même identifiant que la demande : un débit de points ne peut pas
    // exister deux fois pour la même conversion.
    final DocumentReference<Map<String, dynamic>> journal =
        portefeuille.collection('journal').doc(id);
    final DocumentReference<Map<String, dynamic>> commande =
        db.collection(_collTransact).doc(id);
    final DateTime maintenant = DateTime.now();

    try {
      return await db.runTransaction<bool>((Transaction tx) async {
        // ── Lectures ──────────────────────────────────────────────────────
        final DocumentSnapshot<Map<String, dynamic>> r = await tx.get(demande);
        final Map<String, dynamic>? rd = r.data();
        if (rd == null) return false;
        if ((rd['statut'] ?? '') != 'en_attente') return false;

        final DocumentSnapshot<Map<String, dynamic>> j = await tx.get(journal);
        if (j.exists) return false; // déjà débitée

        final DocumentSnapshot<Map<String, dynamic>> w =
            await tx.get(portefeuille);
        final Map<String, dynamic>? wd = w.data();
        final int solde = (wd?['solde'] as num?)?.toInt() ?? 0;
        final String cle = _cle(maintenant);
        final int aujourdhui = (wd?['conversionsJourCle'] ?? '') == cle
            ? ((wd?['conversionsJour'] as num?)?.toInt() ?? 0)
            : 0;

        final DecisionRedemption decision = decisionRedemption(
          montant: rd['montant'],
          solde: solde,
          conversionsAujourdhui: aujourdhui,
          config: _redemption,
        );

        // ── Refus : tracé, jamais silencieux ─────────────────────────────
        if (!decision.valide) {
          tx.update(demande, <String, dynamic>{
            'statut': 'refuse',
            'motif': decision.motif,
            'verifieLe': FieldValue.serverTimestamp(),
          });
          debugPrint('[Conversion] refusée ($id, $uid) : ${decision.motif}');
          return true;
        }

        final int points = decision.points;

        // ── Débit des points ──────────────────────────────────────────────
        tx.set(
          portefeuille,
          <String, dynamic>{
            'uid': uid,
            'solde': solde - points,
            'utilisesTotal':
                ((wd?['utilisesTotal'] as num?)?.toInt() ?? 0) + points,
            'conversionsTotal':
                ((wd?['conversionsTotal'] as num?)?.toInt() ?? 0) + 1,
            'conversionsJour': aujourdhui + 1,
            'conversionsJourCle': cle,
            'derniereActivite': FieldValue.serverTimestamp(),
            if (!w.exists) 'creeLe': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        tx.set(journal, <String, dynamic>{
          'delta': -points,
          'motif': 'conversion',
          'orderId': id,
          'montant': points,
          'operateur': operateur,
          'numero': numero,
          'soldeApres': solde - points,
          'at': FieldValue.serverTimestamp(),
        });

        // ── La recharge elle-même : une commande payée, à livrer ──────────
        // `status: 1` est réservé à l'admin : c'est précisément ce qui rend
        // cette commande incréable par un client.
        tx.set(commande, <String, dynamic>{
          'amount': '$points',
          'idphone': uid,
          'numerocamtel': numero,
          'numeroorange': numero,
          'numerorecharge': numero,
          'status': '1',
          'heure': _iso(maintenant.toUtc()),
          'order': id,
          'idtransact': id,
          'retry': '0',
          'operateur_cible': operateur,
          'paiement': 'points',
          'loyalty_redemption': id,
          'created_at': FieldValue.serverTimestamp(),
        });

        tx.update(demande, <String, dynamic>{
          'statut': 'traite',
          'pointsDebites': points,
          'orderId': id,
          'traiteLe': FieldValue.serverTimestamp(),
        });

        debugPrint('[Conversion] $uid : $points pts → $operateur $numero');
        return true;
      }).timeout(const Duration(seconds: 20));
    } catch (e) {
      if (FirestoreBackoff.estTransitoire(e)) {
        FirestoreBackoff.instance.echec(e);
      } else {
        debugPrint('[Conversion] traitement impossible ($id) : $e');
      }
      return false;
    }
  }

  // ── Utilitaires ──────────────────────────────────────────────────────────

  DateTime _expiration(DateTime depuis) {
    final int mois = depuis.month - 1 + _config.validiteMois;
    return DateTime(depuis.year + mois ~/ 12, mois % 12 + 1, depuis.day);
  }

  static String _deux(int v) => v.toString().padLeft(2, '0');

  static String _cle(DateTime d) =>
      '${d.year}-${_deux(d.month)}-${_deux(d.day)}';

  /// Même format de date que les applications qui écrivent `heure`.
  static String _iso(DateTime utc) =>
      '${utc.year}-${_deux(utc.month)}-${_deux(utc.day)} '
      '${_deux(utc.hour)}:${_deux(utc.minute)}:${_deux(utc.second)}.'
      '${utc.millisecond.toString().padLeft(3, '0')}Z';
}
