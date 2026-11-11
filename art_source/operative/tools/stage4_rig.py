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
# CROTCH (environment, a share of his height): where the crotch is, when the mesh can't show it (Vesper's
# skirt, and her legs together: the remesh joins them down to above the knee).
if os.environ.get("CROTCH"):
    crotch = h * float(os.environ["CROTCH"])
# The armpits and arm lines, each side: going down from the shoulders, where the arm splits off
# from the body, then following that arm down (each step's arm section close to the last one's)
# to where it ends, the fingertips.
def mid(i):
    return (i[0] + i[1]) / 2.0
# ARM_TRACE="jump,gaps" (environment): how far the arm's section may move from one step down to the next
# (m; 0.05 unless set) and how many steps it may go missing before the hand counts as ended (0 unless
# set). An open hand with its thumb and fingers splayed (the Street Operative's fingerless gloves) jumps
# at the knuckles: followed no further, his fingertips came out 15 cm high and his forearms were cut off.
trace_jump, trace_gaps = [float(v) for v in os.environ.get("ARM_TRACE", "0.05,0").split(",")]
arms = {}
for side in (1, -1):
    z = h * 0.8
    armpit = None
    line = []
    prev = None
    missed = 0
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
            near = [i for i in iv if abs(mid(i) - prev) < trace_jump]
            if not near:
                missed += 1
                if missed > trace_gaps:
                    break  # the hand has ended
                z -= 0.01
                continue
            missed = 0
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
    # SHOULDER_BAND="lo,hi" (environment, m out from the middle): where to look for the top of the
    # shoulder (0.22-0.32 m, CROSS's; narrower shoulders need it nearer the middle).
    lo, hi = [float(x) for x in os.environ.get("SHOULDER_BAND", "0.22,0.32").split(",")]
    top = max(v.z for v in V if lo <= v.x * side <= hi and ap < v.z < ap + 0.4)
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
    # SHOULDER_X (environment, m out from the middle): the shoulder joint's place across, when the arm's
    # line carried up doesn't reach the ball of the shoulder (Vesper's arms join her sides low down).
    if os.environ.get("SHOULDER_X"):
        J["Shoulder" + s] = (side * float(os.environ["SHOULDER_X"]), sh_z)
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
# HEM=z (environment, m: as stage 3's): a skirt. Between her legs (within 7 cm of the middle) the skirt
# above the hem is one surface with the inside of her thighs (the remesh joins them), and with the
# thighs' weights it was pulled down them in a stride, a dark spike on each thigh: there it follows
# her hips instead.
if os.environ.get("HEM"):
    hem = float(os.environ["HEM"])
    leg_groups = [gi[n + s] for n in ("LegHip", "Knee", "Ankle") for s in ("R", "L")]
    moved = 0
    for v in me.vertices:
        p = M @ v.co
        if p.z < hem or abs(p.x) > 0.07:
            continue
        w = {g.group: g.weight for g in v.groups}
        off = sum(w.pop(b, 0.0) for b in leg_groups)
        if off > 0.0:
            w[gi["Hips"]] = w.get(gi["Hips"], 0.0) + off
            write(v, w)
            moved += 1
    print("WEIGHTS skirt between the legs given to the hips:", moved, "vertices")
bpy.ops.object.mode_set(mode='WEIGHT_PAINT')
bpy.ops.object.vertex_group_limit_total(group_select_mode='ALL', limit=4)
bpy.ops.object.vertex_group_normalize_all(group_select_mode='ALL', lock_active=False)
bpy.ops.object.mode_set(mode='OBJECT')
# HAND_LIKE="run;palm" (environment, Godot axes, the right hand; the left is its mirror): turn each
# hand about its wrist, at rest, so it hangs as CROSS's does. SoldierRig measures a hand from the mesh
# (which way it runs from the wrist, which way the palm faces: SoldierRig._measure_hand, done the same
# way here) and seats the pistol in it for CROSS's; a hand made open and turned forward and out
# (Bishop's) took the pistol above his knuckles and askew. Turned like CROSS's, the gun sits in his
# grip in every pose with CROSS's numbers. The turn blends out across the cuff with the wrist's weight.
if os.environ.get("HAND_LIKE"):
    want_run, want_palm = [mathutils.Vector([float(x) for x in part.split(",")]) for part in os.environ["HAND_LIKE"].split(";")]
    def to_godot(v):
        return mathutils.Vector((v.x, v.z, -v.y))
    def to_blender(v):
        return mathutils.Vector((v.x, -v.z, v.y))
    def frame(run, palm):
        run = run.normalized()
        palm = (palm - run * palm.dot(run)).normalized()
        return mathutils.Matrix((run, palm, run.cross(palm))).transposed()
    for side, s in ((1, "R"), (-1, "L")):
        wb = gi["Wrist" + s]
        head = to_godot(pos["Wrist" + s])
        pts = [to_godot(M @ v.co) - head for v in me.vertices if any(g.group == wb and g.weight >= 0.6 for g in v.groups)]
        if len(pts) < 8:
            continue
        mid = sum(pts, mathutils.Vector()) / len(pts)
        run = mid.normalized()
        u = run.cross(mathutils.Vector((0, 0, -1))).normalized()
        w = run.cross(u)
        uu = sum((q - mid).dot(u) ** 2 for q in pts)
        ww = sum((q - mid).dot(w) ** 2 for q in pts)
        uw = sum((q - mid).dot(u) * (q - mid).dot(w) for q in pts)
        thin = 0.5 * math.atan2(2.0 * uw, uu - ww) + math.pi / 2.0
        palm = (u * math.cos(thin) + w * math.sin(thin)).normalized()
        if palm.x * side > 0.0:
            palm = -palm
        mirror = mathutils.Vector((side, 1, 1))
        turn_g = frame(want_run * mirror, want_palm * mirror) @ frame(run, palm).transposed()
        # (the same turn in Blender's axes)
        S = mathutils.Matrix(((1, 0, 0), (0, 0, 1), (0, -1, 0)))
        q = (S.transposed() @ turn_g @ S).to_quaternion()
        pivot = pos["Wrist" + s]
        turned = 0
        for v in me.vertices:
            k = sum(g.weight for g in v.groups if g.group == wb)
            if k <= 0.0:
                continue
            p = M @ v.co
            r = mathutils.Quaternion().slerp(q, min(1.0, k))
            v.co = M.inverted() @ (pivot + r @ (p - pivot))
            turned += 1
        print("WEIGHTS hand", s, "turned %.1f deg to hang like CROSS's (%d vertices)" % (math.degrees(q.angle), turned))
    me.update()
    # HAND_NARROW="w,k" (environment: m, a share): an open hand's spread fingers and its thumb, held
    # out from the side of the hand, drawn in before it's curled. Across the hand (square to the way it
    # runs and to the palm), anything more than w from the hand's middle comes in to k of the way it
    # stuck out, easing in from the wrist: the palm keeps its width, and the fist closes round the grip
    # without fingertips and a thumb spiking out of it (Rebel's, Future's, Judge's).
    if os.environ.get("HAND_NARROW"):
        w_keep, k_out = [float(x) for x in os.environ["HAND_NARROW"].split(",")]
        for side, s in ((1, "R"), (-1, "L")):
            wb = gi["Wrist" + s]
            mirror = mathutils.Vector((side, 1, 1))
            run_b = to_blender(want_run * mirror).normalized()
            palm_b = to_blender(want_palm * mirror)
            palm_b = (palm_b - run_b * palm_b.dot(run_b)).normalized()
            across = run_b.cross(palm_b)
            pivot = pos["Wrist" + s]
            hand = [M @ v.co - pivot for v in me.vertices if any(g.group == wb and g.weight >= 0.6 for g in v.groups)]
            a_mid = sum(p.dot(across) for p in hand) / max(1, len(hand))
            drawn = 0
            for v in me.vertices:
                kw = sum(g.weight for g in v.groups if g.group == wb)
                if kw <= 0.0:
                    continue
                p = M @ v.co - pivot
                d = p.dot(across) - a_mid
                if abs(d) <= w_keep:
                    continue
                ease = min(1.0, max(0.0, p.dot(run_b) / 0.04))  # (nothing at the wrist, all of it 4 cm on)
                nd = math.copysign(w_keep + (abs(d) - w_keep) * k_out, d)
                v.co = M.inverted() @ (pivot + p + across * (nd - d) * ease * min(1.0, kw))
                drawn += 1
            print("WEIGHTS hand", s, "drawn in across: %d vertices" % drawn)
        me.update()
    # HAND_TUCK=1 (environment): an open hand's thumb, held out over the palm, tucked in against it
    # before the curl (Rebel's and Judge's stuck out under the fist as a point). Between the wrist and
    # the knuckles, whatever stands further out on the palm side than most of the palm (its 60th
    # percentile) comes in to a fifth of the way it stood out.
    if os.environ.get("HAND_TUCK") == "1":
        for side, s in ((1, "R"), (-1, "L")):
            wb = gi["Wrist" + s]
            mirror = mathutils.Vector((side, 1, 1))
            run_b = to_blender(want_run * mirror).normalized()
            palm_b = to_blender(want_palm * mirror)
            palm_b = (palm_b - run_b * palm_b.dot(run_b)).normalized()
            pivot = pos["Wrist" + s]
            hand = [M @ v.co - pivot for v in me.vertices if any(g.group == wb and g.weight >= 0.6 for g in v.groups)]
            tip = max(p.dot(run_b) for p in hand)
            palm = sorted(p.dot(palm_b) for p in hand if 0.02 < p.dot(run_b) < tip * 0.55)
            if len(palm) < 5:
                continue
            cap = palm[int(len(palm) * 0.6)]
            tucked = 0
            for v in me.vertices:
                kw = sum(g.weight for g in v.groups if g.group == wb)
                p = M @ v.co - pivot
                t = p.dot(palm_b)
                if kw <= 0.0 or t <= cap or p.dot(run_b) <= 0.0:
                    continue
                ease = min(1.0, p.dot(run_b) / 0.03)
                v.co = M.inverted() @ (pivot + p - palm_b * (t - cap) * 0.8 * ease * min(1.0, kw))
                tucked += 1
            print("WEIGHTS hand", s, "thumb tucked in: %d vertices" % tucked)
        me.update()
    # HAND_CURL (environment, degrees): his fingers curled in toward the palm, this far at the tips, from
    # the knuckles (about 55% of the way from the wrist to the fingertips), a smooth bend like a finger's
    # joints, so an open hand closes round the pistol's grip as CROSS's fists do.
    curl = math.radians(float(os.environ.get("HAND_CURL", "0")))
    if curl > 0.0:
        for side, s in ((1, "R"), (-1, "L")):
            wb = gi["Wrist" + s]
            mirror = mathutils.Vector((side, 1, 1))
            run_b = to_blender(want_run * mirror).normalized()
            palm_b = to_blender(want_palm * mirror)
            palm_b = (palm_b - run_b * palm_b.dot(run_b)).normalized()
            pivot = pos["Wrist" + s]
            hand = [v for v in me.vertices if any(g.group == wb and g.weight >= 0.6 for g in v.groups)]
            tip = max((M @ v.co - pivot).dot(run_b) for v in hand)
            s0 = tip * 0.55
            # HAND_SHORTEN=k (environment, a share): the fingers past the knuckles shortened to k of their
            # length first. A long, flat open hand (Judge's gloves) curled whole is a hook with spiked
            # tips, not a fist; shortened, it closes into a compact one.
            shorten = float(os.environ.get("HAND_SHORTEN", "1"))
            if shorten < 1.0:
                for v in me.vertices:
                    k = sum(g.weight for g in v.groups if g.group == wb)
                    p = M @ v.co - pivot
                    sa = p.dot(run_b)
                    if k > 0.0 and sa > s0:
                        v.co = M.inverted() @ (pivot + p - run_b * (sa - s0) * (1.0 - shorten) * min(1.0, k))
                tip = s0 + (tip - s0) * shorten
            R = (tip - s0) / curl  # (a bend this radius turns the fingertips by `curl`)
            bent = 0
            for v in me.vertices:
                k = sum(g.weight for g in v.groups if g.group == wb)
                p = M @ v.co - pivot
                sa = p.dot(run_b)
                if k <= 0.0 or sa <= s0:
                    continue
                t = p.dot(palm_b)
                rest = p - run_b * sa - palm_b * t
                th = (sa - s0) / R
                new = run_b * (s0 + (R - t) * math.sin(th)) + palm_b * (R + (t - R) * math.cos(th)) + rest
                v.co = M.inverted() @ (pivot + p.lerp(new, min(1.0, k)))
                bent += 1
            print("WEIGHTS hand", s, "fingers curled %.0f deg (%d vertices)" % (math.degrees(curl), bent))
        me.update()
    # HAND_SPIKES=deg (environment): points left sticking out of a fist made from an open hand (a
    # thumb's tip, a thin flap where the remesh closed round it) smoothed off. A vertex of the hand,
    # from 2 cm short of the wrist joint on, whose faces' corners there add up to less than `deg` (a flat surface's add up
    # to 360; a spike's tip, far less) moves to the middle of the vertices joined to it, a few times
    # over, until none is left.
    if os.environ.get("HAND_SPIKES"):
        limit = math.radians(float(os.environ["HAND_SPIKES"]))
        import bmesh
        for side, s in ((1, "R"), (-1, "L")):
            wb = gi["Wrist" + s]
            pivot = M.inverted() @ pos["Wrist" + s]
            run_b = (pos["Wrist" + s] - pos["Elbow" + s]).normalized()
            hand = {v.index for v in me.vertices if sum(g.weight for g in v.groups if g.group == wb) >= 0.5
                    and (M @ v.co - pos["Wrist" + s]).dot(run_b) > -0.02}
            moved = set()
            for _ in range(6):
                bm = bmesh.new()
                bm.from_mesh(me)
                bm.verts.ensure_lookup_table()
                spikes = []
                for i in hand:
                    v = bm.verts[i]
                    if len(v.link_edges) < 3:
                        continue
                    total = sum(l.calc_angle() for l in v.link_loops)
                    if total < limit:
                        spikes.append((i, sum((e.other_vert(v).co for e in v.link_edges), mathutils.Vector()) / len(v.link_edges)))
                bm.free()
                if not spikes:
                    break
                for i, mid in spikes:
                    me.vertices[i].co = mid
                    moved.add(i)
            print("WEIGHTS hand", s, "spikes smoothed off: %d vertices" % len(moved))
        me.update()
# HAND_FROM=<json> (environment): each hand replaced with CROSS's (user: "Cross' current hand model is
# the best fit for the game and i would like all other models to have the same hand model"), from
# art_source/operative/cross_hands.json (extract_cross_hands.py): the model's own faces that are wholly
# its wrist's go, and CROSS's go in at the same place on the wrist, in the wrist's frame at rest, with
# his weights by joint name; so SoldierRig's pistol, mounted on the wrist with his numbers, sits in the
# fist as it does in his. HAND_SCALE=k scales them about the grip (Vesper's, smaller). Each new
# face takes its texture from the nearest part of the model's own hand before it went, so the colours
# stay the model's (its skin, its gloves), not CROSS's black gloves.
if os.environ.get("HAND_FROM"):
    import bmesh, json
    from mathutils.bvhtree import BVHTree
    with open(os.environ["HAND_FROM"]) as fh:
        cross_hands = json.load(fh)
    h_scale = float(os.environ.get("HAND_SCALE", "1"))
    HAND_CUT = float(os.environ.get("HAND_CUT", "-0.02"))
    # HAND_DARK=1 (environment): his hands coloured only from the dark of his own (a fingerless glove's
    # leather: the Street Operative's), so CROSS's fists come out gloved, not patched with skin.
    HAND_DARK = os.environ.get("HAND_DARK") == "1"
    _img = [n.image for n in me.materials[0].node_tree.nodes if n.type == 'TEX_IMAGE'][0]
    _tw, _th = _img.size
    _tpx = _img.pixels[:] if HAND_DARK else None
    def tex_lum(f):
        """The texture's brightness at a face's middle."""
        uvs = [l[uvl].uv for l in f.loops]
        u = sum(p.x for p in uvs) / len(uvs)
        v = sum(p.y for p in uvs) / len(uvs)
        i = (min(_th - 1, max(0, int(v * _th))) * _tw + min(_tw - 1, max(0, int(u * _tw)))) * 4
        return 0.3 * _tpx[i] + 0.59 * _tpx[i + 1] + 0.11 * _tpx[i + 2]
    GRIP_MID = (-0.004, -0.096, -0.0025)  # (the pistol grip's middle from the right wrist at rest, Godot axes; the left's is its mirror)
    def to_b(v):  # Godot axes to Blender's
        return mathutils.Vector((v[0], -v[2], v[1]))
    bm = bmesh.new()
    bm.from_mesh(me)
    dl = bm.verts.layers.deform.verify()
    uvl = bm.loops.layers.uv.active
    Mi = M.inverted()
    for s in ("R", "L"):
        wb = gi["Wrist" + s]
        pivot = pos["Wrist" + s]
        run_b = (pos["Wrist" + s] - pos["Elbow" + s]).normalized()
        def along(p):
            return (M @ p - pivot).dot(run_b)
        # (its own hand cut off, the arm's faces from HAND_CUT along it from the wrist joint: 2 cm short of it,
        # under his glove's cuff)
        eb0 = gi["Elbow" + s]
        old = [f for f in bm.faces if all(v[dl].get(wb, 0.0) + v[dl].get(eb0, 0.0) >= 0.5 and along(v.co) > HAND_CUT for v in f.verts)]
        tris = []
        for f in old:
            if min(along(v.co) for v in f.verts) < 0.05:
                continue  # (the colours from the hand itself, not a watch or a cuff at the wrist)
            if HAND_DARK and tex_lum(f) > 0.22:
                continue  # (HAND_DARK: only its glove, for a hand gloved in places)
            ls = f.loops
            for k in range(1, len(ls) - 1):
                tris.append([(M @ l.vert.co, l[uvl].uv.copy()) for l in (ls[0], ls[k], ls[k + 1])])
        tree = BVHTree.FromPolygons([p for t in tris for p, _ in t], [[3 * i, 3 * i + 1, 3 * i + 2] for i in range(len(tris))])
        def paint(f):
            """A new face's texture: each corner from where it lies over the nearest part of the old hand;
            a face whose corners all land on one edge or point there (its texture would stretch into
            stripes) takes the colour at its middle, whole."""
            c = M @ f.calc_center_median()
            hit = tree.find_nearest(c)
            uvs = [uv_at(M @ l.vert.co, hit[2]) for l in f.loops]
            # (how near an even triangle its texture is: 1 for an equilateral one, 0 for a sliver)
            area = abs((uvs[1] - uvs[0]).cross(uvs[2] - uvs[0]))
            edges = sum((uvs[(k + 1) % 3] - uvs[k]).length_squared for k in range(3))
            even = 4.0 * 3 ** 0.5 * area / max(1e-12, edges)
            if area < 1e-5 or even < 0.15:  # (a sliver, or under about 2.6 texels of the 512 texture)
                uvs = [uv_at(hit[0], hit[2])] * len(uvs)
            for l, uv in zip(f.loops, uvs):
                l[uvl].uv = uv
        def uv_at(p, ti):
            (a, ua), (b, ub), (c, uc) = tris[ti]
            w = mathutils.geometry.barycentric_transform(p, a, b, c, mathutils.Vector((1, 0, 0)), mathutils.Vector((0, 1, 0)), mathutils.Vector((0, 0, 1)))
            w = mathutils.Vector((max(0.0, w.x), max(0.0, w.y), max(0.0, w.z)))
            w /= max(1e-6, w.x + w.y + w.z)
            return ua * w.x + ub * w.y + uc * w.z
        gone_tris = sum(len(f.verts) - 2 for f in old)
        bmesh.ops.delete(bm, geom=old, context='FACES_ONLY')
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
        hand = cross_hands[s]
        grip_mid = (GRIP_MID[0] * (1 if s == "R" else -1), GRIP_MID[1], GRIP_MID[2])
        vs = []
        for p, ws in zip(hand["verts"], hand["weights"]):
            # (scaled about the pistol grip's middle, so the gun stays in the smaller fist: SoldierRig
            # mounts it on the wrist with CROSS's numbers whatever the hand's size)
            v = bm.verts.new(Mi @ (pivot + to_b([g + (c - g) * h_scale for c, g in zip(p, grip_mid)])))
            for name, w in ws.items():
                if name in gi:
                    v[dl][gi[name]] = w
            vs.append(v)
        made = 0
        for ids in hand["faces"]:
            f = bm.faces.new([vs[i] for i in ids])
            f.smooth = True
            paint(f)
            made += len(ids) - 2
        # The arm's cut edge joined to his glove's open cuff with a band of faces, so the hand stays
        # on the arm as the wrist bends (each side's edge: the edges with one face, there).
        eb = gi["Elbow" + s]
        new_set = set(vs)
        rim_new = [e for e in bm.edges if e.is_boundary and all(v in new_set for v in e.verts)]
        rim_arm = [e for e in bm.edges if e.is_boundary and not any(v in new_set for v in e.verts)
                   and all(v[dl].get(wb, 0.0) + v[dl].get(eb, 0.0) >= 0.5 and HAND_CUT - 0.03 < along(v.co) < 0.08
                           and (M @ v.co - pivot).length < 0.12 for v in e.verts)]
        try:
            band = bmesh.ops.bridge_loops(bm, edges=rim_new + rim_arm)["faces"]
        except Exception as err:
            band = []
            print("WEIGHTS hand", s, "cuff not joined:", err)
        for f in band:
            f.smooth = True
            paint(f)
        print("WEIGHTS hand", s, "cuff joined to the arm: %d faces (edges %d and %d)" % (len(band), len(rim_new), len(rim_arm)))
        print("WEIGHTS hand", s, "CROSS's in place of its own: %d triangles for %d" % (made, gone_tris))
    bm.to_mesh(me)
    bm.free()
    me.update()
# HAND_CLEAN=k (environment): the dark creases baked between an open hand's fingers show as dark
# marks across the knuckles once HAND_CURL closes it into a fist. On the texture, each hand's texels
# (its faces wholly the wrist bone's, more than 5 cm past the wrist joint, so a watch or a cuff is left
# alone) darker than k times the hand's middle brightness take the colour of the nearest one that
# isn't: the hand's own tone, its light and shade kept. Then any texel there unlike the texels round it
# (a light scratch, a fleck) takes their middle colour (see despeckle below), from the same 5 cm on,
# so a watch or a cuff is left whole.
# WRIST_CLEAN="from,to" (environment, m along the arm from the right wrist joint, + toward the hand):
# the right wrist's band despeckled too. A right hand mirrored in from the left (MIRROR_BOX) meets the
# arm there, and the bake left marks along the join (a dark speck, the left cuff's cufflink mirrored).
def hand_texels(side, s_from, s_to, whole=True):
    """The texels of the faces on one arm between s_from and s_to along it from the wrist joint (m;
    whole: faces wholly the wrist bone's)."""
    s = "R" if side > 0 else "L"
    wb = gi["Wrist" + s]
    wrist = pos["Wrist" + s]
    run = (pos["Wrist" + s] - pos["Elbow" + s]).normalized()
    arm = {gi[n + s] for n in ("Elbow", "Wrist")}
    def on(v):
        a = (M @ v.co - wrist).dot(run)
        if not (s_from < a <= s_to):
            return False
        if whole:
            return sum(g.weight for g in v.groups if g.group == wb) >= 0.5
        return any(g.group in arm and g.weight > 0.3 for g in v.groups)
    on_hand = {v.index for v in me.vertices if on(v)}
    out = set()
    for t in me.loop_triangles:
        if not all(i in on_hand for i in t.vertices):
            continue
        p = [uvd[l].uv * mathutils.Vector((W, H)) for l in t.loops]
        area = (p[1] - p[0]).cross(p[2] - p[0])
        if abs(area) < 1e-9:
            continue
        for y in range(max(0, int(min(q.y for q in p))), min(H - 1, int(max(q.y for q in p))) + 1):
            for x in range(max(0, int(min(q.x for q in p))), min(W - 1, int(max(q.x for q in p))) + 1):
                c = mathutils.Vector((x + 0.5, y + 0.5))
                w0 = (p[2] - p[1]).cross(c - p[1]) / area
                w1 = (p[0] - p[2]).cross(c - p[2]) / area
                if min(w0, w1, 1.0 - w0 - w1) >= -0.15:
                    out.add((x, y))
    return out
def despeckle(texels, far=0.14, rad=2):
    """Each texel whose colour is further than `far` from the middle colour of the texels round it
    (within rad, of the same set) takes that middle colour: specks and thin marks go, edges between
    two colours stay (a texel there is near one side's)."""
    fix = {}
    for (x, y) in texels:
        near = [(x + dx, y + dy) for dx in range(-rad, rad + 1) for dy in range(-rad, rad + 1) if (x + dx, y + dy) in texels]
        if len(near) < 9:
            continue
        cols = [cpx[(q[1] * W + q[0]) * 4:(q[1] * W + q[0]) * 4 + 3] for q in near]
        mid = [sorted(c[k] for c in cols)[len(cols) // 2] for k in range(3)]
        i = (y * W + x) * 4
        if sum((cpx[i + k] - mid[k]) ** 2 for k in range(3)) ** 0.5 > far:
            fix[(x, y)] = mid
    for (x, y), c in fix.items():
        i = (y * W + x) * 4
        cpx[i:i + 3] = c
    return len(fix)
if os.environ.get("HAND_CLEAN") or os.environ.get("WRIST_CLEAN") or os.environ.get("BACK_EMBLEM") or os.environ.get("ANKLE_PATCH") or os.environ.get("RED_OFF_BACK"):
    cimg = [n.image for n in me.materials[0].node_tree.nodes if n.type == 'TEX_IMAGE'][0]
    W, H = cimg.size
    cpx = list(cimg.pixels)
    uvd = me.uv_layers.active.data
    me.calc_loop_triangles()
    cleaned = 0
    specks = 0
    if os.environ.get("HAND_CLEAN"):
        k_dark = float(os.environ["HAND_CLEAN"])
        for side in (1, -1):
            hand = hand_texels(side, 0.05, 1.0)
            def luma(q):
                i = (q[1] * W + q[0]) * 4
                return 0.3 * cpx[i] + 0.59 * cpx[i + 1] + 0.11 * cpx[i + 2]
            if not hand:
                continue
            mid_l = sorted(luma(q) for q in hand)[len(hand) // 2]
            dark = {q for q in hand if luma(q) < k_dark * mid_l}
            src_of = {q: q for q in hand if q not in dark}
            front = list(src_of)
            while front:
                nxt = []
                for (x, y) in front:
                    for d in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        q = (x + d[0], y + d[1])
                        if q in dark and q not in src_of:
                            src_of[q] = src_of[(x, y)]
                            nxt.append(q)
                front = nxt
            for q in dark:
                f = src_of.get(q)
                if f:
                    i, j = (q[1] * W + q[0]) * 4, (f[1] * W + f[0]) * 4
                    cpx[i:i + 3] = cpx[j:j + 3]
                    cleaned += 1
            specks += despeckle(hand_texels(side, 0.05, 1.0, whole=False), far=0.06, rad=3)
    if os.environ.get("WRIST_CLEAN"):
        w_from, w_to = [float(x) for x in os.environ["WRIST_CLEAN"].split(",")]
        specks += despeckle(hand_texels(1, w_from, w_to, whole=False))
    # BACK_EMBLEM=<png> (environment): the emblem on the back of a jacket replaced with another (Rebel's
    # scorpion, the signature of a well-known film's jacket, with the user's own tiger; the decision
    # log's "Eight skins for CROSS"). On the back of his torso (faces facing back, between his shoulder
    # blades and his waist), the old emblem's texels (bright gold: saturated, yellow to orange) are found
    # and filled with the suede round them (below); then the new emblem (art_source/skins/rebel/tiger.png,
    # or cobra.png) is laid over where the old one was, as tall as it was and centred on it, seen from
    # behind (its left on his left), taking a little of the suede's light and shade.
    if os.environ.get("BACK_EMBLEM"):
        import colorsys
        on_back = {}  # texel -> where it is on him (m)
        shared = {}  # texel -> each place on him it shows at
        for t in me.loop_triangles:
            nrm = (M.to_3x3() @ t.normal).normalized()
            if nrm.y > -0.1:  # (facing back, if only a little: the back curves round to the sides)
                continue
            P = [M @ me.vertices[i].co for i in t.vertices]
            c3 = (P[0] + P[1] + P[2]) / 3.0
            if abs(c3.x) > 0.2 or not (pos["Hips"].z < c3.z < pos["Neck"].z):
                continue
            p = [uvd[l].uv * mathutils.Vector((W, H)) for l in t.loops]
            area = (p[1] - p[0]).cross(p[2] - p[0])
            if abs(area) < 1e-9:
                continue
            for y in range(max(0, int(min(q.y for q in p))), min(H - 1, int(max(q.y for q in p))) + 1):
                for x in range(max(0, int(min(q.x for q in p))), min(W - 1, int(max(q.x for q in p))) + 1):
                    c = mathutils.Vector((x + 0.5, y + 0.5))
                    w0 = (p[2] - p[1]).cross(c - p[1]) / area
                    w1 = (p[0] - p[2]).cross(c - p[2]) / area
                    w2 = 1.0 - w0 - w1
                    if min(w0, w1, w2) >= -0.02:
                        q3 = P[0] * w0 + P[1] * w1 + P[2] * w2
                        on_back.setdefault((x, y), q3)
                        # (where two faces share a texel, mirrored across his back, both places)
                        if all((q3 - o).length > 0.03 for o in shared.setdefault((x, y), [])):
                            shared[(x, y)].append(q3)
        def hsv(q):
            i = (q[1] * W + q[0]) * 4
            return colorsys.rgb_to_hsv(cpx[i], cpx[i + 1], cpx[i + 2])
        def is_gold(q, s_min):
            h, s, v = hsv(q)
            return 0.04 < h < 0.18 and s > s_min and v > 0.4  # (bright: not his brown waistband)
        # BACK_EMBLEM_AT="x,z0,z1" (environment): a jacket with no emblem of its own (Future's): the new one
        # placed there instead (its middle across, m, and from its foot to its top, m up), nothing filled.
        at = os.environ.get("BACK_EMBLEM_AT")
        gold = set() if at else {q for q in on_back if is_gold(q, 0.3)}
        # (its soft edges: texels next to it a little gold too)
        for _ in range(2):
            gold |= {(x + dx, y + dy) for (x, y) in gold for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))
                     if (x + dx, y + dy) in on_back and is_gold((x + dx, y + dy), 0.16)}
        # The old emblem filled with the suede round it, on him (not in the texture, where the pieces
        # beside it may be anywhere on his back): each texel takes the middle colour of the back clear
        # of it within 4 cm (or the nearest such texel, further in), then soft blotches like the
        # suede's own (a smooth noise, 4 cm across, a tenth either way), so it isn't a flat patch where
        # the new emblem leaves a gap.
        from mathutils.kdtree import KDTree
        good = [q for q in on_back if q not in gold]
        kd = KDTree(len(good))
        for k, q in enumerate(good):
            kd.insert(on_back[q], k)
        kd.balance()
        def blotch(p):
            s = 0.04
            gx, gy, gz = p.x / s, p.y / s, p.z / s
            ix, iy, iz = math.floor(gx), math.floor(gy), math.floor(gz)
            fx, fy, fz = gx - ix, gy - iy, gz - iz
            def h(a, b, c):
                return ((a * 73856093) ^ (b * 19349663) ^ (c * 83492791)) % 1000 / 999.0
            def sm(t):
                return t * t * (3.0 - 2.0 * t)
            v = 0.0
            for a in (0, 1):
                for b in (0, 1):
                    for c in (0, 1):
                        w = (sm(fx) if a else 1 - sm(fx)) * (sm(fy) if b else 1 - sm(fy)) * (sm(fz) if c else 1 - sm(fz))
                        v += w * h(ix + a, iy + b, iz + c)
            return 0.9 + 0.2 * v
        fill = {}
        for q in gold:
            p = on_back[q]
            near = kd.find_range(p, 0.04) or [kd.find(p)]
            cols = [cpx[(good[k][1] * W + good[k][0]) * 4:(good[k][1] * W + good[k][0]) * 4 + 3] for _, k, _ in near]
            mid = [sorted(c[i] for c in cols)[len(cols) // 2] for i in range(3)]
            fill[q] = [min(1.0, c * blotch(p)) for c in mid]
        for (x, y), c in fill.items():
            cpx[(y * W + x) * 4:(y * W + x) * 4 + 3] = c
        if gold or at:
            if at:
                xa, z0, z1 = [float(v) for v in at.split(",")]
                x0 = x1 = xa
            else:
                where = [on_back[q] for q in gold]
                x0, x1 = min(p.x for p in where), max(p.x for p in where)
                z0, z1 = min(p.z for p in where), max(p.z for p in where)
            em = bpy.data.images.load(os.environ["BACK_EMBLEM"])
            ew, eh = em.size
            epx = list(em.pixels)
            # BACK_EMBLEM_FIT="scale,shift" (environment): the new emblem this share of the old one's
            # height, about its middle, and moved this far across (m; + his right, the viewer's right
            # from behind).
            e_scale, e_shift = [float(v) for v in os.environ.get("BACK_EMBLEM_FIT", "1,0").split(",")]
            zc = (z0 + z1) / 2.0
            tall = (z1 - z0) * e_scale
            z0, z1 = zc - tall / 2.0, zc + tall / 2.0
            wide = tall * ew / eh
            cx = (x0 + x1) / 2.0 + e_shift
            # (printed into the jacket: the emblem takes the suede's light and shade, each texel's brightness
            # against the jacket's middle brightness there, so it isn't a flat sticker on it)
            def lum(i):
                return 0.3 * cpx[i] + 0.59 * cpx[i + 1] + 0.11 * cpx[i + 2]
            lums = sorted(lum((q[1] * W + q[0]) * 4) for q in on_back)
            lum_mid = max(1e-3, lums[len(lums) // 2])
            laid = 0
            def sample(p):
                """The emblem at a place on his back: its colour times its cover, and its cover, summed
                over 2 x 2 samples in the texel (so its edges aren't jagged)."""
                u = (p.x - cx) / wide + 0.5
                v = (z1 - p.z) / tall  # (from its top)
                acc = [0.0, 0.0, 0.0, 0.0]
                if not (0.0 <= u < 1.0 and 0.0 <= v < 1.0):
                    return acc
                for su in (0.25, 0.75):
                    for sv in (0.25, 0.75):
                        ex = min(ew - 1, int(u * ew + (su - 0.5)))
                        ey = min(eh - 1, int(v * eh + (sv - 0.5)))
                        k = ((eh - 1 - max(0, ey)) * ew + max(0, ex)) * 4  # (Blender's rows go up)
                        a = epx[k + 3]
                        for c in range(3):
                            acc[c] += epx[k + c] * a
                        acc[3] += a
                return acc
            # BACK_EMBLEM_SHADOW="opacity,drop" (environment): a soft dark shadow just behind the emblem,
            # so it stands off the pale suede: the emblem's shape, softened over half a centimetre and
            # dropped this far (m) below it, darkening the jacket by this much at most.
            sh_k, sh_drop = [float(v) for v in os.environ.get("BACK_EMBLEM_SHADOW", "0,0").split(",")]
            SHADOW = (0.16, 0.11, 0.05)
            ring = [mathutils.Vector((0.0, 0.0, 0.0))] + [mathutils.Vector((0.005 * math.cos(t * math.pi / 4.0), 0.0, 0.005 * math.sin(t * math.pi / 4.0))) for t in range(8)]
            def shadow_at(p):
                q = p + mathutils.Vector((0.0, 0.0, sh_drop))
                return sum(sample(q + d)[3] for d in ring) / (4.0 * len(ring))
            for (x, y) in on_back:
                i = (y * W + x) * 4
                if sh_k > 0.0:
                    s = max(shadow_at(p) for p in shared[(x, y)]) * sh_k
                    if s > 0.0:
                        for c in range(3):
                            cpx[i + c] = cpx[i + c] * (1.0 - s) + SHADOW[c] * s
                # (a texel shown at two places, mirrored across his back, takes the emblem where it
                # covers more of them: a one-sided emblem can be right at only one of them)
                acc = max((sample(p) for p in shared[(x, y)]), key=lambda s: s[3])
                if acc[3] <= 0.0:
                    continue
                a = acc[3] / 4.0
                shade = min(1.1, max(0.88, 1.0 + 0.5 * (lum(i) / lum_mid - 1.0)))  # (half the suede's shading, kept gentle)
                for c in range(3):
                    cpx[i + c] = cpx[i + c] * (1.0 - a) + min(1.0, acc[c] / 4.0 * shade)
                laid += 1
            print("WEIGHTS back emblem: %d texels of the old one filled, the new one laid on %d (%.2f x %.2f m, %.2f to %.2f m up)"
                  % (len(gold), laid, wide, tall, z0, z1))
        else:
            print("WEIGHTS back emblem: no old emblem found")
    # ANKLE_PATCH=1 (environment): a round light patch on the side of each high-top's ankle (a trainer
    # brand's own mark: the Street Operative's) painted out in the shoe's colour. On the faces of his
    # feet that face sideways (not the laces on top, not the soles), 6 to 18 cm up, the light texels
    # take the middle colour of the rest of those faces' texels, a little of their own light and
    # shade kept.
    if os.environ.get("ANKLE_PATCH") == "1":
        legs = {gi[n] for n in ("AnkleR", "AnkleL", "KneeR", "KneeL")}
        side = set()
        for t in me.loop_triangles:
            if not all(sum(g.weight for g in me.vertices[i].groups if g.group in legs) >= 0.5 for i in t.vertices):
                continue
            nrm = (M.to_3x3() @ t.normal).normalized()
            P = [M @ me.vertices[i].co for i in t.vertices]
            c3 = (P[0] + P[1] + P[2]) / 3.0
            ankle = min((pos["AnkleR"], pos["AnkleL"]), key=lambda a: abs(a.x - c3.x))
            # (the side of the shoe behind the ankle joint, where the patch is: not the laces in front)
            if abs(nrm.x) < 0.5 or not (0.06 < c3.z < 0.2) or c3.y > ankle.y + 0.01:
                continue
            p = [uvd[l].uv * mathutils.Vector((W, H)) for l in t.loops]
            area = (p[1] - p[0]).cross(p[2] - p[0])
            if abs(area) < 1e-9:
                continue
            for y in range(max(0, int(min(q.y for q in p))), min(H - 1, int(max(q.y for q in p))) + 1):
                for x in range(max(0, int(min(q.x for q in p))), min(W - 1, int(max(q.x for q in p))) + 1):
                    c = mathutils.Vector((x + 0.5, y + 0.5))
                    w0 = (p[2] - p[1]).cross(c - p[1]) / area
                    w1 = (p[0] - p[2]).cross(c - p[2]) / area
                    if min(w0, w1, 1.0 - w0 - w1) >= -0.02:
                        side.add((x, y))
        def lum_at(q):
            i = (q[1] * W + q[0]) * 4
            return 0.3 * cpx[i] + 0.59 * cpx[i + 1] + 0.11 * cpx[i + 2]
        def sat_at(q):
            i = (q[1] * W + q[0]) * 4
            mx, mn = max(cpx[i:i + 3]), min(cpx[i:i + 3])
            return (mx - mn) / max(mx, 1e-4)
        def neutral(q):
            """Grey to white, not the denim's blue."""
            i = (q[1] * W + q[0]) * 4
            return sat_at(q) < 0.35 and cpx[i + 2] < cpx[i] + 0.04
        def red(q):
            i = (q[1] * W + q[0]) * 4
            return cpx[i] > cpx[i + 1] + 0.12 and cpx[i] > cpx[i + 2] + 0.08
        light = {q for q in side if lum_at(q) > 0.45 and neutral(q)}
        # (and the patch's dark middle, inside it)
        light |= {(x + dx, y + dy) for (x, y) in light for dx in (-2, -1, 0, 1, 2) for dy in (-2, -1, 0, 1, 2)
                  if (x + dx, y + dy) in side and neutral((x + dx, y + dy))}
        # (and its edge, a texel round it that isn't the shoe's full red)
        light |= {(x + dx, y + dy) for (x, y) in light for dx in (-1, 0, 1) for dy in (-1, 0, 1)
                  if (x + dx, y + dy) in side and not red((x + dx, y + dy))}
        rest = [q for q in side if q not in light and red(q)]
        if rest and light:
            mid = [sorted(cpx[(q[1] * W + q[0]) * 4 + k] for q in rest)[len(rest) // 2] for k in range(3)]
            for q in light:
                i = (q[1] * W + q[0]) * 4
                cpx[i:i + 3] = mid
        print("WEIGHTS ankle patches painted out:", len(light), "texels of", len(side))
    # RED_OFF_BACK="z0,z1" (environment): red painted down the back of his neck and jacket between these
    # heights (m) taken off (the Street Operative's headband tails, part of the source: his ribbons are
    # live now, and the painted ones showed as a red patch on his jacket). On the faces facing back
    # there, each red texel takes the middle colour of the texels round it on him (within 3 cm) that
    # aren't red: his jacket's black, or his neck's skin.
    if os.environ.get("RED_OFF_BACK"):
        from mathutils.kdtree import KDTree
        rz0, rz1 = [float(v) for v in os.environ["RED_OFF_BACK"].split(",")]
        where = {}
        for t in me.loop_triangles:
            nrm = (M.to_3x3() @ t.normal).normalized()
            P = [M @ me.vertices[i].co for i in t.vertices]
            c3 = (P[0] + P[1] + P[2]) / 3.0
            if nrm.y > 0.0 or not (rz0 < c3.z < rz1) or abs(c3.x) > 0.2:
                continue
            p = [uvd[l].uv * mathutils.Vector((W, H)) for l in t.loops]
            area = (p[1] - p[0]).cross(p[2] - p[0])
            if abs(area) < 1e-9:
                continue
            for y in range(max(0, int(min(q.y for q in p))), min(H - 1, int(max(q.y for q in p))) + 1):
                for x in range(max(0, int(min(q.x for q in p))), min(W - 1, int(max(q.x for q in p))) + 1):
                    c = mathutils.Vector((x + 0.5, y + 0.5))
                    w0 = (p[2] - p[1]).cross(c - p[1]) / area
                    w1 = (p[0] - p[2]).cross(c - p[2]) / area
                    if min(w0, w1, 1.0 - w0 - w1) >= -0.02:
                        where[(x, y)] = P[0] * w0 + P[1] * w1 + P[2] * (1.0 - w0 - w1)
        def is_red(q):
            i = (q[1] * W + q[0]) * 4
            r, g, b = cpx[i], cpx[i + 1], cpx[i + 2]
            return r > 0.22 and r > g * 1.8 and r > b * 1.8
        reds = [q for q in where if is_red(q)]
        # (and a texel round each, its soft edge)
        reds = set(reds) | {(x + dx, y + dy) for (x, y) in reds for dx in (-1, 0, 1) for dy in (-1, 0, 1)
                            if (x + dx, y + dy) in where and cpx[((y + dy) * W + x + dx) * 4] > cpx[((y + dy) * W + x + dx) * 4 + 1] * 1.3}
        clear = [q for q in where if q not in reds]
        if reds and clear:
            kd = KDTree(len(clear))
            for k, q in enumerate(clear):
                kd.insert(where[q], k)
            kd.balance()
            fill = {}
            for q in reds:
                near = kd.find_range(where[q], 0.03) or [kd.find(where[q])]
                cols = [cpx[(clear[k][1] * W + clear[k][0]) * 4:(clear[k][1] * W + clear[k][0]) * 4 + 3] for _, k, _ in near]
                fill[q] = [sorted(c[i] for c in cols)[len(cols) // 2] for i in range(3)]
            for (x, y), c in fill.items():
                cpx[(y * W + x) * 4:(y * W + x) * 4 + 3] = c
        print("WEIGHTS red off his back:", len(reds), "texels of", len(where))
    # The margins round the texture's pieces made again from the cleaned colours, 4 texels out (as
    # REMARGIN in stage 3): they still held the colours from before, and a triangle's edge reads a texel
    # or two of them (a dotted line along Midnight's cuff where it meets his hand).
    covered = bytearray(W * H)
    for t in me.loop_triangles:
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
                    covered[y * W + x] = 1
    front = [i for i in range(W * H) if covered[i]]
    for _ in range(4):
        ring = []
        for i in front:
            x, y = i % W, i // W
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                j = (y + dy) * W + x + dx
                if 0 <= x + dx < W and 0 <= y + dy < H and not covered[j]:
                    covered[j] = 2
                    ring.append(j)
        for j in ring:
            x, y = j % W, j // W
            acc = [0.0, 0.0, 0.0]
            n = 0
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                k = (y + dy) * W + x + dx
                if 0 <= x + dx < W and 0 <= y + dy < H and covered[k] == 1:
                    acc = [acc[c] + cpx[k * 4 + c] for c in range(3)]
                    n += 1
            if n:
                cpx[j * 4:j * 4 + 3] = [a / n for a in acc]
        for j in ring:
            covered[j] = 1
        front = ring
    cimg.pixels[:] = cpx
    cimg.pack()  # (the export takes the packed copy)
    print("WEIGHTS hands cleaned:", cleaned, "dark texels,", specks, "specks")
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
if out_game_json:  # what the game reads alongside the model (the lenses; and a headband's ribbons)
    game = {"lenses": lenses}
    # RIBBONS=<json> (environment): a headband's ribbon tails, moved live by SoldierRig (its "Ribbons"):
    # where they're tied on the model at rest, their colour, length, width and how far apart.
    if os.environ.get("RIBBONS"):
        game["ribbons"] = json.loads(os.environ["RIBBONS"])
    with open(out_game_json, "w") as f:
        json.dump(game, f, indent=1)
# --- Export.
for o in bpy.context.selected_objects: o.select_set(False)
low.select_set(True)
rig.select_set(True)
bpy.ops.export_scene.gltf(filepath=out_glb, export_format='GLB', use_selection=True, export_skins=True,
        export_animations=False, export_yup=True, export_apply=False, export_materials='EXPORT')
bpy.ops.wm.save_as_mainfile(filepath=blend.replace(".blend", "_rigged.blend"))
print("EXPORTED", out_glb, os.path.getsize(out_glb))
