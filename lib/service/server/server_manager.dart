import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:unique_identifier/unique_identifier.dart';

/// Gère l'enregistrement de ce téléphone comme serveur de recharge
/// et envoie un heartbeat toutes les 30 secondes.
///
/// Chaque téléphone se configure dans Firestore via
/// `servers/{deviceId}` :
///
/// ```
/// {
///   "name":      "Téléphone Orange #1",   // optionnel, affiché dans l'admin
///   "operators": ["orange"],               // "all" | "orange" | "mtn" | "prepaid" | "postpaid"
/// }
/// ```
///
/// Si le document n'existe pas encore, le téléphone traite tout
/// (comportement par défaut `operators: ["all"]`).
class ServerManager {
  ServerManager._();
  static final ServerManager instance = ServerManager._();

  String _deviceId = 'unknown';
  String get deviceId => _deviceId;

  List<String> _operators = ['all'];
  Timer? _heartbeatTimer;

  // Préfixes Orange Cameroun
  static const _orangePrefixes = ['069', '065', '655', '656', '657', '659'];
  // Préfixes MTN Cameroun
  static const _mtnPrefixes   = ['067', '068', '650', '651', '652', '653', '654', '677', '678', '679'];

  /// À appeler une seule fois dans `initState` du widget principal.
  Future<void> initialize() async {
    // 1. Résoudre l'identifiant unique de l'appareil
    try {
      _deviceId = (await UniqueIdentifier.serial) ?? _fallbackId();
    } on PlatformException {
      _deviceId = _fallbackId();
    }

    // 2. Créer / mettre à jour le document serveur (merge pour ne pas écraser la config)
    await _upsert({'status': 'online', 'lastSeen': FieldValue.serverTimestamp()});

    // 3. Charger la configuration (opérateurs gérés par ce téléphone)
    await _loadConfig();

    // 4. Démarrer le heartbeat toutes les 30 s
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _sendHeartbeat(),
    );

    debugPrint('[ServerManager] Démarré — deviceId=$_deviceId, operators=$_operators');
  }

  Future<void> _loadConfig() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('servers')
          .doc(_deviceId)
          .get();
      if (doc.exists) {
        final raw = doc.data()?['operators'];
        if (raw is List && raw.isNotEmpty) {
          _operators = raw.map((e) => e.toString()).toList();
        }
      }
    } catch (e) {
      debugPrint('[ServerManager] _loadConfig error: $e');
    }
  }

  Future<void> _upsert(Map<String, dynamic> fields) async {
    await FirebaseFirestore.instance
        .collection('servers')
        .doc(_deviceId)
        .set({'deviceId': _deviceId, ...fields}, SetOptions(merge: true));
  }

  Future<void> _sendHeartbeat() async {
    try {
      await FirebaseFirestore.instance
          .collection('servers')
          .doc(_deviceId)
          .update({'status': 'online', 'lastSeen': FieldValue.serverTimestamp()});
    } catch (_) {}
  }

  /// À appeler dans `dispose` pour marquer le téléphone hors-ligne.
  Future<void> goOffline() async {
    _heartbeatTimer?.cancel();
    try {
      await FirebaseFirestore.instance
          .collection('servers')
          .doc(_deviceId)
          .update({'status': 'offline', 'lastSeen': FieldValue.serverTimestamp()});
    } catch (_) {}
  }

  /// Détermine si CE téléphone doit traiter une transaction donnée.
  ///
  /// [numeroorange] : numéro du payeur (Orange ou MTN)
  /// [status]       : statut actuel de la transaction
  bool canHandle({required String numeroorange, required String status}) {
    if (_operators.contains('all')) return true;

    final prefix = numeroorange.length >= 3 ? numeroorange.substring(0, 3) : '';

    // Filtrage par type de recharge
    if (_operators.contains('prepaid')  && (status == '1' || status == '9')) return true;
    if (_operators.contains('postpaid') && (status == '6'))                  return true;

    // Filtrage par opérateur payeur
    if (_operators.contains('orange') && _orangePrefixes.contains(prefix)) return true;
    if (_operators.contains('mtn')    && _mtnPrefixes.contains(prefix))    return true;

    return false;
  }

  String _fallbackId() =>
      'srv_${DateTime.now().millisecondsSinceEpoch}';
}
