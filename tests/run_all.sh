#!/usr/bin/env bash
# Runs unit tests and bot playthroughs. Usage: GODOT=/path/to/godot tests/run_all.sh
set -euo pipefail
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."

"$GODOT" --headless --path . --import >/dev/null 2>&1 || true

echo "== Unit tests"
"$GODOT" --headless --path . -s res://tests/run_tests.gd

echo "== Bot playthroughs"
fail=0
expect() {  # scenario, expected substring
  local out
  out=$("$GODOT" --headless --path . --fixed-fps 60 res://tests/autoplay/autoplay.tscn -- --scenario="$1" 2>&1 | grep RESULT || true)
  if [[ "$out" == *"$2"* ]]; then echo "PASS $out"; else echo "FAIL [$1] expected '$2', got: ${out:-no result}"; fail=1; fi
}
G="MAIN FLOOR LOBBY > BUILDING MAIN FLOOR > SECURITY WING > STAFF CANTEEN > WAREHOUSE > LOADING DOCK > MAIN FLOOR EXIT > HELIPAD"
U="MAIN FLOOR LOBBY > BUILDING MAIN FLOOR > SERVICE TUNNEL > BOILER ROOM > SEWER > PUMP STATION > STORM DRAIN > HELIPAD"
R="MAIN FLOOR LOBBY > ROOFTOPS > WATER TOWERS > GANTRY > SKYLIGHTS > ANTENNA FARM > ROOF EDGE"
expect naive       "reason=killed"
expect ground      "reason=extracted alert=1 route=$G | covers=0 hits=0 missed=0 alarms=0 stumbles=0 doors=13 dogs=0/0/0 runner=1/0"
expect tunnel_quiet "reason=extracted alert=1 route=$U | covers=0 hits=0 missed=0 alarms=0 stumbles=0 doors=13"
expect tunnel_loud "reason=extracted alert=2 route=$G | covers=0 hits=0 missed=0 alarms=0 stumbles=0 doors=13"
expect tunnel_alarm "reason=extracted alert=1 route=$U | covers=0 hits=0 missed=0 alarms=1"
expect roof_down   "reason=extracted alert=1 route=MAIN FLOOR LOBBY > ROOFTOPS > SECURITY WING > STAFF CANTEEN > WAREHOUSE > LOADING DOCK > MAIN FLOOR EXIT > HELIPAD | covers=0 hits=0 missed=0 alarms=0 stumbles=0 doors=13"
expect roof_loud   "reason=extracted alert=2 route=$R > HELIPAD | covers=0 hits=0"
expect miss_ladder "reason=captured alert=2 route=$R |"
expect warehouse_drop "reason=extracted alert=1 route=MAIN FLOOR LOBBY > BUILDING MAIN FLOOR > SECURITY WING > STAFF CANTEEN > WAREHOUSE > PUMP STATION > STORM DRAIN > HELIPAD | covers=0 hits=0"
expect late_switch "reason=extracted alert=1 route=$G"
# cover holds fire until it is in cover, so the alarm runner gets away: Alert 2.
expect cover       "reason=extracted alert=2 route=$G | covers=1 hits=0 missed=1"
# camper never leaves cover, so the alarm runner gets away too.
expect camper      "reason=chopper_left alert=2 route=MAIN FLOOR LOBBY | covers=1"
expect ground_loud "reason=extracted alert=3 route=$G | covers=0"
expect ground_alarms "reason=extracted alert=1 route=$G | covers=0 hits=0 missed=0 alarms=2"
expect stumble_once "reason=extracted alert=1 route=$G | covers=0 hits=1 missed=0 alarms=0 stumbles=1"
expect dog_bite    "reason=extracted alert=2 route=$G | covers=0 hits=1 missed=0 alarms=0 stumbles=1 doors=13 dogs=1/0/"
expect dog_dodge   "reason=extracted alert=2 route=$G | covers=0 hits=0 missed=0 alarms=0 stumbles=0 doors=13 dogs=0/1/"
expect runner_escapes "reason=extracted alert=2 route=$G | covers=0 hits=0 missed=0 alarms=0 stumbles=0 doors=13 dogs=0/0/4 runner=1/1"
expect roof_spotted "reason=extracted alert=3 route=$R > HELIPAD"
expect squad_caught "reason=captured alert=3 route=MAIN FLOOR LOBBY > BUILDING MAIN FLOOR |"
exit $fail
