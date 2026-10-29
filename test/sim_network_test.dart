import 'package:flutter_test/flutter_test.dart';
import 'package:recharge237_serveur/service/ussd/sim_network.dart';

/// [RESEAU 28/10/2026] La garde réseau décide si une session USSD peut partir.
/// Ces tests fixent les cas réellement rencontrés en production (SIM hors
/// service, mode avion, carte verrouillée) et le refus d'un mauvais opérateur.
void main() {
  SimNetworkState state({
    int slot = 0,
    bool known = true,
    bool registered = false,
    bool emergencyOnly = false,
    bool airplaneMode = false,
    String operator = '',
    String carrier = 'MTN',
    String mccMnc = '62401',
    String networkLabel = 'OUT_OF_SERVICE',
    String simState = 'READY',
  }) =>
      SimNetworkState(
        slot: slot,
        known: known,
        registered: registered,
        emergencyOnly: emergencyOnly,
        airplaneMode: airplaneMode,
        operatorName: operator,
        carrier: carrier,
        mccMnc: mccMnc,
        signalLevel: 3,
        networkLabel: networkLabel,
        simState: simState,
        detail: '',
      );

  group('usable', () {
    test('SIM enregistrée : la session peut partir', () {
      final SimNetworkState s = state(
        registered: true,
        operator: 'MTN',
        networkLabel: 'IN_SERVICE',
      );
      expect(s.usable, isTrue);
      expect(s.transient, isFalse);
    });

    test('SIM hors service : refus, et attente justifiée', () {
      final SimNetworkState s = state();
      expect(s.usable, isFalse);
      expect(s.transient, isTrue, reason: 'le réseau peut revenir seul');
    });

    test('mode avion : refus immédiat, inutile d\'attendre', () {
      final SimNetworkState s = state(airplaneMode: true);
      expect(s.usable, isFalse);
      expect(s.transient, isFalse);
      expect(s.reason, contains('Mode avion'));
    });

    test('aucune SIM dans l\'emplacement : refus immédiat', () {
      final SimNetworkState s = state(simState: 'ABSENT', carrier: '');
      expect(s.usable, isFalse);
      expect(s.transient, isFalse);
      expect(s.reason, contains('Aucune SIM'));
    });

    test('carte verrouillée par PIN : refus immédiat, motif explicite', () {
      final SimNetworkState s = state(simState: 'PIN_REQUIRED');
      expect(s.usable, isFalse);
      expect(s.transient, isFalse);
      expect(s.reason, contains('PIN'));
    });

    test('état illisible : on ne bloque pas sur notre propre aveuglement', () {
      final SimNetworkState s = state(known: false);
      expect(s.usable, isTrue);
    });
  });

  group('reason', () {
    test('nomme la SIM, l\'opérateur et la cause', () {
      final SimNetworkState s = state(
        slot: 1,
        operator: 'MTN',
        carrier: 'MTN',
        emergencyOnly: true,
        networkLabel: 'EMERGENCY_ONLY',
      );
      final String r = s.reason;
      expect(r, contains('SIM 2'));
      expect(r, contains('MTN'));
      expect(r, contains('urgence'));
      expect(r, contains('Aucun code USSD composé'));
    });
  });

  group('operatorMismatch', () {
    test('même opérateur : rien à signaler', () {
      expect(state(mccMnc: '62401').operatorMismatch('mtn'), isNull);
      expect(state(mccMnc: '62403').operatorMismatch('camtel'), isNull);
      expect(state(mccMnc: '62402').operatorMismatch('orange'), isNull);
    });

    test('mauvaise carte dans l\'emplacement : refus explicite', () {
      final String? m = state(carrier: 'CAMTEL', mccMnc: '62403')
          .operatorMismatch('mtn');
      expect(m, isNotNull);
      expect(m, contains('CAMTEL'));
      expect(m, contains('MTN'));
    });

    test('carte étrangère ou illisible : on ne refuse jamais', () {
      // 302720 = réseau nord-américain : SIM camerounaise en itinérance, ou
      // lecture partielle. Aucun refus ne doit en découler.
      expect(state(mccMnc: '302720').operatorMismatch('mtn'), isNull);
      expect(state(mccMnc: '').operatorMismatch('mtn'), isNull);
    });

    test('opérateur attendu inconnu : aucune contrainte', () {
      expect(state(mccMnc: '62401').operatorMismatch('operateur_inconnu'), isNull);
    });
  });

  group('SimNetworkCheck', () {
    test('sans problème : la session part', () {
      final SimNetworkCheck c =
          SimNetworkCheck(state(registered: true), null);
      expect(c.ok, isTrue);
      expect(c.reason, isNotEmpty);
    });

    test('avec problème : le motif du problème prime', () {
      final SimNetworkCheck c = SimNetworkCheck(
        state(),
        'SIM 1 (CAMTEL) : une commande MTN ne peut pas y etre executee.',
      );
      expect(c.ok, isFalse);
      expect(c.reason, contains('CAMTEL'));
    });
  });

  test('lecture d\'une carte au format natif', () {
    final SimNetworkState s = SimNetworkState.fromMap(1, <String, dynamic>{
      'known': true,
      'registered': true,
      'emergencyOnly': false,
      'airplaneMode': false,
      'operator': 'MTN',
      'carrier': 'MTN',
      'mccMnc': '62401',
      'signalLevel': 2,
      'stateLabel': 'IN_SERVICE',
      'simState': 'READY',
      'detail': '',
    });
    expect(s.slot, 1);
    expect(s.usable, isTrue);
    expect(s.mccMnc, '62401');
    expect(s.operatorMismatch('mtn'), isNull);
  });

  test('lecture sans carte SIM', () {
    final SimNetworkState s = SimNetworkState.fromMap(0, <String, dynamic>{
      'known': true,
      'registered': false,
      'emergencyOnly': false,
      'airplaneMode': false,
      'simState': 'ABSENT',
      'carrier': '',
      'operator': '',
      'mccMnc': '',
      'signalLevel': 0,
      'stateLabel': 'ABSENT',
      'detail': "aucune SIM dans l'emplacement 1",
    });
    expect(s.usable, isFalse);
    expect(s.simReady, isFalse);
    expect(s.reason, contains('Aucune SIM'));
  });
}
