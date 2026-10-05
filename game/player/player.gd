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
## His death (user: "a momentum ragdoll", slowed a little): it has played out (the end screen can
## open), and the moments the level plays a sound for ("down": he hits the ground).
signal died
signal death_beat(beat: String)
## Killed: his death's clock (s; slowed at first), how it started, whether he's down and whether
## it's over, and his pool of blood.
var dying := false
var _death_t := -1.0
var _death_from := {}
var _death_down := false
var _death_over := false
var _pool: MeshInstance3D


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


## The model's pose every frame (also before the run starts and after it ends, standing; dying,
## his death).
func _process(delta: float) -> void:
	if dying:
		_die_step(delta)
		return
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


## Killed (the run's already over): he goes limp mid-stride and his run carries him on, as far as
## the way ahead is clear (`free_ahead`, m: the barrier he hit, the dog, cover, a shut door), then
## down on his front in his blood (SoldierRig.pose_death); no room, knocked back onto his back;
## mid-slide, slumped back and skidding on (SoldierRig.fall_for). In the air, he comes down first.
func die(free_ahead: float) -> void:
	if dying:
		return
	dying = true
	aiming = false
	var moving := not (in_cover or standoff or halted or _stun_left > 0.0)
	var speed := tuning.run_speed * _speed_mul if moving else 0.0
	var fall := SoldierRig.fall_for(speed, free_ahead, is_sliding(), tuning)
	var travel: float = fall["travel"]
	var back: bool = fall["back"]
	var lift := jump_y
	jump_y = 0.0
	_y_velocity = 0.0
	_slide_left = 0.0
	_rig.position.y = 0.0
	_death_from = _rig.death_start({"travel": travel / SoldierRig.SIZE, "lift": lift / SoldierRig.SIZE, "room": free_ahead / SoldierRig.SIZE,
			"back": back, "slide": fall["slide"], "lean": _rig.rotation.z})
	_shadow.scale = Vector3.ONE
	_death_t = 0.0
	# The killing hit bursts out of his back (they shoot from ahead), and his blood will spread from
	# under his chest where he lands (behind his hips, on his back with his feet ahead).
	Blood.mist(self, Vector3(0.0, 1.3 + lift, 0.1), Vector3(0.0, 0.4, 1.0), 7)
	var chest_z := travel + 0.45 if back else (-travel + 0.45 if fall["slide"] else -travel - 0.55)
	_pool = Blood.pool_at(self, Vector3(0.0, 0.03, chest_z), tuning.death_pool, 11)
	Blood.set_spread(_pool, 0.0)


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


## His death, a frame on: slowed a little (user: about half speed at first, back to normal as he
## hits the ground), his blood spreading once he's down; then it's over (died).
func _die_step(delta: float) -> void:
	_rig.tick_flash(delta)
	var end := _rig.death_end()
	var land := _rig.death_land()
	if _death_t < end:
		var rate := lerpf(tuning.death_slow, 1.0, smoothstep(0.0, land, _death_t))
		_death_t = minf(_death_t + delta * rate, end)
		_rig.pose_death(_death_t, _death_from)
		if _shadow.visible:
			# His shadow goes with him as he's carried on.
			var at := to_local(_rig.global_transform * _rig._in_rig(_rig.hips).origin)
			_shadow.position = Vector3(at.x, 0.03, at.z)
		if not _death_down and _death_t >= land:
			_death_down = true
			_shadow.visible = false  # (his blood, not his shadow, under him now)
			death_beat.emit("down")
		Blood.set_spread(_pool, (_death_t - land) / maxf(end - land - 0.2, 0.1))
	elif not _death_over:
		_death_over = true
		died.emit()


## His death has played out.
func is_dead() -> bool:
	return _death_over


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
