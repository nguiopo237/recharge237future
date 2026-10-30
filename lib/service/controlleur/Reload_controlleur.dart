import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:unique_identifier/unique_identifier.dart';

ReloadControlleur r = Get.find();

class ReloadControlleur extends GetxController {
  RxBool read = false.obs;
  FocusNode focusNode = FocusNode();
  TextEditingController number1 = TextEditingController();
  TextEditingController amounts = TextEditingController();
  TextEditingController number2 = TextEditingController();
  GlobalKey<FormState> formKey = GlobalKey<FormState>();

  List numbers = [
    "650",
    "651",
    "652",
    "653",
    "654",
    "67",
    "680",
    "681",
    "682",
    "683",
  ];
  List numberc = [
    "620",
    "621",
    "242",
    "243",
  ];
  List numbero = [
    "655",
    "656",
    "657",
    "658",
    "6590",
    "6591",
    "6592",
    "6593",
    "6594",
    "6595",
    "69",
  ];

// Définir les regex une fois (en dehors de la fonction)
  final RegExp numbersRegex =
      RegExp(r'^(650|651|652|653|654|67|680|681|682|683)');
  final RegExp numbercRegex = RegExp(r'^(620|621|622|242|243)');
  final RegExp numberoRegex = RegExp(r'^(655|656|657|658|659[0-5]|69)');

  Future<String> detectOperator(String? number) async {
    if (number == null) {
      number = "000";
    } else {}

    if (number != "000" || number!.isNotEmpty && number.length == 9) {
      error3.value = true;

      String prefix = number.substring(0, 3);

      if (numbersRegex.hasMatch(prefix)) {
        detectedOperator.value = "MTN Mobile Money";
        operatorLogo.value = "images/MTN_logo.png";
        print(operatorLogo);
        formKey.currentState?.validate();
        return detectedOperator.value;
      } else if (numberoRegex.hasMatch(prefix)) {
        detectedOperator.value = "Orange Money";
        operatorLogo.value = "images/omlogo.png";
        print(operatorLogo);
        formKey.currentState?.validate();
        return detectedOperator.value;
      } else if (numbercRegex.hasMatch(prefix)) {
        detectedOperator.value = "Camtel";
        operatorLogo.value = "images/blue.png";
        print(operatorLogo);
        formKey.currentState!.validate();
        return "";
      } else {
        detectedOperator.value = "";
        return "";
      }
    } else {
      detectedOperator.value = "";
      operatorLogo.value = "";
      error3.value = false;
    }
    return "";
  }

  Future<String> detectOperator2(String? number) async {
    if (number!.isNotEmpty) {
      String prefix = number.substring(0, 3);

      if (numbersRegex.hasMatch(prefix)) {
        detectedOperator.value = "MTN Mobile Money";
        operatorLogoall.value = "images/MTN_logo.png";
        print(operatorLogo);
        formKey.currentState?.validate();
        return operatorLogoall.value;
      } else if (numberoRegex.hasMatch(prefix)) {
        detectedOperator.value = "Orange Money";
        operatorLogoall.value = "images/omlogo.png";
        print(operatorLogo);
        formKey.currentState?.validate();
        return operatorLogoall.value;
      }
    } else {
      detectedOperator.value = "";
      operatorLogo.value = "";
      error3.value = false;
    }
    return "";
  }

  List<int> presetAmounts = [500, 1000, 2000, 3000, 5000, 10000];
  RxBool verifie = false.obs;
  RxBool error1 = false.obs;
  RxBool error2 = false.obs;
  RxBool error3 = false.obs;
  RxBool error4 = true.obs;
  RxBool error = false.obs;
  RxBool orange = true.obs;
  RxBool loader = false.obs;
  int index = 0;
  RxString detectedOperator = "Opérateur inconnu".obs;
  RxString detectedOperator1 = "Opérateur inconnu".obs;
  RxString detectedOperatorall = "Opérateur inconnu".obs;
  RxString operatorLogo = "".obs; // Stocke le chemin vers le logo
  RxString operatorLogo1 = "".obs; // Stocke le chemi
  RxString operatorLogoall = "".obs; // Stocke le chemi
}
