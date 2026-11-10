#!/usr/bin/env bash
# Builds Vesper for the game from her high-poly source model (art_source/vesper/vesper.glb, made near
# CROSS's A-pose, so her arms aren't lowered) into game/player (vesper.glb, vesper.json).
# Nothing in the game loads her yet. See build_character.sh for the stages.
# Usage (from the project root): art_source/operative/tools/build_vesper.sh [tris=3000] [tex=512]
set -euo pipefail
cd "$(dirname "$0")/../../.."

# Her height, as a share of CROSS's (a first guess, for the user to check: "shorter than Cross and
# Bishop"). Change this one number and rebuild.
HEIGHT_OF_CROSS=0.93
CROSS_HEIGHT=1.898  # (game/player/cross.glb, the top of his head, m)
export HEIGHT=$(awk "BEGIN { printf \"%.4f\", $CROSS_HEIGHT * $HEIGHT_OF_CROSS }")

export WELD=1  # (her source is split along its texture seams: welded before it's reduced, see stage1_reduce.py)
# Parts of her back replaced with the other side's, mirrored (see stage1_reduce.py; metres on the source
# as made, stood on the ground: x0,x1 across, y0 the back half, z0,z1 up):
POUCH_BOX="-0.155,-0.03,0.03,1.0,1.225"  # the pouch at the back of her belt, taken off (user)
SKIRT_BOX="0.08,0.21,0.03,0.83,1.0"      # a pale patch in the source's texture, up from her skirt's hem
export MIRROR_BOX="$POUCH_BOX;$SKIRT_BOX"
# Her side split, at the front: it shows her leg, but the source's texture has it tan. Recoloured to her
# leg's colour just below it (see stage1_reduce.py; the same measures as the boxes above, plus y1).
export TINT_BOX="0.10,0.19,-0.3,0.0,0.84,0.95"
export TINT_FROM="0.74,0.83"
# Her thighs parted (see stage1_reduce.py): at least 5 cm apart from 0.55 m up under her skirt to the
# crotch (the source as made, before HEIGHT), so the remesh keeps her legs apart.
export LEG_GAP="0.55,0.89,0.05"
export VOXEL=0.012  # (as Bishop's: finer, the reduced copy's remesh comes apart)
export SPLIT_OVERLAPS=1  # (her arms hang close: unwrapped apart from her sides, see stage3_bake.py)
export FILL_MISSES=1  # (any face the bake misses is filled from round it)
export GROW_GAPS=1  # (black gaps between islands grown over: thin black marks on her thighs)
export DROP_BITS=1  # (the remesh leaves a few loose crumbs: dropped, see stage3_bake.py)
export HEM=0.785  # (her skirt's hem, m: the bake there is straightened, see stage3_bake.py)
export HEM_KEEP="0.09,0.18,-0.3,0.0"  # (her side split at the front, which shows her leg: left alone)
export HEM_INNER="0.06,0.83,0,0"  # (between her legs up under the skirt: the skirt's dark, not her leg)
export CUT_LEGS="0.66,0.81,0.024"  # (her thighs cut apart from mid-thigh up into the skirt, see stage3_bake.py: no bridge under the hem)
# Her joints where the mesh can't show them (see stage4_rig.py): the crotch under her skirt at CROSS's
# share of the height, the tops of her narrower shoulders looked for nearer the middle (m), and the
# shoulder joint placed across by hand.
export CROTCH=0.464
export SHOULDER_BAND="0.12,0.19"
export SHOULDER_X=0.155  # (the shoulder joint across: the arm's line from her low-joined armpit misses it)
exec art_source/operative/tools/build_character.sh vesper art_source/vesper/vesper.glb game/player "${1:-3000}" "${2:-512}"
