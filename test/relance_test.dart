import 'package:flutter_test/flutter_test.dart';
import 'package:recharge237_serveur/service/server/order_filters.dart';
import 'package:recharge237_serveur/service/server/transaction_claimer.dart';

/// [28/10/2026] Une commande ne s'exécute qu'UNE fois ; la seule seconde
/// tentative possible est une relance demandée par l'admin (app serveur ou
/// Firestore). Ces tests verrouillent cette règle.
void main() {
  group('relaunchStatusFor', () {
    test('chaque type repart dans son statut d\'exécution', () {
      expect(relaunchStatusFor({'operateur_cible': 'camtel_pre'}), '1');
      expect(relaunchStatusFor({'operateur_cible': 'camtel_post'}), '6');
      expect(relaunchStatusFor({'operateur_cible': 'mtn_airtime'}), '1');
      expect(relaunchStatusFor({'operateur_cible': 'mtn_forfait'}), '0');
      expect(
          relaunchStatusFor({'operateur_cible': 'mtn_forfait_activate'}), '1');
    });

    // [ORANGE 31/10/2026] Le flow USSD Orange existe désormais : la commande
    // se relance comme MTN, en repassant simplement à « à livrer » (1).
    test('Orange crédit se relance comme MTN', () {
      expect(relaunchStatusFor({'operateur_cible': 'orange_airtime'}), '1');
    });

    test('anciennes commandes sans type : CAMTEL prépayé', () {
      expect(relaunchStatusFor({}), '1');
    });
  });

  group('canRelaunch', () {
    test('jamais sur une commande déjà livrée ou non payée', () {
      for (final String s in ['0', '3', '10', '21', '31', '34', '5']) {
        expect(canRelaunch({'status': s, 'operateur_cible': 'camtel_pre'}),
            isFalse,
            reason: 'statut $s');
      }
    });

    test('jamais sur une commande déjà en file automatique', () {
      for (final String s in ['1', '6', '11']) {
        expect(canRelaunch({'status': s, 'operateur_cible': 'mtn_airtime'}),
            isFalse,
            reason: 'statut $s');
      }
    });

    test('oui sur un échec ou un blocage', () {
      for (final String s in ['4', '9', '22', '32', '35', '2', '20', '33']) {
        expect(canRelaunch({'status': s, 'operateur_cible': 'mtn_airtime'}),
            isTrue,
            reason: 'statut $s');
      }
    });

    test('pas deux relances d\'affilée', () {
      expect(
        canRelaunch({
          'status': '22',
          'operateur_cible': 'mtn_airtime',
          'relance_demandee': true,
        }),
        isFalse,
      );
    });
  });

  group('TransactionClaimer.canClaim', () {
    test('première tentative acceptée', () {
      expect(
        TransactionClaimer.canClaim(
            status: '1', owner: '', attempts: 0, relaunchRequested: false),
        isTrue,
      );
    });

    test('déjà tentée une fois : jamais reprise automatiquement', () {
      expect(
        TransactionClaimer.canClaim(
            status: '1', owner: '', attempts: 1, relaunchRequested: false),
        isFalse,
      );
      // Même si le téléphone a effacé son serverId à la main.
      expect(
        TransactionClaimer.canClaim(
            status: '1',
            owner: 'ancien',
            attempts: 3,
            relaunchRequested: false),
        isFalse,
      );
    });

    test('une relance demandée passe, une seule fois', () {
      expect(
        TransactionClaimer.canClaim(
            status: '1', owner: 'ancien', attempts: 2, relaunchRequested: true),
        isTrue,
      );
    });

    test('statut non exécutable refusé même en relance', () {
      expect(
        TransactionClaimer.canClaim(
            status: '3', owner: '', attempts: 1, relaunchRequested: true),
        isFalse,
      );
    });
  });
}
