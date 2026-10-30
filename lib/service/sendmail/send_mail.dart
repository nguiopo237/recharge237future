import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server/gmail.dart';
import 'package:http/http.dart' as http;

class SendEmail {
  static Future<void> updateValueInFirestore(String collectionName,
      String documentId, String fieldName, dynamic newValue) async {
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

  static sendMyMail(
      {required String recipientEmail,
      String phoneNumber = "",
      bool update = false}) async {
    String username = 'camillenguiopo@gmail.com';
    String password = 'nsrp httq pxbw hhwb';

    final smtpServer = gmail(username, password);

    print("recipientEmail");
    print(recipientEmail);
    print(phoneNumber);
    print("recipientEmail");

    // Formatage de la date
    final now = DateTime.now();
    final formattedDate = "${now.day} ${_getMonthName(now.month)} ${now.year}";
    final formattedTime =
        "${now.hour}:${now.minute.toString().padLeft(2, '0')}";
    RegExp regExp = RegExp(r'\b\d{9}\b');
    String? numeroTelephone = regExp.stringMatch(recipientEmail);
    RegExp regExpdate =
        RegExp(r'\b(\d{2}/\d{2}/\d{2}\s\d{2}:\d{2}\s(?:AM|PM))\b');
    RegExp regExpDateSeule = RegExp(r'\b(\d{2}/\d{2}/\d{2})\b');
    RegExp regExpheure = RegExp(r'\b\d{2}:\d{2}\s(?:AM|PM)\b');
    String? dateHeureComplete = regExpdate.stringMatch(recipientEmail);
    String? dateSeule = regExpDateSeule.stringMatch(recipientEmail);
    String? heureComplete = regExpheure.stringMatch(recipientEmail);
    int result = 0;

    RegExp regExptransact = RegExp(r'TransactionID is (\d+)');
    String transactionId =
        regExptransact.firstMatch(recipientEmail)?.group(1) ?? '';

    RegExp regExpTransactionID = RegExp(
        r'TransactionID (\d+), (\d{2}-\d{2}-\d{4}) at (\d{2}:\d{2}:\d{2})');
    var transactionDetails = regExpTransactionID.firstMatch(recipientEmail);
    String transactionID = transactionDetails?.group(1) ?? '';
    String date = transactionDetails?.group(2) ?? '';
    String time = transactionDetails?.group(3) ?? '';

    RegExp regExpost = RegExp(r'- ([A-Z0-9_]+)');
    String codePOS = regExpost.firstMatch(recipientEmail)?.group(1) ?? '';

    RegExp regExpAmount = RegExp(r'amount is ([\d.,]+) FCFA');
    RegExp regExpAmountfailed = RegExp(r'send ([\d.,]+) FCFA');
    RegExp regExpAmounts = RegExp(r'Amount is ([\d,.]+) FCFA');
    String amount = regExpAmount.firstMatch(recipientEmail)?.group(1) ?? '';
    String amountf =
        regExpAmountfailed.firstMatch(recipientEmail)?.group(1) ?? '';
    String amounts = regExpAmounts.firstMatch(recipientEmail)?.group(1) ?? '';

    // Extraire le solde
    RegExp regExpBalance = RegExp(r'balance is ([\d.,]+) FCFA');
    RegExp regExpBalances = RegExp(r'balance is\s*(\d+(?:,\d+)*(?:\.\d+)?)');
    String balance = regExpBalance.firstMatch(recipientEmail)?.group(1) ?? '';
    String balances = regExpBalances.firstMatch(recipientEmail)?.group(1) ?? '';

    print("Montant de recharge: $amount FCFA");
    print("Montant de rechargef: $amountf FCFA");
    print("Montant de recharges: $codePOS FCFA");
    print("Solde actuel: $balance FCFA");

    print("Numéro de téléphone extrait: $numeroTelephone");
    print("Date complète (avec heure): $dateHeureComplete");
    print("Date seule: $dateSeule");
    print("Date seule: $balance");
    print("resultat");
    print(recipientEmail.contains("POS") && recipientEmail.contains("DSM"));
    print(recipientEmail.contains("DSM"));
    print("resultat");
    if (recipientEmail.contains("MASTER") ||
        recipientEmail.contains("POS") && recipientEmail.contains("DSM")) {
      print("ce messages est pour la dsm ");
      print("voici sa balance: $balance");
      print("voici sa balance: $balances");
      SendEmail.updateValueInFirestore(
          "solde", "jNIO5y2lj8s9PiTSV4cU", "dsm", balances);
    } else {
      print("ce messages est pour la post");
      SendEmail.updateValueInFirestore(
          "solde", "MrLq19BDw8Jng5hzXnSx", "soldepost", balance);
    }
    print("mail envoyer seul");

    // HTML amélioré avec l'interface attractive
    final htmlContent = """
    <!DOCTYPE html>
    <html lang="fr">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Confirmation de Recharge 237</title>
        <style>
            body {
                font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
                background-color: #f5f7fa;
                margin: 0;
                padding: 0;
            }
            .email-container {
                max-width: 600px;
                margin: 0 auto;
                background: white;
                border-radius: 15px;
                overflow: hidden;
                box-shadow: 0 5px 15px rgba(0,0,0,0.1);
            }
            .header {
                background: linear-gradient(135deg, #6C63FF 0%, #FF6584 100%);
                padding: 30px 20px;
                text-align: center;
                color: white;
            }
            .header h1 {
                margin: 0;
                font-size: 28px;
                font-weight: 700;
            }
            .icon {
                font-size: 50px;
                margin-bottom: 15px;
                display: inline-block;
            }
            .content {
                padding: 30px;
            }
            .amount {
                font-size: 36px;
                font-weight: 700;
                color: #6C63FF;
                text-align: center;
                margin: 20px 0;
                padding-bottom: 15px;
                border-bottom: 2px dashed #e0e0e0;
            }
            .details {
                background: #f8f9fa;
                border-radius: 10px;
                padding: 20px;
                margin: 25px 0;
            }
            .detail-row {
                display: flex;
                justify-content: space-between;
                margin-bottom: 10px;
                padding-bottom: 10px;
                border-bottom: 1px dashed #e0e0e0;
            }
            .detail-row:last-child {
                border-bottom: none;
                margin-bottom: 0;
                padding-bottom: 0;
            }
            .detail-label {
                color: #6c757d;
                font-weight: 500;
            }
            .detail-value {
                color: #2F2E41;
                font-weight: 600;
            }
            .footer {
                text-align: center;
                padding: 20px;
                color: #6c757d;
                font-size: 12px;
                background: #f8f9fa;
            }
        </style>
    </head>
    <body>
        <div class="email-container">
            <div class="header">
                <div class="icon">🎉</div>
                <h1>Recharge Effectuée !</h1>
            </div>
            
            <div class="content">
                <p style="text-align: center; color: #4a5568; line-height: 1.6;">
                    Votre recharge a été effectuée avec succès. Voici les détails de votre transaction.
                </p>
                
                <div class="amount">$amount FCFA</div>
                
                <div class="details">
                    <div class="detail-row">
                        <span class="detail-label">Date </span>
                        <span class="detail-value"> : $dateSeule</span>
                    </div>
                    <div class="detail-row">
                        <span class="detail-label">Heure </span>
                        <span class="detail-value"> : $heureComplete</span>
                    </div>
                    <div class="detail-row">
                        <span class="detail-label">Numéro </span>
                        <span class="detail-value"> : $numeroTelephone</span>
                    </div>
                    <div class="detail-row">
                        <span class="detail-label">ID Transaction : </span>
                        <span class="detail-value">$transactionId</span>
                    </div>
                </div>
                
                
                 <div class="content">
                <p style="text-align: center; color: #4a5568; line-height: 1.6;">
                    Solde de Credit restant à l'issue de cette transaction
                </p>
                
                <div class="amount">$balance FCFA</div>
                
                
                <p style="text-align: center; margin-top: 30px;">
                    <a href="#" style="display: inline-block; background: linear-gradient(135deg, #6C63FF 0%, #FF6584 100%); 
                    color: white; padding: 12px 30px; border-radius: 50px; text-decoration: none; font-weight: 600;">
                        Voir l'historique 
                    </a>
                </p>
            </div>
            
            <div class="footer">
                © ${now.year} Recharge 237 - Tous droits réservés
            </div>
        </div>
    </body>
    </html>
    """;
    final htmlContent9 = """
    <!DOCTYPE html>
    <html lang="fr">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Confirmation de Recharge 237</title>
        <style>
            body {
                font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
                background-color: #f5f7fa;
                margin: 0;
                padding: 0;
            }
            .email-container {
                max-width: 600px;
                margin: 0 auto;
                background: white;
                border-radius: 15px;
                overflow: hidden;
                box-shadow: 0 5px 15px rgba(0,0,0,0.1);
            }
            .header {
                background: linear-gradient(135deg, #6C63FF 0%, #FF6584 100%);
                padding: 30px 20px;
                text-align: center;
                color: white;
            }
            .header h1 {
                margin: 0;
                font-size: 28px;
                font-weight: 700;
            }
            .icon {
                font-size: 50px;
                margin-bottom: 15px;
                display: inline-block;
            }
            .content {
                padding: 30px;
            }
            .amount {
                font-size: 36px;
                font-weight: 700;
                color: #6C63FF;
                text-align: center;
                margin: 20px 0;
                padding-bottom: 15px;
                border-bottom: 2px dashed #e0e0e0;
            }
            .details {
                background: #f8f9fa;
                border-radius: 10px;
                padding: 20px;
                margin: 25px 0;
            }
            .detail-row {
                display: flex;
                justify-content: space-between;
                margin-bottom: 10px;
                padding-bottom: 10px;
                border-bottom: 1px dashed #e0e0e0;
            }
            .detail-row:last-child {
                border-bottom: none;
                margin-bottom: 0;
                padding-bottom: 0;
            }
            .detail-label {
                color: #6c757d;
                font-weight: 500;
            }
            .detail-value {
                color: #2F2E41;
                font-weight: 600;
            }
            .footer {
                text-align: center;
                padding: 20px;
                color: #6c757d;
                font-size: 12px;
                background: #f8f9fa;
            }
        </style>
    </head>
    <body>
        <div class="email-container">
            <div class="header">
                <div class="icon">🎉</div>
                <h1>Recharge Effectuée !</h1>
            </div>
            
            <div class="content">
                <p style="text-align: center; color: #4a5568; line-height: 1.6;">
                    Votre recharge a été effectuée avec succès. Voici les détails de votre transaction.
                </p>
                
                <div class="amount">$amount FCFA</div>
                
                <div class="details">
                    <div class="detail-row">
                        <span class="detail-label">Date </span>
                        <span class="detail-value"> : $dateSeule</span>
                    </div>
                    <div class="detail-row">
                        <span class="detail-label">Heure </span>
                        <span class="detail-value"> : $heureComplete</span>
                    </div>
                    <div class="detail-row">
                        <span class="detail-label">Numéro </span>
                        <span class="detail-value"> : $numeroTelephone</span>
                    </div>
                    <div class="detail-row">
                        <span class="detail-label">ID Transaction : </span>
                        <span class="detail-value">$transactionId</span>
                    </div>
                </div>
                
                
                 <div class="content">
                <p style="text-align: center; color: #4a5568; line-height: 1.6;">
                    Solde de Credit restant à l'issue de cette transaction
                </p>
                
                <div class="amount">$balance FCFA</div>
                
                
                <p style="text-align: center; margin-top: 30px;">
                    <a href="#" style="display: inline-block; background: linear-gradient(135deg, #6C63FF 0%, #FF6584 100%); 
                    color: white; padding: 12px 30px; border-radius: 50px; text-decoration: none; font-weight: 600;">
                        Voir l'historique 
                    </a>
                </p>
            </div>
            
            <div class="footer">
                © ${now.year} Recharge 237 - Tous droits réservés
            </div>
        </div>
    </body>
    </html>
    """;
    final htmlContenterror = """
    <!DOCTYPE html>
    <!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Erreur de Recharge</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
        }
        
        body {
            background-color: #f5f7fa;
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
            padding: 20px;
        }
        
        .error-container {
            max-width: 500px;
            width: 100%;
            background: white;
            border-radius: 15px;
            overflow: hidden;
            box-shadow: 0 5px 15px rgba(0,0,0,0.1);
        }
        
        .header {
            background: linear-gradient(135deg, #FF6584 0%, #FF416C 100%);
            padding: 30px 20px;
            text-align: center;
            color: white;
        }
        
        .header h1 {
            margin: 0;
            font-size: 28px;
            font-weight: 700;
        }
        
        .icon {
            font-size: 50px;
            margin-bottom: 15px;
            display: inline-block;
        }
        
        .content {
            padding: 30px;
        }
        
        .error-message {
            background: #fff5f5;
            border-left: 4px solid #FF6584;
            border-radius: 8px;
            padding: 20px;
            margin-bottom: 25px;
            color: #c53030;
            font-weight: 500;
        }
        
        .details {
            background: #f8f9fa;
            border-radius: 10px;
            padding: 20px;
            margin: 25px 0;
        }
        
        .detail-row {
            display: flex;
            justify-content: space-between;
            margin-bottom: 10px;
            padding-bottom: 10px;
            border-bottom: 1px dashed #e0e0e0;
        }
        
        .detail-row:last-child {
            border-bottom: none;
            margin-bottom: 0;
            padding-bottom: 0;
        }
        
        .detail-label {
            color: #6c757d;
            font-weight: 500;
        }
        
        .detail-value {
            color: #2F2E41;
            font-weight: 600;
        }
        
        .balance-amount {
            font-size: 24px;
            font-weight: 700;
            color: #FF6584;
            text-align: center;
            margin: 20px 0;
            padding-bottom: 15px;
            border-bottom: 2px dashed #e0e0e0;
        }
        
        .actions {
            display: flex;
            justify-content: center;
            gap: 15px;
            margin-top: 30px;
        }
        
        .btn {
            display: inline-block;
            padding: 12px 25px;
            border-radius: 50px;
            text-decoration: none;
            font-weight: 600;
            cursor: pointer;
            transition: all 0.3s ease;
            text-align: center;
        }
        
        .btn-primary {
            background: linear-gradient(135deg, #6C63FF 0%, #4A45E1 100%);
            color: white;
            border: none;
        }
        
        .btn-secondary {
            background: #f1f1f1;
            color: #4a5568;
            border: 1px solid #e0e0e0;
        }
        
        .btn:hover {
            transform: translateY(-2px);
            box-shadow: 0 5px 15px rgba(0,0,0,0.1);
        }
        
        .footer {
            text-align: center;
            padding: 20px;
            color: #6c757d;
            font-size: 12px;
            background: #f8f9fa;
        }
    </style>
</head>
<body>
    <div class="error-container">
        <div class="header">
            <div class="icon">⚠️</div>
            <h1>Recharge Échouée</h1>
        </div>
        
        <div class="content">
            <div class="error-message">    
                Échec de l'envoi de $amountf FCFA. Le solde du compte est insuffisant. 
                Le solde du compte doit être suffisant pour payer les frais de transaction et le montant demandé.
            </div>
            
            <div class="details">
                <div class="detail-row">
                    <span class="detail-label"> Montant demandé </span>
                    <span class="detail-value"> : $amountf FCFA</span>
                </div>
                <div class="detail-row">
                    <span class="detail-label">  Date  </span>
                    <span class="detail-value">  :  $formattedDate  </span>
                </div>
                <div class="detail-row">
                    <span class="detail-label">Heure</span>
                    <span class="detail-value">  : $formattedTime </span>
                </div>
            </div>
            
            <p style="text-align: center; color: #4a5568; line-height: 1.6;">
                Solde actuel de votre compte
            </p>
            
            <div class="balance-amount">$balance FCFA</div>
            
            <div class="actions">
                <button class="btn btn-primary" onclick="rechargerCompte()">Recharger mon compte</button>
                <button class="btn btn-secondary" onclick="retourAccueil()">Retour à l'accueil</button>
            </div>
        </div>
        
        <div class="footer">
            ©  Recharge 237 - Tous droits réservés
        </div>
    </div>

    <script>
        function rechargerCompte() {
            alert("Redirection vers la page de recharge du compte...");
            // Ici, vous pouvez rediriger vers la page de recharge
        }
        
        function retourAccueil() {
            alert("Retour à la page d'accueil...");
            // Ici, vous pouvez rediriger vers la page d'accueil
        }
    </script>
</body>
</html>
    """;
    final htmlContentpost = """
    <!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Transfert Réussi</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
        }
        
        body {
            background-color: #f5f7fa;
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
            padding: 20px;
        }
        
        .success-container {
            max-width: 500px;
            width: 100%;
            background: white;
            border-radius: 15px;
            overflow: hidden;
            box-shadow: 0 5px 15px rgba(0,0,0,0.1);
        }
        
        .header {
            background: linear-gradient(135deg, #6C63FF 0%, #4CAF50 100%);
            padding: 30px 20px;
            text-align: center;
            color: white;
        }
        
        .header h1 {
            margin: 0;
            font-size: 28px;
            font-weight: 700;
        }
        
        .icon {
            font-size: 50px;
            margin-bottom: 15px;
            display: inline-block;
        }
        
        .content {
            padding: 30px;
        }
        
        .success-message {
            text-align: center;
            color: #4a5568;
            line-height: 1.6;
            margin-bottom: 20px;
        }
        
        .amount {
            font-size: 36px;
            font-weight: 700;
            color: #4CAF50;
            text-align: center;
            margin: 20px 0;
            padding-bottom: 15px;
            border-bottom: 2px dashed #e0e0e0;
        }
        
        .details {
            background: #f8f9fa;
            border-radius: 10px;
            padding: 20px;
            margin: 25px 0;
        }
        
        .detail-row {
            display: flex;
            justify-content: space-between;
            margin-bottom: 10px;
            padding-bottom: 10px;
            border-bottom: 1px dashed #e0e0e0;
        }
        
        .detail-row:last-child {
            border-bottom: none;
            margin-bottom: 0;
            padding-bottom: 0;
        }
        
        .detail-label {
            color: #6c757d;
            font-weight: 500;
        }
        
        .detail-value {
            color: #2F2E41;
            font-weight: 600;
        }
        
        .balance-section {
            text-align: center;
            margin: 25px 0;
        }
        
        .balance-label {
            color: #4a5568;
            margin-bottom: 10px;
        }
        
        .balance-amount {
            font-size: 24px;
            font-weight: 700;
            color: #6C63FF;
        }
        
        .actions {
            display: flex;
            justify-content: center;
            gap: 15px;
            margin-top: 30px;
        }
        
        .btn {
            display: inline-block;
            padding: 12px 25px;
            border-radius: 50px;
            text-decoration: none;
            font-weight: 600;
            cursor: pointer;
            transition: all 0.3s ease;
            text-align: center;
            border: none;
        }
        
        .btn-primary {
            background: linear-gradient(135deg, #6C63FF 0%, #4A45E1 100%);
            color: white;
        }
        
        .btn-secondary {
            background: #f1f1f1;
            color: #4a5568;
            border: 1px solid #e0e0e0;
        }
        
        .btn:hover {
            transform: translateY(-2px);
            box-shadow: 0 5px 15px rgba(0,0,0,0.1);
        }
        
        .footer {
            text-align: center;
            padding: 20px;
            color: #6c757d;
            font-size: 12px;
            background: #f8f9fa;
        }
    </style>
</head>
<body>
    <div class="success-container">
        <div class="header">
            <div class="icon">✅</div>
            <h1>Transfert Réussi !</h1>
        </div>
        
        <div class="content">
            <p class="success-message">
                Votre transfert de crédit a été traité avec succès et rechargé sur la sim post.
            </p>
            
            <div class="amount">$amounts FCFA</div>
            
            <div class="details">
                <div class="detail-row">
                    <span class="detail-label">Destinataire : </span>
                    <span class="detail-value">$numeroTelephone</span>
                </div>
                <div class="detail-row">
                    <span class="detail-label">Point de service : </span>
                    <span class="detail-value"> $codePOS </span>
                </div>
                <div class="detail-row">
                    <span class="detail-label">Date :  </span>
                    <span class="detail-value">$date</span>
                </div>
                <div class="detail-row">
                    <span class="detail-label">Heure : </span>
                    <span class="detail-value">$time</span>
                </div>
                <div class="detail-row">
                    <span class="detail-label">ID Transaction : </span>
                    <span class="detail-value">$transactionID</span> 
                </div>
            </div>
            
            <div class="balance-section">
                <div class="balance-label">Votre nouveau solde</div>
                <div class="balance-amount">$balance FCFA</div>
            </div>
            
            <div class="actions">
                <button class="btn btn-primary" onclick="voirHistorique()">Voir l'historique</button>
                <button class="btn btn-secondary" onclick="nouveauTransfert()">Nouveau transfert</button>
            </div>
        </div>
        
        <div class="footer">
            © 2025 Recharge 237 - Tous droits réservés
        </div>
    </div>

    <script>
        function voirHistorique() {
            alert("Redirection vers l'historique des transactions...");
            // Ici, vous pouvez rediriger vers la page d'historique
        }
        
        function nouveauTransfert() {
            alert("Lancement d'un nouveau transfert...");
            // Ici, vous pouvez rediriger vers le formulaire de transfert
        }
    </script>
</body>
</html>
    """;

    final message = Message()
      ..from = Address(username, 'Recharge 237')
      ..recipients.add("recharge2370@gmail.com")
      ..subject = 'Confirmation de recharge - $amount FCFA - $formattedDate'
      ..text =
          'Confirmation de recharge\n\nVous avez effectué une recharge de $amount FCFA le $formattedDate à $formattedTime.\n\n Numéro: $phoneNumber\nID Transaction: TRX-${now.millisecondsSinceEpoch.toString().substring(5)}\n\nMerci pour votre confiance!'
      ..html = recipientEmail.contains("Failed")
          ? htmlContenterror
          : recipientEmail.contains("top-up")
              ? htmlContent
              : htmlContentpost;

    try {
      final sendReport = await send(message, smtpServer);
      print('Message sent: $sendReport');
      return true;
    } on MailerException catch (e) {
      print('Message not sent.');
      for (var p in e.problems) {
        print('Problem: ${p.code}: ${p.msg}');
      }
      return false;
    }
  }

  static Future<void> sendMessagewithtelegram({
    required String message,
    List<String>? chatIds,
  }) async {
    try {
      // Token du bot (à externaliser pour la sécurité)
      const botToken = '8465693687:AAGSAKJ2BXv8IG33lAbY9mgGIsbTz9Tm1o8';
      const botTokens = '7650275482:AAGI3zb-jkk7VIFrlL2LgKVrFGOVQoM8XtI';

      // Liste des chat IDs par défaut
      final defaultChatIds = ['7402111158', '1470497195', '6039338540'];
      final targetChatIds = chatIds ?? defaultChatIds;

      // Encoder le message pour l'URL
      final encodedMessage = Uri.encodeComponent(message);

      // Envoyer à tous les chat IDs
      for (final chatId in targetChatIds) {
        final url =
            Uri.parse('https://api.telegram.org/bot$botTokens/sendMessage'
                '?chat_id=$chatId'
                '&text=$encodedMessage');

        final response = await http.post(url);

        if (response.statusCode == 200) {
          print('Message envoyé avec succès à $chatId: ${response.body}');
        } else {
          print(
              'Erreur pour $chatId: ${response.statusCode} - ${response.body}');
        }

        // Petite pause pour éviter de surcharger l'API
        await Future.delayed(const Duration(milliseconds: 100));
      }
    } catch (e) {
      print('Erreur lors de l\'envoi du message: $e');
      // Vous pourriez relancer l'erreur ou la gérer selon vos besoins
      // throw e;
    }
  }

  // Helper function to get month name
  static String _getMonthName(int month) {
    const months = [
      'janvier',
      'février',
      'mars',
      'avril',
      'mai',
      'juin',
      'juillet',
      'août',
      'septembre',
      'octobre',
      'novembre',
      'décembre'
    ];
    return months[month - 1];
  }
}
