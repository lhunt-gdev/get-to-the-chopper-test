# Stage 3: a clean low-poly character (CHAR, as in stage 1). The 20k working copy is remeshed into one closed skin,
# reduced to the target triangle count, unwrapped, and the working copy's colours are baked onto
# a fresh texture for it (the standard game-art route: the high-poly surface is loose overlapping pieces
# that don't reduce cleanly on their own).
import bpy, bmesh, sys, os, mathutils
sys.path.append(os.path.dirname(__file__))
import render_util
name = os.environ.get("CHAR", "cross")
NAME = name.upper()
argv = sys.argv[sys.argv.index("--") + 1:]
work, out, target, tex = argv[0], argv[1], int(argv[2]), int(argv[3])
voxel = float(argv[4]) if len(argv) > 4 else 0.008
bpy.ops.wm.open_mainfile(filepath=os.path.join(work, f"{name}_20k.blend"))
src = bpy.data.objects[NAME]
src.name = f"{NAME}_high"
low = src.copy(); low.data = src.data.copy(); low.name = f"{NAME}_low"
bpy.context.scene.collection.objects.link(low)
for o in bpy.context.selected_objects: o.select_set(False)
bpy.context.view_layer.objects.active = low; low.select_set(True)
rm = low.modifiers.new("remesh", 'REMESH'); rm.mode = 'VOXEL'; rm.voxel_size = voxel; rm.adaptivity = 0.0
bpy.ops.object.modifier_apply(modifier=rm.name)
print("REMESHED", len(low.data.polygons))
dm = low.modifiers.new("reduce", 'DECIMATE'); dm.decimate_type = 'COLLAPSE'; dm.use_collapse_triangulate = True
low.data.calc_loop_triangles()
dm.ratio = target / max(1, len(low.data.loop_triangles))  # target is in triangles
bpy.ops.object.modifier_apply(modifier=dm.name)
low.data.calc_loop_triangles()
print("LOW_TRIS", len(low.data.loop_triangles))
# Fresh UVs for the low-poly.
while low.data.uv_layers:
    low.data.uv_layers.remove(low.data.uv_layers[0])
low.data.uv_layers.new(name="UVMap")
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=0.003, area_weight=0.0, scale_to_bounds=False)
bpy.ops.uv.pack_islands(rotate=True, margin=0.003)  # fill the whole texture
bpy.ops.object.mode_set(mode='OBJECT')


def overlapping_faces(me, n=512):
    """Faces whose UVs lie over another face's (drawn onto an n x n grid): they'd share texels, so
    one would wear the other's colours (Bishop's thigh wore his hand)."""
    grid = {}
    out = set()
    uvd = me.uv_layers.active.data
    me.calc_loop_triangles()
    for t in me.loop_triangles:
        p = [uvd[l].uv * n for l in t.loops]
        for y in range(int(min(q.y for q in p)), int(max(q.y for q in p)) + 1):
            for x in range(int(min(q.x for q in p)), int(max(q.x for q in p)) + 1):
                cx, cy = x + 0.5, y + 0.5
                e = [(p[(k + 2) % 3].x - p[(k + 1) % 3].x) * (cy - p[(k + 1) % 3].y)
                     - (p[(k + 2) % 3].y - p[(k + 1) % 3].y) * (cx - p[(k + 1) % 3].x) for k in range(3)]
                if all(v > 0 for v in e) or all(v < 0 for v in e):
                    o = grid.get((x, y))
                    if o is not None and o != t.polygon_index:
                        out.add(o)
                        out.add(t.polygon_index)
                    grid[(x, y)] = t.polygon_index
    return out


# SPLIT_OVERLAPS=1 (environment): smart project gathers faces turned the same way into one island,
# and an arm hanging close to the body can be joined to the body's side through the armpit, its
# outside then projected right over the body's side. Those faces are unwrapped again on their own
# (a tighter angle) and everything packed again, until nothing overlaps.
if os.environ.get("SPLIT_OVERLAPS") == "1":
    for _ in range(8):
        bad = overlapping_faces(low.data)
        print("UV_OVERLAPS", len(bad), "faces")
        if not bad:
            break
        bpy.ops.object.mode_set(mode='EDIT')
        bpy.ops.mesh.select_mode(type='FACE')
        bm = bmesh.from_edit_mesh(low.data)
        bm.faces.ensure_lookup_table()
        for f in bm.faces:
            f.select_set(False)
        for i in bad:
            bm.faces[i].select_set(True)
        bm.select_flush_mode()
        bmesh.update_edit_mesh(low.data)
        bpy.ops.uv.smart_project(angle_limit=0.6, island_margin=0.003, area_weight=0.0, scale_to_bounds=False)
        bpy.ops.mesh.select_all(action='SELECT')
        bpy.ops.uv.select_all(action='SELECT')
        bpy.ops.uv.average_islands_scale()  # (the new islands at the same texels per metre as the rest)
        bpy.ops.uv.pack_islands(rotate=True, margin=0.003)
        bpy.ops.object.mode_set(mode='OBJECT')
# A new material and image for the bake target.
img = bpy.data.images.new(f"{name}_bake", tex * 2, tex * 2, alpha=False)
m = bpy.data.materials.new(NAME); m.use_nodes = True
nt = m.node_tree
bsdf = [n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED'][0]
tn = nt.nodes.new('ShaderNodeTexImage'); tn.image = img
nt.links.new(tn.outputs['Color'], bsdf.inputs['Base Color'])
nt.nodes.active = tn
low.data.materials.clear(); low.data.materials.append(m)
# Bake the working copy's colour onto it.
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = 4
scene.render.bake.use_selected_to_active = True
scene.render.bake.cage_extrusion = 0.03
scene.render.bake.max_ray_distance = 0.12
scene.render.bake.margin = 4
scene.render.bake.use_pass_direct = False
scene.render.bake.use_pass_indirect = False
scene.render.bake.use_pass_color = True
# Bake the base colour only: with metallic at 0 the diffuse colour pass is exactly the base colour.
for m_src in src.data.materials:
    for n in m_src.node_tree.nodes:
        if n.type == 'BSDF_PRINCIPLED':
            for l in list(n.inputs['Metallic'].links):
                m_src.node_tree.links.remove(l)
            n.inputs['Metallic'].default_value = 0.0
src.select_set(True); low.select_set(True); bpy.context.view_layer.objects.active = low
bpy.ops.object.bake(type='DIFFUSE', pass_filter={'COLOR'})
# FILL_MISSES=1 (environment): a face folded into a crease (Bishop's, at his hairline) can send all
# its rays past the source and stay black (exactly black: nothing the source has), a black chip in
# the game. Each such face is filled with the average colour of the faces round it.
if os.environ.get("FILL_MISSES") == "1":
    W, H = img.size
    pix = list(img.pixels)
    uvd = low.data.uv_layers.active.data
    low.data.calc_loop_triangles()
    tris = list(low.data.loop_triangles)
    def texel(u):
        return (min(H - 1, max(0, int(u.y * H))) * W + min(W - 1, max(0, int(u.x * W)))) * 4
    def centre_colour(t):
        u = sum((uvd[l].uv for l in t.loops), mathutils.Vector((0.0, 0.0))) / 3.0
        i = texel(u)
        return pix[i:i + 3]
    by_vert = {}
    for t in tris:
        for v in t.vertices:
            by_vert.setdefault(v, []).append(t)
    filled = 0
    for t in tris:
        if any(c != 0.0 for c in centre_colour(t)):
            continue
        near = [centre_colour(o) for v in t.vertices for o in by_vert[v] if o is not t]
        near = [c for c in near if any(x != 0.0 for x in c)]
        if not near:
            continue
        col = [sum(c[k] for c in near) / len(near) for k in range(3)]
        p = [uvd[l].uv * mathutils.Vector((W, H)) for l in t.loops]
        for y in range(int(min(q.y for q in p)) - 2, int(max(q.y for q in p)) + 3):
            for x in range(int(min(q.x for q in p)) - 2, int(max(q.x for q in p)) + 3):
                if not (0 <= x < W and 0 <= y < H):
                    continue
                # inside the triangle, or within 2 texels of it (the bake's own margin)
                d = max(((p[(k + 2) % 3].x - p[(k + 1) % 3].x) * (y + 0.5 - p[(k + 1) % 3].y)
                         - (p[(k + 2) % 3].y - p[(k + 1) % 3].y) * (x + 0.5 - p[(k + 1) % 3].x))
                        / max(1e-6, (p[(k + 2) % 3] - p[(k + 1) % 3]).length) * (1 if (p[1] - p[0]).cross(p[2] - p[0]) > 0 else -1) * -1
                        for k in range(3))
                i = (y * W + x) * 4
                if d <= 2.0 and pix[i] == 0.0 and pix[i + 1] == 0.0 and pix[i + 2] == 0.0:
                    pix[i:i + 3] = col
        filled += 1
    img.pixels[:] = pix
    print("FILLED", filled, "faces the bake missed")
img.scale(tex, tex)  # baked at twice the size, scaled down: cleaner edges
img.filepath_raw = os.path.join(work, f"{name}_{target}_{tex}.png"); img.file_format = 'PNG'; img.save()
img.pack()  # kept inside the .blend, so the later stages don't depend on this machine's paths
print("BAKED", img.filepath_raw)
bpy.data.objects.remove(src)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(work, f"{name}_low_{target}.blend"))
h = max((low.matrix_world @ v.co).z for v in low.data.vertices)
scene.render.engine = 'BLENDER_WORKBENCH'
render_util.render(f"{out}/low{target}", mathutils.Vector((0, 0, h / 2)), h * 1.06)
render_util.render(f"{out}/low{target}_head", mathutils.Vector((0, 0, h - 0.14)), 0.4, angles=(("front", 0), ("left", 90), ("back", 180)), resx=400, resy=400)
print("DONE")
