# Vesper: source art

Vesper's source files (the user's design: an officer in a short-sleeved camo jacket with a peplum,
gold buttons and badges, a white shirt and black tie, a black beret, a short skirt with a side split,
stockings, black gloves and heels). She's a third operative, shorter than CROSS and Bishop, for an
unlockable skin and the conversations later; nothing in the game loads her yet (see the decision log,
"Vesper, a third operative"). Godot ignores this folder.

- `vesper.glb`: the high-poly source model (about 994,000 triangles, three 2048 textures, 1.90 m as
  made, her arms near CROSS's A-pose already, about 21 degrees out). It isn't committed (see
  `.gitignore`), so keep your own copy; the build never changes it.
- `work/`: what the build makes along the way (not committed).

Rebuild her from the project root with `art_source/operative/tools/build_vesper.sh`, which writes
`game/player/vesper.glb` (3,000 triangles, a 512 texture, the 19 joints SoldierRig poses) and
`game/player/vesper.json` (no goggle lenses). How the scripts work is in `art_source/operative/README.md`.

**Her height** is one number at the top of `build_vesper.sh`, `HEIGHT_OF_CROSS` (0.93: 93% of CROSS,
1.765 m; a first guess for the user to check). Change it and rebuild.

What her build does that CROSS's doesn't (each set in `build_vesper.sh`, explained where it's done):

- `MIRROR_BOX` (stage 1): two parts of her back replaced with the other side's, mirrored across, so
  nothing of them is left to bake: the pouch at the back of her belt (taken off, the user's call), and
  a pale triangle in the source's texture up from the back of her skirt's hem.
- `TINT_BOX`, `TINT_FROM` (stage 1): her side split, at the front, shows her leg but the source has it
  tan; it's recoloured to her leg's colour just below it, keeping its light and shade.
- `WELD`, `VOXEL`, `SPLIT_OVERLAPS`, `FILL_MISSES` as Bishop's (see `art_source/bishop/README.md`);
  `DROP_BITS` (stage 3: loose crumbs the remesh leaves dropped); `GROW_GAPS` (stage 3: the black gaps
  between the texture's islands grown over, or thin black marks showed on her thighs).
- `LEG_GAP` (stage 1): her thighs nearly touch, and the remesh webbed them into one panel from her
  skirt down to above her knees. They're parted on the source to at least 5 cm apart from 0.55 m up
  under the skirt to the crotch (the inner side of each thigh moved out, easing to nothing across it,
  the gap closing over its top 4 cm), so her legs are apart right up to the hem and move on their own.
- `CUT_LEGS` (stage 3): the 1.2 cm remesh still joined her thighs with a small bridge just under the
  hem. After the remesh her skin is cut down the middle from mid-thigh up into the skirt, the vertices
  between her legs moved out onto each thigh's inner side and each thigh's opening closed with faces
  of its own, so below the hem nothing joins her legs (no holes; still 3,000 triangles).
- `HEM_INNER` (stage 3): between her legs, up under the skirt, the texture takes the skirt's dark
  colour, so looking up between her thighs it's dark, as under a skirt, not her leg.
- The skirt's texture cleaned up (stage 3): an edge loop round her along the hem so no triangle
  spans it (`HEM_EDGE`; the PS1's affine texturing drew the hem ragged across those, and 200 triangles
  are kept back for the loop: 2,980 in all); leg-coloured specks on the rest of the skirt taken out
  (`HEM_SKIRT`); dark flecks and smudges near the hem smoothed into the texels round them; the strip
  of leg just under the hem, shaded darker in the source, given her leg's tone from just below
  (`HEM_SHADE`); the side split's edge tidied to a clean skirt edge against her leg; and the margins
  round the texture's pieces made again from the cleaned colours (`REMARGIN`), so no dark streaks run
  from the seams.
- `HEM`, `HEM_KEEP` (stages 3 and 4): her skirt is tight on her thighs, so the remesh makes them one
  surface and the bake there was ragged. The texture is straightened along the hem (skirt above, leg
  below; the side split left alone), and the skirt between her legs follows her hips, not her thighs.
- `CROTCH`, `SHOULDER_BAND`, `SHOULDER_X` (stage 4): joints the mesh can't show: the crotch under her
  skirt (at CROSS's share of the height), and her narrower shoulders.
- `HAND_FROM` and `HAND_SCALE` (stage 4): her hands replaced with CROSS's own, scaled to her height
  (user: "the same hand model (scaled down on Vesper)") about the pistol grip's middle, so the gun stays
  in her smaller fist; coloured from her own hands. (See `art_source/skins/README.md`, the hands.)

After a re-import, check `game/player/vesper_vesper_3000_512.png.import` has
`detect_3d/compress_to=0`, like CROSS's.
