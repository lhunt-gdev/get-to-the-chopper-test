class_name Sparks
extends Node3D
## A crackle of electrical sparks at a point: a few tiny, unlit flecks that flicker on and off
## and jump about at random. Placeholder PS1-style effect, no particles.

const COLORS := [Color("fff6b0"), Color("ffffff"), Color("9fd8ff")]

var _flecks: Array[MeshInstance3D] = []
var _rng := RandomNumberGenerator.new()
var _wait := 0.0


func _init(count: int = 4, seed_value: int = 0) -> void:
	_rng.seed = seed_value
	for i in count:
		var m := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.1, 0.1, 0.1)  # chunky, so they read at the low internal resolution
		m.mesh = b
		m.material_override = PsxMaterials.glow(COLORS[i % COLORS.size()])
		m.visible = false
		add_child(m)
		_flecks.append(m)


func _process(delta: float) -> void:
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = _rng.randf_range(0.03, 0.12)
	# Now and then it goes quiet, so the crackle reads as intermittent.
	var burst := _rng.randf() < 0.7
	for f in _flecks:
		f.visible = burst and _rng.randf() < 0.6
		f.position = Vector3(_rng.randf_range(-0.12, 0.12), _rng.randf_range(-0.14, 0.06), _rng.randf_range(-0.12, 0.12))
		f.scale = Vector3.ONE * _rng.randf_range(0.6, 1.6)
