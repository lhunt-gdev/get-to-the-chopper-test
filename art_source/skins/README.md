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
`DROP_BITS`, `GROW_GAPS`, `REMARGIN`, and `HAND_LIKE` so each hand hangs as CROSS's and his pistol sits
in the fist. Besides those, new with the skins (each off unless a build sets it):

- `BAKE_FULL` (stages 1, 1b, 3): the texture is baked from the source at full detail, not from the
  20k working copy. Reduced, a welded source carries its texture across the seams it was split along,
  and the copy wore smears and specks of other colours (a tan fleck on Midnight's black jacket, white
  streaks by his lapels). Stage 1b turns the full source's arms with the copy's.
- The pistol in his hand (Shadow, Casual, Tropical, Midnight, Silent): those sources hold a silenced
  pistol in the right hand, part of the same mesh. The right hand and the pistol are cut away in a box
  and the left hand mirrored in (`MIRROR_BOX`, stage 1), which then closes round the game's own pistol.
  The box stops just under the watch on the left wrist (Casual, Tropical, Silent), so he still wears one.
  Where the mirrored hand meets the arm the bake left marks (a faint line, a dark speck, the left cuff's
  cufflink mirrored onto the right): the right wrist is despeckled (`WRIST_CLEAN`, stage 4: a texel unlike
  the middle colour of the texels round it takes that colour).
- `CENTRE` (stage 1): Silent's source stands 8 mm to one side; he's moved to the middle first, or his
  mirrored hand wouldn't meet his arm.
  (Casual's box takes the watch across too, whole: cut under it, half a watch was left on his right wrist.)
- The fists (stage 4, every skin): the fingers curled 80 degrees round the grip (`HAND_CURL`, as Bishop's),
  rounded fists, and any point left sticking out of them (a thumb's tip, a fingertip) smoothed off
  (`HAND_SPIKES`). Rebel's, Future's and Judge's hands are made open with the fingers spread flat: theirs
  are first drawn in together across the hand (`HAND_NARROW`) and shortened to half past the knuckles
  (`HAND_SHORTEN`), then curled 100 degrees. (A compact, squared fist with the thumb tucked in,
  `HAND_TUCK`, was tried and turned down as too blocky; the option is still there, off.)
- `HAND_CLEAN` (stage 4): bare hands (all but Future's and Judge's gloves): the dark creases between
  the open fingers, which show across the knuckles once the hand is a fist, are cleaned off the texture
  with the hand's own tone, and flecks and light scratches on the hand despeckled, from 5 cm past the
  wrist joint on so a watch or a cuff is left whole; then the margins round the texture's pieces are made
  again from the cleaned colours.
- Shadow's coat (stages 3 and 4): his long coat is cut up the back along its own vent, from below the hem
  to 4 cm under the crotch (`CUT_LEGS`, as Vesper's thighs), so each side of it goes with its own leg and
  in a stride the back panel no longer stretches across between his legs; and his crotch, hidden by the
  coat, is put at CROSS's share of his height (`CROTCH`).
- Rebel, Future and Judge are made with their arms further out (35 to 40 degrees from hanging); stage 1b
  (`slanted`) lowers them to CROSS's A-pose, level front to back.

After the first import, check each `game/player/skins/<name>_<name>_3000_512.png.import` has
`detect_3d/compress_to=0`, like CROSS's (Godot keeps it from then on).
