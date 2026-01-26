import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:sms_autofill/sms_autofill.dart';

Homecontolleur c = Get.find();
class Homecontolleur extends GetxController{

  getmodal(

      {Widget? sectionview, states, isDismissible = true, enableDrag = true})
  {
    Get.bottomSheet(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        isScrollControlled: true,
        isDismissible: isDismissible,
        enableDrag: enableDrag,
        Material(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20), topRight: Radius.circular(20))),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
            child: StatefulBuilder(
              builder: (context, states) {
                return Container(
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10)),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        sectionview!,
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ));
  }

  getdialog({Widget? sectionview, states}) {
    return Get.dialog(barrierDismissible: false,
        Dialog(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            sectionview!,
          ],
        ),
      ),
    ));
  }
  //CountdownController countdownController = CountdownController();
  TextEditingController otpEditingController = TextEditingController();
  var messageOtpCode = ''.obs;




  @override
  void onInit() async {
    super.onInit();
    print(" ecoute signature");
    print(await SmsAutoFill().getAppSignature);
    print(" ecoute signature");
    // Listen for SMS OTP
    await SmsAutoFill().listenForCode();


  }




}