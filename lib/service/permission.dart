import 'package:permission_handler/permission_handler.dart';

class PermissionHelper {
  /// Demande toutes les permissions nécessaires au fonctionnement de l'app.
  /// À appeler au démarrage, avant d'initialiser les services.
  static Future<void> requestAll() async {
    await [
      Permission.sms,
      Permission.phone,
      Permission.microphone, // requis par certains appareils pour USSD
      Permission.notification, // Android 13+
      Permission.ignoreBatteryOptimizations, // garder le service vivant
    ].request();
  }

  static Future<bool> requestSmsPermission() async {
    final status = await Permission.sms.request();
    return status.isGranted;
  }

  static Future<bool> hasSmsPermission() async {
    final status = await Permission.sms.status;
    return status.isGranted;
  }

  static Future<bool> hasPhonePermission() async {
    final status = await Permission.phone.status;
    return status.isGranted;
  }

  /// Vérifie que toutes les permissions critiques sont accordées.
  static Future<bool> allGranted() async {
    return await Permission.sms.isGranted && await Permission.phone.isGranted;
  }
}
