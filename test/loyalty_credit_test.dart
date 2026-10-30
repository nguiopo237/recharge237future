import 'package:flutter_test/flutter_test.dart';
import 'package:recharge237_serveur/service/loyalty/loyalty_rules.dart';

/// [FIDÉLITÉ 31/10/2026] La décision de crédit : c'est ici que de l'argent est
/// distribué ou non. Chaque refus doit être explicite, pour qu'un client qui
/// « n'a pas eu ses points » ait une réponse vérifiable.
void main() {
  const Map<String, double> commissions = <String, double>{
    'camtel_pre': 8,
    'camtel_post': 8,
    'mtn_airtime': 5,
    'mtn_forfait_activate': 5,
    'mtn_bundle': 5,
    'orange_airtime': 5,
  };

  Map<String, dynamic> cmd({
    String op = 'camtel_pre',
    String status = '3',
    Object amount = 5000,
    String uid = 'u1',
    Object? loyalty,
  }) =>
      <String, dynamic>{
        'operateur_cible': op,
        'status': status,
        'amount': amount,
        'idphone': uid,
        if (loyalty != null) 'loyalty': loyalty,
      };

  test('commande livrée de 5 000 F CAMTEL : 5 tranches × 16 = 80 points', () {
    final DecisionCredit d = decisionCredit(
      commande: cmd(),
      commissions: commissions,
    );
    expect(d.crediter, isTrue);
    expect(d.points, 80);
    expect(d.taux!.pointsParTranche, 16);
    expect(d.motif, isEmpty);
  });

  test('un montant stocké en texte est lu correctement', () {
    expect(
      decisionCredit(commande: cmd(amount: '2 000 F'), commissions: commissions)
          .points,
      32,
    );
    expect(
      decisionCredit(commande: cmd(amount: '10000'), commissions: commissions)
          .points,
      160,
    );
  });

  test('refus : commande pas encore livrée', () {
    final DecisionCredit d = decisionCredit(
      commande: cmd(status: '2'),
      commissions: commissions,
    );
    expect(d.crediter, isFalse);
    expect(d.motif, contains('pas livrée'));
  });

  test('refus : commande déjà créditée (rejeu du balayeur)', () {
    final DecisionCredit d = decisionCredit(
      commande: cmd(loyalty: 80),
      commissions: commissions,
    );
    expect(d.crediter, isFalse);
    expect(d.motif, 'déjà créditée');
  });

  test('refus : sous le seuil de 1 000 F', () {
    final DecisionCredit d = decisionCredit(
      commande: cmd(amount: 999),
      commissions: commissions,
    );
    expect(d.crediter, isFalse);
    expect(d.motif, contains('seuil'));
  });

  test('refus : consultation gratuite des offres Boost', () {
    final DecisionCredit d = decisionCredit(
      commande: cmd(op: 'mtn_forfait', status: '31', amount: 0),
      commissions: commissions,
    );
    expect(d.crediter, isFalse);
    expect(d.motif, 'opération non éligible');
  });

  test('refus : commission non configurée pour cet opérateur', () {
    final DecisionCredit d = decisionCredit(
      commande: cmd(op: 'orange_airtime', status: '41'),
      commissions: const <String, double>{'camtel_pre': 8},
    );
    expect(d.crediter, isFalse);
    expect(d.motif, 'commission non configurée');
  });

  test('refus : acheteur inconnu (idphone vide)', () {
    final DecisionCredit d = decisionCredit(
      commande: cmd(uid: ''),
      commissions: commissions,
    );
    expect(d.crediter, isFalse);
    expect(d.motif, 'acheteur inconnu');
  });

  test('refus : programme désactivé par la configuration', () {
    final DecisionCredit d = decisionCredit(
      commande: cmd(),
      commissions: commissions,
      config: const LoyaltyConfig(actif: false),
    );
    expect(d.crediter, isFalse);
    expect(d.motif, 'programme inactif');
  });

  test('MTN crédit livré (statut 21) : 10 points par tranche', () {
    final DecisionCredit d = decisionCredit(
      commande: cmd(op: 'mtn_airtime', status: '21', amount: 1500),
      commissions: commissions,
    );
    expect(d.points, 10, reason: 'une seule tranche entière sur 1 500 F');
  });

  test('MTN Boost activé (statut 34) : crédité, mais statut 35 non', () {
    expect(
      decisionCredit(
        commande: cmd(op: 'mtn_forfait_activate', status: '34', amount: 2000),
        commissions: commissions,
      ).points,
      20,
    );
    expect(
      decisionCredit(
        commande: cmd(op: 'mtn_forfait_activate', status: '35', amount: 2000),
        commissions: commissions,
      ).crediter,
      isFalse,
    );
  });

  test('un montant vide ne fait pas planter le balayeur', () {
    final DecisionCredit d = decisionCredit(
      commande: cmd()..['amount'] = null,
      commissions: commissions,
    );
    expect(d.crediter, isFalse);
    expect(d.motif, 'montant illisible');
    expect(montantLisible(null), isNull);
    expect(montantLisible('abc'), isNull);
    expect(montantLisible(0), 0);
  });
}
