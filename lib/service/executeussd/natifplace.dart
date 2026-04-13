import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:ussd_launcher/ussd_launcher.dart';

import '../fonctionfire.dart';

class UssdLaunchers {
  static const MethodChannel _channel = MethodChannel('ussd_launcher');

  // Variable pour stocker le callback
  static Function(String)? _ussdMessageCallback;

  // Initialisation du listener
  static void _initializeListener() {
    _channel.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'onUssdMessageReceived') {
        final String message = call.arguments;
        print("Message USSD reçu dans le handler: $message");

        // Appeler le callback si défini
        if (_ussdMessageCallback != null) {
          _ussdMessageCallback!(message);
        }
      }
      return null;
    });
  }

  // Méthode pour écouter les messages USSD
  static void listenToUssdMessages(Function(String) onMessageReceived) {
    _ussdMessageCallback = onMessageReceived;
    _initializeListener();
    print("voici le message recu");
    print(_ussdMessageCallback);
  }

  // Pour lancer une requête USSD

  static Future<String?> sendUssdRequest({

    required String ussdCode,
    required int subscriptionId,
    String? documentid,
    int? statut = 1,
  }) async {



    if (isRunning){
      isRunning = false;
    }else{
      isRunning = true;
    }


    if(isRunning==true){

    try {
      print('debut');
      UssdLauncher.setUssdMessageListener((message) {
        print("message flutter  $message");
        if (message.contains("Now")) {
          if (statut == 1) {
            updateValueInFirestore("Transact", documentid!, "status", "3");
            FirebaseFirestore.instance
                .collection('Transact')
                .doc(documentid)
                .update({
              'item': [message],
            })
                .then((_) {
              print('Tableau ajouté avec succès');
            })
                .catchError((error) {
              print('Erreur: $error');
            });

          } else {
            updateValueInFirestore("Transact", documentid!, "status", "10");
            FirebaseFirestore.instance
                .collection('Transact')
                .doc(documentid)
                .update({
              'item': [message],
            })
                .then((_) {
              print('Tableau ajouté avec succès');
            })
                .catchError((error) {
              print('Erreur: $error');
            });
          }
        }
        // Traitez le message ici (mettez à jour votre UI, etc.)
        // Ce callback sera appelé à chaque fois qu'un nouveau message USSD arrive
      });
      final String? response = await _channel.invokeMethod('multisessionUssd', {
        'ussdCode': ussdCode,
        'slotIndex': subscriptionId,
        'options': ["2006"],
      });
      print("resultat de la reponse 2.0 ${response}");
      return response;
    } catch (e) {
      print('Erreur: $e');
    } finally {
      isRunning = false;
      print('finish place');
      if (statut == 1) {
        print('pas de place');
        updateValueInFirestore("Transact", documentid!, "status", "3");
      } else if (statut == 9) {
        print('pas de place');
        updateValueInFirestore("Transact", documentid!, "status", "10");
      }
    }
    }
  }
}

class UssdMessage {
  final String content;
  final int step;
  final DateTime timestamp;
  final String? id;

  UssdMessage({
    required this.content,
    required this.step,
    this.id,
    required this.timestamp,
  });
}
