class_name SecurityTrooper
extends Node3D
## The alarm runner (LOCKED roster: the Security Trooper, an alert specialist). He stands in a
## lane ahead, unarmed. When you come close he spots you (a "!"), turns and sprints off down the
## route ahead of you, a little faster than you run, for a couple of sections (user direction), to
## an alarm. Shoot him before he gets there; if he does, he slams the alarm and alert goes up one
## level. Letting him go is a valid choice (LOCKED). He weaves round walls and vaults low
## obstacles on the way, and he never shoots.
##
## He's the scout (user: "the alarm guard"), unarmed, a radio on his back with a blinking amber
## light (GuardRig without a rifle): he runs, vaults and slides as CROSS does, slams the panel with
## his hand, and falls on his face when he's shot down. The level calls update() every physics
## frame. Everything is in route space: `at` (distance along the route) and `x` (across it).

signal spotted
signal wounded
signal knocked_down
## He reached the alarm and raised it.
signal raised

enum State { IDLE, STARTLED, RUN, ALARM, DOWN }

const SCOUT := preload("res://game/enemies/scout/scout.glb")
const LASER := Color("ff2a2a")
const AMBER := Color("ffb347")
const SWERVE_SPEED := 6.0
## The last stretch (m) where he cuts across to the wall the alarm is on.
const TO_WALL := 8.0
## At the alarm, facing the wall: where his hand goes on the panel (his space: a little right of
## his middle, about the panel's height, the wall ~0.5 m in front of him).
const PANEL := Vector3(0.06, 1.65, -0.53)
## Where his blood pools once he's down: in front of him (he falls on his face, away from you).
const POOL_AT := Vector3(0, 0.035, -1.2)
## Down, how far on from where he was his body lies (feet to head).
const BODY_DOWN := 2.0
## The zone doors on his way (user: "when the alert guard is running, the big doors should open and
## close for him, so he doesn't just faze through them"; the level swings them: its _runner_gates).
## He shoves a door's leaves open this far (m) short of it, and they swing on away from him in
## DOOR_PUSH_TIME s, out of his way before he's at it; once he's clear of them they swing shut
## behind him (DOOR_SHUT_TIME s), well before you can get to them. A roller shutter starts rolling
## up for him further off (it's slower), and drops behind him as soon as he's under it, in
## SHUTTER_DOWN_TIME s: slow off the top, so it's still over his head as he comes out from under
## it, and down before it starts rolling up for you, 11 m out (the level's SHUTTER_OPEN_AHEAD).
## That can be only 0.3 s after he's at it: the least he's ever ahead of you is about 14 m (he
## spots you 40 m off, stands startled for a moment while you close in, then runs on to his alarm
## a little slower than you).
const DOOR_AHEAD := 2.4
const DOOR_PUSH_TIME := 0.22
const DOOR_SHUT_TIME := 0.6
const SHUTTER_AHEAD := 5.0
const SHUTTER_UP_TIME := 0.6
const SHUTTER_DOWN_TIME := 0.22

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
var _lane_x := 0.0
var _body: Node3D
var _rig: GuardRig
var _last_hop := 0.0
var _was_ducking := false
## His alarm panel's been built (the level builds it when he raises the alarm, or, if his stretch of
## route wasn't built then, once it is).
var panel_built := false
var _warn: Label3D
## A blinking amber light on his radio, so you can follow him down a dark corridor.
var _beacon: MeshInstance3D
## A zone door he's shoving open: where his right hand goes out flat onto it (world space; the level
## sets it as he comes up to one, see its _runner_gates), or null.
var push_at: Variant = null


func _init(tuning: Tuning) -> void:
	health = tuning.security_health
	_body = Node3D.new()
	add_child(_body)
	_rig = GuardRig.new(GuardRifle.Kind.CARBINE, SCOUT, "SCOUT", false)
	_body.add_child(_rig)
	# The radio on his back (on the carrier, between his shoulder blades, a little to his right), its
	# aerial, and its blinking amber light on top.
	var radio := Node3D.new()
	radio.name = "Radio"
	_rig.chest.add_child(radio)
	radio.position = Vector3(0.07, -0.14, 0.16)
	_part(radio, Vector3(0.11, 0.18, 0.06), Vector3.ZERO, Color("1c1c1a"))
	_part(radio, Vector3(0.015, 0.26, 0.015), Vector3(0.035, 0.21, 0.0), Color("1c1c1a"))
	_beacon = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.1, 0.06, 0.05)
	_beacon.mesh = bm
	_beacon.material_override = PsxMaterials.glow(AMBER)
	_beacon.position = Vector3(-0.01, 0.12, 0.01)
	radio.add_child(_beacon)
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


## Does he open a zone door at `door_at` now? On his way past it (his alarm's beyond it), and
## within `ahead` m of it. Pure rule, so it's unit-tested (like the two below).
static func opens_door(at: float, alarm_at: float, door_at: float, ahead: float) -> bool:
	return door_at > at and door_at - at <= ahead and alarm_at > door_at


## Is he in the way of a zone door at `door_at` (it mustn't shut on him)? His body (on his feet,
## about 0.35 m either side of where he is; down, face first away from you, from his feet to his
## head BODY_DOWN on) in the room its leaves swing through: from the door to `sweep` m on past
## it, over `half_w` m either side of the middle (beside the doorway, at an alarm on the wall,
## he's clear of it).
static func in_door_way(at: float, x: float, down: bool, door_at: float, sweep: float, half_w: float) -> bool:
	var front := at + (BODY_DOWN if down else 0.35)
	return front > door_at - 0.15 and at - 0.35 < door_at + sweep and absf(x) - 0.3 < half_w


## How long after he reaches a zone door (s) it's shut again behind him, running at `speed`: through
## and clear of its leaves (`sweep` m on), then shut.
static func door_shut_after(sweep: float, speed: float, shut_time: float) -> float:
	return (sweep + 0.35 + 0.15) / speed + shut_time


## How long after he reaches a roller shutter (s) it's down again behind him, running at `speed`:
## it starts down as soon as he's under it (his front at it, as in_door_way has it).
static func shutter_shut_after(speed: float) -> float:
	return SHUTTER_DOWN_TIME - (0.35 + 0.15) / speed


## How high (m) the bottom of a roller shutter dropping behind him still is as he comes out from
## under it, running at `speed`: it started down from `from_h` as he came under it, and he's under
## it until his back is `sweep` m past it (in_door_way's). Eased in, as the level drops it.
static func shutter_over_him(speed: float, from_h: float, sweep: float) -> float:
	var under := (0.35 + 0.15 + sweep + 0.35) / speed
	return from_h * cos(PI / 2.0 * minf(under / SHUTTER_DOWN_TIME, 1.0))


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
			_rig.animate(delta, {"run": 0.4})  # (a step into the turn)
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
			_rig.animate(delta, {"reach": global_transform * PANEL})  # his hand on it
			_beacon.visible = fmod(Time.get_ticks_msec() / 1000.0, 0.5) < 0.3
		return
	var hop := _hop(lows)
	_put(place, hop)
	_beacon.visible = fmod(Time.get_ticks_msec() / 1000.0, 0.5) < 0.3
	# A sprint (as CROSS runs), up over what he vaults, down under what he slides under; at a zone
	# door, his hand out to shove it open.
	var pose := {"run": 1.0, "airborne": hop > 0.05, "rising": hop > _last_hop, "duck": _ducking(highs)}
	if push_at != null:
		pose["reach"] = push_at
	_rig.animate(delta, pose)
	_last_hop = hop
	_was_ducking = _ducking(highs)


## The run's over (nothing updates him any more): if he was running, he slows to a stand.
func stand_down() -> void:
	if is_running():
		if top_level and _last_hop > 0.0:
			global_position.y -= _last_hop  # mid-vault: back on the floor
			_last_hop = 0.0
		_rig.pose_to({"duck": true} if _was_ducking else {}, 0.6)  # (still under a pipe: stays down)


## Shot by the player.
func hit() -> void:
	if not is_alive():
		return
	health -= 1
	wounded.emit()
	_rig.flinch()
	Blood.mist(self, Vector3(0, RifleTrooper.CHEST, 0.25), Vector3(0, 1.0, 0.35), get_instance_id() + health)
	if health <= 0:
		knock_down()


func knock_down() -> void:
	if not is_alive():
		return
	if state == State.ALARM:
		# At the panel he faces the wall: turned back down the route first, so he falls along the
		# wall, not into it.
		rotate_object_local(Vector3.UP, signf(wall_x) * PI / 2.0)
	state = State.DOWN
	_warn.visible = false
	_beacon.visible = false  # (down: no light to follow)
	if top_level and _last_hop > 0.0:
		global_position.y -= _last_hop  # shot mid-vault: he comes down where he is
		_last_hop = 0.0
	knocked_down.emit()
	# Shot in the back as he runs: he goes down on his face, away from you.
	_rig.fall()
	var tween := create_tween()
	tween.tween_interval(GuardRig.FALL_TIME)
	tween.tween_callback(func() -> void: Blood.pool(self, POOL_AT, 1.2, 2.2, get_instance_id()))


## At the alarm: he slaps it, then stays there with his hand on it (posed in update()).
func _slam() -> void:
	_warn.text = "!!"
	_warn.modulate = LASER
	_warn.visible = true
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
