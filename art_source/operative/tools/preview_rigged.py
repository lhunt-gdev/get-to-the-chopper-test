import bpy, sys, os, mathutils
sys.path.append(os.path.dirname(__file__))
import render_util
argv = sys.argv[sys.argv.index("--") + 1:]
bpy.ops.wm.open_mainfile(filepath=argv[0])
low = bpy.data.objects["CROSS_low"]
h = max((low.matrix_world @ v.co).z for v in low.data.vertices)
render_util.render(argv[1], mathutils.Vector((0, 0, h / 2)), h * 1.06, angles=(("front", 0), ("left", 90)))
print("H", h)
