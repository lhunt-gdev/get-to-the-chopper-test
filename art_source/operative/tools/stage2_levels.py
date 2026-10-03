import bpy, sys, os, mathutils
sys.path.append(os.path.dirname(__file__))
import render_util
argv = sys.argv[sys.argv.index("--") + 1:]
work, out = argv[0], argv[1]
for target in (1500, 3000, 5000):
    bpy.ops.wm.open_mainfile(filepath=os.path.join(work, "cross_20k.blend"))
    obj = bpy.data.objects["CROSS"]
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    mod = obj.modifiers.new("lvl", 'DECIMATE'); mod.decimate_type = 'COLLAPSE'
    mod.ratio = target / len(obj.data.polygons); mod.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier=mod.name)
    obj.data.calc_loop_triangles()
    print("LEVEL", target, len(obj.data.loop_triangles))
    h = max((obj.matrix_world @ v.co).z for v in obj.data.vertices)
    render_util.render(f"{out}/lvl{target}", mathutils.Vector((0, 0, h / 2)), h * 1.06, angles=(("front", 0), ("left", 90)))
    render_util.render(f"{out}/lvl{target}_head", mathutils.Vector((0, 0, h - 0.14)), 0.4, angles=(("front", 0), ("left", 90)), resx=400, resy=400)
