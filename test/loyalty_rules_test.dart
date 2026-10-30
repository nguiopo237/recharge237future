import 'package:flutter_test/flutter_test.dart';
import 'package:recharge237_serveur/service/loyalty/loyalty_rules.dart';

/// [FIDÉLITÉ 31/10/2026] Le barème est le seul endroit où la marge du
/// propriétaire peut être mangée : ces tests verrouillent les chiffres, la
/// réserve de sécurité et le seuil de 1 000 F.
void main() {
  const Map<String, double> commissions = <String, double>{
    'camtel_pre': 8,
    'camtel_post': 8,
    'mtn_airtime': 5,
    'mtn_forfait_activate': 5,
    'mtn_bundle': 5,
    'orange_airtime': 5,
  };

  test('barème réel : 16 points Camtel, 10 points MTN/Orange par 1 000 F', () {
    final LoyaltyRate camtel = tauxPour(
      operateurCible: 'camtel_pre',
      commissions: commissions,
    )!;
    expect(camtel.commissionBp, 800);
    expect(camtel.netBp, 640, reason: '8 % − 20 % de réserve de sécurité');
    expect(camtel.remiseBp, 160, reason: '25 % du net redistribué');
    expect(camtel.pointsParTranche, 16);
    expect(camtel.margeConserveePct, 6.40);

    for (final String op in <String>[
      'mtn_airtime',
      'mtn_forfait_activate',
      'mtn_bundle',
      'orange_airtime',
    ]) {
      final LoyaltyRate r =
          tauxPour(operateurCible: op, commissions: commissions)!;
      expect(r.pointsParTranche, 10, reason: op);
      // 5 % − 1,00 % de remise = 4,00 % conservés, réserve déjà déduite.
      expect(r.margeConserveePct, 4.00, reason: op);
    }
  });

  test('la réserve est retirée AVANT la redistribution, et le plafond corrige', () {
    // Sans réserve : 5 % × 25 % = 1,25 % seraient distribués, soit 12 points.
    // Le plafond des 40 % (parrainage compris) n'autorise que 1,00 % :
    // le barème est RAMENÉ à 10 points au lieu de grignoter la marge.
    final LoyaltyRate sansReserve = tauxPour(
      operateurCible: 'mtn_airtime',
      commissions: commissions,
      config: const LoyaltyConfig(reserveCharges: 0),
    )!;
    expect(sansReserve.pointsParTranche, 10);
    expect(sansReserve.plafonne, isTrue);
    expect(sansReserve.partRetenueWorstCasePct, 40.0);

    final LoyaltyRate avecReserve = tauxPour(
      operateurCible: 'mtn_airtime',
      commissions: commissions,
      config: const LoyaltyConfig(reserveCharges: 40),
    )!;
    expect(avecReserve.pointsParTranche, 7,
        reason: '5 % × 60 % × 25 % = 0,75 % → 7 pts, sous le plafond');
    expect(avecReserve.plafonne, isFalse);
    expect(avecReserve.partRetenueWorstCasePct, greaterThan(40.0));
  });

  test('aucune commission configurée = aucun point (jamais de taux inventé)',
      () {
    expect(
      tauxPour(
        operateurCible: 'orange_airtime',
        commissions: const <String, double>{},
      ),
      isNull,
    );
    expect(
      tauxPour(
        operateurCible: 'orange_airtime',
        commissions: const <String, double>{'orange_airtime': 0},
      ),
      isNull,
    );
  });

  test('la consultation gratuite des offres Boost ne rapporte rien', () {
    expect(
      tauxPour(
        operateurCible: 'mtn_forfait',
        commissions: const <String, double>{'mtn_forfait': 5},
      ),
      isNull,
    );
    expect(operateurEligible(''), isFalse);
  });

  test('seuil de 1 000 F et tranches entières : rien sous le seuil', () {
    final LoyaltyRate camtel = tauxPour(
      operateurCible: 'camtel_pre',
      commissions: commissions,
    )!;
    expect(pointsPour(25, camtel), 0);
    expect(pointsPour(999, camtel), 0);
    expect(pointsPour(1000, camtel), 16);
    expect(pointsPour(1999, camtel), 16, reason: 'tranche entière seulement');
    expect(pointsPour(2500, camtel), 32);
    expect(pointsPour(10000, camtel), 160);
  });

  test('un taux trop faible ne distribue rien plutôt que d\'arrondir', () {
    // 0,2 % de commission : 0,2 × 0,8 × 0,25 = 0,04 % → 0,4 point/1 000 F.
    final LoyaltyRate? faible = tauxPour(
      operateurCible: 'mtn_airtime',
      commissions: const <String, double>{'mtn_airtime': 0.2},
    );
    expect(faible!.pointsParTranche, 0);
    expect(faible.actif, isFalse);
    expect(pointsPour(50000, faible), 0);
  });

  test('la config se borne : valeurs absurdes ignorées, pas de marge négative',
      () {
    final LoyaltyConfig c = LoyaltyConfig.fromMap(<String, dynamic>{
      'part_marge': 500,
      'reserve_charges': -10,
      'validite_mois': 0,
    });
    expect(c.partMarge, 100);
    expect(c.reserveCharges, 0);
    expect(c.validiteMois, 12);
    expect(c.actif, isTrue);

    expect(LoyaltyConfig.fromMap(<String, dynamic>{'actif': false}).actif,
        isFalse);
    // Absent = valeurs par défaut, jamais « programme coupé » par accident.
    expect(const LoyaltyConfig().partMarge, 25);
  });

  // ── RÈGLE DES 40 % (plancher absolu de retenue) ──────────────────────────
  group('plancher de 40 % de la commission brute', () {
    test('le barème actuel est EXACTEMENT au plafond autorisé', () {
      for (final MapEntry<String, double> e in commissions.entries) {
        final LoyaltyRate r = tauxPour(
          operateurCible: e.key,
          commissions: commissions,
        )!;
        // Pire cas : filleul doublé + parrain = 3 × la remise.
        expect(r.partRetenueWorstCasePct, 40.0, reason: e.key);
        expect(r.plancherRespecte, isTrue, reason: e.key);
        expect(r.retenueWorstCasePct, e.value * 0.40, reason: e.key);
      }
    });

    test('relever la part redistribuée ne perce jamais le plancher', () {
      final LoyaltyRate r = tauxPour(
        operateurCible: 'camtel_pre',
        commissions: commissions,
        config: const LoyaltyConfig(partMarge: 80),
      )!;
      expect(r.plafonne, isTrue);
      expect(r.pointsParTranche, 16, reason: 'ramené au plafond');
      expect(r.partRetenueWorstCasePct, 40.0);
      expect(r.plancherRespecte, isTrue);
    });

    test('supprimer la réserve ne perce jamais le plancher', () {
      final LoyaltyRate mtn = tauxPour(
        operateurCible: 'mtn_airtime',
        commissions: commissions,
        config: const LoyaltyConfig(reserveCharges: 0, partMarge: 50),
      )!;
      expect(mtn.plafonne, isTrue);
      expect(mtn.pointsParTranche, 10);
      expect(mtn.partRetenueWorstCasePct, 40.0);
    });

    test('un plancher demandé plus bas est refusé (jamais sous 40 %)', () {
      final LoyaltyConfig c = LoyaltyConfig.fromMap(<String, dynamic>{
        'plancher_retenue': 10,
        'part_marge': 100,
      });
      expect(c.plancherEffectif, 40);
      final LoyaltyRate r = tauxPour(
        operateurCible: 'camtel_pre',
        commissions: commissions,
        config: c,
      )!;
      expect(r.plancherRespecte, isTrue);
      expect(r.partRetenueWorstCasePct, 40.0);
    });

    test('exiger PLUS que 40 % est accepté et réduit le barème', () {
      final LoyaltyRate r = tauxPour(
        operateurCible: 'camtel_pre',
        commissions: commissions,
        config: const LoyaltyConfig(plancherRetenue: 70),
      )!;
      // 8 % × (1 − 0,70) / 3 = 0,80 % → 8 points par 1 000 F.
      expect(r.pointsParTranche, 8);
      expect(r.partRetenueWorstCasePct, greaterThanOrEqualTo(70.0));
    });

    test('VERROU EXHAUSTIF : plancher respecté pour toute config plausible',
        () {
      // On balaie les configurations qu'un humain peut réellement saisir :
      // commissions de 0 à 20 %, réserve de 0 à 100 %, part de 0 à 100 %,
      // plancher de 0 à 100 %. Aucune combinaison ne doit desceller les 40 %.
      for (int centiemes = 1; centiemes <= 2000; centiemes += 7) {
        final double commission = centiemes / 100;
        for (int reserve = 0; reserve <= 100; reserve += 10) {
          for (int part = 0; part <= 100; part += 10) {
            for (int plancher = 0; plancher <= 100; plancher += 20) {
              final LoyaltyRate? r = tauxPour(
                operateurCible: 'mtn_airtime',
                commissions: <String, double>{'mtn_airtime': commission},
                config: LoyaltyConfig(
                  reserveCharges: reserve.toDouble(),
                  partMarge: part.toDouble(),
                  plancherRetenue: plancher.toDouble(),
                ),
              );
              if (r == null) continue;
              expect(
                r.plancherRespecte,
                isTrue,
                reason: 'commission=$commission % reserve=$reserve % '
                    'part=$part % plancher=$plancher % → '
                    '${r.partRetenueWorstCasePct} % retenus',
              );
            }
          }
        }
      }
    });

    test('verifierPlancher ne signale rien avec les taux réels', () {
      expect(verifierPlancher(commissions: commissions), isEmpty);
      expect(
        verifierPlancher(
          commissions: commissions,
          config: const LoyaltyConfig(partMarge: 100, reserveCharges: 0),
        ),
        isEmpty,
        reason: 'le plafond corrige, donc aucune violation à signaler',
      );
    });

    test('parrainage : le total reste dans l\'enveloppe autorisée', () {
      final LoyaltyRate camtel = tauxPour(
        operateurCible: 'camtel_pre',
        commissions: commissions,
      )!;
      // Commande de 10 000 F : 10 tranches × 16 = 160 points.
      final PointsParrainage p = pointsParrainagePour(10000, camtel);
      expect(p.filleul, 320, reason: 'points doublés');
      expect(p.parrain, 160);
      expect(p.total, 480);

      // Ce que cela coûte, comparé à la commission brute (10 000 × 8 % = 800 F).
      const int commission = 800;
      final double partRedistribuee = p.total * 100 / commission;
      expect(partRedistribuee, 60.0, reason: '60 % distribués au maximum');
      expect(100 - partRedistribuee, greaterThanOrEqualTo(40.0));
    });
  });

  test('tousLesTaux ignore les opérations non rentables et non configurées',
      () {
    final Map<String, LoyaltyRate> taux = tousLesTaux(
      commissions: <String, double>{
        'camtel_pre': 8,
        'mtn_airtime': 5,
        'mtn_forfait': 5, // consultation gratuite
        'orange_airtime': 0, // pas de taux → exclu
      },
    );
    expect(taux.keys.toSet(), <String>{'camtel_pre', 'mtn_airtime'});
    expect(taux['camtel_pre']!.pointsParTranche, 16);
    expect(taux['mtn_airtime']!.pointsParTranche, 10);
  });
}
