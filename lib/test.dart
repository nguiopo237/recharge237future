import 'dart:async';
// import 'package:another_telephony/telephony.dart';
import 'package:clipboard/clipboard.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:get/get.dart';
import 'package:internet_connection_checker/internet_connection_checker.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:projettest/service/callapi/mail/api.dart';
import 'package:projettest/service/controlleur/widget_controlleur.dart' show c;
import 'package:projettest/service/view/transact/transact_page.dart';
import 'package:sizer/sizer.dart';
import 'package:ussd_flutter/ussd_service.dart';
import 'package:ussd_launcher/ussd_launcher.dart';
import 'component/style/middletext.dart';
import 'main.dart';

class Session extends StatefulWidget {
  const Session({super.key});

  @override
  State<Session> createState() => _SessionState();
}

class _SessionState extends State<Session> {
  final TextEditingController _ussdController = TextEditingController();
  final List<TextEditingController> _optionControllers = [];
  List<String> _ussdMessages = [];
  bool _isLoading = false;
  List<Map<String, dynamic>> _simCards = [];
  int? _selectedSlotIndex;
  String _sessionStatus = '';
  final UssdService _ussdService = UssdService();
  StreamSubscription<UssdResponse>? _ussdSubscription;

  // Services et streams
  final EventChannel _accessibilityChannel = EventChannel('com.example.projettest');
  StreamSubscription<dynamic>? _accessibilitySubscription;
  String _eventLog = "En attente d'événements...";

  // SMS
  // final Telephony telephony = Telephony.instance;
  // List<SmsMessage> _smsMessages = [];
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  // Firebase
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  late ScrollController _scrollController;

  // Variables d'état
  int _currentIndex = 0;
  bool _isUssdSessionActive = false;

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    _scrollController = ScrollController();

    // Initialiser les services dans l'ordre
    await _loadSimCards();
     _initializeConnectivity();
    _initializeUssdListener();
    _initializeAccessibilityListener();
    // _initializeSmsListener();
    _initializeFirestoreListener();
    _initializeBackgroundService();

    // Configurer l'écouteur USSD
    _setupUssdResponseListener();
  }

  Future<void> _loadSimCards() async {
    var status = await Permission.phone.request();
    if (status.isGranted) {
      try {
        final simCards = await UssdLauncher.getSimCards();
        setState(() {
          _simCards = simCards;
          if (_simCards.isNotEmpty) {
            _selectedSlotIndex = _simCards[0]['slotIndex'];
            _initializeOptionFields();
          }
        });
      } catch (e) {
        debugPrint("Erreur lors du chargement des cartes SIM: $e");
      }
    } else {
      debugPrint("Permission téléphone non accordée");
    }
  }

  void _initializeOptionFields() {
    // Initialiser 3 champs d'options
    for (int i = 0; i < 3; i++) {
      _addOptionField();
    }
  }

  void _initializeConnectivity() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
          (List<ConnectivityResult> results) async {
        if (results.isNotEmpty) {
          final hasConnection = await InternetConnectionChecker().hasConnection;
          c.isDeviceConnected.value = hasConnection;

          if (!hasConnection && !c.isAlertSet.value) {
            _showConnectionSnackbar("noconnection".tr, Colors.grey);
          } else if (hasConnection) {
            _showConnectionSnackbar("Connexion rétablie".tr, Colors.green);
          }
        }
      },
    );
  }

  void _initializeUssdListener() {
    UssdLauncher.setUssdMessageListener(_onUssdMessageReceived);
  }

  void _initializeAccessibilityListener() {
    _accessibilitySubscription = _accessibilityChannel.receiveBroadcastStream().listen(
          (dynamic event) {
        setState(() {
          _eventLog = event.toString();
        });
      },
      onError: (error) {
        setState(() {
          _eventLog = "Erreur: $error";
        });
      },
    );
  }

  // void _initializeSmsListener() {
  //   telephony.listenIncomingSms(
  //     onNewMessage: (SmsMessage message) {
  //       debugPrint("Nouveau SMS reçu: ${message.body}");
  //       _saveSmsToFirestore(message);
  //       setState(() {
  //         _smsMessages.insert(0, message);
  //       });
  //     },
  //     listenInBackground: false,
  //   );
  // }

  void _initializeFirestoreListener() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToInitialPosition();
    });
  }

  Future<void> _initializeBackgroundService() async {
    final service = FlutterBackgroundService();
    await service.startService();
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

  void _onUssdMessageReceived(String message) {
    debugPrint("Message USSD reçu: $message");

    setState(() {
      _isLoading=false;
      _ussdMessages.add(message);
      if (message.contains("completed") ||
          message.contains("cancelled") ||
          message.contains("solde")) {
        _sessionStatus = "Session USSD terminée.";
        _isUssdSessionActive = false;
      }
    });
  }

  // void _saveSmsToFirestore(SmsMessage message) {
  //   try {
  //     firestore.collection('sms').add({
  //       'sender': message.address,
  //       'message': message.body,
  //       'date': DateTime.now().toString(),
  //       'deviceId': idphone,
  //     });
  //   } catch (e) {
  //     debugPrint("Erreur Firestore SMS: $e");
  //   }
  // }

  void _showConnectionSnackbar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: color,
        duration: const Duration(seconds: 5),
        content: Text(message),
      ),
    );
  }

  void _scrollToInitialPosition() {
    if (_scrollController.hasClients) {
      final itemHeight = 80.0;
      _scrollController.animateTo(
        itemHeight * 60,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

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

  Future<void> _launchMultiSessionUssd() async {
    if (_isUssdSessionActive) {
      _ussdMessages.add("Une session USSD est déjà en cours");
      return;
    }

    setState(() {
      _isLoading = true;
      _isUssdSessionActive = true;
      _ussdMessages.clear();
      _sessionStatus = '';
    });

    try {
      final List<String> options = _optionControllers
          .where((controller) => controller.text.isNotEmpty)
          .map((controller) => controller.text)
          .toList();

      debugPrint("Lancement USSD multi-session");
      debugPrint("Code: ${_ussdController.text}");
      debugPrint("Slot: $_selectedSlotIndex");
      debugPrint("Options: $options");

      final result = await UssdLauncher.multisessionUssd(
        code: _ussdController.text,
        slotIndex: _selectedSlotIndex ?? 0,
        options: options,
      );

      if (result != null) {
        debugPrint("Résultat USSD: $result");
      }
    } catch (e) {
      _ussdMessages.add('\nErreur : ${e.toString()}');
    } finally {
      setState(() {
        _isLoading = false;
        _isUssdSessionActive = false;
      });
    }
  }

  Future<void> _executeUssdWithOptions({amount,number}) async {
    // Pré-remplir les options selon la SIM sélectionnée
    if (_selectedSlotIndex == 0) {
      // SIM 1
      _ussdController.text = _ussdController.text.isEmpty ? "*825*1*2*1*2#" : _ussdController.text;
      _setOptionValues(["620046820"]);
    } else {
      // SIM 2
      final clipboardText = await FlutterClipboard.paste();
      _ussdController.text = _ussdController.text.isEmpty ? "*550*2*${number==null?"620499600":number}*${amount==null?"5000":amount}#" : _ussdController.text;
      _setOptionValues(["2006"]);
      // Pas d'options pour cette SIM
    }

    await _sendUssdCode(_ussdController.text);
    await _launchMultiSessionUssd();
  }

  void _setOptionValues(List<String> values) {
    for (int i = 0; i < values.length && i < _optionControllers.length; i++) {
      _optionControllers[i].text = values[i];
    }
  }

  void _addOptionField() {
    if (_optionControllers.length < 10) {
      setState(() {
        _optionControllers.add(TextEditingController());
        _isLoading=false;
      });
    }
  }

  void _removeOptionField() {
    if (_optionControllers.isNotEmpty) {
      setState(() {
        _optionControllers.removeLast().dispose();
      });
    }
  }

  void _clearUssdMessages() {
    setState(() {
      _ussdMessages.clear();
      _sessionStatus = '';
    });
  }

  Future<void> _testSimCards() async {
    try {
      final simCard = await UssdLauncher.getSimCards();
      debugPrint("Cartes SIM disponibles: $simCard");
    } catch (e) {
      debugPrint("Erreur test SIM: $e");
    }
  }

  @override
  void dispose() {
    // Nettoyer tous les controllers et subscriptions
    _ussdController.dispose();
    for (var controller in _optionControllers) {
      controller.dispose();
    }
    _ussdSubscription?.cancel();
    _accessibilitySubscription?.cancel();
    _connectivitySubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_isLoading || _isUssdSessionActive) {
          return false;
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Session USSD'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _clearUssdMessages,
              tooltip: 'Effacer les messages',
            ),
          ],
        ),
        body: IndexedStack(
          index: _currentIndex,
          children: [
            _buildUssdSessionView(),
            _buildTransactionsView(),
          ],
        ),
        bottomNavigationBar: _buildBottomNavigationBar(),
      ),
    );
  }

  Widget _buildUssdSessionView() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Section test SIM
            TextButton(
              onPressed: _testSimCards,
              child: const Text("Tester les cartes SIM"),
            ),

            // Sélecteur SIM
            _buildSimSelector(),
            const SizedBox(height: 16),

            // Champ USSD
            TextField(
              controller: _ussdController,
              decoration: const InputDecoration(
                labelText: 'Code USSD',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.dialpad),
              ),
            ),
            const SizedBox(height: 16),

            // Section options
            _buildOptionsSection(),
            const SizedBox(height: 16),

            // Bouton d'exécution
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _executeUssdWithOptions,
              icon: _isLoading
                  ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
                  : const Icon(Icons.send),
              label: Text(_isLoading ? 'En cours...' : 'Lancer Session USSD'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
            ),
            const SizedBox(height: 16),

            // Messages USSD
            _buildUssdMessagesView(),

            // Statut de session
            if (_sessionStatus.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  _sessionStatus,
                  style: const TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSimSelector() {
    return DropdownButtonFormField<int>(
      value: _selectedSlotIndex,
      decoration: const InputDecoration(
        labelText: 'Carte SIM',
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.sim_card),
      ),
      items: _simCards.map((sim) {
        return DropdownMenuItem<int>(
          value: sim['slotIndex'],
          child: Text(
            "${sim['displayName']} (${sim['carrierName'] ?? 'Inconnu'})",
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),
      onChanged: (value) {
        setState(() {
          _selectedSlotIndex = value;
          _updateUssdCodeForSim(value);
        });
      },
    );
  }

  void _updateUssdCodeForSim(int? slotIndex) {
    if (slotIndex == 1) {
      // _ussdController.text = "*825*1*2*1*2#";
      // _setOptionValues(["1", "2", "1"]);

      _ussdController.text = _ussdController.text.isEmpty ? "*550*2*620499600*5000#" : _ussdController.text;
      _setOptionValues(["2006"]);

    } else {
      _ussdController.text = "";
      for (var controller in _optionControllers) {
        controller.clear();
      }
    }
  }

  Widget _buildOptionsSection() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Options USSD',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: _addOptionField,
                  child: const Text('Ajouter'),
                ),
                ElevatedButton(
                  onPressed: _optionControllers.isNotEmpty ? _removeOptionField : null,
                  child: const Text('Retirer'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ..._optionControllers.asMap().entries.map((entry) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: TextField(
                  controller: entry.value,
                  decoration: InputDecoration(
                    labelText: 'Option ${entry.key + 1}',
                    border: const OutlineInputBorder(),
                    suffixIcon: entry.key < 9 ? null : const Icon(Icons.warning, color: Colors.orange),
                  ),
                  enabled: entry.key < 9,
                ),
              );
            }),
            if (_optionControllers.length >= 9)
              const Text(
                'Maximum 10 options',
                style: TextStyle(color: Colors.orange, fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildUssdMessagesView() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Messages USSD',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Container(
              height: 200,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.blueAccent),
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: _ussdMessages.isEmpty
                  ? const Center(
                child: Text(
                  'Aucun message USSD',
                  style: TextStyle(color: Colors.blueAccent),
                ),
              )
                  : ListView.builder(
                reverse: true,
                itemCount: _ussdMessages.length,
                itemBuilder: (context, index) {
                  final message = _ussdMessages[_ussdMessages.length - 1 - index];
                  final isLatest = index == 0;
                  return Container(
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                    decoration: BoxDecoration(
                      border: isLatest
                          ? const Border(bottom: BorderSide(color: Colors.red, width: 2))
                          : null,
                    ),
                    child: Text(
                      message,
                      style: TextStyle(
                        color: isLatest ? Colors.red : Colors.blue,
                        fontWeight: isLatest ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionsView() {
    return StreamBuilder<QuerySnapshot>(
      stream: firestore
          .collection('Transact')
          .orderBy("heure", descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Erreur : ${snapshot.error}'));
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('Aucune transaction disponible'));
        }

        return ListView.builder(
          controller: _scrollController,
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final doc = snapshot.data!.docs[index];
            final transaction = Transactions.fromMap(doc.data() as Map<String, dynamic>);
            return _buildTransactionItem(transaction);
          },
        );
      },
    );
  }

  Widget _buildTransactionItem(Transactions transaction) {
    final color = transaction.amount > 0 ? Colors.green : Colors.red;
    final icon = transaction.amount > 0 ? Icons.arrow_upward : Icons.arrow_downward;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 2,
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(icon, color: color),
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
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              NumberFormat.currency(locale: 'fr_FR', symbol: 'FCFA')
                  .format(transaction.amount),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            _buildStatusBadge(transaction.statut),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    final Map<String, Map<String, dynamic>> statusConfig = {
      "0": {"text": "En attente", "color": Colors.orange},
      "1": {"text": "En traitement", "color": Colors.blue},
      "2": {"text": "En cours", "color": Colors.deepPurple},
      "3": {"text": "Effectuée", "color": Colors.green},
      "4": {"text": "Validation", "color": Colors.cyan},
      "5": {"text": "Validé", "color": Colors.blueAccent},
    };

    final config = statusConfig[status] ?? {"text": "Inconnu", "color": Colors.grey};

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: config["color"]!.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: config["color"] as Color, width: 1),
      ),
      child: Text(
        config["text"] as String,
        style: TextStyle(
          color: config["color"] as Color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildBottomNavigationBar() {
    return BottomNavigationBar(
      currentIndex: _currentIndex,
      onTap: (index) {
        setState(() {
          _currentIndex = index;
        });
      },
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.dialpad),
          label: 'USSD',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.history),
          label: 'Transactions',
        ),
      ],
    );
  }
}

// Classes auxiliaires (gardez vos classes existantes)
class Apss extends StatefulWidget {
  @override
  _ApssState createState() => _ApssState();
}

class _ApssState extends State<Apss> {
  final UssdService _ussdService = UssdService();
  String _ussdResult = 'Aucune réponse USSD';
  StreamSubscription<UssdResponse>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = _ussdService.ussdResponseStream.listen((response) {
      setState(() {
        _ussdResult = 'Message: ${response.message}\nÉtat: ${response.state}';
      });
    }, onError: (error) {
      setState(() {
        _ussdResult = 'Erreur: ${error.message}';
      });
    });
  }

  Future<void> _sendUssdCode(String ussdCode) async {
    try {
      await _ussdService.sendUssd(ussdCode);
    } catch (e) {
      setState(() {
        _ussdResult = 'Erreur: $e';
      });
    }
  }

  Future<void> _checkUssdSupport() async {
    try {
      final isSupported = await _ussdService.isUssdSupported();
      setState(() {
        _ussdResult = 'USSD Supporté: $isSupported';
      });
    } catch (e) {
      setState(() {
        _ussdResult = 'Erreur: $e';
      });
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Test USSD')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () => _sendUssdCode('#123#'),
              child: const Text('Tester USSD'),
            ),
            ElevatedButton(
              onPressed: _checkUssdSupport,
              child: const Text('Vérifier support'),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(_ussdResult),
            ),
          ],
        ),
      ),
    );
  }
}