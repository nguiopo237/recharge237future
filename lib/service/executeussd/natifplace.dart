import 'package:flutter/services.dart';

class UssdLauncher {
  static const MethodChannel _channel = MethodChannel('ussd_launcher');

  // Variable pour stocker le callback
  static Function(String)? _ussdMessageCallback;

  // Initialisation du listener
  static void _initializeListener() {
    _channel.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'onUssdMessageReceived') {
        final String message = call.arguments;
        print("Message USSD reçu dans le handler: $message");

        // Appeler le callback si défini
        if (_ussdMessageCallback != null) {
          _ussdMessageCallback!(message);
        }
      }
      return null;
    });
  }

  // Méthode pour écouter les messages USSD
  static void listenToUssdMessages(Function(String) onMessageReceived) {
    _ussdMessageCallback = onMessageReceived;
    _initializeListener();
  }

  // Pour lancer une requête USSD
  static Future<String?> sendUssdRequest({
    required String ussdCode,
    required int subscriptionId,
  }) async {
    try {
      final String? response = await _channel.invokeMethod('multisessionUssd', {
        'ussdCode': ussdCode,
        'slotIndex': 0,
        'options': ["1","2"],
      });
      print("resultat de la reponse 2.0");
      return response;
    } on PlatformException catch (e) {
      print("Erreur: ${e.message}");
      return null;
    }
  }
}