# Stage 1b (only for a character model made with his arms out: a T-pose, arms straight out, or arms
# partway down): lower his arms to the A-pose the rig expects (stage 4 and SoldierRig: the upper arms
# about 22 degrees out from hanging, like CROSS), once, on the 20k working copy, before the remesh
# and bake.
#
# Each arm turns down about a pivot inside the ball of its shoulder. How much of the turn a vertex
# takes ramps smoothly from none (the body) to all (the arm) across the shoulder, so the shoulder
# bends round like a dual-quaternion (volume-keeping) skin rather than creasing; the side of the
# body under the armpit stays put. With one pivot and one axis per arm, that blend is exactly a
# turn by weight * angle about the pivot, so no armature is needed.
#
# "slanted" is for arms already partway down (Bishop's hang about 38 degrees out): each arm's line is
# measured, and it's turned down only the rest of the way, about the ball of the shoulder, along
# the arm instead of across it.
#
# Usage: blender --background --python stage1b_apose.py -- WORK [hang_degrees=22] [slanted]
# (CHAR as stage 1)
import bpy, sys, os, math, mathutils
name = os.environ.get("CHAR", "cross")
argv = sys.argv[sys.argv.index("--") + 1:]
work = argv[0]
hang = math.radians(float(argv[1]) if len(argv) > 1 else 22.0)
slanted = len(argv) > 2 and argv[2] == "slanted"
path = os.path.join(work, f"{name}_20k.blend")
bpy.ops.wm.open_mainfile(filepath=path)
obj = bpy.data.objects[name.upper()]
me = obj.data
M = obj.matrix_world
Mi = M.inverted()
V = [M @ v.co for v in me.vertices]
h = max(v.z for v in V)


def smoothstep(e0, e1, x):
    t = min(1.0, max(0.0, (x - e0) / (e1 - e0)))
    return t * t * (3.0 - 2.0 * t)


def lower_slanted(side):
    """An arm already partway down: measure its line and turn it down the rest of the way."""
    # The arm's line: the middle of each upright slice through it, from just outside the shoulder
    # (0.28 m out) to the forearm (0.50 m), above the hips (nothing else is out there).
    pts = []
    x = 0.28
    while x <= 0.50 + 1e-6:
        s = [v for v in V if abs(v.x * side - x) < 0.01 and v.z > 0.95]
        if len(s) >= 4:
            lo, hi = min(v.z for v in s), max(v.z for v in s)
            pts.append((x, (lo + hi) / 2.0, (min(v.y for v in s) + max(v.y for v in s)) / 2.0, hi - lo))
        x += 0.02
    if len(pts) < 5:
        print("APOSE side", side, "no arm out there")
        return
    # Least squares, z (and y) against x out from the middle.
    n = len(pts)
    mx = sum(p[0] for p in pts) / n
    mz = sum(p[1] for p in pts) / n
    my = sum(p[2] for p in pts) / n
    sxx = sum((p[0] - mx) ** 2 for p in pts)
    bz = sum((p[0] - mx) * (p[1] - mz) for p in pts) / sxx  # z change per metre out (negative: down)
    by = sum((p[0] - mx) * (p[2] - my) for p in pts) / sxx  # y change per metre out (its lean, front or back)
    below = math.atan(-bz)  # how far below straight out
    out_angle = math.pi / 2.0 - below  # how far out from hanging
    # The arm's thickness across itself (an upright slice through a slanted arm is longer).
    thick = sorted(p[3] for p in pts)[n // 2] * math.cos(below)
    radius = thick / 2.0
    # Along the arm, outward and down (u), and across it, inward and down toward the body (nrm), in
    # (x * side, z).
    u = (math.cos(below), -math.sin(below))
    nrm = (-math.sin(below), -math.cos(below))
    # The pivot, in the ball of the shoulder: on the arm's line, 5 cm under the top of the shoulder
    # (where stage 4 puts the shoulder joint, 4 cm under it).
    top = max(v.z for v in V if 0.18 <= v.x * side <= 0.30 and v.z < h * 0.9)
    pz = top - 0.05
    px = mx + (pz - mz) / bz
    pivot = mathutils.Vector((side * px, my + by * (px - mx), pz))
    # The turn: from the arm's line as made to hanging `hang` out to the side, level front to back
    # (Bishop's source has one arm reaching forward and the other back: both come to his sides). With
    # no lean, and the shoulder at the middle of the body's depth, it's a turn about y, straight down sideways.
    was = mathutils.Vector((side, by, bz)).normalized()
    # Level front to back: the hand ends (about 0.6 m down the arm) at the middle of the body's depth.
    mid = [v.y for v in V if abs(v.x) < 0.12 and abs(v.z - h * 0.66) < 0.02]
    y_mid = (min(mid) + max(mid)) / 2.0
    to = mathutils.Vector((side * math.sin(hang), (y_mid - pivot.y) / 0.6, -math.cos(hang))).normalized()
    axis = was.cross(to).normalized()
    turn = was.angle(to)
    moved = 0
    for i, v in enumerate(me.vertices):
        p = V[i]
        dx, dz = p.x * side - px, p.z - pz
        s = dx * u[0] + dz * u[1]  # how far out along the arm past the pivot
        d = dx * nrm[0] + dz * nrm[1]  # how far in under the arm's line, toward the body
        w = smoothstep(-0.05, 0.09, s)
        # What's well in under the arm (the side of the body, the hips, a holster) stays put.
        if d > radius * 1.1:
            w *= 1.0 - smoothstep(radius * 1.1, radius * 1.6, d)
        if w <= 0.0:
            continue
        r = mathutils.Matrix.Rotation(turn * w, 4, axis)
        q = pivot + (r @ (p - pivot).to_4d()).to_3d()
        v.co = Mi @ q
        moved += 1
    print("APOSE side", side, "leaning %.1f deg %s" % (math.degrees(abs(math.atan(by))), "back" if by > 0 else "forward"))
    print("APOSE side", side, "slanted arm %.1f deg out from hanging, radius %.3f, shoulder top %.3f, pivot %s: moved %d verts, turned %.1f deg" % (
            math.degrees(out_angle), radius, top, tuple(round(c, 3) for c in pivot), moved, math.degrees(turn)))


for side in (1, -1):
    if slanted:
        lower_slanted(side)
        continue
    # The arm's axis: the middle of its section halfway out, at 0.55-0.65 m from the middle.
    mid = [v for v in V if 0.55 <= v.x * side <= 0.65]
    if len(mid) < 10:
        print("APOSE side", side, "no arm out there (not a T-pose?)")
        continue
    za = (min(v.z for v in mid) + max(v.z for v in mid)) / 2.0
    ya = (min(v.y for v in mid) + max(v.y for v in mid)) / 2.0
    radius = (max(v.z for v in mid) - min(v.z for v in mid)) / 2.0
    # Where the arm meets the body: going in from the elbow, the first place the mesh reaches well
    # below the arm (the body's side under the armpit).
    root = 0.55
    x = 0.55
    while x > 0.08:
        band = [v for v in V if abs(v.x * side - x) < 0.01 and abs(v.y - ya) < 0.15]
        if band and min(v.z for v in band) < za - radius * 2.5:
            root = x
            break
        x -= 0.01
    pivot = mathutils.Vector((side * (root - 0.03), ya, za))
    turn = math.pi / 2.0 - hang  # from straight out down to `hang` out from hanging
    axis = mathutils.Vector((0, 1, 0))
    moved = 0
    for i, v in enumerate(me.vertices):
        p = V[i]
        s = p.x * side - (root - 0.03)  # how far out past the pivot
        w = smoothstep(-0.05, 0.09, s)
        # The body's side under the armpit stays with the body.
        if s < 0.09 and p.z < za - radius * 1.1:
            w *= smoothstep(za - radius * 1.6, za - radius * 1.1, p.z)
        if w <= 0.0:
            continue
        r = mathutils.Matrix.Rotation(side * turn * w, 4, axis)
        q = pivot + (r @ (p - pivot).to_4d()).to_3d()
        v.co = Mi @ q
        moved += 1
    print("APOSE side", side, "arm axis z %.3f y %.3f radius %.3f root x %.3f pivot %s: moved %d verts, turned %.1f deg" % (
            za, ya, radius, root, tuple(round(c, 3) for c in pivot), moved, math.degrees(turn)))
me.update()
# Back on the ground (the hands now hang below where they were).
mn_z = min((M @ v.co).z for v in me.vertices)
if mn_z < 0.0:
    for v in me.vertices:
        v.co.z -= mn_z
    me.update()
bpy.ops.wm.save_as_mainfile(filepath=path)
print("APOSED", path)
