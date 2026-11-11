# CROSS's hands, lifted out of his finished model (game/player/cross.glb) for the other operatives
# (stage4_rig.py, HAND_FROM): each hand's faces that are wholly his wrist's (its vertices at least half
# the wrist bone's), its vertices from the wrist joint in Godot's axes at rest (the frame his pistol is
# mounted in), each with its weights by joint name. The copies glTF makes along texture seams are
# welded back together first. Run once, after CROSS is built:
#   blender --background --factory-startup --python extract_cross_hands.py -- <cross.glb> <out.json>
import bpy, bmesh, sys, json, mathutils

argv = sys.argv[sys.argv.index("--") + 1:]
src, out = argv[0], argv[1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
obj = [o for o in bpy.data.objects if o.type == 'MESH'][0]
names = {g.index: g.name for g in obj.vertex_groups}


def godot(v):
    return mathutils.Vector((v.x, v.z, -v.y))


bm = bmesh.new()
bm.from_mesh(obj.data)
bm.transform(obj.matrix_world)
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
dl = bm.verts.layers.deform.verify()
hands = {}
for s in ("R", "L"):
    wrist = godot(arm.matrix_world @ arm.data.bones["Wrist" + s].head_local)
    gi = obj.vertex_groups["Wrist" + s].index
    on = {v for v in bm.verts if v[dl].get(gi, 0.0) >= 0.5}
    faces = [f for f in bm.faces if all(v in on for v in f.verts)]
    used = sorted({v for f in faces for v in f.verts}, key=lambda v: v.index)
    at = {v: i for i, v in enumerate(used)}
    hands[s] = {
        "verts": [[round(c, 5) for c in (godot(v.co) - wrist)] for v in used],
        "weights": [{names[g]: round(w, 4) for g, w in v[dl].items() if w > 0.0} for v in used],
        "faces": [[at[v] for v in f.verts] for f in faces],
    }
    print("HAND", s, len(used), "vertices,", sum(len(f.verts) - 2 for f in faces), "triangles")
with open(out, "w") as fh:
    json.dump(hands, fh, separators=(",", ":"))
