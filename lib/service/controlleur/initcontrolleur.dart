

import 'package:get/get.dart';
import 'package:projettest/service/controlleur/transact_controlleur.dart';
import 'package:projettest/service/controlleur/ussdcontrolleur.dart';
import 'package:projettest/service/controlleur/widget_controlleur.dart';


import 'Reload_controlleur.dart';
import 'activity.dart';
import 'appcycle_controlleur.dart';
import 'home_controlleur.dart';


class AppControllers {

  static initialize() async {

    Get.put(widgetControlleur(), permanent: true);
    // Get.put(IdleController(), permanent: true);
    Get.put(UssdController(), permanent: true);
    Get.put(Homecontolleur(), permanent: true);
    Get.put(ReloadControlleur(), permanent: true);
    Get.put(TransactControlleur(), permanent: true);


  }
}