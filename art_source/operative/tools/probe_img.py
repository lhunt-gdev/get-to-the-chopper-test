import bpy, sys
argv = sys.argv[sys.argv.index("--") + 1:]
bpy.ops.wm.open_mainfile(filepath=argv[0])
low = bpy.data.objects["CROSS_low"]
img = [n.image for n in low.data.materials[0].node_tree.nodes if n.type == 'TEX_IMAGE'][0]
print("IMG", img.name, img.size[:], img.filepath, img.has_data, img.source, img.packed_file is not None)
img.reload()
px = img.pixels[:]
w = img.size[0]
best = []
for i in range(0, len(px), 4):
    r, g, b = px[i], px[i+1], px[i+2]
    best.append((g - max(r, b), (i // 4) % w, (i // 4) // w, round(r, 2), round(g, 2), round(b, 2)))
best.sort(reverse=True)
print("TOPGREEN", best[:8])
