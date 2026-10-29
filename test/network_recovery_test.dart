import 'package:flutter_test/flutter_test.dart';
import 'package:recharge237_serveur/service/server/network_recovery.dart';

/// Politique du cycle « mode avion » de récupération réseau.
///
/// Ces règles protègent l'argent du client et la connexion du serveur : une
/// tentative pendant une session USSD couperait une opération déjà payée, et
/// une tentative trop rapprochée n'aurait aucun effet (l'inscription n'a pas
/// encore eu le temps de se faire).
void main() {
  final DateTime maintenant = DateTime(2026, 10, 28, 20, 0);

  bool possible({
    String label = 'OUT_OF_SERVICE',
    bool airplane = false,
    String simState = 'READY',
    Duration? down = const Duration(minutes: 20),
    Duration? sinceLast,
    bool busy = false,
  }) =>
      NetworkRecovery.shouldAttempt(
        serviceLabel: label,
        airplaneMode: airplane,
        simState: simState,
        downSince: down == null ? null : maintenant.subtract(down),
        lastAttempt:
            sinceLast == null ? null : maintenant.subtract(sinceLast),
        now: maintenant,
        sessionBusy: busy,
      );

  group('quand le cycle est autorisé', () {
    test('carte hors réseau depuis assez longtemps', () {
      expect(possible(), isTrue);
      expect(possible(label: 'EMERGENCY_ONLY'), isTrue);
    });
  });

  group('quand le cycle doit être refusé', () {
    test('coupure trop récente : elle peut se rétablir seule', () {
      expect(possible(down: const Duration(minutes: 3)), isFalse);
      expect(possible(down: const Duration(minutes: 8)), isTrue);
    });

    test('un cycle il y a moins de 30 minutes', () {
      expect(possible(sinceLast: const Duration(minutes: 10)), isFalse);
      expect(possible(sinceLast: const Duration(minutes: 31)), isTrue);
    });

    test('jamais pendant une session USSD', () {
      expect(possible(busy: true), isFalse);
    });

    test('mode avion déjà activé : réglage volontaire, on n\'y touche pas', () {
      expect(possible(airplane: true), isFalse);
    });

    test('carte absente ou verrouillée : un cycle n\'y changerait rien', () {
      expect(possible(simState: 'ABSENT'), isFalse);
      expect(possible(simState: 'PIN_REQUIRED'), isFalse);
      expect(possible(simState: 'PUK_REQUIRED'), isFalse);
      expect(possible(simState: 'NETWORK_LOCKED'), isFalse);
    });

    test('carte en service : rien à faire', () {
      expect(possible(label: 'IN_SERVICE'), isFalse);
    });

    test('aucune coupure enregistrée', () {
      expect(possible(down: null), isFalse);
    });
  });

  group('durées du cycle', () {
    test('le cycle complet tient en moins de 2 minutes hors attente native', () {
      final Duration total =
          NetworkRecovery.airplaneOn + NetworkRecovery.registrationWait;
      expect(total.inSeconds, lessThan(120));
    });

    test('30 minutes minimum entre deux cycles', () {
      expect(NetworkRecovery.minInterval, const Duration(minutes: 30));
    });
  });
}
