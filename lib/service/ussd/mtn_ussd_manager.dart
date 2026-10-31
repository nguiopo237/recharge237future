import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../notification/client_push.dart';
import '../sendmail/send_mail.dart';
import '../server/server_manager.dart';
import 'session_config.dart';
import 'ussd_order_io.dart';
import 'ussd_result.dart';
import 'ussd_screens.dart';
import 'ussd_session.dart';

// [ORANGE 31/10/2026] Les résultats d'une session USSD sont désormais
// PARTAGÉS avec le manager Orange : ils vivent dans `ussd_result.dart` et sont
// réexportés ici, pour que tous les imports existants continuent de marcher.
export 'ussd_result.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Mots-clés de succès / d'échec MTN
// ─────────────────────────────────────────────────────────────────────────────
const _mtnSuccessKeywords = [
  'successfully',
  'succes',
  'succès',
  'success',
  'félicitations',
  'felicitations',
  'confirmed',
  'confirme',
  'confirmé',
  'traité',
  'traite',
  'effectué',
  'effectue',
  'avez vendu',
  'votre crédit',
  'top-up',
  'airtime',
  // [28/10/2026] Réponse réelle de MTN après une vente de crédit acceptée :
  // la transaction part en traitement et la confirmation arrive par SMS.
  // Sans ces phrases, une vente RÉUSSIE était classée « à vérifier ».
  'transaction est en cours',
  'vous recevrez votre confirmation',
  'confirmation par sms',
  'code de confirmation',
];

const _mtnFailKeywords = [
  'failed',
  'échoué',
  'echec',
  'échec',
  'insufficient',
  'solde insuffisant',
  'invalid',
  'invalide',
  'incorrect',
  'error',
  'erreur',
  'non disponible',
  'impossible',
];

/// Pilote les sessions USSD interactives pour MTN Cameroun.
///
/// **Chaque écran est lu avant d'être validé**, comme le ferait un humain :
/// le manager ne devine plus l'étape en cours, il regarde ce que MTN demande
/// (menu, montant, numéro, PIN) et répond en conséquence. Les délais viennent
/// du moteur [UssdSessionRunner], qui attend l'écran réel au lieu d'un délai
/// fixe.
///
/// **Workflow A — Vente de crédit Airtime**
/// ```
/// *126#  →  « Vendre du crédit »  →  montant  →  numéro client  →  PIN
/// ```
///
/// **Workflow B Phase 1 — Liste des forfaits**
/// ```
/// *126*7*[numéroClient]#  →  liste numérotée  (option « suite » / « 00 »)
/// ```
///
/// **Workflow B Phase 2 — Activation d'un forfait**
/// ```
/// *126*7*[numéroClient]#  →  [indexForfait]  →  (confirmation)  →  PIN
/// ```
class MtnUssdManager {
  MtnUssdManager._();
  static final MtnUssdManager instance = MtnUssdManager._();

  // ── Workflow A : Vente de crédit Airtime ──────────────────────────────────

  /// Lance la session USSD pour recharger [clientNumber] de [amount] FCFA.
  ///
  /// Met à jour le statut Firestore automatiquement :
  ///   • "20" = session en cours
  ///   • "21" = succès
  ///   • "22" = échec / timeout
  Future<UssdSessionResult> rechargeAirtime({
    required String docId,
    required String amount,
    required String clientNumber,
    required SimConfig sim,
  }) async {
    if (sim.pin.isEmpty) {
      debugPrint(
          '[MtnUssdManager] PIN MTN non configuré dans Firestore (servers/{id}.simMTN.pin)');
      await _write(docId, {
        'status': '22',
        'failure_reason':
            'PIN MTN non configuré sur ce téléphone (servers/{id}.simMTN.pin)',
      });
      return const UssdSessionResult(
          result: UssdResult.failed, rawMessage: 'PIN non configuré');
    }

    await _updateStatus(docId, '20');
    debugPrint(
        '[MtnUssdManager] Airtime → $clientNumber, $amount FCFA, slot=${sim.slot}');

    final UssdRunResult run = await UssdSessionRunner.instance.run(
      code: '*126#',
      slot: sim.slot,
      rules: [
        _ruleOptionFor('menu-vente-credit',
            ['vendre', 'vente de credit', 'vente de crédit']),
        _ruleMontant(amount),
        _ruleNumero(clientNumber),
        _rulePin(sim.pin),
      ],
      isSuccess: _isSuccessScreen,
      // Cinq pages de menu + choix de l'offre + confirmation + PIN + verdict.
      maxScreens: 14,
      // [RESEAU 28/10/2026] Une commande MTN ne part que sur une carte MTN :
      // la garde vérifie le réseau de l'emplacement ET son opérateur.
      expectedOperator: 'mtn',
    );

    // [RESEAU 28/10/2026] Garde réseau : rien n'a été composé. On ne marque
    // PAS un échec — la commande est gardée et repartira au retour du réseau.
    if (run.networkBlocked) {
      await _garder(docId, run, '1');
      return _toResult(run);
    }

    final result = _toResult(run);
    final success = result.result == UssdResult.success;

    await _write(docId, {
      'status': success ? '21' : '22',
      if (!success)
        'failure_reason': result.rawMessage.isEmpty
            ? 'Aucune réponse MTN (${result.result.name}, SIM ${sim.slot + 1}) — ${run.reason}'
            : '${result.result.name} : ${result.rawMessage}',
      'ussd_outcome': run.outcomeCode,
      'ussd_log': run.log,
      ..._timingFields(run),
    });

    debugPrint(
        '[MtnUssdManager] Airtime résultat: ${result.result} — ${run.reason}');
    return result;
  }

  // ── Workflow B Phase 1 : Récupérer la liste des forfaits ─────────────────

  /// Charge la liste des forfaits disponibles pour [clientNumber].
  ///
  /// Met à jour Firestore :
  ///   • "30" = requête en cours
  ///   • "31" = liste prête (stockée dans `forfait_list`)
  ///   • "32" = échec
  Future<List<String>> queryForfaitList({
    required String docId,
    required String clientNumber,
    required SimConfig sim,
    String operateur = 'mtn',
  }) async {
    // [OFFRES PERSO 29/10/2026] Code de requête réglé par l'admin
    // (`app_config/public.ussd_gooddeal_{mtn|orange}`). MTN : défaut
    // *126*7*{numero}#. Orange : aucun défaut, il doit être configuré.
    final String code = await _codeOffresPerso(operateur, clientNumber);
    if (code.isEmpty) {
      await _write(docId, {
        'status': '32',
        'failure_reason':
            'Offres ${operateur.toUpperCase()} indisponibles : code USSD '
                'non configuré (app_config/public.ussd_gooddeal_$operateur).',
      });
      unawaited(ClientPush.offresMtn(docId: docId, pretes: false));
      return const <String>[];
    }
    await _updateStatus(docId, '30');
    debugPrint(
        '[MtnUssdManager] ForfaitQuery $operateur → $clientNumber, slot=${sim.slot}');

    // « suite » / « 00 » charge la page suivante quand l'opérateur pagine.
    final UssdRunResult run = await UssdSessionRunner.instance.run(
      code: code,
      slot: sim.slot,
      rules: [
        UssdRule(
          label: 'page-suivante',
          // [PAGES 28/10/2026] MTN pagine la liste : « 00. Next », « 00) Suite »,
          // « 0. Plus »… On lit la touche SUR l'écran au lieu de la supposer.
          // « 00. Next » n'était pas reconnu : la session s'arrêtait sur la
          // première page en laissant la fenêtre ouverte pendant des heures.
          answer: (screen, done) => findMorePageKey(screen),
          // [PAGES 28/10/2026] Jusqu'à CINQ pages, avec arrêt immédiat dès
          // que la touche de suite disparaît :
          //  - pas de « 00 »/« next »/« suivant » sur l'écran → une seule page
          //    d'offres ; la règle ne correspond pas, le parcours se termine
          //    et la fenêtre est fermée par « Annuler » (cf. _closeDialog).
          //  - touche présente → on la saisit, page après page, tant que MTN
          //    en annonce une. Relevé réel : un numéro tient sur 1 page
          //    (674583531, deux offres), un autre en a 2. Quatre
          //    enchaînements = pages 2 à 5, et les offres de TOUTES les pages
          //    sont cumulées (offerLines, sans doublon).
          maxUses: 4,
        ),
      ],
      isCompleteWithoutCommit: _looksLikeOfferList,
      maxScreens: 12,
      // [RESEAU 28/10/2026] Requête gratuite : inutile de la lancer si la SIM
      // MTN n'a pas de réseau (ou si l'emplacement n'est pas une carte MTN).
      expectedOperator: operateur,
    );

    // [RESEAU 28/10/2026] Requête non lancée faute de réseau : commande gardée
    // (elle repart à 0 au retour du réseau), pas marquée « offres
    // indisponibles ».
    if (run.networkBlocked) {
      await _garder(docId, run, '0');
      return const <String>[];
    }

    final String rawFull =
        run.screens.isEmpty ? run.finalScreen : run.screens.join('\n');

    if (rawFull.trim().isEmpty || run.outcome == UssdOutcome.notExecuted) {
      // [RESEAU 28/10/2026] Quand aucun écran n'est arrivé, la cause est du
      // côté du réseau ou de la carte : `run.reason` le dit (hors réseau, mode
      // avion, mauvaise SIM...). Avant, la commande affichait seulement
      // « aucun écran capté », ce qui n'aidait pas l'admin.
      final String detail =
          run.screens.isEmpty ? run.reason : run.screens.join(' | ');
      await _write(docId, {
        'status': '32',
        'failure_reason':
            'Aucune offre MTN (${run.outcome.name}, SIM ${sim.slot + 1}) : $detail',
        'ussd_outcome': run.outcomeCode,
        'ussd_log': run.log,
        ..._timingFields(run),
      });
      // [OFFRES ASYNC 29/10/2026] Le client a pu fermer l'app : on le prévient.
      unawaited(ClientPush.offresMtn(docId: docId, pretes: false));
      return [];
    }

    // [PAGES 28/10/2026] Si la deuxieme page annonce encore une suite, on le
    // note dans la commande : l'admin saura qu'il existe d'autres offres que
    // MTN n'a pas montrees en deux pages, au lieu de le deviner.
    final bool autresPages = findMorePageKey(run.finalScreen) != null;

    final List<String> lines = offerLines(run.screens);
    // [PRIX 28/10/2026] Offres structurées : index + libellé complet (le prix
    // peut être sur la ligne suivante) + page. Elles servent de référence de
    // prix pour la passerelle, et de repère fiable à l'activation puisque MTN
    // renumérote parfois chaque page à partir de 1.
    final List<UssdOffer> records = offerRecords(run.screens);

    await _write(docId, {
      'forfait_list': lines,
      'forfait_offers': records.map((UssdOffer o) => o.toMap()).toList(),
      'pages_offres': run.screens.length,
      'autres_pages_annoncees': autresPages,
      'status': '31',
      'ussd_outcome': run.outcomeCode,
      'ussd_log': run.log,
      ..._timingFields(run),
    });

    // [OFFRES ASYNC 29/10/2026] « Vos offres MTN sont prêtes » au client.
    unawaited(ClientPush.offresMtn(
        docId: docId,
        pretes: true,
        nombre: records.isNotEmpty ? records.length : lines.length));
    debugPrint('[MtnUssdManager] Forfaits récupérés : ${lines.length} offres');
    return lines;
  }

  // ── Workflow B Phase 2 : Activer le forfait choisi ───────────────────────

  /// Active le forfait [forfaitIndex] (numéro dans la liste affichée)
  /// pour [clientNumber] après paiement confirmé.
  ///
  /// Met à jour Firestore :
  ///   • "33" = activation en cours
  ///   • "34" = succès
  ///   • "35" = échec / timeout
  ///
  /// [sourceOrder] : commande de requête qui a fourni les offres. Son prix MTN
  /// fait foi — un montant payé différent bloque l'activation.
  Future<UssdSessionResult> activateForfait({
    required String docId,
    required String clientNumber,
    required String forfaitIndex,
    required SimConfig sim,
    String sourceOrder = '',
    String operateur = 'mtn',
  }) async {
    if (sim.pin.isEmpty) {
      await _updateStatus(docId, '35');
      return const UssdSessionResult(
          result: UssdResult.failed, rawMessage: 'PIN non configuré');
    }

    // ── Garde anti-fraude sur le prix ────────────────────────────────────────
    // [PRIX 28/10/2026] Le prix de référence est celui que CE serveur a lu
    // dans le menu MTN (`forfait_offers` de la commande de requête). Un client
    // modifié peut déclarer le montant qu'il veut : sans ce contrôle il payait
    // 100 F pour une offre à 1 000 F et l'offre était activée quand même.
    final UssdOffer? offer = await _offerOf(sourceOrder, forfaitIndex);
    // [PRIX 31/10/2026] Le montant payé sert AUSSI à choisir l'offre dans le
    // menu de l'activation : il est donc lu ici, pas seulement dans la garde.
    final int paye = int.tryParse(await _paidAmountOf(docId)) ?? -1;
    if (offer != null) {
      final int? prix = offer.price;
      if (prix == null) {
        await _write(docId, {
          'status': '35',
          'failure_reason': 'Prix MTN illisible pour l’offre $forfaitIndex : '
              'activation refusée, aucun code composé.',
        });
        return UssdSessionResult(
          result: UssdResult.failed,
          rawMessage: 'Prix MTN illisible (offre $forfaitIndex)',
        );
      }
      if (paye != prix) {
        await _write(docId, {
          'status': '35',
          'failure_reason': 'Montant payé ($paye F) différent du prix MTN de '
              'l’offre ($prix F) : activation refusée, aucun code composé.',
        });
        return UssdSessionResult(
          result: UssdResult.failed,
          rawMessage: 'Montant payé ($paye F) ≠ prix MTN ($prix F)',
        );
      }
    }

    await _updateStatus(docId, '33');
    debugPrint(
        '[MtnUssdManager] ActivateForfait → $clientNumber, offre=$forfaitIndex, slot=${sim.slot}');

    // [OFFRES PERSO 29/10/2026] Même menu que la requête (code configuré).
    final String code = await _codeOffresPerso(operateur, clientNumber);
    if (code.isEmpty) {
      await _write(docId, {
        'status': '35',
        'failure_reason': 'Code USSD des offres ${operateur.toUpperCase()} non '
            'configuré : activation impossible, aucun code composé.',
      });
      return const UssdSessionResult(
          result: UssdResult.failed, rawMessage: 'Code USSD non configuré');
    }
    // [PRIX 31/10/2026] Vrai dès qu'une ligne portant le PRIX PAYÉ a été
    // trouvée et composée. Sinon, l'échec s'explique autrement (offre retirée
    // du menu entre la requête et l'achat) et il faut le dire clairement.
    bool offrePayeeTrouvee = false;
    final UssdRunResult run = await UssdSessionRunner.instance.run(
      code: code,
      slot: sim.slot,
      rules: [
        // L'offre choisie peut se trouver sur une page suivante : on ne saisit
        // son numéro que si elle est réellement affichée sur CET écran. Avant,
        // le premier écran de liste suffisait — on validait donc un numéro
        // d'offre qui n'existait pas encore à l'écran.
        UssdRule(
          label: 'choix-offre',
          answer: (screen, done) {
            // [PRIX 28/10/2026] On cherche d'abord l'offre par son LIBELLÉ :
            // MTN peut renuméroter chaque page à partir de 1, donc taper
            // « 3 » sur la première page où l'offre apparaît peut désigner
            // une autre offre.
            if (offer != null) {
              final String? parLibelle =
                  findOptionForLabel(screen, offer.label);
              if (parLibelle != null) {
                offrePayeeTrouvee = true;
                return parLibelle;
              }
            }
            // [PRIX 31/10/2026] PLUS JAMAIS l'index seul en repli. MTN fait
            // tourner son menu : un test réel a payé 100 F et le code a tapé
            // « 1 », qui désignait ce jour-là l'offre à 500 F — la carte a
            // été débitée de 500 F pour une vente de 100 F. On ne compose donc
            // une touche que si la ligne affichée porte EXACTEMENT le prix
            // payé.
            final String? parPrix = findOptionForPrice(screen, paye);
            if (parPrix != null) offrePayeeTrouvee = true;
            return parPrix;
          },
        ),
        UssdRule(
          label: 'page-suivante',
          answer: (screen, done) => findMorePageKey(screen),
          maxUses: 5,
        ),
        UssdRule(
          label: 'confirmer',
          answer: (screen, done) => _demandeConfirmation(screen) ? '1' : null,
        ),
        _rulePin(sim.pin),
      ],
      isSuccess: _isSuccessScreen,
      // Cinq pages de menu + choix de l'offre + confirmation + PIN + verdict.
      maxScreens: 14,
      // [RESEAU 28/10/2026] Une commande ne part que sur une carte du bon
      // opérateur : la garde vérifie le réseau de l'emplacement ET son
      // opérateur.
      expectedOperator: operateur,
    );

    // [RESEAU 28/10/2026] Même règle : rien n'a été composé, on garde.
    if (run.networkBlocked) {
      await _garder(docId, run, '1');
      return _toResult(run);
    }

    final result = _toResult(run);
    final success = result.result == UssdResult.success;

    await _write(docId, {
      'status': success ? '34' : '35',
      if (!success)
        'failure_reason': !offrePayeeTrouvee && paye > 0
            ? 'L’offre à $paye F n’était plus proposée par MTN pour ce '
                'numéro au moment de l’activation : aucune touche composée, '
                'rien n’a été vendu ni débité. Réessayez la consultation.'
            : (result.rawMessage.isEmpty
                ? 'Aucune réponse MTN (${result.result.name}, SIM ${sim.slot + 1}) — ${run.reason}'
                : '${result.result.name} : ${result.rawMessage}'),
      'ussd_outcome': run.outcomeCode,
      'ussd_log': run.log,
      'offre_payee_trouvee': offrePayeeTrouvee,
      ..._timingFields(run),
    });

    debugPrint(
        '[MtnUssdManager] Forfait résultat: ${result.result} — ${run.reason}');
    return result;
  }

  /// [OFFRES PERSO 29/10/2026] Code USSD des offres personnalisées de
  /// [operateur] pour [numero], lu dans `app_config/public` (1 lecture).
  ///
  /// [ORANGE 31/10/2026] Le menu Good Deal Orange est désormais connu :
  /// `#205*1*{numero}#` affiche les forfaits de CE numéro (phase 1 du
  /// parcours, avant le choix et le code secret). Il reste surchargeable
  /// depuis `app_config/public.ussd_gooddeal_orange`, sans redéployer.
  Future<String> _codeOffresPerso(String operateur, String numero) async {
    String regle =
        operateur == 'mtn' ? '*126*7*{numero}#' : '#205*1*{numero}#';
    try {
      final pub = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('public')
          .get();
      final String v =
          (pub.data()?['ussd_gooddeal_$operateur'] ?? '').toString().trim();
      if (v.contains('{numero}') || (v.startsWith('*') && v.endsWith('#'))) {
        regle = v;
      }
    } catch (e) {
      debugPrint('[MtnUssdManager] code des offres $operateur illisible : $e');
    }
    return regle.replaceAll('{numero}', numero);
  }

  // ── Forfaits du catalogue (29/10/2026) ───────────────────────────────────

  /// Active un forfait du CATALOGUE (Surf Day, Giga surf, MTN Home…) payé par
  /// le client, par le même menu que Boost.
  ///
  /// Le forfait est connu d'avance (document `Forfait` dont le `code` est
  /// dans `retry`) : le serveur compose le code, cherche la ligne de CE
  /// forfait sur l'écran affiché (prix, puis volume et durée), tape son
  /// numéro dès qu'il la voit et ne passe à la page suivante que si elle n'y
  /// est pas ; puis PIN, puis lecture du verdict.
  ///
  /// Le code de départ se règle dans `app_config/public.ussd_forfait_mtn`
  /// (défaut `*126*7*{numero}#`, le menu de Boost), sans republier l'app.
  ///
  /// Statuts : "33" en cours, "34" activé, "35" échec (raison écrite).
  Future<UssdSessionResult> activateCatalogBundle({
    required String docId,
    required String clientNumber,
    required String forfaitCode,
    required SimConfig sim,
  }) async {
    // [CATALOGUE 29/10/2026] Un échec n'est pas un remboursement : le client
    // a payé, l'ADMIN active le forfait à la main. Il est prévenu sur
    // Telegram avec tout ce qu'il faut ; le client lit un message simple.
    Future<UssdSessionResult> echec(String raison,
        {String forfait = ''}) async {
      await _write(docId, {
        'status': '35',
        'failure_reason': _messageClientForfait,
        'admin_detail': raison,
        'a_traiter_admin': true,
      });
      unawaited(_alerterAdminForfait(docId, clientNumber,
          forfait.isEmpty ? forfaitCode : forfait, raison));
      unawaited(ClientPush.forfait(docId: docId, active: false));
      return UssdSessionResult(result: UssdResult.failed, rawMessage: raison);
    }

    if (sim.pin.isEmpty) {
      return echec(
          'PIN MTN non configuré sur ce téléphone : aucun code composé.');
    }

    // Le forfait payé, tel qu'il est au catalogue.
    Map<String, dynamic>? forfait;
    String depart = '*126*7*{numero}#';
    try {
      final FirebaseFirestore db = FirebaseFirestore.instance;
      final q = await db
          .collection('Forfait')
          .where('code', isEqualTo: forfaitCode)
          .limit(1)
          .get();
      if (q.docs.isNotEmpty) forfait = q.docs.first.data();
      final pub = await db.collection('app_config').doc('public').get();
      final String regle =
          (pub.data()?['ussd_forfait_mtn'] ?? '').toString().trim();
      if (regle.contains('{numero}')) depart = regle;
    } catch (e) {
      debugPrint(
          '[MtnUssdManager] lecture du forfait $forfaitCode impossible : $e');
    }
    if (forfait == null) {
      return echec(
          'Forfait « $forfaitCode » introuvable au catalogue : aucun code composé.');
    }

    final dynamic brut =
        forfait['montant'] ?? forfait['prix'] ?? forfait['price'];
    final int prix = brut is num
        ? brut.toInt()
        : int.tryParse('$brut'.replaceAll(RegExp(r'[^0-9]'), '')) ?? -1;
    final int paye = int.tryParse(await _paidAmountOf(docId)) ?? -2;
    if (prix <= 0 || paye != prix) {
      return echec(
          'Montant payé ($paye F) différent du prix du forfait ($prix F) : '
          'aucun code composé.');
    }
    final String nom =
        (forfait['nom'] ?? forfait['name'] ?? forfaitCode).toString();
    final String volume =
        (forfait['volume_data'] ?? forfait['volume'] ?? '').toString();
    final String validite =
        (forfait['validite'] ?? forfait['validity'] ?? '').toString();

    await _updateStatus(docId, '33');
    debugPrint(
        '[MtnUssdManager] Catalogue → $clientNumber : $nom ($prix F, $volume, $validite)');

    bool trouve = false;
    final UssdRunResult run = await UssdSessionRunner.instance.run(
      code: depart.replaceAll('{numero}', clientNumber),
      slot: sim.slot,
      rules: [
        UssdRule(
          label: 'choix-forfait',
          answer: (screen, done) {
            final String? cle = findBundleOption(
              screen,
              price: prix,
              volume: volume,
              validite: validite,
            );
            if (cle != null) trouve = true;
            return cle;
          },
        ),
        UssdRule(
          label: 'page-suivante',
          answer: (screen, done) => trouve ? null : findMorePageKey(screen),
          maxUses: 5,
        ),
        UssdRule(
          label: 'confirmer',
          answer: (screen, done) => _demandeConfirmation(screen) ? '1' : null,
        ),
        _rulePin(sim.pin),
      ],
      isSuccess: _isSuccessScreen,
      maxScreens: 14,
      expectedOperator: 'mtn',
    );

    if (run.networkBlocked) {
      await _garder(docId, run, '1');
      return _toResult(run);
    }

    final result = _toResult(run);
    final bool success = result.result == UssdResult.success;
    final String detail = !trouve
        ? 'Forfait « $nom » ($prix F, $volume, $validite) introuvable dans le menu '
            'MTN pour ce numéro : rien n\'a été activé.'
        : (result.rawMessage.isEmpty
            ? 'Aucune réponse MTN (${result.result.name}, SIM ${sim.slot + 1}) — ${run.reason}'
            : '${result.result.name} : ${result.rawMessage}');
    await _write(docId, {
      'status': success ? '34' : '35',
      if (!success) ...<String, dynamic>{
        'failure_reason': _messageClientForfait,
        'admin_detail': detail,
        'a_traiter_admin': true,
      },
      'ussd_outcome': run.outcomeCode,
      'ussd_log': run.log,
      ..._timingFields(run),
    });
    if (!success) {
      unawaited(_alerterAdminForfait(
          docId, clientNumber, '$nom ($prix F)', detail,
          ecrans: run.screens));
    }
    unawaited(ClientPush.forfait(docId: docId, active: success));
    debugPrint(
        '[MtnUssdManager] Catalogue résultat : ${result.result} — ${run.reason}');
    return result;
  }

  /// Message montré au client quand l'activation automatique n'aboutit pas.
  static const String _messageClientForfait =
      'Votre paiement est bien reçu. L’activation automatique n’a pas abouti : '
      'notre équipe active votre forfait et vous prévient.';

  /// Alerte Telegram à l'admin : tout ce qu'il faut pour activer à la main.
  Future<void> _alerterAdminForfait(
    String docId,
    String clientNumber,
    String forfait,
    String raison, {
    List<String> ecrans = const <String>[],
  }) async {
    try {
      final String menu = ecrans.isEmpty
          ? ''
          : '\nMenu MTN vu :\n${ecrans.map((String e) => e.trim()).join('\n— — —\n')}';
      await SendEmail.sendMessagewithtelegram(
        message: 'Recharge237 — FORFAIT À ACTIVER À LA MAIN\n'
            'Téléphone : ${ServerManager.instance.deviceId}\n'
            'Client    : $clientNumber\n'
            'Forfait   : $forfait\n'
            'Commande  : $docId\n'
            'Raison    : $raison\n'
            'Le client a PAYÉ : active le forfait puis passe la commande à 34.'
            '${menu.length > 2500 ? menu.substring(0, 2500) : menu}',
      );
    } catch (e) {
      debugPrint('[MtnUssdManager] alerte admin impossible : $e');
    }
  }

  // ── Règles de lecture d'écran ─────────────────────────────────────────────
  //
  // Chaque règle reçoit le texte réellement affiché et décide — ou non — de
  // répondre. Une règle qui ne reconnaît pas l'écran ne fait rien : c'est ce
  // qui empêche un montant de partir dans un menu, ou le PIN dans le champ du
  // numéro.

  /// Répond le numéro de l'option dont le libellé contient un des [keywords]
  /// (ex. « 4) Vendre du crédit » → « 4 »).
  UssdRule _ruleOptionFor(String label, List<String> keywords) => UssdRule(
        label: label,
        answer: (screen, done) => _optionNumber(screen, keywords),
      );

  UssdRule _ruleMontant(String amount) => UssdRule(
        label: 'montant',
        answer: (screen, done) =>
            _asksTo(screen, const ['montant', 'amount', 'somme'])
                ? amount
                : null,
      );

  UssdRule _ruleNumero(String clientNumber) => UssdRule(
        label: 'numero',
        answer: (screen, done) => _asksTo(
          screen,
          const [
            'numéro',
            'numero',
            'bénéficiaire',
            'beneficiaire',
            'destinataire',
            'téléphone'
          ],
        )
            ? clientNumber
            : null,
      );

  UssdRule _rulePin(String pin) => UssdRule(
        label: 'pin',
        answer: (screen, done) =>
            _asksTo(screen, kUssdPinWords) ? pin : null,
        secret: true,
        commits: true,
      );

  /// Écran de confirmation qui n'est PAS une demande de code secret.
  ///
  /// [PIN 31/10/2026] Voir [isPlainConfirmScreen] : MTN demande « Entrez votre
  /// code PIN pour confirmer la vente de … ». La règle de confirmation,
  /// déclarée avant celle du PIN, répondait « 1 » et MTN la rejetait
  /// (« Code PIN incorrect ») : aucune activation Boost ne pouvait aboutir.
  bool _demandeConfirmation(String screen) =>
      !_asksTo(screen, kUssdPinWords) && isPlainConfirmScreen(screen);

  /// Numéro de l'option dont la ligne contient un des mots-clés.
  /// `null` si l'écran n'est pas un menu ou ne propose pas ce choix.
  String? _optionNumber(String screen, List<String> keywords) {
    for (final String raw in screen.split('\n')) {
      final String line = raw.trim();
      final RegExpMatch? m =
          RegExp(r'^(\d{1,2})\s*[).\-:]\s*(.+)$').firstMatch(line);
      if (m == null) continue;
      final String libelle = _normalize(m.group(2) ?? '');
      if (keywords.any((k) => libelle.contains(k))) return m.group(1);
    }
    return null;
  }

  bool _asksTo(String screen, List<String> words) {
    final String s = _normalize(screen);
    // Un menu numéroté n'est pas une question de saisie : on évite de répondre
    // un montant/un numéro à un écran de choix.
    if (_looksLikeOfferList(screen) && !s.contains('montant')) return false;
    return words.any(s.contains);
  }

  String _normalize(String s) => s
      .toLowerCase()
      .replaceAll('é', 'e')
      .replaceAll('è', 'e')
      .replaceAll('ê', 'e')
      .replaceAll('à', 'a')
      .replaceAll('û', 'u');

  /// Écran de liste d'offres : au moins deux lignes numérotées.
  bool _looksLikeOfferList(String screen) {
    int n = 0;
    for (final String raw in screen.split('\n')) {
      if (RegExp(r'^\s*\d{1,2}[.)\-]\s*\S').hasMatch(raw)) n++;
      if (n >= 2) return true;
    }
    return false;
  }

  bool _isSuccessScreen(String screen) {
    final String s = _normalize(screen);
    if (_mtnFailKeywords.any((k) => s.contains(_normalize(k)))) return false;
    return _mtnSuccessKeywords.any((k) => s.contains(_normalize(k)));
  }

  /// Traduction du résultat du moteur USSD — partagée avec Orange
  /// (`UssdOrderIo.toResult`) : une seule façon de lire un verdict.
  UssdSessionResult _toResult(UssdRunResult r) => UssdOrderIo.toResult(r);

  /// Champs de mesure ajoutés à la commande :
  ///  - `session_ms` : durée totale de la session USSD ;
  ///  - `ussd_timings` : une entrée par étape (attente de l'opérateur vs
  ///    réponse de l'app). Une session sans étape n'écrit rien.
  Map<String, dynamic> _timingFields(UssdRunResult run) =>
      UssdOrderIo.timingFields(run);

  /// [RESEAU 28/10/2026] Garde une commande que le réseau a empêchée.
  ///
  /// La réclamation est rendue (compteur de tentatives décrémenté) et le
  /// statut remis dans son état d'attente : la file de reprise la retrouvera
  /// au retour du réseau, dans l'ordre d'arrivée. Aucun code n'a été composé,
  /// donc aucun risque de double crédit.
  Future<void> _garder(String docId, UssdRunResult run, String statutAttente) =>
      UssdOrderIo.garder(docId, run, statutAttente,
          prefixeLog: 'MtnUssdManager');

  Future<void> _updateStatus(String docId, String status) async {
    await _write(docId, {'status': status});
  }

  /// Offre [index] telle qu'elle avait été lue dans la requête [sourceOrder].
  ///
  /// `null` quand la commande n'a pas de source (ancienne commande) ou que
  /// l'offre n'y figure plus : l'activation applique alors le comportement
  /// d'avant, sans contrôle de prix supplémentaire côté serveur (la passerelle
  /// fait déjà ce contrôle de son côté).
  Future<UssdOffer?> _offerOf(String sourceOrder, String index) async {
    if (sourceOrder.trim().isEmpty || index.trim().isEmpty) return null;
    try {
      final QuerySnapshot<Map<String, dynamic>> snap = await FirebaseFirestore
          .instance
          .collection('Transact')
          .where('order', isEqualTo: sourceOrder.trim())
          .limit(1)
          .get()
          .timeout(_readTimeout);
      if (snap.docs.isEmpty) return null;
      final Map<String, dynamic> src = snap.docs.first.data();
      // Seule la requête réellement traitée par ce serveur fait foi (statut
      // "31" : un client ne peut pas l'écrire, cf. firestore.rules).
      if (src['status']?.toString() != '31') return null;
      final Object? rawList = src['forfait_offers'];
      if (rawList is! List) return null;
      for (final Object? raw in rawList) {
        if (raw is! Map) continue;
        final Map<String, dynamic> r = Map<String, dynamic>.from(raw);
        if (r['index']?.toString().trim() != index.trim()) continue;
        return UssdOffer(
          index: index.trim(),
          key: (r['key'] ?? index).toString(),
          label: (r['label'] ?? '').toString(),
          price: int.tryParse((r['price'] ?? '').toString()),
          page: int.tryParse((r['page'] ?? '0').toString()) ?? 0,
        );
      }
    } catch (e) {
      debugPrint('[MtnUssdManager] lecture des offres source impossible : $e');
    }
    return null;
  }

  /// Montant déclaré sur la commande d'activation, réduit à ses chiffres.
  Future<String> _paidAmountOf(String docId) async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> doc = await FirebaseFirestore
          .instance
          .collection('Transact')
          .doc(docId)
          .get()
          .timeout(_readTimeout);
      final Object? amount = doc.data()?['amount'];
      return (amount ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
    } catch (e) {
      debugPrint('[MtnUssdManager] lecture du montant impossible : $e');
      return '';
    }
  }

  static const Duration _readTimeout = Duration(seconds: 12);

  /// Écriture Firestore bornée dans le temps — partagée avec Orange
  /// (`UssdOrderIo.write`) : sans délai maximal, une écriture bloquée
  /// suspendait toute la session (incident du 28/10/2026).
  Future<void> _write(String docId, Map<String, dynamic> fields) =>
      UssdOrderIo.write(docId, fields);
}
