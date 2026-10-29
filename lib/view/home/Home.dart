import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:recharge237_serveur/service/view/forfait/activer_forfait.dart';
import 'package:recharge237_serveur/service/view/reload/reload_airtimes.dart';
import 'package:recharge237_serveur/service/view/reloadpost/reload_post.dart';
import 'package:recharge237_serveur/service/view/transact/transact_page.dart';
import 'package:sizer/sizer.dart';
import 'package:sms_autofill/sms_autofill.dart';
import 'package:unique_identifier/unique_identifier.dart';

import '../../component/style/middletext.dart';
import '../../component/widget/boxwidget.dart';
import '../../main.dart';
import '../../service/controlleur/home_controlleur.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../message/PersonList.dart';
import '../message/message/messageView.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {



  Future<void> initUniqueIdentifierState() async
  {

    String identifier;
    try {
      identifier = (await UniqueIdentifier.serial)!;
    } on PlatformException {
      identifier = 'Failed to get Unique Identifier';
    }

    if (!mounted) return;

    setState(() {
      idphone = identifier;
    });

    print("_identifier");
    print(idphone);
    print("_identifier");
    checkMemberExists(idphone!);

  }


  final FirebaseFirestore firestore = FirebaseFirestore.instance;


  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    initUniqueIdentifierState();
  }




  @override
  Widget build(BuildContext context) {

    return Scaffold(
      backgroundColor: Colors.white.withOpacity(0.8),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: Middletext(
          text: 'Mon comptes',
          fontWeight: FontWeight.bold,
          size: 22.sp,
        ),
      ),
      body: ListView(
        padding: EdgeInsets.symmetric(horizontal: 2.w),
        children: [

          StreamBuilder(
            stream: firestore
                .collection('member')
                .where("idphone",isEqualTo: idphone)
            // .orderBy("heure", descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Center(child: CircularProgressIndicator());
              } else if (snapshot.hasError) {
                return Text('Erreur : ${snapshot.error}');
              } else if (!snapshot.hasData) {
                return Text('Pas de données disponibles');
              } else {
                // scrollToIndex1();
                final itemdata = snapshot.data?.docs;
                return  ListView.builder(
                  shrinkWrap: true,
                  reverse: true,
                  padding:  EdgeInsets.symmetric(horizontal: 1.w,vertical: 1.h),
                  itemCount: itemdata!.length,
                  itemBuilder: (context, index) {

                    final group = itemdata[index];
                    final item = Member(isadmin: group["isadmin"],name: group["idphone"], status: group["statut"].toString(), lastSeen: 'sdsd');
                    return   Visibility(
                      visible: item.isadmin=="true",
                      child: Row(
                        children: [
                          Expanded(
                            child: StreamBuilder<QuerySnapshot>(
                              stream: firestore.collection('solde')
                              // .where("idphone", isEqualTo: idphone)
                              // .orderBy("heure", descending: false)
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
                      
                                final solde = snapshot.data!.docs;
                      
                                return Boxwidget(
                                  colorbox: Colors.blue,
                                  title: "Solde post",
                                  subtitle: solde.first["soldepost"].toString(),
                                  colortext: Colors.white,
                                  ontape: () async {
                      
                      
                                    Future<Future<void> Function({String smsCodeRegexPattern})?> getSmsCode() async {
                                      try {
                                        // Méthode avec consentement utilisateur (Android 10+)
                                        final code = await SmsAutoFill().getAppSignature.then((signature) {
                                          return SmsAutoFill().listenForCode;
                                        });
                                        print(code);
                                        return code;
                                      } catch (e) {
                                        print("Erreur: $e");
                                        return null;
                                      }
                                    }
                                    getSmsCode();
                      
                      
                                  },
                      
                                );
                              },
                            ),
                          ),
                          Expanded(
                            child: StreamBuilder<QuerySnapshot>(
                              stream: firestore.collection('solde')
                              // .where("idphone", isEqualTo: idphone)
                              // .orderBy("heure", descending: false)
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
                      
                                final solde = snapshot.data!.docs;
                      
                                return Boxwidget(
                                  colorbox: Colors.blue,
                                  title: "Solde DSM",
                                  subtitle: solde.last["dsm"].toString(),
                                  colortext: Colors.white,
                                  ontape: () async {
                      
                      
                                    Future<Future<void> Function({String smsCodeRegexPattern})?> getSmsCode() async {
                                      try {
                                        // Méthode avec consentement utilisateur (Android 10+)
                                        final code = await SmsAutoFill().getAppSignature.then((signature) {
                                          return SmsAutoFill().listenForCode;
                                        });
                                        print(code);
                                        return code;
                                      } catch (e) {
                                        print("Erreur: $e");
                                        return null;
                                      }
                                    }
                                    getSmsCode();
                      
                      
                                  },
                      
                                );
                              },
                            ),
                          ),
                      
                        ],
                      ),
                    );
                  },
                );
              }
            },
          ),




          SizedBox(height: 1.h,),
          Boxwidget(

            title: "Recharger Crédit",
            subtitle: "Rechargez votre compte rapidement",
            size: 16,
            ontape: () => Get.to(RechargeScreen()),

          ),
          Boxwidget(

            title: "Forfait Internet",
            subtitle: " Activez un forfait data",
            size: 14,
            ontape: () => Get.to(ForfaitScreen()),
          ),
          Boxwidget(

            title: "Historique",
            subtitle: "Consulter vos transactions",
            size: 12,
            ontape: () => Get.to(TransactionsScreen()),
          ),
          Boxwidget(

            title: "Recharger une Post",
            subtitle: "Consulter et afficher Vos transactions",
            size: 12,
            ontape: () => Get.to(ReloadAirtimesPost()),
          ),
          SizedBox(height: 3.h,),

          Middletext(text: "Services Rapides",fontWeight: FontWeight.w700,size: 22.sp,),
          SizedBox(height: 2.h,),
          Row(
            children: [
              Expanded(
                child: Boxwidget(

                  title: "Appeler",
                  subtitle: "Effectuer un appels",
                  size: 12,
                  ontape: () {
                    // NotificationService.showNotification(
                    //   id: 1,
                    //   title: 'Notification Test',
                    //   body: 'Ceci est une notification de test!',
                    // );
                  },
                ),
              ),
              Expanded(
                child: Boxwidget(
                  ontape: () {
                    Get.to(MemberListScreen());
                  },

                  title: "Envoyer un sms",
                  subtitle: "Ecrire un message",
                  size: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
