import 'package:flutter/services.dart';

/// Un SMS reçu par le téléphone serveur.
class SmsRecu {
  final String address;
  final String body;
  final DateTime date;

  const SmsRecu(
      {required this.address, required this.body, required this.date});
}

/// [SMS 29/10/2026] Réception des SMS, sans plugin.
///
/// Remplace le paquet `telephony` (abandonné, retiré car il bloquait la
/// compilation). Le récepteur Android vit dans MainActivity.kt (canal
/// `r237/sms`) ; il exige la permission RECEIVE_SMS, demandée au démarrage
/// (main.dart, checkSmsPermissions).
///
/// [flux] est partagé : plusieurs services peuvent l'écouter en même temps
/// (bilan des soldes, relais Telegram) avec un seul récepteur natif.
class SmsReceiver {
  SmsReceiver._();

  static const EventChannel _canal = EventChannel('r237/sms');
  static Stream<SmsRecu>? _flux;

  static Stream<SmsRecu> get flux =>
      _flux ??= _canal.receiveBroadcastStream().map((dynamic e) {
        final Map<dynamic, dynamic> m = e as Map<dynamic, dynamic>;
        final Object? date = m['date'];
        return SmsRecu(
          address: (m['address'] ?? '').toString(),
          body: (m['body'] ?? '').toString(),
          date: date is int
              ? DateTime.fromMillisecondsSinceEpoch(date)
              : DateTime.now(),
        );
      }).asBroadcastStream();
}
