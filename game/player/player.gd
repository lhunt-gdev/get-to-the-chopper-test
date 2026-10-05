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
## In cover: stopped, crouched, safe from shots ahead. Swipe left/right to leave.
var in_cover: bool = false
## Behind a box you crouch; behind a wall you stand.
var cover_crouch: bool = false
## Facing the boss at the chopper (user design): stopped at the standoff line; swipe left/right steps
## between lanes (you stay stopped), FIRE works, no jumping or sliding. Ends when he's down.
var standoff: bool = false
## Placeholder damage model (Point 4 OPEN): this many hits and you're down.
var hits_left: int = 3
var _invulnerable: float = 0.0
## Stumbling: stunned (no swipes) for a moment, then back up to speed.
var _stun_left: float = 0.0
var _speed_mul: float = 1.0
var _y_velocity: float = 0.0
var _slide_left: float = 0.0
var _shadow: MeshInstance3D
## The operative (user reference sheet): the rigged PS1-style model, posed from this state.
var _rig: SoldierRig
var _surrendered := false
## FIRE held: his right arm comes up and aims ahead (user). Set by the level.
var aiming := false


func _ready() -> void:
	lane = tuning.lane_count / 2
	track_x = lane_x(lane)
	hits_left = tuning.player_hits
	_rig = SoldierRig.new()
	add_child(_rig)
	_shadow = MeshInstance3D.new()
	_shadow.name = "Shadow"
	_shadow.mesh = PsxMaterials.shadow_mesh(Vector2(tuning.player_shadow_size, tuning.player_shadow_size * 0.8))
	_shadow.material_override = PsxMaterials.shadow(false, tuning)
	_shadow.position.y = 0.03
	add_child(_shadow)
	_update_visuals()


func _physics_process(delta: float) -> void:
	if not GameState.run_active or halted:
		return
	_invulnerable -= delta
	if _stun_left > 0.0:
		_stun_left -= delta
	else:
		_speed_mul = move_toward(_speed_mul, 1.0, delta * (1.0 - tuning.obstacle_slow_factor) / tuning.obstacle_slow_recover)
	if not in_cover and not standoff:
		distance += tuning.run_speed * _speed_mul * delta
	track_x = move_toward(track_x, lane_x(lane), tuning.lane_change_speed * delta)

	if is_airborne() or _y_velocity > 0.0:
		_y_velocity -= tuning.gravity * delta
		jump_y = maxf(0.0, jump_y + _y_velocity * delta)
		if jump_y == 0.0:
			_y_velocity = 0.0

	if _slide_left > 0.0:
		_slide_left -= delta
	_update_visuals()


## The model's pose every frame (also before the run starts and after it ends, standing).
func _process(delta: float) -> void:
	var running := GameState.run_active and not halted and not in_cover and not standoff
	_rig.animate(delta, {
		"run": _speed_mul if running else 0.0,
		"airborne": is_airborne(),
		"rising": _y_velocity > 0.0,
		"sliding": is_sliding(),
		"cover": ("crouch" if cover_crouch else "stand") if in_cover else "",
		"stun": _stun_left / tuning.obstacle_stun_time if _stun_left > 0.0 else 0.0,
		"lean": clampf((lane_x(lane) - track_x) / tuning.lane_width, -1.0, 1.0),
		"surrender": _surrendered,
		"aim": aiming and not _surrendered,
	})


func handle_swipe(dir: Vector2i) -> void:
	if halted or is_stunned():
		return
	if standoff:
		# Facing the boss: a step to the next lane, and nothing else.
		if dir.y == 0:
			lane = clampi(lane + dir.x, 0, tuning.lane_count - 1)
		return
	if in_cover:
		# Swiping away from the cover (sideways) leaves it and resumes the run. Nothing else does.
		var to := lane + (dir.x if dir.y == 0 else 0)
		if dir.y == 0 and to >= 0 and to < tuning.lane_count:
			in_cover = false
			lane = to
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


## The boss fight starts: stop at the standoff line (`stop_at`, route distance), up out of a slide.
## A jump you're in lands where you are (no new ones till he's down).
func enter_standoff(stop_at: float) -> void:
	standoff = true
	in_cover = false
	distance = minf(distance, stop_at)
	_slide_left = 0.0


## He's down: run on (to the chopper).
func end_standoff() -> void:
	standoff = false


## Ran into cover: stop just in front of it, and crouch if it's low (a box).
func enter_cover(stop_at: float, crouch: bool) -> void:
	in_cover = true
	cover_crouch = crouch
	distance = minf(distance, stop_at)
	jump_y = 0.0
	_y_velocity = 0.0
	_slide_left = 0.0


## Ran into a jump/slide obstacle: stunned for a moment (no swipes), slowed, then back up to
## speed. Any jump or slide in progress is cut short.
func stumble() -> void:
	_stun_left = tuning.obstacle_stun_time
	_speed_mul = tuning.obstacle_slow_factor
	_slide_left = 0.0
	jump_y = 0.0
	_y_velocity = 0.0


func is_stunned() -> bool:
	return _stun_left > 0.0


## Returns true if the hit landed (not while briefly invulnerable after the last one).
func take_hit() -> bool:
	if _invulnerable > 0.0 or hits_left <= 0:
		return false
	hits_left -= 1
	_invulnerable = tuning.hit_invulnerable_time
	_rig.flash()
	return true


## Captured: stop dead, drop to the ground and put both hands up.
func surrender() -> void:
	halted = true
	jump_y = 0.0
	_y_velocity = 0.0
	_slide_left = 0.0
	_surrendered = true
	_update_visuals()


## A shot: the pistol kicks.
func fire_recoil() -> void:
	_rig.recoil()


## Where shots leave his pistol (world space).
func muzzle_position() -> Vector3:
	return _rig.muzzle_position()


## The muzzle flash's light point (lit only while it shows), for the level's lighting.
func muzzle_light() -> Node3D:
	return _rig.muzzle_light()


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
	_rig.position.y = jump_y
	var t := clampf(jump_y / tuning.player_shadow_fade_height, 0.0, 1.0)
	_shadow.scale = Vector3.ONE * lerpf(1.0, tuning.player_shadow_min_scale, t)
