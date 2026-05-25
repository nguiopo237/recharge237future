import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_phoenix/flutter_phoenix.dart';
import 'package:get/get.dart';
import 'package:internet_connection_checker/internet_connection_checker.dart';
import 'package:projettest/main.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:projettest/service/controlleur/ussdcontrolleur.dart';
import 'package:projettest/service/queuu.dart';
import 'package:projettest/service/sendmail/send_mail.dart';
import 'package:projettest/service/transactionservice.dart';

import 'controlleur/activity.dart';
import 'controlleur/appcycle_controlleur.dart';
import 'controlleur/widget_controlleur.dart';
import 'executeussd/natifplace.dart';

bool isRunning = false;
RxList<Map<String, dynamic>> codesim = <Map<String, dynamic>>[].obs;

Future<void> updateValueInFirestore(String collectionName, String documentId,
    String fieldName, dynamic newValue) async {
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
    {String? number,
    String? amount,
    int statut = 1,
    documentid,
    retry = ""}) async {
  String code = "";
  String codecredit = "*550*3*1#";
  String codecredits = "*825*3*3#";
  String codes = "${number}*${amount}#";
  String codetrdsmckpost = "*550*2*${number}*${amount}#";
  String codetrpostckient = "*550*1*${number}*${amount}#";
  int simId = 0;

  ussd.idtransacts.value = documentid;
  codesim.map((e) {
    if (statut == 1) {
      simId = 0;
      if (e.containsKey("codetrpostckient")) {
        code = "${e.values.single}${codes}";
        print("code a lance");
        print(code);
        print("code a lance");
      }
    }
    if (statut == 5) {
      simId = 0;
      code = "${retry}";
      print("code a lance");
      print(code);
      print("code a lance");
    }

    if (statut == 9) {
      simId = 1;
      if (e.containsKey("codetrdsmckpost")) {
        code = "${e.values.single}${codes}";
        print("code a lance");
        print(documentid);
        print("code a lance");
      }
    }
  }).toList();

  await Future.delayed(Duration(seconds: 5));
  print("Envoi de USSD: $code sur SIM $simId");

  // listenmessage(documentid: documentid,statut: statut);
  String? response = await UssdLaunchers.sendUssdRequest(
      ussdCode: code,
      subscriptionId: simId,
      documentid: documentid,
      statut: statut,
      number: statut == 5 ? number : null);

  if (response != null) {
    print("Réponse initiale: $response");
  } else {
    print("pas de vision: $response");
  }
}

getdata(documentid, numerocam, amount, idtransact, type, context, retry) async {
  print("started transact");
  print(type);
  print(ussd.idtransacts.value);
  print("started transact");
  await Future.delayed(
    Duration(seconds: 15),
    () {
      // ussd.idtransacts.value="";
      print("je viens de vider cela ");
    },
  );
  // updateValueInFirestore(
  //     "Transact", documentid, "status", type == "1" ? "2" : "10");
  bool result = await InternetConnectionChecker().hasConnection;
  if (result == true) {
    if (type == "1") {
      // if (ussd.idtransacts.value == "") {
      ussd.idtransacts.value = documentid;
      ussd.statuts.value = int.parse(type);
      print("ussd.idtransacts.value");
      print(ussd.idtransacts.value);
      print("ussd.idtransacts.value");
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
      // }
    } else {
      // if (ussd.idtransacts.value == "") {
      ussd.idtransacts.value = documentid;
      print("ussd.idtransacts.value");
      print(ussd.idtransacts.value);
      print("ussd.idtransacts.value");
      sendUssd(
          retry: retry,
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
      // }
    }
    // await Future.delayed(Duration(seconds: 6));
  } else {
    // restartapp(documentid,numerocam,amount);
    print('No internet :( Reason:');
  }
}

getcodefirebase() async {
  final lifecycleService = AppLifecycleService();
  await Get.putAsync(() async => lifecycleService);

  print("code value");
  FirebaseFirestore.instance
      .collection('codeadmin')
      .snapshots()
      .listen((QuerySnapshot snapshot) async {
    print("code value");
    print(snapshot.docs.length);

    codesim.value =
        snapshot.docs.map((doc) => doc.data() as Map<String, dynamic>).toList();
    print("item");
    print(codesim.length);
    // print(codesim.first.keys.single);
    // print(codesim.last['codetrpostckient']);
    print("item");
    await Future.forEach(snapshot.docChanges, (DocumentChange change) async {
      print("nombre");
      print(snapshot.docChanges.length);
      print(change.doc.data());
      print("code value");
    });
  });
  print("code value");
}

checkoperation(context) async {
  FirebaseFirestore.instance
      .collection('Transact')
      .orderBy("heure", descending: true)
      .snapshots()
      .listen((QuerySnapshot snapshot) async {
    await Future.delayed(Duration(seconds: 5));
    await Future.forEach(snapshot.docChanges, (DocumentChange change) async {
      print("recherche des elements");
      print("search");
      if (change.doc["status"] == "1" || change.doc["status"] == "9") {
        print("change");
        print(
          change.doc.id,
        );
        print("change");
        await Future.delayed(Duration(seconds: 5));
        getdata(
            change.doc.id,
            change.doc["numerocamtel"],
            change.doc["amount"],
            change.doc["idtransact"],
            change.doc["status"],
            context,
            change.doc["retry"]);
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

Map<String, bool> processedTransactions = {};
final TransactionProcess transactionProcess = TransactionProcess();

void checkoperations(context) async {
  print("essaye");
  print(TransactionProcess.queue.length);

  print("essaye");
  FirebaseFirestore.instance
      .collection('Transact')
      .orderBy("heure", descending: true)
      .snapshots()
      .listen((QuerySnapshot snapshot) async {
    // print("Inactif");
    // print(idle.isIdle.value);
    // print("Inactif");
    for (var change in snapshot.docChanges) {
      int count = snapshot.docs.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        print("verifier");
        print(data["idtransact"]);
        print(data["status"]);
        print("verifier");
        if (data['status'] == "1") {
          print(data["idtransact"]);
        }
        return data['status'] == "1";
      }).length;
      int counts = snapshot.docs.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        print("verifier");
        print(data["idtransact"]);
        print(data["status"]);
        print("verifier");
        if (data['status'] == "1") {
          print(data["idtransact"]);
        }
        return data['status'] == "9";
      }).length;

      ussd.operationlengh.value = count + counts;
      print("Total  donc le statut es  : $count");
      switch (change.type) {
        case DocumentChangeType.added:
          //  print("✏️ Nouvelle transaction ajoutée");

          if ((change.doc["status"] == "1" ||
                  change.doc["status"] == "5" ||
                  change.doc["status"] == "9") &&
              !processedTransactions.containsKey(change.doc.id)) {
            processedTransactions[change.doc.id] = true;

            // ✅ AU LIEU D'APPELER DIRECTEMENT getdata()
            // ✅ Ajouter à la file d'attente


            transactionProcess.addTransaction(
                change.doc.data() as Map<String, dynamic>,
                Get.context!,
                change.doc.id);
          }

          break;

        case DocumentChangeType.modified:
          // Même chose pour les modifications
          //  print("✏️ Nouvelle transaction modifie");

          print(change.doc["status"]);
          transactionProcess.removeTransaction(change.doc.id);
          if ((change.doc["status"] == "1" ||
                  change.doc["status"] == "5" ||
                  change.doc["status"] == "9") &&
              !processedTransactions.containsKey(change.doc.id)) {
            processedTransactions[change.doc.id] = true;

            // ✅ AU LIEU D'APPELER DIRECTEMENT getdata()
            // ✅ Ajouter à la file d'attente
            int count = snapshot.docs.where((doc) {
              final data = doc.data() as Map<String, dynamic>;

              if (data['status'] == "1") {
                print(data["idtransact"]);
              }
              return data['status'] == "1";
            }).length;
            ussd.operationlengh.value = count;
            print("Total  donc le statut es 1 : $count");

            transactionProcess.addTransaction(
                change.doc.data() as Map<String, dynamic>,
                Get.context!,
                change.doc.id);
          }
          // if (change.doc["status"] == "5" )  {
          //   processedTransactions[change.doc.id] = true;
          //
          //   // ✅ AU LIEU D'APPELER DIRECTEMENT getdata()
          //   // ✅ Ajouter à la file d'attente
          //   int counts = snapshot.docs.where((doc) {
          //     final data = doc.data() as Map<String, dynamic>;
          //
          //     if(data['status'] == "5"){
          //       print(data["idtransact"]);
          //     }
          //     return data['status'] == "5";
          //   }).length;
          //   ussd.operationforfaitlengh.value = counts;
          //   print("Total  donc le statut es 1 : $counts");
          //
          //   TransactionProcess().addTransaction(
          //       change.doc.data() as Map<String, dynamic>,
          //       Get.context!,
          //       change.doc.id);
          // }
          break;
        case DocumentChangeType.removed:
          print("✏️ Nouvelle transaction enlever");
          throw UnimplementedError();
      }
    }
  });
}

final Set<String> _processing = {};
final Set<String> _completed = {};


Future<void> processTransaction(DocumentSnapshot doc, BuildContext context) async {
  try {
    await getdata(
        doc.id,
        doc["numerocamtel"],
        doc["amount"],
        doc["idtransact"],
        doc["status"],
        context,
        doc["retry"]
    );
  } finally {
    // Même en cas d'erreur, retirer de processing
    _processing.remove(doc.id);
  }
}

void startMonitoring(BuildContext context) {
  FirebaseFirestore.instance
      .collection('Transact')
      .snapshots()
      .listen((snapshot) {
    for (var change in snapshot.docChanges) {
      final id = change.doc.id;
      final status = change.doc["status"]?.toString() ?? "";

      // Transaction terminée → nettoyer
      if (status == "2" || status == "10" || status == "99") {
        _processing.remove(id);
        _completed.add(id);
        // Nettoyer les anciennes après 1 heure
        Future.delayed(Duration(hours: 1), () => _completed.remove(id));
        continue;
      }

      // Transaction à traiter (uniquement si pas déjà en cours)
      if ((status == "1" || status == "5" || status == "9") &&
          !_processing.contains(id) &&
          !_completed.contains(id)) {
        print("start recharge");
        _processing.add(id);
        processTransaction(change.doc, context);
      }
    }
  });
}



// Option 2: Alternative avec un Set pour plus de clarté
Set<String> executedTransactions = {};

void checkoperationV2(BuildContext context) async {
  FirebaseFirestore.instance
      .collection('Transact')
      .orderBy("heure", descending: true)
      .snapshots()
      .listen((QuerySnapshot snapshot) async {
    for (var change in snapshot.docChanges) {
      final docId = change.doc.id;
      final status = change.doc["status"];

      // Vérifier si la transaction doit être traitée
      bool shouldProcess = (status == "1" || status == "9") &&
          !executedTransactions.contains(docId);

      if (shouldProcess) {
        executedTransactions.add(docId);
        print("✅ Traitement de la transaction: $docId (status: $status)");

        await Future.delayed(Duration(seconds: 5));
        getdata(docId, change.doc["numerocamtel"], change.doc["amount"],
            change.doc["idtransact"], status, context, change.doc["retry"]);
      }
    }
  });
}

// Option 3: Avec nettoyage automatique après un délai
class TransactionProcessor {
  final Map<String, DateTime> _processedTransactions = {};
  final Duration _cleanupDelay = Duration(hours: 1);

  void checkoperation(BuildContext context) async {
    FirebaseFirestore.instance
        .collection('Transact')
        .orderBy("heure", descending: true)
        .snapshots()
        .listen((QuerySnapshot snapshot) async {
      // Nettoyer les anciennes entrées
      _cleanupOldEntries();

      for (var change in snapshot.docChanges) {
        final docId = change.doc.id;
        final status = change.doc["status"];

        if ((status == "1" || status == "9") &&
            !_processedTransactions.containsKey(docId)) {
          _processedTransactions[docId] = DateTime.now();

          print("🎯 Traitement unique de: $docId (status: $status)");

          await Future.delayed(Duration(seconds: 5));
          getdata(docId, change.doc["numerocamtel"], change.doc["amount"],
              change.doc["idtransact"], status, context, change.doc["retry"]);
        }
      }
    });
  }

  void _cleanupOldEntries() {
    final now = DateTime.now();
    _processedTransactions.removeWhere((key, timestamp) {
      return now.difference(timestamp) > _cleanupDelay;
    });
  }
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
          ScaffoldMessenger.of(context == null ? Get.context : context)
              .showSnackBar(SnackBar(
            backgroundColor: Colors.grey,
            duration: Duration(seconds: 60),
            content: Text("noconnection".tr),
          ));
        } else {
          // verifiedoc.loadData();
        //  checkoperations(context);
          startMonitoring(Get.context!);
          //  checkoperation(context);
          ScaffoldMessenger.of(Get.context!)
              .hideCurrentSnackBar(reason: SnackBarClosedReason.swipe);
          print("connection on");
          ScaffoldMessenger.of(Get.context!).showSnackBar(SnackBar(
            backgroundColor: Colors.green,
            duration: Duration(seconds: 5),
            content: Text("Connexion retablie".tr),
          ));
        }
      }
    },
  );
}
