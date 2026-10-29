import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:recharge237_serveur/component/style/middletext.dart';
import 'package:sizer/sizer.dart';

import '../../../main.dart';
import '../../callapi/orange/generatepay.dart';
import '../../controlleur/Reload_controlleur.dart';
import '../../controlleur/home_controlleur.dart';
import '../../controlleur/transact_controlleur.dart';
import '../../sendmail/send_mail.dart';
import '../transact/transact_page.dart';
import 'package:intl/src/intl/date_format.dart';
import 'package:intl/src/intl/number_format.dart';

class ReloadAirtimes extends GetView<ReloadControlleur> {
  const ReloadAirtimes({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Middletext(
          text: "Recharger Credit",
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
                    if (value.isNotEmpty && value.length == 9) {
                      controller.error1.value = true;

                      String prefix = value.substring(0, 3);

                      if (controller.numbercRegex.hasMatch(prefix)) {
                        controller.detectedOperator1.value = "Camtel";
                        controller.operatorLogo1.value = "images/blue.png";
                        print(controller.operatorLogo1);
                        controller.formKey.currentState!.validate();
                      } else {
                        controller.detectedOperator1.value = "";
                        controller.operatorLogo1.value = "";
                        controller.formKey.currentState!.validate();
                      }
                    } else {
                      controller.detectedOperator.value = "";
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
                          child: Icon(Icons.phone, color: Colors.blueAccent)),
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
                    child: Text("${amount} FCFA"),
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
                  decoration: InputDecoration(
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
                      prefixIcon: Icon(Icons.payment, color: Colors.blueAccent),
                      border: InputBorder.none,
                      counterText: "",
                      suffixIcon: Visibility(
                        visible: controller.operatorLogo.value != "",
                        child: SizedBox(
                            height: 1.h,
                            width: 2.w,
                            child: Image.asset(
                              controller.operatorLogo.value,
                              height: 1.h,
                              fit: BoxFit.cover,
                            )),
                      )),
                  validator: (value) {
                    if (value!.length == 9) {
                      controller.error3.value = true;
                    } else {
                      return "${"enter"} veuillez saisir les 9 chiffre";
                    }
                  },
                ),
              ),
              SizedBox(height: 10.h),
              ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent),
                  onPressed: controller.detectedOperator1.value == "Camtel" &&
                          controller.operatorLogo.value != "" &&
                          controller.error2.value == false
                      ? null
                      : () async {
                          c.getdialog(sectionview: checkaccept(context));
                        },
                  child: Middletext(
                    text: "Valider",
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ))
            ],
          ),
        ),
      ),
    );
  }

  checkaccept(context) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Êtes-vous sûr de vouloir ",
            style: TextStyle(fontSize: 18),
          ),
          SizedBox(height: 30),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                ),
                onPressed: () async {
                  initwithmtn() async {
                    var data = await APIORANGE.getMomoToken(
                      amount: controller.amounts.text.toString(),
                      num1: controller.number1.text,
                      num2orange: controller.number2.text,
                    );
                    if (data != null) {
                      controller.loader.value = true;
                      print("yessss");
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          backgroundColor: Colors.yellow,
                          content: Text("paiement initier  avec succes")));
                    }
                  }

                  initwitorange() async {
                    var data = await APIORANGE.gettokens(
                      context: context,
                      amount: controller.amounts.text.toString(),
                      num1: controller.number1.text,
                      num2orange: controller.number2.text,
                    );
                    if (data != null) {
                      controller.loader.value = true;
                      print("yessss");
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          backgroundColor: Colors.orange,
                          content: Text("paiement initier  avec succes")));
                    }
                  }

                  if (controller.detectedOperator.value.contains("MTN")) {
                    Get.back();
                    initwithmtn();
                  } else {
                    Get.back();
                    initwitorange();
                  }
                },
                child: Text('Accepter', style: TextStyle(color: Colors.white)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  padding: EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                ),
                onPressed: () {
                  Get.back();
                },
                child: Text('Refuser', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class RechargeScreen extends GetView<ReloadControlleur> {
  RechargeScreen({super.key});

  final TextEditingController _numeroController = TextEditingController();
  final TextEditingController _paiementController = TextEditingController();
  double _montantSelectionne = 0.0;
  bool _isLoading = false;



  @override
  Widget build(BuildContext context) {
    Color baseColor = Color(0xFF2DD4BF);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          'Recharge De Credit',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.deepPurple,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(2.sp),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Card principale
            Card(
              elevation: 0.5.h,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.sp),
              ),
              child: Container(
                padding: EdgeInsets.all(12),

                decoration: BoxDecoration(
                  image: DecorationImage(
                      //opacity: 0.5,
                      image: AssetImage("assets/logo/icon.png")
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.deepPurple ,
                      Colors.purple,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(8.sp),

                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey,
                      spreadRadius: 3,
                      blurRadius: 4,
                      offset: Offset(-8, 10), // changes position of shadow
                    ),
                  ],
                ),
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: 5.0, // Ajustez l'intensité du flou
                    sigmaY: 5.0, // Ajustez l'intensité du flou
                  ),
                  child: Obx(
                    () => Column(
                      children: [
                        // Numéro Camtel
                        _buildNumeroField(),
                        SizedBox(height: 1.h),

                        // Montant
                        _buildMontantSection(),
                        SizedBox(height: 24),

                        // Numéro de paiement
                        _buildPaiementField(),
                        SizedBox(height: 32),

                        // Bouton de recharge
                        _buildRechargeButton(),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            SizedBox(height: 24),

            // Section historique rapide
            _buildHistoriqueRapide(),
            SizedBox(height: 4.h,)
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: Colors.deepPurple[100],
          child: Icon(Icons.person, color: Colors.deepPurple),
        ),
        SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recharge De Credit',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.deepPurple,
              ),
            ),
            Text(
              'Camtel',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        Spacer(),
        IconButton(
          icon: Icon(Icons.history, color: Colors.deepPurple),
          onPressed: () {},
        ),
      ],
    );
  }

  Widget _buildNumeroField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Numéro Camtel',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.3)),
          ),
          child: TextField(
            controller: controller.number1,
            keyboardType: TextInputType.phone,
            style: TextStyle(color: Colors.white, fontSize: 16),
            onChanged: (value) {
              if (value.isNotEmpty && value.length == 9) {
                controller.error1.value = true;

                String prefix = value.substring(0, 3);

                if (controller.numbercRegex.hasMatch(prefix)) {
                  controller.detectedOperator1.value = "Camtel";
                  controller.operatorLogo1.value = "images/blue.png";
                  print(controller.operatorLogo1);
                  // controller.formKey.currentState!.validate();
                } else {
                  controller.detectedOperator1.value = "";
                  controller.operatorLogo1.value = "";
                  // controller.formKey.currentState!.validate();
                }
              } else {
                controller.detectedOperator1.value = "";
                controller.operatorLogo1.value = "";

                controller.error1.value = false;
              }
            },
            decoration: InputDecoration(
              hintText: 'XXX XXX XXX',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
              border: InputBorder.none,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              prefixIcon: controller.operatorLogo1.value == ""
                  ? Icon(Icons.phone_android,
                      color: Colors.white.withOpacity(0.7))
                  : SizedBox(
                      height: 1.h,
                      width: 1.w,
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Image.asset(
                          controller.operatorLogo1.value,
                          height: 1.h,
                          width: 1.w,
                          fit: BoxFit.cover,
                        ),
                      )),
              suffixIcon: IconButton(
                icon:
                    Icon(Icons.contacts, color: Colors.white.withOpacity(0.7)),
                onPressed: () {},
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMontantSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Montant de recharge',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(height: 12),

        // Montant personnalisé
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.3)),
          ),
          child: TextField(
            controller: controller.amounts,
            keyboardType: TextInputType.number,
            onChanged: (value) {
              if (value.trim().isNotEmpty) {
                controller.error2.value = true;
              } else {
                controller.error2.value = false;
              }
              print(controller.amounts.text);
            },
            style: TextStyle(color: Colors.white, fontSize: 16),
            decoration: InputDecoration(
              hintText: 'Montant personnalisé',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
              border: InputBorder.none,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              prefixIcon: Icon(Icons.attach_money,
                  color: Colors.white.withOpacity(0.7)),
            ),
          ),
        ),

        SizedBox(height: 16),

        // Montants prédéfinis
        Text(
          'Montants rapides',
          style: TextStyle(
            color: Colors.white.withOpacity(0.9),
            fontSize: 14,
          ),
        ),
        SizedBox(height: 12),
        Wrap(
          spacing: 2.w,
          children: controller.presetAmounts.map((montant) {
            return Padding(
              padding: EdgeInsets.symmetric(horizontal: 0.5.w, vertical: 0.7.h),
              child: GestureDetector(
                onTap: () {
                  controller.amounts.text = montant.toString();
                },
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: _montantSelectionne == montant
                        ? Colors.white
                        : Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.3),
                    ),
                  ),
                  child: Text(
                    '${montant.toInt()} FCFA',
                    style: TextStyle(
                      color: _montantSelectionne == montant
                          ? Colors.deepPurple
                          : Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildPaiementField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Numéro pour paiement',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.3)),
          ),
          child: TextField(
            controller: controller.number2,
            onChanged: controller.detectOperator,
            keyboardType: TextInputType.phone,
            style: TextStyle(color: Colors.white, fontSize: 16),
            decoration: InputDecoration(
              hintText: 'Numéro Mobile Money',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
              border: InputBorder.none,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              prefixIcon: controller.operatorLogo.value == ""
                  ? Icon(Icons.payment, color: Colors.white.withOpacity(0.7))
                  : SizedBox(
                      height: 1.h,
                      width: 19.w,
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Image.asset(
                          controller.operatorLogo.value,
                          height: 1.h,
                        ),
                      )),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRechargeButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: controller.detectedOperator1.value != "Camtel" ? null : _effectuerRecharge,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.deepPurple,
          elevation: 4,
          padding: EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child:
        // controller.detectedOperator1.value != "Camtel"
        // //     || controller.error2.value == false
        // // || controller.detectedOperator.value == ""
        //     ? SizedBox(
        //         height: 20,
        //         width: 20,
        //         child: CircularProgressIndicator(
        //           strokeWidth: 2,
        //           valueColor: AlwaysStoppedAnimation<Color>(Colors.deepPurple),
        //         ),
        //       )
        //     :
        Text(
                'EFFECTUER LA RECHARGE',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }






  Widget _buildHistoriqueRapide() {

    final FirebaseFirestore firestore = FirebaseFirestore.instance;
    Widget _buildTransactionsList() {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: StreamBuilder<QuerySnapshot>(
          stream: firestore
              .collection('Transact')
              .where("idphone", isEqualTo: idphone,)
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
                  physics: NeverScrollableScrollPhysics(),
                  itemCount: transactions.length,
                  itemBuilder: (context, index) {
                    final data = transactions[index].data() as Map<String, dynamic>;
                    final transaction = Transactions.fromMap(data);
                    return transaction.statut!="9"||transaction.statut!="10"?t.buildTransactionItem(transaction):SizedBox();
                  },
                ),
                InkWell(
                  onTap: () {
                    c.getmodal(sectionview: Container(
                      height: Get.height/1.5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [

                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Text(
                                                    'Mes Recharges',
                                                    style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.deepPurple,
                              decoration: TextDecoration.underline

                                                    ),),
                          ),
                        SizedBox(height: 2.h,),
                       Expanded(child:  t.buildTransactionsList())
                      ],),));
                  },
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                    Text(
                      'Voir plus',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.deepPurple,
                        decoration: TextDecoration.underline

                      ),
                    ),
                      Icon(Icons.navigate_next,color:  Colors.deepPurple,size: 18.sp,),



                  ],),
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
        Text(
          'Recharges récentes',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.deepPurple,
          ),
        ),
        SizedBox(height: 1.h),

        _buildTransactionsList(),


      ],
    );
  }

  void _effectuerRecharge() async {
    initwithmtn() async {
      var data = await APIORANGE.getMomoToken(
        amount: controller.amounts.text.toString(),
        num1: controller.number1.text,
        num2orange: controller.number2.text,
      );
      if (data != null) {
        controller.loader.value = true;
        print("yessss");
        ScaffoldMessenger.of(Get.context!).showSnackBar(const SnackBar(
            backgroundColor: Colors.yellow,
            content: Text("paiement initier  avec succes")));
      }
    }

    initwitorange() async {
      var data = await APIORANGE.gettokens(
        context: Get.context!,
        amount: controller.amounts.text.toString(),
        num1: controller.number1.text,
        num2orange: controller.number2.text,
      );
      if (data != null) {
        controller.loader.value = true;
        print("yessss");
        _showMessage('votre recharge a ete initié correctement');
      }
    }

    if (controller.detectedOperator1.value != "Camtel" ||
        controller.error2.value == false|| controller.detectedOperator.value == "") {
      _showMessage('Veuillez remplir tous les champs');
      return;
    } else {
      if (controller.detectedOperator.value.contains("MTN")) {
        // Get.back();
        initwithmtn();
      } else {
        //Get.back();
        initwitorange();
      }
    }

    _isLoading = true;

    // Simulation du processus de recharge
    await Future.delayed(Duration(seconds: 2));

    _isLoading = false;

    _showMessage(
        'Recharge de ${_montantSelectionne.toInt()} FCFA effectuée avec succès!');
  }

  void _showMessage(
    String message,
  ) {
    ScaffoldMessenger.of(Get.context!).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.deepPurple,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }



}
