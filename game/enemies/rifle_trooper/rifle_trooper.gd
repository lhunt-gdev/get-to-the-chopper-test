class_name RifleTrooper
extends Node3D
## Baseline mid-range soldier (LOCKED roster). He stands in a lane ahead, aims at the lane
## you're in (a red "!" and a laser dot on the road under you), then fires. Change lane before
## the shot, or be in cover, and he misses. He only shoots forward, down the route at you.
##
## He's the guard (user), his carbine in both hands (GuardRig): held low across him standing guard,
## brought up into his shoulder and pointed at your lane while he aims. The level places him and
## calls update() every physics frame.

signal knocked_down
## He's started aiming at you (the "!").
signal aimed
## He's fired: hit or not.
signal fired(hit: bool)
## He's been shot (not necessarily down).
signal wounded

enum State { IDLE, AIMING, COOLDOWN, DOWN }
enum Shot { NONE, MISSED, HIT }

const LASER := Color("ff2a2a")
## Where his blood pools once he's down: under his chest (he falls on his face, toward you).
const POOL_AT := Vector3(0, 0.035, -1.2)
## His chest (the plate carrier), where shots at him go and the blood bursts from.
const CHEST := 1.35

## Route position: distance along the route, and across it (in his segment's lanes).
var at: float = 0.0
var x: float = 0.0
var min_alert: int = 1
var max_alert: int = 3
## False while a wall stands between him and you (set by the level each frame): he can't aim.
var sight_clear: bool = true
var health: int = 2
var state: State = State.IDLE
## The lane position he's aiming at, fixed when he starts aiming.
var aimed_x: float = 0.0
## Set once he's been active within sight of the player: from then on he stays whatever the alert
## (user rule: dropping the alert never makes a trooper vanish in front of you).
var committed: bool = false

var _timer: float = 0.0
var _body: Node3D
var _rig: GuardRig
## In range, with a clear shot down the route at you: the rifle comes up while he aims.
var _engaged := false
var _warn: Label3D
var _dot: MeshInstance3D
var _tracer: MeshInstance3D


func _init(tuning: Tuning) -> void:
	health = tuning.trooper_health
	_body = Node3D.new()
	add_child(_body)
	_rig = GuardRig.new(GuardRifle.Kind.CARBINE)
	_body.add_child(_rig)
	var shadow := MeshInstance3D.new()
	shadow.mesh = PsxMaterials.shadow_mesh(Vector2(0.8, 0.6))
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
	_warn.position = Vector3(0, 2.5, 0)
	_warn.visible = false
	add_child(_warn)
	_dot = _loose_box(Vector3(0.7, 0.03, 0.7), LASER)
	_tracer = _loose_box(Vector3(0.05, 0.05, 1.0), Color("ffe08a"))


## Whether his shot lands. Pure rule, so it's unit-tested.
static func shot_hits(player_x: float, aim_x: float, in_cover: bool, lane_width: float) -> bool:
	return not in_cover and absf(player_x - aim_x) < lane_width * 0.5


static func aim_time(tuning: Tuning, alert: int) -> float:
	match alert:
		1:
			return tuning.trooper_aim_time_alert1
		2:
			return tuning.trooper_aim_time_alert2
	return tuning.trooper_aim_time_alert3


func is_active(alert: int) -> bool:
	return committed or (alert >= min_alert and alert <= max_alert)


## Commits him once he's active and within sight, or already aiming.
func note_seen(tuning: Tuning, alert: int, player_d: float) -> void:
	if committed or not is_alive():
		return
	if state != State.IDLE or (is_active(alert) and at - player_d <= tuning.trooper_commit_distance):
		committed = true


func is_alive() -> bool:
	return state != State.DOWN


## Auto-targeting: someone about to shoot you comes first.
func get_threat_priority() -> int:
	return 50 if state == State.AIMING else 0


func is_targetable(alert: int) -> bool:
	return is_alive() and is_active(alert)


## Runs his behaviour for one frame. route_point(distance, x, y) -> world position.
## Returns whether he fired and hit you.
func update(delta: float, tuning: Tuning, alert: int, player_d: float, player_x: float,
		in_cover: bool, player_world: Vector3, route_point: Callable) -> Shot:
	note_seen(tuning, alert, player_d)
	visible = is_active(alert) or state == State.DOWN
	if not is_alive():
		return Shot.NONE
	var shot := _behave(delta, tuning, alert, player_d, player_x, in_cover, player_world, route_point)
	if visible:
		# Rifle up, pointed at your lane where you are, while he's aiming and just after a shot.
		var up := _engaged and state != State.IDLE
		_rig.animate(delta, {"aim": true, "target": route_point.call(player_d, aimed_x, 1.1)} if up else {})
	return shot


func _behave(delta: float, tuning: Tuning, alert: int, player_d: float, player_x: float,
		in_cover: bool, player_world: Vector3, route_point: Callable) -> Shot:
	var ahead := at - player_d
	_engaged = is_active(alert) and ahead >= 1.0 and ahead <= tuning.trooper_aim_range and sight_clear
	if not _engaged:
		# Out of range, you've run past him (he can't shoot behind him), or a wall is in the way.
		if state == State.AIMING:
			_stop_aiming()
			state = State.IDLE
		return Shot.NONE
	_timer -= delta
	match state:
		State.IDLE:
			state = State.AIMING
			aimed_x = player_x
			aimed.emit()
			_timer = aim_time(tuning, alert)
			_warn.visible = true
			_dot.visible = true
		State.AIMING:
			_dot.global_position = route_point.call(player_d + 0.6, aimed_x, 0.02)
			_warn.visible = fmod(_timer, 0.2) > 0.08  # blink faster as the shot gets close
			if _timer <= 0.0:
				_stop_aiming()
				state = State.COOLDOWN
				_timer = tuning.trooper_refire
				var hit := shot_hits(player_x, aimed_x, in_cover, tuning.lane_width)
				fired.emit(hit)
				var target: Vector3 = player_world + Vector3(0, 1.1, 0) if hit else route_point.call(player_d, aimed_x, 1.0)
				_rig.fire()
				_flash_tracer(_rig.muzzle_position(), target)
				return Shot.HIT if hit else Shot.MISSED
		State.COOLDOWN:
			if _timer <= 0.0:
				state = State.IDLE
	return Shot.NONE


## Shot by the player.
func hit() -> void:
	if not is_alive():
		return
	health -= 1
	wounded.emit()
	_rig.flinch()
	# A mist of blood bursting from the front of his chest, up and out to the sides (you're toward
	# his -Z), so you see it.
	Blood.mist(self, Vector3(0, CHEST, -0.25), Vector3(0, 1.0, -0.35), get_instance_id() + health)
	if health <= 0:
		knock_down()


func knock_down() -> void:
	if not is_alive():
		return
	state = State.DOWN
	_stop_aiming()
	knocked_down.emit()
	# He falls on his face, toward you, the rifle dropping by his side; once he's down, blood spreads
	# out under his chest and stays.
	_rig.fall()
	var tween := create_tween()
	tween.tween_interval(GuardRig.FALL_TIME)
	tween.tween_callback(func() -> void: Blood.pool(self, POOL_AT, 1.2, 2.2, get_instance_id()))


## The run's over: he stops aiming, and a shot's kick and flash settle on their own (nothing poses
## him any more).
func stand_down() -> void:
	_stop_aiming()
	if is_alive():
		_rig.pose_to({}, GuardRig.KICK_TIME + 0.2)


func _stop_aiming() -> void:
	_warn.visible = false
	_dot.visible = false


func _flash_tracer(from: Vector3, to: Vector3) -> void:
	var l := from.distance_to(to)
	if l < 0.01:
		return
	_tracer.global_transform = Transform3D(Basis.looking_at(to - from) * Basis.from_scale(Vector3(1, 1, l)), (from + to) / 2.0)
	_tracer.visible = true
	get_tree().create_timer(0.07).timeout.connect(func() -> void: _tracer.visible = false)


## A box placed in world space (not moved by the trooper), hidden until used.
func _loose_box(size: Vector3, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	m.mesh = mesh
	m.material_override = PsxMaterials.glow(color)  # lasers and muzzle tracers glow in the dark
	m.top_level = true
	m.visible = false
	add_child(m)
	return m
