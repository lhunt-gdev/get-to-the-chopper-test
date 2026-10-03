import bpy, sys
argv = sys.argv[sys.argv.index("--") + 1:]
bpy.ops.wm.open_mainfile(filepath=argv[0])
for o in bpy.data.objects:
    print("OBJ", o.name, o.type, tuple(round(x, 3) for x in o.rotation_euler), o.parent.name if o.parent else None, [m.type for m in getattr(o, "modifiers", [])])
