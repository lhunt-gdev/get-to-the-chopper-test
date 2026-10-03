# CROSS (Ernest Cross): source art

The player character's source files. Godot ignores this folder (`art_source/.gdignore`), so
nothing here goes into the game build.

- `ernest-cross.glb`: the Meshy model (about 1.3 million triangles, 2048 textures, 46 MB). It isn't
  committed (see `.gitignore`), so keep your own copy.
- `reference_sheet.png`: the turnaround sheet he was designed from.
- `tools/`: the Blender scripts that turn the Meshy model into the game's model.
- `work/`: what the scripts make along the way (not committed).

## Rebuilding him

From the project root, with Blender 5.2 installed:

```bash
art_source/operative/tools/build_cross.sh
```

It runs the stages in order and writes `game/player/cross.glb` (3,000 triangles, a 512 texture,
rigged with the game's 19 joints) and `game/player/cross.json` (where his goggle lenses are, so
they can glow). Then let Godot re-import (open the editor, or `godot --headless --path . --import`).
Options: `build_cross.sh <triangles> <texture size>`, for example `build_cross.sh 2000 256`.

The stages:

1. `stage1_reduce.py`: imports the Meshy model, stands him on the ground, saves his colour texture
   and reduces him to a 20k-triangle working copy.
2. `stage3_bake.py`: remeshes the working copy into one closed skin (Meshy's surface is loose,
   overlapping pieces that tear when reduced directly), reduces it to the target triangle count,
   unwraps it, and bakes the working copy's base colour onto a fresh texture (packed into the file).
3. `stage4_rig.py`: turns him to face the game's forward (his boots tell which way: the toes reach
   forward), finds his joints from the mesh (the crotch, the armpits, the tops of the shoulders,
   each arm traced down to the fingertips) plus body proportions, builds the skeleton (with
   collarbones), shades him smooth, gives him automatic skin weights (then cleans them up round the
   shoulders and chest), finds his goggle lenses from the green in his texture, and exports.

`preview_rigged.py`, `render_util.py`, `probe_*.py`, `inspect.py` and `preview.py` are for
checking the results (renders and printouts). `find_lenses.py` is the lens finder on its own;
stage 4 does it now.

If the Meshy model changes, drop the new one in as `ernest-cross.glb` and run the script again.
The game's poses (`game/player/soldier_rig.gd`) work from the skeleton's joints, so they carry over.
