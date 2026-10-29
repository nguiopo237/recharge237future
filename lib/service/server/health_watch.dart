import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../main.dart' show serverAuthUid;
import '../sendmail/send_mail.dart';
import '../ussd/ussd_session.dart';
import 'firestore_backoff.dart';

/// [SANTE 29/10/2026] Santé du téléphone serveur, publiée pour l'admin.
///
/// Répond aux cas P0 de docs/EXPLOITATION_TELEPHONES.md :
/// - §3.1 `accessibilityOk` : sans le service d'accessibilité, toutes les
///   commandes échouent alors que le téléphone paraît « en ligne ». Alerte
///   Telegram à chaque changement.
/// - §3.2 `authUid` : l'UID Firebase du téléphone, celui que l'admin doit
///   autoriser (bouton « Autoriser ce téléphone » de l'écran serveurs).
/// - §3.3 fenêtre USSD restée ouverte hors session (app tuée) : fermée à
///   chaque contrôle, jamais pendant une session.
///
/// Économe en quota : un contrôle toutes les 5 min, mais une écriture
/// seulement quand quelque chose change.
class HealthWatch {
  HealthWatch._();
  static final HealthWatch instance = HealthWatch._();

  static const Duration periode = Duration(minutes: 5);
  static const Duration premierControle = Duration(seconds: 30);

  String _deviceId = '';
  Timer? _timer;
  Timer? _premier;

  bool? _accessibilitePubliee;
  String? _uidPublie;

  void start(String deviceId) {
    if (_deviceId == deviceId && _timer != null) return;
    _deviceId = deviceId;
    _timer?.cancel();
    _premier?.cancel();
    _timer = Timer.periodic(periode, (_) => checkNow());
    _premier = Timer(premierControle, checkNow);
  }

  void stop() {
    _timer?.cancel();
    _premier?.cancel();
    _timer = null;
    _premier = null;
  }

  Future<void> checkNow() async {
    if (_deviceId.isEmpty) return;

    // §3.3 — Jamais pendant une session : « Annuler » couperait une opération
    // que le client a déjà payée.
    bool fenetreFermee = false;
    if (!UssdSessionRunner.instance.busy) {
      fenetreFermee = await UssdSessionRunner.instance.clearStaleDialog();
    }

    final bool accessibiliteOk =
        await UssdSessionRunner.instance.accessibilityReady();
    final String uid = serverAuthUid;

    final bool aPublier = accessibiliteOk != _accessibilitePubliee ||
        uid != _uidPublie ||
        fenetreFermee;
    if (!aPublier || FirestoreBackoff.instance.enPause) return;

    try {
      await FirebaseFirestore.instance
          .collection('servers')
          .doc(_deviceId)
          .set(<String, dynamic>{
            'accessibilityOk': accessibiliteOk,
            'accessibilityCheckedAt': FieldValue.serverTimestamp(),
            if (uid.isNotEmpty) 'authUid': uid,
            if (fenetreFermee)
              'lastStaleDialogClosedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true))
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      if (FirestoreBackoff.estTransitoire(e)) {
        FirestoreBackoff.instance.echec(e);
      }
      debugPrint('[HealthWatch] publication impossible : $e');
      return;
    }

    final bool? avant = _accessibilitePubliee;
    _accessibilitePubliee = accessibiliteOk;
    _uidPublie = uid;

    // Alerte au changement, et dès le premier contrôle si le service est
    // déjà coupé (cas typique : app réinstallée, MIUI l'a désactivé).
    if (avant != accessibiliteOk && (avant != null || !accessibiliteOk)) {
      await _telegram(accessibiliteOk
          ? 'Recharge237 — ACCESSIBILITÉ RÉTABLIE\n'
              'Téléphone : $_deviceId\n'
              'Les commandes USSD peuvent de nouveau être livrées.'
          : 'Recharge237 — ACCESSIBILITÉ COUPÉE\n'
              'Téléphone : $_deviceId\n'
              'Toutes les commandes USSD de ce téléphone échoueront. Réactive '
              'le service : Paramètres > Accessibilité > ServeurApp Recharge237.');
    }
    if (fenetreFermee) {
      debugPrint('[HealthWatch] fenêtre USSD orpheline fermée');
    }
  }

  Future<void> _telegram(String message) async {
    try {
      await SendEmail.sendMessagewithtelegram(message: message);
    } catch (e) {
      debugPrint('[HealthWatch] Telegram injoignable : $e');
    }
  }
}
