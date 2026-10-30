/// [SUPABASE 29/10/2026] Configuration du projet Supabase de Recharge237.
///
/// À remplir depuis le tableau de bord Supabase : Project Settings > API
/// (ou « Connect ») :
///  - [supabaseUrl]     : « Project URL », ex. https://abcdefgh.supabase.co
///  - [supabaseAnonKey] : clé « anon » / « publishable » (PUBLIQUE, faite pour
///    être dans l'app ; la sécurité vient des règles RLS des tables).
///
/// Ne JAMAIS mettre ici la clé « service_role » / « secret » : elle donne
/// tous les droits sur la base.
///
/// Tant que ces deux valeurs sont vides, Supabase reste DÉSACTIVÉ et l'app
/// fonctionne exactement comme avant, uniquement avec Firebase.
class SupabaseConfig {
  SupabaseConfig._();

  static const String supabaseUrl = 'https://zdiuaowpigcdvjgguhox.supabase.co';
  static const String supabaseAnonKey =
      'sb_publishable_hldgRfR4XbVlXn5BqjVS4g_NGkkNoD0';

  static bool get configured =>
      supabaseUrl.startsWith('https://') && supabaseAnonKey.isNotEmpty;
}
