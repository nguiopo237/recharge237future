import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../report/report_service.dart' show ReportConfig;
import '../server/firestore_backoff.dart';
import 'loyalty_rules.dart';

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

  /// Fenêtre relue à chaque passage. Assez large pour rattraper un téléphone
  /// resté hors ligne, assez courte pour ne pas relire la journée entière.
  static const Duration _fenetre = Duration(hours: 3);

  /// Cadence : un client qui vient de recharger voit ses points en quelques
  /// minutes, sans marteler la base.
  static const Duration _periode = Duration(minutes: 10);

  Timer? _timer;
  String _deviceId = '';
  LoyaltyConfig _config = const LoyaltyConfig();
  Map<String, double> _commissions = const <String, double>{};

  LoyaltyConfig get config => _config;
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
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
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
  }

  // ── Le job ───────────────────────────────────────────────────────────────

  /// Crédite les points des commandes livrées qui ne l'ont pas encore été et
  /// rend le nombre de commandes créditées. Appelable à la main (commande à
  /// distance de l'admin).
  Future<int> sweep() async {
    if (!_config.actif || _deviceId.isEmpty) return 0;
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

  /// Écriture atomique : solde + journal + marqueur de commande + statistique
  /// du jour, ensemble ou pas du tout.
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

    try {
      return await db.runTransaction<bool>((Transaction tx) async {
        // Toutes les lectures AVANT la moindre écriture (exigence Firestore).
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

        // ── Écritures ───────────────────────────────────────────────────────
        tx.set(
          portefeuille,
          <String, dynamic>{
            'uid': uid,
            'solde': solde + points,
            'gagnesTotal': gagnes + points,
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
          'soldeApres': solde + points,
          'at': FieldValue.serverTimestamp(),
        });

        // Marqueur sur la commande : c'est lui qui évite de la relire au
        // passage suivant.
        tx.update(commande, <String, dynamic>{
          'loyalty': points,
          'loyalty_at': FieldValue.serverTimestamp(),
        });

        // Statistique du jour : lue par le bilan Telegram (1 lecture) pour
        // que l'admin voit chaque jour ce que le programme coûte.
        tx.set(
          stats,
          <String, dynamic>{
            'jour': _cle(maintenant),
            'points': FieldValue.increment(points),
            'commandes': FieldValue.increment(1),
            'volume': FieldValue.increment(montant),
          },
          SetOptions(merge: true),
        );

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
