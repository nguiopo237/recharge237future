// To parse this JSON data, do
//
//     final listnumberspaymodel = listnumberspaymodelFromJson(jsonString);

import 'dart:convert';


List<Listnumberspaymodel> listnumberspaymodelFromJson(String str) =>
    List<Listnumberspaymodel>.from(
        json.decode(str).map((x) => Listnumberspaymodel.fromJson(x)));

String listnumberspaymodelToJson(List<Listnumberspaymodel> data) =>
    json.encode(List<dynamic>.from(data.map((x) => x.toJson())));

class Listnumberspaymodel {
  int? id;
  String? numeros;
  String? amount;
  String? numeror;
  String? heure;
  int? statut;
  String? idtransact;

  Listnumberspaymodel({
    this.id,
    this.numeros,
    this.amount,
    this.numeror,
    this.heure,
    this.statut,
    this.idtransact,
  });

  factory Listnumberspaymodel.fromJson(Map<String, dynamic> json) =>
      Listnumberspaymodel(
        id: json["id"],
        numeros: json["numeros"],
        amount: json["amount"],
        numeror: json["numeror"],
        heure: json["heure"],
        statut: json["statut"],
        idtransact: json["idtransact"],
      );

  Map<String, dynamic> toJson() => {
        "id": id,
        "numeros": numeros,
        "amount": amount,
        "numeror": numeror,
        "heure": heure,
        "statut": statut,
        "idtransact": idtransact,
      };
}
