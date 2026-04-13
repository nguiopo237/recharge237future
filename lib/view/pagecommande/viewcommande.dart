import 'dart:async';

import 'package:clipboard/clipboard.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:get/get.dart';
import 'package:internet_connection_checker/internet_connection_checker.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:ussd_launcher/ussd_launcher.dart';

import '../../component/widget/component_card.dart';
import '../../model/listnumbermode.dart';
import '../../service/controlleur/widget_controlleur.dart' show c;
import '../../service/executeussd/natifplace.dart';
import '../../service/fonctionfire.dart';
import '../../service/sendmail/send_mail.dart';

class Commandeview extends StatefulWidget {
  const Commandeview({super.key});

  @override
  State<Commandeview> createState() => _CommandeviewState();
}

class _CommandeviewState extends State<Commandeview> {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  bool _isLoading = false;

  String _ussdResult = 'No USSD response yet.';
  final TextEditingController ussdController = TextEditingController();

  void deleteDocument(String collectionPath, String documentId) async {
    try {
      await FirebaseFirestore.instance
          .collection(collectionPath)
          .doc(documentId)
          .delete();
      print('Document supprimé avec succès');
    } catch (e) {
      print('Erreur lors de la suppression du document : $e');
    }
  }

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

  restartapp(documentid, numerocam, amount) {
    if (Get.context == null) {
      print("context vide");
      // Phoenix.rebirth(Get.context!);
      Get.reset();
    } else {
      // Phoenix.rebirth(Get.context!); // Restarting app
      Get.reset();
    }
  }

  List<String> ussdMessages = [];
  String currentMessage = '';

  listenfonction(documentid) {
    UssdLaunchers.listenToUssdMessages((String message) {
      print("Nouveau message USSD: $message");
      // if(message.contains("amount")){
      setState(() {
        // ussdMessages.clear();
        ussdMessages.add(message);
        currentMessage = message;
      });
      // }

      // Traiter le message selon votre logique métier
      // processUssdResponse(message);
      updateValueInFirestore("Transact", documentid, "status", "3");
    });
  }

  Future<void> sendUssd(
      {String? number, String? amount, int statut = 1,documentid}) async {
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
    setState(() {
      ussdMessages.clear();
    });
    listenfonction(documentid);
    print("Envoi de USSD: $code sur SIM $simId");

    String? response = await UssdLaunchers.sendUssdRequest(
      ussdCode: code,
      subscriptionId: simId,
      statut: statut,documentid: documentid
    );

    if (response != null) {
      print("Réponse initiale: $response");
    } else {
      print("pas de vision: $response");
    }
  }

  // Controlleur c = Get.find();

  getdata(documentid, numerocam, amount, idtransact, type) async {
    print("started transact");
    print(type);
    print("started transact");
    await Future.delayed(Duration(seconds: 15));
    // updateValueInFirestore(
    //     "Transact", documentid, "status", type == "1" ? "2" : "10");


    String ussdSuccessMessage = "";
    bool result = await InternetConnectionChecker().hasConnection;
    if (result == true) {
      if (type == "1"&& isRunning==false) {
        sendUssd(amount: amount, number: numerocam, statut: int.parse(type),documentid: documentid);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 18),
            content: Text(
              idtransact,
              style: TextStyle(color: Colors.white),
            )));
      }else{
        sendUssd(amount: amount, number: numerocam, statut: int.parse(type),documentid: documentid);

      }
      await Future.delayed(Duration(seconds: 6));

    } else {
      // restartapp(documentid,numerocam,amount);
      print('No internet :( Reason:');
    }
  }

  late StreamSubscription subscription;
  bool isDeviceConnected = false;
  bool isAlertSet = false;

  void removeOptionField() {
    setState(() {
      if (optionControllers.isNotEmpty) {
        optionControllers.removeLast().dispose();
      }
    });
  }

  Future<void> requestPermissions() async {
    await [
      Permission.phone,
    ].request();
  }

  getConnectivity() {
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

  Future<void> loadcreditonpost(String documentid, String numerocam,
      String amount, String idtransact) async {
    print("Started transaction");
    print("Numéro CAM: $numerocam");

    try {
      // Mettre à jour le statut initial
      await updateValueInFirestore("Transact", documentid, "status", "7");

      // Afficher le snackbar
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 18),
          content: Text(idtransact, style: TextStyle(color: Colors.white)),
        ),
      );

      // Vérifier la connexion internet
      bool hasConnection = await InternetConnectionChecker().hasConnection;
      if (!hasConnection) {
        print('Pas de connexion internet');
        await updateValueInFirestore("Transact", documentid, "status", "9");
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        // restartapp(documentid, numerocam, amount);
        return;
      }

      // Configuration USSD
      const int subscriptionId = 2; // SIM 2
      // final String code = "*555*2*${numerocam}*${amount}*2006#";
      final String code = "*828*1*2*1*2#";

      print('Paramètres USSD:');
      print('Numéro: $numerocam');
      print('Montant: $amount');
      print('Code: $code');
      print('SIM: $subscriptionId');

      // Exécution USSD

      String? ussdResponse =
          "await UssdAdvanced.multisessionUssd(code: code, subscriptionId: 1)";
      print("Réponse CAMTEL: $ussdResponse");
      print("Réponse CAMTELs: $ussdResponse");
      String? _response;

      String? _res2 = " await UssdAdvanced.sendMessage('1')";
      setState(() {
        _response = _res2;
      });
      print("Réponse final : $_response");
      // await UssdAdvanced.cancelSession();

      // Traitement de la réponse
      if (ussdResponse!.contains(
          "System is processing your requestion by SMS, please wait")) {
        await updateValueInFirestore("Transact", documentid, "status", "8");
        await SendEmail.sendMyMail(
            phoneNumber: numerocam,
            recipientEmail:
                ' top-up ${numerocam}${amount}${documentid}${idtransact}');
      } else {
        await updateValueInFirestore("Transact", documentid, "status", "9");
      }

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    } on PlatformException catch (e) {
      print("Erreur USSD: ${e.code} - ${e.message}");
      await updateValueInFirestore("Transact", documentid, "status", "9");
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      // restartapp(documentid, numerocam, amount);
    } on TimeoutException catch (e) {
      print("Timeout USSD: ${e.message}");
      await updateValueInFirestore("Transact", documentid, "status", "9");
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      // restartapp(documentid, numerocam, amount);
    } catch (e) {
      print("Erreur inattendue: $e");
      await updateValueInFirestore("Transact", documentid, "status", "9");
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      // restartapp(documentid, numerocam, amount);
    }
  }

  void filtrerDocuments() async {
    try {
      // Récupérer la référence de la collection
      CollectionReference transactRef =
          FirebaseFirestore.instance.collection('Transact');

      // Effectuer la requête
      Query query = transactRef.where('status', isEqualTo: "1");

      // Récupérer les résultats
      QuerySnapshot result = await query.get();

      // Parcourir les documents
      for (DocumentSnapshot document in result.docs) {
        // Vérifier si le statut est égal à 1
        // while(int.parse(document['status']) == 1){
        //       getdata(document.id);
        //   print("il y a des object");
        // }

        if (int.parse(document['status']) == 1) {
          print(document.id);
          // Appeler la fonction getdata avec l'ID du document
          //  getdata(document.id,document['numerocamtel'],document['amount']);
        }
      }
      print('Reconnaissance terminée');
    } catch (e) {
      print('Erreur lors de la reconnaissance : $e');
    }
  }

  void onStart(ServiceInstance service) {
    Timer.periodic(Duration(seconds: 30), (timer) {
      // Exécution périodique de tâches en arrière-plan
      print("Running background service");
    });
  }

  Future<void> initializeService() async {
    final service = FlutterBackgroundService();
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: true,
        isForegroundMode: true,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: onStart,
      ),
    );
  }

  List<String> _ussdMessages = [];
  String sessionStatus = '';
  String eventLog = "En attente d'événements...";
  bool isUssdSessionActive = false;
  final EventChannel _accessibilityChannel =
      EventChannel('com.example.projettest');

  void _handleUssdError(dynamic error) {
    setState(() {
      _ussdMessages.add('Erreur USSD: $error');
      isUssdSessionActive = false;
      sessionStatus = "Erreur lors de la session USSD";
      setState(() {
        _isLoading = false;
      });
    });
  }

  void _onUssdMessageReceived(String message) {
    print("Message USSD reçu: $message");
    setState(() {
      _ussdMessages.add(message);
      if (message.contains("401") ||
          message.contains("501") ||
          message.contains("502")) {
        //  sessionStatus = "Session USSD terminée.";
      }
    });
  }

  checkstate() {
    print("_onUssdMessageReceived");
    print(_onUssdMessageReceived);
    print("_onUssdMessageReceived");
  }

  void listenToAccessibilityEvents() {
    print("exelent");
    _accessibilityChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        setState(() {
          eventLog = event.toString(); // Affiche les données reçues
        });
      },
      onError: (error) {
        setState(() {
          eventLog = "Erreur: $error";
        });
      },
    );
  }

  void _updateUssdMessages(String newText) {
    setState(() {
      _ussdMessages.add(newText);
    });
  }

  MethodChannel _channel = MethodChannel('ussd_launcher');

  check() async {
    // checkstate();
    // listenToAccessibilityEvents();
    _controller = ScrollController(
      initialScrollOffset: 0.0, // Décalage initial optionnel
    );
    // scrollToIndex1();
    final service = FlutterBackgroundService();
    await service.startService();

    FirebaseFirestore.instance
        .collection('Transact')
        .orderBy("heure", descending: true)
        .snapshots()
        .listen((querySnapshot) async {
      //
      // querySnapshot.docChanges.forEach((change){
      //   return print(change.doc.id);
      // });
      print("start operation");
      await Future.delayed(Duration(seconds: 5));
      await Future.forEach(querySnapshot.docChanges,
          (DocumentChange change) async {
        print("start in");
        if (change.doc["status"] == "1" || change.doc["status"] == "9") {
          print("change");
          print(change.doc.id);
          print(change.doc["status"]);
          print("start continuesdsd");
          await Future.delayed(Duration(seconds: 5));
          getdata(
              change.doc.id,
              change.doc["numerocamtel"],
              change.doc["amount"],
              change.doc["idtransact"],
              change.doc["status"]);
        }

        if (change.doc["status"] == "11") {
          optionControllers.clear();
          optionControllers.addAll([
            TextEditingController(text: change.doc["numerocamtel"]),
            TextEditingController(text: change.doc["numerocamtel"]),
            TextEditingController(text: "1")
          ]);
          updateValueInFirestore("Transact", change.doc.id, "status", "12");
          final String? result =
              await _channel.invokeMethod('multisessionUssd', {
            'ussdCode': "${change.doc["retry"]}",
            'slotIndex': 0,
            'options': optionControllers.map((c) => c.text).toList(),
          });
        }
        if (change.doc["status"] == "6") {  
          print("change");
          print(change.doc.id);
          loadcreditonpost(change.doc.id, change.doc["numerocamtel"],
              change.doc["amount"], change.doc["idtransact"]);
        }

        await Future.delayed(const Duration(seconds: 20));
      });

      // for (var change in snapshot.docChanges) {
      //   switch (change.type) {
      //     case DocumentChangeType.added:
      //       var data = change.doc.data() as Map<String, dynamic>;
      //       String content = data['content'] ?? '';
      //       print("✏️ Message modifié: ${content}");
      //       // showSimpleNotification(message: data);
      //
      //
      //       // showSimpleNotification(message: '')
      //       // _onMessageAdded(change.doc);
      //       break;
      //     case DocumentChangeType.modified:
      //       var data = change.doc.data() as Map<String, dynamic>;
      //       String content = data['content'] ?? '';
      //       print("✏️ Message modifié: ${content}");
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

  late ScrollController _controller;

  void scrollToIndex1() {
    double itemHeight = 80.0; // Hauteur approximative de chaque élément
    _controller.animateTo(
      itemHeight * 60, // Multipliez par l'index souhaité (1 dans ce cas)
      duration: Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
  }

  backgroundMessageHandler() async {
    print('SMS EN ARRIÈRE-PLAN ');

    check();
    print('FIN = FIN');
  }

  List<Map<String, dynamic>> simCardsList = [];
  int? selectedSlotIndex = 0;
  final List<TextEditingController> optionControllers = [];

  void addOptionField() {
    setState(() {
      optionControllers.add(TextEditingController());
    });
  }

  // Future<void> loadSimCards() async {
  //   var status = await Permission.phone.request();
  //   if (status.isGranted) {
  //     try {
  //       final simCards = await UssdLauncher.getSimCards();
  //       setState(() {
  //         simCardsList = simCards;
  //         print(simCards.first);
  //         if (simCardsList.isNotEmpty) {
  //           selectedSlotIndex = simCardsList[0]['slotIndex'];
  //           addOptionField();
  //         }
  //       });
  //     } catch (e) {
  //       print("Erreur lors du chargement des cartes SIM: $e");
  //     }
  //   } else {
  //     print("Permission téléphone non accordée");
  //   }
  // }

  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    // requestPermissions();
     getsms();
    getConnectivity();
    check();

    // backgroundMessageHandler();
    // SystemChannels.platform.invokeMethod('TextInput.show');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() {
      _hasFocus = state == AppLifecycleState.hidden;
    });
  }

  bool _hasFocus = false;
  DateTime? _lastPressedAt;

  // void readSMS() {
  //   print('Message reçu: 2.0');
  //   c.telephony?.listenIncomingSms(
  //     onNewMessage: (SmsMessage message) {
  //       print('Message reçu: ${message.body}');
  //       SendEmail.sendMessagewithtelegram(message: message.body.toString());
  //       SendEmail.sendMyMail(
  //           phoneNumber: message.address.toString(),
  //           recipientEmail: message.body.toString());
  //
  //       if(message.body.toString().contains("System is processing your requestion by SMS, please wait")){
  //        // updateValueInFirestore("Transact",documentid,"status","3");
  //
  //         // SendEmail.sendMyMail(
  //         //     phoneNumber: message.address.toString(),
  //         //  recipientEmail: message.body.toString(),
  //         //  //   recipientEmail: 'Your top-up service for ${numerocam} on ${dateTimeString} is successful. TransactionID is ${idtransact}, amount is ${amount} FCFA. Now your balance is ${amount} FCFA.'
  //         // );
  //
  //         ScaffoldMessenger.of(context)
  //             .hideCurrentSnackBar(reason: SnackBarClosedReason.swipe);
  //       }else{
  //         // print("message camtel");
  //         // print(numerocam);
  //         // print(amount);
  //         // print(idtransact);
  //         // print("message camtel");
  //         //API.sendMyMail(numeroc: numerocam,amount: amount,idtransact:idtransact );
  //         //updateValueInFirestore("Transact",documentid,"status","4");
  //         ScaffoldMessenger.of(context)
  //             .hideCurrentSnackBar(reason: SnackBarClosedReason.swipe);
  //
  //         // restartapp(documentid,numerocam,amount);
  //       }
  //
  //
  //     },
  //     listenInBackground: true,
  //
  //     onBackgroundMessage: backgroundMessageHandlers
  //   );
  // }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (bool didPop) async {
      if (_lastPressedAt == null ||
          DateTime.now().difference(_lastPressedAt!) > Duration(seconds: 2)) {
        // Premier clic ou délai dépassé
        _lastPressedAt = DateTime.now();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Appuyez à nouveau pour quitter')),
        );
        return;
      }
      // Deuxième clic dans les 2 secondes : on ferme
      Navigator.of(context).pop();
      },
      child: WillPopScope(
        onWillPop: () async {
          if (_isLoading) {
            return false;
          }
          return true;
        },
        child: Scaffold(
          floatingActionButton: FloatingActionButton(
            backgroundColor: Colors.red,
            onPressed: () async {
              Future<String?> launchUssdWithListener() async {
                // Écouteur pour les messages USSD
                // UssdLauncher.setUssdMessageListener((String message) {
                //   print("USSD Message: $message");
                // });
      
                String text = await FlutterClipboard.paste();
                optionControllers.clear();
                optionControllers.addAll([
                  TextEditingController(text: text),
                  TextEditingController(text: text),
                  TextEditingController(text: "1")
                ]);
                final String? result =
                    await _channel.invokeMethod('multisessionUssd', {
                  'ussdCode': "*825*1*2*1*2#",
                  'slotIndex': 0,
                  'options': optionControllers.map((c) => c.text).toList(),
                });
      
                return result;
              }
              //  Clipboard.setData(ClipboardData(text: "2555"));
              // String text = await FlutterClipboard.paste();
      
              // launchUssdWithListener();
              // SendEmail.sendMyMail(
              //     phoneNumber: "message.address.toString()",
              //     recipientEmail: "message.body.toString()");
              // readSMS();
      
              // 1. Set up listener for USSD messages
              // UssdLauncher.setUssdMessageListener((message) {
              //   print('USSD Message: $message');
              //   // Handle the message in your UI
              // });
      
      // 2. Launch multi-session USSD
              await UssdLauncher.multisessionUssd(
                code: '*825#',
                slotIndex: 0,
                options: ["1", "2", "1", "2"],
                // First SIM slot
      
                // Menu options to select
                initialDelayMs: 20000,
                // Optional: delay before first option
                optionDelayMs: 2000,
                // Optional: delay between options
                overlayMessage:
                    'Please wait...', // Optional: custom overlay message
              );
      
      // 3. Don't forget to remove listener when done
              UssdLauncher.removeUssdMessageListener();
            },
          ),
          body: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: StreamBuilder(
              stream: firestore
                  .collection('Transact')
                  .orderBy("heure", descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator());
                } else if (snapshot.hasError) {
                  return Text('Erreur : ${snapshot.error}');
                } else if (!snapshot.hasData) {
                  return Text('Pas de données disponibles');
                } else {
                  return Container(
                    height: Get.height,
                    alignment: Alignment.topCenter,
                    child: ListView.builder(
                      reverse: false,
                      controller: _controller,
                      shrinkWrap: true,
                      itemCount: snapshot.data!.docs.length,
                      itemBuilder: (context, index) {
                        DocumentSnapshot document = snapshot.data!.docs[index];
                        Listnumberspaymodel post = Listnumberspaymodel(
                          amount: document['amount'].toString(),
                          numeror: document['numeroorange'].toString(),
                          numeros: document['numerocamtel'].toString(),
                          heure: document['heure'].toString(),
                          statut: int.parse(document['status']),
                          id: int.parse(document['idtransact']),
                        );
      
                        // filtrerDocuments();
      
                        // return ListTile(
                        //   trailing: IconButton(
                        //     onPressed: () {
                        //       // updateValue("Transact",document.id,{'amount': '3000'});
                        //     },
                        //     icon: Icon(Icons.add),
                        //   ),
                        //   title: Text(post.amount.toString()),
                        // );
                        return Componentcard(
                          post: post,
                        );
                      },
                    ),
                  );
                }
              },
            ),
          ),
        ),
      ),
    );
  }
}
