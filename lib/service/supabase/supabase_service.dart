import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';

/// [SUPABASE 29/10/2026] Accès à la base PostgreSQL Supabase de Recharge237.
///
/// Rôle : décharger Firebase de ce qui n'a pas besoin d'y être (catalogue des
/// forfaits, journaux, télémétrie des téléphones serveurs…) pour garder le
/// quota Firestore aux commandes. Cf. docs/SUPABASE_STRATEGIE.md.
///
/// Règles de prudence, valables pour tout appel :
///  - jamais bloquant : chaque méthode est bornée dans le temps ;
///  - jamais fatal : une erreur Supabase rend `null` / `false`, et l'appelant
///    garde son chemin Firebase habituel ;
///  - désactivé tant que [SupabaseConfig] n'est pas rempli.
class SupabaseService {
  SupabaseService._();
  static final SupabaseService instance = SupabaseService._();

  static const Duration _delai = Duration(seconds: 10);

  bool _pret = false;

  /// Vrai si Supabase est configuré ET initialisé.
  bool get disponible => _pret;

  SupabaseClient? get client => _pret ? Supabase.instance.client : null;

  /// À appeler une fois au démarrage, après Firebase. Ne lève jamais.
  Future<void> init() async {
    if (_pret) return;
    if (!SupabaseConfig.configured) {
      debugPrint('[Supabase] non configuré — Firebase seul');
      return;
    }
    try {
      await Supabase.initialize(
        url: SupabaseConfig.supabaseUrl,
        anonKey: SupabaseConfig.supabaseAnonKey,
      ).timeout(_delai);
      _pret = true;
      debugPrint('[Supabase] prêt');
    } catch (e) {
      debugPrint('[Supabase] initialisation impossible : $e — Firebase seul');
    }
  }

  /// Lit une table (lecture publique, ex. catalogue). `null` = indisponible :
  /// l'appelant retombe alors sur Firestore.
  Future<List<Map<String, dynamic>>?> lire(
    String table, {
    String colonnes = '*',
    Map<String, Object>? egal,
    String? trierPar,
    bool croissant = true,
    int? limite,
  }) async {
    final SupabaseClient? c = client;
    if (c == null) return null;
    try {
      dynamic q = c.from(table).select(colonnes);
      egal?.forEach((String k, Object v) => q = q.eq(k, v));
      if (trierPar != null) q = q.order(trierPar, ascending: croissant);
      if (limite != null) q = q.limit(limite);
      final dynamic res = await (q as Future<dynamic>).timeout(_delai);
      return (res as List<dynamic>)
          .map((dynamic e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (e) {
      debugPrint('[Supabase] lecture $table impossible : $e');
      return null;
    }
  }

  /// Ajoute une ligne (journaux, télémétrie). `false` = non écrit : à
  /// l'appelant de décider s'il retombe sur Firestore ou abandonne.
  Future<bool> ajouter(String table, Map<String, dynamic> ligne) async {
    final SupabaseClient? c = client;
    if (c == null) return false;
    try {
      await c.from(table).insert(ligne).timeout(_delai);
      return true;
    } catch (e) {
      debugPrint('[Supabase] écriture $table impossible : $e');
      return false;
    }
  }

  /// Insère ou remplace une ligne selon sa clé (ex. état d'un téléphone).
  Future<bool> remplacer(
    String table,
    Map<String, dynamic> ligne, {
    String cle = 'id',
  }) async {
    final SupabaseClient? c = client;
    if (c == null) return false;
    try {
      await c.from(table).upsert(ligne, onConflict: cle).timeout(_delai);
      return true;
    } catch (e) {
      debugPrint('[Supabase] remplacement $table impossible : $e');
      return false;
    }
  }
}
