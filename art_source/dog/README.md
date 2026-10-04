# The dog: source art

The guard dog's source files (the user's design: a German Shepherd in a tactical vest). Godot
ignores this folder.

- `dog.glb`: the Meshy model (about 822,000 triangles, 30 MB). It isn't committed (see
  `.gitignore`), so keep your own copy.
- `work/`: what the build makes along the way (not committed).

Rebuild him from the project root with `art_source/operative/tools/build_dog.sh`, which writes
`game/enemies/rusher_dog/dog.glb` (3,000 triangles, a 512 texture), rigged with a dog's 19 bones by
`stage4_rig_dog.py` and scaled to 0.72 m at the shoulder. In the game he's `DogRig`
(`game/enemies/rusher_dog/dog_rig.gd`). How the scripts work is in `art_source/operative/README.md`.
