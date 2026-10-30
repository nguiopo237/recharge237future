/// [EMPLACEMENTS 28/10/2026] Configuration des SIM **par emplacement**, pilotée
/// par l'admin depuis la base — plus aucune hypothèse dans le code.
///
/// Jusqu'ici le serveur devinait où se trouvait chaque carte : une SIM MTN en
/// emplacement 1 sur un téléphone, en emplacement 2 sur un autre, et une
/// permutation de puces le matin suffisait à envoyer un USSD MTN sur une carte
/// CAMTEL. L'admin écrit désormais, pour chaque téléphone, ce que contient
/// chaque emplacement :
///
/// ```json
/// servers/{deviceId}
/// {
///   "slots": [
///     { "slot": 0, "code": "mtn",         "pin": "1234", "active": true,  "minBalance": 5000 },
///     { "slot": 1, "code": "camtel_post", "pin": "5678", "active": true,  "minBalance": 20000 }
///   ]
/// }
/// ```
///
/// `slot` est l'index physique Android : **0 = SIM 1**, 1 = SIM 2.
///
/// `code` décrit ce que l'emplacement sert, et se traduit directement en
/// `operateur_cible` des commandes :
///
/// | code          | commandes servies                              |
/// |---------------|------------------------------------------------|
/// | `mtn`         | `mtn_airtime`, `mtn_forfait`, `mtn_forfait_activate` |
/// | `orange`      | `orange_airtime`                               |
/// | `camtel_pre`  | `camtel_pre`                                   |
/// | `camtel_post` | `camtel_post`                                  |
/// | *(vide)*      | emplacement libre : ignoré par le serveur      |
///
/// `active: false` retire l'opérateur de ce téléphone sans effacer son PIN :
/// les commandes concernées sont laissées à un autre téléphone au lieu
/// d'échouer ici.
///
/// `minBalance` (0 = pas d'alerte) remplace le seuil global
/// `app_config/report.seuil_solde` pour cet opérateur, quand les soldes
/// arrivent par SMS.
///
/// Ce fichier ne contient aucune logique Firestore : uniquement du texte vers
/// un modèle. C'est testé dans `test/slot_config_test.dart`.
library;

import 'package:flutter/foundation.dart';

/// Emplacement libre : le serveur n'y touche pas.
const String kSlotFree = '';

const String kSlotMtn = 'mtn';
const String kSlotOrange = 'orange';
const String kSlotCamtelPre = 'camtel_pre';
const String kSlotCamtelPost = 'camtel_post';

/// Tous les codes acceptés par l'admin, dans l'ordre d'affichage.
const List<String> kSlotCodes = <String>[
  kSlotFree,
  kSlotMtn,
  kSlotOrange,
  kSlotCamtelPre,
  kSlotCamtelPost,
];

/// Libellé lisible d'un code (interface admin et journaux).
String slotCodeLabel(String code) {
  switch (code) {
    case kSlotMtn:
      return 'MTN';
    case kSlotOrange:
      return 'Orange';
    case kSlotCamtelPre:
      return 'CAMTEL prépayé';
    case kSlotCamtelPost:
      return 'CAMTEL postpayé';
    default:
      return 'Emplacement libre';
  }
}

/// Opérateur (`mtn`, `orange`, `camtel`) d'un code d'emplacement.
String operatorOfCode(String code) {
  switch (code) {
    case kSlotMtn:
      return 'mtn';
    case kSlotOrange:
      return 'orange';
    case kSlotCamtelPre:
    case kSlotCamtelPost:
      return 'camtel';
    default:
      return '';
  }
}

/// Commandes USSD que cet emplacement est autorisé à exécuter.
List<String> handlesOfCode(String code) {
  switch (code) {
    case kSlotMtn:
      return const <String>[
        'mtn_airtime',
        'mtn_forfait',
        'mtn_forfait_activate'
      ];
    case kSlotOrange:
      return const <String>['orange_airtime', 'orange_forfait'];
    case kSlotCamtelPre:
      return const <String>['camtel_pre'];
    case kSlotCamtelPost:
      return const <String>['camtel_post'];
    default:
      return const <String>[];
  }
}

/// Retire les accents : « Prépayée » doit être reconnu comme « prepayee »,
/// sinon la suppression des caractères non alphanumériques le réduirait à
/// « prpaye » et l'emplacement serait déclaré libre par erreur.
String _sansAccents(String s) {
  const Map<String, String> table = <String, String>{
    'á': 'a',
    'à': 'a',
    'â': 'a',
    'ä': 'a',
    'ã': 'a',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'í': 'i',
    'ì': 'i',
    'î': 'i',
    'ï': 'i',
    'ó': 'o',
    'ò': 'o',
    'ô': 'o',
    'ö': 'o',
    'õ': 'o',
    'ú': 'u',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ç': 'c',
    'ñ': 'n',
  };
  final StringBuffer out = StringBuffer();
  for (final int unit in s.runes) {
    final String ch = String.fromCharCode(unit);
    out.write(table[ch] ?? ch);
  }
  return out.toString();
}

/// Normalise ce que l'admin a pu écrire (`MTN_CALLBOX`, `postpayée`, `Blue`…)
/// vers un code canonique. Une valeur inconnue devient [kSlotFree] : mieux vaut
/// un emplacement ignoré qu'un USSD envoyé sur la mauvaise carte.
String normalizeSlotCode(String? raw) {
  final String s = _sansAccents((raw ?? '').trim().toLowerCase())
      .replaceAll(RegExp(r'[\s\-/]+'), '_')
      .replaceAll(RegExp(r'[^a-z0-9_]'), '');
  if (s.isEmpty) return kSlotFree;

  if (s.contains('mtn')) return kSlotMtn;
  if (s.contains('orange')) return kSlotOrange;
  if (s.contains('camtel') ||
      s.contains('blue') ||
      s.contains('cdma') ||
      s.contains('prepay') ||
      s.contains('postpay') ||
      s == 'pre' ||
      s == 'post' ||
      s == 'prepayee' ||
      s == 'postpayee') {
    return s.contains('post') ? kSlotCamtelPost : kSlotCamtelPre;
  }
  return kSlotFree;
}

/// Un emplacement tel que l'admin l'a configuré.
@immutable
class SlotSpec {
  /// Index physique Android : 0 = SIM 1.
  final int slot;

  /// Voir [kSlotCodes]. Vide = emplacement libre.
  final String code;

  /// PIN de la carte, saisi par l'admin. Jamais journalisé ni affiché.
  final String pin;

  /// `false` : l'opérateur n'est pas servi par ce téléphone.
  final bool active;

  /// Seuil d'alerte de solde en FCFA (0 = seuil global).
  final int minBalance;

  /// Nom libre donné par l'admin (« MTN Callbox #1 »).
  final String label;

  const SlotSpec({
    required this.slot,
    this.code = kSlotFree,
    this.pin = '',
    this.active = true,
    this.minBalance = 0,
    this.label = '',
  });

  String get operator => operatorOfCode(code);

  bool get isFree => code.isEmpty;

  /// Carte réellement servie par ce téléphone (déclarée et active).
  bool get isPresent => !isFree && active;

  /// Carte utilisable pour une vente : active ET PIN enregistré.
  bool get hasPin => isPresent && pin.isNotEmpty;

  List<String> get handles => active ? handlesOfCode(code) : const <String>[];

  /// Lecture tolérante d'un élément de `servers/{id}.slots`.
  factory SlotSpec.fromMap(Map<dynamic, dynamic> m, {int fallbackSlot = 0}) {
    final int slot = (m['slot'] as num?)?.toInt() ?? fallbackSlot;
    // `operator` est accepté en plus de `code` : l'admin peut écrire l'un ou
    // l'autre depuis la console Firestore.
    final String raw =
        (m['code'] ?? m['operator'] ?? m['type'] ?? '').toString();
    return SlotSpec(
      slot: slot < 0 ? 0 : slot,
      code: normalizeSlotCode(raw),
      pin: m['pin']?.toString().trim() ?? '',
      active: m['active'] != false && m['actif'] != false,
      minBalance: (m['minBalance'] as num?)?.toInt() ??
          (m['min_balance'] as num?)?.toInt() ??
          0,
      label: m['label']?.toString() ?? '',
    );
  }

  /// Forme écrite en base par l'écran admin.
  Map<String, dynamic> toMap() => <String, dynamic>{
        'slot': slot,
        'code': code,
        'pin': pin,
        'active': active,
        'minBalance': minBalance,
        if (label.isNotEmpty) 'label': label,
      };

  SlotSpec copyWith({
    int? slot,
    String? code,
    String? pin,
    bool? active,
    int? minBalance,
    String? label,
  }) =>
      SlotSpec(
        slot: slot ?? this.slot,
        code: code ?? this.code,
        pin: pin ?? this.pin,
        active: active ?? this.active,
        minBalance: minBalance ?? this.minBalance,
        label: label ?? this.label,
      );

  @override
  String toString() =>
      'SIM ${slot + 1} → ${code.isEmpty ? 'libre' : slotCodeLabel(code)}'
      '${active ? '' : ' (désactivé)'}${pin.isEmpty ? '' : ' + PIN'}';
}

/// Vrai si l'admin a explicitement décrit les emplacements de ce téléphone.
///
/// Dans ce cas sa configuration fait autorité : la détection du matériel ne
/// sert plus qu'à afficher ce qui est physiquement présent, jamais à décider
/// du routage.
bool hasDynamicSlots(Map<String, dynamic> d) {
  final Object? raw = d['slots'];
  if (raw is! List || raw.isEmpty) return false;
  return raw.any((Object? e) => e is Map);
}

/// Lit `servers/{id}.slots`.
///
/// Retourne une liste vide quand l'admin n'a rien déclaré : l'appelant garde
/// alors l'ancien comportement (détection + `simMTN` / `simCamtelPre`…), pour
/// qu'un téléphone déjà en production continue de fonctionner sans migration.
///
/// Deux entrées sur le même emplacement : la dernière gagne (c'est celle que
/// l'admin vient d'écrire).
List<SlotSpec> slotSpecsFromDocument(Map<String, dynamic> d) {
  if (!hasDynamicSlots(d)) return const <SlotSpec>[];
  final Map<int, SlotSpec> bySlot = <int, SlotSpec>{};
  final List<Object?> raw = d['slots'] as List<Object?>;
  for (int i = 0; i < raw.length; i++) {
    final Object? item = raw[i];
    if (item is! Map) continue;
    final SlotSpec spec = SlotSpec.fromMap(item, fallbackSlot: i);
    bySlot[spec.slot] = spec;
  }
  final List<SlotSpec> out = bySlot.values.toList()
    ..sort((SlotSpec a, SlotSpec b) => a.slot.compareTo(b.slot));
  return out;
}

/// Emplacement servant un code donné, `null` si ce téléphone ne le sert pas.
SlotSpec? specForCode(List<SlotSpec> slots, String code) {
  if (code.isEmpty) return null;
  for (final SlotSpec s in slots) {
    if (s.code == code && s.active) return s;
  }
  return null;
}

/// Emplacement d'un opérateur, avec sa variante pour CAMTEL (`pre`/`post`).
SlotSpec? specForOperator(
  List<SlotSpec> slots,
  String operator, {
  String variant = '',
}) {
  final String code = operator == 'camtel'
      ? (variant == 'post' ? kSlotCamtelPost : kSlotCamtelPre)
      : normalizeSlotCode(operator);
  return specForCode(slots, code);
}

/// Union des commandes servies par les emplacements actifs.
///
/// C'est cette liste que l'écran admin écrit dans `handles`, pour que le
/// serveur n'accepte que les commandes qu'il peut réellement livrer.
List<String> handlesForSlots(List<SlotSpec> slots) {
  final List<String> out = <String>[];
  for (final SlotSpec s in slots) {
    for (final String h in s.handles) {
      if (!out.contains(h)) out.add(h);
    }
  }
  return out;
}

/// Seuil de solde par opérateur (`mtn`, `orange`, `camtel`).
///
/// Une valeur à 0 n'est pas reportée : l'appelant garde alors son seuil global.
Map<String, int> minBalanceByOperator(List<SlotSpec> slots) {
  final Map<String, int> out = <String, int>{};
  for (final SlotSpec s in slots) {
    if (!s.isPresent || s.minBalance <= 0) continue;
    final String op = s.operator;
    if (op.isEmpty) continue;
    // Deux cartes du même opérateur : on garde le seuil le plus haut, c'est
    // celui qui doit déclencher l'alerte le plus tôt.
    final int? known = out[op];
    if (known == null || s.minBalance > known) out[op] = s.minBalance;
  }
  return out;
}

// ─────────────────────────────────────────────────────────────────────────────
// [CONFIG SIM 29/10/2026] Configuration depuis l'app serveur elle-même.
//
// Constaté le 29/10 sur le Redmi M2003J15SC (2 SIM CAMTEL) : configurer les
// SIM à la main dans la console Firebase a pris une heure — type `int64`
// introuvable, `code` rempli avec le PIN, PIN oublié, `handles` oublié (le
// téléphone aurait alors pris TOUTES les commandes, MTN comprises). D'où :
//  - un écran dans l'app serveur (lib/view/config/sim_config_screen.dart)
//    qui écrit `slots` à partir de choix guidés, contrôlés ci-dessous ;
//  - `slots` fait désormais foi pour le routage : `handles` en est déduit,
//    il ne peut plus être oublié ni contredire les emplacements ;
//  - un téléphone sans AUCUNE configuration ne prend plus aucune commande.
// ─────────────────────────────────────────────────────────────────────────────

/// Marqueur de routage « aucune commande » : téléphone non configuré, ou
/// emplacements tous désactivés.
const String kNoHandles = 'none';

/// Anciens champs de configuration encore lus par compatibilité.
const List<String> kLegacySimKeys = <String>[
  'simMTN',
  'simCamtelPre',
  'simCamtelPost',
  'simOrange',
];

/// Vrai si le téléphone a reçu une configuration, quelle qu'en soit la forme.
bool isServerConfigured(Map<String, dynamic> d) {
  if (hasDynamicSlots(d)) return true;
  if (kLegacySimKeys.any((String k) => d[k] is Map)) return true;
  final Object? h = d['handles'];
  return h is List && h.any((Object? e) => '${e ?? ''}'.trim().isNotEmpty);
}

/// Commandes que ce téléphone doit écouter.
///
/// - `slots` déclarés : déduites des emplacements actifs (ils font foi) ;
/// - ancienne configuration : le champ `handles` tel quel (vide = tout) ;
/// - aucune configuration : [kNoHandles].
List<String> effectiveHandles(Map<String, dynamic> d) {
  if (hasDynamicSlots(d)) {
    final List<String> h = handlesForSlots(slotSpecsFromDocument(d));
    return h.isEmpty ? const <String>[kNoHandles] : h;
  }
  if (!isServerConfigured(d)) return const <String>[kNoHandles];
  final Object? raw = d['handles'];
  return raw is List
      ? raw
          .map((Object? e) => '${e ?? ''}'.trim().toLowerCase())
          .where((String e) => e.isNotEmpty)
          .toList()
      : const <String>[];
}

/// PIN accepté : 4 à 8 chiffres.
bool isValidPin(String pin) => RegExp(r'^\d{4,8}$').hasMatch(pin.trim());

/// Contrôle une configuration avant enregistrement.
///
/// [detected] : opérateur détecté par emplacement (`mtn`, `orange`, `camtel`,
/// `other`, ou absent). Rend la liste des problèmes, vide si tout est bon.
List<String> validateSlots(
  List<SlotSpec> slots, {
  Map<int, String> detected = const <int, String>{},
}) {
  final List<String> problems = <String>[];
  final Map<String, int> vus = <String, int>{};
  for (final SlotSpec s in slots) {
    if (!s.isPresent) continue;
    final String sim = 'SIM ${s.slot + 1}';
    if (s.pin.isEmpty) {
      problems
          .add('$sim : saisis le PIN de la carte ${slotCodeLabel(s.code)}.');
    } else if (!isValidPin(s.pin)) {
      problems.add('$sim : le PIN doit contenir 4 à 8 chiffres.');
    }
    final String det = (detected[s.slot] ?? '').toLowerCase();
    if (det.isEmpty) {
      problems.add('$sim : aucune carte détectée dans cet emplacement.');
    } else if (det != 'other' && det != s.operator) {
      problems.add('$sim : la carte détectée est ${_operateurLisible(det)}, '
          'pas ${slotCodeLabel(s.code)}.');
    }
    final int? autre = vus[s.code];
    if (autre != null) {
      problems.add('SIM ${autre + 1} et $sim servent toutes les deux '
          '${slotCodeLabel(s.code)} : choisis un rôle différent.');
    } else {
      vus[s.code] = s.slot;
    }
  }
  if (!slots.any((SlotSpec s) => s.isPresent)) {
    problems
        .add('Aucune SIM active : ce téléphone ne livrera aucune commande.');
  }
  return problems;
}

String _operateurLisible(String op) {
  switch (op) {
    case 'mtn':
      return 'MTN';
    case 'orange':
      return 'Orange';
    case 'camtel':
      return 'CAMTEL';
    default:
      return op;
  }
}

/// Rôles proposés pour une carte détectée : seuls ceux de son opérateur,
/// pour qu'un USSD ne puisse jamais partir sur la mauvaise carte.
List<String> codesForDetectedOperator(String detected) {
  switch (detected.toLowerCase()) {
    case 'mtn':
      return const <String>[kSlotMtn];
    case 'orange':
      return const <String>[kSlotOrange];
    case 'camtel':
      return const <String>[kSlotCamtelPre, kSlotCamtelPost];
    default:
      // Carte étrangère ou illisible : tout est proposé, l'admin tranche.
      return const <String>[
        kSlotMtn,
        kSlotOrange,
        kSlotCamtelPre,
        kSlotCamtelPost
      ];
  }
}
