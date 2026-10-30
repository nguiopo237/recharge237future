#!/usr/bin/env node
// [30/10/2026] Maintien en vie des téléphones serveurs — version saine.
//
// Remplace `_claude_keepalive.sh`, script perdu hors du dépôt et dont le
// journal témoigne du dysfonctionnement (logs/keepalive.log) :
//
//   [03:49:00] battement fige (162 s) -> relance ; apres relance : 183 s
//   [03:50:23] battement fige (245 s) -> relance ; apres relance : 266 s
//   ... 263 relances, le compteur ne remontant jamais.
//
// Trois défauts, tous réparés ici :
//
//  1. SEUIL. Il relançait dès ~150 s alors que l'app n'ÉCRIT son battement
//     que toutes les 30 min (`ServerManager.ecritureInterval`) et que la
//     documentation annonce un seuil de 3 900 s. Tant que `lastSeen` avait
//     plus de 150 s, il croyait à une panne.
//  2. RELANCE À L'AVEUGLE. Quand Firestore refusait (quota `RESOURCE_
//     EXHAUSTED`), `lastSeen` ne bougeait pas : il prenait donc la
//     CONSÉQUENCE du quota pour une panne de l'app et la « réparait » en
//     relançant, chaque relance coûtant ~35 lectures de plus. Ici, une
//     lecture impossible interdit TOUTE relance — la règle de ce fichier.
//  3. AUCUN PLAFOND. 263 relances sans que personne ne remarque qu'aucune ne
//     fonctionnait. Ici : une relance toutes les 3 900 s au plus, et arrêt
//     définitif après 3 relances restées sans effet.
//
// ── Source du battement ─────────────────────────────────────────────────────
// `tools/firestore_lastseen.mjs` (service account requise, cf. son en-tête).
// Sans clé, le script tourne, journalise l'absence de clé et ne relance RIEN.
// Vérification manuelle, sans rien risquer :
//     node tools/firestore_lastseen.mjs 197c981ceb311c20
//
// ── Usage ───────────────────────────────────────────────────────────────────
//   node tools/keepalive.mjs                 boucle toutes les 5 min
//   node tools/keepalive.mjs --once          un tour, puis s'arrête
//   node tools/keepalive.mjs --no-relance    observation seule
//   node tools/keepalive.mjs --reset         réarme après un arrêt anti-boucle
//   node tools/keepalive.mjs --devices=id1,id2
//
// Arrêt : Ctrl+C. Aucune ressource n'est ouverte en dehors des appels réseau
// et adb.

import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {ageLastSeen, cleDisponible, CHEMIN_CLE} from './firestore_lastseen.mjs';

// ── Réglages ────────────────────────────────────────────────────────────────

/// [SEUIL 3 900 s] Documenté dans `lib/service/server/server_manager.dart` :
/// « relance par le PC après 3 900 s ». 65 min = plus de deux cycles
/// d'écriture manqués (l'app écrit son battement toutes les 30 min) : à ce
/// stade, le téléphone est réellement muet. Un seuil plus court ne fait que
/// confondre « pas encore réécrit » et « plus de battement ».
const SEUIL_RELANCE = 3900; // secondes

/// Cadence de contrôle : 5 min = 288 lectures/jour/téléphone, contre les
/// 1 440/jour de l'ancien veilleur qui tournait toutes les 60 s.
const INTERVALLE_MS = 5 * 60 * 1000;

/// Anti-boucle : après 3 relances qui n'ont pas fait repartir `lastSeen`,
/// on ne relance plus du tout — c'était exactement le bug du 29/10.
const MAX_RELANCES_SANS_EFFET = 3;

const PKG = 'com.recharge237.serveur';

/// Téléphones suivis. `--devices=id1,id2` les remplace pour ce lancement.
const PAR_DEFAUT = [
  '197c981ceb311c20', // téléphone principal (MTN / Camtel)
  'f5bf1e4422033950', // MTN #1
  '765de8c91a25f288',
];

// ── Répertoires ─────────────────────────────────────────────────────────────

const DOSSIER = path.dirname(fileURLToPath(import.meta.url));
const RACINE = path.dirname(DOSSIER);
const JOURNAL = path.join(RACINE, 'logs', 'keepalive.log');
const ETAT_FICHIER = path.join(RACINE, 'logs', 'keepalive.etat.json');

// ── Entrées en ligne de commande ────────────────────────────────────────────

const args = process.argv.slice(2);
const ONCE = args.includes('--once');
const SANS_RELANCE = args.includes('--no-relance');
const appareilArg = args.find((a) => a.startsWith('--devices='));
const appareils = appareilArg
    ? appareilArg.slice('--devices='.length).split(',').map((s) => s.trim()).filter(Boolean)
    : PAR_DEFAUT;

// ── État persistant (anti-boucle) ───────────────────────────────────────────

if (args.includes('--reset')) {
  fs.rmSync(ETAT_FICHIER, {force: true});
}

/** @type {Record<string, {sansEffet:number, arrete:boolean, derniere:number}>} */
let etats = {};
try {
  etats = JSON.parse(fs.readFileSync(ETAT_FICHIER, 'utf8'));
} catch (_) {
  etats = {};
}
for (const id of appareils) {
  etats[id] ??= {sansEffet: 0, arrete: false, derniere: 0};
}
function sauverEtats() {
  fs.mkdirSync(path.dirname(ETAT_FICHIER), {recursive: true});
  fs.writeFileSync(ETAT_FICHIER, JSON.stringify(etats, null, 2), 'utf8');
}

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

// ── adb ─────────────────────────────────────────────────────────────────────

function cheminAdb() {
  if (process.env.ADB) return process.env.ADB;
  const candidats = [
    'C:/Users/wlouo/AppData/Local/Android/Sdk/platform-tools/adb.exe',
    'C:/Users/wlouo/AppData/Local/Android/Sdk/platform-tools/adb',
  ];
  for (const c of candidats) if (fs.existsSync(c)) return c;
  return 'adb';
}
const ADB = cheminAdb();

function adb(serial, commande, timeout = 15000) {
  const r = spawnSync(ADB, ['-s', serial, ...commande], {
    encoding: 'utf8',
    timeout,
    windowsHide: true,
  });
  if (r.error) return {ok: false, texte: String(r.error.message ?? r.error)};
  return {ok: r.status === 0, texte: (r.stdout ?? '').trim()};
}

/// Téléphones connectés ET porteurs de l'app.
function telephones() {
  const liste = spawnSync(ADB, ['devices'], {encoding: 'utf8', timeout: 15000});
  if (liste.error || liste.status !== 0) return {ok: false, serials: []};
  const serials = (liste.stdout ?? '')
      .split('\n')
      .slice(1)
      .map((l) => l.trim())
      .filter((l) => l && /\sdevice$/.test(l))
      .map((l) => l.split(/\s+/)[0]);
  const porteurs = serials.filter((s) =>
    adb(s, ['shell', 'pm', 'list', 'packages', PKG]).texte.includes(PKG));
  return {ok: true, serials: porteurs};
}

/// Apparie un deviceId Android sur un serial adb.
///
/// L'identifiant de l'app (`UniqueIdentifier.serial`) est l'ANDROID_ID : on le
/// compare à celui lu sur chaque téléphone. Un seul téléphone branché => on le
/// prend sans débat, c'est le cas courant (cable USB).
function apparier(deviceId, porteurs) {
  if (porteurs.length === 1) return porteurs[0];
  for (const s of porteurs) {
    const id = adb(s, ['shell', 'settings', 'get', 'secure', 'android_id']);
    if (id.ok && id.texte.trim() === deviceId) return s;
  }
  return null;
}

/// Une session USSD en cours ? Le dialogue appartient au package téléphonie :
/// relancer à ce moment-là couperait une commande déjà payée par le client.
function sessionUssdEnCours(serial) {
  const f = adb(serial, ['shell', 'dumpsys', 'window']);
  if (!f.ok) return true; // doute => on ne touche à rien
  const focus = /mCurrentFocus=Window\{[^}]*\s([^\s/}]+)/.exec(f.texte);
  if (!focus) return false;
  const packageFocalise = focus[1];
  return packageFocalise === 'com.android.phone' ||
         /ussd/i.test(packageFocalise);
}

function relancer(serial) {
  const stop = adb(serial, ['shell', 'am', 'force-stop', PKG]);
  if (!stop.ok) return `force-stop a échoué : ${stop.texte}`;
  const depart = adb(serial, ['shell', 'am', 'start', '-W', '-n', `${PKG}/.MainActivity`]);
  if (!depart.ok) return `démarrage refusé : ${depart.texte}`;
  if (/Error|Exception|not found/i.test(depart.texte)) {
    return `démarrage en erreur : ${depart.texte.slice(0, 120)}`;
  }
  return null;
}

// ── Tour de contrôle ────────────────────────────────────────────────────────

let prevenuSansCle = false;
let prevenuAdb = false;

async function tour() {
  const sansCle = !cleDisponible();
  const {ok, serials} = telephones();

  if (!ok) {
    if (!prevenuAdb) {
      prevenuAdb = true;
      journal('adb indisponible — aucun contrôle, aucune relance');
    }
    return;
  }
  prevenuAdb = false;
  if (serials.length === 0) {
    journal('aucun téléphone joignable par adb — aucun contrôle, aucune relance');
    return;
  }
  if (sansCle && !prevenuSansCle) {
    prevenuSansCle = true;
    journal(
      `service account absente (${CHEMIN_CLE}) — battement illisible, ` +
      'relances DÉSACTIVÉES. Voir l\'en-tête de tools/firestore_lastseen.mjs');
  }
  // Sans clé, il n'y a AUCUNE information à donner tour après tour : le
  // message ci-dessus suffit. On ne remplit pas le journal de lignes vides.
  if (sansCle) return;

  let modifie = false;

  for (const deviceId of appareils) {
    const etat = etats[deviceId];
    if (!etat) continue;

    // 1. Lire le battement. AUCUNE interprétation sans `age`.
    const lecture = sansCle ? {etat: 'sans-cle'} : await ageLastSeen(deviceId);

    if (lecture.etat !== 'lu') {
      // [RÈGLE] Base injoignable / quota refusé / pas de clé : on n'en déduit
      // JAMAIS que l'app est en panne. On attend, on journalise, on ne bouge
      // pas. C'est ce que l'ancien script ne faisait pas.
      const detail = lecture.detail ? ` — ${lecture.detail}` : '';
      journal(`${deviceId} : battement illisible (${lecture.etat}${detail}) — pas de relance`);
      continue;
    }

    const age = lecture.age;

    // 2. Le battement est récent.
    if (age <= SEUIL_RELANCE) {
      if (etat.sansEffet > 0) {
        etat.sansEffet = 0;
        etat.arrete = false;
        modifie = true;
        journal(`${deviceId} : battement reparti (${age} s) — compteur de relances remis à zéro`);
      } else {
        journal(`${deviceId} : vivant (battement ${age} s)`);
      }
      continue;
    }

    // 3. Muet au-delà du seuil.
    if (SANS_RELANCE) {
      journal(`${deviceId} : MUET depuis ${age} s (--no-relance : pas de relance)`);
      continue;
    }
    if (etat.arrete) {
      journal(
        `${deviceId} : MUET depuis ${age} s — relances ARRÊTÉES ` +
        `(${etat.sansEffet} sans effet ; réarmement : node tools/keepalive.mjs --reset)`);
      continue;
    }
    const maintenant = Date.now();
    if (etat.derniere && maintenant - etat.derniere < SEUIL_RELANCE * 1000) {
      const reste = Math.round((SEUIL_RELANCE * 1000 - (maintenant - etat.derniere)) / 1000);
      journal(
        `${deviceId} : MUET depuis ${age} s — relance déjà donnée, ` +
        `prochaine possible dans ${reste} s`);
      continue;
    }

    const serial = apparier(deviceId, serials);
    if (!serial) {
      journal(`${deviceId} : MUET depuis ${age} s — téléphone non trouvé par adb, pas de relance`);
      continue;
    }
    if (sessionUssdEnCours(serial)) {
      journal(`${deviceId} : MUET depuis ${age} s — session USSD en cours, relance REPORTÉE`);
      continue;
    }

    const echec = relancer(serial);
    etat.derniere = maintenant;
    modifie = true;
    if (echec) {
      journal(`${deviceId} : relance impossible — ${echec}`);
      continue;
    }
    etat.sansEffet += 1;
    journal(
      `${deviceId} : MUET depuis ${age} s -> relance n°${etat.sansEffet}` +
      ` (maximum ${MAX_RELANCES_SANS_EFFET} sans effet)`);
    if (etat.sansEffet >= MAX_RELANCES_SANS_EFFET) {
      etat.arrete = true;
      journal(
        `${deviceId} : ${etat.sansEffet} relances sans effet — ARRÊT DES ` +
        "RELANCES pour éviter la boucle du 29/10. Vérifier le téléphone à " +
        'la main, puis : node tools/keepalive.mjs --reset');
    }
  }

  if (modifie) sauverEtats();
}

// ── Démarrage ───────────────────────────────────────────────────────────────

journal(
  `=== maintien en vie démarré — seuil ${SEUIL_RELANCE} s, contrôle toutes ` +
  `${INTERVALLE_MS / 60000} min, relance ${SANS_RELANCE ? 'DÉSACTIVÉE' : 'activée'}, ` +
  `service account ${cleDisponible() ? 'trouvée' : 'ABSENTE'} — ` +
  `${appareils.length} téléphone(s) : ${appareils.join(', ')} ===`);

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
    journal(`erreur de contrôle : ${String(e?.message ?? e)}`);
  } finally {
    enCours = false;
  }
}, INTERVALLE_MS);

process.on('SIGINT', () => {
  clearInterval(minuteur);
  journal('=== arrêt demandé ===');
  process.exit(0);
});

await tour();
