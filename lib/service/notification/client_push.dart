import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// [OFFRES ASYNC 29/10/2026] Notification push envoyée au CLIENT par le
/// serveur, via l'API REST OneSignal (aucune Cloud Function : plan Spark).
///
/// Sert au parcours Good Deal / Boost MTN : le client lance la recherche,
/// ferme l'app, et reçoit « Vos offres MTN sont prêtes 🎁 » (ou « MTN n'a pas
/// répondu »). L'app associe chaque appareil à l'uid du client
/// (`OneSignal.login(uid)`), et chaque commande porte cet uid (`idphone`).
///
/// Identifiants lus une fois par démarrage : `app_config/public`
/// (`onesignal_app_id`) et `admin_secrets/api_keys`
/// (`onesignal_rest_api_key`) — le téléphone serveur est admin.
/// Best-effort : un échec n'affecte jamais la commande.
class ClientPush {
  ClientPush._();

  static String? _appId;
  static String? _restKey;

  static Future<bool> _charger() async {
    if (_appId != null && _restKey != null) return true;
    try {
      final FirebaseFirestore db = FirebaseFirestore.instance;
      final pub = await db.collection('app_config').doc('public').get();
      String appId = (pub.data()?['onesignal_app_id'] ?? '').toString().trim();
      if (appId.isEmpty) {
        final legacy = await db.collection('app_config').doc('api_keys').get();
        appId = (legacy.data()?['onesignal_app_id'] ?? '').toString().trim();
      }
      final sec = await db.collection('admin_secrets').doc('api_keys').get();
      final String key =
          (sec.data()?['onesignal_rest_api_key'] ?? '').toString().trim();
      if (appId.isEmpty || key.isEmpty) {
        debugPrint(
            '[ClientPush] identifiants OneSignal absents : push désactivé');
        return false;
      }
      _appId = appId;
      _restKey = key;
      return true;
    } catch (e) {
      debugPrint('[ClientPush] lecture des identifiants impossible : $e');
      return false;
    }
  }

  /// [CATALOGUE 29/10/2026] Résultat de l'activation d'un forfait payé.
  static Future<void> forfait(
      {required String docId, required bool active}) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('Transact')
          .doc(docId)
          .get();
      final Map<String, dynamic> d = doc.data() ?? <String, dynamic>{};
      final String uid = (d['idphone'] ?? '').toString().trim();
      final String numero = (d['numerocamtel'] ?? '').toString().trim();
      if (uid.isEmpty || uid == '00000') return;
      if (!await _charger()) return;
      final String titre = active ? 'Forfait activé ✅' : 'Forfait non activé';
      final String texte = active
          ? 'Votre forfait est actif sur le $numero.'
          : 'L’activation sur le $numero n’a pas abouti. Notre équipe s’en occupe.';
      await _envoyer(uid, titre, texte, <String, String>{
        'type': 'forfait',
        'order': (d['order'] ?? '').toString(),
      });
    } catch (e) {
      debugPrint('[ClientPush] envoi impossible : $e');
    }
  }

  static Future<void> _envoyer(
      String uid, String titre, String texte, Map<String, String> data) async {
    final http.Response r = await http
        .post(
          Uri.parse('https://onesignal.com/api/v1/notifications'),
          headers: <String, String>{
            'Content-Type': 'application/json; charset=utf-8',
            'Authorization': 'Key $_restKey',
          },
          body: jsonEncode(<String, dynamic>{
            'app_id': _appId,
            'include_aliases': <String, dynamic>{
              'external_id': <String>[uid]
            },
            'target_channel': 'push',
            'headings': <String, String>{'fr': titre, 'en': titre},
            'contents': <String, String>{'fr': texte, 'en': texte},
            'data': data,
          }),
        )
        .timeout(const Duration(seconds: 15));
    debugPrint('[ClientPush] ${data['type']} ${data['order']} → ${r.statusCode}'
        '${r.statusCode >= 300 ? ' ${r.body}' : ''}');
  }

  /// Prévient le client que sa recherche d'offres MTN est terminée.
  ///
  /// [pretes] : `true` si la liste est disponible, `false` si MTN n'a pas
  /// répondu. [nombre] : nombre d'offres trouvées (0 = aucune offre).
  static Future<void> offresMtn({
    required String docId,
    required bool pretes,
    int nombre = 0,
  }) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('Transact')
          .doc(docId)
          .get();
      final Map<String, dynamic> d = doc.data() ?? <String, dynamic>{};
      final String uid = (d['idphone'] ?? '').toString().trim();
      final String order = (d['order'] ?? '').toString().trim();
      final String numero = (d['numerocamtel'] ?? '').toString().trim();
      if (uid.isEmpty || uid == '00000' || order.isEmpty) return;
      if (!await _charger()) return;

      final String titre = !pretes
          ? 'MTN n’a pas répondu'
          : nombre == 0
              ? 'Aucune offre MTN pour le moment'
              : 'Vos offres MTN sont prêtes 🎁';
      final String texte = !pretes
          ? 'La recherche pour le $numero n’a pas abouti. Touchez pour réessayer, c’est gratuit.'
          : nombre == 0
              ? 'MTN ne propose pas d’offre pour le $numero en ce moment.'
              : '$nombre offre${nombre > 1 ? 's' : ''} pour le $numero. Touchez pour choisir la vôtre.';

      final http.Response r = await http
          .post(
            Uri.parse('https://onesignal.com/api/v1/notifications'),
            headers: <String, String>{
              'Content-Type': 'application/json; charset=utf-8',
              'Authorization': 'Key $_restKey',
            },
            body: jsonEncode(<String, dynamic>{
              'app_id': _appId,
              'include_aliases': <String, dynamic>{
                'external_id': <String>[uid],
              },
              'target_channel': 'push',
              'headings': <String, String>{'fr': titre, 'en': titre},
              'contents': <String, String>{'fr': texte, 'en': texte},
              'data': <String, String>{'type': 'mtn_offers', 'order': order},
            }),
          )
          .timeout(const Duration(seconds: 15));
      debugPrint('[ClientPush] offres MTN $order → ${r.statusCode}'
          '${r.statusCode >= 300 ? ' ${r.body}' : ''}');
    } catch (e) {
      debugPrint('[ClientPush] envoi impossible : $e');
    }
  }
}
