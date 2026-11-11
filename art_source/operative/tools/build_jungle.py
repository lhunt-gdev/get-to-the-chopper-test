# The Jungle Operative (the decision log's "Jungle Operative, a skin for CROSS"): CROSS's own finished
# model with its texture repainted, his urban grey camo made a woodland jungle camo and camouflage paint
# streaked across his face under the goggles. The model itself (mesh, joints, weights, hands) is CROSS's
# byte for byte: only the texture packed in it is swapped.
#   blender --background --factory-startup --python build_jungle.py -- <cross.glb> <out.glb>
import bpy, sys, os, json, struct, math, tempfile
import numpy as np
import mathutils

argv = sys.argv[sys.argv.index("--") + 1:]
src, out = argv[0], argv[1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
obj = [o for o in bpy.data.objects if o.type == 'MESH'][0]
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
me = obj.data
M = obj.matrix_world
img = [n.image for n in me.materials[0].node_tree.nodes if n.type == 'TEX_IMAGE'][0]
W, H = img.size
px = np.array(img.pixels[:], dtype=np.float32).reshape(H, W, 4)  # (rows from the bottom, as Blender's)

# --- Which joint each texel's face follows most (its gloves follow his wrists, his boots his ankles,
# his face and hair his head): the camo and the olive drab go on his clothes and kit only.
gi = {g.name: g.index for g in obj.vertex_groups}
names = {g.index: g.name for g in obj.vertex_groups}
uvd = me.uv_layers.active.data
me.calc_loop_triangles()
part = np.full((H, W), "", dtype=object)
def main_bone(vi):
    gs = me.vertices[vi].groups
    return names[max(gs, key=lambda g: g.weight).group] if len(gs) else ""
for t in me.loop_triangles:
    bones = [main_bone(i) for i in t.vertices]
    bone = max(set(bones), key=bones.count)
    p = [uvd[l].uv * mathutils.Vector((W, H)) for l in t.loops]
    area = (p[1] - p[0]).cross(p[2] - p[0])
    if abs(area) < 1e-9:
        continue
    for y in range(max(0, int(min(v.y for v in p))), min(H - 1, int(max(v.y for v in p))) + 1):
        for x in range(max(0, int(min(v.x for v in p))), min(W - 1, int(max(v.x for v in p))) + 1):
            c = mathutils.Vector((x + 0.5, y + 0.5))
            w0 = (p[2] - p[1]).cross(c - p[1]) / area
            w1 = (p[0] - p[2]).cross(c - p[2]) / area
            if min(w0, w1, 1.0 - w0 - w1) >= -0.05:
                part[y, x] = bone
kit = np.vectorize(lambda s: not (s.startswith("Wrist") or s.startswith("Ankle") or s in ("Head", "")))(part)

# --- The camo. His urban camo's texels (on his clothes: a cool grey-blue, not much colour in it,
# neither near black nor near white) each take a woodland colour by how light they are among them
# (four bands by quarter, so its blotches stay where they were), keeping a little of their own light
# and shade within the band so the cloth still has its folds. The rest of his kit that's grey (his
# vest, pouches, knee pads, straps) is tinted olive drab, its light and shade kept.
rgb = px[..., :3]
mx = rgb.max(axis=2)
mn = rgb.min(axis=2)
sat = np.where(mx > 1e-4, (mx - mn) / np.maximum(mx, 1e-4), 0.0)
r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
lum = 0.3 * r + 0.59 * g + 0.11 * b
camo = kit & (b > r + 0.012) & (sat < 0.32) & (mx > 0.16) & (mx < 0.92)
cl = lum[camo]
q = np.quantile(cl, [0.25, 0.5, 0.75])
PALETTE = np.array([
    [0.095, 0.105, 0.065],  # black-green
    [0.235, 0.185, 0.115],  # brown
    [0.165, 0.215, 0.105],  # dark green
    [0.300, 0.330, 0.185],  # olive green
], dtype=np.float32)
band = np.digitize(lum, q)  # 0..3
edges = np.concatenate([[cl.min()], q, [cl.max()]])
lo = edges[band]
hi = edges[band + 1]
within = np.clip((lum - lo) / np.maximum(hi - lo, 1e-4), 0.0, 1.0)
shade = (0.88 + 0.24 * within)[..., None]
newc = PALETTE[band] * shade
gear = kit & ~camo & (sat < 0.25) & (mx > 0.12)
OLIVE = np.array([0.36, 0.36, 0.24], dtype=np.float32)
tint = OLIVE[None, None, :] * (lum / 0.355)[..., None]
rgb[gear] = np.clip(tint[gear], 0.0, 1.0)
rgb[camo] = newc[camo]
print("JUNGLE camo texels repainted:", int(camo.sum()), "| kit tinted olive drab:", int(gear.sum()))

# --- The face paint. Each texel of his face (faces wholly his head's, facing forward, below the
# goggles' lenses) is placed on him, and streaks drawn there: dark green and black, slanting
# down and out from his nose across his cheeks, and a band across the bridge of his nose,
# each streak's edge wavering as paint put on by hand does.
head_g = gi["Head"]
neck_g = gi.get("Neck")
lenses = json.load(open(os.path.splitext(src)[0] + ".json"))["lenses"]
lens_y = sum(l[1] for l in lenses) / len(lenses)  # (Godot's up is Blender's z)
lens_x = sum(l[0] for l in lenses) / len(lenses)
uvd = me.uv_layers.active.data
me.calc_loop_triangles()
def head_w(vi):
    return sum(g.weight for g in me.vertices[vi].groups if g.group == head_g)
face = {}
for t in me.loop_triangles:
    if min(head_w(i) for i in t.vertices) < 0.5:
        continue
    nrm = (M.to_3x3() @ t.normal).normalized()
    if nrm.y < 0.15:  # (facing forward: he faces +Y here)
        continue
    P = [M @ me.vertices[i].co for i in t.vertices]
    p = [uvd[l].uv * mathutils.Vector((W, H)) for l in t.loops]
    area = (p[1] - p[0]).cross(p[2] - p[0])
    if abs(area) < 1e-9:
        continue
    for y in range(max(0, int(min(v.y for v in p))), min(H - 1, int(max(v.y for v in p))) + 1):
        for x in range(max(0, int(min(v.x for v in p))), min(W - 1, int(max(v.x for v in p))) + 1):
            c = mathutils.Vector((x + 0.5, y + 0.5))
            w0 = (p[2] - p[1]).cross(c - p[1]) / area
            w1 = (p[0] - p[2]).cross(c - p[2]) / area
            w2 = 1.0 - w0 - w1
            if min(w0, w1, w2) >= -0.02:
                face[(x, y)] = P[0] * w0 + P[1] * w1 + P[2] * w2
DARK = np.array([0.12, 0.16, 0.07], dtype=np.float32)
BLACK = np.array([0.06, 0.06, 0.045], dtype=np.float32)
painted = 0
for (x, y), p in face.items():
    u = p.x - lens_x            # across his face from its middle (m; + his left)
    z = p.z - lens_y            # down from the lenses (m; - below)
    if z > -0.012 or z < -0.16:
        continue
    if max(px[y, x, :3]) < 0.16:
        continue  # (the goggles' straps and anything as dark)
    a = abs(u)
    wav = 0.0025 * math.sin(z * 140.0 + (1.3 if u > 0 else 0.0)) + 0.0015 * math.sin(a * 220.0)
    paint = None
    # (the band across the bridge of his nose and under his eyes, its lower edge ragged)
    if z > -0.034 + wav and a < 0.052:
        paint = DARK
    # (two broad streaks down each cheek, slanting out as they go down: black nearer his nose, dark
    # green further out; the skin shows between them)
    k = a + 0.45 * z
    for k0, k1, colour in ((0.004, 0.016, BLACK), (0.026, 0.038, DARK)):
        if k0 + wav < k < k1 + wav and z > -0.115 and a > 0.012:
            paint = colour
    if paint is not None:
        px[y, x, :3] = px[y, x, :3] * 0.12 + paint * 0.88
        painted += 1
print("JUNGLE face texels painted:", painted, "of", len(face))

# --- The new texture, packed into a copy of CROSS's model in place of his.
tmp = os.path.join(tempfile.gettempdir(), "jungle_texture.png")
img.pixels[:] = px.ravel()
img.filepath_raw = tmp
img.file_format = 'PNG'
img.save()
png = open(tmp, "rb").read()
data = open(src, "rb").read()
magic, version, length = struct.unpack_from("<III", data, 0)
jlen, jtype = struct.unpack_from("<II", data, 12)
gltf = json.loads(data[20:20 + jlen])
blen, btype = struct.unpack_from("<II", data, 20 + jlen)
bin_ = data[28 + jlen:28 + jlen + blen]
image_view = gltf["images"][0]["bufferView"]
chunks = []
for i, bv in enumerate(gltf["bufferViews"]):
    off = bv.get("byteOffset", 0)
    chunks.append(png if i == image_view else bin_[off:off + bv["byteLength"]])
new_bin = b""
for bv, c in zip(gltf["bufferViews"], chunks):
    new_bin += b"\0" * ((-len(new_bin)) % 4)
    bv["byteOffset"] = len(new_bin)
    bv["byteLength"] = len(c)
    new_bin += c
new_bin += b"\0" * ((-len(new_bin)) % 4)
gltf["buffers"][0]["byteLength"] = len(new_bin)
gltf["images"][0]["name"] = os.path.splitext(os.path.basename(out))[0] + "_3000_512"
js = json.dumps(gltf, separators=(",", ":")).encode()
js += b" " * ((-len(js)) % 4)
glb = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(new_bin))
glb += struct.pack("<II", len(js), 0x4E4F534A) + js + struct.pack("<II", len(new_bin), 0x004E4942) + new_bin
open(out, "wb").write(glb)
json.dump({"lenses": lenses}, open(os.path.splitext(out)[0] + ".json", "w"), indent=1)
print("JUNGLE done:", out, len(glb), "bytes")
