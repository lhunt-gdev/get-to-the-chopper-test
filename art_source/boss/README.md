# The boss: source art

The boss's source files (the user's design: heavy armour, a skull on his chest). He replaces the
Heavy Trooper (user), and will hold a minigun, to be modelled for him. Godot ignores this folder.

- `boss.glb`: the Meshy model (about 601,000 triangles, 26 MB, in a T-pose). It isn't committed
  (see `.gitignore`), so keep your own copy.
- `work/`: what the build makes along the way (not committed).

Rebuild him from the project root with `art_source/operative/tools/build_boss.sh`, which writes
`game/enemies/boss/boss.glb` (3,000 triangles, a 512 texture, the 19 joints SoldierRig poses).
How the scripts work is in `art_source/operative/README.md`.
