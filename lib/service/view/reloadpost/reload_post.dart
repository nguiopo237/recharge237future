import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:otp/otp.dart';
import 'package:recharge237_serveur/component/style/middletext.dart';
import 'package:sizer/sizer.dart';

import '../../../main.dart';
import '../../controlleur/Reload_controlleur.dart';
import '../../controlleur/home_controlleur.dart';
import '../../controlleur/transact_controlleur.dart';
import '../transact/transact_page.dart';

class ReloadAirtimesPost extends GetView<ReloadControlleur> {
  const ReloadAirtimesPost({super.key});

  checkaccept(context) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Êtes-vous sûr de vouloir ",
            style: TextStyle(fontSize: 18),
          ),
          const SizedBox(height: 30),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                ),
                onPressed: () async {
                  Get.back();
                  String order = OTP.generateTOTPCodeString(
                      'JBSWY3DPEHPK3PXP', DateTime.now().millisecondsSinceEpoch,
                      interval: 20, algorithm: Algorithm.SHA512);

                  if (controller.number2.text == "655868646" ||
                      controller.number2.text == "691989964") {
                    try {
                      final docRef = await collectionRef.add({
                        "amount": controller.amounts.text.toString(),
                        "idphone": idphone,
                        "idtransact": order,
                        "numerocamtel": controller.number1.text,
                        "numeroorange": controller.number2.text,
                        "status": "9",
                        "heure": DateTime.now().toString(),
                        "accesstoken": order,
                        "payToken": order,
                        "order": order,
                        "retry": "0",
                      });

                      // Création de la réponse JSON
                      final response = {
                        "success": true,
                        "documentId": docRef.id,
                        "transactionData": {
                          "amount": controller.amounts.text,
                          "transactionId": order,
                          "timestamp": DateTime.now().toIso8601String()
                        }
                      };

                      print("Réponse JSON: ${jsonEncode(response)}");

                      // Affichage d'une confirmation à l'utilisateur
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          backgroundColor: Colors.green,
                          content: Text("Transaction réussie"),
                        ),
                      );
                    } catch (e) {
                      print("Erreur: ${e.toString()}");
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: Colors.red,
                          content: Text(
                              "Erreur lors de la transaction: ${e.toString()}"),
                        ),
                      );
                    }
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        backgroundColor: Colors.orange,
                        content: Text(
                            "Vous n'êtes pas autorisé à effectuer cette action"),
                      ),
                    );
                  }
                },
                child: const Text('Accepter', style: TextStyle(color: Colors.white)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                ),
                onPressed: () {
                  Get.back();
                },
                child: const Text('Refuser', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHistoriqueRapide() {
    final FirebaseFirestore firestore = FirebaseFirestore.instance;
    Widget buildTransactionsList() {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: StreamBuilder<QuerySnapshot>(
          stream: firestore
              .collection('Transact')
              .where(
                "idphone",
                isEqualTo: idphone,
              )
              .orderBy("heure", descending: true)
              .limit(3)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(child: Text('Erreur: ${snapshot.error}'));
            }

            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return const Center(child: Text('Aucune transaction trouvée'));
            }

            final transactions = snapshot.data!.docs;

            return Column(
              children: [
                ListView.builder(
                  // controller: _controller,
                  shrinkWrap: true,
                  reverse: false,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: transactions.length,
                  itemBuilder: (context, index) {
                    final data =
                        transactions[index].data() as Map<String, dynamic>;
                    final transaction = Transactions.fromMap(data);
                    return transaction.statut == "9" ||
                            transaction.statut == "10"
                        ? t.buildTransactionItem(transaction)
                        : const SizedBox();
                  },
                ),
                InkWell(
                  onTap: () {
                    c.getmodal(
                        sectionview: SizedBox(
                      height: Get.height / 1.5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.all(8.0),
                            child: Text(
                              'Mes Recharges',
                              style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.deepPurple,
                                  decoration: TextDecoration.underline),
                            ),
                          ),
                          SizedBox(
                            height: 2.h,
                          ),
                          Expanded(child: t.buildTransactionsList())
                        ],
                      ),
                    ));
                  },
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      const Text(
                        'Voir plus',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.deepPurple,
                            decoration: TextDecoration.underline),
                      ),
                      Icon(
                        Icons.navigate_next,
                        color: Colors.deepPurple,
                        size: 18.sp,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recharges récentes',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.deepPurple,
          ),
        ),
        SizedBox(height: 1.h),
        buildTransactionsList(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Middletext(
          text: "Recharger une sim post",
          fontWeight: FontWeight.bold,
          size: 18.sp,
        ),
      ),
      body: Obx(
        () => Form(
          key: controller.formKey,
          child: ListView(
            padding: EdgeInsets.symmetric(horizontal: 4.w),
            children: [
              SizedBox(
                height: 4.h,
              ),
              Container(
                alignment: Alignment.center,
                padding: EdgeInsets.all(4.w),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: TextField(
                  readOnly: controller.read.value,
                  controller: controller.number1,
                  keyboardType: TextInputType.number,
                  onChanged: (value) {
                    if (value.isNotEmpty) {
                      controller.error1.value = true;

                      if (controller.numberc
                          .contains(value.toString().substring(0, 3))) {
                        controller.detectedOperator1.value = "Camtel";
                        controller.operatorLogo1.value = "images/blue.png";
                        controller.number1.text = value.replaceAll(" ", "");
                        controller.number1.text =
                            controller.number1.text.replaceAll("+237", "");
                      } else {
                        controller.number1.text = "";
                        controller.number1.text = value.replaceAll(" ", "");
                        controller.number1.text =
                            controller.number1.text.replaceAll("+237", "");
                        if (controller.numberc.contains(controller.number1.text
                            .toString()
                            .substring(0, 3))) {
                          controller.detectedOperator1.value = "Camtel";
                          controller.operatorLogo1.value = "images/blue.png";
                        }
                      }
                    } else {
                      controller.operatorLogo1.value = "";
                      controller.error1.value = false;
                    }
                  },
                  decoration: InputDecoration(
                      suffixIcon: Visibility(
                        visible: controller.operatorLogo1.value != "",
                        child: SizedBox(
                            height: 1.h,
                            width: 2.w,
                            child: Image.asset(
                              controller.operatorLogo1.value,
                              height: 1.h,
                            )),
                      ),
                      labelText: "Numéro de téléphone à recharger",
                      prefixIcon: InkWell(
                          onTap: () async {
                            //await FlutterContacts.openExternalView("1");
                            // globalKeys.currentState!.openEndDrawer();
                          },
                          child: const Icon(Icons.phone, color: Colors.blueAccent)),
                      border: InputBorder.none,
                      hintText: "entrez Numero camtel"),
                ),
              ),
              SizedBox(height: 2.h),
              Align(
                  child: Text("Montant de la recharge",
                      style: TextStyle(
                          color: Colors.blueAccent,
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w600))),
              SizedBox(height: 1.h),
              Wrap(
                spacing: 2.w,
                children: controller.presetAmounts.map((amount) {
                  return ElevatedButton(
                    onPressed: () {
                      controller.amounts.text = amount.toString();
                      controller.error2.value = true;

                      //   amountController.text = amount.toString();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.blueAccent,
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                      padding: EdgeInsets.symmetric(
                          horizontal: 4.w, vertical: 1.5.h),
                    ),
                    child: Text("$amount FCFA"),
                  );
                }).toList(),
              ),
              SizedBox(height: 2.h),
              Container(
                padding: EdgeInsets.all(4.w),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: TextFormField(
                  controller: controller.amounts,
                  maxLength: 5,
                  onChanged: (value) {
                    if (value.trim().isNotEmpty) {
                      if (controller.formKey.currentState!.validate()) {
                        controller.error2.value = true;
                      }
                    } else {}
                    print(controller.amounts.text);
                  },
                  validator: (value) {
                    if (value!.trim().isEmpty) {
                      return "enter";
                    }

                    if (int.parse(value) >= 10) {
                      controller.error2.value = true;
                    } else {
                      controller.error2.value = false;

                      return "${"enter"} superieur ou egale à 10";
                    }

                    if (int.parse(value) <= 50000) {
                      controller.error2.value = true;
                    } else {
                      controller.error2.value = false;

                      return "${"enter"} inferieur ou egale à 50000";
                    }

                    return null;
                  },
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: "Montant personnalisé",
                    prefixIcon: Icon(Icons.money, color: Colors.blueAccent),
                    border: InputBorder.none,
                  ),
                ),
              ),
              SizedBox(height: 3.h),
              Container(
                padding: EdgeInsets.all(4.w),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: TextFormField(
                  controller: controller.number2,
                  keyboardType: TextInputType.number,
                  maxLength: 9,
                  onChanged: controller.detectOperator,
                  decoration: InputDecoration(
                      labelText: "Numéro payeur",
                      prefixIcon: const Icon(Icons.payment, color: Colors.blueAccent),
                      border: InputBorder.none,
                      counterText: "",
                      suffixIcon: Visibility(
                        visible: controller.operatorLogo != "",
                        child: SizedBox(
                            height: 1.h,
                            width: 2.w,
                            child: Image.asset(
                              controller.operatorLogo.value,
                              height: 1.h,
                            )),
                      )),
                  validator: (value) {
                    if (value!.length == 9) {
                      controller.error3.value = true;
                    } else {
                      return "${"enter"} veuillez saisir les 9 chiffre";
                    }
                    return null;
                  },
                ),
              ),
              SizedBox(height: 10.h),
              ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent),
                  onPressed: controller.error2.value == false
                      ? null
                      : () async {
                          c.getmodal(sectionview: checkaccept(context));
                        },
                  child: Middletext(
                    text: "Valider",
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  )),
              SizedBox(height: 4.h),
              _buildHistoriqueRapide(),
            ],
          ),
        ),
      ),
    );
  }
}
