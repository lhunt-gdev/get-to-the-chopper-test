import bpy, sys, mathutils
argv = sys.argv[sys.argv.index("--") + 1:]
bpy.ops.wm.open_mainfile(filepath=argv[0])
low = bpy.data.objects["CROSS_low"]
V = [low.matrix_world @ v.co for v in low.data.vertices]
for side in (1, -1):
    shin = [v for v in V if 0.3 < v.z < 0.4 and v.x * side > 0.05]
    foot = [v for v in V if v.z < 0.05 and v.x * side > 0.05]
    sy = (min(v.y for v in shin) + max(v.y for v in shin)) / 2
    print("FOOT side", side, "shin centre y", round(sy, 3), "toe reach +y", round(max(v.y for v in foot) - sy, 3), "toe reach -y", round(sy - min(v.y for v in foot), 3))
head = [v for v in V if v.z > 1.68]
print("HEAD y range", round(min(v.y for v in head), 3), round(max(v.y for v in head), 3))
