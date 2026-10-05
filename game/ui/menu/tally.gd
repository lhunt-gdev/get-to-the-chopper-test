class_name Tally
extends Control
## The end screen's tally (user, after DOS Doom's end-of-level screen): the run's numbers count up
## one row at a time, a tick for each step and a thunk as each row lands; skip() (a tap) shows
## them all. Plain counts (user): no "of N" totals, which would give away what's left to find.
## Each row's label types out first (user: "the text in this screen to type in"), then its number
## counts up from 0, never too fast to see ("the numbers to count up"), or its word types out.

## Each count step plays a tick; each row's last step plays a thunk; each letter typed, a typed.
signal ticked
signal landed
signal typed

const ROW_H := 12.0
## Seconds per count step, the pause after a row lands, and the most steps a row takes. The least
## time a count takes (a 1 rolls 0, 1), and the seconds per letter typed.
const STEP := 0.055
const PAUSE := 0.15
const MAX_STEPS := 12
const MIN_COUNT := 0.35
const TYPE_STEP := 0.018
const ALERT_NAMES := {1: "SNEAKING", 2: "CAUTION", 3: "ALERT"}
const ALERT_COLORS := {1: UiKit.GREEN, 2: UiKit.AMBER, 3: UiKit.RED}

## [label, kind ("time", "clock", "count", "text"), value, colour]: see rows_for().
var rows: Array = []
## Seconds before the first row starts (the route map draws in first).
var delay := 0.0
var _row := 0
var _step := 0
var _wait := 0.0
var _done := false
## Letters of this row's label typed, and of its word (a text row); whether its count has begun
## (its 0 shows a count's step first).
var _typed := 0
var _word := 0
var _counting := false
## Whether the first row has started (nothing shows before, while the route map draws in).
var _started := false


## The rows for a run. stats: time, spare (s of chopper time left; < 0 when he didn't get out),
## downed, hits, run_into, alarms_set_off, alarms_stopped, top_alert, levels, new_areas.
static func rows_for(stats: Dictionary) -> Array:
	var out := [["TIME", "time", float(stats.get("time", 0.0)), UiKit.PAPER]]
	if float(stats.get("spare", -1.0)) >= 0.0:
		out.append(["CHOPPER TO SPARE", "clock", float(stats["spare"]), UiKit.GREEN])
	out.append(["ENEMIES DOWN", "count", int(stats.get("downed", 0)), UiKit.PAPER])
	out.append(["HITS TAKEN", "count", int(stats.get("hits", 0)), UiKit.PAPER])
	out.append(["THINGS RUN INTO", "count", int(stats.get("run_into", 0)), UiKit.PAPER])
	var set_off := int(stats.get("alarms_set_off", 0))
	out.append(["ALARMS SET OFF", "count", set_off, UiKit.RED if set_off > 0 else UiKit.PAPER])
	out.append(["ALARMS STOPPED", "count", int(stats.get("alarms_stopped", 0)), UiKit.PAPER])
	var top := clampi(int(stats.get("top_alert", 1)), 1, 3)
	out.append(["HIGHEST ALERT", "text", ALERT_NAMES[top], ALERT_COLORS[top]])
	out.append(["ROUTE", "text", String(stats.get("levels", "MAIN")), UiKit.TEAL])
	out.append(["NEW AREAS FOUND", "count", int(stats.get("new_areas", 0)), UiKit.TEAL])
	return out


## How a row's value reads after `step` of `steps` count steps.
static func value_text(row: Array, step: int, steps: int) -> String:
	var k := 1.0 if steps <= 0 else float(step) / steps
	match String(row[1]):
		"time":
			var d := int(round(float(row[2]) * k * 10.0))  # tenths of a second, so 59.97 s is 1:00.0
			return "%d:%02d.%d" % [d / 600, (d / 10) % 60, d % 10]
		"clock":
			var c := int(round(float(row[2]) * k))
			return "%d:%02d" % [c / 60, c % 60]
		"count":
			return str(int(round(int(row[2]) * k)))
		_:
			return String(row[2])


## A value squeezed to fit beside its label in `width` px (8 px pixel font): a long route loses the
## spaces round its arrows.
static func fit_value(label: String, text: String, width: float) -> String:
	var f := UiKit.font()
	var room := width - f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x - 6.0
	if f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x > room:
		return text.replace(" > ", ">")
	return text


## How many count steps a row takes (0: it just lands).
static func steps_of(row: Array) -> int:
	match String(row[1]):
		"time", "clock":
			return 10
		"count":
			return mini(int(row[2]), MAX_STEPS)
		_:
			return 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wait = delay
	_done = rows.is_empty()


func _process(delta: float) -> void:
	if _done:
		return
	_wait -= delta / maxf(Engine.time_scale, 0.01)  # (real time, whatever the game's speed)
	if _wait <= 0.0 and not _started:
		_started = true
		queue_redraw()
	while _wait <= 0.0 and not _done:
		_advance()


func _advance() -> void:
	var row: Array = rows[_row]
	var label: String = row[0]
	queue_redraw()
	if _typed < label.length():
		_type(label, _typed)
		_typed += 1
		return
	if String(row[1]) == "text":
		var word := fit_value(label, String(row[2]), size.x)
		if _word < word.length():
			_type(word, _word)
			_word += 1
			return
		_land()
		return
	var steps := steps_of(row)
	if not _counting:
		_counting = true
		_wait += maxf(STEP, MIN_COUNT / steps) if steps > 0 else 0.0
		return
	_step += 1
	if _step < steps:
		ticked.emit()
		_wait += maxf(STEP, MIN_COUNT / steps)
	else:
		_land()


## A letter typed (the space between words is typed silently).
func _type(text: String, i: int) -> void:
	if text[i] != " ":
		typed.emit()
	_wait += TYPE_STEP


func _land() -> void:
	landed.emit()
	_row += 1
	_step = 0
	_typed = 0
	_word = 0
	_counting = false
	_wait += PAUSE
	_done = _row >= rows.size()


## Show every row's final number at once (a tap on the end screen).
func skip() -> void:
	if _done:
		return
	_row = rows.size()
	_done = true
	_started = true
	landed.emit()
	queue_redraw()


func is_done() -> bool:
	return _done


func _draw() -> void:
	if not _started:
		return
	var f := UiKit.font()
	for i in mini(_row + 1, rows.size()):
		var row: Array = rows[i]
		var y := i * ROW_H + 7.0
		var now := i == _row
		var label: String = row[0]
		draw_string(f, Vector2(0, y), label.substr(0, _typed) if now else label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, UiKit.DIM)
		if now and _typed < label.length():
			continue  # (its value once its label's typed)
		if String(row[1]) == "text":
			# A word types out from where it ends up (right-aligned), so it doesn't slide as it grows.
			var word := fit_value(label, String(row[2]), size.x)
			var at := size.x - f.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
			draw_string(f, Vector2(at, y), word.substr(0, _word) if now else word, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, row[3])
			continue
		var steps := steps_of(row)
		var text := fit_value(label, value_text(row, steps if i < _row else _step, steps), size.x)
		draw_string(f, Vector2(0, y), text, HORIZONTAL_ALIGNMENT_RIGHT, size.x, 8, row[3])
