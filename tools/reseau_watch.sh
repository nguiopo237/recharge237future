#!/usr/bin/env bash
# [TEST 28/10/2026] Surveillance continue du réseau des téléphones serveurs.
#
# Écrit une ligne par minute dans logs/reseau.log : état d'enregistrement de
# chaque SIM. Si le téléphone disparaît d'adb (Wi-Fi coupé, app en veille), le
# script tente de le reconnecter tout seul via la découverte mDNS.
#
# Usage : bash tools/reseau_watch.sh   (lancé en tâche de fond)
ADB="/c/Users/wlouo/AppData/Local/Android/Sdk/platform-tools/adb.exe"
LOG="/c/Users/wlouo/IdeaProjects/recharge237future/logs/reseau.log"
mkdir -p "$(dirname "$LOG")"

echo "$(date '+%Y-%m-%d %H:%M:%S') | surveillance démarrée" >> "$LOG"

while true; do
  ts=$(date '+%Y-%m-%d %H:%M:%S')

  if ! "$ADB" devices 2>/dev/null | grep -q "device$"; then
    # Téléphone injoignable : nouvelle tentative de connexion sur chaque
    # service mDNS découvert (le port change à chaque réassociation Wi-Fi).
    for s in $("$ADB" mdns services 2>/dev/null | awk '/_adb-tls-connect/ {print $3}'); do
      "$ADB" connect "$s" >/dev/null 2>&1
    done
    sleep 4
  fi

  etat=$("$ADB" shell dumpsys telephony.registry 2>/dev/null \
    | grep -oE "phoneId=[0-9]+ state=\{mVoiceRegState=[0-9]+\([A-Z_]+\)[^}]*mOperatorAlphaLong=[^,]*, mDataRegState=[0-9]+" \
    | tail -2 | sed 's/state={//' | tr '\n' ' ')

  if [ -z "$etat" ]; then
    echo "$ts | adb indisponible" >> "$LOG"
  else
    echo "$ts | $etat" >> "$LOG"
  fi

  sleep 60
done
