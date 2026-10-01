class_name PursuitGuard
extends Node3D
## One of the Alert 3 pursuit squad (user direction): a soldier running after you down the route,
## one in each lane. He runs at your run speed, so he only gains when you slow down. He jumps
## barriers and slides under pipes like you, and keeps to his lane: cover in it he usually spots
## and swerves round, but sometimes he doesn't and runs straight into it
## (he falls and he's out of the chase, user decision). He never shoots. If one of
## the squad reaches you, you're CAPTURED.
##
## Placeholder art: boxes. The level runs the squad (spawns it, checks cover and the catch) and
## calls update() every physics frame. Everything is in route space: `at` and `x`.

enum State { RUN, OUT, GIVE_UP, GRAB }

const COLOR := Color("5d6b52")  # olive fatigues: a different unit from the grey riflemen
const LASER := Color("ff2a2a")

var at: float = 0.0
## His lane (he swerves out of it round cover, then back).
var home_x: float = 0.0
var x: float = 0.0
var state: State = State.RUN

## For each piece of cover he's come up to: whether he spotted it in time (seeded, so runs repeat).
var decided := {}
var _rng := RandomNumberGenerator.new()
var _speed := 0.0
var _run := 0.0
var _hop := 0.0
var _body: Node3D
var _legs: Array[Node3D] = []
var _arms: Array[Node3D] = []


func _init(tuning: Tuning) -> void:
	_body = Node3D.new()
	add_child(_body)
	_part(_body, Vector3(0.52, 0.75, 0.34), Vector3(0, 1.2, 0), COLOR)                  # torso
	_part(_body, Vector3(0.54, 0.12, 0.36), Vector3(0, 1.3, 0), LASER.darkened(0.1))     # red chest band: "enemy"
	_part(_body, Vector3(0.36, 0.3, 0.36), Vector3(0, 1.75, 0), Color("b89070"))         # head
	_part(_body, Vector3(0.44, 0.18, 0.44), Vector3(0, 1.92, 0), COLOR.darkened(0.4))    # helmet
	_part(_body, Vector3(0.62, 0.08, 0.1), Vector3(0, 1.38, -0.24), Color("1c1c1a"))     # rifle, held across his chest
	# A torch on his helmet: a bright point in the dark (and in the rear-view CCTV).
	var torch := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(0.12, 0.08, 0.06)
	torch.mesh = tm
	torch.material_override = PsxMaterials.glow(Color("fff2c0"))
	torch.position = Vector3(0.12, 1.92, -0.24)
	_body.add_child(torch)
	for s in [-1, 1]:
		var hip := Node3D.new()
		_body.add_child(hip)
		hip.position = Vector3(s * 0.13, 0.82, 0)
		_part(hip, Vector3(0.18, 0.82, 0.2), Vector3(0, -0.41, 0), COLOR.darkened(0.25))
		_legs.append(hip)
		var shoulder := Node3D.new()
		_body.add_child(shoulder)
		shoulder.position = Vector3(s * 0.33, 1.52, 0)
		_part(shoulder, Vector3(0.13, 0.55, 0.14), Vector3(0, -0.27, 0), COLOR.darkened(0.1))
		_arms.append(shoulder)
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
	_body.scale.y = lerpf(_body.scale.y, 0.6 if duck else 1.0, clampf(delta * 18.0, 0.0, 1.0))
	var pace := _speed / maxf(speed, 0.1) if state == State.RUN else _speed / 11.0
	_body.rotation.x = -0.2 * pace  # leaning into the sprint
	_run += delta * 14.0 * pace
	var swing := sin(_run) * 0.8 * pace
	_legs[0].rotation.x = swing
	_legs[1].rotation.x = -swing
	_arms[0].rotation.x = -swing * 0.5
	_arms[1].rotation.x = swing * 0.5


## Ran into cover: he goes down hard, face first, and stays down.
func fall() -> void:
	if state != State.RUN:
		return
	state = State.OUT
	for limb in _legs + _arms:
		limb.rotation.x = 0.0
	_body.scale = Vector3.ONE
	var tween := create_tween()
	tween.tween_property(_body, "rotation:x", -PI / 2.0, 0.28).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(_body, "position:y", 0.2, 0.28)
	tween.parallel().tween_property(_body, "position:z", 0.6, 0.28)  # bounced back off it


## Alert's dropped: the squad falls back.
func give_up() -> void:
	if state == State.RUN:
		state = State.GIVE_UP


## He's got you: stop, rifle up.
func grab() -> void:
	if state != State.RUN:
		return
	state = State.GRAB
	for limb in _legs:
		limb.rotation.x = 0.0
	_body.rotation.x = 0.0
	_body.scale = Vector3.ONE
	_arms[0].rotation.x = -PI / 2.0
	_arms[1].rotation.x = -PI / 2.0


func _part(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> void:
	var m := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	m.mesh = mesh
	m.material_override = PsxMaterials.flat(color)
	m.position = pos
	parent.add_child(m)
