class_name Tally
extends Control
## The end screen's tally (user, after DOS Doom's end-of-level screen): the run's numbers count up
## one row at a time, a tick for each step and a thunk as each row lands; skip() (a tap) shows
## them all. Plain counts (user): no "of N" totals, which would give away what's left to find.
## Each row's label types out first (user: "the text in this screen to type in"), then its number
## counts up from 0, never too fast to see ("the numbers to count up"), or its word types out.
##
## Under the rows, the SCORE line (the decision log's "Scoring and the scoreboard"; Score): as each
## row lands, its points roll into the line (so the screen shows how the score works without a
## points table); after the last, the setting's multiplier ("x2 MEDIUM") types out beside it and the
## number multiplies with a heavier thunk; then NEW BEST (a red slanted block), NEW ENTRY #N, or
## his best on the board stamps in under it. A tally given rows only (no setup()) has no SCORE line.

## Each count step plays a tick; each row's last step plays a thunk; each letter typed, a typed.
signal ticked
signal landed
signal typed
## The score multiplied by the setting (a heavier thunk), and the line under it stamped in.
signal multiplied
signal stamped
## Everything's shown (counted to the end, or skipped).
signal finished

const ROW_H := 12.0
## The SCORE line and the line under it (px), under the rows.
const SCORE_H := 36.0
## Seconds per count step, the pause after a row lands, and the most steps a row takes. The least
## time a count takes (a 1 rolls 0, 1), and the seconds per letter typed.
const STEP := 0.055
const PAUSE := 0.15
const MAX_STEPS := 12
const MIN_COUNT := 0.35
const TYPE_STEP := 0.018
## How long a row's points take to roll into the SCORE line, the pause before the multiplier
## multiplies, and before the line under it stamps in (s).
const ROLL := 0.3
const MULTIPLY_WAIT := 0.3
const STAMP_WAIT := 0.4
const ALERT_NAMES := {1: "SNEAKING", 2: "CAUTION", 3: "ALERT"}
const ALERT_COLORS := {1: UiKit.GREEN, 2: UiKit.AMBER, 3: UiKit.RED}

## [label, kind ("time", "clock", "metres", "count", "text"), value, colour, points]: see rows_for().
var rows: Array = []
## Seconds before the first row starts (the route map draws in first).
var delay := 0.0
## The SCORE line (setup()): on, the setting's name and multiplier, the final score, and the line
## under it: "new_best" (NEW BEST, a red block: `outcome` its text), "entry" (NEW ENTRY #N), "best"
## (his best there, dim), or "" (nothing).
var score_on := false
var setting := ""
var mult := 1
var final_score := 0
var outcome_kind := ""
var outcome := ""
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
## The SCORE line: the points so far (before the multiplier), what's shown of them (rolling up to
## it), how fast it rolls, letters of the multiplier typed, and whether it's multiplied and stamped.
var _target := 0
var _shown := 0.0
var _rate := 0.0
var _mult_typed := 0
var _multiplied := false
var _stamped := false


## The rows for a run. stats: time, distance (m), spare (s of chopper time left; < 0 when he didn't
## get out), downed, hits, run_into, alarms_set_off, alarms_stopped, top_alert, levels, new_areas.
## Each row's last item is what it adds to the score (Score.row_points).
static func rows_for(stats: Dictionary) -> Array:
	var out := [["TIME", "time", float(stats.get("time", 0.0)), UiKit.PAPER]]
	out.append(["DISTANCE", "metres", Score.metres(stats), UiKit.PAPER])
	if float(stats.get("spare", -1.0)) >= 0.0:
		out.append(["CHOPPER TO SPARE", "clock", Score.spare_tenths(stats) / 10.0, UiKit.GREEN])
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
	for row in out:
		row.append(Score.row_points(row[0], stats))
	return out


## The SCORE line for a run (stats as rows_for's, and its "setting"), and the line under it.
func setup(stats: Dictionary, kind: String = "", text: String = "") -> void:
	rows = rows_for(stats)
	score_on = true
	setting = String(stats.get("setting", ""))
	mult = Score.multiplier(setting)
	final_score = Score.total(stats, setting)
	outcome_kind = kind
	outcome = text


## The multiplier as it types out beside SCORE: "x2 MEDIUM" ("x1" with no setting).
func mult_text() -> String:
	return "x%d %s" % [mult, setting.to_upper()] if setting != "" else "x%d" % mult


## How a row's value reads after `step` of `steps` count steps.
static func value_text(row: Array, step: int, steps: int) -> String:
	var k := 1.0 if steps <= 0 else float(step) / steps
	match String(row[1]):
		"time", "clock":
			var d := int(round(float(row[2]) * k * 10.0))  # tenths of a second, so 59.97 s is 1:00.0
			return "%d:%02d.%d" % [d / 600, (d / 10) % 60, d % 10]
		"metres":
			return "%d M" % int(round(int(row[2]) * k))
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
		"time", "clock", "metres":
			return 10
		"count":
			return mini(int(row[2]), MAX_STEPS)
		_:
			return 0


## The height the tally needs (its rows, and the SCORE line if it has one).
func needed_height() -> float:
	return ROW_H * rows.size() + (SCORE_H if score_on else 0.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wait = delay
	_done = rows.is_empty() and not score_on


func _process(delta: float) -> void:
	var dt := delta / maxf(Engine.time_scale, 0.01)  # (real time, whatever the game's speed)
	if score_on and not _multiplied and _shown != float(_target):
		_shown = move_toward(_shown, float(_target), maxf(_rate, 1.0) * dt)
		queue_redraw()
	if _done:
		return
	_wait -= dt
	if _wait <= 0.0 and not _started:
		_started = true
		queue_redraw()
	while _wait <= 0.0 and not _done:
		if _row < rows.size():
			_advance()
		else:
			_advance_score()


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


## After the rows: the multiplier types out, the number multiplies, the line under it stamps in.
func _advance_score() -> void:
	queue_redraw()
	if not score_on:
		_finish()
		return
	var m := mult_text()
	if _mult_typed < m.length():
		_type(m, _mult_typed)
		_mult_typed += 1
		if _mult_typed == m.length():
			_wait += MULTIPLY_WAIT
		return
	if not _multiplied:
		_multiplied = true
		_shown = float(final_score)
		multiplied.emit()
		_wait += STAMP_WAIT
		return
	if not _stamped:
		_stamped = true
		if outcome_kind != "":
			stamped.emit()
	_finish()


## A letter typed (the space between words is typed silently).
func _type(text: String, i: int) -> void:
	if text[i] != " ":
		typed.emit()
	_wait += TYPE_STEP


func _land() -> void:
	landed.emit()
	if _row < rows.size() and rows[_row].size() > 4:
		_target += int(rows[_row][4])
		_rate = absf(float(_target) - _shown) / ROLL
	_row += 1
	_step = 0
	_typed = 0
	_word = 0
	_counting = false
	_wait += PAUSE
	if _row >= rows.size() and not score_on:
		_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	finished.emit()


## Show every row's final number at once (a tap on the end screen).
func skip() -> void:
	if _done:
		return
	_row = rows.size()
	_started = true
	if score_on:
		_target = 0
		for row in rows:
			_target += int(row[4]) if row.size() > 4 else 0
		_mult_typed = mult_text().length()
		_multiplied = true
		_stamped = true
		_shown = float(final_score)
	landed.emit()
	queue_redraw()
	_finish()


func is_done() -> bool:
	return _done


## The score the SCORE line shows now (never below 0).
func shown_score() -> int:
	return maxi(0, roundi(_shown))


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
	if score_on:
		_draw_score(f, rows.size() * ROW_H + 4.0)


## The SCORE line at `y0`: a rule, SCORE and the multiplier typed beside it, the number (16 px) on
## the right; under it, the stamp (NEW BEST on a red slanted block, NEW ENTRY #N, or BEST).
func _draw_score(f: Font, y0: float) -> void:
	draw_rect(Rect2(0, y0, size.x, 1), Color(UiKit.TEAL_DIM, 0.8))
	draw_string(f, Vector2(0, y0 + 15.0), "SCORE", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, UiKit.DIM)
	var m := mult_text()
	if _mult_typed > 0:
		draw_string(f, Vector2(36.0, y0 + 15.0), m.substr(0, _mult_typed), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, UiKit.AMBER)
	var num := Score.format(shown_score())
	draw_string(f, Vector2(0, y0 + 17.0), num, HORIZONTAL_ALIGNMENT_RIGHT, size.x, 16, UiKit.PAPER if not _multiplied else UiKit.AMBER)
	if not _stamped or outcome_kind == "" or outcome == "":
		return
	var w := f.get_string_size(outcome, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
	var x := roundf((size.x - w) / 2.0)
	var base_y := y0 + 31.0
	match outcome_kind:
		"new_best":
			var r := Rect2(x - 10.0, base_y - 9.0, w + 20.0, 12.0)
			draw_colored_polygon(lean(Rect2(r.position + Vector2(2, 2), r.size), 4.0), Color(UiKit.INK, 0.9))
			draw_colored_polygon(lean(r, 4.0), UiKit.RED)
			draw_string(f, Vector2(x, base_y), outcome, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, UiKit.INK)
		"entry":
			draw_string(f, Vector2(x, base_y), outcome, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, UiKit.TEAL)
		_:
			draw_string(f, Vector2(x, base_y), outcome, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(UiKit.DIM, 0.9))


## A block's shape: the box with its top leaning `slant` right of its bottom (as the menus' blocks).
static func lean(r: Rect2, slant: float) -> PackedVector2Array:
	return PackedVector2Array([r.position + Vector2(slant, 0.0), Vector2(r.end.x, r.position.y),
			r.end - Vector2(slant, 0.0), Vector2(r.position.x, r.end.y)])
