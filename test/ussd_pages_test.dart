import 'package:flutter_test/flutter_test.dart';
import 'package:recharge237_serveur/service/ussd/ussd_screens.dart';

/// Écrans réels relevés le 28/10/2026 sur MTN Cameroun (*126*7*<numéro>#).
/// Ils servent de référence : si le serveur ne reconnaît plus ces textes, la
/// liste Boost reste bloquée à la première page et la fenêtre USSD ne se
/// ferme jamais.
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
  group('findMorePageKey', () {
    test('« 00. Next » de MTN est reconnu', () {
      expect(findMorePageKey(_page1), '00');
    });

    test('autres écritures de pagination', () {
      expect(findMorePageKey('1) Offre\n00) Suite'), '00');
      expect(findMorePageKey('0. Plus'), '0');
      expect(findMorePageKey('99. More'), '99');
      expect(findMorePageKey('# Suivant'), '#');
    });

    // [PAGES 28/10/2026] MTN ne colle pas toujours le mot à la touche.
    test('mot de suite séparé du numéro', () {
      expect(findMorePageKey('00 - Voir la suite'), '00');
      expect(findMorePageKey('00: page suivante'), '00');
      expect(findMorePageKey('00 Next'), '00');
      expect(findMorePageKey('0 pour la suite'), '0');
    });

    test('une offre numérotée n\'est pas une pagination', () {
      expect(findMorePageKey('5) 2'), isNull);
      expect(findMorePageKey('1) Depot de 100F; C=50F'), isNull);
      expect(findMorePageKey(''), isNull);
    });
  });

  group('offerLines', () {
    test('garde les offres de la page 1 et écarte « 00. Next »', () {
      final List<String> lines = offerLines(<String>[_page1]);
      expect(lines, hasLength(5));
      expect(lines.first, '1) Depot de 100F; C=50F');
      expect(lines.last, '5) 2');
      expect(lines.any((String l) => l.contains('Next')), isFalse);
    });

    test('menu paginé : les offres des deux pages sont conservées', () {
      final List<String> lines = offerLines(<String>[_page1, _page2]);
      expect(lines, hasLength(7));
      expect(lines.where((String l) => l.startsWith('7)')), hasLength(1));
      // L'ordre du menu est respecté.
      expect(lines.first.startsWith('1)'), isTrue);
      expect(lines.last.startsWith('7)'), isTrue);
    });

    test('écran répété : aucune offre en double', () {
      final List<String> lines = offerLines(<String>[_page1, _page1]);
      expect(lines, hasLength(5));
    });

    test('un écran sans offre ne fabrique rien', () {
      expect(offerLines(<String>['Session expirée']), isEmpty);
      expect(offerLines(const <String>[]), isEmpty);
    });
  });

  group('menuLineFor', () {
    test('sait si l\'offre demandée est bien sur CET écran', () {
      expect(menuLineFor(_page1, '3'), isNotNull);
      // L'offre 6 n'existe que page 2 : il faut d'abord paginer.
      expect(menuLineFor(_page1, '6'), isNull);
      expect(menuLineFor(_page2, '6'), isNotNull);
    });
  });

  // ── Offre coupée entre deux pages ────────────────────────────────────────
  // Relevé réel du 28/10/2026 sur MTN Boost (677156949) : MTN a coupé le
  // nombre « 250U » en deux entre le bas de la page 1 et le haut de la page 2.
  group('offre coupée entre deux écrans', () {
    const String page1Reelle = '''
Offres MTN Boost pour 237677156949:
1) Depot de 100F; C=50F
2) 1200U=6700U+13170U+732MB/7D: C=60F
3) 500U=1GB/30D: C=25F
4) 1000U=2.1GB/30D: C=50F
5) 2
00. Next
''';
    const String page2Reelle = '''
50U=900U+75MB+2500U/3D: C=13F
6) 500U=5237U + 237MB+6200U/3D: C=25F
7) 250U=500MB+100 SMS/3D: C=13F
8) 1000U de credit + bonus de 2000U d appels MTN valide jusqu a minuit : C=0F
''';

    test('les huit offres sont retrouvées, la cinquième recollée', () {
      final List<UssdOffer> offres =
          offerRecords(<String>[page1Reelle, page2Reelle]);
      expect(offres, hasLength(8));
      final UssdOffer cinq = offres.firstWhere((UssdOffer o) => o.index == '5');
      // « 5) 2 » + « 50U=… » = la vraie offre 250U=900U+75MB+2500U/3D.
      expect(cinq.label, startsWith('250U=900U'));
      // [PRIX 30/10/2026] 250 (le dépôt « 250U »), PAS 13 qui est la
      // commission « C=13F » : c'est le bug financier corrigé ici.
      expect(cinq.price, 250);
      expect(cinq.displayTitle, '900U + 75 Mo + 2500U / 3 jours');
      // La ligne de continuation ne crée pas d'offre fantôme sans numéro.
      expect(offres.where((UssdOffer o) => o.index.isEmpty), isEmpty);
    });

    test('aucune offre ne garde le code technique « C= »', () {
      final List<UssdOffer> offres =
          offerRecords(<String>[page1Reelle, page2Reelle]);
      for (final UssdOffer o in offres) {
        expect(o.displayTitle.toUpperCase(), isNot(contains('C=')),
            reason: 'offre ${o.index} : ${o.displayTitle}');
      }
    });

    test('le libellé brut de MTN reste intact pour l\'activation', () {
      final List<UssdOffer> offres =
          offerRecords(<String>[page1Reelle, page2Reelle]);
      // C'est ce texte que `findOptionForLabel` compare à l'écran réel.
      expect(offres.firstWhere((UssdOffer o) => o.index == '3').label,
          '500U=1GB/30D: C=25F');
    });
  });

  // ── Libellés destinés au client ───────────────────────────────────────────
  group('offerDisplayTitle', () {
    test('retire les codes techniques et rend les unités lisibles', () {
      const Map<String, String> cas = <String, String>{
        '500U=1GB/30D: C=25F': '1 Go / 30 jours',
        '1000U=2.1GB/30D: C=50F': '2,1 Go / 30 jours',
        '250U=500MB+100 SMS/3D: C=13F': '500 Mo + 100 SMS / 3 jours',
        '1200U=6700U+13170U+732MB/7D: C=60F':
            '6700U + 13170U + 732 Mo / 7 jours',
        '500U=5237U + 237MB+6200U/3D: C=25F':
            '5237U + 237 Mo + 6200U / 3 jours',
        '1000U=1GB/1D: C=25F': '1 Go / 1 jour',
      };
      cas.forEach((String brut, String attendu) {
        expect(offerDisplayTitle(brut), attendu, reason: brut);
      });
    });

    test('offre sans débit « U= » : le contenu est conservé', () {
      expect(offerDisplayTitle('Depot de 100F; C=50F'), 'Dépôt de 100 F');
      expect(
        offerDisplayTitle(
            '1000U de credit + bonus de 2000U d appels MTN valide jusqu a minuit : C=0F'),
        "1000U de crédit + bonus de 2000U d'appels MTN valable jusqu'à minuit",
      );
    });

    test('un libellé déjà propre n\'est pas abîmé', () {
      expect(offerDisplayTitle('1 Go / 30 jours'), '1 Go / 30 jours');
      expect(offerDisplayTitle('Appels illimités'), 'Appels illimités');
    });
  });

  // ── Prix client vs commission (30/10/2026) ───────────────────────────────
  // Le prix facturé au client ne doit JAMAIS être la commission « C=… ».
  group('parseOfferPrice', () {
    test('la commission « C= » n\'est jamais le prix', () {
      // Relevés réels MTN Boost : le montant payé est celui de gauche.
      const Map<String, int> cas = <String, int>{
        'Depot de 100F; C=50F': 100,
        '500U=1GB/30D: C=25F': 500,
        '250U=500MB+100 SMS/3D: C=13F': 250,
        '1000U=2.1GB/30D: C=50F': 1000,
        '1200U=6700U+13170U+732MB/7D: C=60F': 1200,
        '500U=5237U + 237MB+6200U/3D: C=25F': 500,
        '1000U de credit + bonus de 2000U d appels MTN valide jusqu a minuit : C=0F':
            1000,
      };
      cas.forEach((String texte, int attendu) {
        expect(parseOfferPrice(texte), attendu, reason: texte);
      });
    });

    test('prix écrit en francs, commission séparée ou non', () {
      expect(parseOfferPrice('Pack 200 Mo à 200F'), 200);
      expect(parseOfferPrice('1 000 FCFA'), 1000);
      // Formes de commission rencontrées ou plausibles.
      expect(parseOfferPrice('Depot de 300F ; com=70F'), 300);
      expect(parseOfferPrice('Depot de 300F C:70F'), 300);
      expect(parseOfferPrice('Depot de 300F cout=70F'), 300);
    });

    test('commission seule : prix illisible, donc aucun prix', () {
      // Mieux vaut refuser l'activation que facturer 25 F une offre à 500 F.
      expect(parseOfferPrice('C=25F'), isNull);
      expect(parseOfferPrice('Offre réservée aux revendeurs'), isNull);
      expect(parseOfferPrice(''), isNull);
    });

    test('un écran Boost complet donne tous les bons prix', () {
      const String page1 = '''
Offres MTN Boost pour 237677156949:
1) Depot de 100F; C=50F
2) 1200U=6700U+13170U+732MB/7D: C=60F
3) 500U=1GB/30D: C=25F
4) 1000U=2.1GB/30D: C=50F
5) 2
00. Next
''';
      const String page2 = '''
50U=900U+75MB+2500U/3D: C=13F
6) 500U=5237U + 237MB+6200U/3D: C=25F
7) 250U=500MB+100 SMS/3D: C=13F
8) 1000U de credit + bonus de 2000U d appels MTN valide jusqu a minuit : C=0F
''';
      final List<UssdOffer> offres =
          offerRecords(<String>[page1, page2]);
      expect(
        offres.map((UssdOffer o) => o.price).toList(),
        <int>[100, 1200, 500, 1000, 250, 500, 250, 1000],
      );
    });
  });

  // [PIN 31/10/2026] Écran réel MTN relevé dans le journal d'une activation
  // Boost échouée (commande wZwsOyYDa3Jx17QF7fcK) : il contient « confirmer »
  // ET réclame le PIN. La règle de confirmation répondait « 1 », MTN refusait
  // le code et AUCUNE activation Boost ne pouvait aboutir.
  group('isPlainConfirmScreen', () {
    const String ecranPin = '''
Entrez votre code PIN pour confirmer la vente de 500U=1GB/30D + 500 SMS: C=25F a 237674583531. Cout: 500.0 FCFA, Commission: 25 FCFA''',
        pinExplicite = 'Entrez votre code PIN a 5 chiffres',
        confirmation = '1. Confirmer\n2. Annuler',
        confirmationSimple = 'Voulez-vous confirmer cette operation ?';

    test('le PIN a la priorité sur « confirmer »', () {
      expect(isPlainConfirmScreen(ecranPin), isFalse);
      expect(isPlainConfirmScreen(pinExplicite), isFalse);
      expect(isPlainConfirmScreen('Code secret : '), isFalse);
      expect(isPlainConfirmScreen('Saisissez votre mot de passe'), isFalse);
    });

    test('une vraie confirmation reste une confirmation', () {
      expect(isPlainConfirmScreen(confirmation), isTrue);
      expect(isPlainConfirmScreen(confirmationSimple), isTrue);
    });

    test('un écran neutre ne déclenche aucune réponse', () {
      expect(isPlainConfirmScreen('Votre solde est de 500 FCFA'), isFalse);
    });
  });
}
