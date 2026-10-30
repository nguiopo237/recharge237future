import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:recharge237_serveur/service/server/firestore_backoff.dart';

class _ZeroRandom implements Random {
  @override
  double nextDouble() => 0;
  @override
  bool nextBool() => false;
  @override
  int nextInt(int max) => 0;
}

void main() {
  late DateTime maintenant;
  late FirestoreBackoff b;

  setUp(() {
    maintenant = DateTime(2026, 10, 29, 3);
    b = FirestoreBackoff(horloge: () => maintenant, aleatoire: _ZeroRandom());
  });

  test('double à chaque échec et plafonne à 5 minutes', () {
    final List<int> attentes = <int>[
      for (int i = 0; i < 10; i++)
        b.echec(Exception('Quota exceeded')).inSeconds,
    ];
    expect(attentes, <int>[5, 10, 20, 40, 80, 160, 300, 300, 300, 300]);
    expect(b.saturation, isTrue);
  });

  test('pause respectée puis levée', () {
    b.echec();
    expect(b.enPause, isTrue);
    maintenant = maintenant.add(const Duration(seconds: 6));
    expect(b.enPause, isFalse);
  });

  test('un succès remet à zéro', () {
    b.echec();
    b.echec();
    b.succes();
    expect(b.enPause, isFalse);
    expect(b.echec().inSeconds, 5);
  });

  test('executer saute l appel pendant la pause', () async {
    b.echec();
    int appels = 0;
    final int? r = await b.executer(() async => ++appels);
    expect(r, isNull);
    expect(appels, 0);
  });

  test('executer compte les erreurs transitoires, relance les autres',
      () async {
    final int? r =
        await b.executer<int>(() async => throw TimeoutException('x'));
    expect(r, isNull);
    expect(b.echecsConsecutifs, 1);
    maintenant = maintenant.add(const Duration(minutes: 1));
    expect(() => b.executer<int>(() async => throw StateError('droits')),
        throwsStateError);
  });

  test('reconnaît le message de quota', () {
    expect(
        FirestoreBackoff.estSaturation(
            Exception('8 RESOURCE_EXHAUSTED: Quota exceeded.')),
        isTrue);
    expect(FirestoreBackoff.estSaturation(Exception('permission-denied')),
        isFalse);
  });
}
