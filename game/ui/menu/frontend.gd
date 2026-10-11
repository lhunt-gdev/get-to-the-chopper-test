class_name Frontend
extends CanvasLayer
## Every menu screen, in the game's espionage style (UiKit): the main menu (over the slowly
## swaying opening camera), the mission briefing (Briefing), SETTINGS, CONTROLS, the
## pause menu, and the end screens (the end-of-mission conversation, then the debrief). It keeps
## working while the game is paused. The level listens to its signals.

## A mission and setting picked in the mission select (open ones only): the level builds it and opens
## its briefing.
signal start_requested(mission: int, setting: String)
signal resume_requested
signal retry_requested
signal menu_requested
## Any button pressed (the level plays a blip for it).
signal clicked
## The end screen's tally: a count step (a tick), a row landing (a thunk).
signal tally_ticked
signal tally_landed
## A letter of the end screen or the briefing typed out (the level plays a tick).
signal typed
## The mission briefing closed (SKIP, or a tap after its last line): the opening pan comes next.
signal briefing_done
## A sound for the briefing (or the end-of-mission conversation) to play (the call, the codec
## opening and closing, static).
signal briefing_cue(sound: String, volume_db: float)
## The run's over and the debrief (the route map and the tally) has opened: after the end-of-mission
## conversation, or at once without one (the level plays the end's sting now).
signal debrief_opened(reason: StringName)
## The debrief's SCORE line: multiplied by the setting (a heavier thunk), and the line under it
## stamped in ("new_best", "entry" or "best").
signal score_multiplied
signal score_stamped(kind: String)

## END_TALK: the end-of-mission conversation (a Briefing), between the run and the debrief (END).
## MISSIONS: the mission select, after MISSION SELECT; MISSION: one mission's screen after it (its
## EASY / MEDIUM / HARD, each with his best time). NAME: the name entry, when a run makes a board's
## top 10; BOARD: a mission's scoreboard (from the debrief, the mission's screen, HIGH SCORES).
enum Screen { NONE, MAIN, SETTINGS, CONTROLS, PAUSE, END, BRIEFING, END_TALK, MISSIONS, MISSION, NAME, BOARD }

const AIM_NAMES := {"auto": "AUTO", "auto_tap": "AUTO + TAP", "tap": "TAP ONLY"}
const SWIPE_NAMES := {"low": "LOW", "medium": "MEDIUM", "high": "HIGH"}
const END_TITLES := {
	&"extracted": ["MISSION COMPLETE", "EXTRACTED BY CHOPPER", UiKit.GREEN],
	&"killed": ["KILLED IN ACTION", "AGENT DOWN", UiKit.RED],
	&"captured": ["CAPTURED", "TAKEN BY THE ENEMY", UiKit.AMBER],
	&"chopper_left": ["MISSION FAILED", "THE CHOPPER LEFT", UiKit.RED],
	&"dead_end": ["MISSION FAILED", "NO WAY THROUGH", UiKit.RED],
}

var mission_title := "MISSION 1"
var _screen := Screen.NONE
## The mission whose screen is (or was last) up.
var _mission := 1
## Where SETTINGS / CONTROLS go back to.
var _back_to := Screen.MAIN
## The scoreboard shown (or last shown): its mission and setting, where its BACK goes, and his entry
## to blink on it (its seq; 0: none).
var _board_mission := 1
var _board_setting := "easy"
var _board_back := Screen.MAIN
var _board_flash := 0
## The debrief's been seen to its end (back from the board or the name entry: shown at once), and
## whether the run's entry on its board still wants a name (the name entry opens after the tally).
var _end_done := false
var _name_pending := false
## The name entry's name so far, and whether it's still the one it was filled in with (the first
## key typed replaces it).
var _name := ""
var _name_fresh := true
var _root: Control
var _dim: ColorRect


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_dim = ColorRect.new()
	_dim.color = Color(0.0, 0.02, 0.03, 0.55)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP  # nothing reaches the game under a menu
	add_child(_dim)
	_root = Control.new()
	_root.theme = UiKit.theme()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_show(Screen.NONE)


func is_open() -> bool:
	return _screen != Screen.NONE


func show_main() -> void:
	_show(Screen.MAIN)


func show_pause() -> void:
	_show(Screen.PAUSE)


func hide_all() -> void:
	_show(Screen.NONE)


## A picked mission's briefing: the conversation in `script` (Briefing.load_file()).
func show_briefing(script: Dictionary) -> void:
	_briefing_script = script
	_show(Screen.BRIEFING)


func in_briefing() -> bool:
	return _screen == Screen.BRIEFING


## The mission select (after MISSION SELECT), up.
func in_missions() -> bool:
	return _screen == Screen.MISSIONS


## A mission's screen (its EASY / MEDIUM / HARD), up; which mission it is.
func in_mission() -> bool:
	return _screen == Screen.MISSION


func mission_shown() -> int:
	return _mission


## Opens mission n's screen (a tap on its row in the mission select; user: "There would be another
## screen after the mission select that shows the 3 difficulty options"): only a mission that's built
## with a setting open. False, and nothing happens, otherwise.
func open_mission(n: int) -> bool:
	if _screen != Screen.MISSIONS or not MissionRow.can_open(n):
		return false
	_mission = n
	_show(Screen.MISSION)
	return true


## Picks mission n on `setting` (a tap on its button on the mission's screen): only one that's open
## and built (Progress.is_playable; user: "they can only select a mission they have unlocked"). Then
## the level builds it and opens its briefing (start_requested). False, and nothing happens,
## otherwise.
func choose(n: int, setting: String) -> bool:
	if _screen != Screen.MISSION or n != _mission or not Progress.is_playable(n, setting):
		return false
	clicked.emit()
	start_requested.emit(n, setting)
	return true


## The mission's screen's button for mission n on `setting` (while it's up), else null.
func chip(n: int, setting: String) -> SettingChip:
	for c in _root.get_children():
		if c is SettingChip and not c.is_queued_for_deletion() and c.mission == n and c.setting == setting:
			return c
	return null


## The mission select's row for mission n (while it's up), else null.
func mission_row(n: int) -> MissionRow:
	for c in _root.get_children():
		if c is MissionRow and not c.is_queued_for_deletion() and c.number == n:
			return c
	return null


## The run's over: the end-of-mission conversation in `talk` (Briefing.conversation() for the end's
## reason) first, then, when it closes (SKIP, or a tap after its last line), the debrief; with no
## lines to play, the debrief at once. stats: the tally's numbers (Tally.rows_for), and for the route
## map graph, visited, discovered, end_into (how far into the last area it ended) and end_ramp (the
## stairs at its start).
func show_end(reason: StringName, stats: Dictionary, talk: Dictionary = {}) -> void:
	_end_reason = reason
	_end_stats = stats
	_end_done = false
	_name_pending = int(stats.get("rank", 0)) > 0 and int(stats.get("seq", 0)) > 0
	if Briefing.lines_of(talk).is_empty():
		_open_debrief()
		return
	_briefing_script = talk
	_show(Screen.END_TALK)


func in_end_talk() -> bool:
	return _screen == Screen.END_TALK


## The debrief (the end screen), up.
func in_debrief() -> bool:
	return _screen == Screen.END


## The debrief's lines for what an extraction opened ([n, setting] pairs: Progress.record_extraction)
## from mission `from`: this mission's next setting up ("MEDIUM UNLOCKED"), then the next mission's
## ("MISSION 2: EASY + MEDIUM UNLOCKED").
static func unlock_lines(news: Array, from: int) -> PackedStringArray:
	var same := PackedStringArray()
	var next := {}  # mission -> its settings opened
	for pair in news:
		if int(pair[0]) == from:
			same.append("%s UNLOCKED" % String(pair[1]).to_upper())
		else:
			if not next.has(int(pair[0])):
				next[int(pair[0])] = PackedStringArray()
			next[int(pair[0])].append(String(pair[1]).to_upper())
	for m in next:
		same.append("MISSION %d: %s UNLOCKED" % [m, " + ".join(next[m])])
	return same


## A run time as the tally shows it (minutes, seconds, tenths: "1:21.4").
static func time_text(seconds: float) -> String:
	return Tally.value_text(["", "time", seconds], 1, 1)


## The debrief's line for a new best time (Progress.record_run): "NEW BEST TIME" for his first time
## out on it, "NEW BEST TIME - WAS 1:30.2" when it beat his old one; "" if it isn't one.
static func best_line(new_best: bool, was: float) -> String:
	if not new_best:
		return ""
	return "NEW BEST TIME" if was < 0.0 else "NEW BEST TIME - WAS %s" % time_text(was)


## The line under the debrief's SCORE (from the run's stats: Progress.record_run): ["new_best",
## "NEW BEST" (and its place: "NEW BEST #2")] when it beat his own best there; ["entry", "NEW ENTRY
## #4"] when it made the board but isn't his best; ["best", "BEST 161,000"] (his best there, dim)
## otherwise; ["", ""] with no board (the TEST RANGE, or no score).
static func score_outcome(stats: Dictionary) -> Array:
	var rank := int(stats.get("rank", 0))
	if bool(stats.get("new_best_score", false)):
		return ["new_best", "NEW BEST #%d" % rank if rank > 0 else "NEW BEST"]
	if rank > 0:
		return ["entry", "NEW ENTRY #%d" % rank]
	var best := maxi(int(stats.get("score_was", -1)), -1)
	if best >= 0 and int(stats.get("mission", 0)) >= 1:
		return ["best", "BEST %s" % Score.format(best)]
	return ["", ""]


## The name entry (a run made the top 10), up; the name in it so far.
func in_name_entry() -> bool:
	return _screen == Screen.NAME


func name_text() -> String:
	return _name


## A scoreboard, up; which one ([mission, setting]).
func in_board() -> bool:
	return _screen == Screen.BOARD


func board_shown() -> Array:
	return [_board_mission, _board_setting]


## Opens mission n's scoreboard on `setting` (BACK goes to `back`), his entry `flash` blinking on it
## (0: none). False, and nothing happens, for a mission that isn't built or a setting that isn't one.
func open_board(n: int, setting: String, back: Screen = Screen.MAIN, flash: int = 0) -> bool:
	if not Progress.is_built(n) or not setting in RouteGraph.SETTINGS:
		return false
	_board_mission = n
	_board_setting = setting
	_board_back = back
	_board_flash = flash
	_show(Screen.BOARD)
	return true


## The name entry's keys: a letter, a number, " ", "." or "-" types it (up to the longest name; the
## first replaces the name it was filled in with); "DEL" takes the last off; "OK" saves it
## (Progress.rename) and opens the board with the entry blinking. False if the name entry isn't up.
func press_key(key: String) -> bool:
	if _screen != Screen.NAME:
		return false
	match key:
		"OK":
			_name_ok()
		"DEL":
			_name_fresh = false
			_name = _name.substr(0, maxi(0, _name.length() - 1))
		_:
			if key.length() != 1 or not Progress.NAME_CHARS.contains(key.to_upper()):
				return false
			if _name_fresh:
				_name = ""
				_name_fresh = false
			if _name.length() < Progress.NAME_MAX:
				_name += key.to_upper()
	for c in _root.get_children():
		if c is NameSlots:
			c.text = _name
			c.queue_redraw()
	return true


func _name_ok() -> void:
	var n := int(_end_stats.get("mission", 0))
	var which := String(_end_stats.get("setting", ""))
	var seq := int(_end_stats.get("seq", 0))
	Progress.rename(n, which, seq, _name)
	_name_pending = false
	open_board(n, which, Screen.END, seq)


## The name entry's key at `key` ("A", "DEL", "OK"...), while it's up; else null.
func key_cap(key: String) -> Button:
	for c in _root.get_children():
		if c is KeyCap and not c.is_queued_for_deletion() and c.key == key:
			return c
	return null


func _open_debrief() -> void:
	_end_guard = _screen == Screen.END_TALK
	_show(Screen.END)
	debrief_opened.emit(_end_reason)


var _end_reason: StringName = &"extracted"
## Straight after an end conversation: the debrief's buttons wait END_GUARD s before they take a tap
## or Enter, so one meant for the conversation's last line can't retry or quit before the debrief's
## been seen (a tap on them meanwhile reaches the screen behind: the debrief shown at once).
const END_GUARD := 0.6
var _end_guard := false
var _end_stats: Dictionary = {}
var _briefing_script: Dictionary = {}


func _show(s: Screen) -> void:
	_screen = s
	for c in _root.get_children():
		c.queue_free()
	_dim.visible = s != Screen.NONE
	# (The briefing darkens the screen behind itself as it opens, from the main menu's dim; the end
	# conversation the same, over the run's last moment.)
	_dim.color = Color(0.0, 0.02, 0.03, 0.35 if s in [Screen.MAIN, Screen.BRIEFING, Screen.END_TALK] else 0.7)
	match s:
		Screen.MAIN:
			_build_main()
		Screen.SETTINGS:
			_build_settings()
		Screen.CONTROLS:
			_build_controls()
		Screen.MISSIONS:
			_build_missions()
		Screen.MISSION:
			_build_mission()
		Screen.PAUSE:
			_build_pause()
		Screen.END:
			_build_end()
		Screen.NAME:
			_build_name()
		Screen.BOARD:
			_build_board()
		Screen.BRIEFING, Screen.END_TALK:
			_build_briefing()


# --- Screens --------------------------------------------------------------------------

## The room left above and below the main menu's logo (px).
const LOGO_ROOM := 10.0


## The main menu's title, down the screen (px): the logo's top (LOGO_ROOM under the tag), the
## mission line (LOGO_ROOM under the logo), and the red rule under that (CROSS's head stays under
## it: the tests).
static func logo_top() -> float:
	return 78.0 + LOGO_ROOM


static func mission_line() -> float:
	return logo_top() + Logo.height() + LOGO_ROOM


static func title_rule() -> float:
	return mission_line() + 15.0


func _build_main() -> void:
	_back_to = Screen.MAIN
	_root.add_child(Reticle.new())
	var tag := UiKit.label("// CLASSIFIED: EYES ONLY", 8, UiKit.RED, HORIZONTAL_ALIGNMENT_CENTER)
	_place_wide(tag, 70)
	var logo := Logo.new()
	# Room round the logo (user: "it needs a bit of padding around the logo as the other texts are too
	# close"): see logo_top.
	_place_wide(logo, logo_top())
	logo.offset_bottom = logo_top() + Logo.height()
	_place_wide(UiKit.label(mission_title.replace("\n", ": "), 8, UiKit.DIM, HORIZONTAL_ALIGNMENT_CENTER), mission_line())
	Reticle.rule_bottom = title_rule()
	Reticle.ring_y = roundf(logo_top() + Logo.height() / 2.0)
	var first := _button("MISSION SELECT", 290, func() -> void: _open(Screen.MISSIONS))
	# HIGH SCORES: the scoreboard of the mission and setting last picked.
	_button("HIGH SCORES", 318, func() -> void:
		var n := int(Progress.last.get_slice(":", 0))
		open_board(n if Progress.is_built(n) else 1, Progress.last.get_slice(":", 1), Screen.MAIN))
	_button("SETTINGS", 346, func() -> void: _open(Screen.SETTINGS))
	_button("CONTROLS", 374, func() -> void: _open(Screen.CONTROLS))
	_place_wide(UiKit.label("PROOF OF CONCEPT BUILD", 8, Color(UiKit.DIM, 0.7), HORIZONTAL_ALIGNMENT_CENTER), 446)
	_place_wide(UiKit.label(build_label(), 8, Color(UiKit.DIM, 0.55), HORIZONTAL_ALIGNMENT_CENTER), 458)
	first.grab_focus()


## Which build this is: the commit the live site was built from and when (UTC), written by the
## CI into game/build_info.json, so you can tell a fresh version from a cached old one. "DEV"
## when run from the editor.
static func build_label() -> String:
	var path := "res://game/build_info.json"
	if not FileAccess.file_exists(path):
		return "BUILD DEV"
	var info = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not info is Dictionary:
		return "BUILD DEV"
	return ("BUILD %s - %s" % [info.get("commit", "?"), info.get("built", "")]).strip_edges().to_upper()

## The mission briefing (or the end-of-mission conversation): its own screen (Briefing), its typing
## ticking like the end screen's. The briefing closing starts the pan (briefing_done); the end
## conversation closing opens the debrief.
func _build_briefing() -> void:
	var b := Briefing.new()
	b.data = _briefing_script
	b.typed.connect(func() -> void: typed.emit())
	b.cue.connect(func(sound: String, db: float) -> void: briefing_cue.emit(sound, db))
	b.finished.connect(func() -> void:
		if _screen == Screen.END_TALK:
			_open_debrief()
		else:
			briefing_done.emit())
	_root.add_child(b)  # (connected first: it calls as it opens)
	b.skip_button.pressed.connect(func() -> void: clicked.emit())  # (a button's click, like the rest)


func _build_pause() -> void:
	_back_to = Screen.PAUSE
	_header("PAUSED", "MISSION ON HOLD")
	var first := _button("RESUME", 170, func() -> void: resume_requested.emit())
	_button("SETTINGS", 198, func() -> void: _open(Screen.SETTINGS))
	_button("CONTROLS", 226, func() -> void: _open(Screen.CONTROLS))
	_button("QUIT TO MENU", 268, func() -> void: menu_requested.emit())
	first.grab_focus()


func _build_controls() -> void:
	_header("CONTROLS", "FIELD MANUAL")
	var lines := [
		["SWIPE < >", "DODGE A LANE"],
		["SWIPE UP", "JUMP"],
		["SWIPE DOWN", "SLIDE"],
		["HOLD FIRE", "SHOOT (AUTO-AIM)"],
		["TAP ENEMY", "TARGET IT"],
		["RUN INTO COVER", "HIDE BEHIND IT"],
		["  SWIPE < >", "LEAVE COVER"],
		["OUTER LANES", "TAKE SIDE EXITS"],
		["TRIPWIRES", "RAISE THE ALERT"],
		["ALARM BOXES", "SHOOT: ALERT DOWN"],
		["DOGS", "DODGE OR SHOOT"],
		["THE CHOPPER", "REACH IT IN TIME"],
	]
	var y := 104.0
	for row in lines:
		var a := UiKit.label(row[0], 8, UiKit.TEAL)
		a.position = Vector2(26, y)
		_root.add_child(a)
		var b := UiKit.label(row[1], 8, UiKit.PAPER)
		b.position = Vector2(132, y)
		_root.add_child(b)
		y += 18.0
	_button("BACK", 430, func() -> void: _open(_back_to)).grab_focus()


## Where the mission select's rows start, and the least and most room each takes (px): 9 rows fit a
## 480-high screen; a taller one spreads them out a little, up to the most.
const MISSION_TOP := 88.0
const MISSION_ROW_MIN := 36.0
const MISSION_ROW_MAX := 44.0
## The gap between two rows (px).
const MISSION_GAP := 6.0


## How far apart the mission select's rows are (px) on a screen `height` high (BACK under the last).
static func mission_step(height: float) -> float:
	return clampf(floorf((height - MISSION_TOP - 62.0) / Progress.MISSIONS.size()), MISSION_ROW_MIN, MISSION_ROW_MAX)


## The mission select (user: "a mission select where the player can click to see all missions but
## they can only select a mission they have unlocked"; then "The menu is too cramped": the settings
## moved to each mission's own screen): all nine missions as file tabs down the screen, each with its
## number, its name, under that his best time on each setting ("E 1:21  M --  H --"; user: "it
## could display the best time for that mission"), and a small mark for each setting (E, M, H:
## green once he's got out on it, a padlock while it's locked). A tap on one that's built with a setting open opens its screen
## (open_mission); a locked one is greyed with a padlock and does nothing, and the missions not built
## yet say COMING SOON. BACK: the main menu.
func _build_missions() -> void:
	_header("MISSION SELECT", "CONDOR JOB SHEET")
	var size := _root.get_viewport_rect().size
	var count := Progress.MISSIONS.size()
	var step := mission_step(size.y)
	var focus: MissionRow = null
	var last_n := int(Progress.last.get_slice(":", 0))
	for i in count:
		var n := i + 1
		var row := MissionRow.new()
		row.number = n
		row.title = String(Progress.MISSIONS[i]["name"])
		row.built = Progress.is_built(n)
		for s in RouteGraph.SETTINGS:
			row.unlocked.append(Progress.is_unlocked(n, s))
			row.cleared.append(Progress.is_cleared(n, s))
			row.best.append(Progress.best_time(n, s))
		row.position = Vector2(14, MISSION_TOP + i * step)
		row.size = Vector2(size.x - 28, step - MISSION_GAP)
		row.pressed.connect(func() -> void:
			clicked.emit()
			open_mission(n))
		_root.add_child(row)
		if row.playable() and (focus == null or n == last_n):
			focus = row
	var back := _button("BACK", MISSION_TOP + count * step + 6.0, func() -> void: _open(Screen.MAIN))
	(focus if focus != null else back).grab_focus()


## The mission screen's setting buttons: where the first starts (under the header), their height
## and the gap between (px). On a screen taller than 480 the block moves down by half the extra (up
## to MISSION_SHIFT_MAX), so it sits nearer the middle.
const SETTING_TOP := 104.0
const SETTING_H := 76.0
const SETTING_GAP := 12.0
const MISSION_SHIFT_MAX := 60.0


## The mission screen's first setting button's top on a screen `height` high.
static func setting_top(height: float) -> float:
	return SETTING_TOP + clampf(floorf((height - 480.0) / 2.0), 0.0, MISSION_SHIFT_MAX)


## A mission's screen (user: "another screen after the mission select that shows the 3 difficulty
## options with the players best time if it's been set. They click the difficulty they want to play
## and the game starts."): its name, EASY / MEDIUM / HARD as big buttons, each with his best time
## there (his fastest extraction's run time; "--" if none), a locked one greyed with its padlock (and
## what clears it). A tap on an open one starts it (choose: the briefing, then the run). BACK: the
## mission select.
func _build_mission() -> void:
	var n := _mission
	_header(String(Progress.MISSIONS[n - 1]["name"]), "MISSION %02d: PICK YOUR SETTING" % n)
	var size := _root.get_viewport_rect().size
	var top := setting_top(size.y)
	var focus: SettingChip = null
	for s in RouteGraph.SETTINGS.size():
		var which: String = RouteGraph.SETTINGS[s]
		var c := SettingChip.new()
		c.mission = n
		c.setting = which
		c.built = Progress.is_built(n)
		c.open = Progress.is_unlocked(n, which)
		c.cleared = Progress.is_cleared(n, which)
		c.best = Progress.best_time(n, which)
		c.score = Progress.best_score(n, which)
		c.needs =String(RouteGraph.SETTINGS[s - 1]).to_upper() if s > 0 else ""
		c.position = Vector2(14, top + s * (SETTING_H + SETTING_GAP))
		c.size = Vector2(size.x - 28, SETTING_H)
		c.pressed.connect(func() -> void: choose(n, which))
		_root.add_child(c)
		if c.playable() and (focus == null or Progress.key(n, which) == Progress.last):
			focus = c
	var end := top + 3.0 * SETTING_H + 2.0 * SETTING_GAP
	_place_wide(UiKit.label("BEST: FASTEST EXTRACTION, TOP SCORE", 8, Color(UiKit.DIM, 0.8), HORIZONTAL_ALIGNMENT_CENTER), end + 12.0)
	# The mission's scoreboard (on the setting last picked here, else EASY), and BACK, side by side.
	var on := Progress.last.get_slice(":", 1) if int(Progress.last.get_slice(":", 0)) == n else "easy"
	var board := _button("BOARD", end + 36.0, func() -> void: open_board(n, on, Screen.MISSION))
	board.offset_left = -112
	board.offset_right = -8
	board.disabled = not Progress.is_built(n)
	var back := _button("BACK", end + 36.0, func() -> void: _open(Screen.MISSIONS))
	back.offset_left = 8
	back.offset_right = 112
	(focus if focus != null else back).grab_focus()


func _build_settings() -> void:
	_header("SETTINGS", "AGENT PREFERENCES")
	var y := 90.0
	y = _section("AUDIO", y)
	y = _toggle_row("SOUND", "sound_on", y)
	y = _slider_row("MASTER", "master_volume", y)
	y = _slider_row("MUSIC", "music_volume", y)
	y = _slider_row("EFFECTS", "effects_volume", y)
	y = _slider_row("AMBIENCE", "ambience_volume", y)
	y = _section("DISPLAY", y + 4)
	y = _slider_row("BRIGHTNESS", "brightness", y, 50, 150)
	y = _toggle_row("SCREEN SHAKE", "screen_shake", y)
	y = _toggle_row("RETRO FILTER", "retro_filter", y)
	y = _toggle_row("BLOOD", "blood", y)
	y = _section("CONTROLS", y + 4)
	y = _choice_row("AIM", "aim", AIM_NAMES, y)
	y = _choice_row("TRIGGER", "fire_side", {"right": "RIGHT", "left": "LEFT"}, y)
	y = _choice_row("SWIPE", "swipe", SWIPE_NAMES, y)
	# RESET and BACK side by side, under the rows.
	var reset := _button("RESET", y + 10, func() -> void:
		Settings.reset()
		_show(Screen.SETTINGS))
	reset.offset_left = -112
	reset.offset_right = -8
	var back := _button("BACK", y + 10, func() -> void: _open(_back_to))
	back.offset_left = 8
	back.offset_right = 112
	back.grab_focus()


func _build_end() -> void:
	var info: Array = END_TITLES.get(_end_reason, ["MISSION FAILED", String(_end_reason).to_upper(), UiKit.RED])
	var col: Color = info[2]
	_root.add_child(Stamp.new(col))
	var title := UiKit.label(info[0], 16, col, HORIZONTAL_ALIGNMENT_CENTER)
	var sub := UiKit.label(info[1], 8, UiKit.PAPER, HORIZONTAL_ALIGNMENT_CENTER)
	_place_wide(title, 80)
	_place_wide(sub, 104)
	# The debrief (the LOCKED post-run route record): the route map, then the tally under it, with
	# the SCORE line (Tally.setup) at its foot.
	var w := _root.get_viewport_rect().size.x
	var panel := DebriefPanel.new()
	var tally := Tally.new()
	var outcome := score_outcome(_end_stats)
	tally.setup(_end_stats, outcome[0], outcome[1])
	panel.rect = Rect2(14, DEBRIEF_TOP, w - 28, TALLY_TOP + tally.needed_height() + 6.0 - DEBRIEF_TOP)
	_root.add_child(panel)
	var x := panel.rect.position.x + 10.0
	var inner := panel.rect.size.x - 20.0
	var typer := Typer.new()
	var area_typer := Typer.new()
	var map: RouteMap = null
	var graph = _end_stats.get("graph")
	if graph is RouteGraph:
		map = RouteMap.new()
		map.graph = graph
		var run: Array[StringName] = []
		for id in _end_stats.get("visited", []):
			run.append(StringName(id))
		map.visited = run
		map.discovered = _end_stats.get("discovered", {})
		map.end_reason = _end_reason
		map.end_into = float(_end_stats.get("end_into", 0.0))
		map.end_ramp = float(_end_stats.get("end_ramp", 0.0))
		map.position = Vector2(x, 156)
		map.size = Vector2(inner, 52)
		_root.add_child(map)
		if not run.is_empty():
			var where := UiKit.label("▶ " + graph.display_name(run[-1]), 8, col)
			where.position = Vector2(x, 213)
			_root.add_child(where)
			area_typer.add(where.text, 0.035, Typer.label_setter(where))
	# The title, subtitle and DEBRIEF type out (user: MGS-style, a tick a letter); the area's name as
	# the route map's line reaches it.
	typer.add(info[0], 0.05, Typer.label_setter(title))
	typer.add(info[1], 0.03, Typer.label_setter(sub))
	typer.add("DEBRIEF", 0.04, func(n: int) -> void: panel.shown = n)
	# Which mission and setting it was, across from DEBRIEF.
	var n := int(_end_stats.get("mission", 0))
	var which := String(_end_stats.get("setting", ""))
	if n >= 1 and n <= Progress.MISSIONS.size() and which != "":
		panel.tag = "%s / %s" % [Progress.MISSIONS[n - 1]["name"], which.to_upper()]
	# A new best time (user: the best for each setting), then what getting out opened (user: the
	# unlocks), under the buttons, typed out after DEBRIEF.
	var buttons_y := panel.rect.end.y + 4.0
	var y := buttons_y + 28.0
	var lines := PackedStringArray()
	var best := best_line(bool(_end_stats.get("new_best", false)), float(_end_stats.get("was_best", -1.0)))
	if best != "":
		lines.append(best)
	lines.append_array(unlock_lines(_end_stats.get("unlocked", []), n))
	for line in lines:
		var l := UiKit.label(line, 8, UiKit.AMBER if line == best else UiKit.GREEN, HORIZONTAL_ALIGNMENT_CENTER)
		_place_wide(l, y)
		typer.add(line, 0.03, Typer.label_setter(l))
		y += 12.0
	area_typer.delay = RouteMap.DRAW_TIME if map != null else 0.0
	for t in [typer, area_typer]:
		_root.add_child(t)
	tally.delay = maxf(RouteMap.DRAW_TIME + 0.3 if map != null else 0.3, typer.length() + 0.1)
	tally.position = Vector2(x, TALLY_TOP)
	tally.size = Vector2(inner, tally.needed_height())
	_root.add_child(tally)
	# A tap anywhere but the buttons shows it all at once.
	var skip := SkipArea.new()
	var show_all := func() -> void:
		typer.finish()
		area_typer.finish()
		if map != null:
			map.finish()
		tally.skip()
	skip.pressed.connect(show_all)
	_root.add_child(skip)
	if _end_done:
		show_all.call()  # (back from the board or the name entry: as it was left, nothing again)
	# (its sounds after that, so it's quiet when it's shown at once)
	for t in [typer, area_typer, tally]:
		t.typed.connect(func() -> void: typed.emit())
	tally.ticked.connect(func() -> void: tally_ticked.emit())
	tally.landed.connect(func() -> void: tally_landed.emit())
	tally.multiplied.connect(func() -> void: score_multiplied.emit())
	tally.stamped.connect(func() -> void: score_stamped.emit(tally.outcome_kind))
	# Once it's all shown: the name entry after a beat, if the run made the board and has no name yet
	# (user: up to 8 letters on big keys, filled in with CROSS); else it's simply done.
	tally.finished.connect(func() -> void:
		_end_done = true
		if not _name_pending:
			return
		var beat := Timer.new()
		beat.one_shot = true
		beat.wait_time = NAME_BEAT
		beat.ignore_time_scale = true
		beat.process_mode = Node.PROCESS_MODE_ALWAYS
		tally.add_child(beat)  # (it goes with the screen if that's closed first)
		beat.timeout.connect(func() -> void:
			if _screen == Screen.END and _name_pending:
				_open_name())
		beat.start())
	if tally.is_done():
		_end_done = true
	# RETRY, BOARD and MAIN MENU side by side (the run's board: the name entry first if its entry has
	# no name yet; none for a run with no board, the TEST RANGE).
	var first := _button("RETRY", buttons_y, func() -> void: retry_requested.emit())
	var second := _button("BOARD", buttons_y, func() -> void:
		if _name_pending:
			_open_name()
		else:
			open_board(n, which, Screen.END, int(_end_stats.get("seq", 0)) if int(_end_stats.get("rank", 0)) > 0 else 0))
	var third := _button("MAIN MENU", buttons_y, func() -> void: menu_requested.emit())
	for i in 3:
		var b: Button = [first, second, third][i]
		b.offset_left = -126.0 + i * 86.0
		b.offset_right = b.offset_left + 80.0
	var has_board := Progress.is_built(n) and which in RouteGraph.SETTINGS
	second.disabled = not has_board
	if _end_guard and not _end_done:
		for b: Button in [first, second, third]:
			b.disabled = true
			b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# (the wait is the button's own: it goes with the screen if that's closed first)
		var wait := Timer.new()
		wait.one_shot = true
		wait.wait_time = END_GUARD
		wait.ignore_time_scale = true
		wait.process_mode = Node.PROCESS_MODE_ALWAYS
		first.add_child(wait)
		wait.timeout.connect(func() -> void:
			for b: Button in [first, second, third]:
				b.disabled = b == second and not has_board
				b.mouse_filter = Control.MOUSE_FILTER_STOP
			first.grab_focus())
		wait.start()
	else:
		first.grab_focus()


## The name entry, for the run's entry on its board.
func _open_name() -> void:
	_name = Progress.last_name
	_name_fresh = true
	_show(Screen.NAME)


## The debrief's panel's top and the tally's (px); the pause after the tally before the name entry
## opens (s).
const DEBRIEF_TOP := 132.0
const TALLY_TOP := 236.0
const NAME_BEAT := 1.0
## The name entry's keys (user: "A-Z 0-9 space . -, DEL, OK"), 7 across, as they're laid out; " " is
## the space key, and OK takes two keys' room.
const KEY_ROWS := [["A", "B", "C", "D", "E", "F", "G"], ["H", "I", "J", "K", "L", "M", "N"], ["O", "P", "Q", "R", "S", "T", "U"],
		["V", "W", "X", "Y", "Z", "0", "1"], ["2", "3", "4", "5", "6", "7", "8"], ["9", ".", "-", " ", "DEL", "OK"]]
## A key's size and the gap between keys (px).
const KEY_SIZE := Vector2(34, 30)
const KEY_GAP := 2.0


## The name entry's keys' top on a screen `height` high: low on the screen, where a thumb reaches
## (60 px clear of the bottom), but never up into the name above them.
static func name_grid_top(height: float) -> float:
	var grid_h := KEY_ROWS.size() * (KEY_SIZE.y + KEY_GAP) - KEY_GAP
	return maxf(88.0 + tall_shift(height, 50.0) + 72.0, height - 60.0 - grid_h)


## How far down a tall screen moves a menu block (px): half the extra height over 480, up to `most`.
static func tall_shift(height: float, most: float = 60.0) -> float:
	return clampf(floorf((height - 480.0) / 2.0), 0.0, most)


## The name entry (a run made the board's top 10; user: "names up to 8 letters on big on-screen keys
## pre-filled with CROSS (last name used after that)"): NEW ENTRY #N, the score, the name in eight
## slots, and a grid of big keys (A-Z, 0-9, space, full stop, hyphen; DEL, OK), never the phone's
## own keyboard (it covers half the screen in Safari). A computer's keyboard types too. OK saves the
## name and opens the board, the entry blinking on it. Skipped (RETRY or MAIN MENU before it opened),
## the entry keeps the name it was filled in with.
func _build_name() -> void:
	var rank := int(_end_stats.get("rank", 0))
	_header("NEW ENTRY #%d" % rank, "ENTER YOUR NAME")
	var size := _root.get_viewport_rect().size
	var top := name_grid_top(size.y) - 72.0  # (the score and the name just above the keys)
	var n := int(_end_stats.get("mission", 0))
	var which := String(_end_stats.get("setting", ""))
	_place_wide(UiKit.label(Score.format(int(_end_stats.get("score", 0))), 16, UiKit.AMBER, HORIZONTAL_ALIGNMENT_CENTER), top)
	if n >= 1 and n <= Progress.MISSIONS.size():
		_place_wide(UiKit.label("%s / %s" % [Progress.MISSIONS[n - 1]["name"], which.to_upper()], 8, UiKit.DIM, HORIZONTAL_ALIGNMENT_CENTER), top + 20.0)
	var slots := NameSlots.new()
	slots.text = _name
	slots.position = Vector2(roundf((size.x - NameSlots.width()) / 2.0), top + 36.0)
	slots.size = Vector2(NameSlots.width(), NameSlots.H)
	_root.add_child(slots)
	var grid_top := name_grid_top(size.y)
	var left := roundf((size.x - (7.0 * KEY_SIZE.x + 6.0 * KEY_GAP)) / 2.0)
	var ok: KeyCap = null
	for r in KEY_ROWS.size():
		var col := 0
		for k: String in KEY_ROWS[r]:
			var cap := KeyCap.new()
			cap.key = k
			var cells := 2 if k == "OK" else 1
			cap.position = Vector2(left + col * (KEY_SIZE.x + KEY_GAP), grid_top + r * (KEY_SIZE.y + KEY_GAP))
			cap.size = Vector2(KEY_SIZE.x * cells + KEY_GAP * (cells - 1), KEY_SIZE.y)
			cap.pressed.connect(func() -> void:
				clicked.emit()
				press_key(k))
			_root.add_child(cap)
			if k == "OK":
				ok = cap
			col += cells
	var keys := NameKeys.new()
	keys.typed.connect(func(k: String) -> void:
		clicked.emit()
		press_key(k))
	_root.add_child(keys)
	ok.grab_focus()


## The scoreboard: mission n's top 10 on a setting (the cast's entries and his: Progress.board), each
## with its place, name, score, ending and the highest alert in its colour; never the route (LOCKED:
## areas you haven't found stay unknown). EASY / MEDIUM / HARD switch it; his entries are teal, the one
## just entered blinks. BACK goes where it was opened from.
func _build_board() -> void:
	var n := _board_mission
	_header("HIGH SCORES", "MISSION %02d: %s" % [n, Progress.MISSIONS[n - 1]["name"]])
	var size := _root.get_viewport_rect().size
	var tab_w := floorf((size.x - 28.0 - 2.0 * 6.0) / 3.0)
	var focus: Button = null
	for i in RouteGraph.SETTINGS.size():
		var s: String = RouteGraph.SETTINGS[i]
		var tab := BoardTab.new()
		tab.setting = s
		tab.on = s == _board_setting
		tab.position = Vector2(14.0 + i * (tab_w + 6.0), BOARD_TABS)
		tab.size = Vector2(tab_w, 16)
		tab.pressed.connect(func() -> void:
			clicked.emit()
			if s != _board_setting:
				_board_setting = s
				_board_flash = 0 if _board_back != Screen.END or s != String(_end_stats.get("setting", "")) else _board_flash
				_show(Screen.BOARD)
				var again := board_tab(s)
				if again != null:
					again.grab_focus())
		_root.add_child(tab)
		if tab.on:
			focus = tab
	var step := board_step(size.y)
	var entries := Progress.board(n, _board_setting)
	for i in entries.size():
		var e: Dictionary = entries[i]
		var row := BoardRow.new()
		row.rank = i + 1
		row.entry = e
		row.mine = not e["house"]
		row.flash = row.mine and _board_flash > 0 and int(e["seq"]) == _board_flash
		row.position = Vector2(14, BOARD_ROWS + i * step)
		row.size = Vector2(size.x - 28, step - 4.0)
		_root.add_child(row)
	var back := _button("BACK", BOARD_ROWS + Progress.BOARD_SIZE * step + 4.0, func() -> void:
		if _board_back == Screen.END:
			_show(Screen.END)  # (as it was left: _end_done)
		else:
			_open(_board_back))
	(focus if focus != null else back).grab_focus()


## The board's switch and its first row (px).
const BOARD_TABS := 88.0
const BOARD_ROWS := 112.0


## How far apart the board's rows are (px) on a screen `height` high (BACK under the last).
static func board_step(height: float) -> float:
	return clampf(floorf((height - BOARD_ROWS - 40.0) / Progress.BOARD_SIZE), 28.0, 40.0)


## The board's switch for `setting` (while it's up), else null.
func board_tab(setting: String) -> Button:
	for c in _root.get_children():
		if c is BoardTab and not c.is_queued_for_deletion() and c.setting == setting:
			return c
	return null


## The board's rows (while it's up), top first.
func board_rows() -> Array:
	return _root.get_children().filter(func(c: Node) -> bool: return c is BoardRow and not c.is_queued_for_deletion())


# --- Building blocks ------------------------------------------------------------------

func _open(s: Screen) -> void:
	if s in [Screen.MAIN, Screen.PAUSE]:
		_back_to = s
	_show(s)


func _header(title: String, sub: String) -> void:
	var bar := HeaderBar.new()
	_root.add_child(bar)
	_place_wide(UiKit.label(title, 16, UiKit.TEAL, HORIZONTAL_ALIGNMENT_CENTER), 44)
	_place_wide(UiKit.label("// " + sub, 8, UiKit.DIM, HORIZONTAL_ALIGNMENT_CENTER), 66)


func _place_wide(c: Control, y: float) -> void:
	c.set_anchors_preset(Control.PRESET_TOP_WIDE)
	c.offset_top = y
	_root.add_child(c)


func _button(text: String, y: float, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.set_anchors_preset(Control.PRESET_CENTER_TOP)
	b.offset_left = -78
	b.offset_right = 78
	b.offset_top = y
	b.offset_bottom = y + 20
	b.pressed.connect(func() -> void:
		clicked.emit()
		action.call())
	_root.add_child(b)
	return b


func _section(title: String, y: float) -> float:
	var l := UiKit.label(title, 8, UiKit.RED)
	l.position = Vector2(20, y)
	_root.add_child(l)
	var line := ColorRect.new()
	line.color = Color(UiKit.RED, 0.5)
	line.position = Vector2(20 + title.length() * 6 + 4, y + 4)
	line.size = Vector2(230 - title.length() * 6 - 4, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(line)
	return y + 17.0


func _row_label(text: String, y: float) -> void:
	var l := UiKit.label(text, 8, UiKit.PAPER)
	l.position = Vector2(26, y + 3)
	_root.add_child(l)


func _toggle_row(text: String, key: String, y: float) -> float:
	_row_label(text, y)
	var b := Button.new()
	var on: bool = Settings.get_value(key)
	b.text = "ON" if on else "OFF"
	b.theme_type_variation = "CompactButton"
	_root.add_child(b)  # in the menu first, so its theme (and small size) applies
	b.position = Vector2(192, y - 1)  # level with the label
	b.size = Vector2(48, 15)
	b.pressed.connect(func() -> void:
		clicked.emit()
		Settings.set_value(key, not bool(Settings.get_value(key)))
		b.text = "ON" if Settings.get_value(key) else "OFF")
	return y + 22.0


func _slider_row(text: String, key: String, y: float, lo: float = 0, hi: float = 100) -> float:
	_row_label(text, y)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 5
	s.value = float(Settings.get_value(key))
	s.position = Vector2(140, y + 2)
	s.size = Vector2(80, 10)
	_root.add_child(s)
	var v := UiKit.label(str(int(s.value)), 8, UiKit.TEAL)
	v.position = Vector2(226, y + 3)
	_root.add_child(v)
	s.value_changed.connect(func(val: float) -> void:
		v.text = str(int(val))
		Settings.set_value(key, int(val)))
	return y + 22.0


func _choice_row(text: String, key: String, names: Dictionary, y: float) -> float:
	_row_label(text, y)
	var b := Button.new()
	b.text = "< %s >" % names.get(Settings.get_value(key), "?")
	b.theme_type_variation = "CompactButton"
	_root.add_child(b)
	b.position = Vector2(146, y - 1)
	b.size = Vector2(94, 15)
	b.pressed.connect(func() -> void:
		clicked.emit()
		var keys := names.keys()
		var i := (keys.find(Settings.get_value(key)) + 1) % keys.size()
		Settings.set_value(key, keys[i])
		b.text = "< %s >" % names[keys[i]])
	return y + 22.0


## The main menu's backdrop: a gun-barrel reticle (a GoldenEye nod) behind the title.
## The game's name (user: "Hot exfil sounds cool"; the slanted-block logo from the mockups, in the
## game's own pixel font): HOT on a solid red block, EXFIL on a dark block outlined in teal, one
## over the other, both leaning like the game's other slanted blocks, a hard shadow under each.
class Logo extends Control:
	## The letters' size (the pixel font is crisp at 8, 16 or 24), a block's padding round them, how far
	## its top leans right of its bottom, the gap between the two, and the whole logo's height.
	const SIZE := 24
	const PAD := Vector2(9, 3)
	const SLANT := 7.0
	const GAP := 4.0
	const SHADOW := Vector2(3, 3)
	## HOT and EXFIL side by side on one row (else one over the other).
	static var one_row := false
	static func height() -> float:
		return SIZE + PAD.y * 2.0 + SHADOW.y if one_row else (SIZE + PAD.y * 2.0) * 2.0 + GAP + SHADOW.y

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var f := UiKit.font()
		var parts := [["HOT", UiKit.RED, UiKit.INK, false], ["EXFIL", UiKit.PANEL_SOLID, UiKit.TEAL, true]]
		var widths := []
		for row in parts:
			widths.append(f.get_string_size(String(row[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE).x + PAD.x * 2.0 + SLANT)
		var x := roundf((size.x - (float(widths[0]) + GAP * 1.5 + float(widths[1]))) / 2.0)
		var y := 0.0
		for i in parts.size():
			var row: Array = parts[i]
			var text: String = row[0]
			var r := Rect2(x if one_row else roundf((size.x - float(widths[i])) / 2.0), y, widths[i], SIZE + PAD.y * 2.0)
			draw_colored_polygon(_lean(Rect2(r.position + SHADOW, r.size)), Color(UiKit.INK, 0.9))
			draw_colored_polygon(_lean(r), row[1])
			if row[3]:
				var edge := _lean(r)
				edge.append(edge[0])
				draw_polyline(edge, UiKit.TEAL, 2.0)
			draw_string(f, Vector2(r.position.x + PAD.x + SLANT * 0.5, r.position.y + PAD.y + f.get_ascent(SIZE)), text,
					HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE, row[2])
			if one_row:
				x += r.size.x + GAP * 1.5
			else:
				y += r.size.y + GAP

	## A block's shape: the box with its top leaning SLANT right of its bottom.
	static func _lean(r: Rect2) -> PackedVector2Array:
		return PackedVector2Array([r.position + Vector2(SLANT, 0.0), Vector2(r.end.x, r.position.y),
				r.end - Vector2(SLANT, 0.0), Vector2(r.position.x, r.end.y)])


class Reticle extends Control:
	## The lower red rule's height (under the mission line: the main menu sets it).
	static var rule_bottom := 166.0
	## The rings' centre height (behind the logo: the main menu sets it).
	static var ring_y := 122.0
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)  # added already: size it now

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var c := Vector2(get_viewport_rect().size.x / 2.0, ring_y)
		for i in 4:
			draw_arc(c, 34.0 + i * 16.0, 0, TAU, 40, Color(UiKit.TEAL, 0.18 - i * 0.03), 1.0)
		var a := _t * 0.4
		for k in 4:
			var d := Vector2(cos(a + k * PI / 2.0), sin(a + k * PI / 2.0))
			draw_line(c + d * 26.0, c + d * 98.0, Color(UiKit.TEAL, 0.12), 1.0)
		draw_rect(Rect2(0, 62, get_viewport_rect().size.x, 1), Color(UiKit.RED, 0.4))
		draw_rect(Rect2(0, rule_bottom, get_viewport_rect().size.x, 1), Color(UiKit.RED, 0.4))


## A dossier header strip across the top of a menu screen.
class HeaderBar extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)  # added already: size it now

	func _draw() -> void:
		var w := get_viewport_rect().size.x
		UiKit.panel(self, Rect2(12, 34, w - 24, 46), UiKit.TEAL, UiKit.PANEL_SOLID, 8.0)


## The end screen's stamp: a big angled frame in the result's colour.
class Stamp extends Control:
	var col: Color

	func _init(c: Color) -> void:
		col = c

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)  # added already: size it now

	func _draw() -> void:
		var w := get_viewport_rect().size.x
		UiKit.panel(self, Rect2(14, 70, w - 28, 50), col, UiKit.PANEL_SOLID, 10.0)


## The debrief's codec panel: its header, and a rule between the route map and the tally (which
## are their own controls, laid over it: RouteMap and Tally).
class DebriefPanel extends Control:
	var rect := Rect2()
	## The mission and setting played (right of DEBRIEF), once DEBRIEF has typed out.
	var tag := ""
	## Letters of its header shown (it types out).
	var shown := 7:
		set(n):
			shown = n
			queue_redraw()

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)  # added already: size it now

	func _draw() -> void:
		UiKit.panel(self, rect, UiKit.TEAL, UiKit.PANEL_SOLID, 8.0)
		var x := rect.position.x + 10.0
		draw_string(UiKit.font(), Vector2(x, rect.position.y + 16), "DEBRIEF".substr(0, shown), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, UiKit.RED)
		if tag != "" and shown >= 7:
			var w := UiKit.font().get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
			draw_string(UiKit.font(), Vector2(rect.end.x - 10.0 - w, rect.position.y + 16), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, UiKit.DIM)
		draw_rect(Rect2(x, rect.position.y + 96, rect.size.x - 20.0, 1), Color(UiKit.TEAL_DIM, 0.8))


## The end screen behind its buttons: a tap on it skips the route map and tally to the end.
class SkipArea extends Control:
	signal pressed

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)  # added already: size it now

	func _gui_input(event: InputEvent) -> void:
		if (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed):
			pressed.emit()
			accept_event()


## A mission's file tab in the mission select, a button: its number on a slanted block, its name,
## and on the right a small mark for each of its settings (E, M, H: green once he's got out on it,
## teal while it's open, a padlock while it's locked), or COMING SOON for one not built yet. Pickable
## (it opens the mission's screen) when it's built and a setting is open; greyed otherwise.
class MissionRow extends Button:
	const MARK := Vector2(13.0, 11.0)
	const MARK_GAP := 3.0
	var number := 1
	var title := ""
	var built := true
	## Per setting (RouteGraph.SETTINGS' order): open, and got out of.
	var unlocked := []
	var cleared := []
	## His best time on each (s; < 0: none yet).
	var best := []

	## A best time on a mission row, to the second (never shown better than he did): "1:21"; "--"
	## for none.
	static func best_text(t: float) -> String:
		if t < 0.0:
			return "--"
		var s := floori(t)
		return "%d:%02d" % [s / 60, s % 60]

	## Whether mission n's row can be picked now: built, with a setting open.
	static func can_open(n: int) -> bool:
		if not Progress.is_built(n):
			return false
		for s in RouteGraph.SETTINGS:
			if Progress.is_unlocked(n, s):
				return true
		return false

	func playable() -> bool:
		return built and unlocked.has(true)

	func _ready() -> void:
		flat = true
		text = ""
		disabled = not playable()
		focus_mode = Control.FOCUS_ALL if playable() else Control.FOCUS_NONE
		mouse_filter = Control.MOUSE_FILTER_STOP
		add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var mode := get_draw_mode()
		var on := playable()
		var accent := UiKit.TEAL_DIM if on else Color(UiKit.DIM, 0.45)
		var fill := UiKit.PANEL_SOLID if on else Color(0.02, 0.04, 0.05, 0.9)
		if on and mode in [DRAW_PRESSED, DRAW_HOVER_PRESSED]:
			accent = UiKit.RED
			fill = Color(0.2, 0.05, 0.04, 0.95)
		elif on and (has_focus() or mode == DRAW_HOVER):
			accent = UiKit.TEAL
			fill = Color(0.04, 0.12, 0.12, 0.95)
		UiKit.panel(self, r, accent, fill, 6.0)
		var f := UiKit.font()
		var mid := roundf(size.y / 2.0)
		var block := Rect2(9.0, mid - 7.0, 23.0, 13.0)
		draw_colored_polygon(SettingChip.lean(block, 3.0), UiKit.RED if built else Color("3a2a28"))
		draw_string(f, Vector2(block.position.x + 5.0, mid + 3.0), "%02d" % number, HORIZONTAL_ALIGNMENT_LEFT, -1, 8,
				UiKit.INK if built else Color(UiKit.DIM, 0.8))
		var ink := UiKit.PAPER if on else UiKit.DIM
		if on and (has_focus() or mode == DRAW_HOVER):
			ink = UiKit.TEAL
		if not built:
			draw_string(f, Vector2(40.0, mid + 3.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, ink)
			var soon := "COMING SOON"
			var w := f.get_string_size(soon, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
			draw_string(f, Vector2(size.x - w - 10.0, mid + 3.0), soon, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(UiKit.AMBER, 0.75))
			return
		# Built: its name, and under it his best time on each setting (user: "it could display the
		# best time for that mission ... E for easy, M for medium, H for hard"): "E 1:21  M --  H --".
		draw_string(f, Vector2(40.0, mid - 2.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, ink)
		var bx := 40.0
		for s in RouteGraph.SETTINGS.size():
			var t: float = best[s] if s < best.size() else -1.0
			var letter := String(RouteGraph.SETTINGS[s]).substr(0, 1).to_upper()
			draw_string(f, Vector2(bx, mid + 9.0), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(UiKit.DIM, 0.9))
			var v := best_text(t)
			draw_string(f, Vector2(bx + 12.0, mid + 9.0), v, HORIZONTAL_ALIGNMENT_LEFT, -1, 8,
					UiKit.AMBER if t >= 0.0 else Color(UiKit.DIM, 0.6))
			bx += 12.0 + f.get_string_size(v, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x + 10.0
		# The marks, one per setting, right-aligned.
		var x := size.x - 10.0 - 3.0 * MARK.x - 2.0 * MARK_GAP
		for s in RouteGraph.SETTINGS.size():
			var m := Rect2(x + s * (MARK.x + MARK_GAP), mid - floorf(MARK.y / 2.0) - 1.0, MARK.x, MARK.y)
			var open: bool = s < unlocked.size() and unlocked[s]
			var done: bool = s < cleared.size() and cleared[s]
			var shape := SettingChip.lean(m, 2.0)
			if done:
				draw_colored_polygon(shape, UiKit.GREEN)
			else:
				draw_colored_polygon(shape, Color(0.03, 0.07, 0.08, 0.9))
				var edge := shape.duplicate()
				edge.append(shape[0])
				draw_polyline(edge, UiKit.TEAL_DIM if open else Color("2a3a3a"), 1.0)
			if open or done:
				var letter := String(RouteGraph.SETTINGS[s]).substr(0, 1).to_upper()
				draw_string(f, Vector2(m.position.x + 4.0, m.position.y + 9.0), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 8,
						UiKit.INK if done else UiKit.PAPER)
			else:
				UiKit.draw_padlock(self, Vector2(m.position.x + 4.0, m.position.y + 2.0), Color(UiKit.DIM, 0.6))


## One setting of one mission on the mission's screen (EASY, MEDIUM or HARD), a big slanted block
## like the game's other buttons: the setting's name, whether he's got out on it, and his best time
## there on the right ("--" until he has one). Teal-edged and pickable when it's open and its mission
## is built; greyed with a big padlock while it's locked (user: "locked ones greyed with a padlock"),
## saying what clears it, and not pickable.
class SettingChip extends Button:
	const SLANT := 8.0
	var mission := 1
	var setting := "easy"
	var built := true
	var open := false
	var cleared := false
	## His best time on it (s; < 0: none yet), and his top score on its board (< 0: none yet).
	var best := -1.0
	var score := -1
	## The setting to clear to open it ("" for EASY).
	var needs := ""

	func playable() -> bool:
		return built and open

	func _ready() -> void:
		flat = true
		text = ""
		disabled = not playable()
		focus_mode = Control.FOCUS_ALL if playable() else Control.FOCUS_NONE
		mouse_filter = Control.MOUSE_FILTER_STOP
		add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var mode := get_draw_mode()
		var fill := Color(0.03, 0.08, 0.09, 0.92)
		var edge := UiKit.TEAL_DIM
		var ink := UiKit.PAPER
		if not playable():
			fill = Color(0.03, 0.05, 0.05, 0.8)
			edge = Color("223333")
			ink = Color(UiKit.DIM, 0.6)
		elif mode in [DRAW_PRESSED, DRAW_HOVER_PRESSED]:
			fill = Color(0.35, 0.08, 0.05, 0.95)
			edge = UiKit.RED
		elif has_focus() or mode == DRAW_HOVER:
			fill = Color(0.05, 0.16, 0.16, 0.95)
			edge = UiKit.TEAL
			ink = UiKit.TEAL
		var shape := lean(r, SLANT)
		draw_colored_polygon(shape, fill)
		var y := 2.0
		while y < size.y - 1.0:  # (faint scanlines, like the codec panels)
			draw_line(Vector2(SLANT * (1.0 - y / size.y) + 2.0, y), Vector2(size.x - SLANT * y / size.y - 1.0, y), Color(edge, 0.07), 1.0)
			y += 2.0
		var line := shape.duplicate()
		line.append(shape[0])
		draw_polyline(line, edge, 1.0)
		draw_line(shape[3] + Vector2(1, 0), shape[0] + Vector2(1, 0), edge, 3.0)  # the heavier leading edge, like a tab
		var f := UiKit.font()
		# Left: the setting's name (16 px), and under it whether he's got out on it (or what opens it).
		var top := roundf(size.y / 2.0) - 14.0
		draw_string(f, Vector2(SLANT + 12.0, top + 14.0), setting.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, ink)
		var status := "CLEARED" if cleared else "NOT CLEARED YET"
		var status_col := UiKit.GREEN if cleared else Color(UiKit.DIM, 0.9)
		if not open:
			status = "CLEAR %s TO UNLOCK" % needs if needs != "" else "LOCKED"
			status_col = Color(UiKit.DIM, 0.7)
		elif not built:
			status = "COMING SOON"
			status_col = Color(UiKit.AMBER, 0.75)
		draw_string(f, Vector2(SLANT + 8.0, top + 28.0), status, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, status_col)
		# Right: a big padlock while it's locked; else BEST over his time.
		var right := size.x - SLANT - 12.0
		if not open:
			UiKit.draw_padlock(self, Vector2(right - 15.0, roundf(size.y / 2.0) - 10.0), ink, 3)
			return
		var label := "BEST"
		var t := Frontend.time_text(best) if best >= 0.0 else "--"
		draw_string(f, Vector2(right - f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x, top + 4.0), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(UiKit.DIM, 0.9))
		draw_string(f, Vector2(right - f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x, top + 26.0), t,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiKit.AMBER if best >= 0.0 else Color(UiKit.DIM, 0.6))
		# Under it, his top score on its board (the scoreboard: "--" until he has one).
		var pts := "%s PTS" % Score.format(score) if score >= 0 else "-- PTS"
		draw_string(f, Vector2(right - f.get_string_size(pts, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x, top + 40.0), pts,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 8, UiKit.TEAL if score >= 0 else Color(UiKit.DIM, 0.6))

	## A block's shape: the box with its top leaning `slant` right of its bottom.
	static func lean(r: Rect2, slant: float) -> PackedVector2Array:
		return PackedVector2Array([r.position + Vector2(slant, 0.0), Vector2(r.end.x, r.position.y),
				r.end - Vector2(slant, 0.0), Vector2(r.position.x, r.end.y)])


## The name entry's name: eight slots in a row, a letter (16 px) in each so far, the next slot's
## underline blinking (the cursor).
class NameSlots extends Control:
	const SLOT := Vector2(20, 22)
	const GAP := 4.0
	const H := 22.0
	var text := ""
	var _t := 0.0

	static func width() -> float:
		return Progress.NAME_MAX * (SLOT.x + GAP) - GAP

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var f := UiKit.font()
		for i in Progress.NAME_MAX:
			var r := Rect2(i * (SLOT.x + GAP), 0, SLOT.x, SLOT.y)
			draw_rect(r, Color(0.03, 0.08, 0.09, 0.92))
			var cursor := i == text.length()
			var line := UiKit.TEAL if cursor and fmod(_t, 0.8) < 0.5 else UiKit.TEAL_DIM
			draw_rect(Rect2(r.position.x, r.end.y - 2.0, r.size.x, 2.0), line)
			if i < text.length():
				var ch := text[i]
				var w := f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
				draw_string(f, Vector2(r.position.x + roundf((r.size.x - w) / 2.0) + 1.0, r.position.y + 17.0), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiKit.PAPER)


## One of the name entry's big keys: a slanted block like the game's other buttons, its letter in
## 16 px (SP for the space; DEL; OK in red).
class KeyCap extends Button:
	const SLANT := 3.0
	var key := "A"

	func _ready() -> void:
		flat = true
		text = ""
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	func _draw() -> void:
		var mode := get_draw_mode()
		var fill := Color(0.03, 0.08, 0.09, 0.92)
		var edge := UiKit.TEAL_DIM
		var ink := UiKit.PAPER
		if key == "OK":
			fill = Color(0.24, 0.06, 0.04, 0.95)
			edge = UiKit.RED
		if mode in [DRAW_PRESSED, DRAW_HOVER_PRESSED]:
			fill = Color(0.35, 0.08, 0.05, 0.95)
			edge = UiKit.RED
		elif has_focus() or mode == DRAW_HOVER:
			fill = Color(0.45, 0.1, 0.06, 0.95) if key == "OK" else Color(0.05, 0.16, 0.16, 0.95)
			edge = UiKit.PAPER if key == "OK" else UiKit.TEAL
			ink = UiKit.PAPER if key == "OK" else UiKit.TEAL
		var shape := SettingChip.lean(Rect2(Vector2.ZERO, size), SLANT)
		draw_colored_polygon(shape, fill)
		var line := shape.duplicate()
		line.append(shape[0])
		draw_polyline(line, edge, 1.0)
		var f := UiKit.font()
		var label: String = {" ": "SP"}.get(key, key)
		var px := 16 if label.length() == 1 else 8
		var w := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		draw_string(f, Vector2(roundf((size.x - w) / 2.0) + 1.0, roundf(size.y / 2.0) + (7.0 if px == 16 else 4.0)), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, px, ink)


## A computer's keyboard on the name entry: letters, numbers, space, full stop and hyphen type;
## Backspace is DEL, Enter is OK.
class NameKeys extends Node:
	signal typed(key: String)

	func _input(event: InputEvent) -> void:
		var k := event as InputEventKey
		if k == null or not k.pressed or k.echo:
			return
		var out := ""
		match k.keycode:
			KEY_BACKSPACE, KEY_DELETE:
				out = "DEL"
			KEY_ENTER, KEY_KP_ENTER:
				out = "OK"
			_:
				var ch := String.chr(k.unicode).to_upper() if k.unicode > 0 else ""
				if ch.length() == 1 and Progress.NAME_CHARS.contains(ch):
					out = ch
		if out != "":
			get_viewport().set_input_as_handled()
			typed.emit(out)


## The board's EASY / MEDIUM / HARD switch: a small slanted tab, filled teal when it's the one shown.
class BoardTab extends Button:
	var setting := "easy"
	var on := false

	func _ready() -> void:
		flat = true
		text = ""
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	func _draw() -> void:
		var mode := get_draw_mode()
		var fill := UiKit.TEAL if on else Color(0.03, 0.08, 0.09, 0.92)
		var edge := UiKit.TEAL if on else UiKit.TEAL_DIM
		var ink := UiKit.INK if on else UiKit.PAPER
		if mode in [DRAW_PRESSED, DRAW_HOVER_PRESSED]:
			fill = Color(0.35, 0.08, 0.05, 0.95)
			edge = UiKit.RED
			ink = UiKit.PAPER
		elif not on and (has_focus() or mode == DRAW_HOVER):
			edge = UiKit.TEAL
			ink = UiKit.TEAL
		var shape := SettingChip.lean(Rect2(Vector2.ZERO, size), 4.0)
		draw_colored_polygon(shape, fill)
		var line := shape.duplicate()
		line.append(shape[0])
		draw_polyline(line, edge, 1.0)
		if has_focus() and on:
			draw_polyline(line, UiKit.PAPER, 1.0)
		var f := UiKit.font()
		var label := setting.to_upper()
		var w := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
		draw_string(f, Vector2(roundf((size.x - w) / 2.0) + 1.0, 11.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, ink)


## One place on the board: its number on a slanted block, the name and the score; under them, how
## the run ended and its highest alert (in its colour). His own entries are teal; the one just
## entered blinks. Never the route (LOCKED).
class BoardRow extends Control:
	## How each ending reads (the end conversations' tags).
	const ENDINGS := {"extracted": ["EXFIL COMPLETE", UiKit.GREEN], "killed": ["AGENT DOWN", UiKit.RED],
			"captured": ["AGENT CAPTURED", UiKit.AMBER], "chopper_left": ["METER RAN OUT", UiKit.RED], "dead_end": ["NO WAY THROUGH", UiKit.RED]}
	var rank := 1
	var entry := {}
	var mine := false
	var flash := false
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		if flash:
			_t += delta
			queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		UiKit.panel(self, r, UiKit.TEAL if mine else UiKit.TEAL_DIM, Color(0.04, 0.12, 0.12, 0.95) if mine else UiKit.PANEL_SOLID, 6.0)
		var f := UiKit.font()
		var mid := roundf(size.y / 2.0)
		var block := Rect2(8.0, mid - 7.0, 23.0, 13.0)
		draw_colored_polygon(SettingChip.lean(block, 3.0), UiKit.TEAL if mine else UiKit.RED)
		draw_string(f, Vector2(block.position.x + 5.0, mid + 3.0), "%02d" % rank, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, UiKit.INK)
		var lit := not flash or fmod(_t, 0.6) < 0.4
		var ink := UiKit.TEAL if mine else UiKit.PAPER
		if lit:
			draw_string(f, Vector2(40.0, mid - 2.0), String(entry.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, ink)
			var score := Score.format(int(entry.get("score", 0)))
			draw_string(f, Vector2(0, mid - 2.0), score, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 10.0, 8, UiKit.AMBER)
		var end: Array = ENDINGS.get(String(entry.get("ending", "")), [String(entry.get("ending", "")).to_upper(), UiKit.DIM])
		draw_string(f, Vector2(40.0, mid + 9.0), end[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(end[1], 0.8))
		var alert := clampi(int(entry.get("alert", 1)), 1, 3)
		draw_string(f, Vector2(0, mid + 9.0), Tally.ALERT_NAMES[alert], HORIZONTAL_ALIGNMENT_RIGHT, size.x - 10.0, 8, Tally.ALERT_COLORS[alert])
