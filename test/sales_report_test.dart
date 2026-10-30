import 'package:flutter_test/flutter_test.dart';
import 'package:recharge237_serveur/service/report/sales_report.dart';

/// [COMPTA 28/10/2026] Bilan comptable : ce qui compte comme vente livrée,
/// ce qui compte comme échec, ce qui est exclu (requête Boost gratuite), et
/// ce que l'admin lit dans le message Telegram.
void main() {
  final DateTime from = DateTime(2026, 10, 28, 0, 0);
  final DateTime to = DateTime(2026, 10, 29, 0, 0);

  Map<String, dynamic> tx({
    required String op,
    required String status,
    required Object amount,
  }) =>
      <String, dynamic>{
        'operateur_cible': op,
        'status': status,
        'amount': amount,
      };

  test('agrège livrées, échecs et en attente par application', () {
    final SalesReport r = buildSalesReport(
      transactions: <Map<String, dynamic>>[
        tx(op: 'mtn_airtime', status: '21', amount: 500),
        tx(op: 'mtn_airtime', status: '21', amount: '1000'),
        tx(op: 'mtn_airtime', status: '22', amount: 200),
        tx(op: 'mtn_airtime', status: '2', amount: 300),
        tx(op: 'camtel_pre', status: '3', amount: 1500),
        // Requête Boost GRATUITE : aucune vente, doit être ignorée.
        tx(op: 'mtn_forfait', status: '31', amount: 0),
      ],
      from: from,
      to: to,
    );

    expect(r.appsActives.length, 2);
    final AppSales mtn =
        r.appsActives.firstWhere((AppSales a) => a.key == 'mtn_airtime');
    expect(mtn.delivered, 2);
    expect(mtn.failed, 1);
    expect(mtn.pending, 1);
    expect(mtn.volume, 1500);

    final AppSales camtel =
        r.appsActives.firstWhere((AppSales a) => a.key == 'camtel_pre');
    expect(camtel.delivered, 1);
    expect(camtel.volume, 1500);

    expect(r.totalVolume, 3000);
    expect(r.totalDelivered, 3);
    expect(r.totalFailed, 1);
    expect(r.failureRate, 25);
  });

  test('commissions calculées seulement si un taux est configuré', () {
    final SalesReport avec = buildSalesReport(
      transactions: <Map<String, dynamic>>[
        tx(op: 'mtn_airtime', status: '21', amount: 2000),
      ],
      from: from,
      to: to,
      commissions: <String, double>{'mtn_airtime': 5},
    );
    expect(avec.appsActives.single.commission, 100);

    final SalesReport sans = buildSalesReport(
      transactions: <Map<String, dynamic>>[
        tx(op: 'mtn_airtime', status: '21', amount: 2000),
      ],
      from: from,
      to: to,
    );
    expect(sans.appsActives.single.commission, 0);
    expect(sans.compose(sans).contains('non configurée'), isTrue);
  });

  test('message Telegram : totaux, soldes et alerte de solde bas', () {
    final SalesReport r = buildSalesReport(
      transactions: <Map<String, dynamic>>[
        tx(op: 'mtn_airtime', status: '21', amount: 12500),
        tx(op: 'camtel_pre', status: '3', amount: 500),
        tx(op: 'mtn_airtime', status: '22', amount: 100),
      ],
      from: from,
      to: DateTime(2026, 10, 28, 23, 59),
      commissions: <String, double>{'mtn_airtime': 4},
    );

    final String msg = composeAccountingMessage(
      report: r,
      balances: <BalanceLine>[
        BalanceLine(
          operator: 'mtn',
          balance: 3200,
          at: DateTime(2026, 10, 28, 18, 5),
        ),
      ],
      alerts: <String>['Écart de solde MTN : attendu 15 000, relevé 14 700'],
      deviceId: 'f5bf1e4422033950',
      seuilSolde: 5000,
    );

    expect(msg, contains('BILAN DES VENTES'));
    expect(msg, contains('28/10/2026'));
    expect(msg, contains('MTN crédit'));
    expect(msg, contains('TOTAL : 13 000 FCFA'));
    expect(msg, contains('Commission estimée : 500 FCFA'));
    expect(msg, contains('SOLDES OPÉRATEURS'));
    expect(msg, contains('MTN : 3 200 FCFA'));
    expect(msg, contains('SOLDE BAS'));
    expect(msg, contains('Écart de solde MTN'));
    expect(msg, contains('f5bf1e4422033950'));
  });

  test('journée sans vente : message explicite, pas vide', () {
    final SalesReport r = buildSalesReport(
        transactions: const <Map<String, dynamic>>[], from: from, to: to);
    final String msg =
        composeAccountingMessage(report: r, balances: const <BalanceLine>[]);
    expect(msg, contains('Aucune vente sur la période'));
    expect(msg, contains('Aucun solde reçu par SMS'));
  });

  test('montants lisibles avec séparateurs de milliers', () {
    expect(formatFcfa(12345), '12 345 FCFA');
    expect(formatFcfa(0), '0 FCFA');
    expect(formatNombre(1500), '1 500');
  });
}

extension on SalesReport {
  String compose(SalesReport r) =>
      composeAccountingMessage(report: r, balances: const <BalanceLine>[]);
}
