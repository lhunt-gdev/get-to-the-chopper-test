class_name Hud
extends CanvasLayer
## The in-run HUD, in the game's espionage style (see UiKit): a LIFE bar and alert box top left,
## the chopper clock top centre with a codec message box under it, a progress rail down the left,
## the pistol-trigger FIRE button, a pause button, and the area caption. The helicopter should
## still carry the urgency, not a big timer.

## Pause pressed (the level pauses the game and shows the pause menu).
signal pause_pressed

## Each side of a fork has a colour. The road paint, sign and this prompt all use the same ones.
const SIDE_COLORS := {"left": Color("d9a032"), "straight": Color("a8a898"), "right": Color("4f9fd0")}
const SIDE_DIRS := {"left": -1, "straight": 0, "right": 1}
## Height of the cinema bars during the opening pan (pixels at 270x480).
const LETTERBOX := 44.0
const ALERT_NAMES := {1: "SNEAKING", 2: "CAUTION", 3: "ALERT"}
const ALERT_COLORS := {1: UiKit.GREEN, 2: UiKit.AMBER, 3: UiKit.RED}

var _status: StatusPanel
var _message: MessageBox
var _rail: ProgressRail
var _junction: RichTextLabel
var _title: Label
var _hint: Label
var _flash: ColorRect
var _fire: TriggerButton
var _clock: ClockDial
var _pause: PauseButton


## An old-style analog timer, top centre. The hand sweeps clockwise from 12 as the chopper's
## window runs out; the red wedge is LIFTING OFF.
class ClockDial extends Control:
	const R := 15.0
	var tuning: Tuning
	var fraction := 0.0
	## Where LIFTING OFF starts on the dial (0-1), from the mission's chopper timeline.
	var lift_fraction := 0.8

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		if tuning == null:
			return
		var c := Vector2(get_viewport_rect().size.x / 2.0, 4.0 + R)
		draw_circle(c, R + 3.0, UiKit.INK)
		draw_arc(c, R + 2.5, 0, TAU, 32, UiKit.TEAL_DIM, 1.0)
		draw_circle(c, R, Color("d8d0b0"))
		_wedge(c, R - 1.0, lift_fraction, 1.0, Color("c8402e"))
		# Spent time greys out, so the dial also reads as "how much is left".
		_wedge(c, R - 5.0, 0.0, fraction, Color(0.25, 0.24, 0.2, 0.55))
		for i in 12:
			var a := TAU * i / 12.0 - PI / 2.0
			var d := Vector2(cos(a), sin(a))
			draw_line(c + d * (R - (4.0 if i % 3 == 0 else 2.5)), c + d * (R - 0.5), Color("2a2a26"), 1.0)
		var ha := TAU * fraction - PI / 2.0
		draw_line(c, c + Vector2(cos(ha), sin(ha)) * (R - 2.0), Color("1c1c1a"), 2.0)
		draw_circle(c, 2.0, Color("c8402e"))

	func _wedge(c: Vector2, r: float, from: float, to: float, color: Color) -> void:
		if to <= from:
			return
		var pts := PackedVector2Array([c])
		var steps := maxi(2, int((to - from) * 32.0))
		for i in steps + 1:
			var a := TAU * lerpf(from, to, float(i) / steps) - PI / 2.0
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		draw_colored_polygon(pts, color)


## Top left: LIFE (one segment per hit, red and pulsing on the last one) and, under it, the alert
## box: SNEAKING / CAUTION / ALERT, MGS-style.
class StatusPanel extends Control:
	var hp := 3
	var hp_total := 3
	var alert := 1
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		position = Vector2(4, 4)
		size = Vector2(92, 36)

	func _process(delta: float) -> void:
		_t += delta
		if hp <= 1 or alert >= 3:
			queue_redraw()

	func _draw() -> void:
		var f := UiKit.font()
		# LIFE
		UiKit.panel(self, Rect2(0, 0, 92, 16), UiKit.TEAL, UiKit.PANEL, 4.0)
		draw_string(f, Vector2(6, 11), "LIFE", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, UiKit.TEAL)
		var bar := Rect2(32, 4, 56, 8)
		draw_rect(bar, UiKit.INK)
		var seg_w := (bar.size.x - 2.0 - (hp_total - 1)) / maxf(hp_total, 1)
		for i in hp_total:
			var r := Rect2(bar.position.x + 1.0 + i * (seg_w + 1.0), bar.position.y + 1.0, seg_w, bar.size.y - 2.0)
			var col := UiKit.TEAL if hp > 1 else UiKit.RED
			if i >= hp:
				col = Color("1d3333")
			elif hp <= 1:
				col = col.lerp(UiKit.PAPER, 0.5 + 0.5 * sin(_t * 10.0))
			draw_rect(r, col)
			draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), Color(1, 1, 1, 0.25))
		# Alert box
		var ac: Color = ALERT_COLORS.get(alert, UiKit.GREEN)
		var pulse := 0.65 + 0.35 * sin(_t * 8.0) if alert >= 3 else 1.0
		UiKit.panel(self, Rect2(0, 19, 74, 16), Color(ac, pulse), Color(ac.darkened(0.8), 0.9), 4.0)
		draw_string(f, Vector2(6, 30), ALERT_NAMES.get(alert, "ALERT"), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(ac, pulse))
		draw_string(f, Vector2(62, 30), str(alert), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, UiKit.PAPER)


## Under the clock: a codec-style message box. Text types out; persistent messages blink.
class MessageBox extends Control:
	var text := ""
	var color := UiKit.PAPER
	var left := 0.0
	var blink := false
	var _shown := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func show_message(t: String, c: Color, seconds: float, persistent: bool) -> void:
		text = t
		color = c
		left = INF if persistent else seconds
		blink = persistent
		_shown = 0.0
		visible = t != ""
		queue_redraw()

	func _process(delta: float) -> void:
		if text == "":
			return
		left -= delta
		_shown += delta
		if left <= 0.0:
			text = ""
			visible = false
		queue_redraw()

	func _draw() -> void:
		if text == "":
			return
		var w := get_viewport_rect().size.x
		var bw := maxf(120.0, text.length() * 6.0 + 26.0)
		var r := Rect2((w - bw) / 2.0, 0, bw, 16)
		UiKit.panel(self, r, color, UiKit.PANEL, 4.0)
		var typed := text.substr(0, mini(text.length(), int(_shown * 40.0)))
		var on := not blink or fmod(_shown, 0.6) < 0.42
		if on:
			draw_string(UiKit.font(), Vector2(r.position.x + 12, 11), typed, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, color)


## Down the left side: the mission so far. The chopper is at the top, the start at the bottom,
## and an arrow pointing right marks where you are.
class ProgressRail extends Control:
	var fraction := 0.0
	const TOP := 116.0
	const BOTTOM := 330.0
	const X := 12.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func set_fraction(f: float) -> void:
		f = clampf(f, 0.0, 1.0)
		if absf(f - fraction) > 0.002:
			fraction = f
			queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(X - 1, TOP, 3, BOTTOM - TOP), UiKit.INK)
		draw_rect(Rect2(X, TOP, 1, BOTTOM - TOP), UiKit.TEAL_DIM)
		var y := lerpf(BOTTOM, TOP, fraction)
		draw_rect(Rect2(X, y, 1, BOTTOM - y), UiKit.TEAL)
		for i in 11:
			var ty := lerpf(BOTTOM, TOP, i / 10.0)
			draw_rect(Rect2(X + 2, ty, 3 if i % 5 == 0 else 2, 1), UiKit.TEAL_DIM)
		# The chopper at the top: a little rotor and body. The start: a square.
		draw_rect(Rect2(X - 5, TOP - 9, 11, 1), UiKit.PAPER)
		draw_rect(Rect2(X - 2, TOP - 7, 6, 4), UiKit.PAPER)
		draw_rect(Rect2(X + 4, TOP - 6, 4, 1), UiKit.PAPER)
		draw_rect(Rect2(X - 2, BOTTOM + 3, 5, 5), UiKit.DIM)
		# You: an arrow pointing right, at the rail.
		var a := PackedVector2Array([Vector2(X - 9, y - 4), Vector2(X - 2, y), Vector2(X - 9, y + 4)])
		draw_colored_polygon(a, UiKit.INK)
		var a2 := PackedVector2Array([Vector2(X - 8, y - 3), Vector2(X - 3, y), Vector2(X - 8, y + 3)])
		draw_colored_polygon(a2, UiKit.AMBER)


## The one FIRE control (LOCKED Controls v1): a gun's trigger, modelled 1:1 on the user's
## reference silhouette. The guard is a lopsided, egg-shaped loop (a heavy flat top, a bulging
## right side, the bottom rising to the left), and the red trigger blade hooks down and forward
## inside it, with a small ledge at its back. No disc or label. Held, the blade pulls back; every
## shot jolts the whole thing and flashes it. SwipeInput decides what counts as touching it; this
## draws it in the same place.
class TriggerButton extends Control:
	## The reference is 282 x 240; these outlines are in its pixels.
	const REF_SIZE := Vector2(282, 240)
	const REF_CENTRE := Vector2(141, 122)
	## The guard's outer edge and its inner edge, point for point (so it draws as a ring of quads).
	const GUARD_OUT := [Vector2(28, 22), Vector2(60, 15), Vector2(120, 13), Vector2(180, 14), Vector2(225, 18),
			Vector2(242, 28), Vector2(252, 55), Vector2(262, 95), Vector2(266, 130), Vector2(262, 170),
			Vector2(248, 200), Vector2(225, 220), Vector2(195, 228), Vector2(160, 226), Vector2(120, 214),
			Vector2(80, 200), Vector2(45, 178), Vector2(20, 148), Vector2(10, 115), Vector2(12, 75), Vector2(18, 40)]
	const GUARD_IN := [Vector2(45, 47), Vector2(70, 45), Vector2(120, 44), Vector2(180, 44), Vector2(212, 48),
			Vector2(226, 58), Vector2(234, 80), Vector2(240, 105), Vector2(240, 132), Vector2(236, 160),
			Vector2(222, 186), Vector2(203, 200), Vector2(180, 205), Vector2(150, 203), Vector2(122, 192),
			Vector2(86, 180), Vector2(58, 162), Vector2(40, 140), Vector2(32, 112), Vector2(34, 80), Vector2(38, 58)]
	## The blade: down its front (left) edge to the tip, back up its rear edge, out along the ledge.
	const BLADE := [Vector2(118, 44), Vector2(122, 60), Vector2(132, 80), Vector2(140, 100), Vector2(142, 120),
			Vector2(136, 140), Vector2(122, 158), Vector2(104, 172), Vector2(90, 182), Vector2(88, 185),
			Vector2(104, 184), Vector2(126, 177), Vector2(152, 163), Vector2(170, 145), Vector2(178, 120),
			Vector2(180, 100), Vector2(180, 82), Vector2(186, 75), Vector2(210, 72), Vector2(218, 64),
			Vector2(214, 54), Vector2(200, 50), Vector2(176, 46)]
	## Where the blade hangs from (it swings round this when pulled).
	const PIVOT := Vector2(150, 46)

	var tuning: Tuning
	var held := false
	var _pull := 0.0
	var _kick := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)
		get_viewport().size_changed.connect(queue_redraw)

	## A shot: the trigger snaps back and the whole thing jolts.
	func kick() -> void:
		_kick = 1.0

	func _process(delta: float) -> void:
		var want := 1.0 if held else 0.0
		var before := _pull + _kick
		_pull = move_toward(_pull, want, delta * 12.0)
		_kick = move_toward(_kick, 0.0, delta * 8.0)
		if absf(_pull + _kick - before) > 0.0001:
			queue_redraw()

	func _draw() -> void:
		if tuning == null:
			return
		var b := SwipeInput.fire_button(get_viewport_rect().size, tuning)
		var k := b.z * 2.1 / REF_SIZE.x  # reference pixels to screen pixels
		var c := Vector2(b.x, b.y) + Vector2(2.0, -2.5) * _kick  # the jolt of the shot
		var at := func(p: Vector2) -> Vector2: return c + (p - REF_CENTRE) * k
		# The blade first (under the guard), swung back round its pivot when pulled.
		var ang := -0.3 * clampf(_pull + _kick * 0.5, 0.0, 1.0)
		var blade := PackedVector2Array()
		for p in BLADE:
			blade.append(at.call(PIVOT + (p - PIVOT).rotated(ang)))
		# In the UI's colours (like a codec panel): a teal blade, red while held (like a pressed
		# button); each shot flashes the edges pale.
		var flash := Color(0.85, 1.0, 0.95)
		var blade_col := (UiKit.RED if held else UiKit.TEAL).lerp(flash, _kick * 0.5)
		draw_colored_polygon(blade, blade_col)
		var edge := blade.duplicate()
		edge.append(blade[0])
		draw_polyline(edge, UiKit.INK, 1.0)
		# The guard: a dark codec-panel ring (quads between its outer and inner edges) with a bright
		# teal edge and a soft glow, like the menus' panels.
		var fill := UiKit.PANEL_SOLID.lerp(UiKit.TEAL_DIM, 0.25 + 0.4 * _kick)
		# A darker edge (user): deep teal, deep red while held, still flashing pale on a shot.
		var line := (UiKit.RED.darkened(0.35) if held else UiKit.TEAL_DIM).lerp(flash, _kick)
		var outer := PackedVector2Array()
		var inner := PackedVector2Array()
		for i in GUARD_OUT.size():
			outer.append(at.call(GUARD_OUT[i]))
			inner.append(at.call(REF_CENTRE.lerp(GUARD_IN[i], 0.93)))  # a touch chunkier, like the reference
		var n := outer.size()
		for i in n:
			var j := (i + 1) % n
			draw_colored_polygon(PackedVector2Array([outer[i], outer[j], inner[j], inner[i]]), fill)
		outer.append(outer[0])
		inner.append(inner[0])
		draw_polyline(outer, UiKit.INK, 3.5)  # a dark rim round the outside
		draw_polyline(outer, line, 1.5)
		draw_polyline(inner, line, 1.0)


## Top right: pause.
class PauseButton extends Button:
	func _ready() -> void:
		theme = UiKit.theme()
		text = "II"
		focus_mode = Control.FOCUS_NONE
		set_anchors_preset(Control.PRESET_TOP_RIGHT)
		offset_left = -30
		offset_top = 4
		offset_right = -4
		offset_bottom = 22


static func side_color(side: String) -> Color:
	return SIDE_COLORS.get(side, Color.WHITE)


## -1 left, 0 straight on, 1 right.
static func side_dir(side: String) -> int:
	return SIDE_DIRS.get(side, 0)


## dir: -1 left, 0 straight on, 1 right.
static func route_prompt(label: String, dir: int) -> String:
	match dir:
		-1:
			return "< " + label
		1:
			return label + " >"
	return "^ " + label


func _ready() -> void:
	_status = StatusPanel.new()
	add_child(_status)
	_junction = RichTextLabel.new()
	add_child(_junction)
	_junction.bbcode_enabled = true
	_junction.fit_content = true
	_junction.scroll_active = false
	_junction.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_junction.add_theme_font_override("normal_font", UiKit.font())
	_junction.add_theme_font_size_override("normal_font_size", 8)
	_junction.add_theme_color_override("font_outline_color", UiKit.INK)
	_junction.add_theme_constant_override("outline_size", 3)
	_junction.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_junction.offset_left = 8
	_junction.offset_right = -8
	_junction.offset_top = 64
	_title = UiKit.label("", 16, UiKit.PAPER, HORIZONTAL_ALIGNMENT_CENTER)
	_title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_title.offset_top = 120
	add_child(_title)
	_hint = UiKit.label("", 8, UiKit.TEAL, HORIZONTAL_ALIGNMENT_CENTER)
	_hint.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_hint.offset_top = 104
	add_child(_hint)
	_flash = ColorRect.new()
	_flash.color = Color(0.85, 0.1, 0.05, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_flash)
	GameState.alert_changed.connect(_on_alert_changed)


var _cctv: ColorRect
var _cctv_mat: ShaderMaterial
var _cctv_label: Label
var _cctv_rec: Label


## Stairwell security-camera footage over the game view (off when cam is empty). The labels read
## like a CCTV monitor: camera number and timestamp top left, a blinking REC top right.
func set_cctv(on: bool, cam: String, seconds: float) -> void:
	if _cctv == null:
		_cctv_mat = ShaderMaterial.new()
		_cctv_mat.shader = preload("res://assets/shaders/psx/cctv.gdshader")
		_cctv = ColorRect.new()
		_cctv.material = _cctv_mat
		_cctv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_cctv.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(_cctv)
		move_child(_cctv, 0)  # under the rest of the HUD: only the game view looks like footage
		_cctv_label = UiKit.label("", 8, Color("d8f0d8"))
		_cctv_label.position = Vector2(8, 74)
		add_child(_cctv_label)
		_cctv_rec = UiKit.label("", 8, UiKit.RED)
		_cctv_rec.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		_cctv_rec.offset_left = -52
		_cctv_rec.offset_top = 74
		add_child(_cctv_rec)
	_cctv.visible = on
	_cctv_label.visible = on
	_cctv_rec.visible = on
	if _grade:
		_grade.visible = not on and _retro
	if not on:
		return
	_cctv_mat.set_shader_parameter("amount", 1.0)
	_cctv_mat.set_shader_parameter("time", Time.get_ticks_msec() / 1000.0)
	var t := int(seconds)
	_cctv_label.text = "%s\n03:%02d:%02d:%02d" % [cam, 14 + t / 60, t % 60, int(fmod(seconds, 1.0) * 24.0)]
	_cctv_rec.text = "● REC" if fmod(seconds, 1.0) < 0.6 else ""


var _grade: ColorRect
var _grade_mat: ShaderMaterial
var _retro := true
var _bars: Array[ColorRect] = []
var _area: Label
var _area_tween: Tween


## The MGS colour grade over the whole game view (under the HUD). alert / caution: 0..1, pulsing.
func set_grade(alert: float, caution: float) -> void:
	if _grade == null:
		_grade_mat = ShaderMaterial.new()
		_grade_mat.shader = preload("res://assets/shaders/psx/grade.gdshader")
		_grade = ColorRect.new()
		_grade.material = _grade_mat
		_grade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_grade.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(_grade)
		move_child(_grade, 0)
	_grade_mat.set_shader_parameter("alert", alert)
	_grade_mat.set_shader_parameter("caution", caution)


## The RETRO FILTER setting: the colour grade and dither on or off.
func set_retro_filter(on: bool) -> void:
	_retro = on
	if _grade:
		_grade.visible = on and not (_cctv != null and _cctv.visible)


## Cinema bars top and bottom (the opening pan); they slide away when the run starts.
func set_letterbox(on: bool, seconds: float = 0.0) -> void:
	if _bars.is_empty() and not on:
		return  # never shown (a retry skips the opening pan)
	if _bars.is_empty():
		for top in [true, false]:
			var bar := ColorRect.new()
			bar.color = Color.BLACK
			bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			bar.set_anchors_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
			bar.offset_top = 0.0 if top else -LETTERBOX
			bar.offset_bottom = LETTERBOX if top else 0.0
			add_child(bar)
			_bars.append(bar)
	for i in _bars.size():
		var bar := _bars[i]
		var shown := 0.0 if on else (-LETTERBOX if i == 0 else LETTERBOX)
		var prop := "offset_top" if i == 0 else "offset_bottom"
		var other := "offset_bottom" if i == 0 else "offset_top"
		var t := create_tween().set_parallel()
		t.tween_property(bar, prop, shown, seconds)
		t.tween_property(bar, other, shown + (LETTERBOX if i == 0 else -LETTERBOX), seconds)


## The in-run HUD shows only during a run (not over the main menu, the pan or the end screens).
func set_playing(on: bool) -> void:
	for n in [_status, _clock, _fire, _rail, _pause, _message]:
		if n:
			n.visible = on if n != _message else (on and _message.text != "")


## MGS-style location caption: the area's name types out bottom left, then fades.
func show_area(area_name: String) -> void:
	if _area == null:
		_area = UiKit.label("", 16, Color("e8f0e0"))
		_area.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		_area.offset_left = 22
		_area.offset_top = -120
		add_child(_area)
	if _area_tween:
		_area_tween.kill()
	_area.text = area_name
	_area.visible_ratio = 0.0
	_area.modulate.a = 1.0
	_area_tween = create_tween()
	_area_tween.tween_property(_area, "visible_ratio", 1.0, 0.04 * area_name.length())
	_area_tween.tween_interval(2.2)
	_area_tween.tween_property(_area, "modulate:a", 0.0, 0.6)


func setup(tuning: Tuning) -> void:
	_rail = ProgressRail.new()
	add_child(_rail)
	_fire = TriggerButton.new()
	_fire.tuning = tuning
	add_child(_fire)
	_clock = ClockDial.new()
	_clock.tuning = tuning
	add_child(_clock)
	_message = MessageBox.new()
	_message.set_anchors_preset(Control.PRESET_FULL_RECT)
	_message.offset_top = 40  # just under the clock
	_message.visible = false
	add_child(_message)
	_pause = PauseButton.new()
	add_child(_pause)
	_pause.pressed.connect(func() -> void: pause_pressed.emit())
	show_hp(tuning.player_hits, tuning.player_hits)


func show_hp(left: int, total: int) -> void:
	_status.hp = left
	_status.hp_total = total
	_status.queue_redraw()


func show_clock(fraction: float, lift_fraction: float = -1.0) -> void:
	if _clock and lift_fraction >= 0.0 and _clock.lift_fraction != lift_fraction:
		_clock.lift_fraction = lift_fraction
		_clock.queue_redraw()
	if _clock and absf(_clock.fraction - fraction) > 0.001:
		_clock.fraction = fraction
		_clock.queue_redraw()


## How far through the mission you are (0 at the start, 1 at the chopper).
func show_progress(fraction: float) -> void:
	if _rail:
		_rail.set_fraction(fraction)


## A message under the clock. Persistent ones blink until cleared; others fade after a while.
func show_chopper_message(text: String, color: Color, seconds: float, persistent: bool) -> void:
	_message.show_message(text, color, seconds, persistent)


func show_hit() -> void:
	_flash.color.a = 0.45
	create_tween().tween_property(_flash, "color:a", 0.0, 0.3)


func set_firing(held: bool) -> void:
	if _fire and _fire.held != held:
		_fire.held = held


## The FIRE button moved (the FIRE BUTTON setting): draw it in its new place.
func redraw_fire() -> void:
	if _fire:
		_fire.queue_redraw()


## A shot went off: kick the trigger.
func fire_kick() -> void:
	if _fire:
		_fire.kick()


func show_cover_hint(on: bool) -> void:
	_hint.text = "IN COVER - SWIPE < > TO BREAK COVER" if on else ""


## Legacy prompt after the opening pan: the menu now does this, so it's just the mission title.
func show_title() -> void:
	pass


## During the opening pan: just the mission name.
func show_mission_title(title: String) -> void:
	_title.text = title


func hide_title() -> void:
	_title.text = ""


func show_junction(options: Array[Dictionary]) -> void:
	var parts := PackedStringArray()
	for side in RouteGraph.SIDES:  # left to right, whatever order they were authored in
		for o in options:
			if RouteGraph.side_of(o) == side:
				parts.append("[color=#%s]%s[/color]" % [side_color(side).lightened(0.3).to_html(false),
						route_prompt(String(o.get("shown", o.get("label", o["to"]))), side_dir(side))])
	_junction.text = "[center]%s[/center]" % "    ".join(parts)


func clear_junction() -> void:
	_junction.text = ""


## The run's over: the end screen (in the Frontend) takes over; the HUD just clears up.
func show_end(_reason: StringName, _route_summary: String) -> void:
	clear_junction()
	_message.show_message("", UiKit.PAPER, 0.0, false)
	_hint.text = ""
	set_playing(false)


func _on_alert_changed(level: int) -> void:
	_status.alert = level
	_status.queue_redraw()
