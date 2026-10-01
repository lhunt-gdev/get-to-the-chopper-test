class_name Frontend
extends CanvasLayer
## Every menu screen, in the game's espionage style (UiKit): the main menu (over the slowly
## swaying opening camera), SETTINGS, CONTROLS, the pause menu, and the end screens. It keeps
## working while the game is paused. The level listens to its signals.

## ENTER GAME on the title screen: the first tap, so audio can start (browsers block it until then).
signal title_done
signal start_requested
signal resume_requested
signal retry_requested
signal menu_requested
## Any button pressed (the level plays a blip for it).
signal clicked

enum Screen { NONE, TITLE, MAIN, SETTINGS, CONTROLS, PAUSE, END }

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


func show_title() -> void:
	_show(Screen.TITLE)


func show_main() -> void:
	_show(Screen.MAIN)


func show_pause() -> void:
	_show(Screen.PAUSE)


func hide_all() -> void:
	_show(Screen.NONE)


## The run's over. stats: {time, hits, downed, alert, route: PackedStringArray}.
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
	if s == Screen.TITLE:
		_dim.color.a = 0.0  # the camouflage does the darkening (and still blocks input)
	match s:
		Screen.TITLE:
			_build_title()
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

## The title screen: near-black camouflage, the title, ENTER GAME. Your tap on it is the first
## input, which lets the browser start the sound.
func _build_title() -> void:
	_root.add_child(CamoBackdrop.new())
	_place_wide(UiKit.label("GET TO THE", 16, UiKit.PAPER, HORIZONTAL_ALIGNMENT_CENTER), 168)
	_place_wide(UiKit.label("CHOPPER!", 24, UiKit.TEAL, HORIZONTAL_ALIGNMENT_CENTER), 192)
	var start := _button("ENTER GAME", 320, func() -> void: title_done.emit())
	start.grab_focus()

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
	_place_wide(UiKit.label("PROOF OF CONCEPT BUILD", 8, Color(UiKit.DIM, 0.7), HORIZONTAL_ALIGNMENT_CENTER), 452)
	first.grab_focus()


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
	var report := ReportPanel.new()
	report.stats = _end_stats
	report.accent = col
	_root.add_child(report)
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
		set_anchors_preset(Control.PRESET_FULL_RECT)

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
		set_anchors_preset(Control.PRESET_FULL_RECT)

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
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		var w := get_viewport_rect().size.x
		UiKit.panel(self, Rect2(14, 70, w - 28, 50), col, UiKit.PANEL_SOLID, 10.0)


## The debrief: time, hits taken, enemies down, alert, and the route taken (the LOCKED post-run
## route record), in a codec panel.
class ReportPanel extends Control:
	var stats: Dictionary
	var accent := UiKit.TEAL

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		var w := get_viewport_rect().size.x
		var r := Rect2(14, 132, w - 28, 236)
		UiKit.panel(self, r, UiKit.TEAL, UiKit.PANEL_SOLID, 8.0)
		var f := UiKit.font()
		var x := r.position.x + 12
		var y := r.position.y + 18
		draw_string(f, Vector2(x, y), "DEBRIEF", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, UiKit.RED)
		y += 18
		var t: float = stats.get("time", 0.0)
		var rows := [["TIME", "%d:%04.1f" % [int(t) / 60, fmod(t, 60.0)]], ["HITS TAKEN", str(stats.get("hits", 0))],
				["ENEMIES DOWN", str(stats.get("downed", 0))], ["ALERT", "%d" % stats.get("alert", 1)]]
		for row in rows:
			draw_string(f, Vector2(x, y), row[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, UiKit.DIM)
			draw_string(f, Vector2(x + 120, y), row[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, UiKit.PAPER)
			y += 14
		y += 8
		draw_string(f, Vector2(x, y), "ROUTE", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, UiKit.RED)
		y += 16
		var route: PackedStringArray = stats.get("route", PackedStringArray())
		for i in route.size():
			var last := i == route.size() - 1
			draw_string(f, Vector2(x, y), ("▶ " if last else "  ") + route[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 8,
					accent if last else UiKit.PAPER)
			y += 13


## The title screen's backdrop: #080808 (65% opaque) with a random woodland-camouflage pattern in very dark
## olive, brown and green, dithered (4x4 Bayer) in 2x2-pixel blocks like the PS1. New each load.
class CamoBackdrop extends TextureRect:
	## Slightly see-through, so the game shows faintly behind it (user).
	const OPACITY := 0.65
	const TONES: Array[Color] = [Color("080808"), Color("10130d"), Color("15120d"), Color("181d14")]
	const BAYER := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		position = Vector2.ZERO
		size = get_viewport_rect().size  # the whole screen (the menu root has no size of its own)
		stretch_mode = TextureRect.STRETCH_SCALE
		expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		self_modulate.a = OPACITY
		texture = ImageTexture.create_from_image(camo(135, 240, randi()))

	## The pattern, w x h pixels. Pure (seeded), so it's testable.
	static func camo(w: int, h: int, seed_value: int) -> Image:
		var blobs := FastNoiseLite.new()
		blobs.seed = seed_value
		blobs.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		blobs.frequency = 0.022
		blobs.fractal_octaves = 2
		var img := Image.create(w, h, false, Image.FORMAT_RGB8)
		var levels := TONES.size()
		for y in h:
			for x in w:
				var n := clampf(blobs.get_noise_2d(x, y * 0.8) * 0.5 + 0.5, 0.0, 1.0)  # a little wider than tall
				var b: float = BAYER[(y % 4) * 4 + (x % 4)] / 16.0 - 0.5
				var i := clampi(int(n * levels + b * 0.45), 0, levels - 1)  # dithered only near the edges
				img.set_pixel(x, y, TONES[i])
		return img
