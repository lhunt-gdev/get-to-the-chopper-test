extends SceneTree
## Pictures of the screens with words on them, in one language, to look at for fit (the decision log's
## "Languages: Luxembourgish first"): the main menu (and with the iPhone's save tip), SETTINGS (its
## LANGUAGE row), CONTROLS (swipes and the move buttons, each AIM), the mission select, mission 1's
## screen, the debrief for each ending, the scoreboard, the name entry, every line of the briefing and
## of each end conversation, CREDITS, LICENCES, the end-of-demo screen, the pause menu, every
## first-time tip (swipes and buttons; FIRE's by AIM) and the HUD in cover and facing the boss. Run with a window
## (the pictures need the renderer; not --headless):
##   godot --path . -s res://tests/l10n/render_screens.gd -- --out=C:/somewhere --locale=xx
## --locale: en, lb, or xx (the pseudo-language: every string about 35% longer, in accented capitals,
## L10n.pseudo); --size=270x480 (or 270x585, a taller phone); --scale=3 (each pixel 3 across, to look at
## closely). The player's own settings and saves are never touched (Progress keeps to memory; Settings
## isn't saved).

var _out := "user://l10n_screens"
var _locale := L10n.PSEUDO
var _size := Vector2i(270, 480)
var _scale := 1


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.get_slice("=", 1)
		elif a.begins_with("--locale="):
			_locale = a.get_slice("=", 1)
		elif a.begins_with("--scale="):
			_scale = maxi(1, int(a.get_slice("=", 1)))
		elif a.begins_with("--size="):
			_size = Vector2i(int(a.get_slice("=", 1).get_slice("x", 0)), int(a.get_slice("=", 1).get_slice("x", 1)))
	_run()


func _run() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(_out)
	root.size = Vector2i(roundi(_size.x * 1.5), roundi(_size.y * 1.5))
	var progress: Node = root.get_node("Progress")
	progress.save_path = ""  # (in memory only)
	progress.reset()
	progress.mark_ios_tip()
	if _locale == L10n.PSEUDO:
		L10n.use_pseudo()
	else:
		TranslationServer.set_locale(_locale)
	var back := ColorRect.new()  # (the level's scene behind the menus: a dark stand-in)
	back.color = Color("10181a")
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	var under := CanvasLayer.new()
	under.layer = -1
	under.add_child(back)
	root.add_child(under)
	var FE: GDScript = load("res://game/ui/menu/frontend.gd")  # (by path: it needs the autoloads)
	var fe = FE.new()
	root.add_child(fe)
	var mission_1 = JSON.parse_string(FileAccess.get_file_as_string("res://game/levels/prototype_slice/route.json"))
	fe.mission = mission_1
	var brief := Briefing.load_file("res://game/levels/prototype_slice/briefing.json")
	var graph := RouteGraph.from_json_file("res://game/levels/prototype_slice/route.json")
	var run: Array[StringName] = [&"main_floor_lobby", &"building_main_floor", &"security_wing", &"staff_canteen", &"main_floor_exit", &"helipad"]
	var debrief := {"time": 79.2, "spare": 24.6, "distance": 820, "downed": 6, "hits": 1, "run_into": 1, "alarms_set_off": 1, "alarms_stopped": 1,
			"top_alert": 2, "levels": "MAIN", "new_areas": 2, "mission": 1, "setting": "medium", "unlocked": [[1, "hard"], [2, "easy"], [2, "medium"]],
			"new_best": true, "was_best": 90.0, "rank": 4, "seq": 0, "new_best_score": true, "graph": graph, "visited": run, "discovered": {}}
	var settings: Node = root.get_node("Settings")
	var saved: Dictionary = settings._values.duplicate()  # (set straight in: never saved)
	await _shot("main", func() -> void: fe.show_main())
	FE.force_ios_tip = true
	progress.ios_tip_seen = false
	await _shot("main_ios_tip", func() -> void: fe.show_main())
	FE.force_ios_tip = false
	await _shot("settings", func() -> void: fe._open(FE.Screen.SETTINGS))
	await _shot("controls", func() -> void: fe._open(FE.Screen.CONTROLS))
	for aim in ["auto_tap", "tap"]:
		settings._values["aim"] = aim
		await _shot("controls_aim_" + aim, func() -> void: fe._open(FE.Screen.CONTROLS))
	settings._values["controls"] = "buttons"
	for aim in ["auto", "tap"]:
		settings._values["aim"] = aim
		await _shot("controls_buttons_aim_" + aim, func() -> void: fe._open(FE.Screen.CONTROLS))
	settings._values = saved.duplicate()
	await _shot("missions", func() -> void: fe._open(FE.Screen.MISSIONS))
	await _shot("mission", func() -> void: fe.open_mission(1))
	for ending: String in Progress.ENDINGS:
		var stats := debrief.duplicate()
		if ending != "extracted":
			stats.erase("spare")
			stats["new_best"] = false
			stats["unlocked"] = []
		await _shot("debrief_" + ending, func() -> void: fe.show_end(StringName(ending), stats), 2.0, func() -> void: _finish_debrief(fe))
	await _shot("board", func() -> void: fe.open_board(1, "medium"))
	await _shot("name", func() -> void:
		fe.show_end(&"extracted", debrief)
		fe._open_name())
	await _shot("credits", func() -> void: fe._open(FE.Screen.CREDITS))
	await _shot("licences", func() -> void: fe._open(FE.Screen.LICENCES))
	await _shot("demo_end", func() -> void: fe.open_demo_end())
	await _shot("pause", func() -> void: fe.show_pause())
	# Every line of the briefing and of each ending's conversation.
	var talk := Briefing.conversation(brief)
	for i in Briefing.lines_of(talk).size():
		await _shot("briefing_%d" % (i + 1), func() -> void: fe.show_briefing(Briefing.conversation(brief)), 3.0, func() -> void: _tap_lines(fe, i + 1))
	for ending: String in Briefing.ENDINGS:
		talk = Briefing.conversation(brief, ending)
		if talk.is_empty():
			continue
		for i in Briefing.lines_of(talk).size():
			await _shot("end_%s_%d" % [ending, i + 1], func() -> void: fe.show_end(StringName(ending), {"mission": 1, "setting": "hard"}, Briefing.conversation(brief, ending)),
					3.0, func() -> void: _tap_lines(fe, i + 1))
	fe.hide_all()
	# The HUD: every tip's card (swipes, then the move buttons; FIRE's by AIM), the cover hint and the
	# boss stand-off with the alert box up.
	var hud = load("res://game/ui/hud/hud.gd").new()  # (by path: it needs the autoloads)
	root.add_child(hud)
	var tuning := Tuning.new()
	hud.setup(tuning)
	hud.set_playing(true)
	root.get_node("GameState").alert_changed.emit(2)
	hud.show_chopper_message(L10n.t("HUD_CHOPPER_LANDED"), Color("9fd36b"), 99.0, false)
	hud.show_area(FE.area_name(graph, &"building_main_floor"))
	for buttons in [false, true]:
		tuning.move_buttons = buttons
		var mode := "buttons" if buttons else "swipe"
		for id: String in FirstTips.ORDER:
			await _shot("tip_%s_%s" % [mode, id], func() -> void: hud.show_tip(id), 1.0)
		for aim in ["auto_tap", "tap"]:
			settings._values["aim"] = aim
			await _shot("tip_%s_fire_%s" % [mode, aim], func() -> void: hud.show_tip("fire"), 1.0)
		settings._values = saved.duplicate()
		await _shot("hud_" + mode, func() -> void:
			hud.show_tip("")
			hud.show_cover_hint(true)
			hud.show_boss(0.6), 1.5)
		await _shot("hud_standoff_" + mode, func() -> void: hud.show_cover_hint(false, true), 1.0)
	settings._values = saved
	quit()


## Shows a screen (`open`), lets it settle (`wait` s; `then` once it's up), and saves its picture.
func _shot(name: String, open: Callable, wait: float = 0.6, then: Callable = Callable()) -> void:
	open.call()
	await create_timer(0.2, true, false, true).timeout
	if then.is_valid():
		await then.call()
	await create_timer(wait, true, false, true).timeout
	await process_frame
	var img := root.get_texture().get_image()
	if _scale > 1:
		img.resize(img.get_width() * _scale, img.get_height() * _scale, Image.INTERPOLATE_NEAREST)
	var path := _out.path_join("%s_%s.png" % [_locale, name])
	img.save_png(path)
	print("saved ", ProjectSettings.globalize_path(path) if path.begins_with("user://") else path)


## The debrief all shown (a tap's worth).
func _finish_debrief(fe: Node) -> void:
	for c in fe.find_children("*", "", true, false):
		if c is Typer:
			(c as Typer).finish()
		elif c is Tally:
			(c as Tally).skip()
		elif c is RouteMap:
			(c as RouteMap).finish()
	await process_frame


## The conversation on its `n`th line, typed out (a tap's worth on each).
func _tap_lines(fe: Node, n: int) -> void:
	var b: Briefing = null
	for c in fe.find_children("*", "", true, false):
		if c is Briefing:
			b = c
	if b == null:
		return
	while not b.is_talking():
		await process_frame
	for i in n:
		b.tap()  # (the line all there)
		await process_frame
		if i < n - 1:
			b.tap()  # (the next)
			await process_frame
