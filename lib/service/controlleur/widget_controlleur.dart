import 'dart:async';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:get/get.dart';

widgetControlleur c = Get.find();

class widgetControlleur extends GetxController {
  StreamSubscription? subscription;
  RxBool isDeviceConnected = false.obs;
  RxBool isAlertSet = false.obs;
  RxList docid = [].obs;
  void restartApp() {
    Get.reset();
  }

  String formaterDateFrancais(DateTime date) {
    const List<String> jours = [
      'lundi',
      'mardi',
      'mercredi',
      'jeudi',
      'vendredi',
      'samedi',
      'dimanche'
    ];

    const List<String> mois = [
      'janvier',
      'février',
      'mars',
      'avril',
      'mai',
      'juin',
      'juillet',
      'août',
      'septembre',
      'octobre',
      'novembre',
      'décembre'
    ];

    return '${jours[date.weekday - 1]} ${date.day} ${mois[date.month - 1]} ${date.year}';
  }

  String formaterHeure(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}:'
        '${date.second.toString().padLeft(2, '0')}';
  }

  void startBackgroundService() {
    final service = FlutterBackgroundService();
    service.startService();
  }

  void stopBackgroundService() {
    final service = FlutterBackgroundService();
    service.invoke("stop");
  }
  // [29/10/2026] Paquet `telephony` retiré (abandonné, il bloquait la
  // compilation). L'écoute des SMS en arrière-plan qui vivait ici ne servait
  // plus : les commandes passent par Firestore et les sessions USSD.

  @override
  void onInit() {
    // TODO: implement onInit
    super.onInit();

    print("on initplace");
  }
}
