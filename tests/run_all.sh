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
last=""
run() {  # scenario, then any more arguments for the bot (--route=...): its RESULT line, in $last
  last=$("$GODOT" --headless --path . --fixed-fps 60 res://tests/autoplay/autoplay.tscn -- --scenario="$1" "${@:2}" 2>&1 | grep RESULT || true)
}
# Every run must end auto-saved (user: "auto save itself after the player finishes a run"), whatever
# the ending: saved=ok (its progress and route map on the device as it ended, in the bot's own files;
# getting out of mission 1 sets its best time to the run's).
check() {  # what it ran, expected substring(s): every one must be in the RESULT line in $last
  local ok=1
  for want in "${@:2}" "saved=ok"; do
    [[ "$last" == *"$want"* ]] || ok=0
  done
  if [[ $ok == 1 ]]; then echo "PASS $last"; else echo "FAIL [$1] expected '${*:2}', got: ${last:-no result}"; fail=1; fi
}
expect() { run "$1"; check "$@"; }  # on mission 1
expect_on() { run "$1" --setting="$2"; check "$1 ($2)" "${@:3}"; }  # on mission 1, on a setting (easy, medium, hard)
expect_range() { run "$1" --route=test_range; check "$1 (test range)" "${@:2}"; }  # on the TEST RANGE
# A clean run's time (s) must be between lo and hi, to keep mission 1's lengths honest (on MEDIUM,
# where they were tuned, the chopper lifts off at 96 s; EASY and HARD have their own below).
clean_time() {  # what it ran, lo, hi
  local t
  t=$(sed -n 's/.* time=\([0-9.]*\) .*/\1/p' <<<"$last")
  if [[ -n "$t" ]] && awk "BEGIN{exit !($t >= $2 && $t <= $3)}"; then echo "PASS [$1] clean run ${t} s (${2}-${3})"; else echo "FAIL [$1] clean run ${t:-?} s, wanted ${2}-${3}"; fail=1; fi
}

# ---- Mission 1, COLD CALL (game/levels/prototype_slice/route.json): 10 areas, one junction at the
# end of the SECURITY WING. Straight on (always open) to the CANTEEN and the EXIT; the basement
# stairs (far left, open only while it's quiet) to the SERVICE TUNNEL and the BOILER ROOM's ladders;
# the fire escape (far right, open only once the alarm is up) to the ROOFTOPS and the ROOF EDGE's
# ladders. No dogs, alarm runner, snipers, searchlights or pursuit squad: dogs=0/0/0, runner=0/0,
# squad=0/0 in every run. The MAIN FLOOR EXIT's front has three glass doors you burst through.
G="MAIN FLOOR LOBBY > BUILDING MAIN FLOOR > SECURITY WING > STAFF CANTEEN > MAIN FLOOR EXIT > HELIPAD"
U="MAIN FLOOR LOBBY > BUILDING MAIN FLOOR > SECURITY WING > SERVICE TUNNEL > BOILER ROOM"
R="MAIN FLOOR LOBBY > BUILDING MAIN FLOOR > SECURITY WING > ROOFTOPS > ROOF EDGE"
NONE="dogs=0/0/0 runner=0/0 squad=0/0 lights=0"
# The end-of-mission conversation after the run, then the debrief (talk=ending/how/ok): naive,
# ground, miss_ladder and camper tap through every line; naive_skip, boss_skip and boss_hold_fire
# press SKIP. Killed: CROSS's signal lost the whole way (SIGNAL LOST, no lines of his).
expect naive       "reason=killed" "death=ok end=typed" "talk=killed/tapped/ok"
# Killed, SKIP in the conversation, then a tap on the end screen while it types: everything at once.
expect naive_skip  "reason=killed" "death=ok end=skipped" "talk=killed/skipped/ok"
expect ground      "reason=extracted alert=1 route=$G | covers=0 hits=0 missed=0 alarms=0 stumbles=0 doors=12 $NONE" "boss=1/0/" "ko=3/0/ok" "talk=extracted/tapped/ok" "setting=medium bosshp=30 opened=1:hard,1:medium,2:easy,2:medium"
clean_time ground 78 85
# Quiet: down the basement stairs, the BOILER ROOM's left ladder up.
expect tunnel_quiet "reason=extracted alert=1 route=$U > HELIPAD | covers=0 hits=0 missed=0 alarms=0 stumbles=0 doors=9 $NONE" "boss=1/0/" "ko=3/0/ok"
clean_time tunnel_quiet 77 84
# Through the WING's wire: the basement door slams, so the left lane carries straight on (alert 2).
expect tunnel_loud "reason=extracted alert=2 route=$G | covers=0 hits=0 missed=0 alarms=0 stumbles=0 doors=12 $NONE" "boss=1/0/" "ko=3/0/ok"
# Through the MAIN FLOOR's wire (alert 2), the WING's box shot (back to 1: the door lifts), down after all.
expect tunnel_alarm "reason=extracted alert=1 route=$U > HELIPAD | covers=0 hits=0 missed=0 alarms=1 stumbles=0 doors=9 $NONE" "boss=1/0/" "ko=3/0/ok"
# Stays in the middle at the BOILER ROOM's end: no ladder there, CAPTURED.
expect tunnel_miss_ladder "reason=captured alert=1 route=$U | covers=0 hits=0" "$NONE"
# Loud: through the WING's wire (alert 2), up the fire escape, the ROOF EDGE's right ladder down.
expect fire_escape "reason=extracted alert=2 route=$R > HELIPAD | covers=0 hits=0 missed=0 alarms=0 stumbles=0 doors=7 $NONE" "snipers=0/0/0" "boss=1/0/" "ko=3/0/ok"
clean_time fire_escape 71 78
# As fire_escape, but stays in the middle at the ROOF EDGE: CAPTURED.
expect miss_ladder "reason=captured alert=2 route=$R | covers=0 hits=0" "$NONE" "talk=captured/tapped/ok"
# Quiet, heading for the fire escape: it's shut (the door, its padlock), he's eased a lane in and
# carries straight on.
expect fire_shut   "reason=extracted alert=1 route=$G | covers=0 hits=0 missed=0 alarms=0 stumbles=0 doors=12 $NONE" "boss=1/0/" "ko=3/0/ok"
# Through the MAIN FLOOR's wire (alert 2: the fire escape opens), heading for it, the WING's box shot
# (back to 1): the fire door shuts again in front of him, and he carries straight on.
expect fire_closes "reason=extracted alert=1 route=$G | covers=0 hits=0 missed=0 alarms=1 stumbles=0 doors=12 $NONE" "boss=1/0/" "ko=3/0/ok"
# Up the fire escape, the ROOFTOPS' box shot: back to SNEAKING for the ROOF EDGE and ARDBALLS.
expect roof_calm   "reason=extracted alert=1 route=$R > HELIPAD | covers=0 hits=0 missed=0 alarms=1 stumbles=0 doors=7 $NONE" "boss=1/0/" "ko=3/0/ok"
# Heads for the basement stairs, then swipes back to the middle a few metres before the split:
# straight on is still open.
expect late_switch "reason=extracted alert=1 route=$G | covers=0 hits=0" "$NONE" "boss=1/0/" "ko=3/0/ok"
# cover holds fire until it's in cover (the LOBBY's crate), kills the guard from there, goes on.
expect cover       "reason=extracted alert=1 route=$G | covers=1 hits=0 missed=1" "$NONE" "boss=1/0/" "ko=3/0/ok"
# camper never leaves cover: the chopper leaves without him (gone at 106 s).
expect camper      "reason=chopper_left alert=1 route=MAIN FLOOR LOBBY | covers=1" "time=106.0" "talk=chopper_left/tapped/ok"
# Both wires, no boxes: ALERT, and still no squad in mission 1.
expect ground_loud "reason=extracted alert=3 route=$G | covers=0 hits=0" "$NONE" "boss=1/0/" "ko=3/0/ok"
# Both wires, all three boxes on the way (MAIN FLOOR, WING, EXIT): back to SNEAKING.
expect ground_alarms "reason=extracted alert=1 route=$G | covers=0 hits=0 missed=0 alarms=3" "$NONE" "boss=1/0/" "ko=3/0/ok"
expect stumble_once "reason=extracted alert=1 route=$G | covers=0 hits=1 missed=0 alarms=0 stumbles=1" "boss=1/0/" "ko=3/0/ok"
# The boss at the chopper: stepping into a swept lane costs a hit; never shooting him, he blocks the
# way and the chopper leaves.
expect boss_hit "reason=extracted alert=1 route=$G | covers=0 hits=1" "boss=1/1/" "ko=3/0/ok"
expect boss_hold_fire "reason=chopper_left alert=1 route=$G |" "time=106.0" "boss=0/0/" "ko=0/0/-" "talk=chopper_left/skipped/ok"
# TAP ONLY aiming: tapping the boss makes him the target (he's not one of the troopers).
expect boss_tap "reason=extracted alert=1 route=$G | covers=0 hits=0" "boss=1/0/" "ko=3/0/ok"
# The boss's KO replay skipped with a tap: one shot shown, and you run on.
expect boss_skip "reason=extracted alert=1 route=$G | covers=0 hits=0" "boss=1/0/" "ko=1/1/ok" "talk=extracted/skipped/ok"
# Through the real main menu, the mission briefing and the opening pan (tapped through every line,
# the pan starting mid gun check; or SKIP, then a tap skipping the pan): nothing of the run under
# the briefing; CROSS's ready stance hands over to the run with no joint jumping, the pistol never
# at the camera, no camera cut, control on time. START MISSION opens the mission select first (all
# nine missions, 2 to 9 COMING SOON), then mission 1's row its own screen (EASY / MEDIUM / HARD):
# menu_start, on a fresh save, clicks what's locked (mission 2's row; mission 1 MEDIUM and HARD:
# nothing happens), BACK to the select and into mission 1 again, then EASY; intro_skip (out of EASY
# and MEDIUM already) picks HARD, which builds the MAIN FLOOR under the menu again for it.
expect menu_start "reason=extracted alert=1 route=$G | covers=0 hits=0 missed=0 alarms=0 stumbles=0 doors=12" "boss=1/0/" "ko=3/0/ok" "intro=ok" "brief=ok" "select=ok(easy)" "setting=easy bosshp=20 opened=1:medium,2:easy"
expect intro_skip "reason=extracted alert=1 route=$G | covers=0 hits=0 missed=0 alarms=0 stumbles=0 doors=12" "boss=1/0/" "ko=3/0/ok" "intro=ok" "brief=ok" "select=ok(hard)" "setting=hard bosshp=40 opened=2:hard"

# ---- Mission 1's settings (route.json "settings"; user: "an easy medium and hard for each level"):
# the same layout and routes, only the pressure changes. The bots above play MEDIUM (chopper lifts at
# 96 s, gone 106; the boss 30 hits). EASY: lifts at 108 s, gone 118; the boss 20 hits, slower
# spin-ups. HARD: lifts at 86 s, gone 96; the boss 40 hits, quicker spin-ups; and a third wire on the
# MAIN FLOOR, and two more guards each at CAUTION and ALERT on the way straight on (the CANTEEN, the
# EXIT), so the loud roof is the quick way out. Every setting starts at SNEAKING. opened= is what
# getting out opened in the mission select (each bot starts on a fresh save: mission 1 EASY only).
expect_on ground easy "reason=extracted alert=1 route=$G | covers=0 hits=0 missed=0 alarms=0 stumbles=0 doors=12 $NONE" "boss=1/0/" "ko=3/0/ok" "setting=easy bosshp=20 opened=1:medium,2:easy"
clean_time "ground (easy)" 76 82  # (about 27 s to spare before the lift-off)
expect_on camper easy "reason=chopper_left alert=1 route=MAIN FLOOR LOBBY | covers=1" "time=118.0" "setting=easy"
# HARD: a clean run straight on reaches the pad only just before the lift-off (it jumps the third
# wire: still SNEAKING); the loud roof gets there about 10 s sooner.
expect_on ground hard "reason=extracted alert=1 route=$G | covers=0 hits=0 missed=0 alarms=0 stumbles=0 doors=12 $NONE" "boss=1/0/" "ko=3/0/ok" "setting=hard bosshp=40"
clean_time "ground (hard)" 81 86
expect_on fire_escape hard "reason=extracted alert=2 route=$R > HELIPAD | covers=0 hits=0 missed=0 alarms=0 stumbles=0 doors=7 $NONE" "boss=1/0/" "ko=3/0/ok" "setting=hard bosshp=40"
clean_time "fire_escape (hard)" 73 79
expect_on camper hard "reason=chopper_left alert=1 route=MAIN FLOOR LOBBY | covers=1" "time=96.0" "setting=hard"

# ---- The TEST RANGE (tests/fixtures/test_range.json: the full 19-area level as it was before
# mission 1, kept for the bots and never exported), for what mission 1 leaves out: the dogs, the
# alarm runner, the snipers, the searchlights, the pursuit squad, the roof's stairs back down and
# the warehouse drop. Its expectations are unchanged. The WAREHOUSE's exit is a roller shutter: one
# door, where a double door counts two leaves.
TG="MAIN FLOOR LOBBY > BUILDING MAIN FLOOR > SECURITY WING > STAFF CANTEEN > WAREHOUSE > LOADING DOCK > MAIN FLOOR EXIT > HELIPAD"
TR="MAIN FLOOR LOBBY > ROOFTOPS > WATER TOWERS > GANTRY > SKYLIGHTS > ANTENNA FARM > ROOF EDGE"
expect_range roof_down   "reason=extracted alert=1 route=MAIN FLOOR LOBBY > ROOFTOPS > SECURITY WING > STAFF CANTEEN > WAREHOUSE > LOADING DOCK > MAIN FLOOR EXIT > HELIPAD | covers=0 hits=0 missed=0 alarms=0 stumbles=0 doors=15" "boss=1/0/" "ko=3/0/ok"
expect_range warehouse_drop "reason=extracted alert=1 route=MAIN FLOOR LOBBY > BUILDING MAIN FLOOR > SECURITY WING > STAFF CANTEEN > WAREHOUSE > PUMP STATION > STORM DRAIN > HELIPAD | covers=0 hits=0" "boss=1/0/" "ko=3/0/ok"
expect_range roof_loud   "reason=extracted alert=2 route=$TR > HELIPAD | covers=0 hits=0" "snipers=0/4/0" "boss=1/0/" "ko=3/0/ok"
# The roof snipers are out at Alert 2: sniper_hit holds its lane for the first one (hit once) and
# dodges the other three. The last number: snipers out of view on a tall phone when they locked.
expect_range sniper_hit  "reason=extracted alert=2 route=$TR > HELIPAD | covers=0 hits=1" "snipers=1/3/0" "boss=1/0/" "ko=3/0/ok"
expect_range roof_spotted "reason=extracted alert=3 route=$TR > HELIPAD" "boss=1/0/" "ko=3/0/ok"
expect_range dog_bite    "reason=extracted alert=2 route=$TG | covers=0 hits=1 missed=0 alarms=0 stumbles=1 doors=15 dogs=1/0/" "boss=1/0/" "ko=3/0/ok"
expect_range dog_dodge   "reason=extracted alert=2 route=$TG | covers=0 hits=0 missed=0 alarms=0 stumbles=0 doors=15 dogs=0/1/" "boss=1/0/" "ko=3/0/ok"
# (The bot never shoots the runner: he gets to his panel, on the wall, out of its lane. On the way the
# MAIN FLOOR's doors open for him, and are shut again when the bot gets there: gates=1/1/ok.)
expect_range runner_escapes "reason=extracted alert=2 route=$TG | covers=0 hits=0 missed=0 alarms=0 stumbles=0 doors=15 dogs=0/0/4 runner=0/1" "boss=1/0/" "ko=3/0/ok" "gates=1/1/ok"
# Both wires on the test range: Alert 3, and the squad comes after him (he outruns it).
expect_range ground_loud "reason=extracted alert=3 route=$TG | covers=0" "squad=5/0" "boss=1/0/" "ko=3/0/ok"
# Both wires, then the next cover and stays in it: the squad catches up, CAPTURED.
expect_range squad_caught "reason=captured alert=3 route=MAIN FLOOR LOBBY > BUILDING MAIN FLOOR |" "talk=captured/skipped/ok"
exit $fail
