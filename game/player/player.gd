class_name Player
extends Node3D
## Auto-runs along the route. Swipes change lane, jump or slide.
## LOCKED Controls v1: no analogue stick, no manual camera.
##
## All movement is in route space: distance along the route, track_x across it, jump_y above
## the ground. The level places this node on the route (which can turn and climb) every frame.

@export var tuning: Tuning

var lane: int = 0
var distance: float = 0.0
var track_x: float = 0.0
var jump_y: float = 0.0
## Set when captured: stops running and ignores input.
var halted: bool = false
var _y_velocity: float = 0.0
var _slide_left: float = 0.0
var _shadow: MeshInstance3D
var _arms: Array[MeshInstance3D] = []

@onready var _body: MeshInstance3D = $Body


func _ready() -> void:
	lane = tuning.lane_count / 2
	track_x = lane_x(lane)
	var skin := PsxMaterials.flat(Color("5b6b3a"))
	_body.material_override = skin
	_shadow = MeshInstance3D.new()
	_shadow.name = "Shadow"
	_shadow.mesh = PsxMaterials.shadow_mesh(Vector2(tuning.player_shadow_size, tuning.player_shadow_size * 0.8))
	_shadow.material_override = PsxMaterials.shadow(false, tuning)
	_shadow.position.y = 0.03
	add_child(_shadow)
	# Raised arms for the hands-up pose, hidden until captured.
	for side in [-1, 1]:
		var arm := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.14, 0.6, 0.14)
		arm.mesh = mesh
		arm.material_override = skin
		arm.position = Vector3(side * 0.32, 1.85, 0)
		arm.visible = false
		add_child(arm)
		_arms.append(arm)
	_update_visuals()


func _physics_process(delta: float) -> void:
	if not GameState.run_active or halted:
		return
	distance += tuning.run_speed * delta
	track_x = move_toward(track_x, lane_x(lane), tuning.lane_change_speed * delta)

	if is_airborne() or _y_velocity > 0.0:
		_y_velocity -= tuning.gravity * delta
		jump_y = maxf(0.0, jump_y + _y_velocity * delta)
		if jump_y == 0.0:
			_y_velocity = 0.0

	if _slide_left > 0.0:
		_slide_left -= delta
	var target_scale := 0.45 if is_sliding() else 1.0
	_body.scale.y = move_toward(_body.scale.y, target_scale, delta * 10.0)
	_update_visuals()


func handle_swipe(dir: Vector2i) -> void:
	if halted:
		return
	match dir:
		Vector2i.LEFT:
			lane = clampi(lane - 1, 0, tuning.lane_count - 1)
		Vector2i.RIGHT:
			lane = clampi(lane + 1, 0, tuning.lane_count - 1)
		Vector2i.UP:
			if not is_airborne():
				_slide_left = 0.0
				_y_velocity = tuning.jump_velocity
		Vector2i.DOWN:
			_slide_left = tuning.slide_duration
			if is_airborne():
				_y_velocity = minf(_y_velocity, -tuning.jump_velocity)  # fast-fall into the slide


## Captured: stop dead, drop to the ground and put both hands up.
func surrender() -> void:
	halted = true
	jump_y = 0.0
	_y_velocity = 0.0
	_slide_left = 0.0
	_body.scale.y = 1.0
	for arm in _arms:
		arm.visible = true
	_update_visuals()


## Entering a side branch renumbers the lanes under you (you stay where you are in the world).
func shift_lanes(by: int) -> void:
	lane = clampi(lane + by, 0, tuning.lane_count - 1)
	track_x = clampf(track_x + by * tuning.lane_width, lane_x(0), lane_x(tuning.lane_count - 1))


func lane_x(i: int) -> float:
	return (i - (tuning.lane_count - 1) / 2.0) * tuning.lane_width


func is_airborne() -> bool:
	return jump_y > 0.001


func clears_low_obstacle() -> bool:
	return jump_y >= tuning.jump_clear_height


func is_sliding() -> bool:
	return _slide_left > 0.0 and not is_airborne()


func distance_run() -> float:
	return distance


## The body rises with the jump; the shadow stays on the ground and shrinks, so jump height is readable.
func _update_visuals() -> void:
	_body.position.y = 0.8 * _body.scale.y + jump_y
	var t := clampf(jump_y / tuning.player_shadow_fade_height, 0.0, 1.0)
	_shadow.scale = Vector3.ONE * lerpf(1.0, tuning.player_shadow_min_scale, t)
