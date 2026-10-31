/// [IDENTITÉ 31/10/2026] Qui a le droit de gagner des points ou de parrainer.
///
/// POURQUOI UNE RÈGLE PURE ICI : les points et le parrainage valent de
/// l'argent réel. Un profil anonyme (`idphone` seul) ne peut pas être
/// poursuivi en cas d'abus, et un même fraudeur peut créer cent profils vides
/// pour récolter cent bonus de parrainage. On exige donc TROIS preuves
/// d'identité avant de payer quoi que ce soit :
///
///   1. un NOM COMPLET (prénom + nom, pas un pseudo d'une lettre) ;
///   2. un NUMÉRO DE TÉLÉPHONE CAMEROUNAIS valide (9 chiffres, préfixe
///      mobile) — c'est aussi le canal par lequel on joint le client ;
///   3. une ADRESSE EMAIL valide.
///
/// Le calcul est côté SERVEUR (téléphone serveur, droits admin) et non côté
/// client : un client modifié ne peut pas s'inventer une identité pour
/// déclencher un bonus. La collecte, elle, se fait dans les applications, qui
/// affichent les champs manquants.
///
/// Un profil incomplet ne perd pas ses points : il n'en gagne pas. Le message
/// qui lui est destiné est explicite ([manquants]), pour qu'il puisse
/// compléter et participer ensuite.
library;

/// Profil minimal exigé pour participer aux bonus.
class IdentiteClient {
  final String nom;
  final String telephone;
  final String email;

  const IdentiteClient({this.nom = '', this.telephone = '', this.email = ''});

  /// Nom complet : au moins deux mots de deux lettres au moins.
  ///
  /// « J » ou « test » ne sont pas des noms : c'est exactement ce genre de
  /// saisie qui rend un profil intraçable.
  bool get nomValide {
    final List<String> mots = nom
        .trim()
        .split(RegExp(r'\s+'))
        .where((String m) => m.isNotEmpty)
        .toList();
    if (mots.length < 2) return false;
    return mots.every((String m) =>
        RegExp(r"^[A-Za-zÀ-ÿ'’\-. ]{2,}$").hasMatch(m));
  }

  /// Numéro camerounais : 9 chiffres commençant par 6, avec ou sans `+237`.
  String get telephoneNormalise {
    String n = telephone.replaceAll(RegExp(r'[^0-9]'), '');
    if (n.startsWith('00237')) n = n.substring(5);
    if (n.length == 12 && n.startsWith('237')) n = n.substring(3);
    return n;
  }

  bool get telephoneValide =>
      RegExp(r'^6\d{8}$').hasMatch(telephoneNormalise);

  /// Adresse email plausible : une seule arobase, un domaine avec point, une
  /// extension de deux lettres au moins, aucun espace.
  bool get emailValide {
    final String e = email.trim();
    if (e.isEmpty || e.length > 254 || e.contains(' ')) return false;
    if (e.contains('..')) return false;
    return RegExp(r'^[A-Za-z0-9._%+\-]+@[A-Za-z0-9\-]+(\.[A-Za-z0-9\-]+)*\.[A-Za-z]{2,}$')
        .hasMatch(e);
  }

  bool get complete => nomValide && telephoneValide && emailValide;

  /// Champs à réclamer au client, en clair, dans l'ordre d'affichage.
  List<String> get manquants => <String>[
        if (!nomValide) 'nom complet',
        if (!telephoneValide) 'numéro de téléphone camerounais',
        if (!emailValide) 'adresse email',
      ];

  /// Motif lisible pour les journaux et Telegram — vide si tout est complet.
  String get motifIncomplet =>
      complete ? '' : 'identité incomplète (${manquants.join(', ')})';
}

/// Lit l'identité dans un document `users/{uid}`.
///
/// Plusieurs noms de champs sont acceptés : les applications ont écrit
/// `phoneNumber` à un endroit, `phone` à un autre, et `nom`/`nomComplet`
/// selon l'écran. Refuser un profil simplement parce que la clé diffère
/// punirait un client honnête.
IdentiteClient identiteDe(Map<String, dynamic>? profil) {
  if (profil == null) return const IdentiteClient();
  String lit(List<String> cles) {
    for (final String c in cles) {
      final String v = (profil[c] ?? '').toString().trim();
      if (v.isNotEmpty && v.toLowerCase() != 'null') return v;
    }
    return '';
  }

  return IdentiteClient(
    nom: lit(<String>['nom', 'nomComplet', 'fullName', 'name', 'displayName']),
    telephone:
        lit(<String>['phoneNumber', 'phone', 'telephone', 'numero', 'tel']),
    email: lit(<String>['email', 'mail', 'emailAddress']),
  );
}

/// Vrai si ce profil peut participer au programme (points ET parrainage).
bool peutParticiper(Map<String, dynamic>? profil) =>
    identiteDe(profil).complete;
