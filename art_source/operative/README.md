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
1b. `stage1b_apose.py` (only for a model Meshy made in a T-pose, arms straight out, like the
   guard): lowers his arms to the A-pose the rig expects (about 22 degrees out from hanging, like
   CROSS), bending each shoulder round smoothly so it doesn't crease.
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

## Other characters

The scripts work for any Meshy character, named by the `CHAR` environment variable (file and object
names follow it). `tools/build_character.sh` runs them all for one:

```bash
art_source/operative/tools/build_character.sh NAME SOURCE.glb OUT_DIR [triangles] [texture size] [apose]
```

It works in a `work/` folder next to the source model and writes `OUT_DIR/NAME.glb` and
`OUT_DIR/NAME.json`; `apose` adds stage 1b. `build_cross.sh` is this for CROSS, and
`build_guard.sh` for the guard (`art_source/guard/`, into `game/enemies/guard/`). Every character
built this way has the same 19-joint skeleton, so SoldierRig poses him too: the guard is posed by
`GuardRig` (`game/enemies/guard/guard_rig.gd`, a SoldierRig with a rifle in both hands, no lenses
file: he has no goggles), which the rifle troopers, the pursuit squad and the sniper wear.

`build_scout.sh` and `build_boss.sh` are the same for the scout and the boss (`art_source/scout/`,
`art_source/boss/`, into `game/enemies/scout/` and `game/enemies/boss/`; both T-posed).

The dog has four legs, so his last stage is his own: `build_dog.sh` runs stages 1 and 3 as above,
then `stage4_rig_dog.py`, which turns him to face forward (his head, the highest part, is at one
end), scales him to 0.72 m at the shoulder (the line of his back between his legs), finds his paws,
traces each leg up from its paw to where it meets the body, finds his head and tail, and places a
dog's 19 bones from those and a dog's proportions (hips, spine, chest, neck, head, two in the tail,
three in each leg). The weights are bone heat, worked out at ten times his size (bone heat fails on a
mesh this small, with legs this thin), then each leg below the body kept to its own bones. He writes
`game/enemies/rusher_dog/dog.glb`; `DogRig` (`game/enemies/rusher_dog/dog_rig.gd`) poses him.

After a re-import, check the new texture's `.import` file has `detect_3d/compress_to=0` (Godot
can set 1 the first time, which makes it lossy); CROSS's and the guard's are 0.

