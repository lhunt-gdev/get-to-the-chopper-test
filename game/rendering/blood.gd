class_name Blood
extends RefCounted
## Blood effects, PS1-style: a mist of flecks when someone is shot, and a pool that spreads out
## under them when they go down. No particle systems or alpha fades: a few chunky flecks that fly
## and shrink away, and a dithered stain on the floor.

const POOL_SHADER := preload("res://assets/shaders/psx/psx_blood_pool.gdshader")
const MIST_COLORS := [Color("a0120e"), Color("7a0c0a"), Color("c41c14")]


## A burst of blood flecks at `pos` (in `parent`'s space), sprayed along `away` (the way the shot
## was going), then falling.
static func mist(parent: Node3D, pos: Vector3, away: Vector3, seed_value: int = 0) -> void:
	var m := Mist.new(pos, away.normalized(), seed_value)
	parent.add_child(m)


## A pool of blood on the floor at `pos` (in `parent`'s space), spreading out to `radius` metres
## over `seconds`. It stays.
static func pool(parent: Node3D, pos: Vector3, radius: float, seconds: float, seed_value: int = 0) -> MeshInstance3D:
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
	var t := m.create_tween()
	t.tween_method(func(v: float) -> void: mat.set_shader_parameter("spread", v), 0.0, 1.0, seconds) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	return m


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
