#!/usr/bin/env bash
# Builds a character for the game from its Meshy model, end to end, and puts him in the game.
#   SOURCE.glb (the Meshy model, ~0.5-1.3M triangles; its work files go in work/ beside it)
#     -> stage1_reduce.py   work/<name>_20k.blend           on the ground, a 20k working copy
#     -> stage1b_apose.py   (only with "apose": a T-pose model's arms lowered to the A-pose)
#     -> stage3_bake.py     work/<name>_low_<tris>.blend    remeshed, reduced, unwrapped, colours baked
#                           work/<name>_<tris>_<tex>.png    (also packed into the .blend)
#     -> stage4_rig.py      work/<name>_low_<tris>_rigged.blend, work/<name>_rigged.glb,
#                           work/<name>_joints.json         faced forward, skeleton, weights, lenses
#     -> OUT_DIR/<name>.glb + OUT_DIR/<name>.json           (the model, and his lens positions)
# Usage (from the project root):
#   art_source/operative/tools/build_character.sh NAME SOURCE.glb OUT_DIR [tris=3000] [tex=512] [apose]
#   e.g. build_character.sh guard art_source/guard/guard-meshy.glb game/enemies/guard 3000 512 apose
# Set BLENDER to Blender's exe if it isn't in the default place. Run the game's import afterwards
# (Godot does it when the editor opens, or: godot --headless --path . --import).
set -euo pipefail
cd "$(dirname "$0")/../../.."
NAME="${1:?name}"
SRC_REL="${2:?source glb}"
OUT="${3:?output folder}"
TRIS="${4:-3000}"
TEX="${5:-512}"
POSE="${6:-}"
BLENDER="${BLENDER:-/c/Program Files/Blender Foundation/Blender 5.2/blender.exe}"
ROOT="$(pwd -W 2>/dev/null || pwd)"
SRC="$ROOT/$SRC_REL"
WORK="$ROOT/$(dirname "$SRC_REL")/work"
TOOLS="art_source/operative/tools"
mkdir -p "$WORK" "$OUT"
export CHAR="$NAME"
# (A stage that fails stops the build: Blender exits non-zero on a Python error.)
run() { "$BLENDER" --background --python-exit-code 1 --python "$TOOLS/$1" -- "${@:2}" 2>&1 | { grep -E "^(BASE|TRIS|SAVED|APOSE|APOSED|REMESHED|LOW_TRIS|BAKED|DONE|TURNED|LANDMARKS|WEIGHTS|LENSES|EXPORTED)|Error|Traceback" || true; }; }
echo "== $NAME, stage 1: reduce"
run stage1_reduce.py "$SRC" "$WORK"
if [[ "$POSE" == "apose" ]]; then
  echo "== $NAME, stage 1b: arms down to the A-pose"
  run stage1b_apose.py "$WORK"
fi
echo "== $NAME, stage 3: remesh, reduce to $TRIS triangles, bake a ${TEX}px texture"
run stage3_bake.py "$WORK" "$WORK" "$TRIS" "$TEX"
echo "== $NAME, stage 4: face forward, rig, weights, lenses, export"
rm -f "$WORK/${NAME}_rigged.glb"  # (so a failed stage 4 can't leave an old one to copy)
run stage4_rig.py "$WORK/${NAME}_low_${TRIS}.blend" "$WORK/${NAME}_rigged.glb" "$WORK/${NAME}_joints.json" "$ROOT/$OUT/$NAME.json"
cp "$WORK/${NAME}_rigged.glb" "$OUT/$NAME.glb"
echo "== done: $OUT/$NAME.glb ($(wc -c < "$OUT/$NAME.glb") bytes), $OUT/$NAME.json"
