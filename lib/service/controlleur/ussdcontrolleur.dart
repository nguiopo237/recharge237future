// ussd_controller.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../fonctionfire.dart';
import '../sendmail/send_mail.dart';
UssdController ussd = Get.find();
enum MessageType {
  pinRequest,
  success,
  error,
  invalidCode,
  unknown,
}
class UssdController extends GetxController {
  static const MethodChannel _methodChannel = MethodChannel('ussd_launcher');
  static const EventChannel _eventChannel = EventChannel('ussd_launcher_events');

  var messages = <String>[].obs;
  var lastMessage = "".obs;
  var idtransacts = "".obs;
  RxInt operationlengh = 0.obs;
  RxInt operationforfaitlengh = 0.obs;
  var documentid = "".obs;
  RxInt statuts = 0.obs;
  var isConnected = false.obs;
  StreamSubscription? _eventSubscription;

  @override
  void onInit() {
    super.onInit();
    _initUssdListener();
  }

  void _initUssdListener() async {
    try {
      // Essayer de se connecter à l'EventChannel
      _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
            (event) {
          _onUssdMessageReceived(event.toString());
        },
        onError: (error) {
          print("❌ EventChannel error: $error");
          isConnected.value = false;
          // Fallback vers MethodChannel
          _setupMethodChannelFallback();
        },
        onDone: () {
          print("EventChannel done");
          isConnected.value = false;
        },
      );

      isConnected.value = true;
      print("✅ EventChannel connected successfully");

    } catch (e) {
      print("❌ Failed to connect EventChannel: $e");
      _setupMethodChannelFallback();
    }
  }

  void _setupMethodChannelFallback() {
    print("🔄 Using MethodChannel fallback");
    _methodChannel.setMethodCallHandler((call) async {
      if (call.method == "onUssdMessageReceived") {
        _onUssdMessageReceived(call.arguments.toString());
      }
      return null;
    });
  }

  void _onUssdMessageReceived(String message) {
    print("📨 USSD Message: $message");
    messages.add(message);
    lastMessage.value = message;

    // Traiter le message automatiquement
  //  _processUssdMessage(message);
    processUssdMessages(message);
  }

  addinfotransact(message){
    print('Tableau ajouté avec succèsss');
    print( idtransacts.value);
    print('Tableau ajouté avec succès');
    FirebaseFirestore.instance
        .collection('Transact')
        .doc(idtransacts.value)
        .update({
      'item': [message],
    })
        .then((_) {
      idtransacts.value = "";
      print('Tableau ajouté avec succès');
    })
        .catchError((error) {
      print('Erreur: $error');
    });
  }

  MessageType _detectMessageType(String lowerMsg) {
    // Priorité aux cas spéciaux
    if (lowerMsg.contains("non valide")) {
      return MessageType.invalidCode;
    }

    // Détection de demande de PIN
    if (lowerMsg.contains("pin") ||
        lowerMsg.contains("code secret") ||
        lowerMsg.contains("enter your pin")) {
      return MessageType.pinRequest;
    }

    // Détection de succès
    if (lowerMsg.contains("top-up")||lowerMsg.contains("you")) {
      return MessageType.success;
    }

    // Détection d'erreur
    if (lowerMsg.contains("failed") ||
        lowerMsg.contains("échec") ||
        lowerMsg.contains("system error") ||
        lowerMsg.contains("incorrect") ||
        lowerMsg.contains("unsuccessfully") ||
        lowerMsg.contains("insuffisant")) {
      return MessageType.error;
    }

    return MessageType.unknown;
  }

  void processUssdMessages(String message) {
    String lowerMsg = message.toLowerCase();
    print("d: $lowerMsg");
    // if(lowerMsg.contains("please")){
    //   addinfotransact(lowerMsg);
    //   if (statuts.value == 2||statuts.value == 1) {
    //     print('pas de place');
    //     print(idtransacts.value);
    //     updateValueInFirestore("Transact", idtransacts.value ?? "0", "status", "2");
    //
    //   }
    //   if (statuts.value==11 ||statuts.value == 9) {
    //     print('pas de place');
    //     print(idtransacts.value);
    //     updateValueInFirestore("Transact", idtransacts.value ?? "0", "status", "11");
    //   }
    //   SendEmail.sendMessagewithtelegram(message: "${lowerMsg} ce message concerne l id donc la transaction est : ${idtransacts.value}");
    // }



    MessageType type = _detectMessageType(lowerMsg);

    switch (type) {
      case MessageType.pinRequest:
        print("🔐 PIN requested - Auto sending PIN");
        _autoSendPin();
        break;

      case MessageType.success:
        print("✅ Transaction successful");
        print( idtransacts.value);
        print( statuts.value);

        if (statuts.value == 2||statuts.value == 1) {
          print('pas de place ${statuts.value}');
          print(idtransacts.value);
          updateValueInFirestore("Transact", idtransacts.value ?? "0", "status", "3");

        }
        if (statuts.value == 5) {
          print('pas de place ${statuts.value}');
          print(idtransacts.value);
          updateValueInFirestore("Transact", idtransacts.value ?? "0", "status", "7");
        }


        if (statuts.value==11 ||statuts.value == 9) {
          print('pas de place ${statuts.value}');
          print(idtransacts.value);
          updateValueInFirestore("Transact", idtransacts.value ?? "0", "status", "10");
        }
        addinfotransact(lowerMsg);
        Get.snackbar("Succès", message,
            snackPosition: SnackPosition.TOP,
            backgroundColor: Colors.green,
            colorText: Colors.white,
            animationDuration: const Duration(seconds: 6)
        );

        idtransacts.value = "";
        break;

      case MessageType.error:
        print("❌ Transaction failed");
        print( idtransacts.value);
        print( statuts.value);
        print( "commence ici ");
        updateValueInFirestore("Transact", idtransacts.value ?? "0", "status", "4");
        addinfotransact(lowerMsg);
        if (statuts.value == 2||statuts.value == 1) {
          print('pas de place ${statuts.value}');
          updateValueInFirestore("Transact", idtransacts.value ?? "0", "status", "4");
          print(idtransacts.value);
        }

        if (statuts.value == 5) {
          print('pas de place ${statuts.value}');
          print(idtransacts.value);
           updateValueInFirestore("Transact", idtransacts.value ?? "0", "status", "4");
        }


        if (statuts.value == 11||statuts.value == 9) {
          print('pas de place ${statuts.value}');
          print(idtransacts.value);
          updateValueInFirestore("Transact", idtransacts.value ?? "0", "status", "11");

        }
     //   updateValueInFirestore("Transact", idtransacts.value ?? "0", "status", "4");

        Get.snackbar("Erreur", message,
            snackPosition: SnackPosition.TOP,
            backgroundColor: Colors.red,
            colorText: Colors.white,
            animationDuration: const Duration(seconds: 6)
        );

        // idtransacts.value = "";
        break;

      case MessageType.invalidCode:
        print("❌ Problème de connexion");
        print(idtransacts.value);
        addinfotransact(lowerMsg);
        idtransacts.value = "";
        Get.snackbar("Problème de connexion ou code IHM non valide.", message,
            snackPosition: SnackPosition.TOP,
            backgroundColor: Colors.black,
            colorText: Colors.white,
            animationDuration: const Duration(seconds: 6)
        );
        break;

      case MessageType.unknown:
        print("ℹ️ Message non reconnu: $lowerMsg");
        break;
    }

    // Extraction du montant (commune à tous les cas)
    RegExp amountRegex = RegExp(r'(\d+)\s*FCFA', caseSensitive: false);
    if (amountRegex.hasMatch(message)) {
      String amount = amountRegex.firstMatch(message)!.group(1)!;
      print("💰 Amount: $amount FCFA");
    }

    // Extraction du numéro de téléphone (commune à tous les cas)
    RegExp phoneRegex = RegExp(r'(6|7)\d{8}');
    if (phoneRegex.hasMatch(message)) {
      String phone = phoneRegex.firstMatch(message)!.group(0)!;
      print("📞 Phone number: $phone");
    }
  }


  void _processUssdMessage(String message) {
    String lowerMsg = message.toLowerCase();
    print("lowerMsg");
    print(lowerMsg);
    print("lowerMsg");

    // Détection de demande de PIN
    if (lowerMsg.contains("pin") ||
        lowerMsg.contains("code secret") ||
        lowerMsg.contains("enter your pin")) {
      print("🔐 PIN requested - Auto sending PIN");
      _autoSendPin();
    }

    // Détection de succès
    if (lowerMsg.contains("top-up")
    //||
        // lowerMsg.contains("effectué") ||
        // lowerMsg.contains("recharge")
    ) {
      if (statuts.value == 2||statuts.value == 3) {
        print('pas de place ${statuts.value}');
        updateValueInFirestore("Transact", idtransacts.value??"0", "status", "3");


      } else if (statuts.value == 11||statuts.value == 10) {
        print('pas de place ${statuts.value}');
        updateValueInFirestore("Transact", idtransacts.value??"0", "status", "10");

      }
      addinfotransact(lowerMsg);

      print("✅ Transaction successful");
      print(statuts.value);
      print('statuts.value');
      Get.snackbar("Succès", message, snackPosition: SnackPosition.TOP,backgroundColor: Colors.green,colorText: Colors.white,animationDuration: Duration(seconds: 6));
    }

    // Détection d'erreur
    if (lowerMsg.contains("failed") ||
        lowerMsg.contains("échec") ||
        lowerMsg.contains("incorrect") ||
        lowerMsg.contains("unsuccessfully") ||
        lowerMsg.contains("insuffisant")) {
      print("❌ Transaction failed");
      if (statuts.value == 2) {
        print('pas de place ${statuts.value}');
        updateValueInFirestore("Transact", idtransacts.value??"0", "status", "4");

      }
      if (statuts.value == 5) {
        print('pas de place ${statuts.value}');
        updateValueInFirestore("Transact", idtransacts.value??"0", "status", "8");

      }
      if (statuts.value == 9) {
        print('pas de place ${statuts.value}');
        updateValueInFirestore("Transact", idtransacts.value??"0", "status", "11");

      }
      addinfotransact(lowerMsg);
      Get.snackbar("Erreur", message, snackPosition: SnackPosition.TOP,backgroundColor: Colors.red,colorText: Colors.white,animationDuration: Duration(seconds: 6));


    }

    if (
        lowerMsg.contains("non valide")) {
      print("❌ Problème de connexion");
      addinfotransact(lowerMsg);
      idtransacts.value = "";
      Get.snackbar("Problème de connexion ou code IHM non valide.", message, snackPosition: SnackPosition.TOP,backgroundColor: Colors.black,colorText: Colors.white,animationDuration: Duration(seconds: 6));
    }

    // Extraction du montant
    RegExp amountRegex = RegExp(r'(\d+)\s*FCFA', caseSensitive: false);
    if (amountRegex.hasMatch(message)) {
      String amount = amountRegex.firstMatch(message)!.group(1)!;
      print("💰 Amount: $amount FCFA");
    }

    // Extraction du numéro de téléphone
    RegExp phoneRegex = RegExp(r'(6|7)\d{8}');
    if (phoneRegex.hasMatch(message)) {
      String phone = phoneRegex.firstMatch(message)!.group(0)!;
      print("📞 Phone number: $phone");
    }
  }




  void _autoSendPin() {
    // Attendre 1 seconde avant d'envoyer le PIN
    Future.delayed(Duration(seconds: 1), () {
      sendUssdResponse("2006");
    });
  }

  Future<void> sendUssd({
    required String code,
    List<String> options = const [],
    int slotIndex = 0,
    int initialDelayMs = 3000,
    int optionDelayMs = 2500,
  }) async {
    try {
      print("📤 Sending USSD: $code");

      await _methodChannel.invokeMethod('multisessionUssd', {
        'ussdCode': code,
        'slotIndex': slotIndex,
        'options': options,
        'initialDelayMs': initialDelayMs,
        'optionDelayMs': optionDelayMs,
      });

      print("✅ USSD sent successfully");
    } catch (e) {
      print("❌ Error sending USSD: $e");
      Get.snackbar("Erreur", "Impossible d'envoyer la requête: $e");
    }
  }

  Future<void> sendUssdResponse(String response) async {
    try {
      print("📤 Sending USSD response: $response");

      await _methodChannel.invokeMethod('multisessionUssd', {
        'ussdCode': "",  // Code vide pour réponse
        'slotIndex': 0,
        'options': [response],
      });

      print("✅ Response sent successfully");
    } catch (e) {
      print("❌ Error sending response: $e");
    }
  }

  void clearMessages() {
    messages.clear();
  }

  @override
  void onClose() {
    _eventSubscription?.cancel();
    super.onClose();
  }
}