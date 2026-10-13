class_name SwipeInput
extends Node
## Turns touches into swipes, taps and FIRE. A swipe fires as soon as the finger has
## moved far enough, not on release, so dodges feel instant.
## A touch that starts on the FIRE button (bottom right) holds FIRE and is never a swipe.
## Arrow keys do the swipes on desktop; Space/Enter holds FIRE (and starts / retries).

signal swiped(direction: Vector2i)  ## (-1,0) left, (1,0) right, (0,-1) up, (0,1) down
signal tapped(screen_position: Vector2)
signal fire_pressed
signal fire_released

@export var tuning: Tuning

## Touch index -> {start: Vector2, t: int, consumed: bool, fire: bool}
var _touches: Dictionary = {}


## How far past the drawn radius a touch still holds FIRE (a little forgiving at the edge).
const TOUCH_REACH := 1.15
## The bottom of the screen kept clear of FIRE's touch area in Home Screen mode (px): an iPhone's
## home swipe starts there, and a thumb held on FIRE that low could send you to the Home Screen.
const HOME_SWIPE_CLEAR := 24.0

## Home Screen mode: -1 not asked yet, else 0 / 1. Asked of the browser once (web only).
static var _standalone := -1


## The FIRE button as (centre x, centre y, radius) for a screen of this size. The HUD draws it here.
## From the Home Screen it sits higher, its touch area clear of the bottom HOME_SWIPE_CLEAR px.
static func fire_button(screen: Vector2, t: Tuning) -> Vector3:
	var r := screen.x * t.fire_button_fraction
	var margin := screen.x * 0.04
	var x := r + margin if t.fire_on_left else screen.x - r - margin
	var y := screen.y - r - margin
	if standalone():
		y = minf(y, screen.y - HOME_SWIPE_CLEAR - r * TOUCH_REACH)
	return Vector3(x, y, r)


## Whether the game runs from the Home Screen (iOS's navigator.standalone, or the display-mode:
## standalone media query): what the browser says, read once through JavaScriptBridge. Never on any
## other platform.
static func standalone() -> bool:
	if _standalone < 0:
		_standalone = 0
		if OS.has_feature("web"):
			var got = JavaScriptBridge.eval("(navigator.standalone === true || !!(window.matchMedia && " \
					+ "window.matchMedia('(display-mode: standalone)').matches)) ? 1 : 0", true)
			_standalone = 1 if (got is int or got is float) and int(got) == 1 else 0
	return _standalone == 1


## For tests: as if from the Home Screen (true), not (false), or ask the browser again (null).
static func set_standalone_for_test(on: Variant) -> void:
	_standalone = -1 if on == null else (1 if on else 0)


static func on_fire_button(p: Vector2, screen: Vector2, t: Tuning) -> bool:
	var b := fire_button(screen, t)
	return p.distance_to(Vector2(b.x, b.y)) <= b.z * TOUCH_REACH


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
	elif event.is_action_released("ui_accept"):
		fire_released.emit()


func _on_touch(e: InputEventScreenTouch) -> void:
	if e.pressed:
		var fire := on_fire_button(e.position, _screen(), tuning)
		_touches[e.index] = {"start": e.position, "t": Time.get_ticks_msec(), "consumed": fire, "fire": fire}
		if fire:
			fire_pressed.emit()
		return
	var tr: Dictionary = _touches.get(e.index, {})
	_touches.erase(e.index)
	if tr.get("fire", false):
		fire_released.emit()
		return
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


func _screen() -> Vector2:
	return get_viewport().get_visible_rect().size


func _threshold() -> float:
	return _screen().x * tuning.swipe_min_fraction


static func direction_of(d: Vector2) -> Vector2i:
	if absf(d.x) >= absf(d.y):
		return Vector2i.RIGHT if d.x > 0.0 else Vector2i.LEFT
	return Vector2i.DOWN if d.y > 0.0 else Vector2i.UP
