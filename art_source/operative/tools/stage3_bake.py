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
# The full-detail source, when stage 1 kept one (BAKE_FULL): the texture is baked from it, not the 20k copy.
full = bpy.data.objects.get(f"{NAME}_full")
bake_src = full or src
low = src.copy(); low.data = src.data.copy(); low.name = f"{NAME}_low"
bpy.context.scene.collection.objects.link(low)
for o in bpy.context.selected_objects: o.select_set(False)
bpy.context.view_layer.objects.active = low; low.select_set(True)
rm = low.modifiers.new("remesh", 'REMESH'); rm.mode = 'VOXEL'; rm.voxel_size = voxel; rm.adaptivity = 0.0
bpy.ops.object.modifier_apply(modifier=rm.name)
print("REMESHED", len(low.data.polygons))
# DROP_BITS=1 (environment): the remesh can leave a few crumbs floating loose beside the skin (bits
# of the source thinner than a voxel); anything under 1% of the biggest piece is dropped, so it
# isn't reduced, baked and rigged along with him (Vesper's: 14 crumbs of 8-12 vertices).
if os.environ.get("DROP_BITS") == "1":
    bm = bmesh.new()
    bm.from_mesh(low.data)
    bm.verts.ensure_lookup_table()
    seen = set()
    parts = []
    for v in bm.verts:
        if v.index in seen:
            continue
        part = [v]
        seen.add(v.index)
        k = 0
        while k < len(part):
            for e in part[k].link_edges:
                w = e.other_vert(part[k])
                if w.index not in seen:
                    seen.add(w.index)
                    part.append(w)
            k += 1
        parts.append(part)
    biggest = max(len(p) for p in parts)
    crumbs = [v for p in parts if len(p) < biggest * 0.01 for v in p]
    bmesh.ops.delete(bm, geom=crumbs, context='VERTS')
    bm.to_mesh(low.data)
    bm.free()
    print("DROPPED", len(parts) - sum(1 for p in parts if len(p) >= biggest * 0.01), "loose bits,", len(crumbs), "vertices")
# CUT_LEGS="z_from,z_to,x_edge" (environment, m): legs the remesh joined (Vesper's thighs, a little
# bridge just under her skirt's hem, inside 1.2 cm voxels): cut apart, before the reduction. The
# remeshed skin is split down the middle (x = 0) from z_from up to z_to (up inside the skirt, out of
# sight), every vertex between the legs there is moved out onto its own thigh's inner side (x_edge
# from the middle), and each thigh's opened side is closed with new faces lying on it: below z_to
# nothing joins her legs, and each is whole.
if os.environ.get("CUT_LEGS"):
    z_from, z_to, x_edge = [float(v) for v in os.environ["CUT_LEGS"].split(",")]
    bm = bmesh.new()
    bm.from_mesh(low.data)
    region = [f for f in bm.faces if abs(f.calc_center_median().x) < 0.1 and z_from - 0.02 < f.calc_center_median().z < z_to + 0.02]
    geom = list({v for f in region for v in f.verts}) + list({e for f in region for e in f.edges}) + region
    bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(0, 0, 0), plane_no=(1, 0, 0), dist=1e-5)
    cut = [e for e in bm.edges if all(abs(v.co.x) < 1e-4 and z_from <= v.co.z <= z_to for v in e.verts) and len(e.link_faces) == 2]
    bmesh.ops.split_edges(bm, edges=cut)
    moved = 0
    for v in bm.verts:
        if abs(v.co.x) >= x_edge or not (z_from <= v.co.z <= z_to) or not v.link_faces:
            continue
        sides = [f.calc_center_median().x for f in v.link_faces]
        if min(sides) < 0.0 < max(sides):
            continue  # (still on both legs: where the cut stops, up in the skirt)
        v.co.x = x_edge if sum(sides) > 0 else -x_edge
        moved += 1
    bm.normal_update()
    # Each opening (a loop of open edges) runs down one thigh and back up the other, joined where the
    # cut stopped (the vertices left at x = 0, up in the skirt): it's closed a thigh at a time, each
    # stretch between two of those joins made a face of its own (so nothing spans between her legs).
    made = []
    seen = set()
    for e0 in [e for e in bm.edges if e.is_boundary]:
        if e0 in seen:
            continue
        loop = [e0.verts[0]]
        e, v = e0, e0.verts[1]
        seen.add(e)
        while v != loop[0]:
            loop.append(v)
            nxt = [x for x in v.link_edges if x.is_boundary and x not in seen]
            if not nxt:
                break
            e = nxt[0]
            seen.add(e)
            v = e.other_vert(v)
        joins = [i for i, w in enumerate(loop) if abs(w.co.x) < 1e-4]
        if len(joins) < 2:
            continue
        for a, b in zip(joins, joins[1:] + [joins[0] + len(loop)]):
            chain = [loop[i % len(loop)] for i in range(a, b + 1)]
            if len(chain) >= 3:
                try:
                    made.append(bm.faces.new(chain))
                except ValueError:
                    pass
    made = bmesh.ops.triangulate(bm, faces=made)["faces"]
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(low.data)
    bm.free()
    low.data.update()
    print("CUT_LEGS split %d edges, moved %d vertices out to the thighs, closed %d openings" % (len(cut), moved, len(made)))
dm = low.modifiers.new("reduce", 'DECIMATE'); dm.decimate_type = 'COLLAPSE'; dm.use_collapse_triangulate = True
low.data.calc_loop_triangles()
# HEM_EDGE="z,reserve" (environment): an edge loop round her at height z (her skirt's hem), so no
# triangle spans the hem: the PS1's affine texturing bends the texture across a big triangle, and
# the hem drew ragged across the ones that spanned it. `reserve` triangles are kept back from the
# reduction for the loop, so it stays within the budget.
hem_edge = [float(v) for v in os.environ["HEM_EDGE"].split(",")] if os.environ.get("HEM_EDGE") else None
dm.ratio = (target - (int(hem_edge[1]) if hem_edge else 0)) / max(1, len(low.data.loop_triangles))  # target is in triangles
bpy.ops.object.modifier_apply(modifier=dm.name)
low.data.calc_loop_triangles()
print("LOW_TRIS", len(low.data.loop_triangles))
if hem_edge:
    bm = bmesh.new()
    bm.from_mesh(low.data)
    near = [f for f in bm.faces if abs(f.calc_center_median().x) < 0.22 and abs(f.calc_center_median().z - hem_edge[0]) < 0.06]
    geom = list({v for f in near for v in f.verts}) + list({e for f in near for e in f.edges}) + near
    bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(0, 0, hem_edge[0]), plane_no=(0, 0, 1), dist=1e-4)
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 3])
    bm.to_mesh(low.data)
    bm.free()
    low.data.update()
    low.data.calc_loop_triangles()
    print("LOW_TRIS with the hem's edge loop", len(low.data.loop_triangles))
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
for m_src in bake_src.data.materials:
    for n in m_src.node_tree.nodes:
        if n.type == 'BSDF_PRINCIPLED':
            for l in list(n.inputs['Metallic'].links):
                m_src.node_tree.links.remove(l)
            n.inputs['Metallic'].default_value = 0.0
bake_src.select_set(True); low.select_set(True); bpy.context.view_layer.objects.active = low
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
# HEM=z (environment, m): a skirt's hem, straight at height z. Where the skirt is tight on the
# thighs the remesh makes them one surface, and the bake there lands ragged: skirt-coloured spikes
# and drips down the thighs, leg-coloured teeth up into the skirt. On the baked texture, below the hem
# (down 0.3 m) every skirt-coloured texel (cooler: red under 1.4 x blue, or under 70% of her legs'
# own brightness) takes the colour of the nearest leg-coloured one below the hem, and in a 1.5 cm band
# above it every leg-coloured one the nearest skirt-coloured one above it, so the hem reads straight,
# with each side's own texture. HEM_KEEP="x0,x1,y0,y1" (m) leaves the band above alone there (her
# side split, which shows her leg).
if os.environ.get("HEM"):
    hem = float(os.environ["HEM"])
    keep = [float(x) for x in os.environ["HEM_KEEP"].split(",")] if os.environ.get("HEM_KEEP") else None
    # HEM_INNER="x,z,bx,bz" (m): between her legs the skirt's colour too, as under a skirt: within x of
    # the middle up under the skirt to z (the insides of her thighs in there), and within bx of it
    # from bz below the hem up to it (where the remesh closes the gap between her thighs just under the
    # hem, a little rounded: the underneath of the skirt there, seen between her legs).
    inner_x, inner_z, under_x, under_z = [float(v) for v in os.environ["HEM_INNER"].split(",")] if os.environ.get("HEM_INNER") else (0.0, 0.0, 0.0, 0.0)
    # HEM_SKIRT="top,x" (m): the rest of the skirt too, up to `top` and within x of the middle (her
    # hands hang further out): any warm, leg-coloured texel on it is a speck (Vesper's: an orange one on
    # the back) and takes the skirt's colour; her side split (HEM_KEEP) is left out, and only tidied
    # (see below).
    skirt_top, skirt_x = [float(v) for v in os.environ["HEM_SKIRT"].split(",")] if os.environ.get("HEM_SKIRT") else (0.0, 0.0)
    split = set()  # texels on her side split
    zmap = {}  # texel -> its height on her
    W, H = img.size
    pix = list(img.pixels)
    uvd = low.data.uv_layers.active.data
    low.data.calc_loop_triangles()
    side = {}  # texel -> True below the hem, False in the band above it
    for t in low.data.loop_triangles:
        cs = [low.data.vertices[i].co for i in t.vertices]
        if max(c.z for c in cs) < hem - 0.3 or min(c.z for c in cs) > max(hem + 0.015, inner_z, skirt_top):
            continue
        p = [uvd[l].uv * mathutils.Vector((W, H)) for l in t.loops]
        area = (p[1] - p[0]).cross(p[2] - p[0])
        if abs(area) < 1e-9:
            continue
        for y in range(int(min(q.y for q in p)), int(max(q.y for q in p)) + 1):
            for x in range(int(min(q.x for q in p)), int(max(q.x for q in p)) + 1):
                c = mathutils.Vector((x + 0.5, y + 0.5))
                w0 = (p[2] - p[1]).cross(c - p[1]) / area
                w1 = (p[0] - p[2]).cross(c - p[2]) / area
                w2 = 1.0 - w0 - w1
                if min(w0, w1, w2) < -0.02 or not (0 <= x < W and 0 <= y < H):
                    continue
                z = cs[0].z * w0 + cs[1].z * w1 + cs[2].z * w2
                zmap[(x, y)] = z
                ax = abs(cs[0].x * w0 + cs[1].x * w1 + cs[2].x * w2)
                if hem - under_z <= z < hem and ax < under_x:
                    side[(x, y)] = None
                elif hem - 0.3 <= z < hem:
                    side[(x, y)] = True
                elif hem <= z <= inner_z and ax < inner_x:
                    side[(x, y)] = None
                elif hem <= z <= max(hem + 0.015, skirt_top):
                    px_ = cs[0].x * w0 + cs[1].x * w1 + cs[2].x * w2
                    py_ = cs[0].y * w0 + cs[1].y * w1 + cs[2].y * w2
                    if keep and keep[0] <= px_ <= keep[1] and keep[2] <= py_ <= keep[3]:
                        split.add((x, y))
                    elif z <= hem + 0.015:
                        side[(x, y)] = False
                    elif ax < skirt_x:
                        side[(x, y)] = None
    def luma(q):
        i = (q[1] * W + q[0]) * 4
        return 0.3 * pix[i] + 0.59 * pix[i + 1] + 0.11 * pix[i + 2]
    # (the legs' own brightness: the middle of the warm texels below the hem)
    legs = sorted(luma(q) for q, below in side.items() if below and pix[(q[1] * W + q[0]) * 4] >= 1.4 * pix[(q[1] * W + q[0]) * 4 + 2])
    dark = 0.7 * legs[len(legs) // 2] if legs else 0.0
    def cool(q):  # (skirt-coloured: cooler, or much darker than her legs)
        i = (q[1] * W + q[0]) * 4
        return pix[i] < 1.4 * pix[i + 2] or luma(q) < dark
    def warm(q):
        i = (q[1] * W + q[0]) * 4
        return pix[i] >= 1.4 * pix[i + 2]
    # (None: between her legs under the skirt, HEM_INNER: anything warm there, even darkened, is her leg
    # showing; it takes the skirt's colour like the band above the hem)
    wrong = {q for q, below in side.items() if (warm(q) if below is None else cool(q) == below)}
    for q in side:
        if side[q] is None:
            side[q] = False
    src_of = {q: q for q in side if q not in wrong}
    front = list(src_of)
    while front:
        nxt = []
        for (x, y) in front:
            for d in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                q = (x + d[0], y + d[1])
                if q in wrong and q not in src_of and side[q] == side[(x, y)]:
                    src_of[q] = src_of[(x, y)]
                    nxt.append(q)
        front = nxt
    # (a texel with no right-coloured one joined to it, on a piece of the texture all on the wrong
    # side, takes the average of that side's right-coloured texels)
    mean = {}
    for below in (True, False):
        good = [(q[1] * W + q[0]) * 4 for q, b in side.items() if b == below and q not in wrong]
        mean[below] = [sum(pix[i + k] for i in good) / max(1, len(good)) for k in range(3)]
    fixed = 0
    for q in wrong:
        s = src_of.get(q)
        i = (q[1] * W + q[0]) * 4
        if s:
            j = (s[1] * W + s[0]) * 4
            pix[i:i + 3] = pix[j:j + 3]
        else:
            pix[i:i + 3] = mean[side[q]]
        fixed += 1
    # Then flecks: on her legs under the hem (and on the skirt above it) a texel much darker (or, on the
    # skirt, much lighter) than the texels round it (5 x 5, the same side; 7 x 7 and finer within 10 cm
    # under the hem) takes the colour of the middle
    # one of them: smudges and specks gone, the fabric's and the stockings' own shading kept.
    flecks = 0
    for _ in range(2):
        fix = {}
        for (x, y), below in side.items():
            close = below and zmap.get((x, y), 0.0) > hem - 0.1  # (on her legs near the hem: finer)
            rad = 3 if close else 2
            near = [(x + dx, y + dy) for dx in range(-rad, rad + 1) for dy in range(-rad, rad + 1) if side.get((x + dx, y + dy)) == below]
            if len(near) < 9:
                continue
            near.sort(key=luma)
            m = near[len(near) // 2]
            l, lm = luma((x, y)), luma(m)
            if l < (0.9 if close else 0.86) * lm or (not below and l > 1.5 * lm + 0.02):
                fix[(x, y)] = m
        for (x, y), m in fix.items():
            i, j = (y * W + x) * 4, (m[1] * W + m[0]) * 4
            pix[i:i + 3] = pix[j:j + 3]
        flecks += len(fix)
    print("HEM flecks smoothed:", flecks)
    # And the strip of leg just under the hem (HEM_SHADE m), shaded darker in the source as though in
    # the skirt's shadow, reads as a smudge under it: it takes the colours of her leg a little lower
    # down (the nearest texels from HEM_SHADE to 2.5 x it under the hem), her leg's tone up to the hem.
    shade = float(os.environ.get("HEM_SHADE", "0"))
    if shade > 0.0:
        strip = {q for q, below in side.items() if below and zmap.get(q, -1.0) > hem - shade}
        ref = {q: q for q, below in side.items() if below and hem - 2.5 * shade <= zmap.get(q, 9.0) <= hem - shade}
        front = list(ref)
        while front:
            nxt = []
            for (x, y) in front:
                for d in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    q = (x + d[0], y + d[1])
                    if q in strip and q not in ref:
                        ref[q] = ref[(x, y)]
                        nxt.append(q)
            front = nxt
        for q in strip:
            s = ref.get(q)
            if s:
                i, j = (q[1] * W + q[0]) * 4, (s[1] * W + s[0]) * 4
                pix[i:i + 3] = pix[j:j + 3]
        print("HEM strip under the hem in her leg's tone:", len(strip), "texels")
    # Her side split: each texel there skirt or leg (warm), the odd one out among its neighbours (a
    # pale texel in the skirt's edge, a dark one in her leg) made like them, twice over, and recoloured
    # from the nearest of its new kind: a clean dark edge against her leg.
    kind = {q: warm(q) for q in split}
    for _ in range(2):
        flip = {}
        for (x, y), k in kind.items():
            near = [kind[(x + dx, y + dy)] for dx in (-1, 0, 1) for dy in (-1, 0, 1) if (dx or dy) and (x + dx, y + dy) in kind]
            if len(near) >= 5 and sum(1 for n in near if n != k) >= 5:
                flip[(x, y)] = not k
        kind.update(flip)
    tidied = 0
    for (x, y), k in kind.items():
        if warm((x, y)) == k:
            continue
        best = None
        for r in range(1, 6):
            for dx in range(-r, r + 1):
                for dy in (-r, r) if abs(dx) != r else range(-r, r + 1):
                    q = (x + dx, y + dy)
                    if q in kind and kind[q] == k and warm(q) == k:
                        best = q
                        break
                if best:
                    break
            if best:
                break
        if best:
            i, j = (y * W + x) * 4, (best[1] * W + best[0]) * 4
            pix[i:i + 3] = pix[j:j + 3]
            tidied += 1
    print("HEM side split tidied:", tidied, "texels of", len(split))
    img.pixels[:] = pix
    print("HEM", fixed, "of", len(wrong), "texels on the wrong side of the hem recoloured")
img.scale(tex, tex)  # baked at twice the size, scaled down: cleaner edges
# REMARGIN=n (environment, texels): after the texture's been worked on (the hem, the misses), the
# margin round every piece of it made again from what's in the piece now, n texels out: the bake's own
# margin still held the colours from before, and a triangle's edge reads a texel or two of it (dark
# streaks down Vesper's thighs from the hem, flecks along the seams).
if os.environ.get("REMARGIN"):
    reach = int(os.environ["REMARGIN"])
    W, H = img.size
    pix = list(img.pixels)
    uvd = low.data.uv_layers.active.data
    low.data.calc_loop_triangles()
    done = bytearray(W * H)  # 1: a texel of a piece, or margin already made
    for t in low.data.loop_triangles:
        p = [uvd[l].uv * mathutils.Vector((W, H)) for l in t.loops]
        area = (p[1] - p[0]).cross(p[2] - p[0])
        if abs(area) < 1e-9:
            continue
        for y in range(max(0, int(min(q.y for q in p))), min(H - 1, int(max(q.y for q in p))) + 1):
            for x in range(max(0, int(min(q.x for q in p))), min(W - 1, int(max(q.x for q in p))) + 1):
                c = mathutils.Vector((x + 0.5, y + 0.5))
                w0 = (p[2] - p[1]).cross(c - p[1]) / area
                w1 = (p[0] - p[2]).cross(c - p[2]) / area
                if min(w0, w1, 1.0 - w0 - w1) >= -0.01:
                    done[y * W + x] = 1
    front = [i for i in range(W * H) if done[i]]
    grown = 0
    for _ in range(reach):
        ring = []
        for i in front:
            x, y = i % W, i // W
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                if 0 <= x + dx < W and 0 <= y + dy < H and not done[(y + dy) * W + x + dx]:
                    done[(y + dy) * W + x + dx] = 2
                    ring.append((y + dy) * W + x + dx)
        for j in ring:
            x, y = j % W, j // W
            acc = [0.0, 0.0, 0.0]
            n = 0
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                if 0 <= x + dx < W and 0 <= y + dy < H and done[(y + dy) * W + x + dx] == 1:
                    k = ((y + dy) * W + x + dx) * 4
                    acc = [acc[c] + pix[k + c] for c in range(3)]
                    n += 1
            if n:
                pix[j * 4:j * 4 + 3] = [a / n for a in acc]
                grown += 1
        for j in ring:
            done[j] = 1
        front = ring
    img.pixels[:] = pix
    print("REMARGIN", grown, "margin texels made again from their pieces")
# GROW_GAPS=1 (environment): the gaps between islands, still unbaked black, grown over from the
# islands' edges 4 texels further than the bake's margin: a triangle's corner at an island's edge can
# sample them (thin black marks on Vesper's thighs).
if os.environ.get("GROW_GAPS") == "1":
    W, H = img.size
    pix = list(img.pixels)
    for _ in range(4):
        grown = list(pix)
        for y in range(H):
            for x in range(W):
                i = (y * W + x) * 4
                if pix[i] != 0.0 or pix[i + 1] != 0.0 or pix[i + 2] != 0.0:
                    continue
                acc = [0.0, 0.0, 0.0]
                n = 0
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    if 0 <= x + dx < W and 0 <= y + dy < H:
                        j = ((y + dy) * W + x + dx) * 4
                        if pix[j] != 0.0 or pix[j + 1] != 0.0 or pix[j + 2] != 0.0:
                            acc = [acc[k] + pix[j + k] for k in range(3)]
                            n += 1
                if n:
                    grown[i:i + 3] = [a / n for a in acc]
        pix = grown
    img.pixels[:] = pix
img.filepath_raw = os.path.join(work, f"{name}_{target}_{tex}.png"); img.file_format = 'PNG'; img.save()
img.pack()  # kept inside the .blend, so the later stages don't depend on this machine's paths
print("BAKED", img.filepath_raw)
bpy.data.objects.remove(src)
if full:
    bpy.data.objects.remove(full)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(work, f"{name}_low_{target}.blend"))
h = max((low.matrix_world @ v.co).z for v in low.data.vertices)
scene.render.engine = 'BLENDER_WORKBENCH'
render_util.render(f"{out}/low{target}", mathutils.Vector((0, 0, h / 2)), h * 1.06)
render_util.render(f"{out}/low{target}_head", mathutils.Vector((0, 0, h - 0.14)), 0.4, angles=(("front", 0), ("left", 90), ("back", 180)), resx=400, resy=400)
print("DONE")
