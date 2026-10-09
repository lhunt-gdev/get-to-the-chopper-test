class_name Boss
extends Node3D
## The boss (user design; he replaces the LOCKED roster's Heavy Trooper): the heavy-armoured man with
## the skull on his chest, waiting at the chopper with his minigun, the last thing between you and
## it, braced behind it (user: "a cool action ready stance"). When you come within the standoff
## distance the level stops your run; you can only step between lanes and fire. He spins up (the
## lanes he's about to sweep light up red on the floor: the telegraph), then sweeps across the lanes
## once, **always leaving 2 random lanes free** (user): the rounds fly out from the tip of his gun,
## so they spread out into a fan that builds up behind it as it turns, with gaps over the free lanes
## (he holds his fire over them) where it reaches you (user). A round that reaches you is a hit. The
## gun's flash lights him and the deck round him; the empty cases fly out of it and pile up round
## his feet (user). Then he spins down, and again with 2 new free lanes (a new pattern every run).
## He goes down after `boss_health` hits, and the way to the chopper is clear.
##
## The level places him (on the route's centre line at `at`), and calls update() every physics frame
## once the fight is on. Everything is in route space: `at` (distance along the route), lane x.

## His minigun's spinning up (the telegraph: the swept lanes are lit).
signal spinning_up
## The sweep has started.
signal sweeping
## Shot (not necessarily down).
signal wounded
## Down: the way to the chopper is clear (his KO replay follows).
signal defeated
## A moment of his death, each time it's shown (the level plays its sound): "hit" (each of the last
## hits), "let_go" (the minigun out of his hands), "gun_down" (it hits the deck), "body_down" (he does).
signal death_beat(beat: String)

enum State { WAITING, SPINUP, SWEEP, SPINDOWN, DOWN }

const MODEL := preload("res://game/enemies/boss/boss.glb")
## A little bigger than the guards.
const SCALE := 1.25
const DANGER := Color(1.0, 0.12, 0.08)
const TRACER := Color("ffc24a")
const TRACER_GLOW := Color(1.0, 0.55, 0.15, 0.9)
const BRASS := Color("c9a043")
## Where shots at him go (his chest, scaled up with him).
const CHEST := 1.65
## A round: a tracer's streak this long and thick (m), how far it flies on past you before it's gone,
## and how far rounds stray from where the gun's pointing (across, and up and down, m at your line).
const ROUND_LENGTH := 1.1
const ROUND_THICK := 0.08
## The glow round a round's head (m across: it always faces the camera).
const ROUND_GLOW := 0.4
const ROUND_PAST := 8.0
const ROUND_STRAY := Vector2(0.18, 0.25)
const MAX_ROUNDS := 48
## A case (a little bigger than life, so it reads at the standoff), and how many lie about at most.
const CASE_SIZE := Vector3(0.04, 0.04, 0.1)
const MAX_CASES := 150
const GRAVITY := 9.8
## Waiting, he holds his stance (and breathes) while the camera's this near (m).
const WATCH_RANGE := 60.0
## His death (see GuardRig.pose_death): how long it runs on its own clock (s; the blood has spread by
## then), its beats, and the pool (boss space, m: under his back where he lands, his head toward the
## chopper) and when it spreads.
const DEATH_END := GuardRig.DEATH_END
const DEATH_BEATS := [[0.0, "hit"], [0.08, "hit"], [0.08, "let_go"], [0.16, "hit"], [0.6, "gun_down"], [0.95, "body_down"]]
const POOL_AT := Vector3(0.15, 0.035, 2.35)
const POOL_RADIUS := 1.5
const POOL_FROM := 1.0
const POOL_TIME := 1.6
## Hidden multimesh instances (no size).
const GONE := Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)

var at: float = 0.0
var health: int = 30
## The hits he takes in all (the HUD's BOSS bar is health against this): Tuning's, or the setting's.
var max_health: int = 30
var state: State = State.WAITING
## This attack's two free lanes (lane indices, 0 = leftmost), and which way the sweep goes (+1 left
## to right, -1 right to left).
var free_lanes: Array[int] = []
var sweep_dir: int = 1
## Where the gun's pointing across the road at your line (lane x), during a sweep.
var stream_x: float = 0.0
## His minigun's roar (a loop the level gives him): playing only while the gun's firing.
var fire_sound: AudioStreamPlayer3D = null
## The flash's light (the level makes it a lamp): visible, and flickering, only while the gun fires.
var flash_lamp: Node3D
## His death's own clock (s since he was killed; -1 alive): it runs on (slowed with the game in the
## KO replay) and is wound back for each replay (replay_death).
var death_t := -1.0

var _rig: GuardRig
var _rng := RandomNumberGenerator.new()
## The rounds' stray and the cases' tumble (apart from _rng, so the pattern is the seed's alone).
var _fx_rng := RandomNumberGenerator.new()
var _timer := 0.0
var _lane_count := 5
var _lane_width := 1.4
var _spinup := [1.1, 0.9, 0.75]
var _sweep_time := 1.2
var _spindown_time := 1.2
var _fire_rate := 40.0
var _round_speed := 28.0
var _hit_radius := 0.4
## Which attack this is (rounds carry it), the last one whose rounds have hit you (once an attack at
## most), and where you were last frame.
var _attack := 0
var _attack_hit := -1
var _last_player_x := 0.0
## Rounds owed (a fraction of one left over from last frame: the gun fires 40 a second).
var _fire_debt := 0.0
## The run's over: he stays as he was left (no more standing to his stance).
var _stood_down := false
var _markers: Array[MeshInstance3D] = []
## Rounds in the air: {live, from, dir, travel (m from the muzzle), line (m to your line), x (lane x
## at your line), attack, checked}; a ring, the oldest reused.
var _rounds: Array[Dictionary] = []
var _round_next := 0
var _round_mm: MultiMesh
var _glow_mm: MultiMesh
## Cases: {pos, vel, axis, spin, angle, resting, bounces}; a ring, the oldest reused.
var _cases: Array[Dictionary] = []
var _case_next := 0
var _case_mm: MultiMesh
var _flying := 0
var _placed_bounds := false
var _shadow: MeshInstance3D
## How he stood as he was killed (GuardRig.death_start), the next beat to come, and his pool.
var _death_from := {}
var _beat := 0
var _pool: MeshInstance3D


func _init(tuning: Tuning) -> void:
	health = tuning.boss_health
	max_health = health
	_lane_count = tuning.lane_count
	_lane_width = tuning.lane_width
	_spinup = [tuning.boss_spinup_alert1, tuning.boss_spinup_alert2, tuning.boss_spinup_alert3]
	_sweep_time = tuning.boss_sweep_time
	_spindown_time = tuning.boss_spindown_time
	_fire_rate = tuning.boss_fire_rate
	_round_speed = tuning.boss_round_speed
	_hit_radius = tuning.boss_round_hit_radius
	var body := Node3D.new()
	body.scale = Vector3.ONE * SCALE
	add_child(body)
	_rig = GuardRig.new(GuardRifle.Kind.MINIGUN, MODEL, "BOSS")
	body.add_child(_rig)
	_rig.animate(0.0, _stance())
	_shadow = MeshInstance3D.new()
	_shadow.mesh = PsxMaterials.shadow_mesh(Vector2(1.4, 1.0))
	_shadow.material_override = PsxMaterials.shadow(false, tuning)
	_shadow.position.y = 0.03
	add_child(_shadow)
	# The swept lanes' red strips on the floor (placed in world space each frame).
	for i in _lane_count:
		_markers.append(_loose_box(Vector3(0.3, 0.02, 1.0), DANGER))
	# The rounds (tracers' streaks) and the cases: one draw each, every round and case an instance.
	var streak := BoxMesh.new()
	streak.size = Vector3(ROUND_THICK, ROUND_THICK, ROUND_LENGTH)
	_round_mm = _multimesh(streak, PsxMaterials.glow(TRACER), MAX_ROUNDS)
	var glow_quad := QuadMesh.new()
	glow_quad.size = Vector2.ONE * ROUND_GLOW
	var glow := PsxMaterials.halo(TRACER_GLOW).duplicate() as StandardMaterial3D
	glow.billboard_keep_scale = true  # (so a hidden one, no size, stays hidden)
	_glow_mm = _multimesh(glow_quad, glow, MAX_ROUNDS)
	for i in MAX_ROUNDS:
		_rounds.append({"live": false})
	var case_mesh := BoxMesh.new()
	case_mesh.size = CASE_SIZE
	_case_mm = _multimesh(case_mesh, PsxMaterials.flat(BRASS), MAX_CASES)
	for i in MAX_CASES:
		_cases.append({"live": false})
	flash_lamp = Node3D.new()
	flash_lamp.name = "FlashLamp"
	flash_lamp.top_level = true
	flash_lamp.visible = false
	add_child(flash_lamp)


## The mission's setting's boss (route.json "settings", user: "about 20, 30 and 40 hits"): how many
## hits he takes, and his spin-up at SNEAKING, CAUTION and ALERT (EASY's slower). Anything it
## doesn't say stays Tuning's. Before the fight.
func configure(setting_boss: Dictionary) -> void:
	if int(setting_boss.get("health", 0)) > 0:
		health = int(setting_boss["health"])
		max_health = health
	var spin = setting_boss.get("spinup")
	if spin is Array and spin.size() == 3:
		_spinup = [float(spin[0]), float(spin[1]), float(spin[2])]


func set_seed(s: int) -> void:
	_rng.seed = s
	_fx_rng.seed = s + 1


## Two different lanes out of `lane_count`, from two random numbers 0..1. Pure, unit-tested.
static func pick_free_lanes(a: float, b: float, lane_count: int) -> Array[int]:
	var first := clampi(int(a * lane_count), 0, lane_count - 1)
	var second := clampi(int(b * (lane_count - 1)), 0, lane_count - 2)
	if second >= first:
		second += 1
	return [first, second]


## Whether a round reaching your line at `x` hits you, as you moved from `p0` to `p1` this frame:
## the nearest you came to it, within `radius`. Pure, unit-tested.
static func round_hits(x: float, p0: float, p1: float, radius: float) -> bool:
	return absf(x - clampf(x, minf(p0, p1), maxf(p0, p1))) < radius


## Whether he fires a round that would reach your line at `x`: never into a free lane (he holds his
## fire over them, so their gaps in the fan are clean). Pure, unit-tested.
static func fires_at(x: float, free: Array[int], lane_width: float, lane_count: int) -> bool:
	return not free.has(lane_of(x, lane_width, lane_count))


## The lane (index) nearest x, across `lane_count` lanes `lane_width` wide.
static func lane_of(x: float, lane_width: float, lane_count: int) -> int:
	var mid := (lane_count - 1) / 2.0
	return clampi(roundi(x / lane_width + mid), 0, lane_count - 1)


static func spinup_for(alert: int, times: Array) -> float:
	return float(times[clampi(alert, 1, 3) - 1])


func is_alive() -> bool:
	return state != State.DOWN


## The fight's on (or over): he's a target from his first spin-up until he's down.
func is_targetable(_alert: int) -> bool:
	return is_alive() and state != State.WAITING


func get_threat_priority() -> int:
	return 200


func lane_x(lane: int) -> float:
	return (lane - (_lane_count - 1) / 2.0) * _lane_width


## Rounds in the air now (for the bots and tests).
func rounds_in_air() -> int:
	var n := 0
	for r in _rounds:
		if r["live"]:
			n += 1
	return n


## Cases fired so far that are still about (flying or on the deck).
func cases_out() -> int:
	var n := 0
	for c in _cases:
		if c["live"]:
			n += 1
	return n


## The fight starts (you've come within the standoff distance).
func begin(alert: int) -> void:
	if state == State.WAITING:
		_spin_up(alert)


## Waiting at the chopper (and while the rounds and cases still in the air after the fight come
## down): he holds his stance, the gun levelled at the way you'll come.
func _process(delta: float) -> void:
	if death_t >= 0.0 and death_t < DEATH_END:
		death_t = minf(death_t + delta, DEATH_END)
		_pose_death()
	if state == State.WAITING and not _stood_down and is_visible_in_tree():
		var cam := get_viewport().get_camera_3d()
		if cam != null and cam.global_position.distance_to(global_position) < WATCH_RANGE:
			_rig.animate(delta, _stance())
	if (state == State.WAITING or state == State.DOWN) and _flying > 0:
		_move_fx(delta, NAN)


## Every physics frame once the fight's on: player_d / player_x where you are, the alert, and
## route_point(d, x, y) -> world. Returns whether a round hit you this frame.
func update(delta: float, alert: int, player_d: float, player_x: float, route_point: Callable) -> bool:
	_timer -= delta
	match state:
		State.WAITING, State.DOWN:
			return false
		State.SPINUP:
			_show_markers(player_d, route_point, fmod(_timer, 0.24) > 0.08)
			var edge := lane_x(0 if sweep_dir > 0 else _lane_count - 1) - sweep_dir * _lane_width * 0.6
			_pose(delta, {"brace": true, "aim": true, "spin": 1.0, "target": route_point.call(player_d, edge, 1.0)})
			if _timer <= 0.0:
				state = State.SWEEP
				_timer = _sweep_time
				stream_x = -sweep_dir * _sweep_half()
				_fire_debt = 0.0
				sweeping.emit()
		State.SWEEP:
			_show_markers(player_d, route_point, true)
			# The gun turns from one side to the other (a little past each edge lane), firing except
			# over the free lanes.
			var t := clampf(1.0 - _timer / _sweep_time, 0.0, 1.0)
			var half := _sweep_half()
			stream_x = -sweep_dir * half + sweep_dir * 2.0 * half * t
			var firing := fires_at(stream_x, free_lanes, _lane_width, _lane_count)
			_pose(delta, {"brace": true, "aim": true, "spin": 1.0, "firing": firing, "target": route_point.call(player_d, stream_x, 1.0)})
			if firing and _rig.is_firing():
				_fire(delta, player_d, route_point)
			else:
				_fire_debt = 0.0
			_roar(firing)
			_show_flash(_rig.is_firing())
			if _timer <= 0.0:
				state = State.SPINDOWN
				_timer = _spindown_time
				_hide_fx()
		State.SPINDOWN:
			_pose(delta, {"brace": true, "aim": true, "spin": 0.0, "target": route_point.call(player_d, 0.0, 1.0)})
			if _timer <= 0.0:
				_spin_up(alert)
	var hit := _move_fx(delta, player_x)
	_last_player_x = player_x
	return hit


## Shot by the player.
func hit() -> void:
	if not is_alive():
		return
	health -= 1
	wounded.emit()
	_rig.flinch()
	Blood.mist(self, Vector3(0, CHEST, -0.3), Vector3(0, 1.0, -0.35), get_instance_id() + health)
	if health <= 0:
		state = State.DOWN
		_hide_fx()
		_death_from = _rig.death_start()
		death_t = 0.0
		_beat = 0
		_pool = Blood.pool_at(self, POOL_AT, POOL_RADIUS, get_instance_id())
		_pose_death()
		defeated.emit()


## Show his death again from `from_t` (s on its clock): a replay (the blood winds back with it).
func replay_death(from_t: float = 0.0) -> void:
	if death_t < 0.0:
		return
	death_t = clampf(from_t, 0.0, DEATH_END)
	_beat = 0
	while _beat < DEATH_BEATS.size() and float(DEATH_BEATS[_beat][0]) < death_t:
		_beat += 1
	_pose_death()


## Straight to the end of his death (the replay skipped): lying in his blood, the gun by him.
func finish_death() -> void:
	if death_t < 0.0:
		return
	death_t = DEATH_END
	_beat = DEATH_BEATS.size()
	_pose_death()


## His death's all worked out (its ragdoll), so its end can be shown at once.
func death_ready() -> bool:
	return _rig.death_baked()


## Where his hips are now (boss space): the KO replay's cameras follow him.
func body_point() -> Vector3:
	return to_local(_rig.hips.global_position)


func _pose_death() -> void:
	_rig.pose_death(death_t, _death_from)
	while _beat < DEATH_BEATS.size() and death_t >= float(DEATH_BEATS[_beat][0]):
		var beat: String = DEATH_BEATS[_beat][1]
		if beat == "hit":
			# Each hit bursts out of his back (the way the shot was going).
			Blood.mist(self, to_local(_rig.chest.global_position) + Vector3(0, 0.1, 0.1), Vector3(0.15, 0.45, 1.0), get_instance_id() + _beat)
		death_beat.emit(beat)
		_beat += 1
	_shadow.visible = death_t < GuardRig.DEATH_LIFT
	if _pool != null:
		Blood.set_spread(_pool, (death_t - POOL_FROM) / POOL_TIME)


## The run's over: his gun spins down, the lanes go dark (rounds already fired fly on out).
func stand_down() -> void:
	_hide_fx()
	if is_alive():
		state = State.WAITING
		_stood_down = true
		_rig.pose_to({"brace": true, "spin": 0.0}, 1.5)


## His stance waiting (the gun levelled 12 m ahead of him, at your chest).
func _stance() -> Dictionary:
	var s := {"brace": true, "aim": true, "spin": 0.0}
	if is_inside_tree():
		s["target"] = global_transform * Vector3(0, 1.0, -12.0)
	return s


## How far the gun turns each side of the middle (a little past each edge lane).
func _sweep_half() -> float:
	return (_lane_count / 2.0 + 0.3) * _lane_width


func _spin_up(alert: int) -> void:
	state = State.SPINUP
	_timer = spinup_for(alert, _spinup)
	free_lanes = pick_free_lanes(_rng.randf(), _rng.randf(), _lane_count)
	sweep_dir = 1 if _rng.randf() < 0.5 else -1
	_attack += 1
	spinning_up.emit()


func _pose(delta: float, s: Dictionary) -> void:
	if state == State.DOWN:
		return  # (he falls on his own)
	_rig.animate(delta, s)


## This frame's rounds (40 a second): each from the tip of the barrels toward your line where the gun
## is pointing (straying a little), and a case out of the side of the gun with each.
func _fire(delta: float, player_d: float, route_point: Callable) -> void:
	_fire_debt += delta * _fire_rate
	while _fire_debt >= 1.0:
		_fire_debt -= 1.0
		var x := stream_x + _fx_rng.randf_range(-ROUND_STRAY.x, ROUND_STRAY.x)
		if not fires_at(x, free_lanes, _lane_width, _lane_count):
			continue  # (none strays into a free lane)
		var from := _rig.muzzle_position()
		var to: Vector3 = route_point.call(player_d, x, 1.0 + _fx_rng.randf_range(-ROUND_STRAY.y, ROUND_STRAY.y))
		var line := from.distance_to(to)
		if line < 0.5:
			continue
		# Fired a moment ago, between frames (_move_fx then flies it on by this frame's step).
		var age := _fire_debt / _fire_rate
		var r := _rounds[_round_next]
		if not r["live"]:
			_flying += 1
		_rounds[_round_next] = {"live": true, "from": from, "dir": (to - from) / line, "line": line, "x": x,
				"travel": (age - delta) * _round_speed, "attack": _attack, "checked": false}
		_round_next = (_round_next + 1) % MAX_ROUNDS
		_eject_case()
	_place_bounds()


## A case out of the ejection port: flung out to his right, tumbling.
func _eject_case() -> void:
	var port := _rig.eject_port()
	if port == null or not port.is_inside_tree():
		return
	var xf := port.global_transform.orthonormalized()
	var out := xf.basis.x
	var vel := out * _fx_rng.randf_range(1.6, 2.6) + Vector3.UP * _fx_rng.randf_range(0.6, 1.5) \
			+ xf.basis.z * _fx_rng.randf_range(-0.3, 0.3)
	var axis := Vector3(_fx_rng.randf_range(-1, 1), _fx_rng.randf_range(-1, 1), _fx_rng.randf_range(-1, 1))
	if axis.length() < 0.1:
		axis = Vector3.RIGHT
	var c := _cases[_case_next]
	if not c["live"] or c["resting"]:
		_flying += 1
	_cases[_case_next] = {"live": true, "pos": xf.origin, "vel": vel, "axis": axis.normalized(),
			"spin": _fx_rng.randf_range(14.0, 30.0), "angle": _fx_rng.randf() * TAU, "resting": false, "bounces": 0}
	_case_next = (_case_next + 1) % MAX_CASES


## The rounds fly on and the cases fall (and bounce, and lie there). With `player_x` (not NAN), a
## round reaching your line near you hits you (once an attack): returns whether one did.
func _move_fx(delta: float, player_x: float) -> bool:
	var hit := false
	var checking := not is_nan(player_x)
	for i in MAX_ROUNDS:
		var r := _rounds[i]
		if not r["live"]:
			continue
		r["travel"] += _round_speed * delta
		var travel: float = r["travel"]
		var line: float = r["line"]
		if checking and not r["checked"] and travel >= line:
			r["checked"] = true
			if r["attack"] != _attack_hit and round_hits(r["x"], _last_player_x, player_x, _hit_radius):
				_attack_hit = r["attack"]
				hit = true
				r["live"] = false  # (into you)
		if r["live"] and travel > line + ROUND_PAST:
			r["live"] = false
		if not r["live"]:
			_flying -= 1
			_round_mm.set_instance_transform(i, GONE)
			_glow_mm.set_instance_transform(i, GONE)
			continue
		var length := clampf(travel, 0.0, ROUND_LENGTH)
		if length < 0.01:
			_round_mm.set_instance_transform(i, GONE)
			_glow_mm.set_instance_transform(i, GONE)
			continue
		var dir: Vector3 = r["dir"]
		var head: Vector3 = (r["from"] as Vector3) + dir * travel
		_round_mm.set_instance_transform(i, Transform3D(Basis.looking_at(dir) * Basis.from_scale(Vector3(1, 1, length / ROUND_LENGTH)),
				head - dir * length * 0.5))
		_glow_mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, head))
	var deck := global_position.y + CASE_SIZE.y * 0.5
	for i in MAX_CASES:
		var c := _cases[i]
		if not c["live"] or c["resting"]:
			continue
		var vel: Vector3 = c["vel"]
		vel.y -= GRAVITY * delta
		var pos: Vector3 = c["pos"] + vel * delta
		c["angle"] += c["spin"] * delta
		if pos.y <= deck and vel.y < 0.0:
			pos.y = deck
			c["bounces"] += 1
			if c["bounces"] >= 3 or absf(vel.y) < 0.6:
				# Down: lying on its side on the deck.
				c["resting"] = true
				c["pos"] = pos
				_flying -= 1
				_case_mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, c["angle"] as float), pos))
				continue
			vel = Vector3(vel.x * 0.5, -vel.y * 0.35, vel.z * 0.5)
			c["spin"] *= 0.6
		c["vel"] = vel
		c["pos"] = pos
		_case_mm.set_instance_transform(i, Transform3D(Basis(c["axis"] as Vector3, c["angle"] as float), pos))
	return hit


## The flash's light: on while the gun fires, just ahead of the barrels, flickering with the flash.
func _show_flash(on: bool) -> void:
	flash_lamp.visible = on
	if on:
		flash_lamp.global_position = _rig.muzzle_position() + Vector3.UP * 0.2
		flash_lamp.set_meta("power", _fx_rng.randf_range(0.55, 1.0))


## The red strips down the lanes he's about to sweep (not the free ones), from him to past you.
func _show_markers(player_d: float, route_point: Callable, on: bool) -> void:
	for i in _lane_count:
		var m := _markers[i]
		m.visible = on and not free_lanes.has(i)
		if m.visible:
			var a: Vector3 = route_point.call(player_d - 2.0, lane_x(i), 0.03)
			var b: Vector3 = route_point.call(at - 1.0, lane_x(i), 0.03)
			_stretch(m, a, b)


## The lanes go dark, the gun stops (its flash and roar); rounds already fired fly on.
func _hide_fx() -> void:
	for m in _markers:
		m.visible = false
	_roar(false)
	_show_flash(false)


func _roar(on: bool) -> void:
	if fire_sound == null or not is_instance_valid(fire_sound) or fire_sound.playing == on:
		return
	if on:
		fire_sound.play()
	else:
		fire_sound.stop()


## The rounds' and cases' bounds, round him (they're placed in world space), once he's in place.
func _place_bounds() -> void:
	if _placed_bounds or not is_inside_tree():
		return
	_placed_bounds = true
	var box := AABB(global_position - Vector3(40, 10, 40), Vector3(80, 20, 80))
	for mm in [_round_mm, _glow_mm, _case_mm]:
		mm.custom_aabb = box


## A thin box from `from` to `to` (world).
static func _stretch(m: MeshInstance3D, from: Vector3, to: Vector3) -> void:
	var l := from.distance_to(to)
	if l < 0.05:
		m.visible = false
		return
	m.global_transform = Transform3D(Basis.looking_at(to - from) * Basis.from_scale(Vector3(1, 1, l)), (from + to) / 2.0)


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


## A multimesh of `count` instances (all hidden till used), placed in world space.
func _multimesh(mesh: Mesh, mat: Material, count: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	for i in count:
		mm.set_instance_transform(i, GONE)
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.top_level = true
	add_child(mi)
	return mm
