#!/usr/bin/env bash
# [TEST 28/10/2026] Surveillance continue du réseau des téléphones serveurs.
#
# Écrit une ligne par minute dans logs/reseau.log : état d'enregistrement de
# chaque SIM. Si le téléphone disparaît d'adb (Wi-Fi coupé, app en veille), le
# script tente de le reconnecter tout seul via la découverte mDNS.
#
# Usage : bash tools/reseau_watch.sh   (lancé en tâche de fond)
#
# [FIX 30/10/2026] Deux pannes silencieuses, corrigées ici :
#
#  1. « adb indisponible » en boucle alors que adb marchait. Le téléphone
#     remonte DEUX fois dans `adb devices` (même appareil, deux alias mDNS :
#     `adb-xxx._adb-tls-connect._tcp` et `adb-xxx (2)._adb-tls-connect._tcp`).
#     `adb shell` sans `-s <serial>` refuse alors avec « more than one device »
#     et le script concluait à tort que le téléphone était injoignable. On
#     choisit désormais UN serial, comme le fait déjà sim1_watch.sh.
#  2. La regex datant du 28/10 (`phoneId=N state={...}`) ne correspond plus au
#     dumpsys de ce téléphone : l'état courant s'écrit
#     `    mServiceState={mVoiceRegState=0(IN_SERVICE), ... mOperatorAlphaLong=...,
#     mDataRegState=0`. Elle est réalignée sur ce format réel.
ADB="${ADB:-/c/Users/wlouo/AppData/Local/Android/Sdk/platform-tools/adb.exe}"
LOG="/c/Users/wlouo/IdeaProjects/serveur_recharge237/logs/reseau.log"
mkdir -p "$(dirname "$LOG")"

echo "$(date '+%Y-%m-%d %H:%M:%S') | surveillance démarrée" >> "$LOG"

# Serial à interroger : le premier qui répond réellement.
pick() {
  local s
  while IFS= read -r s; do
    [ -z "$s" ] && continue
    if "$ADB" -s "$s" shell true >/dev/null 2>&1; then printf '%s' "$s"; return 0; fi
  done < <("$ADB" devices | sed -n 's/[[:space:]]*device.*//p' | sed '/^List of/d;/^$/d')
  return 1
}

while true; do
  ts=$(date '+%Y-%m-%d %H:%M:%S')

  if ! "$ADB" devices 2>/dev/null | grep -q "device"; then
    # Téléphone injoignable : nouvelle tentative de connexion sur chaque
    # service mDNS découvert (le port change à chaque réassociation Wi-Fi).
    for s in "$("$ADB" mdns services 2>/dev/null | awk '/_adb-tls-connect/ {print $3}')"; do
      "$ADB" connect "$s" >/dev/null 2>&1
    done
    sleep 4
  fi

  serial=$(pick)
  if [ -z "$serial" ]; then
    echo "$ts | adb indisponible" >> "$LOG"
    sleep 60
    continue
  fi

  # États COURANTS uniquement : les lignes d'historique du journal
  # téléphonique commencent par une date, celles d'état par des espaces.
  etat=$("$ADB" -s "$serial" shell 'dumpsys telephony.registry' 2>/dev/null \
    | grep -E '^    mServiceState=' \
    | head -2 \
    | sed -E 's/^    mServiceState=\{//; s/\},?$//' \
    | sed -E 's/, m(NetworkRegistrationInfos|NrFrequencyRange|IsIwlanPreferred)=.*//' \
    | grep -oE 'mVoiceRegState=[0-9]+\([A-Z_]+\)|mDataRegState=[0-9]+\([A-Z_]+\)|mOperatorAlphaLong=[^,]+' \
    | tr '\n' ' ')

  if [ -z "$etat" ]; then
    echo "$ts | adb indisponible (serial=$serial)" >> "$LOG"
  else
    echo "$ts | $etat" >> "$LOG"
  fi

  sleep 60
done
