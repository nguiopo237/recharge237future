import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:projettest/component/widget/widget_text.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'package:sizer/sizer.dart';
import 'package:ussd_flutter/ussd_service.dart';
import 'package:ussd_launcher/ussd_launcher.dart';


import '../../model/listnumbermode.dart';




class invoiceR237 extends StatefulWidget {
  final Listnumberspaymodel? post;

  invoiceR237({super.key,
    this.post ,
  });

  @override
  State<invoiceR237> createState() => _invoiceR237State();
}

class _invoiceR237State extends State<invoiceR237> {
  bool _isLoading = false;
  List<String> _ussdMessages = [];
  final UssdService _ussdService = UssdService();
  TextEditingController ussdController = TextEditingController();
  String sessionStatus = '';
  String _ussdResult = 'No USSD response yet.';
  final List<TextEditingController> optionControllers = [];
  List<Map<String, dynamic>> simCardsList = [];
  int? selectedSlotIndex;
  String _sessionStatus = '';
  bool _isUssdSessionActive = false;
  StreamSubscription<UssdResponse>? _ussdSubscription;

  void _updateUssdMessages(String newText) {
    setState(() {
      _ussdMessages.add(newText);
    });
  }

  void _handleUssdResponse(UssdResponse response) {
    print("session d ecoute et reponse");
    setState(() {
      _ussdMessages.add('${response.message}\n État de la sitation: ${response.state}');

      if (response.state == UssdSessionState.error ||
          response.state == UssdSessionState.error ||
          response.state == UssdSessionState.error) {
        _isUssdSessionActive = false;
        _sessionStatus = "Session USSD terminée (${response.state})";
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
      _isUssdSessionActive = false;
      _sessionStatus = "Erreur lors de la session USSD";
      setState(() {
        _isLoading = false;
      });
    });
  }

  Future<void> launchMultiSessionUssd({amount,number,bool post = false}) async {
    print("ecoute du ussd kmille activation ");
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
      print("ici");

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
      print(_ussdResult);
      print("debut de l action");
      Future<void> _sendUssdCode(String ussdCode) async {
        try {
          final response = await _ussdService.sendUssd(ussdCode);
          setState(() {
            _ussdMessages.add('Message: ${response.message}\nÉtat: ${response.state}');
          });
        } catch (e) {
          setState(() {
            _ussdMessages.add('Erreur envoi USSD: $e');
          });
        }
      }
      optionControllers.clear();
      optionControllers.addAll([TextEditingController(text: "${number}"),TextEditingController(text: "${number}"),TextEditingController(text: "1")]);



      //  _sendUssdCode(_ussdController.text);
      // _launchMultiSessionUssd();
      _sendUssdCode(ussdController.text);
      await UssdLauncher.multisessionUssd(
        // code: ussdController.text,
        code: "*825*1*2*1*2#",
        //code: "*825*1*2*1*2#",
        slotIndex: 0,
        options: options,
      );
    } catch (e) {
      print("other");
      _updateUssdMessages('\nErreur : ${e.toString()}');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
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
            // addOptionField();
          }
        });
      } catch (e) {
        print("Erreur lors du chargement des cartes SIM: $e");
      }
    } else {
      print("Permission téléphone non accordée");
    }
  }

  void _setupUssdResponseListener() {
    _ussdSubscription = _ussdService.ussdResponseStream.listen(
          (UssdResponse response) {
        _handleUssdResponse(response);
      },
      onError: (error) {
        _handleUssdError(error);
      },
    );
  }


  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    loadSimCards();
    _setupUssdResponseListener();
    launchMultiSessionUssd(number: widget.post!.numeros);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("tiket"),),
      body: Padding(
        padding:  EdgeInsets.all(12.0),
        child: Container(
          padding: EdgeInsets.all(10),

          height:120.h ,
          width: 120.w,
          decoration:  BoxDecoration(
            border: Border.all(color: Colors.black,width: 1.w/20),
            image: DecorationImage(

              image: AssetImage("images/photoback.jpg",),

              fit: BoxFit.fitHeight,
              opacity: 000.2,

            ),
          ),



          child: SingleChildScrollView(
            child: Column(
              children: [
                QrImageView(

                  data: widget.post!.idtransact.toString(),
                  version: QrVersions.auto,
                  size: 12.h,
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(" www.recharge237.com ",style: TextStyle(fontSize: 12.sp)),
                    SizedBox(
                      width: 8.w,
                      height: 8.h,
                      child: Image.asset("images/photo.jpg",height: 6.h,width: 6.w,fit: BoxFit.cover,),
                    )
                  ],
                ),
                Text(
                  "Reçu",
                  style: TextStyle(fontSize: 3.w, fontWeight: FontWeight.bold),
                ),
                Row(
                  children: [
                    Text("Date d'édition: ",style: TextStyle(fontSize: 8.sp)),
                    Text(DateTime.now().toString(),style: TextStyle(fontSize: 8.sp)),
                  ],
                ),


                Divider(),
                SizedBox(height: 2.h,),
                Text(
                  "Transactions",
                  style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold,decoration: TextDecoration.underline),
                ),
                SizedBox(height: 2.h,),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Type",
                      style: TextStyle( fontWeight: FontWeight.bold,fontSize: 12.sp),
                    ),
                    Text("Transfert de crédit",style: TextStyle(fontSize: 12.sp)),
                  ],
                ),
                SizedBox(height: 1.h,),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Montant rechargé",
                      style: TextStyle( fontWeight: FontWeight.bold,fontSize: 12.sp),),

                    Text("${widget.post!.amount.toString()} FCFA",style: TextStyle(fontSize: 12.sp)),
                  ],
                ),
                SizedBox(height: 1.h,),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Date",
                      style: TextStyle( fontWeight: FontWeight.bold,fontSize: 12.sp),),
                    Text(
                        "il y'a ${timeago.format(DateTime.parse(widget.post!.heure!.toString()))}"),
                  ],
                ),
                SizedBox(height: 1.h,),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Référence",style: TextStyle( fontWeight: FontWeight.bold,fontSize: 12.sp),),
                    Text(widget.post!.id.toString(),style: TextStyle(fontSize: 12.sp)),
                  ],
                ), SizedBox(height: 1.h,),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Statut",style: TextStyle( fontWeight: FontWeight.bold,fontSize: 12.sp),),
                    Text(widget.post!.statut==2?"Succès":"En Cour de traitement",style: TextStyle(fontSize: 12.sp)),
                  ],
                ),
                Divider(),
                SizedBox(height: 4.h,),





                Column(
                  children: [

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Identifiant de la transaction",


                          style: TextStyle( fontWeight: FontWeight.bold,fontSize: 12.sp
                          ),
                        ),
                        Text("IdBlue",style: TextStyle(fontSize: 12.sp)),
                      ],
                    ),
                    SizedBox(height: 2.h,),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("Numéro de téléphone rechargé",
                            style: TextStyle( fontWeight: FontWeight.bold,fontSize: 12.sp)),

                        Text(widget.post!.numeros.toString(),style: TextStyle(fontSize: 12.sp)),
                      ],
                    ),
                    SizedBox(height: 2.h,),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("Numéro de téléphone payeur",
                          style: TextStyle( fontWeight: FontWeight.bold,fontSize: 12.sp),),

                        Text(widget.post!.numeror.toString(),style: TextStyle(fontSize: 12.sp)),
                      ],
                    ),
                    SizedBox(height: 2.h,),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("Référence Orange Money",style: TextStyle( fontWeight: FontWeight.bold,fontSize: 12.sp),),
                        Text(widget.post!.id.toString(),style: TextStyle(fontSize: 12.sp)),
                      ],
                    ),
                    SizedBox(height: 2.h,),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("Référence Blue/CAMTEL",style: TextStyle( fontWeight: FontWeight.bold,fontSize: 12.sp),),
                        Text(widget.post!.numeros.toString(),style: TextStyle(fontSize: 12.sp)),
                      ],
                    ),

                    Divider(),


                    Padding(
                      padding: const EdgeInsets.only(bottom: 20.0),
                      child: MiddleText(
                        text:
                        '© 2024, Proudly developed by LOUOKDOM \nServices Sarl All right reserved',
                        //color: Colors.white,
                        size: 9.sp,
                        textAlign: TextAlign.center,
                      ),
                    )
                  ],),

              ],
            ),
          ),),
      ),

    );
  }
}
