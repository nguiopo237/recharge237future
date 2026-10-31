import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../server/order_filters.dart'
    show amountTooSmallReason, isAmountAllowed, isOrangeNumber;
import 'mtn_ussd_manager.dart' show MtnUssdManager, UssdResult, UssdSessionResult;
import 'session_config.dart';
import 'ussd_order_io.dart';
import 'ussd_screens.dart' show normalizeUssd, ussdErrorOf;
import 'ussd_session.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Parcours USSD Orange Cameroun (flows fournis le 31/10/2026)
//
// 1. TRANSFERT SIMPLE (crédit de notre réserve vers le client)
//      #189*1*[numero_client]*[montant]*[code_secret]#
//    Le code secret est DANS le code composé : une seule session, aucune
//    saisie intermédiaire. C'est le seul parcours où un secret quitte l'app
//    dans la chaîne initiale — d'où le masquage systématique des journaux
//    (voir [masquerCodeSecret] et `displayCode` du moteur USSD).
//
// 2. VENTE DE CRÉDIT GOOD DEAL (débit de notre float marchand)
//      #205*1*[numero_client]*[montant]#
//    Validation directe du montant pour le numéro indiqué, sans code secret.
//
// 3. VENTE DE FORFAIT GOOD DEAL (deux phases, comme le Boost MTN)
//      Phase 1 : #205*1*[numero_client]#  → menu d'offres de CE numéro
//      Phase 2 : le client choisit une offre, paie, puis le serveur rejoue le
//                menu, tape le numéro de l'offre et saisit le code secret.
//    Ce parcours réutilise le moteur MTN (`queryForfaitList` /
//    `activateForfait`) : même lecture d'écran, même contrôle de prix, mêmes
//    statuts 30/31/32 puis 33/34/35. Il est exposé ici pour que le dispatch
//    n'ait qu'un seul objet Orange à connaître.
//
// CODES DE STATUT (`Transact.status`) :
//   40 = en cours · 41 = livré · 42 = échec  (cf. status_labels.dart)
// ─────────────────────────────────────────────────────────────────────────────

/// Gabarit par défaut de la vente de crédit : Good Deal, sans code secret.
///
/// Surchargeable sans redéployer dans `app_config/public.ussd_orange_credit`.
const String kOrangeCreditGoodDeal = '#205*1*{numero}*{montant}#';

/// Gabarit du transfert simple (celui qui embarque le code secret).
const String kOrangeCreditTransfert =
    '#189*1*{numero}*{montant}*{code}#';

/// Vrai si un gabarit est exploitable : un code USSD, un numéro et un montant.
///
/// On refuse un gabarit incomplet plutôt que de composer un code bancal sur
/// une vraie SIM : une commande Orange ne doit jamais partir sur un code
/// inventé.
bool gabaritOrangeValide(String gabarit) {
  final String g = gabarit.trim();
  if (g.length < 6) return false;
  if (!g.endsWith('#')) return false;
  if (!g.startsWith('*') && !g.startsWith('#')) return false;
  return g.contains('{numero}') && g.contains('{montant}');
}

/// Chiffres seuls : `+237 6 74 58 35 31` → `237674583531`.
String _chiffres(String brut) => brut.replaceAll(RegExp(r'[^0-9]'), '');

/// Numéro Orange au format national (9 chiffres).
///
/// Toutes les écritures d'un même numéro doivent donner le MÊME code :
/// `+237 6 74 58 35 31`, `00237674583531` et `674583531` désignent le même
/// client, et un code composé avec un préfixe en trop échoue chez Orange.
String numeroOrange(String brut) {
  String n = _chiffres(brut);
  if (n.startsWith('00')) n = n.substring(2); // 00237…
  if (n.length > 9 && n.startsWith('237')) n = n.substring(3);
  if (n.length > 9) n = n.substring(n.length - 9); // garde-fou
  return n;
}

/// Construit le code à composer à partir du gabarit configuré.
///
/// `{numero}`, `{montant}` et `{code}` sont remplacés ; un gabarit sans `{code}`
/// compose une vente Good Deal classique (aucun secret dans le code).
String orangeCreditCode({
  required String gabarit,
  required String numero,
  required String montant,
  required String codeSecret,
}) {
  return gabarit
      .replaceAll('{numero}', numeroOrange(numero))
      .replaceAll('{montant}', _chiffres(montant))
      .replaceAll('{code}', codeSecret.trim());
}

/// Version journalisable d'un code qui contient un secret.
///
/// Rend le code inchangé quand [secret] est vide ; sinon remplace TOUTES ses
/// occurrences par `****`. Utilisée à la fois pour nos propres traces et pour
/// `displayCode` du moteur USSD (qui écrit `ussd_log` dans Firestore).
String masquerCodeSecret(String code, String secret) {
  final String s = secret.trim();
  if (s.isEmpty) return code;
  return code.replaceAll(s, '****');
}

/// Mots-clés de succès Orange (comparés sans accents, en minuscules).
///
/// Orange confirme rarement par un seul mot : selon le parcours, la réponse
/// est « Transfert effectué », « Votre recharge a été effectuée », ou un
/// accusé « en cours de traitement, vous recevrez un SMS ». Les trois formes
/// valent un succès — l'argent est parti dans tous les cas.
const List<String> _orangeSuccessKeywords = <String>[
  'succes',
  'success',
  'reussi',
  'effectue',
  'bien recu',
  'confirme',
  'confirmation',
  'en cours de traitement',
  'vous recevrez',
  'sera credite',
  'a ete credite',
  'credit envoye',
  'montant transfere',
  'recharge effectuee',
  'transfert effectue',
  'merci',
  'reussi avec succes',
];

/// Pilote les sessions USSD Orange : mêmes règles que MTN (lecture de l'écran
/// avant de répondre, garde réseau, aucun relancement automatique).
class OrangeUssdManager {
  OrangeUssdManager._();
  static final OrangeUssdManager instance = OrangeUssdManager._();

  /// `true` : la livraison Orange est branchée. Ce drapeau n'est plus une
  /// condition de routage (cf. `order_filters.dart`) — il reste exposé pour
  /// les diagnostics et pour les tests d'architecture.
  static const bool deliveryImplemented = true;

  static const String _docPublic = 'public';

  /// Vrai tant que le téléphone sait faire quelque chose d'Orange.
  bool get pret => deliveryImplemented;

  // ── 1 & 2 : vente de crédit ──────────────────────────────────────────────

  /// Recharge [clientNumber] de [amount] FCFA par le code Orange configuré.
  ///
  /// Met à jour Firestore : 40 (en cours) → 41 (livré) / 42 (échec).
  /// Garde la commande (aucun code composé) si le réseau de la carte Orange
  /// n'est pas enregistré.
  Future<UssdSessionResult> rechargeAirtime({
    required String docId,
    required String amount,
    required String clientNumber,
    required SimConfig sim,
  }) async {
    final String gabarit = await _gabaritCredit();
    final String numero = numeroOrange(clientNumber);

    if (!isOrangeNumber(numero)) {
      return _refus(
        docId,
        'Numéro $clientNumber non reconnu comme Orange : aucun code composé.',
      );
    }
    if (!isAmountAllowed(amount)) {
      return _refus(docId, amountTooSmallReason(amount));
    }

    final bool secretDansLeCode = gabarit.contains('{code}');
    if (secretDansLeCode && sim.pin.trim().isEmpty) {
      return _refus(
        docId,
        'Code secret Orange non configuré sur ce téléphone : aucun code '
        'composé (renseigner le PIN de l’emplacement Orange).',
      );
    }

    final String code = orangeCreditCode(
      gabarit: gabarit,
      numero: numero,
      montant: amount,
      codeSecret: sim.pin,
    );
    // Le code réel contient le secret : il ne doit jamais atteindre un journal.
    final String codeJournalisable =
        secretDansLeCode ? masquerCodeSecret(code, sim.pin) : code;

    await _updateStatus(docId, '40');
    debugPrint('[OrangeUssdManager] Crédit → $numero, ${_chiffres(amount)} F, '
        'slot=${sim.slot} '
        '(${secretDansLeCode ? 'transfert + code secret' : 'Good Deal'}), '
        'code ${secretDansLeCode ? 'masqué' : codeJournalisable}');

    final UssdRunResult run = await UssdSessionRunner.instance.run(
      code: code,
      displayCode: codeJournalisable,
      slot: sim.slot,
      rules: <UssdRule>[
        // Orange ajoute parfois un écran « 1. Confirmer / 2. Annuler » même
        // sur un code complet : on valide, comme le ferait un agent.
        UssdRule(
          label: 'confirmer',
          answer: (String screen, Set<String> done) =>
              _demandeConfirmation(screen) ? '1' : null,
        ),
        // Uniquement quand le secret N'EST PAS dans le code : c'est alors
        // l'opérateur qui le réclame, exactement comme pour MTN.
        if (!secretDansLeCode)
          UssdRule(
            label: 'code-secret',
            answer: (String screen, Set<String> done) =>
                _demandeCodeSecret(screen) ? sim.pin : null,
            secret: true,
            commits: true,
          ),
      ],
      // Verdict affiché SANS question (vente directe) : c'est un succès.
      isSuccess: _isSuccessScreen,
      isCompleteWithoutCommit: _isSuccessScreen,
      maxScreens: 6,
      expectedOperator: 'orange',
    );

    if (run.networkBlocked) {
      await UssdOrderIo.garder(docId, run, '1', prefixeLog: 'OrangeUssdManager');
      return UssdOrderIo.toResult(run);
    }

    // [SÉCURITÉ 31/10/2026] Le code secret est parti DANS le code initial.
    // Si l'opérateur n'a rien renvoyé, l'argent a pu partir : on ne classe
    // jamais cela en « échec », sinon une relance créditerait deux fois.
    final bool indetermine = secretDansLeCode &&
        run.screens.isEmpty &&
        run.outcome == UssdOutcome.notExecuted;

    final UssdSessionResult result = UssdOrderIo.toResult(run);
    final bool success = !indetermine && result.result == UssdResult.success;

    await UssdOrderIo.write(docId, <String, dynamic>{
      'status': success ? '41' : '42',
      if (indetermine) ...<String, dynamic>{
        'failure_reason': 'Code secret transmis mais aucune réponse Orange : '
            'opération À VÉRIFIER avant toute relance (le client a peut-être '
            'été crédité).',
        'a_traiter_admin': true,
        'a_verifier': true,
      } else if (!success)
        'failure_reason': result.rawMessage.isEmpty
            ? 'Aucune réponse Orange (${result.result.name}, '
                'SIM ${sim.slot + 1}) — ${run.reason}'
            : '${result.result.name} : ${result.rawMessage}',
      'ussd_outcome': indetermine ? 'a_verifier' : run.outcomeCode,
      'ussd_log': run.log,
      ...UssdOrderIo.timingFields(run),
    });

    debugPrint('[OrangeUssdManager] Crédit résultat : '
        '${indetermine ? 'indéterminé' : result.result} — ${run.reason}');
    return indetermine
        ? UssdSessionResult(
            result: UssdResult.timeout,
            rawMessage: result.rawMessage,
            allMessages: result.allMessages,
            log: result.log,
            timings: result.timings,
            totalMs: result.totalMs,
          )
        : result;
  }

  // ── 3 : Good Deal (forfaits) ─────────────────────────────────────────────

  /// Phase 1 : lit le menu d'offres Orange de [clientNumber] (gratuit).
  ///
  /// Code réglé par `app_config/public.ussd_gooddeal_orange`
  /// (défaut `#205*1*{numero}#`). Statuts 30/31/32, comme MTN.
  Future<List<String>> queryForfaitList({
    required String docId,
    required String clientNumber,
    required SimConfig sim,
  }) =>
      MtnUssdManager.instance.queryForfaitList(
        docId: docId,
        clientNumber: clientNumber,
        sim: sim,
        operateur: 'orange',
      );

  /// Phase 2 : active l'offre [forfaitIndex] payée par le client.
  ///
  /// Même contrôle de prix que MTN (l'offre doit correspondre à ce que CE
  /// serveur a lu), puis code secret de l'agent en dernière étape.
  /// Statuts 33/34/35.
  Future<UssdSessionResult> activateForfait({
    required String docId,
    required String clientNumber,
    required String forfaitIndex,
    required SimConfig sim,
    String sourceOrder = '',
  }) =>
      MtnUssdManager.instance.activateForfait(
        docId: docId,
        clientNumber: clientNumber,
        forfaitIndex: forfaitIndex,
        sim: sim,
        sourceOrder: sourceOrder,
        operateur: 'orange',
      );

  // ── Réglages ─────────────────────────────────────────────────────────────

  /// Gabarit du crédit Orange, lu dans `app_config/public` (1 lecture).
  ///
  /// Défaut : vente Good Deal `#205*1*{numero}*{montant}#`. Pour basculer sur
  /// le transfert `#189*1*{numero}*{montant}*{code}#`, il suffit d'écrire
  /// `ussd_orange_credit` dans ce document — sans toucher au code.
  Future<String> _gabaritCredit() async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> doc = await FirebaseFirestore
          .instance
          .collection('app_config')
          .doc(_docPublic)
          .get()
          .timeout(const Duration(seconds: 8));
      final String v =
          (doc.data()?['ussd_orange_credit'] ?? '').toString().trim();
      if (v.isEmpty) return kOrangeCreditGoodDeal;
      if (gabaritOrangeValide(v)) return v;
      debugPrint('[OrangeUssdManager] gabarit refusé (incomplet) : $v — '
          'utilisation du Gabarit Good Deal par défaut.');
    } catch (e) {
      debugPrint('[OrangeUssdManager] gabarit illisible, défaut appliqué : $e');
    }
    return kOrangeCreditGoodDeal;
  }

  // ── Lecture d'écran ──────────────────────────────────────────────────────

  bool _isSuccessScreen(String screen) {
    if (ussdErrorOf(screen) != null) return false;
    final String s = normalizeUssd(screen);
    return _orangeSuccessKeywords.any(s.contains);
  }

  /// Écran qui demande une confirmation explicite.
  ///
  /// [PIN 31/10/2026] Un écran qui réclame le code secret n'est pas une simple
  /// confirmation : « Entrez votre code PIN pour confirmer… » contient
  /// « confirmer ». Sans ce garde-fou, on répondait « 1 » à la place du
  /// secret et l'opérateur rejetait l'opération (même piège que MTN).
  bool _demandeConfirmation(String screen) {
    if (_demandeCodeSecret(screen)) return false;
    final String s = normalizeUssd(screen);
    return s.contains('confirmer') ||
        s.contains('confirmez') ||
        s.contains('valider') ||
        s.contains('appuyez sur 1');
  }

  /// Écran qui réclame le code secret de l'agent.
  bool _demandeCodeSecret(String screen) {
    final String s = normalizeUssd(screen);
    return s.contains('code secret') ||
        s.contains('code confidentiel') ||
        s.contains('mot de passe') ||
        s.contains('pin') ||
        s.contains('password');
  }

  // ── Écritures ────────────────────────────────────────────────────────────

  Future<void> _updateStatus(String docId, String status) =>
      UssdOrderIo.write(docId, <String, dynamic>{'status': status});

  /// Refus AVANT toute composition : rien n'est parti, la commande est
  /// marquée en échec avec la vraie raison (l'admin n'a pas à deviner).
  Future<UssdSessionResult> _refus(String docId, String raison) async {
    await UssdOrderIo.write(docId, <String, dynamic>{
      'status': '42',
      'failure_reason': raison,
    });
    debugPrint('[OrangeUssdManager] refus ($docId) : $raison');
    return UssdSessionResult(result: UssdResult.failed, rawMessage: raison);
  }
}
