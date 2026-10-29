import 'package:flutter_test/flutter_test.dart';
import 'package:recharge237_serveur/service/server/network_watch.dart';
import 'package:recharge237_serveur/service/ussd/session_config.dart';

/// [RESEAU 28/10/2026] La surveillance ne doit alerter que sur les SIM
/// réellement confiées au téléphone, une seule fois par emplacement.
void main() {
  // [CADENCE 28/10/2026] Le rythme de contrôle suit la charge : soutenu
  // quand une commande attend (fenêtre de réseau à attraper), relâché sinon.
  group('cadence de surveillance', () {
    test('5 min quand des commandes attendent', () {
      expect(NetworkWatch.cadenceFor(pending: true), const Duration(minutes: 5));
    });

    test('30 min quand la file est vide', () {
      expect(NetworkWatch.cadenceFor(pending: false), const Duration(minutes: 30));
    });
  });

  group('networkTargets', () {
    test('téléphone MTN seul : une seule SIM surveillée', () {
      const SessionConfig c = SessionConfig(
        mtn: SimConfig(slot: 0, pin: '1234'),
        orange: SimConfig(slot: 1),
        camtelPre: SimConfig(slot: 0),
        camtelPost: SimConfig(slot: 1),
        mtnConfigured: true,
      );
      final List<SimTarget> t = networkTargets(c);
      expect(t.length, 1);
      expect(t.first.slot, 0);
      expect(t.first.operator, 'mtn');
    });

    test('MTN + CAMTEL sur deux emplacements', () {
      const SessionConfig c = SessionConfig(
        mtn: SimConfig(slot: 0, pin: '1234'),
        orange: SimConfig(slot: 1),
        camtelPre: SimConfig(slot: 1, pin: '5678'),
        camtelPost: SimConfig(slot: 1, pin: '5678'),
        mtnConfigured: true,
        camtelConfigured: true,
      );
      final List<SimTarget> t = networkTargets(c);
      expect(t.map((SimTarget e) => e.slot).toList(), <int>[0, 1]);
      expect(t.map((SimTarget e) => e.operator).toList(), <String>['mtn', 'camtel']);
    });

    test('même carte en prépayée et postpayée : un seul contrôle', () {
      const SessionConfig c = SessionConfig(
        mtn: SimConfig(slot: 0),
        orange: SimConfig(slot: 1),
        camtelPre: SimConfig(slot: 0, pin: '5678'),
        camtelPost: SimConfig(slot: 0, pin: '5678'),
        camtelConfigured: true,
      );
      final List<SimTarget> t = networkTargets(c);
      expect(t.length, 1);
      expect(t.first.slot, 0);
      expect(t.first.operator, 'camtel');
    });

    test('aucune SIM configurée : rien à surveiller', () {
      const SessionConfig c = SessionConfig(
        mtn: SimConfig(slot: 0),
        orange: SimConfig(slot: 1),
        camtelPre: SimConfig(slot: 0),
        camtelPost: SimConfig(slot: 1),
      );
      expect(networkTargets(c), isEmpty);
    });

    test('emplacement forcé par l\'admin respecté', () {
      const SessionConfig c = SessionConfig(
        mtn: SimConfig(slot: 1, pin: '9999'),
        orange: SimConfig(slot: 0),
        camtelPre: SimConfig(slot: 0),
        camtelPost: SimConfig(slot: 0),
        mtnConfigured: true,
      );
      expect(networkTargets(c).single.slot, 1);
    });
  });

  group('targetForOrder', () {
    const SessionConfig c = SessionConfig(
      mtn: SimConfig(slot: 0, pin: '1234'),
      orange: SimConfig(slot: 1, pin: '0000'),
      camtelPre: SimConfig(slot: 1, pin: '5678'),
      camtelPost: SimConfig(slot: 1, pin: '5678'),
      mtnConfigured: true,
      camtelConfigured: true,
      orangeConfigured: true,
    );

    test('chaque type de commande vise la bonne SIM', () {
      expect(targetForOrder(c, 'mtn_airtime')?.slot, 0);
      expect(targetForOrder(c, 'mtn_forfait')?.slot, 0);
      expect(targetForOrder(c, 'mtn_forfait_activate')?.slot, 0);
      expect(targetForOrder(c, 'camtel_pre')?.slot, 1);
      expect(targetForOrder(c, 'camtel_post')?.slot, 1);
      // Anciennes commandes sans operateur_cible : CAMTEL prépayé.
      expect(targetForOrder(c, '')?.operator, 'camtel');
    });

    test('opérateur absent du téléphone : aucune cible', () {
      const SessionConfig mtnSeul = SessionConfig(
        mtn: SimConfig(slot: 0, pin: '1234'),
        orange: SimConfig(slot: 1),
        camtelPre: SimConfig(slot: 1),
        camtelPost: SimConfig(slot: 1),
        mtnConfigured: true,
      );
      expect(targetForOrder(mtnSeul, 'camtel_pre'), isNull);
      expect(targetForOrder(mtnSeul, 'orange_airtime'), isNull);
      expect(targetForOrder(mtnSeul, 'type_inconnu'), isNull);
    });
  });

  group('messages lisibles', () {
    test('heure', () {
      expect(heureDe(DateTime(2026, 10, 28, 9, 5)), '09:05');
      expect(heureDe(null), '—');
    });

    test('durée', () {
      expect(dureeCourte(const Duration(seconds: 40)), '40 s');
      expect(dureeCourte(const Duration(minutes: 12)), '12 min');
      expect(dureeCourte(const Duration(hours: 2, minutes: 5)), '2 h 05');
    });
  });
}
