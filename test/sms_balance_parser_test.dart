import 'package:flutter_test/flutter_test.dart';
import 'package:recharge237_serveur/service/report/sms_balance_parser.dart';

/// [COMPTA 28/10/2026] Les SMS des opérateurs n'ont pas de format garanti.
/// Ces tests fixent ce qui doit être compris, et surtout ce qui ne doit PAS
/// être deviné : un message publicitaire ne doit jamais produire un montant
/// comptable.
void main() {
  test('vente de crédit MTN : montant, solde, référence, sens sortie', () {
    final SmsParse p = parseSmsBody(
      'Vous avez vendu 500 FCFA de credit a 677123456. '
      'Votre nouveau solde est de 12 345 FCFA. ID: 1234567890',
      sender: 'MTN',
    );
    expect(p.recognised, isTrue);
    expect(p.amount, 500);
    expect(p.balance, 12345);
    expect(p.direction, SmsDirection.debit);
    expect(p.operator, 'mtn');
    expect(p.reference, contains('1234567890'));
  });

  test('réception de crédit MTN : sens entrée', () {
    final SmsParse p = parseSmsBody(
      'Vous avez recu 5000 FCFA de 674583531. '
      'Votre solde est de 17 000 FCFA.',
      sender: 'MTN',
    );
    expect(p.recognised, isTrue);
    expect(p.direction, SmsDirection.credit);
    expect(p.amount, 5000);
    expect(p.balance, 17000);
  });

  test('message de solde seul', () {
    final SmsParse p = parseSmsBody('Votre solde est de 4 500 FCFA.',
        sender: 'CAMTEL');
    expect(p.recognised, isTrue);
    expect(p.balance, 4500);
    expect(p.amount, isNull);
    expect(p.operator, 'camtel');
  });

  test('SMS anglais (MTN) compris', () {
    final SmsParse p = parseSmsBody(
      'You have transferred 1000 FCFA. Your balance is 2,500 FCFA',
      sender: 'MTN',
    );
    expect(p.direction, SmsDirection.debit);
    expect(p.amount, 1000);
    expect(p.balance, 2500);
  });

  test('réponse technique sans montant : non reconnue, jamais inventée', () {
    final SmsParse p = parseSmsBody(
      'System is processing your requestion by SMS, please wait',
    );
    expect(p.recognised, isFalse);
    expect(p.balance, isNull);
    expect(p.reason, contains('montant'));
  });

  test('publicité avec des montants : AUCUN montant comptable retenu', () {
    final SmsParse p = parseSmsBody(
      'Rechargez 1000 FCFA et gagnez 500 FCFA de bonus ! Offre valable.',
      sender: 'MTN',
    );
    expect(p.recognised, isFalse);
    expect(p.balance, isNull);
    expect(p.amount, isNull);
  });

  test('opérateur déduit de l\'expéditeur quand le texte ne le dit pas', () {
    final SmsParse p = parseSmsBody('Votre solde est de 900 FCFA.',
        sender: 'Orange CM');
    expect(p.operator, 'orange');
  });

  test('montants avec espaces, points ou virgules', () {
    expect(smsAmount('12 345'), 12345);
    expect(smsAmount('12.345'), 12345);
    expect(smsAmount('12,345'), 12345);
  });

  test('un nombre trop long n\'est pas un montant', () {
    // Numéro de téléphone ou identifiant attrapé par erreur.
    expect(smsAmount('674583531987'), isNull);
  });

  test('message vide', () {
    final SmsParse p = parseSmsBody('   ');
    expect(p.recognised, isFalse);
    expect(p.reason, contains('vide'));
  });
}
