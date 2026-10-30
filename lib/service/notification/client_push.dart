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

  /// [RELANCES 31/10/2026] Rappel « votre forfait expire » (J-3, J-2, J-1, J-0).
  ///
  /// Ciblage : l'ABONNEMENT push de l'appareil (`pushId`, écrit par le registre
  /// des appareils) est préféré à l'alias `external_id`. Raison : le site web
  /// n'appelle jamais `OneSignal.login` — il n'a donc aucune identité externe,
  /// seulement un abonnement. Un visiteur du site ne serait jamais joignable
  /// par alias. Repli sur l'uid quand l'abonnement n'est pas encore connu (app
  /// mobile qui vient d'être installée, permission accordée plus tard).
  ///
  /// Rend `true` seulement si OneSignal a accepté la notification : le job de
  /// relance s'en sert pour libérer sa réservation et réessayer plus tard.
  static Future<bool> rappelForfait({
    required String uid,
    required String pushId,
    required int jours,
    String offre = '',
    String numero = '',
    String orderId = '',
  }) async {
    if (!await _charger()) return false;

    final String titre = switch (jours) {
      3 => 'Il vous reste 3 jours de forfait',
      2 => 'Plus que 2 jours de forfait',
      1 => 'Votre forfait expire demain',
      _ => 'Votre forfait est arrivé à expiration',
    };
    final String corps = switch (jours) {
      3 => 'Évitez la panne de connexion, rechargez dès maintenant sur Recharge237.',
      2 => 'Pensez à renouveler pour ne pas perdre votre connexion.',
      1 => 'Renouvelez en 1 clic sur Recharge237, avant la coupure.',
      _ => 'Rechargez instantanément sur Recharge237.',
    };

    // Contexte utile au client : quelle offre, sur quelle ligne.
    final StringBuffer texte = StringBuffer(corps);
    if (offre.trim().isNotEmpty) {
      texte.write(' (offre « ${offre.trim()} »');
      texte.write(numero.trim().isEmpty ? ')' : ', ligne ${numero.trim()})');
    } else if (numero.trim().isNotEmpty) {
      texte.write(' Ligne ${numero.trim()}.');
    }

    final Map<String, dynamic> payload = <String, dynamic>{
      'app_id': _appId,
      'headings': <String, String>{'fr': titre, 'en': titre},
      'contents': <String, String>{'fr': texte.toString(), 'en': texte.toString()},
      'data': <String, String>{
        'type': 'forfait_expiry',
        'jours': jours.toString(),
        if (orderId.isNotEmpty) 'order': orderId,
      },
    };
    if (pushId.trim().isNotEmpty) {
      payload['include_subscription_ids'] = <String>[pushId.trim()];
    } else {
      payload['include_aliases'] = <String, dynamic>{
        'external_id': <String>[uid.trim()],
      };
      payload['target_channel'] = 'push';
    }

    try {
      final http.Response r = await http
          .post(
            Uri.parse('https://onesignal.com/api/v1/notifications'),
            headers: <String, String>{
              'Content-Type': 'application/json; charset=utf-8',
              'Authorization': 'Key $_restKey',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 15));
      debugPrint('[ClientPush] rappel J-$jours ${pushId.isEmpty ? uid : pushId} '
          '→ ${r.statusCode}'
          '${r.statusCode >= 300 ? ' ${r.body}' : ''}');
      return r.statusCode >= 200 && r.statusCode < 300;
    } catch (e) {
      debugPrint('[ClientPush] rappel forfait impossible : $e');
      return false;
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
