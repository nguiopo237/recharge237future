/// Lecture des écrans USSD renvoyés par l'opérateur (texte capté par le
/// service d'accessibilité). Fonctions pures, testées dans
/// test/ussd_screens_test.dart.
///
/// Textes réels relevés le 27/10/2026 sur MTN Cameroun (*126#, SIM en
/// itinérance) :
///  - menu : "MTN Mobile Money\n1) Depot d argent\n...\n4) Vendre du credit\n..."
///  - après "4" : "Entrez le montant" (≈ 3,6 s)
///  - montant trop bas : "Erreur montant minimum" (la question revient ensuite)
///  - réseau perdu : "Réseau mobile non disponible"
///  - session expirée (≈ 30 s sans réponse) :
///    "Problème de connexion ou code IHM non valide."
library;

/// Minuscules, sans accents, espaces normalisés.
String normalizeUssd(String raw) {
  const Map<String, String> accents = {
    'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a',
    'ç': 'c',
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'î': 'i', 'ï': 'i', 'í': 'i',
    'ô': 'o', 'ö': 'o', 'ó': 'o',
    'ù': 'u', 'û': 'u', 'ü': 'u', 'ú': 'u',
    '’': "'",
  };
  final StringBuffer b = StringBuffer();
  for (final int r in raw.toLowerCase().runes) {
    final String ch = String.fromCharCode(r);
    b.write(accents[ch] ?? ch);
  }
  return b.toString().replaceAll(RegExp(r'[ \t]+'), ' ').trim();
}

/// Écran d'attente du téléphone (pas encore la réponse de l'opérateur).
bool isTransientScreen(String raw) {
  final String s = normalizeUssd(raw);
  return s.contains('execution du code') ||
      s.contains('session ussd initiee') && !s.contains(')') ||
      s.contains('veuillez patienter') && !s.contains(')') ||
      s.contains('patientez') && !s.contains(')') ||
      s.contains('traitement en cours') ||
      s.contains('en cours de traitement') ||
      s.contains('verification en cours') ||
      s == 'envoi...' ||
      s == 'chargement...';
}

/// Raison d'échec si l'écran est une erreur, sinon `null`.
/// [retryable] indique si relancer plus tard a un sens (réseau, session).
class UssdError {
  final String reason;
  final bool retryable;
  const UssdError(this.reason, {required this.retryable});
}

UssdError? ussdErrorOf(String raw) {
  final String s = normalizeUssd(raw);
  const List<String> network = [
    'reseau mobile non disponible',
    'reseau non disponible',
    'pas de service',
    'aucun service',
    'no network',
    'network not available',
    'mmi code',
  ];
  const List<String> session = [
    'probleme de connexion',
    'code ihm non valide',
    'session expir',
    'session terminee',
    'delai depasse',
    'time out',
    'timeout',
  ];
  const List<String> generic = [
    'erreur',
    'error',
    'echec',
    'echoue',
    'failed',
    'invalide',
    'invalid',
    'incorrect',
    'insuffisant',
    'insufficient',
    'refuse',
    'non autorise',
    'not allowed',
    'impossible',
    'operation annulee',
    'transaction annulee',
    'compte bloque',
    'est bloque',
  ];
  for (final String k in network) {
    if (s.contains(k)) return UssdError(raw.trim(), retryable: true);
  }
  for (final String k in session) {
    if (s.contains(k)) return UssdError(raw.trim(), retryable: true);
  }
  for (final String k in generic) {
    if (s.contains(k)) return UssdError(raw.trim(), retryable: false);
  }
  return null;
}

/// Lignes numérotées d'un menu : "4) Vendre du credit", "2. Pack 1Go 500F".
final RegExp _numberedLine = RegExp(r'^\s*(\d{1,2})\s*[).:-]\s*(\S.*)$');

List<String> numberedLines(String raw) => raw
    .split('\n')
    .map((String l) => l.trim())
    .where((String l) => _numberedLine.hasMatch(l))
    .toList();

/// Numéro de l'option dont le libellé correspond à [label] (texte
/// normalisé), ex. `findMenuOption(menu, RegExp(r'vendre du credit'))` → "4".
String? findMenuOption(String raw, RegExp label) {
  for (final String line in raw.split('\n')) {
    final RegExpMatch? m = _numberedLine.firstMatch(line.trim());
    if (m != null && label.hasMatch(normalizeUssd(m.group(2)!))) {
      return m.group(1);
    }
  }
  return null;
}

/// Libellé de l'option [index] dans l'écran, ou `null`.
String? menuLineFor(String raw, String index) {
  for (final String line in raw.split('\n')) {
    final RegExpMatch? m = _numberedLine.firstMatch(line.trim());
    if (m != null && m.group(1) == index.trim()) return line.trim();
  }
  return null;
}

/// Touche pour afficher la page suivante d'une liste ("00) Suite",
/// "0. Plus", "# Suivant"...), ou `null`.
///
/// [PAGES 28/10/2026] La détection est volontairement SOUPLE : MTN n'écrit pas
/// toujours la touche collée au mot. Relevés réels : « 00. Next »,
/// « 00) Suite », « 0. Plus ». On accepte donc tout numéro de pagination
/// (00, 0, 99, *, #) suivi, sur la même ligne, d'un mot de continuation où
/// qu'il soit placé — « 00 - Voir la suite », « 00: page suivante »...
///
/// Le parcours s'arrête de lui-même dès que ce motif disparaît : c'est la
/// seule condition d'arrêt, la limite de pages n'est qu'un garde-fou.
String? findMorePageKey(String raw) {
  final RegExp more = RegExp(
      r'^\s*(00|0|99|\*|#)\s*[).:\-]?\s*.*\b(suite|suivant|suivante|plus|more|next|page suivante)\b');
  for (final String line in raw.split('\n')) {
    final RegExpMatch? m = more.firstMatch(normalizeUssd(line));
    if (m != null) return m.group(1);
  }
  return null;
}

/// Offres numérotées de PLUSIEURS écrans (menu paginé), dans l'ordre, sans
/// doublon.
///
/// Relevé le 28/10/2026 sur MTN Boost : la liste tient sur une page de cinq
/// offres terminée par « 00. Next ». Ne garder que le dernier écran faisait
/// perdre les offres des pages précédentes.
///
/// « 00. Next » est une commande, pas une offre : elle est écartée.
List<String> offerLines(List<String> screens) {
  final List<String> out = <String>[];
  final Set<String> vus = <String>{};
  for (final String screen in screens) {
    for (final String raw in screen.split('\n')) {
      final String line = raw.trim();
      if (!_numberedLine.hasMatch(line)) continue;
      if (findMorePageKey(line) != null) continue;
      if (!vus.add(line)) continue;
      out.add(line);
    }
  }
  return out;
}

/// Dernier montant suivi de F/FCFA dans un texte (le prix figure presque
/// toujours en fin de libellé MTN, ex. « Pack 200 Mo à 200F »).
final RegExp _amountRe = RegExp(r'(\d[\d\s]{0,9})\s*F', caseSensitive: false);

/// Prix lu dans un libellé d'offre, ou `null` s'il est absent.
int? parseOfferPrice(String text) {
  final List<RegExpMatch> found = _amountRe.allMatches(text).toList();
  if (found.isEmpty) return null;
  return int.tryParse(found.last.group(1)!.replaceAll(' ', ''));
}

/// Libellé d'offre destiné AU CLIENT.
///
/// [DISPLAY 28/10/2026] MTN écrit ses lignes pour un revendeur, pas pour un
/// acheteur : « 500U=1GB/30D: C=25F ». Le client, lui, doit lire ce qu'il
/// achète. On retire donc les codes techniques (`C=...` et assimilés) et on
/// rend les unités lisibles. Relevés réels sur MTN Boost :
///   « 500U=1GB/30D: C=25F »              → « 1 Go / 30 jours »
///   « 250U=500MB+100 SMS/3D: C=13F »     → « 500 Mo + 100 SMS / 3 jours »
///   « 1000U=2.1GB/30D: C=50F »           → « 2,1 Go / 30 jours »
///   « Depot de 100F; C=50F »             → « Dépôt de 100 F »
///
/// Ce libellé ne sert QU'À l'affichage : [UssdOffer.label] continue de porter
/// le texte exact de MTN, indispensable pour retrouver l'offre à l'activation.
/// Le prix reste celui que le serveur a lu (`price`), jamais déduit du texte
/// nettoyé.
String offerDisplayTitle(String raw) {
  String t = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  // 1. Codes techniques : « C=25F », « ; com=50F », « cout=... ».
  t = t.replaceAll(
      RegExp(
          r'[;,]?\s*\b(?:c|com|comm|commission|cout|coût)\s*=\s*\d+(?:[.,]\d+)?\s*(?:f|fcfa|xaf)\b',
          caseSensitive: false),
      '');
  // 2. « 500U=1GB/30D » : la gauche est ce que ça coûte, la droite ce que le
  //    client reçoit. On n'affiche que la droite.
  final RegExpMatch? debit =
      RegExp(r'^\s*\d+(?:[.,]\d+)?\s*u\s*=\s*(.+)$', caseSensitive: false)
          .firstMatch(t);
  if (debit != null) t = debit.group(1)!;
  // 3. Unités et durées lisibles.
  t = t.replaceAllMapped(RegExp(r'(\d+(?:[.,]\d+)?)\s*GB\b', caseSensitive: false),
      (Match m) => '${m.group(1)!.replaceAll('.', ',')} Go');
  t = t.replaceAllMapped(RegExp(r'(\d+(?:[.,]\d+)?)\s*MB\b', caseSensitive: false),
      (Match m) => '${m.group(1)!.replaceAll('.', ',')} Mo');
  t = t.replaceAllMapped(RegExp(r'/\s*(\d{1,2})\s*D\b', caseSensitive: false),
      (Match m) => ' / ${m.group(1)} ${m.group(1) == '1' ? 'jour' : 'jours'}');
  // 4. Quelques tournures MTN rendues lisibles (« d appels », « jusqu a »).
  t = t
      .replaceAllMapped(RegExp(r'\bd appels?\b', caseSensitive: false),
          (Match m) => "d'appels")
      .replaceAllMapped(RegExp(r'\bjusqu a\b', caseSensitive: false),
          (Match m) => "jusqu'à")
      .replaceAllMapped(RegExp(r'\bde credit\b', caseSensitive: false),
          (Match m) => 'de crédit')
      .replaceAllMapped(RegExp(r'\bvalide\b', caseSensitive: false),
          (Match m) => 'valable')
      .replaceAllMapped(RegExp(r'\bdepot\b', caseSensitive: false),
          (Match m) => 'Dépôt');
  // 5. Espaces et ponctuation orphelins laissés par les retraits.
  t = t.replaceAll(RegExp(r'\s*\+\s*'), ' + ');
  t = t.replaceAllMapped(RegExp(r'(\d)\s*F\b'), (Match m) => '${m.group(1)} F');
  t = t.replaceAll(RegExp(r'\s*[:;,-]+\s*$'), '');
  return t.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Offre MTN structurée, telle que lue dans le menu USSD.
///
/// [label] conserve le texte exact affiché (détail + prix), [price] le prix
/// extrait quand il est lisible, et [key] la touche à composer pour la choisir
/// sur l'écran où elle apparaît (elle peut différer d'une page à l'autre).
class UssdOffer {
  final String index;
  final String key;
  final String label;
  final int? price;
  final int page;

  /// Libellé lisible pour le client (cf. [offerDisplayTitle]). `null` = à
  /// calculer depuis [label].
  final String? title;

  const UssdOffer({
    required this.index,
    required this.label,
    required this.page,
    String? key,
    this.price,
    this.title,
  }) : key = key ?? index;

  /// Texte montré au client : jamais le texte brut de MTN s'il est nettoyable.
  String get displayTitle => (title != null && title!.trim().isNotEmpty)
      ? title!
      : offerDisplayTitle(label);

  UssdOffer withExtraText(String extra) {
    final String merged = '$label $extra'.trim();
    return UssdOffer(
      index: index,
      key: key,
      label: merged,
      price: parseOfferPrice(merged) ?? price,
      page: page,
    );
  }

  /// Recollage d'un libellé coupé par l'affichage, sur deux pages.
  ///
  /// [PAGES 28/10/2026] Relevé réel : « 5) 2 » en bas d'une page, puis
  /// « 50U=900U+75MB+2500U/3D: C=13F » en haut de la suivante — MTN a coupé le
  /// nombre « 250U » en deux. Quand le fragment se termine par un chiffre et
  /// que la suite commence par un chiffre, on colle sans espace ; sinon on
  /// garde une espace pour ne pas souder deux mots.
  UssdOffer withContinuation(String suite) {
    final String a = label.trimRight();
    final String b = suite.trimLeft();
    final bool nombreCoupe =
        RegExp(r'\d$').hasMatch(a) && RegExp(r'^\d').hasMatch(b);
    final String merged = nombreCoupe ? '$a$b' : '$a $b'.trim();
    return UssdOffer(
      index: index,
      key: key,
      label: merged,
      price: parseOfferPrice(merged) ?? price,
      page: page,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'index': index,
        'key': key,
        'label': label,
        'title': displayTitle,
        if (price != null) 'price': price,
        'page': page,
      };
}

/// Offres structurées de PLUSIEURS écrans (menu paginé).
///
/// [MTN PRIX 28/10/2026] Deux problèmes réglés ici :
///   • le prix peut se trouver sur la ligne SUIVANTE du même écran (MTN coupe
///     parfois le libellé) : les lignes non numérotées sont rattachées à
///     l'offre précédente avant de chercher le prix, sinon l'offre sortait
///     sans prix et le client ne pouvait pas l'acheter ;
///   • la numérotation MTN peut recommencer à 1 sur chaque page : l'offre
///     garde donc sa page et son libellé, pour que l'activation retrouve la
///     bonne entrée au lieu de taper un numéro ambigu.
List<UssdOffer> offerRecords(List<String> screens) {
  final List<UssdOffer> out = <UssdOffer>[];
  final Set<String> vus = <String>{};
  int? courant;

  // [PAGES 28/10/2026] MTN coupe parfois une offre en DEUX écrans. Relevé
  // réel (677156949, 28/10) :
  //   page 1 se termine par « 5) 2 »            (libellé tronqué, sans prix)
  //   page 2 commence par « 50U=900U+...C=13F » (la suite, sans numéro)
  // Sans recollage, le client voyait une offre « 2 » inutilisable et perdait
  // la vraie (250U=900U+75MB+2500U/3D). On recolle donc la première ligne
  // non numérotée d'une page sur la dernière offre de la page précédente
  // quand celle-ci n'a pas encore de prix.
  int? coupee;

  for (int page = 0; page < screens.length; page++) {
    courant = null;
    bool debutDePage = true;
    for (final String raw in screens[page].split('\n')) {
      final String line = raw.trim();
      if (line.isEmpty) continue;
      final RegExpMatch? m = _numberedLine.firstMatch(line);
      if (m != null) {
        // « 00. Next » est une commande de page, pas une offre.
        if (findMorePageKey(line) != null) {
          courant = null;
          debutDePage = false;
          continue;
        }
        final String index = m.group(1)!;
        final String label = (m.group(2) ?? '').trim();
        debutDePage = false;
        if (!vus.add('$page|$index|$label')) {
          courant = null;
          continue;
        }
        out.add(UssdOffer(
          index: index,
          label: label.isEmpty ? line : label,
          price: parseOfferPrice(label),
          page: page,
        ));
        courant = out.length - 1;
        coupee = null;
        continue;
      }
      // Ligne non numérotée : suite d'une offre.
      if (debutDePage && coupee != null) {
        out[coupee] = out[coupee].withContinuation(line);
        courant = coupee;
        coupee = null;
        debutDePage = false;
        continue;
      }
      debutDePage = false;
      // Suite du texte de l'offre en cours (prix parfois rejeté à la ligne).
      final int? enCours = courant;
      if (enCours != null) out[enCours] = out[enCours].withExtraText(line);
    }
    // Dernière offre de la page sans prix lisible = libellé probablement coupé
    // par l'affichage : la suite est en tête de la page suivante.
    coupee = (out.isNotEmpty && out.last.page == page && out.last.price == null)
        ? out.length - 1
        : null;
  }
  return out;
}

/// Touche à composer pour choisir l'offre dont le libellé correspond à
/// [label] sur CET écran, ou `null` si elle n'y est pas.
///
/// Utilisé à l'activation : on ne valide jamais un numéro « au hasard », on ne
/// répond que si l'offre achetée est réellement affichée.
String? findOptionForLabel(String raw, String label) {
  final String cible = normalizeUssd(label);
  if (cible.length < 6) return null;
  for (final String line in raw.split('\n')) {
    final RegExpMatch? m = _numberedLine.firstMatch(line.trim());
    if (m == null) continue;
    final String libelle = normalizeUssd(m.group(2) ?? '');
    if (libelle.length < 6) continue;
    if (libelle == cible) return m.group(1);
    if (libelle.contains(cible) || cible.contains(libelle)) return m.group(1);
  }
  return null;
}

bool asksPin(String raw) {
  final String s = normalizeUssd(raw);
  return RegExp(r'\bpin\b|code secret|mot de passe|password|passcode')
      .hasMatch(s);
}

bool asksAmount(String raw) => normalizeUssd(raw).contains('montant') ||
    normalizeUssd(raw).contains('amount');

bool asksPhoneNumber(String raw) => RegExp(
        r'numero|telephone|beneficiaire|destinataire|phone number|msisdn')
    .hasMatch(normalizeUssd(raw));

/// Option "Confirmer" d'un écran de confirmation ("1) Confirmer"), ou `null`.
String? findConfirmOption(String raw) =>
    findMenuOption(raw, RegExp(r'^(confirmer|valider|oui|accepter|yes|confirm)'));

/// Numéros de téléphone camerounais (9 chiffres, éventuellement précédés
/// de 237) cités dans l'écran.
List<String> mentionedPhones(String raw) => RegExp(r'(?:237)?(6\d{8})\b')
    .allMatches(raw.replaceAll(' ', ''))
    .map((RegExpMatch m) => m.group(1)!)
    .toList();

/// `false` si l'écran cite un ou plusieurs numéros et qu'aucun n'est
/// [clientNumber] : on ne valide jamais une opération vers un autre numéro.
bool phonesConsistent(String raw, String clientNumber) {
  final List<String> phones = mentionedPhones(raw);
  if (phones.isEmpty) return true;
  final String c = clientNumber.replaceAll(RegExp(r'[^0-9]'), '');
  final String local = c.length == 12 && c.startsWith('237') ? c.substring(3) : c;
  return phones.contains(local);
}

/// Prix affichés dans une ligne d'offre ("1Go 24h 500F", "1 000 FCFA").
List<int> pricesInLine(String line) => RegExp(r'(\d[\d .]*)\s*(?:f\b|fcfa|xaf)')
    .allMatches(normalizeUssd(line))
    .map((RegExpMatch m) =>
        int.tryParse(m.group(1)!.replaceAll(RegExp(r'[ .]'), '')) ?? -1)
    .where((int p) => p > 0)
    .toList();

/// Réponse finale MTN indiquant une opération réussie.
bool isMtnSuccess(String raw) {
  if (ussdErrorOf(raw) != null) return false;
  final String s = normalizeUssd(raw);
  return RegExp(
          r'succes|reussi|effectue|vous avez (vendu|envoye|transfere|achete|active|souscrit|recharge)|a ete (vendu|envoye|transfere|active|recharge|credite)|nouveau solde|new balance|successful')
      .hasMatch(s);
}

/// Un montant de recharge valide : chiffres uniquement, > 0.
bool isValidAmount(String amount) =>
    RegExp(r'^\d+$').hasMatch(amount.trim()) && int.parse(amount.trim()) > 0;

/// Numéro MTN Cameroun (9 chiffres) : 67x, 650-654, 680-684.
bool isMtnNumber(String number) {
  String n = number.replaceAll(RegExp(r'[^0-9]'), '');
  if (n.length == 12 && n.startsWith('237')) n = n.substring(3);
  return RegExp(r'^(67\d|65[0-4]|68[0-4])\d{6}$').hasMatch(n);
}

/// Numéro local à 9 chiffres (retire l'indicatif 237 et les séparateurs).
String localNumber(String number) {
  final String n = number.replaceAll(RegExp(r'[^0-9]'), '');
  return n.length == 12 && n.startsWith('237') ? n.substring(3) : n;
}

/// Écran ouvert mais vide de contenu exploitable : ni menu numéroté, ni
/// question, ni verdict de l'opérateur — juste un titre.
///
/// Relevé le 28/10/2026 (commande de 106 F, 04:11) : téléphone verrouillé,
/// MIUI n'a peint que « MTN Mobile Money », sans le corps du menu. Personne ne
/// pouvait répondre, MTN a fermé la session au bout de 30 s. Un humain, lui,
/// aurait appuyé sur « Annuler » tout de suite.
bool isUnusableScreen(String raw) {
  final String s = normalizeUssd(raw);
  if (s.isEmpty) return true;
  if (numberedLines(raw).isNotEmpty) return false;
  if (asksPin(raw) || asksAmount(raw) || asksPhoneNumber(raw)) return false;
  if (ussdErrorOf(raw) != null) return false;
  if (isMtnSuccess(raw)) return false;
  // Un écran qui porte des chiffres transporte une information (montant,
  // numéro, solde) : on ne le considère jamais comme vide.
  if (RegExp(r'\d').hasMatch(s)) return false;
  return s.split(RegExp(r'\s+')).length <= 6;
}

/// Fenêtre d'information de l'opérateur ou du système (« INFOS SYSTEME DE
/// OPERATEUR », « Information », « Message système »…).
///
/// Elle n'apporte rien à la session et masque le dialogue USSD : un humain
/// appuie sur « OK / Annuler » et continue. Le serveur fait pareil
/// (voir [UssdSessionRunner]) au lieu d'attendre qu'elle disparaisse seule.
bool isBlockingInfoScreen(String raw) {
  final String s = normalizeUssd(raw);
  return s.contains('infos systeme') ||
      s.contains('info systeme') ||
      s.contains('informations systeme') ||
      s.contains('information systeme') ||
      s.contains('message systeme') ||
      s.contains('notification systeme') ||
      s.contains('system info') ||
      s.contains('infos de votre operateur');
}

/// Texte sur une ligne pour les journaux.
String oneLine(String raw) => raw.replaceAll(RegExp(r'\s*\n\s*'), ' | ').trim();
