import 'package:flutter_test/flutter_test.dart';
import 'package:recharge237_serveur/service/server/remote_command_handler.dart';
import 'package:recharge237_serveur/service/server/slot_config.dart';
import 'package:recharge237_serveur/service/ussd/session_config.dart';

/// [EMPLACEMENTS 28/10/2026] L'admin doit pouvoir dire, pour chaque téléphone,
/// quelle carte se trouve dans quel emplacement — et le serveur doit obéir
/// sans rien déduire, y compris quand on permute les puces.
void main() {
  group('normalizeSlotCode', () {
    test('écritures libres reconnues', () {
      expect(normalizeSlotCode('MTN'), 'mtn');
      expect(normalizeSlotCode('mtn_callbox'), 'mtn');
      expect(normalizeSlotCode('MTN Good Deal'), 'mtn');
      expect(normalizeSlotCode('Orange'), 'orange');
      expect(normalizeSlotCode('CAMTEL'), 'camtel_pre');
      expect(normalizeSlotCode('camtel_post'), 'camtel_post');
      expect(normalizeSlotCode('Postpayée'), 'camtel_post');
      expect(normalizeSlotCode('Blue'), 'camtel_pre');
      expect(normalizeSlotCode('Prépayée'), 'camtel_pre');
    });

    test('valeur vide ou inconnue : emplacement libre', () {
      expect(normalizeSlotCode(''), kSlotFree);
      expect(normalizeSlotCode(null), kSlotFree);
      expect(normalizeSlotCode('???'), kSlotFree);
      expect(normalizeSlotCode('libre'), kSlotFree);
    });
  });

  group('handlesOfCode', () {
    test('chaque carte annonce exactement ce qu\'elle peut livrer', () {
      expect(handlesOfCode(kSlotMtn),
          containsAll(<String>['mtn_airtime', 'mtn_forfait']));
      expect(handlesOfCode(kSlotOrange), <String>['orange_airtime']);
      expect(handlesOfCode(kSlotCamtelPre), <String>['camtel_pre']);
      expect(handlesOfCode(kSlotCamtelPost), <String>['camtel_post']);
      expect(handlesOfCode(kSlotFree), isEmpty);
    });
  });

  group('slotSpecsFromDocument', () {
    test('sans `slots`, rien n\'est déclaré (ancien format préservé)', () {
      final List<SlotSpec> s = slotSpecsFromDocument(<String, dynamic>{
        'simMTN': <String, dynamic>{'pin': '1234'},
      });
      expect(s, isEmpty);
      expect(hasDynamicSlots(<String, dynamic>{'simMTN': <String, dynamic>{}}),
          isFalse);
    });

    test('emplacements lus, triés et dédoublonnés', () {
      final List<SlotSpec> s = slotSpecsFromDocument(<String, dynamic>{
        'slots': <dynamic>[
          <String, dynamic>{'slot': 1, 'code': 'camtel_post', 'pin': '9999'},
          <String, dynamic>{'slot': 0, 'code': 'mtn', 'pin': '1234'},
          <String, dynamic>{'slot': 1, 'code': 'orange', 'pin': '5555'},
        ],
      });
      expect(s.length, 2);
      expect(s.first.slot, 0);
      expect(s.first.code, 'mtn');
      // La dernière écriture sur le même emplacement gagne.
      expect(s.last.code, 'orange');
    });

    test('`operator` accepté à la place de `code`, avec actif/inactif', () {
      final List<SlotSpec> s = slotSpecsFromDocument(<String, dynamic>{
        'slots': <dynamic>[
          <String, dynamic>{'slot': 0, 'operator': 'MTN_CALLBOX', 'pin': '1'},
          <String, dynamic>{
            'slot': 1,
            'operator': 'ORANGE',
            'pin': '2',
            'active': false,
            'minBalance': 15000,
          },
        ],
      });
      expect(s.first.code, 'mtn');
      expect(s.last.active, isFalse);
      expect(s.last.minBalance, 15000);
      expect(s.last.handles, isEmpty, reason: 'carte désactivée : rien à servir');
    });
  });

  group('SessionConfig avec emplacements déclarés', () {
    test('le slot de l\'admin est respecté, dans les deux sens', () {
      // Téléphone A : MTN sur SIM 1.
      final SessionConfig a = SessionConfig.fromDocument(<String, dynamic>{
        'slots': <dynamic>[
          <String, dynamic>{'slot': 0, 'code': 'mtn', 'pin': '1234'},
        ],
      });
      expect(a.mtn.slot, 0);
      expect(a.mtnConfigured, isTrue);
      expect(a.slotsDeclared, isTrue);

      // Téléphone B : la même carte passe en SIM 2 après permutation.
      final SessionConfig b = SessionConfig.fromDocument(<String, dynamic>{
        'slots': <dynamic>[
          <String, dynamic>{'slot': 1, 'code': 'mtn', 'pin': '1234'},
        ],
      });
      expect(b.mtn.slot, 1);
      expect(b.mtnConfigured, isTrue);
    });

    test('une carte MTN en SIM 2 ne prend pas les commandes CAMTEL', () {
      final SessionConfig c = SessionConfig.fromDocument(<String, dynamic>{
        'slots': <dynamic>[
          <String, dynamic>{'slot': 1, 'code': 'mtn', 'pin': '1234'},
          <String, dynamic>{'slot': 0, 'code': '', 'pin': ''},
        ],
      });
      expect(c.mtnConfigured, isTrue);
      expect(c.camtelConfigured, isFalse);
      expect(c.orangeConfigured, isFalse);
    });

    test('la détection ne réactive pas une carte que l\'admin a retirée', () {
      // Le matériel voit une SIM MTN, mais l'admin a laissé l'emplacement
      // libre (ou désactivé) : le serveur doit s'abstenir, pas deviner.
      final SessionConfig c = SessionConfig.fromDocument(<String, dynamic>{
        'sims': <dynamic>[
          <String, dynamic>{'slot': 0, 'operator': 'mtn'},
        ],
        'slots': <dynamic>[
          <String, dynamic>{'slot': 0, 'code': 'mtn', 'pin': '1234', 'active': false},
        ],
      });
      expect(c.mtnConfigured, isFalse);
      expect(c.mtnSimPresent, isFalse);
    });

    test('requête Boost gratuite : carte sans PIN acceptée', () {
      final SessionConfig c = SessionConfig.fromDocument(<String, dynamic>{
        'slots': <dynamic>[
          <String, dynamic>{'slot': 0, 'code': 'mtn', 'pin': ''},
        ],
      });
      expect(c.mtnSimPresent, isTrue, reason: 'liste gratuite, aucun PIN requis');
      expect(c.mtnConfigured, isFalse, reason: 'vente de crédit encore bloquée');
    });

    test('CAMTEL prépayé et postpayé sur deux emplacements distincts', () {
      final SessionConfig c = SessionConfig.fromDocument(<String, dynamic>{
        'slots': <dynamic>[
          <String, dynamic>{'slot': 0, 'code': 'camtel_pre', 'pin': '1111'},
          <String, dynamic>{'slot': 1, 'code': 'camtel_post', 'pin': '2222'},
        ],
      });
      expect(c.camtelConfigured, isTrue);
      expect(c.camtelPre.slot, 0);
      expect(c.camtelPost.slot, 1);
    });

    test('postpayé seul : le prépayé retombe sur la même carte', () {
      final SessionConfig c = SessionConfig.fromDocument(<String, dynamic>{
        'slots': <dynamic>[
          <String, dynamic>{'slot': 1, 'code': 'camtel_post', 'pin': '2222'},
        ],
      });
      expect(c.camtelConfigured, isTrue);
      expect(c.camtelPost.slot, 1);
      expect(c.camtelPre.slot, 1);
    });
  });

  group('ancien format toujours fonctionnel', () {
    test('simMTN / simCamtelPre : même comportement qu\'avant', () {
      final SessionConfig c = SessionConfig.fromDocument(<String, dynamic>{
        'sims': <dynamic>[
          <String, dynamic>{'slot': 1, 'operator': 'mtn'},
          <String, dynamic>{'slot': 0, 'operator': 'camtel'},
        ],
        'simMTN': <String, dynamic>{'pin': '1234'},
        'simCamtelPre': <String, dynamic>{'pin': '5678'},
      });
      expect(c.slotsDeclared, isFalse);
      expect(c.mtn.slot, 1);
      expect(c.mtnConfigured, isTrue);
      expect(c.camtelConfigured, isTrue);
      expect(c.camtelPre.slot, 0);
    });

    test('aucune configuration : rien n\'est servi', () {
      final SessionConfig c = SessionConfig.fromDocument(const <String, dynamic>{});
      expect(c.mtnConfigured, isFalse);
      expect(c.camtelConfigured, isFalse);
      expect(c.orangeConfigured, isFalse);
    });
  });

  group('résumé lisible', () {
    test('dit quel emplacement sert quelle carte', () {
      final SessionConfig c = SessionConfig.fromDocument(<String, dynamic>{
        'slots': <dynamic>[
          <String, dynamic>{'slot': 0, 'code': 'mtn', 'pin': '1234'},
          <String, dynamic>{'slot': 1, 'code': 'orange', 'pin': ''},
        ],
      });
      final String t = c.toString();
      expect(t, contains('emplacements admin'));
      expect(t, contains('MTN SIM 1 + PIN'));
      expect(t, contains('Orange SIM 2 sans PIN'));
    });
  });

  group('seuils de solde par emplacement', () {
    test('seuil le plus élevé retenu quand deux cartes du même opérateur', () {
      final List<SlotSpec> s = slotSpecsFromDocument(<String, dynamic>{
        'slots': <dynamic>[
          <String, dynamic>{'slot': 0, 'code': 'camtel_pre', 'minBalance': 5000},
          <String, dynamic>{'slot': 1, 'code': 'camtel_post', 'minBalance': 30000},
        ],
      });
      expect(minBalanceByOperator(s), <String, int>{'camtel': 30000});
    });

    test('seuil à 0 ou carte désactivée : rien d\'imposé', () {
      final List<SlotSpec> s = slotSpecsFromDocument(<String, dynamic>{
        'slots': <dynamic>[
          <String, dynamic>{'slot': 0, 'code': 'mtn', 'minBalance': 0},
          <String, dynamic>{
            'slot': 1,
            'code': 'orange',
            'minBalance': 9000,
            'active': false,
          },
        ],
      });
      expect(minBalanceByOperator(s), isEmpty);
    });
  });

  group('handlesForSlots', () {
    test('seules les cartes actives comptent, sans doublon', () {
      final List<SlotSpec> s = slotSpecsFromDocument(<String, dynamic>{
        'slots': <dynamic>[
          <String, dynamic>{'slot': 0, 'code': 'mtn'},
          <String, dynamic>{'slot': 1, 'code': 'orange', 'active': false},
        ],
      });
      expect(handlesForSlots(s),
          <String>['mtn_airtime', 'mtn_forfait', 'mtn_forfait_activate']);
    });
  });

  group('signature de configuration', () {
    test('insensible à l\'ordre des clés', () {
      final String a = RemoteCommandHandler.configSignature(<String, dynamic>{
        'slots': <dynamic>[
          <String, dynamic>{'slot': 0, 'code': 'mtn', 'pin': '1'},
        ],
      });
      final String b = RemoteCommandHandler.configSignature(<String, dynamic>{
        'slots': <dynamic>[
          <String, dynamic>{'pin': '1', 'code': 'mtn', 'slot': 0},
        ],
      });
      expect(a, b);
    });

    test('les champs de vie courante ne déclenchent rien', () {
      final Map<String, dynamic> base = <String, dynamic>{
        'slots': <dynamic>[
          <String, dynamic>{'slot': 0, 'code': 'mtn', 'pin': '1'},
        ],
      };
      final String s1 = RemoteCommandHandler.configSignature(base);
      final String s2 = RemoteCommandHandler.configSignature(<String, dynamic>{
        ...base,
        'status': 'online',
        'lastSeen': 12345,
        'network': <dynamic>[
          <String, dynamic>{'slot': 0, 'ok': true},
        ],
        'command': 'ping',
      });
      expect(s1, s2);
    });

    test('un changement de PIN ou d\'emplacement est détecté', () {
      final String s1 = RemoteCommandHandler.configSignature(<String, dynamic>{
        'slots': <dynamic>[
          <String, dynamic>{'slot': 0, 'code': 'mtn', 'pin': '1'},
        ],
      });
      final String s2 = RemoteCommandHandler.configSignature(<String, dynamic>{
        'slots': <dynamic>[
          <String, dynamic>{'slot': 1, 'code': 'mtn', 'pin': '1'},
        ],
      });
      final String s3 = RemoteCommandHandler.configSignature(<String, dynamic>{
        'slots': <dynamic>[
          <String, dynamic>{'slot': 0, 'code': 'mtn', 'pin': '2'},
        ],
      });
      expect(s1, isNot(s2));
      expect(s1, isNot(s3));
    });
  });
}
