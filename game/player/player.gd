class_name Player
extends Node3D
## Auto-runs away from the camera (along -Z). Swipes change lane, jump or slide.
## LOCKED Controls v1: no analogue stick, no manual camera.

@export var tuning: Tuning

var lane: int = 0
var _y_velocity: float = 0.0
var _slide_left: float = 0.0

@onready var _body: MeshInstance3D = $Body


func _ready() -> void:
	lane = tuning.lane_count / 2
	position.x = lane_x(lane)
	_body.material_override = PsxMaterials.flat(Color("5b6b3a"))


func _physics_process(delta: float) -> void:
	if not GameState.run_active:
		return
	position.z -= tuning.run_speed * delta
	position.x = move_toward(position.x, lane_x(lane), tuning.lane_change_speed * delta)

	if is_airborne() or _y_velocity > 0.0:
		_y_velocity -= tuning.gravity * delta
		position.y = maxf(0.0, position.y + _y_velocity * delta)
		if position.y == 0.0:
			_y_velocity = 0.0

	if _slide_left > 0.0:
		_slide_left -= delta
	var target_scale := 0.45 if is_sliding() else 1.0
	_body.scale.y = move_toward(_body.scale.y, target_scale, delta * 10.0)
	_body.position.y = 0.8 * _body.scale.y


func handle_swipe(dir: Vector2i) -> void:
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


func lane_x(i: int) -> float:
	return (i - (tuning.lane_count - 1) / 2.0) * tuning.lane_width


func is_airborne() -> bool:
	return position.y > 0.001


func clears_low_obstacle() -> bool:
	return position.y >= tuning.jump_clear_height


func is_sliding() -> bool:
	return _slide_left > 0.0 and not is_airborne()


func distance_run() -> float:
	return -position.z
