# CROSS, stage 3: a clean low-poly CROSS. The 20k working copy is remeshed into one closed skin,
# reduced to the target triangle count, unwrapped, and the working copy's colours are baked onto
# a fresh texture for it (the standard game-art route: Meshy's surface is loose overlapping pieces
# that don't reduce cleanly on their own).
import bpy, sys, os, mathutils
sys.path.append(os.path.dirname(__file__))
import render_util
argv = sys.argv[sys.argv.index("--") + 1:]
work, out, target, tex = argv[0], argv[1], int(argv[2]), int(argv[3])
voxel = float(argv[4]) if len(argv) > 4 else 0.008
bpy.ops.wm.open_mainfile(filepath=os.path.join(work, "cross_20k.blend"))
src = bpy.data.objects["CROSS"]
src.name = "CROSS_high"
low = src.copy(); low.data = src.data.copy(); low.name = "CROSS_low"
bpy.context.scene.collection.objects.link(low)
for o in bpy.context.selected_objects: o.select_set(False)
bpy.context.view_layer.objects.active = low; low.select_set(True)
rm = low.modifiers.new("remesh", 'REMESH'); rm.mode = 'VOXEL'; rm.voxel_size = voxel; rm.adaptivity = 0.0
bpy.ops.object.modifier_apply(modifier=rm.name)
print("REMESHED", len(low.data.polygons))
dm = low.modifiers.new("reduce", 'DECIMATE'); dm.decimate_type = 'COLLAPSE'; dm.use_collapse_triangulate = True
low.data.calc_loop_triangles()
dm.ratio = target / max(1, len(low.data.loop_triangles))  # target is in triangles
bpy.ops.object.modifier_apply(modifier=dm.name)
low.data.calc_loop_triangles()
print("LOW_TRIS", len(low.data.loop_triangles))
# Fresh UVs for the low-poly.
while low.data.uv_layers:
    low.data.uv_layers.remove(low.data.uv_layers[0])
low.data.uv_layers.new(name="UVMap")
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=0.003, area_weight=0.0, scale_to_bounds=False)
bpy.ops.uv.pack_islands(rotate=True, margin=0.003)  # fill the whole texture
bpy.ops.object.mode_set(mode='OBJECT')
# A new material and image for the bake target.
img = bpy.data.images.new("cross_bake", tex * 2, tex * 2, alpha=False)
m = bpy.data.materials.new("CROSS"); m.use_nodes = True
nt = m.node_tree
bsdf = [n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED'][0]
tn = nt.nodes.new('ShaderNodeTexImage'); tn.image = img
nt.links.new(tn.outputs['Color'], bsdf.inputs['Base Color'])
nt.nodes.active = tn
low.data.materials.clear(); low.data.materials.append(m)
# Bake the working copy's colour onto it.
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = 4
scene.render.bake.use_selected_to_active = True
scene.render.bake.cage_extrusion = 0.03
scene.render.bake.max_ray_distance = 0.12
scene.render.bake.margin = 4
scene.render.bake.use_pass_direct = False
scene.render.bake.use_pass_indirect = False
scene.render.bake.use_pass_color = True
# Bake the base colour only: with metallic at 0 the diffuse colour pass is exactly the base colour.
for m_src in src.data.materials:
    for n in m_src.node_tree.nodes:
        if n.type == 'BSDF_PRINCIPLED':
            for l in list(n.inputs['Metallic'].links):
                m_src.node_tree.links.remove(l)
            n.inputs['Metallic'].default_value = 0.0
src.select_set(True); low.select_set(True); bpy.context.view_layer.objects.active = low
bpy.ops.object.bake(type='DIFFUSE', pass_filter={'COLOR'})
img.scale(tex, tex)  # baked at twice the size, scaled down: cleaner edges
img.filepath_raw = os.path.join(work, f"cross_{target}_{tex}.png"); img.file_format = 'PNG'; img.save()
img.pack()  # kept inside the .blend, so the later stages don't depend on this machine's paths
print("BAKED", img.filepath_raw)
bpy.data.objects.remove(src)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(work, f"cross_low_{target}.blend"))
h = max((low.matrix_world @ v.co).z for v in low.data.vertices)
scene.render.engine = 'BLENDER_WORKBENCH'
render_util.render(f"{out}/low{target}", mathutils.Vector((0, 0, h / 2)), h * 1.06)
render_util.render(f"{out}/low{target}_head", mathutils.Vector((0, 0, h - 0.14)), 0.4, angles=(("front", 0), ("left", 90), ("back", 180)), resx=400, resy=400)
print("DONE")
