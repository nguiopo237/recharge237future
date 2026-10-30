/// [FIDÉLITÉ 31/10/2026] Barème de points Recharge237 — calcul PUR, sans
/// Firestore, sans horloge, donc testable (`test/loyalty_rules_test.dart`).
///
/// PRINCIPE : le programme ne distribue jamais un pourcentage « choisi » du
/// chiffre d'affaires, il distribue une FRACTION de la marge réellement
/// configurée ([ReportConfig.commissions]). Si la commission MTN passe de 5 %
/// à 4 %, le budget de points baisse tout seul : impossible de se réveiller
/// avec un programme fidélité qui mange la marge parce qu'un barème écrit en
/// dur a été oublié.
///
/// La marge est d'abord MINORÉE d'une réserve de sécurité pour les charges et
/// les taxes ([LoyaltyConfig.reserveCharges], 20 % par défaut) : on ne
/// redistribue jamais sur de l'argent qui n'est pas encore du bénéfice net.
/// Sur ce net, on redistribue [LoyaltyConfig.partMarge] (25 %).
///
/// Exemple avec les taux réels (Camtel 8 %, MTN/Orange 5 %) :
///   Camtel : 8 % × 0,80 × 0,25 = 1,60 %  → 16 points par 1 000 F
///   MTN    : 5 % × 0,80 × 0,25 = 1,00 %  → 10 points par 1 000 F
///   Orange : idem MTN                    → 10 points par 1 000 F
/// Il reste donc au propriétaire 6,40 % sur Camtel et 3,80 % sur MTN/Orange,
/// même si TOUS les points distribués sont un jour consommés.
library;

import '../report/sales_report.dart'
    show kDeliveredStatuses, kNonBillableOperations;

/// Montant minimal d'une recharge qui rapporte des points.
///
/// Ce seuil ne demande AUCUNE règle spéciale dans le calcul : celui-ci compte
/// des tranches ENTIÈRES de 1 000 F (`999 ~/ 1000 == 0`). Le seuil est donc
/// exprimé ici pour la documentation et l'affichage, pas pour un `if`.
const int kMontantEligibleMin = 1000;

/// PLANCHER ABSOLU : le propriétaire conserve TOUJOURS au moins 40 % de sa
/// commission brute, même dans le pire scénario cumulé (parrainage compris).
///
/// C'est un VERROU ARITHMÉTIQUE, pas une intention : le barème ne peut pas
/// redistribuer plus que ce que cette règle autorise, quelle que soit la
/// configuration saisie dans `app_config/loyalty` (voir [tauxPour]). Tu peux
/// exiger PLUS que 40 % ([LoyaltyConfig.plancherRetenue]), jamais moins.
const double kPlancherRetenue = 40;

/// Pire multiplicateur d'une seule commande : le filleul parrainé voit ses
/// points doublés (×2) et le parrain reçoit les points du filleul (×1).
///
/// Le plafond de redistribution est divisé par ce facteur, sinon un parrainage
/// heureux pourrait à lui seul franchir le plancher des 40 %.
const int kFacteurParrainage = 3;

/// Opérations qui ne rapportent jamais de points : elles ne rapportent rien.
///
/// `mtn_forfait` est la simple CONSULTATION des offres Boost (gratuite) ;
/// elle est déjà exclue de la comptabilité par [kNonBillableOperations].
bool operateurEligible(String operateurCible) {
  final String op = operateurCible.trim().toLowerCase();
  if (op.isEmpty) return false;
  return !kNonBillableOperations.contains(op);
}

/// Réglages du programme, lus dans `app_config/loyalty`.
///
/// ```json
/// {
///   "actif": true,
///   "part_marge": 25,        // % du net redistribué en points
///   "reserve_charges": 20,   // % de la commission gardé pour charges/taxes
///   "validite_mois": 12      // durée de vie des points
/// }
/// ```
class LoyaltyConfig {
  final bool actif;

  /// Fraction de la marge NETTE redistribuée, en pourcentage (25 = 25 %).
  final double partMarge;

  /// Part de la commission mise en réserve pour charges et taxes, en
  /// pourcentage de la commission (20 = 20 %). Ce qui reste est considéré
  /// comme du bénéfice réellement disponible.
  final double reserveCharges;

  /// Durée de validité des points, en mois.
  final int validiteMois;

  /// Part MINIMALE de la commission brute que le propriétaire garde, en
  /// pourcentage de cette commission. Ne peut jamais descendre sous
  /// [kPlancherRetenue] : une valeur plus basse est ignorée.
  final double plancherRetenue;

  const LoyaltyConfig({
    this.actif = true,
    this.partMarge = 25,
    this.reserveCharges = 20,
    this.validiteMois = 12,
    this.plancherRetenue = kPlancherRetenue,
  });

  /// Plancher effectif : jamais moins de [kPlancherRetenue].
  double get plancherEffectif =>
      plancherRetenue < kPlancherRetenue ? kPlancherRetenue : plancherRetenue;

  factory LoyaltyConfig.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const LoyaltyConfig();
    double pct(Object? v, double defaut) {
      final double? d = v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
      if (d == null) return defaut;
      return d.clamp(0, 100).toDouble();
    }

    final int validite = (m['validite_mois'] as num?)?.toInt() ?? 12;
    return LoyaltyConfig(
      actif: m['actif'] != false,
      partMarge: pct(m['part_marge'], 25),
      reserveCharges: pct(m['reserve_charges'], 20),
      validiteMois: validite <= 0 ? 12 : validite,
      // Une valeur sous le plancher est REFUSÉE, pas silencieusement
      // appliquée : [plancherEffectif] la ramène à 40 %.
      plancherRetenue: pct(m['plancher_retenue'], kPlancherRetenue),
    );
  }
}

/// Taux de points retenu pour une opération, tous calculés en points de base
/// (1 bp = 0,01 %). Aucun flottant dans le calcul : `floor(1.6 * 10)` peut
/// valoir 15 en IEEE-754, et un point perdu par client est une réclamation
/// impossible à expliquer.
class LoyaltyRate {
  /// `operateur_cible` concerné (`mtn_airtime`, `camtel_pre`...).
  final String operateur;

  /// Commission configurée, en points de base (800 = 8 %).
  final int commissionBp;

  /// Commission après réserve de sécurité (640 = 6,40 %).
  final int netBp;

  /// Part du chiffre d'affaires redistribuée en points (160 = 1,60 %).
  final int remiseBp;

  /// Points gagnés par tranche complète de 1 000 F.
  final int pointsParTranche;

  /// Plancher de retenue appliqué, en points de base de la commission
  /// (4000 = 40 %).
  final int plancherBp;

  /// Vrai si le plafond a dû RÉDUIRE le barème demandé par la configuration.
  /// Autrement dit : sans ce plafond, la règle des 40 % aurait été violée.
  final bool plafonne;

  const LoyaltyRate({
    required this.operateur,
    required this.commissionBp,
    required this.netBp,
    required this.remiseBp,
    required this.pointsParTranche,
    required this.plancherBp,
    this.plafonne = false,
  });

  double get commissionPct => commissionBp / 100;
  double get remisePct => remiseBp / 100;

  /// Marge conservée par le propriétaire si TOUS les points gagnés sont
  /// dépensés (sans parrainage), en pourcentage de la commission brute.
  double get margeConserveePct => (commissionBp - remiseBp) / 100;

  /// Pire cas CUMULÉ : la même commande déclenche un parrainage récompensé
  /// (filleul doublé + parrain), soit [kFacteurParrainage] fois la remise.
  double get retenueWorstCasePct =>
      (commissionBp - remiseBp * kFacteurParrainage) / 100;

  /// Part de la commission brute qui reste au propriétaire dans ce pire cas,
  /// en pourcentage de la commission (doit toujours être ≥ 40).
  double get partRetenueWorstCasePct =>
      commissionBp == 0
          ? 100
          : (commissionBp - remiseBp * kFacteurParrainage) * 100 / commissionBp;

  /// Le verrou : vrai si la règle des 40 % tient dans le pire scénario.
  bool get plancherRespecte =>
      (commissionBp - remiseBp * kFacteurParrainage) * 10000 >=
      commissionBp * plancherBp;

  /// Vrai si ce taux distribue réellement quelque chose.
  bool get actif => pointsParTranche > 0;

  String get description =>
      '$pointsParTranche pts / $kMontantEligibleMin F '
      '(remise ${remisePct.toStringAsFixed(2)} %, '
      'retenu ${retenueWorstCasePct.toStringAsFixed(2)} % même avec '
      'parrainage = ${partRetenueWorstCasePct.toStringAsFixed(1)} % de la '
      'commission${plafonne ? ', PLAFONNÉ' : ''})';
}

/// Calcule le taux d'une opération.
///
/// Rend `null` quand rien ne peut être distribué — et c'est un choix : sans
/// commission configurée, on n'invente pas un taux (même philosophie que le
/// bilan comptable, qui écrit « commission non configurée » au lieu d'un
/// chiffre inventé).
LoyaltyRate? tauxPour({
  required String operateurCible,
  required Map<String, double> commissions,
  LoyaltyConfig config = const LoyaltyConfig(),
}) {
  final String op = operateurCible.trim().toLowerCase();
  if (!operateurEligible(op)) return null;

  final double? taux = commissions[op];
  if (taux == null || taux <= 0) return null;

  // Tout en points de base, arrondi au plus proche : 8.0 → 800, 4.5 → 450.
  final int commissionBp = (taux * 100).round();
  if (commissionBp <= 0) return null;

  // 1) Réserve de sécurité pour charges et taxes.
  final int reserveBp = (config.reserveCharges * 100).round();
  final int netBp = ((commissionBp * (10000 - reserveBp)) / 10000).round();

  // 2) Fraction de ce net redistribuée en points.
  final int partBp = (config.partMarge * 100).round();
  final int remiseDemandeeBp = ((netBp * partBp) / 10000).round();

  // 3) VERROU DES 40 % : plafond absolu de redistribution.
  //
  //    Le propriétaire doit garder au moins `plancher` de sa commission
  //    BRUTE, parrainage compris. Une commande peut distribuer jusqu'à
  //    kFacteurParrainage fois la remise normale (filleul doublé + parrain),
  //    d'où la division :
  //        remise ≤ commission × (1 − plancher) / kFacteurParrainage
  //
  //    Avec les taux réels et plancher 40 % :
  //        Camtel 8 %  → 8 × 0,60 / 3 = 1,60 %  = 16 pts / 1 000 F
  //        MTN/Orange 5 % → 5 × 0,60 / 3 = 1,00 % = 10 pts / 1 000 F
  //    C'est EXACTEMENT le barème retenu : il est donc au plafond, et si
  //    quelqu'un relève `part_marge` ou baisse `reserve_charges`, ce plafond
  //    ramène le barème à l'identique au lieu de grignoter la marge.
  final int plancherBp = (config.plancherEffectif * 100).round();
  final int remiseMaxBp =
      (commissionBp * (10000 - plancherBp)) ~/ (10000 * kFacteurParrainage);
  final bool plafonne = remiseDemandeeBp > remiseMaxBp;
  final int remiseBp =
      remiseDemandeeBp > remiseMaxBp ? remiseMaxBp : remiseDemandeeBp;

  // 4) Conversion en points par tranche de 1 000 F : une tranche de 1 000 F
  //    vaut remiseBp/10000 du montant, soit remiseBp/10 points.
  final int pointsParTranche = remiseBp ~/ 10;

  return LoyaltyRate(
    operateur: op,
    commissionBp: commissionBp,
    netBp: netBp,
    remiseBp: remiseBp,
    pointsParTranche: pointsParTranche,
    plancherBp: plancherBp,
    plafonne: plafonne,
  );
}

/// Points gagnés pour [montant] FCFA à ce taux : tranches ENTIÈRES de 1 000 F
/// seulement, donc jamais d'arrondi en faveur du client.
int pointsPour(int montant, LoyaltyRate rate) {
  if (montant < kMontantEligibleMin || rate.pointsParTranche <= 0) return 0;
  return (montant ~/ kMontantEligibleMin) * rate.pointsParTranche;
}

/// Montant lu comme partout ailleurs dans l'app : tantôt un nombre, tantôt
/// une chaîne (« 1 000 », « 1000 F »).
int? montantLisible(Object? raw) {
  if (raw is num) return raw.round();
  final String chiffres =
      (raw ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
  if (chiffres.isEmpty) return null;
  return int.tryParse(chiffres);
}

/// Résultat de l'examen d'une commande : combien de points, ou pourquoi rien.
///
/// Le [motif] d'un refus n'est pas décoratif : c'est ce qui permet de répondre
/// « pourquoi ce client n'a pas eu ses points ? » sans relire le code. Il
/// n'est jamais écrit dans le journal du client (qui ne contient que des
/// mouvements réels), seulement tracé en console.
class DecisionCredit {
  final int points;
  final String motif;

  /// Taux appliqué, quand un crédit a lieu (null sinon).
  final LoyaltyRate? taux;

  const DecisionCredit(this.points, this.motif, [this.taux]);

  bool get crediter => points > 0;
}

/// Décide si une commande doit rapporter des points — FONCTION PURE, donc
/// testable sans Firestore (`test/loyalty_rules_test.dart`).
///
/// C'est le seul endroit où l'on décide de distribuer de l'argent : chaque
/// refus y est explicite, dans un ordre qui va du moins coûteux au plus
/// coûteux (aucune lecture supplémentaire n'est faite ici).
DecisionCredit decisionCredit({
  required Map<String, dynamic> commande,
  required Map<String, double> commissions,
  LoyaltyConfig config = const LoyaltyConfig(),
}) {
  if (!config.actif) return const DecisionCredit(0, 'programme inactif');
  if (commande['loyalty'] != null) {
    return const DecisionCredit(0, 'déjà créditée');
  }

  // [CONVERSION 31/10/2026] Une recharge payée EN POINTS n'est pas une vente :
  // la créditer rembourserait une partie de ce que le programme vient de
  // distribuer, et gonflerait artificiellement le volume pris en compte pour
  // calculer la marge. Le client la voit dans son historique, mais elle ne
  // rapporte rien — ni à lui, ni à son parrain.
  if ((commande['paiement'] ?? '').toString().trim() == 'points') {
    return const DecisionCredit(0, 'payée en points');
  }

  final String operateur =
      (commande['operateur_cible'] ?? '').toString().trim().toLowerCase();
  if (!operateurEligible(operateur)) {
    return const DecisionCredit(0, 'opération non éligible');
  }

  final String statut = (commande['status'] ?? '').toString().trim();
  final Set<String>? livres = kDeliveredStatuses[operateur];
  if (livres == null || !livres.contains(statut)) {
    return DecisionCredit(0, 'pas livrée (statut $statut)');
  }

  final String uid = (commande['idphone'] ?? '').toString().trim();
  if (uid.isEmpty) return const DecisionCredit(0, 'acheteur inconnu');

  final int? montant = montantLisible(commande['amount']);
  if (montant == null) return const DecisionCredit(0, 'montant illisible');
  if (montant < kMontantEligibleMin) {
    return const DecisionCredit(
        0, 'sous le seuil de $kMontantEligibleMin F');
  }

  final LoyaltyRate? rate = tauxPour(
    operateurCible: operateur,
    commissions: commissions,
    config: config,
  );
  if (rate == null) return const DecisionCredit(0, 'commission non configurée');
  if (!rate.actif) return const DecisionCredit(0, 'taux trop faible');

  final int points = pointsPour(montant, rate);
  if (points <= 0) return const DecisionCredit(0, 'aucun point');

  return DecisionCredit(points, '', rate);
}

/// Répartition d'un parrainage récompensé (lot 2), calculée avec le MÊME
/// taux plafonné : le total ne peut donc jamais dépasser ce que la règle des
/// 40 % autorise.
class PointsParrainage {
  /// Points du filleul : ses points doublés (×[kFacteurParrainage] − 1).
  final int filleul;

  /// Points du parrain : les points normaux du filleul (×1).
  final int parrain;

  const PointsParrainage({required this.filleul, required this.parrain});

  int get total => filleul + parrain;
}

PointsParrainage pointsParrainagePour(int montant, LoyaltyRate rate) {
  final int base = pointsPour(montant, rate);
  return PointsParrainage(
    filleul: base * (kFacteurParrainage - 1),
    parrain: base,
  );
}

/// Contrôle de la règle des 40 % sur TOUS les opérateurs configurés.
///
/// Rend la liste des violations (vide = tout va bien). Utilisé au démarrage
/// de l'app serveur et dans les tests : si un jour un taux mal saisi faisait
/// passer la marge sous le plancher, l'admin le voit dans les journaux au lieu
/// de le découvrir sur ses bénéfices.
List<String> verifierPlancher({
  required Map<String, double> commissions,
  LoyaltyConfig config = const LoyaltyConfig(),
}) {
  final List<String> violations = <String>[];
  for (final LoyaltyRate r in tousLesTaux(
    commissions: commissions,
    config: config,
  ).values) {
    if (!r.plancherRespecte) {
      violations.add(
        '${r.operateur} : ${r.partRetenueWorstCasePct.toStringAsFixed(1)} % '
        'retenus, sous le plancher de ${config.plancherEffectif.toStringAsFixed(0)} %',
      );
    }
  }
  return violations;
}

/// Tous les taux actifs, pour l'affichage (application et bilan Telegram).
Map<String, LoyaltyRate> tousLesTaux({
  required Map<String, double> commissions,
  LoyaltyConfig config = const LoyaltyConfig(),
}) {
  final Map<String, LoyaltyRate> out = <String, LoyaltyRate>{};
  for (final String op in commissions.keys) {
    final LoyaltyRate? r =
        tauxPour(operateurCible: op, commissions: commissions, config: config);
    if (r != null && r.actif) out[op] = r;
  }
  return out;
}
