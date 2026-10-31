import 'package:flutter_test/flutter_test.dart';
import 'package:recharge237_serveur/service/loyalty/identity_rules.dart';

/// [IDENTITÉ 31/10/2026] Barrière d'identité : aucun point, aucun bonus de
/// parrainage pour un profil anonyme ou incomplet. Ces tests fixent ce qui
/// compte comme « identifié » — et surtout ce qui NE compte pas, parce que
/// c'est là que se jouent les abus (pseudo d'une lettre, numéro bidon, email
/// sans domaine).
void main() {
  group('IdentiteClient.nomValide', () {
    test('prénom + nom suffisent', () {
      expect(
        const IdentiteClient(nom: 'Jean Dupont').nomValide,
        isTrue,
      );
      expect(
        const IdentiteClient(nom: '  MARIE-CLAIRE   Ngono  ').nomValide,
        isTrue,
      );
      // Accents et apostrophes réels.
      expect(const IdentiteClient(nom: "Aïcha O'Neil").nomValide, isTrue);
    });

    test('un pseudo ou un mot seul ne vaut pas un nom complet', () {
      expect(const IdentiteClient(nom: 'J').nomValide, isFalse);
      expect(const IdentiteClient(nom: 'test').nomValide, isFalse);
      expect(const IdentiteClient(nom: 'a b').nomValide, isFalse);
      expect(const IdentiteClient(nom: '123 456').nomValide, isFalse);
      expect(const IdentiteClient(nom: '  ').nomValide, isFalse);
    });
  });

  group('IdentiteClient.telephoneValide', () {
    test('numéros camerounais réels, quel que soit le format', () {
      expect(const IdentiteClient().telephoneValide, isFalse);
      for (final String n in <String>[
        '674583531',
        '+237 674 58 35 31',
        '237674583531',
        '00237674583531',
        '6 74 58 35 31',
      ]) {
        expect(IdentiteClient(telephone: n).telephoneValide, isTrue,
            reason: n);
        expect(IdentiteClient(telephone: n).telephoneNormalise, '674583531');
      }
    });

    test('numéros invalides refusés', () {
      expect(const IdentiteClient(telephone: '12345').telephoneValide, isFalse);
      expect(
          const IdentiteClient(telephone: '574583531').telephoneValide, isFalse);
      expect(const IdentiteClient(telephone: '00000').telephoneValide, isFalse);
      expect(const IdentiteClient(telephone: '').telephoneValide, isFalse);
    });
  });

  group('IdentiteClient.emailValide', () {
    test('adresses plates valides', () {
      for (final String e in <String>[
        'client@recharge237.com',
        'jean.dupont+recharge@gmail.com',
        'a_b-c@mail.co.uk',
      ]) {
        expect(IdentiteClient(email: e).emailValide, isTrue, reason: e);
      }
    });

    test('adresses bidons refusées', () {
      for (final String e in <String>[
        'client',
        'client@',
        '@recharge237.com',
        'client@localhost',
        'client @mail.com',
        'client@@mail.com',
        'client@mail..com',
      ]) {
        expect(IdentiteClient(email: e).emailValide, isFalse, reason: e);
      }
    });
  });

  group('complete / manquants', () {
    const IdentiteClient complet = IdentiteClient(
      nom: 'Jean Dupont',
      telephone: '674583531',
      email: 'client@recharge237.com',
    );

    test('les trois preuves rendent le profil participant', () {
      expect(complet.complete, isTrue);
      expect(complet.manquants, isEmpty);
      expect(complet.motifIncomplet, isEmpty);
    });

    test('il manque une preuve : rien n\'est versé', () {
      const IdentiteClient sansEmail =
          IdentiteClient(nom: 'Jean Dupont', telephone: '674583531');
      expect(sansEmail.complete, isFalse);
      expect(sansEmail.manquants, <String>['adresse email']);
      expect(sansEmail.motifIncomplet, contains('adresse email'));
    });

    test('profil anonyme : les trois champs sont réclamés', () {
      const IdentiteClient vide = IdentiteClient();
      expect(vide.complete, isFalse);
      expect(vide.manquants.length, 3);
      expect(vide.motifIncomplet, contains('nom complet'));
      expect(vide.motifIncomplet, contains('téléphone'));
    });
  });

  group('identiteDe : lecture des documents users', () {
    test('accepte les différents noms de champs écrits par les apps', () {
      final IdentiteClient a = identiteDe(<String, dynamic>{
        'nomComplet': 'Marie Ngono',
        'phone': '+237690000000',
        'mail': 'marie@recharge237.com',
      });
      expect(a.complete, isTrue);

      final IdentiteClient b = identiteDe(<String, dynamic>{
        'fullName': 'Paul Biya',
        'phoneNumber': '677112233',
        'email': 'paul@example.cm',
      });
      expect(b.complete, isTrue);
    });

    test('un document absent ou vide ne participe pas', () {
      expect(identiteDe(null).complete, isFalse);
      expect(identiteDe(<String, dynamic>{}).complete, isFalse);
      // Les apps écrivent souvent la chaîne "null" quand le champ est vide.
      expect(
        identiteDe(<String, dynamic>{
          'nom': 'null',
          'email': 'null',
          'phoneNumber': 'null',
        }).complete,
        isFalse,
      );
    });

    test('peutParticiper résume la règle pour le service', () {
      expect(
        peutParticiper(<String, dynamic>{
          'nom': 'Jean Dupont',
          'phoneNumber': '674583531',
          'email': 'client@recharge237.com',
        }),
        isTrue,
      );
      expect(peutParticiper(<String, dynamic>{'idphone': 'abc'}), isFalse);
    });
  });
}
