#!/usr/bin/env bash
# Builds one of CROSS's skins (the decision log's "Eight skins for CROSS") from its high-poly source
# model, art_source/skins/<name>/<name>.glb, into game/player/skins (<name>.glb, <name>.json): 3,000
# triangles, a 512 texture, CROSS's 19 joints, CROSS's height (they're made his height, 1.90 m, so
# they aren't scaled). Nothing in the game loads them yet. See build_character.sh for the stages and
# art_source/skins/README.md for each skin.
# Usage (from the project root): art_source/operative/tools/build_skin.sh NAME [tris=3000] [tex=512]
#   NAME: shadow, casual, tropical, midnight, silent, rebel, future or judge
set -euo pipefail
cd "$(dirname "$0")/../../.."
NAME="${1:?skin name}"
SRC="art_source/skins/$NAME/$NAME.glb"
[[ -f "$SRC" ]] || { echo "no source model at $SRC" >&2; exit 1; }

# What every skin's source needs (as Bishop's, see art_source/bishop/README.md): split along its texture
# seams (hundreds of loose pieces), so welded before it's reduced; the remesh no finer than 1.2 cm, or
# it comes apart; the arms hang close, so they're unwrapped apart from the sides; anything the bake
# misses filled from round it; the remesh's loose crumbs dropped; the black gaps between the texture's
# pieces grown over, and their margins made again from the finished colours.
export WELD=1
export VOXEL=0.012
export SPLIT_OVERLAPS=1
export FILL_MISSES=1
export DROP_BITS=1
export GROW_GAPS=1
export REMARGIN=4
# The texture baked from the source at full detail, not the 20k working copy: reduced, a welded source
# smears its texture across its seams (tan flecks on a black jacket; see stage1_reduce.py).
export BAKE_FULL=1
# Each hand turned at the wrist to hang as CROSS's does and its fingers curled closed, so SoldierRig's
# pistol (CROSS's, mounted with his numbers) sits in the fist (see stage4_rig.py; as Bishop's).
export HAND_LIKE="-0.0546,-0.9743,-0.2186;-0.9328,-0.0283,0.3592"
export HAND_CURL=80
POSE=""

# The skin's own needs.
# GUN: the source holds a silenced pistol in his right hand, which the game gives him itself; his
# right hand and the pistol (a box from the hand down past the silencer, metres on the source stood on
# the ground: x across, his right is -x; y front to back; z up) are replaced with his left hand mirrored
# across (MIRROR_BOX, see stage1_reduce.py), which then closes round the game's pistol like the others'.
# The sources are within millimetres of mirror images there. The box stops above the hand but just
# under the watch on his left wrist (Casual, Tropical, Silent), so it isn't mirrored onto his right too.
gun_box() {  # z0 (below the silencer's end), z1 (up the forearm, above the hand)
  export MIRROR_BOX="-0.45,-0.265,-1.0,$1,$2"
}
# BARE: bare hands: the dark creases between the open fingers, curled into a fist, are cleaned off the
# knuckles (HAND_CLEAN, see stage4_rig.py; texels darker than 85% of the hand's middle brightness).
bare() {
  export HAND_CLEAN=0.85
}
# OPEN: made with open hands, fingers spread out flat (Rebel, Future, Judge). Curled as they are, they
# make hooks with spiked fingertips, not fists: the fingers are drawn in together across the hand and
# shortened to half past the knuckles first, then curled 100 degrees, a compact fist round the grip
# (HAND_NARROW, HAND_SHORTEN, HAND_CURL, see stage4_rig.py).
open_hands() {
  export HAND_NARROW="0.035,0.4"
  export HAND_SHORTEN=0.5
  export HAND_CURL=100
}
case "$NAME" in
  shadow)    # long leather coat, sunglasses
    gun_box 0.56 0.97; bare
    # His coat hides his crotch (the remesh joins it to his legs down to 0.69 m): put at CROSS's share
    # of his height, as Vesper's under her skirt (see stage4_rig.py).
    export CROTCH=0.464 ;;
  casual)    # leather flying jacket, jeans, sunglasses
    gun_box 0.59 0.96; bare ;;
  tropical)  # flowered shirt, jeans
    gun_box 0.71 0.975; bare ;;
  midnight)  # dinner suit, bow tie
    gun_box 0.59 0.97; bare ;;
  silent)    # black sneaking suit, shoulder holster; made 8 mm to one side, so centred first
    export CENTRE=1
    gun_box 0.62 0.965; bare ;;
  rebel)     # suede jacket with a scorpion on the back; arms further out, lowered to the A-pose
    open_hands; bare
    POSE=slanted ;;
  future)    # cyber jacket, purple hair, fingerless gloves; arms further out
    open_hands
    POSE=slanted ;;
  judge)     # armour and helmet, gloves; arms further out
    open_hands
    POSE=slanted ;;
  *)
    echo "unknown skin: $NAME" >&2; exit 1 ;;
esac
exec art_source/operative/tools/build_character.sh "$NAME" "$SRC" game/player/skins "${2:-3000}" "${3:-512}" $POSE
