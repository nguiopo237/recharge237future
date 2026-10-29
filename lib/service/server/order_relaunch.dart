import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'order_filters.dart';

/// Relance MANUELLE d'une commande, décidée par l'admin.
///
/// [28/10/2026] Le serveur n'exécute plus une commande qu'une seule fois : il
/// envoie le rapport (Telegram + `failure_reason`) et s'arrête là. Si une
/// seconde tentative est nécessaire, c'est l'admin qui la demande :
///
///  - dans l'app serveur : bouton « Relancer » sur la commande ;
///  - dans Firestore, à la main : `relance_demandee: true` et `status` remis à
///    l'état d'exécution (cf. [relaunchStatusFor]),
///
/// puis le téléphone exécute **une** tentative et consomme le drapeau
/// (TransactionClaimer). Une relance = une tentative, jamais plus.
class OrderRelaunch {
  OrderRelaunch._();

  static const String _collection = 'Transact';

  /// Demande une relance. Retourne le statut réécrit, ou `null` si la
  /// commande ne peut pas être relancée (déjà livrée, non payée, Orange…).
  static Future<String?> request({
    required String docId,
    required Map<String, dynamic> data,
    required String deviceId,
  }) async {
    if (!canRelaunch(data)) return null;
    final String? status = relaunchStatusFor(data);
    if (status == null) return null;

    try {
      await FirebaseFirestore.instance
          .collection(_collection)
          .doc(docId)
          .update({
        'status': status,
        'relance_demandee': true,
        'relance_par': deviceId,
        'relance_at': FieldValue.serverTimestamp(),
        // On libère la commande : elle n'appartient plus au téléphone qui a
        // échoué (le compteur `attempts`, lui, reste : c'est la trace).
        'serverId': null,
        'claimedAt': null,
        // Raison précédente conservée sous un nom d'archive, pour que la
        // nouvelle tentative reparte proprement.
        if ((data['failure_reason'] ?? '').toString().trim().isNotEmpty)
          'failure_reason_avant_relance':
              data['failure_reason'].toString().trim(),
        'failure_reason': FieldValue.delete(),
      });
      debugPrint('[Relaunch] $docId relancée (status $status) par $deviceId');
      return status;
    } catch (e) {
      debugPrint('[Relaunch] $docId : relance impossible — $e');
      return null;
    }
  }
}
