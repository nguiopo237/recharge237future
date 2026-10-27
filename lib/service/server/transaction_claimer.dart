import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Protège contre le double-traitement quand plusieurs téléphones
/// écoutent la même collection Firestore.
///
/// Le principe : avant de traiter une transaction, on tente de
/// l'attribuer atomiquement à CE téléphone en écrivant `serverId`.
/// Si un autre téléphone a déjà écrit son propre `serverId`, la
/// transaction Firestore échoue silencieusement et on passe à la
/// suivante.
class TransactionClaimer {
  TransactionClaimer._();
  static final TransactionClaimer instance = TransactionClaimer._();

  static const _collection = 'Transact';

  /// Statuts que l'on peut réclamer.
  static const _claimableStatuses = {'1', '6', '9'};

  /// Tente de réclamer [docId] pour le serveur [serverId].
  ///
  /// Retourne `true`  → ce téléphone a obtenu la transaction.
  /// Retourne `false` → déjà prise par un autre téléphone, ou statut invalide.
  Future<bool> claim(String docId, String serverId) async {
    try {
      return await FirebaseFirestore.instance
          .runTransaction<bool>((txn) async {
        final ref = FirebaseFirestore.instance
            .collection(_collection)
            .doc(docId);
        final snap = await txn.get(ref);

        if (!snap.exists) return false;

        final status       = snap['status']?.toString() ?? '';
        final existingOwner = snap.data()?['serverId']?.toString() ?? '';

        // Statut non traitable
        if (!_claimableStatuses.contains(status)) return false;

        // Déjà réclamée par un autre serveur
        if (existingOwner.isNotEmpty && existingOwner != serverId) {
          debugPrint('[Claimer] $docId déjà prise par $existingOwner');
          return false;
        }

        txn.update(ref, {
          'serverId':  serverId,
          'claimedAt': FieldValue.serverTimestamp(),
        });
        return true;
      });
    } catch (e) {
      debugPrint('[Claimer] Erreur claim $docId : $e');
      return false;
    }
  }

  /// Libère la réclamation (ex : erreur inattendue, timeout USSD).
  /// Remet le statut à "1" pour qu'un autre téléphone puisse réessayer.
  Future<void> release(String docId) async {
    try {
      await FirebaseFirestore.instance
          .collection(_collection)
          .doc(docId)
          .update({'serverId': null, 'claimedAt': null, 'status': '1'});
    } catch (_) {}
  }
}
