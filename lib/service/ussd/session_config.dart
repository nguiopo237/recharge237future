import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../server/slot_config.dart';

/// Configuration d'une SIM / d'un opérateur pour ce téléphone.
/// Chargée depuis `servers/{deviceId}` dans Firestore.
///
/// Le téléphone publie lui-même son matériel dans `sims` (voir ServerManager) :
///
/// ```json
/// {
///   "sims": [
///     { "slot": 0, "operator": "mtn",    "carrier": "MTN",    "number": "6xx" },
///     { "slot": 1, "operator": "camtel", "carrier": "CAMTEL", "number": "2xx" }
///   ],
///   "simMTN":       { "pin": "1234" },
///   "simCamtelPre": { "pin": "5678" },
///   "simCamtelPost":{ "pin": "5678" }
/// }
/// ```
///
/// Les EMPLACEMENTS viennent donc de la détection : l'admin n'a que les PIN à
/// renseigner. Il peut malgré tout forcer un emplacement en écrivant `slot`
/// dans `simMTN` / `simCamtelPre` / `simCamtelPost` : cette valeur est
/// prioritaire sur la détection.
///
/// Plusieurs SIM CAMTEL : celle du plus petit emplacement est la prépayée, la
/// suivante la postpayée (même règle que le script d'autorisation).
class SimConfig {
  final int slot;
  final String pin;

  const SimConfig({required this.slot, this.pin = ''});

  /// Vrai si cette SIM peut réellement servir : un PIN est enregistré.
  bool get isConfigured => pin.isNotEmpty;

  factory SimConfig.fromMap(Map<String, dynamic> m) => SimConfig(
        slot: (m['slot'] as num?)?.toInt() ?? 0,
        pin: m['pin']?.toString() ?? '',
      );
}

class SessionConfig {
  final SimConfig mtn;
  final SimConfig orange;
  final SimConfig camtelPre;
  final SimConfig camtelPost;

  /// [MTN 27/10/2026] `true` seulement si un PIN MTN est enregistré ET qu'une
  /// SIM MTN est réellement présente dans ce téléphone (détectée, ou
  /// emplacement forcé par l'admin). Sans cela, le serveur ignore toutes les
  /// commandes MTN (crédit, Good Deal) au lieu de lancer un USSD MTN sur une
  /// SIM CAMTEL : il les laisse à un autre téléphone équipé.
  final bool mtnConfigured;

  /// [BOOST 28/10/2026] Vrai si une carte MTN est RÉELLEMENT présente dans ce
  /// téléphone, même sans PIN enregistré.
  ///
  /// La requête de la liste Boost/Good Deal est GRATUITE : elle ne saisit
  /// aucun code secret. Exiger un PIN pour l'exécuter empêchait de tester le
  /// menu sur un téléphone fraîchement installé, pour aucune raison de
  /// sécurité. Les ventes de crédit, elles, exigent toujours le PIN.
  final bool mtnSimPresent;

  /// Vrai si ce téléphone possède réellement une SIM CAMTEL (détectée, ou
  /// déclarée explicitement par l'admin dans `simCamtelPre`).
  ///
  /// Sans cette garde, un téléphone équipé d'une seule SIM MTN prendrait les
  /// commandes CAMTEL, composerait `*550*` sur une SIM MTN et les ferait
  /// échouer en statut 4, alors qu'un autre téléphone aurait pu les livrer.
  final bool camtelConfigured;

  /// [EMPLACEMENTS 28/10/2026] Vrai quand le routage vient de la
  /// configuration `slots` écrite par l'admin, et non plus de la détection.
  /// Dans ce cas, ce que l'admin a déclaré fait foi : un emplacement qu'il n'a
  /// pas attribué n'est pas utilisé, même si une carte y est physiquement
  /// présente.
  final bool slotsDeclared;

  /// Vrai si ce téléphone possède réellement une SIM Orange (détectée, ou
  /// déclarée dans `simOrange`).
  ///
  /// [ORANGE 28/10/2026] La garde est en place, mais aucune livraison Orange
  /// n'est encore branchée : ce booléen servira au jour où le flux USSD sera
  /// disponible, et il permet déjà au contrôle admin de dire si la carte est
  /// là ou non.
  final bool orangeConfigured;

  const SessionConfig({
    required this.mtn,
    required this.orange,
    required this.camtelPre,
    required this.camtelPost,
    this.mtnConfigured = false,
    this.mtnSimPresent = false,
    this.camtelConfigured = false,
    this.orangeConfigured = false,
    this.slotsDeclared = false,
  });

  /// Résumé lisible des cartes servies par ce téléphone (journaux, écran).
  @override
  String toString() {
    final List<String> parts = <String>[];
    if (mtnSimPresent) {
      parts.add(
          'MTN SIM ${mtn.slot + 1}${mtnConfigured ? ' + PIN' : ' sans PIN'}');
    }
    if (camtelConfigured) {
      parts.add('CAMTEL SIM ${camtelPre.slot + 1}');
    }
    if (orangeConfigured) {
      parts.add('Orange SIM ${orange.slot + 1}'
          '${orange.isConfigured ? ' + PIN' : ' sans PIN'}');
    }
    return '${slotsDeclared ? 'emplacements admin — ' : 'détection — '}'
        '${parts.isEmpty ? 'aucune carte servie' : parts.join(' · ')}';
  }

  /// Construit la config à partir du document `servers/{deviceId}`.
  /// Fonction pure : testable sans Firestore.
  factory SessionConfig.fromDocument(Map<String, dynamic> d) {
    // 0. [EMPLACEMENTS 28/10/2026] Configuration écrite par l'admin : elle
    // fait autorité. Aucune déduction, aucune permutation de puces ne peut
    // plus envoyer une commande sur la mauvaise carte.
    final List<SlotSpec> declared = slotSpecsFromDocument(d);
    if (declared.isNotEmpty) {
      final SlotSpec? mtn = specForCode(declared, kSlotMtn);
      final SlotSpec? orange = specForCode(declared, kSlotOrange);
      final SlotSpec? pre = specForCode(declared, kSlotCamtelPre);
      final SlotSpec? post = specForCode(declared, kSlotCamtelPost);
      return SessionConfig(
        mtn: SimConfig(slot: mtn?.slot ?? 0, pin: mtn?.pin ?? ''),
        orange: SimConfig(slot: orange?.slot ?? 1, pin: orange?.pin ?? ''),
        camtelPre:
            SimConfig(slot: pre?.slot ?? post?.slot ?? 0, pin: pre?.pin ?? ''),
        camtelPost:
            SimConfig(slot: post?.slot ?? pre?.slot ?? 1, pin: post?.pin ?? ''),
        mtnConfigured: mtn?.hasPin ?? false,
        mtnSimPresent: mtn?.isPresent ?? false,
        camtelConfigured:
            (pre?.isPresent ?? false) || (post?.isPresent ?? false),
        orangeConfigured: orange?.isPresent ?? false,
        slotsDeclared: true,
      );
    }

    // 1. Emplacements détectés, groupés par opérateur puis triés.
    final detected = <String, List<int>>{};
    final rawSims = d['sims'];
    if (rawSims is List) {
      for (final item in rawSims) {
        if (item is! Map) continue;
        final op = (item['operator'] ?? '').toString().toLowerCase();
        final slot = (item['slot'] as num?)?.toInt();
        if (op.isEmpty || slot == null) continue;
        detected.putIfAbsent(op, () => <int>[]).add(slot);
      }
    }
    for (final slots in detected.values) {
      slots.sort();
    }
    int? firstSlotOf(String op) {
      final slots = detected[op];
      return (slots != null && slots.isNotEmpty) ? slots.first : null;
    }

    // 2. Chaque opérateur : emplacement forcé par l'admin > détection > défaut.
    SimConfig parse(String key, {required int defaultSlot, int? detectedSlot}) {
      final raw = d[key];
      if (raw is Map) {
        final forced = (raw['slot'] as num?)?.toInt();
        return SimConfig(
          slot: forced ?? detectedSlot ?? defaultSlot,
          pin: raw['pin']?.toString() ?? '',
        );
      }
      return SimConfig(slot: detectedSlot ?? defaultSlot);
    }

    final List<int> camtelSlots = detected['camtel'] ?? const <int>[];
    final camtelPreSlot = camtelSlots.isNotEmpty ? camtelSlots.first : null;
    final camtelPostSlot =
        camtelSlots.length > 1 ? camtelSlots[1] : camtelPreSlot;

    final mtn = parse('simMTN',
        defaultSlot: firstSlotOf('mtn') ?? 0, detectedSlot: firstSlotOf('mtn'));

    final rawMtn = d['simMTN'];
    final bool mtnSlotKnown =
        firstSlotOf('mtn') != null || (rawMtn is Map && rawMtn['slot'] != null);

    // CAMTEL : soit une carte détectée, soit une déclaration explicite de
    // l'admin (ancien script). Un téléphone MTN seul n'a ni l'un ni l'autre.
    final bool camtelSlotKnown =
        camtelSlots.isNotEmpty || d['simCamtelPre'] is Map;

    // Même règle pour Orange : carte vue par la détection, ou déclarée.
    final bool orangeSlotKnown =
        firstSlotOf('orange') != null || d['simOrange'] is Map;

    return SessionConfig(
      mtn: mtn,
      orange: parse('simOrange',
          defaultSlot: firstSlotOf('orange') ?? 1,
          detectedSlot: firstSlotOf('orange')),
      camtelPre: parse('simCamtelPre',
          defaultSlot: camtelPreSlot ?? 0, detectedSlot: camtelPreSlot),
      camtelPost: parse('simCamtelPost',
          defaultSlot: camtelPostSlot ?? 1, detectedSlot: camtelPostSlot),
      mtnConfigured: mtn.isConfigured && mtnSlotKnown,
      mtnSimPresent: mtnSlotKnown,
      camtelConfigured: camtelSlotKnown,
      orangeConfigured: orangeSlotKnown,
    );
  }

  /// Charge la config depuis Firestore. Utilise des valeurs par défaut
  /// si le document n'existe pas encore.
  static Future<SessionConfig> load(String deviceId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('servers')
          .doc(deviceId)
          .get();
      return SessionConfig.fromDocument(doc.data() ?? const {});
    } catch (e) {
      debugPrint('[SessionConfig] Erreur chargement config : $e');
      return const SessionConfig(
        mtn: SimConfig(slot: 0),
        orange: SimConfig(slot: 1),
        camtelPre: SimConfig(slot: 0),
        camtelPost: SimConfig(slot: 1),
      );
    }
  }
}
