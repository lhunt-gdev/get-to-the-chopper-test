class_name SwipeInput
extends Node
## Turns touches into swipes, taps and FIRE. A swipe fires as soon as the finger has
## moved far enough, not on release, so dodges feel instant.
## A touch that starts on the FIRE button (bottom right) holds FIRE and is never a swipe.
## With SETTINGS' MOVE on BUTTONS, a touch that starts on one of the four move buttons (the HUD's
## ButtonPad, while it shows) is that button's swipe, once, as it goes down, and nothing else: never a
## swipe or a tap as it moves or lifts, never FIRE. Each finger is its own touch, so a thumb can hold
## FIRE while the other taps the buttons. Swipes work as ever round them.
## Arrow keys do the swipes on desktop; Space/Enter holds FIRE (and starts / retries).

signal swiped(direction: Vector2i)  ## (-1,0) left, (1,0) right, (0,-1) up, (0,1) down
signal tapped(screen_position: Vector2)
signal fire_pressed
signal fire_released
## A move button held down by touch `index` (or, ZERO, let go): the HUD lights it (Hud.ButtonPad).
signal button_held(index: int, direction: Vector2i)

@export var tuning: Tuning
## The HUD's move buttons (set by the level): pressed only while they show (live play, MOVE on BUTTONS).
var pad: Control

## Touch index -> {start: Vector2, t: int, consumed: bool, fire: bool, button: Vector2i (ZERO: none)}
var _touches: Dictionary = {}


## How far past the drawn radius a touch still holds FIRE (a little forgiving at the edge).
const TOUCH_REACH := 1.15
## The bottom of the screen kept clear of FIRE's touch area in Home Screen mode (px): an iPhone's
## home swipe starts there, and a thumb held on FIRE that low could send you to the Home Screen.
const HOME_SWIPE_CLEAR := 24.0
## The move buttons (MOVE: BUTTONS): each BUTTON_R px round (30 across, about 44 pt on a phone; its touch
## area TOUCH_REACH past that, like FIRE's), BUTTON_SPACING px from the diamond's middle to each one's
## (about 12 px between two neighbours, corner to corner), and the middle PAD_INSET px in from its side of the screen
## and PAD_LIFT px up from the bottom: low, under the thumb.
const BUTTON_R := 15.0
const BUTTON_SPACING := 30.0
const PAD_INSET := 68.0
const PAD_LIFT := 68.0
## The four, top to bottom: up JUMP, left and right change lane, down SLIDE.
const BUTTON_DIRS: Array[Vector2i] = [Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN]

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


## The move buttons (MOVE: BUTTONS) for a screen of this size: direction -> (centre x, centre y,
## radius), a diamond on the side away from FIRE (TRIGGER), the same size on any screen (a wider one
## just has more room between it and FIRE). The HUD draws them here. From the Home Screen it sits
## higher, like FIRE, the bottom one's touch area clear of the bottom HOME_SWIPE_CLEAR px.
static func move_buttons(screen: Vector2, t: Tuning) -> Dictionary:
	var x := screen.x - PAD_INSET if t.fire_on_left else PAD_INSET
	var y := screen.y - PAD_LIFT
	if standalone():
		y = minf(y, screen.y - HOME_SWIPE_CLEAR - BUTTON_SPACING - BUTTON_R * TOUCH_REACH)
	var out := {}
	for d: Vector2i in BUTTON_DIRS:
		out[d] = Vector3(x + d.x * BUTTON_SPACING, y + d.y * BUTTON_SPACING, BUTTON_R)
	return out


## The move button at `p` (its direction), or ZERO for none: within TOUCH_REACH of its edge.
static func on_move_button(p: Vector2, screen: Vector2, t: Tuning) -> Vector2i:
	var all := move_buttons(screen, t)
	for d: Vector2i in all:
		var b: Vector3 = all[d]
		if p.distance_to(Vector2(b.x, b.y)) <= b.z * TOUCH_REACH:
			return d
	return Vector2i.ZERO


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


## Whether the move buttons take touches now: MOVE on BUTTONS and the pad showing (live play).
func buttons_live() -> bool:
	return tuning.move_buttons and pad != null and pad.is_visible_in_tree()


func _on_touch(e: InputEventScreenTouch) -> void:
	if e.pressed:
		var fire := on_fire_button(e.position, _screen(), tuning)
		var button := Vector2i.ZERO if fire or not buttons_live() else on_move_button(e.position, _screen(), tuning)
		_touches[e.index] = {"start": e.position, "t": Time.get_ticks_msec(), "consumed": fire or button != Vector2i.ZERO,
				"fire": fire, "button": button}
		if fire:
			fire_pressed.emit()
		elif button != Vector2i.ZERO:
			button_held.emit(e.index, button)
			swiped.emit(button)  # (the swipe's own way in: whatever a swipe does, it does)
		return
	var tr: Dictionary = _touches.get(e.index, {})
	_touches.erase(e.index)
	if pad != null:
		button_held.emit(e.index, Vector2i.ZERO)
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
