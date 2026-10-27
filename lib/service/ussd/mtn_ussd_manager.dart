import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:ussd_launcher/ussd_launcher.dart';

import 'session_config.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Résultats possibles d'une session USSD
// ─────────────────────────────────────────────────────────────────────────────
enum UssdResult { success, failed, timeout, noNetwork }

class UssdSessionResult {
  final UssdResult result;
  final String rawMessage;       // Dernier message USSD brut
  final List<String> allMessages; // Tous les messages de la session (pour forfait list)

  const UssdSessionResult({
    required this.result,
    required this.rawMessage,
    this.allMessages = const [],
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Mots-clés de succès MTN (à compléter selon les retours réels de l'opérateur)
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
  'traité',
  'traite',
  'top-up',
  'airtime',
];

const _mtnFailKeywords = [
  'failed',
  'échoué',
  'echec',
  'insufficient',
  'solde insuffisant',
  'invalid',
  'invalide',
  'incorrect',
  'error',
  'erreur',
];

// ─────────────────────────────────────────────────────────────────────────────
// Durée maximale d'une étape USSD (réglementaire MTN ≈ 3 min, on prend 90 s)
// ─────────────────────────────────────────────────────────────────────────────
const _kSessionTimeout = Duration(seconds: 90);

/// Pilote les sessions USSD interactives pour MTN Cameroun.
///
/// Chaque workflow envoie un code USSD initial puis navigue
/// étape par étape, exactement comme le ferait un humain.
///
/// **Workflow A — Vente de crédit Airtime**
/// ```
/// *126#  →  4 (Vente crédit)  →  [montant]  →  [numéroClient]  →  [PIN]
/// ```
///
/// **Workflow B Phase 1 — Récupérer la liste des forfaits**
/// ```
/// *126#  →  8 (ou autre entrée forfait)  →  [numéroClient]
///   si réponse contient "suite" → envoyer "00" pour tout charger
/// ```
///
/// **Workflow B Phase 2 — Activer un forfait choisi**
/// ```
/// *126#  →  8  →  [numéroClient]  →  [indexForfait]  →  [PIN]
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
      debugPrint('[MtnUssdManager] PIN MTN non configuré dans Firestore (servers/{id}/simMTN/pin)');
      await _updateStatus(docId, '22');
      return const UssdSessionResult(result: UssdResult.failed, rawMessage: 'PIN non configuré');
    }

    await _updateStatus(docId, '20');
    debugPrint('[MtnUssdManager] Airtime → $clientNumber, $amount FCFA, slot=${sim.slot}');

    // Étapes : *126# → 4 → montant → numéroClient → PIN
    final session = await _runSession(
      code: '*126#',
      simSlot: sim.slot,
      options: ['4', amount, clientNumber, sim.pin],
    );

    final success = _containsKeyword(session.rawMessage, _mtnSuccessKeywords);
    await _updateStatus(docId, success ? '21' : '22');

    debugPrint('[MtnUssdManager] Airtime résultat: ${session.result} — ${session.rawMessage}');
    return session;
  }

  // ── Workflow B Phase 1 : Récupérer la liste des forfaits ─────────────────

  /// Charge la liste des forfaits disponibles pour [clientNumber].
  ///
  /// Gère la pagination automatiquement (envoie "00" si le menu contient
  /// "suite" ou similaire).
  ///
  /// Met à jour Firestore :
  ///   • "30" = requête en cours
  ///   • "31" = liste prête (stockée dans `forfait_list`)
  ///   • "32" = échec
  Future<List<String>> queryForfaitList({
    required String docId,
    required String clientNumber,
    required SimConfig sim,
  }) async {
    await _updateStatus(docId, '30');
    debugPrint('[MtnUssdManager] ForfaitQuery → $clientNumber, slot=${sim.slot}');

    // Première tentative : charger la liste sans pagination
    final session = await _runSession(
      code: '*126#',
      simSlot: sim.slot,
      options: ['8', clientNumber],
    );

    // Si la réponse contient "suite" → relancer avec "00" pour tout charger
    final rawFull = _hasPagination(session.rawMessage)
        ? await _loadFullList(clientNumber: clientNumber, sim: sim)
        : session.rawMessage;

    if (session.result == UssdResult.timeout || rawFull.isEmpty) {
      await _updateStatus(docId, '32');
      return [];
    }

    // Parser les lignes numérotées (ex: "1. Pack 200 Mo 200F\n2. Pack 1Go 500F\n...")
    final lines = rawFull
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && RegExp(r'^\d+[.)]\s').hasMatch(l))
        .toList();

    // Sauvegarder dans Firestore + passer en "liste prête"
    await FirebaseFirestore.instance.collection('Transact').doc(docId).update({
      'forfait_list': lines,
      'status': '31',
    });

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
  Future<UssdSessionResult> activateForfait({
    required String docId,
    required String clientNumber,
    required String forfaitIndex,
    required SimConfig sim,
  }) async {
    if (sim.pin.isEmpty) {
      await _updateStatus(docId, '35');
      return const UssdSessionResult(result: UssdResult.failed, rawMessage: 'PIN non configuré');
    }

    await _updateStatus(docId, '33');
    debugPrint('[MtnUssdManager] ActivateForfait → $clientNumber, offre=$forfaitIndex, slot=${sim.slot}');

    // Étapes : *126# → 8 → numéroClient → indexForfait → PIN
    final session = await _runSession(
      code: '*126#',
      simSlot: sim.slot,
      options: ['8', clientNumber, forfaitIndex, sim.pin],
    );

    final success = _containsKeyword(session.rawMessage, _mtnSuccessKeywords);
    await _updateStatus(docId, success ? '34' : '35');

    debugPrint('[MtnUssdManager] Forfait résultat: ${session.result} — ${session.rawMessage}');
    return session;
  }

  // ── Helpers privés ────────────────────────────────────────────────────────

  /// Lance une session USSD multi-étapes via le plugin `ussd_launcher`.
  /// Collecte TOUS les messages reçus pendant la session.
  Future<UssdSessionResult> _runSession({
    required String code,
    required int simSlot,
    required List<String> options,
  }) async {
    final allMessages = <String>[];
    String lastMessage = '';
    final sessionDone = Completer<void>();

    // Écoute chaque message renvoyé par l'opérateur
    UssdLauncher.setUssdMessageListener((message) {
      allMessages.add(message);
      lastMessage = message;
      debugPrint('[MtnSession] Message reçu : $message');

      // Fin de session détectée
      if (_isSessionEnd(message) && !sessionDone.isCompleted) {
        sessionDone.complete();
      }
    });

    bool timedOut = false;

    try {
      await Future.any([
        // Lance la session USSD
        UssdLauncher.multisessionUssd(
          code: code,
          slotIndex: simSlot,
          options: options,
        ),
        // Timeout global
        Future.delayed(_kSessionTimeout).then((_) {
          timedOut = true;
          if (!sessionDone.isCompleted) sessionDone.complete();
        }),
        // La session se termine via le listener
        sessionDone.future,
      ]);
    } catch (e) {
      debugPrint('[MtnSession] Erreur session : $e');
    }

    if (timedOut) {
      return UssdSessionResult(
        result:     UssdResult.timeout,
        rawMessage: lastMessage,
        allMessages: allMessages,
      );
    }

    final result = _containsKeyword(lastMessage, _mtnSuccessKeywords)
        ? UssdResult.success
        : _containsKeyword(lastMessage, _mtnFailKeywords)
            ? UssdResult.failed
            : UssdResult.failed; // inconnu → échec par précaution

    return UssdSessionResult(
      result:     result,
      rawMessage: lastMessage,
      allMessages: allMessages,
    );
  }

  /// Recharge la liste des forfaits avec pagination ("00").
  Future<String> _loadFullList({
    required String clientNumber,
    required SimConfig sim,
  }) async {
    final session = await _runSession(
      code: '*126#',
      simSlot: sim.slot,
      options: ['8', clientNumber, '00'],
    );
    return session.allMessages.join('\n');
  }

  Future<void> _updateStatus(String docId, String status) async {
    try {
      await FirebaseFirestore.instance
          .collection('Transact')
          .doc(docId)
          .update({'status': status});
    } catch (_) {}
  }

  bool _containsKeyword(String msg, List<String> keywords) {
    final lower = msg.toLowerCase();
    return keywords.any((k) => lower.contains(k));
  }

  /// La session est terminée si le message contient un indicateur de fin.
  bool _isSessionEnd(String msg) {
    final lower = msg.toLowerCase();
    return lower.contains('successfully') ||
        lower.contains('succès') ||
        lower.contains('succes') ||
        lower.contains('failed') ||
        lower.contains('echec') ||
        lower.contains('échoué') ||
        lower.contains('confirmed') ||
        lower.contains('invalide') ||
        lower.contains('incorrect') ||
        lower.contains('error') ||
        lower.contains('erreur') ||
        // Codes de fin MTN
        msg.contains('401') ||
        msg.contains('501') ||
        msg.contains('502');
  }

  bool _hasPagination(String msg) {
    final lower = msg.toLowerCase();
    return lower.contains('suite') ||
        lower.contains('more') ||
        lower.contains('plus') ||
        lower.contains('00 pour');
  }
}
