import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:get/get.dart';
import 'package:recharge237_serveur/service/permission.dart';
import 'package:recharge237_serveur/service/controlleur/initcontrolleur.dart';
import 'package:recharge237_serveur/service/controlleur/transact_controlleur.dart';
import 'package:recharge237_serveur/service/controlleur/widget_controlleur.dart';
import 'package:recharge237_serveur/service/executeussd/inteface.dart';
import 'package:recharge237_serveur/service/notification/notification_service.dart';
import 'package:recharge237_serveur/service/view/readsms.dart';
import 'package:recharge237_serveur/test.dart';
import 'package:recharge237_serveur/testview.dart';
import 'package:recharge237_serveur/view/pagecommande/viewcommande.dart';
import 'package:sizer/sizer.dart';
import 'package:unique_identifier/unique_identifier.dart';
// import 'package:another_telephony/telephony.dart';
import 'view/home/Home.dart';

// [PRODUCTION 27/10/2026] Le serveur travaille sur la MÊME base que l'app
// mobile et l'app Web : le projet Firebase `recharge237-r237`. Avant, il
// pointait vers `recharge237-8d1db` (ici) et, en réalité, vers la base de test
// `bdtestserveur` (google-services.json, qui prenait le dessus) : il ne voyait
// donc jamais les commandes des clients.
// Le plugin Gradle google-services a été retiré (android/app/build.gradle.kts)
// pour que ces options soient réellement utilisées.
FirebaseOptions android = FirebaseOptions(
  apiKey: "AIzaSyAMvJnNHxr3bKCn_Xz_vQResqW9PHk4tiE",
  appId: "1:435642925266:android:4deccba5bfee3f415eed0b",
  messagingSenderId: "435642925266",
  projectId: "recharge237-r237",
  storageBucket: "recharge237-r237.firebasestorage.app",
);

/// UID Firebase Auth du serveur (affiché à l'écran et envoyé sur Telegram au
/// démarrage) : c'est ce compte que l'admin doit déclarer admin dans
/// `users/{uid}` (champ `isadmin: true`), sinon firestore.rules refuse au
/// serveur la lecture des commandes et l'écriture des statuts.
String serverAuthUid = '';

/// Connexion du serveur : firestore.rules exige `request.auth != null` partout.
/// Session anonyme persistante (même UID à chaque redémarrage tant que les
/// données de l'app ne sont pas effacées).
Future<void> ensureServerSignedIn() async {
  try {
    final auth = FirebaseAuth.instance;
    final user = auth.currentUser ?? (await auth.signInAnonymously()).user;
    serverAuthUid = user?.uid ?? '';
    debugPrint('[Auth] Serveur connecté, uid=$serverAuthUid');
  } catch (e) {
    debugPrint('[Auth] Connexion impossible : $e');
  }
}

CollectionReference collectionRef =
FirebaseFirestore.instance.collection('Transact');
CollectionReference sms =
FirebaseFirestore.instance.collection('sms');
CollectionReference collectionperson =
FirebaseFirestore.instance.collection('member');
CollectionReference collectionmessage_person =
FirebaseFirestore.instance.collection('message');
CollectionReference collectionmessage_sms =
FirebaseFirestore.instance.collection('SMS');

String ?idphone = '00000';
final FirebaseFirestore firestore = FirebaseFirestore.instance;

// final Telephony telephony = Telephony.instance;
// List<SmsMessage> _smsMessages = [];
bool _smsPermissionGranted = false;
// List<QueryDocumentSnapshot<Map<String, dynamic>>>users = [];
QueryDocumentSnapshot<Map<String, dynamic>>? values ;

checkuser() async {
final result =  await FirebaseFirestore.instance
      .collection('member')
      .where("idphone", isEqualTo: idphone)
      .get().then((value) {
    print(value.docs.first['idphone']);
    values = value.docs.first ;
    print("value");
    print(values!["idphone"]);
    print(values!["isadmin"]);
    return values!["isadmin"];
    },);
if(result!=null){
  print("result");
  print(result);
  print("result");
  return result;
}
return result;
}


Future<bool> checkMemberExists(String memberName) async {
  try {
    CollectionReference collectionPerson =
    FirebaseFirestore.instance.collection('member');
    QuerySnapshot querySnapshot = await collectionPerson
        .where('idphone', isEqualTo: memberName.trim()) // trim() pour enlever les espaces
        .limit(1) // Optimisation : on ne prend que le premier résultat
        .get();
    print("verification dans la bd");
    print(querySnapshot.docs.isEmpty);
    if(querySnapshot.docs.isEmpty){
  await  collectionPerson.add({
        "idphone" :memberName,
        "statut" : "En ligne",
        "isadmin" : "false",

      });
  checkuser();
    }else{
      checkuser();
    }
    print("verification dans la bd");

    return querySnapshot.docs.isNotEmpty;
  } on FirebaseException catch (e) {
    print('Erreur Firebase: ${e.code} - ${e.message}');
    return false;
  } catch (e) {
    print('Erreur inattendue: $e');
    return false;
  }
}

/// Point d'entrée du service en arrière-plan.
/// Doit être une fonction de top-level annotée vm:entry-point.
@pragma('vm:entry-point')
void onServiceStart(ServiceInstance service) async {
  // Le service tourne en arrière-plan — la vraie logique est dans Commandeview.
  // Ce callback suffit pour que Flutter Background Service garde le processus vivant.
}

Future<void> _initBackgroundService() async {
  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onServiceStart,
      autoStart: true,
      isForegroundMode: true,
      // Ne pas fournir de notificationChannelId personnalisé : le plugin ne
      // crée le canal de notification Android que lorsque cette valeur est
      // null (il utilise alors son propre canal "FOREGROUND_DEFAULT" qu'il
      // crée lui-même). Avec un ID personnalisé, il saute la création du
      // canal, ce qui fait planter startForeground en boucle
      // (CannotPostForegroundServiceNotificationException : canal inexistant).
      initialNotificationTitle: 'Recharge 237',
      initialNotificationContent: 'Service actif…',
      foregroundServiceNotificationId: 237,
    ),
    iosConfiguration: IosConfiguration(autoStart: false),
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Le plugin Gradle google-services n'est plus appliqué : c'est cet appel qui
  // crée l'app Firebase par défaut avec les options de production ci-dessus.
  // On garde la tolérance "duplicate-app" (relance à chaud, ancienne install).
  // (Firebase.apps est toujours vide à ce stade côté Dart, donc ce n'est
  // pas un indicateur fiable pour éviter l'appel.)
  try {
    await Firebase.initializeApp(options: android);
  } on FirebaseException catch (e) {
    if (e.code != 'duplicate-app') rethrow;
  }
  await ensureServerSignedIn();
  await PermissionHelper.requestAll();
  await _initBackgroundService();
  AppControllers.initialize();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  Future<void> checkSmsPermissions() async {
    print("Vérification des permissions SMS");
    bool? permissionsGranted = await  c.telephony?.requestPhoneAndSmsPermissions;
    // final bool? permissionsGranted = await telephony.requestSmsPermissions;

    setState(() {
      _smsPermissionGranted = permissionsGranted ?? false;
    });

    if (_smsPermissionGranted) {
      // _listenToIncomingSms();
      // _loadExistingSms();
    } else {
      print("Permissions SMS non accordées");
    }
  }

  // Future<void> _loadExistingSms() async {
  //   try {
  //     final List<SmsMessage> messages = await telephony.getInboxSms(
  //       columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
  //       sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
  //     );
  //
  //     setState(() {
  //       _smsMessages = messages;
  //     });
  //   } catch (e) {
  //     print("Erreur lors du chargement des SMS: $e");
  //   }
  // }

  // void _listenToIncomingSms() {
  //   telephony.listenIncomingSms(
  //     onNewMessage: (SmsMessage message) {
  //       print("Nouveau SMS reçu: ${message.body}");
  //
  //       // Ajouter à Firestore
  //       sms.add({
  //         'sender': message.address,
  //         'message': message.body,
  //         'date': DateTime.now().toString(),
  //         'deviceId': idphone,
  //       }).then((value) {
  //         print("SMS enregistré dans Firestore");
  //       }).catchError((error) {
  //         print("Erreur Firestore: $error");
  //       });
  //
  //       setState(() {
  //         _smsMessages.insert(0, message); // Ajoute en tête de liste
  //       });
  //     },
  //     listenInBackground: false,
  //   );
  // }

  Future<void> _initializeNotifications() async {
    // await NotificationService.initialize();
  }

  @override
  void initState() {
    super.initState();

    checkSmsPermissions();
  }

  @override
  Widget build(BuildContext context) {
    return Sizer(
      builder: (context, orientation, deviceType) {
        return GetMaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Recharge237 AppServeur',
          theme: ThemeData.light(),
          home: Commandeview(),
         // home: UssdScreen(),
        // home: RealtimeSmsReaderScreen(),
        //  home: HomePage(),
        );
      },
    );
  }
}