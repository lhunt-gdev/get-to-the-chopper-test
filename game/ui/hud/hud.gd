class_name Hud
extends CanvasLayer
## Deliberately minimal, retro HUD. The helicopter should carry the urgency, not a big timer.

const ALERT_COLORS := {1: Color("9fd36b"), 2: Color("f0c040"), 3: Color("ff4b3a")}
const END_TEXT := {
	&"extracted": "EXTRACTED",
	&"killed": "KILLED IN ACTION",
	&"captured": "CAPTURED",
	&"chopper_left": "THE CHOPPER LEFT",
	&"dead_end": "NO WAY THROUGH",
}

var _alert: Label
var _junction: Label
var _end: Label
var _title: Label


func _ready() -> void:
	_alert = _label(Vector2(6, 4), HORIZONTAL_ALIGNMENT_LEFT)
	_junction = _label(Vector2(0, 70), HORIZONTAL_ALIGNMENT_CENTER)
	_end = _label(Vector2(0, 150), HORIZONTAL_ALIGNMENT_CENTER)
	_end.autowrap_mode = TextServer.AUTOWRAP_WORD
	_title = _label(Vector2(0, 120), HORIZONTAL_ALIGNMENT_CENTER)
	GameState.alert_changed.connect(_on_alert_changed)


func show_title() -> void:
	_title.text = "GET TO THE CHOPPER!\n\nSWIPE < > TO DODGE\nSWIPE UP TO JUMP\nSWIPE DOWN TO SLIDE\n\nAT A FORK, BE ON THAT SIDE\n\nTAP TO START"


func hide_title() -> void:
	_title.text = ""


func show_junction(options: Array[Dictionary]) -> void:
	var labels := PackedStringArray()
	for o in options:
		labels.append(String(o.get("label", o["to"])))
	if labels.size() == 2:
		_junction.text = "< %s    %s >" % [labels[0], labels[1]]
	else:
		_junction.text = "  |  ".join(labels)


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
