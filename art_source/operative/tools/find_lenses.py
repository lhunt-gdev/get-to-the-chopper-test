# Where CROSS's goggle lenses are on the model: the vertices whose texture there is bright green,
# in two clusters (left and right lens). Written to the joints JSON in Godot's axes (x, z, -y).
import bpy, sys, json
argv = sys.argv[sys.argv.index("--") + 1:]
bpy.ops.wm.open_mainfile(filepath=argv[0])
low = bpy.data.objects["CROSS_low"]
me = low.data
# (Stage 4 does this itself now.) Only on a model facing +Y, i.e. stage 4's output: his toes reach forward.
_V = [low.matrix_world @ v.co for v in me.vertices]
_shin = [v for v in _V if 0.3 < v.z < 0.4]; _foot = [v for v in _V if v.z < 0.05]
_sy = (min(v.y for v in _shin) + max(v.y for v in _shin)) / 2.0
if _sy - min(v.y for v in _foot) > max(v.y for v in _foot) - _sy:
    raise SystemExit("find_lenses: this model faces -Y; run it on stage 4's rigged .blend")
img = [n.image for n in low.data.materials[0].node_tree.nodes if n.type == 'TEX_IMAGE'][0]
w, h = img.size
px = list(img.pixels)
uv = me.uv_layers.active.data
hits = []
me.calc_loop_triangles()
for tri in me.loop_triangles:
    uvs = [uv[li].uv for li in tri.loops]
    cos = [low.matrix_world @ me.vertices[vi].co for vi in tri.vertices]
    for a in range(5):
        for b in range(5 - a):
            c = 4 - a - b
            wa, wb, wc = a / 4.0, b / 4.0, c / 4.0
            u = uvs[0].x * wa + uvs[1].x * wb + uvs[2].x * wc
            v = uvs[0].y * wa + uvs[1].y * wb + uvs[2].y * wc
            x = min(w - 1, max(0, int(u * w))); y = min(h - 1, max(0, int(v * h)))
            i = (y * w + x) * 4
            r, g, bl = px[i], px[i + 1], px[i + 2]
            if g > 0.5 and g - max(r, bl) > 0.12:  # the lenses' green glow
                hits.append(cos[0] * wa + cos[1] * wb + cos[2] * wc)
print("GREEN_HITS", len(hits))
lenses = []
pts = sorted([p for p in hits if p.z > 1.6], key=lambda p: p.x)
gaps = [(pts[i + 1].x - pts[i].x, i) for i in range(len(pts) - 1)]
cut = max(gaps)[1] + 1 if gaps else len(pts)
for group in (pts[:cut], pts[cut:]):  # two lenses: split where the gap between them is
    if group:
        c = sum(group, group[0] * 0) / len(group)
        lenses.append([c.x, c.z, -max(p.y for p in group)])
print("LENSES", lenses)
with open(argv[1]) as f:
    data = json.load(f)
data["lenses_godot"] = lenses
with open(argv[1], "w") as f:
    json.dump(data, f, indent=1)
