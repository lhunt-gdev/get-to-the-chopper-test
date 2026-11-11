# CROSS's skins: source art

Seven of the user's designs, "Cross variation skins, so same hight as Cross": **Shadow, Casual,
Tropical, Midnight, Silent, Rebel and Future** Operative (an eighth, Judge, was taken out: too close to a
well-known comic-book character). Each is a skin to swap with CROSS's in
the game later; nothing in the game loads them yet (see the decision log, "Eight skins for CROSS").
Godot ignores this folder.

- `<name>/<name>.glb`: each skin's high-poly source model (0.3 to 0.9 million faces, three 2048
  textures, no rig, 1.90 m tall as made, CROSS's height, so none is scaled). They aren't committed
  (see `.gitignore`), so keep your own copies; the build never changes them.
- `<name>/work/`: what the build makes along the way (not committed).

Build one from the project root with `art_source/operative/tools/build_skin.sh <name>` (about half a
minute each), which writes `game/player/skins/<name>.glb` (3,000 triangles, a 512 texture, the 19
joints SoldierRig poses) and `game/player/skins/<name>.json` (no goggle lenses). Each skin's settings
are in the `case` block in `build_skin.sh`. How the stages work is in `art_source/operative/README.md`;
the settings Bishop's and Vesper's builds brought in are in `art_source/bishop/README.md` and
`art_source/vesper/README.md`.

What every skin's build does (as Bishop's): `WELD`, `VOXEL=0.012`, `SPLIT_OVERLAPS`, `FILL_MISSES`,
`DROP_BITS`, `GROW_GAPS`, `REMARGIN`, and `HAND_LIKE` so each hand hangs as CROSS's and his pistol sits
in the fist. Besides those, new with the skins (each off unless a build sets it):

- `BAKE_FULL` (stages 1, 1b, 3): the texture is baked from the source at full detail, not from the
  20k working copy. Reduced, a welded source carries its texture across the seams it was split along,
  and the copy wore smears and specks of other colours (a tan fleck on Midnight's black jacket, white
  streaks by his lapels). Stage 1b turns the full source's arms with the copy's.
- The pistol in his hand (Shadow, Casual, Tropical, Midnight, Silent): those sources hold a silenced
  pistol in the right hand, part of the same mesh. The right hand and the pistol are cut away in a box
  and the left hand mirrored in (`MIRROR_BOX`, stage 1), so the right hand (replaced with CROSS's, below)
  takes its colour from a hand, not the gun.
  Where the mirrored hand meets the arm the bake left marks (a faint line, a dark speck, the left cuff's
  cufflink mirrored onto the right): the right wrist is despeckled (`WRIST_CLEAN`, stage 4: a texel unlike
  the middle colour of the texels round it takes that colour).
- `CENTRE` (stage 1): Silent's source stands 8 mm to one side; he's moved to the middle first, or his
  mirrored hand wouldn't meet his arm.
- The hands (stage 4, every skin, and Bishop's and Vesper's): CROSS's own (user: "Cross' current hand
  model is the best fit for the game"), `HAND_FROM`. `extract_cross_hands.py` lifts his two hands out of
  his finished model into `art_source/operative/cross_hands.json` (run it again if CROSS is rebuilt);
  stage 4 cuts the skin's own hand off 2 cm short of the wrist joint, puts CROSS's in at the same place
  on the wrist (so SoldierRig's pistol sits in the fist as in his), joins his glove's cuff to the arm's cut
  edge with a band of faces so the hand stays on the arm as the wrist bends, and colours his hand from
  the skin's own hand (each new face from the nearest part of it, the hand only, not a watch or a cuff at
  the wrist): bare skin, or the skin's own gloves. The watches (Casual, Tropical, Silent) go under the
  cuff. (Tried before: the skins' own hands curled closed, `HAND_CURL` with `HAND_SPIKES`, `HAND_NARROW`,
  `HAND_SHORTEN`, `HAND_TUCK`; and a fist modelled new with the thumb and the index finger on their own.)
- `HAND_CLEAN` (stage 4): bare hands (all but Future's gloves): dark creases and flecks on
  the hand are cleaned off the texture with the hand's own tone before CROSS's hands take their colour
  from it; then the margins round the texture's pieces are made again from the cleaned colours.
- Shadow's coat (stages 3 and 4): his long coat is cut up the back along its own vent, from below the hem
  to 4 cm under the crotch (`CUT_LEGS`, as Vesper's thighs), so each side of it goes with its own leg and
  in a stride the back panel no longer stretches across between his legs; and his crotch, hidden by the
  coat, is put at CROSS's share of his height (`CROTCH`).
- Rebel and Future are made with their arms further out (35 to 40 degrees from hanging); stage 1b
  (`slanted`) lowers them to CROSS's A-pose, level front to back.

After the first import, check each `game/player/skins/<name>_<name>_2980_512.png.import` has
`detect_3d/compress_to=0`, like CROSS's (Godot keeps it from then on).

## The Jungle Operative

Not from a source model of its own: CROSS's finished model (`game/player/cross.glb`) with its texture
repainted, built by `art_source/operative/tools/build_jungle.sh` (`build_jungle.py`) into
`game/player/skins/jungle.glb`; run it again whenever CROSS is rebuilt. His mesh, joints, weights,
hands and goggles are CROSS's byte for byte; only the texture packed in the model is swapped:
- His urban grey-blue camo (on his clothes: not his gloves, boots, face or hair, told by the joint each
  face follows) takes a woodland palette by how light each texel is among them (black-green, brown,
  dark green, olive, a quarter each), so its blotches stay where his were.
- The rest of his grey kit (vest, pouches, knee pads, straps) is tinted olive drab, its light and shade
  kept; his gloves, boots and goggles stay black.
- Camouflage paint across his face under the goggles, placed on him in 3D: a dark green band across
  the bridge of his nose, and two streaks down each cheek, slanting out (black, then dark green), their
  edges wavering as paint put on by hand.

## Rebel's jacket

The source's scorpion on the back (the signature of a well-known film's jacket) is painted out and
replaced (`BACK_EMBLEM`, stage 4): the old emblem's bright gold texels on the back of his torso are filled
with the suede round them on him (the middle colour within 4 cm, with soft blotches like the suede's own),
and the new emblem laid where it was (Rebel's: `BACK_EMBLEM_FIT`, 85% as tall and 3 cm to the right from behind), in the
same gold over a soft dark shadow (`BACK_EMBLEM_SHADOW`, so it stands off the pale suede), taking a little of the suede's light and
shade. The emblem is **the user's own tiger** (`rebel/tiger_source.png`, black on white, made a deeper gold (0.72, 0.47, 0.07) on clear
as `rebel/tiger.png`). The other choice, a cobra drawn for the game (`rebel/cobra.svg`, `cobra.png`):
`BACK_EMBLEM=$PWD/art_source/skins/rebel/cobra.png art_source/operative/tools/build_skin.sh rebel`.
