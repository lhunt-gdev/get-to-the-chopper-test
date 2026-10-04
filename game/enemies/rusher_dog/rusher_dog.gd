class_name RusherDog
extends Node3D
## The Rusher (LOCKED roster): a German Shepherd. It stands guard in its lane; when you come close
## it barks (a red "!", a crouch: the telegraph), then sprints straight down the route at you,
## locked onto the lane you were in when it barked (user decision). Dodge out of that lane or shoot
## it; you can't jump it (user decision). If it reaches you in your lane it bites: a hit and a
## stumble (user decision), then it runs on past. Cover doesn't help (LOCKED): it gets round to you.
## On the way it bounds over low obstacles and runs round walls.
##
## He's the user's German Shepherd in a tactical vest (DogRig): standing guard, crouched and
## barking for the telegraph, galloping at you, leaping at you for the bite, dropping onto his side
## when he's shot. The level calls update() every physics frame. Everything is in route space:
## `at` (distance along the route) and `x` (across it).

signal barked
signal bit
signal yelped

enum State { IDLE, WINDUP, CHARGE, PASSED, DOWN }
enum Contact { NONE, BIT, MISSED }

const LASER := Color("ff2a2a")
## Sideways speed (m/s) when it swerves round a wall or back into its lane.
const SWERVE_SPEED := 7.0
## How far behind you it carries on running before it's gone (inside the 10 m the level keeps
## updating it for, or it would stay there, frozen, behind you).
const RUN_ON := 8.0
## How far from you (m) he springs for the bite: his leap at you peaks as he reaches you (he and you
## close at ~20 m/s), in front of the camera.
const LUNGE_AT := 3.5

var at: float = 0.0
var x: float = 0.0
var min_alert: int = 1
var max_alert: int = 3
var state: State = State.IDLE
## The lane it's coming down (your x when it barked).
var locked_x: float = 0.0
## Like troopers: once it's been active in front of you, it stays whatever the alert.
var committed: bool = false

var _timer := 0.0
var _body: Node3D
var _dog: DogRig
var _warn: Label3D
var _hop := 0.0
var _lunged := false
## Bounding over something: where it is along the route (to land clear of it if he's shot).
var _over_at := 0.0
var _route_point: Callable


func _init(tuning: Tuning) -> void:
	_body = Node3D.new()
	add_child(_body)
	_dog = DogRig.new()  # head toward -Z (toward you, like a trooper's rifle)
	_body.add_child(_dog)
	var shadow := MeshInstance3D.new()
	shadow.mesh = PsxMaterials.shadow_mesh(Vector2(0.5, 1.0))
	shadow.material_override = PsxMaterials.shadow(false, tuning)
	shadow.position.y = 0.03
	add_child(shadow)
	_warn = Label3D.new()
	_warn.text = "!"
	_warn.font_size = 64
	_warn.pixel_size = 0.03
	_warn.modulate = LASER
	_warn.outline_modulate = Color.BLACK
	_warn.outline_size = 10
	_warn.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_warn.no_depth_test = true
	_warn.position = Vector3(0, 1.4, 0)
	_warn.visible = false
	add_child(_warn)


## Whether it gets you as it reaches you. Pure rule, so it's unit-tested: in cover it gets round
## to you anyway; otherwise only if you're still in the lane it's coming down.
static func bites(player_x: float, dog_x: float, in_cover: bool, lane_width: float) -> bool:
	return in_cover or absf(player_x - dog_x) < lane_width * 0.5 + 0.15


## How close you get before it barks (it notices you further off at higher alert).
static func trigger_distance(tuning: Tuning, alert: int) -> float:
	return tuning.rusher_trigger_distance + tuning.rusher_trigger_per_alert * (clampi(alert, 1, 3) - 1)


## How long it barks before it charges (shorter at higher alert).
static func windup_time(tuning: Tuning, alert: int) -> float:
	match alert:
		1:
			return tuning.rusher_windup_alert1
		2:
			return tuning.rusher_windup_alert2
	return tuning.rusher_windup_alert3


func is_active(alert: int) -> bool:
	return committed or (alert >= min_alert and alert <= max_alert)


func note_seen(tuning: Tuning, alert: int, player_d: float) -> void:
	if committed or not is_alive():
		return
	if state != State.IDLE or (is_active(alert) and at - player_d <= tuning.trooper_commit_distance):
		committed = true


func is_alive() -> bool:
	return state != State.DOWN


func is_targetable(alert: int) -> bool:
	return is_alive() and state != State.PASSED and is_active(alert)


## Auto-targeting (agreed rule): a barking or charging dog comes before an aiming trooper (50).
func get_threat_priority() -> int:
	return 60 if state in [State.WINDUP, State.CHARGE] else 0


## One frame. walls: cover walls in route space ({at, x0, x1}) to run round. lows: low obstacles
## ({at, x}) to bound over. route_point(distance, x, y) -> world position. Returns whether it
## reached you this frame, and if so whether it bit.
func update(delta: float, tuning: Tuning, alert: int, player_d: float, player_x: float, in_cover: bool,
		walls: Array, lows: Array, route_point: Callable) -> Contact:
	note_seen(tuning, alert, player_d)
	visible = is_active(alert) or state == State.DOWN
	var contact := _behave(delta, tuning, alert, player_d, player_x, in_cover, walls, lows, route_point)
	if state == State.CHARGE and not _lunged and at <= player_d + 0.6 + LUNGE_AT:
		_lunged = true
		_dog.lunge()  # the bite: a leap at you (it lands as he reaches you)
	_pose(delta, player_d)
	return contact


## The run's over (nothing updates him any more): whatever he's doing settles, standing.
func stand_down() -> void:
	_warn.visible = false
	if is_alive():
		_land()
		_dog.pose_to({}, 0.6)


## Him, posed for what he's doing: on guard he stands as he's built (nothing to pose: from the
## front, as you see him, a wag wouldn't show); barking, crouched; running, a gallop, stretched out
## over what he bounds over. Down, he drops on his own (DogRig.fall()).
func _pose(delta: float, _player_d: float) -> void:
	if not visible or state == State.DOWN or state == State.IDLE:
		return
	if state == State.WINDUP:
		_dog.animate(delta, {"bark": true})
	else:
		_dog.animate(delta, {"run": 1.0, "leap": clampf(_hop / 0.6, 0.0, 1.0)})


func _behave(delta: float, tuning: Tuning, alert: int, player_d: float, player_x: float, in_cover: bool,
		walls: Array, lows: Array, route_point: Callable) -> Contact:
	match state:
		State.IDLE:
			var ahead := at - player_d
			if is_active(alert) and ahead > 0.0:
				if ahead <= trigger_distance(tuning, alert):
					state = State.WINDUP
					locked_x = player_x
					_timer = windup_time(tuning, alert)
					_warn.visible = true
					barked.emit()
		State.WINDUP:
			_timer -= delta
			_warn.visible = fmod(_timer, 0.2) > 0.08
			if _timer <= 0.0:
				state = State.CHARGE
				_warn.visible = false
				var here := global_transform
				top_level = true  # from here it moves along the route on its own
				global_transform = here
		State.CHARGE:
			at -= tuning.rusher_speed * delta
			x = move_toward(x, _lane_target(player_d, walls), SWERVE_SPEED * delta)
			_place(route_point, lows, delta)
			if at <= player_d + 0.6:
				state = State.PASSED
				if bites(player_x, x, in_cover, tuning.lane_width):
					bit.emit()
					return Contact.BIT
				return Contact.MISSED
		State.PASSED:
			at -= tuning.rusher_speed * delta
			_place(route_point, lows, delta)
			if at < player_d - RUN_ON:
				visible = false
	return Contact.NONE


## Shot: one is enough. It yelps, drops, and bleeds.
func hit() -> void:
	if not is_alive():
		return
	state = State.DOWN
	_warn.visible = false
	yelped.emit()
	_land()  # shot in mid-bound: he comes down, clear of what he was bounding over
	_dog.fall()  # onto his side, resting on the floor
	var tween := create_tween()
	tween.tween_interval(DogRig.DROP_TIME)
	tween.tween_callback(func() -> void: Blood.pool(self, Vector3(0, 0.035, 0), 0.8, 1.8, get_instance_id()))


## The lane to head for: its locked lane, unless a wall stands in the way just ahead, when it
## swerves past the wall's nearer open edge (then back in behind it).
func _lane_target(player_d: float, walls: Array) -> float:
	for w in walls:
		var wall_at: float = w["at"]
		if wall_at < at + 0.6 and wall_at > at - 5.0 and wall_at > player_d:
			var x0: float = w["x0"]
			var x1: float = w["x1"]
			if locked_x > x0 - 0.3 and locked_x < x1 + 0.3:
				var open_left := x0 > -50.0 and x0 > -3.6
				var open_right := x1 < 50.0 and x1 < 3.6
				if open_left and (not open_right or locked_x - x0 <= x1 - locked_x):
					return x0 - 0.5
				return x1 + 0.5
	return locked_x


## Mid-bound (the run's over, or he's shot): down on the floor, on the far side of what he was
## bounding over (on your side of it: he was coming toward you).
func _land() -> void:
	if not top_level or _hop <= 0.0 or not _route_point.is_valid():
		return
	at = minf(at, _over_at - 1.1)
	var pos: Vector3 = _route_point.call(at, x, 0.0)
	var toward: Vector3 = _route_point.call(at - 1.0, x, 0.0)
	global_transform = Transform3D(Basis.IDENTITY, pos).looking_at(toward, Vector3.UP)
	_hop = 0.0


## Puts it on the route at (at, x), facing down the route toward you, bounding over any low
## obstacle it's passing (how high, for his pose: _hop).
func _place(route_point: Callable, lows: Array, _delta: float) -> void:
	_route_point = route_point
	var hop := 0.0
	for o in lows:
		var dd := absf(float(o["at"]) - at)
		if dd < 0.9 and absf(float(o["x"]) - x) < 0.9:
			var h := 0.75 * cos(PI * 0.5 * dd / 0.9)  # highest right over it
			if h > hop:
				hop = h
				_over_at = float(o["at"])
	var pos: Vector3 = route_point.call(at, x, hop)
	var toward: Vector3 = route_point.call(at - 1.0, x, hop)
	global_transform = Transform3D(Basis.IDENTITY, pos).looking_at(toward, Vector3.UP)
	_hop = hop
