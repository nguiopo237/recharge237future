import 'package:flutter_test/flutter_test.dart';
import 'package:recharge237_serveur/service/ussd/ussd_screens.dart';

/// [CATALOGUE 29/10/2026] Reconnaissance d'un forfait du catalogue sur un
/// écran du menu MTN (prix, puis volume et durée).
void main() {
  const String ecranUnites = '''
Choisissez une offre
1) 100U=100MB/1D: C=5F
2) 500U=600MB/1D: C=25F
3) 1000U=2GB/1D: C=50F
4) 1000U=750MB/7D: C=50F
00) Suivant''';

  const String ecranFrancs = '''
1. Surf 1 jour 100 MB 100F
2. Surf 1 jour 2 GB 1000F
3. Surf 30 jours 9 GB 8000F''';

  test('prix en unités, deux offres au même prix : départagées par le volume',
      () {
    expect(
        findBundleOption(ecranUnites,
            price: 1000, volume: '2 Go', validite: '1 jour'),
        '3');
    expect(
        findBundleOption(ecranUnites,
            price: 1000, volume: '750 Mo', validite: '7 jours'),
        '4');
  });

  test('prix unique sur l\'écran', () {
    expect(
        findBundleOption(ecranUnites,
            price: 500, volume: '600 Mo', validite: '1 jour'),
        '2');
  });

  test('prix en francs', () {
    expect(
        findBundleOption(ecranFrancs,
            price: 8000, volume: '9 Go', validite: '30 jours'),
        '3');
  });

  test('absent de cet écran : null (page suivante)', () {
    expect(
        findBundleOption(ecranUnites,
            price: 2700, volume: '1 Go / jour', validite: '7 jours'),
        isNull);
  });

  test('prix trouvé mais volume contradictoire : on ne choisit pas', () {
    expect(
        findBundleOption(ecranUnites,
            price: 500, volume: '5 Go', validite: '1 jour'),
        isNull);
  });

  test('ne confond pas 1000 et 11000', () {
    const String e = '1) 11000U=10GB/30D: C=500F';
    expect(
        findBundleOption(e, price: 1000, volume: '10 Go', validite: '30 jours'),
        isNull);
  });

  test('volumes et durées', () {
    expect(volumesMo('1,5 Go'), <double>[1536]);
    expect(volumesMo('600MB'), <double>[600]);
    expect(dureeJours('/30D'), 30);
    expect(dureeJours('7 jours'), 7);
    expect(dureeJours('24h'), 1);
  });
}
