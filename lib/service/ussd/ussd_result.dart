import 'ussd_session.dart' show UssdStepTiming;

/// [ORANGE 31/10/2026] Résultats d'une session USSD, partagés par TOUS les
/// opérateurs.
///
/// Ces deux types vivaient dans `mtn_ussd_manager.dart` : le manager Orange
/// devait donc importer le manager MTN pour récupérer un simple enum. Ils sont
/// désormais ici, et `mtn_ussd_manager.dart` les réexporte — les imports
/// existants (`show UssdResult, UssdSessionResult`) continuent de fonctionner
/// sans modification.
enum UssdResult { success, failed, timeout, noNetwork }

class UssdSessionResult {
  final UssdResult result;
  final String rawMessage; // Dernier message USSD brut
  final List<String> allMessages; // Tous les écrans de la session
  final String log; // Journal lisible (PIN masqué)

  // [MESURE 28/10/2026] Durée réelle de la session, étape par étape, écrite
  // dans la commande : plus besoin d'adb pour savoir où partent les secondes.
  final List<UssdStepTiming> timings;
  final int totalMs;

  const UssdSessionResult({
    required this.result,
    required this.rawMessage,
    this.allMessages = const [],
    this.log = '',
    this.timings = const <UssdStepTiming>[],
    this.totalMs = 0,
  });
}
