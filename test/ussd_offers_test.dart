import 'package:flutter_test/flutter_test.dart';
import 'package:recharge237_serveur/service/ussd/ussd_screens.dart';

/// Écrans réels MTN Cameroun (*126*7*<numéro>#, relevés le 28/10/2026).
///
/// [PRIX 30/10/2026] Attention à la lecture : « C=50F » est la COMMISSION du
/// revendeur, pas le prix. Le prix client est le dépôt de gauche
/// (« Depot de 100F », « 1200U », « 500U »). Ces tests exigeaient auparavant
/// la commission comme prix (50, 60, 15, 25) : c'était le bug financier.
/// Ce fichier vérifie aussi le prix rejeté sur la ligne suivante
/// (« 2) 1200U=6700U+1 » puis « C=60F »), pour que l'offre ne soit jamais
/// vendue sans prix.
const String _page1 = '''
Offres MTN Boost pour 237677156949:
1) Depot de 100F; C=50F
2) 1200U=6700U+1
3170U+732MB/7D:
C=60F
3) 500U=1GB/30D: C=25F
4) 1000U=2.1GB/30D: C=50F
5) 2
00. Next
''';

const String _page2 = '''
Offres MTN Boost pour 237677156949:
6) 200U=1GB/7D: C=15F
7) 500U=2GB/7D: C=30F
''';

void main() {
  group('offerRecords — prix', () {
    test('prix en fin de ligne', () {
      final List<UssdOffer> offres = offerRecords(<String>[_page1]);
      final UssdOffer o1 = offres.firstWhere((o) => o.index == '1');
      // 100 F (dépôt), pas 50 F (commission « C=50F »).
      expect(o1.price, 100);
      expect(o1.label, contains('Depot de 100F'));
    });

    test('prix rejeté sur la ligne suivante', () {
      final List<UssdOffer> offres = offerRecords(<String>[_page1]);
      final UssdOffer o2 = offres.firstWhere((o) => o.index == '2');
      // Le prix est le dépôt « 1200U » ; « C=60F » reste une commission.
      expect(o2.price, 1200);
      expect(o2.label, contains('3170U+732MB/7D'));
    });

    test('une offre sans prix reste sans prix (jamais 0)', () {
      final List<UssdOffer> offres = offerRecords(<String>[_page1]);
      final UssdOffer o5 = offres.firstWhere((o) => o.index == '5');
      expect(o5.price, isNull);
    });

    test('« 00. Next » n\'est pas une offre', () {
      final List<UssdOffer> offres = offerRecords(<String>[_page1]);
      expect(offres.any((o) => o.index == '00'), isFalse);
      expect(offres.length, 5);
    });
  });

  group('offerRecords — pages', () {
    test('les offres des pages suivantes sont conservées avec leur page', () {
      final List<UssdOffer> offres = offerRecords(<String>[_page1, _page2]);
      final UssdOffer o6 = offres.firstWhere((o) => o.index == '6');
      // « 200U=1GB/7D: C=15F » → 200 F à payer, 15 F de commission.
      expect(o6.price, 200);
      expect(o6.page, 1);
      expect(offres.firstWhere((o) => o.index == '1').page, 0);
    });

    test('même numéro sur deux pages : deux offres distinctes', () {
      final List<UssdOffer> offres = offerRecords(<String>[
        '1) Pack 500Mo a 500F',
        '1) Pack 5Go a 5000F',
      ]);
      expect(offres.length, 2);
      expect(offres[0].price, 500);
      expect(offres[1].price, 5000);
      expect(offres[0].page, 0);
      expect(offres[1].page, 1);
    });

    test('toMap ne perd ni le prix ni la page', () {
      final Map<String, Object?> map = offerRecords(<String>[_page1])
          .firstWhere((o) => o.index == '3')
          .toMap();
      expect(map['index'], '3');
      expect(map['price'], 500);
      expect(map['page'], 0);
      expect(map['label'], contains('C=25F'));
    });
  });

  group('findOptionForLabel — activation', () {
    test('retrouve la touche de l\'offre achetée sur l\'écran', () {
      expect(findOptionForLabel(_page1, '500U=1GB/30D: C=25F'), '3');
      expect(findOptionForLabel(_page2, '500U=2GB/7D: C=30F'), '7');
    });

    test('ne répond rien quand l\'offre n\'est pas affichée', () {
      expect(findOptionForLabel(_page1, '500U=2GB/7D: C=30F'), isNull);
    });

    test('un libellé trop court ne sert pas de repère', () {
      expect(findOptionForLabel('1) 2', '2'), isNull);
    });
  });
}
