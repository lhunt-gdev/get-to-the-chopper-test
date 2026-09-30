class_name AlarmBox
extends Node3D
## A wall-mounted alarm box (LOCKED recommendation): an environmental target with a short
## timing window as you run past. It blinks while it can be shot. A hit lowers alert by one
## level (not a full reset; the level applies it). Miss the window and it's behind you: no backtracking.

## Shot in its window. The level lowers alert (so this stays free of autoloads, for unit tests).
signal destroyed

const LIT := Color("ff3a2a")
const DARK := Color("3a1a16")

## Distance along the route.
var at: float = 0.0
var in_window: bool = false
var _alive: bool = true
var _light: MeshInstance3D
## A small beacon on top that blinks the whole time the box is live, so you spot it instantly.
var _beacon: MeshInstance3D
var _blink: float = 0.0


func _init() -> void:
	var box := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.8, 0.9, 0.3)
	box.mesh = mesh
	box.material_override = PsxMaterials.flat(Color("c9a227"))
	add_child(box)
	_light = MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(0.46, 0.46, 0.1)
	_light.mesh = lm
	_light.material_override = PsxMaterials.flat(DARK)
	_light.position = Vector3(0, 0.05, 0.18)  # on the face toward the road
	add_child(_light)
	_beacon = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.32, 0.26, 0.32)
	_beacon.mesh = bm
	_beacon.material_override = PsxMaterials.flat(LIT)
	_beacon.position = Vector3(0, 0.58, 0)  # on top
	add_child(_beacon)


func is_alive() -> bool:
	return _alive


func is_targetable(_alert: int) -> bool:
	return _alive and in_window


## Auto-targeting: above an idle trooper, below one who is about to shoot.
func get_threat_priority() -> int:
	return 20


func update(delta: float, tuning: Tuning, player_d: float) -> void:
	var ahead := at - player_d
	in_window = _alive and ahead >= tuning.alarm_window_near and ahead <= tuning.alarm_window_far
	if not _alive:
		return
	_blink += delta
	# The beacon always blinks; it goes fast, with the face light, while the box can be shot.
	var period := 0.3 if in_window else 0.7
	var beacon_on := fmod(_blink, period) < period * 0.55
	_beacon.material_override = PsxMaterials.flat(Color("ff6a4a") if beacon_on else DARK)
	var on := in_window and beacon_on
	_light.material_override = PsxMaterials.flat(LIT if on else DARK)


func hit() -> void:
	if not is_targetable(0):
		return
	_alive = false
	in_window = false
	_light.material_override = PsxMaterials.flat(Color("111111"))
	_beacon.material_override = PsxMaterials.flat(Color("111111"))
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3(1.3, 1.3, 1.3), 0.06)
	tween.tween_property(self, "scale", Vector3.ONE, 0.1)
	destroyed.emit()
