# Stage 1: import a character's Meshy model, stand him on the ground,
# save his colour texture, and reduce him to a 20k-triangle working copy.
# CHAR (environment) names the character's files and objects: "cross" (the default), "guard"...
import bpy, sys, math, os
name = os.environ.get("CHAR", "cross")
NAME = name.upper()
argv = sys.argv[sys.argv.index("--") + 1:]
src, work = argv[0], argv[1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
mat = meshes[0].data.materials[0]
base = None
for n in mat.node_tree.nodes:
    if n.type == 'BSDF_PRINCIPLED':
        link = n.inputs['Base Color'].links
        if link and link[0].from_node.type == 'TEX_IMAGE':
            base = link[0].from_node.image
print("BASE", base.name if base else None, [(n.type, n.image.name if getattr(n, 'image', None) else '') for n in mat.node_tree.nodes])
base.filepath_raw = os.path.join(work, f"{name}_basecolor_2048.png")
base.file_format = 'PNG'
base.save()
obj = meshes[0]
bpy.context.view_layer.objects.active = obj
obj.select_set(True)
# Feet on the ground. (Which way he faces is left to stage 4, which checks his boots.)
mn_z = min((obj.matrix_world @ v.co).z for v in obj.data.vertices)
obj.location.z -= mn_z
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
mod = obj.modifiers.new("reduce", 'DECIMATE')
mod.decimate_type = 'COLLAPSE'
mod.ratio = 20000 / len(obj.data.polygons)
mod.use_collapse_triangulate = True
bpy.ops.object.modifier_apply(modifier=mod.name)
obj.data.calc_loop_triangles()
print("TRIS", len(obj.data.loop_triangles))
obj.name = NAME
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(work, f"{name}_20k.blend"))
print("SAVED")
