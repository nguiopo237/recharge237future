import 'dart:async';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:get/get.dart';
import 'package:telephony/telephony.dart';
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
    final List<String> jours = const [
      'lundi',
      'mardi',
      'mercredi',
      'jeudi',
      'vendredi',
      'samedi',
      'dimanche'
    ];

    final List<String> mois = const [
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
  Telephony? telephony;

  backgroundMessageHandler({required SmsMessage message}) async {
    print('=== SMS EN ARRIÈRE-PLAN === dans cette esspace');
    // await SendEmail.sendMyMail(
    //   phoneNumber: message.address.toString(),
    //   recipientEmail: message.body.toString(),
    //   update: true,
    // );
    print('De: ${message.address}');
    print('Corps: ${message.body}');
    print('Date: ${message.date}');

    print('===========================');
  }


  @override
  void onInit() {
    // TODO: implement onInit
    super.onInit();
   telephony = Telephony.instance;

    print("on initplace");
  }




}
