class_name Ambience
extends Node
## MGS-style mood lighting: dark areas lit by the lamps you can see. Keeps every lamp in the level,
## and each frame hands the nearest ones (plus the area's ambient and moonlight) to the PS1 shader
## through global shader uniforms (see psx_lit.gdshader). Lamps flicker, beacons blink, and at
## high alert the lamps pulse red (MGS's ALERT phase).
##
## The shader has SLOTS lamp slots. They go to the lamps nearest a point FOCUS_AHEAD in front of the
## camera, but a lamp whose pool can't reach anything in view (behind the camera, or off to the
## side of the picture) comes after every lamp whose pool can: it lights nothing on screen, so a
## lamp ahead gets its slot instead, while it is still far off and dark, and brightens as you come
## nearer. With more lamps in view than slots, a lamp that gets a slot or loses one while you'd see
## its light fades in or out over EASE s instead of popping, and one holding a slot keeps it over a
## lamp only STICK m nearer for up to STICK_TIME s, so two lamps much the same way off don't take
## turns (and once it has been out of the nearest that long, the nearer one gets it: a still scene
## always ends up lit by the nearest, whatever came before).
##
## While the rear-view CCTV monitor is up (the Alert 3 chase), the same slots light its picture too,
## so a lamp whose pool reaches into its view counts as in view as well: the lamps behind you that it
## shows rank by their distance from the focus with the lamps ahead, as every lamp did before lamps
## out of view went last, and come on from dark like them. One only the monitor shows goes off at once
## when it loses its slot, so a lamp on the screen never waits for it to fade.
##
## Cheap on a phone: an update makes nothing new. Its lists are kept from one frame to the next (grown
## only when more lamps are in reach than ever before), the lamps are put in order by one native sort
## of plain numbers (_rank), and whether a lamp's pool reaches into a picture is a few sums (View).

const SLOTS := 12
const ALERT_RED := Color(1.0, 0.12, 0.08)
const CAUTION_AMBER := Color(1.0, 0.6, 0.2)
## How far in front of the camera the lamps nearest are counted from (m).
const FOCUS_AHEAD := 8.0
## How long a lamp's light takes to come on, or go off, when it gets or loses a slot in view (s).
const EASE := 0.3
## A lamp holding a slot keeps it over one less than STICK m nearer the focus, for up to STICK_TIME s
## out of the nearest (m, s).
const STICK := 1.0
const STICK_TIME := 0.25
## Less light than this (its distance fade, times how far it has come on) can't be seen come or go.
const UNSEEN := 0.02
## In one frame, the camera moving further than this (m) or turning further than CUT_TURN (the
## cosine of the angle) is a cut to another shot: the slots are just set, nothing eased.
const CUT_MOVE := 1.5
const CUT_TURN := 0.9
## A lamp out of view ranks this much further off (m): after every lamp in view.
const OUT_OF_VIEW := 1e6
## The ranking's numbers (_rank): a lamp's distance in steps of 1/RANK_STEPS m, times RANK_PLACES,
## plus its place in the list. So no more than RANK_PLACES lamps are ranked at once (a whole level
## has about a hundred; any more in reach at once are left out).
const RANK_STEPS := 1024.0
const RANK_PLACES := 4096

## The shader's names for each slot's lamp, made once for every update to use.
const POS_NAMES: Array[StringName] = [&"lamp_pos_0", &"lamp_pos_1", &"lamp_pos_2", &"lamp_pos_3",
		&"lamp_pos_4", &"lamp_pos_5", &"lamp_pos_6", &"lamp_pos_7", &"lamp_pos_8", &"lamp_pos_9",
		&"lamp_pos_10", &"lamp_pos_11", &"lamp_pos_12", &"lamp_pos_13"]
const COL_NAMES: Array[StringName] = [&"lamp_col_0", &"lamp_col_1", &"lamp_col_2", &"lamp_col_3",
		&"lamp_col_4", &"lamp_col_5", &"lamp_col_6", &"lamp_col_7", &"lamp_col_8", &"lamp_col_9",
		&"lamp_col_10", &"lamp_col_11", &"lamp_col_12", &"lamp_col_13"]

@export var tuning: Tuning

## {node, color, range, flicker, blink, alert, fixture, on_mat, off_mat, seed, ...}: every field an
## update writes is there from the start, so an update never adds one.
var _lamps: Array[Dictionary] = []
## This frame, what's lit in each slot (the 12 nearest, then the two of their own): the lamp's node
## (or null) and how lit it is.
var slot_nodes: Array = []
var slot_lit: Array[float] = []
## The lamps in reach this update: the first _near_n of _near, then the same in order, nearest the
## focus first (_ranked), and the ranking's numbers (_order: the first _order_used are in use, the
## rest INF). Kept from one update to the next, so none of them is made anew.
var _near: Array[Dictionary] = []
var _near_n := 0
var _ranked: Array[Dictionary] = []
var _order := PackedFloat64Array()
var _order_used := 0
## The lamps holding the SLOTS after the last update, nearest the focus first (the first _held_n;
## each one's "in": how far it has come on), and the list the next update fills (they swap).
var _held: Array[Dictionary] = []
var _held_n := 0
var _next: Array[Dictionary] = []
## What the camera sees, and the rear-view CCTV's camera while its monitor is up.
var _view := View.new()
var _rear_view := View.new()
## The camera last update (where it was, the way it looked), to tell a cut from a move.
var _eye := Vector3.INF
var _look := Vector3.ZERO
## The next update sets the slots at once (the first frame, a retry: snap()).
var _cut_next := true
var _tick := 0
var _amb := Color(1, 1, 1)
var _moon := Color(0, 0, 0)
var _moon_dir := Vector3.UP
var _target_amb := Color(1, 1, 1)
var _target_moon := Color(0, 0, 0)
var _target_moon_dir := Vector3.UP
var _time := 0.0
## 0 = calm, 1 = full ALERT (red pulse). Eases toward the alert level.
var _alert := 0.0
var _caution := 0.0
## BRIGHTNESS setting (1 = normal), on top of Tuning.brightness.
var brightness_scale := 1.0


## What a camera sees, as far as a lamp's pool goes: its place and axes, how far its picture's sides
## lean out (the tangents of half its view across and up), and its near and far planes. Set from the
## camera each update (a few numbers: nothing made). The same frustum as Camera3D.get_frustum().
class View:
	var eye := Vector3.ZERO
	var right := Vector3.RIGHT
	var up := Vector3.UP
	var back := Vector3.BACK
	var tan_x := 1.0
	var tan_y := 1.0
	## The tilted sides' slope lengths (sqrt(1 + tan²)): a distance from one, in metres, times this.
	var len_x := 1.0
	var len_y := 1.0
	var near := 0.05
	var far := 4000.0

	## From `camera` (a perspective one with its lens not offset, as every camera in the game is), its
	## picture as drawn.
	func aim(camera: Camera3D) -> void:
		var basis := camera.global_basis
		eye = camera.global_position
		right = basis.x.normalized()
		up = basis.y.normalized()
		back = basis.z.normalized()
		var size := camera.get_viewport().get_visible_rect().size
		var aspect := size.x / size.y if size.y > 0.0 and size.x > 0.0 else 1.0
		var t := tan(deg_to_rad(camera.fov) * 0.5)
		if camera.keep_aspect == Camera3D.KEEP_WIDTH:
			tan_x = t
			tan_y = t / aspect
		else:
			tan_y = t
			tan_x = t * aspect
		len_x = sqrt(1.0 + tan_x * tan_x)
		len_y = sqrt(1.0 + tan_y * tan_y)
		near = camera.near
		far = camera.far

	## Whether a pool of light `range_m` round `pos` reaches inside every side of the picture (it can
	## light something on screen).
	func reaches(pos: Vector3, range_m: float) -> bool:
		var rel := pos - eye
		var z := rel.dot(back)  # (in front of the lens, below 0)
		return z + near < range_m and -z - far < range_m \
				and absf(rel.dot(right)) + tan_x * z < range_m * len_x \
				and absf(rel.dot(up)) + tan_y * z < range_m * len_y


func _init() -> void:
	_held.resize(SLOTS)
	_next.resize(SLOTS)


## A lamp at `node` (it moves with it). range: how far its pool reaches. flicker 0..1: how often it
## stutters. blink > 0: on/off period in seconds (beacons). alert: pulses red at ALERT.
## fixture: the glowing mesh you see, swapped to off_mat while the lamp is off. own_slot: lit in a
## slot of its own, outside the nearest SLOTS (one lamp: his muzzle flash, so a shot never puts out
## a level lamp by taking its slot); lit while its node is visible. second_slot: the same, in a second
## slot of its own (the boss's muzzle flash, lit however far from the camera's focus). A node with a
## "power" meta (0..1) is lit that much, set by its owner every frame (a flash's flicker).
func add_lamp(node: Node3D, color: Color, range_m: float, opts: Dictionary = {}) -> void:
	var lamp := {"node": node, "color": color, "range": range_m, "flicker": opts.get("flicker", 0.0),
			"blink": opts.get("blink", 0.0), "alert": opts.get("alert", true), "fixture": opts.get("fixture", null),
			"on_mat": opts.get("on_mat", null), "off_mat": opts.get("off_mat", null),
			"seed": float(absi(hash(node.get_instance_id())) % 1000) / 37.0, "lit": 1.0,
			"own_slot": opts.get("own_slot", false), "second_slot": opts.get("second_slot", false),
			"held": false, "in": 1.0, "tick": -1, "out_t": 0.0,
			"pos": Vector3.ZERO, "dist": 0.0, "fade": 0.0, "seen": false, "shown": false, "key": 0.0, "want": false}
	_lamps.append(lamp)


## The area you're in: its ambient light, and moonlight (from `dir`) where there's open sky.
func set_area(ambient: Color, moon: Color, dir: Vector3) -> void:
	_target_amb = ambient
	_target_moon = moon
	_target_moon_dir = dir.normalized()


## Jump straight to the area's light (the first frame, a retry), the lamps too.
func snap() -> void:
	_amb = _target_amb
	_moon = _target_moon
	_moon_dir = _target_moon_dir
	_cut_next = true


func _process(delta: float) -> void:
	_time += delta


## camera: the one the picture is drawn with (the lamps nearest where it looks are the ones lit).
## rear: the rear-view CCTV's camera while its monitor is up (null when it isn't): a lamp whose pool
## reaches into its picture counts as in view too.
func update(delta: float, camera: Camera3D, alert_level: int, rear: Camera3D = null) -> void:
	var eye := camera.global_position
	var look := -camera.global_basis.z
	var focus := eye + look * FOCUS_AHEAD
	var cut := _cut_next or eye.distance_to(_eye) > CUT_MOVE or look.dot(_look) < CUT_TURN
	_cut_next = false
	_eye = eye
	_look = look
	_view.aim(camera)
	var with_rear := rear != null
	if with_rear:
		_rear_view.aim(rear)
	_tick += 1
	var k := clampf(delta * 1.5, 0.0, 1.0)
	_amb = _amb.lerp(_target_amb, k)
	_moon = _moon.lerp(_target_moon, k)
	_moon_dir = _moon_dir.lerp(_target_moon_dir, k).normalized()
	_alert = move_toward(_alert, 1.0 if alert_level >= 3 else 0.0, delta * 1.5)
	_caution = move_toward(_caution, 1.0 if alert_level == 2 else 0.0, delta * 1.5)
	var pulse := 0.5 + 0.5 * sin(_time * tuning.alert_pulse_speed)
	var b := tuning.brightness * brightness_scale
	var amb := _amb.lerp(_amb * Color(1.3, 0.65, 0.6), _alert * (0.3 + 0.4 * pulse)) * b
	RenderingServer.global_shader_parameter_set(&"amb_color", Vector4(amb.r, amb.g, amb.b, 1))
	RenderingServer.global_shader_parameter_set(&"moon_color", Vector4(_moon.r * b, _moon.g * b, _moon.b * b, 1))
	RenderingServer.global_shader_parameter_set(&"moon_dir", Vector4(_moon_dir.x, _moon_dir.y, _moon_dir.z, 0))

	var own_pos := Vector4.ZERO
	var own_col := Vector4.ZERO
	var second_pos := Vector4.ZERO
	var second_col := Vector4.ZERO
	if slot_nodes.size() != SLOTS + 2:
		slot_nodes.resize(SLOTS + 2)
		slot_lit.resize(SLOTS + 2)
	slot_nodes.fill(null)
	slot_lit.fill(0.0)
	var fade_far := tuning.lamp_fade_far
	_near_n = 0
	# Every lamp, the ones whose node has gone dropped in place as it goes (the list closes up behind).
	var kept := 0
	for i in _lamps.size():
		var l = _lamps[i]  # (untyped on purpose: a Dictionary-typed local in a loop gets a new empty one made every time round)
		if not is_instance_valid(l["node"]):
			continue
		if kept != i:
			_lamps[kept] = l
		kept += 1
		var node: Node3D = l["node"]
		if not node.is_inside_tree() or not node.is_visible_in_tree():  # e.g. walls rebuilt, the old ones on their way out
			continue
		if l["own_slot"]:
			var oc: Color = l["color"]
			var p: Vector3 = node.global_position
			own_pos = Vector4(p.x, p.y, p.z, l["range"])
			own_col = Vector4(oc.r * b, oc.g * b, oc.b * b, 1)
			slot_nodes[SLOTS] = node
			slot_lit[SLOTS] = 1.0
			continue
		if l["second_slot"]:
			var sc: Color = l["color"]
			var sp: Vector3 = node.global_position
			var se := _lit(l) * b
			second_pos = Vector4(sp.x, sp.y, sp.z, l["range"])
			second_col = Vector4(sc.r * se, sc.g * se, sc.b * se, 1)
			slot_nodes[SLOTS + 1] = node
			slot_lit[SLOTS + 1] = _lit(l)
			continue
		var lit := _lit(l)
		l["lit"] = lit
		var fixture = l["fixture"]
		if fixture != null and is_instance_valid(fixture) and l["on_mat"] != null:
			var mat: Material = l["on_mat"] if lit > 0.5 else l["off_mat"]
			if fixture.material_override != mat:
				fixture.material_override = mat
		var pos := node.global_position
		var dist := pos.distance_to(focus)
		var range_m: float = l["range"]
		l["pos"] = pos
		l["dist"] = dist
		if dist < fade_far + range_m and _near_n < RANK_PLACES:
			# Far lamps fade out (instead of popping) where the list cuts off, hidden in the fog.
			l["fade"] = clampf((fade_far - dist) / 10.0, 0.0, 1.0)
			var shown := _view.reaches(pos, range_m)
			var seen := shown or (with_rear and _rear_view.reaches(pos, range_m))
			l["shown"] = shown
			l["seen"] = seen
			l["key"] = dist if seen else dist + OUT_OF_VIEW
			l["tick"] = _tick
			if _near_n == _near.size():
				_grow(_near_n + 32)  # (more lamps in reach than ever before: once in a while)
			_near[_near_n] = l
			_near_n += 1
	if kept != _lamps.size():
		_lamps.resize(kept)
	# How long each lamp holding a slot has been out of the nearest; while that's under STICK_TIME it
	# keeps its slot over one less than STICK m nearer (not across a cut).
	_rank()
	for r in _near_n:
		var l = _ranked[r]
		var held: bool = l["held"]
		l["out_t"] = 0.0 if r < SLOTS or not held else float(l["out_t"]) + delta
		if held and l["out_t"] < STICK_TIME and not cut:
			l["key"] = float(l["key"]) - STICK
	_rank()
	for r in _near_n:
		_ranked[r]["want"] = r < SLOTS
	# The lamps that held a slot: kept if still wanted (coming on, if they were going off); off at
	# once if out of range, hidden or gone, or if nothing of their light on the screen could be seen
	# go (one only the rear monitor shows goes at once, so a lamp on the screen never waits for it);
	# otherwise going off, still holding their slot till they're out.
	var step := delta / EASE
	var n := 0
	for h in _held_n:
		var l = _held[h]
		if l["tick"] != _tick:
			l["held"] = false
		elif l["want"]:
			l["in"] = 1.0 if cut else minf(1.0, float(l["in"]) + step)
			_next[n] = l
			n += 1
		elif cut or not l["shown"] or float(l["fade"]) * float(l["in"]) <= UNSEEN:
			l["held"] = false
		else:
			l["in"] = float(l["in"]) - step
			if l["in"] > 0.0:
				_next[n] = l
				n += 1
			else:
				l["held"] = false
	# Then the wanted ones without a slot, nearest first, while there are slots free: coming on from
	# dark if you'd see it (on the screen or the rear monitor), at once if not (still too far off to
	# show, or its light out of view).
	for r in _near_n:
		var l = _ranked[r]
		if n >= SLOTS or not l["want"]:
			break
		if l["held"]:
			continue
		l["in"] = 0.0 if not cut and l["seen"] and float(l["fade"]) > UNSEEN else 1.0
		l["held"] = true
		_next[n] = l
		n += 1
	# Nearest first, as they always were: the shader adds them up in slot order, so the same lamps
	# light the picture to the last bit as before. (Twelve at most, nearly in order already: the
	# ones kept are, from the last update.)
	for i in range(1, n):
		var l = _next[i]
		var d: float = l["dist"]
		var j := i - 1
		while j >= 0 and float(_next[j]["dist"]) > d:
			_next[j + 1] = _next[j]
			j -= 1
		_next[j + 1] = l
	var was := _held
	_held = _next
	_next = was
	_held_n = n
	for i in SLOTS:
		var pos := Vector4.ZERO
		var col := Vector4.ZERO
		if i < n:
			var l = _held[i]
			var c: Color = l["color"]
			if l["alert"]:
				c = c.lerp(CAUTION_AMBER * c.get_luminance() * 1.3, _caution * 0.12)
				c = c.lerp(ALERT_RED * 1.3, _alert * (0.25 + 0.3 * pulse))
			var e: float = l["lit"] * l["fade"] * l["in"] * b
			var p: Vector3 = l["pos"]
			pos = Vector4(p.x, p.y, p.z, l["range"])
			col = Vector4(c.r * e, c.g * e, c.b * e, 1)
			slot_nodes[i] = l["node"]
			slot_lit[i] = e
		RenderingServer.global_shader_parameter_set(POS_NAMES[i], pos)
		RenderingServer.global_shader_parameter_set(COL_NAMES[i], col)
	RenderingServer.global_shader_parameter_set(POS_NAMES[SLOTS], own_pos)
	RenderingServer.global_shader_parameter_set(COL_NAMES[SLOTS], own_col)
	RenderingServer.global_shader_parameter_set(POS_NAMES[SLOTS + 1], second_pos)
	RenderingServer.global_shader_parameter_set(COL_NAMES[SLOTS + 1], second_col)


## How strongly the screen edges throb: x = ALERT red, y = CAUTION amber (both 0..1, pulsing).
func screen_alert() -> Vector2:
	var pulse := 0.5 + 0.5 * sin(_time * tuning.alert_pulse_speed)
	return Vector2(_alert * (0.35 + 0.65 * pulse), _caution * (0.6 + 0.4 * pulse))


## Puts the lamps in reach (the first _near_n of _near) in order of their key, nearest first, into
## _ranked. Each key (to a RANK_STEPS-th of a metre) and the lamp's place in _near are packed into one
## number, key steps x RANK_PLACES + place, so one native sort of plain numbers orders them (lamps the
## same to the step go by place), with nothing made new and no comparing done in script.
func _rank() -> void:
	for i in _near_n:
		_order[i] = floorf((float(_near[i]["key"]) + STICK) * RANK_STEPS) * RANK_PLACES + i  # (+ STICK: never below 0)
	for i in range(_near_n, _order_used):
		_order[i] = INF
	_order_used = _near_n
	_order.sort()
	for r in _near_n:
		_ranked[r] = _near[int(_order[r]) % RANK_PLACES]


## Room for `count` lamps in reach (the lists only ever grow, and seldom: a few times a run at most).
func _grow(count: int) -> void:
	var was := _order.size()
	_near.resize(count)
	_ranked.resize(count)
	_order.resize(count)
	for i in range(was, count):
		_order[i] = INF


## How lit a lamp is right now, 0..1: blinking beacons, and the odd stutter of a failing tube.
func _lit(l: Dictionary) -> float:
	var node: Node3D = l["node"]
	if node.has_meta(&"power"):
		return float(node.get_meta(&"power"))
	var t: float = _time + l["seed"]
	if l["blink"] > 0.0:
		return 1.0 if fmod(t, l["blink"]) < l["blink"] * 0.35 else 0.0
	if l["flicker"] > 0.0:
		# Mostly on; now and then a burst of quick flickers.
		var burst := sin(t * 0.7) * sin(t * 1.3 + 1.0)
		if burst > 1.0 - l["flicker"]:
			return 0.0 if fmod(t * 23.0, 1.0) < 0.5 else 0.6
	return 1.0
