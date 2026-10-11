#!/usr/bin/env bash
# Remakes the cast's scoreboard entries (route.json "house": VESPER, ARDBALLS, BISHOP, CONDOR, VORHALT,
# ARDBALLS) from real bot runs on every setting of mission 1, COLD CALL. Rerun it whenever the level, a
# setting or the points (Score) change:
#   GODOT=/path/to/godot bash tests/house/make_house.sh
# Each bot prints a HOUSE line with its run's raw tally (tests/autoplay/autoplay.gd); write_house.gd
# picks the ten for each setting and writes them into route.json's "house" block (nothing else in the
# file changes). The player's own scores are never touched (they're in his save, not the file).
set -euo pipefail
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/../.."
OUT="${HOUSE_RUNS:-$(mktemp)}"
: > "$OUT"
# The bots it draws on: escapes quiet and loud, by the ground, the tunnels and the roofs, with alarms
# set off and stopped, from cover, with a hit (the boss, a barrier); and the failures: a capture, the
# chopper leaving with ARDBALLS standing, killed halfway, killed at once.
SCENARIOS="ground tunnel_quiet fire_escape ground_loud ground_alarms tunnel_alarm fire_closes roof_calm cover stumble_once boss_hit miss_ladder tunnel_miss_ladder boss_hold_fire halfway naive"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
jobs_run=0
for setting in easy medium hard; do
  for s in $SCENARIOS; do
    (
      line=$("$GODOT" --headless --path . --fixed-fps 60 res://tests/autoplay/autoplay.tscn -- --scenario="$s" --setting="$setting" 2>&1 | grep '^HOUSE ' || true)
      if [[ -n "$line" ]]; then echo "${line#HOUSE }" >> "$OUT"; echo "ran $s ($setting)"; else echo "no result: $s ($setting)"; fi
    ) &
    jobs_run=$((jobs_run + 1))
    if (( jobs_run % 4 == 0 )); then wait; fi
  done
done
wait
"$GODOT" --headless --path . -s res://tests/house/write_house.gd -- --runs="$OUT"
