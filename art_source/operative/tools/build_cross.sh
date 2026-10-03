#!/usr/bin/env bash
# Builds CROSS for the game from the Meshy model, end to end, and puts him in game/player.
#   art_source/operative/ernest-cross.glb  (the Meshy model, ~1.3M triangles)
#     -> stage1_reduce.py   work/cross_20k.blend          on the ground, a 20k working copy
#     -> stage3_bake.py     work/cross_low_<tris>.blend   remeshed, reduced, unwrapped, colours baked
#                           work/cross_<tris>_<tex>.png   (also packed into the .blend)
#     -> stage4_rig.py      work/cross_low_<tris>_rigged.blend, work/cross_rigged.glb,
#                           work/cross_joints.json        faced forward, skeleton, weights, lenses
#     -> game/player/cross.glb + game/player/cross.json   (the model, and his lens positions)
# Usage (from the project root): art_source/operative/tools/build_cross.sh [tris=3000] [tex=512]
# Set BLENDER to Blender's exe if it isn't in the default place. Run the game's import afterwards
# (Godot does it when the editor opens, or: godot --headless --path . --import).
set -euo pipefail
cd "$(dirname "$0")/../../.."
BLENDER="${BLENDER:-/c/Program Files/Blender Foundation/Blender 5.2/blender.exe}"
TRIS="${1:-3000}"
TEX="${2:-512}"
ROOT="$(pwd -W 2>/dev/null || pwd)"
SRC="$ROOT/art_source/operative/ernest-cross.glb"
WORK="$ROOT/art_source/operative/work"
TOOLS="art_source/operative/tools"
mkdir -p "$WORK"
run() { "$BLENDER" --background --python "$TOOLS/$1" -- "${@:2}" 2>&1 | grep -E "^(BASE|TRIS|SAVED|REMESHED|LOW_TRIS|BAKED|DONE|TURNED|LANDMARKS|WEIGHTS|LENSES|EXPORTED)|Error|Traceback" || true; }
echo "== stage 1: reduce"
run stage1_reduce.py "$SRC" "$WORK"
echo "== stage 3: remesh, reduce to $TRIS triangles, bake a ${TEX}px texture"
run stage3_bake.py "$WORK" "$WORK" "$TRIS" "$TEX"
echo "== stage 4: face forward, rig, weights, lenses, export"
run stage4_rig.py "$WORK/cross_low_${TRIS}.blend" "$WORK/cross_rigged.glb" "$WORK/cross_joints.json" "$ROOT/game/player/cross.json"
cp "$WORK/cross_rigged.glb" game/player/cross.glb
echo "== done: game/player/cross.glb ($(wc -c < game/player/cross.glb) bytes), game/player/cross.json"
