import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Protège contre le double-traitement quand plusieurs téléphones
/// écoutent la même collection Firestore.
///
/// Le principe : avant de traiter une transaction, on tente de
/// l'attribuer atomiquement à CE téléphone en écrivant `serverId`.
/// Si un autre téléphone a déjà écrit son propre `serverId`, la
/// transaction Firestore échoue silencieusement et on passe à
/// la suivante.
///
/// [28/10/2026] **Une commande n'est exécutée qu'UNE seule fois.**
///
/// Avant, la seule barrière était `serverId` : un document dont le champ
/// avait été vidé (ou jamais écrit) repartait tout seul, et le serveur
/// pouvait donc composer deux fois le même USSD — donc créditer deux fois.
/// Désormais chaque réclamation incrémente `attempts` ; une commande déjà
/// tentée n'est plus jamais reprise automatiquement, quel que soit l'état
/// du téléphone qui l'a prise.
///
/// La seule façon d'en exécuter une seconde est une **relance demandée par
/// l'admin** : soit le bouton « Relancer » dans l'app serveur, soit, à la
/// main dans Firestore, `relance_demandee: true` (+ `status` remis à l'état
/// d'exécution, cf. `relaunchStatusFor`). Le drapeau est consommé par la
/// réclamation : une relance = une tentative, jamais plus.
class TransactionClaimer {
  TransactionClaimer._();
  static final TransactionClaimer instance = TransactionClaimer._();

  static const _collection = 'Transact';

  /// Statuts que l'on peut réclamer.
  /// [MTN GOOD DEAL 27/10/2026] "0" ajouté pour la requête d'offres (gratuite,
  /// operateur_cible == 'mtn_forfait') : elle ne transite jamais par "1" —
  /// aucun paiement n'est impliqué, et firestore.rules réserve l'écriture de
  /// "1" à l'admin/la passerelle. Les autres branches de check() exigent
  /// toutes un statut précis ("1"/"6"/"9"/"11") en plus de `operateur_cible` :
  /// élargir ici à "0" ne change leur déclenchement en rien.
  /// [PRODUCTION 27/10/2026] "11" (point de vente) ajouté : la branche POS de
  /// check() réclamait la transaction mais le claim la refusait toujours,
  /// donc les commandes des points de vente n'étaient jamais exécutées.
  static const _claimableStatuses = {'0', '1', '6', '9', '11'};

  /// Décide si une commande peut être prise par un téléphone.
  ///
  /// Fonction pure (testée dans test/relance_test.dart) :
  ///  - statut inconnu → non ;
  ///  - déjà prise par un téléphone et pas de relance demandée → non ;
  ///  - déjà tentée une fois et pas de relance demandée → non ;
  ///  - relance demandée → oui, une seule fois (le drapeau est consommé).
  static bool canClaim({
    required String status,
    required String owner,
    required int attempts,
    required bool relaunchRequested,
  }) {
    if (!_claimableStatuses.contains(status)) return false;
    if (relaunchRequested) return true;
    if (owner.isNotEmpty) return false;
    return attempts < 1;
  }

  /// Rend une commande gardée par erreur par ce téléphone.
  ///
  /// [RESEAU 28/10/2026] Réservé au cas où la session n'a PAS pu démarrer
  /// faute de réseau (aucun code composé, donc aucun débit possible). La
  /// réclamation est rendue et le compteur décrémenté pour que la commande
  /// reparte au retour du réseau — sinon elle resterait bloquée à vie, une
  /// tentative ayant déjà été consommée.
  ///
  /// Ne fait rien si un autre téléphone l'a prise entre-temps.
  Future<bool> release(String docId, String serverId) async {
    try {
      return await FirebaseFirestore.instance.runTransaction<bool>((txn) async {
        final ref = FirebaseFirestore.instance
            .collection(_collection)
            .doc(docId);
        final snap = await txn.get(ref);
        if (!snap.exists) return false;
        final Map<String, dynamic> data = snap.data() ?? const {};
        if ((data['serverId'] ?? '').toString() != serverId) return false;
        final int attempts = (data['attempts'] as num?)?.int ?? 0;
        txn.update(ref, <String, dynamic>{
          'serverId': '',
          'attempts': attempts > 0 ? attempts - 1 : 0,
          'last_release_at': FieldValue.serverTimestamp(),
          'last_release_by': serverId,
        });
        debugPrint('[Claimer] $docId rendue (aucun code composé)');
        return true;
      });
    } catch (e) {
      debugPrint('[Claimer] Erreur release $docId : $e');
      return false;
    }
  }

  /// [BACKOFF 29/10/2026] Réduction de la fréquence des requêtes Firestore :
  /// en cas d'échec transient (ex. `cloud_firestore/resource-exhausted`), on
  /// réessaie avec un backoff exponentiel au lieu de laisser la transaction
  /// bloquée jusqu'à une relance manuelle — ce qui épuisait le quota gratuit
  /// du plan Spark sous forte charge (10 000 clients).
  Future<bool> claim(String docId, String serverId) async {
    const List<Duration> _claimBackoffDelays = [
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 8),
    ];
    Object? lastError;
    for (int attempt = 0; attempt < _claimBackoffDelays.length; attempt++) {
      bool result = false;
      try {
        result = await FirebaseFirestore.instance
            .runTransaction<bool>((txn) async {
          final ref = FirebaseFirestore.instance
              .collection(_collection)
              .doc(docId);
          final snap = await txn.get(ref);

          if (!snap.exists) return false;

          final Map<String, dynamic> data = snap.data() ?? const {};
          final String status = data['status']?.toString() ?? '';
          final String existingOwner = data['serverId']?.toString() ?? '';
          final int attempts = (data['attempts'] as num?)?.int ?? 0;
          final bool relaunch = data['relance_demandee'] == true;

          // Statut non traitable
          if (!_claimableStatuses.contains(status)) return false;

          // Déjà réclamée — y compris par CE téléphone. [PRODUCTION 27/10/2026]
          // Avant, une commande déjà prise par ce même téléphone (redémarrage en
          // pleine session USSD, nouvel événement Firestore) était relancée :
          // risque de double crédit. Une commande réclamée mais restée bloquée
          // est laillée à l'admin (champ `serverId` visible dans Firestore).
          if (!canClaim(
            status: status,
            owner: existingOwner,
            attempts: attempts,
            relaunchRequested: relaunch,
          )) {
            debugPrint(existingOwner.isNotEmpty
                ? '[Claimer] $docId déjà prise par $existingOwner'
                : '[Claimer] $docId déjà tentée ($attempts fois) — relance manuelle requise');
            return false;
          }

          txn.update(ref, {
            'serverId': serverId,
            'claimedAt': FieldValue.serverTimestamp(),
            // Compteur durable : c'est lui qui garantit « une seule fois »,
            // même si serverId est effacé par une intervention manuelle.
            'attempts': attempts + 1,
            'last_attempt_at': FieldValue.serverTimestamp(),
            'last_attempt_by': serverId,
            // Une relance demandée ne vaut que pour cette tentative : elle est
            // consommée ici, jamais réutilisée par un événement suivant.
            if (relaunch) 'relance_demandee': false,
            if (relaunch) 'relance_executee_par': serverId,
          });
          if (relaunch) {
            debugPrint('[Claimer] $docId relancée à la demande de l\'admin');
          }
          return true;
        });

      } catch (e) {
        lastError = e;
        debugPrint('[Claimer] Erreur claim $docId (tentative ${attempt + 1}/${_claimBackoffDelays.length}) : $e');
      }

      if (result) return true;
      if (attempt < _claimBackoffDelays.length - 1) {
        await Future.delayed(_claimBackoffDelays[attempt]);
      }
    }
    debugPrint('[Claimer] Erreur claim $docId définitive : $lastError');
    return false;
  }
}
