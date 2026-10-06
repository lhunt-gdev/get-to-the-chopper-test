class_name Briefing
extends Control
## The mission briefing (user): after START MISSION and before the opening pan, a conversation
## between CROSS, his General and the mission briefer, in the game's own chunky, slanted look (the
## GTA-style blocks of the menus and the HUD), not a codec. The two faces are tilted, slanted cards on
## a diagonal: whoever CROSS is talking to up on the left, CROSS down on the right (user: "CROSS
## should be in the right"), each with a bold name plate. The pictures are under a teal CRT effect like
## the HUD (codec_portrait.gdshader). Between the cards the line being said comes in on slanted
## subtitle strips, one a row, sliding in from the speaker's side and typing out a letter at a time
## with the speaker's name first: "[CROSS] ...". The speaker's card is lit and forward, the
## listener's dimmed and pushed back; a new caller's card flips over through a burst of static.
## Nothing else moves on: the run and the chopper's clock haven't started.
##
## A tap finishes the line being typed; the next tap shows the next line; after the last line it
## closes (then the pan and the run follow). SKIP (up in the top bar, where the pause button is in
## the run, away from the reading taps; or Esc) closes it at once. One tap reaches a control as two
## events (a touch and the click emulated from it, in the same frame): it counts once. A tap that
## lands just as a line finishes typing on its own counts as finishing it, not as "next".
##
## The script is data (briefing.json, next to the level): load_file(), then problems(). Each cast
## member's name is set once there; "{general}" in a line becomes the General's name.

## Closed (SKIP, or a tap after the last line), once its screen has gone.
signal finished
## A letter typed (the level plays a tick). Spaces are silent.
signal typed
## A sound to play: the call, the cards coming in, static, the cards going.
signal cue(sound: String, volume_db: float)

enum Phase { OPENING, TALKING, CLOSING, DONE }

## Who's always in the right card; everyone else takes the left.
const PLAYER := "cross"
## The most letters a name can have: it's shown big on the name plate by its card.
const NAME_MOST := 12
## Letters a text row holds, and rows a line can have (the speaker's [NAME] included).
const COLS := 39
const ROWS := 5
const ROW_H := 12.0
## Typing: seconds a letter, and the extra pause after a full stop and after a comma.
const PER_LETTER := 0.03
const PAUSE_STOP := 0.16
const PAUSE_COMMA := 0.07
## A tap this soon (s) after a line finished typing on its own was meant to finish it: not "next".
const GRACE := 0.2
## The opening: the call, the cards whipping in from their sides, the two faces switching on (a
## CRT: a dot, a line, the picture), the first line.
const OPEN_FROM := 0.05
const OPEN_TIME := 0.3
const POWER_LEFT_AT := 0.35
const POWER_RIGHT_AT := 0.48
const POWER_TIME := 0.5
const FIRST_LINE_AT := 1.0
## A new caller on the left card: the burst of static (the card flips edge-on and the picture
## changes at its height).
const STATIC_TIME := 0.42
const STATIC_SWAP := 0.12
## Closing: both faces switch off, then the cards whip away to their sides.
const CLOSE_TIME := 0.5
## The listener's face this bright (the speaker's 1).
const DIMMED := 0.35
## How dark the scene goes behind it (it's still there: the camera swaying, CROSS in his loop).
const SHADE := 0.62
## Layout (px). A card: its picture's box (the slanted sides cut into it), how far its top sits right
## of its bottom (the house lean), its tilt (radians), the gap between a card and the speech.
const CARD := Vector2(112, 132)
const CARD_SLANT := 14.0
const TILT := {"left": -0.05, "right": -0.05}
const CARD_GAP := 10.0
## The card's frame round the picture (an accent ring in an ink rim), and its heavy outer edge.
const RIM := 4.0
const EDGE := 4.0
## The listener's card: this much smaller, pushed this far back toward its corner.
const BACK_SCALE := 0.9
const BACK_PUSH := Vector2(7, 5)
## A card coming forward overshoots by this much (a punch).
const PUNCH := 0.06
## The speech: its band between the cards; each row on a strip this tall, each strip this far right
## of the one under it (the block leans like the rest), its ends this slanted, this much room each side
## of the letters; the bar on the speaker's side (pointing at their card), and the gap to the rows.
const TEXT_H := 70.0
const STRIP_H := 11.0
## A strip's fill: a dark teal block, clear of the darkened scene behind it.
const STRIP_FILL := Color(0.075, 0.17, 0.175, 0.95)
const STEP := 2.0
const STRIP_SLANT := 3.0
const STRIP_PAD := 6.0
## A strip's heavy edge on the speaker's side (px, plus its slant).
const STRIP_EDGE := 2.0
const RAIL_H := 3.0
const RAIL_GAP := 3.0
## A strip slides in this fast (s) from this far (px) on the speaker's side; the bar from further.
const SLIDE_TIME := 0.14
const SLIDE_FROM := 40.0
const RAIL_TIME := 0.18
## A name plate: height, slant, room each side of the name, how far it overlaps its card, and how far
## from the card's top (the left card) or bottom (the right).
const PLATE_H := 20.0
const PLATE_SLANT := 5.0
const PLATE_PAD := 7.0
const PLATE_OVER := 12.0
const PLATE_IN := 16.0
const SKIP_SIZE := Vector2(64, 30)
## The speech waveforms (user: "the speech waveform should sit under each speaker's name plate and
## only be the length of that name plate, the exception is Cross where the waveform would be over his
## name plate"): the voice as it comes through while its owner speaks, a flat hiss while they listen.
## A bar every WAVE_STEP px, a sample every 1/WAVE_RATE s, newest at the card's side; WAVE_H px tall,
## WAVE_GAP off its plate, leaning with the plates (WAVE_LEAN of its height).
const WAVE_STEP := 3.0
const WAVE_RATE := 30.0
const WAVE_H := 12.0
const WAVE_GAP := 3.0
const WAVE_LEAN := 0.25
## The most samples a waveform holds (a plate for the longest name).
const WAVE_MOST := 64
## The slash behind the speech: its tilt, and how far past the speech's band it reaches up and down.
const SLASH_TILT := -0.16
const SLASH_OVER := 16.0
## Typed text that a word processor puts in, made plain for the pixel font.
const PLAIN := {"’": "'", "‘": "'", "“": "\"", "”": "\"", "—": "-", "–": "-", "…": "...", "\n": " ", "\t": " "}

## The script (load_file()); set before it's added.
var data: Dictionary = {}
var skip_button: Button

var _lines: Array = []  # [{who, text: "[NAME] ..."}]
var _phase := Phase.OPENING
var _t := 0.0
var _line := -1
var _n := 0
var _wait := 0.0
var _done_at := -1.0  # when the line got all there (-1: still typing)
var _done_by_tap := false
var _rows: Array = []  # [start, length] of each row of the line
var _row_at: Array = []  # when each row's strip came in (-1: not yet)
var _name_len := 0
var _left := ""
var _speaker := ""
var _rail_side := ""
var _rail_at := 0.0
var _lit := {"left": DIMMED, "right": DIMMED}
var _rising := {"left": false, "right": false}
var _level := 0.0
## Each side's waveform (its newest sample last), when the next sample's due, and the waveforms' own
## dice (so they never touch the game's: the run after the briefing plays out the same).
var _wave := {"left": PackedFloat32Array(), "right": PackedFloat32Array()}
var _wave_acc := 0.0
var _wave_rng := RandomNumberGenerator.new()
var _static_t := -1.0
var _static_to := ""
var _close_t := 0.0
var _power_from := {}
var _tap_frame := -1
var _open_cued := false
var _pics := {}
var _rect := {}
var _front: Layer


## The script from a JSON file ({} if it's missing or broken).
static func load_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Briefing: no script at %s (check the export's include filter has *.json)" % path)
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}


## A line's text made plain: curly quotes, dashes and "..." from a word processor become ones the
## pixel font has, line breaks become spaces, runs of spaces one.
static func plain(text: String) -> String:
	for k: String in PLAIN:
		text = text.replace(k, PLAIN[k])
	return " ".join(text.split(" ", false)).strip_edges()


## A line of the script as shown: "[NAME] text", the {names} filled in.
static func line_text(d: Dictionary, entry: Dictionary) -> String:
	var cast: Dictionary = d.get("cast", {})
	var text := plain(String(entry.get("text", "")))
	for id: String in cast:
		text = text.replace("{%s}" % id, String(cast[id].get("name", id)))
	var who: Dictionary = cast.get(String(entry.get("who", "")), {})
	return "[%s] %s" % [String(who.get("name", "?")), text]


## The rows a text wraps to, `cols` letters at most, broken at spaces (a word too long for a row is
## split): [start, length] of each, in the text.
static func wrap_rows(text: String, cols: int) -> Array:
	var rows := []
	var i := 0
	var n := text.length()
	while i < n:
		while i < n and text[i] == " ":
			i += 1
		if i >= n:
			break
		var end := mini(i + cols, n)
		if end < n and text[end] != " ":
			var sp := text.rfind(" ", end)
			if sp > i:
				end = sp
		rows.append([i, end - i])
		i = end
	return rows


## What's wrong with a script (empty: nothing): the cast (CROSS in it; each a name short enough for
## its plate and a picture), and every line (a known speaker, some words, only letters the font has,
## every {name} known, and short enough for the strips).
static func problems(d: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var cast = d.get("cast")
	if not cast is Dictionary or not (cast as Dictionary).has(PLAYER):
		out.append("the cast must have \"%s\" in it" % PLAYER)
		return out
	for id: String in cast:
		var c = cast[id]
		if not c is Dictionary or String(c.get("name", "")) == "":
			out.append("cast %s: no name" % id)
			continue
		for ch in String(c["name"]):
			if not _has_glyph(ch):
				out.append("cast %s: the font has no '%s'" % [id, ch])
		if String(c["name"]).length() > NAME_MOST:
			out.append("cast %s: '%s' is longer than %d letters (its name plate)" % [id, c["name"], NAME_MOST])
		if not ResourceLoader.exists(String(c.get("portrait", ""))):
			out.append("cast %s: no picture at '%s'" % [id, c.get("portrait", "")])
	var lines = d.get("lines")
	if not lines is Array or (lines as Array).is_empty():
		out.append("no lines")
		return out
	for i in (lines as Array).size():
		var l = lines[i]
		if not l is Dictionary or not cast.has(String(l.get("who", ""))):
			out.append("line %d: who's speaking? ('%s')" % [i + 1, l.get("who", "") if l is Dictionary else l])
			continue
		if plain(String(l.get("text", ""))) == "":
			out.append("line %d: no words" % (i + 1))
			continue
		var text := line_text(d, l)
		var brace := text.find("{")
		if brace >= 0:
			out.append("line %d: no one called %s in the cast" % [i + 1, text.substr(brace, text.find("}", brace) - brace + 1)])
			continue
		for ch in text:
			if not _has_glyph(ch):
				out.append("line %d: the font has no '%s'" % [i + 1, ch])
				break
		var rows := wrap_rows(text, COLS).size()
		if rows > ROWS:
			out.append("line %d: %d rows, the speech holds %d (%d letters)" % [i + 1, rows, ROWS, text.length()])
	return out


## The lines it can play: those with a known speaker and some words.
static func lines_of(d: Dictionary) -> Array:
	var out := []
	var cast = d.get("cast")
	var lines = d.get("lines")
	if not cast is Dictionary or not lines is Array:
		return out
	for l in lines:
		if l is Dictionary and (cast as Dictionary).has(String(l.get("who", ""))) and plain(String(l.get("text", ""))) != "":
			out.append({"who": String(l["who"]), "text": line_text(d, l)})
	return out


## Where everything goes on a screen this size (it's 270 wide; 480 to 585 tall), the block centred
## up and down between the cinema bars: the left card up at the left, the speech's band under it, the
## right card (CROSS) under that at the right; SKIP in the top bar. The cards' rects are their
## pictures' boxes, before the slant and tilt (card_outline()).
static func layout(view: Vector2) -> Dictionary:
	var top := roundf((view.y - (CARD.y * 2.0 + CARD_GAP * 2.0 + TEXT_H)) / 2.0)
	var text_y := top + CARD.y + CARD_GAP
	return {
		"left": Rect2(14, top, CARD.x, CARD.y),
		"right": Rect2(view.x - 14 - CARD.x, text_y + TEXT_H + CARD_GAP, CARD.x, CARD.y),
		"text": Rect2(6, text_y, view.x - 12, TEXT_H),
		"skip": Rect2(view.x - 8 - SKIP_SIZE.x, roundf((44.0 - SKIP_SIZE.y) / 2.0), SKIP_SIZE.x, SKIP_SIZE.y),
	}


## A card's outline on the screen when it's in place and forward (its owner speaking): the picture's
## box `r` with its slanted sides, grown by `grow` (RIM + EDGE: the whole frame), tilted.
static func card_outline(r: Rect2, side: String, grow: float = 0.0) -> PackedVector2Array:
	var xf := Transform2D(TILT[side], r.get_center())
	return xf * _card_poly(-grow, grow, grow)


## A name plate's box (before its slant) for a name `letters` long, by the card in `r`, on a screen
## `width` wide: the left card's at its top right, the right card's at its bottom left, each
## overlapping its card a little, and kept on the screen.
static func plate_rect(r: Rect2, side: String, letters: int, width: float) -> Rect2:
	var w := letters * 12.0 + PLATE_PAD * 2.0 + PLATE_SLANT
	if side == "left":
		return Rect2(minf(r.end.x - PLATE_OVER, width - 8.0 - w), r.position.y + PLATE_IN, w, PLATE_H)
	return Rect2(maxf(8.0, r.position.x + PLATE_OVER - w), r.end.y - PLATE_IN - PLATE_H, w, PLATE_H)


## Where TAP goes once a line of `rows` rows is all there: under the rows when the left card's
## speaker said it (`top`: the rows hug the top of the band), under the band at its left when CROSS
## did (his card's under the band at the right).
static func hint_rect(band: Rect2, rows: int, top: bool, hint: String) -> Rect2:
	var w := (hint.length() + 2) * 6.0 + 12.0
	if top:
		return Rect2(band.position.x, band.position.y + RAIL_H + RAIL_GAP + rows * ROW_H + 2.0, w, 13.0)
	return Rect2(band.position.x + 2.0, band.end.y + 4.0, w, 13.0)


## The widest a strip gets (a full row of COLS letters, at the far right of the block's lean).
static func strip_reach() -> float:
	return (ROWS - 1) * STEP + STRIP_PAD * 2.0 + COLS * 6.0 - 1.0 + STRIP_SLANT


## A card's shape about its centre: the box CARD with its sides leaning like the rest (its top
## CARD_SLANT right of its bottom), its left side moved `l` px across (- is out), its right side
## `r` px across (+ is out), its top and bottom `yo` px out.
static func _card_poly(l: float, r: float, yo: float) -> PackedVector2Array:
	var h := CARD / 2.0
	return _lean(-h.x + l, h.x - CARD_SLANT + r, -h.y - yo, h.y + yo)


## A quad between two leaning lines (a card's sides: CARD_SLANT across over CARD's height), which
## cross the card's bottom at `xl` and `xr`, from `y0` down to `y1` (all about the card's centre).
static func _lean(xl: float, xr: float, y0: float, y1: float) -> PackedVector2Array:
	var m := CARD_SLANT / CARD.y  # (px across for each px up)
	var hy := CARD.y / 2.0
	return PackedVector2Array([Vector2(xl + (hy - y0) * m, y0), Vector2(xr + (hy - y0) * m, y0),
			Vector2(xr + (hy - y1) * m, y1), Vector2(xl + (hy - y1) * m, y1)])


static func _has_glyph(ch: String) -> bool:
	return ch == " " or UiKit.GLYPHS.has(ch.to_upper())


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP  # a tap anywhere (but SKIP) is "next"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)  # added already: size it now
	_lines = lines_of(data)
	# Who's on the left card first: the first in the script who isn't CROSS.
	for l in _lines:
		if l["who"] != PLAYER:
			_left = l["who"]
			break
	if _left == "":
		for id: String in data.get("cast", {}):
			if id != PLAYER:
				_left = id
				break
	for side in ["left", "right"]:
		var p := Portrait.new()
		_pics[side] = p
		add_child(p)
		_wave[side].resize(WAVE_MOST)
		_wave[side].fill(0.0)
	_wave_rng.seed = 7
	_pics["left"].texture = _picture(_left)
	_pics["right"].texture = _picture(PLAYER)
	# The plates and the speech, over the faces.
	_front = Layer.new(_draw_front)
	add_child(_front)
	skip_button = Button.new()
	skip_button.text = "SKIP ▶▶"
	skip_button.theme_type_variation = "CompactButton"
	skip_button.focus_mode = Control.FOCUS_NONE  # (Space / Enter are "next", not SKIP)
	add_child(skip_button)
	skip_button.pressed.connect(skip)
	_layout()
	cue.emit("codec", -4.0)  # the call
	if _lines.is_empty():
		_close()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and skip_button != null:
		_layout()


func _layout() -> void:
	_rect = layout(get_viewport_rect().size)
	for side in ["left", "right"]:
		var p: Portrait = _pics[side]
		p.size = _rect[side].size
		p.pivot_offset = _rect[side].size / 2.0
	_pose_cards()
	skip_button.position = _rect["skip"].position
	skip_button.size = _rect["skip"].size


# --- What the level, the tests and the bots use ----------------------------------------------

## A tap: finish the line being typed, or show the next, or (after the last) close.
func tap() -> void:
	if _phase != Phase.TALKING:
		return  # (opening: the first line's on its way; closing: going)
	if _n < _length():
		_n = _length()  # the whole line at once
		_done_at = _t
		_done_by_tap = true
		_level = maxf(_level, 0.7)
	elif not _done_by_tap and _t - _done_at < GRACE:
		return  # (it finished just as you tapped to finish it)
	elif _line + 1 < _lines.size():
		_start_line(_line + 1)
	else:
		_close()


## SKIP: close it now.
func skip() -> void:
	if _phase == Phase.OPENING or _phase == Phase.TALKING:
		_close()


func line_index() -> int:
	return _line


func line_count() -> int:
	return _lines.size()


## The line being shown, as typed in full ("[NAME] ...").
func line() -> String:
	return String(_lines[_line]["text"]) if _line >= 0 and _line < _lines.size() else ""


## Letters of the line shown so far.
func shown() -> int:
	return _n


func line_done() -> bool:
	return _line >= 0 and _n >= _length()


func is_talking() -> bool:
	return _phase == Phase.TALKING


func is_closing() -> bool:
	return _phase == Phase.CLOSING or _phase == Phase.DONE


## Who's on the left card, and who's speaking.
func left_who() -> String:
	return _left


func speaker() -> String:
	return _speaker


## A card's picture box (in the screen, before its slant and tilt), and how lit its face is (the
## speaker 1, the listener DIMMED), how much static is on it, how far switched on.
func frame_rect(side: String) -> Rect2:
	return _rect[side]


func lit(side: String) -> float:
	return _lit[side]


func static_on(side: String) -> float:
	return (_pics[side] as Portrait).static_amt


## The loudest of a side's last few waveform samples (0..1): up while its owner speaks.
func wave_peak(side: String, samples: int = 12) -> float:
	var w: PackedFloat32Array = _wave[side]
	var most := 0.0
	for i in range(maxi(0, w.size() - samples), w.size()):
		most = maxf(most, w[i])
	return most


## Where a side's waveform goes by its name plate (its box before the slant): exactly as long as the
## plate, under the caller's and over CROSS's (user).
static func wave_rect(plate: Rect2, side: String) -> Rect2:
	var y := plate.end.y + WAVE_GAP if side == "left" else plate.position.y - WAVE_GAP - WAVE_H
	return Rect2(plate.position.x, y, plate.size.x, WAVE_H)


func power(side: String) -> float:
	return (_pics[side] as Portrait).power


# --- Input ---------------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	var press: bool = (event is InputEventScreenTouch and event.pressed and event.index == 0) \
			or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	if not press:
		return
	accept_event()
	# One tap arrives as a touch and an emulated click (or the other way round), in the same frame.
	var f := Engine.get_process_frames()
	if f == _tap_frame:
		return
	_tap_frame = f
	tap()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		tap()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		skip()
		get_viewport().set_input_as_handled()


# --- Running ---------------------------------------------------------------------------------

func _process(delta: float) -> void:
	var dt := delta / maxf(Engine.time_scale, 0.01)  # real time
	_t += dt
	match _phase:
		Phase.OPENING:
			if _t >= OPEN_FROM + 0.2 and not _open_cued:
				_open_cued = true
				cue.emit("codec_open", -6.0)
			if _t >= FIRST_LINE_AT:
				_phase = Phase.TALKING
				_start_line(0)
		Phase.TALKING:
			_type(dt)
		Phase.CLOSING:
			_close_t += dt
			if _close_t >= CLOSE_TIME:
				_phase = Phase.DONE
				finished.emit()
	# The left card's static, and the new caller coming on at its height.
	if _static_t >= 0.0:
		var was := _static_t
		_static_t += dt
		if was < STATIC_SWAP and _static_t >= STATIC_SWAP:
			_left = _static_to
			_pics["left"].texture = _picture(_left)
		if _static_t >= STATIC_TIME:
			_static_t = -1.0
	var burst := 0.0 if _static_t < 0.0 else smoothstep(0.0, 0.05, _static_t) * (1.0 - smoothstep(0.22, STATIC_TIME, _static_t))
	# The speaker's face lit, the listener's dimmed (a quick fade; the card comes forward with it).
	for side in ["left", "right"]:
		var who := PLAYER if side == "right" else _left
		var want := 1.0 if who == _speaker and _phase == Phase.TALKING else DIMMED
		if _phase == Phase.OPENING:
			want = 1.0  # both on full as they warm up
		_rising[side] = want > _lit[side] or (_rising[side] and _lit[side] < 1.0 and want == 1.0)
		_lit[side] = move_toward(_lit[side], want, dt * 6.0)
	# The voice: up with each letter, falling back to a flicker (the face lifts a little with it).
	_level = move_toward(_level, 0.07, dt * 2.6)
	# The waveforms: the speaker's voice on theirs while the line comes through, a hiss on the other.
	_wave_acc += dt
	while _wave_acc >= 1.0 / WAVE_RATE:
		_wave_acc -= 1.0 / WAVE_RATE
		var talking := _phase == Phase.TALKING and not line_done()
		for side in ["left", "right"]:
			var on: bool = talking and _side(_speaker) == side
			var v := _level * _wave_rng.randf_range(0.35, 1.0) if on else _wave_rng.randf_range(0.02, 0.07)
			var w: PackedFloat32Array = _wave[side]
			w.remove_at(0)
			w.append(clampf(v, 0.0, 1.0))
			_wave[side] = w
	# Each row's strip comes in as its first letter types (all at once when a tap finishes the line).
	for i in mini(_rows.size(), _row_at.size()):
		if _row_at[i] < 0.0 and _n > int(_rows[i][0]):
			_row_at[i] = _t
	var pl: Portrait = _pics["left"]
	var pr: Portrait = _pics["right"]
	pl.power = _power_at(POWER_LEFT_AT)
	pr.power = _power_at(POWER_RIGHT_AT)
	pl.static_amt = burst
	pr.static_amt = 0.0
	pl.lit = _lit["left"]
	pr.lit = _lit["right"]
	pl.talk = _level if _speaker == _left else 0.0
	pr.talk = _level if _speaker == PLAYER else 0.0
	_pose_cards()
	skip_button.visible = _phase == Phase.OPENING or _phase == Phase.TALKING
	queue_redraw()
	_front.queue_redraw()


func _start_line(i: int) -> void:
	_line = i
	_n = 0
	_done_at = -1.0
	_done_by_tap = false
	var who: String = _lines[i]["who"]
	var text: String = _lines[i]["text"]
	_rows = wrap_rows(text, COLS)
	_row_at = []
	_row_at.resize(_rows.size())
	_row_at.fill(-1.0)
	_name_len = text.find("]") + 1
	_wait = 0.1
	if who != PLAYER:
		# A new caller (or a change of mind while the last one's still coming through): static on
		# the left card, the new face coming up through it.
		var coming := _static_to if _static_t >= 0.0 and _static_t < STATIC_SWAP else _left
		if who != coming:
			_static_t = 0.0
			_static_to = who
			_wait = STATIC_TIME * 0.7
			cue.emit("codec_static", -8.0)
	_speaker = who
	# The bar on the speaker's side comes in from their side when the other side was speaking.
	var side := _side(who)
	if side != _rail_side:
		_rail_side = side
		_rail_at = _t


func _type(dt: float) -> void:
	var text := line()
	var total := text.length()
	if _n >= total:
		return
	_wait -= dt
	while _wait <= 0.0 and _n < total:
		_n += 1
		var ch := text[_n - 1]
		_wait += PER_LETTER
		if ch == " ":
			continue
		typed.emit()
		_level = maxf(_level, randf_range(0.5, 1.0))
		if _n < total and _n > _name_len:
			if ch in ".!?":
				_wait += PAUSE_STOP
			elif ch in ",;:":
				_wait += PAUSE_COMMA
	if _n >= total:
		_done_at = _t


func _length() -> int:
	return line().length()


func _close() -> void:
	_power_from = {"left": _power_at(POWER_LEFT_AT), "right": _power_at(POWER_RIGHT_AT)}
	_phase = Phase.CLOSING
	_close_t = 0.0
	cue.emit("codec_close", -6.0)


## How far a face has switched on (0..1): on as it opens; off (from wherever it was) as it closes.
func _power_at(at: float) -> float:
	if _phase == Phase.CLOSING or _phase == Phase.DONE:
		var side := "left" if at == POWER_LEFT_AT else "right"
		return float(_power_from.get(side, 0.0)) * (1.0 - clampf(_close_t / 0.3, 0.0, 1.0))
	return clampf((_t - at) / POWER_TIME, 0.0, 1.0)


## How far the cards are in (0: off their sides; 1: in place, with a little overshoot on the way in;
## closing, they whip away once the faces are off).
func _cards_in() -> float:
	if _phase == Phase.CLOSING or _phase == Phase.DONE:
		var q := clampf((_close_t - 0.25) / 0.2, 0.0, 1.0)
		return 1.0 - q * q
	var p := clampf((_t - OPEN_FROM) / OPEN_TIME, 0.0, 1.0)
	var c1 := 1.4
	return 1.0 + (c1 + 1.0) * pow(p - 1.0, 3.0) + c1 * pow(p - 1.0, 2.0)  # (back-out)


## How far the speech is shown (it goes first as it closes).
func _speech_in() -> float:
	if _phase == Phase.CLOSING or _phase == Phase.DONE:
		return 1.0 - clampf(_close_t / 0.15, 0.0, 1.0)
	return 1.0


func _shade() -> float:
	var k := smoothstep(0.0, 0.25, _t)
	if _phase == Phase.CLOSING or _phase == Phase.DONE:
		k = minf(k, 1.0 - smoothstep(0.25, CLOSE_TIME, _close_t))
	return k


## 0 (listening) .. 1 (speaking): how far forward a card is.
func _pop(side: String) -> float:
	return clampf((_lit[side] - DIMMED) / (1.0 - DIMMED), 0.0, 1.0)


## The left card's width while a new caller comes on: it flips edge-on as the static peaks and back
## round with the new face.
func _flip() -> float:
	if _static_t < 0.0:
		return 1.0
	return maxf(absf(cos(clampf(_static_t / (STATIC_SWAP * 2.0), 0.0, 1.0) * PI)), 0.04)


## Where a card is now: its centre, tilt and scale (sliding in or out, forward while its owner
## speaks and back while they listen, flipping for a new caller).
func _card_pose(side: String) -> Dictionary:
	var r: Rect2 = _rect[side]
	var dir := -1.0 if side == "left" else 1.0
	var k := _pop(side)
	var s := lerpf(BACK_SCALE, 1.0, k) + (PUNCH * sin(k * PI) if _rising[side] and _phase == Phase.TALKING else 0.0)
	var away := (1.0 - _cards_in()) * (r.size.x + 70.0)
	var at := r.get_center() + BACK_PUSH * dir * (1.0 - k) + Vector2(dir * away, 0.0)
	var fx := _flip() if side == "left" else 1.0
	return {"at": at, "tilt": TILT[side], "scale": Vector2(s * fx, s), "away": dir * away}


func _pose_cards() -> void:
	for side in ["left", "right"]:
		var p: Portrait = _pics[side]
		var pose := _card_pose(side)
		p.position = pose["at"] - p.pivot_offset
		p.rotation = pose["tilt"]
		p.scale = pose["scale"]
		p.visible = _cards_in() > 0.0


func _side(who: String) -> String:
	return "right" if who == PLAYER else "left"


## The speaker's colour: CROSS in paper, the others in the HUD's teal.
func _accent(who: String) -> Color:
	return UiKit.PAPER if who == PLAYER else UiKit.TEAL


func _picture(id: String) -> Texture2D:
	var c: Dictionary = data.get("cast", {}).get(id, {})
	var path := String(c.get("portrait", ""))
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


func _name(id: String) -> String:
	return String(data.get("cast", {}).get(id, {}).get("name", id.to_upper()))


# --- Drawing ---------------------------------------------------------------------------------

## Behind everything: the scene darkened, the red MISSION BRIEFING tag in the top bar, and the two
## cards' frames (the faces go over them, then the plates and the speech: _draw_front).
func _draw() -> void:
	var s := get_viewport_rect().size
	var shade := _shade()
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.0, 0.012, 0.018, SHADE * shade))
	var f := UiKit.font()
	var tag := Rect2(8, 15, 16 * 6 + 14, 14)
	_slab(self, Rect2(tag.position + Vector2(2, 2), tag.size), 3.0, Color(UiKit.INK, 0.8 * shade))
	_slab(self, tag, 3.0, Color(UiKit.RED, shade))
	draw_string(f, Vector2(tag.position.x + 8, tag.position.y + 11), "MISSION BRIEFING", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(UiKit.INK, shade))
	# Where we are (3/9), next to it.
	if _line >= 0:
		var count_s := "%d/%d" % [_line + 1, _lines.size()]
		var cr := Rect2(tag.end.x + 4.0, tag.position.y, count_s.length() * 6.0 + 14.0, tag.size.y)
		_slab(self, cr, 3.0, Color(UiKit.PANEL_SOLID, shade))
		draw_string(f, Vector2(cr.position.x + 8, cr.position.y + 11), count_s, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(UiKit.DIM, shade))
	var cards := _cards_in()
	if cards <= 0.0:
		return
	# A broad slash across the screen behind the speech, from the left card down to CROSS's.
	var band: Rect2 = _rect["text"]
	var half := Vector2(s.x * 0.85 * clampf(cards, 0.0, 1.0), TEXT_H / 2.0 + SLASH_OVER)
	draw_set_transform(band.get_center(), SLASH_TILT, Vector2.ONE)
	draw_rect(Rect2(-half, half * 2.0), Color(UiKit.TEAL_DIM, 0.2 * shade))
	draw_rect(Rect2(-half.x, -half.y, half.x * 2.0, 2.0), Color(UiKit.TEAL, 0.45 * shade))
	draw_rect(Rect2(-half.x, half.y - 2.0, half.x * 2.0, 2.0), Color(UiKit.RED, 0.6 * shade))
	draw_set_transform_matrix(Transform2D.IDENTITY)
	for side in ["left", "right"]:
		_draw_card_frame(side)


## A card's frame: a hard ink shadow (further off while it's forward), an ink rim, a ring in its
## owner's colour (dim while they listen), and a heavy edge on its outer side.
func _draw_card_frame(side: String) -> void:
	var pose := _card_pose(side)
	var k := _pop(side)
	var who := PLAYER if side == "right" else _left
	var acc := UiKit.TEAL_DIM.lerp(_accent(who), k) if who != PLAYER else UiKit.DIM.lerp(UiKit.PAPER, k)
	var h := CARD / 2.0
	var shadow := Vector2(4, 5) + Vector2(3, 3) * k
	var out_l := RIM + (EDGE if side == "left" else 0.0)
	var out_r := RIM + (EDGE if side == "right" else 0.0)
	draw_set_transform(pose["at"] + shadow, pose["tilt"], pose["scale"])
	draw_colored_polygon(_card_poly(-out_l, out_r, RIM), Color(UiKit.INK, 0.85))
	draw_set_transform(pose["at"], pose["tilt"], pose["scale"])
	draw_colored_polygon(_card_poly(-RIM, RIM, RIM), UiKit.INK)
	draw_colored_polygon(_card_poly(-2.0, 2.0, 2.0), acc)
	# The heavy edge (like a menu button's leading edge), outside the rim on the outer side.
	if side == "left":
		draw_colored_polygon(_lean(-h.x - RIM - EDGE, -h.x - RIM, -h.y - RIM, h.y + RIM), acc)
	else:
		draw_colored_polygon(_lean(h.x - CARD_SLANT + RIM, h.x - CARD_SLANT + RIM + EDGE, -h.y - RIM, h.y + RIM), acc)
	draw_set_transform_matrix(Transform2D.IDENTITY)


## Over the faces: the two name plates, the line on its strips, and where we are / TAP.
func _draw_front(ci: CanvasItem) -> void:
	if _cards_in() <= 0.0:
		return
	_draw_plate(ci, "left")
	_draw_plate(ci, "right")
	if _line >= 0:
		_draw_speech(ci)


## A name plate: a chunky slanted block with the name big, solid in its owner's colour while they
## speak, dark while they listen; it rides with its card (and flips with it for a new caller).
func _draw_plate(ci: CanvasItem, side: String) -> void:
	var who := PLAYER if side == "right" else _left
	var name := _name(who)
	var r := plate_rect(_rect[side], side, name.length(), get_viewport_rect().size.x)
	var pose := _card_pose(side)
	var k := _pop(side)
	var dir := -1.0 if side == "left" else 1.0
	r.position += Vector2(pose["away"], 0.0) + BACK_PUSH * dir * (1.0 - k)
	if side == "left":
		var fx := _flip()
		var c := r.get_center().x
		r.size.x *= fx
		r.position.x = c - r.size.x / 2.0
		if fx < 0.5:
			name = ""
	var acc := _accent(who)
	var f := UiKit.font()
	_slab(ci, Rect2(r.position + Vector2(3, 3) * (0.5 + k), r.size), PLATE_SLANT, Color(UiKit.INK, 0.9))
	_slab(ci, r, PLATE_SLANT, UiKit.PANEL_SOLID.lerp(acc, k))
	if k < 0.5:
		_slab_outline(ci, r, PLATE_SLANT, Color(acc, 0.55))
	# A red tab at the plate's far end while its owner speaks.
	if k > 0.05:
		var tab := Rect2(r.end.x - 6.0, r.position.y, 6.0, r.size.y) if side == "left" else Rect2(r.position.x, r.position.y, 6.0, r.size.y)
		_slab(ci, tab, PLATE_SLANT, Color(UiKit.RED, k))
	if name != "":
		var tx := r.position.x + PLATE_PAD + PLATE_SLANT * 0.5 + (0.0 if side == "left" else 2.0)
		ci.draw_string(f, Vector2(tx, r.position.y + 17), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(acc, 0.7).lerp(UiKit.INK, k))
		_draw_wave(ci, side, r, k, acc)


## A waveform along its plate (see wave_rect): a dotted line through its middle, then a bar a
## sample, newest by the card (the plate's far end from it oldest), leaning like the plate; bright
## while its owner speaks (k: how far forward their card is), faint while they listen.
func _draw_wave(ci: CanvasItem, side: String, plate: Rect2, k: float, acc: Color) -> void:
	var r := wave_rect(plate, side)
	var mid := roundf(r.get_center().y)
	var lean := WAVE_LEAN
	# (the plate leans PLATE_SLANT over its height: the wave's ends follow its slant)
	var x0 := r.position.x + PLATE_SLANT * (0.0 if side == "left" else 1.0)
	var x1 := r.end.x - PLATE_SLANT * (1.0 if side == "left" else 0.0)
	for x in range(int(x0), int(x1), 4):
		ci.draw_rect(Rect2(x, mid, 2, 1), Color(acc, 0.25 + 0.2 * k))
	var w: PackedFloat32Array = _wave[side]
	var n := mini(w.size(), floori((x1 - x0 - 1.0) / WAVE_STEP))
	for i in n:
		var v: float = w[w.size() - 1 - i]  # (newest first: by the card)
		var x := x0 + i * WAVE_STEP if side == "left" else x1 - 2.0 - i * WAVE_STEP
		var h := maxf(1.0, roundf(v * (r.size.y / 2.0 - 1.0)))
		var a := (0.3 + 0.7 * minf(1.0, v * 1.6)) * (0.45 + 0.55 * k)
		ci.draw_colored_polygon(PackedVector2Array([
				Vector2(x - lean * h, mid + h + 1.0), Vector2(x + 2.0 - lean * h, mid + h + 1.0),
				Vector2(x + 2.0 + lean * h, mid - h), Vector2(x + lean * h, mid - h)]), Color(acc, a))


## The line on its strips: a bar on the speaker's side (from their side, with a notch pointing at
## their card), then a strip a row, each sliding in from the speaker's side as its first letter
## types: "[NAME]" solid in the speaker's colour at its start, the words in paper. The rows hug the
## speaker's card (the top of the band for the left card, the bottom for CROSS). Under them, once the
## line's all there, TAP and a blinking arrow (TAP TO CONTINUE the first time, TAP TO END on the last
## line).
func _draw_speech(ci: CanvasItem) -> void:
	var band: Rect2 = _rect["text"]
	var f := UiKit.font()
	var text := line()
	var side := _side(_speaker)
	var top := side == "left"
	var dir := -1.0 if top else 1.0
	var acc := _accent(_speaker)
	var fade := _speech_in()
	var n := mini(_rows.size(), ROWS)
	var rows_h := (n - 1) * ROW_H + STRIP_H
	var y0 := band.position.y + RAIL_H + RAIL_GAP if top else band.end.y - RAIL_H - RAIL_GAP - rows_h
	# How wide the block is (its widest strip), for the bar.
	var reach := 0.0
	for i in n:
		reach = maxf(reach, (n - 1 - i) * STEP + STRIP_PAD * 2.0 + int(_rows[i][1]) * 6.0 - 1.0 + STRIP_SLANT)
	# The bar, and its notch pointing at the speaker's card.
	var rk := clampf((_t - _rail_at) / RAIL_TIME, 0.0, 1.0)
	rk = 1.0 - pow(1.0 - rk, 3.0)
	var slide := dir * (1.0 - rk) * 200.0
	var bar_y := band.position.y if top else band.end.y - RAIL_H
	_slab(ci, Rect2(band.position.x + slide, bar_y, reach, RAIL_H), 1.0, Color(acc, fade))
	var nx: float = (_rect["left"].position.x + 30.0 if top else _rect["right"].end.x - 46.0) + slide
	var ny := bar_y + 1.0 if top else bar_y + RAIL_H - 1.0
	var tip := -8.0 if top else 8.0
	ci.draw_colored_polygon(PackedVector2Array([Vector2(nx, ny), Vector2(nx + 7.0, ny + tip), Vector2(nx + 14.0, ny)]), Color(acc, fade))
	# The strips.
	var foot := Vector2(band.position.x, y0)
	for i in n:
		var at: float = _row_at[i] if i < _row_at.size() else -1.0
		if at < 0.0:
			break
		var start: int = _rows[i][0]
		var count: int = _rows[i][1]
		var vis := clampi(_n - start, 0, count)
		var k := clampf((_t - at) / SLIDE_TIME, 0.0, 1.0)
		k = 1.0 - pow(1.0 - k, 3.0)
		var a := k * fade
		var x := band.position.x + (n - 1 - i) * STEP + dir * (1.0 - k) * SLIDE_FROM
		var y := y0 + i * ROW_H
		var strip := Rect2(x, y, STRIP_PAD * 2.0 + count * 6.0 - 1.0 + STRIP_SLANT, STRIP_H)
		_slab(ci, Rect2(strip.position + Vector2(2, 2), strip.size), STRIP_SLANT, Color(UiKit.INK, 0.9 * a))
		_slab(ci, strip, STRIP_SLANT, Color(STRIP_FILL, STRIP_FILL.a * a))
		# The speaker's end of the strip: a heavy edge in their colour.
		var ew := STRIP_EDGE + STRIP_SLANT
		var edge := Rect2(strip.position.x, y, ew, STRIP_H) if top else Rect2(strip.end.x - ew, y, ew, STRIP_H)
		_slab(ci, edge, STRIP_SLANT, Color(acc, a))
		var tx := strip.position.x + STRIP_PAD + 1.0
		var name_part := clampi(_name_len - start, 0, vis)
		if name_part > 0:
			# "[NAME]" solid in the speaker's colour, from the strip's start.
			_slab(ci, Rect2(strip.position.x, y, tx - strip.position.x + name_part * 6.0 + 2.0, STRIP_H), STRIP_SLANT, Color(acc, a))
			ci.draw_string(f, Vector2(tx, y + 9.0), text.substr(start, name_part), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(UiKit.INK, a))
		if vis > name_part:
			ci.draw_string(f, Vector2(tx + name_part * 6.0, y + 9.0), text.substr(start + name_part, vis - name_part), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(UiKit.PAPER, a))
		foot = Vector2(strip.position.x, 0.0)
	if _phase == Phase.TALKING and line_done():
		# TAP under the rows (the left card's speaker), or under the bar at the left (CROSS's: his
		# card's at the right).
		var hint := "TAP TO END" if _line + 1 >= _lines.size() else ("TAP TO CONTINUE" if _line == 0 else "TAP")
		var hr := hint_rect(band, n, top, hint)
		hr.position.x = foot.x if top else hr.position.x
		_slab(ci, Rect2(hr.position + Vector2(2, 2), hr.size), 3.0, Color(UiKit.INK, 0.9))
		_slab(ci, hr, 3.0, UiKit.PANEL_SOLID)
		_slab(ci, Rect2(hr.position, Vector2(6.0, hr.size.y)), 3.0, acc)
		ci.draw_string(f, Vector2(hr.position.x + 10, hr.position.y + 10), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, acc)
		if fmod(_t - _done_at, 0.8) < 0.5:
			ci.draw_string(f, Vector2(hr.position.x + 10 + (hint.length() + 1) * 6.0, hr.position.y + 10), "▶", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, acc)


## A slanted block: `r` with its top `slant` px right of its bottom (inside r).
static func _slab(ci: CanvasItem, r: Rect2, slant: float, col: Color) -> void:
	if col.a <= 0.0 or r.size.x <= 0.0:
		return
	ci.draw_colored_polygon(PackedVector2Array([Vector2(r.position.x + slant, r.position.y), Vector2(r.end.x, r.position.y),
			Vector2(r.end.x - slant, r.end.y), Vector2(r.position.x, r.end.y)]), col)


static func _slab_outline(ci: CanvasItem, r: Rect2, slant: float, col: Color) -> void:
	ci.draw_polyline(PackedVector2Array([Vector2(r.position.x + slant, r.position.y), Vector2(r.end.x, r.position.y),
			Vector2(r.end.x - slant, r.end.y), Vector2(r.position.x, r.end.y), Vector2(r.position.x + slant, r.position.y)]), col, 1.0)


## A layer drawn by a Briefing method (the plates and the speech, over the faces).
class Layer extends Control:
	var paint: Callable

	func _init(c: Callable) -> void:
		paint = c
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		paint.call(self)


## A face on a card: the user's picture, cropped to the card, through the teal CRT shader
## (codec_portrait.gdshader), which also cuts the card's slanted sides.
class Portrait extends Control:
	var texture: Texture2D:
		set(t):
			texture = t
			_crop()
			queue_redraw()
	var lit := 1.0:
		set(v):
			lit = v
			_mat.set_shader_parameter("lit", v)
	var power := 0.0:
		set(v):
			power = v
			_mat.set_shader_parameter("power", v)
	var static_amt := 0.0:
		set(v):
			static_amt = v
			_mat.set_shader_parameter("static_amt", v)
	var talk := 0.0:
		set(v):
			talk = v
			_mat.set_shader_parameter("talk", v)
	var _mat := ShaderMaterial.new()
	var _src := Rect2()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR  # (shrunk about 2x)
		_mat.shader = preload("res://assets/shaders/psx/codec_portrait.gdshader")
		_mat.set_shader_parameter("power", 0.0)
		_mat.set_shader_parameter("slant", CARD_SLANT / CARD.x)
		material = _mat

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			_crop()

	## The middle of the picture at the card's shape (a little nearer the top: the face).
	func _crop() -> void:
		if texture == null or size.x <= 0.0 or size.y <= 0.0:
			return
		var ts := texture.get_size()
		var want := size.x / size.y
		if ts.x / ts.y > want:
			var w := ts.y * want
			_src = Rect2((ts.x - w) / 2.0, 0.0, w, ts.y)
		else:
			var h := ts.x / want
			_src = Rect2(0.0, (ts.y - h) * 0.3, ts.x, h)
		_mat.set_shader_parameter("region", Vector4(_src.position.x / ts.x, _src.position.y / ts.y, _src.size.x / ts.x, _src.size.y / ts.y))
		queue_redraw()

	func _draw() -> void:
		if texture == null:
			draw_rect(Rect2(Vector2.ZERO, size), UiKit.INK)
		else:
			draw_texture_rect_region(texture, Rect2(Vector2.ZERO, size), _src)
