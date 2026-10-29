/// [INTERNET 28/10/2026] Décide QUAND prévenir l'admin d'une coupure
/// d'Internet sur un téléphone serveur.
///
/// Classe pure : aucun accès réseau, aucune horloge implicite (le temps est
/// passé en argument), donc entièrement testable — voir
/// test/internet_watch_test.dart.
///
/// Différence avec le réseau de l'opérateur : une SIM peut être enregistrée et
/// le téléphone sans Internet (Wi-Fi coupé, forfait épuisé). Dans ce cas il ne
/// livre plus rien **et** il ne peut pas le dire, puisque Telegram passe par la
/// même connexion. Le téléphone prévient donc à son retour, et le script PC
/// `_claude_watch_servers.js` surveille son silence.
enum InternetEvent {
  /// Rien à signaler.
  none,

  /// Coupure confirmée au-delà du seuil : à signaler.
  perte,

  /// Coupure toujours en cours : rappel périodique.
  rappel,

  /// La base répond de nouveau après une coupure : à signaler.
  retour,
}

class InternetWatch {
  /// Silence toléré avant de conclure à une coupure. Deux battements manqués
  /// (le battement est à 30 s).
  final Duration seuil;

  /// Intervalle entre deux rappels pendant une coupure prolongée.
  final Duration rappel;

  bool _ok = true;
  DateTime _dernierContact;
  DateTime? _coupureDepuis;
  DateTime? _derniereAlerte;
  Duration? _derniereCoupure;

  InternetWatch({
    this.seuil = const Duration(seconds: 75),
    this.rappel = const Duration(minutes: 30),
    DateTime? maintenant,
  }) : _dernierContact = maintenant ?? DateTime.now();

  /// Vrai si la base répondait au dernier battement.
  bool get ok => _ok;

  /// Début de la coupure en cours (`null` si tout va bien).
  DateTime? get coupureDepuis => _coupureDepuis;

  /// Durée de la coupure en cours, ou `null`.
  Duration? dureeCoupure(DateTime maintenant) =>
      _coupureDepuis == null ? null : maintenant.difference(_coupureDepuis!);

  /// Durée de la DERNIÈRE coupure terminée (lue après un [InternetEvent.retour]).
  Duration? get derniereCoupure => _derniereCoupure;

  /// À appeler à chaque battement.
  InternetEvent beat({required bool joignable, required DateTime maintenant}) {
    if (joignable) {
      _dernierContact = maintenant;
      if (_ok) return InternetEvent.none;
      _derniereCoupure = _coupureDepuis == null
          ? null
          : maintenant.difference(_coupureDepuis!);
      _ok = true;
      _coupureDepuis = null;
      _derniereAlerte = null;
      return InternetEvent.retour;
    }

    final int muet = maintenant.difference(_dernierContact).inSeconds;
    if (muet < seuil.inSeconds) return InternetEvent.none;

    if (_ok) {
      _ok = false;
      _coupureDepuis = _dernierContact;
      _derniereAlerte = maintenant;
      return InternetEvent.perte;
    }

    final DateTime? derniere = _derniereAlerte;
    if (derniere == null || maintenant.difference(derniere) >= rappel) {
      _derniereAlerte = maintenant;
      return InternetEvent.rappel;
    }
    return InternetEvent.none;
  }
}
