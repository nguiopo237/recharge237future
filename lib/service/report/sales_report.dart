/// [COMPTA 28/10/2026] Agrégation comptable des ventes, sans Firestore ni
/// Telegram : tout est calculé à partir d'une liste de commandes, donc
/// testable (test/sales_report_test.dart) et réutilisable par une autre app.
library;

/// Libellés des applications vendues, par `operateur_cible`.
const Map<String, String> kOperationLabels = <String, String>{
  'camtel_pre': 'CAMTEL prépayé',
  'camtel_post': 'CAMTEL postpayé',
  'mtn_airtime': 'MTN crédit',
  'mtn_forfait_activate': 'MTN Boost / Good Deal',
  'mtn_bundle': 'MTN forfait catalogue',
  'orange_airtime': 'Orange crédit',
};

/// Statuts qui comptent comme une vente RÉELLEMENT livrée.
///
/// Repris de `status_labels.dart` : 3 = livré, 11 = activé (point de vente),
/// 8 = traité par SMS, 10 = SIM rechargée, 21 = MTN crédit livré,
/// 34 = forfait activé, 5 = forfait activé par l'admin, 41 = Orange livré.
const Map<String, Set<String>> kDeliveredStatuses = <String, Set<String>>{
  'camtel_pre': <String>{'3', '11'},
  'camtel_post': <String>{'8', '10'},
  'mtn_airtime': <String>{'21'},
  'mtn_forfait_activate': <String>{'34', '5'},
  'mtn_bundle': <String>{'34'},
  'orange_airtime': <String>{'41'},
};

/// Statuts d'échec (rien n'a été livré au client).
const Map<String, Set<String>> kFailedStatuses = <String, Set<String>>{
  'camtel_pre': <String>{'4'},
  'camtel_post': <String>{'4'},
  'mtn_airtime': <String>{'22'},
  'mtn_forfait_activate': <String>{'35'},
  'mtn_bundle': <String>{'35'},
  'orange_airtime': <String>{'42'},
};

/// Types de commande volontairement EXCLUS de la comptabilité : la requête de
/// liste Boost/Good Deal est gratuite (aucun argent, aucune vente).
const Set<String> kNonBillableOperations = <String>{'mtn_forfait'};

/// Une application vendue (un type d'opération) sur la période.
class AppSales {
  final String key;
  final String label;
  int delivered = 0;
  int failed = 0;
  int pending = 0;

  /// Volume encaissé sur les ventes livrées, en FCFA.
  int volume = 0;

  /// Commission estimée, en FCFA (0 si aucun taux configuré).
  int commission = 0;

  AppSales(this.key, this.label);

  int get total => delivered + failed + pending;

  /// Taux appliqué, en pourcentage (null si non configuré).
  String get commissionLabel =>
      commission == 0 ? 'non configurée' : formatFcfa(commission);
}

/// Bilan d'une période.
class SalesReport {
  final DateTime from;
  final DateTime to;
  final List<AppSales> apps;
  final Map<String, double> commissions;

  SalesReport({
    required this.from,
    required this.to,
    required this.apps,
    this.commissions = const <String, double>{},
  });

  int get totalVolume => apps.fold(0, (int s, AppSales a) => s + a.volume);
  int get totalDelivered =>
      apps.fold(0, (int s, AppSales a) => s + a.delivered);
  int get totalFailed => apps.fold(0, (int s, AppSales a) => s + a.failed);
  int get totalPending => apps.fold(0, (int s, AppSales a) => s + a.pending);
  int get totalCommission =>
      apps.fold(0, (int s, AppSales a) => s + a.commission);

  /// Taux d'échec en pourcentage, arrondi (0 si aucune commande terminée).
  int get failureRate {
    final int terminees = totalDelivered + totalFailed;
    if (terminees == 0) return 0;
    return ((totalFailed * 100) / terminees).round();
  }

  List<AppSales> get appsActives =>
      apps.where((AppSales a) => a.total > 0).toList();
}

/// Montant lisible : « 12 500 FCFA ».
String formatFcfa(int? value) {
  if (value == null) return '—';
  final String digits = value.abs().toString();
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(' ');
    out.write(digits[i]);
  }
  return '${value < 0 ? '-' : ''}$out FCFA';
}

/// Montant sans devise : « 12 500 ».
String formatNombre(int value) {
  final String full = formatFcfa(value);
  return full.replaceAll(' FCFA', '');
}

/// Date courte « 28/10 » puis « 28/10/2026 ».
String formatJour(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
String formatDate(DateTime d) => '${formatJour(d)}/${d.year}';
String formatHeure(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

int? _montant(Object? raw) {
  if (raw is num) return raw.round();
  final String digits =
      (raw ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return null;
  return int.tryParse(digits);
}

/// Construit le bilan des commandes comprises dans [from] .. [to].
///
/// [commissions] : taux en pourcentage par `operateur_cible` (ex.
/// `{'mtn_airtime': 4.5}`). Absent = commission non calculée, et le rapport
/// l'écrit noir sur blanc au lieu d'afficher un chiffre inventé.
SalesReport buildSalesReport({
  required Iterable<Map<String, dynamic>> transactions,
  required DateTime from,
  required DateTime to,
  Map<String, double> commissions = const <String, double>{},
}) {
  final Map<String, AppSales> byKey = <String, AppSales>{};

  for (final Map<String, dynamic> t in transactions) {
    final String op =
        (t['operateur_cible'] ?? '').toString().trim().toLowerCase();
    if (kNonBillableOperations.contains(op)) continue;

    final String key = op.isEmpty ? 'camtel_pre' : op;
    final String label = kOperationLabels[key] ?? 'Autre ($key)';
    final AppSales app = byKey.putIfAbsent(key, () => AppSales(key, label));

    final String status = (t['status'] ?? '').toString().trim();
    final int amount = _montant(t['amount']) ?? 0;
    final Set<String> delivered = kDeliveredStatuses[key] ??
        const <String>{'3', '8', '10', '21', '34', '41', '11', '5'};
    final Set<String> failed =
        kFailedStatuses[key] ?? const <String>{'4', '22', '32', '35', '42'};

    if (delivered.contains(status)) {
      app.delivered++;
      app.volume += amount;
    } else if (failed.contains(status)) {
      app.failed++;
    } else {
      app.pending++;
    }

    final double? taux = commissions[key];
    if (taux != null) {
      app.commission = (app.volume * taux / 100).round();
    }
  }

  final List<AppSales> apps = byKey.values.toList()
    ..sort((AppSales a, AppSales b) => b.volume.compareTo(a.volume));

  return SalesReport(
    from: from,
    to: to,
    apps: apps,
    commissions: commissions,
  );
}

/// Une ligne de solde, telle qu'extraite d'un SMS opérateur.
class BalanceLine {
  final String operator;
  final int balance;
  final DateTime at;
  final String source;

  const BalanceLine({
    required this.operator,
    required this.balance,
    required this.at,
    this.source = 'SMS',
  });

  String get label {
    switch (operator) {
      case 'mtn':
        return 'MTN';
      case 'orange':
        return 'Orange';
      case 'camtel':
        return 'CAMTEL / Blue';
      default:
        return operator.isEmpty ? 'Opérateur inconnu' : operator;
    }
  }
}

/// Assemble le message Telegram complet : ventes, soldes, alertes.
///
/// Fonction pure : le service ne fait qu'appeler Telegram avec le résultat.
String composeAccountingMessage({
  required SalesReport report,
  required List<BalanceLine> balances,
  List<String> alerts = const <String>[],
  String deviceId = '',
  String title = 'BILAN DES VENTES',
  int? seuilSolde,
  String? loyalty,
}) {
  final StringBuffer b = StringBuffer();
  b.writeln('Recharge237 — $title');
  b.writeln('Journée : ${formatDate(report.from)}');
  b.writeln(
      'Période : ${formatJour(report.from)} ${formatHeure(report.from)} → '
      '${formatJour(report.to)} ${formatHeure(report.to)}');
  if (deviceId.isNotEmpty) b.writeln('Téléphone : $deviceId');
  b.writeln('─────────────────────');

  if (report.appsActives.isEmpty) {
    b.writeln('Aucune vente sur la période.');
  } else {
    for (final AppSales a in report.appsActives) {
      b.writeln(a.label);
      b.writeln(
          '  Ventes   : ${formatFcfa(a.volume)} (${a.delivered} livrée(s))');
      if (a.failed > 0) b.writeln('  Échecs   : ${a.failed}');
      if (a.pending > 0) b.writeln('  En cours : ${a.pending}');
      if (a.commission > 0) {
        final double? taux = report.commissions[a.key];
        b.writeln('  Comm.    : ${formatFcfa(a.commission)}'
            '${taux == null ? '' : ' (${taux.toStringAsFixed(taux == taux.roundToDouble() ? 0 : 1)} %)'}');
      }
    }
    b.writeln('─────────────────────');
    b.writeln('TOTAL : ${formatFcfa(report.totalVolume)}');
    b.writeln(
        'Livrées : ${report.totalDelivered} · Échecs : ${report.totalFailed}'
        ' · En cours : ${report.totalPending} (${report.failureRate} % d\'échec)');
    b.writeln(report.totalCommission > 0
        ? 'Commission estimée : ${formatFcfa(report.totalCommission)}'
        : 'Commission : non configurée (app_config/report.commissions)');
  }

  // [FIDÉLITÉ 31/10/2026] Ce que le programme de points a coûté sur la
  // journée. Tenu par le serveur, jamais par le client : l'admin voit chaque
  // jour la réserve consommable, au lieu de la découvrir en fin de mois.
  if (loyalty != null && loyalty.isNotEmpty) {
    b.writeln('');
    b.writeln('FIDÉLITÉ');
    b.writeln('  $loyalty');
  }

  b.writeln('');
  b.writeln('SOLDES OPÉRATEURS (SMS)');
  if (balances.isEmpty) {
    b.writeln('  Aucun solde reçu par SMS.');
  } else {
    for (final BalanceLine l in balances) {
      final bool bas = seuilSolde != null && l.balance < seuilSolde;
      b.writeln('  ${l.label} : ${formatFcfa(l.balance)}'
          '${bas ? '  ⚠️ SOLDE BAS' : ''}');
      b.writeln(
          '    relevé le ${formatDate(l.at)} à ${formatHeure(l.at)} (${l.source})');
    }
  }

  if (alerts.isNotEmpty) {
    b.writeln('');
    b.writeln('⚠️ ALERTES');
    for (final String a in alerts) {
      b.writeln('  • $a');
    }
  }
  return b.toString().trimRight();
}
