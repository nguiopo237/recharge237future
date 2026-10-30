import 'package:flutter_test/flutter_test.dart';
import 'package:recharge237_serveur/service/ussd/orange_ussd_manager.dart';

/// [ORANGE 31/10/2026] Tests des helpers PURS du parcours Orange : composition
/// du code USSD et masquage du code secret.
///
/// Le point le plus sensible n'est pas la syntaxe du code, c'est la fuite : un
/// transfert Orange embarque le code secret DANS la chaîne composée. Si ces
/// fonctions se trompent, le secret finit dans `ussd_log` (Firestore) et dans
/// les alertes Telegram.
void main() {
  group('Gabarits', () {
    test('les deux gabarits fournis sont valides', () {
      expect(gabaritOrangeValide(kOrangeCreditGoodDeal), isTrue);
      expect(gabaritOrangeValide(kOrangeCreditTransfert), isTrue);
      expect(kOrangeCreditGoodDeal, '#205*1*{numero}*{montant}#');
      expect(kOrangeCreditTransfert, '#189*1*{numero}*{montant}*{code}#');
    });

    test('un gabarit incomplet est refusé (aucun code bancal composé)', () {
      for (final String g in <String>[
        '',
        '#205*1#',
        '*205*1*{numero}#', // montant manquant
        '#205*1*{montant}#', // numéro manquant
        '#205*1*{numero}*{montant}', // pas de dièse final
        '205*1*{numero}*{montant}#', // ne commence pas par * ou #
      ]) {
        expect(gabaritOrangeValide(g), isFalse, reason: g);
      }
    });
  });

  group('Composition du code', () {
    test('vente Good Deal : numéro et montant, aucun secret', () {
      expect(
        orangeCreditCode(
          gabarit: kOrangeCreditGoodDeal,
          numero: '674583531',
          montant: '100',
          codeSecret: '',
        ),
        '#205*1*674583531*100#',
      );
    });

    test('transfert simple : le code secret est la dernière étape', () {
      expect(
        orangeCreditCode(
          gabarit: kOrangeCreditTransfert,
          numero: '650000000',
          montant: '500',
          codeSecret: '19930',
        ),
        '#189*1*650000000*500*19930#',
      );
    });

    test('numéro et montant sont nettoyés (espaces, 237, séparateurs)', () {
      expect(
        orangeCreditCode(
          gabarit: kOrangeCreditGoodDeal,
          numero: '+237 6 74 58 35 31',
          montant: '1 000 F',
          codeSecret: '',
        ),
        '#205*1*674583531*1000#',
      );
      expect(numeroOrange('00237674583531'), '674583531');
      expect(numeroOrange('674583531'), '674583531');
    });
  });

  group('Masquage du code secret', () {
    test('le secret disparaît du journal, pas le reste du code', () {
      final String code = orangeCreditCode(
        gabarit: kOrangeCreditTransfert,
        numero: '674583531',
        montant: '100',
        codeSecret: '19930',
      );
      final String masque = masquerCodeSecret(code, '19930');

      expect(masque, '#189*1*674583531*100*****#');
      expect(masque.contains('19930'), isFalse);
      expect(masque, contains('674583531'));
    });

    test('toutes les occurrences sont masquées', () {
      final String masque = masquerCodeSecret('*1*1234*1234#', '1234');
      expect(masque.contains('1234'), isFalse);
      // Deux occurrences remplacées, et le reste du code est intact.
      expect('****'.allMatches(masque).length, 2);
      expect(masque.startsWith('*1'), isTrue);
      expect(masque.endsWith('#'), isTrue);
    });

    test('sans secret, le code reste lisible (vente Good Deal)', () {
      const String code = '#205*1*674583531*100#';
      expect(masquerCodeSecret(code, ''), code);
    });
  });
}
