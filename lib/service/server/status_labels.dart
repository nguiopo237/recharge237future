import 'package:flutter/material.dart';

/// Référentiel unique des statuts `Transact` côté serveur.
///
/// Avant, l'app ne connaissait que `0/1/2/3/9/10` : tout le reste — dont tous
/// les statuts MTN ajoutés avec la livraison automatisée — tombait dans un
/// libellé générique « en attente de validation », y compris une recharge
/// réellement livrée. Fonction pure : testée dans
/// test/server_status_test.dart.
enum StatusKind { waiting, processing, success, failed, neutral }

class ServerStatusInfo {
  final String label;
  final Color color;
  final IconData icon;
  final StatusKind kind;

  const ServerStatusInfo(this.label, this.color, this.icon, this.kind);

  bool get isPending =>
      kind == StatusKind.waiting || kind == StatusKind.processing;
  bool get isSuccess => kind == StatusKind.success;
  bool get isFailure => kind == StatusKind.failed;
}

// Palette alignée sur l'app cliente (AppTheme) pour rester cohérent.
const _blue = Color(0xFF006CD9);
const _navy = Color(0xFF06294D);
const _green = Color(0xFF16A34A);
const _red = Color(0xFFD90200);
const _amber = Color(0xFFB45309);
const _grey = Color(0xFF64748B);
const _orange = Color(0xFFEA7A20);

ServerStatusInfo serverStatusInfo(Object? rawStatus) {
  final String s = (rawStatus ?? '').toString().trim();
  switch (s) {
    // ── Cycle client (paiement) ────────────────────────────────────────────
    case '0':
      return const ServerStatusInfo('En attente de paiement', _amber,
          Icons.schedule_rounded, StatusKind.waiting);
    case '1':
      return const ServerStatusInfo(
          'À livrer', _blue, Icons.bolt_rounded, StatusKind.processing);
    case '2':
      return const ServerStatusInfo('En cours de livraison', _blue,
          Icons.sync_rounded, StatusKind.processing);
    case '3':
      return const ServerStatusInfo(
          'Livré', _green, Icons.check_circle_rounded, StatusKind.success);
    case '4':
      return const ServerStatusInfo(
          'Échec', _red, Icons.error_rounded, StatusKind.failed);

    // ── CAMTEL ────────────────────────────────────────────────────────────
    case '6':
      return const ServerStatusInfo('CAMTEL postpayé', _blue,
          Icons.account_balance_rounded, StatusKind.processing);
    case '9':
      return const ServerStatusInfo('SIM post en cours', _blue,
          Icons.sim_card_rounded, StatusKind.processing);
    case '10':
      return const ServerStatusInfo('SIM rechargée', _green,
          Icons.check_circle_rounded, StatusKind.success);
    case '11':
      return const ServerStatusInfo('Activé (point de vente)', _green,
          Icons.storefront_rounded, StatusKind.success);
    case '12':
      return const ServerStatusInfo(
          'CAMTEL en cours', _blue, Icons.sync_rounded, StatusKind.processing);
    case '5':
      return const ServerStatusInfo('Forfait activé (admin)', _green,
          Icons.card_giftcard_rounded, StatusKind.success);
    case '8':
      return const ServerStatusInfo(
          'Traité par SMS', _blue, Icons.sms_rounded, StatusKind.success);

    // ── MTN crédit ────────────────────────────────────────────────────────
    case '20':
      return const ServerStatusInfo('MTN — crédit en cours', _blue,
          Icons.sync_rounded, StatusKind.processing);
    case '21':
      return const ServerStatusInfo('MTN — crédit livré', _green,
          Icons.check_circle_rounded, StatusKind.success);
    case '22':
      return const ServerStatusInfo(
          'MTN — échec', _red, Icons.error_rounded, StatusKind.failed);

    // ── MTN Good Deal / forfaits ──────────────────────────────────────────
    case '30':
      return const ServerStatusInfo('MTN — offres en cours', _blue,
          Icons.downloading_rounded, StatusKind.processing);
    case '31':
      return const ServerStatusInfo('MTN — offres prêtes', _green,
          Icons.list_alt_rounded, StatusKind.success);
    case '32':
      return const ServerStatusInfo('MTN — offres indisponibles', _red,
          Icons.error_rounded, StatusKind.failed);
    case '33':
      return const ServerStatusInfo(
          'MTN — activation', _blue, Icons.sync_rounded, StatusKind.processing);
    case '34':
      return const ServerStatusInfo('MTN — forfait activé', _green,
          Icons.check_circle_rounded, StatusKind.success);
    case '35':
      return const ServerStatusInfo('MTN — activation échouée', _red,
          Icons.error_rounded, StatusKind.failed);

    // ── Orange / à venir ──────────────────────────────────────────────────
    case '40':
      return const ServerStatusInfo('Orange — en cours', _orange,
          Icons.sync_rounded, StatusKind.processing);
    case '41':
      return const ServerStatusInfo('Orange — livré', _green,
          Icons.check_circle_rounded, StatusKind.success);
    case '42':
      return const ServerStatusInfo(
          'Orange — échec', _red, Icons.error_rounded, StatusKind.failed);

    default:
      return ServerStatusInfo(s.isEmpty ? 'Statut inconnu' : 'Statut $s', _grey,
          Icons.help_outline_rounded, StatusKind.neutral);
  }
}

/// Nom de l'opérateur visé par une commande.
///
/// `operateur_cible` fait foi quand il est présent (c'est ce que le serveur a
/// réellement exécuté) ; sinon on déduit du préfixe du numéro cible.
String operatorLabel(Map<String, dynamic> data) {
  final String cible = (data['operateur_cible'] ?? '').toString().toLowerCase();
  if (cible.startsWith('mtn')) return 'MTN';
  if (cible.startsWith('orange')) return 'Orange';
  if (cible.startsWith('camtel')) return 'CAMTEL';

  final String num = (data['numerocamtel'] ?? data['numerorecharge'] ?? '')
      .toString()
      .replaceAll(RegExp(r'[^0-9]'), '');
  final String local = num.length >= 9 ? num.substring(num.length - 9) : num;
  if (RegExp(r'^(62|24[23])').hasMatch(local)) return 'CAMTEL';
  if (RegExp(r'^(67|65[0-4]|68[0-4])').hasMatch(local)) return 'MTN';
  if (RegExp(r'^(69|65[5-9])').hasMatch(local)) return 'Orange';
  return '—';
}

/// Couleur d'identification de l'opérateur (badge de la carte).
Color operatorColor(String operator) {
  switch (operator) {
    case 'MTN':
      return const Color(0xFFF0C000);
    case 'Orange':
      return _orange;
    case 'CAMTEL':
      return _navy;
    default:
      return _grey;
  }
}
