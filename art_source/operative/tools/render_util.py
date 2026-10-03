# Shared preview renders: flat-lit, textured, orthographic, from the front (+Y), sides and back.
import bpy, math, mathutils
def setup(resx=512, resy=768):
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_WORKBENCH'
    scene.display.shading.light = 'FLAT'
    scene.display.shading.color_type = 'TEXTURE'
    scene.display.shading.show_object_outline = False
    scene.render.resolution_x = resx; scene.render.resolution_y = resy
    if not scene.world:
        scene.world = bpy.data.worlds.new("w")
    scene.world.color = (0.75, 0.75, 0.75)
    cam = bpy.data.objects.get("preview_cam")
    if not cam:
        cam = bpy.data.objects.new("preview_cam", bpy.data.cameras.new("preview_cam"))
        scene.collection.objects.link(cam)
    scene.camera = cam
    cam.data.type = 'ORTHO'
    return scene, cam
def render(out, centre, height, angles=(("front", 0), ("left", 90), ("back", 180), ("right", 270)), resx=512, resy=768, elev=0.0):
    scene, cam = setup(resx, resy)
    cam.data.ortho_scale = height
    for name, ang in angles:
        a = math.radians(ang)
        # The model faces +Y: "front" looks at him from +Y, "left" from his left (-X), etc.
        d = mathutils.Vector((-math.sin(a), math.cos(a), math.sin(math.radians(elev))))
        cam.location = centre + d.normalized() * 6.0
        cam.rotation_euler = (d.normalized() * -1).to_track_quat('-Z', 'Y').to_euler()
        scene.render.filepath = f"{out}_{name}.png"
        bpy.ops.render.render(write_still=True)
