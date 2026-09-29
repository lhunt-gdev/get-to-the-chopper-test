class_name SwipeInput
extends Node
## Turns touches into swipes and taps. A swipe fires as soon as the finger has
## moved far enough, not on release, so dodges feel instant.
## Arrow keys and Space/Enter do the same on desktop.

signal swiped(direction: Vector2i)  ## (-1,0) left, (1,0) right, (0,-1) up, (0,1) down
signal tapped(screen_position: Vector2)
signal fire_pressed

@export var tuning: Tuning

## Touch index -> {start: Vector2, t: int, consumed: bool}
var _touches: Dictionary = {}


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_on_touch(event)
	elif event is InputEventScreenDrag:
		_on_drag(event)
	elif event.is_action_pressed("ui_left"):
		swiped.emit(Vector2i.LEFT)
	elif event.is_action_pressed("ui_right"):
		swiped.emit(Vector2i.RIGHT)
	elif event.is_action_pressed("ui_up"):
		swiped.emit(Vector2i.UP)
	elif event.is_action_pressed("ui_down"):
		swiped.emit(Vector2i.DOWN)
	elif event.is_action_pressed("ui_accept"):
		fire_pressed.emit()


func _on_touch(e: InputEventScreenTouch) -> void:
	if e.pressed:
		_touches[e.index] = {"start": e.position, "t": Time.get_ticks_msec(), "consumed": false}
		return
	var tr: Dictionary = _touches.get(e.index, {})
	_touches.erase(e.index)
	if tr.is_empty() or tr["consumed"]:
		return
	var moved: float = (e.position - tr["start"]).length()
	if moved < _threshold() and Time.get_ticks_msec() - int(tr["t"]) <= tuning.tap_max_ms:
		tapped.emit(e.position)


func _on_drag(e: InputEventScreenDrag) -> void:
	var tr: Dictionary = _touches.get(e.index, {})
	if tr.is_empty() or tr["consumed"]:
		return
	var d: Vector2 = e.position - tr["start"]
	if d.length() < _threshold():
		return
	tr["consumed"] = true
	swiped.emit(direction_of(d))


func _threshold() -> float:
	return get_viewport().get_visible_rect().size.x * tuning.swipe_min_fraction


static func direction_of(d: Vector2) -> Vector2i:
	if absf(d.x) >= absf(d.y):
		return Vector2i.RIGHT if d.x > 0.0 else Vector2i.LEFT
	return Vector2i.DOWN if d.y > 0.0 else Vector2i.UP
