import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../sendmail/send_mail.dart';
import '../ussd/session_config.dart';
import '../ussd/sim_network.dart';
import 'firestore_backoff.dart';
import 'network_recovery.dart';
import 'server_doc_cache.dart';
import 'order_filters.dart' show kActionableStatuses;

/// [RESEAU 28/10/2026] Surveillance périodique du réseau des SIM de CE
/// téléphone, pour l'admin.
///
/// La garde [SimNetworkGuard] protège chaque commande au moment de l'exécuter.
/// Elle ne dit rien tant qu'aucune commande n'arrive : l'admin peut donc
/// ignorer pendant des heures que son téléphone MTN est hors réseau, et
/// l'apprendre seulement quand un client a payé et que la livraison échoue.
///
/// Ce chien de garde comble ce trou :
///  - il lit l'état réel de chaque SIM configurée à cadence ADAPTATIVE :
///    toutes les 5 minutes s'il reste des commandes à livrer, toutes les
///    30 minutes quand rien n'attend (inutile de réveiller la radio pour
///    rien) ;
///  - il publie le résultat dans `servers/{deviceId}` (`network`, `networkOk`,
///    `networkCheckedAt`) pour l'app admin, la console et les scripts ;
///  - il envoie un message Telegram **au changement** (coupure, puis retour),
///    et un rappel toutes les heures tant que la coupure dure — jamais un
///    message par contrôle, sinon plus personne ne les lit.
///
/// La cadence se recalcule à chaque relevé : c'est la base de données qui dit
/// s'il reste du travail (`Transact` avec un statut actionnable).
class SimTarget {
  /// Emplacement (0 = SIM 1).
  final int slot;

  /// Opérateur attendu sur cet emplacement (`mtn`, `camtel`, `orange`).
  final String operator;

  const SimTarget(this.slot, this.operator);

  @override
  String toString() => 'slot ${slot + 1} ($operator)';
}

/// Emplacements à surveiller pour ce téléphone.
///
/// Seules les SIM réellement confiées à ce téléphone sont surveillées : une
/// carte absente ne doit pas produire d'alerte sur un téléphone qui ne la gère
/// pas. Un emplacement déclaré deux fois (ex. prépayée et postpayée sur la
/// même carte) n'est vérifié qu'une fois.
///
/// Fonction pure : testée dans test/network_watch_test.dart.
List<SimTarget> networkTargets(SessionConfig c) {
  final Map<int, SimTarget> bySlot = <int, SimTarget>{};
  void add(int slot, String op) =>
      bySlot.putIfAbsent(slot, () => SimTarget(slot, op));
  if (c.mtnConfigured) add(c.mtn.slot, 'mtn');
  if (c.camtelConfigured) {
    add(c.camtelPre.slot, 'camtel');
    add(c.camtelPost.slot, 'camtel');
  }
  if (c.orangeConfigured) add(c.orange.slot, 'orange');
  return bySlot.values.toList()..sort((a, b) => a.slot.compareTo(b.slot));
}

/// SIM concernée par une commande, d'après son `operateur_cible`.
///
/// `null` quand ce téléphone n'a pas la carte correspondante : dans ce cas la
/// commande ne le regarde pas et la garde réseau n'a rien à dire.
///
/// Fonction pure : testée dans test/network_watch_test.dart.
SimTarget? targetForOrder(SessionConfig c, String operateurCible) {
  final String op = operateurCible.trim().toLowerCase();
  switch (op) {
    case '':
    case 'camtel_pre':
      return c.camtelConfigured ? SimTarget(c.camtelPre.slot, 'camtel') : null;
    case 'camtel_post':
      return c.camtelConfigured ? SimTarget(c.camtelPost.slot, 'camtel') : null;
    case 'mtn_forfait':
      // Requête GRATUITE : une carte MTN suffit, le PIN n'est pas nécessaire.
      // `mtnConfigured` implique une carte connue : une config construite à la
      // main (ou un ancien document) ne renseigne pas toujours `mtnSimPresent`,
      // et refuser la liste gratuite pour cette raison serait un faux refus.
      return (c.mtnSimPresent || c.mtnConfigured)
          ? SimTarget(c.mtn.slot, 'mtn')
          : null;
    case 'mtn_airtime':
    case 'mtn_forfait_activate':
    case 'mtn_bundle':
      return c.mtnConfigured ? SimTarget(c.mtn.slot, 'mtn') : null;
    case 'orange_airtime':
    case 'orange_forfait':
    case 'orange_forfait_activate':
      return c.orangeConfigured ? SimTarget(c.orange.slot, 'orange') : null;
  }
  return null;
}

class NetworkWatch {
  NetworkWatch._();
  static final NetworkWatch instance = NetworkWatch._();

  /// Appelé après un relevé où au moins une SIM est utilisable : c'est le
  /// signal qui relance les commandes gardées pendant la coupure.
  Future<void> Function()? onNetworkHealthy;

  /// Cadence quand des commandes attendent d'être livrées : 5 minutes. Assez
  /// court pour attraper une fenêtre de réseau qui s'ouvre (les cartes en
  /// itinérance en donnent de brèves) sans saturer la radio.
  static const Duration busyInterval = Duration(minutes: 5);

  /// Cadence quand la file est vide : 30 minutes. Rien à livrer, donc on
  /// économise la batterie et les écritures.
  static const Duration idleInterval = Duration(minutes: 30);

  /// Ancien nom conservé pour les appels existants (= cadence active quand des
  /// commandes attendent).
  static const Duration interval = busyInterval;

  /// Rappel tant que la coupure dure.
  static const Duration reminder = Duration(minutes: 60);

  /// Premier contrôle, juste après le démarrage : l'admin voit l'état sans
  /// attendre 5 minutes.
  static const Duration firstCheckDelay = Duration(seconds: 20);

  Timer? _timer;
  Timer? _first;
  String _deviceId = '';

  /// Vrai quand des commandes attendent une livraison (cadence 5 min).
  bool _busy = false;

  /// [CADENCE 28/10/2026] Surcharge décidée par l'admin depuis la base
  /// (`servers/{id}.networkCheckMinutes`). Sert aux journées où le réseau
  /// n'est disponible que par brèves fenêtres : on descend à 1 minute le
  /// temps de les attraper, puis on remet 5 sans recompiler l'app.
  ///
  /// Bornes 1–60 minutes : au-delà on ignore la valeur (faute de frappe).
  int? _cadenceMinute;

  /// Cadence effective quand du travail attend.
  Duration get busyCadence => _cadenceMinute == null
      ? busyInterval
      : Duration(minutes: _cadenceMinute!);

  /// Vrai si la cadence courante est celle du travail en attente.
  bool get busy => _busy;

  /// Cadence à appliquer selon la file d'attente. Fonction pure, testée.
  static Duration cadenceFor({required bool pending}) =>
      pending ? busyInterval : idleInterval;

  /// Dernier verdict connu par emplacement (`true` = utilisable).
  final Map<int, bool> _lastOk = <int, bool>{};

  /// Début de la coupure en cours, par emplacement.
  final Map<int, DateTime> _downSince = <int, DateTime>{};

  /// Dernier message envoyé pour une coupure, par emplacement.
  final Map<int, DateTime> _lastAlert = <int, DateTime>{};

  /// Dernier état publié (pour l'affichage local).
  List<Map<String, dynamic>> lastResults = const <Map<String, dynamic>>[];

  bool get allOk =>
      lastResults.every((Map<String, dynamic> r) => r['ok'] == true);

  void start(String deviceId) {
    if (_deviceId == deviceId && _timer != null) return;
    _deviceId = deviceId;
    _timer?.cancel();
    _first?.cancel();
    // Au démarrage on ne sait pas encore s'il y a du travail : premier relevé
    // rapide, qui fixera lui-même la cadence.
    _timer = Timer.periodic(idleInterval, (_) => checkNow());
    _first = Timer(firstCheckDelay, checkNow);
    debugPrint('[NetworkWatch] surveillance démarrée pour $deviceId '
        '(premier relevé dans ${firstCheckDelay.inSeconds} s)');
  }

  /// Applique la cadence correspondant à la file d'attente.
  ///
  /// Appelée après chaque relevé, et par le traitement des commandes : dès
  /// qu'une commande arrive, le rythme passe à 5 minutes sans attendre le
  /// prochain cycle.
  void setPendingWork(bool pending) {
    if (pending == _busy && _timer != null) return;
    _busy = pending;
    final Duration d = pending ? busyCadence : idleInterval;
    _timer?.cancel();
    _first?.cancel();
    _first = null;
    _timer = Timer.periodic(d, (_) => checkNow());
    debugPrint('[NetworkWatch] cadence → ${d.inMinutes} min '
        '(${pending ? 'commandes en attente' : 'aucune attente'})');
  }

  /// Vrai s'il reste au moins une commande à traiter pour ce serveur.
  ///
  /// Lecture minuscule (`limit(1)`) : elle ne sert qu'à choisir la cadence.
  Future<bool> _hasPendingWork() async {
    if (FirestoreBackoff.instance.enPause) return true;
    try {
      final QuerySnapshot<Map<String, dynamic>> snap = await FirebaseFirestore
          .instance
          .collection('Transact')
          .where('status', whereIn: kActionableStatuses)
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 10));
      return snap.docs.isNotEmpty;
    } catch (e) {
      // En cas de doute on garde la cadence active : mieux vaut vérifier trop
      // souvent que rater une fenêtre de réseau.
      debugPrint('[NetworkWatch] file d\'attente illisible : $e');
      return true;
    }
  }

  void stop() {
    _timer?.cancel();
    _first?.cancel();
    _timer = null;
    _first = null;
  }

  /// Contrôle immédiat. Sans attente : c'est un relevé, pas une session.
  Future<void> checkNow() async {
    if (_deviceId.isEmpty) return;
    // [QUOTA 29/10/2026] Base saturée : relevé sauté, le suivant reprendra.
    if (FirestoreBackoff.instance.enPause) return;
    try {
      // [QUOTA 29/10/2026] Le document serveur est déjà écouté en temps réel
      // (RemoteCommandHandler) : on lit sa copie au lieu de relire la base.
      Map<String, dynamic>? donnees =
          ServerDocCache.fraiche(const Duration(hours: 1))
              ? ServerDocCache.donnees
              : null;
      if (donnees == null) {
        final DocumentSnapshot<Map<String, dynamic>> doc =
            await FirebaseFirestore.instance
                .collection('servers')
                .doc(_deviceId)
                .get()
                .timeout(const Duration(seconds: 10));
        donnees = doc.data() ?? <String, dynamic>{};
        ServerDocCache.mettreAJour(donnees);
      }
      // [CADENCE 28/10/2026] Réglage à chaud, lu à chaque relevé.
      final Object? brut = donnees['networkCheckMinutes'];
      final int? demande = brut is num ? brut.toInt() : int.tryParse('$brut');
      _cadenceMinute =
          (demande != null && demande >= 1 && demande <= 60) ? demande : null;

      final SessionConfig cfg = SessionConfig.fromDocument(donnees);
      final List<SimTarget> targets = networkTargets(cfg);
      if (targets.isEmpty) {
        debugPrint('[NetworkWatch] aucune SIM configurée pour ce téléphone');
        return;
      }

      final List<Map<String, dynamic>> results = <Map<String, dynamic>>[];
      final List<String> messages = <String>[];

      for (final SimTarget t in targets) {
        // `maxWait: zero` : au relevé périodique on ne patiente pas 15 s.
        final SimNetworkCheck check = await SimNetworkGuard.check(
          t.slot,
          expected: t.operator,
          maxWait: Duration.zero,
        );
        final bool? previous = _lastOk[t.slot];
        _lastOk[t.slot] = check.ok;

        results.add(<String, dynamic>{
          'slot': t.slot,
          'operator': t.operator,
          'ok': check.ok,
          'label': check.state.networkLabel,
          'carrier': check.state.carrier,
          'signal': check.state.signalLevel,
          'reason': check.ok ? '' : check.reason,
          // [RESEAU 28/10/2026] Le cycle de récupération a besoin de savoir si
          // le mode avion est déjà actif (réglage volontaire : on n'y touche
          // pas) et si la carte est seulement sans couverture ou carrément
          // absente/verrouillée (auquel cas un cycle ne sert à rien).
          'airplane': check.state.airplaneMode,
          'simState': check.state.simState,
          'at': DateTime.now().toUtc().toIso8601String(),
        });

        if (!check.ok) {
          _downSince.putIfAbsent(t.slot, () => DateTime.now());
          final bool nouveauProbleme = previous != false;
          if (nouveauProbleme || _reminderDue(t.slot)) {
            messages.add(_downMessage(t, check, reminder: !nouveauProbleme));
            _lastAlert[t.slot] = DateTime.now();
          }
        } else {
          final DateTime? since = _downSince.remove(t.slot);
          _lastAlert.remove(t.slot);
          if (previous == false) messages.add(_backMessage(t, check, since));
        }
      }

      lastResults = results;
      // [QUOTA 29/10/2026] On n'écrit que si l'état a changé (une SIM tombe ou
      // revient), ou au plus tard toutes les 30 min pour montrer que le relevé
      // tourne. Chaque écriture déclenchait une lecture chez chaque écran
      // admin ouvert sur la liste des serveurs.
      final String empreinte = _empreinteReseau(results);
      final DateTime maintenant = DateTime.now();
      final bool aPublier = empreinte != _derniereEmpreinte ||
          _dernierePublication == null ||
          maintenant.difference(_dernierePublication!) >=
              const Duration(minutes: 30);
      if (aPublier) {
        await FirebaseFirestore.instance
            .collection('servers')
            .doc(_deviceId)
            .set(<String, dynamic>{
          'network': results,
          'networkOk': allOk,
          'networkCheckedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)).timeout(const Duration(seconds: 10));
        _derniereEmpreinte = empreinte;
        _dernierePublication = maintenant;
      }

      for (final String m in messages) {
        await SendEmail.sendMessagewithtelegram(message: m);
      }

      // [RESEAU 28/10/2026] Carte bloquée « appels d'urgence uniquement »
      // depuis assez longtemps : on tente un cycle court du mode avion (moins
      // de 2 min, Wi-Fi et données restaurés). C'est la seule action connue
      // pour forcer une nouvelle inscription. La tentative est sautée si une
      // session USSD tourne, et espacée de 30 min.
      unawaited(NetworkRecovery.instance.maybeRecover(
        deviceId: _deviceId,
        network: results,
        downSince: Map<int, DateTime>.from(_downSince),
      ));

      // [CADENCE 28/10/2026] Le rythme suit la charge : 5 min s'il reste des
      // commandes à livrer, 30 min sinon.
      setPendingWork(await _hasPendingWork());
      // [RESEAU 28/10/2026] Réseau de retour : on relance les commandes
      // gardées. Sert aussi de filet de sécurité toutes les 5 minutes.
      final Future<void> Function()? relance = onNetworkHealthy;
      if (relance != null &&
          results.any((Map<String, dynamic> r) => r['ok'] == true)) {
        unawaited(relance());
      }
      debugPrint('[NetworkWatch] état publié : '
          '${results.map((Map<String, dynamic> r) => 'slot ${(r['slot'] as int) + 1} ${r['ok'] == true ? 'OK' : 'KO'}').join(' · ')}');
    } catch (e) {
      // Un relevé manqué n'est pas une panne : le suivant corrigera.
      if (FirestoreBackoff.estTransitoire(e))
        FirestoreBackoff.instance.echec(e);
      debugPrint('[NetworkWatch] relevé impossible : $e');
    }
  }

  String? _derniereEmpreinte;
  DateTime? _dernierePublication;

  /// Ce qui compte pour l'admin : SIM en service ou non, et pourquoi. Le
  /// niveau de signal et l'heure du relevé varient à chaque passage et ne
  /// justifient pas, seuls, une écriture.
  static String _empreinteReseau(List<Map<String, dynamic>> results) => results
      .map((Map<String, dynamic> r) =>
          '${r['slot']}|${r['ok']}|${r['label']}|${r['reason']}|${r['simState']}|${r['airplane']}')
      .join(';');

  bool _reminderDue(int slot) {
    final DateTime? last = _lastAlert[slot];
    if (last == null) return false;
    return DateTime.now().difference(last) >= reminder;
  }

  String _downMessage(SimTarget t, SimNetworkCheck c,
      {required bool reminder}) {
    final DateTime? since = _downSince[t.slot];
    final String op = operatorDisplayName(t.operator);
    return '${reminder ? 'Recharge237 — TOUJOURS HORS RÉSEAU' : 'Recharge237 — RÉSEAU INDISPONIBLE'}\n'
        'Téléphone : $_deviceId\n'
        'SIM       : slot ${t.slot + 1} ($op)\n'
        'État      : ${c.state.networkLabel}'
        '${c.state.signalLevel >= 0 ? ' — signal ${c.state.signalLevel}/4' : ''}\n'
        'Motif     : ${c.reason}\n'
        'Depuis    : ${heureDe(since)}\n'
        'Effet     : aucune commande $op ne peut être livrée par ce téléphone '
        'tant que le réseau ne revient pas.';
  }

  String _backMessage(SimTarget t, SimNetworkCheck c, DateTime? since) {
    final String duree = since == null
        ? ''
        : '\nCoupure   : ${dureeCourte(DateTime.now().difference(since))}';
    return 'Recharge237 — RÉSEAU REVENU\n'
        'Téléphone : $_deviceId\n'
        'SIM       : slot ${t.slot + 1} (${operatorDisplayName(t.operator)})\n'
        'Réseau    : ${c.state.operatorName.isEmpty ? 'enregistré' : c.state.operatorName}'
        '${c.state.signalLevel >= 0 ? ' — signal ${c.state.signalLevel}/4' : ''}$duree';
  }
}

/// Heure locale « 15:32 » (ou « — » si inconnue).
String heureDe(DateTime? t) {
  if (t == null) return '—';
  final String h = t.hour.toString().padLeft(2, '0');
  final String m = t.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

/// Durée lisible : « 12 min », « 2 h 05 ».
String dureeCourte(Duration d) {
  if (d.inMinutes < 1) return '${d.inSeconds} s';
  if (d.inMinutes < 60) return '${d.inMinutes} min';
  final int h = d.inHours;
  final String m = (d.inMinutes % 60).toString().padLeft(2, '0');
  return '$h h $m';
}
