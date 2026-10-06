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
expect() {  # scenario, expected substring(s): every one must be in its RESULT line
  local out ok=1
  out=$("$GODOT" --headless --path . --fixed-fps 60 res://tests/autoplay/autoplay.tscn -- --scenario="$1" 2>&1 | grep RESULT || true)
  for want in "${@:2}"; do
    [[ "$out" == *"$want"* ]] || ok=0
  done
  if [[ $ok == 1 ]]; then echo "PASS $out"; else echo "FAIL [$1] expected '${*:2}', got: ${out:-no result}"; fail=1; fi
}
# The WAREHOUSE's exit is a roller shutter: one door, where a double door counts two leaves. The
# MAIN FLOOR EXIT's front has three glass doors you burst through: three more.
G="MAIN FLOOR LOBBY > BUILDING MAIN FLOOR > SECURITY WING > STAFF CANTEEN > WAREHOUSE > LOADING DOCK > MAIN FLOOR EXIT > HELIPAD"
U="MAIN FLOOR LOBBY > BUILDING MAIN FLOOR > SERVICE TUNNEL > BOILER ROOM > SEWER > PUMP STATION > STORM DRAIN > HELIPAD"
R="MAIN FLOOR LOBBY > ROOFTOPS > WATER TOWERS > GANTRY > SKYLIGHTS > ANTENNA FARM > ROOF EDGE"
# The end-of-mission conversation after the run, then the debrief (talk=ending/how/ok): naive,
# ground, miss_ladder and camper tap through every line; naive_skip, boss_skip, squad_caught and
# boss_hold_fire press SKIP. Killed: CROSS's signal lost the whole way (SIGNAL LOST, no lines of his).
expect naive       "reason=killed" "death=ok end=typed" "talk=killed/tapped/ok"
# Killed, SKIP in the conversation, then a tap on the end screen while it types: everything at once.
expect naive_skip  "reason=killed" "death=ok end=skipped" "talk=killed/skipped/ok"
expect ground      "reason=extracted alert=1 route=$G | covers=0 hits=0 missed=0 alarms=0 stumbles=0 doors=15 dogs=0/0/0 runner=1/0" "boss=1/0/" "ko=3/0/ok" "talk=extracted/tapped/ok"
expect tunnel_quiet "reason=extracted alert=1 route=$U | covers=0 hits=0 missed=0 alarms=0 stumbles=0 doors=13" "boss=1/0/" "ko=3/0/ok"
expect tunnel_loud "reason=extracted alert=2 route=$G | covers=0 hits=0 missed=0 alarms=0 stumbles=0 doors=15" "boss=1/0/" "ko=3/0/ok"
expect tunnel_alarm "reason=extracted alert=1 route=$U | covers=0 hits=0 missed=0 alarms=1" "boss=1/0/" "ko=3/0/ok"
expect roof_down   "reason=extracted alert=1 route=MAIN FLOOR LOBBY > ROOFTOPS > SECURITY WING > STAFF CANTEEN > WAREHOUSE > LOADING DOCK > MAIN FLOOR EXIT > HELIPAD | covers=0 hits=0 missed=0 alarms=0 stumbles=0 doors=15" "boss=1/0/" "ko=3/0/ok"
expect roof_loud   "reason=extracted alert=2 route=$R > HELIPAD | covers=0 hits=0" "snipers=0/4/0" "boss=1/0/" "ko=3/0/ok"
# The roof snipers are out at Alert 2: sniper_hit holds its lane for the first one (hit once) and
# dodges the other three. The last number: snipers out of view on a tall phone when they locked.
expect sniper_hit  "reason=extracted alert=2 route=$R > HELIPAD | covers=0 hits=1" "snipers=1/3/0" "boss=1/0/" "ko=3/0/ok"
expect miss_ladder "reason=captured alert=2 route=$R |" "talk=captured/tapped/ok"
expect warehouse_drop "reason=extracted alert=1 route=MAIN FLOOR LOBBY > BUILDING MAIN FLOOR > SECURITY WING > STAFF CANTEEN > WAREHOUSE > PUMP STATION > STORM DRAIN > HELIPAD | covers=0 hits=0" "boss=1/0/" "ko=3/0/ok"
expect late_switch "reason=extracted alert=1 route=$G" "boss=1/0/" "ko=3/0/ok"
# cover holds fire until it is in cover, so the alarm runner gets away: Alert 2.
expect cover       "reason=extracted alert=2 route=$G | covers=1 hits=0 missed=1" "boss=1/0/" "ko=3/0/ok"
# camper never leaves cover, so the alarm runner gets away too.
expect camper      "reason=chopper_left alert=2 route=MAIN FLOOR LOBBY | covers=1" "talk=chopper_left/tapped/ok"
expect ground_loud "reason=extracted alert=3 route=$G | covers=0" "boss=1/0/" "ko=3/0/ok"
# The dock's alarm box is out in the yard, in plain view: the bot shoots all three.
expect ground_alarms "reason=extracted alert=1 route=$G | covers=0 hits=0 missed=0 alarms=3" "boss=1/0/" "ko=3/0/ok"
expect stumble_once "reason=extracted alert=1 route=$G | covers=0 hits=1 missed=0 alarms=0 stumbles=1" "boss=1/0/" "ko=3/0/ok"
expect dog_bite    "reason=extracted alert=2 route=$G | covers=0 hits=1 missed=0 alarms=0 stumbles=1 doors=15 dogs=1/0/" "boss=1/0/" "ko=3/0/ok"
expect dog_dodge   "reason=extracted alert=2 route=$G | covers=0 hits=0 missed=0 alarms=0 stumbles=0 doors=15 dogs=0/1/" "boss=1/0/" "ko=3/0/ok"
# (The bot never shoots the runner: he gets to his panel, on the wall, out of its lane.)
expect runner_escapes "reason=extracted alert=2 route=$G | covers=0 hits=0 missed=0 alarms=0 stumbles=0 doors=15 dogs=0/0/4 runner=0/1" "boss=1/0/" "ko=3/0/ok"
expect roof_spotted "reason=extracted alert=3 route=$R > HELIPAD" "boss=1/0/" "ko=3/0/ok"
expect squad_caught "reason=captured alert=3 route=MAIN FLOOR LOBBY > BUILDING MAIN FLOOR |" "talk=captured/skipped/ok"
# The boss at the chopper: stepping into a swept lane costs a hit; never shooting him, he blocks the
# way and the chopper leaves.
expect boss_hit "reason=extracted alert=1 route=$G | covers=0 hits=1" "boss=1/1/" "ko=3/0/ok"
expect boss_hold_fire "reason=chopper_left alert=1 route=$G |" "boss=0/0/" "ko=0/0/-" "talk=chopper_left/skipped/ok"
# TAP ONLY aiming: tapping the boss makes him the target (he's not one of the troopers).
expect boss_tap "reason=extracted alert=1 route=$G | covers=0 hits=0" "boss=1/0/" "ko=3/0/ok"
# The boss's KO replay skipped with a tap: one shot shown, and you run on.
expect boss_skip "reason=extracted alert=1 route=$G | covers=0 hits=0" "boss=1/0/" "ko=1/1/ok" "talk=extracted/skipped/ok"
# Through the real main menu, the mission briefing and the opening pan (tapped through every line,
# the pan starting mid gun check; or SKIP, then a tap skipping the pan): nothing of the run under
# the briefing; CROSS's ready stance hands over to the run with no joint jumping, the pistol never
# at the camera, no camera cut, control on time.
expect menu_start "reason=extracted alert=1 route=$G | covers=0 hits=0 missed=0 alarms=0 stumbles=0 doors=15" "boss=1/0/" "ko=3/0/ok" "intro=ok" "brief=ok"
expect intro_skip "reason=extracted alert=1 route=$G | covers=0 hits=0 missed=0 alarms=0 stumbles=0 doors=15" "boss=1/0/" "ko=3/0/ok" "intro=ok" "brief=ok"
exit $fail
