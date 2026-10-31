import 'package:flutter_test/flutter_test.dart';
import 'package:recharge237_serveur/service/loyalty/loyalty_rules.dart';
import 'package:recharge237_serveur/service/loyalty/referral_rules.dart';

/// [PARRAINAGE 31/10/2026] LOT 2 — ces tests verrouillent les barrières
/// anti-abus et le budget : un parrainage récompensé ne doit jamais coûter
/// plus de 3 × la base (le facteur déjà pris en compte par le plafond des
/// 40 %), ni échapper aux plafonds quotidiens.
void main() {
  const Map<String, double> commissions = <String, double>{
    'camtel_pre': 8,
    'camtel_post': 8,
    'mtn_airtime': 5,
    'mtn_forfait_activate': 5,
    'orange_airtime': 5,
  };

  final LoyaltyRate mtn = tauxPour(
    operateurCible: 'mtn_airtime',
    commissions: commissions,
  )!;

  ContexteParrainage contexte({
    String filleul = 'filleul-1',
    String parrain = 'parrain-1',
    String? telFilleul,
    String? telParrain,
    String? appFilleul,
    String? appParrain,
    bool dejaRecompense = false,
    bool premierAchatEligible = true,
    int aujourdHui = 0,
    int total = 0,
    bool croise = false,
    // [IDENTITÉ 31/10/2026] Vrai par défaut ici : ces tests portent sur le
    // budget et les plafonds, pas sur l'identité (testée séparément plus bas
    // et dans identity_rules_test.dart).
    bool identiteFilleul = true,
    bool identiteParrain = true,
  }) =>
      ContexteParrainage(
        filleulUid: filleul,
        parrainUid: parrain,
        telephoneFilleul: telFilleul,
        telephoneParrain: telParrain,
        appareilFilleul: appFilleul,
        appareilParrain: appParrain,
        dejaRecompense: dejaRecompense,
        premierAchatEligible: premierAchatEligible,
        recompensesParrainAujourdhui: aujourdHui,
        recompensesParrainTotal: total,
        parrainEstFilleulDuFilleul: croise,
        identiteFilleulComplete: identiteFilleul,
        identiteParrainComplete: identiteParrain,
      );

  test('1 000 F MTN : 10 pts de base, donc 10 au filleul + 10 au parrain '
      '(30 pts distribués au total, soit 3 × base)', () {
    final DecisionParrainage d = decisionParrainage(
      base: pointsPour(1000, mtn),
      rate: mtn,
      contexte: contexte(),
    );

    expect(d.recompenser, isTrue);
    expect(d.pointsFilleulExtra, 10, reason: 'le filleul voit ses 10 pts doublés');
    expect(d.pointsParrain, 10);
    expect(d.total, 20);

    // Total réellement distribué sur la commande : 10 (crédit normal)
    // + 20 (parrainage) = 30 = 3 × base = le facteur du plafond des 40 %.
    expect(10 + d.total, 3 * mtn.pointsParTranche);
  });

  test('les 40 % tiennent même quand la commande déclenche un parrainage', () {
    for (final MapEntry<String, double> e in commissions.entries) {
      final LoyaltyRate r =
          tauxPour(operateurCible: e.key, commissions: commissions)!;
      final DecisionParrainage d = decisionParrainage(
        base: pointsPour(1000, r),
        rate: r,
        contexte: contexte(),
      );
      expect(d.recompenser, isTrue, reason: e.key);

      // Points distribués en pire cas = 3 × base, exprimés en pourcentage du
      // montant : 3 × base / 1000. La marge retenue doit rester ≥ 40 % de la
      // commission brute.
      final double distribuePct = (3 * r.pointsParTranche) / 1000 * 100;
      final double retenuePct = r.commissionPct - distribuePct;
      expect(
        retenuePct / r.commissionPct * 100,
        greaterThanOrEqualTo(kPlancherRetenue),
        reason: '${e.key} : $retenuePct % sur ${r.commissionPct} %',
      );
    }
  });

  test('auto-parrainage refusé', () {
    final DecisionParrainage d = decisionParrainage(
      base: 10,
      rate: mtn,
      contexte: contexte(filleul: 'moi', parrain: 'moi'),
    );
    expect(d.recompenser, isFalse);
    expect(d.motif, 'auto-parrainage');
  });

  test('même numéro refusé, même écrit autrement', () {
    for (final (String, String) a in <(String, String)>[
      ('674583531', '+237 6 74 58 35 31'),
      ('0674583531', '237674583531'),
      ('00237674583531', '674583531'),
    ]) {
      final DecisionParrainage d = decisionParrainage(
        base: 10,
        rate: mtn,
        contexte: contexte(telFilleul: a.$1, telParrain: a.$2),
      );
      expect(d.recompenser, isFalse, reason: '${a.$1} / ${a.$2}');
      expect(d.motif, 'même numéro que le parrain');
    }
  });

  test('un numéro absent ne bloque pas (clients anonymes)', () {
    final DecisionParrainage d = decisionParrainage(
      base: 10,
      rate: mtn,
      contexte: contexte(telFilleul: null, telParrain: '674583531'),
    );
    expect(d.recompenser, isTrue);
  });

  test('même appareil refusé, empreinte inconnue tolérée', () {
    final DecisionParrainage meme = decisionParrainage(
      base: 10,
      rate: mtn,
      contexte: contexte(appFilleul: 'F5BF1E4422033950', appParrain: 'f5bf1e4422033950'),
    );
    expect(meme.recompenser, isFalse);
    expect(meme.motif, 'même appareil que le parrain');

    final DecisionParrainage inconnu = decisionParrainage(
      base: 10,
      rate: mtn,
      contexte: contexte(appFilleul: '', appParrain: 'f5bf1e4422033950'),
    );
    expect(inconnu.recompenser, isTrue);
  });

  test('plafond de 5 par jour : la 5e passe, la 6e est refusée', () {
    final DecisionParrainage cinquieme = decisionParrainage(
      base: 10,
      rate: mtn,
      contexte: contexte(aujourdHui: 4),
    );
    expect(cinquieme.recompenser, isTrue);

    final DecisionParrainage sixieme = decisionParrainage(
      base: 10,
      rate: mtn,
      contexte: contexte(aujourdHui: 5),
    );
    expect(sixieme.recompenser, isFalse);
    expect(sixieme.motif, 'plafond quotidien atteint');
  });

  test('plafond de vie optionnel', () {
    const ReferralConfig config = ReferralConfig(maxParCompte: 50);
    final DecisionParrainage d = decisionParrainage(
      base: 10,
      rate: mtn,
      contexte: contexte(total: 50),
      config: config,
    );
    expect(d.recompenser, isFalse);
    expect(d.motif, 'plafond du compte atteint');
  });

  test('pas de récompense avant le premier achat livré, ni deux fois', () {
    final DecisionParrainage pasEncore = decisionParrainage(
      base: 10,
      rate: mtn,
      contexte: contexte(premierAchatEligible: false),
    );
    expect(pasEncore.recompenser, isFalse);
    expect(pasEncore.motif, 'pas le premier achat éligible');

    final DecisionParrainage deja = decisionParrainage(
      base: 10,
      rate: mtn,
      contexte: contexte(dejaRecompense: true),
    );
    expect(deja.recompenser, isFalse);
    expect(deja.motif, 'déjà récompensé');
  });

  test('échange croisé de codes refusé (A parraine B qui parraine A)', () {
    final DecisionParrainage d = decisionParrainage(
      base: 10,
      rate: mtn,
      contexte: contexte(croise: true),
    );
    expect(d.recompenser, isFalse);
    expect(d.motif, 'parrainage croisé');
  });

  test('programme coupé : plus rien n\'est payé', () {
    final DecisionParrainage d = decisionParrainage(
      base: 10,
      rate: mtn,
      contexte: contexte(),
      config: const ReferralConfig(actif: false),
    );
    expect(d.recompenser, isFalse);
    expect(d.motif, 'parrainage coupé');
  });

  test('bonus filleul désactivable : le parrain gagne encore', () {
    final DecisionParrainage d = decisionParrainage(
      base: 10,
      rate: mtn,
      contexte: contexte(),
      config: const ReferralConfig(bonusFilleul: false),
    );
    expect(d.pointsFilleulExtra, 0);
    expect(d.pointsParrain, 10);
    expect(d.recompenser, isTrue);
  });

  test('un taux qui violerait les 40 % coupe le parrainage', () {
    // Barème volontairement absurde : 500 points par tranche sur une
    // commission MTN de 5 %. Le plafond ne peut pas passer, donc le
    // parrainage doit refuser de payer.
    const LoyaltyRate gourmand = LoyaltyRate(
      operateur: 'mtn_airtime',
      commissionBp: 500,
      netBp: 400,
      remiseBp: 400,
      pointsParTranche: 500,
      plancherBp: 4000,
    );
    final DecisionParrainage d = decisionParrainage(
      base: 500,
      rate: gourmand,
      contexte: contexte(),
    );
    expect(d.recompenser, isFalse);
    expect(d.motif, 'plancher de marge violé');
  });

  test('configuration illisible : valeurs par défaut prudentes', () {
    const ReferralConfig defaut = ReferralConfig();
    expect(defaut.actif, isTrue);
    expect(defaut.maxParJour, 5);

    final ReferralConfig lu = ReferralConfig.fromMap(<String, dynamic>{
      'actif': 'non',
      'max_par_jour': '7',
      'bonus_filleul': false,
    });
    expect(lu.actif, isTrue, reason: 'seul le booléen false coupe');
    expect(lu.maxParJour, 7);
    expect(lu.bonusFilleul, isFalse);

    final ReferralConfig negatif =
        ReferralConfig.fromMap(<String, dynamic>{'max_par_jour': -3});
    expect(negatif.maxParJour, 5);
  });

  test('clé du compteur quotidien : un document par parrain et par jour', () {
    expect(
      cleCompteurParrain('abc', DateTime.utc(2026, 11, 1)),
      'abc_2026-11-01',
    );
  });

  // [IDENTITÉ 31/10/2026] Aucun bonus sans nom complet + téléphone
  // camerounais + email, des DEUX côtés. Ces tests verrouillent le fait que
  // le parrainage ne peut pas servir de robinet à points pour des comptes
  // anonymes créés en série.
  test('filleul non identifié : aucun bonus (ni pour lui, ni pour le parrain)',
      () {
    final DecisionParrainage d = decisionParrainage(
      base: pointsPour(1000, mtn),
      rate: mtn,
      contexte: contexte(identiteFilleul: false),
    );
    expect(d.recompenser, isFalse);
    expect(d.total, 0);
    expect(d.motif, 'identité du filleul incomplète');
  });

  test('parrain non identifié : aucun bonus', () {
    final DecisionParrainage d = decisionParrainage(
      base: pointsPour(1000, mtn),
      rate: mtn,
      contexte: contexte(identiteParrain: false),
    );
    expect(d.recompenser, isFalse);
    expect(d.motif, 'identité du parrain incomplète');
  });

  test('identités complètes : la récompense repasse normalement', () {
    final DecisionParrainage d = decisionParrainage(
      base: pointsPour(1000, mtn),
      rate: mtn,
      contexte: contexte(identiteFilleul: true, identiteParrain: true),
    );
    expect(d.recompenser, isTrue);
    expect(d.pointsParrain, 10);
    expect(d.pointsFilleulExtra, 10);
  });
}
