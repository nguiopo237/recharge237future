import 'dart:collection';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../main.dart';
import 'controlleur/activity.dart';
import 'controlleur/ussdcontrolleur.dart';
import 'fonctionfire.dart';

class TransactionProcess {
  static final TransactionProcess _instance = TransactionProcess._internal();
  factory TransactionProcess() => _instance;
  TransactionProcess._internal();

  static Queue<TransactionData> queue = Queue();
  bool _isProcessing = false;

  void addTransaction(Map<String, dynamic> docData, BuildContext context,id) {
    queue.add(TransactionData(
      id: id,
      numerocamtel: docData['numerocamtel'],
      amount: docData['amount'],
      idtransact: docData['idtransact'],
      status: docData['status'],
      context: context,
      retry: docData['retry'],

    ));

    print("📥 Transaction ajoutée à la file. Position: ${queue.length}");

    if (!_isProcessing) {
      _processQueue();
    }
  }

  void removeTransaction(String id) {
    print(id);
    // Trouver l'index de la transaction avec l'ID correspondant
    final index = queue.where((transaction) => transaction.id == id);
    print(index);
    if (index != -1) {
      // Supprimer la transaction de la file
      final removedTransaction = queue.remove(index);
      print("🗑️ Transaction supprimée de la file. ID: $id, Position: $index");
      checkoperations(Get.context);
      // Optionnel: Nettoyer le contexte si nécessaire
      // removedTransaction.context = null;
    } else {
      print("⚠️ Transaction non trouvée dans la file. ID: $id");
    }
  }


  Future<void> _processQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;

    while (queue.isNotEmpty) {
      final transaction = queue.removeFirst();
      print("🔄 Traitement de ${transaction.id} (${queue.length} restants)");
      ussd.idtransacts.value = transaction.id;
      try {
        // Attendre 5 secondes avant de traiter
        await Future.delayed(Duration(seconds: 5));

        // Exécuter getdata

        await getdata(
          transaction.id,
          transaction.numerocamtel,
          transaction.amount,
          transaction.idtransact,
          transaction.status,
          transaction.context,
          transaction.retry
        );

        print("✅ Transaction ${transaction.id} terminée");
      } catch (e) {
        print("❌ Erreur sur ${transaction.id}: $e");
        // Optionnel: Réessayer ou logguer l'erreur
      }

      // Petit délai entre les transactions
      await Future.delayed(Duration(seconds: 1));
    }

    _isProcessing = false;
    print("🏁 Toutes les transactions ont été traitées");


  }
}

class TransactionData {
  final String id;
  final String numerocamtel;
  final String amount;
  final String idtransact;
  final String status;
  final String? retry;
  final BuildContext context;

  TransactionData({
    required this.id,
     this.retry,
    required this.numerocamtel,
    required this.amount,
    required this.idtransact,
    required this.status,
    required this.context,
  });
}

// DANS VOTRE FONCTION ORIGINALE MODIFIÉE :
