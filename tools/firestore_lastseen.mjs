// [30/10/2026] Lecture de `servers/{deviceId}.lastSeen` depuis le PC.
//
// C'est la SOURCE DE VÉRITÉ du battement de cœur : l'app écrit ce champ (cf.
// `ServerManager.ecritureInterval`, toutes les 30 min). Les scripts du PC ont
// besoin de son âge pour décider si un téléphone est muet — ou, pour le
// maintien en vie, s'il faut le relancer (seuil 3 900 s, cf. `keepalive.mjs`).
//
// Pourquoi c'est le PC qui regarde : quand la base refuse (quota
// `RESOURCE_EXHAUSTED`), le téléphone ne peut plus RIEN écrire, donc il ne
// peut pas signaler non plus qu'il est muet. C'est le seul angle mort du
// système, et il faut le voir depuis l'extérieur.
//
// Aucune dépendance : Node 18+ suffit (fetch + crypto natifs).
//
// ── Requiert une service account ────────────────────────────────────────────
// `firestore.rules` exige `request.auth != null` partout, et les règles ne
// s'appliquent PAS aux service accounts : c'est le seul moyen pour le PC de
// lire un document. Une clé se crée une fois dans la console Firebase :
//   Paramètres du projet > Comptes de service > Générer une clé privée
// Puis, soit :
//   export GOOGLE_APPLICATION_CREDENTIALS="/chemin/vers/compte-service.json"
// soit (plus simple, jamais versionné) déposer le fichier :
//   tools/service-account.json
//
// ── Usage ───────────────────────────────────────────────────────────────────
//   node tools/firestore_lastseen.mjs 197c981ceb311c20
//     -> AGE 245            (secondes écoulées depuis le dernier battement)
//     -> ETAT sans-cle       (aucune service account trouvée)
//     -> ETAT abscent        (le document servers/{id} n'existe pas)
//     -> ETAT refuse         (droits insuffisants)
//     -> ETAT injoignable    (réseau, ou quota épuisé côté PC)
//
// Code retour : 0 = âge lu, 2 = état non résolu.

import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

/// Projet Firebase réel de l'app (cf. lib/main.dart — pas `bdtestserveur`,
/// qui est celui du vieux google-services.json).
export const PROJET = process.env.FIREBASE_PROJECT ?? 'recharge237-r237';

const DOSSIER = path.dirname(fileURLToPath(import.meta.url));

/// Emplacement de la clé, par ordre de priorité.
export const CHEMIN_CLE =
    process.env.GOOGLE_APPLICATION_CREDENTIALS ??
    path.join(DOSSIER, 'service-account.json');

let _jeton = null;

/// La service account est-elle fournie ?
export function cleDisponible() {
  return fs.existsSync(CHEMIN_CLE);
}

function base64url(valeur) {
  return Buffer.from(valeur).toString('base64url');
}

/// Obtient (et mémoïse pendant ~1 h) un jeton d'accès OAuth2.
///
/// Renvoie `null` quand aucune clé n'est trouvée : l'appelant doit alors se
/// contenter d'un état « sans-cle », JAMAIS inventer un âge.
async function jeton() {
  if (_jeton && Date.now() < _jeton.expire - 60_000) return _jeton.valeur;

  let compte;
  try {
    compte = JSON.parse(fs.readFileSync(CHEMIN_CLE, 'utf8'));
  } catch (_) {
    return null;
  }
  if (!compte.private_key || !compte.client_email) return null;

  const maintenant = Math.floor(Date.now() / 1000);
  const entete = base64url(JSON.stringify({alg: 'RS256', typ: 'JWT'}));
  const charge = base64url(JSON.stringify({
    iss: compte.client_email,
    scope: 'https://www.googleapis.com/auth/datastore',
    aud: 'https://oauth2.googleapis.com/token',
    iat: maintenant,
    exp: maintenant + 3600,
  }));
  const signe = crypto
      .sign('RSA-SHA256', Buffer.from(`${entete}.${charge}`), compte.private_key)
      .toString('base64url');
  const assertion = `${entete}.${charge}.${signe}`;

  const reponse = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: {'content-type': 'application/x-www-form-urlencoded'},
    body: new URLSearchParams({
      grant_type: 'jwt-bearer',
      assertion,
    }),
  });
  if (!reponse.ok) {
    throw new Error(`oauth ${reponse.status} ${await reponse.text()}`);
  }
  const corps = await reponse.json();
  _jeton = {
    valeur: corps.access_token,
    expire: maintenant + (corps.expires_in ?? 3600),
  };
  return _jeton.valeur;
}

/// Âge du battement de CE téléphone, en secondes.
///
/// Renvoie toujours `{etat}` ; `age` n'est présent que si la valeur a
/// réellement été lue — l'appelant doit refuser de conclure sans `age`.
///
/// états : sans-cle | injoignable | refuse | absent | sans-champ | lu
export async function ageLastSeen(deviceId) {
  if (!cleDisponible()) return {etat: 'sans-cle'};

  let temoin;
  try {
    temoin = await jeton();
  } catch (e) {
    return {etat: 'injoignable', detail: String(e?.message ?? e)};
  }
  if (!temoin) return {etat: 'sans-cle'};

  // `mask` limite la lecture au seul champ demandé.
  const url =
      `https://firestore.googleapis.com/v1/projects/${PROJET}` +
      `/databases/(default)/documents/servers/${encodeURIComponent(deviceId)}` +
      '?mask=lastSeen';

  let reponse;
  try {
    reponse = await fetch(url, {
      headers: {authorization: `Bearer ${temoin}`},
    });
  } catch (e) {
    return {etat: 'injoignable', detail: String(e?.message ?? e)};
  }

  if (reponse.status === 404) return {etat: 'absent'};
  if (reponse.status === 401 || reponse.status === 403) {
    return {etat: 'refuse', detail: `HTTP ${reponse.status}`};
  }
  if (reponse.status === 429 || reponse.status >= 500) {
    // Surtout 429 : quota épuisé. À ne JAMAIS confondre avec « muet ».
    return {etat: 'injoignable', detail: `HTTP ${reponse.status}`};
  }
  if (!reponse.ok) {
    return {etat: 'injoignable', detail: `HTTP ${reponse.status}`};
  }

  let corps;
  try {
    corps = await reponse.json();
  } catch (_) {
    return {etat: 'injoignable', detail: 'réponse illisible'};
  }

  const brut = corps?.fields?.lastSeen;
  const iso = brut?.timestampValue ?? brut?.stringValue ?? null;
  if (!iso) return {etat: 'sans-champ'};

  const quand = Date.parse(iso);
  if (Number.isNaN(quand)) return {etat: 'sans-champ'};

  return {etat: 'lu', age: Math.max(0, Math.round((Date.now() - quand) / 1000))};
}

// ── CLI : vérification manuelle ─────────────────────────────────────────────
const moi = process.argv[1] && path.resolve(process.argv[1]);
if (moi && moi === path.resolve(fileURLToPath(import.meta.url))) {
  const cible = process.argv[2];
  if (!cible) {
    console.error('usage : node tools/firestore_lastseen.mjs <deviceId>');
    process.exit(2);
  }
  const resultat = await ageLastSeen(cible);
  if (resultat.etat === 'lu') {
    console.log(`AGE ${resultat.age}`);
    process.exit(0);
  }
  const detail = resultat.detail ? ` — ${resultat.detail}` : '';
  console.log(`ETAT ${resultat.etat}${detail}`);
  process.exit(2);
}
