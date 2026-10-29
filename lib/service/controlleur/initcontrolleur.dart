

import 'package:get/get.dart';
import 'package:recharge237_serveur/service/controlleur/transact_controlleur.dart';
import 'package:recharge237_serveur/service/controlleur/widget_controlleur.dart';
import 'package:telephony/telephony.dart';

import 'Reload_controlleur.dart';
import 'home_controlleur.dart';


class AppControllers {

  static initialize() async {

    Get.put(widgetControlleur(), permanent: true);
    Get.put(Homecontolleur(), permanent: true);
    Get.put(ReloadControlleur(), permanent: true);
    Get.put(TransactControlleur(), permanent: true);


  }
}