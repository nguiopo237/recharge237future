import 'package:flutter_test/flutter_test.dart';
import 'package:recharge237_serveur/service/server/order_filters.dart';
import 'package:recharge237_serveur/service/server/sim_probe.dart';
import 'package:recharge237_serveur/service/ussd/orange_ussd_manager.dart';
import 'package:recharge237_serveur/service/ussd/session_config.dart';

/// [DETECTION 28/10/2026] Le téléphone déclare son matériel ; l'admin ne pose
/// que les PIN. Ces tests figent les deux règles qui en découlent :
///  - l'opérateur est reconnu depuis le nom de la SIM (Camtel s'appelle aussi
///    « Blue » ou « Bell »), avec le MCC/MNC en secours ;
///  - les emplacements viennent de la détection, et un opérateur n'est actif
///    que si son PIN est enregistré.
void main() {
  group('SimProbe.operatorOf', () {
    test('reconnaît les noms commerciaux des trois opérateurs', () {
      expect(SimProbe.operatorOf(carrier: 'MTN'), 'mtn');
      expect(SimProbe.operatorOf(carrier: 'Orange'), 'orange');
      expect(SimProbe.operatorOf(carrier: 'CAMTEL'), 'camtel');
    });

    // [ITINERANCE 28/10/2026] « Bell » n'est pas une marque camerounaise :
    // c'est le réseau visité. Une carte MTN Cameroun en itinérance au Canada
    // s'annonçait « Bell » et était classée CAMTEL — le téléphone acceptait
    // alors des commandes CAMTEL qu'il ne pouvait pas livrer (constaté en
    // production). « Bell » seul n'est donc plus reconnu ; c'est le code
    // réseau de la carte qui tranche (62403 = CAMTEL).
    test('Camtel vendu sous la marque Blue', () {
      expect(SimProbe.operatorOf(carrier: 'Blue'), 'camtel');
      expect(SimProbe.operatorOf(carrier: 'CAMTEL MOBILE'), 'camtel');
    });

    test('réseau visité « Bell » : jamais CAMTEL par erreur', () {
      expect(SimProbe.operatorOf(carrier: 'Bell', mccMnc: '62401'), 'mtn');
      expect(SimProbe.operatorOf(carrier: 'Bell', mccMnc: '62403'), 'camtel');
      expect(SimProbe.operatorOf(carrier: 'Bell', mccMnc: '302610'), 'other');
    });

    test('le MCC/MNC sert de secours quand le nom est inexploitable', () {
      expect(SimProbe.operatorOf(carrier: '', mccMnc: '62401'), 'mtn');
      expect(SimProbe.operatorOf(carrier: 'SIM', mccMnc: '62402'), 'orange');
      expect(SimProbe.operatorOf(carrier: '', mccMnc: '62403'), 'camtel');
      expect(SimProbe.operatorOf(carrier: '', mccMnc: '62404'), 'other');
    });

    test('le nom de la SIM est prioritaire sur un MNC trompeur', () {
      expect(SimProbe.operatorOf(carrier: 'MTN', mccMnc: '62403'), 'mtn');
    });
  });

  group('Routage admin (handles)', () {
    test('liste vide = tout ce que le matériel permet', () {
      expect(handlesOperation(const [], 'camtel_pre'), isTrue);
      expect(handlesOperation(const [], 'mtn_airtime'), isTrue);
    });

    test('"all" équivaut à tout traiter', () {
      expect(handlesOperation(const ['all'], 'mtn_forfait'), isTrue);
    });

    test('un type listé est traité, les autres non', () {
      const h = ['mtn_airtime', 'mtn_forfait'];
      expect(handlesOperation(h, 'mtn_airtime'), isTrue);
      expect(handlesOperation(h, 'mtn_forfait'), isTrue);
      expect(handlesOperation(h, 'camtel_pre'), isFalse);
      expect(handlesOperation(h, 'camtel_post'), isFalse);
    });

    test('un téléphone CAMTEL ne prend pas l\'activation MTN', () {
      const h = ['camtel_pre', 'camtel_post'];
      expect(handlesOperation(h, 'camtel_post'), isTrue);
      expect(handlesOperation(h, 'mtn_forfait'), isFalse);
    });

    test('les types connus sont stables, Orange reserve', () {
      expect(kOperationTypes, [
        'camtel_pre',
        'camtel_post',
        'mtn_airtime',
        'mtn_forfait',
        'orange_airtime',
        'orange_forfait',
      ]);
    });

    test('orange_airtime est routable et désormais livrable', () {
      expect(
          handlesOperation(const ['orange_airtime'], 'orange_airtime'), isTrue);
      // [ORANGE 31/10/2026] Le manager Orange compose réellement son code
      // (Good Deal ou transfert + code secret).
      expect(OrangeUssdManager.deliveryImplemented, isTrue);
    });
  });

  group('SessionConfig.fromDocument', () {
    /// Téléphone décrit dans la conversation : MTN en slot 0, CAMTEL en slot 1.
    Map<String, dynamic> doc({
      bool mtnPin = false,
      bool camtelPins = false,
      Map<String, dynamic>? forced,
    }) =>
        {
          'model': '24115RA8EG',
          'sims': [
            {
              'slot': 0,
              'operator': 'mtn',
              'carrier': 'MTN',
              'number': '677000000'
            },
            {
              'slot': 1,
              'operator': 'camtel',
              'carrier': 'CAMTEL',
              'number': ''
            },
          ],
          if (mtnPin) 'simMTN': {'pin': '1234'},
          if (camtelPins) 'simCamtelPre': {'pin': '5678'},
          if (forced != null) ...forced,
        };

    test('les emplacements viennent de la détection, pas du script', () {
      final c = SessionConfig.fromDocument(doc());
      expect(c.mtn.slot, 0);
      expect(c.camtelPre.slot, 1);
      expect(c.camtelPost.slot, 1);
    });

    test('sans PIN, aucun opérateur n\'est actif', () {
      final c = SessionConfig.fromDocument(doc());
      expect(c.mtnConfigured, isFalse);
      expect(c.camtelPre.isConfigured, isFalse);
    });

    test('PIN MTN seul + SIM MTN détectée = MTN actif', () {
      final c = SessionConfig.fromDocument(doc(mtnPin: true));
      expect(c.mtnConfigured, isTrue);
      expect(c.mtn.pin, '1234');
    });

    test('un PIN MTN sans SIM MTN n\'active rien', () {
      final c = SessionConfig.fromDocument({
        'sims': [
          {'slot': 0, 'operator': 'camtel', 'carrier': 'CAMTEL'},
        ],
        'simMTN': {'pin': '1234'},
      });
      expect(c.mtnConfigured, isFalse);
    });

    test('un emplacement forcé par l\'admin est prioritaire', () {
      final c = SessionConfig.fromDocument(doc(
        mtnPin: true,
        forced: {
          'simMTN': {'slot': 1, 'pin': '1234'},
        },
      ));
      expect(c.mtn.slot, 1);
      expect(c.mtnConfigured, isTrue);
    });

    test('téléphone MTN seul : ne prend pas les commandes CAMTEL', () {
      final c = SessionConfig.fromDocument({
        'sims': [
          {'slot': 0, 'operator': 'mtn', 'carrier': 'Bell — MTN'},
        ],
        'simMTN': {'pin': '1234'},
      });
      expect(c.mtnConfigured, isTrue);
      expect(c.camtelConfigured, isFalse);
    });

    test('une SIM CAMTEL détectée autorise les commandes CAMTEL', () {
      final c = SessionConfig.fromDocument(doc());
      expect(c.camtelConfigured, isTrue);
    });

    test('déclaration explicite de l\'admin : CAMTEL autorisé sans détection',
        () {
      final c = SessionConfig.fromDocument({
        'simCamtelPre': {'slot': 0, 'pin': '1111'},
      });
      expect(c.camtelConfigured, isTrue);
    });

    test('deux SIM CAMTEL : la plus petite est la prépayée', () {
      final c = SessionConfig.fromDocument({
        'sims': [
          {'slot': 0, 'operator': 'camtel', 'carrier': 'CAMTEL'},
          {'slot': 1, 'operator': 'camtel', 'carrier': 'Blue'},
        ],
        'simCamtelPre': {'pin': '1111'},
        'simCamtelPost': {'pin': '2222'},
      });
      expect(c.camtelPre.slot, 0);
      expect(c.camtelPost.slot, 1);
      expect(c.camtelPre.pin, '1111');
      expect(c.camtelPost.pin, '2222');
    });

    test('SIM Orange détectée : carte connue, prête pour le futur flow', () {
      final c = SessionConfig.fromDocument({
        'sims': [
          {'slot': 1, 'operator': 'orange', 'carrier': 'Orange'},
        ],
        'simOrange': {'pin': '9999'},
      });
      expect(c.orangeConfigured, isTrue);
      expect(c.orange.slot, 1);
      expect(c.orange.pin, '9999');
    });

    test('déclaration Orange explicite sans détection', () {
      final c = SessionConfig.fromDocument({
        'simOrange': {'slot': 0, 'pin': '9999'},
      });
      expect(c.orangeConfigured, isTrue);
    });

    test('téléphone MTN seul : Orange non configuré', () {
      final c = SessionConfig.fromDocument({
        'sims': [
          {'slot': 0, 'operator': 'mtn', 'carrier': 'MTN'},
        ],
        'simMTN': {'pin': '1234'},
      });
      expect(c.orangeConfigured, isFalse);
    });

    test('numéros Orange reconnus, les autres refusés', () {
      expect(isOrangeNumber('069123456'), isTrue);
      expect(isOrangeNumber('+237 655 12 34 56'), isTrue);
      expect(isOrangeNumber('657123456'), isTrue);
      expect(isOrangeNumber('677123456'), isFalse);
      expect(isOrangeNumber('622387010'), isFalse);
    });

    test('document vide : valeurs par défaut, rien d\'actif', () {
      final c = SessionConfig.fromDocument(const {});
      expect(c.mtn.slot, 0);
      expect(c.camtelPre.slot, 0);
      expect(c.mtnConfigured, isFalse);
      expect(c.camtelConfigured, isFalse);
    });
  });
}
