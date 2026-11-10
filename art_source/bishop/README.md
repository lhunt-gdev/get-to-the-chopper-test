# Bishop: source art

Bishop's source files (the user's design: a grey-haired officer in a camo dress jacket with
epaulettes and ribbons, a shirt and black tie, camo trousers, a thigh holster, dress shoes). He's a
second operative, as tall as CROSS, for an unlockable skin and the conversations later; nothing in the
game loads him yet (see the decision log, "Bishop, a second operative"). Godot ignores this folder.

- `bishop.glb`: the high-poly source model (about 1,150,000 triangles, three 2048 textures, 38 MB, his
  arms partway down, about 40 degrees out from hanging). It isn't committed (see `.gitignore`), so
  keep your own copy.
- `work/`: what the build makes along the way (not committed).

Rebuild him from the project root with `art_source/operative/tools/build_bishop.sh`, which writes
`game/player/bishop.glb` (3,000 triangles, a 512 texture, the 19 joints SoldierRig poses) and
`game/player/bishop.json` (no goggle lenses). He's 1.90 m as made, CROSS's height, so he isn't scaled.
How the scripts work is in `art_source/operative/README.md`.

His source needs four things the others didn't, each switched on in `build_bishop.sh`:

- `WELD=1`: the source is split along its texture seams (2,078 loose pieces), which fall apart when
  reduced; its vertices are welded first, so it's one skin.
- `slanted` (stage 1b): his arms are made partway down, not in a T-pose, so each arm's line is measured
  and turned down only the rest of the way to CROSS's A-pose (about 18 degrees).
- `VOXEL=0.012`: the remesh's voxel size (1.2 cm, not 0.8): finer, his reduced copy comes apart into
  hundreds of pieces.
- `SPLIT_OVERLAPS=1` and `FILL_MISSES=1`: his hanging arms were unwrapped over his sides (his thigh
  wore his hand's colours), so overlapping faces are unwrapped again apart; and a face folded in at
  his hairline missed the bake (a black chip), so it's filled from the faces round it.

After a re-import, check `game/player/bishop_bishop_3000_512.png.import` has
`detect_3d/compress_to=0`, like CROSS's.
