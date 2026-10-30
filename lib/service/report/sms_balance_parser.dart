/// [COMPTA 28/10/2026] Lecture des SMS des opérateurs (solde, mouvement).
///
/// Les opérateurs n'envoient pas tous le même texte, et il change avec le
/// temps. Ce fichier ne cherche donc pas à reconnaître une phrase exacte : il
/// cherche des **montants suivis d'une devise**, un **mot de solde**
/// (« solde », « balance », « reste »), un **sens** (reçu / vendu) et une
/// référence. Ce qui n'est pas reconnu n'est pas inventé : le SMS est conservé
/// tel quel et signalé, pour qu'on ajoute la règle manquante.
///
/// Classe pure, testée dans test/sms_balance_parser_test.dart.
library;

/// Sens du mouvement décrit par le SMS.
enum SmsDirection {
  /// Aucun mouvement identifiable (message d'information, publicité…).
  none,

  /// De l'argent est entré sur la SIM (dépôt, réception, transfert reçu).
  credit,

  /// De l'argent est sorti (vente de crédit, retrait, transfert envoyé).
  debit,
}

/// Ce qu'un SMS a permis d'extraire.
class SmsParse {
  /// Vrai si un solde OU un mouvement exploitable a été trouvé.
  final bool recognised;

  /// Solde restant annoncé par l'opérateur, en FCFA.
  final int? balance;

  /// Montant du mouvement annoncé, en FCFA.
  final int? amount;

  final SmsDirection direction;

  /// `mtn`, `orange`, `camtel`, ou vide si indéterminé.
  final String operator;

  /// Référence / identifiant de transaction, si présent.
  final String reference;

  /// Pourquoi le message n'a pas été exploité (vide si reconnu).
  final String reason;

  const SmsParse({
    required this.recognised,
    this.balance,
    this.amount,
    this.direction = SmsDirection.none,
    this.operator = '',
    this.reference = '',
    this.reason = '',
  });

  const SmsParse.unknown(String why, {String operator = ''})
      : recognised = false,
        balance = null,
        amount = null,
        direction = SmsDirection.none,
        operator = operator,
        reference = '',
        reason = why;

  String get directionLabel {
    switch (direction) {
      case SmsDirection.credit:
        return 'entrée';
      case SmsDirection.debit:
        return 'sortie';
      case SmsDirection.none:
        return '—';
    }
  }

  @override
  String toString() => 'SmsParse(recognised: $recognised, balance: $balance, '
      'amount: $amount, ${direction.name}, op: $operator, ref: $reference)';
}

/// Texte comparable : minuscules, sans accents, espaces normalisés.
String smsNormalise(String s) {
  final String lower = s.toLowerCase();
  final StringBuffer out = StringBuffer();
  const Map<String, String> accents = <String, String>{
    'à': 'a',
    'á': 'a',
    'â': 'a',
    'ä': 'a',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'í': 'i',
    'î': 'i',
    'ï': 'i',
    'ó': 'o',
    'ô': 'o',
    'ö': 'o',
    'ú': 'u',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ç': 'c',
    'ñ': 'n',
  };
  for (final int unit in lower.codeUnits) {
    final String ch = String.fromCharCode(unit);
    out.write(accents[ch] ?? ch);
  }
  return out.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// « 12 345 », « 12.345 », « 12,345 » → 12345.
int? smsAmount(String raw) {
  final String digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return null;
  // Un montant en FCFA ne dépasse pas quelques millions : au-delà, c'est une
  // date ou un numéro de téléphone mal attrapé.
  if (digits.length > 9) return null;
  return int.tryParse(digits);
}

/// Tous les montants du message, dans l'ordre, avec leur position.
List<({int value, int at})> smsAmounts(String body) {
  final RegExp re = RegExp(
    r'(\d[\d\s.,]{0,12}?)\s*(?:FCFA|F\.?\s?CFA|XAF|FRANCS?)\b',
    caseSensitive: false,
  );
  final List<({int value, int at})> out = <({int value, int at})>[];
  for (final RegExpMatch m in re.allMatches(body)) {
    final int? v = smsAmount(m.group(1) ?? '');
    if (v != null && v > 0) out.add((value: v, at: m.start));
  }
  return out;
}

const List<String> _balanceWords = <String>[
  'solde',
  'balance',
  'reste',
  'disponible',
  'credit restant',
];

const List<String> _debitWords = <String>[
  'avez vendu',
  'vendu',
  'vente',
  'retrait',
  'retire',
  'debite',
  'transfere',
  'transfert de',
  'envoye',
  'envoyez',
  'achat',
  // « sold » seul matchait l'intérieur de « solde » : une RÉCEPTION était
  // comptée comme une sortie (relevé par test/sms_balance_parser_test.dart).
  'you have sold',
  'you have transferred',
  'withdrawn',
];

const List<String> _creditWords = <String>[
  'avez recu',
  'recu',
  'credite',
  'depot',
  'versement',
  'reception',
  'received',
  'deposited',
];

/// Opérateur d'après l'expéditeur puis le texte.
String smsOperator(String body, {String sender = ''}) {
  final String all = smsNormalise('$sender $body');
  // CAMTEL avant MTN : « Blue » est la marque de CAMTEL.
  if (all.contains('camtel') || all.contains('blue')) return 'camtel';
  if (all.contains('mtn')) return 'mtn';
  if (all.contains('orange')) return 'orange';
  return '';
}

/// Analyse un SMS d'opérateur.
///
/// Ne lève jamais : en cas de doute, rend un [SmsParse] non reconnu avec la
/// raison, plutôt qu'un montant inventé.
SmsParse parseSmsBody(String body, {String sender = ''}) {
  final String text = body.trim();
  if (text.isEmpty) return const SmsParse.unknown('message vide');
  final String op = smsOperator(text, sender: sender);
  final String norm = smsNormalise(text);
  final List<({int value, int at})> amounts = smsAmounts(text);

  // 1. Sens du mouvement.
  SmsDirection direction = SmsDirection.none;
  if (_debitWords.any(norm.contains)) {
    direction = SmsDirection.debit;
  } else if (_creditWords.any(norm.contains)) {
    direction = SmsDirection.credit;
  }

  // 2. Solde : le premier montant qui SUIT un mot de solde.
  int? balance;
  for (final ({int value, int at}) a in amounts) {
    final int start = a.at > 45 ? a.at - 45 : 0;
    final String before = smsNormalise(text.substring(start, a.at));
    if (_balanceWords.any(before.contains)) {
      balance = a.value;
      break;
    }
  }

  // 3. Montant du mouvement : le premier montant qui n'est pas le solde.
  int? amount;
  for (final ({int value, int at}) a in amounts) {
    if (a.value == balance) continue;
    amount = a.value;
    break;
  }

  // 4. Référence de transaction.
  String reference = '';
  final RegExpMatch? ref = RegExp(
    r'(?:id|ref|reference|transaction|trans|txn)\s*[:#-]?\s*([A-Z0-9]{6,})',
    caseSensitive: false,
  ).firstMatch(text);
  if (ref != null) reference = ref.group(1) ?? '';

  if (balance == null && amount == null) {
    return SmsParse.unknown(
      amounts.isEmpty
          ? 'aucun montant en FCFA'
          : 'montant présent mais ni solde ni mouvement identifiable',
      operator: op,
    );
  }
  // Un montant seul, sans mot de solde ni de mouvement, n'est pas une
  // information comptable fiable (publicité, offre, rappel).
  if (balance == null && direction == SmsDirection.none) {
    return SmsParse.unknown(
      'montant sans indication de solde ni de mouvement',
      operator: op,
    );
  }

  return SmsParse(
    recognised: true,
    balance: balance,
    amount: amount,
    direction: direction,
    operator: op,
    reference: reference,
  );
}
