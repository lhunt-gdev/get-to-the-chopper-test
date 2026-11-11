#!/usr/bin/env bash
# Builds one of CROSS's skins (the decision log's "Eight skins for CROSS") from its high-poly source
# model, art_source/skins/<name>/<name>.glb, into game/player/skins (<name>.glb, <name>.json): 3,000
# triangles, a 512 texture, CROSS's 19 joints, CROSS's height (they're made his height, 1.90 m, so
# they aren't scaled). Nothing in the game loads them yet. See build_character.sh for the stages and
# art_source/skins/README.md for each skin.
# Usage (from the project root): art_source/operative/tools/build_skin.sh NAME [tris=3000] [tex=512]
#   NAME: shadow, casual, tropical, midnight, silent, rebel, future or street
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
# Each hand replaced with CROSS's own (user: "Cross' current hand model is the best fit for the game"):
# his fists' shape, at the same place on the wrist, so SoldierRig's pistol (CROSS's, mounted with his
# numbers) sits in them as in his; coloured from the skin's own hand (HAND_FROM, see stage4_rig.py and
# extract_cross_hands.py). The wrist is first turned to hang as CROSS's does (HAND_LIKE), so the arm
# runs into them as his does.
export HAND_LIKE="-0.0546,-0.9743,-0.2186;-0.9328,-0.0283,0.3592"
export HAND_FROM="$PWD/art_source/operative/cross_hands.json"
POSE=""

# The skin's own needs.
# GUN: the source holds a silenced pistol in his right hand, which the game gives him itself; his
# right hand and the pistol (a box from the hand down past the silencer, metres on the source stood on
# the ground: x across, his right is -x; y front to back; z up) are replaced with his left hand mirrored
# across (MIRROR_BOX, see stage1_reduce.py), so the right hand takes its colour from a hand, not the gun.
# The sources are within millimetres of mirror images there.
# Where the mirrored hand meets his arm the bake left marks (a faint line, a dark speck, the left cuff's
# cufflink on the right): the right wrist, from 8 cm up the arm to 6 cm past the joint, is despeckled
# (WRIST_CLEAN, see stage4_rig.py).
gun_box() {  # z0 (below the silencer's end), z1 (up the forearm, above the hand)
  export MIRROR_BOX="-0.45,-0.265,-1.0,$1,$2"
  export WRIST_CLEAN="-0.08,0.06"
}
# BARE: bare hands: dark creases and flecks on the hand cleaned off the texture, so CROSS's fists take
# an even skin colour from it (HAND_CLEAN, see stage4_rig.py; texels darker than 85% of the hand's middle
# brightness).
bare() {
  export HAND_CLEAN=0.85
}
case "$NAME" in
  shadow)    # long leather coat, sunglasses
    gun_box 0.56 0.97; bare
    # His coat hides his crotch (the remesh joins it to his legs down to 0.69 m): put at CROSS's share
    # of his height, as Vesper's under her skirt (see stage4_rig.py).
    export CROTCH=0.464
    # His coat cut up the back, along its own vent, from below the hem to 4 cm under the crotch
    # (CUT_LEGS, stage 3): each side of it goes with its own leg, and in a stride the back panel no
    # longer stretches across between his legs.
    export CUT_LEGS="0.2,0.84,0.012" ;;
  casual)    # leather flying jacket, jeans, sunglasses
    gun_box 0.59 0.96; bare ;;
  tropical)  # flowered shirt, jeans
    gun_box 0.71 0.975; bare ;;
  midnight)  # dinner suit, bow tie
    gun_box 0.59 0.97; bare ;;
  silent)    # black sneaking suit, shoulder holster; made 8 mm to one side, so centred first
    export CENTRE=1
    gun_box 0.62 0.965; bare ;;
  rebel)     # suede jacket with a tiger on the back; arms further out, lowered to the A-pose
    bare
    # The source's scorpion on his back (a well-known film's jacket's) painted out and the user's tiger laid
    # where it was (BACK_EMBLEM, see stage4_rig.py; art_source/skins/rebel/tiger_source.png, the user's own
    # drawing, made gold on clear as tiger.png).
    export BACK_EMBLEM="${BACK_EMBLEM:-$PWD/art_source/skins/rebel/tiger.png}"  # (or cobra.png, the other choice)
    # (85% of the scorpion's height, 3 cm to the right from behind; a soft shadow just behind it, a
    # third dark at most, half a centimetre down, so it stands off the pale suede)
    export BACK_EMBLEM_FIT="${BACK_EMBLEM_FIT:-0.85,0.03}"
    export BACK_EMBLEM_SHADOW="${BACK_EMBLEM_SHADOW:-0.35,0.005}"
    POSE=slanted ;;
  future)    # cyber jacket, purple hair, fingerless gloves; arms further out
    # A tech insignia drawn for the game on his back, in his jacket's own violet, between his shoulder
    # blades (BACK_EMBLEM, BACK_EMBLEM_AT: x, and from 1.23 to 1.49 m up; art_source/skins/future/emblem.svg,
    # drawn as emblem.png).
    export BACK_EMBLEM="$PWD/art_source/skins/future/emblem.png"
    export BACK_EMBLEM_AT="${BACK_EMBLEM_AT:-0,1.23,1.49}"
    POSE=slanted ;;
  street)    # black leather jacket, red T-shirt, red headband, dark glasses, ripped jeans, red high-tops,
             # fingerless gloves; arms further out
    # CROSS's hands gloved in his own black leather, not patched with the skin his fingerless gloves
    # show (HAND_DARK); the round patch on each high-top's ankle, a trainer brand's own mark, painted
    # out in the shoe's red (ANKLE_PATCH; see stage4_rig.py).
    export HAND_DARK=1
    export ANKLE_PATCH=1
    # (his splayed fingerless-glove hands: the arm traced on past their knuckles to his real fingertips)
    export ARM_TRACE="0.09,3"
    POSE=slanted ;;
  *)
    echo "unknown skin: $NAME" >&2; exit 1 ;;
esac
# 2,980: CROSS's hands and the band joining them to the arm come to about 20 more triangles than the
# skin's own hands on some (Shadow's), so the rest is reduced to that much less; 3,000 in all.
exec art_source/operative/tools/build_character.sh "$NAME" "$SRC" game/player/skins "${2:-2980}" "${3:-512}" $POSE
