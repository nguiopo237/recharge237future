import 'dart:async';

import 'package:clipboard/clipboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';


import '../../model/listnumbermode.dart';

import 'package:timeago/timeago.dart' as timeago;


import '../../service/controlleur/widget_controlleur.dart';
import '../../service/sendmail/send_mail.dart';
import 'invoice.dart';


class Componentcard extends StatefulWidget {
  final Listnumberspaymodel post;

  const Componentcard({super.key, required this.post});

  @override
  State<Componentcard> createState() => _ComponentcardState();
}

class _ComponentcardState extends State<Componentcard> {


  List<String> _ussdMessages = [];

  TextEditingController ussdController = TextEditingController();
  String sessionStatus = '';
  String _ussdResult = 'No USSD response yet.';
  final List<TextEditingController> optionControllers = [];
  List<Map<String, dynamic>> simCardsList = [];
  int? selectedSlotIndex;
  String _sessionStatus = '';
  bool _isUssdSessionActive = false;
  bool _isLoading = false;


  void _updateUssdMessages(String newText) {
    setState(() {
      _ussdMessages.add(newText);
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






  String getStatutText({int statut = 0}) {
    switch (statut) {
      case 0:
        return "en attente de validation";
      case 1:
        return "en attente de traitements";
      case 2:
        return "en cour de traitement";
      case 3:
        return "operation reussi";
      case 9:
        return "En attente de recharge SIM Post";
      case 10:
        return "Sim recharger avec succes";
      default:
        return "en attente de validation";
    }
  }

  Color getStatutColor({int statut = 0}) {
    switch (statut) {
      case 0:
        return Colors.orangeAccent;
      case 1:
        return Colors.blue;
      case 2:
        return Colors.deepPurple;
      case 3:
        return Colors.green;
      case 9:
        return Colors.pink;
      case 10:
        return Colors.pinkAccent;
      default:
        return Colors.green; // ou une autre couleur par défaut
    }
  }



  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Clipboard.setData(ClipboardData(text: "${widget.post.numeros}"));
        SendEmail.updateValueInFirestore("solde","jNIO5y2lj8s9PiTSV4cU","dsm","6565");

        // FlutterClipboard.copy(
        //     '${widget.post.numeros}');
        // Get.to(invoiceR237(
        //   post: widget.post,
        // ));
       // optionControllers.clear();
       // optionControllers.addAll([TextEditingController(text: "${widget.post.numeros}"),TextEditingController(text: "${widget.post.numeros}"),TextEditingController(text: "1")]);
       // launchMultiSessionUssd(number:widget.post.numeros,);
      },
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Container(
          padding: EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10)),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("${c.formaterDateFrancais(DateTime.parse(widget.post.heure.toString()))} à ${c.formaterHeure(DateTime.parse(widget.post.heure.toString()))} "),

                  Text(widget.post.numeros.toString()),
                  getStatutWidget()
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("${widget.post.amount} Fcfa",),
                  // Text(widget.post.payToken.toString()),

                  Text(widget.post.id.toString()),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    getStatutText(statut: widget.post.statut?.toInt()??0),
                    style: TextStyle(
                      color: getStatutColor(statut: widget.post.statut?.toInt()??0),
                    ),
                  ),

                  Text(widget.post.numeror.toString()),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget getStatutWidget() {
    switch (widget.post.statut) {
      case 3:
      case 10:
        return Icon(
          Icons.check_circle,
          color: Colors.green,
        );
      default:
        return SizedBox(
          height: 15,
          width: 15,
          child: CircularProgressIndicator(color: Colors.grey),
        );
    }
  }


}
