import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Une SIM détectée matériellement dans le téléphone.
///
/// [operator] est normalisé ('camtel', 'mtn', 'orange', 'other') pour que le
/// reste du code n'ait jamais à interpréter un nom commercial : Camtel se
/// présente aussi comme « Blue » ou « Bell » selon la SIM et le réseau.
class DetectedSim {
  /// Emplacement physique de la carte (0 = SIM 1).
  final int slot;

  /// Nom porté par la SIM (ex. « MTN », « CAMTEL », « Blue », « Orange »).
  final String carrier;

  /// MCC/MNC renvoyé par la carte (ex. « 62401 »), vide si indisponible.
  final String mccMnc;

  /// Numéro de la SIM, souvent vide (l'opérateur ne l'expose pas toujours).
  final String number;

  /// Opérateur normalisé : camtel | mtn | orange | other.
  final String operator;

  const DetectedSim({
    required this.slot,
    required this.carrier,
    required this.mccMnc,
    required this.number,
    required this.operator,
  });

  Map<String, dynamic> toMap() => {
        'slot': slot,
        'operator': operator,
        'carrier': carrier,
        'mccMnc': mccMnc,
        'number': number,
      };

  @override
  String toString() => 'SIM $slot $operator ($carrier)';
}

/// Inventaire matériel du téléphone, publié dans `servers/{deviceId}`.
class DetectedHardware {
  final String model;
  final String manufacturer;
  final int sdk;
  final List<DetectedSim> sims;

  const DetectedHardware({
    required this.model,
    required this.manufacturer,
    required this.sdk,
    required this.sims,
  });

  List<DetectedSim> simsOf(String operator) =>
      sims.where((s) => s.operator == operator).toList();

  Map<String, dynamic> toMap() => {
        'model': model,
        'manufacturer': manufacturer,
        'sdk': sdk,
        'sims': sims.map((s) => s.toMap()).toList(),
      };
}

/// Lit le matériel du téléphone via le canal natif `r237/ussd` (méthode `sims`).
class SimProbe {
  SimProbe._();

  static const MethodChannel _channel = MethodChannel('r237/ussd');

  /// MCC/MNC des opérateurs camerounais (secours quand le nom de la SIM est
  /// inexploitable). 62401 = MTN, 62402 = Orange, 62403 et 62405 = CAMTEL.
  static const Map<String, String> _operatorByMnc = {
    '62401': 'mtn',
    '62402': 'orange',
    '62403': 'camtel',
    // [29/10/2026] CAMTEL 4G (Blue) : constaté sur les 2 SIM CAMTEL du
    // Redmi M2003J15SC, rejetées à tort comme « autre opérateur ».
    '62405': 'camtel',
  };

  /// Normalise un opérateur : marque écrite sur la carte, puis MCC/MNC.
  ///
  /// [ITINERANCE 28/10/2026] « Bell » n'est PAS une marque camerounaise :
  /// c'est le nom du réseau VISITÉ. Constaté sur le téléphone serveur : une
  /// carte MTN Cameroun, en itinérance au Canada, s'annonçait « Bell » et
  /// était classée CAMTEL — donc ce téléphone croyait avoir une SIM CAMTEL
  /// et prenait des commandes qu'il ne pouvait pas livrer. On ne se fie donc
  /// jamais au nom du réseau visité : à défaut de marque connue, c'est le
  /// code réseau d'origine de la CARTE (`simOperator`) qui tranche.
  static String operatorOf({required String carrier, String mccMnc = ''}) {
    final String c = carrier.toLowerCase();
    // 1. Marque écrite sur la carte : la plus fiable quand elle est lisible.
    if (c.contains('mtn')) return 'mtn';
    if (c.contains('orange')) return 'orange';
    if (c.contains('camtel') || c.contains('blue')) return 'camtel';
    // 2. Réseau d'origine de la carte (62401 MTN, 62402 Orange, 62403 CAMTEL),
    //    qui reste juste même en itinérance.
    final String mnc = mccMnc.trim();
    if (mnc.isNotEmpty) {
      for (final MapEntry<String, String> e in _operatorByMnc.entries) {
        if (mnc.startsWith(e.key)) return e.value;
      }
    }
    return 'other';
  }

  /// Lit le matériel ; renvoie `null` si le canal natif échoue (on ne publie
  /// alors rien, pour ne pas écraser une détection précédente avec du vide).
  static Future<DetectedHardware?> detect() async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>('sims');
      if (raw == null) return null;

      final sims = <DetectedSim>[];
      final list = raw['sims'];
      if (list is List) {
        for (final item in list) {
          if (item is! Map) continue;
          final carrier = (item['carrier'] ?? '').toString();
          final mccMnc = (item['mccMnc'] ?? '').toString();
          sims.add(DetectedSim(
            slot: (item['slot'] as num?)?.toInt() ?? 0,
            carrier: carrier,
            mccMnc: mccMnc,
            number: (item['number'] ?? '').toString(),
            operator: operatorOf(carrier: carrier, mccMnc: mccMnc),
          ));
        }
      }
      sims.sort((a, b) => a.slot.compareTo(b.slot));

      return DetectedHardware(
        model: (raw['model'] ?? '').toString(),
        manufacturer: (raw['manufacturer'] ?? '').toString(),
        sdk: (raw['sdk'] as num?)?.toInt() ?? 0,
        sims: sims,
      );
    } catch (e) {
      debugPrint('[SimProbe] Détection impossible : $e');
      return null;
    }
  }
}
