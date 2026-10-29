import 'package:flutter_test/flutter_test.dart';
import 'package:recharge237_serveur/service/server/order_filters.dart';

void main() {
  group('isRecentOrder', () {
    final now = DateTime.utc(2026, 10, 27, 23, 0);

    test('commande récente (format écrit par les apps)', () {
      expect(isRecentOrder('2026-10-27 22:30:00.000Z', now: now), isTrue);
    });
    test('commande de plus de 12 h ignorée', () {
      expect(isRecentOrder('2026-10-27 10:00:00.000Z', now: now), isFalse);
      expect(isRecentOrder('2026-03-01 10:00:00.000Z', now: now), isFalse);
    });
    test('heure absente ou illisible ignorée', () {
      expect(isRecentOrder(null, now: now), isFalse);
      expect(isRecentOrder('', now: now), isFalse);
      expect(isRecentOrder('27/10/26 10:00 PM', now: now), isFalse);
    });
    test('horloge client légèrement en avance tolérée', () {
      expect(isRecentOrder('2026-10-27 23:05:00.000Z', now: now), isTrue);
      expect(isRecentOrder('2026-10-28 02:00:00.000Z', now: now), isFalse);
    });
  });

  group('isCamtelNumber', () {
    test('numéros CAMTEL acceptés', () {
      expect(isCamtelNumber('620199999'), isTrue);
      expect(isCamtelNumber('621000000'), isTrue);
      expect(isCamtelNumber('242123456'), isTrue);
      expect(isCamtelNumber('243123456'), isTrue);
      expect(isCamtelNumber('237 620 19 99 99'), isTrue);
    });
    test('numéros MTN / Orange refusés', () {
      expect(isCamtelNumber('677123456'), isFalse);
      expect(isCamtelNumber('650123456'), isFalse);
      expect(isCamtelNumber('699123456'), isFalse);
      expect(isCamtelNumber('655123456'), isFalse);
      expect(isCamtelNumber('62019999'), isFalse);
      expect(isCamtelNumber(''), isFalse);
    });
  });

  group('isCamtelTransferAccepted', () {
    test('réponse CAMTEL de succès reconnue', () {
      expect(
        isCamtelTransferAccepted('System is processing your requestion by SMS, please wait'),
        isTrue,
      );
    });
    test('réponse vide ou erreur', () {
      expect(isCamtelTransferAccepted(''), isFalse);
      expect(isCamtelTransferAccepted('Solde insuffisant'), isFalse);
      expect(isCamtelTransferAccepted('No USSD response yet.'), isFalse);
    });
  });

  group('isAmountAllowed (minimum opérateur 100 F)', () {
    test('accepte 100 et au-delà', () {
      expect(isAmountAllowed(100), isTrue);
      expect(isAmountAllowed('100'), isTrue);
      expect(isAmountAllowed(5000), isTrue);
      expect(isAmountAllowed('25 000'), isTrue); // espaces tolérés
    });
    test('refuse en dessous de 100', () {
      expect(isAmountAllowed(99), isFalse);
      expect(isAmountAllowed('25'), isFalse);
      expect(isAmountAllowed(0), isFalse);
      expect(isAmountAllowed(null), isFalse);
      expect(isAmountAllowed('abc'), isFalse);
    });
    test('message de refus explicite', () {
      expect(amountTooSmallReason(25), contains('25'));
      expect(amountTooSmallReason(25), contains('100'));
    });
  });

  test('statuts surveillés par le serveur', () {
    expect(kActionableStatuses, containsAll(['0', '1', '6', '9', '11']));
    expect(kActionableStatuses, isNot(contains('3')));
    expect(kActionableStatuses.length, lessThanOrEqualTo(30)); // limite whereIn
  });
}
