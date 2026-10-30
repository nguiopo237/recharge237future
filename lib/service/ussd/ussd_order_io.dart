import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../server/server_manager.dart';
import '../server/transaction_claimer.dart';
import 'ussd_result.dart';
import 'ussd_session.dart';

/// [ORANGE 31/10/2026] Écritures Firestore et traduction des résultats USSD,
/// communes à MTN et Orange.
///
/// POURQUOI CE FICHIER : ces quatre opérations (écrire le verdict, garder une
/// commande bloquée par le réseau, horodater les étapes, traduire un
/// [UssdRunResult]) étaient dans `mtn_ussd_manager.dart`. Les dupliquer dans le
/// manager Orange aurait créé deux façons d'écrire un statut de commande — la
/// garantie la plus importante du serveur. Elles sont donc ici, une seule fois,
/// et MTN comme Orange les appellent.
///
/// Aucune décision métier ici : uniquement de l'écriture bornée dans le temps
/// (sans délai maximal, une écriture bloquée suspendait toute la session, cf.
/// incident du 28/10/2026).
class UssdOrderIo {
  UssdOrderIo._();

  static const Duration _readTimeout = Duration(seconds: 12);
  static const Duration _writeTimeout = Duration(seconds: 12);

  /// Écriture bornée dans le temps sur `Transact/{docId}`.
  static Future<void> write(String docId, Map<String, dynamic> fields) async {
    try {
      await FirebaseFirestore.instance
          .collection('Transact')
          .doc(docId)
          .update(fields)
          .timeout(_writeTimeout);
    } catch (e) {
      debugPrint('[UssdOrderIo] écriture Firestore impossible : $e');
    }
  }

  /// [RESEAU 28/10/2026] Garde une commande que le réseau a empêchée.
  ///
  /// La réclamation est rendue (compteur de tentatives décrémenté) et le
  /// statut remis dans son état d'attente : la file de reprise la retrouvera
  /// au retour du réseau, dans l'ordre d'arrivée. Aucun code n'a été composé,
  /// donc aucun risque de double crédit.
  static Future<void> garder(
    String docId,
    UssdRunResult run,
    String statutAttente, {
    String prefixeLog = 'USSD',
  }) async {
    await TransactionClaimer.instance
        .release(docId, ServerManager.instance.deviceId);
    await write(docId, <String, dynamic>{
      'status': statutAttente,
      'failure_reason': '${run.reason} — commande gardée : elle repartira '
          'automatiquement au retour du réseau.',
      'ussd_outcome': run.outcomeCode,
      'held_at': FieldValue.serverTimestamp(),
    });
    debugPrint('[$prefixeLog] $docId gardée (réseau indisponible)');
  }

  /// Champs de mesure ajoutés à la commande :
  ///  - `session_ms` : durée totale de la session USSD ;
  ///  - `ussd_timings` : une entrée par étape (attente de l'opérateur vs
  ///    réponse de l'app). Une session sans étape n'écrit rien.
  static Map<String, dynamic> timingFields(UssdRunResult run) {
    if (run.timings.isEmpty) return const <String, dynamic>{};
    return <String, dynamic>{
      'session_ms': run.totalMs,
      'ussd_timings': run.timings.map((UssdStepTiming t) => t.toMap()).toList(),
    };
  }

  /// Traduit le résultat du moteur USSD en résultat « métier ».
  ///
  /// `notExecuted` devient `timeout` quand la raison est l'absence de toute
  /// réponse : c'est un problème de réseau/opérateur, pas un refus.
  static UssdSessionResult toResult(UssdRunResult r) {
    final UssdResult res;
    switch (r.outcome) {
      case UssdOutcome.success:
        res = UssdResult.success;
        break;
      case UssdOutcome.failed:
        res = UssdResult.failed;
        break;
      case UssdOutcome.uncertain:
        res = UssdResult.timeout;
        break;
      case UssdOutcome.notExecuted:
        res = r.reason.toLowerCase().contains('aucune réponse')
            ? UssdResult.timeout
            : UssdResult.failed;
        break;
    }
    return UssdSessionResult(
      result: res,
      rawMessage: r.finalScreen,
      allMessages: r.screens,
      log: r.log,
      timings: r.timings,
      totalMs: r.totalMs,
    );
  }

  /// Lit un document `Transact` (offres source, montant payé…) avec un délai.
  static Future<Map<String, dynamic>?> read(String docId) async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> doc = await FirebaseFirestore
          .instance
          .collection('Transact')
          .doc(docId)
          .get()
          .timeout(_readTimeout);
      return doc.data();
    } catch (e) {
      debugPrint('[UssdOrderIo] lecture impossible ($docId) : $e');
      return null;
    }
  }
}
