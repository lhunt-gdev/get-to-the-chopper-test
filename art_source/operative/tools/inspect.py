import bpy, sys, mathutils
bpy.ops.wm.read_factory_settings(use_empty=True)
path = sys.argv[sys.argv.index("--") + 1]
bpy.ops.import_scene.gltf(filepath=path)
tris = 0
for o in bpy.data.objects:
    line = f"OBJ {o.name} type={o.type} parent={o.parent.name if o.parent else None} loc={tuple(round(v,3) for v in o.location)} rot={tuple(round(v,3) for v in o.rotation_euler)} scale={tuple(round(v,3) for v in o.scale)}"
    if o.type == 'MESH':
        me = o.data
        me.calc_loop_triangles()
        t = len(me.loop_triangles); tris += t
        bb = [o.matrix_world @ mathutils.Vector(c) for c in o.bound_box]
        mn = [round(min(v[i] for v in bb), 3) for i in range(3)]; mx = [round(max(v[i] for v in bb), 3) for i in range(3)]
        line += f" verts={len(me.vertices)} tris={t} uvs={len(me.uv_layers)} mats={[m.name for m in me.materials]} bbox={mn}..{mx} vgroups={len(o.vertex_groups)}"
    if o.type == 'ARMATURE':
        line += f" bones={len(o.data.bones)} " + ",".join(b.name for b in o.data.bones)
    print(line)
print("TOTAL_TRIS", tris)
for m in bpy.data.materials:
    texs = [n.image.name + f"{tuple(n.image.size)}" for n in (m.node_tree.nodes if m.node_tree else []) if n.type == 'TEX_IMAGE' and n.image]
    print("MAT", m.name, texs)
for img in bpy.data.images:
    print("IMG", img.name, tuple(img.size), img.filepath)
print("ANIMS", [a.name for a in bpy.data.actions])
