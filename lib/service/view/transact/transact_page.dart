import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:get/get.dart';
import '../../../component/style/middletext.dart';
import '../../../main.dart';
import '../../controlleur/transact_controlleur.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  String _currentFilter = 'Toutes';

  // Variables pour stocker les totaux
  double _totalRevenus = 0;
  double _totalDepenses = 0;
  double _totalBalance = 0;

  @override
  void initState() {
    super.initState();
    t.controller = ScrollController(initialScrollOffset: 0.0);
    _calculerTotaux();
  }

  @override
  void dispose() {
    t.controller.dispose();
    super.dispose();
  }

  // Fonction pour calculer les totaux
  Future<void> _calculerTotaux() async {
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('Transact')
          .where("idphone", isEqualTo: idphone)
          .get();

      double revenus = 0;
      double depenses = 0;

      for (var doc in querySnapshot.docs) {
        final data = doc.data();
        final amount = data['amount'] ?? 0;
        final status = _currentFilter != "Toutes" ? "${data['status']}" : "3";
        final montant = (amount is num)
            ? amount.toDouble()
            : (amount is String)
                ? double.tryParse(amount) ?? 0
                : 0;

        if (status == "3") {
          revenus += montant;
        } else if (status == "0") {
          depenses += montant;
        }
      }

      setState(() {
        _totalRevenus = revenus;
        _totalDepenses = depenses;
        _totalBalance = revenus + depenses;
      });
      _scrollToIndex();
    } catch (e) {
      print('Erreur lors du calcul des totaux: $e');
    }
  }

  void _scrollToIndex() {
    const double itemHeight = 80.0;
    t.controller.animateTo(
      itemHeight * 60,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes Transactions'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _calculerTotaux,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildBalanceCard(_totalBalance),
          _buildQuickFilters(),
          Expanded(
            child: t.buildTransactionsList(
                filter: _currentFilter == "Toutes" ? null : "3"),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceCard(double balance) {
    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Solde actuel',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              NumberFormat.currency(locale: 'fr_FR', symbol: 'FCFA')
                  .format(balance),
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: balance >= 0 ? Colors.green : Colors.red,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildIncomeOutcome(
                  label: 'Succès',
                  amount: _totalRevenus,
                  color: Colors.green,
                ),
                _buildIncomeOutcome(
                  label: 'Litige',
                  amount: _totalDepenses,
                  color: Colors.red,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIncomeOutcome({
    required String label,
    required double amount,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          NumberFormat.currency(locale: 'fr_FR', symbol: 'FCFA')
              .format(amount.abs()),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildQuickFilters() {
    return SizedBox(
      height: 60,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _buildFilterChip('Toutes'),
          _buildFilterChip('Recharge de Credit'),
          _buildFilterChip('Activation de forfait'),
          _buildFilterChip('Reinitialisation des Post'),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String category) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: FilterChip(
        label: Text(category),
        selected: _currentFilter == category,
        onSelected: (selected) {
          setState(() {
            _currentFilter = selected ? category : 'Toutes';
          });
          _calculerTotaux();
        },
      ),
    );
  }

  Widget _buildTransactionItem(Transactions transaction) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 1,
      child: ListTile(
        contentPadding: const EdgeInsets.all(8.0),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: transaction.amount > 0
                ? Colors.green.withOpacity(0.2)
                : Colors.red.withOpacity(0.2),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(
            transaction.icon,
            color: transaction.amount > 0 ? Colors.green : Colors.red,
          ),
        ),
        title: Text(
          transaction.title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(transaction.category),
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
                _getStatusText(transaction.statut),
                style: TextStyle(
                  color: _getStatusColor(transaction.statut),
                  fontSize: 12,
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

  String _getStatusText(String status) {
    switch (status) {
      case "0":
        return "en attente de validations";
      case "1":
        return "en attente de traitement";
      case "2":
        return "en cours de traitement";
      case "3":
        return "Recharge de crédit Effectuée";
      case "4":
        return "en Attente de validation du forfait";
      case "5":
        return "Forfait Validé";
      default:
        return "Statut inconnu";
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case "0":
        return Colors.orangeAccent;
      case "1":
        return Colors.blue;
      case "2":
        return Colors.deepPurple;
      case "3":
        return Colors.green;
      case "4":
        return Colors.orange;
      case "5":
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Filtrer les transactions'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildFilterRadio('Toutes'),
                _buildFilterRadio('Recharge de Credit'),
                _buildFilterRadio('Activation de forfait'),
                _buildFilterRadio('Reinitialisation des Post'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFilterRadio(String category) {
    return RadioListTile<String>(
      title: Text(category),
      value: category,
      groupValue: _currentFilter,
      onChanged: (value) {
        setState(() {
          _currentFilter = value!;
        });
        Navigator.pop(context);
      },
    );
  }
}

class Transactions {
  final String? id;
  final String title;
  final String order;
  final double amount;
  final DateTime date;
  final String category;
  late final String statut;
  final String accesstoken;
  final String payToken;
  final IconData icon;

  Transactions({
    this.id,
    required this.title,
    required this.payToken,
    required this.accesstoken,
    required this.amount,
    required this.date,
    required this.category,
    required this.order,
    required this.statut,
    required this.icon,
  });

  factory Transactions.fromMap(Map<String, dynamic> map) {
    return Transactions(
      id: map['idtransact']?.toString(),
      title: map['numerocamtel']?.toString() ?? '',
      amount: double.tryParse(map['amount']?.toString() ?? '0') ?? 0,
      date: DateTime.parse(map['heure']!.toString()),
      category: map['numeroorange']?.toString() ?? '',
      statut: map['status']?.toString() ?? '0',
      accesstoken: map['accesstoken']?.toString() ?? '0',
      order: map['order']?.toString() ?? '0',
      payToken: map['payToken']?.toString() ?? '0',
      icon: _getIconForCategory(map['numeroorange']?.toString() ?? ''),
    );
  }

  static IconData _getIconForCategory(String category) {
    if (category.contains('Recharge')) return Icons.credit_card;
    if (category.contains('forfait')) return Icons.sim_card;
    if (category.contains('Post')) return Icons.restart_alt;
    return Icons.receipt;
  }
}
