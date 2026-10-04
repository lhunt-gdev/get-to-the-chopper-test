# Stage 1b (only for a character Meshy made in a T-pose, arms straight out): lower his arms to the
# A-pose the rig expects (stage 4 and SoldierRig: the upper arms about 22 degrees out from hanging,
# like CROSS), once, on the 20k working copy, before the remesh and bake.
#
# Each arm turns down about a pivot inside the ball of its shoulder. How much of the turn a vertex
# takes ramps smoothly from none (the body) to all (the arm) across the shoulder, so the shoulder
# bends round like a dual-quaternion (volume-keeping) skin rather than creasing; the side of the
# body under the armpit stays put. With one pivot and one axis per arm, that blend is exactly a
# turn by weight * angle about the pivot, so no armature is needed.
#
# Usage: blender --background --python stage1b_apose.py -- WORK [hang_degrees=22]   (CHAR as stage 1)
import bpy, sys, os, math, mathutils
name = os.environ.get("CHAR", "cross")
argv = sys.argv[sys.argv.index("--") + 1:]
work = argv[0]
hang = math.radians(float(argv[1]) if len(argv) > 1 else 22.0)
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


for side in (1, -1):
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
