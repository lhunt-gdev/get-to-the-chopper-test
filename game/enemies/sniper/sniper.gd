class_name Sniper
extends Node3D
## The Sniper (LOCKED roster: a timed movement threat with a laser telegraph, out of auto-target
## range, so you dodge him rather than shoot him; the design is the user's, see "The Sniper" in the
## decision log). Roofs only, CAUTION and ALERT only. He lies in a nest on top of a tall block on
## the next building over, ahead of you and out to one side. When you reach his spot his red laser
## comes on and follows you for a second; then it locks onto the lane you're in (brighter, blinking,
## a beep), and that's your window: change lane before he fires, or be in cover, and he misses. He
## fires once.
##
## The level places him (this node on the route's centre line where he starts, `at`), sets where
## his nest is (`nest`, in this node's space) and calls update() every physics frame. He isn't one
## of the level's combatants, so auto-aim never picks him.

## His laser's come on, following you.
signal tracking
## It's locked on: the window to dodge.
signal locked
## He's fired: hit or not, and where the shot went (world).
signal fired(hit: bool, where: Vector3)

enum State { WAITING, TRACKING, LOCKED, DONE }
enum Shot { NONE, MISSED, HIT }

const LASER := Color("ff2a2a")
## Locked on: a stronger red, thicker, and blinking.
const LASER_LOCKED := Color("ff4a30")
const BLINK := 0.09
## Reach your spot this far past where he'd start (a higher alert after you've passed), and he
## stays quiet: he only starts while he still has the stretch ahead of you.
const START_LATE := 6.0

## Route distance where he starts, on the centre line (absolute), and which side his nest is on.
var at: float = 0.0
var side: int = 1
## The lowest alert he's active at (user: CAUTION and up).
var min_alert: int = 2
## Where his nest is, in this node's space (its floor, facing back down the route).
var nest := Transform3D(Basis.IDENTITY, Vector3(15, 7, -55))
var state: State = State.WAITING
## Across the route (lane x, in his segment's lanes): where his laser is now, and where it locked.
var aim_x: float = 0.0
var locked_x: float = 0.0

var _timer: float = 0.0
var _window: float = 0.6
var _blink: float = 0.0
var _nest: Node3D
var _figure: Node3D
var _scope: Node3D
var _glint: MeshInstance3D
var _laser: MeshInstance3D
var _laser_locked: MeshInstance3D
var _dot: MeshInstance3D
var _tracer: MeshInstance3D
var _flash: MeshInstance3D
var _track_time := 1.0
var _follow_speed := 7.0
var _lane_width := 1.4
var _lane_count := 5
var _window_alert2 := 0.6
var _window_alert3 := 0.45


func _init(tuning: Tuning) -> void:
	_track_time = tuning.sniper_track_time
	_follow_speed = tuning.sniper_follow_speed
	_lane_width = tuning.lane_width
	_lane_count = tuning.lane_count
	_window_alert2 = tuning.sniper_window_alert2
	_window_alert3 = tuning.sniper_window_alert3
	_laser = _loose_box(Vector3(0.045, 0.045, 1.0), LASER)  # thin (user)
	_laser_locked = _loose_box(Vector3(0.08, 0.08, 1.0), LASER_LOCKED)
	_dot = _loose_box(Vector3(0.7, 0.03, 0.7), LASER)
	_tracer = _loose_box(Vector3(0.08, 0.08, 1.0), Color("ffe08a"))


func _ready() -> void:
	_build_nest()


## Whether his shot lands: still in the lane he locked onto, and not in cover. Pure, unit-tested.
static func shot_hits(player_x: float, locked_on_x: float, in_cover: bool, lane_width: float) -> bool:
	return not in_cover and absf(player_x - locked_on_x) < lane_width * 0.5


## The centre of the lane nearest x (lane x, in his segment's lanes), where the lock lands.
static func lane_centre(x: float, lane_width: float, lane_count: int) -> float:
	var mid := (lane_count - 1) / 2.0
	return (clampi(roundi(x / lane_width + mid), 0, lane_count - 1) - mid) * lane_width


## The window to dodge once he's locked on (s): shorter at ALERT (LOCKED: alert changes the
## pressure).
static func window_for(alert: int, at_alert2: float, at_alert3: float) -> float:
	return at_alert3 if alert >= 3 else at_alert2


func is_locked() -> bool:
	return state == State.LOCKED


func is_tracking() -> bool:
	return state == State.TRACKING


## Seconds until he fires (tracking and locked; INF otherwise).
func time_to_shot() -> float:
	match state:
		State.TRACKING:
			return _timer + _window
		State.LOCKED:
			return _timer
	return INF


## Every physics frame: player_d / player_x where you are (route distance, and across in this
## segment's lanes), in_cover, the alert, and route_point(d, x, y) -> world, for his laser.
func update(delta: float, alert: int, player_d: float, player_x: float, in_cover: bool, route_point: Callable) -> Shot:
	match state:
		State.WAITING:
			if player_d < at:
				return Shot.NONE
			if player_d > at + START_LATE or alert < min_alert:
				if player_d > at + START_LATE:
					state = State.DONE
				return Shot.NONE
			state = State.TRACKING
			_timer = _track_time
			_window = window_for(alert, _window_alert2, _window_alert3)
			aim_x = player_x
			tracking.emit()
		State.TRACKING:
			aim_x = move_toward(aim_x, player_x, _follow_speed * delta)
			_timer -= delta
			if _timer <= 0.0:
				state = State.LOCKED
				locked_x = lane_centre(aim_x, _lane_width, _lane_count)  # squarely on one lane
				_timer = _window
				_blink = 0.0
				locked.emit()
		State.LOCKED:
			_timer -= delta
			_blink += delta
			if _timer <= 0.0:
				var hit := shot_hits(player_x, locked_x, in_cover, _lane_width)
				var where: Vector3 = route_point.call(player_d, player_x, 1.1) if hit else route_point.call(player_d + 0.8, locked_x, 0.05)
				_fire(where)
				fired.emit(hit, where)
				return Shot.HIT if hit else Shot.MISSED
		State.DONE:
			return Shot.NONE
	_show_laser(route_point.call(player_d, aim_x if state == State.TRACKING else locked_x, 1.1),
			route_point.call(player_d + 0.6, aim_x if state == State.TRACKING else locked_x, 0.02))
	return Shot.NONE


## Off for good (the run's over, or the road he covers is gone).
func stand_down() -> void:
	state = State.DONE
	_hide_laser()


func scope_position() -> Vector3:
	return _scope.global_position if _scope != null and _scope.is_inside_tree() else global_position


# --- Looks --------------------------------------------------------------------------------------

## His nest: the top of a tall block on the next building over (it runs down out of sight), a low
## lip round it, and him lying on it with his rifle, its scope glinting red.
func _build_nest() -> void:
	_nest = Node3D.new()
	_nest.name = "Nest"
	add_child(_nest)
	_nest.transform = nest
	var concrete := Color("3a3d40")
	_part(_nest, Vector3(3.4, 22.0, 3.4), Vector3(0, -11.15, 0), concrete)
	_part(_nest, Vector3(3.6, 0.3, 3.6), Vector3(0, -0.15, 0), concrete.darkened(0.2))
	for lip: Array in [[Vector3(3.6, 0.35, 0.2), Vector3(0, 0.17, -1.7)], [Vector3(0.2, 0.35, 3.6), Vector3(-1.7, 0.17, 0)], [Vector3(0.2, 0.35, 3.6), Vector3(1.7, 0.17, 0)]]:
		_part(_nest, lip[0], lip[1], concrete.darkened(0.35))
	_figure = Node3D.new()
	_nest.add_child(_figure)
	_figure.position = Vector3(0, 0.05, 0.5)
	var drab := Color("4a4f45")
	_part(_figure, Vector3(0.5, 0.32, 1.5), Vector3(0, 0.16, 0.45), drab)  # lying flat, feet back
	_part(_figure, Vector3(0.3, 0.3, 0.3), Vector3(0, 0.3, -0.35), drab.darkened(0.3))  # head
	_part(_figure, Vector3(0.09, 0.09, 1.4), Vector3(0.12, 0.3, -0.9), Color("1c1c1a"))  # rifle
	_part(_figure, Vector3(0.11, 0.11, 0.32), Vector3(0.12, 0.42, -0.5), Color("101012"))  # scope
	_scope = Node3D.new()
	_figure.add_child(_scope)
	_scope.position = Vector3(0.12, 0.42, -0.68)
	_glint = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.8, 1.8)  # big enough to see where the laser comes from, far off
	_glint.mesh = quad
	var glint_mat: StandardMaterial3D = PsxMaterials.halo(Color(1.0, 0.3, 0.25, 0.9)).duplicate()
	glint_mat.billboard_keep_scale = true  # so it grows when he locks on (a copy: the halo's shared)
	_glint.material_override = glint_mat
	_scope.add_child(_glint)
	_glint.visible = false
	_flash = MeshInstance3D.new()
	var flash_quad := QuadMesh.new()
	flash_quad.size = Vector2(2.2, 2.2)
	_flash.mesh = flash_quad
	_flash.material_override = PsxMaterials.halo(Color(1.0, 0.85, 0.5, 1.0))
	_scope.add_child(_flash)
	_flash.position = Vector3(0, 0, -0.6)
	_flash.visible = false


## The laser from his scope to you (`to`), its dot on the road under the lane it's on (`dot`),
## him turned to aim along it, and the glint. Locked on: brighter, and blinking.
func _show_laser(to: Vector3, dot: Vector3) -> void:
	var from := scope_position()
	var lock := state == State.LOCKED
	var on := not lock or fmod(_blink, BLINK * 2.0) < BLINK
	_stretch(_laser, from, to, on and not lock)
	_stretch(_laser_locked, from, to, on and lock)
	_dot.global_position = dot
	_dot.visible = on
	_glint.visible = true
	_glint.scale = Vector3.ONE * (1.6 if lock else 1.0)
	var flat := Vector3(to.x, _figure.global_position.y, to.z)
	if flat.distance_to(_figure.global_position) > 0.5:
		_figure.look_at(flat, Vector3.UP)


func _hide_laser() -> void:
	for m in [_laser, _laser_locked, _dot]:
		m.visible = false
	if _glint != null:
		_glint.visible = false


## The shot: the laser goes out, a flash at his scope and the shot's streak to where it went.
func _fire(where: Vector3) -> void:
	state = State.DONE
	_hide_laser()
	var from := scope_position()
	_stretch(_tracer, from, where, true)
	_flash.visible = true
	get_tree().create_timer(0.07).timeout.connect(func() -> void:
		if is_instance_valid(self):
			_tracer.visible = false
			_flash.visible = false)


## A thin box from `from` to `to` (world), shown or hidden.
static func _stretch(m: MeshInstance3D, from: Vector3, to: Vector3, show: bool) -> void:
	var l := from.distance_to(to)
	m.visible = show and l > 0.05
	if m.visible:
		m.global_transform = Transform3D(Basis.looking_at(to - from) * Basis.from_scale(Vector3(1, 1, l)), (from + to) / 2.0)


func _part(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	m.mesh = mesh
	m.material_override = PsxMaterials.flat(color)
	m.position = pos
	parent.add_child(m)
	return m


## A glowing box placed in world space (not moved with him), hidden until used.
func _loose_box(size: Vector3, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	m.mesh = mesh
	m.material_override = PsxMaterials.glow(color)
	m.top_level = true
	m.visible = false
	add_child(m)
	return m
