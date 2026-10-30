/// [FIDÉLITÉ 31/10/2026] LOT 3 — conversion des points en recharge.
///
/// POURQUOI DES PALIERS DE 1 000 F : c'est la granularité sur laquelle la
/// marge a été calculée. Un point vaut 1 F (cf. `LoyaltyWallet`), et 1 000 F
/// de recharge coûte au plus 1 000 F × (1 − commission). En convertissant par
/// tranches entières, on ne crée jamais de « monnaie » plus fine que ce que le
/// programme a provisionné — et un montant libre (1 137 F, par exemple)
/// reviendrait à rembourser plus que ce qui a été mis de côté pour ce client.
///
/// LE POINT CRITIQUE : convertir ne doit pas pouvoir dépasser le solde, ni
/// relancer plusieurs conversions le même jour sur un compte compromis. Ces
/// deux contrôles sont ici, purs, et testés — pas au fond d'une transaction.
library;

/// Pas de conversion : 1 000 F. Non configurable en dessous.
const int kPalierRedemption = 1000;

/// Réglages, lus dans `app_config/loyalty` (le même document que le barème).
///
/// ```json
/// {
///   "conversion_active": true,
///   "conversion_plafond": 5000,   // max par opération
///   "conversion_max_jour": 2      // max de conversions servies par jour
/// }
/// ```
class RedemptionConfig {
  /// Coupe la conversion sans arrêter le gain de points.
  final bool actif;

  /// Montant maximal convertible en une fois. Borne le risque : un compte
  /// compromis ne vide pas un solde de 20 000 points d'un coup.
  final int plafondParOperation;

  /// Conversions servies par jour et par client.
  final int maxParJour;

  const RedemptionConfig({
    this.actif = true,
    this.plafondParOperation = 5000,
    this.maxParJour = 2,
  });

  factory RedemptionConfig.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const RedemptionConfig();
    int entier(Object? v, int defaut) {
      if (v is num) return v.toInt();
      return int.tryParse('${v ?? ''}') ?? defaut;
    }

    final int plafond = entier(m['conversion_plafond'], 5000);
    final int jour = entier(m['conversion_max_jour'], 2);
    return RedemptionConfig(
      actif: m['conversion_active'] != false,
      // Un plafond nul ou négatif rendrait la fonctionnalité inutilisable :
      // on retombe sur la valeur par défaut plutôt que d'accepter un réglage
      // qui a l'air actif mais ne sert à rien.
      plafondParOperation: plafond < kPalierRedemption ? 5000 : plafond,
      maxParJour: jour < 0 ? 2 : jour,
    );
  }
}

/// Verdict d'une demande de conversion.
class DecisionRedemption {
  /// Points à débiter (1 point = 1 F, donc aussi le montant rechargé).
  final int points;

  /// Raison du refus, vide si la conversion est acceptée.
  final String motif;

  const DecisionRedemption(this.points, this.motif);

  bool get valide => points > 0;
}

/// Décide si [montant] points peuvent être convertis — FONCTION PURE.
///
/// L'ordre des refus va du plus évident au plus coûteux à expliquer : le
/// client lit « il vous manque des points » avant « plafond du jour atteint »,
/// comme dans [decisionCredit] et [decisionParrainage].
DecisionRedemption decisionRedemption({
  required Object? montant,
  required int solde,
  int conversionsAujourdhui = 0,
  RedemptionConfig config = const RedemptionConfig(),
}) {
  if (!config.actif) {
    return const DecisionRedemption(0, 'conversion désactivée');
  }

  final int? demande = _entier(montant);
  if (demande == null) {
    return const DecisionRedemption(0, 'montant illisible');
  }
  if (demande < kPalierRedemption) {
    return const DecisionRedemption(
        0, 'sous le palier de $kPalierRedemption F');
  }
  if (demande % kPalierRedemption != 0) {
    return const DecisionRedemption(
        0, 'montant hors palier (multiples de $kPalierRedemption F)');
  }
  if (demande > config.plafondParOperation) {
    return DecisionRedemption(
        0, 'au-delà du plafond par opération '
            '(${config.plafondParOperation} F)');
  }
  if (config.maxParJour > 0 && conversionsAujourdhui >= config.maxParJour) {
    return const DecisionRedemption(0, 'plafond quotidien atteint');
  }
  if (demande > solde) {
    return const DecisionRedemption(0, 'points insuffisants');
  }

  return DecisionRedemption(demande, '');
}

/// Montant lu comme partout ailleurs dans l'app (nombre ou texte « 2 000 »).
int? _entier(Object? raw) {
  if (raw is num) return raw.round();
  final String chiffres =
      (raw ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
  if (chiffres.isEmpty) return null;
  return int.tryParse(chiffres);
}
