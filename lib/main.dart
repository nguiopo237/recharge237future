import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:projettest/service/controlleur/initcontrolleur.dart';
import 'package:projettest/service/controlleur/transact_controlleur.dart';
import 'package:projettest/service/controlleur/widget_controlleur.dart';
import 'package:projettest/service/executeussd/inteface.dart';
import 'package:projettest/service/notification/notification_service.dart';
import 'package:projettest/service/view/readsms.dart';
import 'package:projettest/test.dart';
import 'package:projettest/testview.dart';
import 'package:projettest/view/pagecommande/viewcommande.dart';
import 'package:sizer/sizer.dart';
import 'package:unique_identifier/unique_identifier.dart';
// import 'package:another_telephony/telephony.dart';
import 'view/home/Home.dart';

FirebaseOptions android = FirebaseOptions(
  apiKey: "AIzaSyB0ZGRlxlr-uJS2Yn4bGzCfHqtDXKaJDao",
  appId: "1:221039842981:android:c66e4209200ee74c7e1f4c",
  messagingSenderId: "",
  projectId: "recharge237-8d1db",
);

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

Future<void> main() async {

  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: android);
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

    // final bool? permissionsGranted = await telephony.requestSmsPermissions;

    setState(() {

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
          title: 'Recharge 237',
          theme: ThemeData.light(),
          // home: Commandeview(),
         // home: UssdScreen(),
        // home: RealtimeSmsReaderScreen(),
         home: HomePage(),
        );
      },
    );
  }
}