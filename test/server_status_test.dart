import 'package:flutter_test/flutter_test.dart';
import 'package:recharge237_serveur/service/server/status_labels.dart';

void main() {
  group('serverStatusInfo', () {
    test('les statuts MTN ne tombent plus dans le libellé générique', () {
      expect(serverStatusInfo('20').isPending, isTrue);
      expect(serverStatusInfo('21').isSuccess, isTrue);
      expect(serverStatusInfo('21').label, contains('livré'));
      expect(serverStatusInfo('22').isFailure, isTrue);
      expect(serverStatusInfo('31').isSuccess, isTrue);
      expect(serverStatusInfo('32').isFailure, isTrue);
      expect(serverStatusInfo('34').isSuccess, isTrue);
      expect(serverStatusInfo('35').isFailure, isTrue);
    });

    test('cycle client classique', () {
      expect(serverStatusInfo('0').isPending, isTrue);
      expect(serverStatusInfo('1').isPending, isTrue);
      expect(serverStatusInfo('3').isSuccess, isTrue);
      expect(serverStatusInfo('4').isFailure, isTrue);
      expect(serverStatusInfo('10').isSuccess, isTrue);
    });

    test('chaque statut connu a un libellé explicite', () {
      for (final String s in ['5', '6', '8', '9', '11', '12', '30', '33']) {
        expect(serverStatusInfo(s).label, isNot(contains('Statut inconnu')),
            reason: 'statut $s');
      }
    });

    test('statut inconnu ou vide reste lisible', () {
      expect(serverStatusInfo(null).label, 'Statut inconnu');
      expect(serverStatusInfo('').label, 'Statut inconnu');
      expect(serverStatusInfo('999').label, contains('999'));
      expect(serverStatusInfo('999').kind, StatusKind.neutral);
    });
  });

  group('operatorLabel', () {
    test('operateur_cible fait foi', () {
      expect(operatorLabel({'operateur_cible': 'mtn_airtime'}), 'MTN');
      expect(operatorLabel({'operateur_cible': 'mtn_forfait'}), 'MTN');
      expect(operatorLabel({'operateur_cible': 'camtel_pre'}), 'CAMTEL');
      expect(operatorLabel({'operateur_cible': 'orange'}), 'Orange');
    });

    test('sinon on déduit du préfixe du numéro cible', () {
      expect(operatorLabel({'numerocamtel': '674583531'}), 'MTN');
      expect(operatorLabel({'numerocamtel': '620123456'}), 'CAMTEL');
      expect(operatorLabel({'numerocamtel': '242123456'}), 'CAMTEL');
      expect(operatorLabel({'numerocamtel': '699123456'}), 'Orange');
      expect(operatorLabel({'numerocamtel': '000'}), '—');
    });
  });
}
