import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Configuration d'une SIM / d'un opérateur pour ce téléphone.
/// Chargée depuis `servers/{deviceId}` dans Firestore.
///
/// Structure Firestore attendue :
/// ```json
/// {
///   "simMTN":    { "slot": 0, "pin": "1234" },
///   "simOrange": { "slot": 1, "pin": "5678" },
///   "simCamtelPre":  { "slot": 0 },
///   "simCamtelPost": { "slot": 1 }
/// }
/// ```
/// Le PIN est sensible mais reste local (sur ton téléphone uniquement).
class SimConfig {
  final int slot;
  final String pin;

  const SimConfig({required this.slot, this.pin = ''});

  factory SimConfig.fromMap(Map<String, dynamic> m) => SimConfig(
        slot: (m['slot'] as num?)?.toInt() ?? 0,
        pin:  m['pin']?.toString() ?? '',
      );
}

class SessionConfig {
  final SimConfig mtn;
  final SimConfig orange;
  final SimConfig camtelPre;
  final SimConfig camtelPost;

  const SessionConfig({
    required this.mtn,
    required this.orange,
    required this.camtelPre,
    required this.camtelPost,
  });

  /// Charge la config depuis Firestore. Utilise des valeurs par défaut
  /// si le document n'existe pas encore.
  static Future<SessionConfig> load(String deviceId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('servers')
          .doc(deviceId)
          .get();

      final d = doc.data() ?? {};

      SimConfig parse(String key, {int defaultSlot = 0}) {
        final raw = d[key];
        if (raw is Map<String, dynamic>) return SimConfig.fromMap(raw);
        return SimConfig(slot: defaultSlot);
      }

      return SessionConfig(
        mtn:         parse('simMTN',       defaultSlot: 0),
        orange:      parse('simOrange',    defaultSlot: 1),
        camtelPre:   parse('simCamtelPre', defaultSlot: 0),
        camtelPost:  parse('simCamtelPost',defaultSlot: 1),
      );
    } catch (e) {
      debugPrint('[SessionConfig] Erreur chargement config : $e');
      return const SessionConfig(
        mtn:        SimConfig(slot: 0),
        orange:     SimConfig(slot: 1),
        camtelPre:  SimConfig(slot: 0),
        camtelPost: SimConfig(slot: 1),
      );
    }
  }
}
