import 'package:flutter/material.dart';
import 'package:ussd_launcher/ussd_launcher.dart';
import 'package:permission_handler/permission_handler.dart';

class UssdService {
  static UssdService? _instance;
  static UssdService get instance => _instance ??= UssdService._();

  UssdService._();

  // Callback pour les réponses USSD
  Function(String)? onUssdResponse;
  Function(String)? onUssdError;

  /// Vérifier et demander les permissions
  Future<bool> checkAndRequestPermissions() async {
    final phoneStatus = await Permission.phone.status;
    // final telephonyStatus = await Permission.telephony.status;

    if (!phoneStatus.isGranted) {
      final requests = <Permission>[];
      if (!phoneStatus.isGranted) requests.add(Permission.phone);
      // if (!telephonyStatus.isGranted) requests.add(Permission.telephony);

      final results = await requests.request();
      return results.values.every((status) => status.isGranted);
    }
    return true;
  }

  /// Écouter les messages USSD en temps réel
  void startListening() {
    UssdLauncher.setUssdMessageListener((message) {
      print('USSD Response: $message');

      // Vérifier si c'est une erreur
      if (message.contains('ERROR') ||
          message.contains('Failed') ||
          message.contains('Connection problem')) {
        onUssdError?.call(message);
      } else {
        onUssdResponse?.call(message);
      }
    });
  }

  /// Arrêter l'écoute
  void stopListening() {
    UssdLauncher.removeUssdMessageListener();
  }

  /// Envoyer une requête USSD simple
  Future sendSingleUssd({
    required String code,
    int slotIndex = 0,
    int timeoutMs = 30000,
  }) async {
    try {
      final hasPermission = await checkAndRequestPermissions();
      if (!hasPermission) {
        onUssdError?.call('Permissions non accordées');
        return null;
      }

      startListening();

      final result = await UssdLauncher.sendUssdRequest(
        ussdCode: code,
        subscriptionId: slotIndex,
      ).timeout(Duration(milliseconds: timeoutMs));

      return result;
    } catch (e) {
      onUssdError?.call('Erreur: $e');
      return null;
    }
  }

  /// Envoyer une requête USSD multi-session avec options
  Future<void> sendMultisessionUssd({
    required String code,
    required List<String> options,
    int slotIndex = 0,
    int initialDelayMs = 2000,
    int optionDelayMs = 1500,
    String overlayMessage = 'Traitement en cours...',
    Function(String)? onStepResponse,
  }) async {
    try {
      final hasPermission = await checkAndRequestPermissions();
      if (!hasPermission) {
        onUssdError?.call('Permissions non accordées');
        return;
      }

      startListening();

      onStepResponse?.call('Initialisation de la session USSD...');

      await UssdLauncher.multisessionUssd(
        code: code,
        slotIndex: slotIndex,
        options: options,
        initialDelayMs: initialDelayMs,
        optionDelayMs: optionDelayMs,
        overlayMessage: overlayMessage,
      );

      onStepResponse?.call('Session USSD terminée avec succès');
    } catch (e) {
      onUssdError?.call('Erreur multi-session: $e');
    }
  }

  /// Méthode optimisée pour le rechargement de compte
  Future<void> rechargeCompte({
    required String numero,
    required String montant,
    required String operateur, // 'MTN', 'ORANGE', 'CAMTEL'
  }) async {
    String ussdCode;
    List<String> options;

    switch (operateur.toUpperCase()) {
      case 'MTN':
        ussdCode = '*126#';
        options = ['1', numero, montant, '1']; // Exemple
        break;
      case 'ORANGE':
        ussdCode = '#144#';
        options = ['2', numero, montant]; // Exemple
        break;
      default:
        onUssdError?.call('Opérateur non supporté');
        return;
    }

    await sendMultisessionUssd(
      code: ussdCode,
      options: options,
      initialDelayMs: 3000,
      optionDelayMs: 2000,
      onStepResponse: (message) {
        print('Étape: $message');
      },
    );
  }

  /// Vérifier le solde
  Future checkBalance(String code) async {
    return await sendSingleUssd(code: code);
  }
}

// Widget d'exemple d'utilisation
class UssdScreen extends StatefulWidget {
  const UssdScreen({super.key});

  @override
  State<UssdScreen> createState() => _UssdScreenState();
}

class _UssdScreenState extends State<UssdScreen> {
  final UssdService _ussdService = UssdService.instance;
  final List<String> _messages = [];
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();

    // Configurer les callbacks
    _ussdService.onUssdResponse = (response) {
      setState(() {
        _messages.add('📱 Réponse: $response');
        _isProcessing = false;
      });
      _showDialog('Réponse USSD', response);
    };

    _ussdService.onUssdError = (error) {
      setState(() {
        _messages.add('❌ Erreur: $error');
        _isProcessing = false;
      });
      _showDialog('Erreur', error, isError: true);
    };
  }

  @override
  void dispose() {
    _ussdService.stopListening();
    super.dispose();
  }

  void _showDialog(String title, String message, {bool isError = false}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _executeUssd() async {
    setState(() {
      _isProcessing = true;
      _messages.clear();
    });

    await _ussdService.sendMultisessionUssd(
      code: '*825#',
      options: ['1', '2', '1', '2'],
      slotIndex: 0,
      initialDelayMs: 20000,
      optionDelayMs: 2000,
      overlayMessage: 'Veuillez patienter...',
      onStepResponse: (step) {
        setState(() {
          _messages.add('🔄 $step');
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Service USSD'),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: _messages.length,
              itemBuilder: (context, index) => ListTile(
                title: Text(_messages[index]),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton(
              onPressed: _isProcessing ? null : _executeUssd,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
              child: _isProcessing
                  ? const CircularProgressIndicator()
                  : const Text('EXÉCUTER USSD'),
            ),
          ),
        ],
      ),
    );
  }
}