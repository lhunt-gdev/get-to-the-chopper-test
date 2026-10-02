class_name Ambience
extends Node
## MGS-style mood lighting: dark areas lit by the lamps you can see. Keeps every lamp in the level,
## and each frame hands the nearest ones (plus the area's ambient and moonlight) to the PS1 shader
## through global shader uniforms (see psx_lit.gdshader). Lamps flicker, beacons blink, and at
## high alert the lamps pulse red (MGS's ALERT phase).

const SLOTS := 12
const ALERT_RED := Color(1.0, 0.12, 0.08)
const CAUTION_AMBER := Color(1.0, 0.6, 0.2)

@export var tuning: Tuning

## {node, color, range, flicker, blink, alert, fixture, on_mat, off_mat, seed}
var _lamps: Array[Dictionary] = []
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


## A lamp at `node` (it moves with it). range: how far its pool reaches. flicker 0..1: how often it
## stutters. blink > 0: on/off period in seconds (beacons). alert: pulses red at ALERT.
## fixture: the glowing mesh you see, swapped to off_mat while the lamp is off.
func add_lamp(node: Node3D, color: Color, range_m: float, opts: Dictionary = {}) -> void:
	var lamp := {"node": node, "color": color, "range": range_m, "flicker": opts.get("flicker", 0.0),
			"blink": opts.get("blink", 0.0), "alert": opts.get("alert", true), "fixture": opts.get("fixture", null),
			"on_mat": opts.get("on_mat", null), "off_mat": opts.get("off_mat", null),
			"seed": float(absi(hash(node.get_instance_id())) % 1000) / 37.0, "lit": 1.0}
	_lamps.append(lamp)


## The area you're in: its ambient light, and moonlight (from `dir`) where there's open sky.
func set_area(ambient: Color, moon: Color, dir: Vector3) -> void:
	_target_amb = ambient
	_target_moon = moon
	_target_moon_dir = dir.normalized()


## Jump straight to the area's light (the first frame, a retry).
func snap() -> void:
	_amb = _target_amb
	_moon = _target_moon
	_moon_dir = _target_moon_dir


func _process(delta: float) -> void:
	_time += delta


## focus: where the camera is looking (the lamps nearest it are the ones lit).
func update(delta: float, focus: Vector3, alert_level: int) -> void:
	var k := clampf(delta * 1.5, 0.0, 1.0)
	_amb = _amb.lerp(_target_amb, k)
	_moon = _moon.lerp(_target_moon, k)
	_moon_dir = _moon_dir.lerp(_target_moon_dir, k).normalized()
	_alert = move_toward(_alert, 1.0 if alert_level >= 3 else 0.0, delta * 1.5)
	_caution = move_toward(_caution, 1.0 if alert_level == 2 else 0.0, delta * 1.5)
	var pulse := 0.5 + 0.5 * sin(_time * tuning.alert_pulse_speed)
	var b := tuning.brightness * brightness_scale
	var amb := _amb.lerp(_amb * Color(1.3, 0.65, 0.6), _alert * (0.3 + 0.4 * pulse)) * b
	RenderingServer.global_shader_parameter_set("amb_color", Vector4(amb.r, amb.g, amb.b, 1))
	RenderingServer.global_shader_parameter_set("moon_color", Vector4(_moon.r * b, _moon.g * b, _moon.b * b, 1))
	RenderingServer.global_shader_parameter_set("moon_dir", Vector4(_moon_dir.x, _moon_dir.y, _moon_dir.z, 0))

	_lamps = _lamps.filter(func(l: Dictionary) -> bool: return is_instance_valid(l["node"]))
	var near: Array[Dictionary] = []
	for l in _lamps:
		var node: Node3D = l["node"]
		if not node.is_inside_tree() or not node.is_visible_in_tree():  # e.g. walls rebuilt, the old ones on their way out
			continue
		l["lit"] = _lit(l)
		var fixture = l["fixture"]
		if fixture != null and is_instance_valid(fixture) and l["on_mat"] != null:
			fixture.material_override = l["on_mat"] if l["lit"] > 0.5 else l["off_mat"]
		l["pos"] = node.global_position
		l["dist"] = l["pos"].distance_to(focus)
		if l["dist"] < tuning.lamp_fade_far + l["range"]:
			near.append(l)
	near.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["dist"] < b["dist"])
	for i in SLOTS:
		var pos := Vector4.ZERO
		var col := Vector4.ZERO
		if i < near.size():
			var l: Dictionary = near[i]
			var c: Color = l["color"]
			if l["alert"]:
				c = c.lerp(CAUTION_AMBER * c.get_luminance() * 1.3, _caution * 0.12)
				c = c.lerp(ALERT_RED * 1.3, _alert * (0.25 + 0.3 * pulse))
			# Far lamps fade out (instead of popping) where the list cuts off, hidden in the fog.
			var fade := clampf((tuning.lamp_fade_far - float(l["dist"])) / 10.0, 0.0, 1.0)
			var e: float = l["lit"] * fade * b
			var p: Vector3 = l["pos"]
			pos = Vector4(p.x, p.y, p.z, l["range"])
			col = Vector4(c.r * e, c.g * e, c.b * e, 1)
		RenderingServer.global_shader_parameter_set("lamp_pos_%d" % i, pos)
		RenderingServer.global_shader_parameter_set("lamp_col_%d" % i, col)


## How strongly the screen edges throb: x = ALERT red, y = CAUTION amber (both 0..1, pulsing).
func screen_alert() -> Vector2:
	var pulse := 0.5 + 0.5 * sin(_time * tuning.alert_pulse_speed)
	return Vector2(_alert * (0.35 + 0.65 * pulse), _caution * (0.6 + 0.4 * pulse))


## How lit a lamp is right now, 0..1: blinking beacons, and the odd stutter of a failing tube.
func _lit(l: Dictionary) -> float:
	var t: float = _time + l["seed"]
	if l["blink"] > 0.0:
		return 1.0 if fmod(t, l["blink"]) < l["blink"] * 0.35 else 0.0
	if l["flicker"] > 0.0:
		# Mostly on; now and then a burst of quick flickers.
		var burst := sin(t * 0.7) * sin(t * 1.3 + 1.0)
		if burst > 1.0 - l["flicker"]:
			return 0.0 if fmod(t * 23.0, 1.0) < 0.5 else 0.6
	return 1.0
