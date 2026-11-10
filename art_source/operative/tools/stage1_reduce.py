# Stage 1: import a character's high-poly source model, stand him on the ground,
# save his colour texture, and reduce him to a 20k-triangle working copy.
# CHAR (environment) names the character's files and objects: "cross" (the default), "guard"...
# The boxes below (MIRROR_BOX) are in metres on the source as made, stood on the ground,
# before any HEIGHT scaling: x across (the source's own +x), y front to back (+y her back), z up.
import bpy, bmesh, sys, math, os, mathutils
name = os.environ.get("CHAR", "cross")
NAME = name.upper()
argv = sys.argv[sys.argv.index("--") + 1:]
src, work = argv[0], argv[1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
mat = meshes[0].data.materials[0]
base = None
for n in mat.node_tree.nodes:
    if n.type == 'BSDF_PRINCIPLED':
        link = n.inputs['Base Color'].links
        if link and link[0].from_node.type == 'TEX_IMAGE':
            base = link[0].from_node.image
print("BASE", base.name if base else None, [(n.type, n.image.name if getattr(n, 'image', None) else '') for n in mat.node_tree.nodes])
obj = meshes[0]
bpy.context.view_layer.objects.active = obj
obj.select_set(True)
# Feet on the ground. (Which way he faces is left to stage 4, which checks his boots.)
mn_z = min((obj.matrix_world @ v.co).z for v in obj.data.vertices)
obj.location.z -= mn_z
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# TINT_BOX="x0,x1,y0,y1,z0,z1" (environment) and TINT_FROM="z0,z1": a patch of the source's colour
# texture the wrong colour (Vesper's side split shows her leg through it, but in a tan, not her
# stockings' colour). On the source's faces in the box, the warm tan texels (red over 1.6 x blue)
# take the average colour of her leg just below (the same box across, TINT_FROM's heights), each
# keeping its own light and shade (scaled by its brightness over the patch's average).
if os.environ.get("TINT_BOX"):
    box = [float(x) for x in os.environ["TINT_BOX"].split(",")]
    lo_z, hi_z = [float(x) for x in os.environ["TINT_FROM"].split(",")]
    me = obj.data
    W, H = base.size
    px = list(base.pixels)
    uvd = me.uv_layers.active.data
    me.calc_loop_triangles()
    def texels(z0, z1):
        out = set()
        for t in me.loop_triangles:
            c = sum((me.vertices[i].co for i in t.vertices), mathutils.Vector()) / 3.0
            if not (box[0] <= c.x <= box[1] and box[2] <= c.y <= box[3] and z0 <= c.z <= z1):
                continue
            p = [uvd[l].uv * mathutils.Vector((W, H)) for l in t.loops]
            for y in range(int(min(q.y for q in p)), int(max(q.y for q in p)) + 1):
                for x in range(int(min(q.x for q in p)), int(max(q.x for q in p)) + 1):
                    e = [(p[(k + 2) % 3].x - p[(k + 1) % 3].x) * (y + 0.5 - p[(k + 1) % 3].y)
                         - (p[(k + 2) % 3].y - p[(k + 1) % 3].y) * (x + 0.5 - p[(k + 1) % 3].x) for k in range(3)]
                    if (all(v >= 0 for v in e) or all(v <= 0 for v in e)) and 0 <= x < W and 0 <= y < H:
                        out.add((y * W + x) * 4)
        return out
    def luma(i):
        return 0.3 * px[i] + 0.59 * px[i + 1] + 0.11 * px[i + 2]
    tan = [i for i in texels(box[4], box[5]) if px[i] > 1.6 * max(px[i + 2], 0.01) and luma(i) > 0.15]
    leg = [i for i in texels(lo_z, hi_z) if 1.25 * px[i + 2] < px[i] <= 1.6 * px[i + 2] and luma(i) > 0.15]
    if tan and leg:
        leg_mean = [sum(px[i + k] for i in leg) / len(leg) for k in range(3)]
        tan_luma = sum(luma(i) for i in tan) / len(tan)
        for i in tan:
            k = luma(i) / tan_luma
            px[i:i + 3] = [min(1.0, c * k) for c in leg_mean]
        base.pixels[:] = px
    print("TINTED", len(tan), "texels to her leg's colour, from", len(leg))
base.filepath_raw = os.path.join(work, f"{name}_basecolor_2048.png")
base.file_format = 'PNG'
base.save()
if os.environ.get("TINT_BOX") and base.packed_file:
    # (the .blend would keep the imported packed copy, without the change: it uses the saved file)
    base.unpack(method='REMOVE')
    base.filepath_raw = os.path.join(work, f"{name}_basecolor_2048.png")
    base.reload()
# MIRROR_BOX="x0,x1,y0,z0,z1[;...]" (environment): parts of one side to replace with the other side's
# (Vesper's: the pouch at the back of her belt, and a pale texture mistake at the back of her skirt).
# Every face inside a box (x0..x1 across, from y0 back, z0..z1 up) goes, and the same box on the other
# side, mirrored across, fills its place: that side's shape and texture, so there's no hole and
# nothing of the part left to bake.
for spec in filter(None, os.environ.get("MIRROR_BOX", "").split(";")):
    x0, x1, y0, z0, z1 = [float(x) for x in spec.split(",")]
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    uvl = bm.loops.layers.uv.active
    def inbox(c, s):
        return x0 <= c.x * s <= x1 and c.y >= y0 and z0 <= c.z <= z1
    gone = [f for f in bm.faces if inbox(f.calc_center_median(), 1)]
    other = [f for f in bm.faces if inbox(f.calc_center_median(), -1)]
    copies = {}
    made = 0
    for f in other:
        vs = []
        for v in reversed(f.verts):  # (mirrored, so the winding is reversed to keep it facing out)
            if v not in copies:
                copies[v] = bm.verts.new(mathutils.Vector((-v.co.x, v.co.y, v.co.z)))
            vs.append(copies[v])
        uvs = [l[uvl].uv.copy() for l in reversed(f.loops)]
        try:
            nf = bm.faces.new(vs, f)
        except ValueError:
            continue
        for l, u in zip(nf.loops, uvs):
            l[uvl].uv = u
        made += 1
    bmesh.ops.delete(bm, geom=gone, context='FACES')
    bm.to_mesh(obj.data)
    bm.free()
    print("MIRRORED", len(gone), "faces taken off,", made, "mirrored in")
# WELD=1 (environment): weld the source's vertices that sit on top of each other (within 0.1 mm) first.
# A source exported split along its texture seams (Bishop's: 2,078 loose pieces) falls apart into
# fragments when reduced, and the remesh in stage 3 can't close them; welded, it's one skin.
if os.environ.get("WELD") == "1":
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    before = len(bm.verts)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0001)
    print("WELDED", before - len(bm.verts), "vertices")
    bm.to_mesh(obj.data)
    bm.free()
# HEIGHT (environment, m): scale him to this height, feet on the ground (Vesper is shorter than CROSS).
if os.environ.get("HEIGHT"):
    h = max(v.co.z for v in obj.data.vertices)
    k = float(os.environ["HEIGHT"]) / h
    obj.data.transform(mathutils.Matrix.Scale(k, 4))
    obj.data.update()
    print("SCALED", round(h, 4), "m to", os.environ["HEIGHT"], "m (x%.4f)" % k)
mod = obj.modifiers.new("reduce", 'DECIMATE')
mod.decimate_type = 'COLLAPSE'
mod.ratio = 20000 / len(obj.data.polygons)
mod.use_collapse_triangulate = True
bpy.ops.object.modifier_apply(modifier=mod.name)
obj.data.calc_loop_triangles()
print("TRIS", len(obj.data.loop_triangles))
obj.name = NAME
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(work, f"{name}_20k.blend"))
print("SAVED")
