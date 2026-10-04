# Stage 4: rig a low-poly character (CHAR, as in stage 1; CROSS by default) with the game's skeleton (SoldierRig's 19 joints) and
# export him for Godot. Joint positions are found from the mesh itself (the crotch, the armpits,
# the arm lines, the fingertips, the tops of the shoulders) plus standard body proportions; the
# skin weights are Blender's automatic (bone heat) weights, so joints bend smoothly, then cleaned
# up round the shoulders and chest (see below).
import bpy, sys, os, json, math, mathutils
NAME = os.environ.get("CHAR", "cross").upper()
argv = sys.argv[sys.argv.index("--") + 1:]
blend, out_glb, out_json = argv[0], argv[1], argv[2]
out_game_json = argv[3] if len(argv) > 3 else None
bpy.ops.wm.open_mainfile(filepath=blend)
low = bpy.data.objects[f"{NAME}_low"]
me = low.data
M = low.matrix_world
V = [M @ v.co for v in me.vertices]
h = max(v.z for v in V)
# --- Face him toward +Y (glTF/Godot -Z, the game's forward). His boots tell which way he faces:
# the toes reach much further in front of the shin than the heels do behind it.
shin = [v for v in V if 0.3 < v.z < 0.4]
foot = [v for v in V if v.z < 0.05]
sy = (min(v.y for v in shin) + max(v.y for v in shin)) / 2.0
if sy - min(v.y for v in foot) > max(v.y for v in foot) - sy:
    # Turn the mesh itself (the glTF importer leaves objects in quaternion rotation mode, where
    # setting rotation_euler does nothing).
    me.transform(mathutils.Matrix.Rotation(math.pi, 4, 'Z'))
    me.update()
    print("TURNED to face +Y")
M = low.matrix_world
V = [M @ v.co for v in me.vertices]
tris = [[V[i] for i in t.vertices] for t in (me.calc_loop_triangles() or me.loop_triangles)]

def section(z):
    """Segments where the mesh crosses the horizontal plane at height z."""
    segs = []
    for a, b, c in tris:
        pts = []
        for p, q in ((a, b), (b, c), (c, a)):
            if (p.z - z) * (q.z - z) < 0.0:
                t = (z - p.z) / (q.z - p.z)
                pts.append(p.lerp(q, t))
        if len(pts) == 2:
            segs.append(pts)
    return segs

def intervals(z, side=None):
    """The section's extent along x, as merged intervals (optionally one side only)."""
    xs = []
    for p, q in section(z):
        lo, hi = min(p.x, q.x), max(p.x, q.x)
        if side == 1 and hi < 0.0: continue
        if side == -1 and lo > 0.0: continue
        xs.append([lo, hi])
    xs.sort()
    merged = []
    for lo, hi in xs:
        if merged and lo <= merged[-1][1] + 0.012:
            merged[-1][1] = max(merged[-1][1], hi)
        else:
            merged.append([lo, hi])
    return merged

def y_mid(z, x0, x1):
    ys = [p.y for s in section(z) for p in s if x0 <= p.x <= x1]
    return (min(ys) + max(ys)) / 2.0 if ys else 0.0

# The crotch: the lowest height where the body is whole across the middle.
crotch = None
z = 0.5
while z < 1.2:
    if any(lo < -0.02 and hi > 0.02 for lo, hi in intervals(z)):
        crotch = z
        break
    z += 0.004
# The armpits and arm lines, each side: going down from the shoulders, where the arm splits off
# from the body, then following that arm down (each step's arm section close to the last one's)
# to where it ends, the fingertips.
def mid(i):
    return (i[0] + i[1]) / 2.0
arms = {}
for side in (1, -1):
    z = h * 0.8
    armpit = None
    line = []
    prev = None
    while z > 0.4:
        iv = intervals(z, side)
        if armpit is None:
            outer = [i for i in iv if mid(i) * side > 0.12]
            if len(iv) >= 2 and outer:
                arm = max(outer, key=lambda i: abs(mid(i)))
                armpit = z
                line.append((z, mid(arm), arm))
                prev = mid(arm)
        else:
            near = [i for i in iv if abs(mid(i) - prev) < 0.05]
            if not near:
                break  # the hand has ended
            arm = min(near, key=lambda i: abs(mid(i) - prev))
            line.append((z, mid(arm), arm))
            prev = mid(arm)
        z -= 0.01
    fingertip = line[-1][0] if line else 0.75
    arms[side] = {"armpit": armpit, "fingertip": fingertip, "line": line}
print("LANDMARKS", json.dumps({"h": h, "crotch": crotch, "armpits": [arms[1]["armpit"], arms[-1]["armpit"]], "fingertips": [arms[1]["fingertip"], arms[-1]["fingertip"]]}))

def arm_x(side, z):
    line = arms[side]["line"]
    best = min(line, key=lambda p: abs(p[0] - z))
    return best[1]

def leg_x(side, z):
    iv = [i for i in intervals(z, side) if (i[0] + i[1]) / 2.0 * side > 0.0]
    inner = min(iv, key=lambda i: abs((i[0] + i[1]) / 2.0))
    return (inner[0] + inner[1]) / 2.0

J = {}
# The pelvis and hips up where the thigh bones meet the pelvis (user: the hip points were too low),
# about 9 cm above the crotch; the spine's first joint above them.
J["Hips"] = (0.0, crotch + 0.13)
J["Spine"] = (0.0, crotch + 0.25)
# The chest: the top of the spine, just under the neck, where the collarbones hang from (user: the
# shoulders' middle point should be up by the neck).
J["Chest"] = (0.0, h * 0.80)
J["Neck"] = (0.0, h * 0.82)
J["Head"] = (0.0, h * 0.855)
for side, s in ((1, "R"), (-1, "L")):
    ap = arms[side]["armpit"]
    ft = arms[side]["fingertip"]
    # The shoulder joint, where the arm turns: up in the ball of the shoulder, 4 cm under its top
    # (user, twice: the shoulders were too low, and bent the shoulder out of shape with his arms up).
    top = max(v.z for v in V if 0.22 <= v.x * side <= 0.32 and ap < v.z < ap + 0.4)
    sh_z = top - 0.04
    print("SHOULDER_TOP", side, round(top, 3))
    # The arm's line, traced from the armpit down and carried on up to the shoulder joint's height
    # (so the shoulder sits on it); the wrist a hand's length above the fingertips, the elbow just
    # past halfway.
    x_ap = arm_x(side, ap - 0.02)
    x_ft = arm_x(side, ft + 0.01)
    slope = (x_ft - x_ap) / max(0.01, (ap - 0.02) - (ft + 0.01))  # x change per metre down
    def along(z):
        return x_ap + slope * ((ap - 0.02) - z)
    wr_z = ft + 0.19
    el_z = sh_z - 0.53 * (sh_z - wr_z)
    J["Shoulder" + s] = (along(sh_z), sh_z)  # on the arm's line, so the arm turns about itself
    # The collarbone, from beside the top of the breastbone out to the shoulder: it lifts the
    # shoulder when the arm goes up high (a shrug), so the shoulder joint doesn't bend that far alone.
    J["Clavicle" + s] = (side * 0.045, J["Chest"][1])
    J["Elbow" + s] = (arm_x(side, el_z), el_z)  # in the middle of the arm there, not on a straight line
    J["Wrist" + s] = (arm_x(side, wr_z), wr_z)
    lh_z = crotch + 0.09
    J["LegHip" + s] = (side * (abs(leg_x(1, crotch - 0.1)) + abs(leg_x(-1, crotch - 0.1))) / 2.0, lh_z)
    kn_z = h * 0.275
    J["Knee" + s] = (leg_x(side, kn_z), kn_z)
    an_z = h * 0.05
    J["Ankle" + s] = (leg_x(side, h * 0.12), an_z)
# Depth (y) of each joint: the middle of the body or limb's cross-section there.
pos = {}
for name, (x, z) in J.items():
    w = 0.06 if name in ("Hips", "Spine", "Chest", "Neck", "Head", "ClavicleR", "ClavicleL") else 0.05
    pos[name] = mathutils.Vector((x, y_mid(z, x - w, x + w), z))
pos["Head"].y = y_mid(h * 0.88, -0.06, 0.06) - 0.01  # the head turns about the top of the neck
tree = {"Hips": None, "Spine": "Hips", "Chest": "Spine", "Neck": "Chest", "Head": "Neck",
        "ClavicleR": "Chest", "ShoulderR": "ClavicleR", "ElbowR": "ShoulderR", "WristR": "ElbowR",
        "ClavicleL": "Chest", "ShoulderL": "ClavicleL", "ElbowL": "ShoulderL", "WristL": "ElbowL",
        "LegHipR": "Hips", "KneeR": "LegHipR", "AnkleR": "KneeR",
        "LegHipL": "Hips", "KneeL": "LegHipL", "AnkleL": "KneeL"}
tails = {"Hips": "Spine", "Spine": "Chest", "Chest": "Neck", "Neck": "Head", "ClavicleR": "ShoulderR", "ClavicleL": "ShoulderL",
         "ShoulderR": "ElbowR", "ElbowR": "WristR",
         "ShoulderL": "ElbowL", "ElbowL": "WristL", "LegHipR": "KneeR", "KneeR": "AnkleR",
         "LegHipL": "KneeL", "KneeL": "AnkleL"}
# --- The armature.
arm_data = bpy.data.armatures.new(f"{NAME}_rig")
rig = bpy.data.objects.new(f"{NAME}_rig", arm_data)
bpy.context.scene.collection.objects.link(rig)
for o in bpy.context.selected_objects: o.select_set(False)
bpy.context.view_layer.objects.active = rig
rig.select_set(True)
bpy.ops.object.mode_set(mode='EDIT')
eb = {}
for name in tree:
    b = arm_data.edit_bones.new(name)
    b.head = pos[name]
    if name in tails:
        b.tail = pos[tails[name]]
    elif name == "Head":
        b.tail = mathutils.Vector((pos[name].x, pos[name].y, h * 0.98))
    elif name.startswith("Wrist"):
        b.tail = pos[name] + (pos[name] - pos["Elbow" + name[-1]]).normalized() * 0.15
    elif name.startswith("Ankle"):
        b.tail = mathutils.Vector((pos[name].x, pos[name].y - 0.16, 0.03))  # toward the toe (+Y is his front... see below)
    eb[name] = b
for name, parent in tree.items():
    if parent:
        eb[name].parent = eb[parent]
        eb[name].use_connect = False
# Toes point forward, +Y.
for s in ("R", "L"):
    a = eb["Ankle" + s]
    a.tail = mathutils.Vector((a.head.x, a.head.y + 0.16, 0.03))
bpy.ops.object.mode_set(mode='OBJECT')
# --- Smooth (Gouraud) shading, as on the PS1: vertices shared between faces except at UV seams.
for poly in me.polygons:
    poly.use_smooth = True
# --- Skin weights: Blender's automatic weights.
for o in bpy.context.selected_objects: o.select_set(False)
low.select_set(True)
rig.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.parent_set(type='ARMATURE_AUTO')
# What bone heat left unweighted (it fails on bad geometry): counted before the clean-up below, which
# gives every vertex a weight, so a failure still shows in the log and cross_joints.json.
unweighted = sum(1 for v in me.vertices if not any(g.weight > 0.01 for g in v.groups))
# --- ...cleaned up (user: his shoulders bent out of shape with his arms up). Bone heat gave the
# shoulder bones a pull on the collar and the top of the vest by the neck, the side of the vest under
# the arm, and gave almost all the chest to the spine (the chest bone is short), so:
#  - nothing near the middle follows an arm: the arm bones' weight goes from everything more than
#    9 cm inside the shoulder joint (the collarbone and chest keep it), and the collarbones' fades
#    out toward the collar (to the chest), so a shrug lifts the shoulders but not the collar;
#  - from the armpit down to the fingertips, arm and body are apart on the model, so each vertex
#    there goes wholly to whichever it's part of (no web of vest stretched up under a raised arm,
#    no waist pulled out with it);
#  - the upper body goes from the spine to the chest bone, gradually, from the bottom of the ribs up
#    to under the arms, so the shoulders and the vest round them turn together;
#  - then the weights round the shoulders are smoothed a little, so nothing changes hands in one
#    step (the 9 cm line across his chest stays soft), and the arm-and-body split below the armpit
#    is applied again, since smoothing spreads the shoulder's weight back down the vest under the
#    arm: the vest stays put like the stiff carrier it is, and the stretch goes to the armpit.
VG = low.vertex_groups
gi = {g.name: g.index for g in VG}
arm_bones = {side: [gi[n + s] for n in ("Shoulder", "Elbow", "Wrist")] for side, s in ((1, "R"), (-1, "L"))}
body_bones = [gi[n] for n in ("Hips", "Spine", "Chest", "ClavicleR", "ClavicleL", "Neck")]
_body_edge = {}
def body_edge(side, z):
    """How far out (|x|) the body's own section reaches at height z on one side (the trunk, or the
    leg below the crotch: the section nearest the middle)."""
    key = (side, round(z, 3))
    if key not in _body_edge:
        iv = intervals(z, side)
        trunk = min(iv, key=lambda i: abs(mid(i))) if iv else None
        _body_edge[key] = max(trunk[0] * side, trunk[1] * side) if trunk else 0.0
    return _body_edge[key]
def arm_part(side, p):
    """Between the armpit and the fingertips: "arm" if p is in the arm's section there, "body" if
    it's inside the arm's inner edge and within the body's own section, None otherwise."""
    z, _, (lo, hi) = min(arms[side]["line"], key=lambda e: abs(e[0] - p.z))
    inner, outer = sorted((lo * side, hi * side))
    x = p.x * side
    if x < inner - 0.015 and x <= body_edge(side, p.z) + 0.015:
        return "body"
    return "arm" if inner - 0.015 <= x <= outer + 0.015 else None
inside = {side: abs(pos["Shoulder" + s].x) - 0.09 for side, s in ((1, "R"), (-1, "L"))}
def keep_apart(p, w, line=True):
    """The first two rules on one vertex's weights ({group: weight}), in place (line=False: only
    the arm-and-body split below the armpit)."""
    for side in (1, -1):
        if p.x * side < inside[side]:
            if line:
                for b in arm_bones[side]:
                    w.pop(b, None)
        elif arms[side]["fingertip"] < p.z < arms[side]["armpit"] - 0.01:
            part = arm_part(side, p)
            if part == "arm" and any(b in w for b in arm_bones[side]):
                for b in body_bones:
                    w.pop(b, None)
            elif part == "body":
                for b in arm_bones[side]:
                    w.pop(b, None)
def write(v, w):
    """Set one vertex's weights to w (group indices are read before anything is changed: removing
    a weight moves the vertex's weight list)."""
    for b in [g.group for g in v.groups]:
        if w.get(b, 0.0) <= 1e-4:
            VG[b].remove([v.index])
    for b, x in w.items():
        if x > 1e-4:
            VG[b].add([v.index], x, 'REPLACE')
chest_lo, chest_hi = h * 0.64, h * 0.74
fallback = 0
for v in me.vertices:
    p = M @ v.co
    w = {g.group: g.weight for g in v.groups}
    keep_apart(p, w)
    for side in (1, -1):
        c = gi["Clavicle" + ("R" if side > 0 else "L")]
        if c in w:
            k = min(1.0, max(0.0, (p.x * side - 0.05) / 0.07))
            w[gi["Chest"]] = w.get(gi["Chest"], 0.0) + w[c] * (1.0 - k)
            w[c] *= k
    if sum(w.values()) < 1e-4:  # it only followed an arm: the body, by the height ramp below
        w = {gi["Spine"]: 1.0}
        fallback += 1
    torso = w.get(gi["Spine"], 0.0) + w.get(gi["Chest"], 0.0)
    if torso > 0.0:
        t = min(1.0, max(0.0, (p.z - chest_lo) / (chest_hi - chest_lo)))
        t = t * t * (3.0 - 2.0 * t)
        w[gi["Spine"]], w[gi["Chest"]] = torso * (1.0 - t), torso * t
    write(v, w)
bpy.context.view_layer.objects.active = low
for o in bpy.context.selected_objects: o.select_set(False)
low.select_set(True)
bpy.ops.object.mode_set(mode='WEIGHT_PAINT')
for n in ("ClavicleR", "ClavicleL", "ShoulderR", "ShoulderL", "Chest", "Neck"):
    VG.active_index = gi[n]
    bpy.ops.object.vertex_group_smooth(group_select_mode='ACTIVE', factor=0.5, repeat=2)
bpy.ops.object.mode_set(mode='OBJECT')
reapplied = 0
for v in me.vertices:
    p = M @ v.co
    w = {g.group: g.weight for g in v.groups}
    before = dict(w)
    keep_apart(p, w, line=False)
    if w != before and sum(w.values()) > 1e-4:
        write(v, w)
        reapplied += 1
bpy.ops.object.mode_set(mode='WEIGHT_PAINT')
bpy.ops.object.vertex_group_limit_total(group_select_mode='ALL', limit=4)
bpy.ops.object.vertex_group_normalize_all(group_select_mode='ALL', lock_active=False)
bpy.ops.object.mode_set(mode='OBJECT')
groups = {g.index: g.name for g in low.vertex_groups}
print("WEIGHTS groups", len(groups), "unweighted by bone heat", unweighted, "of", len(me.vertices),
      "| given to the body (only followed an arm)", fallback,
      "| split again below the armpit after smoothing", reapplied)
# --- The goggle lenses: where his texture is bright green, in two clusters (Godot axes).
img = [n.image for n in me.materials[0].node_tree.nodes if n.type == 'TEX_IMAGE'][0]
iw, ih = img.size
px = img.pixels[:]
uvd = me.uv_layers.active.data
me.calc_loop_triangles()
hits = []
for tri in me.loop_triangles:
    uvs = [uvd[li].uv for li in tri.loops]
    cos = [low.matrix_world @ me.vertices[vi].co for vi in tri.vertices]
    for a in range(5):
        for b in range(5 - a):
            wa, wb, wc = a / 4.0, b / 4.0, (4 - a - b) / 4.0
            u = uvs[0].x * wa + uvs[1].x * wb + uvs[2].x * wc
            v = uvs[0].y * wa + uvs[1].y * wb + uvs[2].y * wc
            i = (min(ih - 1, max(0, int(v * ih))) * iw + min(iw - 1, max(0, int(u * iw)))) * 4
            r, g, bl = px[i], px[i + 1], px[i + 2]
            if g > 0.5 and g - max(r, bl) > 0.12 and (cos[0] * wa).z + (cos[1] * wb).z + (cos[2] * wc).z > 1.6:
                hits.append(cos[0] * wa + cos[1] * wb + cos[2] * wc)
hits.sort(key=lambda p: p.x)
lenses = []
if len(hits) >= 2:
    gaps = [(hits[i + 1].x - hits[i].x, i) for i in range(len(hits) - 1)]
    cut = max(gaps)[1] + 1
    for group in (hits[:cut], hits[cut:]):
        c = sum(group, group[0] * 0) / len(group)
        lenses.append([round(c.x, 4), round(c.z, 4), round(-max(p.y for p in group), 4)])
print("LENSES", lenses)
with open(out_json, "w") as f:
    json.dump({"h": h, "joints": {k: [v.x, v.y, v.z] for k, v in pos.items()}, "unweighted": unweighted, "lenses_godot": lenses}, f, indent=1)
if out_game_json:  # what the game reads alongside the model (the lenses)
    with open(out_game_json, "w") as f:
        json.dump({"lenses": lenses}, f, indent=1)
# --- Export.
for o in bpy.context.selected_objects: o.select_set(False)
low.select_set(True)
rig.select_set(True)
bpy.ops.export_scene.gltf(filepath=out_glb, export_format='GLB', use_selection=True, export_skins=True,
        export_animations=False, export_yup=True, export_apply=False, export_materials='EXPORT')
bpy.ops.wm.save_as_mainfile(filepath=blend.replace(".blend", "_rigged.blend"))
print("EXPORTED", out_glb, os.path.getsize(out_glb))
