import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// [RESEAU 28/10/2026] Garde réseau placée AVANT toute session USSD, pour les
/// trois opérateurs (CAMTEL prépayé/postpayé, MTN crédit, MTN Boost/Good Deal,
/// Orange dès que son flux sera branché).
///
/// Pourquoi : constaté en production les 27 et 28/10. Une SIM `OUT_OF_SERVICE`
/// (aucune couverture) laissait l'app composer quand même le code. L'opérateur
/// ne répondait pas, ou répondait « Problème de connexion ou code IHM non
/// valide » au bout de plusieurs minutes, et la commande restait bloquée « en
/// cours » — le client ayant déjà payé. Le contrôle coûte une seconde ; il
/// évite une session perdue et permet d'écrire la vraie raison dans la
/// commande.
///
/// Le contrôle est aussi **spécifique à l'opérateur** : si l'emplacement confié
/// par l'admin contient la carte d'un autre opérateur (ex. une commande MTN sur
/// l'emplacement de la SIM CAMTEL), la session est refusée immédiatement au lieu
/// de composer un code MTN sur une SIM CAMTEL.

/// Codes MNC camerounais (MCC 624) des opérateurs livrés par le serveur.
/// `mccMnc` renvoyé par Android est le réseau d'origine de la CARTE
/// (`TelephonyManager.simOperator`) : il reste valable même en itinérance.
///
/// [29/10/2026] CAMTEL a DEUX codes : 03 et 05 (Blue 4G). Constaté sur les
/// deux SIM CAMTEL du Redmi M2003J15SC (62405), refusées à tort comme
/// « autre opérateur » : aucune commande CAMTEL n'aurait été livrée.
const Map<String, List<String>> kOperatorMnc = <String, List<String>>{
  'mtn': <String>['01'],
  'orange': <String>['02'],
  'camtel': <String>['03', '05'],
};

/// Nom lisible d'un code opérateur (`mtn` → « MTN »).
String operatorDisplayName(String code) {
  switch (code.toLowerCase()) {
    case 'mtn':
      return 'MTN';
    case 'orange':
      return 'Orange';
    case 'camtel':
      return 'CAMTEL';
    default:
      return code;
  }
}

/// Opérateur déduit d'un `mccMnc` camerounais, ou chaîne vide.
String operatorFromMccMnc(String mccMnc) {
  if (mccMnc.length < 5 || !mccMnc.startsWith('624')) return '';
  final String mnc = mccMnc.substring(3);
  for (final MapEntry<String, List<String>> e in kOperatorMnc.entries) {
    if (e.value.any(mnc.startsWith)) return operatorDisplayName(e.key);
  }
  return '';
}

/// États de SIM qui ne se débloquent pas tout seuls : inutile d'attendre.
const Set<String> kSimHardBlocked = <String>{
  'ABSENT',
  'PIN_REQUIRED',
  'PUK_REQUIRED',
  'NETWORK_LOCKED',
  'PERM_DISABLED',
  'CARD_IO_ERROR',
  'CARD_RESTRICTED',
};

/// Photographie du réseau mobile d'UNE SIM, telle que lue sur le téléphone
/// (canal natif `r237/ussd` → `MainActivity.describeServiceState`).
///
/// Classe pure : testable sans téléphone (test/sim_network_test.dart).
class SimNetworkState {
  /// Emplacement de la SIM (0 = SIM 1).
  final int slot;

  /// Faux si Android n'a pas pu donner l'état. Dans ce cas on ne bloque pas :
  /// mieux vaut tenter la session que refuser à cause de notre propre
  /// aveuglement (permission refusée, constructeur exotique...).
  final bool known;

  /// La SIM est enregistrée sur le réseau de son opérateur.
  final bool registered;

  /// Réseau trouvé pour les appels d'urgence uniquement (aucun USSD).
  final bool emergencyOnly;

  final bool airplaneMode;

  /// Nom du réseau sur lequel la carte est enregistrée (ex. « MTN »).
  final String operatorName;

  /// Nom porté par la carte elle-même (ex. « MTN », « Blue »).
  final String carrier;

  /// Réseau d'origine de la carte (ex. « 62401 »).
  final String mccMnc;

  /// 0 à 4, `-1` si inconnu.
  final int signalLevel;

  /// État brut d'Android : `IN_SERVICE`, `OUT_OF_SERVICE`, `EMERGENCY_ONLY`…
  final String networkLabel;

  /// `READY`, `ABSENT`, `PIN_REQUIRED`, `NOT_READY`, `UNKNOWN`…
  final String simState;

  final String detail;

  const SimNetworkState({
    required this.slot,
    required this.known,
    required this.registered,
    required this.emergencyOnly,
    required this.airplaneMode,
    required this.operatorName,
    required this.carrier,
    required this.mccMnc,
    required this.signalLevel,
    required this.networkLabel,
    required this.simState,
    required this.detail,
  });

  factory SimNetworkState.fromMap(int slot, Map<String, dynamic>? m) {
    if (m == null)
      return SimNetworkState.unknown(slot, 'état réseau illisible');
    String str(String key) => (m[key] ?? '').toString().trim();
    int integer(String key, [int fallback = -1]) =>
        (m[key] as num?)?.toInt() ?? fallback;
    final String simState = str('simState');
    return SimNetworkState(
      slot: slot,
      // Clé absente = ancienne version du natif : on suppose l'état lisible.
      known: m['known'] != false,
      registered: m['registered'] == true,
      emergencyOnly: m['emergencyOnly'] == true,
      airplaneMode: m['airplaneMode'] == true,
      operatorName: str('operator'),
      carrier: str('carrier'),
      mccMnc: str('mccMnc'),
      signalLevel: integer('signalLevel'),
      networkLabel: str('stateLabel'),
      simState: simState.isEmpty ? 'UNKNOWN' : simState,
      detail: str('detail'),
    );
  }

  factory SimNetworkState.unknown(int slot, String detail) => SimNetworkState(
        slot: slot,
        known: false,
        registered: false,
        emergencyOnly: false,
        airplaneMode: false,
        operatorName: '',
        carrier: '',
        mccMnc: '',
        signalLevel: -1,
        networkLabel: 'UNKNOWN',
        simState: 'UNKNOWN',
        detail: detail,
      );

  /// « SIM 1 »
  String get label => 'SIM ${slot + 1}';

  /// « SIM 1 (MTN) »
  String get simLabel => carrier.isEmpty ? label : '$label ($carrier)';

  /// La carte est présente et déverrouillée.
  bool get simReady => !kSimHardBlocked.contains(simState);

  /// Vrai si une session USSD a une chance d'aboutir.
  bool get usable {
    if (!known) return true; // état illisible : on ne bloque pas
    if (airplaneMode) return false;
    if (!simReady) return false;
    return registered;
  }

  /// Vrai si l'état peut se débloquer seul en quelques secondes (recherche de
  /// réseau, ré-enregistrement après une coupure) : cela vaut la peine
  /// d'attendre avant de refuser.
  bool get transient => !usable && !airplaneMode && simReady;

  /// Explication en français, écrite dans `failure_reason` et envoyée à
  /// l'admin : elle doit lui dire quoi faire, pas seulement que ça a échoué.
  String get reason {
    if (airplaneMode) {
      return 'Mode avion activé sur ce téléphone : aucun USSD ne peut aboutir '
          '($label). Désactive le mode avion.';
    }
    switch (simState) {
      case 'ABSENT':
        return "Aucune SIM dans l'emplacement ${slot + 1} : aucune commande ne "
            'peut être exécutée.';
      case 'PIN_REQUIRED':
        return '$label verrouillée par code PIN : déverrouille-la sur le '
            'téléphone.';
      case 'PUK_REQUIRED':
        return '$label bloquée (code PUK requis) : déverrouille-la sur le '
            'téléphone.';
      case 'NETWORK_LOCKED':
        return '$label verrouillée sur un autre opérateur : aucun USSD possible.';
      case 'PERM_DISABLED':
      case 'CARD_IO_ERROR':
      case 'CARD_RESTRICTED':
        return '$label désactivée ou illisible : change la carte ou redémarre '
            'le téléphone.';
    }
    if (registered) {
      return 'Réseau mobile indisponible sur $simLabel.';
    }
    final String op = operatorName.isNotEmpty ? ' ($operatorName)' : '';
    final String why = emergencyOnly || networkLabel == 'EMERGENCY_ONLY'
        ? "appels d'urgence seulement"
        : 'aucune couverture mobile';
    return '$simLabel hors réseau$op : $why. Aucun code USSD composé.';
  }

  /// Vrai si cette carte n'est pas celle de l'opérateur attendu.
  ///
  /// Ne se prononce que sur un `mccMnc` camerounais identifiable : une carte
  /// lue sans réseau d'origine (ou étrangère) ne déclenche jamais de refus.
  String? operatorMismatch(String expected) {
    final List<String> want =
        kOperatorMnc[expected.toLowerCase()] ?? const <String>[];
    if (want.isEmpty) return null;
    if (mccMnc.length < 5 || !mccMnc.startsWith('624')) return null;
    if (want.any(mccMnc.substring(3).startsWith)) return null;
    final String found = operatorFromMccMnc(mccMnc);
    return '$simLabel porte ${found.isEmpty ? 'un autre opérateur ($mccMnc)' : found} '
        ': une commande ${operatorDisplayName(expected)} ne peut pas y être '
        'exécutée. Corrige l\'emplacement dans servers/{deviceId}.';
  }

  /// Ligne de journal (aucun secret).
  String get summary =>
      '$simLabel · ${networkLabel.isEmpty ? simState : networkLabel}'
      '${emergencyOnly ? ' (urgence)' : ''} · réseau "${operatorName}" · '
      'carte "$carrier" $mccMnc · signal $signalLevel/4 · SIM $simState'
      '${detail.isNotEmpty ? ' · $detail' : ''}';
}

/// Verdict d'une vérification : l'état lu et, si la session ne doit pas partir,
/// le motif exact.
class SimNetworkCheck {
  final SimNetworkState state;
  final String? problem;

  const SimNetworkCheck(this.state, this.problem);

  /// Vrai si la session peut être lancée.
  bool get ok => problem == null;

  String get reason => problem ?? state.reason;

  String get slotLabel => state.label;
}

/// Lecture de l'état réseau et attente bornée avant de refuser.
class SimNetworkGuard {
  SimNetworkGuard._();

  static const MethodChannel _native = MethodChannel('r237/ussd');

  /// Délai maximal passé à attendre que la SIM s'enregistre (recherche de
  /// réseau après une coupure, réveil du téléphone). Au-delà, on refuse avec
  /// la vraie raison au lieu de laisser une session traîner des minutes.
  ///
  /// 15 s : mesuré le 28/10 sur le téléphone de production, un refus coûtait
  /// 20 s de file d'attente pour toutes les autres commandes. Assez pour un
  /// ré-enregistrement ordinaire, sans bloquer le serveur.
  static const Duration defaultWait = Duration(seconds: 15);

  static Future<SimNetworkState> read(int slot) async {
    try {
      final Map<String, dynamic>? m =
          await _native.invokeMapMethod<String, dynamic>(
        'serviceState',
        <String, dynamic>{'slot': slot},
      );
      return SimNetworkState.fromMap(slot, m);
    } catch (e) {
      debugPrint('[SimNetwork] état de la SIM ${slot + 1} illisible : $e');
      return SimNetworkState.unknown(slot, e.toString());
    }
  }

  /// Lit l'état, laisse à la SIM le temps de s'enregistrer si elle est en
  /// recherche, puis rend le verdict.
  ///
  /// [expected] : opérateur attendu (`mtn`, `orange`, `camtel`). Si la carte de
  /// l'emplacement est celle d'un autre opérateur, la session est refusée.
  static Future<SimNetworkCheck> check(
    int slot, {
    String? expected,
    Duration maxWait = defaultWait,
    Duration poll = const Duration(seconds: 3),
  }) async {
    SimNetworkState state = await read(slot);
    final DateTime limit = DateTime.now().add(maxWait);
    while (state.transient && DateTime.now().isBefore(limit)) {
      debugPrint('[SimNetwork] ${state.label} en recherche de réseau '
          '(${state.networkLabel}) — nouvelle vérification dans '
          '${poll.inSeconds} s');
      await Future<void>.delayed(poll);
      state = await read(slot);
    }
    debugPrint('[SimNetwork] ${state.summary}');
    if (!state.usable) return SimNetworkCheck(state, state.reason);
    return SimNetworkCheck(
        state, expected == null ? null : state.operatorMismatch(expected));
  }
}
