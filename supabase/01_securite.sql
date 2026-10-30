-- ============================================================================
-- Recharge237 — Sécurité de la base Supabase (29/10/2026)
-- À exécuter UNE fois dans Supabase > SQL Editor, AVANT de créer des tables.
--
-- Principe (équivalent des règles Firestore) : la clé « publishable » est
-- publique — elle est dans les apps, donc lisible par n'importe qui. Ce qui
-- protège la base, ce sont les règles RLS (Row Level Security) : une table
-- avec RLS et sans règle est TOTALEMENT fermée à cette clé. On n'ouvre
-- ensuite que le strict nécessaire, table par table.
-- ============================================================================

-- 1. Filet de sécurité : toute nouvelle table du schéma public naît avec RLS
--    activé. Un oubli ne peut plus exposer une table à tout Internet.
create or replace function public.r237_rls_automatique()
returns event_trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  cmd record;
begin
  for cmd in
    select * from pg_event_trigger_ddl_commands()
    where command_tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      and object_type in ('table', 'partitioned table')
      and schema_name = 'public'
  loop
    execute format('alter table %s enable row level security', cmd.object_identity);
  end loop;
end;
$$;

drop event trigger if exists r237_rls_automatique;
create event trigger r237_rls_automatique
  on ddl_command_end
  when tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
  execute function public.r237_rls_automatique();

-- La fonction ne doit pas être appelable depuis l'API.
revoke all on function public.r237_rls_automatique() from public, anon, authenticated;

-- 2. Rattrapage : RLS sur toutes les tables déjà présentes dans public.
do $$
declare
  t record;
begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('alter table public.%I enable row level security', t.tablename);
  end loop;
end;
$$;

-- 3. Catalogue des forfaits : lecture publique, AUCUNE écriture via l'API.
--    (Les mises à jour passent par le script d'import du PC, avec la clé
--    secrète qui ne quitte jamais le PC.)
create table if not exists public.forfaits (
  id            text primary key,
  code          text,
  source_code   text,
  nom           text not null,
  description   text,
  montant       integer not null check (montant > 0),
  volume_data   text,
  validite      text,
  operateur     text not null,
  categorie     text,
  disponible    boolean not null default true,
  mis_a_jour    timestamptz not null default now()
);
alter table public.forfaits enable row level security;

drop policy if exists "catalogue lisible par tous" on public.forfaits;
create policy "catalogue lisible par tous"
  on public.forfaits for select
  to anon, authenticated
  using (true);

-- Écriture, modification, suppression : aucune règle = refusé.
revoke insert, update, delete, truncate on public.forfaits from anon, authenticated;

-- 4. Vérification : toutes les tables de public doivent afficher rls = true.
select tablename, rowsecurity as rls
from pg_tables
where schemaname = 'public'
order by tablename;
