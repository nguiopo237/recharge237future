import 'package:flutter_test/flutter_test.dart';
import 'package:recharge237_serveur/service/notification/forfait_reminder_service.dart';

/// [RELANCES 31/10/2026] Calcul du jalon de relance (J-3 → J-0) et
/// anti-doublon.
///
/// Deux erreurs coûteraient cher en production :
///  - un mauvais calcul de jour ⇒ rappel envoyé avec le mauvais texte, ou
///    jamais envoyé (forfait expirant aujourd'hui compté « J-1 ») ;
///  - un anti-doublon défaillant ⇒ le même rappel repart à chaque passage du
///    job (toutes les minutes) et le client reçoit une avalanche de push.
void main() {
  group('joursRestants', () {
    final DateTime aujourdhui = DateTime(2026, 10, 31, 8, 30);

    test('compte en dates, pas en heures', () {
      // Expire aujourd'hui à 23 h 59 : c'est bien « J-0 » toute la journée.
      expect(joursRestants(DateTime(2026, 10, 31, 23, 59), aujourdhui), 0);
      expect(joursRestants(DateTime(2026, 10, 31, 0, 1), aujourdhui), 0);
      expect(joursRestants(DateTime(2026, 11, 1, 0, 0), aujourdhui), 1);
      expect(joursRestants(DateTime(2026, 11, 3, 23, 59), aujourdhui), 3);
    });

    test('une échéance passée ne produit plus de relance', () {
      expect(joursRestants(DateTime(2026, 10, 30, 23, 59), aujourdhui), isNull);
      expect(joursRestants(DateTime(2026, 9, 1), aujourdhui), isNull);
    });

    test('au-delà de la fenêtre de 4 jours, le job ignore l\'échéance', () {
      // 4 jours : hors des jalons J-3 → J-0.
      expect(joursRestants(DateTime(2026, 11, 4, 9), aujourdhui), 4);
    });
  });

  group('dejaRelance', () {
    test('détecte un jalon déjà envoyé', () {
      expect(dejaRelance(<dynamic>[3], 3), isTrue);
      expect(dejaRelance(<dynamic>[3, 2, 1], 2), isTrue);
      expect(dejaRelance(<dynamic>[3], 0), isFalse);
    });

    test('accepte les nombres relus de Firestore', () {
      // Firestore rend des `int`, mais un import JSON peut donner des `double`.
      expect(dejaRelance(<dynamic>[2.0], 2), isTrue);
    });

    test('champ absent ou mal formé : considéré comme « jamais relancé »', () {
      expect(dejaRelance(null, 1), isFalse);
      expect(dejaRelance(<dynamic>[], 1), isFalse);
      expect(dejaRelance('3', 3), isFalse);
      expect(dejaRelance(<dynamic>['3'], 3), isFalse);
    });
  });

  test('les quatre jalons attendus sont bien déclarés', () {
    expect(joursDeRappel, <int>[3, 2, 1, 0]);
  });
}
