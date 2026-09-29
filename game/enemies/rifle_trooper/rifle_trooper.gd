class_name RifleTrooper
extends Node3D
## Baseline mid-range soldier (LOCKED roster). He stands in a lane ahead, aims at the lane
## you're in (a red "!" and a laser dot on the road under you), then fires. Change lane before
## the shot, or be in cover, and he misses. He only shoots forward, down the route at you.
##
## Placeholder art: boxes. The level places him and calls update() every physics frame.

signal knocked_down

enum State { IDLE, AIMING, COOLDOWN, DOWN }
enum Shot { NONE, MISSED, HIT }

const COLOR := Color("8a93a3")  # light enough to read through the fog
const LASER := Color("ff2a2a")

## Route position: distance along the route, and across it (in his segment's lanes).
var at: float = 0.0
var x: float = 0.0
var min_alert: int = 1
var max_alert: int = 3
var health: int = 2
var state: State = State.IDLE
## The lane position he's aiming at, fixed when he starts aiming.
var aimed_x: float = 0.0

var _timer: float = 0.0
var _body: Node3D
var _warn: Label3D
var _dot: MeshInstance3D
var _tracer: MeshInstance3D


func _init(tuning: Tuning) -> void:
	health = tuning.trooper_health
	_body = Node3D.new()
	add_child(_body)
	_part(Vector3(0.55, 1.6, 0.35), Vector3(0, 0.8, 0), COLOR)
	_part(Vector3(0.4, 0.3, 0.4), Vector3(0, 1.75, 0), COLOR.darkened(0.4))
	_part(Vector3(0.1, 0.1, 0.8), Vector3(0.2, 1.3, -0.35), Color("1c1c1a"))  # rifle, pointing at you
	_part(Vector3(0.58, 0.14, 0.38), Vector3(0, 1.2, 0), LASER.darkened(0.1))  # red chest band: "enemy"
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
	return alert >= min_alert and alert <= max_alert


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
	visible = is_active(alert) or state == State.DOWN
	if not is_alive():
		return Shot.NONE
	var ahead := at - player_d
	if not is_active(alert) or ahead < 1.0 or ahead > tuning.trooper_aim_range:
		# Out of range, or you've run past him: he can't shoot behind him.
		if state == State.AIMING:
			_stop_aiming()
			state = State.IDLE
		return Shot.NONE
	_timer -= delta
	match state:
		State.IDLE:
			state = State.AIMING
			aimed_x = player_x
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
				var target: Vector3 = player_world + Vector3(0, 1.1, 0) if hit else route_point.call(player_d, aimed_x, 1.0)
				_flash_tracer(global_transform * Vector3(0.2, 1.3, -0.8), target)
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
	_body.scale = Vector3(1.15, 0.9, 1.15)
	create_tween().tween_property(_body, "scale", Vector3.ONE, 0.12)
	if health <= 0:
		knock_down()


func knock_down() -> void:
	if not is_alive():
		return
	state = State.DOWN
	_stop_aiming()
	knocked_down.emit()
	var tween := create_tween()
	tween.tween_property(_body, "rotation:x", -PI / 2.0, 0.3).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(_body, "position:y", 0.2, 0.3)


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


func _part(size: Vector3, pos: Vector3, color: Color) -> void:
	var m := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	m.mesh = mesh
	m.material_override = PsxMaterials.flat(color)
	m.position = pos
	_body.add_child(m)


## A box placed in world space (not moved by the trooper), hidden until used.
func _loose_box(size: Vector3, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	m.mesh = mesh
	m.material_override = PsxMaterials.flat(color)
	m.top_level = true
	m.visible = false
	add_child(m)
	return m
