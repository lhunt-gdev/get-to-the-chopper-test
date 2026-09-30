class_name Steam
extends Node3D
## Light steam drifting up from a vent: a few soft grey puffs that rise, grow and fade, on a loop.
## Placeholder PS1-style effect, no particles.

const RISE := 1.3       # metres each puff climbs
const LIFE := 1.8       # seconds from vent to gone

var _puffs: Array[MeshInstance3D] = []
var _mats: Array[StandardMaterial3D] = []
var _age: Array[float] = []
var _rng := RandomNumberGenerator.new()


func _init(count: int = 4, seed_value: int = 0) -> void:
	_rng.seed = seed_value
	for i in count:
		var m := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.3, 0.3, 0.3)
		m.mesh = b
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.82, 0.84, 0.86, 0.0)
		mat.disable_fog = true
		m.material_override = mat
		add_child(m)
		_puffs.append(m)
		_mats.append(mat)
		_age.append(LIFE * float(i) / count)  # staggered, so it's a steady wisp


func _process(delta: float) -> void:
	for i in _puffs.size():
		_age[i] += delta
		if _age[i] >= LIFE:
			_age[i] -= LIFE
			_puffs[i].position = Vector3(_rng.randf_range(-0.15, 0.15), 0, _rng.randf_range(-0.15, 0.15))
		var t := _age[i] / LIFE
		var p := _puffs[i]
		p.position.y = RISE * t
		p.position.x += delta * 0.12  # drifts a little on the wind
		p.scale = Vector3.ONE * lerpf(0.6, 2.2, t)
		_mats[i].albedo_color.a = 0.32 * sin(t * PI)
