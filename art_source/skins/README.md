# CROSS's skins: source art

Eight more of the user's designs, "Cross variation skins, so same hight as Cross": **Shadow, Casual,
Tropical, Midnight, Silent, Rebel, Future and Judge** Operative. Each is a skin to swap with CROSS's in
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
`DROP_BITS`, `GROW_GAPS`, `REMARGIN`, and `HAND_LIKE` with `HAND_CURL` so CROSS's pistol sits in each fist.
Besides those, new with the skins (each off unless a build sets it):

- `BAKE_FULL` (stages 1, 1b, 3): the texture is baked from the source at full detail, not from the
  20k working copy. Reduced, a welded source carries its texture across the seams it was split along,
  and the copy wore smears and specks of other colours (a tan fleck on Midnight's black jacket, white
  streaks by his lapels). Stage 1b turns the full source's arms with the copy's.
- The pistol in his hand (Shadow, Casual, Tropical, Midnight, Silent): those sources hold a silenced
  pistol in the right hand, part of the same mesh. The right hand and the pistol are cut away in a box
  and the left hand mirrored in (`MIRROR_BOX`, stage 1), which then closes round the game's own pistol.
  The box stops just under the watch on the left wrist (Casual, Tropical, Silent), so he still wears one.
- `CENTRE` (stage 1): Silent's source stands 8 mm to one side; he's moved to the middle first, or his
  mirrored hand wouldn't meet his arm.
- `HAND_CLEAN` (stage 4): bare hands (all but Future's and Judge's gloves): the dark creases between
  the open fingers, which show across the knuckles once the hand is curled into a fist, are cleaned off
  the texture with the hand's own tone.
- `HAND_NARROW`, `HAND_SHORTEN` (stage 4; Rebel, Future, Judge): their hands are made open with the
  fingers spread flat, and curled as they were they made hooks with spiked fingertips. The fingers are
  drawn in together across the hand and shortened to half past the knuckles, then curled 100 degrees:
  a compact fist round the grip.
- `CROTCH` (stage 4, Shadow): his long coat hides his crotch, so it's put at CROSS's share of his height.
- Rebel, Future and Judge are made with their arms further out (35 to 40 degrees from hanging); stage 1b
  (`slanted`) lowers them to CROSS's A-pose, level front to back.

After the first import, check each `game/player/skins/<name>_<name>_3000_512.png.import` has
`detect_3d/compress_to=0`, like CROSS's (Godot keeps it from then on).
