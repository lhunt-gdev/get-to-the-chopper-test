extends SceneTree
## UNLOCKS' carousel tiles: a small portrait of each skin (Skins.LIST), head and shoulders in his ready
## stance, lit as the menu lights him, on a clear background, into assets/ui/skins/<id>.png.
##   godot --path <project> -s art_source/operative/tools/skin_portraits.gd [-- <only this id>]

const SIZE := 48


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	RenderingServer.global_shader_parameter_set("amb_color", Vector4(0.62, 0.62, 0.62, 1))
	RenderingServer.global_shader_parameter_set("moon_color", Vector4(0.6, 0.58, 0.55, 1))
	RenderingServer.global_shader_parameter_set("moon_dir", Vector4(-0.45, 0.55, -0.7, 0))
	var only := OS.get_cmdline_user_args()
	for id in Skins.ids():
		if not only.is_empty() and not only.has(id):
			continue
		var vp := SubViewport.new()
		vp.size = Vector2i(SIZE * 4, SIZE * 4)
		vp.transparent_bg = true
		vp.own_world_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(vp)
		var env := WorldEnvironment.new()
		var e := Environment.new()
		e.background_mode = Environment.BG_CLEAR_COLOR
		env.environment = e
		vp.add_child(env)
		var r := Skins.make_rig(id)
		vp.add_child(r)
		for i in 90:
			r.animate(1.0 / 60.0, {"ready": true})
		var head := r._in_rig(r.head).origin * r.scale.x
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = 0.72
		vp.add_child(cam)
		var look := Vector3(0.0, head.y - 0.06, 0.0)
		cam.look_at_from_position(look + Vector3(0.55, 0.12, -1.6), look)
		cam.current = true
		for i in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		var im := vp.get_texture().get_image()
		im.convert(Image.FORMAT_RGBA8)
		im.resize(SIZE, SIZE, Image.INTERPOLATE_NEAREST)
		im.save_png("res://assets/ui/skins/%s.png" % id)
		print("PORTRAIT ", id)
		vp.queue_free()
		await process_frame
	quit()
