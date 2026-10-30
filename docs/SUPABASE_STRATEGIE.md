# Supabase dans l'écosystème Recharge237 — stratégie (29/10/2026)

## Objectif

Garder le quota Firestore (plan gratuit : 50 000 lectures, 20 000 écritures,
20 000 suppressions par jour) pour ce qui en a vraiment besoin — les
**commandes** — et déplacer vers Supabase (PostgreSQL) tout le reste.

## Pourquoi PAS une bascule automatique de tout l'écosystème

« Quand le quota Firebase est fini, tout bascule sur Supabase » paraît simple,
mais pour les commandes cela crée deux bases qui divergent :

- une commande créée sur Supabase pendant la coupure est invisible pour la
  passerelle de paiement (Cloudflare Worker), les téléphones serveurs, l'écran
  admin et l'historique client, qui lisent Firestore ;
- au retour du quota, il faut fusionner les deux bases sans perdre ni
  doubler une recharge payée (risque de double crédit) ;
- l'authentification, les règles de sécurité et les écoutes temps réel
  devraient exister en double et rester identiques.

Pour ne jamais être bloqué par le quota, la solution fiable est le **plan
Blaze** (le quota gratuit reste offert ; on ne paie que le dépassement, de
l'ordre de quelques dollars par mois à 10 000 commandes/jour). Supabase sert à
**réduire durablement** la consommation, données par données, chacune ayant
UNE seule base de référence.

## Ce qui est en place (étape 0)

Dans les trois apps (mobile, web, serveur) :

- paquet `supabase_flutter` dans `pubspec.yaml` ;
- `lib/service/supabase/supabase_config.dart` : URL et clé « anon » à remplir ;
- `lib/service/supabase/supabase_service.dart` : `init()`, `lire()`,
  `ajouter()`, `remplacer()` — jamais bloquant, jamais fatal ;
- initialisation dans `main.dart` juste après Firebase.

Tant que la configuration est vide, rien ne change : Firebase seul.

## Plan de bascule progressif

Chaque étape : (1) créer la table Supabase, (2) écrire dans les DEUX bases
quelques jours, (3) lire Supabase en premier avec repli Firestore,
(4) arrêter l'écriture Firestore. Retour arrière possible à chaque étape.

| Étape | Données | Firestore aujourd'hui | Gain estimé |
|---|---|---|---|
| 1 | Catalogue `Forfait` (80 offres) | lectures clients (cache 6 h) | faible — sert de test sans risque |
| 2 | Télémétrie des téléphones serveurs (`servers` : battement, réseau, santé) | ~50 à 400 écritures/jour/téléphone + lectures de l'écran admin | moyen |
| 3 | Journaux : `sms_operateur`, `soldes`, `reports`, `sales_audit` | 1 à 3 écritures par commande selon les SMS | moyen à fort |
| 4 | Lectures d'analyse (tableau de bord admin, historique 7 jours) via une copie des commandes terminées | lectures massives de `Transact` | fort en lectures |
| 5 | Commandes `Transact` elles-mêmes (option) | ~5 écritures/commande | très fort, mais gros chantier : passerelle, serveurs, règles, temps réel |

L'étape 5 n'est à envisager que si Blaze est exclu : Supabase accepte les
jetons Firebase Auth (« Third-party auth »), ce qui permet de garder les
comptes clients Firebase et d'écrire les règles RLS avec l'UID Firebase.

## Étape 1 — catalogue des forfaits (SQL à exécuter dans Supabase)

À coller dans Supabase > SQL Editor :

```sql
create table if not exists public.forfaits (
  id            text primary key,          -- même id que le document Firestore
  code          text,
  source_code   text,
  nom           text not null,
  description   text,
  montant       integer not null,
  volume_data   text,
  validite      text,
  operateur     text not null,             -- MTN, CAMTEL, ORANGE
  categorie     text,
  disponible    boolean not null default true,
  mis_a_jour    timestamptz not null default now()
);

alter table public.forfaits enable row level security;

-- Lecture publique du catalogue ; aucune écriture depuis les apps.
create policy "catalogue lisible par tous"
  on public.forfaits for select using (true);
```

Ensuite : le script `scripts/import_forfaits.js` alimente aussi cette table,
et `ForfaitControlleur.loadForfaits()` lit `SupabaseService.instance.lire('forfaits')`
en premier, Firestore en repli (le cache local de 6 h est conservé).

## Étape 2 — télémétrie des téléphones serveurs

```sql
create table if not exists public.serveurs_etat (
  device_id     text primary key,
  modele        text,
  statut        text,
  dernier_signe timestamptz,
  internet_ok   boolean,
  reseau_ok     boolean,
  accessibilite boolean,
  details       jsonb,
  mis_a_jour    timestamptz not null default now()
);
alter table public.serveurs_etat enable row level security;
```

Les écritures viennent des téléphones serveurs : avec la clé « anon », il faut
une règle d'insertion/mise à jour restreinte (ou une Edge Function). À décider
au moment de l'étape 2.

## Limites du plan gratuit Supabase (à vérifier sur supabase.com/pricing)

Base de 500 Mo, projet mis en pause après une semaine sans aucune activité,
trafic sortant limité. Pas de limite par nombre de lectures/écritures comme
Firestore : c'est ce qui le rend intéressant pour les journaux.

## Ce qu'il faut fournir

- Project URL et clé « anon / publishable » (Supabase > Project Settings > API)
  à mettre dans `supabase_config.dart` des trois apps ;
- exécuter le SQL de chaque étape dans le SQL Editor (aucune modification de
  base n'est faite sans l'accord de l'admin).

## Sécurité (29/10/2026) — à faire avant toute donnée

1. SQL Editor : exécuter `supabase/01_securite.sql` (RLS automatique sur
   toute nouvelle table, rattrapage des tables existantes, catalogue en
   lecture seule). La dernière requête doit montrer `rls = true` partout.
2. Authentication > Sign In / Providers : **désactiver « Allow new users to
   sign up »** et les connexions anonymes. Les apps n'utilisent pas
   l'authentification Supabase : un attaquant ne doit pas pouvoir se créer
   un compte « authenticated ».
3. Advisors > Security Advisor : doit être sans alerte rouge.
4. Clés : seule la clé `sb_publishable_…` est dans les apps. La clé
   `sb_secret_…` / `service_role` et le mot de passe de la base ne vont
   JAMAIS dans une app ni dans Git — seulement dans les scripts du PC.
5. Database > Backups : vérifier la sauvegarde quotidienne.
