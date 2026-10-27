
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
import 'package:telephony/telephony.dart';
import 'package:ussd_flutter/ussd_service.dart';
import 'package:ussd_launcher/ussd_launcher.dart';

import '../../component/widget/component_card.dart';
import '../../model/listnumbermode.dart';
import '../../service/controlleur/widget_controlleur.dart' show c;
import '../../service/sendmail/send_mail.dart';
import '../../service/server/server_manager.dart';
import '../../service/server/transaction_claimer.dart';
import '../../service/ussd/mtn_ussd_manager.dart';
import '../../service/ussd/session_config.dart';


class Commandeview extends StatefulWidget {
  const Commandeview({super.key});

  @override
  State<Commandeview> createState() => _CommandeviewState();
}

class _CommandeviewState extends State<Commandeview> {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  bool _isLoading = false;

  // Config SIM/PIN chargée depuis Firestore au démarrage
  SessionConfig _simConfig = const SessionConfig(
    mtn:        SimConfig(slot: 0),
    orange:     SimConfig(slot: 1),
    camtelPre:  SimConfig(slot: 0),
    camtelPost: SimConfig(slot: 1),
  );
  final UssdService _ussdService = UssdService();
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

  Future<void> updateValueInFirestore(String collectionName, String documentId, String fieldName, dynamic newValue) async {
    try {
      // Récupérer une référence à la collection et au document
      DocumentReference docRef = FirebaseFirestore.instance.collection(collectionName).doc(documentId);

      // Mettre à jour la valeur
      await docRef.update({fieldName: newValue});

      print('Valeur mise à jour avec succès');
    } catch (e) {
      print('Erreur lors de la mise à jour de la valeur : $e');
    }
  }


  restartapp(documentid,numerocam,amount){
    if(Get.context==null){
      print("context vide");
      // Phoenix.rebirth(Get.context!);
      Get.reset();
    }else{
      // Phoenix.rebirth(Get.context!); // Restarting app
      Get.reset();
    }

  }

  // Controlleur c = Get.find();

  getdata(documentid, numerocam, amount, idtransact,type )async{
    print("started transact");
    print(type);
    print("started transact");
    await Future.delayed(Duration(seconds: 15));
    updateValueInFirestore("Transact",documentid,"status",type=="1"?"2":"10");
    if(type=="1"){
      updateValueInFirestore("Transact",documentid,"status","3");
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.blue,
        duration: Duration(seconds: 18),
        content: Text(idtransact,style: TextStyle(color: Colors.white),)));
    String ussdSuccessMessage = "";
    bool result = await InternetConnectionChecker().hasConnection;
    int subscriptionId = 1; // ID de la souscription SIM, généralement 1 pour la première carte SIM
    // String code = "*155#";
    String code = "*555*1*${numerocam}*${amount}*2006#";// Remplacez ceci par le code USSD que vous souhaitez exécuter
    //String code = "*155#"; // Remplacez ceci par le code USSD que vous souhaitez exécuter
    if(result == true) {
      print('connexion internet disponible');
      print(numerocam);
      print(amount);

      DateTime now = DateTime.now();

      // Créer un formatteur pour la date
      DateFormat dateFormatter = DateFormat('dd/MM/yy');
      String date = dateFormatter.format(now);

      // Créer un formatteur pour l'heure en 12 heures
      DateFormat timeFormatter = DateFormat('hh:mm a');
      String time = timeFormatter.format(now);

      // Combiner la date et l'heure
      String dateTimeString = '$date $time';

      print(dateTimeString);
      // await Future.delayed(Duration(seconds: 6));
      try {


        if(selectedSlotIndex==0){

          print("charger les element 0");
          optionControllers.clear();
          optionControllers.add(TextEditingController(text: _simConfig.camtelPre.pin));

        }else{

          if (ussdController.text.isEmpty) {
            //  ussdController.text = "*555*2*${numerocam}*10*2006#";
            ussdController.text = "*825*1*2*1*2#";
          }
        }
        print("charger optionControllers");
        print(optionControllers.length);
        print(optionControllers.first.text);
        print("charger les element");

        await  launchMultiSessionUssd(amount: amount,number: numerocam,post: type=="1"?false:true);
        print("message camtel");
        print(ussdSuccessMessage);
        print("message camtel");
        if(ussdSuccessMessage.contains("System is processing your requestion by SMS, please wait")){
          updateValueInFirestore("Transact",documentid,"status","3");

          SendEmail.sendMyMail(
              phoneNumber: numerocam,
              recipientEmail: 'Your top-up service for ${numerocam} on ${dateTimeString} is successful. TransactionID is ${idtransact}, amount is ${amount} FCFA. Now your balance is ${amount} FCFA.');

          ScaffoldMessenger.of(context)
              .hideCurrentSnackBar(reason: SnackBarClosedReason.swipe);
        }else{
          print("message camtel");
          print(numerocam);
          print(amount);
          print(idtransact);
          print("message camtel");
          //API.sendMyMail(numeroc: numerocam,amount: amount,idtransact:idtransact );
          updateValueInFirestore("Transact",documentid,"status","4");
          ScaffoldMessenger.of(context)
              .hideCurrentSnackBar(reason: SnackBarClosedReason.swipe);

          // restartapp(documentid,numerocam,amount);
        }


        print("Succès ! Message : $ussdSuccessMessage");
        print("Succès ! Message : $documentid");
      } on PlatformException catch (e) {
        updateValueInFirestore("Transact",documentid,"status","4");
        ScaffoldMessenger.of(context)
            .hideCurrentSnackBar(reason: SnackBarClosedReason.swipe);

        // restartapp(documentid,numerocam,amount);
        print("Erreur ! Code : ${e.code} - Message : ${e.message}");
      }

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


  getConnectivity() {

    c.subscription = Connectivity().onConnectivityChanged.listen(
          (List<ConnectivityResult> results) async {
        // Prendre le premier résultat de la liste
        print("results.length");
        print(results.length);
        print("results.length");
        if (results.isNotEmpty) {
          // final result = results.first;

          c.isDeviceConnected.value = await InternetConnectionChecker().hasConnection;
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

  Future<void> loadcreditonpost(String documentid, String numerocam, String amount, String idtransact) async {
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

      String? ussdResponse = "await UssdAdvanced.multisessionUssd(code: code, subscriptionId: 1)";
      print("Réponse CAMTEL: $ussdResponse");
      print("Réponse CAMTELs: $ussdResponse");
      String? _response;

      String? _res2 =" await UssdAdvanced.sendMessage('1')";
      setState(() {
        _response = _res2;
      });
      print("Réponse final : $_response");
      // await UssdAdvanced.cancelSession();



      // Traitement de la réponse
      if (ussdResponse!.contains("System is processing your requestion by SMS, please wait")) {
        await updateValueInFirestore("Transact", documentid, "status", "8");
        await   SendEmail.sendMyMail(
            phoneNumber: numerocam,
            recipientEmail: ' top-up ${numerocam}${amount}${documentid}${idtransact}');
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
      CollectionReference transactRef = FirebaseFirestore.instance.collection('Transact');

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
  StreamSubscription<UssdResponse>? ussdSubscription;
  String sessionStatus = '';
  String eventLog = "En attente d'événements...";
  bool isUssdSessionActive = false;
  final EventChannel _accessibilityChannel =
  EventChannel('com.example.projettest');

  void _handleUssdResponse(UssdResponse response) {
    print("session d ecoute et reponse");
    setState(() {
      _ussdMessages.add('${response.message}\n État de la sitation: ${response.state}');

      if (response.state == UssdSessionState.error ||
          response.state == UssdSessionState.error ||
          response.state == UssdSessionState.error) {
        isUssdSessionActive = false;
        sessionStatus = "Session USSD terminée (${response.state})";
        print("session terminé et verification ");
        setState(() {
          _isLoading = false;
        });
      }
      print("session de reponse et reponse  ${response.message} ");
    });
  }

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


  void _setupUssdResponseListener() {
    ussdSubscription = _ussdService.ussdResponseStream.listen(
          (UssdResponse response) {
        _handleUssdResponse(response);
      },
      onError: (error) {
        _handleUssdError(error);
      },
    );
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
    UssdLauncher.setUssdMessageListener(_onUssdMessageReceived);
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


  Future<void> _sendUssdCode(String ussdCode) async {
    print("_ussdResult");
    try {
      final response = await _ussdService.sendUssd(
        ussdCode,
      );
      setState(() {
        _ussdResult = 'Message: ${response.message}\nState: ${response.state}';
      });
      print("_ussdResult");
      print(_ussdResult);
      print("_ussdResult");
    } catch (e) {
      setState(() {
        _ussdResult = 'Error sending USSD: $e';
      });
    }
  }



  Future<void> launchMultiSessionUssd({amount,number,bool post = false}) async {
    print("ecoute du ussd kmille");
    print(post);
    print("ecoute du ussd kmille");
    setState(() {
      _isLoading = true;
      _ussdMessages.clear();
      sessionStatus = '';
    });

    try {


      // optionControllers.clear();
      List<String> options =
      optionControllers.map((controller) => controller.text).toList();
      // print("ici");

      _ussdService.ussdResponseStream.listen((response) {

        setState(() {
          _ussdResult =
          'Message: ${response.message}\nState: ${response.state}';
        });
      }, onError: (error) {
        setState(() {
          _ussdResult = 'Error: ${error.message}';
        });
      });


      //  _sendUssdCode(_ussdController.text);
     // _launchMultiSessionUssd();

      UssdLauncher.setUssdMessageListener((String message) {
        // Mettre à jour votre UI avec le message reçu
      });
      _sendUssdCode(ussdController.text);
      await UssdLauncher.multisessionUssd(
        // code: ussdController.text,
        code: "*550*${post == false ? "1" : "2"}*$number*$amount#",
        //code: "*825*1*2*1*2#",
        slotIndex: post == false ? 0 : 1,
        options: options,
      );
    } catch (e) {
      _updateUssdMessages('\nErreur : ${e.toString()}');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

   MethodChannel _channel = MethodChannel('ussd_launcher');

  check() async {
    _controller = ScrollController(initialScrollOffset: 0.0);

    final bgService = FlutterBackgroundService();
    await bgService.startService();

    final server  = ServerManager.instance;
    final claimer = TransactionClaimer.instance;
    final mtn     = MtnUssdManager.instance;

    FirebaseFirestore.instance
        .collection('Transact')
        .orderBy("heure", descending: true)
        .snapshots()
        .listen((querySnapshot) async {
      await Future.delayed(const Duration(seconds: 5));

      await Future.forEach(querySnapshot.docChanges,
          (DocumentChange change) async {
        final docId         = change.doc.id;
        final status        = change.doc["status"]?.toString() ?? '';
        final operateur     = change.doc["operateur_cible"]?.toString() ?? 'camtel_pre';
        final numero        = change.doc["numeroorange"]?.toString() ?? '';
        final numCible      = change.doc["numerocamtel"]?.toString() ?? '';
        final amount        = change.doc["amount"]?.toString() ?? '';
        final idTransact    = change.doc["idtransact"]?.toString() ?? '';
        final forfaitIndex  = change.doc["forfait_index"]?.toString() ?? '';

        // ─────────────────────────────────────────────────────────────
        // CAMTEL PRÉPAYÉ / RETRY  (comportement original inchangé)
        // ─────────────────────────────────────────────────────────────
        if ((status == "1" || status == "9") &&
            (operateur == 'camtel_pre' || operateur == '')) {
          if (!server.canHandle(numeroorange: numero, status: status)) return;
          final claimed = await claimer.claim(docId, server.deviceId);
          if (!claimed) return;

          await Future.delayed(const Duration(seconds: 5));
          getdata(docId, numCible, amount, idTransact, status);
        }

        // ─────────────────────────────────────────────────────────────
        // CAMTEL POSTPAYÉ  (comportement original inchangé)
        // ─────────────────────────────────────────────────────────────
        if (status == "6" && operateur == 'camtel_post') {
          if (!server.canHandle(numeroorange: numero, status: status)) return;
          final claimed = await claimer.claim(docId, server.deviceId);
          if (!claimed) return;

          loadcreditonpost(docId, numCible, amount, idTransact);
        }

        // ─────────────────────────────────────────────────────────────
        // RETRY USSD CAMTEL  (comportement original inchangé)
        // ─────────────────────────────────────────────────────────────
        if (status == "11") {
          if (!server.canHandle(numeroorange: numero, status: '1')) return;
          final claimed = await claimer.claim(docId, server.deviceId);
          if (!claimed) return;

          optionControllers.clear();
          optionControllers.addAll([
            TextEditingController(text: numCible),
            TextEditingController(text: numCible),
            TextEditingController(text: "1"),
          ]);
          updateValueInFirestore("Transact", docId, "status", "12");
          await _channel.invokeMethod('multisessionUssd', {
            'ussdCode': "${change.doc["retry"]}",
            'slotIndex': 0,
            'options': optionControllers.map((c) => c.text).toList(),
          });
        }

        // ─────────────────────────────────────────────────────────────
        // MTN AIRTIME  — Workflow A interactif
        // Statuts : 1 (en attente) → 20 (en cours) → 21 (ok) / 22 (ko)
        // ─────────────────────────────────────────────────────────────
        if (status == "1" && operateur == 'mtn_airtime') {
          if (!server.canHandle(numeroorange: numero, status: status)) return;
          final claimed = await claimer.claim(docId, server.deviceId);
          if (!claimed) return;

          debugPrint('[check] MTN Airtime → $numCible $amount FCFA');
          await mtn.rechargeAirtime(
            docId:        docId,
            amount:       amount,
            clientNumber: numCible,
            sim:          _simConfig.mtn,
          );
        }

        // ─────────────────────────────────────────────────────────────
        // MTN FORFAIT Phase 1 — Récupérer la liste des offres
        // Déclenché quand status == "1" et operateur == "mtn_forfait"
        // → après succès, status passe à "31" et `forfait_list` est rempli
        // ─────────────────────────────────────────────────────────────
        if (status == "1" && operateur == 'mtn_forfait') {
          if (!server.canHandle(numeroorange: numero, status: status)) return;
          final claimed = await claimer.claim(docId, server.deviceId);
          if (!claimed) return;

          debugPrint('[check] MTN Forfait Query → $numCible');
          await mtn.queryForfaitList(
            docId:        docId,
            clientNumber: numCible,
            sim:          _simConfig.mtn,
          );
          // Après ça, l'app client lit `forfait_list` et affiche les offres.
          // L'utilisateur sélectionne + paie → l'app met status à "1" et
          // operateur à "mtn_forfait_activate" avec forfait_index rempli.
        }

        // ─────────────────────────────────────────────────────────────
        // MTN FORFAIT Phase 2 — Activer l'offre choisie après paiement
        // Statuts : 1 → 33 (activation) → 34 (ok) / 35 (ko)
        // ─────────────────────────────────────────────────────────────
        if (status == "1" && operateur == 'mtn_forfait_activate') {
          if (forfaitIndex.isEmpty) {
            debugPrint('[check] Erreur : forfait_index manquant pour $docId');
            return;
          }
          if (!server.canHandle(numeroorange: numero, status: status)) return;
          final claimed = await claimer.claim(docId, server.deviceId);
          if (!claimed) return;

          debugPrint('[check] MTN Forfait Activate → $numCible, offre=$forfaitIndex');
          await mtn.activateForfait(
            docId:        docId,
            clientNumber: numCible,
            forfaitIndex: forfaitIndex,
            sim:          _simConfig.mtn,
          );
        }

        await Future.delayed(const Duration(seconds: 20));
      });
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


  Future<void> loadSimCards() async {
    var status = await Permission.phone.request();
    if (status.isGranted) {
      try {
        final simCards = await UssdLauncher.getSimCards();
        setState(() {
          simCardsList = simCards;
          print(simCards.first);
          if (simCardsList.isNotEmpty) {
            selectedSlotIndex = simCardsList[0]['slotIndex'];
            addOptionField();
          }
        });
      } catch (e) {
        print("Erreur lors du chargement des cartes SIM: $e");
      }
    } else {
      print("Permission téléphone non accordée");
    }
  }



  @override
  void initState() {
    super.initState();
    readSMS();
    loadSimCards();
    _setupUssdResponseListener();
    getConnectivity();
    // Initialise l'enregistrement serveur, charge les PIN, puis démarre l'écoute
    ServerManager.instance.initialize().then((_) async {
      _simConfig = await SessionConfig.load(ServerManager.instance.deviceId);
      check();
    });
  }

  @override
  void dispose() {
    ServerManager.instance.goOffline();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() {
      _hasFocus = state == AppLifecycleState.hidden;
    });
  }



bool _hasFocus =false;

  @pragma('vm:entry-point')
  static Future<void> backgroundMessageHandlers(SmsMessage message) async {
    print('📱 SMS reçu en arrière-plan: ${message.body}');
    // Tu peux stocker en local ou envoyer une notification
    SendEmail.sendMyMail(
        phoneNumber: message.address.toString(),
        recipientEmail: message.body.toString());
  }

  void readSMS() {
    print('Message reçu: 2.0');
    c.telephony?.listenIncomingSms(
      onNewMessage: (SmsMessage message) {
        print('Message reçu: ${message.body}');
        SendEmail.sendMessagewithtelegram(message: message.body.toString());
        SendEmail.sendMyMail(
            phoneNumber: message.address.toString(),
            recipientEmail: message.body.toString());

        if(message.body.toString().contains("System is processing your requestion by SMS, please wait")){
         // updateValueInFirestore("Transact",documentid,"status","3");

          // SendEmail.sendMyMail(
          //     phoneNumber: message.address.toString(),
          //  recipientEmail: message.body.toString(),
          //  //   recipientEmail: 'Your top-up service for ${numerocam} on ${dateTimeString} is successful. TransactionID is ${idtransact}, amount is ${amount} FCFA. Now your balance is ${amount} FCFA.'
          // );

          ScaffoldMessenger.of(context)
              .hideCurrentSnackBar(reason: SnackBarClosedReason.swipe);
        }else{
          // print("message camtel");
          // print(numerocam);
          // print(amount);
          // print(idtransact);
          // print("message camtel");
          //API.sendMyMail(numeroc: numerocam,amount: amount,idtransact:idtransact );
          //updateValueInFirestore("Transact",documentid,"status","4");
          ScaffoldMessenger.of(context)
              .hideCurrentSnackBar(reason: SnackBarClosedReason.swipe);

          // restartapp(documentid,numerocam,amount);
        }


      },
      listenInBackground: true,

      onBackgroundMessage: backgroundMessageHandlers
    );
  }



  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: ()async {
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
              optionControllers.addAll([TextEditingController(text: text),TextEditingController(text: text),TextEditingController(text: "1")]);
              final String? result = await _channel.invokeMethod('multisessionUssd', {
                'ussdCode': "*825*1*2*1*2#",
                'slotIndex': 0,
                'options': optionControllers.map((c) => c.text).toList(),
              });

              return result;
            }
            //  Clipboard.setData(ClipboardData(text: "2555"));
            // String text = await FlutterClipboard.paste();

             launchUssdWithListener();
            // SendEmail.sendMyMail(
            //     phoneNumber: "message.address.toString()",
            //     recipientEmail: "message.body.toString()");
            // readSMS();
            },),

        bottomNavigationBar: GestureDetector(
          onLongPress: () {
            FlutterClipboard.copy(ServerManager.instance.deviceId);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('ID copié dans le presse-papiers'),
              duration: Duration(seconds: 2),
            ));
          },
          child: Container(
            color: Colors.black87,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
            child: Text(
              'ID : ${ServerManager.instance.deviceId}',
              style: const TextStyle(color: Colors.white54, fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: StreamBuilder(
            stream: firestore.collection('Transact').orderBy("heure",descending: true).snapshots(),
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
                      return Componentcard(post: post,);
                    },
                  ),
                );
              }
            },
          ),
        ),
      ),
    );
  }
}