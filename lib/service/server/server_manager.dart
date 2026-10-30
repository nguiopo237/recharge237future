import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:unique_identifier/unique_identifier.dart';

import 'package:firebase_auth/firebase_auth.dart';

import '../sendmail/send_mail.dart';
import 'firestore_backoff.dart';
import 'internet_watch.dart';
import 'network_watch.dart' show dureeCourte;
import 'order_filters.dart' as filters;
import 'sim_probe.dart';
import 'slot_config.dart';

/// Gère l'enregistrement de ce téléphone comme serveur de recharge
/// et écrit un heartbeat toutes les 30 minutes (contrôle par lecture toutes
/// les 5 min, cf. [heartbeatInterval]).
///
/// Chaque téléphone se configure dans Firestore via
/// `servers/{deviceId}` :
///
/// ```
/// {
///   "name":      "Téléphone Orange #1",   // optionnel, affiché dans l'admin
///   "operators": ["orange"],               // "all" | "orange" | "mtn" | "prepaid" | "postpaid"
///   "simMTN":   { "pin": "1234" },        // le PIN seul suffit
///   "handles":  ["mtn_airtime", "mtn_forfait"]  // routage voulu par l'admin
/// }
/// ```
///
/// `handles` décide de ce que CE téléphone exécute : `camtel_pre`,
/// `camtel_post`, `mtn_airtime`, `mtn_forfait` (requête + activation), ou
/// `all`. Absent/vide = tout ce que son matériel permet. Le matériel reste
/// une garde de sécurité : un type assigné à un téléphone qui n'a pas la SIM
/// correspondante n'est jamais exécuté ici (la commande reste aux autres).
///
/// Le téléphone DÉCLARE lui-même son matériel à chaque démarrage (et à chaque
/// `reload_config`) : modèle et SIM actives avec opérateur et emplacement,
/// dans `model`, `manufacturer`, `sims` et `simsDetectedAt`. L'admin n'a donc
/// qu'à renseigner les PIN (et éventuellement `name`) : les emplacements sont
/// lus depuis `sims` par SessionConfig, ou forcés en écrivant `slot` dans
/// `simMTN` / `simCamtelPre` / `simCamtelPost`.
///
/// Si le document n'existe pas encore, le téléphone traite tout
/// (comportement par défaut `operators: ["all"]`).
class ServerManager {
  ServerManager._();
  static final ServerManager instance = ServerManager._();

  String _deviceId = 'unknown';
  String get deviceId => _deviceId;

  List<String> _operators = ['all'];
  List<String> _handles = const <String>[];
  Timer? _heartbeatTimer;

  /// [28/10/2026] Chien de garde Firestore.
  ///
  /// Après une coupure réseau, le client Firestore peut rester « figé » :
  /// l'app tourne, mais plus aucune écriture ne part (heartbeat immobile,
  /// commandes bloquées au statut 20). Constaté le 28/10 : heartbeat figé
  /// 169 s alors que le téléphone répondait au ping. On force alors une
  /// reconnexion propre du client.
  DateTime _lastAck = DateTime.now();
  bool _reconnecting = false;
  static const Duration _heartbeatTimeout = Duration(seconds: 10);

  /// [QUOTA 29/10/2026] Battement toutes les 2 min (au lieu de 30 s) : 720
  /// écritures par jour et par téléphone au lieu de 2 880, et autant de
  /// lectures en moins chez chaque admin qui regarde la liste des serveurs.
  /// Les scripts du PC (`_claude_keepalive.sh`, `_claude_watch_servers.js`)
  /// ont été réglés en conséquence : ne pas raccourcir l'un sans l'autre.
  ///
  /// [QUOTA 29/10/2026 bis] 4 min : 360 écritures/jour/téléphone au lieu de
  /// 720 (3 téléphones = ~1 000 écritures/jour économisées sur 20 000, soit
  /// ~200 commandes de plus par jour). Seuils associés : figé après 9 min
  /// ici, « SILENCIEUX » après 9 min dans l'écran admin, relance par le PC
  /// après 540 s.
  ///
  /// [QUOTA 29/10/2026 ter] Demande de l'admin : battement ÉCRIT toutes les
  /// 30 min seulement (48 écritures/jour/téléphone au lieu de 720). Entre
  /// deux écritures, un contrôle toutes les 5 min par une LECTURE serveur
  /// (1 lecture : le quota de lectures est 2,5 fois plus large) garde la
  /// détection d'une base figée en ~10 min au lieu d'une heure.
  /// Seuils associés : « SILENCIEUX » après 65 min dans l'écran admin,
  /// relance par le PC après 3 900 s.
  static const Duration heartbeatInterval = Duration(minutes: 5);
  static const Duration ecritureInterval = Duration(minutes: 30);
  static const Duration _staleAfter = Duration(minutes: 11);
  DateTime? _derniereEcriture;

  /// Évite d'envoyer une alerte Telegram « quota » à chaque battement raté.
  bool _quotaSignale = false;

  /// Dernière empreinte des cartes publiée : évite une LECTURE du document
  /// serveur à chaque inventaire (seul le premier inventaire lit la base).
  String? _signaturePubliee;

  /// [INTERNET 28/10/2026] Surveillance de la liaison avec la base.
  ///
  /// Différent du réseau de l'opérateur : une SIM peut être parfaitement
  /// enregistrée et le téléphone sans Internet (Wi-Fi coupé, forfait épuisé,
  /// données désactivées). Dans ce cas il ne livre plus rien — et il ne peut
  /// pas le dire en temps réel, puisque Telegram passe par Internet.
  ///
  /// Deux canaux complètent donc ce silence : ce téléphone prévient dès que
  /// la base redevient joignable (avec la durée de la coupure), et le script
  /// `_claude_watch_servers.js` côté PC alerte quand un téléphone se tait.
  /// Machine à états pure (testée dans test/internet_watch_test.dart).
  final InternetWatch _internet =
      InternetWatch(seuil: const Duration(minutes: 5));

  /// Vrai si la base a répondu au dernier contrôle.
  bool get internetOk => _internet.ok;

  /// [TRACE 28/10/2026] Empreinte des cartes détectées, pour signaler sur
  /// Telegram tout changement matériel : carte remplacée, permutée de slot ou
  /// retirée. L'admin le voit sans être devant le téléphone, et les
  /// emplacements déclarés (`slots`) peuvent alors être corrigés s'ils ne
  /// correspondent plus au matériel.
  ///
  /// Comparée à `simsSignature` en base (et non à une valeur en mémoire) : un
  /// redémarrage de l'app ne produit donc aucune fausse alerte.
  int _beats = 0;

  /// Types d'opération confiés à ce téléphone par l'admin (`handles`).
  List<String> get handles => List<String>.unmodifiable(_handles);

  /// [CONFIG SIM 29/10/2026] Faux tant que l'admin n'a déclaré aucune SIM :
  /// le téléphone ne prend alors aucune commande et l'écran le signale.
  bool get configured => _configured;
  bool _configured = true;

  /// Vrai si ce téléphone doit exécuter [type] (`camtel_pre`, `camtel_post`,
  /// `mtn_airtime`, `mtn_forfait`). Liste vide = tout ce que le matériel
  /// permet.
  bool handlesOperation(String type) =>
      filters.handlesOperation(_handles, type);

  // Préfixes Orange Cameroun
  static const _orangePrefixes = ['069', '065', '655', '656', '657', '659'];
  // Préfixes MTN Cameroun
  static const _mtnPrefixes = [
    '067',
    '068',
    '650',
    '651',
    '652',
    '653',
    '654',
    '677',
    '678',
    '679'
  ];

  /// À appeler une seule fois dans `initState` du widget principal.
  Future<void> initialize() async {
    // 1. Résoudre l'identifiant unique de l'appareil
    try {
      _deviceId = (await UniqueIdentifier.serial) ?? _fallbackId();
    } on PlatformException {
      _deviceId = _fallbackId();
    }

    // 2. Créer / mettre à jour le document serveur (merge pour ne pas écraser la config)
    //
    // [SANTE 29/10/2026] Téléphone neuf ou réinstallé : son UID anonyme n'est
    // pas admin, la base refuse l'écriture. Il demande alors lui-même son
    // autorisation (bouton « Autoriser » de l'écran Serveurs de l'admin) et
    // attend, sans que personne ait à toucher au téléphone.
    await _attendreAutorisationSiBesoin();
    await _upsert({
      'status': 'online',
      'lastSeen': FieldValue.serverTimestamp(),
      // [INTERNET 28/10/2026] Marqueur lisible par l'admin : une coupure ne
      // peut pas être écrite en temps réel (plus de connexion), mais ce champ
      // reste faux après le retour tant que le téléphone n'a pas repris.
      'internetOk': true,
      'internetLastOkAt': FieldValue.serverTimestamp(),
    });

    // 3. Publier le matériel (modèle + SIM détectées) pour l'admin
    await _publishHardware();

    // 4. Charger la configuration (opérateurs gérés par ce téléphone)
    await _loadConfig();

    // 5. Démarrer le heartbeat (toutes les 2 min)
    _lastAck = DateTime.now();
    _reconnecting = false;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      heartbeatInterval,
      (_) => _sendHeartbeat(),
    );

    debugPrint(
        '[ServerManager] Démarré — deviceId=$_deviceId, operators=$_operators');
  }

  /// Recharge la liste des opérateurs depuis Firestore (appelé par reload_config)
  /// et redétecte les SIM (une carte a pu être changée depuis le démarrage).
  Future<void> reloadOperators() async {
    // Demande explicite de l'admin : on refait vraiment l'inventaire.
    _signaturePubliee = null;
    await _publishHardware();
    await _loadConfig();
  }

  /// Décrit le matériel de CE téléphone dans `servers/{deviceId}`.
  ///
  /// `name` n'est jamais touché ici : c'est l'admin qui le choisit. En cas
  /// d'échec de lecture, on n'écrit rien plutôt que d'effacer une détection
  /// précédente avec une liste vide.
  ///
  /// [TRACE 28/10/2026] Toute modification de l'inventaire des cartes part
  /// aussi sur Telegram : c'est le seul moyen de savoir qu'une SIM a bougé
  /// quand l'admin n'a pas le téléphone sous les yeux.
  Future<void> _publishHardware() async {
    final hw = await SimProbe.detect();
    if (hw == null) return;
    final String signature = simSignatureOf(hw.sims);
    // [QUOTA 29/10/2026] Cartes inchangées depuis la dernière publication :
    // ni lecture ni écriture.
    if (_signaturePubliee == signature) return;
    if (FirestoreBackoff.instance.enPause) return;
    try {
      // Ce qui était publié avant, pour ne signaler qu'un VRAI changement
      // (une première détection ne doit pas produire d'alerte). Lu une seule
      // fois par démarrage ; ensuite la mémoire suffit.
      Object? avant = _signaturePubliee;
      if (avant == null) {
        final doc = await FirebaseFirestore.instance
            .collection('servers')
            .doc(_deviceId)
            .get();
        avant = doc.data()?['simsSignature'];
      }

      await _upsert({
        'model': hw.model,
        'manufacturer': hw.manufacturer,
        'sdk': hw.sdk,
        'sims': hw.sims.map((s) => s.toMap()).toList(),
        'simsSignature': signature,
        'simsDetectedAt': FieldValue.serverTimestamp(),
      });
      _signaturePubliee = signature;
      debugPrint(
          '[ServerManager] Matériel publié : ${hw.model} — ${hw.sims.join(', ')}');

      if (avant is String && avant.isNotEmpty && avant != signature) {
        await _signalerChangementSim(avant, hw.sims);
      }
    } catch (e) {
      if (FirestoreBackoff.estTransitoire(e)) {
        FirestoreBackoff.instance.echec(e);
      }
      debugPrint('[ServerManager] Publication du matériel impossible : $e');
    }
  }

  /// Annonce sur Telegram un changement de cartes, avec l'avant et l'après.
  Future<void> _signalerChangementSim(
      String avant, List<DetectedSim> apres) async {
    final String avantLisible = simSignatureVersTexte(avant);
    final String apresLisible = apres.isEmpty
        ? 'aucune carte'
        : apres
            .map((s) => simSignatureVersTexte(simSignatureOf(<DetectedSim>[s])))
            .join('\n');
    try {
      await SendEmail.sendMessagewithtelegram(
        message: 'Recharge237 — CHANGEMENT DE SIM\n'
            'Téléphone : $_deviceId\n'
            'Avant :\n$avantLisible\n'
            'Après :\n$apresLisible\n'
            'Vérifie les emplacements déclarés (slots) et les PIN dans la base : '
            'une commande part sur une carte n\'a pas les droits nécessaires échoue.',
      );
      debugPrint('[ServerManager] Changement de SIM signalé sur Telegram');
    } catch (e) {
      debugPrint('[ServerManager] Alerte changement de SIM impossible : $e');
    }
  }

  Future<void> _loadConfig() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('servers')
          .doc(_deviceId)
          .get();
      if (doc.exists) {
        final data = doc.data();
        final raw = data?['operators'];
        if (raw is List && raw.isNotEmpty) {
          _operators = raw.map((e) => e.toString()).toList();
        }
        // [CONFIG SIM 29/10/2026] `slots` fait foi : `handles` en est déduit.
        _handles = effectiveHandles(data ?? const <String, dynamic>{});
        _configured = isServerConfigured(data ?? const <String, dynamic>{});
      } else {
        _handles = const <String>[kNoHandles];
        _configured = false;
      }
      debugPrint(
          '[ServerManager] Routage : ${_configured ? _handles.join(', ') : 'NON CONFIGURÉ — aucune commande prise'}');
    } catch (e) {
      debugPrint('[ServerManager] _loadConfig error: $e');
    }
  }

  /// [SANTE 29/10/2026] cf. docs/EXPLOITATION_TELEPHONES.md §3.2.
  ///
  /// Essaie une écriture minuscule sur `servers/{deviceId}`. Si la base la
  /// refuse pour droits insuffisants, le téléphone :
  ///  1. dépose une demande dans `server_enrollments/{uid}` (autorisé par
  ///     firestore.rules pour son propre UID uniquement) ;
  ///  2. prévient sur Telegram ;
  ///  3. relit SON document `users/{uid}` toutes les 60 s jusqu'à
  ///     `isadmin == true` (1 lecture/min, seulement pendant l'attente).
  Future<void> _attendreAutorisationSiBesoin() async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    try {
      await _upsert({'authUid': uid});
      return;
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') return;
    } catch (_) {
      return;
    }

    debugPrint('[ServerManager] UID $uid non autorisé — demande envoyée');
    final hw = await SimProbe.detect();
    try {
      await FirebaseFirestore.instance
          .collection('server_enrollments')
          .doc(uid)
          .set(<String, dynamic>{
        'deviceId': _deviceId,
        'model': hw?.model ?? '',
        'manufacturer': hw?.manufacturer ?? '',
        'requestedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[ServerManager] Demande d\'autorisation impossible : $e');
    }
    try {
      await SendEmail.sendMessagewithtelegram(
        message: 'Recharge237 — TÉLÉPHONE À AUTORISER\n'
            'Téléphone : $_deviceId${hw == null ? '' : ' (${hw.model})'}\n'
            'UID : $uid\n'
            'Ce téléphone ne peut pas lire les commandes. Ouvre l\'app admin > '
            'Serveurs > « Téléphones à autoriser » et appuie sur Autoriser. '
            'Il reprendra tout seul dans la minute.',
      );
    } catch (_) {}

    while (true) {
      await Future<void>.delayed(const Duration(seconds: 60));
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get(const GetOptions(source: Source.server));
        if (doc.data()?['isadmin'] == true) {
          debugPrint('[ServerManager] Téléphone autorisé — démarrage');
          return;
        }
      } catch (e) {
        if (FirestoreBackoff.estTransitoire(e)) {
          await Future<void>.delayed(FirestoreBackoff.instance.echec(e));
        }
      }
    }
  }

  Future<void> _upsert(Map<String, dynamic> fields) async {
    await FirebaseFirestore.instance
        .collection('servers')
        .doc(_deviceId)
        .set({'deviceId': _deviceId, ...fields}, SetOptions(merge: true));
  }

  Future<void> _sendHeartbeat() async {
    // [QUOTA 29/10/2026] Base saturée ou injoignable : on respecte la pause
    // du backoff au lieu d'insister à chaque battement.
    if (FirestoreBackoff.instance.enPause) {
      debugPrint('[ServerManager] battement sauté (pause '
          '${FirestoreBackoff.instance.resteAttente.inSeconds} s)');
      return;
    }

    // [QUOTA 29/10/2026] La preuve de liaison est l'ACCUSÉ de l'écriture :
    // `update()` ne se termine qu'une fois la base l'a enregistrée (hors
    // ligne, il reste en attente et le délai expire). L'ancienne lecture
    // `Source.server` faite en plus à chaque battement coûtait 2 880 lectures
    // par jour et par téléphone pour la même information.
    bool joignable;
    try {
      final DateTime maintenant = DateTime.now();
      final bool ecrire = _derniereEcriture == null ||
          maintenant.difference(_derniereEcriture!) >= ecritureInterval;
      final DocumentReference<Map<String, dynamic>> ref =
          FirebaseFirestore.instance.collection('servers').doc(_deviceId);
      if (ecrire) {
        await ref.update({
          'status': 'online',
          'lastSeen': FieldValue.serverTimestamp()
        }).timeout(_heartbeatTimeout);
        _derniereEcriture = maintenant;
      } else {
        // Contrôle de liaison sans écriture : lecture forcée sur le serveur.
        await ref
            .get(const GetOptions(source: Source.server))
            .timeout(_heartbeatTimeout);
      }
      joignable = true;
      FirestoreBackoff.instance.succes();
      if (_quotaSignale) {
        _quotaSignale = false;
        _envoyerTelegram('Recharge237 — QUOTA FIRESTORE : base de nouveau '
            'disponible\nTéléphone : $_deviceId');
      }
    } catch (e) {
      debugPrint('[ServerManager] Heartbeat non confirmé : $e');
      if (FirestoreBackoff.estSaturation(e)) {
        // Le quota n'est pas une coupure Internet : pas d'alerte « internet
        // coupé », pas de reconnexion forcée (elle coûterait des lectures).
        final Duration pause = FirestoreBackoff.instance.echec(e);
        if (!_quotaSignale) {
          _quotaSignale = true;
          _envoyerTelegram('Recharge237 — QUOTA FIRESTORE ATTEINT\n'
              'Téléphone : $_deviceId\n'
              'La base refuse les requêtes (RESOURCE_EXHAUSTED). Le serveur '
              'ralentit (pause ${pause.inSeconds} s, doublée à chaque échec, '
              'max 5 min) et reprend seul.');
        }
        return;
      }
      if (FirestoreBackoff.estTransitoire(e)) {
        FirestoreBackoff.instance.echec(e);
      }
      joignable = false;
    }

    final InternetEvent evenement = _internet.beat(
      joignable: joignable,
      maintenant: DateTime.now(),
    );
    if (joignable) {
      _lastAck = DateTime.now();
      if (evenement == InternetEvent.retour) {
        await _surInternetOk(coupure: _internet.derniereCoupure);
      }
      // Inventaire des cartes toutes les 30 min (6 contrôles de 5 min) ;
      // il ne touche la base que si une carte a changé.
      _beats++;
      if (_beats % 6 == 0) {
        await _publishHardware();
      }
      return;
    }

    final int stale = DateTime.now().difference(_lastAck).inSeconds;
    debugPrint('[ServerManager] Base injoignable depuis ${stale}s');
    if (evenement == InternetEvent.perte) {
      await _alerterInternet(stale, rappel: false);
    } else if (evenement == InternetEvent.rappel) {
      await _alerterInternet(stale, rappel: true);
    }
    if (DateTime.now().difference(_lastAck) >= _staleAfter) {
      await _reconnectFirestore();
    }
  }

  /// La base est joignable : si l'on sortait d'une coupure, on le signale.
  Future<void> _surInternetOk({required Duration? coupure}) async {
    try {
      await _upsert({
        'internetOk': true,
        'internetLastOkAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
    final String duree =
        coupure == null ? '' : '\nCoupure   : ${dureeCourte(coupure)}';
    try {
      await SendEmail.sendMessagewithtelegram(
        message: 'Recharge237 — INTERNET REVENU\n'
            'Téléphone : $_deviceId\n'
            'Base de données : de nouveau joignable$duree\n'
            'Les commandes gardées pendant la coupure repartent '
            'automatiquement, dans leur ordre d\'arrivée.',
      );
    } catch (e) {
      debugPrint('[ServerManager] Telegram injoignable : $e');
    }
    debugPrint(
        '[ServerManager] Internet revenu${coupure == null ? '' : ' après ${dureeCourte(coupure)}'}');
  }

  Future<void> _envoyerTelegram(String message) async {
    try {
      await SendEmail.sendMessagewithtelegram(message: message);
    } catch (e) {
      debugPrint('[ServerManager] Telegram injoignable : $e');
    }
  }

  /// Message Telegram (best effort : sans Internet il ne partira pas — c'est
  /// justement pourquoi le script côté PC surveille aussi le silence).
  Future<void> _alerterInternet(int muetSecondes,
      {required bool rappel}) async {
    try {
      await SendEmail.sendMessagewithtelegram(
        message:
            '${rappel ? 'Recharge237 — TOUJOURS SANS INTERNET' : 'Recharge237 — INTERNET COUPÉ'}\n'
            'Téléphone : $_deviceId\n'
            'Base de données injoignable depuis ${dureeCourte(Duration(seconds: muetSecondes))}\n'
            'Effet : ce téléphone ne livre plus rien. Il ne peut pas prévenir '
            'en temps réel ; les commandes sont gardées et repartiront au retour.',
      );
    } catch (e) {
      debugPrint('[ServerManager] Alerte Internet impossible à envoyer : $e');
    }
  }

  /// Ferme puis relance proprement le client Firestore (nouvelle connexion
  /// HTTP). Sans cela, l'app continuait à lire son cache et croyait écrire,
  /// alors que rien n'atteignait la base.
  Future<void> _reconnectFirestore() async {
    if (_reconnecting) return;
    _reconnecting = true;
    try {
      debugPrint('[ServerManager] Reconnexion Firestore…');
      await FirebaseFirestore.instance.terminate();
      await FirebaseFirestore.instance.enableNetwork();
      _lastAck = DateTime.now();
    } catch (e) {
      debugPrint('[ServerManager] Reconnexion impossible : $e');
    } finally {
      _reconnecting = false;
    }
  }

  /// À appeler dans `dispose` pour marquer le téléphone hors-ligne.
  Future<void> goOffline() async {
    _heartbeatTimer?.cancel();
    try {
      await FirebaseFirestore.instance
          .collection('servers')
          .doc(_deviceId)
          .update(
              {'status': 'offline', 'lastSeen': FieldValue.serverTimestamp()});
    } catch (_) {}
  }

  /// Détermine si CE téléphone doit traiter une transaction donnée.
  ///
  /// [numeroorange] : numéro du payeur (Orange ou MTN)
  /// [status]       : statut actuel de la transaction
  bool canHandle({required String numeroorange, required String status}) {
    if (_operators.contains('all')) return true;

    final prefix = numeroorange.length >= 3 ? numeroorange.substring(0, 3) : '';

    // Filtrage par type de recharge
    if (_operators.contains('prepaid') && (status == '1' || status == '9')) {
      return true;
    }
    if (_operators.contains('postpaid') && (status == '6')) return true;

    // Filtrage par opérateur payeur
    if (_operators.contains('orange') && _orangePrefixes.contains(prefix)) {
      return true;
    }
    if (_operators.contains('mtn') && _mtnPrefixes.contains(prefix)) {
      return true;
    }

    return false;
  }

  String _fallbackId() => 'srv_${DateTime.now().millisecondsSinceEpoch}';
}

// ── Empreinte des cartes (traçabilité Telegram) ────────────────────────────
//
// Fonctions pures, séparées de ServerManager pour être testables sans
// Firestore ni canal natif.

/// Empreinte stable de l'inventaire des cartes : une entrée par emplacement,
/// triée, au format `slot:operateur:marque:mccMnc`.
String simSignatureOf(List<DetectedSim> sims) {
  final List<String> parts = sims
      .map((s) => '${s.slot}:${s.operator}:${s.carrier}:${s.mccMnc}')
      .toList();
  parts.sort();
  return parts.join('|');
}

/// Rend une entrée d'empreinte lisible par un humain sur Telegram.
String simSignatureVersTexte(String part) {
  if (part.isEmpty) return 'aucune carte';
  final List<String> f = part.split(':');
  if (f.length < 4) return part;
  final int slot = (int.tryParse(f[0]) ?? 0) + 1;
  final String operateur = f[1].toUpperCase();
  // La marque peut contenir ':' (rare) : on recolle tout le milieu.
  final String marque = f.sublist(2, f.length - 1).join(':');
  final String reseau = f.last;
  return 'SIM $slot — $operateur (marque « $marque »)'
      '${reseau.isEmpty ? '' : ' · réseau $reseau'}';
}
