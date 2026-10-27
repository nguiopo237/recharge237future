import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'server_manager.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Commandes reconnues (écrites par l'admin dans servers/{deviceId}.command)
// ─────────────────────────────────────────────────────────────────────────────
//
//  "restart"       → recharge toute l'interface (équivalent redémarrage app)
//  "reload_config" → recharge les PIN et les opérateurs depuis Firestore
//  "go_offline"    → arrête de traiter les transactions
//  "go_online"     → reprend le traitement
//  "ping"          → répond avec le statut actuel du téléphone
//
// L'admin écrit dans Firestore :
//   servers/{deviceId}: { "command": "restart", "commandSentAt": <timestamp> }
//
// Le téléphone exécute puis répond :
//   servers/{deviceId}: { "command": null, "commandResponse": "...", "commandResponseAt": <timestamp> }
// ─────────────────────────────────────────────────────────────────────────────

class RemoteCommandHandler {
  RemoteCommandHandler._();
  static final RemoteCommandHandler instance = RemoteCommandHandler._();

  StreamSubscription<DocumentSnapshot>? _subscription;

  // Callback fourni par le widget pour redémarrer l'interface
  VoidCallback? _onRestart;
  // Callback pour recharger la config SIM/PIN dans le widget
  Future<void> Function()? _onReloadConfig;

  /// À appeler dans initState() du widget principal.
  void startListening({
    required VoidCallback onRestart,
    required Future<void> Function() onReloadConfig,
  }) {
    _onRestart = onRestart;
    _onReloadConfig = onReloadConfig;

    final deviceId = ServerManager.instance.deviceId;
    _subscription?.cancel();

    _subscription = FirebaseFirestore.instance
        .collection('servers')
        .doc(deviceId)
        .snapshots()
        .listen((snap) async {
      if (!snap.exists) return;

      final command = snap.data()?['command']?.toString() ?? '';
      if (command.isEmpty) return;

      debugPrint('[RemoteCommand] Commande reçue : $command');

      // Effacer immédiatement pour éviter une double exécution
      await _clearCommand(deviceId);

      switch (command) {
        case 'restart':
          await _respond(deviceId, 'App redémarrée');
          _onRestart?.call();
          break;

        case 'reload_config':
          if (_onReloadConfig != null) await _onReloadConfig!();
          await _respond(deviceId, 'Config rechargée');
          break;

        case 'go_offline':
          await ServerManager.instance.goOffline();
          await _respond(deviceId, 'Téléphone mis hors ligne');
          break;

        case 'go_online':
          await FirebaseFirestore.instance
              .collection('servers')
              .doc(deviceId)
              .update({
            'status': 'online',
            'lastSeen': FieldValue.serverTimestamp(),
          });
          await _respond(deviceId, 'Téléphone remis en ligne');
          break;

        case 'ping':
          await _respond(deviceId,
              'Actif — ${DateTime.now().toIso8601String()}');
          break;

        default:
          debugPrint('[RemoteCommand] Commande inconnue : $command');
          await _respond(deviceId, 'Commande inconnue : $command');
      }
    });

    debugPrint('[RemoteCommand] Écoute démarrée pour $deviceId');
  }

  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
  }

  Future<void> _clearCommand(String deviceId) async {
    try {
      await FirebaseFirestore.instance
          .collection('servers')
          .doc(deviceId)
          .update({'command': FieldValue.delete()});
    } catch (_) {}
  }

  Future<void> _respond(String deviceId, String message) async {
    try {
      await FirebaseFirestore.instance
          .collection('servers')
          .doc(deviceId)
          .update({
        'commandResponse': message,
        'commandResponseAt': FieldValue.serverTimestamp(),
      });
      debugPrint('[RemoteCommand] Réponse envoyée : $message');
    } catch (_) {}
  }
}
