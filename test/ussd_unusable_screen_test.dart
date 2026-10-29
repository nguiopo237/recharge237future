import 'package:flutter_test/flutter_test.dart';
import 'package:recharge237_serveur/service/ussd/ussd_screens.dart';

void main() {
  group('isUnusableScreen', () {
    test('titre seul (téléphone verrouillé) → écran vide', () {
      // Relevé le 28/10/2026 à 04:11 : MIUI n'a peint que le titre.
      expect(isUnusableScreen('MTN Mobile Money'), isTrue);
      expect(isUnusableScreen('MTN Mobile Money\n'), isTrue);
      expect(isUnusableScreen(''), isTrue);
    });

    test('menus, questions et verdicts restent exploitables', () {
      expect(
        isUnusableScreen(
            'MTN Mobile Money\n1) Depot d argent\n4) Vendre du credit'),
        isFalse,
      );
      expect(isUnusableScreen('Entrez le montant'), isFalse);
      expect(isUnusableScreen('Entrez le numero du beneficiaire'), isFalse);
      expect(isUnusableScreen('Entrez votre code PIN'), isFalse);
      expect(
        isUnusableScreen(
            'Recharge de 100 FCFA a 237674583531 effectuee avec succes'),
        isFalse,
      );
      expect(
        isUnusableScreen('Probleme de connexion ou code IHM non valide.'),
        isFalse,
      );
    });

    test('un écran porteur de chiffres n\'est jamais jugé vide', () {
      expect(isUnusableScreen('Votre solde est 5000 FCFA'), isFalse);
    });
  });
}
