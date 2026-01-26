import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:otp/otp.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../../main.dart';


class APIORANGE{

  static Future<void> updateValueforfait({order,payToken,code}) async {
    print(payToken);
    try {
      QuerySnapshot querySnapshot = await FirebaseFirestore.instance
          .collection('Transact')
          .where('payToken', isEqualTo: payToken)
          .get();
      if (querySnapshot.docs.isNotEmpty) {
        // Mise à jour du statut
        await FirebaseFirestore.instance
            .collection('Transact')
            .doc(querySnapshot.docs.first.id)
            .update({'status': "11",'retry': "${code}"});

        print('Statut mis à jour avec succès');
      } else {
        print('Aucun document trouvé pour ce numéro Orange');
        print(querySnapshot.docs);
      }




    } catch (e) {
      print('Erreur lors de la modification de la valeur : $e');
    }
  }

  static Future<String?> getMomoToken({amount, num1, num2orange,bool init = true}) async {
    print("start with mtn");
    print(init);
    final url = Uri.parse('https://proxy.momoapi.mtn.com/collection/token/');
    String apiUserId = "3ac31112-55a6-4df2-b51d-83a6693c8535";
    String apiKey = "b852a1076df54dadbf93e14fa1a0436d";
    String subscriptionKey = "48f314fe512e4f99ab450cda504c5b26";
    final targetEnv = 'mtncameroon';

    final authStr = base64Encode(utf8.encode('$apiUserId:$apiKey'));

    // Solution 1: Corps vide (recommandé pour l'endpoint token)
    final requestBody = '';
    // OU Solution 2: Si vous devez envoyer des données
    // final requestBody = jsonEncode({'key': 'value'});

    final headers = {
      'Authorization': 'Basic $authStr',
      'Ocp-Apim-Subscription-Key': subscriptionKey,
      // 'X-Target-Environment': targetEnv,
      // 'Content-Type': 'application/json',
      // 'Accept': 'application/json',
      // "Content-Length": "1"
    };

    try {
      // Utiliser la chaîne directement, pas utf8.encode()
      final response = await http.post(url, headers: headers,);

      print("response.statusCode: ${response.statusCode}");

      if (response.statusCode == 200) {
        var uuid = Uuid();
        String v1 = uuid.v1();

        final data = jsonDecode(response.body);

      final  order1 = OTP.generateTOTPCodeString(
            'JBSWY3DPEHPK3PXP', DateTime.now().millisecondsSinceEpoch,
            interval: 20, algorithm: Algorithm.SHA512);

      if(init==true){
        createpayment(amount: amount,num1: num1,num2orange: num2orange,idtransact:order1 ,XReferenceId: v1,accesstoken: data['access_token'],subscriptionKey: subscriptionKey,targetEnv: targetEnv);

      }
        return data['access_token'];
      } else {
        print('Erreur token - Status: ${response.statusCode}, Body: ${response.body}');
        return null;
      }
    } catch (e) {
      print('Erreur de requête: $e');
      return null;
    }
  }
  static Future<String?> createpayment({amount, num1, num2orange, idtransact,accesstoken,subscriptionKey,targetEnv,XReferenceId,}) async {
    collectionRef.add({
      "amount": "${amount.toString()}",
      "idphone": idphone.toString(),
      "idtransact":idtransact.toString(),
      "numerocamtel":"${num1}",
      "numeroorange": "${num2orange}",
      "status":  num2orange=="679089505"? "1":"0",
      //"status":  "${num2orange=="679089505"?"1":"0"}",
      "heure":"${DateTime.now().toUtc()}",
      "accesstoken":accesstoken.toString(),
      "payToken":XReferenceId.toString(),
      "order":idtransact.toString(),
      "retry":"0",
    });

print("question");
    var headers = {
      'Ocp-Apim-Subscription-Key': "${subscriptionKey}",
      'Authorization': "Bearer ${accesstoken}",
      'X-Reference-Id': '${XReferenceId}',
      'X-Target-Environment': '${targetEnv}',
      'Content-Type': 'text/plain',
      // 'Accept': 'application/json',
      // "Content-Length": "1"
      };
    var request = http.Request('POST', Uri.parse('https://proxy.momoapi.mtn.com/collection/v1_0/requesttopay'));
    request.body = json.encode(
        {
          "amount": "${amount.toString()}",
          "currency": "XAF",
          "externalId": "679089505",
          "payer": {
            "partyIdType": "MSISDN",
            "partyId": "${num2orange}"
          },
          "payerMessage": "MoMo Market Payment",
          "payeeNote": "MoMo Market Payment"
        }
    );
    request.headers.addAll(headers);

    http.StreamedResponse response = await request.send();
    print("code de stream");
    print(response.stream.bytesToString());
    print(response.statusCode);
    print("code de stream");
    if (response.statusCode == 200||response.statusCode == 202 ) {

      print("paiement initier avec succes");
      print("code de stream");
      var data = await getstatutMOMO(XReferenceId: XReferenceId,targetEnv: targetEnv,subscriptionKey: subscriptionKey,accesstoken: accesstoken);;
      if(data!=null){
        print("updatre");
      }

       }
    else {
      print("response.reasonPhrase");
      print(response.reasonPhrase);
      print("response.reasonPhrase");
    }

  }


  static Future<String?> ?getstatutMOMO({targetEnv,subscriptionKey,accesstoken,XReferenceId}) async {
    print("verifie");
    var headers = {

    'Ocp-Apim-Subscription-Key': "${subscriptionKey}",
    'Authorization': "Bearer ${accesstoken}",
    'X-Target-Environment': '${targetEnv}',
    };
    var request = http.Request('GET', Uri.parse('https://proxy.momoapi.mtn.com/collection/v1_0/requesttopay/${XReferenceId}'));

    request.headers.addAll(headers);

    http.StreamedResponse response = await request.send();

    if (response.statusCode == 200) {
      print("reponse");
      print(await response.stream.bytesToString());
      print("reponse");
      // if(statut["data"]["status"]!="SUCCESSFULL"){
      //   print("en attente");
      //   print(statut["data"]["status"]);
      //   Future.delayed(Duration(seconds: 5),() {
      //     getstatut(accesstoken,payToken,order);
      //   },);
      //
      //
      // }else {
      //
      //   updateValueWithoutLogin(order,payToken);
      //
      //   // updateValueWithoutLogin("Transact",order,{'statut': '1'});
      //   Get.snackbar(backgroundColor: Colors.green,
      //       'Info',
      //       "Payement effectuer avec succes",
      //
      //       colorText: Colors.white,
      //
      //       snackPosition: SnackPosition.TOP, duration: Duration(seconds: 30)
      //   );
      //   // update(order.toString());
      //   // ScaffoldMessenger.of(context)
      //   //     .showSnackBar(const SnackBar(
      //   //     backgroundColor: Colors.green,
      //   //     content:
      //   //     Text("paiement effectuer avec succes")));
      //   // print("pas en attente");
      //
      //   return statut["data"]["status"];
    //  }
    }
    else {
    print(response.reasonPhrase);
    }

      }




  static gettokens({amount, num1, num2orange, required BuildContext context})async{
    print("start generate");
    print(amount);
    print(num1);
    print(num2orange);
    String order = "";

    order = OTP.generateTOTPCodeString(
        'JBSWY3DPEHPK3PXP', DateTime.now().millisecondsSinceEpoch,
        interval: 20, algorithm: Algorithm.SHA512);
    print(order);
    var headers = {
      'Content-Type': 'application/x-www-form-urlencoded',
      'Authorization': 'Basic Y3VnelVHWGNzX0Z3UnJfZjZwU0U3RlpsVkFzYTo4bjFGYkNTeV9QOFNLVDRmMkFjUnJmM1JiM0Vh'
    };
    var data = {
      'grant_type': 'client_credentials'
    };
    var dio = Dio();
    var response = await dio.request(
      'https://api-s1.orange.cm/token',
      options: Options(
        method: 'POST',
        headers: headers,
      ),
      data: data,
    );

    if (response.statusCode == 200) {
      print("json.encode(response.data)");
      print(json.encode(response.data));
      print("json.encode(response.data)");


      var data = json.encode(response.data);
      var see = jsonDecode(data);
      print("end");
      print(see["access_token"]);

      payrequest(see["access_token"],amount,num1,num2orange,order,context);
      print(order);
      return data;
      // return see["access_token"];
    }
    else {
      print(response.statusMessage);
    }
  }


  static payrequest(accesstoken,amount,num1,num2orange,order, BuildContext context)async{
    var headers = {
      'X-AUTH-TOKEN': 'WU5PVEVIRUFEMjpAWU5vVGVIRUBEMlBST0RBUEk=',
      'Authorization': 'Bearer ${accesstoken}'
    };
    var request = http.Request('POST', Uri.parse('https://api-s1.orange.cm/omcoreapis/1.0.2/mp/init'));
    // request.body = '''''';
    request.headers.addAll(headers);

    http.StreamedResponse response = await request.send();
    var data = await response.stream.bytesToString();
    var payyoken = jsonDecode(data);
    if (response.statusCode == 200) {
      print("payyoken");
      print(payyoken["data"]["payToken"]);
      print(accesstoken);
      print("payyoken");


      collectionRef.add({
        "amount": amount,
        "idphone": idphone,
        "idtransact": order,
        "numerocamtel":num1,
        "numeroorange": num2orange,
        "status":  num2orange=="691989964"||num2orange=="655868646"? "1":"0",
        "heure":"${DateTime.now()}",
        "accesstoken":accesstoken,
        "payToken":payyoken["data"]["payToken"],
        "order":order,
        "retry":"0",
      });


      startpayement(
        accesstoken: accesstoken,
        amount: amount,
        payToken: payyoken["data"]["payToken"],
        num1: num1,
        num2orange: num2orange,
        order: order,
        idphone: idphone,
        context: context,
      );
    }
    else {
      print(response.reasonPhrase);
    }
  }

  static startpayement(
      {accesstoken,
        idphone,
        payToken,
        amount,
        num1,
        num2orange,
        order, context})async
  {
    print("accesstoken");
    print(num2orange);
    print(accesstoken);
    print("accesstoken");

    var headers = {
      'X-AUTH-TOKEN': 'WU5PVEVIRUFEMjpAWU5vVGVIRUBEMlBST0RBUEk=',
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${accesstoken}'
    };
    var request = http.Request('POST', Uri.parse('https://api-s1.orange.cm/omcoreapis/1.0.2/mp/pay'));
    request.body = json.encode({
      "amount": amount,
      "notifUrl": "https://www.y-note.cm/notification",
      "payToken": payToken,
      "description": "Credit de communication sur R237",
      "subscriberMsisdn": num2orange,
      "pin": "7859",
      "channelUserMsisdn": "659925095",
      "OrderId": order
    });
    request.headers.addAll(headers);

    http.StreamedResponse response = await request.send();

    if (response.statusCode == 200) {
      // if(idphone =="d947dde024156a0e"||idphone =="ca1d476160210d3b"){
      //   updateValueWithoutLogin(order,payToken);
      // }
      // print(await response.stream.bytesToString());
      var data = await getstatut(accesstoken,payToken,order);
      if(data!=null){
        print("updatre");
      }
    }
    else {
      print(response.reasonPhrase);
    }














    // var headers = {
    //   'X-AUTH-TOKEN': 'WU5PVEVIRUFEMjpAWU5vVGVIRUBEMlBST0RBUEk',
    //   'Content-Type': 'application/json',
    //   'Authorization': 'Bearer ${accesstoken}'
    // };
    // var request = http.Request('POST', Uri.parse('https://api-s1.orange.cm/omcoreapis/1.0.2/mp/pay'));
    // request.body = json.encode({
    //   "amount": "10",
    //   "notifUrl": "https://www.y-note.cm/notification",
    //   "payToken": "MP2503215B8978323F2A344CBD46",
    //   "description": "Credit de communication sur RE237",
    //   "subscriberMsisdn": "655868646",
    //   "pin": "7859",
    //   "channelUserMsisdn": "659925095",
    //   "OrderId": "450"
    //
    // });
    // request.headers.addAll(headers);
    //
    // http.StreamedResponse response = await request.send();
    // var responses = await http.Response.fromStream(response);
    // final jsonData = jsonDecode(responses.body);
    //
    // print(response.statusCode);
    // print(jsonData);
    // // print(response.headers);
    //
    // if (response.statusCode == 200) {
    //   print(await response.stream.bytesToString());
    // //  print(response.statusCode);
    //
    //   // collectionRef.add({
    //   //   "amount": amount,
    //   //   "idphone": idphone,
    //   //   "idtransact": order,
    //   //   "numerocamtel":num1,
    //   //   "numeroorange": num2orange,
    //   //   "status": "1",
    //   //   "heure":"${DateTime.now()}",
    //   // });
    //  // sender(num1,amount,num2orange,order);
    //
    //   // var data = await getstatut(accesstoken,payToken,order);
    //   //  if(data!=null){
    //   //    update(order.toString());
    //   //  }
    //
    // }
    // else {
    //
    //   print(response.reasonPhrase);
    // }
  }

  static getstatut(accesstoken,payToken,order)async
  {
print(accesstoken);
print(payToken);
print(order);
    var headers = {
      'X-AUTH-TOKEN': 'WU5PVEVIRUFEMjpAWU5vVGVIRUBEMlBST0RBUEk=',
      'Authorization': 'Bearer ${accesstoken}'
    };
    var request = http.Request('GET', Uri.parse('https://api-s1.orange.cm/omcoreapis/1.0.2/mp/paymentstatus/${payToken}'));
    request.body = '''''';
    request.headers.addAll(headers);

    http.StreamedResponse response = await request.send();
    var data = await response.stream.bytesToString();
    var statut = jsonDecode(data.toString());

    if (response.statusCode == 200) {

      print(statut);
      if(statut["data"]["status"]!="SUCCESSFULL"){
        print("en attente");
        print(statut["data"]["status"]);
        Future.delayed(Duration(seconds: 5),() {
          getstatut(accesstoken,payToken,order);
        },);


      }else {

        updateValueWithoutLogin(order,payToken);

        // updateValueWithoutLogin("Transact",order,{'statut': '1'});
        Get.snackbar(backgroundColor: Colors.green,
            'Info',
            "Payement effectuer avec succes",

            colorText: Colors.white,

            snackPosition: SnackPosition.TOP, duration: Duration(seconds: 30)
        );
        // update(order.toString());
        // ScaffoldMessenger.of(context)
        //     .showSnackBar(const SnackBar(
        //     backgroundColor: Colors.green,
        //     content:
        //     Text("paiement effectuer avec succes")));
        // print("pas en attente");

        return statut["data"]["status"];
      }
      // return statut;
    }
    else {
      print(response.reasonPhrase);
    }
  }

  static Future<void> updateValueWithoutLogin(order,payToken) async {
    print(payToken);
    try {
      QuerySnapshot querySnapshot = await FirebaseFirestore.instance
          .collection('Transact')
          .where('payToken', isEqualTo: payToken)
          .get();
      if (querySnapshot.docs.isNotEmpty) {
        // Mise à jour du statut
        await FirebaseFirestore.instance
            .collection('Transact')
            .doc(querySnapshot.docs.first.id)
            .update({'status': "1"});

        print('Statut mis à jour avec succès');
      } else {
        print('Aucun document trouvé pour ce numéro Orange');
        print(querySnapshot.docs);
      }

    } catch (e) {
      print('Erreur lors de la modification de la valeur : $e');
    }
  }





}
