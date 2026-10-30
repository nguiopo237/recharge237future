import 'package:flutter_test/flutter_test.dart';
import 'package:recharge237_serveur/service/loyalty/loyalty_rules.dart';
import 'package:recharge237_serveur/service/loyalty/redemption_rules.dart';

/// [CONVERSION 31/10/2026] LOT 3 — la conversion transforme des points en
/// argent réel. Ces tests verrouillent les trois choses qui pourraient coûter
/// cher : un montant hors palier, un débit supérieur au solde, et une
/// conversion illimitée sur un compte compromis.
void main() {
  test('palier : 1 000 F accepté, tout multiple de 1 000 accepté', () {
    expect(
      decisionRedemption(montant: 1000, solde: 5000).valide,
      isTrue,
    );
    expect(decisionRedemption(montant: 1000, solde: 5000).points, 1000);
    expect(decisionRedemption(montant: 3000, solde: 5000).points, 3000);
    expect(
      decisionRedemption(montant: '2 000', solde: 5000).points,
      2000,
      reason: 'montant écrit comme dans l’app',
    );
  });

  test('refus sous le palier et hors palier', () {
    final DecisionRedemption petit =
        decisionRedemption(montant: 500, solde: 5000);
    expect(petit.valide, isFalse);
    expect(petit.motif, contains('palier'));

    final DecisionRedemption bancal =
        decisionRedemption(montant: 1500, solde: 5000);
    expect(bancal.valide, isFalse);
    expect(bancal.motif, contains('multiples de 1000'));
  });

  test('jamais plus que le solde', () {
    final DecisionRedemption d = decisionRedemption(montant: 2000, solde: 1999);
    expect(d.valide, isFalse);
    expect(d.motif, 'points insuffisants');

    // Le solde exact est utilisable jusqu'au dernier point.
    expect(decisionRedemption(montant: 2000, solde: 2000).valide, isTrue);
  });

  test('plafond par opération', () {
    const RedemptionConfig config = RedemptionConfig(plafondParOperation: 3000);
    expect(
      decisionRedemption(montant: 3000, solde: 9999, config: config).valide,
      isTrue,
    );
    final DecisionRedemption trop =
        decisionRedemption(montant: 4000, solde: 9999, config: config);
    expect(trop.valide, isFalse);
    expect(trop.motif, contains('plafond par opération'));
  });

  test('plafond quotidien : la 2e passe, la 3e est refusée', () {
    expect(
      decisionRedemption(montant: 1000, solde: 9000, conversionsAujourdhui: 1)
          .valide,
      isTrue,
    );
    final DecisionRedemption troisieme = decisionRedemption(
      montant: 1000,
      solde: 9000,
      conversionsAujourdhui: 2,
    );
    expect(troisieme.valide, isFalse);
    expect(troisieme.motif, 'plafond quotidien atteint');
  });

  test('la conversion peut être coupée sans arrêter le programme', () {
    final DecisionRedemption d = decisionRedemption(
      montant: 1000,
      solde: 9000,
      config: const RedemptionConfig(actif: false),
    );
    expect(d.valide, isFalse);
    expect(d.motif, 'conversion désactivée');
  });

  test('configuration illisible : valeurs prudentes', () {
    const RedemptionConfig defaut = RedemptionConfig();
    expect(defaut.actif, isTrue);
    expect(defaut.plafondParOperation, 5000);
    expect(defaut.maxParJour, 2);

    final RedemptionConfig lu = RedemptionConfig.fromMap(<String, dynamic>{
      'conversion_active': 'non',
      'conversion_plafond': 2000,
      'conversion_max_jour': '0',
    });
    expect(lu.actif, isTrue, reason: 'seul le booléen false coupe');
    expect(lu.plafondParOperation, 2000);
    expect(lu.maxParJour, 0, reason: '0 = pas de limite quotidienne');

    // Un plafond inférieur au palier rendrait la fonctionnalité inutilisable.
    final RedemptionConfig absurde =
        RedemptionConfig.fromMap(<String, dynamic>{'conversion_plafond': 500});
    expect(absurde.plafondParOperation, 5000);
  });

  test('une recharge payée en points ne rapporte aucun point', () {
    // Sans cette exclusion, convertir 1 000 F re-créditerait des points et le
    // programme s'auto-alimenterait.
    final DecisionCredit d = decisionCredit(
      commande: <String, dynamic>{
        'operateur_cible': 'mtn_airtime',
        'status': '21',
        'idphone': 'u1',
        'amount': '1000',
        'paiement': 'points',
      },
      commissions: const <String, double>{'mtn_airtime': 5},
    );
    expect(d.crediter, isFalse);
    expect(d.motif, 'payée en points');
  });
}
