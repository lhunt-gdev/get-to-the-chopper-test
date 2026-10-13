class_name FirstTips
extends RefCounted
## The first-time tips (the decision log's "The demo pass"): one-time prompts in mission 1's opening
## stretch (the LOBBY, the MAIN FLOOR and the SECURITY WING, up to its junction) teaching the controls
## and the rules: change lane, jump, slide, run into cover and swipe out of it, hold FIRE (and the
## TRIGGER side setting), tripwires and alarm boxes, and the junction's doors (the moves' worded for
## the on-screen move buttons with SETTINGS' MOVE on BUTTONS: BY_BUTTONS). Each shows once, ever,
## on this device (Progress remembers it; SETTINGS' TIPS turns them off, SHOW AGAIN brings them back),
## just before the thing it teaches and never mid-danger: only while no guard is aiming at him (FIRE's
## own excepted: a guard ahead is what it's about; it comes first behind cover, the calmest place to
## learn it), one at a time, with a breather between (none in cover: he's stopped there, and safe).
## The holds (JUMP, SLIDE, the tripwire's) and cover's are the ones that must come before the first
## barrier, pipe, wire or cover they're for (MOMENTS): they skip the breather, and cut a softer tip
## short if one's still up (one that would only just have come up waits for them instead); the holds
## show while a guard aims too (the hold slows him with the rest). Leaving cover's tip is never
## followed by cover's own (he knows it then).
##
## How the game slows for one (Controls v1 stays as LOCKED: nothing here pauses the game):
## - The swipes that must land at the right moment (JUMP, SLIDE, the tripwire's) use a slow-motion
##   hold: as the barrier, pipe or wire comes up, time eases down, to almost nothing (MIN_SCALE) by the
##   time it's HOLD_GAP m ahead, the right moment to swipe. The swipe (or a tap) lets it go, and time
##   eases back to normal. At MIN_SCALE the last few metres take seconds of real time: time to read it
##   and act on it.
## - The rest use a gentle slow-motion (SOFT_SCALE): there's room, so he keeps running while he reads.
##   The doors' tip slows only as gently again on top of the junction's own slowdown, which is LOCKED
##   as a slowdown, never a pause.
## Each goes as soon as he does what it says (by what he does, not by how: the bots' moves count),
## with a tap, or once the moment has passed. Looks and timing only: nothing of the run's results
## (the chopper's clock runs on the game's time, slowed with it).
##
## The level gathers what's going on each frame (its _tip_state(); pure functions here pick the tip, say
## when it's done and how slow the game goes: pick(), done(), scale_for()), and the HUD draws the card
## (Card). The bots play without them unless a scenario asks (the level's `tips`).

## The tips, in the order they're picked when two could show at once.
const ORDER := ["fire", "lane", "jump", "slide", "alert", "cover", "cover_out", "doors"]
## Each one's lines (the first is its headline) and its gesture icon.
const TIPS := {
	"lane": {"lines": ["SWIPE LEFT OR RIGHT", "TO CHANGE LANE"], "icon": "swipe_side"},
	"jump": {"lines": ["SWIPE UP TO JUMP"], "icon": "swipe_up"},
	"slide": {"lines": ["SWIPE DOWN TO SLIDE"], "icon": "swipe_down"},
	"cover": {"lines": ["RUN INTO COVER TO HIDE", "OR SWIPE EARLY TO RUN ON PAST"], "icon": "cover"},
	"cover_out": {"lines": ["SWIPE LEFT OR RIGHT", "TO LEAVE COVER"], "icon": "swipe_side"},
	"fire": {"lines": ["HOLD FIRE TO SHOOT", "IT AIMS FOR YOU", "SETTINGS: TRIGGER LEFT OR RIGHT"], "icon": "hold"},
	"alert": {"lines": ["TRIPWIRES RAISE THE ALERT", "JUMP THEM TO STAY QUIET", "SHOOT ALARM BOXES TO LOWER IT"], "icon": "wire"},
	"doors": {"lines": ["ARROWS: THE DOOR IS OPEN", "PADLOCK: IT'S LOCKED", "OUTER LANES TAKE THE SIDE DOORS"], "icon": "doors"},
}

## FIRE's lines by SETTINGS' AIM ("auto", "auto_tap", "tap"), as CONTROLS words it: TIPS' own are AUTO's.
const FIRE_BY_AIM := {
	"tap": ["TAP AN ENEMY TO TARGET IT", "HOLD FIRE TO SHOOT IT", "SETTINGS: TRIGGER LEFT OR RIGHT"],
	"auto_tap": ["HOLD FIRE TO SHOOT", "IT AIMS, OR TAP AN ENEMY", "SETTINGS: TRIGGER LEFT OR RIGHT"],
}

## The moves' lines and icons with SETTINGS' MOVE on BUTTONS (the on-screen move buttons), as CONTROLS
## words it: TIPS' own are SWIPE's. (Swipes still work: these teach the buttons.) Each one's card rings
## its buttons on the screen (BUTTONS_FOR).
const BY_BUTTONS := {
	"lane": {"lines": ["TAP ◀ OR ▶", "TO CHANGE LANE"], "icon": "tap_side"},
	"jump": {"lines": ["TAP ▲ TO JUMP"], "icon": "tap_up"},
	"slide": {"lines": ["TAP ▼ TO SLIDE"], "icon": "tap_down"},
	"cover": {"lines": ["RUN INTO COVER TO HIDE", "OR TAP ◀ ▶ EARLY TO RUN ON PAST"], "icon": "cover"},
	"cover_out": {"lines": ["TAP ◀ OR ▶", "TO LEAVE COVER"], "icon": "tap_side"},
}
const BUTTONS_FOR := {
	"lane": [Vector2i.LEFT, Vector2i.RIGHT], "jump": [Vector2i.UP], "slide": [Vector2i.DOWN], "cover_out": [Vector2i.LEFT, Vector2i.RIGHT],
}

## The breather after one goes before the next can show (game time, s).
const COOLDOWN := 1.2
## The slow-motion hold (JUMP, SLIDE, the tripwire): time eases down from HOLD_FROM_SCALE, HOLD_EASE
## m before the hold point, to MIN_SCALE at HOLD_GAP m short of the obstacle (where a swipe clears it).
const HOLD_GAP := 3.0
const HOLD_EASE := 6.0
const HOLD_FROM_SCALE := 0.4
const MIN_SCALE := 0.05
## The gentle slow-motion (the rest), and the doors' on top of the junction's own slowdown.
const SOFT_SCALE := 0.35
const DOORS_SCALE := 0.6
## How fast the game's speed moves toward what a tip wants (a whole step, 0 to 1, in 1 / this s of
## real time): in, and back out once it's gone.
const EASE_IN := 4.0
const EASE_OUT := 3.0
## Where each shows: a lane tip from just through the start door while there's room ahead in his
## lane; a jump, slide or wire tip once it's the next thing in his lane and within SHOW_AHEAD m;
## cover's within COVER_AHEAD m; FIRE's while a guard's his target and nothing's within CALM_AHEAD m
## in his lane, or he's behind cover (first, then: the calmest place to learn it); the doors' within DOORS_AHEAD m of the split with nothing left in his lane before it.
const LANE_FROM := 0.5
const LANE_ROOM := 10.0
const SHOW_AHEAD := 14.0
const COVER_AHEAD := 16.0
const CALM_AHEAD := 8.0
const DOORS_AHEAD := 28.0
## Which tips hold (the slow-motion hold); and the obstacle each looks for ("pass", as the level has
## it).
const HOLDS := ["jump", "slide", "alert"]
const PASS_FOR := {"jump": "jump", "slide": "slide", "alert": "jump_or_alert", "cover": "cover"}
## The tips with a moment of their own, the next thing in his lane (the holds, and cover's): each must
## show before the first one it's for, so it skips the breather and cuts a softer tip short. A softer
## tip doesn't start this many m short of one's moment (MOMENT_SOON): it would only be cut short.
const MOMENTS := ["jump", "slide", "alert", "cover"]
const MOMENT_SOON := 3.0


## The tip to show now, or "": `s` is the moment (the level's _tip_state()): "seen" (ids already shown),
## "d" (how far he's run), "in_cover", "airborne", "sliding", "aimed_at" (a guard is aiming at him),
## "next" and "gap" (the next thing in his lane: its "pass", and how far ahead, m; "" / INF for
## none), "target" (FIRE has a guard to shoot), "split" (how far to the junction's split, INF for
## none ahead) and "clear_to_split" (nothing left in his lane before it).
static func pick(s: Dictionary) -> String:
	var seen: Dictionary = s.get("seen", {})
	for id: String in ORDER:
		if seen.has(id) or not wants(id, s):
			continue
		return id
	return ""


## Tip `id`'s lines (the first its headline), with SETTINGS' AIM `aim` (FIRE's follows it) and MOVE
## on BUTTONS or not (`buttons`: the moves' follow it).
static func lines_of(id: String, aim: String = "auto", buttons: bool = false) -> Array:
	if id == "fire" and FIRE_BY_AIM.has(aim):
		return FIRE_BY_AIM[aim]
	if buttons and BY_BUTTONS.has(id):
		return BY_BUTTONS[id]["lines"]
	return TIPS.get(id, {}).get("lines", [])


## Tip `id`'s gesture icon (Card.draw_icon), with MOVE on BUTTONS or not.
static func icon_of(id: String, buttons: bool = false) -> String:
	if buttons and BY_BUTTONS.has(id):
		return String(BY_BUTTONS[id]["icon"])
	return String(TIPS.get(id, {}).get("icon", ""))


## The hold or cover's tip to show now (MOMENTS), or "": as pick(), but only those (they skip the
## breather after the last tip).
static func pick_moment(s: Dictionary) -> String:
	var seen: Dictionary = s.get("seen", {})
	for id: String in ORDER:
		if id in MOMENTS and not seen.has(id) and wants(id, s):
			return id
	return ""


## The hold or cover's tip that cuts tip `up` short at the moment `s`, or "": a softer tip still up
## as its moment comes (one of them is never cut short).
static func preempt(up: String, s: Dictionary) -> String:
	return "" if up in MOMENTS else pick_moment(s)


## Whether tip `id` would show at the moment `s` (see pick()).
static func wants(id: String, s: Dictionary) -> bool:
	var gap := float(s.get("gap", INF))
	var next := String(s.get("next", ""))
	var busy := bool(s.get("airborne", false)) or bool(s.get("sliding", false))
	var in_cover := bool(s.get("in_cover", false))
	if id == "cover_out":
		return in_cover
	if not in_cover and not id in MOMENTS and _moment_soon(s):
		return false  # (a hold's or cover's moment is just ahead: it would cut this one short)
	if id == "fire":
		# (behind cover is the calmest place to learn it: there it comes first)
		return bool(s.get("target", false)) and not busy and (in_cover or gap > CALM_AHEAD)
	if in_cover or (bool(s.get("aimed_at", false)) and not id in HOLDS):
		return false
	match id:
		"lane":
			return float(s.get("d", 0.0)) >= LANE_FROM and gap > LANE_ROOM and not busy
		"jump", "alert":
			# (mid-slide too: a swipe up jumps out of it, and a wire just past a pipe has no other moment)
			return next == PASS_FOR[id] and gap > HOLD_GAP + 0.5 and gap <= SHOW_AHEAD and not bool(s.get("airborne", false))
		"slide":
			return next == PASS_FOR[id] and gap > HOLD_GAP + 0.5 and gap <= SHOW_AHEAD and not busy
		"cover":
			# (never once leaving cover's has shown: he's been in cover by then)
			return next == "cover" and gap > 3.0 and gap <= COVER_AHEAD and not (s.get("seen", {}) as Dictionary).has("cover_out")
		"doors":
			return float(s.get("split", INF)) <= DOORS_AHEAD and bool(s.get("clear_to_split", false))
	return false


## Whether a hold or cover's tip not shown yet has its moment, for the next thing in his lane, within
## MOMENT_SOON m.
static func _moment_soon(s: Dictionary) -> bool:
	var seen: Dictionary = s.get("seen", {})
	var next := String(s.get("next", ""))
	for id: String in MOMENTS:
		if next == PASS_FOR[id] and not seen.has(id) and not (id == "cover" and seen.has("cover_out")):
			return float(s.get("gap", INF)) <= (COVER_AHEAD if id == "cover" else SHOW_AHEAD) + MOMENT_SOON
	return false


## Whether tip `id`, shown at the moment `from`, is done at the moment `now`: he's done what it says
## (by what he does: the bots' moves count), or the moment's passed. A tap closes any of them (the
## level's).
static func done(id: String, from: Dictionary, now: Dictionary) -> bool:
	match id:
		"lane":
			return int(now.get("lane", 0)) != int(from.get("lane", 0)) or float(now.get("gap", INF)) < LANE_ROOM * 0.6
		"jump", "alert":
			return bool(now.get("airborne", false)) or String(now.get("next", "")) != PASS_FOR[id]
		"slide":
			return bool(now.get("sliding", false)) or String(now.get("next", "")) != "slide"
		"cover":
			return bool(now.get("in_cover", false)) or String(now.get("next", "")) != "cover"
		"cover_out":
			return not bool(now.get("in_cover", false))
		"fire":
			return bool(now.get("firing", false)) or not bool(now.get("target", false))
		"doors":
			return float(now.get("split", INF)) == INF or int(now.get("lane", 0)) != int(from.get("lane", 0))
	return true


## How fast the game runs while tip `id` is up (1 normal), `gap` m short of the thing it teaches:
## the hold eases down to MIN_SCALE at HOLD_GAP; the rest a gentle slow-motion (on top of the
## junction's own for the doors).
static func scale_for(id: String, gap: float) -> float:
	if id in HOLDS:
		return lerpf(MIN_SCALE, HOLD_FROM_SCALE, clampf((gap - HOLD_GAP) / HOLD_EASE, 0.0, 1.0))
	if id == "doors":
		return DOORS_SCALE
	if id == "cover_out":
		return 1.0  # (in cover he's stopped, and safe)
	return SOFT_SCALE


## The game's speed a frame on: from `now` toward `want`, over `real_dt` s of real time.
static func ease_scale(now: float, want: float, real_dt: float) -> float:
	return move_toward(now, want, real_dt * (EASE_IN if want < now else EASE_OUT))


## The card a tip shows on (the HUD's): the game's codec look, a TIP tab, a small gesture icon
## (animated: a fingertip swiping, pressing, or the thing it's about), its lines in the pixel font
## (the first teal, the rest paper), and TAP TO CLOSE under them. It sits across the upper middle of
## the screen, clear of the clock, the alert box, the junction's prompt and the FIRE trigger.
class Card extends Control:
	const W := 238.0
	const ICON := 22.0
	const LINE := 11.0
	## Its top as a part of the screen's height.
	const TOP := 0.24
	var id := ""
	## Where the FIRE trigger is (x, y, radius: SwipeInput.fire_button), for FIRE's tip to ring it.
	var fire_at := Vector3.ZERO
	## SETTINGS' AIM (set by the HUD), for FIRE's wording (lines_of).
	var aim := "auto_tap"
	## SETTINGS' MOVE on BUTTONS (set by the HUD), for the moves' wording, and where the move buttons
	## are (SwipeInput.move_buttons), for their cards to ring them.
	var buttons := false
	var pad_at := {}
	var _t := 0.0
	var _in := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE  # (a tap goes on to the game, which closes it)
		set_anchors_preset(Control.PRESET_FULL_RECT)
		visible = false

	func show_tip(which: String) -> void:
		id = which
		_t = 0.0
		_in = 0.0
		visible = which != ""
		queue_redraw()

	func lines() -> Array:
		return FirstTips.lines_of(id, aim, buttons)

	## The card's box on a screen `size` big.
	func box(size: Vector2) -> Rect2:
		var h := 10.0 + ICON + 6.0 + lines().size() * LINE + 4.0 + LINE + 4.0
		return Rect2(roundf((size.x - W) / 2.0), roundf(size.y * TOP), W, h)

	func _process(delta: float) -> void:
		if not visible:
			return
		var real := delta / maxf(Engine.time_scale, 0.01)  # (the game may be slowed: the card isn't)
		_t += real
		_in = minf(1.0, _in + real * 10.0)
		queue_redraw()

	func _draw() -> void:
		if id == "":
			return
		var f := UiKit.font()
		var r := box(get_viewport_rect().size)
		r.position.y += roundf((1.0 - _in) * 8.0)
		var a := _in
		UiKit.panel(self, r, Color(UiKit.TEAL, a), Color(UiKit.PANEL, 0.92 * a), 6.0)
		# The TIP tab on its top edge, like a codec frequency plate.
		var tab := Rect2(r.position + Vector2(10, -6), Vector2(30, 11))
		draw_rect(tab, Color(UiKit.RED, a))
		draw_string(f, tab.position + Vector2(6, 9), "TIP", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(UiKit.INK, a))
		var icon := Rect2(r.position.x + (r.size.x - ICON * 2.0) / 2.0, r.position.y + 8.0, ICON * 2.0, ICON)
		draw_icon(self, FirstTips.icon_of(id, buttons), icon, _t, a)
		var y := icon.end.y + 6.0 + 8.0
		var ls := lines()
		for i in ls.size():
			var text := String(ls[i])
			var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
			draw_string(f, Vector2(roundf(r.position.x + (r.size.x - w) / 2.0), y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8,
					Color(UiKit.TEAL if i == 0 else UiKit.PAPER, a))
			y += LINE
		if id == "fire" and fire_at.z > 0.0:
			# FIRE's: rings going out round the trigger, wherever TRIGGER has put it.
			for k in 2:
				var p := fmod(_t * 1.2 + k * 0.5, 1.0)
				draw_arc(Vector2(fire_at.x, fire_at.y), fire_at.z * (1.0 + 0.5 * p), 0, TAU, 32, Color(UiKit.TEAL, a * (1.0 - p)), 2.0)
		if buttons and BUTTONS_FOR.has(id):
			# The moves' with MOVE on BUTTONS: the same rings round the buttons it means.
			for d: Vector2i in BUTTONS_FOR[id]:
				var b: Vector3 = pad_at.get(d, Vector3.ZERO)
				if b.z <= 0.0:
					continue
				for k in 2:
					var p := fmod(_t * 1.2 + k * 0.5, 1.0)
					draw_arc(Vector2(b.x, b.y), b.z * (1.0 + 0.5 * p), 0, TAU, 24, Color(UiKit.TEAL, a * (1.0 - p)), 2.0)
		var hint := "TAP TO CLOSE"
		var hw := f.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
		draw_string(f, Vector2(roundf(r.position.x + (r.size.x - hw) / 2.0), y + 4.0), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 8,
				Color(UiKit.DIM, 0.8 * a))

	## A tip's gesture icon in `r` (2:1), `t` s into its loop, at alpha `a`: a fingertip swiping side
	## to side, up or down, pressing (FIRE), a figure running into a wall (cover), a tripwire with an
	## alarm box, or the doors' arrows and padlock.
	static func draw_icon(ci: CanvasItem, kind: String, r: Rect2, t: float, a: float) -> void:
		var c := r.get_center()
		var teal := Color(UiKit.TEAL, a)
		var paper := Color(UiKit.PAPER, a)
		var dim := Color(UiKit.TEAL_DIM, a)
		var loop := fmod(t, 1.2) / 1.2
		var swing := 0.5 - 0.5 * cos(loop * TAU)  # (0 -> 1 -> 0)
		match kind:
			"swipe_side":
				var x := lerpf(-12.0, 12.0, swing)
				ci.draw_line(c + Vector2(-16, 0), c + Vector2(16, 0), dim, 1.0)
				_chevron(ci, c + Vector2(-20, 0), -1, teal)
				_chevron(ci, c + Vector2(20, 0), 1, teal)
				_finger(ci, c + Vector2(x, 0), paper)
			"swipe_up", "swipe_down":
				var dir := -1.0 if kind == "swipe_up" else 1.0
				var y := lerpf(-6.0 * dir, 6.0 * dir, fmod(t, 0.9) / 0.9)
				ci.draw_line(c + Vector2(0, 8), c + Vector2(0, -8), dim, 1.0)
				_chevron_v(ci, c + Vector2(0, 10.0 * dir), dir, teal)
				_finger(ci, c + Vector2(0, y), paper)
			"tap_side", "tap_up", "tap_down":
				# The move buttons' (MOVE: BUTTONS): small round buttons, a fingertip tapping each in
				# turn, lighting it (the side ones: left, then right).
				var dirs: Array = [Vector2i.LEFT, Vector2i.RIGHT] if kind == "tap_side" else [Vector2i.UP if kind == "tap_up" else Vector2i.DOWN]
				var on := int(loop * 2.0) % dirs.size()
				var down := fmod(loop * 2.0, 1.0) > 0.35  # (each tap: the finger comes down partway through)
				for i in dirs.size():
					var dir := Vector2(dirs[i])
					var p := c + Vector2((i * 2 - 1) * 12.0 if dirs.size() == 2 else 0.0, 0.0)
					var lit := i == on and down
					ci.draw_circle(p, 8.0, Color(UiKit.INK, a * 0.5))
					ci.draw_circle(p, 7.0, Color(UiKit.TEAL, a * (0.45 if lit else 0.18)))
					ci.draw_arc(p, 7.0, 0, TAU, 16, Color(UiKit.TEAL, a), 1.0)
					var side := Vector2(-dir.y, dir.x)
					ci.draw_colored_polygon(PackedVector2Array([p + dir * 3.5, p - dir * 2.0 + side * 3.0, p - dir * 2.0 - side * 3.0]), paper if lit else teal)
					if i == on:
						_finger(ci, p + Vector2(5, 5) + (Vector2.ZERO if down else Vector2(3, 3)), paper)
			"hold":
				# A press: the fingertip on the trigger, rings going out from it while it's held.
				ci.draw_arc(c + Vector2(10, 0), 7.0, 0, TAU, 16, teal, 2.0)
				ci.draw_line(c + Vector2(8, -2), c + Vector2(11, 6), Color(UiKit.RED, a), 2.0)
				for k in 2:
					var p := fmod(t * 1.4 + k * 0.5, 1.0)
					ci.draw_arc(c + Vector2(-8, 0), 3.0 + p * 7.0, 0, TAU, 16, Color(UiKit.TEAL, a * (1.0 - p)), 1.0)
				_finger(ci, c + Vector2(-8, 0), paper)
			"cover":
				# A wall, and a figure running up to it and pressing in behind it.
				ci.draw_rect(Rect2(c + Vector2(8, -9), Vector2(6, 18)), teal)
				var x2 := lerpf(-18.0, 2.0, minf(1.0, loop * 1.6))
				ci.draw_rect(Rect2(c + Vector2(x2, -6), Vector2(4, 4)), paper)
				ci.draw_rect(Rect2(c + Vector2(x2, -1), Vector2(4, 7)), paper)
			"wire":
				ci.draw_line(c + Vector2(-22, 6), c + Vector2(10, 6), Color(UiKit.RED, a * (0.7 + 0.3 * sin(t * 9.0))), 2.0)
				ci.draw_rect(Rect2(c + Vector2(-24, 2), Vector2(2, 8)), dim)
				ci.draw_rect(Rect2(c + Vector2(10, 2), Vector2(2, 8)), dim)
				ci.draw_rect(Rect2(c + Vector2(14, -9), Vector2(9, 9)), Color(UiKit.AMBER, a))
				ci.draw_rect(Rect2(c + Vector2(16, -7), Vector2(5, 5)), Color(UiKit.RED, a if fmod(t, 0.6) < 0.3 else a * 0.4))
			"doors":
				# An open door's arrows (as the stairs doors have them) and a locked one's padlock.
				for k in 3:
					var on := fmod(t * 3.0, 3.0) >= k
					_chevron_v(ci, c + Vector2(-12, 6 - k * 5), -1.0, Color(UiKit.TEAL, a if on else a * 0.35))
				UiKit.draw_padlock(ci, c + Vector2(8, -6), Color(UiKit.RED, a), 2)

	static func _finger(ci: CanvasItem, p: Vector2, col: Color) -> void:
		ci.draw_circle(p, 4.0, Color(UiKit.INK, col.a))
		ci.draw_circle(p, 3.0, col)

	static func _chevron(ci: CanvasItem, p: Vector2, dir: int, col: Color) -> void:
		ci.draw_polyline(PackedVector2Array([p + Vector2(-3 * dir, -4), p + Vector2(1 * dir, 0), p + Vector2(-3 * dir, 4)]), col, 2.0)

	static func _chevron_v(ci: CanvasItem, p: Vector2, dir: float, col: Color) -> void:
		ci.draw_polyline(PackedVector2Array([p + Vector2(-4, -3.0 * dir), p + Vector2(0, dir), p + Vector2(4, -3.0 * dir)]), col, 2.0)
