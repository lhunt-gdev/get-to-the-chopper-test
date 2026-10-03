import bpy, sys, math, mathutils
argv = sys.argv[sys.argv.index("--") + 1:]
path, out = argv[0], argv[1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=path)
objs = [o for o in bpy.data.objects if o.type == 'MESH']
mn = mathutils.Vector((1e9,)*3); mx = mathutils.Vector((-1e9,)*3)
for o in objs:
    for c in o.bound_box:
        v = o.matrix_world @ mathutils.Vector(c)
        mn = mathutils.Vector(map(min, mn, v)); mx = mathutils.Vector(map(max, mx, v))
centre = (mn + mx) / 2; h = mx.z - mn.z
scene = bpy.context.scene
scene.render.engine = 'BLENDER_WORKBENCH'
scene.display.shading.light = 'FLAT'
scene.display.shading.color_type = 'TEXTURE'
scene.render.resolution_x = 512; scene.render.resolution_y = 768
scene.render.film_transparent = False
scene.world = bpy.data.worlds.new("w"); scene.world.color = (0.8, 0.8, 0.8)
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); scene.collection.objects.link(cam); scene.camera = cam
cam.data.type = 'ORTHO'; cam.data.ortho_scale = h * 1.08
for name, ang in [("front", 0), ("left", 90), ("back", 180), ("right", 270)]:
    a = math.radians(ang)
    # glTF forward is -Y in Blender after import? Look from -Y (front) by default.
    cam.location = centre + mathutils.Vector((math.sin(a) * 5, -math.cos(a) * 5, 0))
    cam.rotation_euler = (math.radians(90), 0, a)
    scene.render.filepath = f"{out}_{name}.png"
    bpy.ops.render.render(write_still=True)
print("DONE", h)
