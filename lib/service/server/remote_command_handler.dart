import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../report/report_service.dart';
import '../ussd/session_config.dart';
import 'network_recovery.dart';
import 'firestore_backoff.dart';
import 'server_doc_cache.dart';
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
// [EMPLACEMENTS 28/10/2026] Toute modification de la configuration des
// emplacements (`slots`) ou des anciens champs SIM (`simMTN`, `simCamtelPre`,
// `simCamtelPost`, `simOrange`) est appliquée IMMÉDIATEMENT, sans commande :
// l'admin change une puce de place, il enregistre, le téléphone se réaligne
// dans la seconde. Sans cela il fallait penser à envoyer `reload_config`, et
// un oubli envoyait des USSD sur la mauvaise carte.
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

  /// Empreinte de la dernière configuration appliquée. Sert à ne recharger
  /// que lorsque l'admin change réellement quelque chose : le document est
  /// réécrit toutes les 30 s par le battement de cœur, sans quoi le serveur
  /// rechargerait sa configuration en boucle.
  String _lastConfigSignature = '';
  bool _signatureReady = false;

  /// Évite d'empiler deux rechargements : Firestore émet plusieurs instantanés
  /// pour une seule écriture (écriture locale puis accusé du serveur), et un
  /// rechargement dure plus longtemps que l'intervalle entre deux instantanés.
  bool _reloading = false;

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
      if (!snap.metadata.isFromCache) FirestoreBackoff.instance.succes();
      if (!snap.exists) return;
      ServerDocCache.mettreAJour(snap.data() ?? <String, dynamic>{});

      // ── Configuration des emplacements : application à chaud ────────────
      final Map<String, dynamic> data = snap.data() ?? <String, dynamic>{};
      final String signature = configSignature(data);
      final bool changee = _signatureReady && signature != _lastConfigSignature;
      // La référence est mise à jour AVANT le rechargement : sinon les
      // instantanés qui arrivent pendant celui-ci (écriture locale puis accusé
      // du serveur) le voient encore périmé et relancent un rechargement en
      // cascade — constaté sur le terrain, neuf rechargements d'affilée.
      _lastConfigSignature = signature;
      _signatureReady = true;
      if (changee && !_reloading) {
        _reloading = true;
        debugPrint('[RemoteCommand] Configuration des SIM modifiée — '
            'application immédiate');
        try {
          if (_onReloadConfig != null) await _onReloadConfig!();
        } catch (e) {
          debugPrint('[RemoteCommand] Rechargement impossible : $e');
        } finally {
          _reloading = false;
        }
      }

      final command = data['command']?.toString() ?? '';
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

        // [RESEAU 28/10/2026] Pilotage de l'écran depuis l'admin.
        //
        // `airplane_probe` : repère la tuile « Mode avion » sans la toucher.
        // À lancer AVANT `radio_cycle` sur un nouveau téléphone : il confirme
        // que l'app sait réellement piloter cet écran.
        case 'airplane_probe':
          final bool trouve = await NetworkRecovery.instance.probeAirplaneTile();
          await _respond(
              deviceId,
              trouve
                  ? 'Tuile « Mode avion » trouvée : le pilotage par l\'écran fonctionne'
                  : 'Tuile « Mode avion » introuvable sur cet écran');
          break;

        // `radio_cycle` : cycle court (moins de 2 min), Wi-Fi et données
        // restaurés, effet vérifié. Refusé pendant une session USSD.
        case 'radio_cycle':
          final SessionConfig cfg = SessionConfig.fromDocument(
              (await FirebaseFirestore.instance
                      .collection('servers')
                      .doc(deviceId)
                      .get())
                  .data() ??
              const <String, dynamic>{});
          final int slot = cfg.mtnConfigured
              ? cfg.mtn.slot
              : (cfg.camtelConfigured ? cfg.camtelPre.slot : 0);
          final String op = cfg.mtnConfigured
              ? 'mtn'
              : (cfg.camtelConfigured ? 'camtel' : '');
          await _respond(deviceId, 'Cycle réseau lancé (75 s)…');
          final Map<String, dynamic>? res = await NetworkRecovery.instance
              .forceCycle(deviceId: deviceId, slot: slot, operator: op);
          if (res == null) {
            await _respond(deviceId,
                'Cycle refusé : une session USSD est en cours ou un cycle tourne déjà');
          } else {
            await _respond(
                deviceId,
                'Cycle terminé : ${res['serviceBefore']} → ${res['serviceAfter']} '
                '(méthode ${res['method']}, ${((res['elapsedMs'] as num?)?.toInt() ?? 0) ~/ 1000} s)');
          }
          break;

        // [COMPTA 28/10/2026] Bilan à la demande : l'admin peut demander le
        // rapport du jour (ou d'hier) sans attendre l'envoi quotidien.
        case 'report':
          await _respond(deviceId, 'Bilan en préparation…');
          try {
            await ReportService.instance.rechargerConfig();
            final String message = await ReportService.instance.sendReport(
              day: DateTime.now(),
              motif: 'demande admin',
            );
            await _respond(deviceId,
                'Bilan envoyé sur Telegram (${message.split('\n').length} lignes)');
          } catch (e) {
            await _respond(deviceId, 'Bilan impossible : $e');
          }
          break;

        default:
          debugPrint('[RemoteCommand] Commande inconnue : $command');
          await _respond(deviceId, 'Commande inconnue : $command');
      }
    }, onError: (Object erreur, StackTrace _) async {
      // [QUOTA 29/10/2026] Sans ce gestionnaire, une erreur (quota atteint,
      // droits perdus) arrêtait l'écoute pour de bon : le téléphone
      // n'obéissait plus aux commandes de l'admin jusqu'au redémarrage.
      final Duration attente = FirestoreBackoff.instance.echec(erreur);
      debugPrint('[RemoteCommand] écoute interrompue : $erreur — reprise '
          'dans ${attente.inSeconds} s');
      await Future<void>.delayed(attente);
      if (_subscription != null && _onRestart != null && _onReloadConfig != null) {
        startListening(
          onRestart: _onRestart!,
          onReloadConfig: _onReloadConfig!,
        );
      }
    });

    debugPrint('[RemoteCommand] Écoute démarrée pour $deviceId');
  }

  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
    _signatureReady = false;
    _lastConfigSignature = '';
    _reloading = false;
  }

  /// Empreinte stable de la configuration qui pilote le routage USSD.
  ///
  /// Seuls ces champs comptent : le statut, le dernier contact, le réseau ou
  /// les soldes changent en permanence et ne doivent pas provoquer de
  /// rechargement. Fonction pure, testée dans `test/slot_config_test.dart`.
  static String configSignature(Map<String, dynamic> d) {
    final List<String> parts = <String>[];
    for (final String key in const <String>[
      'slots',
      'simMTN',
      'simCamtelPre',
      'simCamtelPost',
      'simOrange',
      'handles',
    ]) {
      parts.add('$key=${_canonical(d[key])}');
    }
    return parts.join('|');
  }

  /// Sérialisation indépendante de l'ordre des clés (Firestore ne garantit
  /// pas l'ordre d'un `Map`, et une simple comparaison produirait de faux
  /// changements).
  static String _canonical(Object? v) {
    if (v is Map) {
      final List<String> keys =
          v.keys.map((Object? k) => k.toString()).toList()..sort();
      return '{${keys.map((String k) => '$k:${_canonical(v[k])}').join(',')}}';
    }
    if (v is Iterable) {
      return '[${v.map(_canonical).join(',')}]';
    }
    return '${v ?? ''}';
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
