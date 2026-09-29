class_name Hud
extends CanvasLayer
## Deliberately minimal, retro HUD. The helicopter should carry the urgency, not a big timer.

const ALERT_COLORS := {1: Color("9fd36b"), 2: Color("f0c040"), 3: Color("ff4b3a")}
## Each side of a fork has a colour. The road paint, sign and this prompt all use the same ones.
const SIDE_COLORS := {"left": Color("d9a032"), "straight": Color("a8a898"), "right": Color("4f9fd0")}
const SIDE_DIRS := {"left": -1, "straight": 0, "right": 1}
const END_TEXT := {
	&"extracted": "EXTRACTED",
	&"killed": "KILLED IN ACTION",
	&"captured": "CAPTURED",
	&"chopper_left": "THE CHOPPER LEFT",
	&"dead_end": "NO WAY THROUGH",
}

var _alert: Label
var _junction: RichTextLabel
var _end: Label
var _title: Label
var _hp: Label
var _hint: Label
var _flash: ColorRect
var _fire: FireButton


## The one FIRE control (LOCKED Controls v1): a chunky circle, bottom right. SwipeInput decides
## what counts as touching it; this just draws it in the same place.
class FireButton extends Control:
	var tuning: Tuning
	var held := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)
		get_viewport().size_changed.connect(queue_redraw)

	func _draw() -> void:
		if tuning == null:
			return
		var b := SwipeInput.fire_button(get_viewport_rect().size, tuning)
		var c := Vector2(b.x, b.y)
		draw_circle(c, b.z, Color(0, 0, 0, 0.45))
		draw_arc(c, b.z, 0, TAU, 20, Color("d8d0b0") if not held else Color("ff5a3a"), 2.0)
		if held:
			draw_circle(c, b.z - 3, Color(1, 0.35, 0.2, 0.35))
		var font := get_theme_default_font()
		var size := 10
		var w := font.get_string_size("FIRE", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		draw_string(font, c + Vector2(-w / 2.0, size / 3.0), "FIRE", HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color("f0e8c8"))


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
	_alert = _label(Vector2(6, 4), HORIZONTAL_ALIGNMENT_LEFT)
	_junction = RichTextLabel.new()
	add_child(_junction)
	_junction.bbcode_enabled = true
	_junction.fit_content = true
	_junction.scroll_active = false
	_junction.add_theme_font_size_override("normal_font_size", 12)
	_junction.add_theme_color_override("font_outline_color", Color.BLACK)
	_junction.add_theme_constant_override("outline_size", 3)
	_junction.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_junction.offset_left = 8
	_junction.offset_right = -8
	_junction.offset_top = 70
	_end = _label(Vector2(0, 150), HORIZONTAL_ALIGNMENT_CENTER)
	_end.autowrap_mode = TextServer.AUTOWRAP_WORD
	_title = _label(Vector2(0, 120), HORIZONTAL_ALIGNMENT_CENTER)
	_hp = _label(Vector2(6, 16), HORIZONTAL_ALIGNMENT_LEFT)
	_hint = _label(Vector2(0, 104), HORIZONTAL_ALIGNMENT_CENTER)
	_flash = ColorRect.new()
	_flash.color = Color(0.85, 0.1, 0.05, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_flash)
	GameState.alert_changed.connect(_on_alert_changed)


func setup(tuning: Tuning) -> void:
	_fire = FireButton.new()
	_fire.tuning = tuning
	add_child(_fire)
	show_hp(tuning.player_hits, tuning.player_hits)


func show_hp(left: int, total: int) -> void:
	_hp.text = "HP " + "#".repeat(left) + "-".repeat(maxi(0, total - left))
	_hp.modulate = Color("f0e8c8") if left > 1 else Color("ff4b3a")


func show_hit() -> void:
	_flash.color.a = 0.45
	create_tween().tween_property(_flash, "color:a", 0.0, 0.3)


func set_firing(held: bool) -> void:
	if _fire and _fire.held != held:
		_fire.held = held
		_fire.queue_redraw()


func show_cover_hint(on: bool) -> void:
	_hint.text = "IN COVER\nSWIPE < > TO BREAK COVER" if on else ""


func show_title() -> void:
	_title.text = "GET TO THE CHOPPER!\n\nSWIPE < > TO DODGE\nSWIPE UP TO JUMP\nSWIPE DOWN TO SLIDE\nHOLD FIRE TO SHOOT\n\nOUTER LANES TAKE SIDE EXITS\nRUN INTO COVER TO HIDE\n\nTAP TO START"


func hide_title() -> void:
	_title.text = ""


func show_junction(options: Array[Dictionary]) -> void:
	var parts := PackedStringArray()
	for side in RouteGraph.SIDES:  # left to right, whatever order they were authored in
		for o in options:
			if RouteGraph.side_of(o) == side:
				parts.append("[color=#%s]%s[/color]" % [side_color(side).lightened(0.3).to_html(false),
						route_prompt(String(o.get("label", o["to"])), side_dir(side))])
	_junction.text = "[center]%s[/center]" % "    ".join(parts)


func clear_junction() -> void:
	_junction.text = ""


func show_end(reason: StringName, route_summary: String) -> void:
	clear_junction()
	_end.text = "%s\n\nROUTE\n%s\n\nTAP TO RETRY" % [END_TEXT.get(reason, String(reason).to_upper()), route_summary]


func _on_alert_changed(level: int) -> void:
	_alert.text = "ALERT %d" % level
	_alert.modulate = ALERT_COLORS.get(level, Color.WHITE)


func _label(pos: Vector2, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	add_child(l)
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", 10)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 3)
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		l.set_anchors_preset(Control.PRESET_TOP_WIDE)
		l.offset_left = 8
		l.offset_right = -8
		l.offset_top = pos.y
	else:
		l.position = pos
	return l
