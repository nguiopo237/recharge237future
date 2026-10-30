import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../sendmail/send_mail.dart';
import '../server/firestore_backoff.dart';
import 'client_push.dart';

/// Jours de rappel, du plus lointain au jour même. L'ordre n'a pas d'importance
/// pour l'exécution, mais il sert à composer les bilans Telegram.
const List<int> joursDeRappel = <int>[3, 2, 1, 0];

/// Nombre de jours pleins entre [aujourdhui] et [expiration], ou `null` si
/// l'échéance est déjà derrière nous.
///
/// Comparaison sur des DATES (minuit), pas sur des instants : un forfait qui
/// expire aujourd'hui à 23 h 59 doit être compté « J-0 » toute la journée, et
/// non « J-1 » le matin puis « J-0 » le soir — sinon la relance du matin
/// partirait avec le mauvais texte (ou deux fois).
int? joursRestants(DateTime expiration, DateTime aujourdhui) {
  final DateTime e = DateTime(expiration.year, expiration.month, expiration.day);
  final DateTime a = DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day);
  final int jours = e.difference(a).inDays;
  return jours < 0 ? null : jours;
}

/// Vrai si le rappel du jour [jour] a déjà été envoyé pour cette échéance.
bool dejaRelance(dynamic remindedOn, int jour) {
  if (remindedOn is! List) return false;
  for (final dynamic v in remindedOn) {
    if (v is num && v.toInt() == jour) return true;
  }
  return false;
}

/// [RELANCES 31/10/2026] Relance automatique des clients avant l'expiration de
/// leur forfait : J-3, J-2, J-1 et le jour J.
///
/// Pourquoi dans l'app serveur et pas dans une Cloud Function : le projet
/// Firebase est sur le plan gratuit Spark, où les fonctions planifiées ne
/// peuvent pas être déployées (aucune fonction n'est d'ailleurs active —
/// `firebase functions:list` répond « No functions found »). Le téléphone
/// serveur, lui, tourne déjà jour et nuit, possède les droits admin et sait
/// déjà envoyer des push OneSignal (`ClientPush`). C'est donc lui qui tient
/// l'horloge, exactement comme pour le bilan comptable quotidien
/// ([ReportService]).
///
/// Les échéances sont écrites par les APPLICATIONS CLIENTES dans
/// `devices/{deviceId}.forfait` au moment où le forfait est réellement livré
/// (cf. `forfait_reminder.dart` côté client) : c'est le seul endroit où l'on
/// connaît à la fois l'appareil à prévenir (donc son abonnement push) et la
/// durée de validité de l'offre achetée.
///
/// Le job est volontairement IDEMPOTENT : chaque rappel est réservé dans
/// `forfait.remindedOn` par une transaction avant l'envoi, puis libéré si
/// l'envoi échoue. Un redémarrage du téléphone, un second téléphone serveur ou
/// un passage manuel ne peuvent donc ni doubler un rappel ni le perdre.
///
/// Un client qui recharge avant l'échéance écrase son échéance (et remet
/// `remindedOn` à zéro) : il ne reçoit plus de rappel pour l'ancien forfait.
class ForfaitReminderService {
  ForfaitReminderService._();
  static final ForfaitReminderService instance = ForfaitReminderService._();

  /// Réglages lus dans `app_config/reminders` (modifiables depuis la console
  /// Firebase, sans redéployer l'app) :
  /// ```json
  /// { "actif": true, "heure": 9, "minute": 0 }
  /// ```
  static const String _collectionConfig = 'app_config';
  static const String _docConfig = 'reminders';

  Timer? _timer;
  String _deviceId = '';
  bool _actif = true;
  int _heure = 9;
  int _minute = 0;

  /// Date du dernier passage effectué par cette session : une seule exécution
  /// par jour, même si le minuteur tourne chaque minute.
  DateTime? _dernierPassage;

  /// Anti-doublon du bilan Telegram (une ligne par jour au maximum).
  DateTime? _dernierBilan;

  bool get actif => _actif;

  /// Démarre la surveillance. Appelé par l'écran serveur, une seule fois.
  Future<void> start(String deviceId) async {
    if (_timer != null && _deviceId == deviceId) return;
    _deviceId = deviceId;
    await rechargerConfig();
    _timer?.cancel();
    // Une minute : le job est quotidien, mais un réveil un peu tardif (téléphone
    // en veille, réseau revenu à 9 h 07) doit être rattrapé dans la minute.
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _tick());
    debugPrint('[Rappels] actif — relances J-3/J-2/J-1/J-0 à '
        '${_heure.toString().padLeft(2, '0')}:${_minute.toString().padLeft(2, '0')}');
    // Rattrapage au démarrage : si l'heure est déjà passée et que le passage
    // du jour n'a pas eu lieu (téléphone éteint), on le fait tout de suite.
    await _tick();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> rechargerConfig() async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> doc = await FirebaseFirestore
          .instance
          .collection(_collectionConfig)
          .doc(_docConfig)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 10));
      final Map<String, dynamic> m = doc.data() ?? const <String, dynamic>{};
      _actif = m['actif'] != false;
      final int h = (m['heure'] as num?)?.toInt() ?? 9;
      final int min = (m['minute'] as num?)?.toInt() ?? 0;
      _heure = (h < 0 || h > 23) ? 9 : h;
      _minute = (min < 0 || min > 59) ? 0 : min;
    } catch (e) {
      debugPrint('[Rappels] config par défaut (09:00) : $e');
    }
  }

  // ── Planification ────────────────────────────────────────────────────────

  Future<void> _tick() async {
    if (!_actif || _deviceId.isEmpty) return;
    if (FirestoreBackoff.instance.enPause) return;
    final DateTime now = DateTime.now();
    final bool heurePassee = now.hour > _heure ||
        (now.hour == _heure && now.minute >= _minute);
    if (!heurePassee) return;
    final DateTime jour = DateTime(now.year, now.month, now.day);
    if (_dernierPassage != null && !_dernierPassage!.isBefore(jour)) return;
    _dernierPassage = jour; // posé avant l'appel : pas de double passage
    final int envoyes = await run();
    if (envoyes > 0 || _dernierBilan == null || _dernierBilan!.isBefore(jour)) {
      await _bilanTelegram(envoyes, jour);
      _dernierBilan = jour;
    }
  }

  // ── Le job ───────────────────────────────────────────────────────────────

  /// Envoie les rappels dus et rend le nombre de push réellement acceptés par
  /// OneSignal. Peut être appelé à la main (commande à distance de l'admin).
  Future<int> run() async {
    final DateTime today = DateTime.now();
    final DateTime debut = DateTime(today.year, today.month, today.day);
    // Fenêtre de 4 jours : J-0 à J-3. Une seule inégalité de plage sur un même
    // champ (`forfait.expiresAt`) — aucun index composite n'est nécessaire.
    final DateTime fin = debut.add(const Duration(days: 4));

    QuerySnapshot<Map<String, dynamic>> snap;
    try {
      snap = await FirebaseFirestore.instance
          .collection('devices')
          .where('forfait.expiresAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(debut))
          .where('forfait.expiresAt', isLessThan: Timestamp.fromDate(fin))
          .limit(500)
          .get()
          .timeout(const Duration(seconds: 25));
      FirestoreBackoff.instance.succes();
    } catch (e) {
      if (FirestoreBackoff.estTransitoire(e)) {
        FirestoreBackoff.instance.echec(e);
      } else {
        debugPrint('[Rappels] requête refusée : $e');
      }
      return 0;
    }

    if (snap.docs.isEmpty) {
      debugPrint('[Rappels] aucune échéance dans les 4 prochains jours');
      return 0;
    }

    int envoyes = 0;
    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in snap.docs) {
      if (FirestoreBackoff.instance.enPause) break;
      final Map<String, dynamic> d = doc.data();
      final dynamic forfait = d['forfait'];
      if (forfait is! Map) continue;

      final dynamic brut = forfait['expiresAt'];
      if (brut is! Timestamp) continue;
      final int? jours = joursRestants(brut.toDate(), today);
      if (jours == null || jours > 3) continue;
      if (dejaRelance(forfait['remindedOn'], jours)) continue;

      final String pushId = (d['pushId'] ?? '').toString().trim();
      final String uid = (d['uid'] ?? d['idphone'] ?? '').toString().trim();
      if (pushId.isEmpty && uid.isEmpty) {
        debugPrint('[Rappels] ${doc.id} sans identifiant de ciblage — ignoré');
        continue;
      }

      // Réservation atomique : deux téléphones serveurs ne peuvent pas envoyer
      // le même rappel.
      if (!await _reserver(doc.reference, jours)) continue;

      final bool ok = await ClientPush.rappelForfait(
        uid: uid,
        pushId: pushId,
        jours: jours,
        offre: (forfait['offre'] ?? '').toString(),
        numero: (forfait['numero'] ?? '').toString(),
        orderId: (forfait['orderId'] ?? '').toString(),
      );

      if (ok) {
        envoyes++;
      } else {
        // Envoi refusé : on libère la réservation pour qu'un prochain passage
        // réessaie, plutôt que de perdre définitivement le rappel.
        await _liberer(doc.reference, jours);
      }
    }

    debugPrint('[Rappels] $envoyes rappel(s) envoyé(s) sur ${snap.size} échéance(s)');
    return envoyes;
  }

  /// Coche le rappel du jour dans `forfait.remindedOn` — rend `true` si c'est
  /// bien nous qui l'avons réservé (donc si l'envoi doit avoir lieu).
  Future<bool> _reserver(DocumentReference<Map<String, dynamic>> ref, int jour) async {
    try {
      return await FirebaseFirestore.instance
          .runTransaction<bool>((Transaction tx) async {
        final DocumentSnapshot<Map<String, dynamic>> snap = await tx.get(ref);
        final dynamic forfait = snap.data()?['forfait'];
        if (forfait is! Map) return false;
        if (dejaRelance(forfait['remindedOn'], jour)) return false;
        tx.update(ref, <String, dynamic>{
          'forfait.remindedOn': FieldValue.arrayUnion(<int>[jour]),
        });
        return true;
      }).timeout(const Duration(seconds: 20));
    } catch (e) {
      if (FirestoreBackoff.estTransitoire(e)) {
        FirestoreBackoff.instance.echec(e);
      } else {
        debugPrint('[Rappels] réservation impossible (${ref.id}) : $e');
      }
      return false;
    }
  }

  Future<void> _liberer(DocumentReference<Map<String, dynamic>> ref, int jour) async {
    try {
      await ref.update(<String, dynamic>{
        'forfait.remindedOn': FieldValue.arrayRemove(<int>[jour]),
      });
    } catch (e) {
      debugPrint('[Rappels] libération impossible (${ref.id}) : $e');
    }
  }

  Future<void> _bilanTelegram(int envoyes, DateTime jour) async {
    final String texte = envoyes == 0
        ? 'RELANCE FORFAITS — ${_date(jour)}\nAucun rappel dû aujourd\'hui.'
        : 'RELANCE FORFAITS — ${_date(jour)}\n$envoyes rappel(s) push envoyé(s) '
            '(J-3/J-2/J-1/J-0).';
    try {
      await SendEmail.sendMessagewithtelegram(message: texte);
    } catch (e) {
      debugPrint('[Rappels] bilan Telegram non envoyé : $e');
    }
  }

  String _date(DateTime d) => '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';
}
