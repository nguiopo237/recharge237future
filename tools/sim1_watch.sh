#!/usr/bin/env bash
# [28/10/2026] Surveillance de la SIM 1 (slot 0) du telephone serveur.
#
# Pourquoi : sur ce site, la SIM 1 est en itinerance sur un reseau qui ne lui
# ouvre que les DONNEES (Rogers). Un code USSD exige le canal voix. Ce script
# regarde donc, minute par minute, si la voix finit par s'enregistrer sur le
# slot 0 -- c'est la seule condition qui rend les ventes MTN possibles.
#
# Aucune ecriture dans Firestore, aucune commande envoyee au telephone, sauf
# le cycle mode avion (30 s) autorise par l'admin, au plus une fois toutes les
# 30 minutes, uniquement si la voix reste absente.
ADB="/c/Users/wlouo/AppData/Local/Android/Sdk/platform-tools/adb.exe"
LOG="/c/Users/wlouo/IdeaProjects/serveur_recharge237/logs/sim1.log"
ETAT_CYCLE="/c/Users/wlouo/IdeaProjects/serveur_recharge237/logs/sim1_dernier_cycle.txt"
INTERVALLE=60
CYCLE_MIN=30

mkdir -p "$(dirname "$LOG")"

serials() {
  "$ADB" devices | sed -n 's/[[:space:]]*device.*//p' | sed '/^List of/d;/^$/d'
}

pick() {
  local s
  while IFS= read -r s; do
    [ -z "$s" ] && continue
    if "$ADB" -s "$s" shell true >/dev/null 2>&1; then printf '%s' "$s"; return 0; fi
  done < <(serials)
  return 1
}

etat_slot0() {
  # Une seule ligne = etat COURANT de la carte 1 (les lignes historiques du
  # journal telephonique commencent par une date, on les ignore).
  local serial="$1" line
  line=$("$ADB" -s "$serial" shell 'dumpsys telephony.registry | grep -E "^    mServiceState=" | head -1' 2>/dev/null)
  [ -z "$line" ] && { echo "INCONNU|"; return; }
  local voix op
  voix=$(printf '%s' "$line" | sed -n 's/.*mVoiceRegState=[0-9]*(\([A-Z_]*\)).*/\1/p')
  op=$(printf '%s' "$line" | sed -n 's/.*mOperatorAlphaLong=\([^,]*\),.*/\1/p')
  echo "${voix:-INCONNU}|${op:-}"
}

cycle_avion() {
  local serial="$1"
  "$ADB" -s "$serial" shell 'nohup sh -c "cmd connectivity airplane-mode enable; sleep 30; cmd connectivity airplane-mode disable; sleep 2; svc wifi enable" >/dev/null 2>&1 &' >/dev/null 2>&1
  date +%s > "$ETAT_CYCLE"
}

# Le cycle est interdit au demarrage : sans horodatage, le script croirait
# qu'aucun cycle n'a jamais eu lieu et en declencherait un immediatement
# (c'est arrive une fois). On considere donc le demarrage comme un cycle.
[ -f "$ETAT_CYCLE" ] || date +%s > "$ETAT_CYCLE"

echo "=== surveillance SIM 1 (slot 0) demarree $(date '+%F %T') ===" >> "$LOG"
echo "    prochain cycle mode avion autorise a $(date -d "@$(( $(cat "$ETAT_CYCLE") + CYCLE_MIN * 60 ))" '+%H:%M' 2>/dev/null || echo '?') " >> "$LOG"
while true; do
  ts=$(date '+%F %T')
  serial=$(pick)
  if [ -z "$serial" ]; then
    echo "$ts | telephone injoignable (adb)" >> "$LOG"
    sleep "$INTERVALLE"
    continue
  fi
  res=$(etat_slot0 "$serial")
  voix=${res%%|*}
  op=${res#*|}
  if [ "$voix" = "IN_SERVICE" ]; then
    echo "$ts | SIM 1 VOIX OK sur ${op:-?} -> USSD possible" >> "$LOG"
  else
    echo "$ts | SIM 1 voix=${voix} (${op:-aucun reseau}) -> USSD impossible" >> "$LOG"
    dernier=$(cat "$ETAT_CYCLE" 2>/dev/null || echo 0)
    maintenant=$(date +%s)
    if [ $((maintenant - dernier)) -ge $((CYCLE_MIN * 60)) ]; then
      echo "$ts | cycle mode avion 30 s (relance reseau)" >> "$LOG"
      cycle_avion "$serial"
    fi
  fi
  sleep "$INTERVALLE"
done
