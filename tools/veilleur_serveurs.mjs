#!/usr/bin/env node
// [30/10/2026] Veilleur des téléphones serveurs — surveillance + alertes.
//
// Reprend `tools/_claude_watch_servers.js` (perdu hors du dépôt, son journal
// s'arrête le 29/10 à 18:10) : il disait « OK / MUET depuis X min » et
// prévenait l'admin sur Telegram. Ce fichier n'alerte PAS, ne relance PAS :
// il constate et prévient. La relance appartient à `keepalive.mjs`.
//
// ── Pourquoi 5 min de cadence et 10 min de seuil ───────────────────────────
// L'ancien veilleur tournait toutes les 60 s avec un seuil de 3 min, soit
// 1 440 lectures/jour ET par téléphone rien que pour surveiller — dans un
// projet Spark à 50 000 lectures/jour. Aujourd'hui :
//   - cadence 5 min   -> 288 lectures/jour/téléphone,
//   - seuil 10 min    -> aligné sur `ServerManager._staleAfter` (11 min),
//                         soit bien avant le badge « SILENCIEUX » (65 min)
//                         de l'écran admin.
// On paie cinq fois moins cher pour prévenir cinq fois plus tard — le
// téléphone alerte lui-même en parallèle (HealthWatch, Telegram).
//
// ── Alertes Telegram (facultatif) ───────────────────────────────────────────
// Aucun secret dans le dépôt : fournir les variables soit par l'environnement,
// soit dans `tools/veilleur.env` (ignoré par git), au format `CLE=valeur` :
//
//   TELEGRAM_BOT_TOKEN=123456:ABC...
//   TELEGRAM_CHAT_IDS=7402111158,1470497195
//
// Les mêmes valeurs que `lib/service/sendmail/send_mail.dart`. Sans elles,
// les alertes sont JOURNALISÉES mais pas envoyées — le script tourne quand
// même. Test de l'envoi : TELEGRAM_CHAT_IDS=... TELEGRAM_BOT_TOKEN=... \
//   node tools/veilleur_serveurs.mjs --once --test-telegram
//
// ── Usage ───────────────────────────────────────────────────────────────────
//   node tools/veilleur_serveurs.mjs                boucle toutes les 5 min
//   node tools/veilleur_serveurs.mjs --once         un tour, puis s'arrête
//   node tools/veilleur_serveurs.mjs --devices=id1,id2
//
// Arrêt : Ctrl+C.

import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {ageLastSeen, cleDisponible, CHEMIN_CLE} from './firestore_lastseen.mjs';

// ── Réglages ────────────────────────────────────────────────────────────────

const INTERVALLE_MS = 5 * 60 * 1000;   // cadence de contrôle
const SEUIL_MUET_S = 10 * 60;           // « MUET » au-delà de 10 min

const PAR_DEFAUT = [
  '197c981ceb311c20',
  'f5bf1e4422033950',
  '765de8c91a25f288',
];

// ── Répertoires et entrées ──────────────────────────────────────────────────

const DOSSIER = path.dirname(fileURLToPath(import.meta.url));
const RACINE = path.dirname(DOSSIER);
const JOURNAL = path.join(RACINE, 'logs', 'veilleur_serveurs.log');

const args = process.argv.slice(2);
const ONCE = args.includes('--once');
const TEST_TELEGRAM = args.includes('--test-telegram');
const appareilArg = args.find((a) => a.startsWith('--devices='));
const appareils = appareilArg
    ? appareilArg.slice('--devices='.length).split(',').map((s) => s.trim()).filter(Boolean)
    : PAR_DEFAUT;

// ── Configuration Telegram (jamais versionnée) ──────────────────────────────

function chargerEnvFichier() {
  const fichier = path.join(DOSSIER, 'veilleur.env');
  if (!fs.existsSync(fichier)) return;
  for (const ligne of fs.readFileSync(fichier, 'utf8').split(/\r?\n/)) {
    const m = /^([A-Z_][A-Z0-9_]*)\s*=\s*(.*)$/.exec(ligne.trim());
    if (m && !process.env[m[1]]) process.env[m[1]] = m[2].replace(/^["']|["']$/g, '');
  }
}
chargerEnvFichier();

const TOKEN = process.env.TELEGRAM_BOT_TOKEN ?? '';
const DESTINATAIRES = (process.env.TELEGRAM_CHAT_IDS ?? '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);
const alertesActives = Boolean(TOKEN) && DESTINATAIRES.length > 0;

// ── Journal ─────────────────────────────────────────────────────────────────

function journal(ligne) {
  const d = new Date();
  const deux = (n) => String(n).padStart(2, '0');
  const horodatage =
      `${d.getFullYear()}-${deux(d.getMonth() + 1)}-${deux(d.getDate())} ` +
      `${deux(d.getHours())}:${deux(d.getMinutes())}:${deux(d.getSeconds())}`;
  fs.mkdirSync(path.dirname(JOURNAL), {recursive: true});
  fs.appendFileSync(JOURNAL, `[${horodatage}] ${ligne}\n`, 'utf8');
}

// ── Telegram ────────────────────────────────────────────────────────────────

async function prevenir(texte) {
  if (!alertesActives) {
    journal(`ALERTE (Telegram non configurée) : ${texte.replace(/\n/g, ' | ')}`);
    return;
  }
  let envoyes = 0;
  for (const chatId of DESTINATAIRES) {
    try {
      const r = await fetch(
          `https://api.telegram.org/bot${TOKEN}/sendMessage`, {
            method: 'POST',
            headers: {'content-type': 'application/json'},
            body: JSON.stringify({chat_id: chatId, text: texte}),
          });
      if (r.ok) envoyes += 1;
    } catch (_) {
      // Telegram hors ligne : on ne fait pas échouer la surveillance pour
      // autant, la ligne reste dans le journal.
    }
  }
  journal(`alerte envoyee (${envoyes}/${DESTINATAIRES.length} destinataire(s)) : ` +
      `${texte.replace(/\n/g, ' | ')}`);
}

/** Dernier état notifié par téléphone, pour n'alerter qu'au CHANGEMENT. */
const derniereAlerte = new Map();

// ── Tour ────────────────────────────────────────────────────────────────────

let prevenuSansCle = false;

async function tour() {
  if (!cleDisponible()) {
    // Message unique : répéter toutes les 5 min ne dirait rien de plus.
    if (!prevenuSansCle) {
      prevenuSansCle = true;
      journal(
        `service account absente (${CHEMIN_CLE}) — battement illisible, ` +
        "surveillance DESACTIVÉE. Voir l'en-tête de tools/firestore_lastseen.mjs");
    }
    return;
  }

  for (const deviceId of appareils) {
    const lecture = await ageLastSeen(deviceId);

    if (lecture.etat !== 'lu') {
      // Pas de preuve = pas d'accusation : on ne déclare pas « MUET » un
      // téléphone dont on n'a pas pu lire le battement.
      const detail = lecture.detail ? ` — ${lecture.detail}` : '';
      journal(`${deviceId} : battement illisible (${lecture.etat}${detail}) — aucun verdict`);
      continue;
    }

    const age = lecture.age;
    const muet = age > SEUIL_MUET_S;
    const etat = muet ? 'KO' : 'OK';
    const etatLisible = muet
        ? `MUET depuis ${Math.round(age / 60)} min`
        : `joignable, dernier signal il y a ${Math.round(age / 60)} min`;

    journal(`${etat}   ${deviceId} : ${etatLisible}`);

    if (derniereAlerte.get(deviceId) === etat) continue;
    derniereAlerte.set(deviceId, etat);

    if (muet) {
      await prevenir(
          'Recharge237 — TELEPHONE MUET\n' +
          `Telephone : ${deviceId}\n` +
          `Dernier signal : il y a ${Math.round(age / 60)} min\n` +
          'Verifier : app ouverte ? batterie sans restriction ? base Firestore ?');
    } else if (derniereAlerte.has(deviceId)) {
      // Retour annoncé seulement s'il y avait eu une alerte avant.
      await prevenir(
          'Recharge237 — TELEPHONE REVENU\n' +
          `Telephone : ${deviceId}\n` +
          `Dernier signal : il y a ${Math.round(age / 60)} min`);
    }
  }
}

// ── Démarrage ───────────────────────────────────────────────────────────────

journal(
    `=== veilleur demarre — seuil ${SEUIL_MUET_S / 60} min, controle toutes ` +
    `${INTERVALLE_MS / 60000} min, alertes ` +
    `${alertesActives ? `Telegram (${DESTINATAIRES.length} destinataire(s))` : 'NON configurees'} — ` +
    `${appareils.length} telephone(s) : ${appareils.join(', ')} ===`);

if (TEST_TELEGRAM) {
  await prevenir('Recharge237 — test du veilleur : alerte OK');
  process.exit(0);
}

if (ONCE) {
  await tour();
  process.exit(0);
}

let enCours = false;
const minuteur = setInterval(async () => {
  if (enCours) return;
  enCours = true;
  try {
    await tour();
  } catch (e) {
    journal(`erreur de controle : ${String(e?.message ?? e)}`);
  } finally {
    enCours = false;
  }
}, INTERVALLE_MS);

process.on('SIGINT', () => {
  clearInterval(minuteur);
  journal('=== arret demande ===');
  process.exit(0);
});

await tour();
