/// [QUOTA 29/10/2026] Dernier état connu du document `servers/{deviceId}`.
///
/// Le téléphone écoute déjà ce document en temps réel (RemoteCommandHandler)
/// pour recevoir les ordres de l'admin. Les autres services (relevé réseau…)
/// lisent cette copie au lieu de relire la base à chaque passage.
class ServerDocCache {
  ServerDocCache._();

  static Map<String, dynamic>? _donnees;
  static DateTime? _recuLe;

  /// Copie reçue par l'écoute, ou `null` si rien n'est encore arrivé.
  static Map<String, dynamic>? get donnees => _donnees;

  /// Vrai si une copie a été reçue depuis moins de [age].
  static bool fraiche(Duration age) {
    final DateTime? t = _recuLe;
    return _donnees != null && t != null && DateTime.now().difference(t) < age;
  }

  static void mettreAJour(Map<String, dynamic> donnees) {
    _donnees = Map<String, dynamic>.from(donnees);
    _recuLe = DateTime.now();
  }

  static void vider() {
    _donnees = null;
    _recuLe = null;
  }
}
