/// [PARRAINAGE 31/10/2026] LOT 2 — règles PURES du parrainage payant.
///
/// Aucun Firestore, aucune horloge : tout est décidé ici, et le service ne
/// fait plus qu'exécuter le verdict dans une transaction. C'est ce qui rend
/// les barrières anti-abus vérifiables par des tests plutôt que par la
/// lecture attentive d'un `if` perdu au milieu d'une écriture.
///
/// CE QUI EST PAYÉ (et pourquoi le total tient dans les 40 %) :
///   - le filleul voit son PREMIER achat éligible doublé  → 2 × base
///   - le parrain reçoit une fois la base de ce même achat → 1 × base
///   - total distribué sur la commande : 3 × base.
/// C'est exactement [kFacteurParrainage] : le plafond de `loyalty_rules.dart`
/// divise la remise par ce facteur, donc 3 × base ne peut jamais dépasser la
/// marge autorisée. On refait quand même le contrôle ici ([LoyaltyRate
/// .plancherRespecte]) : deux verrous valent mieux qu'un commentaire.
library;

import 'loyalty_rules.dart';

/// Réglages du parrainage, lus dans `app_config/referral`.
///
/// ```json
/// {
///   "actif": true,
///   "max_par_jour": 5,        // parrainages RÉCOMPENSÉS par parrain et par jour
///   "bonus_filleul": true,    // doubler aussi le premier achat du filleul
///   "max_par_compte": 0       // 0 = pas de plafond de vie
/// }
/// ```
class ReferralConfig {
  /// Coupe le parrainage sans toucher au programme de fidélité.
  final bool actif;

  /// Nombre de parrainages récompensés par parrain et par jour. Le plafond
  /// anti-script : un compte neuf qui parraine 100 faux comptes le même jour
  /// ne touche que cinq récompenses.
  final int maxParJour;

  /// Doubler le premier achat du filleul. Désactivable seul : le parrain peut
  /// continuer à gagner sans que le budget double côté filleul.
  final bool bonusFilleul;

  /// Plafond de récompenses sur la vie du compte (0 = illimité). Utile si un
  /// parrain devient trop dispendieux sans avoir à couper le programme.
  final int maxParCompte;

  const ReferralConfig({
    this.actif = true,
    this.maxParJour = 5,
    this.bonusFilleul = true,
    this.maxParCompte = 0,
  });

  factory ReferralConfig.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const ReferralConfig();
    int entier(Object? v, int defaut) {
      if (v is num) return v.toInt();
      return int.tryParse('${v ?? ''}') ?? defaut;
    }

    final int maxJour = entier(m['max_par_jour'], 5);
    final int maxCompte = entier(m['max_par_compte'], 0);
    return ReferralConfig(
      actif: m['actif'] != false,
      // Un plafond négatif n'a pas de sens : on retombe sur 5.
      maxParJour: maxJour < 0 ? 5 : maxJour,
      bonusFilleul: m['bonus_filleul'] != false,
      maxParCompte: maxCompte < 0 ? 0 : maxCompte,
    );
  }
}

/// Tout ce que la décision a besoin de savoir, déjà rassemblé par le service
/// (une lecture par document, aucune requête : le total reste dans les
/// quotas du plan gratuit).
class ContexteParrainage {
  final String filleulUid;
  final String parrainUid;

  /// Numéros déclarés sur les deux profils (facultatifs : beaucoup de clients
  /// restent anonymes, on ne bloque alors que sur ce qui est connu).
  final String? telephoneFilleul;
  final String? telephoneParrain;

  /// Empreinte matérielle (deviceSerial) quand elle existe.
  final String? appareilFilleul;
  final String? appareilParrain;

  /// Vrai si ce filleul a DÉJÀ été récompensé (marqueur `rewarded`).
  final bool dejaRecompense;

  /// Vrai si la commande en cours est le tout premier achat éligible du
  /// filleul (`commandesEligibles == 0` avant crédit).
  final bool premierAchatEligible;

  /// Récompenses déjà servies au parrain aujourd'hui (compteur du jour).
  final int recompensesParrainAujourdhui;

  /// Récompenses déjà servies au parrain depuis toujours (compteur de vie).
  final int recompensesParrainTotal;

  /// Vrai si le parrain est lui-même filleul DU filleul (échange croisé de
  /// codes entre deux comptes complices : on refuse la boucle).
  final bool parrainEstFilleulDuFilleul;

  /// [IDENTITÉ 31/10/2026] Profil du filleul complet (nom, téléphone
  /// camerounais, email — voir `identity_rules.dart`).
  ///
  /// Défaut `false` VOLONTAIREMENT : si un jour le service oublie de
  /// transmettre l'information, on ne paie pas. Un bonus versé à un profil
  /// anonyme est irrécupérable ; un bonus non versé est rattrapable.
  final bool identiteFilleulComplete;

  /// Idem pour le parrain : un parrain anonyme ne peut pas être payé.
  final bool identiteParrainComplete;

  const ContexteParrainage({
    required this.filleulUid,
    required this.parrainUid,
    this.telephoneFilleul,
    this.telephoneParrain,
    this.appareilFilleul,
    this.appareilParrain,
    this.dejaRecompense = false,
    this.premierAchatEligible = false,
    this.recompensesParrainAujourdhui = 0,
    this.recompensesParrainTotal = 0,
    this.parrainEstFilleulDuFilleul = false,
    this.identiteFilleulComplete = false,
    this.identiteParrainComplete = false,
  });
}

/// Verdict : combien de points à qui, ou pourquoi rien.
class DecisionParrainage {
  /// Points supplémentaires pour le filleul (en plus du crédit normal).
  final int pointsFilleulExtra;

  /// Points pour le parrain.
  final int pointsParrain;

  /// Raison du refus, vide quand la récompense est accordée. Jamais montrée
  /// au client : seulement tracée en console/Telegram pour répondre à
  /// « pourquoi ce parrain n'a rien touché ? ».
  final String motif;

  const DecisionParrainage({
    this.pointsFilleulExtra = 0,
    this.pointsParrain = 0,
    this.motif = '',
  });

  bool get recompenser => pointsParrain > 0 || pointsFilleulExtra > 0;

  int get total => pointsFilleulExtra + pointsParrain;
}

/// Normalise un numéro camerounais pour comparaison : chiffres seulement,
/// préfixe 237 retiré, 9 derniers chiffres. `+237 6 74 58 35 31`,
/// `00237674583531` et `674583531` doivent désigner le MÊME numéro, sinon la
/// barrière « même téléphone » se contourne en changeant le format.
String? numeroComparable(String? brut) {
  final String chiffres = (brut ?? '').replaceAll(RegExp(r'[^0-9]'), '');
  if (chiffres.isEmpty) return null;
  if (chiffres.length <= 9) return chiffres;
  return chiffres.substring(chiffres.length - 9);
}

/// Normalise une empreinte d'appareil. Vide = inconnu, donc inutilisable
/// comme preuve : on ne refuse jamais sur une absence.
String? appareilComparable(String? brut) {
  final String v = (brut ?? '').trim().toLowerCase();
  if (v.isEmpty || v == 'unknown' || v == 'null') return null;
  return v;
}

/// Le seul endroit où l'on décide de payer un parrainage.
///
/// ORDRE DES REFUS : du gratuit au coûteux, comme [decisionCredit]. Tous les
/// contrôles sont déjà en mémoire, donc leur ordre ne change rien au coût ;
/// il change seulement le motif affiché, et on préfère le plus parlant
/// (auto-parrainage avant « déjà récompensé », par exemple).
DecisionParrainage decisionParrainage({
  required int base,
  required LoyaltyRate rate,
  required ContexteParrainage contexte,
  ReferralConfig config = const ReferralConfig(),
}) {
  if (!config.actif) return const DecisionParrainage(motif: 'parrainage coupé');
  if (base <= 0) return const DecisionParrainage(motif: 'aucune base');
  if (contexte.parrainUid.trim().isEmpty) {
    return const DecisionParrainage(motif: 'aucun parrain');
  }
  if (contexte.parrainUid == contexte.filleulUid) {
    return const DecisionParrainage(motif: 'auto-parrainage');
  }
  if (contexte.parrainEstFilleulDuFilleul) {
    return const DecisionParrainage(motif: 'parrainage croisé');
  }

  // ── Barrières d'identité [31/10/2026] ────────────────────────────────────
  // Placées AVANT les autres refus (plafonds, verrou de marge) : la raison
  // « profil incomplet » est celle qui doit remonter à l'admin quand un
  // client se plaint de n'avoir rien touché.
  if (!contexte.identiteFilleulComplete) {
    return const DecisionParrainage(motif: 'identité du filleul incomplète');
  }
  if (!contexte.identiteParrainComplete) {
    return const DecisionParrainage(motif: 'identité du parrain incomplète');
  }
  if (contexte.dejaRecompense) {
    return const DecisionParrainage(motif: 'déjà récompensé');
  }
  if (!contexte.premierAchatEligible) {
    return const DecisionParrainage(motif: 'pas le premier achat éligible');
  }

  // ── Barrières d'identité ─────────────────────────────────────────────────
  final String? telFilleul = numeroComparable(contexte.telephoneFilleul);
  final String? telParrain = numeroComparable(contexte.telephoneParrain);
  if (telFilleul != null && telFilleul == telParrain) {
    return const DecisionParrainage(motif: 'même numéro que le parrain');
  }
  final String? appFilleul = appareilComparable(contexte.appareilFilleul);
  final String? appParrain = appareilComparable(contexte.appareilParrain);
  if (appFilleul != null && appFilleul == appParrain) {
    return const DecisionParrainage(motif: 'même appareil que le parrain');
  }

  // ── Plafonds ─────────────────────────────────────────────────────────────
  if (config.maxParJour > 0 &&
      contexte.recompensesParrainAujourdhui >= config.maxParJour) {
    return const DecisionParrainage(motif: 'plafond quotidien atteint');
  }
  if (config.maxParCompte > 0 &&
      contexte.recompensesParrainTotal >= config.maxParCompte) {
    return const DecisionParrainage(motif: 'plafond du compte atteint');
  }

  // ── Le verrou des 40 % ───────────────────────────────────────────────────
  // Le plafond de `loyalty_rules.dart` garantit déjà que 3 × base tient dans
  // la marge autorisée. On le REVÉRIFIE : si un jour un taux était forcé par
  // la configuration, le parrainage se coupe tout seul au lieu de grignoter
  // la commission.
  if (!rate.plancherRespecte) {
    return const DecisionParrainage(motif: 'plancher de marge violé');
  }

  final int bonusFilleul = config.bonusFilleul ? base : 0;
  return DecisionParrainage(
    pointsFilleulExtra: bonusFilleul,
    pointsParrain: base,
  );
}

/// Clé du compteur quotidien d'un parrain : `uid_AAAA-MM-JJ`.
///
/// Un document par parrain et par jour, incrémenté DANS la même transaction
/// que la récompense : le plafond ne peut donc pas être dépassé par deux
/// téléphones serveurs qui créditeraient en même temps.
String cleCompteurParrain(String parrainUid, DateTime jour) {
  final DateTime d = jour.toUtc();
  String deux(int v) => v.toString().padLeft(2, '0');
  return '${parrainUid}_${d.year}-${deux(d.month)}-${deux(d.day)}';
}
