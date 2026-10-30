// [MESURE 28/10/2026] Chronométrage du moteur de session USSD.
//
// Un faux opérateur répond en 2 ms : tout le temps mesuré ici est donc celui
// QUE NOTRE LOGICIEL AJOUTE (pauses de saisie, aller-retours du canal natif,
// lecture des écrans). C'est la partie que l'on peut réduire ; le reste, en
// production, est le temps de réponse réel de MTN.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recharge237_serveur/service/ussd/ussd_session.dart';

const MethodCodec _codec = StandardMethodCodec();

Future<void> _deliver(String screen) async {
  final ByteData data =
      _codec.encodeMethodCall(MethodCall('onUssdMessageReceived', screen));
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage('ussd_launcher', data, (_) {});
}

/// Écrans réels de MTN (relevés en production le 28/10) + réponses attendues.
const List<({String screen, String answer})> _mtnFlow = [
  (
    screen: "MTN Mobile Money\n1) Depot d'argent\n2) Retrait d'argent\n"
        "3) Paiement factures\n4) Vendre du credit\n5) Operations\n"
        "6) Prets et Avances\n7) Mon compte\n8) MTN Boost",
    answer: '4',
  ),
  (screen: 'Entrez le montant', answer: '100'),
  (screen: 'Entez le Numero de telephone:', answer: '674583531'),
  (
    screen: "Confirmer l'achat du credit de 100FCFA pour 237674583531. "
        "Entrez votre code PIN:",
    answer: '1234',
  ),
];

const String _finalScreen =
    'Recharge de 100 FCFA à 237674583531 le 2026-10-28 08:14:50 effectue avec succes. Nouveau solde: 86,443FCFA';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late int step;
  late List<int> replyStamps;

  setUp(() {
    step = 0;
    replyStamps = <int>[];
    final Stopwatch clock = Stopwatch()..start();

    // Canal natif : numérotation, saisie, fermeture.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('r237/ussd'),
            (MethodCall call) async {
      switch (call.method) {
        case 'serviceReady':
          return true;
        case 'cancel':
          return false;
        case 'dial':
          // L'opérateur « répond » le premier menu 2 ms plus tard.
          Timer(const Duration(milliseconds: 2), () {
            unawaited(_deliver(_mtnFlow[0].screen));
          });
          return true;
        case 'reply':
          final String sent = (call.arguments as Map)['text'] as String;
          expect(sent, _mtnFlow[step].answer,
              reason: 'étape ${step + 1} : mauvaise réponse envoyée');
          replyStamps.add(clock.elapsedMilliseconds);
          step++;
          Timer(const Duration(milliseconds: 2), () {
            unawaited(_deliver(
                step < _mtnFlow.length ? _mtnFlow[step].screen : _finalScreen));
          });
          return true;
      }
      return null;
    });

    // Plugin : service d'accessibilité actif.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('ussd_launcher'),
            (MethodCall call) async {
      if (call.method == 'isAccessibilityEnabled') return true;
      return null;
    });
  });

  test('4 étapes MTN : mesure du temps ajouté par le logiciel', () async {
    final Stopwatch total = Stopwatch()..start();
    final UssdRunResult run = await UssdSessionRunner.instance.run(
      code: '*126#',
      slot: 0,
      rules: <UssdRule>[
        UssdRule(
          label: 'menu-vente-credit',
          answer: (String s, Set<String> done) =>
              s.contains('Vendre du credit') ? '4' : null,
        ),
        UssdRule(
          label: 'montant',
          answer: (String s, Set<String> done) =>
              s.toLowerCase().contains('montant') ? '100' : null,
        ),
        UssdRule(
          label: 'numero',
          answer: (String s, Set<String> done) =>
              s.toLowerCase().contains('numero') ? '674583531' : null,
        ),
        UssdRule(
          label: 'pin',
          answer: (String s, Set<String> done) =>
              s.toLowerCase().contains('code pin') ? '1234' : null,
          secret: true,
          commits: true,
        ),
      ],
      isSuccess: (String s) => s.toLowerCase().contains('succes'),
      firstTimeout: const Duration(seconds: 3),
      stepTimeout: const Duration(seconds: 3),
      finalTimeout: const Duration(seconds: 3),
    );
    total.stop();

    // ignore: avoid_print
    print('OUTCOME=${run.outcome.name} total=${total.elapsedMilliseconds} ms');
    for (final UssdStepTiming t in run.timings) {
      // ignore: avoid_print
      print('  ${t.line}');
    }
    // ignore: avoid_print
    print(run.timingsLog);

    expect(run.outcome, UssdOutcome.success);
    expect(step, 4, reason: 'les 4 écrans doivent recevoir leur réponse');
    expect(run.timings.length, 4);
    // Chaque étape ne doit coûter que la pause de saisie (25-70 ms) et
    // quelques millisecondes de traitement : au-delà, c'est un temps mort.
    for (final UssdStepTiming t in run.timings) {
      expect(t.replyMs, lessThan(150),
          reason: 'étape ${t.step} : ${t.replyMs} ms pour répondre');
      // L'étape 1 englobe la pause volontaire avant la numérotation (100 à
      // 250 ms, le temps qu'une fenêtre précédente se ferme).
      expect(t.screenWaitMs, lessThan(t.step == 1 ? 350 : 120),
          reason: 'étape ${t.step} : ${t.screenWaitMs} ms de latence interne');
    }
    // 4 étapes × (≈47 ms de pause + overhead) : très en dessous d'une seconde.
    expect(total.elapsedMilliseconds, lessThan(1000));
    expect(run.timingsLog, contains('4 étapes'));
  });

  test('les mesures sont sérialisables pour Firestore', () {
    const UssdStepTiming t = UssdStepTiming(
      step: 2,
      label: 'montant',
      screenWaitMs: 1200,
      replyMs: 48,
    );
    expect(t.toMap(), <String, Object?>{
      'step': 2,
      'label': 'montant',
      'wait_ms': 1200,
      'reply_ms': 48,
    });
  });
}
