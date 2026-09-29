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
expect naive       "reason=killed"
expect left        "reason=extracted alert=1 route=COMPOUND EXIT > MOTOR POOL"
expect right_quiet "reason=extracted alert=1 route=COMPOUND EXIT > ROOFTOPS > SERVICE TUNNEL"
expect right_loud  "reason=extracted alert=2 route=COMPOUND EXIT > ROOFTOPS > AIRFIELD GATE"
exit $fail
