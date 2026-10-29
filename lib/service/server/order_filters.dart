/// [PRODUCTION 27/10/2026] Filtres de sécurité du serveur USSD, isolés ici
/// pour être testés (test/order_filters_test.dart).

/// Statuts `Transact` qui déclenchent une action du serveur :
///  - "0"  : requête Good Deal MTN (gratuite, `operateur_cible: mtn_forfait`) ;
///  - "1"  : paiement confirmé par la passerelle, à livrer ;
///  - "6"  : CAMTEL postpayé ;
///  - "9"  : recharge SIM post / relance ;
///  - "11" : point de vente (code USSD dans `retry`).
const List<String> kActionableStatuses = ['0', '1', '6', '9', '11'];

/// Âge maximal d'une commande traitée automatiquement. Au-delà, elle est
/// laissée à l'admin (évite de relancer d'anciennes commandes déjà livrées à
/// la main lors du branchement du serveur sur la base de production).
const Duration kMaxOrderAge = Duration(hours: 12);

/// `heure` est écrit par les apps sous la forme `DateTime.now().toUtc()`
/// convertie en texte (ex. "2026-10-27 23:05:12.345Z"). Illisible ou trop
/// ancienne => `false` (on ne traite pas, par prudence).
bool isRecentOrder(Object? heure, {DateTime? now, Duration maxAge = kMaxOrderAge}) {
  if (heure == null) return false;
  final DateTime? t = DateTime.tryParse(heure.toString().trim());
  if (t == null) return false;
  final DateTime ref = (now ?? DateTime.now()).toUtc();
  final Duration age = ref.difference(t.toUtc());
  // Petite tolérance si l'horloge du téléphone client avance un peu.
  return age <= maxAge && age >= const Duration(minutes: -10);
}

/// Types d'opération qu'un téléphone peut se voir confier par l'admin
/// (champ `handles` de `servers/{deviceId}`). Les valeurs sont exactement
/// celles que les apps clientes écrivent dans `operateur_cible`.
const List<String> kOperationTypes = [
  'camtel_pre',
  'camtel_post',
  'mtn_airtime',
  'mtn_forfait',
  // [ORANGE 28/10/2026] Type réservé : aucun flux USSD Orange n'est encore
  // branché, donc l'assigner ne livre rien pour l'instant. Il est déclaré ici
  // pour que la configuration admin, le contrôle et les tests soient prêts le
  // jour où le flow sera fourni (cf. lib/service/ussd/orange_ussd_manager.dart).
  'orange_airtime',
];

/// Routage décidé par l'admin : quel téléphone exécute quel type de recharge
/// ou d'activation.
///
///  - liste absente ou vide : le téléphone traite tout ce que son matériel
///    permet (comportement historique, aucun risque pour les bases existantes) ;
///  - `all` : la même chose, écrit explicitement ;
///  - sinon : seuls les types listés sont traités, les autres restent aux
///    autres téléphones.
///
/// `mtn_forfait` couvre la requête gratuite ET l'activation de l'offre
/// choisie : un téléphone à SIM MTN doit traiter les deux, sinon le client
/// reçoit une liste d'offres que personne n'active.
bool handlesOperation(List<String> handles, String type) {
  if (handles.isEmpty) return true;
  if (handles.contains('all')) return true;
  return handles.contains(type);
}

/// [28/10/2026] Montant minimal accepté par les opérateurs (MTN, Orange,
/// Blue/CAMTEL) : 100 F. En dessous, l'USSD aboutit à un refus : mieux vaut
/// ne jamais lancer la session et le dire clairement.
const int kMinRechargeAmount = 100;

/// Vrai si [amount] (nombre ou texte) atteint le minimum opérateur.
bool isAmountAllowed(Object? amount) {
  final int? v = amount is num
      ? amount.toInt()
      : int.tryParse((amount?.toString() ?? '').replaceAll(RegExp(r'[^0-9]'), ''));
  return v != null && v >= kMinRechargeAmount;
}

/// Numéro CAMTEL (9 chiffres) : mobiles 62x, fixes / Blue 242 et 243.
/// Accepte les espaces et l'indicatif 237 éventuel.
bool isCamtelNumber(String number) {
  String n = number.replaceAll(RegExp(r'[^0-9]'), '');
  if (n.length == 12 && n.startsWith('237')) n = n.substring(3);
  return RegExp(r'^(62\d|24[23])\d{6}$').hasMatch(n);
}

/// Numéro Orange Cameroun : préfixes 069, 065, 655 à 659. Accepte les espaces
/// et l'indicatif 237, comme [isCamtelNumber].
///
/// [ORANGE 28/10/2026] Prêt pour la validation des cibles Orange, mais aucune
/// livraison n'est encore implémentée côté serveur.
bool isOrangeNumber(String number) {
  String n = number.replaceAll(RegExp(r'[^0-9]'), '');
  if (n.length == 12 && n.startsWith('237')) n = n.substring(3);
  return RegExp(r'^(069|065|65[5-9])\d{6}$').hasMatch(n);
}

/// Message de refus enregistré dans `failure_reason`.
String amountTooSmallReason(Object? amount) =>
    'Montant $amount FCFA inférieur au minimum opérateur ($kMinRechargeAmount FCFA)';

/// [28/10/2026] Statut d'exécution d'origine d'une commande, pour une
/// **relance manuelle** décidée par l'admin.
///
/// Le serveur ne relance plus rien de lui-même. L'admin remet la commande dans
/// son état « à exécuter » (bouton « Relancer » de l'app serveur, ou à la main
/// dans Firestore : `relance_demandee: true` + ce `status`). `null` = rien à
/// relancer (type inconnu, ou Orange dont le flow USSD n'existe pas encore).
String? relaunchStatusFor(Map<String, dynamic> data) {
  final String op =
      (data['operateur_cible'] ?? '').toString().trim().toLowerCase();
  switch (op) {
    case 'camtel_pre':
    case 'camtel_post':
      return op == 'camtel_pre' ? '1' : '6';
    case 'mtn_airtime':
    case 'mtn_forfait_activate':
      return '1';
    case 'mtn_forfait':
      // Requête gratuite de la liste d'offres (aucun paiement).
      return '0';
    case 'orange_airtime':
      return null;
  }
  // Anciennes commandes sans `operateur_cible` : CAMTEL prépayé historique.
  return '1';
}

/// Statuts pour lesquels une relance n'a AUCUN sens (ou serait dangereuse) :
/// commande non payée, déjà en file automatique, ou déjà livrée — relancer
/// créditerait deux fois le client.
const Set<String> kNotRelaunchableStatuses = {
  '0', // pas encore payée
  '1', '6', '11', // déjà en file : le serveur va la prendre
  '3', '10', '21', '31', '34', '5', '8', // déjà livrée / réussie
};

/// Vrai si l'admin peut relancer cette commande à la main.
bool canRelaunch(Map<String, dynamic> data) {
  final String status = (data['status'] ?? '').toString().trim();
  if (kNotRelaunchableStatuses.contains(status)) return false;
  if ((data['relance_demandee'] as Object?) == true) return false; // déjà demandée
  return relaunchStatusFor(data) != null;
}

/// Réponse USSD CAMTEL indiquant que le transfert de crédit a été accepté
/// (texte réellement renvoyé par CAMTEL, faute de frappe comprise).
bool isCamtelTransferAccepted(String ussdText) {
  final String t = ussdText.toLowerCase();
  return t.contains('processing your requestion') ||
      t.contains('processing your request');
}
