class_name PursuitGuard
extends Node3D
## One of the Alert 3 pursuit squad (user direction): a soldier running after you down the route,
## one in each lane. He runs at your run speed, so he only gains when you slow down. He jumps
## barriers and slides under pipes like you, and keeps to his lane: cover in it he usually spots
## and swerves round, but sometimes he doesn't and runs straight into it
## (he falls and he's out of the chase, user decision). He never shoots. If one of
## the squad reaches you, you're CAPTURED.
##
## He's the guard (user), his carbine across his chest in both hands (GuardRig), a light under its
## handguard (a bright point in the dark, and on the rear-view CCTV). The level runs the squad
## (spawns it, checks cover and the catch) and calls update() every physics frame. Everything is in
## route space: `at` and `x`.

enum State { RUN, OUT, GIVE_UP, GRAB }

## He's posed at half the physics rate (PS1 games animated at less than the frame rate, and the
## squad is five rigs at once): every POSE_EVERY-th physics frame.
const POSE_EVERY := 2

var at: float = 0.0
## His lane (he swerves out of it round cover, then back).
var home_x: float = 0.0
var x: float = 0.0
var state: State = State.RUN

## For each piece of cover he's come up to: whether he spotted it in time (seeded, so runs repeat).
var decided := {}
var _rng := RandomNumberGenerator.new()
var _speed := 0.0
var _hop := 0.0
var _body: Node3D
var _rig: GuardRig
var _pose_tick := 0
var _pose_delta := 0.0


func _init(tuning: Tuning) -> void:
	_body = Node3D.new()
	add_child(_body)
	_rig = GuardRig.new(GuardRifle.Kind.CARBINE_LIGHT)
	_body.add_child(_rig)
	var shadow := MeshInstance3D.new()
	shadow.mesh = PsxMaterials.shadow_mesh(Vector2(0.8, 0.6))
	shadow.material_override = PsxMaterials.shadow(false, tuning)
	shadow.position.y = 0.03
	add_child(shadow)


## Whether, moving from `before` to `after` this frame in his lane at `gx`, he runs into a piece
## of cover at (cover_at, cover_x). Pure rule, so it's unit-tested.
static func runs_into(before: float, after: float, gx: float, cover_at: float, cover_x: float, lane_width: float) -> bool:
	var face := cover_at - 0.5  # its near face
	return before < face and after >= face and absf(gx - cover_x) < lane_width * 0.5


## Whether the squad has caught you: one of them is within `reach` of you (any lane).
static func catches(guard_at: float, player_d: float, reach: float) -> bool:
	return guard_at >= player_d - reach


func set_seed(s: int) -> void:
	_rng.seed = s
	_pose_tick = s % POSE_EVERY  # the squad's poses spread across the frames


## Does he spot this piece of cover in time to swerve round it?
func spots(key: String, chance: float) -> bool:
	if not decided.has(key):
		decided[key] = _rng.randf() < chance
	return decided[key]


func is_chasing() -> bool:
	return state == State.RUN


## One frame. speed: how fast he runs (m/s). lows: barriers ({at, x}) to jump, highs: pipes
## ({at, x}) to slide under. place(at, x, y) -> world position.
func update(delta: float, speed: float, lows: Array, highs: Array, place: Callable) -> void:
	match state:
		State.RUN:
			_speed = speed
		State.GIVE_UP:
			_speed = move_toward(_speed, 0.0, delta * 9.0)  # pulls up, gives up
		_:
			return  # down, or holding you: he stays where he is
	at += _speed * delta
	var hop := 0.0
	for o in lows:
		var dd := absf(float(o["at"]) - at)
		if dd < 1.1 and absf(float(o["x"]) - x) < 0.9:
			hop = maxf(hop, 0.8 * cos(PI * 0.5 * dd / 1.1))
	var duck := false
	for o in highs:
		if absf(float(o["at"]) - at) < 1.3 and absf(float(o["x"]) - x) < 0.9:
			duck = true
	var pos: Vector3 = place.call(at, x, hop)
	var ahead: Vector3 = place.call(at + 1.0, x, hop)
	global_transform = Transform3D(Basis.IDENTITY, pos).looking_at(Vector3(ahead.x, pos.y, ahead.z), Vector3.UP)
	var pace := _speed / maxf(speed, 0.1) if state == State.RUN else _speed / 11.0
	# Running (as fast as he's going), up over a barrier, down under a pipe.
	_pose_delta += delta
	_pose_tick += 1
	if _pose_tick % POSE_EVERY == 0 or delta == 0.0:
		_rig.animate(_pose_delta, {"run": clampf(pace, 0.0, 1.0), "airborne": hop > 0.05, "rising": hop > _hop, "duck": duck})
		_pose_delta = 0.0
	_hop = hop


## Ran into cover: he goes down hard, face first, and stays down.
func fall() -> void:
	if state != State.RUN:
		return
	state = State.OUT
	_rig.fall()
	create_tween().tween_property(_body, "position:z", 0.6, 0.28)  # bounced back off it


## Alert's dropped: the squad falls back.
func give_up() -> void:
	if state == State.RUN:
		state = State.GIVE_UP


## He's got you: he stops and aims at you (`at`: world space; he never fires, user decision).
func grab(at: Vector3) -> void:
	if state != State.RUN:
		return
	state = State.GRAB
	_rig.pose_to({"aim": true, "target": at}, 0.8)

