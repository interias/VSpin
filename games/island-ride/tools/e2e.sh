#!/usr/bin/env bash
# Manuelle E2E-Prüfung: echte Bridge (Simulator) + Spiel headless. Belegt „mehr Kadenz → schneller“.
# Startet je Kadenz `vspin-bridge --source sim --sim-cadence N` auf ws://127.0.0.1:8765,
# lässt tools/e2e_probe.gd fahren und beendet die Bridge wieder. Port 8765 muss frei sein.
# Mit VSPIN_PORT_BASE=n (#62) laufen Bridge und Probe auf Port 8765 + n – parallel zu anderen Läufen.
#
#   GODOT=/pfad/zu/godot PYTHON=/pfad/zu/python games/island-ride/tools/e2e.sh [Kadenz ...]
# Standard: Kadenzen 60 und 90, je 6 s.
set -euo pipefail

GODOT="${GODOT:-godot}"
PYTHON="${PYTHON:-python}"
SECONDS_PER_RUN="${SECONDS_PER_RUN:-6}"
base="${VSPIN_PORT_BASE:-0}"
if ! [[ "$base" =~ ^[0-9]+$ ]] || [ "$base" -gt 466 ]; then
  echo "VSPIN_PORT_BASE=$base: erwartet eine ganze Zahl 0–466" >&2  # laut statt still auf 8765 (#62)
  exit 1
fi
port=$((8765 + base))
project="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bridge="$(cd "$project/../../bridge" && pwd)"
cadences=("$@")
[ ${#cadences[@]} -eq 0 ] && cadences=(60 90)

"$GODOT" --headless --path "$project" --import >/dev/null 2>&1 || true

bridge_pid=""
cleanup() { [ -n "$bridge_pid" ] && kill -INT "$bridge_pid" 2>/dev/null && wait "$bridge_pid" 2>/dev/null; true; }
trap cleanup EXIT

speeds=()
for cadence in "${cadences[@]}"; do
  log="$(mktemp)"
  (cd "$bridge" && PYTHONPATH=src exec "$PYTHON" -m vspin_bridge --source sim --sim-cadence "$cadence" --port "$port") \
    </dev/null >"$log" 2>&1 &
  bridge_pid=$!
  for _ in $(seq 50); do (exec 3<>/dev/tcp/127.0.0.1/$port) 2>/dev/null && break; sleep 0.2; done
  line="$("$GODOT" --headless --path "$project" -s res://tools/e2e_probe.gd -- --seconds="$SECONDS_PER_RUN" | grep '^E2E')"
  echo "sim-cadence=$cadence  $line"
  kill -INT "$bridge_pid"; wait "$bridge_pid" || true; bridge_pid=""
  echo "  Bridge-Log: $(tr '\n' '|' <"$log")"
  rm -f "$log"
  speeds+=("$(sed -E 's/.*speed_kmh=([0-9.]+).*/\1/' <<<"$line")")
done

for ((i = 1; i < ${#speeds[@]}; i++)); do
  if awk -v a="${speeds[i-1]}" -v b="${speeds[i]}" -v ca="${cadences[i-1]}" -v cb="${cadences[i]}" \
      'BEGIN { exit !((cb > ca && b > a) || (cb < ca && b < a) || (cb == ca)) }'; then
    echo "OK: ${cadences[i-1]} rpm → ${speeds[i-1]} km/h, ${cadences[i]} rpm → ${speeds[i]} km/h"
  else
    echo "FEHLER: Geschwindigkeit folgt der Kadenz nicht (${speeds[*]})"; exit 1
  fi
done
