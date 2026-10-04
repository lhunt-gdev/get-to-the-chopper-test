# The guard: source art

The guard's source files (the user's design: a black balaclava, tan pixel camo, an olive plate
carrier, black gloves and boots, no goggles). Godot ignores this folder.

- `guard-meshy.glb`: the Meshy model made from the sheet (about 443,000 triangles, 19 MB, in a
  T-pose). It isn't committed (see `.gitignore`), so keep your own copy.
- `reference_sheet.png`: the sheet he was made from.
- `work/`: what the build makes along the way (not committed).

Rebuild him from the project root with `art_source/operative/tools/build_guard.sh`, which writes
`game/enemies/guard/guard.glb` (3,000 triangles, a 512 texture). How the scripts work is in
`art_source/operative/README.md`. In the game he's `GuardRig` (`game/enemies/guard/guard_rig.gd`),
with his rifles modelled in code (`guard_rifle.gd`): the rifle troopers, the pursuit squad and the
sniper.
