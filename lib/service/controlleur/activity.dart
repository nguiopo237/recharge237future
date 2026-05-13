import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
IdleController idle = Get.find();
class IdleController extends GetxController {
  Timer? _idleTimer;
  final RxBool isIdle = false.obs;
  final Duration idleTimeout = Duration(minutes: 5);

  void resetTimer() {
    _idleTimer?.cancel();
    isIdle.value = false;
    _startTimer();
  }

  void _startTimer() {
    _idleTimer = Timer(idleTimeout, () {
      isIdle.value = true;
      _onIdleDetected();
    });
  }

  void _onIdleDetected() {
    print("Inactivité détectée");
    Get.dialog(
      AlertDialog(
        title: Text("Session inactive"),
        content: Text("Voulez-vous continuer ?"),
        actions: [
          TextButton(
            onPressed: () {
              Get.back();
              resetTimer();
            },
            child: Text("Continuer"),
          ),
        ],
      ),
      barrierDismissible: false,
    );
  }

  @override
  void onClose() {
    _idleTimer?.cancel();
    super.onClose();
  }
}

// Dans votre widget
class HomePage extends StatelessWidget {
  final IdleController controller = Get.put(IdleController());

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => controller.resetTimer(),
      onPanDown: (_) => controller.resetTimer(),
      child: Scaffold(
        appBar: AppBar(title: Text("Accueil")),
        body: Center(
          child: Obx(() => Text(
            controller.isIdle.value ? "Inactif" : "Actif",
          )),
        ),
      ),
    );
  }
}
