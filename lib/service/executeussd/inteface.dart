import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:internet_connection_checker/internet_connection_checker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:ussd_launcher/ussd_launcher.dart';
// import 'package:ussd_launcher/ussd_launcher.dart%20';

import '../../component/widget/component_card.dart';
import '../../main.dart';
import '../../model/listnumbermode.dart';
import '../fonctionfire.dart';
import 'natifplace.dart';

class UssdScreen extends StatefulWidget {
  @override
  _UssdScreenState createState() => _UssdScreenState();
}

class _UssdScreenState extends State<UssdScreen> {
  List<String> ussdMessages = [];
  String currentMessage = '';

  // viewsimcard() async {
  //   List<Map<String, dynamic>> simCards = await UssdLauncher.getSimCards();
  //   for (var sim in simCards) {
  //     print('SIM: ${sim['displayName']} - ${sim['carrierName']}');
  //     print('Slot: ${sim['slotIndex']}, ID: ${sim['subscriptionId']}');
  //   }
  // }




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

  listenmessage({documentid, int ?statut}) {
    UssdLaunchers.listenToUssdMessages((String message) {
      print("Nouveau message USSD: $message");
      // if(message.contains("amount")){
      setState(() {
        // ussdMessages.clear();
        ussdMessages.add(message);
        currentMessage = message;
      });

      if(statut==1){
        updateValueInFirestore("Transact", documentid, "status", "3");
        UssdLauncher.removeUssdMessageListener();
      }else{
        updateValueInFirestore("Transact", documentid, "status", "10");
        UssdLauncher.removeUssdMessageListener();
      }
      // }

      // DocumentReference postRef = FirebaseFirestore.instance
      //     .collection('Transact')
      //     .doc(documentid);
      //  postRef.update({
      //   'item': FieldValue.arrayUnion([ussdMessage]),
      // });
      // UssdLauncher.removeUssdMessageListener();
      // Traiter le message selon votre logique métier
      processUssdResponse(message);
    });
  }

  @override
  void initState() {
    super.initState();
    // viewsimcard();
    // Écouter les messages USSD
    getConnectivity(context);
  }

  getdata(documentid, numerocam, amount, idtransact, type) async {
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



  late ScrollController _controller;

  void processUssdResponse(String message) {
    // Exemple : analyser la réponse USSD
    if (message.contains("solde")) {
      print("C'est un message de solde");
      // Extraire le montant, etc.
    } else if (message.contains("forfait")) {
      print("C'est un message de forfait");
    }
    // Ajoutez votre logique ici
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
  DateTime? _lastPressedAt;
  bool _isLoading = false;
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
    child:Scaffold(
        appBar: AppBar(title: Text("USSD Messages")),
        body: WillPopScope(
          onWillPop: () async {
            return false;
          },
          child: Column(
            children: [
              ElevatedButton(
                onPressed: () =>
                    sendUssd(statut: 1, number: "620046820", amount: "10"),
                child: Text("Envoyer USSD"),
              ),
              SizedBox(height: 20),
              Text(
                "Message actuel:",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Container(
                padding: EdgeInsets.all(16),
                margin: EdgeInsets.all(10),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.blue),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  currentMessage.isEmpty
                      ? "En attente de message..."
                      : currentMessage,
                  style: TextStyle(fontSize: 16),
                ),
              ),
              SizedBox(height: 20),
              Text(
                "Historique des messages:",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              // Expanded(
              //   child: ListView.builder(
              //     itemCount: ussdMessages.length,
              //     itemBuilder: (context, index) {
              //       final data = ussdMessages[index];
              //       return ListTile(
              //         title: Text(data),
              //         subtitle: Text("Message ${data}"),
              //       );
              //     },
              //   ),
              // ),
              Expanded(
                child: Padding(
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
                            // controller: _controller,
                            shrinkWrap: true,
                            itemCount: snapshot.data!.docs.length,
                            itemBuilder: (context, index) {
                              DocumentSnapshot document =
                                  snapshot.data!.docs[index];
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
              )
            ],
          ),
        ),
      ),
    ));
  }
}
