#!/usr/bin/env bash
# Builds Bishop for the game from his high-poly source model (art_source/bishop/bishop.glb, made with
# his arms partway down, about 38 degrees out from hanging, so they are lowered the rest of the way to
# the A-pose first) into game/player (bishop.glb, bishop.json).
# He's CROSS's height as made (1.90 m), so he isn't scaled. Nothing in the game loads him yet.
# See build_character.sh for the stages.
# Usage (from the project root): art_source/operative/tools/build_bishop.sh [tris=3000] [tex=512]
set -euo pipefail
cd "$(dirname "$0")/../../.."
export WELD=1  # (his source is split along its texture seams: welded before it's reduced, see stage1_reduce.py)
export VOXEL=0.012  # (finer than this, his reduced copy's remesh comes apart into hundreds of pieces)
export SPLIT_OVERLAPS=1  # (his arms hang close: unwrapped apart from his sides, see stage3_bake.py)
export FILL_MISSES=1  # (a face folded in at his hairline misses the bake: filled from round it)
exec art_source/operative/tools/build_character.sh bishop art_source/bishop/bishop.glb game/player "${1:-3000}" "${2:-512}" slanted
