# The scout: source art

The scout's source files (the user's design: a balaclava, tan camo, a light plate carrier).
Godot ignores this folder.

- `scout.glb`: the Meshy model (about 423,000 triangles, 19 MB, in a T-pose). It isn't committed
  (see `.gitignore`), so keep your own copy.
- `work/`: what the build makes along the way (not committed).

Rebuild him from the project root with `art_source/operative/tools/build_scout.sh`, which writes
`game/enemies/scout/scout.glb` (3,000 triangles, a 512 texture, the 19 joints SoldierRig poses).
He's the alarm runner (user: "the alarm guard"; game/enemies/security_trooper/security_trooper.gd), unarmed, posed by `GuardRig` without a rifle. How the scripts work is in `art_source/operative/README.md`.
