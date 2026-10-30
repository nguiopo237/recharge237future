import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../sendmail/send_mail.dart';
import '../server/firestore_backoff.dart';
import '../sms/sms_receiver.dart';
import '../server/slot_config.dart';
import 'sales_report.dart';
import 'sms_balance_parser.dart';

/// Réglages du module comptable, lus dans `app_config/report`.
///
/// ```json
/// {
///   "actif": true,
///   "heure_envoi": 0,
///   "minute_envoi": 5,
///   "seuil_solde": 5000,
///   "seuil_ecart": 0,
///   "commissions": { "mtn_airtime": 4.5, "camtel_pre": 3 }
/// }
/// ```
///
/// Absent = valeurs par défaut ci-dessous. Les commissions ne sont jamais
/// inventées : sans taux configuré, le rapport l'écrit et n'affiche pas de
/// marge.
class ReportConfig {
  final bool actif;
  final int heureEnvoi;
  final int minuteEnvoi;

  /// En dessous de ce solde, alerte « solde bas » (0 = pas d'alerte).
  final int seuilSolde;

  /// Écart toléré entre solde annoncé par SMS et solde attendu.
  final int seuilEcart;

  /// Taux de commission en pourcentage, par `operateur_cible`.
  final Map<String, double> commissions;

  const ReportConfig({
    this.actif = true,
    this.heureEnvoi = 0,
    this.minuteEnvoi = 5,
    this.seuilSolde = 5000,
    this.seuilEcart = 0,
    this.commissions = const <String, double>{},
  });

  factory ReportConfig.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const ReportConfig();
    final Map<String, double> com = <String, double>{};
    final Object? raw = m['commissions'];
    if (raw is Map) {
      raw.forEach((Object? k, Object? v) {
        final double? taux = v is num ? v.toDouble() : double.tryParse('$v');
        if (taux != null) com['$k'] = taux;
      });
    }
    return ReportConfig(
      actif: m['actif'] != false,
      heureEnvoi: (m['heure_envoi'] as num?)?.toInt() ?? 0,
      minuteEnvoi: (m['minute_envoi'] as num?)?.toInt() ?? 5,
      seuilSolde: (m['seuil_solde'] as num?)?.toInt() ?? 5000,
      seuilEcart: (m['seuil_ecart'] as num?)?.toInt() ?? 0,
      commissions: com,
    );
  }
}

/// [COMPTA 28/10/2026] Bilan comptable quotidien, soldes opérateurs lus dans
/// les SMS, rapprochement et diffusion Telegram.
///
/// Le serveur tourne jour et nuit sur le téléphone : c'est donc lui qui tient
/// l'horloge (pas de cron système). Le rapport porte sur la journée TERMINÉE
/// (00:05 par défaut, réglable), et le document `reports/{aaaa-mm-jj}` évite
/// tout double envoi, même après un redémarrage.
class ReportService {
  ReportService._();
  static final ReportService instance = ReportService._();

  String _deviceId = '';
  ReportConfig _config = const ReportConfig();
  Timer? _timer;
  bool _smsActif = false;

  /// Dernier jour de rapport envoyé par cette session.
  DateTime? _dernierEnvoi;

  /// Anti-spam des SMS illisibles : une alerte par heure maximum.
  DateTime? _derniereAlerteSms;

  /// [EMPLACEMENTS 28/10/2026] Seuil de solde propre à chaque opérateur,
  /// lu dans `servers/{deviceId}.slots[i].minBalance`. Il remplace le seuil
  /// global : une grosse SIM revendeur et une petite SIM de secours n'ont
  /// évidemment pas le même point d'alerte.
  Map<String, int> _seuilsParOperateur = const <String, int>{};

  ReportConfig get config => _config;

  Future<void> start(String deviceId) async {
    if (_timer != null && _deviceId == deviceId) return;
    _deviceId = deviceId;
    await rechargerConfig();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _tick());
    _demarrerSms();
    await _rattraper();
    if (_config.actif) {
      debugPrint('[Report] actif — envoi quotidien à '
          '${_deuxChiffres(_config.heureEnvoi)}:${_deuxChiffres(_config.minuteEnvoi)}');
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _smsSub?.cancel();
    _smsSub = null;
    _smsActif = false;
  }

  Future<void> rechargerConfig() async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> doc = await FirebaseFirestore
          .instance
          .collection('app_config')
          .doc('report')
          .get()
          .timeout(const Duration(seconds: 10));
      _config = ReportConfig.fromMap(doc.data());
    } catch (e) {
      debugPrint('[Report] config illisible, valeurs par défaut : $e');
    }
    await _rechargerSeuilsEmplacements();
  }

  /// Seuils de solde déclarés par l'admin sur les emplacements de CE téléphone.
  Future<void> _rechargerSeuilsEmplacements() async {
    if (_deviceId.isEmpty) return;
    try {
      final DocumentSnapshot<Map<String, dynamic>> doc = await FirebaseFirestore
          .instance
          .collection('servers')
          .doc(_deviceId)
          .get()
          .timeout(const Duration(seconds: 10));
      _seuilsParOperateur =
          minBalanceByOperator(slotSpecsFromDocument(doc.data() ?? const {}));
    } catch (e) {
      debugPrint('[Report] seuils d\'emplacement illisibles : $e');
    }
  }

  /// Seuil applicable à un opérateur : celui de son emplacement s'il est
  /// déclaré, sinon le seuil global `app_config/report.seuil_solde`.
  int seuilPour(String operator) {
    final int? propre = _seuilsParOperateur[operator.trim().toLowerCase()];
    return (propre != null && propre > 0) ? propre : _config.seuilSolde;
  }

  // ── Planification ────────────────────────────────────────────────────────

  Future<void> _tick() async {
    if (!_config.actif || _deviceId.isEmpty) return;
    // [QUOTA 29/10/2026] Base saturée : on attend la fin de la pause.
    if (FirestoreBackoff.instance.enPause) return;
    final DateTime now = DateTime.now();
    final bool passe = now.hour > _config.heureEnvoi ||
        (now.hour == _config.heureEnvoi && now.minute >= _config.minuteEnvoi);
    if (!passe) return;
    final DateTime hier = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 1));
    if (_dernierEnvoi != null && !_dernierEnvoi!.isBefore(hier)) return;
    if (await _dejaEnvoye(hier)) {
      _dernierEnvoi = hier;
      return;
    }
    await sendReport(day: hier, motif: 'bilan quotidien');
  }

  /// Au démarrage : si le rapport d'hier n'est pas parti (téléphone éteint à
  /// l'heure prévue), on l'envoie tout de suite, une seule fois.
  Future<void> _rattraper() async {
    if (!_config.actif || _deviceId.isEmpty) return;
    final DateTime now = DateTime.now();
    final bool passe = now.hour > _config.heureEnvoi ||
        (now.hour == _config.heureEnvoi && now.minute >= _config.minuteEnvoi);
    if (!passe) return;
    final DateTime hier = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 1));
    if (await _dejaEnvoye(hier)) {
      _dernierEnvoi = hier;
      return;
    }
    await sendReport(day: hier, motif: 'rattrapage');
  }

  Future<bool> _dejaEnvoye(DateTime jour) async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> doc = await FirebaseFirestore
          .instance
          .collection('reports')
          .doc(_cle(jour))
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 10));
      return doc.exists;
    } catch (e) {
      // [QUOTA 29/10/2026] Avant : une erreur répondait « pas encore
      // envoyé », et le bilan (qui relit toutes les transactions de la
      // veille) était relancé CHAQUE MINUTE tant que la base refusait. On
      // répond maintenant « ne rien faire » et on ralentit.
      if (FirestoreBackoff.estTransitoire(e)) {
        FirestoreBackoff.instance.echec(e);
      }
      return true;
    }
  }

  // ── Rapport ──────────────────────────────────────────────────────────────

  /// Construit et envoie le bilan d'une journée.
  ///
  /// [motif] précise l'origine (« bilan quotidien », « demande admin »).
  /// Rend le message envoyé (utile pour la réponse de commande à distance).
  Future<String> sendReport({required DateTime day, String motif = ''}) async {
    final DateTime debut = DateTime(day.year, day.month, day.day);
    final DateTime fin = debut.add(const Duration(days: 1));

    final List<Map<String, dynamic>> transactions =
        await _transactions(debut, fin);
    final SalesReport rapport = buildSalesReport(
      transactions: transactions,
      from: debut,
      to: fin,
      commissions: _config.commissions,
    );
    final List<BalanceLine> soldes = await _soldes();
    final List<String> alertes = _alertesDepuis(soldes, debut);

    final String message = composeAccountingMessage(
      report: rapport,
      balances: soldes,
      alerts: alertes,
      deviceId: _deviceId,
      title: motif.isEmpty ? 'BILAN DES VENTES' : 'BILAN DES VENTES — $motif',
      seuilSolde: _config.seuilSolde,
    );

    await SendEmail.sendMessagewithtelegram(message: message);
    await _ecrireRapport(debut, rapport, message);
    _dernierEnvoi = debut;
    debugPrint('[Report] bilan ${formatDate(debut)} envoyé — '
        '${formatFcfa(rapport.totalVolume)}');
    return message;
  }

  /// Commandes de la période.
  ///
  /// Une seule plage sur `heure` (pas d'index composite nécessaire), puis
  /// filtrage précis côté client : les apps écrivent des dates ISO, parfois
  /// avec « T », parfois avec un espace — la comparaison de chaînes reste
  /// fiable sur la partie date.
  Future<List<Map<String, dynamic>>> _transactions(
      DateTime debut, DateTime fin) async {
    try {
      final QuerySnapshot<Map<String, dynamic>> snap = await FirebaseFirestore
          .instance
          .collection('Transact')
          .where('heure', isGreaterThanOrEqualTo: _iso(debut.toUtc()))
          // [QUOTA 29/10/2026] Borne haute : sans elle, la requête relisait
          // aussi toutes les transactions du jour en cours. Borne au JOUR
          // suivant (« 2026-10-30 ») : quel que soit le format écrit
          // (« T » ou espace), rien de la période n'est oublié ; le tri
          // exact reste fait ci-dessous.
          .where('heure',
              isLessThan: _jourSeul(fin.toUtc().add(const Duration(days: 1))))
          .get()
          .timeout(const Duration(seconds: 25));
      final DateTime d = debut.toUtc();
      final DateTime f = fin.toUtc();
      final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in snap.docs) {
        final Map<String, dynamic> m = doc.data();
        final DateTime? t = DateTime.tryParse((m['heure'] ?? '').toString());
        if (t == null) continue;
        final DateTime u = t.toUtc();
        if (u.isBefore(d) || !u.isBefore(f)) continue;
        out.add(m);
      }
      return out;
    } catch (e) {
      debugPrint('[Report] lecture des commandes impossible : $e');
      return const <Map<String, dynamic>>[];
    }
  }

  Future<List<BalanceLine>> _soldes() async {
    try {
      final QuerySnapshot<Map<String, dynamic>> snap =
          await FirebaseFirestore.instance.collection('soldes').get();
      final List<BalanceLine> out = <BalanceLine>[];
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in snap.docs) {
        final Map<String, dynamic> m = doc.data();
        final int? b = (m['balance'] as num?)?.toInt();
        final DateTime? at = (m['at'] as Timestamp?)?.toDate();
        if (b == null || at == null) continue;
        out.add(BalanceLine(
          operator: (m['operator'] ?? doc.id).toString(),
          balance: b,
          at: at,
          source: m['source']?.toString() ?? 'SMS',
        ));
      }
      out.sort(
          (BalanceLine a, BalanceLine b) => a.operator.compareTo(b.operator));
      return out;
    } catch (e) {
      debugPrint('[Report] soldes illisibles : $e');
      return const <BalanceLine>[];
    }
  }

  /// Anomalies à joindre au bilan : écarts relevés et soldes bas.
  List<String> _alertesDepuis(List<BalanceLine> soldes, DateTime debut) {
    final List<String> out = <String>[];
    for (final BalanceLine s in soldes) {
      if (s.at.isBefore(debut)) continue;
      final int seuil = seuilPour(s.operator);
      if (seuil > 0 && s.balance < seuil) {
        out.add('Solde ${s.label} bas : ${formatFcfa(s.balance)} '
            '(seuil ${formatFcfa(seuil)})');
      }
    }
    return out;
  }

  Future<void> _ecrireRapport(
      DateTime debut, SalesReport rapport, String message) async {
    try {
      await FirebaseFirestore.instance
          .collection('reports')
          .doc(_cle(debut))
          .set(
        <String, dynamic>{
          'jour': _cle(debut),
          'deviceId': _deviceId,
          'volume': rapport.totalVolume,
          'livrees': rapport.totalDelivered,
          'echecs': rapport.totalFailed,
          'en_cours': rapport.totalPending,
          'commission': rapport.totalCommission,
          'details': rapport.apps
              .map((AppSales a) => <String, dynamic>{
                    'operation': a.key,
                    'label': a.label,
                    'livrees': a.delivered,
                    'echecs': a.failed,
                    'volume': a.volume,
                    'commission': a.commission,
                  })
              .toList(),
          'message': message,
          'envoye_le': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      ).timeout(const Duration(seconds: 12));
    } catch (e) {
      debugPrint('[Report] écriture du rapport impossible : $e');
    }
  }

  // ── SMS opérateurs ───────────────────────────────────────────────────────

  StreamSubscription<SmsRecu>? _smsSub;

  /// [SMS 29/10/2026] Écoute des SMS opérateurs via le récepteur natif
  /// (SmsReceiver, canal `r237/sms`), qui remplace le paquet `telephony`.
  void _demarrerSms() {
    if (_smsActif) return;
    try {
      _smsSub = SmsReceiver.flux.listen(
        (SmsRecu m) => _onSms(m.body, m.address),
        onError: (Object e) => debugPrint('[Report] SMS illisible : $e'),
      );
      _smsActif = true;
      debugPrint('[Report] écoute des SMS opérateurs démarrée');
    } catch (e) {
      debugPrint('[Report] écoute SMS impossible : $e');
    }
  }

  Future<void> _onSms(String body, String sender) async {
    if (body.trim().isEmpty) return;
    final SmsParse parse = parseSmsBody(body, sender: sender);
    debugPrint('[SMS] $sender → '
        '${parse.recognised ? 'solde=${parse.balance} montant=${parse.amount} ${parse.directionLabel}' : 'non reconnu (${parse.reason})'}');
    // [QUOTA 29/10/2026] Chaque recharge déclenche un SMS de l'opérateur :
    // l'archiver coûtait 1 écriture par commande, et enregistrer le solde
    // 1 lecture + 1 écriture de plus. Sur le plan gratuit (20 000
    // écritures/jour), c'était ~30 % du budget à 10 000 commandes.
    //  - seuls les SMS NON reconnus sont archivés (ils servent à ajouter
    //    des règles au lecteur de SMS) ;
    //  - le solde est écrit au plus une fois toutes les 30 min par
    //    opérateur, sauf passage sous le seuil d'alerte (immédiat).
    if (!parse.recognised) await _archiverSms(sender, body, parse);
    if (parse.balance != null) {
      if (_soldeAEcrire(parse)) await _enregistrerSolde(parse);
    } else if (!parse.recognised) {
      await _signalerSms(sender, body, parse.reason);
    }
  }

  static const Duration _intervalleSolde = Duration(minutes: 30);
  final Map<String, DateTime> _soldeEcritA = <String, DateTime>{};
  final Map<String, int> _soldeEcrit = <String, int>{};

  /// Vrai si ce relevé de solde doit partir dans la base maintenant.
  bool _soldeAEcrire(SmsParse parse) {
    final String op = parse.operator.isEmpty ? 'inconnu' : parse.operator;
    final int balance = parse.balance!;
    final DateTime? dernier = _soldeEcritA[op];
    final int seuil = seuilPour(op);
    final int? precedent = _soldeEcrit[op];
    final bool passeSousSeuil = seuil > 0 &&
        balance < seuil &&
        (precedent == null || precedent >= seuil);
    final bool du = dernier == null ||
        DateTime.now().difference(dernier) >= _intervalleSolde;
    if (!du && !passeSousSeuil) {
      debugPrint('[Report] solde $op ${formatFcfa(balance)} gardé en mémoire '
          '(prochaine écriture dans '
          '${_intervalleSolde.inMinutes - DateTime.now().difference(dernier).inMinutes} min)');
      return false;
    }
    _soldeEcritA[op] = DateTime.now();
    _soldeEcrit[op] = balance;
    return true;
  }

  Future<void> _archiverSms(String sender, String body, SmsParse parse) async {
    try {
      await FirebaseFirestore.instance.collection('sms_operateur').add(
        <String, dynamic>{
          'from': sender,
          'body': body.length > 500 ? body.substring(0, 500) : body,
          'at': FieldValue.serverTimestamp(),
          'deviceId': _deviceId,
          'operator': parse.operator,
          'reconnu': parse.recognised,
          'balance': parse.balance,
          'amount': parse.amount,
          'sens': parse.direction.name,
          'reference': parse.reference,
          'raison': parse.reason,
        },
      );
    } catch (e) {
      debugPrint('[Report] archivage SMS impossible : $e');
    }
  }

  /// Enregistre un solde et rapproche avec les ventes livrées depuis le relevé
  /// précédent. L'écart est calculé, jamais masqué.
  Future<void> _enregistrerSolde(SmsParse parse) async {
    final String op = parse.operator.isEmpty ? 'inconnu' : parse.operator;
    final int balance = parse.balance!;
    final DocumentReference<Map<String, dynamic>> ref =
        FirebaseFirestore.instance.collection('soldes').doc(op);
    int? ancien;
    DateTime? ancienAt;
    try {
      final DocumentSnapshot<Map<String, dynamic>> snap = await ref.get();
      final Map<String, dynamic>? m = snap.data();
      ancien = (m?['balance'] as num?)?.toInt();
      ancienAt = (m?['at'] as Timestamp?)?.toDate();
    } catch (e) {
      debugPrint('[Report] solde précédent illisible : $e');
    }

    int vendu = 0;
    if (ancienAt != null) {
      vendu = await _ventesLivrees(op, ancienAt, DateTime.now());
    }
    final int? attendu = ancien == null ? null : ancien - vendu;
    final int? ecart = attendu == null ? null : balance - attendu;

    try {
      await ref.set(<String, dynamic>{
        'operator': op,
        'balance': balance,
        'at': FieldValue.serverTimestamp(),
        'source': 'SMS',
        'deviceId': _deviceId,
        'reference': parse.reference,
        'solde_precedent': ancien,
        'vendu_depuis': vendu,
        'solde_attendu': attendu,
        'ecart': ecart,
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 12));
    } catch (e) {
      debugPrint('[Report] écriture du solde impossible : $e');
    }

    if (ecart != null && ecart.abs() > _config.seuilEcart) {
      await SendEmail.sendMessagewithtelegram(
        message: 'Recharge237 — ÉCART DE SOLDE\n'
            'Téléphone : $_deviceId\n'
            'Opérateur : ${op.toUpperCase()}\n'
            'Solde SMS : ${formatFcfa(balance)}\n'
            'Attendu   : ${formatFcfa(attendu)} '
            '(ancien ${formatFcfa(ancien)} − ${formatFcfa(vendu)} livrés)\n'
            'Écart     : ${formatFcfa(ecart)}\n'
            'À vérifier : une commande livrée sans passer par la base, ou un '
            'relevé manquant.',
      );
    }

    final int seuilSolde = seuilPour(op);
    if (seuilSolde > 0 &&
        balance < seuilSolde &&
        (ancien == null || ancien >= seuilSolde)) {
      await SendEmail.sendMessagewithtelegram(
        message: 'Recharge237 — SOLDE BAS\n'
            'Téléphone : $_deviceId\n'
            'Opérateur : ${op.toUpperCase()}\n'
            'Solde     : ${formatFcfa(balance)}\n'
            'Seuil     : ${formatFcfa(seuilSolde)}'
            '${_seuilsParOperateur.containsKey(op) ? ' (emplacement)' : ''}\n'
            'Les ventes de crédit vont échouer : réapprovisionne la SIM.',
      );
    }
  }

  /// Somme des ventes LIVRÉES d'un opérateur depuis [depuis].
  Future<int> _ventesLivrees(
      String operator, DateTime depuis, DateTime jusqu) async {
    final Set<String> cles = <String>{};
    if (operator == 'mtn') {
      cles.addAll(
          <String>['mtn_airtime', 'mtn_forfait_activate', 'mtn_bundle']);
    } else if (operator == 'camtel') {
      cles.addAll(<String>['camtel_pre', 'camtel_post']);
    } else if (operator == 'orange') {
      cles.add('orange_airtime');
    } else {
      return 0;
    }
    final List<Map<String, dynamic>> t = await _transactions(depuis, jusqu);
    int total = 0;
    for (final Map<String, dynamic> m in t) {
      final String op = (m['operateur_cible'] ?? '').toString();
      if (!cles.contains(op)) continue;
      final Set<String> livre = kDeliveredStatuses[op] ?? const <String>{};
      if (!livre.contains((m['status'] ?? '').toString())) continue;
      final Object? a = m['amount'];
      final int? v = a is num
          ? a.round()
          : int.tryParse(a?.toString().replaceAll(RegExp(r'[^0-9]'), '') ?? '');
      total += v ?? 0;
    }
    return total;
  }

  /// SMS financier incompris : signalé, avec le texte exact, pour qu'on ajoute
  /// la règle — jamais interprété de travers.
  Future<void> _signalerSms(String sender, String body, String raison) async {
    final String norm = smsNormalise(body);
    final bool financier = norm.contains('fcfa') ||
        norm.contains('solde') ||
        norm.contains('balance') ||
        norm.contains('xaf');
    if (!financier) return;
    final DateTime now = DateTime.now();
    if (_derniereAlerteSms != null &&
        now.difference(_derniereAlerteSms!) < const Duration(hours: 1)) {
      return;
    }
    _derniereAlerteSms = now;
    await SendEmail.sendMessagewithtelegram(
      message: 'Recharge237 — SMS OPÉRATEUR NON RECONNU\n'
          'Téléphone : $_deviceId\n'
          'Expéditeur : $sender\n'
          'Raison    : $raison\n'
          '─────────────────────\n'
          '${body.length > 400 ? '${body.substring(0, 400)}…' : body}',
    );
  }

  // ── Utilitaires ──────────────────────────────────────────────────────────

  static String _deuxChiffres(int v) => v.toString().padLeft(2, '0');

  static String _cle(DateTime d) =>
      '${d.year}-${_deuxChiffres(d.month)}-${_deuxChiffres(d.day)}';

  /// « 2026-10-30 » : borne de jour, inférieure à toute heure de ce jour.
  static String _jourSeul(DateTime utc) =>
      '${utc.year}-${_deuxChiffres(utc.month)}-${_deuxChiffres(utc.day)}';

  /// Date ISO au format écrit par les apps (« 2026-10-28 23:05:12.345Z »).
  static String _iso(DateTime utc) =>
      '${utc.year}-${_deuxChiffres(utc.month)}-${_deuxChiffres(utc.day)} '
      '${_deuxChiffres(utc.hour)}:${_deuxChiffres(utc.minute)}:'
      '${_deuxChiffres(utc.second)}.${utc.millisecond.toString().padLeft(3, '0')}Z';
}
