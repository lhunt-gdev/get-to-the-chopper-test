class_name Casings
extends SubViewportContainer
## Spent casings (the decision log's "Spent casings from the trigger"; a try-out): each shot throws a
## spent pistol casing out from behind the FIRE trigger, up and in toward the middle of the screen,
## tumbling end over end, then gravity has it and it falls off the bottom of the screen, where it
## "lands" (a faint tink: the level plays it). Drawn over the game on the HUD, under the trigger, so
## it comes out from behind it.
##
## A small 3D model (mesh(): an 8-sided brass case, its rim, its groove and its slightly narrower
## mouth, 60 triangles; PsxTextures.casing; the PS1 look of psx_casing) in a see-through SubViewport
## of its own, the screen's size, with its own world and an orthographic camera one unit to a pixel:
## so a point on screen (x, y) is (x, -y) in there. It only draws while a casing is in the air; the
## rest of the time it's hidden and its viewport isn't drawn at all. A pool of CAP; a shot while all
## of them are in the air throws none.

## A casing came off the bottom of the screen (as if it hit the floor down there).
signal landed

const SHADER := preload("res://assets/shaders/psx/psx_casing.gdshader")
## The most in the air at once (FIRE held, a shot every fire_interval, has 3 or 4 up).
const CAP := 8
## Pixels to one unit of the model (it's 2 across and 3.8 long: about 6 x 11 px on the 270-wide screen).
const PX := 2.8
## Where one comes from: up from the trigger's middle by this much of its radius (under the top of
## the guard, out of sight until it flies).
const FROM_UP := 0.62
## How it flies (px, s): its kick up and in toward the middle, gravity, its tumble (radians a second,
## end over end) and its slower roll about its length.
const KICK_UP := Vector2(250.0, 320.0)
const KICK_IN := Vector2(50.0, 110.0)
const GRAVITY := 1100.0
const TUMBLE := Vector2(14.0, 22.0)
const ROLL := Vector2(-4.0, 4.0)
## How far past the bottom edge it counts as gone (px: all of it off the screen).
const GONE_BELOW := 8.0
## However it flies, gone after this long (s).
const MAX_LIFE := 3.0

## The profile, base to mouth: (height, radius) of each ring (the rim, the groove's step, the case
## tapering a little to its mouth), and the side's texture rows (v) at each.
const RINGS := [Vector2(0.0, 1.0), Vector2(0.28, 1.0), Vector2(0.4, 0.9), Vector2(3.8, 0.86)]
const RING_V := [1.0, 14.0 / 16.0, 13.0 / 16.0, 0.0]
const SIDES := 8
const LENGTH := 3.8

static var _mesh: ArrayMesh
static var _material: ShaderMaterial

var _view: SubViewport
var _camera: Camera3D
## The pool: a MeshInstance3D each, and what each one in the air is doing ({on, at, vel, axis,
## tumble, roll, age}).
var _shells: Array[MeshInstance3D] = []
var _state: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
## Hidden and still (the pause menu): the casings in the air wait, unseen, for the run to go on.
var suspended := false:
	set(on):
		suspended = on
		_refresh()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stretch = true
	_rng.randomize()
	_view = SubViewport.new()
	_view.transparent_bg = true
	_view.own_world_3d = true
	_view.positional_shadow_atlas_size = 0
	_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_view)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.near = 1.0
	_camera.far = 60.0
	_view.add_child(_camera)
	for i in CAP:
		var m := MeshInstance3D.new()
		m.mesh = mesh()
		m.material_override = material()
		m.scale = Vector3.ONE * PX
		m.visible = false
		_view.add_child(m)
		_shells.append(m)
		_state.append({"on": false})
	visible = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_place_camera)
	_place_camera()


## The camera over the screen: one unit to a pixel, (x, -y) the point (x, y) on it.
func _place_camera() -> void:
	var s := size if size.y > 0.0 else get_viewport_rect().size
	_camera.size = s.y
	_camera.position = Vector3(s.x * 0.5, -s.y * 0.5, 30.0)


## A shot: a casing out from behind the trigger at `trigger` (SwipeInput.fire_button: x, y, radius),
## thrown toward the middle of the screen. None if CAP are in the air already.
func eject(trigger: Vector3) -> void:
	var i := -1
	for k in CAP:
		if not _state[k]["on"]:
			i = k
			break
	if i < 0:
		return
	var screen := size if size.y > 0.0 else get_viewport_rect().size
	var inward := -1.0 if trigger.x > screen.x * 0.5 else 1.0
	var at := Vector2(trigger.x, trigger.y - trigger.z * FROM_UP)
	var vel := Vector2(inward * _rng.randf_range(KICK_IN.x, KICK_IN.y), -_rng.randf_range(KICK_UP.x, KICK_UP.y))
	# End over end, the way it's thrown (its top going in), on an axis tipped a little off the
	# screen's, so it shows its base and its mouth now and then.
	var axis := Vector3(_rng.randf_range(-0.35, 0.35), _rng.randf_range(-0.35, 0.35), 1.0).normalized()
	_state[i] = {"on": true, "at": at, "vel": vel, "axis": axis, "age": 0.0,
			"tumble": -inward * _rng.randf_range(TUMBLE.x, TUMBLE.y), "roll": _rng.randf_range(ROLL.x, ROLL.y)}
	var m := _shells[i]
	# Lying about level as it comes out (thrown sideways from the gun), at a little random angle.
	m.basis = Basis(Vector3.FORWARD, PI * 0.5 + _rng.randf_range(-0.5, 0.5)) * Basis(Vector3.UP, _rng.randf_range(0.0, TAU))
	m.scale = Vector3.ONE * PX
	m.position = Vector3(at.x, -at.y, 0.0)
	m.visible = true
	_refresh()


## Every casing gone at once (the run's over, the KO replay, the menus), with no tink.
func clear() -> void:
	for i in CAP:
		_state[i] = {"on": false}
		_shells[i].visible = false
	_refresh()


## How many are in the air.
func alive() -> int:
	var n := 0
	for s in _state:
		if s["on"]:
			n += 1
	return n


## Where each one in the air is on the screen (px), for the tests.
func positions() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for s in _state:
		if s["on"]:
			out.append(s["at"])
	return out


func _process(delta: float) -> void:
	if alive() == 0:
		return
	var bottom := (size.y if size.y > 0.0 else get_viewport_rect().size.y) + GONE_BELOW
	for i in CAP:
		var s := _state[i]
		if not s["on"]:
			continue
		var vel: Vector2 = s["vel"]
		vel.y += GRAVITY * delta
		var at: Vector2 = s["at"] + vel * delta
		s["vel"] = vel
		s["at"] = at
		s["age"] = float(s["age"]) + delta
		var m := _shells[i]
		m.position = Vector3(at.x, -at.y, 0.0)
		m.basis = (Basis(s["axis"], float(s["tumble"]) * delta) * m.basis * Basis(Vector3.UP, float(s["roll"]) * delta)).orthonormalized()
		m.scale = Vector3.ONE * PX
		if at.y > bottom or float(s["age"]) > MAX_LIFE:
			_state[i] = {"on": false}
			m.visible = false
			if at.y > bottom:
				landed.emit()
	_refresh()


## Shown (and its viewport drawn) only while one's in the air, and not under the pause menu.
func _refresh() -> void:
	var on := not suspended and alive() > 0
	visible = on
	if _view:
		_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED


## The casing's model, made the first time: 60 triangles round its length (y, the base at
## -LENGTH / 2), 2 across.
static func mesh() -> ArrayMesh:
	if _mesh != null:
		return _mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := LENGTH * 0.5
	var side_u := float(PsxTextures.CASING_SIDE.size.x) / 32.0
	for b in RINGS.size() - 1:
		var lo: Vector2 = RINGS[b]
		var hi: Vector2 = RINGS[b + 1]
		var d := hi - lo
		for i in SIDES:
			var a0 := TAU * i / SIDES
			var a1 := TAU * (i + 1) / SIDES
			var ring := func(a: float, r: Vector2) -> Vector3: return Vector3(cos(a) * r.y, r.x - half, sin(a) * r.y)
			# Smooth round it, flat along each band (its slope: the groove's step faces up and out).
			var nrm := func(a: float) -> Vector3: return Vector3(cos(a) * d.x, -d.y, sin(a) * d.x).normalized()
			var p := [ring.call(a0, lo), ring.call(a1, lo), ring.call(a1, hi), ring.call(a0, hi)]
			var n := [nrm.call(a0), nrm.call(a1), nrm.call(a1), nrm.call(a0)]
			var uv := [Vector2(side_u * i / SIDES, RING_V[b]), Vector2(side_u * (i + 1) / SIDES, RING_V[b]),
					Vector2(side_u * (i + 1) / SIDES, RING_V[b + 1]), Vector2(side_u * i / SIDES, RING_V[b + 1])]
			_tri(st, [p[0], p[1], p[2]], [n[0], n[1], n[2]], [uv[0], uv[1], uv[2]], (n[0] + n[1]) * 0.5)
			_tri(st, [p[0], p[2], p[3]], [n[0], n[2], n[3]], [uv[0], uv[2], uv[3]], (n[0] + n[1]) * 0.5)
	# The base (the primer in its middle) and the mouth, each an octagon of 6 triangles.
	for top in [false, true]:
		var r: Vector2 = RINGS[-1] if top else RINGS[0]
		var rect: Rect2i = PsxTextures.CASING_MOUTH if top else PsxTextures.CASING_BASE
		var c := Vector2(rect.position) + Vector2(rect.size) * 0.5
		var n := Vector3.UP if top else Vector3.DOWN
		var pts: Array[Vector3] = []
		var uvs: Array[Vector2] = []
		for i in SIDES:
			var a := TAU * i / SIDES
			pts.append(Vector3(cos(a) * r.y, r.x - half, sin(a) * r.y))
			uvs.append((c + Vector2(cos(a), sin(a)) * rect.size.x * 0.48) / Vector2(32.0, 16.0))
		for i in range(1, SIDES - 1):
			_tri(st, [pts[0], pts[i], pts[i + 1]], [n, n, n], [uvs[0], uvs[i], uvs[i + 1]], n)
	_mesh = st.commit()
	return _mesh


## One triangle, wound to face `out` (the engine's front faces are clockwise).
static func _tri(st: SurfaceTool, p: Array, n: Array, uv: Array, out: Vector3) -> void:
	var order := [0, 1, 2]
	if (p[1] - p[0]).cross(p[2] - p[0]).dot(out) > 0.0:
		order = [0, 2, 1]
	for k in order:
		st.set_normal(n[k])
		st.set_uv(uv[k])
		st.add_vertex(p[k])


## The casings' material (the PS1 look of psx_casing, PsxTextures.casing), made the first time.
static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
		_material.set_shader_parameter("albedo_texture", PsxTextures.casing())
	return _material
