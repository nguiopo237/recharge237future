import 'package:flutter_test/flutter_test.dart';
import 'package:recharge237_serveur/service/server/internet_watch.dart';

/// [INTERNET 28/10/2026] Le téléphone ne peut pas prévenir en temps réel qu'il
/// n'a plus Internet (Telegram passe par la même connexion). Ces tests fixent
/// donc précisément QUAND il parle : jamais pour un battement manqué isolé,
/// une fois à la coupure confirmée, un rappel par demi-heure, puis le retour
/// avec sa durée.
void main() {
  final DateTime t0 = DateTime(2026, 10, 28, 12, 0);

  test('connexion normale : aucun message', () {
    final InternetWatch w = InternetWatch(maintenant: t0);
    for (int i = 0; i < 10; i++) {
      expect(
        w.beat(joignable: true, maintenant: t0.add(Duration(seconds: 30 * i))),
        InternetEvent.none,
      );
    }
    expect(w.ok, isTrue);
    expect(w.coupureDepuis, isNull);
  });

  test('un seul battement manqué : pas d\'alerte prématurée', () {
    final InternetWatch w = InternetWatch(maintenant: t0);
    // 30 s de silence : sous le seuil de 75 s.
    expect(w.beat(joignable: false, maintenant: t0.add(const Duration(seconds: 30))),
        InternetEvent.none);
    expect(w.ok, isTrue);
  });

  test('coupure confirmée : une perte, pas de répétition immédiate', () {
    final InternetWatch w = InternetWatch(maintenant: t0);
    final DateTime t1 = t0.add(const Duration(seconds: 90));
    expect(w.beat(joignable: false, maintenant: t1), InternetEvent.perte);
    expect(w.ok, isFalse);
    expect(w.coupureDepuis, t0);
    // Les battements suivants ne doivent pas spammer.
    expect(w.beat(joignable: false, maintenant: t1.add(const Duration(minutes: 5))),
        InternetEvent.none);
    expect(w.beat(joignable: false, maintenant: t1.add(const Duration(minutes: 29))),
        InternetEvent.none);
  });

  test('coupure prolongée : un rappel par demi-heure', () {
    final InternetWatch w = InternetWatch(maintenant: t0);
    final DateTime t1 = t0.add(const Duration(seconds: 90));
    expect(w.beat(joignable: false, maintenant: t1), InternetEvent.perte);
    expect(w.beat(joignable: false, maintenant: t1.add(const Duration(minutes: 30))),
        InternetEvent.rappel);
    expect(w.beat(joignable: false, maintenant: t1.add(const Duration(minutes: 45))),
        InternetEvent.none);
    expect(w.beat(joignable: false, maintenant: t1.add(const Duration(minutes: 61))),
        InternetEvent.rappel);
  });

  test('retour : signalé une fois, avec la durée de la coupure', () {
    final InternetWatch w = InternetWatch(maintenant: t0);
    w.beat(joignable: false, maintenant: t0.add(const Duration(seconds: 90)));
    final DateTime retour = t0.add(const Duration(minutes: 42));
    expect(w.beat(joignable: true, maintenant: retour), InternetEvent.retour);
    expect(w.ok, isTrue);
    expect(w.derniereCoupure, const Duration(minutes: 42));
    expect(w.coupureDepuis, isNull);
    // Un battement normal ensuite : silence.
    expect(w.beat(joignable: true, maintenant: retour.add(const Duration(seconds: 30))),
        InternetEvent.none);
  });

  test('deuxième coupure : nouvelle alerte, pas de blocage', () {
    final InternetWatch w = InternetWatch(maintenant: t0);
    w.beat(joignable: false, maintenant: t0.add(const Duration(seconds: 90)));
    final DateTime retour = t0.add(const Duration(minutes: 10));
    w.beat(joignable: true, maintenant: retour);
    expect(
      w.beat(joignable: false, maintenant: retour.add(const Duration(seconds: 90))),
      InternetEvent.perte,
    );
  });
}
