import 'package:sms_autofill/sms_autofill.dart';

class Homecontolleurs with CodeAutoFill {
  String? _lastCode;
  String? _lastMessage;
  DateTime? _lastTimestamp;
  Function(String)? onCodeReceived;

  // Getter pour accéder aux dernières données
  String? get lastCode => _lastCode;
  String? get lastMessage => _lastMessage;
  DateTime? get lastTimestamp => _lastTimestamp;

  void initializeSmsListener({Function(String)? onCodeCallback}) async {
    onCodeReceived = onCodeCallback;

    try {
      print("🚀 Initialisation de l'écoute SMS...");

      final signature = await SmsAutoFill().getAppSignature;
      print("📝 Signature app: $signature");

      listenForCode();

      print("✅ Écoute SMS active");
    } catch (e) {
      print("❌ Erreur initialisation SMS: $e");
    }
  }

  @override
  void codeUpdated() {
    if (code != null) {
      _lastCode = code;
      _lastMessage = "Code SMS reçu: $code";
      _lastTimestamp = DateTime.now();

      print("=================================");
      print("✅ NOUVEAU SMS DÉTECTÉ !");
      print("📨 Code: $code");
      print("🕒 $_lastTimestamp");
      print("=================================");

      onCodeReceived?.call(code!);
    }
  }

  // Méthode pour afficher le dernier message
  void displayLastMessage() {
    if (_lastCode == null) {
      print("📭 Aucun message intercepté pour le moment");
      return;
    }

    print("\n" * 3);
    print("📋 DERNIER MESSAGE INTERCEPTÉ");
    print("================================");
    print("🔐 Code: $_lastCode");
    print("📝 Message: $_lastMessage");
    print("⏰ Heure: ${_lastTimestamp?.toString() ?? 'Inconnue'}");
    print("================================");
    print("\n" * 3);
  }

  void dispose() {
    cancel();
    print("🔴 Écoute SMS arrêtée");
  }
}
