import 'package:flutter_test/flutter_test.dart';
import 'package:recharge237_serveur/service/server/sim_probe.dart';

/// [ITINERANCE 28/10/2026] Une carte MTN Cameroun en itinérance s'annonce
/// « Bell » (réseau visité). Elle était classée CAMTEL : ce téléphone croyait
/// avoir une carte CAMTEL et acceptait des commandes qu'il ne pouvait pas
/// livrer. Ces tests verrouillent la règle.
void main() {
  test('carte MTN en itinérance sur Bell : reconnue MTN', () {
    expect(SimProbe.operatorOf(carrier: 'Bell', mccMnc: '62401'), 'mtn');
  });

  test('marque lisible sur la carte : elle prime', () {
    expect(SimProbe.operatorOf(carrier: 'MTN', mccMnc: '62401'), 'mtn');
    expect(SimProbe.operatorOf(carrier: 'Orange CM', mccMnc: '62402'), 'orange');
    expect(SimProbe.operatorOf(carrier: 'Blue', mccMnc: '62403'), 'camtel');
  });

  test('carte CAMTEL annoncée par son nom : toujours CAMTEL', () {
    expect(SimProbe.operatorOf(carrier: 'CAMTEL', mccMnc: ''), 'camtel');
    expect(SimProbe.operatorOf(carrier: 'Bell', mccMnc: '62403'), 'camtel');
  });

  test('marque explicite même avec un code réseau étranger', () {
    expect(SimProbe.operatorOf(carrier: 'MTN', mccMnc: '302610'), 'mtn');
  });

  test('carte étrangère sans marque connue : jamais CAMTEL par erreur', () {
    expect(SimProbe.operatorOf(carrier: 'Bell', mccMnc: '302610'), 'other');
    expect(SimProbe.operatorOf(carrier: 'Rogers', mccMnc: ''), 'other');
    expect(SimProbe.operatorOf(carrier: '', mccMnc: ''), 'other');
  });
}
