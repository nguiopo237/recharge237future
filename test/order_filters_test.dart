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
        isCamtelTransferAccepted(
            'System is processing your requestion by SMS, please wait'),
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

  group('routesForHandles', () {
    test('handles vides ou all : tout écouter', () {
      expect(routesForHandles(const <String>[]), isNull);
      expect(routesForHandles(const <String>['all']), isNull);
    });

    test('valeur inconnue : tout écouter par prudence', () {
      expect(routesForHandles(const <String>['camtel_pre', 'inconnu']), isNull);
    });

    test('téléphone CAMTEL prépayé : ni Good Deal ni MTN', () {
      final routes = routesForHandles(const <String>['camtel_pre'])!;
      expect(routes.map((r) => r.toString()), <String>['1/9/11']);
    });

    test('téléphone postpayé', () {
      expect(
          routesForHandles(const <String>['camtel_post'])!
              .map((r) => r.toString()),
          <String>['6/9']);
    });

    test('téléphone MTN : crédit, requête et activation Good Deal', () {
      final routes =
          routesForHandles(const <String>['mtn_airtime', 'mtn_forfait'])!;
      expect(routes.map((r) => r.toString()), <String>[
        '1/11 · mtn_airtime',
        '0 · mtn_forfait',
        '1/11 · mtn_forfait_activate',
        '1/11 · mtn_bundle',
      ]);
    });

    test('au plus 30 disjonctions (limite Firestore)', () {
      final routes = routesForHandles(kOperationTypes)!;
      final int n =
          routes.fold<int>(0, (int a, OrderRoute r) => a + r.statuses.length);
      expect(n, lessThanOrEqualTo(30));
    });
  });

  test('relance d\'un forfait du catalogue MTN', () {
    expect(
        relaunchStatusFor(<String, dynamic>{'operateur_cible': 'mtn_bundle'}),
        '1');
  });

  test('handles de l\'écran Serveurs (sous-types MTN) : filtre conservé', () {
    final routes = routesForHandles(
        const <String>['mtn_airtime', 'mtn_forfait', 'mtn_forfait_activate']);
    expect(routes, isNotNull);
    expect(routes!.map((r) => r.operateur), contains('mtn_bundle'));
  });

  // [CONFIG SIM 29/10/2026] Téléphone non configuré.
  test('marqueur none : aucune écoute, aucune commande acceptée', () {
    expect(routesForHandles(<String>['none']), isEmpty);
    expect(handlesOperation(<String>['none'], 'camtel_pre'), isFalse);
    expect(handlesOperation(<String>[], 'camtel_pre'), isTrue);
  });

  // [OFFRES PERSO 29/10/2026] Good Deal Orange.
  //
  // [ORANGE 30/10/2026] Tant que le flow USSD Orange n'est pas branché
  // (`OrangeUssdManager.deliveryImplemented == false`), un téléphone ne doit
  // PAS écouter les commandes Orange : elles resteraient en échec alors que le
  // client a payé. Elles doivent rester au statut « payée, à livrer » (1), que
  // l'admin traite à la main. Le routage est donc VIDE pour un téléphone
  // dédié Orange (et non `null`, qui voudrait dire « toutes les commandes »).
  test('Orange non implémenté : aucune route écoutée (commande laissée à l’admin)', () {
    expect(routesForHandles(<String>['orange_forfait']), isEmpty);
    expect(routesForHandles(<String>['orange_forfait_activate']), isEmpty);
    expect(routesForHandles(<String>['orange_airtime']), isEmpty);
    // Un téléphone mixte garde ses autres opérateurs, sans Orange.
    expect(
      routesForHandles(<String>['orange_airtime', 'camtel_pre']).toString(),
      '[1/9/11]',
    );
  });

  test('Good Deal Orange : statuts de relance inchangés', () {
    expect(
        relaunchStatusFor(
            <String, dynamic>{'operateur_cible': 'orange_forfait'}),
        '0');
    expect(
        relaunchStatusFor(
            <String, dynamic>{'operateur_cible': 'orange_forfait_activate'}),
        '1');
  });
}
