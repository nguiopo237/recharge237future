import 'package:flutter/foundation.dart';

import 'mtn_ussd_manager.dart' show UssdResult, UssdSessionResult;
import 'session_config.dart';

/// [ORANGE 28/10/2026] Emplacement réservé pour la livraison de crédit Orange.
///
/// Ce fichier ne compose AUCUN code USSD : il refuse explicitement. C'est
/// volontaire — une commande Orange ne doit jamais être réservée puis échouer
/// parce qu'un code inventé a été composé sur une vraie SIM.
///
/// Ce qu'il reste à fournir pour l'implémenter (rien d'autre à chercher) :
///   1. le code USSD de vente/transfert, et sa forme avec montant et numéro
///      bénéficiaire (ex. `*XXX*<numéro>*<montant>#`) ;
///   2. les invites successives du menu, et le texte exact de succès/échec
///      renvoyé par Orange ;
///   3. la position du PIN : dans le code, ou saisi à une étape du menu ;
///   4. le format attendu du montant (entier, multiples de 50, plafond…).
///
/// Une fois disponible, utiliser `UssdSession` (comme le manager MTN) pour
/// jouer la séquence, puis remplacer [deliveryImplemented] et le corps de
/// [rechargeAirtime]. Tout le reste est déjà prêt : type de routage
/// `orange_airtime`, `SessionConfig.orange` / `orangeConfigured`, détection de
/// la SIM et de son emplacement, validation `isOrangeNumber`.
class OrangeUssdManager {
  OrangeUssdManager._();
  static final OrangeUssdManager instance = OrangeUssdManager._();

  /// `false` tant que le flow USSD n'est pas branché. Aucune commande Orange
  /// n'est réservée dans cet état.
  static const bool deliveryImplemented = false;

  Future<UssdSessionResult> rechargeAirtime({
    required String docId,
    required String amount,
    required String clientNumber,
    required SimConfig sim,
  }) async {
    debugPrint(
      '[Orange] Livraison non implémentée — commande $docId, $amount F vers '
      '$clientNumber, SIM ${sim.slot + 1} (aucun code composé)',
    );
    return const UssdSessionResult(
      result: UssdResult.failed,
      rawMessage:
          'Livraison Orange pas encore configurée : flow USSD inconnu (aucun code composé).',
    );
  }
}
