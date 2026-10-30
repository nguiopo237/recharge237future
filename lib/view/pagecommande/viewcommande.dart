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
import 'package:ussd_flutter/ussd_service.dart';
import 'package:ussd_launcher/ussd_launcher.dart';

import '../../component/widget/transaction_card.dart';
import '../../main.dart' show serverAuthUid;
import '../../service/controlleur/widget_controlleur.dart' show c;
import '../../service/sendmail/send_mail.dart';
import '../../service/report/report_service.dart';
import '../../service/report/sms_balance_parser.dart' show parseSmsBody;
import '../../service/server/order_filters.dart';
import '../../service/server/firestore_backoff.dart';
import '../../service/sms/sms_receiver.dart';
import '../../service/server/health_watch.dart';
import '../../service/server/network_watch.dart';
import '../../service/server/order_relaunch.dart';
import '../../service/server/status_labels.dart';
import '../../service/server/remote_command_handler.dart';
import '../../service/server/server_manager.dart';
import '../../service/server/transaction_claimer.dart';
import '../../service/ussd/mtn_ussd_manager.dart';
import '../../service/ussd/ussd_session.dart';
import '../config/sim_config_screen.dart';
import '../../service/ussd/session_config.dart';
import '../../service/ussd/sim_network.dart';
import '../../service/ussd/ussd_screens.dart'
    show isTransientScreen, isUnusableScreen;

class Commandeview extends StatefulWidget {
  const Commandeview({super.key});

  @override
  State<Commandeview> createState() => _CommandeviewState();
}

class _CommandeviewState extends State<Commandeview>
    with WidgetsBindingObserver {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  bool _isLoading = false;

  // Config SIM/PIN chargée depuis Firestore au démarrage
  SessionConfig _simConfig = const SessionConfig(
    mtn: SimConfig(slot: 0),
    orange: SimConfig(slot: 1),
    camtelPre: SimConfig(slot: 0),
    camtelPost: SimConfig(slot: 1),
  );
  final UssdService _ussdService = UssdService();
  String _ussdResult = 'No USSD response yet.';

  /// [28/10/2026] Dernier écran réellement renvoyé par l'opérateur pendant la
  /// session en cours. C'est LUI qui signe le message Telegram (avant, la
  /// signature pouvait être vide ou résumée).
  String _derniereReponseSysteme = '';
  final TextEditingController ussdController = TextEditingController();
  void deleteDocument(String collectionPath, String documentId) async {
    try {
      await FirebaseFirestore.instance
          .collection(collectionPath)
          .doc(documentId)
          .delete();
      debugPrint('Document supprimé avec succès');
    } catch (e) {
      debugPrint('Erreur lors de la suppression du document : $e');
    }
  }

  Future<void> updateValueInFirestore(String collectionName, String documentId,
      String fieldName, dynamic newValue) async {
    try {
      // Récupérer une référence à la collection et au document
      DocumentReference docRef =
          FirebaseFirestore.instance.collection(collectionName).doc(documentId);

      // Mettre à jour la valeur
      // [28/10/2026] Délai maximal : une écriture bloquée ne doit pas figer
      // la boucle de traitement des commandes.
      await docRef
          .update({fieldName: newValue}).timeout(const Duration(seconds: 12));

      debugPrint('Valeur mise à jour avec succès');
    } catch (e) {
      debugPrint('Erreur lors de la mise à jour de la valeur : $e');
    }
  }

  restartapp(documentid, numerocam, amount) {
    if (Get.context == null) {
      debugPrint("context vide");
      // Phoenix.rebirth(Get.context!);
      Get.reset();
    } else {
      // Phoenix.rebirth(Get.context!); // Restarting app
      Get.reset();
    }
  }

  // Controlleur c = Get.find();

  getdata(documentid, numerocam, amount, idtransact, type) async {
    debugPrint("started transact");
    debugPrint(type);
    debugPrint("started transact");
    // [28/10/2026] 15 s d'attente avant même de lancer l'USSD : réduit à 2 s,
    // le temps que la base enregistre le passage à "2".
    await Future.delayed(const Duration(seconds: 2));
    // [RESEAU 28/10/2026] Garde réseau AVANT de composer le code CAMTEL.
    // Sans elle, une SIM hors service laissait partir la session : CAMTEL ne
    // repondait pas (ou au bout de plusieurs minutes) et la commande restait
    // bloquee alors que le client avait paye. Ici on refuse tout de suite, en
    // ecrivant la vraie raison, et rien n'est compose.
    final SimNetworkCheck reseauCamtel = await SimNetworkGuard.check(
      type == "1" ? _simConfig.camtelPre.slot : _simConfig.camtelPost.slot,
      expected: 'camtel',
    );
    if (!reseauCamtel.ok) {
      // [RESEAU 28/10/2026] Commande GARDÉE : rien n'a été composé. On rend la
      // réclamation et on ne touche pas au statut, pour qu'elle reparte au
      // retour du réseau au lieu d'être annoncée en échec au client.
      debugPrint('[reseau] $documentid gardée : ${reseauCamtel.reason}');
      await TransactionClaimer.instance
          .release(documentid, ServerManager.instance.deviceId);
      await updateValueInFirestore("Transact", documentid, "failure_reason",
          '${reseauCamtel.reason} — commande gardée, elle repartira au retour du réseau.');
      return;
    }
    // [PRODUCTION 27/10/2026] "2" = en cours de traitement. Avant, la commande
    // passait à "3" (réussie) — ou "10" pour le post — AVANT même l'envoi du
    // USSD : le client voyait « réussi » alors que rien n'était encore livré.
    // Le statut final n'est plus écrit qu'après la réponse de l'opérateur.
    updateValueInFirestore("Transact", documentid, "status", "2");
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 18),
        content: Text(
          idtransact,
          style: const TextStyle(color: Colors.white),
        )));
    String ussdSuccessMessage = "";
    bool result = await InternetConnectionChecker().hasConnection;
    int subscriptionId =
        1; // ID de la souscription SIM, généralement 1 pour la première carte SIM
    // String code = "*155#";
    String code =
        "*555*1*$numerocam*$amount*2006#"; // Remplacez ceci par le code USSD que vous souhaitez exécuter
    //String code = "*155#"; // Remplacez ceci par le code USSD que vous souhaitez exécuter
    if (result == true) {
      debugPrint('connexion internet disponible');
      debugPrint(numerocam);
      debugPrint(amount);

      DateTime now = DateTime.now();

      // Créer un formatteur pour la date
      DateFormat dateFormatter = DateFormat('dd/MM/yy');
      String date = dateFormatter.format(now);

      // Créer un formatteur pour l'heure en 12 heures
      DateFormat timeFormatter = DateFormat('hh:mm a');
      String time = timeFormatter.format(now);

      // Combiner la date et l'heure
      String dateTimeString = '$date $time';

      debugPrint(dateTimeString);
      // await Future.delayed(Duration(seconds: 6));
      try {
        if (selectedSlotIndex == 0) {
          debugPrint("charger les element 0");
          optionControllers.clear();
          optionControllers
              .add(TextEditingController(text: _simConfig.camtelPre.pin));
        } else {
          if (ussdController.text.isEmpty) {
            //  ussdController.text = "*555*2*${numerocam}*10*2006#";
            ussdController.text = "*825*1*2*1*2#";
          }
        }
        debugPrint("charger optionControllers");
        debugPrint('${optionControllers.length}');
        debugPrint(optionControllers.first.text);
        debugPrint("charger les element");

        await launchMultiSessionUssd(
            amount: amount,
            number: numerocam,
            post: type == "1" ? false : true);
        // [PRODUCTION 27/10/2026] `ussdSuccessMessage` n'était jamais rempli :
        // toute recharge finissait en "4" (échec), même réussie. On lit les
        // réponses réellement reçues de l'opérateur (laissées le temps
        // d'arriver).
        await Future.delayed(const Duration(seconds: 5));
        ussdSuccessMessage = '${_ussdMessages.join('\n')}\n$_ussdResult';
        // Réponse finale lue : on referme la fenêtre de l'opérateur (une
        // fenêtre laissée ouverte bloque la commande suivante).
        await _closeUssdDialog();
        _notifyTelegram(
          operateur: 'Camtel Prépayé',
          simSlot: _simConfig.camtelPre.slot,
          clientNumber: numerocam,
          amount: amount,
          // Dernière réponse système reçue pendant la session CAMTEL.
          resultat: _derniereReponseSysteme.isNotEmpty
              ? _derniereReponseSysteme
              : _ussdMessages.join('\n'),
          succes: isCamtelTransferAccepted(ussdSuccessMessage),
        );
        debugPrint("message camtel");
        debugPrint(ussdSuccessMessage);
        debugPrint("message camtel");
        if (isCamtelTransferAccepted(ussdSuccessMessage)) {
          updateValueInFirestore(
              "Transact", documentid, "status", type == "1" ? "3" : "10");

          // [E-MAIL 29/10/2026] Plus d'e-mail à chaque recharge réussie :
          // Gmail bloque l'envoi au-delà de ~500 e-mails/jour. Le bilan
          // quotidien récapitule les ventes.

          ScaffoldMessenger.of(context)
              .hideCurrentSnackBar(reason: SnackBarClosedReason.swipe);
        } else {
          debugPrint("message camtel");
          debugPrint(numerocam);
          debugPrint(amount);
          debugPrint(idtransact);
          debugPrint("message camtel");
          //API.sendMyMail(numeroc: numerocam,amount: amount,idtransact:idtransact );
          final String reponse = ussdSuccessMessage.trim();
          await FirebaseFirestore.instance
              .collection("Transact")
              .doc(documentid)
              .update({
            "status": "4",
            "failure_reason": reponse.isEmpty
                ? "Aucune réponse de l'opérateur CAMTEL"
                : (reponse.length > 300 ? reponse.substring(0, 300) : reponse),
          });
          ScaffoldMessenger.of(context)
              .hideCurrentSnackBar(reason: SnackBarClosedReason.swipe);

          // restartapp(documentid,numerocam,amount);
        }

        debugPrint("Succès ! Message : $ussdSuccessMessage");
        debugPrint("Succès ! Message : $documentid");
      } on PlatformException catch (e) {
        updateValueInFirestore("Transact", documentid, "status", "4");
        ScaffoldMessenger.of(context)
            .hideCurrentSnackBar(reason: SnackBarClosedReason.swipe);

        // restartapp(documentid,numerocam,amount);
        debugPrint("Erreur ! Code : ${e.code} - Message : ${e.message}");
      }
    } else {
      // restartapp(documentid,numerocam,amount);
      debugPrint('No internet :( Reason:');
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
        debugPrint("results.length");
        debugPrint('${results.length}');
        debugPrint("results.length");
        if (results.isNotEmpty) {
          // final result = results.first;

          c.isDeviceConnected.value =
              await InternetConnectionChecker().hasConnection;
          if (!c.isDeviceConnected.value && c.isAlertSet.value == false) {
            // c.snackbar(message: "noconnection".tr,type: SnackbarType.warning);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              backgroundColor: Colors.grey,
              duration: const Duration(seconds: 60),
              content: Text("noconnection".tr),
            ));
          } else {
            // verifiedoc.loadData();
            ScaffoldMessenger.of(context)
                .hideCurrentSnackBar(reason: SnackBarClosedReason.swipe);
            debugPrint("connection on");
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 5),
              content: Text("Connexion retablie".tr),
            ));
          }
        }
      },
    );
  }

  Future<void> loadcreditonpost(String documentid, String numerocam,
      String amount, String idtransact) async {
    debugPrint("Started transaction");
    debugPrint("Numéro CAM: $numerocam");

    // [RESEAU 28/10/2026] Meme garde que pour la prepayee, sur l'emplacement
    // de la SIM postpayee : aucun code n'est compose sans reseau.
    final SimNetworkCheck reseauPost = await SimNetworkGuard.check(
      _simConfig.camtelPost.slot,
      expected: 'camtel',
    );
    if (!reseauPost.ok) {
      // [RESEAU 28/10/2026] Même règle que la prépayée : on garde.
      debugPrint('[reseau] $documentid (post) gardée : ${reseauPost.reason}');
      await TransactionClaimer.instance
          .release(documentid, ServerManager.instance.deviceId);
      await updateValueInFirestore("Transact", documentid, "failure_reason",
          '${reseauPost.reason} — commande gardée, elle repartira au retour du réseau.');
      return;
    }

    try {
      // Mettre à jour le statut initial
      await updateValueInFirestore("Transact", documentid, "status", "7");

      // Afficher le snackbar
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.blue,
          duration: const Duration(seconds: 18),
          content: Text(idtransact, style: const TextStyle(color: Colors.white)),
        ),
      );

      // Vérifier la connexion internet
      bool hasConnection = await InternetConnectionChecker().hasConnection;
      if (!hasConnection) {
        debugPrint('Pas de connexion internet');
        await updateValueInFirestore("Transact", documentid, "status", "9");
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        // restartapp(documentid, numerocam, amount);
        return;
      }

      // Configuration USSD
      const int subscriptionId = 2; // SIM 2
      // final String code = "*555*2*${numerocam}*${amount}*2006#";
      const String code = "*828*1*2*1*2#";

      debugPrint('Paramètres USSD:');
      debugPrint('Numéro: $numerocam');
      debugPrint('Montant: $amount');
      debugPrint('Code: $code');
      debugPrint('SIM: $subscriptionId');

      // Exécution USSD

      String? ussdResponse =
          "await UssdAdvanced.multisessionUssd(code: code, subscriptionId: 1)";
      debugPrint("Réponse CAMTEL: $ussdResponse");
      debugPrint("Réponse CAMTELs: $ussdResponse");
      String? response;

      String? res2 = " await UssdAdvanced.sendMessage('1')";
      setState(() {
        response = res2;
      });
      debugPrint("Réponse final : $response");
      // await UssdAdvanced.cancelSession();

      // Traitement de la réponse
      if (ussdResponse.contains(
          "System is processing your requestion by SMS, please wait")) {
        await updateValueInFirestore("Transact", documentid, "status", "8");
        await SendEmail.sendMyMail(
            phoneNumber: numerocam,
            recipientEmail:
                ' top-up $numerocam$amount$documentid$idtransact');
      } else {
        await updateValueInFirestore("Transact", documentid, "status", "9");
      }
      _notifyTelegram(
        operateur: 'Camtel Postpayé',
        simSlot: _simConfig.camtelPost.slot,
        clientNumber: numerocam,
        amount: amount,
        resultat: ussdResponse,
      );

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    } on PlatformException catch (e) {
      debugPrint("Erreur USSD: ${e.code} - ${e.message}");
      await updateValueInFirestore("Transact", documentid, "status", "9");
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      // restartapp(documentid, numerocam, amount);
    } on TimeoutException catch (e) {
      debugPrint("Timeout USSD: ${e.message}");
      await updateValueInFirestore("Transact", documentid, "status", "9");
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      // restartapp(documentid, numerocam, amount);
    } catch (e) {
      debugPrint("Erreur inattendue: $e");
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
        //   debugPrint("il y a des object");
        // }

        if (int.parse(document['status']) == 1) {
          debugPrint(document.id);
          // Appeler la fonction getdata avec l'ID du document
          //  getdata(document.id,document['numerocamtel'],document['amount']);
        }
      }
      debugPrint('Reconnaissance terminée');
    } catch (e) {
      debugPrint('Erreur lors de la reconnaissance : $e');
    }
  }

  void onStart(ServiceInstance service) {
    // [FLUIDITE 30/10/2026] Ce timer ne faisait qu'imprimer toutes les 30 s
    // et n'était JAMAIS annulé : chaque (re)démarrage du service en laissait
    // un de plus, à vie, pour rien. Il n'y avait aucune tâche à exécuter ici —
    // le vrai travail (ServerManager, écoute des commandes) est déclenché par
    // initState, qui vit dans le même isolate.
    debugPrint('[Background] service demarre');
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

  final List<String> _ussdMessages = [];
  StreamSubscription<UssdResponse>? ussdSubscription;

  /// [FLUIDITE 30/10/2026] Abonnement de la session USSD en cours.
  ///
  /// `launchMultiSessionUssd` en créait un NOUVEAU à chaque commande et
  /// n'annulait jamais le précédent : chaque recharge laissait derrière elle
  /// un écouteur en vie, tous appelant `setState`. Après quelques commandes,
  /// une seule réponse de l'opérateur déclenchait une cascade de rebuilds de
  /// l'écran entier — c'est la cause directe des gels constatés. Un seul
  /// abonnement, réutilisé, fermé à la destruction du widget.
  StreamSubscription<UssdResponse>? _ussdSessionSub;
  String sessionStatus = '';
  String eventLog = "En attente d'événements...";
  bool isUssdSessionActive = false;
  final EventChannel _accessibilityChannel =
      EventChannel('com.example.projettest');

  void _handleUssdResponse(UssdResponse response) {
    debugPrint("session d ecoute et reponse");
    setState(() {
      _ussdMessages
          .add('${response.message}\n État de la sitation: ${response.state}');

      if (response.state == UssdSessionState.error ||
          response.state == UssdSessionState.error ||
          response.state == UssdSessionState.error) {
        isUssdSessionActive = false;
        sessionStatus = "Session USSD terminée (${response.state})";
        debugPrint("session terminé et verification ");
        // [FLUIDITE 30/10/2026] Un seul setState : le setState imbriqué
        // reconstruisait l'écran DEUX fois pour la même event.
        _isLoading = false;
      }
      debugPrint("session de reponse et reponse  ${response.message} ");
    });
  }

  void _handleUssdError(dynamic error) {
    setState(() {
      _ussdMessages.add('Erreur USSD: $error');
      isUssdSessionActive = false;
      sessionStatus = "Erreur lors de la session USSD";
      // [FLUIDITE 30/10/2026] Idem : un seul setState, pas deux.
      _isLoading = false;
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
    debugPrint("Message USSD reçu: $message");
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
    debugPrint("_onUssdMessageReceived");
    debugPrint('$_onUssdMessageReceived');
    debugPrint("_onUssdMessageReceived");
  }

  void listenToAccessibilityEvents() {
    debugPrint("exelent");
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

  /// Envoie le résultat d'une opération USSD sur Telegram,
  /// signé par les coordonnées du téléphone et de la SIM utilisée.
  Future<void> _notifyTelegram({
    required String operateur,
    required int simSlot,
    required String clientNumber,
    required String amount,
    required String resultat,
    bool succes = false,
  }) async {
    // [TELEGRAM 29/10/2026] Une livraison réussie n'envoie plus de message :
    // à 10 000 commandes/jour, c'était 30 000 messages (3 destinataires).
    // Elle figure dans le bilan quotidien ; Telegram ne sert plus qu'aux
    // échecs et aux doutes, ceux qui demandent une action de l'admin.
    if (succes) {
      debugPrint(
          '[Telegram] $operateur $clientNumber $amount F : livré — pas de message');
      return;
    }
    final deviceId = ServerManager.instance.deviceId;
    // Signature = dernière réponse système de l'opération. Si l'appelant n'en
    // fournit pas, on prend le dernier écran capté pendant la session, puis un
    // texte explicite — jamais une signature vide.
    final String signature = resultat.trim().isNotEmpty
        ? resultat.trim()
        : (_derniereReponseSysteme.trim().isNotEmpty
            ? _derniereReponseSysteme.trim()
            : "Aucune réponse de l'opérateur");
    final message = 'Recharge237 — opération USSD\n'
        'Téléphone : $deviceId\n'
        'SIM       : slot ${simSlot + 1} ($operateur)\n'
        'Client    : $clientNumber\n'
        'Montant   : $amount FCFA\n'
        '─────────────────────\n'
        'Réponse opérateur :\n'
        '$signature\n'
        '─────────────────────\n'
        'Une seule tentative — relancer depuis l\'admin si nécessaire.';
    await SendEmail.sendMessagewithtelegram(message: message);
  }

  Future<void> _sendUssdCode(String ussdCode) async {
    debugPrint("_ussdResult");
    try {
      final response = await _ussdService.sendUssd(
        ussdCode,
      );
      setState(() {
        _ussdResult = 'Message: ${response.message}\nState: ${response.state}';
      });
      debugPrint("_ussdResult");
      debugPrint(_ussdResult);
      debugPrint("_ussdResult");
    } catch (e) {
      setState(() {
        _ussdResult = 'Error sending USSD: $e';
      });
    }
  }

  /// [28/10/2026] Même règle que MTN, appliquée aux autres opérateurs : une
  /// fenêtre USSD laissée ouverte (écran vide, session expirée) ne doit jamais
  /// rester par-dessus l'app — elle bloque la commande suivante. On appuie sur
  /// « Annuler », exactement comme un humain.
  Timer? _surEcranVide;
  static const Duration _delaiEcranVide = Duration(seconds: 12);

  /// Vrai dès qu'un vrai écran de l'opérateur a été lu : la session est lancée,
  /// on ne la coupe plus (une coupure après l'envoi du PIN perdrait la
  /// confirmation d'un transfert peut-être déjà effectué).
  bool _ecranUtilisableVu = false;

  /// Relance manuelle d'une commande : une seule nouvelle tentative, puis
  /// rapport habituel. `true` = relance acceptée.
  Future<bool> _relancerCommande(
      String docId, Map<String, dynamic> data) async {
    final String? status = await OrderRelaunch.request(
      docId: docId,
      data: data,
      deviceId: ServerManager.instance.deviceId,
    );
    return status != null;
  }

  Future<bool> _closeUssdDialog() async {
    try {
      final bool closed =
          await const MethodChannel('r237/ussd').invokeMethod<bool>('cancel') ??
              false;
      if (closed) debugPrint('[USSD] Fenêtre fermée (Annuler)');
      return closed;
    } catch (_) {
      return false;
    }
  }

  /// Si l'écran reçu est vide de contenu (titre seul : téléphone verrouillé,
  /// écran éteint) et que l'opérateur n'envoie plus rien, on ferme.
  ///
  /// Uniquement à l'ouverture : si rien n'est encore affiché, aucune réponse
  /// n'a pu partir, donc fermer ne peut rien annuler d'utile.
  void _watchEmptyScreen(String message) {
    if (_ecranUtilisableVu) return;
    if (isTransientScreen(message)) return;
    _surEcranVide?.cancel();
    _surEcranVide = null;
    if (!isUnusableScreen(message)) {
      _ecranUtilisableVu = true;
      return;
    }
    _surEcranVide = Timer(_delaiEcranVide, () async {
      final bool closed = await _closeUssdDialog();
      _updateUssdMessages(
          '\n[fenêtre USSD ${closed ? "fermée (Annuler)" : "vide"} : écran '
          'sans contenu depuis ${_delaiEcranVide.inSeconds} s]');
    });
  }

  Future<void> launchMultiSessionUssd(
      {amount, number, bool post = false}) async {
    debugPrint("ecoute du ussd kmille");
    debugPrint('$post');
    debugPrint("ecoute du ussd kmille");
    setState(() {
      _isLoading = true;
      _ussdMessages.clear();
      _ussdResult =
          ''; // [PRODUCTION 27/10/2026] pas de réponse d'une session précédente
      _derniereReponseSysteme = '';
      sessionStatus = '';
    });
    _ecranUtilisableVu = false;
    _surEcranVide?.cancel();
    _surEcranVide = null;

    try {
      // optionControllers.clear();
      List<String> options =
          optionControllers.map((controller) => controller.text).toList();
      // debugPrint("ici");

      // [FLUIDITE 30/10/2026] Un seul abonnement par session, l'ancien fermé
      // avant d'en ouvrir un autre : sinon chaque commande en laissait un de
      // plus, tous actifs, tous à appeler setState (voir [_ussdSessionSub]).
      await _ussdSessionSub?.cancel();
      _ussdSessionSub = _ussdService.ussdResponseStream.listen((response) {
        if (!mounted) return;
        setState(() {
          _ussdResult =
              'Message: ${response.message}\nState: ${response.state}';
        });
      }, onError: (error) {
        if (!mounted) return;
        setState(() {
          _ussdResult = 'Error: ${error.message}';
        });
      });

      //  _sendUssdCode(_ussdController.text);
      // _launchMultiSessionUssd();

      UssdLauncher.setUssdMessageListener((String message) {
        final String m = message.trim();
        if (m.isEmpty) return;
        _derniereReponseSysteme = m;
        _updateUssdMessages(m);
        _watchEmptyScreen(m);
      });
      _sendUssdCode(ussdController.text);
      // Aucune fenêtre d'une session précédente ne doit rester ouverte.
      await _closeUssdDialog();
      await UssdLauncher.multisessionUssd(
        // code: ussdController.text,
        code: "*550*${post == false ? "1" : "2"}*$number*$amount#",
        //code: "*825*1*2*1*2#",
        // [PRODUCTION 27/10/2026] Slot lu dans servers/{deviceId}
        // (simCamtelPre / simCamtelPost), défaut 0 / 1 comme avant.
        slotIndex: post == false
            ? _simConfig.camtelPre.slot
            : _simConfig.camtelPost.slot,
        options: options,
      );
    } catch (e) {
      _updateUssdMessages('\nErreur : ${e.toString()}');
    } finally {
      _surEcranVide?.cancel();
      _surEcranVide = null;
      setState(() {
        _isLoading = false;
      });
    }
  }

  final MethodChannel _channel = const MethodChannel('ussd_launcher');

  /// Vrai tant que l'écoute des commandes est active.
  ///
  /// [ECOUTE 28/10/2026] Un abonnement Firestore qui reçoit une erreur
  /// (droits révoqués, jeton expiré, réseau) meurt DÉFINITIVEMENT : le serveur
  /// continuait de tourner, affichait « en ligne », et ne voyait plus aucune
  /// commande. Constaté en vrai après une réinstallation : le compte anonyme
  /// du téléphone avait changé d'UID, n'était plus admin, et l'écoute s'est
  /// arrêtée sans un mot. On se réabonne maintenant tout seul.
  bool _ecouteActive = false;

  /// [QUOTA 29/10/2026] Le délai avant de retenter l'écoute n'est plus fixe
  /// (15 s) : il suit le backoff partagé (5 s, 10 s, 20 s… max 5 min). Une
  /// seule alerte Telegram par panne, et une au retour.
  bool _alerteEcouteEnvoyee = false;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _ecouteCommandes;

  /// [ROUTAGE 29/10/2026] Familles de commandes écoutées (null = toutes).
  List<OrderRoute>? _routesEcoutees;

  /// Vrai si la requête filtrée a été refusée : on reste sur l'écoute complète.
  bool _ecouteComplete = false;

  Query<Map<String, dynamic>> _requeteCommandes(List<OrderRoute>? routes) {
    final CollectionReference<Map<String, dynamic>> col =
        FirebaseFirestore.instance.collection('Transact');
    if (routes == null) {
      return col.where('status', whereIn: kActionableStatuses);
    }
    Filter filtreRoute(OrderRoute r) {
      final Filter statut = r.statuses.length == 1
          ? Filter('status', isEqualTo: r.statuses.first)
          : Filter('status', whereIn: r.statuses);
      final String? op = r.operateur;
      return op == null
          ? statut
          : Filter.and(statut, Filter('operateur_cible', isEqualTo: op));
    }

    final List<Filter> f = routes.map(filtreRoute).toList();
    if (f.length == 1) return col.where(f.first);
    Filter ou = Filter.or(f[0], f[1]);
    for (int i = 2; i < f.length; i++) {
      ou = Filter.or(ou, f[i]);
    }
    return col.where(ou);
  }

  check() async {
    final bgService = FlutterBackgroundService();
    await bgService.startService();

    // [RESEAU 28/10/2026] Dès qu'une SIM redevient utilisable, la file de
    // reprise rejoue les commandes gardées pendant la coupure.
    NetworkWatch.instance.onNetworkHealthy = _drainPending;

    // [PRODUCTION 27/10/2026] On n'écoute plus TOUTE la collection (des
    // milliers de documents en production) : seulement les statuts qui
    // déclenchent une action du serveur.
    // [QUOTA 29/10/2026] Cette écoute est GARDÉE en temps réel, c'est voulu :
    // une requête filtrée sur les seuls statuts à traiter ne coûte une
    // lecture que lorsqu'une commande change. Un sondage toutes les 30 s
    // coûterait au minimum 2 880 lectures par jour, même sans aucune
    // commande, et ajouterait jusqu'à 30 s d'attente au client.
    await _ecouteCommandes?.cancel();
    // [ROUTAGE 29/10/2026] Seulement les commandes des opérateurs servis par
    // CE téléphone (cf. routesForHandles). Repli sur l'écoute complète si la
    // requête filtrée est refusée par la base (index manquant…).
    final List<OrderRoute>? routes = _ecouteComplete
        ? null
        : routesForHandles(ServerManager.instance.handles);
    _routesEcoutees = routes;
    // [CONFIG SIM 29/10/2026] Aucune SIM déclarée : on n'écoute rien plutôt
    // que de prendre des commandes qu'on ne peut pas livrer.
    if (routes != null && routes.isEmpty) {
      debugPrint('[check] SIM non configurées — aucune commande écoutée');
      if (mounted) setState(() {});
      return;
    }
    debugPrint(
        '[check] écoute : ${routes == null ? 'toutes les commandes' : routes.join(' | ')}');
    _ecouteCommandes =
        _requeteCommandes(routes).snapshots().listen((querySnapshot) async {
      _ecouteActive = true;
      // Une copie venue du cache local ne prouve pas que la base répond.
      if (!querySnapshot.metadata.isFromCache) {
        FirestoreBackoff.instance.succes();
      }
      if (_alerteEcouteEnvoyee && !querySnapshot.metadata.isFromCache) {
        _alerteEcouteEnvoyee = false;
        SendEmail.sendMessagewithtelegram(
          message: 'Recharge237 — ÉCOUTE DES COMMANDES RÉTABLIE\n'
              'Téléphone : ${ServerManager.instance.deviceId}',
        ).catchError((Object _) {});
      }
      await Future.delayed(const Duration(seconds: 5));

      await Future.forEach(querySnapshot.docChanges,
          (DocumentChange change) async {
        if (change.type == DocumentChangeType.removed) return;
        final Map<String, dynamic> data =
            (change.doc.data() as Map<String, dynamic>?) ?? const {};
        // [CADENCE 28/10/2026] Une commande arrive : la surveillance réseau
        // passe immédiatement à la cadence soutenue (5 min), sans attendre
        // la fin du cycle lent (30 min).
        NetworkWatch.instance.setPendingWork(true);
        await _traiterCommande(change.doc.id, data);
      });
    }, onError: (Object erreur, StackTrace _) async {
      _ecouteActive = false;
      // [ROUTAGE 29/10/2026] Requête filtrée refusée (index absent, requête
      // jugée invalide) : on repasse sur l'écoute complète, qui marche
      // toujours, plutôt que de ne plus rien voir.
      if (routes != null &&
          erreur is FirebaseException &&
          (erreur.code == 'failed-precondition' ||
              erreur.code == 'invalid-argument')) {
        debugPrint(
            '[check] écoute filtrée refusée ($erreur) : écoute complète');
        _ecouteComplete = true;
        if (mounted) check();
        return;
      }
      final Duration attente = FirestoreBackoff.instance.echec(erreur);
      debugPrint('[check] écoute des commandes interrompue : $erreur — '
          'nouvelle tentative dans ${attente.inSeconds} s');
      if (!_alerteEcouteEnvoyee) {
        _alerteEcouteEnvoyee = true;
        try {
          await SendEmail.sendMessagewithtelegram(
            message: 'Recharge237 — ÉCOUTE DES COMMANDES ARRÊTÉE\n'
                'Téléphone : ${ServerManager.instance.deviceId}\n'
                'Erreur    : $erreur\n'
                '${FirestoreBackoff.estSaturation(erreur) ? 'Cause : quota Firestore atteint.\n' : ''}'
                'Le serveur se réabonne seul (attente doublée à chaque échec, '
                'max 5 min). Si cela dure, vérifie que l\'UID Firebase du '
                'téléphone est toujours admin.',
          );
        } catch (_) {}
      }
      await Future.delayed(attente);
      if (!mounted) return;
      check();
    });
  }

  // [RESEAU 28/10/2026] Écart laissé entre deux commandes rejouées : le temps
  // que la fenêtre USSD de l'opérateur se referme et que le réseau respire.
  static const Duration _ecartEntreCommandes = Duration(seconds: 30);

  bool _draining = false;

  /// Rejoue les commandes GARDÉES pendant une coupure réseau, dans l'ordre
  /// d'arrivée, avec un écart entre chacune.
  ///
  /// Appelée par [NetworkWatch] dès qu'une SIM redevient utilisable (et toutes
  /// les 5 minutes comme filet de sécurité). Une commande tentée sans réseau
  /// n'est plus marquée en échec : elle reste en attente, ce qui est le seul
  /// comportement acceptable pour un client qui a déjà payé.
  Future<void> _drainPending() async {
    if (_draining) return;
    _draining = true;
    try {
      final QuerySnapshot<Map<String, dynamic>> snap = await FirebaseFirestore
          .instance
          .collection('Transact')
          .where('status', whereIn: kActionableStatuses)
          .limit(50)
          .get()
          .timeout(const Duration(seconds: 15));
      final docs = snap.docs.toList()
        ..sort((a, b) => (a.data()['heure'] ?? '')
            .toString()
            .compareTo((b.data()['heure'] ?? '').toString()));
      for (final doc in docs) {
        final data = doc.data();
        final bool relance = data['relance_demandee'] == true;
        if (!isRecentOrder(data['heure']) && !relance) continue;
        // Déjà tentée (sans relance de l'admin) : c'est à lui de décider.
        final int attempts = (data['attempts'] as num?)?.toInt() ?? 0;
        if (attempts > 0 && !relance) continue;
        // Le réseau est-il revenu pour CET opérateur ? Sinon on s'arrête là.
        final SimTarget? cible = targetForOrder(
          _simConfig,
          data['operateur_cible']?.toString() ?? 'camtel_pre',
        );
        if (cible != null) {
          final SimNetworkCheck reseau = await SimNetworkGuard.check(
            cible.slot,
            expected: cible.operator,
            maxWait: Duration.zero,
          );
          if (!reseau.ok) {
            debugPrint('[drain] pause : ${reseau.reason}');
            break;
          }
        }
        await _traiterCommande(doc.id, data);
        if (_derniereCommandeExecutee) {
          // On attend la FIN RÉELLE de la commande (statut final), puis
          // l'écart demandé : jamais deux sessions en même temps.
          await _attendreFin(doc.id);
          await Future.delayed(_ecartEntreCommandes);
        }
      }
    } catch (e) {
      debugPrint('[drain] reprise impossible : $e');
    } finally {
      _draining = false;
    }
  }

  /// Statuts d'une commande encore en train de s'exécuter.
  static const Set<String> _statutsEnCours = {'2', '12', '20', '30', '33'};

  /// Attend que la commande ait atteint un statut final.
  ///
  /// Une session dure de 20 à 90 s selon l'opérateur ; au-delà de 4 minutes on
  /// considère qu'elle est bloquée et on laisse la main (la commande reste
  /// alors visible pour l'admin, jamais relancée d'elle-même).
  /// [QUOTA 30/10/2026] Avant : une lecture forcée (`Source.server`) toutes
  /// les 3 s pendant 4 min, soit jusqu'à **80 lectures pour UNE commande**,
  /// et aucune information entre deux sondes. Maintenant : une écoute du
  /// document, facturée une seule fois par changement de statut (2 à 4
  /// lectures par commande) et qui voit le statut final dès qu'il est écrit.
  ///
  /// Les instantanés servis par le cache local sont ignorés : c'est bien
  /// l'état du serveur qui décide. Passé le délai de 4 min sans nouveau
  /// statut, on fait comme avant — on laisse la main sans bloquer la file.
  Future<void> _attendreFin(String docId) async {
    try {
      await FirebaseFirestore.instance
          .collection('Transact')
          .doc(docId)
          .snapshots()
          .timeout(const Duration(minutes: 4))
          .firstWhere((DocumentSnapshot<Map<String, dynamic>> snap) {
        if (snap.metadata.isFromCache) return false;
        final String st = (snap.data()?['status'] ?? '').toString();
        return !_statutsEnCours.contains(st);
      });
    } on TimeoutException {
      debugPrint('[drain] $docId toujours en cours après 4 min — on continue');
    } catch (e) {
      debugPrint('[drain] $docId suivi interrompu : $e — on continue');
    }
  }

  /// Vrai quand la dernière commande traitée a réellement lancé une session.
  bool _derniereCommandeExecutee = false;

  /// Traite UNE commande.
  ///
  /// Extraite de `check()` pour être rejouable par [_drainPending] au retour
  /// du réseau, sans dupliquer la logique des quatre opérateurs.
  Future<void> _traiterCommande(String docId, Map<String, dynamic> data) async {
    final server = ServerManager.instance;
    final claimer = TransactionClaimer.instance;
    final mtn = MtnUssdManager.instance;
    _derniereCommandeExecutee = false;
    // [PRODUCTION 27/10/2026] Garde-fou au branchement sur la vraie base :
    // les anciennes commandes restées à "1"/"9"/"6"/"11" (déjà traitées à
    // la main, peut-être) ne sont JAMAIS relancées automatiquement —
    // risque de double crédit. Seules les commandes récentes sont traitées.
    // [28/10/2026] Le serveur n'exécute une commande qu'UNE fois : il
    // n'y a plus de relance automatique. Seule une relance demandée par
    // l'admin (bouton de l'app, ou `relance_demandee: true` dans
    // Firestore) peut repartir — et elle aussi une seule fois.
    final bool relanceDemandee = data['relance_demandee'] == true;
    if (!isRecentOrder(data['heure']) && !relanceDemandee) return;
    final status = data['status']?.toString() ?? '';
    final operateur = data['operateur_cible']?.toString() ?? 'camtel_pre';
    final numero = data['numeroorange']?.toString() ?? '';
    final numCible = data['numerocamtel']?.toString() ?? '';
    final amount = data['amount']?.toString() ?? '';
    final idTransact = data['idtransact']?.toString() ?? '';
    final forfaitIndex = data['forfait_index']?.toString() ?? '';
    // [PRIX 28/10/2026] Commande de requête qui a fourni la liste d'offres :
    // elle contient le prix MTN de référence, seul juge pour l'activation.
    final sourceOrder = data['source_order']?.toString() ?? '';

    // [RESEAU 28/10/2026] Pas de réseau pour cet opérateur : la commande est
    // GARDÉE telle quelle — aucune réclamation, aucun statut touché, aucun
    // message d'échec au client. Elle repartira dans son ordre d'arrivée dès
    // le retour du réseau ([[NetworkWatch]] → [[_drainPending]]).
    final SimTarget? cible = targetForOrder(_simConfig, operateur);
    if (cible != null) {
      final SimNetworkCheck reseau = await SimNetworkGuard.check(
        cible.slot,
        expected: cible.operator,
        maxWait: Duration.zero,
      );
      if (!reseau.ok) {
        debugPrint('[reseau] $docId gardée — ${reseau.reason}');
        return;
      }
    }

    // ─────────────────────────────────────────────────────────────
    // CAMTEL PRÉPAYÉ / RETRY  (comportement original inchangé)
    // ─────────────────────────────────────────────────────────────
    if ((status == "1" || status == "9") &&
        (operateur == 'camtel_pre' || operateur == '')) {
      // [ROUTAGE 29/10/2026] "9" = recharge POSTPAYÉE (getdata compose
      // alors sur la SIM post). Elle reste acceptée par un téléphone
      // CAMTEL prépayé (comme avant) ET l'est désormais aussi par un
      // téléphone qui ne sert que le postpayé.
      // [ROUTAGE 28/10/2026] L'admin décide quel téléphone exécute quoi
      // (`handles` dans servers/{deviceId}).
      final bool servi = status == "9"
          ? server.handlesOperation('camtel_post') ||
              server.handlesOperation('camtel_pre')
          : server.handlesOperation('camtel_pre');
      if (!servi) return;
      // [PRODUCTION 27/10/2026] Le transfert *550* est un transfert de
      // crédit CAMTEL : jamais vers un numéro d'un autre opérateur.
      if (!isCamtelNumber(numCible)) {
        debugPrint(
            '[check] $docId ignorée : $numCible n\'est pas un numéro CAMTEL');
        return;
      }
      // [DETECTION 28/10/2026] Pas de SIM CAMTEL sur ce téléphone : la
      // commande reste à un autre serveur (aucun USSD CAMTEL lancé sur
      // une SIM MTN, aucun statut modifié).
      if (!_simConfig.camtelConfigured) return;
      if (!server.canHandle(numeroorange: numero, status: status)) return;
      // [28/10/2026] Minimum opérateur : 100 F.
      if (!isAmountAllowed(amount)) {
        await updateValueInFirestore("Transact", docId, "status", "22");
        await updateValueInFirestore(
            "Transact", docId, "failure_reason", amountTooSmallReason(amount));
        return;
      }
      final claimed = await claimer.claim(docId, server.deviceId);
      if (!claimed) return;

      await Future.delayed(const Duration(seconds: 1));
      _derniereCommandeExecutee = true;
      getdata(docId, numCible, amount, idTransact, status);
    }

    // ─────────────────────────────────────────────────────────────
    // CAMTEL POSTPAYÉ  (comportement original inchangé)
    // ─────────────────────────────────────────────────────────────
    if (status == "6" && operateur == 'camtel_post') {
      if (!server.handlesOperation('camtel_post')) return;
      if (!isCamtelNumber(numCible)) return;
      // [DETECTION 28/10/2026] Même garde que la prépayée : un téléphone
      // sans SIM CAMTEL ne doit pas prendre une recharge postpayée.
      if (!_simConfig.camtelConfigured) return;
      if (!server.canHandle(numeroorange: numero, status: status)) return;
      final claimed = await claimer.claim(docId, server.deviceId);
      if (!claimed) return;

      _derniereCommandeExecutee = true;
      loadcreditonpost(docId, numCible, amount, idTransact);
    }

    // ─────────────────────────────────────────────────────────────
    // RETRY USSD CAMTEL  (comportement original inchangé)
    // ─────────────────────────────────────────────────────────────
    // [ROUTAGE 29/10/2026] Seulement les commandes CAMTEL : une commande
    // MTN d'un point de vente arrive aussi au statut "11" (la passerelle
    // pose "11" pour tout POS) et partait ici, avec un code CAMTEL composé
    // sur un numéro MTN. Elle passe maintenant par les branches MTN.
    if (status == "11" && (operateur == 'camtel_pre' || operateur == '')) {
      // [DETECTION 28/10/2026] Le retry rejoue une commande CAMTEL : réservé
      // aux téléphones qui ont la SIM correspondante.
      if (!_simConfig.camtelConfigured) return;
      if (!server.handlesOperation('camtel_pre')) return;
      if (!server.canHandle(numeroorange: numero, status: '1')) return;
      final claimed = await claimer.claim(docId, server.deviceId);
      if (!claimed) return;

      optionControllers.clear();
      optionControllers.addAll([
        TextEditingController(text: numCible),
        TextEditingController(text: numCible),
        TextEditingController(text: "1"),
      ]);
      // [RESEAU 28/10/2026] Une relance de point de vente compose aussi
      // un vrai code : sans reseau, on ne la lance pas.
      final SimNetworkCheck reseauRetry = await SimNetworkGuard.check(
        _simConfig.camtelPre.slot,
        expected: 'camtel',
      );
      if (!reseauRetry.ok) {
        // [RESEAU 28/10/2026] Rien n'a été composé : la commande est
        // GARDÉE, pas marquée en échec.
        debugPrint('[reseau] $docId (retry) gardée : ${reseauRetry.reason}');
        await claimer.release(docId, server.deviceId);
        await updateValueInFirestore("Transact", docId, "failure_reason",
            '${reseauRetry.reason} — commande gardée, elle repartira au retour du réseau.');
        return;
      }
      _derniereCommandeExecutee = true;
      updateValueInFirestore("Transact", docId, "status", "12");
      await _closeUssdDialog();
      await _channel.invokeMethod('multisessionUssd', {
        'ussdCode': "${data['retry'] ?? ''}",
        'slotIndex': 0,
        'options': optionControllers.map((c) => c.text).toList(),
      });
    }

    // ─────────────────────────────────────────────────────────────
    // MTN AIRTIME  — Workflow A interactif
    // Statuts : 1 (en attente) → 20 (en cours) → 21 (ok) / 22 (ko)
    // ─────────────────────────────────────────────────────────────
    if ((status == "1" || status == "11") && operateur == 'mtn_airtime') {
      if (!server.handlesOperation('mtn_airtime')) return;
      // [MTN 27/10/2026] Pas de SIM MTN déclarée sur ce téléphone :
      // on laisse la commande à un autre serveur (aucun USSD MTN lancé
      // sur une SIM CAMTEL, aucun statut modifié).
      if (!_simConfig.mtnConfigured) return;
      if (!server.canHandle(numeroorange: numero, status: status)) return;
      // [28/10/2026] Minimum opérateur MTN : 100 F (refusé en dessous par
      // l'USSD de vente de crédit). Inutile de lancer la session.
      if (!isAmountAllowed(amount)) {
        await updateValueInFirestore("Transact", docId, "status", "22");
        await updateValueInFirestore(
            "Transact", docId, "failure_reason", amountTooSmallReason(amount));
        return;
      }
      final claimed = await claimer.claim(docId, server.deviceId);
      if (!claimed) return;

      debugPrint('[check] MTN Airtime → $numCible $amount FCFA');
      _derniereCommandeExecutee = true;
      final resAirtime = await mtn.rechargeAirtime(
        docId: docId,
        amount: amount,
        clientNumber: numCible,
        sim: _simConfig.mtn,
      );
      _notifyTelegram(
        operateur: 'MTN Airtime',
        simSlot: _simConfig.mtn.slot,
        clientNumber: numCible,
        amount: amount,
        resultat: resAirtime.rawMessage,
        succes: resAirtime.result.name == 'success',
      );
    }

    // ─────────────────────────────────────────────────────────────
    // MTN FORFAIT Phase 1 — Récupérer la liste des offres
    // [MTN GOOD DEAL 27/10/2026] Déclenché à status == "0" (pas "1") :
    // cette requête est GRATUITE, aucun paiement n'est associé — un
    // client normal ne peut jamais poser status == "1" lui-même
    // (firestore.rules le réserve à l'admin/la passerelle), donc cette
    // transaction n'atteindrait jamais "1" si on attendait ce statut.
    // → après succès, status passe à "31" et `forfait_list` est rempli
    // ─────────────────────────────────────────────────────────────
    if (status == "0" && operateur == 'mtn_forfait') {
      if (!server.handlesOperation('mtn_forfait')) return;
      // [MTN 27/10/2026] Pas de SIM MTN déclarée sur ce téléphone :
      // on laisse la commande à un autre serveur (aucun USSD MTN lancé
      // sur une SIM CAMTEL, aucun statut modifié).
      //
      // [BOOST 28/10/2026] Cette requête est GRATUITE et ne saisit aucun
      // code secret : la carte MTN suffit, le PIN n'est pas requis.
      if (!_simConfig.mtnSimPresent) return;
      if (!server.canHandle(numeroorange: numero, status: status)) return;
      final claimed = await claimer.claim(docId, server.deviceId);
      if (!claimed) return;

      debugPrint('[check] MTN Forfait Query → $numCible');
      _derniereCommandeExecutee = true;
      final resList = await mtn.queryForfaitList(
        docId: docId,
        clientNumber: numCible,
        sim: _simConfig.mtn,
      );
      _notifyTelegram(
        operateur: 'MTN Forfait (liste)',
        simSlot: _simConfig.mtn.slot,
        clientNumber: numCible,
        amount: '—',
        resultat:
            resList.isEmpty ? 'Aucune offre récupérée' : resList.join('\n'),
        succes: resList.isNotEmpty,
      );
      // Après ça, l'app client lit `forfait_list` et affiche les offres.
      // L'utilisateur sélectionne + paie → l'app met status à "1" et
      // operateur à "mtn_forfait_activate" avec forfait_index rempli.
    }

    // ─────────────────────────────────────────────────────────────
    // MTN FORFAIT Phase 2 — Activer l'offre choisie après paiement
    // Statuts : 1 → 33 (activation) → 34 (ok) / 35 (ko)
    // ─────────────────────────────────────────────────────────────
    if ((status == "1" || status == "11") &&
        operateur == 'mtn_forfait_activate') {
      // [MTN 27/10/2026] Pas de SIM MTN déclarée sur ce téléphone :
      // on laisse la commande à un autre serveur (aucun USSD MTN lancé
      // sur une SIM CAMTEL, aucun statut modifié).
      if (!_simConfig.mtnConfigured) return;
      // Le même téléphone doit traiter la requête ET l'activation.
      if (!server.handlesOperation('mtn_forfait')) return;
      if (forfaitIndex.isEmpty) {
        debugPrint('[check] Erreur : forfait_index manquant pour $docId');
        return;
      }
      if (!server.canHandle(numeroorange: numero, status: status)) return;
      final claimed = await claimer.claim(docId, server.deviceId);
      if (!claimed) return;

      debugPrint(
          '[check] MTN Forfait Activate → $numCible, offre=$forfaitIndex');
      _derniereCommandeExecutee = true;
      final resActivate = await mtn.activateForfait(
        docId: docId,
        clientNumber: numCible,
        forfaitIndex: forfaitIndex,
        sim: _simConfig.mtn,
        sourceOrder: sourceOrder,
      );
      _notifyTelegram(
        operateur: 'MTN Forfait (activation)',
        simSlot: _simConfig.mtn.slot,
        clientNumber: numCible,
        amount: '—',
        resultat: resActivate.rawMessage,
        succes: resActivate.result.name == 'success',
      );
    }

    // ─────────────────────────────────────────────────────────────
    // [OFFRES PERSO 29/10/2026] GOOD DEAL ORANGE — même parcours que le
    // Boost MTN : requête gratuite (0 → 30 → 31/32), puis activation de
    // l'offre payée (1/11 → 33 → 34/35). Code USSD réglé par l'admin
    // (app_config/public.ussd_gooddeal_orange) ; non configuré = la
    // commande échoue proprement, aucun code composé.
    // ─────────────────────────────────────────────────────────────
    if (status == "0" && operateur == 'orange_forfait') {
      if (!server.handlesOperation('orange_forfait')) return;
      if (!_simConfig.orangeConfigured) return;
      if (!server.canHandle(numeroorange: numero, status: status)) return;
      final claimed = await claimer.claim(docId, server.deviceId);
      if (!claimed) return;
      debugPrint('[check] Orange Good Deal Query → $numCible');
      _derniereCommandeExecutee = true;
      final resList = await mtn.queryForfaitList(
        docId: docId,
        clientNumber: numCible,
        sim: _simConfig.orange,
        operateur: 'orange',
      );
      _notifyTelegram(
        operateur: 'Orange Good Deal (liste)',
        simSlot: _simConfig.orange.slot,
        clientNumber: numCible,
        amount: '—',
        resultat:
            resList.isEmpty ? 'Aucune offre récupérée' : resList.join('\n'),
        succes: resList.isNotEmpty,
      );
    }

    if ((status == "1" || status == "11") &&
        operateur == 'orange_forfait_activate') {
      if (!_simConfig.orangeConfigured) return;
      if (!server.handlesOperation('orange_forfait')) return;
      if (forfaitIndex.isEmpty) {
        debugPrint('[check] Erreur : forfait_index manquant pour $docId');
        return;
      }
      if (!server.canHandle(numeroorange: numero, status: status)) return;
      final claimed = await claimer.claim(docId, server.deviceId);
      if (!claimed) return;
      debugPrint(
          '[check] Orange Good Deal Activate → $numCible, offre=$forfaitIndex');
      _derniereCommandeExecutee = true;
      final resActivate = await mtn.activateForfait(
        docId: docId,
        clientNumber: numCible,
        forfaitIndex: forfaitIndex,
        sim: _simConfig.orange,
        sourceOrder: sourceOrder,
        operateur: 'orange',
      );
      _notifyTelegram(
        operateur: 'Orange Good Deal (activation)',
        simSlot: _simConfig.orange.slot,
        clientNumber: numCible,
        amount: '—',
        resultat: resActivate.rawMessage,
        succes: resActivate.result.name == 'success',
      );
    }

    // ─────────────────────────────────────────────────────────────
    // [CATALOGUE 29/10/2026] FORFAIT MTN DU CATALOGUE (Surf Day,
    // Giga surf, MTN Home…), payé par le client. Même menu que Boost :
    // le serveur cherche la ligne du forfait payé et l'active.
    // Statuts : 1/11 → 33 (activation) → 34 (ok) / 35 (ko)
    // ─────────────────────────────────────────────────────────────
    if ((status == "1" || status == "11") && operateur == 'mtn_bundle') {
      if (!_simConfig.mtnConfigured) return;
      if (!server.handlesOperation('mtn_forfait')) return;
      final String code = data['retry']?.toString() ?? '';
      if (code.isEmpty || code == '0') {
        // Pas un remboursement : l'admin active à la main (alerte Telegram).
        await FirebaseFirestore.instance.collection('Transact').doc(docId).set({
          'status': '35',
          'failure_reason': 'Votre paiement est bien reçu. Notre équipe active '
              'votre forfait et vous prévient.',
          'admin_detail':
              'Forfait MTN sans code catalogue : activation automatique impossible.',
          'a_traiter_admin': true,
        }, SetOptions(merge: true));
        await SendEmail.sendMessagewithtelegram(
          message: 'Recharge237 — FORFAIT À ACTIVER À LA MAIN\n'
              'Client    : $numCible\n'
              'Montant   : $amount F\n'
              'Commande  : $docId\n'
              'Raison    : forfait MTN sans code catalogue.\n'
              'Le client a PAYÉ : active le forfait puis passe la commande à 34.',
        );
        return;
      }
      if (!server.canHandle(numeroorange: numero, status: status)) return;
      final claimed = await claimer.claim(docId, server.deviceId);
      if (!claimed) return;

      debugPrint('[check] MTN Forfait catalogue → $numCible, forfait=$code');
      _derniereCommandeExecutee = true;
      final resCatalogue = await mtn.activateCatalogBundle(
        docId: docId,
        clientNumber: numCible,
        forfaitCode: code,
        sim: _simConfig.mtn,
      );
      _notifyTelegram(
        operateur: 'MTN Forfait catalogue',
        simSlot: _simConfig.mtn.slot,
        clientNumber: numCible,
        amount: amount,
        resultat: resCatalogue.rawMessage,
        succes: resCatalogue.result.name == 'success',
      );
    }
  }

  // Initialisé directement ici (et non dans check(), qui est asynchrone)
  // car build() peut s'exécuter avant que check() ne termine, provoquant
  // un LateInitializationError sur un écran blanc.
  final ScrollController _controller =
      ScrollController(initialScrollOffset: 0.0);
  void scrollToIndex1() {
    double itemHeight = 80.0; // Hauteur approximative de chaque élément
    _controller.animateTo(
      itemHeight * 60, // Multipliez par l'index souhaité (1 dans ce cas)
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
  }

  backgroundMessageHandler() async {
    debugPrint('SMS EN ARRIÈRE-PLAN ');

    check();
    debugPrint('FIN = FIN');
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
    // [29/10/2026] main.dart demande déjà les permissions au même moment :
    // deux demandes simultanées lèvent une PlatformException. On lit alors
    // simplement l'état une fois la première demande terminée.
    PermissionStatus status;
    try {
      status = await Permission.phone.request();
    } on PlatformException {
      await Future<void>.delayed(const Duration(seconds: 3));
      status = await Permission.phone.status;
    }
    if (status.isGranted) {
      try {
        final simCards = await UssdLauncher.getSimCards();
        setState(() {
          simCardsList = simCards;
          debugPrint('${simCards.first}');
          if (simCardsList.isNotEmpty) {
            selectedSlotIndex = simCardsList[0]['slotIndex'];
            addOptionField();
          }
        });
      } catch (e) {
        debugPrint("Erreur lors du chargement des cartes SIM: $e");
      }
    } else {
      debugPrint("Permission téléphone non accordée");
    }
  }

  @override
  void initState() {
    super.initState();
    // [ACCESSIBILITE 29/10/2026] Suivi premier plan / arrière-plan :
    // didChangeAppLifecycleState n'était jamais appelé (observateur absent).
    WidgetsBinding.instance.addObserver(this);
    _verifierAncienneApp();
    readSMS();
    loadSimCards();
    _setupUssdResponseListener();
    getConnectivity();
    // Initialise l'enregistrement serveur, charge les PIN, puis démarre l'écoute
    // [PRODUCTION 27/10/2026] L'UID du serveur est envoyé sur Telegram à
    // chaque démarrage : l'admin sait ainsi quel compte déclarer admin.
    // [TELEGRAM 29/10/2026] MIUI relance souvent l'app : ce message partait
    // à chaque redémarrage. Il n'est plus envoyé que si l'UID a changé ou
    // si le dernier envoi date de plus de 12 h.
    _annoncerDemarrage();
    ServerManager.instance.initialize().then((_) async {
      // [ORPHELINES 28/10/2026] Si l'app a été tuée en pleine session (mise à
      // jour, plantage, redémarrage du téléphone), Android laisse le dialogue
      // USSD à l'écran : il masque l'app et bloque la commande suivante. On le
      // ferme comme le ferait un humain en rouvrant l'app.
      await UssdSessionRunner.instance.clearStaleDialog();
      _simConfig = await SessionConfig.load(ServerManager.instance.deviceId);
      // [RESEAU 28/10/2026] Surveillance périodique : l'admin est prévenu sur
      // Telegram dès qu'une SIM de ce téléphone perd le réseau (et quand il
      // revient), au lieu de le découvrir sur une commande échouée.
      NetworkWatch.instance.start(ServerManager.instance.deviceId);
      // [SANTE 29/10/2026] Accessibilité, UID et fenêtres USSD orphelines.
      HealthWatch.instance.onChange = () {
        if (mounted) setState(() {});
      };
      HealthWatch.instance.start(ServerManager.instance.deviceId);
      // [COMPTA 28/10/2026] Bilan quotidien, soldes lus dans les SMS des
      // opérateurs et diffusion Telegram.
      ReportService.instance.start(ServerManager.instance.deviceId);
      check();
      // Écoute les commandes distantes de l'admin
      RemoteCommandHandler.instance.startListening(
        onRestart: _remoteRestart,
        onReloadConfig: _remoteReloadConfig,
      );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ecouteCommandes?.cancel();
    _smsRelais?.cancel();
    // [FLUIDITE 30/10/2026] Abonnements USSD et minuteur d'écran vide : ils
    // survivaient à la destruction du widget. `remoteRestart` recrée un
    // Commandeview, donc chaque redémarrage d'interface laissait un ancien
    // écouteur appeler setState sur un widget démonté.
    ussdSubscription?.cancel();
    _ussdSessionSub?.cancel();
    _surEcranVide?.cancel();
    RemoteCommandHandler.instance.stopListening();
    // [RESEAU 28/10/2026] Plus de surveillance quand le serveur n'écoute plus :
    // inutile d'alerter l'admin sur un téléphone volontairement hors service.
    NetworkWatch.instance.stop();
    HealthWatch.instance.stop();
    ServerManager.instance.goOffline();
    super.dispose();
  }

  /// Redémarre l'interface complète (déclenché par commande distante "restart").
  void _remoteRestart() {
    debugPrint('[RemoteCommand] Redémarrage interface...');
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const Commandeview()),
      (route) => false,
    );
  }

  /// Recharge les PIN et opérateurs depuis Firestore (commande "reload_config").
  Future<void> _remoteReloadConfig() async {
    _simConfig = await SessionConfig.load(ServerManager.instance.deviceId);
    await ServerManager.instance.reloadOperators();
    // [EMPLACEMENTS 28/10/2026] Les seuils de solde par opérateur viennent de
    // la même configuration : ils suivent le même rechargement.
    await ReportService.instance.rechargerConfig();
    debugPrint('[RemoteCommand] Config rechargée — $_simConfig');
    // [ROUTAGE 29/10/2026] Opérateurs servis modifiés par l'admin : on
    // réécoute avec le nouveau filtre.
    final List<OrderRoute>? nouvelles =
        routesForHandles(ServerManager.instance.handles);
    if ('$nouvelles' != '$_routesEcoutees' && mounted) check();
    // Bandeau « SIM non configurées » : suit la configuration.
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // [FLUIDITE 30/10/2026] Ce rappel arrive parfois APRÈS la destruction du
    // widget (redémarrage d'interface par commande distante) : setState sur
    // un State démonté lève une exception et fait planter la frame suivante.
    if (!mounted) return;
    setState(() {
      _hasFocus = state == AppLifecycleState.hidden;
    });
    // Retour des réglages d'accessibilité : contrôle immédiat (le bandeau
    // rouge disparaît sans attendre le contrôle des 5 min).
    if (state == AppLifecycleState.resumed) {
      HealthWatch.instance.checkNow();
      _verifierAncienneApp();
    }
  }

  bool _hasFocus = false;

  StreamSubscription<SmsRecu>? _smsRelais;

  /// Relaie chaque SMS reçu sur Telegram et par e-mail.
  ///
  /// [SMS 29/10/2026] Passe par le récepteur natif (SmsReceiver, canal
  /// `r237/sms`) qui remplace le paquet `telephony`. Même comportement
  /// qu'avant ; l'app serveur tourne au premier plan, l'écoute en
  /// arrière-plan séparée n'est plus nécessaire.
  void readSMS() {
    _smsRelais?.cancel();
    _smsRelais = SmsReceiver.flux.listen((SmsRecu message) {
      debugPrint('Message reçu: ${message.body}');
      // [TELEGRAM 29/10/2026] Chaque recharge déclenche un SMS de
      // l'opérateur : les relayer tous doublait le volume Telegram et
      // dépassait la limite Gmail (~500 e-mails/jour). Les SMS de solde et
      // de transaction reconnus sont exploités par ReportService (bilan,
      // solde bas, écart) ; seuls les autres sont relayés, sans e-mail.
      if (parseSmsBody(message.body, sender: message.address).recognised) {
        return;
      }
      SendEmail.sendMessagewithtelegram(
        message: 'Téléphone : ${ServerManager.instance.deviceId}\n'
            'SMS de    : ${message.address}\n'
            '─────────────────────\n'
            '${message.body}',
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .hideCurrentSnackBar(reason: SnackBarClosedReason.swipe);
      }
    }, onError: (Object e) => debugPrint('[SMS] relais impossible : $e'));
  }

  // ── Habillage de l'écran serveur ──────────────────────────────────────────
  // Objectif : lisible d'un coup d'œil sur le téléphone qui tourne 24/7 —
  // état du serveur, volume du jour, puis chaque commande avec son statut
  // réel (y compris les statuts MTN, longtemps affichés « en attente »).

  /// 0 = toutes, 1 = à traiter, 2 = livrées, 3 = échecs.
  int _filtre = 0;

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      // [ARRIERE-PLAN 29/10/2026] Retour ne ferme plus le serveur : il passe
      // en arrière-plan et continue de traiter les commandes.
      onWillPop: () async {
        try {
          await const MethodChannel('r237/ussd').invokeMethod('moveToBack');
        } catch (_) {}
        return false;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F6FA),
        appBar: _buildAppBar(),
        body: Column(
          children: [
            _bandeauAncienneApp(),
            _bandeauAccessibilite(),
            _bandeauConfigSim(),
            Expanded(child: _buildBody()),
          ],
        ),
        bottomNavigationBar: _buildStatusStrip(),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      titleSpacing: 16,
      title: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF006CD9), Color(0xFF06294D)],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.cell_tower_rounded,
                color: Colors.white, size: 19),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Recharge237',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF06294D),
                    letterSpacing: -0.2,
                  ),
                ),
                Text(
                  'Serveur USSD • ${ServerManager.instance.deviceId}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF7A8699),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        const Padding(
          padding: EdgeInsets.only(right: 2),
          child: Center(child: _OnlineDot()),
        ),
        PopupMenuButton<int>(
          icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF06294D)),
          color: Colors.white,
          surfaceTintColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          onSelected: (int value) {
            switch (value) {
              case 1:
                _copier('ID du téléphone', ServerManager.instance.deviceId);
                break;
              case 2:
                _copier('UID Firebase', serverAuthUid);
                break;
              case 3:
                _remoteReloadConfig();
                _toast('Configuration rechargée');
                break;
              case 4:
                _testUssd();
                break;
              case 5:
                _ouvrirConfigSim();
                break;
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 5, child: Text('Configurer les SIM')),
            PopupMenuDivider(),
            PopupMenuItem(value: 1, child: Text("Copier l'ID du téléphone")),
            PopupMenuItem(value: 2, child: Text("Copier l'UID Firebase")),
            PopupMenuItem(value: 3, child: Text('Recharger la configuration')),
            PopupMenuDivider(),
            PopupMenuItem(value: 4, child: Text('Test USSD (débogage)')),
          ],
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  /// [QUOTA 30/10/2026] Flux des 30 dernières commandes, créé UNE seule fois.
  ///
  /// Avant, la requête était reconstruite à chaque appel de [_buildBody],
  /// donc à chaque `setState` — il y en a une vingtaine dans cet écran
  /// (bandeaux, compteur, filtres, traitement des commandes). Un nouvel objet
  /// stream faisait annuler l'abonnement précédent par le `StreamBuilder` et
  /// en relisait un autre : **30 documents relus à chaque rebuild**, pour un
  /// écran qui ne change pourtant pas. Une seule commande traitée déclenchant
  /// plusieurs `setState`, c'était la première source de lectures du serveur.
  ///
  /// Le flux est désormais conservé en mémoire : les rebuilds ne coûtent plus
  /// rien, seuls les vrais changements en base émettent.
  Stream<QuerySnapshot>? _commandesStream;

  Widget _buildBody() {
    final Stream<QuerySnapshot> ecoute = _commandesStream ??= firestore
        .collection('Transact')
        .orderBy("heure", descending: true)
        // [QUOTA 29/10/2026] 30 au lieu de 100 : chaque redémarrage de
        // l'app (fréquent sous MIUI, cf. _claude_keepalive.sh) relisait les
        // 100 documents.
        .limit(30)
        .snapshots();
    return StreamBuilder<QuerySnapshot>(
      stream: ecoute,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _buildMessage(
            icon: Icons.cloud_off_rounded,
            title: 'Base de données injoignable',
            detail: '${snapshot.error}',
            color: const Color(0xFFD90200),
          );
        }

        final List<DocumentSnapshot> docs = snapshot.data?.docs ?? const [];
        if (docs.isEmpty) {
          return _buildMessage(
            icon: Icons.inbox_rounded,
            title: 'Aucune commande',
            detail:
                'Les commandes des clients apparaîtront ici automatiquement.',
          );
        }

        final List<Map<String, dynamic>> toutes = docs.map((d) {
          final Map<String, dynamic> data =
              (d.data() as Map<String, dynamic>?) ?? <String, dynamic>{};
          return <String, dynamic>{...data, '_doc': d.id};
        }).toList();

        int enAttente = 0;
        int livrees = 0;
        int echecs = 0;
        for (final Map<String, dynamic> m in toutes) {
          final ServerStatusInfo info = serverStatusInfo(m['status']);
          if (info.isSuccess) {
            livrees++;
          } else if (info.isFailure) {
            echecs++;
          } else {
            enAttente++;
          }
        }

        final List<Map<String, dynamic>> visibles = toutes.where((m) {
          final ServerStatusInfo info = serverStatusInfo(m['status']);
          switch (_filtre) {
            case 1:
              return !info.isSuccess && !info.isFailure;
            case 2:
              return info.isSuccess;
            case 3:
              return info.isFailure;
            default:
              return true;
          }
        }).toList();

        // [FLUIDITE 30/10/2026] `ListView.builder` au lieu d'une liste pleine :
        // seuls les éléments demandés par le défilement sont construits et
        // placés (une petite dizaine sur les 30 suivies). Avant, les 30 cartes
        // étaient reconstruites à CHAQUE setState — et l'écran en déclenche
        // plusieurs par seconde pendant une session (chaque écran USSD reçu
        // appelle setState). Les compteurs et les filtres restent en tête.
        final List<Widget Function(BuildContext)> lignes =
            <Widget Function(BuildContext)>[
          (_) => _buildSummary(enAttente, livrees, echecs),
          (_) => const SizedBox(height: 14),
          (_) => _buildFilters(enAttente, livrees, echecs),
          (_) => const SizedBox(height: 12),
          if (visibles.isEmpty)
            (_) => Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: _buildMessage(
                    icon: Icons.filter_alt_off_rounded,
                    title: 'Aucune commande dans ce filtre',
                    detail: 'Choisis « Toutes » pour revoir les 100 dernières.',
                  ),
                )
          else
            ...visibles.map(
              (Map<String, dynamic> m) => (BuildContext _) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TransactionCard(
                      data: m,
                      docId: '${m['_doc']}',
                      onLongPress: () => _copier(
                          'Identifiant', '${m['idtransact'] ?? m['_doc']}'),
                      // [28/10/2026] Seul moyen de faire une 2e tentative :
                      // l'admin la demande (le serveur, lui, ne relance jamais).
                      onRelaunch: () => _relancerCommande(
                          '${m['_doc']}', Map<String, dynamic>.from(m)),
                    ),
                  ),
            ),
        ];

        return RefreshIndicator(
          onRefresh: () async =>
              Future<void>.delayed(const Duration(milliseconds: 400)),
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            itemCount: lignes.length,
            itemBuilder: (BuildContext ctx, int index) => lignes[index](ctx),
          ),
        );
      },
    );
  }

  Widget _buildSummary(int enAttente, int livrees, int echecs) {
    final int total = enAttente + livrees + echecs;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF06294D), Color(0xFF0C3A69)],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'DERNIÈRES COMMANDES',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: Color(0xFF9FB6D0),
                ),
              ),
              const Spacer(),
              Text(
                '$total sur 100',
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF9FB6D0),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _SummaryTile(
                value: livrees,
                label: 'Livrées',
                color: const Color(0xFF4ADE80),
              ),
              _SummaryTile(
                value: enAttente,
                label: 'En attente',
                color: const Color(0xFFFBBF24),
              ),
              _SummaryTile(
                value: echecs,
                label: 'Échecs',
                color: const Color(0xFFFB7185),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(int enAttente, int livrees, int echecs) {
    final List<({int value, String label, int count})> options = [
      (value: 0, label: 'Toutes', count: enAttente + livrees + echecs),
      (value: 1, label: 'À traiter', count: enAttente),
      (value: 2, label: 'Livrées', count: livrees),
      (value: 3, label: 'Échecs', count: echecs),
    ];
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: options.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, index) {
          final option = options[index];
          final bool selected = _filtre == option.value;
          return GestureDetector(
            onTap: () => setState(() => _filtre = option.value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? const Color(0xFF06294D) : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected
                      ? const Color(0xFF06294D)
                      : const Color(0xFFE6EAF0),
                ),
              ),
              child: Text(
                '${option.label}  ${option.count}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : const Color(0xFF44546A),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMessage({
    required IconData icon,
    required String title,
    required String detail,
    Color color = const Color(0xFF7A8699),
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
                color: Color(0xFF06294D),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 12, height: 1.4, color: Color(0xFF7A8699)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusStrip() {
    return GestureDetector(
      onLongPress: () =>
          _copier('ID du téléphone', ServerManager.instance.deviceId),
      child: Container(
        color: const Color(0xFF0B1522),
        // Barre de gestes / boutons système du bas : sans cette marge, l'ID et
        // l'UID passaient dessous et devenaient illisibles.
        padding: EdgeInsets.fromLTRB(
          14,
          8,
          14,
          10 + MediaQuery.of(context).viewPadding.bottom,
        ),
        // Deux lignes : l'ID et l'UID en entier, lisibles sur un écran de
        // téléphone (avant, la moitié du texte passait sous la barre système).
        child: Row(
          children: [
            const _OnlineDot(dark: true),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'ID  ${ServerManager.instance.deviceId}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      letterSpacing: 0.2,
                      color: Color(0xFFB9CADD),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    serverAuthUid.isEmpty
                        ? 'UID  non connecté'
                        : 'UID  $serverAuthUid',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9.5,
                      letterSpacing: 0.2,
                      fontWeight: FontWeight.w500,
                      color: serverAuthUid.isEmpty
                          ? const Color(0xFFFB7185)
                          : const Color(0xFF8AA3BF),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.copy_rounded, size: 13, color: Color(0xFF5A7595)),
          ],
        ),
      ),
    );
  }

  /// [CONFIG SIM 29/10/2026] Écran de configuration des SIM ; au retour,
  /// la configuration est rechargée et l'écoute des commandes réalignée.
  Future<void> _ouvrirConfigSim() async {
    final bool? enregistre = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const SimConfigScreen()),
    );
    if (enregistre == true) {
      await _remoteReloadConfig();
      if (mounted) setState(() {});
      _toast('SIM configurées — le téléphone les utilise dès maintenant');
    }
  }

  /// [RENOMMAGE 29/10/2026] L'app s'appelle désormais com.recharge237.serveur.
  /// Android voit l'ancienne (com.example.projettest) comme une autre app :
  /// tant qu'elle est installée, elle prend aussi des commandes. Ce bandeau
  /// la signale et ouvre sa désinstallation en un geste.
  bool _ancienneApp = false;

  Future<void> _verifierAncienneApp() async {
    try {
      final bool presente = await const MethodChannel('r237/ussd')
              .invokeMethod<bool>('oldAppInstalled') ??
          false;
      if (mounted && presente != _ancienneApp) {
        setState(() => _ancienneApp = presente);
      }
    } catch (_) {}
  }

  Widget _bandeauAncienneApp() {
    if (!_ancienneApp) return const SizedBox.shrink();
    return Material(
      color: const Color(0xFFFDECEC),
      child: InkWell(
        onTap: () =>
            const MethodChannel('r237/ussd').invokeMethod('uninstallOldApp'),
        child: const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Icon(Icons.delete_forever_rounded, color: Color(0xFFD90200)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'L\'ancienne version de ServeurApp est encore installée et '
                  'prend aussi des commandes. Touche ici pour la désinstaller.',
                  style: TextStyle(
                      color: Color(0xFF8A0000), fontWeight: FontWeight.w600),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Color(0xFFD90200)),
            ],
          ),
        ),
      ),
    );
  }

  /// [ACCESSIBILITE 29/10/2026] Bandeau rouge tant que l'accessibilité est
  /// coupée : sans elle, aucune commande ne part et le téléphone ne se
  /// réveille même pas (la session est refusée avant de composer).
  Widget _bandeauAccessibilite() {
    if (HealthWatch.instance.accessibiliteOk != false) {
      return const SizedBox.shrink();
    }
    return Material(
      color: const Color(0xFFFDECEC),
      child: InkWell(
        onTap: () => UssdLauncher.openAccessibilitySettings(),
        child: const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Icon(Icons.accessibility_new_rounded, color: Color(0xFFD90200)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Accessibilité coupée : aucune commande ne peut être livrée. '
                  'Touche ici, puis active « ServeurApp Recharge237 ».',
                  style: TextStyle(
                      color: Color(0xFF8A0000), fontWeight: FontWeight.w600),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Color(0xFFD90200)),
            ],
          ),
        ),
      ),
    );
  }

  /// Bandeau affiché tant qu'aucune SIM n'est déclarée.
  Widget _bandeauConfigSim() {
    if (ServerManager.instance.configured) return const SizedBox.shrink();
    return Material(
      color: const Color(0xFFFFF4E5),
      child: InkWell(
        onTap: _ouvrirConfigSim,
        child: const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Icon(Icons.sim_card_alert_rounded, color: Color(0xFFB25E00)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'SIM non configurées : ce téléphone ne prend aucune commande. '
                  'Touche ici pour choisir le rôle de chaque carte et saisir son PIN.',
                  style: TextStyle(
                      color: Color(0xFF7A4100), fontWeight: FontWeight.w600),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Color(0xFFB25E00)),
            ],
          ),
        ),
      ),
    );
  }

  static const MethodChannel _prefs = MethodChannel('r237/prefs');

  Future<void> _annoncerDemarrage() async {
    try {
      final String? dernierUid =
          await _prefs.invokeMethod<String>('get', {'key': 'start_uid'});
      final int dernierEnvoi = int.tryParse(
              await _prefs.invokeMethod<String>('get', {'key': 'start_at'}) ??
                  '') ??
          0;
      final int maintenant = DateTime.now().millisecondsSinceEpoch;
      if (dernierUid == serverAuthUid &&
          maintenant - dernierEnvoi <
              const Duration(hours: 12).inMilliseconds) {
        debugPrint('[Telegram] démarrage déjà annoncé — pas de message');
        return;
      }
      await SendEmail.sendMessagewithtelegram(
        message: 'Serveur Recharge237 démarré\n'
            'Téléphone : ${ServerManager.instance.deviceId}\n'
            'UID Firebase : ${serverAuthUid.isEmpty ? "NON CONNECTÉ" : serverAuthUid}',
      );
      await _prefs
          .invokeMethod('set', {'key': 'start_uid', 'value': serverAuthUid});
      await _prefs
          .invokeMethod('set', {'key': 'start_at', 'value': '$maintenant'});
    } catch (e) {
      debugPrint('[Telegram] annonce de démarrage impossible : $e');
    }
  }

  void _copier(String label, String value) {
    if (value.trim().isEmpty) {
      _toast('$label indisponible');
      return;
    }
    FlutterClipboard.copy(value);
    _toast('$label copié');
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Ancien bouton flottant rouge : conservé pour le dépannage, mais rangé
  /// dans le menu pour ne plus encombrer l'écran de production.
  Future<void> _testUssd() async {
    final String text = await FlutterClipboard.paste();
    optionControllers.clear();
    optionControllers.addAll([
      TextEditingController(text: text),
      TextEditingController(text: text),
      TextEditingController(text: "1"),
    ]);
    await _closeUssdDialog();
    // [29/10/2026] Sans accessibilité, le plugin lève une exception qui
    // n'était pas rattrapée (« Unhandled Exception … ACCESSIBILITY_NOT_ENABLED »).
    try {
      await _channel.invokeMethod('multisessionUssd', {
        'ussdCode': "*825*1*2*1*2#",
        'slotIndex': 0,
        'options': optionControllers.map((c) => c.text).toList(),
      });
    } on PlatformException catch (e) {
      _toast(e.code == 'ACCESSIBILITY_NOT_ENABLED'
          ? 'Active le service d\'accessibilité de ServeurApp Recharge237'
          : 'Test USSD impossible : ${e.message ?? e.code}');
    }
  }
}

/// Pastille d'état : verte dès que le téléphone a envoyé un signal récent.
class _OnlineDot extends StatelessWidget {
  final bool dark;
  const _OnlineDot({this.dark = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: const Color(0xFF22C55E),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF22C55E).withValues(alpha: 0.55),
            blurRadius: 6,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  final int value;
  final String label;
  final Color color;

  const _SummaryTile({
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF9FB6D0),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '$value',
            style: const TextStyle(
              fontSize: 22,
              height: 1.1,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
