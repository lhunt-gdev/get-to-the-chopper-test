extends Node
## The player's settings (audio, display, controls), saved on the device (user://settings.cfg,
## which on the web is the browser's storage). Autoload "Settings". Changing one emits `changed`
## so the game applies it straight away.

signal changed

const PATH := "user://settings.cfg"
const DEFAULTS := {
	"sound_on": true,
	"master_volume": 80,
	"music_volume": 70,
	"effects_volume": 80,
	"ambience_volume": 60,
	"brightness": 100,      # percent of normal
	"screen_shake": true,
	"retro_filter": true,
	"aim": "auto_tap",      # "auto" | "auto_tap" | "tap"
	"fire_side": "right",   # "right" | "left"
	"swipe": "medium",      # "low" | "medium" | "high"
}

var _values: Dictionary = DEFAULTS.duplicate()


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		for k in DEFAULTS:
			_values[k] = cfg.get_value("settings", k, DEFAULTS[k])


func get_value(key: String) -> Variant:
	return _values.get(key, DEFAULTS.get(key))


func set_value(key: String, value: Variant) -> void:
	if _values.get(key) == value:
		return
	_values[key] = value
	_save()
	changed.emit()


func reset() -> void:
	_values = DEFAULTS.duplicate()
	_save()
	changed.emit()


func _save() -> void:
	var cfg := ConfigFile.new()
	for k in _values:
		cfg.set_value("settings", k, _values[k])
	cfg.save(PATH)


## A 0-100 volume as dB (0 is silent).
static func volume_db(percent: float) -> float:
	return -80.0 if percent <= 0.0 else linear_to_db(percent / 100.0)
