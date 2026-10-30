import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:sizer/sizer.dart';

import '../../component/style/middletext.dart';
import '../../main.dart';
import '../../view/message/message/messageView.dart';
import '../view/transact/transact_page.dart';
import 'package:intl/src/intl/date_format.dart';
import 'package:intl/src/intl/number_format.dart';

import 'Reload_controlleur.dart';

TransactControlleur t = Get.find();
// TransactControlleur t = Get.put(TransactControlleur());

class TransactControlleur extends GetxController {
  RxList<QueryDocumentSnapshot<Map<String, dynamic>>> transact =
      <QueryDocumentSnapshot<Map<String, dynamic>>>[].obs;

  RxDouble totalBalance = 0.0.obs;

  late ScrollController controller;

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
        return Colors.brown; // ou une autre couleur par défaut
    }
  }

  Widget buildTransactionItem(Transactions transaction) {
    String operatorLogoall = "";

    String? prefix = transaction.category.substring(0, 3);

    if (r.numbersRegex.hasMatch(prefix)) {
      operatorLogoall = "images/MTN_logo.png";
    } else if (r.numberoRegex.hasMatch(prefix)) {
      operatorLogoall = "images/omlogo.png";
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 4),
      elevation: 1,
      child: ListTile(
        onTap: () {
          Get.to(ChatScreen(
            transaction: transaction,
          ));
        },
        contentPadding: EdgeInsets.zero,
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: SizedBox(
              height: 1.h,
              width: 19.w,
              child: Padding(
                padding: const EdgeInsets.all(2.0),
                child: Image.asset(
                  operatorLogoall,
                  height: 1.h,
                ),
              )),
        ),
        // title: Text(
        //   transaction.title,
        //   style: const TextStyle(fontWeight: FontWeight.bold),
        // ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  transaction.category,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 8.sp),
                ),
                Text(
                  "-->",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 8.sp),
                ),
                Text(
                  transaction.title,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 8.sp),
                ),
              ],
            ),
            Text(
              DateFormat('dd MMM yyyy - HH:mm').format(transaction.date),
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        trailing: Column(
          children: [
            Expanded(
              child: Text(
                NumberFormat.currency(locale: 'fr_FR', symbol: 'FCFA')
                    .format(transaction.amount),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: transaction.amount > 0 ? Colors.green : Colors.red,
                ),
              ),
            ),
            Expanded(
              child: Text(
                getStatutText(statut: int.parse(transaction.statut)),
                style: TextStyle(
                  color: getStatutColor(statut: int.parse(transaction.statut)),
                  fontSize: 8.sp,
                ),
              ),
            ),
            Expanded(
              child: Middletext(
                text: transaction.id?.toString() ?? "",
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  buildTransactionsList({filter}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: StreamBuilder<QuerySnapshot>(
        stream: firestore
            .collection('Transact')
            .where("idphone", isEqualTo: idphone)
            .orderBy("heure", descending: true)
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

          return ListView.builder(
            // controller: controller,
            shrinkWrap: true,
            itemCount: filter == null
                ? transactions.length
                : transactions
                    .where(
                      (element) => element["status"] == "$filter",
                    )
                    .length,
            itemBuilder: (context, index) {
              final data = filter == null
                  ? transactions[index].data() as Map<String, dynamic>
                  : transactions
                      .where(
                        (element) => element["status"] == "$filter",
                      )
                      .toList()[index]
                      .data() as Map<String, dynamic>;
              final transaction = Transactions.fromMap(data);

              return buildTransactionItem(transaction);
            },
          );
        },
      ),
    );
  }
}
