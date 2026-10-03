class_name Frontend
extends CanvasLayer
## Every menu screen, in the game's espionage style (UiKit): the main menu (over the slowly
## swaying opening camera), SETTINGS, CONTROLS, the pause menu, and the end screens. It keeps
## working while the game is paused. The level listens to its signals.

signal start_requested
signal resume_requested
signal retry_requested
signal menu_requested
## Any button pressed (the level plays a blip for it).
signal clicked
## The end screen's tally: a count step (a tick), a row landing (a thunk).
signal tally_ticked
signal tally_landed

enum Screen { NONE, MAIN, SETTINGS, CONTROLS, PAUSE, END }

const AIM_NAMES := {"auto": "AUTO", "auto_tap": "AUTO + TAP", "tap": "TAP ONLY"}
const SWIPE_NAMES := {"low": "LOW", "medium": "MEDIUM", "high": "HIGH"}
const END_TITLES := {
	&"extracted": ["MISSION COMPLETE", "EXTRACTED BY CHOPPER", UiKit.GREEN],
	&"killed": ["KILLED IN ACTION", "AGENT DOWN", UiKit.RED],
	&"captured": ["CAPTURED", "TAKEN BY THE ENEMY", UiKit.AMBER],
	&"chopper_left": ["MISSION FAILED", "THE CHOPPER LEFT", UiKit.RED],
	&"dead_end": ["MISSION FAILED", "NO WAY THROUGH", UiKit.RED],
}

var mission_title := "MISSION 1"
var _screen := Screen.NONE
## Where SETTINGS / CONTROLS go back to.
var _back_to := Screen.MAIN
var _root: Control
var _dim: ColorRect


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_dim = ColorRect.new()
	_dim.color = Color(0.0, 0.02, 0.03, 0.55)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP  # nothing reaches the game under a menu
	add_child(_dim)
	_root = Control.new()
	_root.theme = UiKit.theme()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_show(Screen.NONE)


func is_open() -> bool:
	return _screen != Screen.NONE


func show_main() -> void:
	_show(Screen.MAIN)


func show_pause() -> void:
	_show(Screen.PAUSE)


func hide_all() -> void:
	_show(Screen.NONE)


## The run's over. stats: the tally's numbers (Tally.rows_for), and for the route map graph,
## visited, discovered, end_into (how far into the last area it ended) and end_ramp (the stairs
## at its start).
func show_end(reason: StringName, stats: Dictionary) -> void:
	_end_reason = reason
	_end_stats = stats
	_show(Screen.END)


var _end_reason: StringName = &"extracted"
var _end_stats: Dictionary = {}


func _show(s: Screen) -> void:
	_screen = s
	for c in _root.get_children():
		c.queue_free()
	_dim.visible = s != Screen.NONE
	_dim.color = Color(0.0, 0.02, 0.03, 0.35 if s == Screen.MAIN else 0.7)
	match s:
		Screen.MAIN:
			_build_main()
		Screen.SETTINGS:
			_build_settings()
		Screen.CONTROLS:
			_build_controls()
		Screen.PAUSE:
			_build_pause()
		Screen.END:
			_build_end()


# --- Screens --------------------------------------------------------------------------

func _build_main() -> void:
	_back_to = Screen.MAIN
	_root.add_child(Reticle.new())
	var tag := UiKit.label("// CLASSIFIED: EYES ONLY", 8, UiKit.RED, HORIZONTAL_ALIGNMENT_CENTER)
	_place_wide(tag, 70)
	_place_wide(UiKit.label("GET TO THE", 16, UiKit.PAPER, HORIZONTAL_ALIGNMENT_CENTER), 92)
	_place_wide(UiKit.label("CHOPPER!", 24, UiKit.TEAL, HORIZONTAL_ALIGNMENT_CENTER), 116)
	_place_wide(UiKit.label(mission_title.replace("\n", ": "), 8, UiKit.DIM, HORIZONTAL_ALIGNMENT_CENTER), 150)
	var first := _button("START MISSION", 290, func() -> void: start_requested.emit())
	_button("SETTINGS", 318, func() -> void: _open(Screen.SETTINGS))
	_button("CONTROLS", 346, func() -> void: _open(Screen.CONTROLS))
	_place_wide(UiKit.label("PROOF OF CONCEPT BUILD", 8, Color(UiKit.DIM, 0.7), HORIZONTAL_ALIGNMENT_CENTER), 446)
	_place_wide(UiKit.label(build_label(), 8, Color(UiKit.DIM, 0.55), HORIZONTAL_ALIGNMENT_CENTER), 458)
	first.grab_focus()


## Which build this is: the commit the live site was built from and when (UTC), written by the
## CI into game/build_info.json, so you can tell a fresh version from a cached old one. "DEV"
## when run from the editor.
static func build_label() -> String:
	var path := "res://game/build_info.json"
	if not FileAccess.file_exists(path):
		return "BUILD DEV"
	var info = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not info is Dictionary:
		return "BUILD DEV"
	return ("BUILD %s - %s" % [info.get("commit", "?"), info.get("built", "")]).strip_edges().to_upper()

func _build_pause() -> void:
	_back_to = Screen.PAUSE
	_header("PAUSED", "MISSION ON HOLD")
	var first := _button("RESUME", 170, func() -> void: resume_requested.emit())
	_button("SETTINGS", 198, func() -> void: _open(Screen.SETTINGS))
	_button("CONTROLS", 226, func() -> void: _open(Screen.CONTROLS))
	_button("QUIT TO MENU", 268, func() -> void: menu_requested.emit())
	first.grab_focus()


func _build_controls() -> void:
	_header("CONTROLS", "FIELD MANUAL")
	var lines := [
		["SWIPE < >", "DODGE A LANE"],
		["SWIPE UP", "JUMP"],
		["SWIPE DOWN", "SLIDE"],
		["HOLD FIRE", "SHOOT (AUTO-AIM)"],
		["TAP ENEMY", "TARGET IT"],
		["RUN INTO COVER", "HIDE BEHIND IT"],
		["  SWIPE < >", "LEAVE COVER"],
		["OUTER LANES", "TAKE SIDE EXITS"],
		["TRIPWIRES", "RAISE THE ALERT"],
		["ALARM BOXES", "SHOOT: ALERT DOWN"],
		["DOGS", "DODGE OR SHOOT"],
		["THE CHOPPER", "REACH IT IN TIME"],
	]
	var y := 104.0
	for row in lines:
		var a := UiKit.label(row[0], 8, UiKit.TEAL)
		a.position = Vector2(26, y)
		_root.add_child(a)
		var b := UiKit.label(row[1], 8, UiKit.PAPER)
		b.position = Vector2(132, y)
		_root.add_child(b)
		y += 18.0
	_button("BACK", 430, func() -> void: _open(_back_to)).grab_focus()


func _build_settings() -> void:
	_header("SETTINGS", "AGENT PREFERENCES")
	var y := 90.0
	y = _section("AUDIO", y)
	y = _toggle_row("SOUND", "sound_on", y)
	y = _slider_row("MASTER", "master_volume", y)
	y = _slider_row("MUSIC", "music_volume", y)
	y = _slider_row("EFFECTS", "effects_volume", y)
	y = _slider_row("AMBIENCE", "ambience_volume", y)
	y = _section("DISPLAY", y + 4)
	y = _slider_row("BRIGHTNESS", "brightness", y, 50, 150)
	y = _toggle_row("SCREEN SHAKE", "screen_shake", y)
	y = _toggle_row("RETRO FILTER", "retro_filter", y)
	y = _section("CONTROLS", y + 4)
	y = _choice_row("AIM", "aim", AIM_NAMES, y)
	y = _choice_row("FIRE BUTTON", "fire_side", {"right": "RIGHT", "left": "LEFT"}, y)
	y = _choice_row("SWIPE", "swipe", SWIPE_NAMES, y)
	# RESET and BACK side by side, under the rows.
	var reset := _button("RESET", y + 10, func() -> void:
		Settings.reset()
		_show(Screen.SETTINGS))
	reset.offset_left = -112
	reset.offset_right = -8
	var back := _button("BACK", y + 10, func() -> void: _open(_back_to))
	back.offset_left = 8
	back.offset_right = 112
	back.grab_focus()


func _build_end() -> void:
	var info: Array = END_TITLES.get(_end_reason, ["MISSION FAILED", String(_end_reason).to_upper(), UiKit.RED])
	var col: Color = info[2]
	_root.add_child(Stamp.new(col))
	_place_wide(UiKit.label(info[0], 16, col, HORIZONTAL_ALIGNMENT_CENTER), 80)
	_place_wide(UiKit.label(info[1], 8, UiKit.PAPER, HORIZONTAL_ALIGNMENT_CENTER), 104)
	# The debrief (the LOCKED post-run route record): the route map, then the tally under it.
	var w := _root.get_viewport_rect().size.x
	var panel := DebriefPanel.new()
	panel.rect = Rect2(14, 132, w - 28, 236)
	_root.add_child(panel)
	var x := panel.rect.position.x + 10.0
	var inner := panel.rect.size.x - 20.0
	var map: RouteMap = null
	var graph = _end_stats.get("graph")
	if graph is RouteGraph:
		map = RouteMap.new()
		map.graph = graph
		var run: Array[StringName] = []
		for id in _end_stats.get("visited", []):
			run.append(StringName(id))
		map.visited = run
		map.discovered = _end_stats.get("discovered", {})
		map.end_reason = _end_reason
		map.end_into = float(_end_stats.get("end_into", 0.0))
		map.end_ramp = float(_end_stats.get("end_ramp", 0.0))
		map.position = Vector2(x, 156)
		map.size = Vector2(inner, 52)
		_root.add_child(map)
		if not run.is_empty():
			var where := UiKit.label("▶ " + graph.display_name(run[-1]), 8, col)
			where.position = Vector2(x, 213)
			_root.add_child(where)
	var tally := Tally.new()
	tally.rows = Tally.rows_for(_end_stats)
	tally.delay = RouteMap.DRAW_TIME + 0.3 if map != null else 0.3
	tally.position = Vector2(x, 236)
	tally.size = Vector2(inner, Tally.ROW_H * tally.rows.size())
	tally.ticked.connect(func() -> void: tally_ticked.emit())
	tally.landed.connect(func() -> void: tally_landed.emit())
	_root.add_child(tally)
	# A tap anywhere but the buttons shows it all at once.
	var skip := SkipArea.new()
	skip.pressed.connect(func() -> void:
		if map != null:
			map.finish()
		tally.skip())
	_root.add_child(skip)
	var first := _button("RETRY", 380, func() -> void: retry_requested.emit())
	_button("MAIN MENU", 408, func() -> void: menu_requested.emit())
	first.grab_focus()


# --- Building blocks ------------------------------------------------------------------

func _open(s: Screen) -> void:
	if s in [Screen.MAIN, Screen.PAUSE]:
		_back_to = s
	_show(s)


func _header(title: String, sub: String) -> void:
	var bar := HeaderBar.new()
	_root.add_child(bar)
	_place_wide(UiKit.label(title, 16, UiKit.TEAL, HORIZONTAL_ALIGNMENT_CENTER), 44)
	_place_wide(UiKit.label("// " + sub, 8, UiKit.DIM, HORIZONTAL_ALIGNMENT_CENTER), 66)


func _place_wide(c: Control, y: float) -> void:
	c.set_anchors_preset(Control.PRESET_TOP_WIDE)
	c.offset_top = y
	_root.add_child(c)


func _button(text: String, y: float, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.set_anchors_preset(Control.PRESET_CENTER_TOP)
	b.offset_left = -78
	b.offset_right = 78
	b.offset_top = y
	b.offset_bottom = y + 20
	b.pressed.connect(func() -> void:
		clicked.emit()
		action.call())
	_root.add_child(b)
	return b


func _section(title: String, y: float) -> float:
	var l := UiKit.label(title, 8, UiKit.RED)
	l.position = Vector2(20, y)
	_root.add_child(l)
	var line := ColorRect.new()
	line.color = Color(UiKit.RED, 0.5)
	line.position = Vector2(20 + title.length() * 6 + 4, y + 4)
	line.size = Vector2(230 - title.length() * 6 - 4, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(line)
	return y + 17.0


func _row_label(text: String, y: float) -> void:
	var l := UiKit.label(text, 8, UiKit.PAPER)
	l.position = Vector2(26, y + 3)
	_root.add_child(l)


func _toggle_row(text: String, key: String, y: float) -> float:
	_row_label(text, y)
	var b := Button.new()
	var on: bool = Settings.get_value(key)
	b.text = "ON" if on else "OFF"
	b.theme_type_variation = "CompactButton"
	_root.add_child(b)  # in the menu first, so its theme (and small size) applies
	b.position = Vector2(192, y - 1)  # level with the label
	b.size = Vector2(48, 15)
	b.pressed.connect(func() -> void:
		clicked.emit()
		Settings.set_value(key, not bool(Settings.get_value(key)))
		b.text = "ON" if Settings.get_value(key) else "OFF")
	return y + 22.0


func _slider_row(text: String, key: String, y: float, lo: float = 0, hi: float = 100) -> float:
	_row_label(text, y)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 5
	s.value = float(Settings.get_value(key))
	s.position = Vector2(140, y + 2)
	s.size = Vector2(80, 10)
	_root.add_child(s)
	var v := UiKit.label(str(int(s.value)), 8, UiKit.TEAL)
	v.position = Vector2(226, y + 3)
	_root.add_child(v)
	s.value_changed.connect(func(val: float) -> void:
		v.text = str(int(val))
		Settings.set_value(key, int(val)))
	return y + 22.0


func _choice_row(text: String, key: String, names: Dictionary, y: float) -> float:
	_row_label(text, y)
	var b := Button.new()
	b.text = "< %s >" % names.get(Settings.get_value(key), "?")
	b.theme_type_variation = "CompactButton"
	_root.add_child(b)
	b.position = Vector2(146, y - 1)
	b.size = Vector2(94, 15)
	b.pressed.connect(func() -> void:
		clicked.emit()
		var keys := names.keys()
		var i := (keys.find(Settings.get_value(key)) + 1) % keys.size()
		Settings.set_value(key, keys[i])
		b.text = "< %s >" % names[keys[i]])
	return y + 22.0


## The main menu's backdrop: a gun-barrel reticle (a GoldenEye nod) behind the title.
class Reticle extends Control:
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)  # added already: size it now

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var c := Vector2(get_viewport_rect().size.x / 2.0, 122)
		for i in 4:
			draw_arc(c, 34.0 + i * 16.0, 0, TAU, 40, Color(UiKit.TEAL, 0.18 - i * 0.03), 1.0)
		var a := _t * 0.4
		for k in 4:
			var d := Vector2(cos(a + k * PI / 2.0), sin(a + k * PI / 2.0))
			draw_line(c + d * 26.0, c + d * 98.0, Color(UiKit.TEAL, 0.12), 1.0)
		draw_rect(Rect2(0, 62, get_viewport_rect().size.x, 1), Color(UiKit.RED, 0.4))
		draw_rect(Rect2(0, 166, get_viewport_rect().size.x, 1), Color(UiKit.RED, 0.4))


## A dossier header strip across the top of a menu screen.
class HeaderBar extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)  # added already: size it now

	func _draw() -> void:
		var w := get_viewport_rect().size.x
		UiKit.panel(self, Rect2(12, 34, w - 24, 46), UiKit.TEAL, UiKit.PANEL_SOLID, 8.0)


## The end screen's stamp: a big angled frame in the result's colour.
class Stamp extends Control:
	var col: Color

	func _init(c: Color) -> void:
		col = c

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)  # added already: size it now

	func _draw() -> void:
		var w := get_viewport_rect().size.x
		UiKit.panel(self, Rect2(14, 70, w - 28, 50), col, UiKit.PANEL_SOLID, 10.0)


## The debrief's codec panel: its header, and a rule between the route map and the tally (which
## are their own controls, laid over it: RouteMap and Tally).
class DebriefPanel extends Control:
	var rect := Rect2()

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)  # added already: size it now

	func _draw() -> void:
		UiKit.panel(self, rect, UiKit.TEAL, UiKit.PANEL_SOLID, 8.0)
		var x := rect.position.x + 10.0
		draw_string(UiKit.font(), Vector2(x, rect.position.y + 16), "DEBRIEF", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, UiKit.RED)
		draw_rect(Rect2(x, rect.position.y + 96, rect.size.x - 20.0, 1), Color(UiKit.TEAL_DIM, 0.8))


## The end screen behind its buttons: a tap on it skips the route map and tally to the end.
class SkipArea extends Control:
	signal pressed

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)  # added already: size it now

	func _gui_input(event: InputEvent) -> void:
		if (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed):
			pressed.emit()
			accept_event()
