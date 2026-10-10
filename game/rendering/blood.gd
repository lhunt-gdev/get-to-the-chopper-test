class_name Blood
extends RefCounted
## Blood effects, PS1-style: a mist of flecks when someone is shot, and a pool that spreads out
## under them when they go down. No particle systems or alpha fades: a few chunky flecks that fly
## and shrink away, and a dithered stain on the floor.
## The BLOOD setting (Settings "blood") off: none of them appear. Asked as each one would start, so
## switching it mid-run (the pause menu) counts from the next one; a pool already spreading goes on.

const POOL_SHADER := preload("res://assets/shaders/psx/psx_blood_pool.gdshader")
const MIST_COLORS := [Color("a0120e"), Color("7a0c0a"), Color("c41c14")]


## Whether blood shows (the BLOOD setting; on when there's no Settings autoload, as in a bare test).
## Looked up at run time rather than by name, so the classes using Blood still load without it.
static func enabled() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	var settings: Node = tree.root.get_node_or_null(^"Settings") if tree != null and tree.root != null else null
	return settings == null or bool(settings.call("get_value", "blood"))


## A burst of blood flecks at `pos` (in `parent`'s space), sprayed along `away` (the way the shot
## was going), then falling. Nothing with BLOOD off.
static func mist(parent: Node3D, pos: Vector3, away: Vector3, seed_value: int = 0) -> void:
	if not enabled():
		return
	var m := Mist.new(pos, away.normalized(), seed_value)
	parent.add_child(m)


## A pool of blood on the floor at `pos` (in `parent`'s space), spreading out to `radius` metres
## over `seconds`. It stays. Null (nothing) with BLOOD off.
static func pool(parent: Node3D, pos: Vector3, radius: float, seconds: float, seed_value: int = 0) -> MeshInstance3D:
	var m := pool_at(parent, pos, radius, seed_value)
	if m == null:
		return null
	var mat := m.material_override as ShaderMaterial
	var t := m.create_tween()
	t.tween_method(func(v: float) -> void: mat.set_shader_parameter("spread", v), 0.0, 1.0, seconds) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	return m


## The same pool, not spreading yet: its owner sets how far it has spread (set_spread), and can wind
## it back (a replay). Null (nothing) with BLOOD off.
static func pool_at(parent: Node3D, pos: Vector3, radius: float, seed_value: int = 0) -> MeshInstance3D:
	if not enabled():
		return null
	var m := MeshInstance3D.new()
	var quad := PlaneMesh.new()
	quad.size = Vector2(radius * 2.0, radius * 2.0)
	m.mesh = quad
	var mat := ShaderMaterial.new()
	mat.shader = POOL_SHADER
	mat.set_shader_parameter("spread", 0.0)
	mat.set_shader_parameter("seed", float(seed_value % 100) * 0.37)
	m.material_override = mat
	m.position = pos
	parent.add_child(m)
	return m


## How far a pool has spread, 0..1 (eased out as pool() does it). A null pool (BLOOD off) is skipped.
static func set_spread(pool_mesh: MeshInstance3D, v: float) -> void:
	if pool_mesh == null:
		return
	var e := 1.0 - (1.0 - clampf(v, 0.0, 1.0)) * (1.0 - clampf(v, 0.0, 1.0))
	(pool_mesh.material_override as ShaderMaterial).set_shader_parameter("spread", e)
	pool_mesh.visible = v > 0.0


## The flecks: each flies out along the spray with some scatter, drops under gravity and shrinks
## to nothing, then the burst frees itself.
class Mist extends Node3D:
	const LIFE := 0.55
	const GRAVITY := 9.0
	var _flecks: Array[MeshInstance3D] = []
	var _velocity: Array[Vector3] = []
	var _age := 0.0

	func _init(pos: Vector3, away: Vector3, seed_value: int) -> void:
		position = pos
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		for i in 18:
			var f := MeshInstance3D.new()
			var b := BoxMesh.new()
			b.size = Vector3.ONE * rng.randf_range(0.06, 0.12)  # chunky, to read at 270x480
			f.mesh = b
			f.material_override = PsxMaterials.glow(Blood.MIST_COLORS[i % Blood.MIST_COLORS.size()])
			add_child(f)
			_flecks.append(f)
			var scatter := Vector3(rng.randf_range(-1, 1) * 2.2, rng.randf_range(-0.3, 1), rng.randf_range(-1, 1)) * 1.2
			_velocity.append(away * rng.randf_range(1.5, 3.0) + scatter)

	func _process(delta: float) -> void:
		_age += delta
		if _age >= LIFE:
			queue_free()
			return
		var s := 1.0 - _age / LIFE
		for i in _flecks.size():
			_velocity[i].y -= GRAVITY * delta
			_flecks[i].position += _velocity[i] * delta
			_flecks[i].scale = Vector3.ONE * s
