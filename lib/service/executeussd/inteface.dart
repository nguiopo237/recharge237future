import 'package:flutter/material.dart';
import 'natifplace.dart';





class UssdScreen extends StatefulWidget {
  @override
  _UssdScreenState createState() => _UssdScreenState();
}

class _UssdScreenState extends State<UssdScreen> {
  List<String> ussdMessages = [];
  String currentMessage = '';

  @override
  void initState() {
    super.initState();

    // Écouter les messages USSD
    UssdLauncher.listenToUssdMessages((String message) {
      print("Nouveau message USSD: $message");

      setState(() {
        ussdMessages.add(message);
        currentMessage = message;
      });

      // Traiter le message selon votre logique métier
      processUssdResponse(message);
    });
  }

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

  Future<void> sendUssd() async {
    String code = "*825#";
    int simId = 0;

    print("Envoi de USSD: $code sur SIM $simId");

    String? response = await UssdLauncher.sendUssdRequest(
      ussdCode: code,
      subscriptionId: simId,
    );

    if (response != null) {
      print("Réponse initiale: $response");
    }else{
      print("pas de vision: $response");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("USSD Messages")),
      body: WillPopScope(
        onWillPop: () async{
        return false; },

        child: Column(
          children: [
            ElevatedButton(
              onPressed: sendUssd,
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
            Expanded(
              child: ListView.builder(
                itemCount: ussdMessages.length,
                itemBuilder: (context, index) {
                  final data = ussdMessages[index];
                  return ListTile(
                    title: Text(data),
                    subtitle: Text("Message ${data}"),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}