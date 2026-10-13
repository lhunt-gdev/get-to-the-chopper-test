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
	"blood": true,          # blood effects (Blood): the mist and the pools
	"aim": "auto_tap",      # "auto" | "auto_tap" | "tap"
	"fire_side": "right",   # "right" | "left"
	"swipe": "medium",      # "low" | "medium" | "high"
	"controls": "swipe",    # "swipe" | "buttons" (MOVE: the on-screen move buttons too; swipes work either way)
	"tips": true,           # the first-time tips in mission 1 (FirstTips; which were seen: Progress)
}

var _values: Dictionary = DEFAULTS.duplicate()


func _ready() -> void:
	load_from(PATH)


## Reads the settings saved at `path`: each one only if it's the kind of value its default is (a
## number for a volume, ON / OFF for a switch, a word for a choice); anything else, and anything
## missing, its default. A file that can't be read at all is kept as it was ("<path>.bad":
## SaveFile.keep_bad) and every setting is its default.
func load_from(path: String) -> void:
	_values = DEFAULTS.duplicate()
	if not SaveFile.exists(path):
		return
	var cfg := ConfigFile.new()
	if cfg.parse(SaveFile.read_text(path)) != OK:
		SaveFile.keep_bad(path)
		push_warning("Settings: %s couldn't be read; the defaults" % path)
		return
	for k in DEFAULTS:
		var v: Variant = cfg.get_value("settings", k, DEFAULTS[k])
		_values[k] = v if typeof(v) == typeof(DEFAULTS[k]) else DEFAULTS[k]


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


## Saved the moment one changes (in the pause menu mid-run too), not only at a run's end; safely
## (SaveFile: a temp file, then a rename; a failed write is a warning). (`path`: the tests' own file.)
func _save(path: String = PATH) -> void:
	var cfg := ConfigFile.new()
	for k in _values:
		cfg.set_value("settings", k, _values[k])
	SaveFile.write_text(path, cfg.encode_to_text())


## A 0-100 volume as dB (0 is silent).
static func volume_db(percent: float) -> float:
	return -80.0 if percent <= 0.0 else linear_to_db(percent / 100.0)
