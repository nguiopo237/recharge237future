import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:get/get.dart';
import 'package:internet_connection_checker/internet_connection_checker.dart';
import 'package:projettest/main.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:projettest/service/sendmail/send_mail.dart';

import 'controlleur/widget_controlleur.dart';
import 'executeussd/natifplace.dart';
bool isRunning = false;
Future<void> updateValueInFirestore(String collectionName, String documentId,
    String fieldName, dynamic newValue) async

{
  try {
    // Récupérer une référence à la collection et au document
    DocumentReference docRef =
    FirebaseFirestore.instance.collection(collectionName).doc(documentId);

    // Mettre à jour la valeur
    await docRef.update({fieldName: newValue});

    print('Valeur mise à jour avec succès');
  } catch (e) {
    print('Erreur lors de la mise à jour de la valeur : $e');
  }
}

getsms() async {
  final permissionStatus = await Permission.sms.request();
  print(permissionStatus);
  final service = FlutterBackgroundService();
  easySmsReceiver.listenIncomingSms(
    onNewMessage: (message) {
      // do something
      print("voici le message recu ici ");
      print(message.body);
      print("voici le message recu ici ");
      SendEmail.sendMessagewithtelegram(message: message.body.toString());
    },
  );
}

Future<void> sendUssd(
    {String? number, String? amount, int statut = 1, documentid}) async
{
  String code = "";
  String codecredit = "*550*3*1#";
  String codecredits = "*825*3*3#";
  String codetrdsmckpost = "*550*2*${number}*${amount}#";
  String codetrpostckient = "*550*1*${number}*${amount}#";
  int simId = 0;
  if (statut == 1) {
    simId = 0;
    code = codetrpostckient;
  } else {
    simId = 1;
    code = codetrdsmckpost;
  }
  await Future.delayed(Duration(seconds: 5));
  print("Envoi de USSD: $code sur SIM $simId");
  // listenmessage(documentid: documentid,statut: statut);
  String? response = await UssdLaunchers.sendUssdRequest(
    ussdCode: code,
    subscriptionId: simId,
    documentid: documentid,
    statut: statut,
  );

  if (response != null) {
    print("Réponse initiale: $response");
  } else {
    print("pas de vision: $response");
  }
}


getdata(documentid, numerocam, amount, idtransact, type,context) async {
  print("started transact");
  print(type);
  print("started transact");
  await Future.delayed(Duration(seconds: 15));
  // updateValueInFirestore(
  //     "Transact", documentid, "status", type == "1" ? "2" : "10");
  bool result = await InternetConnectionChecker().hasConnection;
  if (result == true) {
    if (type == "1") {
      sendUssd(
          amount: amount,
          number: numerocam,
          statut: int.parse(type),
          documentid: documentid);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 18),
          content: Text(
            idtransact,
            style: TextStyle(color: Colors.white),
          )));
    }else{
      sendUssd(
          amount: amount,
          number: numerocam,
          statut: int.parse(type),
          documentid: documentid);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 18),
          content: Text(
            idtransact,
            style: TextStyle(color: Colors.white),
          )));
    }
    // await Future.delayed(Duration(seconds: 6));
  } else {
    // restartapp(documentid,numerocam,amount);
    print('No internet :( Reason:');
  }
}


check(context) async {
  // checkstate();
  // listenToAccessibilityEvents();

  // // scrollToIndex1();
  // if (!await UssdLauncher.isOverlayPermissionGranted()) {
  //   await UssdLauncher.openOverlaySettings();
  //   // await UssdLauncher.openOverlaySettings();
  // }

  FirebaseFirestore.instance
      .collection('Transact')
      .orderBy("heure", descending: true)
      .snapshots()
      .listen((QuerySnapshot snapshot) async {

    await Future.delayed(Duration(seconds: 5));
    await Future.forEach(snapshot.docChanges, (DocumentChange change) async {
      print("search");
      print("search");
      if (change.doc["status"] == "1" || change.doc["status"] == "9") {
        print("change");
        print( change.doc.id,);
        print("change");
        await Future.delayed(Duration(seconds: 5));
        getdata(
            change.doc.id,
            change.doc["numerocamtel"],
            change.doc["amount"],
            change.doc["idtransact"],
            change.doc["status"],
            context

        );
      }
    });

    // for (var change in snapshot.docChanges) {
    //   switch (change.type) {
    //     case DocumentChangeType.added:
    //
    //       print("✏️ Message ajout");
    //       // showSimpleNotification(message: data);
    //       if (change.doc["status"] == "1" || change.doc["status"] == "9") {
    //         print("change");
    //         print(change.doc.id);
    //         print(change.doc["status"]);
    //         print("start continuesdsd");
    //         await Future.delayed(Duration(seconds: 5));
    //         getdata(
    //             change.doc.id,
    //             change.doc["numerocamtel"],
    //             change.doc["amount"],
    //             change.doc["idtransact"],
    //             change.doc["status"]);
    //       }
    //
    //       // showSimpleNotification(message: '')
    //       // _onMessageAdded(change.doc);
    //       break;
    //     case DocumentChangeType.modified:
    //       print("✏️ Message modif");
    //       if (change.doc["status"] == "1" || change.doc["status"] == "9") {
    //         print("change");
    //         print(change.doc.id);
    //         print(change.doc["status"]);
    //         print("start continuesdsd");
    //         await Future.delayed(Duration(seconds: 5));
    //         getdata(
    //             change.doc.id,
    //             change.doc["numerocamtel"],
    //             change.doc["amount"],
    //             change.doc["idtransact"],
    //             change.doc["status"]);
    //       }
    //
    //       // _onMessageModified(change.doc);
    //       // showSimpleNotification(message: data);
    //       break;
    //     case DocumentChangeType.removed:
    //       print("❌ Message supprimé: ${change.doc.data()}");
    //       // _onMessageRemoved(change.doc);
    //       break;
    //   }
    // }
  });
}


getConnectivity(context) {
  c.subscription = Connectivity().onConnectivityChanged.listen(
        (List<ConnectivityResult> results) async {
      // Prendre le premier résultat de la liste
      print("results.length");
      print(results.length);
      print("results.length");
      if (results.isNotEmpty) {
        // final result = results.first;

        c.isDeviceConnected.value =
        await InternetConnectionChecker().hasConnection;
        if (!c.isDeviceConnected.value && c.isAlertSet.value == false) {
          // c.snackbar(message: "noconnection".tr,type: SnackbarType.warning);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: Colors.grey,
            duration: Duration(seconds: 60),
            content: Text("noconnection".tr),
          ));
        } else {
          // verifiedoc.loadData();
          check(context);
          ScaffoldMessenger.of(context)
              .hideCurrentSnackBar(reason: SnackBarClosedReason.swipe);
          print("connection on");
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: Colors.green,
            duration: Duration(seconds: 5),
            content: Text("Connexion retablie".tr),
          ));
        }
      }
    },
  );
}