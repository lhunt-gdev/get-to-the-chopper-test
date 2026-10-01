class_name SecurityTrooper
extends Node3D
## The alarm runner (LOCKED roster: the Security Trooper, an alert specialist). He stands in a
## lane ahead, unarmed. When you come close he spots you (a "!"), turns and sprints off down the
## route ahead of you, a little faster than you run, for a couple of sections (user direction), to
## an alarm. Shoot him before he gets there; if he does, he slams the alarm and alert goes up one
## level. Letting him go is a valid choice (LOCKED). He weaves round walls and vaults low
## obstacles on the way, and he never shoots.
##
## Placeholder art: boxes. The level calls update() every physics frame. Everything is in route
## space: `at` (distance along the route) and `x` (across it).

signal spotted
signal wounded
signal knocked_down
## He reached the alarm and raised it.
signal raised

enum State { IDLE, STARTLED, RUN, ALARM, DOWN }

const COLOR := Color("7088b0")  # bluer than the riflemen, light enough to read through the fog
const LASER := Color("ff2a2a")
const AMBER := Color("ffb347")
const SWERVE_SPEED := 6.0
## The last stretch (m) where he cuts across to the wall the alarm is on.
const TO_WALL := 8.0

var at: float = 0.0
var x: float = 0.0
var min_alert: int = 1
var max_alert: int = 1
var state: State = State.IDLE
var health: int = 2
var committed: bool = false
## Route distance he set off from, and where the alarm is.
var start_at: float = 0.0
var alarm_at: float = 0.0
## The x of the wall he's heading for at the end (the outer edge of the road).
var wall_x: float = 0.0

var _timer := 0.0
var _run := 0.0
var _lane_x := 0.0
var _body: Node3D
var _legs: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _warn: Label3D
## A blinking amber light on his radio, so you can follow him down a dark corridor.
var _beacon: MeshInstance3D


func _init(tuning: Tuning) -> void:
	health = tuning.security_health
	_body = Node3D.new()
	add_child(_body)
	_part(_body, Vector3(0.5, 0.75, 0.32), Vector3(0, 1.2, 0), COLOR)                    # torso
	_part(_body, Vector3(0.38, 0.3, 0.38), Vector3(0, 1.75, 0), Color("c9a07a"))          # head
	_part(_body, Vector3(0.42, 0.14, 0.42), Vector3(0, 1.94, 0), COLOR.darkened(0.45))    # cap
	_part(_body, Vector3(0.52, 0.1, 0.34), Vector3(0, 1.0, 0), AMBER.darkened(0.15))     # amber belt: "security"
	_part(_body, Vector3(0.12, 0.22, 0.08), Vector3(0.18, 1.35, 0.2), Color("1c1c1a"))   # radio on his back
	_part(_body, Vector3(0.02, 0.3, 0.02), Vector3(0.22, 1.58, 0.2), Color("1c1c1a"))    # its aerial
	_beacon = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.14, 0.1, 0.06)
	_beacon.mesh = bm
	_beacon.material_override = PsxMaterials.glow(AMBER)
	_beacon.position = Vector3(0.18, 1.5, 0.25)
	_body.add_child(_beacon)
	for s in [-1, 1]:
		var hip := Node3D.new()
		_body.add_child(hip)
		hip.position = Vector3(s * 0.13, 0.82, 0)
		_part(hip, Vector3(0.18, 0.82, 0.2), Vector3(0, -0.41, 0), COLOR.darkened(0.25))
		_legs.append(hip)
		var shoulder := Node3D.new()
		_body.add_child(shoulder)
		shoulder.position = Vector3(s * 0.32, 1.52, 0)
		_part(shoulder, Vector3(0.13, 0.6, 0.14), Vector3(0, -0.3, 0), COLOR.darkened(0.1))
		_arms.append(shoulder)
	var shadow := MeshInstance3D.new()
	shadow.mesh = PsxMaterials.shadow_mesh(Vector2(0.8, 0.6))
	shadow.material_override = PsxMaterials.shadow(false, tuning)
	shadow.position.y = 0.03
	add_child(shadow)
	_warn = Label3D.new()
	_warn.text = "!"
	_warn.font_size = 64
	_warn.pixel_size = 0.03
	_warn.modulate = AMBER
	_warn.outline_modulate = Color.BLACK
	_warn.outline_size = 10
	_warn.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_warn.no_depth_test = true
	_warn.position = Vector3(0, 2.5, 0)
	_warn.visible = false
	add_child(_warn)


## How far along his run to the alarm he is, 0..1. Pure rule, so it's unit-tested.
static func run_progress(start: float, alarm: float, now: float) -> float:
	if alarm <= start:
		return 1.0
	return clampf((now - start) / (alarm - start), 0.0, 1.0)


func is_active(alert: int) -> bool:
	return committed or (alert >= min_alert and alert <= max_alert)


func note_seen(tuning: Tuning, alert: int, player_d: float) -> void:
	if committed or not is_alive():
		return
	if state != State.IDLE or (is_active(alert) and at - player_d <= tuning.trooper_commit_distance):
		committed = true


func is_alive() -> bool:
	return state != State.DOWN


## Still on his way to the alarm (spotted you, not down, not there yet).
func is_running() -> bool:
	return state in [State.STARTLED, State.RUN]


func is_targetable(alert: int) -> bool:
	return is_alive() and is_active(alert)


## Auto-targeting (Targeting's rule): a Security Trooper going for an alarm comes first.
func get_threat_priority() -> int:
	return 100 if is_running() else 0


func progress() -> float:
	return run_progress(start_at, alarm_at, at)


## One frame. walls: cover walls ({at, x0, x1}) on the stretch he's on, to run round. lows: low
## obstacles ({at, x}) to vault, highs: overhead ones ({at, x}) to duck under. place(at, x, y) ->
## world position, or null where the route ahead isn't built (he's out of sight in the fog).
func update(delta: float, tuning: Tuning, alert: int, player_d: float, walls: Array, lows: Array,
		highs: Array, place: Callable) -> void:
	note_seen(tuning, alert, player_d)
	if state == State.IDLE:
		visible = is_active(alert)
		var ahead := at - player_d
		if is_active(alert) and ahead > 0.0 and ahead <= tuning.security_trigger_distance:
			state = State.STARTLED
			committed = true
			_timer = tuning.security_startle_time
			_warn.visible = true
			start_at = at
			alarm_at = at + tuning.security_alarm_distance
			_lane_x = x
			var here := global_transform
			top_level = true  # from here he moves along the route on his own
			global_transform = here
			spotted.emit()
		return
	match state:
		State.STARTLED:
			_timer -= delta
			_warn.visible = fmod(_timer, 0.16) > 0.06
			_body.rotation.y = lerpf(_body.rotation.y, PI, clampf(delta * 14.0, 0.0, 1.0))  # turning to run
			if _timer <= 0.0:
				state = State.RUN
				_warn.visible = false
				_body.rotation.y = 0.0  # from now on the whole of him faces down the route (_put)
		State.RUN:
			at += tuning.security_speed * delta
			var target := _lane_x
			if alarm_at - at < TO_WALL:
				target = wall_x  # the alarm's on the wall: cut across to it
			else:
				target = _round_walls(walls, target)
			x = move_toward(x, target, SWERVE_SPEED * delta)
			if at >= alarm_at:
				at = alarm_at
				state = State.ALARM
				_slam()
				raised.emit()
	if state == State.STARTLED:
		return  # turning on the spot, still where he stood
	if state == State.DOWN:
		return  # where he fell
	if state == State.ALARM:
		if _put(place, 0.0):  # at the panel (shown once that stretch is built), facing the wall
			rotate_object_local(Vector3.UP, -signf(wall_x) * PI / 2.0)
		return
	_put(place, _hop(lows))
	_beacon.visible = fmod(Time.get_ticks_msec() / 1000.0, 0.5) < 0.3
	_body.scale.y = lerpf(_body.scale.y, 0.62 if _ducking(highs) else 1.0, clampf(delta * 18.0, 0.0, 1.0))
	_body.rotation.x = -0.22  # leaning into the sprint
	_run += delta * 14.0
	var swing := sin(_run) * 0.8
	_legs[0].rotation.x = swing
	_legs[1].rotation.x = -swing
	_arms[0].rotation.x = -swing
	_arms[1].rotation.x = swing


## Shot by the player.
func hit() -> void:
	if not is_alive():
		return
	health -= 1
	wounded.emit()
	_body.scale = Vector3(1.15, 0.9, 1.15)
	create_tween().tween_property(_body, "scale", Vector3.ONE, 0.12)
	Blood.mist(self, Vector3(0, 1.25, 0.25), Vector3(0, 1.0, 0.35), get_instance_id() + health)
	if health <= 0:
		knock_down()


func knock_down() -> void:
	if not is_alive():
		return
	state = State.DOWN
	_warn.visible = false
	knocked_down.emit()
	for limb in _legs + _arms:
		limb.rotation.x = 0.0
	var tween := create_tween()
	# Shot in the back as he runs: he goes down forward, away from you.
	tween.tween_property(_body, "rotation:x", -PI / 2.0, 0.3).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(_body, "position:y", 0.2, 0.3)
	tween.tween_callback(func() -> void: Blood.pool(self, Vector3(0, 0.035, -0.8), 1.2, 2.2, get_instance_id()))


## At the alarm: he slaps it, then stays there with his hand on it.
func _slam() -> void:
	_body.rotation.x = 0.0
	_body.scale = Vector3.ONE
	_warn.text = "!!"
	_warn.modulate = LASER
	_warn.visible = true
	for limb in _legs:
		limb.rotation.x = 0.0
	_arms[0].rotation.x = 0.0
	_arms[1].rotation.x = -PI / 2.0  # reaching up to the panel
	get_tree().create_timer(1.5).timeout.connect(func() -> void:
		if is_instance_valid(self):
			_warn.visible = false)


## Swerve round a wall just ahead of him in his lane, to its nearer open edge.
func _round_walls(walls: Array, want: float) -> float:
	for w in walls:
		var wall_at: float = w["at"]
		if wall_at > at - 0.6 and wall_at < at + 6.0:
			var x0: float = w["x0"]
			var x1: float = w["x1"]
			if want > x0 - 0.3 and want < x1 + 0.3:
				var open_left := x0 > -3.6
				var open_right := x1 < 3.6
				if open_left and (not open_right or want - x0 <= x1 - want):
					return x0 - 0.5
				return x1 + 0.5
	return want


func _hop(lows: Array) -> float:
	var hop := 0.0
	for o in lows:
		var dd := absf(float(o["at"]) - at)
		if dd < 1.0 and absf(float(o["x"]) - x) < 0.9:
			hop = maxf(hop, 0.9 * cos(PI * 0.5 * dd / 1.0))
	return hop


func _ducking(highs: Array) -> bool:
	for o in highs:
		if absf(float(o["at"]) - at) < 1.2 and absf(float(o["x"]) - x) < 0.9:
			return true
	return false


## On the route at (at, x), facing on down the route (his back to you); hidden where the route
## isn't built (out of sight, round a split you didn't take, or deep in the fog).
func _put(place: Callable, hop: float) -> bool:
	var pos = place.call(at, x, hop)
	var ahead = place.call(at + 1.0, x, hop)
	if pos == null or ahead == null:
		visible = false
		return false
	visible = true
	var p: Vector3 = pos
	var a: Vector3 = ahead
	global_transform = Transform3D(Basis.IDENTITY, p).looking_at(Vector3(a.x, p.y, a.z), Vector3.UP)
	return true


func _part(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> void:
	var m := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	m.mesh = mesh
	m.material_override = PsxMaterials.flat(color)
	m.position = pos
	parent.add_child(m)
