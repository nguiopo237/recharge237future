import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:intl/intl.dart';
import 'package:projettest/component/style/middletext.dart';
import 'package:sizer/sizer.dart';

import '../../../main.dart';
import '../../callapi/orange/generatepay.dart';
import '../../controlleur/home_controlleur.dart';
import '../../controlleur/transact_controlleur.dart';

class ForfaitScreen extends StatefulWidget {
  const ForfaitScreen({super.key});

  @override
  State<ForfaitScreen> createState() => _ForfaitScreenState();
}

class _ForfaitScreenState extends State<ForfaitScreen> {
  // Liste de transactions exemple
  final List<Transaction> transactions = [
    // Transaction(
    //   id: '1',
    //   title: 'Achat en ligne',
    //   amount: -49.99,
    //   date: DateTime.now().subtract(const Duration(days: 2)),
    //   category: 'Recharge de Credit',
    //   icon: Icons.shopping_cart,
    // ),
    // Transaction(
    //   id: '2',
    //   title: 'forfait',
    //   amount: 2500.00,
    //   date: DateTime.now().subtract(const Duration(days: 5)),
    //   category: 'Activation de forfait',
    //   icon: Icons.work,
    // ),
    // Transaction(
    //   id: '3',
    //   title: 'Post Init',
    //   amount: -32.50,
    //   date: DateTime.now().subtract(const Duration(days: 1)),
    //   category: 'Reinitialisation des Post',
    //   icon: Icons.restaurant,
    // ),
    // Transaction(
    //   id: '4',
    //   title: 'Abonnement Spotify',
    //   amount: -9.99,
    //   date: DateTime.now().subtract(const Duration(days: 3)),
    //   category: 'Divertissement',
    //   icon: Icons.music_note,
    // ),
    // Transaction(
    //   id: '5',
    //   title: 'Transfert reçu',
    //   amount: 150.00,
    //   date: DateTime.now().subtract(const Duration(days: 4)),
    //   category: 'Transfert',
    //   icon: Icons.account_balance_wallet,
    // ),
  ];
  late ScrollController _controller;
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  void scrollToIndex1() {
    double itemHeight = 80.0; // Hauteur approximative de chaque élément
    _controller.animateTo(
      itemHeight * 60, // Multipliez par l'index souhaité (1 dans ce cas)
      duration: Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
  }

  // Filtre actuel
  String _currentFilter = 'Toutes';

  TransactControlleur controlleur = TransactControlleur();

  getforfait({order,payToken}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
      Container(width: 100.w,
        child: Wrap(children: [
          Container(
            child: StreamBuilder(
              stream: firestore
                  .collection('Forfait')
              // .where("idphone",isEqualTo: idphone)
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

                  return ListView.builder(

                    controller: _controller,
                    reverse: false,
                    shrinkWrap: true,
                    itemCount: snapshot.data!.docs.length,
                    itemBuilder: (context, index) {
                      final data = snapshot.data!.docs![index];
                      return    Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: FilterChip(
                          backgroundColor: Colors.blue,
                          label: Middletext(
                            text: data["name"],
                            color: Colors.white,
                          ),
                          selected: _currentFilter == "1",
                          onSelected: (selected) {
                            APIORANGE.updateValueforfait(
                                order: order,
                                payToken: payToken
                            );
                            print("yes");

                          },
                        ),
                      );
                    },
                  );
                }
              },
            ),
          ),
        ],),
      )

      ],
    );
  }

  Widget _buildForfaitGrid({required String order, required String payToken}) {
    return StreamBuilder<QuerySnapshot>(
      stream: firestore.collection('Forfait').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Text('Erreur : ${snapshot.error}');
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Text('Aucun forfait disponible');
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 2.0,
            mainAxisSpacing: 4.0,
            crossAxisSpacing: 4.0,
          ),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final data = snapshot.data!.docs[index];

            return Padding(
              padding: const EdgeInsets.all(8.0),
              child: Card(
                elevation: 2,
                child: InkWell(
                  onTap: () {
                    Get.back();
                    APIORANGE.updateValueforfait(
                        order: order,
                        payToken: payToken,
                      code: data['code'],
                    );
                    print("yes");
                  },
                  // onTap: () => _showValidationDialog(
                  //   order: order,
                  //   payToken: payToken,
                  //   forfaitName: data['name'],
                  // ),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Middletext(
                        text: data['name'],
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }


  // List<QueryDocumentSnapshot<Map<String, dynamic>>>transact =[];
  //
  // double totalBalance = 0;

  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    _controller = ScrollController(
      initialScrollOffset: 0.0, // Décalage initial optionnel
    );
    scrollToIndex1();
  }

  @override
  Widget build(BuildContext context) {
    // Calcul du solde total

    // Transactions filtrées
    List<Transaction> filteredTransactions = _currentFilter == 'Toutes'
        ? transactions
        : transactions
            .where((transaction) => transaction.category == _currentFilter)
            .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes Numeros'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filtres rapides
          _buildQuickFilters(),
          // Liste des transactions
          Expanded(
            child: _buildTransactionsList(filteredTransactions),
          ),
          // getforfait()
        ],
      ),
      // floatingActionButton: FloatingActionButton(
      //   onPressed: () {
      //     // Ajouter une nouvelle transaction
      //     _showAddTransactionDialog();
      //   },
      //   child: const Icon(Icons.add),
      // ),
    );
  }

  Widget _buildIncomeOutcome(
      {required String label, required double amount, required Color color}) {
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
    // Liste des catégories uniques
    Set<String> categories = transactions.map((t) => t.category).toSet();
    List<String> allCategories = ['Toutes',"User","PArse"];

    return SizedBox(
      height: 60,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: allCategories.length,
        itemBuilder: (context, index) {
          String category = allCategories[index];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: FilterChip(
              label: Text(category),
              selected: _currentFilter == category,
              onSelected: (selected) {
                setState(() {
                  _currentFilter = selected ? category : 'Toutes';
                });
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildTransactionsList(List<Transaction> transactions) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: StreamBuilder(
        stream: firestore
            .collection('Transact')
            .where("idphone", isEqualTo: idphone)
            .orderBy("heure", descending: false)
            // .where("status",isEqualTo: "1")
            // .where("status",isEqualTo: "0")
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

            return ListView.builder(
              controller: _controller,
              reverse: true,
              shrinkWrap: true,
              itemCount: snapshot.data!.docs.where((doc) {
                return doc['idphone'] == idphone;
              }).length,
              itemBuilder: (context, index) {
                final data = snapshot.data?.docs.where((doc) {
                  controlleur.transact.value = snapshot.data!.docs;

                  return doc['idphone'] == idphone;
                }).toList();
                final datas = data![index];

                Transaction post = Transaction(
                  statut: datas['status'].toString(),
                  title: datas['numerocamtel'].toString(),
                  idtransact:datas['idtransact'].toString(),
                  icon: datas['status'].toString()=="3"?Icons.shopping_cart: datas['status'].toString()=="5"? Icons.work : Icons.restaurant,
                  category: datas['numeroorange'].toString(),
                  date: DateTime.parse(datas['heure'].toString()),
                  amount: double.parse(datas['amount'].toString()),

                  // amount: datas['amount'].toString(),
                  // numeror: datas['numeroorange'].toString(),
                  // numeros: datas['numerocamtel'].toString(),
                  // heure: datas['heure'].toString(),
                  // accesstoken: datas['accesstoken'],
                  // payToken: datas['payToken'],
                  // retry: int.parse(datas['retry']),
                  // statut: int.parse(datas['status']),
                  // id: int.parse(datas['idtransact']),
                  // idphone: datas['idphone']
                );

                return InkWell(
                    onTap: () {
                      c.getmodal(sectionview: _buildForfaitGrid(payToken:  datas['payToken'],order: datas['order']));
                    },
                    child: _buildTransactionItem(post));
              },
            );
          }
        },
      ),
    );
  }

  Widget _buildTransactionItem(Transaction transaction) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 1,
      child: ListTile(
        contentPadding: EdgeInsets.all(8.0),
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
                "${transaction.statut == "0" ? "en attente de validations " : transaction.statut == "1" ? "en attente de traitement" : transaction.statut == "2" ? "en cour de traitement" : transaction.statut == "3"?  "Recharge de credit Effectuée":  transaction.statut == "4"?'en Attente de validation du forfait': "Forfait Valider "}",
                style: TextStyle(
                    color: transaction.statut == "0"
                        ? Colors.orangeAccent
                        : transaction.statut == "1"
                        ? Colors.blue
                        : transaction.statut == "2"
                        ? Colors.deepPurple
                        :  transaction.statut == "3" ?Colors.green:transaction.statut == "5"?Colors.blueAccent:Colors.cyan),
              ),
            ),



            Expanded(child: Middletext(text: transaction.idtransact.toString()??"",fontWeight: FontWeight.bold,))
          ],
        ),
      ),
    );
  }

  void _showFilterDialog() {
    Set<String> categories = transactions.map((t) => t.category).toSet();
    List<String> allCategories = ['Toutes', ...categories];

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Filtrer les transactions'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: allCategories.length,
              itemBuilder: (context, index) {
                String category = allCategories[index];
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
              },
            ),
          ),
        );
      },
    );
  }

  void _showAddTransactionDialog() {
    // Contrôleurs pour le formulaire
    final titleController = TextEditingController();
    final amountController = TextEditingController();
    String selectedCategory = 'Shopping';

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Ajouter une transaction'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'Titre',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: amountController,
                  decoration: const InputDecoration(
                    labelText: 'Montant',
                    border: OutlineInputBorder(),
                    prefixText: '€ ',
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedCategory,
                  items: [
                    'Shopping',
                    'Revenu',
                    'Nourriture',
                    'Divertissement',
                    'Transfert'
                  ].map((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    );
                  }).toList(),
                  onChanged: (value) {
                    selectedCategory = value!;
                  },
                  decoration: const InputDecoration(
                    labelText: 'Catégorie',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () {
                // Ajouter la nouvelle transaction
                final newTransaction = Transaction(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  title: titleController.text,
                  amount: double.tryParse(amountController.text) ?? 0,
                  date: DateTime.now(),
                  category: selectedCategory,
                  icon: _getIconForCategory(selectedCategory),
                  statut: '0',
                );

                setState(() {
                  transactions.insert(0, newTransaction);
                });
                Navigator.pop(context);
              },
              child: const Text('Ajouter'),
            ),
          ],
        );
      },
    );
  }

  IconData _getIconForCategory(String category) {
    switch (category) {
      case 'Shopping':
        return Icons.shopping_cart;
      case 'Revenu':
        return Icons.work;
      case 'Nourriture':
        return Icons.restaurant;
      case 'Divertissement':
        return Icons.movie;
      case 'Transfert':
        return Icons.account_balance_wallet;
      default:
        return Icons.receipt;
    }
  }
}

class Transaction {
  final String? id;
  final String title;
  final double amount;
  final DateTime date;
  final String category;
  final String statut;
  final String? idtransact;
  final IconData icon;

  Transaction({
    this.id,
    this.idtransact,
    required this.title,
    required this.statut,
    required this.amount,
    required this.date,
    required this.category,
    required this.icon,
  });
}
