#!/usr/bin/env bash
# Builds the dog (the user's Meshy German Shepherd, art_source/dog/dog.glb) for the game: stages 1
# and 3 as for the humans (build_character.sh), then his own four-legged rig (stage4_rig_dog.py),
# scaled to WITHERS metres at the shoulder.
#   art_source/operative/tools/build_dog.sh [tris=3000] [tex=512] [withers=0.72]
set -euo pipefail
cd "$(dirname "$0")/../../.."
TRIS="${1:-3000}"
TEX="${2:-512}"
WITHERS="${3:-0.72}"
BLENDER="${BLENDER:-/c/Program Files/Blender Foundation/Blender 5.2/blender.exe}"
ROOT="$(pwd -W 2>/dev/null || pwd)"
WORK="$ROOT/art_source/dog/work"
OUT="game/enemies/rusher_dog"
TOOLS="art_source/operative/tools"
mkdir -p "$WORK" "$OUT"
export CHAR=dog
# (A stage that fails stops the build: Blender exits non-zero on a Python error.)
run() { "$BLENDER" --background --python-exit-code 1 --python "$TOOLS/$1" -- "${@:2}" 2>&1 | { grep -E "^(BASE|TRIS|SAVED|REMESHED|LOW_TRIS|BAKED|DONE|TURNED|SCALED|LANDMARKS|TAIL|WEIGHTS|EXPORTED)|Error|Traceback" || true; }; }
echo "== dog, stage 1: reduce"
run stage1_reduce.py "$ROOT/art_source/dog/dog.glb" "$WORK"
echo "== dog, stage 3: remesh, reduce to $TRIS triangles, bake a ${TEX}px texture"
run stage3_bake.py "$WORK" "$WORK" "$TRIS" "$TEX"
echo "== dog, stage 4: face forward, scale, rig (four legs), weights, export"
rm -f "$WORK/dog_rigged.glb"  # (so a failed stage 4 can't leave an old one to copy)
run stage4_rig_dog.py "$WORK/dog_low_${TRIS}.blend" "$WORK/dog_rigged.glb" "$WORK/dog_joints.json" "$WITHERS"
cp "$WORK/dog_rigged.glb" "$OUT/dog.glb"
echo "== done: $OUT/dog.glb ($(wc -c < "$OUT/dog.glb") bytes)"
