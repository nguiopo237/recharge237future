/// [PRODUCTION 27/10/2026] Filtres de sécurité du serveur USSD, isolés ici
/// pour être testés (test/order_filters_test.dart).
library;

import '../ussd/orange_ussd_manager.dart';

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
bool isRecentOrder(Object? heure,
    {DateTime? now, Duration maxAge = kMaxOrderAge}) {
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
  // [OFFRES PERSO 29/10/2026] Good Deal Orange : requête gratuite + activation,
  // sur le même téléphone (comme `mtn_forfait`).
  'orange_forfait',
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
  if (handles.contains('none')) return false;
  if (handles.isEmpty) return true;
  if (handles.contains('all')) return true;
  return handles.contains(type);
}

/// [ROUTAGE 29/10/2026] Une famille de commandes qu'un téléphone écoute :
/// statuts concernés, et `operateur_cible` exigé (`null` = n'importe lequel,
/// y compris absent — les commandes CAMTEL n'ont pas toujours ce champ).
class OrderRoute {
  final List<String> statuses;
  final String? operateur;
  const OrderRoute(this.statuses, [this.operateur]);

  @override
  String toString() =>
      '${statuses.join('/')}${operateur == null ? '' : ' · $operateur'}';
}

/// [ROUTAGE 29/10/2026] Ce que CE téléphone doit écouter, d'après `handles`.
///
/// Avant, chaque téléphone écoutait toutes les commandes à traiter de tous
/// les opérateurs, y compris chaque commande créée et pas encore payée
/// (statut "0") : chaque changement coûtait une lecture PAR téléphone.
/// Désormais un téléphone CAMTEL ne voit plus les commandes MTN, et seul un
/// téléphone Good Deal voit les requêtes au statut "0".
///
/// Correspondance (identique aux branches de check()) :
///  - camtel_pre    : "1", "9" (postpayé, accepté comme avant) et "11"
///                    (point de vente) — sans filtre d'opérateur, les
///                    anciennes commandes CAMTEL n'ayant pas le champ ;
///  - camtel_post   : "9" et "6" ;
///  - mtn_airtime   : "1"/"11" avec `mtn_airtime` ;
///  - mtn_forfait   : "0" avec `mtn_forfait` (requête), "1"/"11" avec
///                    `mtn_forfait_activate` (activation Boost) et avec
///                    `mtn_bundle` (forfait du catalogue) ;
///  - orange_airtime: "1"/"11" avec `orange_airtime`.
///
/// `null` = tout écouter (handles vides, `all`, ou valeurs inconnues : on ne
/// risque jamais de laisser une commande sans téléphone).
List<OrderRoute>? routesForHandles(List<String> handles) {
  final Set<String> h =
      handles.map((String e) => e.trim().toLowerCase()).toSet();
  if (h.isEmpty || h.contains('all')) return null;
  // [CONFIG SIM 29/10/2026] Téléphone non configuré : n'écoute rien.
  if (h.contains('none')) return const <OrderRoute>[];
  // L'écran Serveurs écrit aussi les sous-types MTN : ils relèvent de
  // `mtn_forfait` (même SIM, même menu).
  if (h.remove('mtn_forfait_activate') | h.remove('mtn_bundle')) {
    h.add('mtn_forfait');
  }
  if (h.remove('orange_forfait_activate')) h.add('orange_forfait');
  if (h.any((String e) => !kOperationTypes.contains(e))) return null;
  final List<OrderRoute> routes = <OrderRoute>[];
  if (h.contains('camtel_pre')) {
    routes.add(const OrderRoute(<String>['1', '9', '11']));
  }
  if (h.contains('camtel_post')) {
    routes.add(const OrderRoute(<String>['6', '9']));
  }
  if (h.contains('mtn_airtime')) {
    routes.add(const OrderRoute(<String>['1', '11'], 'mtn_airtime'));
  }
  if (h.contains('mtn_forfait')) {
    routes.add(const OrderRoute(<String>['0'], 'mtn_forfait'));
    routes.add(const OrderRoute(<String>['1', '11'], 'mtn_forfait_activate'));
    // [CATALOGUE 29/10/2026] Forfaits MTN du catalogue : même SIM, même menu.
    routes.add(const OrderRoute(<String>['1', '11'], 'mtn_bundle'));
  }
  // [ORANGE 30/10/2026] Le flow USSD Orange n'est pas encore branché. Un
  // téléphone qui ne saurait pas livrer ne doit surtout PAS réserver la
  // commande : elle finirait en échec alors que le client a payé. On ignore
  // donc les types Orange tant que `OrangeUssdManager.deliveryImplemented` est
  // faux ; les commandes restent au statut « payée, à livrer » (1) et
  // l'administrateur les traite à la main. Le jour où le flow est fourni, la
  // constante passe à vrai et tout s'active sans autre modification.
  const bool orangePret = OrangeUssdManager.deliveryImplemented;
  if (orangePret && h.contains('orange_airtime')) {
    routes.add(const OrderRoute(<String>['1', '11'], 'orange_airtime'));
  }
  if (orangePret && h.contains('orange_forfait')) {
    routes.add(const OrderRoute(<String>['0'], 'orange_forfait'));
    routes
        .add(const OrderRoute(<String>['1', '11'], 'orange_forfait_activate'));
  }
  // Téléphone dédié Orange (tous ses handles ignorés) : `routes` est vide. On
  // renvoie une liste VIDE = « n'écoute rien ». Renvoyer `null` signifierait
  // « toutes les commandes », donc voler les commandes CAMTEL/MTN des autres
  // téléphones — inacceptable.
  if (routes.isEmpty && (h.contains('orange_airtime') || h.contains('orange_forfait'))) {
    return const <OrderRoute>[];
  }
  return routes.isEmpty ? null : routes;
}

/// [28/10/2026] Montant minimal accepté par les opérateurs (MTN, Orange,
/// Blue/CAMTEL) : 100 F. En dessous, l'USSD aboutit à un refus : mieux vaut
/// ne jamais lancer la session et le dire clairement.
const int kMinRechargeAmount = 100;

/// Vrai si [amount] (nombre ou texte) atteint le minimum opérateur.
bool isAmountAllowed(Object? amount) {
  final int? v = amount is num
      ? amount.toInt()
      : int.tryParse(
          (amount?.toString() ?? '').replaceAll(RegExp(r'[^0-9]'), ''));
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
    case 'mtn_bundle':
      return '1';
    case 'mtn_forfait':
    case 'orange_forfait':
      // Requête gratuite de la liste d'offres (aucun paiement).
      return '0';
    case 'orange_forfait_activate':
      return '1';
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
  if ((data['relance_demandee'] as Object?) == true) {
    return false; // déjà demandée
  }
  return relaunchStatusFor(data) != null;
}

/// Réponse USSD CAMTEL indiquant que le transfert de crédit a été accepté
/// (texte réellement renvoyé par CAMTEL, faute de frappe comprise).
bool isCamtelTransferAccepted(String ussdText) {
  final String t = ussdText.toLowerCase();
  return t.contains('processing your requestion') ||
      t.contains('processing your request');
}
