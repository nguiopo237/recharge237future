import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../sendmail/send_mail.dart';
import '../ussd/sim_network.dart';
import '../ussd/ussd_session.dart';

/// [RESEAU 28/10/2026] Récupération automatique du réseau d'une carte bloquée
/// en « appels d'urgence uniquement ».
///
/// Constaté en production les 27 et 28/10 : une SIM MTN restait des heures
/// « Appels d'urgence uniquement » alors que le réseau existait. La carte ne se
/// ré-inscrit pas toute seule, et aucune commande ne peut être livrée. Le seul
/// remède connu est un cycle court du mode avion, qui force une nouvelle
/// inscription.
///
/// Règles imposées par l'admin, appliquées ici sans exception :
///  - le cycle complet tient en **moins de 2 minutes** ;
///  - le Wi-Fi et les données mobiles sont **remis dans l'état d'avant** : un
///    serveur sans internet ne peut plus lire la base ni recevoir d'ordres ;
///  - on n'agit **jamais** pendant une session USSD (une opération payée par le
///    client ne doit pas être coupée en plein menu) ;
///  - une tentative au maximum toutes les 30 minutes par téléphone, et
///    seulement après 8 minutes de coupure réelle ;
///  - l'effet est **vérifié** : si la radio n'a pas bougé, l'admin est prévenu
///    au lieu de lui faire croire que le serveur s'est réparé.
class NetworkRecovery {
  NetworkRecovery._();
  static final NetworkRecovery instance = NetworkRecovery._();

  static const MethodChannel _native = MethodChannel('r237/ussd');

  /// Une coupure plus courte se rétablit souvent d'elle-même : inutile de
  /// toucher à la radio.
  static const Duration downBefore = Duration(minutes: 8);

  /// Jamais deux cycles rapprochés : laisser le temps à l'inscription de se
  /// faire, et ne pas vider la batterie.
  static const Duration minInterval = Duration(minutes: 30);

  /// Durée coupée (mode avion actif).
  static const Duration airplaneOn = Duration(seconds: 35);

  /// Attente d'inscription après le retour du réseau.
  static const Duration registrationWait = Duration(seconds: 40);

  /// Marge de sécurité pour l'aller-retour natif (le cycle lui-même dure
  /// 75 s ; au-delà de 3 min le natif ne répond plus, on abandonne).
  static const Duration nativeTimeout = Duration(minutes: 3);

  DateTime? _lastAttempt;
  bool _running = false;

  /// Vrai pendant un cycle (pour ne pas en lancer deux).
  bool get running => _running;

  /// Dernière tentative, pour l'écran serveur.
  DateTime? get lastAttempt => _lastAttempt;

  /// Décide si un cycle a un sens pour cet emplacement.
  ///
  /// Fonction pure : testée dans test/network_recovery_test.dart.
  static bool shouldAttempt({
    required String serviceLabel,
    required bool airplaneMode,
    required String simState,
    required DateTime? downSince,
    required DateTime? lastAttempt,
    required DateTime now,
    required bool sessionBusy,
  }) {
    if (sessionBusy) return false;
    if (downSince == null) return false;
    if (now.difference(downSince) < downBefore) return false;
    // Laisser le temps entre deux cycles.
    if (lastAttempt != null && now.difference(lastAttempt) < minInterval) {
      return false;
    }
    // Mode avion déjà actif : c'est un réglage volontaire, on n'y touche pas.
    if (airplaneMode) return false;
    // Carte absente, verrouillée, illisible : un cycle n'y changerait rien.
    if (kSimHardBlocked.contains(simState)) return false;
    // Seuls les états « pas de couverture » méritent un cycle.
    return serviceLabel == 'OUT_OF_SERVICE' ||
        serviceLabel == 'EMERGENCY_ONLY' ||
        serviceLabel == 'UNKNOWN' ||
        serviceLabel.isEmpty;
  }

  /// [RESEAU 28/10/2026] Sonde SANS RISQUE : repère la tuile « Mode avion » du
  /// tiroir de réglages rapides et lit son état, sans la toucher.
  ///
  /// Sert à savoir, AVANT de couper la radio d'un téléphone de production, si
  /// le pilotage par l'écran est possible sur ce modèle.
  Future<bool> probeAirplaneTile() async {
    try {
      return await _native.invokeMethod<bool>('airplaneProbe') ?? false;
    } catch (e) {
      debugPrint('[Recovery] sonde mode avion impossible : $e');
      return false;
    }
  }

  /// Cycle forcé par l'admin, sans attendre les conditions habituelles.
  ///
  /// Utilisé par la commande à distance `radio_cycle`. Les garde-fous qui
  /// protègent l'argent du client restent appliqués : jamais pendant une
  /// session USSD, et jamais si une commande est en cours d'exécution.
  Future<Map<String, dynamic>?> forceCycle({
    required String deviceId,
    required int slot,
    required String operator,
  }) async {
    if (_running) return null;
    if (UssdSessionRunner.instance.busy) {
      debugPrint('[Recovery] cycle refusé : session USSD en cours');
      return null;
    }
    _running = true;
    _lastAttempt = DateTime.now();
    Map<String, dynamic>? res;
    try {
      res = await _native
          .invokeMapMethod<String, dynamic>('radioCycle', <String, dynamic>{
        'slot': slot,
        'onMs': airplaneOn.inMilliseconds,
        'waitMs': registrationWait.inMilliseconds,
      })
          .timeout(nativeTimeout);
    } catch (e) {
      debugPrint('[Recovery] cycle forcé impossible : $e');
    } finally {
      _running = false;
    }
    await _publish(deviceId, slot, operator, res);
    return res;
  }

  /// Enregistre le résultat et prévient l'admin sur Telegram.
  Future<void> _publish(
    String deviceId,
    int slot,
    String operator,
    Map<String, dynamic>? res,
  ) async {
    final String avant = (res?['serviceBefore'] ?? '').toString();
    final String apres = (res?['serviceAfter'] ?? '').toString();
    final bool retabli = apres == 'IN_SERVICE';
    final bool radioChanged = res?['radioChanged'] == true;
    final bool tente = res?['attempted'] == true;
    final bool wifiOk = res?['wifiRestored'] != false;
    final bool dataOk = res?['dataRestored'] != false;
    final int elapsed = (res?['elapsedMs'] as num?)?.toInt() ?? 0;
    final String methode = (res?['method'] ?? '').toString();

    final String rapport = _message(
      slot: slot,
      operator: operator,
      tente: tente,
      radioChanged: radioChanged,
      avant: avant,
      apres: apres,
      retabli: retabli,
      wifiOk: wifiOk,
      dataOk: dataOk,
      elapsed: elapsed,
      methode: methode,
      detail: (res?['detail'] ?? '').toString(),
    );

    try {
      await FirebaseFirestore.instance.collection('servers').doc(deviceId).set(
        <String, dynamic>{
          'lastRecovery': <String, dynamic>{
            'at': DateTime.now().toUtc().toIso8601String(),
            'slot': slot,
            'operator': operator,
            'attempted': tente,
            'radioChanged': radioChanged,
            'serviceBefore': avant,
            'serviceAfter': apres,
            'recovered': retabli,
            'wifiRestored': wifiOk,
            'dataRestored': dataOk,
            'method': methode,
            'elapsedMs': elapsed,
            'detail': (res?['detail'] ?? '').toString(),
          },
        },
        SetOptions(merge: true),
      ).timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('[Recovery] rapport non enregistré : $e');
    }

    await SendEmail.sendMessagewithtelegram(message: rapport);
  }

  /// Lance un cycle si les conditions sont réunies. Ne leve jamais d'exception.
  Future<void> maybeRecover({
    required String deviceId,
    required List<Map<String, dynamic>> network,
    required Map<int, DateTime> downSince,
  }) async {
    if (_running || deviceId.isEmpty) return;
    final DateTime now = DateTime.now();

    Map<String, dynamic>? cible;
    for (final Map<String, dynamic> r in network) {
      if (r['ok'] == true) continue;
      final int slot = (r['slot'] as num?)?.toInt() ?? 0;
      final bool possible = shouldAttempt(
        serviceLabel: (r['label'] ?? '').toString(),
        airplaneMode: r['airplane'] == true,
        simState: (r['simState'] ?? '').toString(),
        downSince: downSince[slot],
        lastAttempt: _lastAttempt,
        now: now,
        sessionBusy: UssdSessionRunner.instance.busy,
      );
      if (possible) {
        cible = r;
        break;
      }
    }
    if (cible == null) return;

    final int slot = (cible['slot'] as num?)?.toInt() ?? 0;
    final String operateur = (cible['operator'] ?? '').toString();
    _running = true;
    _lastAttempt = now;
    debugPrint('[Recovery] cycle mode avion sur SIM ${slot + 1} ($operateur)');

    Map<String, dynamic>? res;
    try {
      res = await _native
          .invokeMapMethod<String, dynamic>('radioCycle', <String, dynamic>{
        'slot': slot,
        'onMs': airplaneOn.inMilliseconds,
        'waitMs': registrationWait.inMilliseconds,
      })
          .timeout(nativeTimeout);
    } catch (e) {
      debugPrint('[Recovery] cycle impossible : $e');
    } finally {
      _running = false;
    }

    await _publish(deviceId, slot, operateur, res);
  }

  /// Texte envoyé à l'admin. Dit ce qui a été tenté ET ce qui en est résulté,
  /// jamais « réparé » sans preuve.
  static String _message({
    required int slot,
    required String operator,
    required bool tente,
    required bool radioChanged,
    required String avant,
    required String apres,
    required bool retabli,
    required bool wifiOk,
    required bool dataOk,
    required int elapsed,
    required String methode,
    required String detail,
  }) {
    final StringBuffer b = StringBuffer()
      ..writeln(
          'Recharge237 — ${retabli ? 'RÉSEAU RÉTABLI' : 'TENTATIVE RÉSEAU'}')
      ..writeln('SIM       : slot ${slot + 1} '
          '(${operatorDisplayName(operator)})')
      ..writeln('Avant     : ${avant.isEmpty ? 'inconnu' : avant}')
      ..writeln('Après     : ${apres.isEmpty ? 'inconnu' : apres}')
      ..writeln('Durée     : ${(elapsed / 1000).round()} s');
    if (!tente) {
      b.writeln('Résultat  : cycle refusé par le téléphone : $detail');
    } else if (!radioChanged) {
      b.writeln('Résultat  : SANS EFFET — ni le réglage système ni la tuile '
          '« Mode avion » n\'ont pu être actionnés sur ce téléphone. Fais le '
          'cycle à la main une fois, puis signale-le.');
    } else if (methode == 'ecran') {
      b.writeln('Résultat  : radio basculée par l\'écran (tuile Mode avion).');
    } else if (retabli) {
      b.writeln('Résultat  : carte ré-inscrite, les commandes en attente '
          'repartent automatiquement.');
    } else {
      b.writeln('Résultat  : toujours hors réseau après le cycle — la '
          'couverture de cet opérateur est probablement absente ici.');
    }
    if (!wifiOk || !dataOk) {
      b.writeln('Attention : Wi-Fi ${wifiOk ? 'OK' : 'NON RÉTABLI'} · '
          'données mobiles ${dataOk ? 'OK' : 'NON RÉTABLIES'} — vérifie le '
          'téléphone.');
    }
    return b.toString().trimRight();
  }
}
