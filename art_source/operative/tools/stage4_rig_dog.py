# Stage 4, for a four-legged character (the dog; CHAR as in stage 1): face him forward, scale him
# to size, rig him with a dog's skeleton (DogRig's 19 bones: hips, spine, chest, neck, head, two in
# the tail, and three in each leg) and export him for Godot. As for the humans (stage4_rig.py), the
# joints are found from the mesh itself (his four paws, each leg traced up from its paw to where it
# meets the body, the line of his back, his head and tail) plus a dog's proportions, and the skin
# weights are Blender's automatic (bone heat) weights, then kept apart between the legs and the body.
#
# Usage: blender --background --python stage4_rig_dog.py -- LOW.blend OUT.glb OUT_joints.json [withers_m=0.72]
import bpy, sys, os, json, math, mathutils
NAME = os.environ.get("CHAR", "dog").upper()
argv = sys.argv[sys.argv.index("--") + 1:]
blend, out_glb, out_json = argv[0], argv[1], argv[2]
WITHERS = float(argv[3]) if len(argv) > 3 else 0.72
bpy.ops.wm.open_mainfile(filepath=blend)
low = bpy.data.objects[f"{NAME}_low"]
me = low.data


def verts():
    M = low.matrix_world
    return [M @ v.co for v in me.vertices]


V = verts()
# --- Face him toward +Y (glTF/Godot -Z, the game's forward): his head (the highest part, with his
# ears) is at one end of him.
ys = [v.y for v in V]
y0, y1 = min(ys), max(ys)
span = y1 - y0
front_top = max(v.z for v in V if v.y > y1 - span * 0.3)
back_top = max(v.z for v in V if v.y < y0 + span * 0.3)
if back_top > front_top:
    me.transform(mathutils.Matrix.Rotation(math.pi, 4, 'Z'))
    me.update()
    print("TURNED to face +Y")
V = verts()


def feet_of(V):
    """His four paws: the lowest vertices, in four groups (left/right, front/back)."""
    low_v = [v for v in V if v.z < 0.03 * (max(p.z for p in V))]
    mid_y = (min(v.y for v in low_v) + max(v.y for v in low_v)) / 2.0
    out = {}
    for side in (1, -1):
        for end in (1, -1):  # 1 front, -1 back
            q = [v for v in low_v if v.x * side > 0 and (v.y - mid_y) * end > 0]
            out[(side, end)] = sum(q, mathutils.Vector()) / len(q)
    return out


# --- His size: the line of his back between his front and back legs, scaled to WITHERS.
F = feet_of(V)
yf = (F[(1, 1)].y + F[(-1, 1)].y) / 2.0
yb = (F[(1, -1)].y + F[(-1, -1)].y) / 2.0
tops = []
y = yb + (yf - yb) * 0.3
while y < yb + (yf - yb) * 0.7:
    band = [v.z for v in V if abs(v.y - y) < 0.025 and abs(v.x) < 0.15]
    if band:
        tops.append(max(band))
    y += 0.02
tops.sort()
back = tops[len(tops) // 2]
k = WITHERS / back
me.transform(mathutils.Matrix.Scale(k, 4))
me.update()
print("SCALED by %.3f (back %.3f -> %.2f m)" % (k, back, WITHERS))
V = verts()
W = WITHERS
H = max(v.z for v in V)
F = feet_of(V)
yf = (F[(1, 1)].y + F[(-1, 1)].y) / 2.0
yb = (F[(1, -1)].y + F[(-1, -1)].y) / 2.0
tris = [[V[i] for i in t.vertices] for t in (me.calc_loop_triangles() or me.loop_triangles)]


def section(z):
    """Points where the mesh crosses the horizontal plane at height z."""
    pts = []
    for a, b, c in tris:
        for p, q in ((a, b), (b, c), (c, a)):
            if (p.z - z) * (q.z - z) < 0.0:
                t = (z - p.z) / (q.z - p.z)
                pts.append(p.lerp(q, t))
    return pts


def trace(paw):
    """A leg's middle line, from its paw up: at each height the middle of its section, near the last
    one; it ends where the leg runs into the body (the section reaches in to his middle). The tail,
    hanging down the middle behind a back leg, isn't the body."""
    line = []
    prev = mathutils.Vector((paw.x, paw.y, 0.0))
    z = 0.02 * W
    while z < 0.85 * W:
        near = [p for p in section(z) if abs(p.x - prev.x) < 0.08 and abs(p.y - prev.y) < 0.1 and p.x * paw.x > 0.0
                and not (abs(p.x) < 0.05 and p.y < prev.y - 0.03)]
        if not near:
            break
        c = sum(near, mathutils.Vector()) / len(near)
        if min(abs(p.x) for p in near) < 0.035:
            break  # the body
        line.append(mathutils.Vector((c.x, c.y, z)))
        prev = c
        z += 0.01
    return line


def at(line, z):
    """A leg line's point at height z (its last point above its top)."""
    best = min(line, key=lambda p: abs(p.z - z))
    return mathutils.Vector((best.x, best.y, z))


legs = {key: trace(p) for key, p in F.items()}
print("LANDMARKS", json.dumps({"withers": W, "h": H, "front_y": yf, "back_y": yb,
        "leg_tops": {f"{'R' if s > 0 else 'L'}{'front' if e > 0 else 'back'}": round(l[-1].z, 3) if l else None for (s, e), l in legs.items()}}))
J = {}
for (side, end), line in legs.items():
    s = "R" if side > 0 else "L"
    top = line[-1].z
    if end > 0:
        # Front leg: the wrist (carpus) low on it; the elbow where it meets the chest; the shoulder
        # joint up in front of that, in the point of the shoulder.
        J["FrontPaw" + s] = at(line, 0.17 * W)
        J["FrontLower" + s] = at(line, min(top, 0.62 * W) - 0.02)
        el = J["FrontLower" + s]
        J["FrontUpper" + s] = mathutils.Vector((el.x * 0.85, el.y + 0.1 * W, el.z + 0.2 * W))
        J["FrontToe" + s] = mathutils.Vector((F[(side, end)].x, F[(side, end)].y + 0.07 * W, 0.015))
    else:
        # Hind leg: the hock low on it; the stifle (knee) higher, a little forward; the hip joint up
        # in the rump, behind.
        J["HindFoot" + s] = at(line, 0.24 * W)
        kn = at(line, min(top, 0.5 * W) - 0.02)
        J["HindLower" + s] = mathutils.Vector((kn.x, kn.y + 0.04 * W, kn.z))
        # The hip joint inside the rump, partway up from where the leg meets the body to the top of
        # the croup above it (it slopes down: not a fixed height).
        croup = max(v.z for v in V if abs(v.x) < 0.08 and abs(v.y - line[-1].y) < 0.04)
        J["HindUpper" + s] = mathutils.Vector((kn.x * 0.9, line[-1].y - 0.01, croup - 0.4 * (croup - top)))
        J["Croup" + s] = mathutils.Vector((0.0, line[-1].y, croup))
        J["HindToe" + s] = mathutils.Vector((F[(side, end)].x, F[(side, end)].y + 0.07 * W, 0.015))
y_shoulder = (J["FrontUpperR"].y + J["FrontUpperL"].y) / 2.0
y_hip = (J["HindUpperR"].y + J["HindUpperL"].y) / 2.0
croup_z = (J.pop("CroupR").z + J.pop("CroupL").z) / 2.0
hip_z = (J["HindUpperR"].z + J["HindUpperL"].z) / 2.0
J["Hips"] = mathutils.Vector((0.0, y_hip + 0.02 * W, hip_z + 0.25 * (croup_z - hip_z)))
J["Chest"] = mathutils.Vector((0.0, y_shoulder - 0.1 * W, 0.84 * W))
J["Spine"] = (J["Hips"] + J["Chest"]) / 2.0 + mathutils.Vector((0.0, 0.0, 0.03 * W))
# The head: everything well forward of the front legs and up above the back.
head = [v for v in V if v.y > yf + 0.25 * W and v.z > 0.95 * W]
hc = sum(head, mathutils.Vector()) / len(head)
nose = max(head, key=lambda v: v.y)
J["Head"] = mathutils.Vector((0.0, hc.y - 0.12 * W, hc.z - 0.05 * W))  # the top of the neck, behind the skull
J["Neck"] = mathutils.Vector((0.0, y_shoulder + 0.02 * W, 0.95 * W))
J["Nose"] = mathutils.Vector((0.0, nose.y, nose.z))
# The tail: from its tip (the lowest point down the middle, behind the back paws), traced up its
# middle, height by height, to where it leaves the croup (where it's no longer behind the backs of
# the thighs).
tail_v = [v for v in V if v.y < yb - 0.1 and abs(v.x) < 0.05]
tip = min(tail_v, key=lambda v: v.z)
tail_line = [mathutils.Vector((0.0, tip.y, tip.z))]
z = tip.z + 0.02
while z < 0.9 * W:
    pts = section(z)
    prev = tail_line[-1]
    near = [p for p in pts if abs(p.x) < 0.06 and abs(p.y - prev.y) < 0.06]
    thighs = [p.y for p in pts if 0.06 <= abs(p.x) < 0.2]
    if not near or not thighs:
        break
    c = sum(near, mathutils.Vector()) / len(near)
    if c.y > min(thighs) - 0.02:
        break  # into the rump
    tail_line.append(mathutils.Vector((0.0, c.y, z)))
    z += 0.02
root = tail_line[-1]
J["Tail1"] = root + mathutils.Vector((0.0, 0.02, 0.0))
J["Tail2"] = tail_line[len(tail_line) // 2]
J["TailTip"] = tail_line[0]
print("TAIL", len(tail_line), "points: root", tuple(round(a, 3) for a in root), "tip", tuple(round(a, 3) for a in J["TailTip"]))
tree = {"Hips": None, "Spine": "Hips", "Chest": "Spine", "Neck": "Chest", "Head": "Neck",
        "Tail1": "Hips", "Tail2": "Tail1",
        "FrontUpperR": "Chest", "FrontLowerR": "FrontUpperR", "FrontPawR": "FrontLowerR",
        "FrontUpperL": "Chest", "FrontLowerL": "FrontUpperL", "FrontPawL": "FrontLowerL",
        "HindUpperR": "Hips", "HindLowerR": "HindUpperR", "HindFootR": "HindLowerR",
        "HindUpperL": "Hips", "HindLowerL": "HindUpperL", "HindFootL": "HindLowerL"}
tails = {"Hips": "Spine", "Spine": "Chest", "Chest": "Neck", "Neck": "Head", "Head": "Nose",
         "Tail1": "Tail2", "Tail2": "TailTip"}
for s in ("R", "L"):
    tails.update({"FrontUpper" + s: "FrontLower" + s, "FrontLower" + s: "FrontPaw" + s, "FrontPaw" + s: "FrontToe" + s,
                  "HindUpper" + s: "HindLower" + s, "HindLower" + s: "HindFoot" + s, "HindFoot" + s: "HindToe" + s})
# --- The armature.
arm_data = bpy.data.armatures.new(f"{NAME}_rig")
rig = bpy.data.objects.new(f"{NAME}_rig", arm_data)
bpy.context.scene.collection.objects.link(rig)
for o in bpy.context.selected_objects:
    o.select_set(False)
bpy.context.view_layer.objects.active = rig
rig.select_set(True)
bpy.ops.object.mode_set(mode='EDIT')
eb = {}
for name in tree:
    b = arm_data.edit_bones.new(name)
    b.head = J[name]
    b.tail = J[tails[name]]
    eb[name] = b
for name, parent in tree.items():
    if parent:
        eb[name].parent = eb[parent]
        eb[name].use_connect = False
bpy.ops.object.mode_set(mode='OBJECT')
for poly in me.polygons:
    poly.use_smooth = True
# --- Skin weights: Blender's automatic weights (worked out with him ten times bigger: bone heat
# fails to find a solution on a mesh this small, with legs this thin)...
me.validate()
BIG = 10.0
def rescale(f):
    me.transform(mathutils.Matrix.Scale(f, 4))
    me.update()
    for o in bpy.context.selected_objects:
        o.select_set(False)
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    for b in arm_data.edit_bones:
        b.head = b.head * f
        b.tail = b.tail * f
    bpy.ops.object.mode_set(mode='OBJECT')
rescale(BIG)
for o in bpy.context.selected_objects:
    o.select_set(False)
low.select_set(True)
rig.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.parent_set(type='ARMATURE_AUTO')
rescale(1.0 / BIG)
unweighted = sum(1 for v in me.vertices if not any(g.weight > 0.01 for g in v.groups))
# ...kept apart: below where a leg meets the body, a vertex on that leg goes wholly to the leg's own
# bones (no belly stretched down with a leg swinging back, no leg pulled by its neighbour), and none
# of the body or the other legs.
VG = low.vertex_groups
gi = {g.name: g.index for g in VG}
leg_bones = {}
for (side, end), line in legs.items():
    s = "R" if side > 0 else "L"
    names = ("FrontUpper", "FrontLower", "FrontPaw") if end > 0 else ("HindUpper", "HindLower", "HindFoot")
    leg_bones[(side, end)] = ([gi[n + s] for n in names], line)
split = 0
M = low.matrix_world
for v in me.vertices:
    p = M @ v.co
    for key, (bones, line) in leg_bones.items():
        if not line or p.z > line[-1].z - 0.01:
            continue
        c = at(line, p.z)
        if (p.x - c.x) ** 2 + (p.y - c.y) ** 2 < (0.07 * W / 0.72) ** 2 * 4.0:
            w = {g.group: g.weight for g in v.groups}
            keep = {b: w.get(b, 0.0) for b in bones}
            if sum(keep.values()) < 1e-4:
                keep = {bones[1] if p.z > J[("FrontPaw" if key[1] > 0 else "HindFoot") + ("R" if key[0] > 0 else "L")].z else bones[2]: 1.0}
            for g in [g.group for g in v.groups]:
                if g not in keep:
                    VG[g].remove([v.index])
            for b, x in keep.items():
                if x > 1e-4:
                    VG[b].add([v.index], x, 'REPLACE')
            split += 1
            break
# Anything bone heat left out (a few stray vertices) goes to the nearest bone.
bones_at = {n: (J[n], J[tails[n]]) for n in tree}
def nearest(p):
    best, bd = None, 1e9
    for n, (a, b) in bones_at.items():
        ab = b - a
        t = max(0.0, min(1.0, (p - a).dot(ab) / max(1e-9, ab.length_squared)))
        d = (a + ab * t - p).length
        if d < bd:
            best, bd = n, d
    return best
stray = 0
for v in me.vertices:
    if not any(g.weight > 0.01 for g in v.groups):
        VG[gi[nearest(M @ v.co)]].add([v.index], 1.0, 'REPLACE')
        stray += 1
# ...and the tail kept to the tail bones: a vertex near the traced tail (below its root) goes to the
# nearer of Tail1 and Tail2 (half to the hips right at the root), none to the hips or legs.
def seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(1e-9, ab.length_squared)))
    return (a + ab * t - p).length
tailed = 0
for v in me.vertices:
    p = M @ v.co
    if p.z > J["Tail1"].z + 0.01 or p.y > J["Tail1"].y or abs(p.x) > 0.07:
        continue
    d1 = seg_dist(p, J["Tail1"], J["Tail2"])
    d2 = seg_dist(p, J["Tail2"], J["TailTip"])
    if min(d1, d2) > 0.05:
        continue
    w = {gi["Tail1"]: 1.0} if d1 <= d2 else {gi["Tail2"]: 1.0}
    if (p - J["Tail1"]).length < 0.03:
        w = {gi["Tail1"]: 0.5, gi["Hips"]: 0.5}
    for g in [g.group for g in v.groups]:
        if g not in w:
            VG[g].remove([v.index])
    for b, x in w.items():
        VG[b].add([v.index], x, 'REPLACE')
    tailed += 1
bpy.context.view_layer.objects.active = low
for o in bpy.context.selected_objects:
    o.select_set(False)
low.select_set(True)
bpy.ops.object.mode_set(mode='WEIGHT_PAINT')
bpy.ops.object.vertex_group_limit_total(group_select_mode='ALL', limit=4)
bpy.ops.object.vertex_group_normalize_all(group_select_mode='ALL', lock_active=False)
bpy.ops.object.mode_set(mode='OBJECT')
print("WEIGHTS groups", len(VG), "unweighted by bone heat", unweighted, "of", len(me.vertices), "| legs kept apart", split, "| strays to the nearest bone", stray, "| tail", tailed)
with open(out_json, "w") as f:
    json.dump({"withers": W, "h": H, "joints": {k2: [v.x, v.y, v.z] for k2, v in J.items()}, "unweighted": unweighted}, f, indent=1)
# --- Export.
for o in bpy.context.selected_objects:
    o.select_set(False)
low.select_set(True)
rig.select_set(True)
bpy.ops.export_scene.gltf(filepath=out_glb, export_format='GLB', use_selection=True, export_skins=True,
        export_animations=False, export_yup=True, export_apply=False, export_materials='EXPORT')
bpy.ops.wm.save_as_mainfile(filepath=blend.replace(".blend", "_rigged.blend"))
print("EXPORTED", out_glb, os.path.getsize(out_glb))
