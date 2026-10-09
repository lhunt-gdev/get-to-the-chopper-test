class_name RouteGraph
extends RefCounted
## An authored mission route stored as data: segments (nodes) joined by
## directed edges. Routes are authored, never procedural (LOCKED).
##
## JSON format (see game/levels/prototype_slice/route.json):
##   mission: its id (each mission keeps its own route map); title; chopper: its timeline
##   squad: false keeps the Alert 3 pursuit squad out of it (on unless it says so)
##   cover_exit_rule: false switches the cover-exit rule off (only the frozen TEST RANGE does)
##   settings: {easy, medium, hard} (SETTINGS), each {chopper: its timeline, boss: {health, spinup:
##     [s at SNEAKING, CAUTION, ALERT]}}; then an obstacle, enemy, alarm box, searchlight or sniper can
##     say which settings it's in, like min_alert: "min_setting", "max_setting" or "settings": [...]
##     (for_setting). A route with settings is read for one of them (DEFAULT_SETTING if none is asked).
##   start: node id
##   nodes: [{ id, length, tier, bends: [{at, side}], obstacles: [...], next: [edge, ...], end }]
##   edge:  { to, label, side, via, min_alert, max_alert }
## An edge can be gated by alert level, so the routes on offer change with alert (LOCKED).
##
## Splits: only the outer lanes take a split. The far-left lane takes the "left" edge and the
## far-right lane the "right" edge. The middle lanes always carry "straight" on (the default side).
## A side edge goes via "corridor" (turns off), "stairs" (turns off and changes tier) or "ladder"
## (end-of-level climb to the chopper). A node with no straight edge captures a player who is
## in the middle lanes when they reach its end.

const SIDES := ["left", "straight", "right"]
## barrier: jump it. pipe: slide under it. tripwire: jump it or raise alert.
## box / wall: cover (run into it to take cover).
const OBSTACLE_KINDS := ["barrier", "pipe", "tripwire", "box", "wall"]
## Fairness (user rule): walls are solid, so no trooper may stand in a wall's lanes within this
## many metres behind it. No unfair surprises when you run round one.
const WALL_TROOPER_CLEARANCE := 15.0
## Fairness (user rule): where cover fills 3+ lanes, the open lanes are the only way through, so
## no jump/slide obstacle may be within this many metres in them. You can't swipe and jump at once.
const CROSSING_WINDOW := 4.0
## How deep each object is along the route (metres), and the clear gap needed between two
## objects in the same lane (user rule: nothing overlaps). Barriers, pipes and tripwires are as deep
## as the level builds them (prototype_slice.gd KINDS; a test keeps them the same): the
## fair-reaction rule times you through them.
const DEPTHS := {"barrier": 0.3, "pipe": 0.3, "tripwire": 0.05, "box": 0.9, "wall": 1.0, "booth": 3.5, "trooper": 0.5}
const MIN_GAP := 1.0
## The fair-reaction rule (user, 2026-10-08): "But it only works as long as there is still time for
## the player to land and swipe." Between two obstacles you have to act on in the same lane, there is
## always time to land if you must, then a swipe's reaction time, then for that swipe to work before
## the second one can trip you (reaction_gap). Obstacles to jump that one jump clears together
## (one_jump_reach) are one obstacle to it: there's no landing between them. What each one asks of you:
const ACTIONS := {"barrier": "jump", "tripwire": "jump", "pipe": "slide"}
## The swipe's reaction time (s), by setting. HARD is the floor ("for the harder level is ok for this
## to be challenging"): about a quarter of a second to see the cue (you're down, you're past it) and
## start the swipe, the swipe itself (the finger has to travel 8% of the screen's width before it
## counts: SwipeInput), and Safari's touch and display delay: about 0.35 s, rounded up. "On easy
## levels the gaps between objects will be larger": MEDIUM and EASY give more (reaction_for), and each
## setting is held to its own (validate_settings).
const REACTION_HARD := 0.4
const REACTION_MEDIUM := 0.5
const REACTION_EASY := 0.6
## A mission's settings, easiest first (user: "I think an easy medium and hard for each level is good
## means more replay value"). The same layout and routes on each; only the pressure changes: the
## chopper's time, the boss, and guards and tripwires by setting.
const SETTINGS := ["easy", "medium", "hard"]
## What a route with settings is read as when nobody says (the bots that don't pick one, the tests):
## MEDIUM, where the chopper times were first tuned.
const DEFAULT_SETTING := "medium"
## The keys an object can carry to say which settings it's in (for_setting).
const SETTING_KEYS := ["min_setting", "max_setting", "settings"]
## The lists of things in an area that can be by setting.
const BY_SETTING := ["obstacles", "enemies", "alarms", "searchlights", "snipers"]
## How far past its front and back faces an obstacle can still trip you (m): the level's hit test
## (prototype_slice.gd _check_obstacles) reaches this far.
const HIT_REACH := 0.2
## Optional per-obstacle "look" (overrides the area's default look; gameplay is unchanged).
const LOOKS := {"wall": ["booth"], "pipe": ["pipe", "wires", "double_pipe", "bunting", "girder", "banner", "exit_sign"], "box": ["crate", "desk", "cabinet", "roof_vent", "reception"],
		"barrier": ["cabinet", "blockade", "vent"]}
## Themes whose slide obstacles are live wires (unless "look" says otherwise).
const WIRE_THEMES := ["office", "security", "canteen"]
## Live wires span only this many neighbouring lanes (user rule: never all 5).
const WIRE_LANES := [3, 4]
## Nothing (an obstacle of any kind, a trooper, a dog, the alarm runner, a searchlight or a sniper)
## within this many metres after a stairwell's exit door, up or down: the same room a zone door
## gets (MARKER_CLEAR_AFTER). User, 2026-10-07: "Rule that after the player exits the stairs up or
## down objects can not be placed right outside, it's unfair as player can not react quick enough
## to avoid." (It used to count from the start of the area, where the flight begins, so only the
## 8 m after the door were kept clear: under a second at run speed.)
const STAIR_EXIT_CLEAR := 20.0
## How long a flight of stairs is (m): one tier (Tuning.tier_height, 4 m) up or down, at
## Tuning.stairs_run (3) metres on per metre of height. It's the first stretch of the area it takes
## you to, and its exit door is at its end. The level builds every flight from those two
## (prototype_slice.gd _segment_shape, ramp_len) and checks they still come to this when it loads.
const STAIRS_FLIGHT := 12.0
## So in an area reached by stairs, nothing before this far in (m): the flight, then the clear
## stretch after its exit door.
const STAIR_CLEAR_TO := STAIRS_FLIGHT + STAIR_EXIT_CLEAR
## Nothing (obstacle or trooper) this close before a halfway marker's double door, or this far
## after it: you burst through blind, so you need time to see what's ahead (like a stairwell's exit).
## Enemy kinds a level can place.
const ENEMY_KINDS := ["rifle_trooper", "rusher_dog", "security_trooper"]
const MARKER_CLEAR_BEFORE := 6.0
const MARKER_CLEAR_AFTER := 20.0
## Zone doors (the old halfway marker, "marker" in route.json): this far into an area, after the
## split behind you is decided.
const ZONE_DOOR_AT := 8
## Searchlights on the roofs: at least this far apart (m), so each one is its own moment.
const SEARCHLIGHT_GAP := 20.0
## ...and not in the last stretch before a split, where you're lining up for your exit.
const SEARCHLIGHT_SPLIT_CLEAR := 25.0
## Snipers (user design): the stretch from his spot to just past where he fires (m; he tracks for a
## second and locks for under one, at run speed), kept free of obstacles so a dodge is always one
## free lane away; clear of searchlights by this much each side, so a dodge never steps into a
## pool; done before the last stretch of an area (its fork and slowdown); this far apart.
const SNIPER_STRETCH := 24.0
const SNIPER_LIGHT_CLEAR := 10.0
const SNIPER_END_CLEAR := 22.0
const SNIPER_GAP := 30.0
## No cover wall on the inside of a corner (user rule): it blocks the view round it and looks
## wrong. Each bend is a jog: it turns toward its side, runs BEND_RUN m (Tuning.branch_out_length),
## then turns back, so it has two corners, the second with its inside on the other side. A corridor
## turn-off does the same at its start. Walls must keep off the corner's inside lanes from
## CORNER_CLEAR_BEFORE m before each corner to CORNER_CLEAR_AFTER m after it.
const BEND_RUN := 14.0
const CORNER_CLEAR_BEFORE := 12.0
const CORNER_CLEAR_AFTER := 4.0
## The lanes on the inside of a corner, by the side it turns to (authored for 5 lanes).
const INSIDE_LANES := {"left": [0, 1], "right": [3, 4]}
## Areas with no walls to mount tripwire emitters on (user rule: no tripwires on the rooftops).
const NO_TRIPWIRE_THEMES := ["rooftops", "towers", "gantry", "skylights", "antennas", "edge"]
const VIAS := ["corridor", "stairs", "ladder"]
## Height tiers, in tier steps (Tuning.tier_height metres each).
const TIERS := {"roof": 1, "ground": 0, "underground": -1}

var start_id: StringName = &""
var _nodes: Dictionary = {}  # StringName -> Dictionary
## The mission-wide settings from the top of the file (e.g. "chopper": its own timeline). For a
## route with settings, read for one: that setting's "chopper" and "boss" in place, and "setting".
var _mission: Dictionary = {}
## Which setting this is the route for ("" for a route without settings: the TEST RANGE).
var setting := ""


static func from_json_file(path: String, for_setting_name: String = "") -> RouteGraph:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("RouteGraph: cannot open %s (is *.json in the export include filter?)" % path)
		return null
	return from_dict(JSON.parse_string(f.get_as_text()), for_setting_name)


## A route from its data. One with settings is read for `for_setting_name` (DEFAULT_SETTING if empty):
## only what's in that setting, with its chopper and boss (for_setting).
static func from_dict(data: Dictionary, for_setting_name: String = "") -> RouteGraph:
	if data.get("settings") is Dictionary:
		data = for_setting(data, for_setting_name if for_setting_name != "" else DEFAULT_SETTING)
	var g := RouteGraph.new()
	g.start_id = StringName(data.get("start", ""))
	g._mission = data
	g.setting = String(data.get("setting", ""))
	for n: Dictionary in data.get("nodes", []):
		g._nodes[StringName(n["id"])] = n
	return g


## A route with settings, as it is on one of them (a copy; the data is left as it is): its chopper and
## boss from that setting's block, and in each area only the things in that setting (in_setting).
static func for_setting(data: Dictionary, which: String) -> Dictionary:
	var out := data.duplicate(true)
	var block: Dictionary = data.get("settings", {}).get(which, {}) if data.get("settings") is Dictionary else {}
	out["setting"] = which
	for key in ["chopper", "boss"]:
		if block.has(key):
			out[key] = block[key].duplicate(true)
	for n: Dictionary in out.get("nodes", []):
		for list in BY_SETTING:
			if n.get(list) is Array:
				n[list] = n[list].filter(func(thing: Variant) -> bool: return not thing is Dictionary or in_setting(thing, which))
	return out


## Whether a thing (an obstacle, a guard, an alarm box...) is there on a setting: by its "settings"
## (the ones it's in), or "min_setting" / "max_setting" (like min_alert: from, and up to); with none,
## on every setting.
static func in_setting(thing: Dictionary, which: String) -> bool:
	var rank := SETTINGS.find(which)
	if thing.get("settings") is Array:
		return which in thing["settings"]
	if rank < SETTINGS.find(String(thing.get("min_setting", SETTINGS[0]))):
		return false
	return rank <= SETTINGS.find(String(thing.get("max_setting", SETTINGS[-1])))


## The swipe's reaction time a setting is held to (the fair-reaction and cover-exit rules): HARD's
## floor, MEDIUM and EASY more ("on easy levels the gaps between objects will be larger").
static func reaction_for(which: String) -> float:
	return {"easy": REACTION_EASY, "medium": REACTION_MEDIUM}.get(which, REACTION_HARD)


## Every route rule on every setting of a route's data, each at its own reaction floor
## (reaction_for), plus the settings' own rules (_settings_problems); each problem says which setting.
## A route without settings: validate() as it is.
static func validate_settings(data: Dictionary, tuning: Tuning = null) -> PackedStringArray:
	if not data.get("settings") is Dictionary:
		return from_dict(data).validate(tuning)
	var problems := _settings_problems(data)
	for which: String in SETTINGS:
		if not data["settings"].has(which):
			continue
		for p in from_dict(data, which).validate(tuning, reaction_for(which)):
			problems.append("[%s] %s" % [which.to_upper(), p])
	return problems


## The settings themselves: all three there, each with a chopper timeline in order and a boss; a
## harder one never kinder (the chopper no later, the boss no weaker, his spin-ups no slower); every
## object's setting names real; and the first area the same on every one (it's built under the main
## menu, before a setting is picked: the level swaps the rest when one is).
static func _settings_problems(data: Dictionary) -> PackedStringArray:
	var problems := PackedStringArray()
	var blocks: Dictionary = data["settings"]
	for which in blocks:
		if not which in SETTINGS:
			problems.append("unknown setting '%s' (easy, medium or hard)" % which)
	var last := {}
	for which: String in SETTINGS:
		if not blocks.has(which) or not blocks[which] is Dictionary:
			problems.append("the %s setting is missing" % which)
			continue
		var b: Dictionary = blocks[which]
		var ch: Dictionary = b.get("chopper", {}) if b.get("chopper") is Dictionary else {}
		var t0 := float(ch.get("lands_at", 0)); var t1 := float(ch.get("lifts_at", 0)); var t2 := float(ch.get("gone_at", 0))
		if not (t0 > 0.0 and t0 < t1 and t1 < t2):
			problems.append("%s: its chopper times must be lands_at < lifts_at < gone_at" % which)
		var boss: Dictionary = b.get("boss", {}) if b.get("boss") is Dictionary else {}
		var spin: Array = boss.get("spinup", []) if boss.get("spinup") is Array else []
		if int(boss.get("health", 0)) <= 0 or spin.size() != 3 or spin.any(func(s: Variant) -> bool: return float(s) <= 0.0):
			problems.append("%s: the boss needs \"health\" (hits) and \"spinup\" (3 times, s: SNEAKING, CAUTION, ALERT)" % which)
		if b.has("start_alert") and int(b["start_alert"]) != 1:
			problems.append("%s: every setting starts at SNEAKING" % which)
		if not last.is_empty():
			if t1 > float(last["lifts"]) or t2 > float(last["gone"]):
				problems.append("%s: the chopper waits longer than on %s" % [which, last["name"]])
			if int(boss.get("health", 0)) < int(last["health"]):
				problems.append("%s: the boss takes fewer hits than on %s" % [which, last["name"]])
			for i in mini(spin.size(), last["spin"].size()):
				if float(spin[i]) > float(last["spin"][i]):
					problems.append("%s: the boss spins up slower than on %s" % [which, last["name"]])
					break
		last = {"name": which, "lifts": t1, "gone": t2, "health": int(boss.get("health", 0)), "spin": spin}
	for n: Dictionary in data.get("nodes", []):
		for list in BY_SETTING:
			for thing in n.get(list, []):
				if not thing is Dictionary:
					continue
				var names: Array = thing.get("settings", []) if thing.get("settings") is Array else []
				for key in ["min_setting", "max_setting"]:
					if thing.has(key):
						names.append(thing[key])
				for s in names:
					if not String(s) in SETTINGS:
						problems.append("node '%s': %s at %s m: unknown setting '%s'" % [n.get("id"), thing.get("kind", list), thing.get("at"), s])
				if String(n.get("id", "")) == String(data.get("start", "")) and SETTING_KEYS.any(func(k: String) -> bool: return thing.has(k)):
					problems.append("node '%s': %s at %s m is by setting, but the first area is built under the main menu: it must be the same on every setting"
							% [n.get("id"), thing.get("kind", list), thing.get("at")])
	return problems


func mission() -> Dictionary:
	return _mission


func has_node_id(id: StringName) -> bool:
	return _nodes.has(id)


func node_data(id: StringName) -> Dictionary:
	return _nodes.get(id, {})


func length_of(id: StringName) -> float:
	return float(node_data(id).get("length", 50.0))


## What a fork shows for an exit: UP or DOWN for stairs; otherwise its label (or the area name).
func edge_label(from: StringName, edge: Dictionary) -> String:
	if via_of(edge) == "stairs":
		return "UP" if tier_of(StringName(edge.get("to", ""))) > tier_of(from) else "DOWN"
	return String(edge.get("label", display_name(StringName(edge.get("to", "")))))


## What the area is called on screen: its "name", or its id in capitals.
func display_name(id: StringName) -> String:
	return String(node_data(id).get("name", String(id).to_upper().replace("_", " ")))


## Non-empty when this node finishes the mission (e.g. "extract").
func end_type(id: StringName) -> String:
	return String(node_data(id).get("end", ""))


## -1 underground, 0 ground, 1 roof.
func tier_of(id: StringName) -> int:
	return int(TIERS.get(node_data(id).get("tier", "ground"), 0))


## The outgoing edges open at this alert level, in authored order.
func available_next(id: StringName, alert_level: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for edge: Dictionary in node_data(id).get("next", []):
		if alert_level < int(edge.get("min_alert", 1)):
			continue
		if alert_level > int(edge.get("max_alert", 3)):
			continue
		out.append(edge)
	return out


## Every authored edge, whatever the alert level.
func all_next(id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for edge: Dictionary in node_data(id).get("next", []):
		out.append(edge)
	return out


## The doors to the stairs up or down at the end of this node, and whether each is open at this
## alert: [{edge, side, open}]. The level's door cues: arrows in while open, a padlock while
## locked (user). Ladders aren't doors, so they're left out.
func stair_doors(id: StringName, alert_level: int) -> Array[Dictionary]:
	var open := available_next(id, alert_level)
	var out: Array[Dictionary] = []
	for edge in all_next(id):
		if via_of(edge) == "stairs":
			out.append({"edge": edge, "side": side_of(edge), "open": open.has(edge)})
	return out


static func side_of(edge: Dictionary) -> String:
	return String(edge.get("side", "straight"))


static func via_of(edge: Dictionary) -> String:
	return String(edge.get("via", "corridor")) if side_of(edge) != "straight" else ""


## Which side a lane takes: only the outer lanes split off.
static func lane_side(lane: int, lane_count: int) -> String:
	if lane <= 0:
		return "left"
	if lane >= lane_count - 1:
		return "right"
	return "straight"


## The edge a player in this lane takes. An outer lane takes its side's edge if that is open,
## otherwise straight on. Empty means there is no way on from here: the player is captured.
static func pick_edge(lane: int, lane_count: int, options: Array[Dictionary]) -> Dictionary:
	var side := lane_side(lane, lane_count)
	for want in [side, "straight"]:
		for edge in options:
			if side_of(edge) == want:
				return edge
	return {}


## True when the open options are a real choice worth showing (anything but a single straight road).
static func is_choice(options: Array[Dictionary]) -> bool:
	return options.size() >= 2 or (options.size() == 1 and side_of(options[0]) != "straight")


## Spots where cover fills 3+ lanes and a jump/slide obstacle sits in an open lane close by.
static func _forced_crossings(id: StringName, obstacles: Array) -> PackedStringArray:
	var problems := PackedStringArray()
	var reported := {}
	for c in obstacles:
		if not String(c.get("kind", "")) in ["box", "wall"]:
			continue
		var at := float(c.get("at", 0))
		var covered := {}
		for o in obstacles:
			if String(o.get("kind", "")) in ["box", "wall"] and absf(float(o.get("at", 0)) - at) <= CROSSING_WINDOW:
				for l in o.get("lanes", []):
					covered[int(l)] = true
		if covered.size() < 3:
			continue
		for o in obstacles:
			if not String(o.get("kind", "")) in ["barrier", "pipe"] or absf(float(o.get("at", 0)) - at) > CROSSING_WINDOW:
				continue
			for l in o.get("lanes", []):
				if not covered.has(int(l)) and not reported.has(o):
					reported[o] = true
					problems.append("node '%s': %s at %s m blocks the only way past the cover at %s m (you can't swipe and jump at once)"
							% [id, o["kind"], o.get("at"), c.get("at")])
					break
	return problems


## The cover-exit rule (the fair-reaction rule's floor, out of cover): in cover you're stopped just in
## front of it (cover_stop_gap short of its face), and a swipe sideways puts you straight back to
## full speed in the next lane. So whatever you meet first there, if it's something to jump or slide
## (a barrier, a pipe or a tripwire), its stretch must start far enough ahead for the second swipe
## after the first: `reaction` seconds and a frame (the swipe is read once a frame), and a jump's lift
## to clear height. That's this many metres of road, from where you stop to where it can trip you.
## (Cover first in that lane is fine: you stop again, and it's that cover's own way out that counts.)
static func cover_exit_gap(kind: String, t: Tuning, reaction: float = REACTION_HARD) -> float:
	var need := reaction + 1.0 / Engine.physics_ticks_per_second
	if ACTIONS[kind] == "jump":
		need += _above_clear_height(t).x
	return need * t.run_speed


## Each way out of each cover in an area, sideways into a lane the cover doesn't fill, by the
## cover-exit rule (cover_exit_gap).
static func _cover_exits(id: StringName, obstacles: Array, t: Tuning, reaction: float, lane_count: int) -> PackedStringArray:
	var problems := PackedStringArray()
	for c in obstacles:
		var c_kind := String(c.get("kind", ""))
		if not c_kind in ["box", "wall"]:
			continue
		var stop: float = float(c.get("at", 0)) - DEPTHS[c_kind] / 2.0 - t.cover_stop_gap
		var c_lanes: Array = c.get("lanes", []).map(func(v: Variant) -> int: return int(v))
		for lane: int in c_lanes:
			for to: int in [lane - 1, lane + 1]:
				if to < 0 or to >= lane_count or to in c_lanes:
					continue
				# The first thing ahead in that lane: cover you'd stop at, or a stretch that can trip you.
				var first: Dictionary = {}
				var first_at := INF
				for o in obstacles:
					if not int(to) in o.get("lanes", []).map(func(v: Variant) -> int: return int(v)):
						continue
					var kind := String(o.get("kind", ""))
					var at := float(o.get("at", 0))
					var begins := INF
					if kind in ["box", "wall"]:
						begins = at - float(DEPTHS[kind]) / 2.0 - t.cover_stop_gap if at > stop else INF
					elif ACTIONS.has(kind) and at + float(DEPTHS[kind]) / 2.0 + HIT_REACH > stop:
						begins = at - float(DEPTHS[kind]) / 2.0 - HIT_REACH
					if begins < first_at:
						first_at = begins
						first = o
				if first.is_empty() or not ACTIONS.has(String(first.get("kind", ""))):
					continue
				var need := cover_exit_gap(String(first["kind"]), t, reaction)
				if first_at - stop < need - 0.001:
					problems.append("node '%s': out of the %s at %s m in lane %d into lane %d, the %s at %s m comes too soon (%.2f m from where you stop in cover to it, %.2f m needed: a %.2f s swipe)"
							% [id, c_kind, c.get("at"), lane, to, first["kind"], first.get("at"), maxf(first_at - stop, 0.0), need, reaction])
	return problems


## Objects that would overlap: two things sharing a lane closer than their depths plus MIN_GAP.
static func _overlaps(id: StringName, obstacles: Array, enemies: Array) -> PackedStringArray:
	var things: Array[Dictionary] = []
	for o in obstacles:
		# A guard booth runs 3 m on down the road behind its front face: centre it there, deeper.
		var booth := String(o.get("look", "")) == "booth"
		things.append({"what": "booth" if booth else String(o.get("kind", "")), "at": float(o.get("at", 0)) - (1.25 if booth else 0.0), "lanes": o.get("lanes", [])})
	for e in enemies:
		things.append({"what": "trooper", "at": float(e.get("at", 0)), "lanes": [e.get("lane", -1)]})
	var problems := PackedStringArray()
	for i in things.size():
		for j in range(i + 1, things.size()):
			var a := things[i]
			var b := things[j]
			var shared := false
			for l in a["lanes"]:
				if int(l) in b["lanes"].map(func(v: Variant) -> int: return int(v)):
					shared = true
			var room: float = (DEPTHS.get(a["what"], 0.5) + DEPTHS.get(b["what"], 0.5)) / 2.0 + MIN_GAP
			if shared and absf(a["at"] - b["at"]) < room:
				problems.append("node '%s': %s at %s m overlaps %s at %s m" % [id, a["what"], a["at"], b["what"], b["at"]])
	return problems


## The fair-reaction rule's least distance (m, centre to centre down the road) from a `first` to a
## `second` obstacle in the same lane (kinds in ACTIONS), worked out from Tuning's run and jump, so
## that however you got past `first`, there is time to land if you must, then `reaction` seconds to
## swipe, then for the swipe to work before `second` can trip you. A sidestep doesn't count as a way
## out: it is a swipe too, and it only moves you into another lane's obstacles.
static func reaction_gap(first: String, second: String, t: Tuning, reaction: float = REACTION_HARD) -> float:
	# The stretch of road each one can trip you on.
	var zone_a: float = DEPTHS[first] + 2.0 * HIT_REACH
	var zone_b: float = DEPTHS[second] + 2.0 * HIT_REACH
	return zone_a / 2.0 + _clear_road(ACTIONS[first], zone_a, ACTIONS[second], t, reaction) + zone_b / 2.0


## The fair-reaction rule's clear road (m) from the end of a stretch you act on, `zone_a` m long (one
## obstacle's, or the stretch of a few that one jump clears together), to the start of the next one's,
## by what each asks of you ("jump" or "slide"): time to land if you must, then `reaction` seconds to
## swipe, then for the swipe to work.
static func _clear_road(first: String, zone_a: float, second: String, t: Tuning, reaction: float) -> float:
	var lift := t.jump_velocity
	var g := t.gravity
	var air := 2.0 * lift / g  # a whole jump, up and down
	var clear := _above_clear_height(t)
	var up := clear.x
	var down := clear.y
	# Seconds from leaving the first one's stretch to reaching the second's: the reaction, and a
	# frame, since the game reads the swipe and checks for a hit once a frame (the swipe has to be in
	# by the frame before the second one's stretch).
	var need := reaction + 1.0 / Engine.physics_ticks_per_second
	if first == "jump":
		# The latest jump that clears it (his feet at clear height just as its stretch starts) has
		# him this far into the jump as he leaves it: the longest in the air after it.
		var off := up + zone_a / t.run_speed
		if second == "jump":
			need += air - off  # he has to land first: an up swipe in the air does nothing
		else:
			# A down swipe in the air drops him at jump_velocity straight into the slide, which counts
			# once he's down (Player.handle_swipe). The longest drop is from the highest he can be
			# when he swipes.
			var at := clampf(lift / g, off + reaction, down + need)
			var h := maxf(lift * at - g * at * at / 2.0, 0.0) if at < air else 0.0
			need += (sqrt(lift * lift + 2.0 * g * h) - lift) / g
	if second == "jump":
		need += up  # an up swipe's lift to clear height
	return need * t.run_speed


## In a jump, his feet are above jump_clear_height from x until y seconds after he takes off.
static func _above_clear_height(t: Tuning) -> Vector2:
	var root := sqrt(maxf(t.jump_velocity * t.jump_velocity - 2.0 * t.gravity * t.jump_clear_height, 0.0))
	return Vector2(t.jump_velocity - root, t.jump_velocity + root) / t.gravity


## The longest stretch of road (m) one jump carries his feet over above jump_clear_height, less a
## frame's run: the game reads the swipe once a frame, so he can only take off on a frame, and there
## must be one whose jump clears the whole stretch. Jump obstacles in a lane closer together than
## this, from the front of the first one's stretch to the back of the last one's, are one jump to the
## fair-reaction rule (user: "there is still time for the player to land and swipe": with one jump
## over them all, there's no landing between them to need time for).
static func one_jump_reach(t: Tuning) -> float:
	var clear := _above_clear_height(t)
	return (clear.y - clear.x - 1.0 / Engine.physics_ticks_per_second) * t.run_speed


## The furthest apart (m, centre to centre) a `first` and a `second` obstacle to jump can be in a lane
## for one jump to clear both. Further apart, the second needs reaction_gap.
static func one_jump_gap(first: String, second: String, t: Tuning) -> float:
	return one_jump_reach(t) - (DEPTHS[first] + DEPTHS[second]) / 2.0 - 2.0 * HIT_REACH


## A stretch of road's obstacles for the fair-reaction rule: the ones to act on and the cover (which
## stops you), as {kind, at, lanes, name, area}. `offset` is added to each "at"; `lanes` maps an
## authored lane to the lane it's checked in (missing: left out).
func _road_of(id: StringName, offset: float = 0.0, lanes: Dictionary = {}) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for ob in node_data(id).get("obstacles", []):
		var kind := String(ob.get("kind", ""))
		if not (ACTIONS.has(kind) or kind in ["box", "wall"]):
			continue
		var in_lanes: Array[int] = []
		for l in ob.get("lanes", []):
			if lanes.is_empty():
				in_lanes.append(int(l))
			elif lanes.has(int(l)):
				in_lanes.append(int(lanes[int(l)]))
		if in_lanes.is_empty():
			continue
		var name := "%s at %s m" % [kind, ob.get("at")] + (" into '%s'" % id if offset > 0.0 else "")
		out.append({"kind": kind, "at": float(ob.get("at", 0)) + offset, "lanes": in_lanes, "name": name, "area": id})
	return out


## The fair-reaction rule along a stretch of road (_road_of): in each lane, each obstacle to act on
## and the next one there (unless cover between them stops you first) must be reaction_gap apart.
## Obstacles to jump that one jump clears together (one_jump_reach) count as one, as deep as the
## stretch they cover. `across` (the road of two areas joined): only the pairs from one area into
## the next, the first one starting in the area before (a one-jump pair over the join included, so
## what follows it is timed from the pair) and the second in the next. `inside`: only the pairs
## that start in that area (on a road joined to the area before it: _too_soon_in).
static func _too_soon(where: String, road: Array, t: Tuning, reaction: float, across := false, inside: StringName = &"") -> PackedStringArray:
	var order := road.duplicate()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["at"] < b["at"])
	var reach := one_jump_reach(t)
	var pairs := {}  # "first's obstacles | second's" (indices in `order`) -> {a, b, lanes}
	var lanes := {}
	for o in order:
		for l: int in o["lanes"]:
			lanes[l] = true
	for lane: int in lanes:
		# What you act on in this lane, in order: {members (indices in `order`), start, end, action}
		# for each obstacle, or for each run of them that one jump clears; {} for cover (you stop at it).
		var acts: Array[Dictionary] = []
		for i in order.size():
			var o: Dictionary = order[i]
			if not lane in o["lanes"]:
				continue
			if not ACTIONS.has(o["kind"]):
				acts.append({})
				continue
			var half: float = DEPTHS[o["kind"]] / 2.0 + HIT_REACH
			var last: Dictionary = acts.back() if not acts.is_empty() else {}
			if not last.is_empty() and last["action"] == "jump" and ACTIONS[o["kind"]] == "jump" \
					and maxf(last["end"], o["at"] + half) - minf(last["start"], o["at"] - half) <= reach + 0.001:
				last["members"].append(i)
				last["start"] = minf(last["start"], o["at"] - half)
				last["end"] = maxf(last["end"], o["at"] + half)
			else:
				acts.append({"members": [i], "start": o["at"] - half, "end": o["at"] + half, "action": ACTIONS[o["kind"]]})
		for k in range(1, acts.size()):
			var a := acts[k - 1]
			var b := acts[k]
			if a.is_empty() or b.is_empty():
				continue
			if across and order[a["members"][0]]["area"] == order[b["members"][0]]["area"]:
				continue
			if inside != &"" and order[a["members"][0]]["area"] != inside:
				continue
			var key := "%s|%s" % [a["members"], b["members"]]
			if not pairs.has(key):
				pairs[key] = {"a": a, "b": b, "lanes": []}
			pairs[key]["lanes"].append(lane)
	var found := pairs.values()
	found.sort_custom(func(p: Dictionary, q: Dictionary) -> bool:
		return Vector2i(p["a"]["members"].back(), p["b"]["members"][0]) < Vector2i(q["a"]["members"].back(), q["b"]["members"][0]))
	var problems := PackedStringArray()
	for pair: Dictionary in found:
		var a: Dictionary = pair["a"]
		var b: Dictionary = pair["b"]
		var road_needed := _clear_road(a["action"], a["end"] - a["start"], b["action"], t, reaction)
		var clear: float = b["start"] - a["end"]
		if clear < road_needed - 0.001:
			# Told centre to centre, from the last one you're past to the first one ahead.
			var apart: float = order[b["members"][0]]["at"] - order[a["members"].back()]["at"]
			var in_lanes: Array = pair["lanes"]
			in_lanes.sort()
			problems.append("%s: %s is too soon after the %s in lane%s %s (%.2f m apart, %.2f m needed: time to land if you must, then a %.2f s swipe)"
					% [where, _act_name(order, b), _act_name(order, a), "s" if in_lanes.size() > 1 else "", ", ".join(PackedStringArray(in_lanes.map(func(l: int) -> String: return str(l)))),
					apart, apart + road_needed - clear, reaction])
	return problems


## What the fair-reaction rule calls one thing you act on (_too_soon): an obstacle, or a run of them
## one jump clears.
static func _act_name(order: Array, act: Dictionary) -> String:
	var names := PackedStringArray()
	for i: int in act["members"]:
		names.append(order[i]["name"])
	if names.size() == 1:
		return names[0]
	return "%s (one jump clears %s)" % [" and the ".join(names), "both" if names.size() == 2 else "them all"]


## The fair-reaction rule across the join from this area into each next one (the pairs from one into
## the other: _too_soon's `across`). Up a ladder you climb rather than run.
func _too_soon_on(id: StringName, t: Tuning, reaction: float) -> PackedStringArray:
	var problems := PackedStringArray()
	var here := _road_of(id)
	for edge in all_next(id):
		var to := StringName(edge.get("to", ""))
		if not _nodes.has(to) or via_of(edge) == "ladder":
			continue
		problems.append_array(_too_soon("node '%s' into '%s'" % [id, to], here + _road_of(to, length_of(id), _join_lanes(edge)), t, reaction, true))
	return problems


## Which of the next area's lanes you run on into along `edge`, and from which lane of this one:
## {its lane: this lane}. Straight on, every lane goes on; at a side exit, only its outer lane does,
## as the branch's lane nearest the main road (the level's _handover_lanes).
func _join_lanes(edge: Dictionary) -> Dictionary:
	var last_lane := int(_mission.get("authored_for_lanes", 5)) - 1
	var lanes := {}
	match side_of(edge):
		"left":
			lanes[last_lane] = 0
		"right":
			lanes[0] = last_lane
		_:
			for l in last_lane + 1:
				lanes[l] = l
	return lanes


## The fair-reaction rule inside one area, its pairs timed as you meet them coming in: on its own
## road where you can come in without running on into it (it's the start, nothing leads in, or a
## ladder does), and on its road joined to the area before for each way you run on into it. So a
## one-jump pair over the join counts as one, as it would inside one area (what follows it is timed
## from the pair: _too_soon_on tells that one), and a way in that runs nothing on into it times the
## area's first obstacles as they stand. A pair found more than one way is told once.
func _too_soon_in(id: StringName, ways_in: Array, t: Tuning, reaction: float) -> PackedStringArray:
	var where := "node '%s'" % id
	var own := _road_of(id)
	var problems := PackedStringArray()
	var alone := ways_in.is_empty() or id == start_id
	for way: Dictionary in ways_in:
		if via_of(way["edge"]) == "ladder":
			alone = true
	if alone:
		problems.append_array(_too_soon(where, own, t, reaction))
	for way: Dictionary in ways_in:
		if via_of(way["edge"]) == "ladder":
			continue
		var from: StringName = way["from"]
		var back := {}  # the area before's lanes -> this one's
		var lanes := _join_lanes(way["edge"])
		for l: int in lanes:
			back[lanes[l]] = l
		for problem in _too_soon(where, _road_of(from, -length_of(from), back) + own, t, reaction, false, id):
			if not problem in problems:
				problems.append(problem)
	return problems


## Every way into each area: {area: [{from, edge}]}, whatever the alert.
func _ways_in() -> Dictionary:
	var ways := {}
	for id: StringName in _nodes:
		for edge in all_next(id):
			var to := StringName(edge.get("to", ""))
			if _nodes.has(to):
				if not ways.has(to):
					ways[to] = []
				ways[to].append({"from": id, "edge": edge})
	return ways


## True if some route from this node reaches the end of the mission (whatever the alert).
func reaches_end(from: StringName) -> bool:
	var seen := {}
	var todo: Array[StringName] = [from]
	while not todo.is_empty():
		var id: StringName = todo.pop_back()
		if seen.has(id) or not _nodes.has(id):
			continue
		seen[id] = true
		if end_type(id) != "":
			return true
		for edge in all_next(id):
			todo.append(StringName(edge.get("to", "")))
	return false


## Returns a list of problems. Empty means the graph is valid. The fair-reaction rule is worked out
## from `tuning` (Tuning's defaults if none), with `reaction` for the swipe (the setting's).
func validate(tuning: Tuning = null, reaction: float = REACTION_HARD) -> PackedStringArray:
	var t := tuning if tuning != null else Tuning.new()
	var problems := PackedStringArray()
	if not _nodes.has(start_id):
		problems.append("start node '%s' does not exist" % start_id)
	var ch: Dictionary = _mission.get("chopper", {})
	if not ch.is_empty():
		var t0 := float(ch.get("lands_at", 0)); var t1 := float(ch.get("lifts_at", 0)); var t2 := float(ch.get("gone_at", 0))
		if not (t0 > 0.0 and t0 < t1 and t1 < t2):
			problems.append("mission chopper times must be lands_at < lifts_at < gone_at")
	var ways_in := _ways_in()
	# Every route, up, down or main, must still get you to the chopper.
	for id: StringName in _nodes:
		if not reaches_end(id):
			problems.append("node '%s' can never reach the end of the mission" % id)
	for id: StringName in _nodes:
		var n: Dictionary = _nodes[id]
		var edges: Array = n.get("next", [])
		if edges.is_empty() and String(n.get("end", "")) == "":
			problems.append("node '%s' has no exits and is not an end" % id)
		if not TIERS.has(n.get("tier", "ground")):
			problems.append("node '%s' has unknown tier '%s'" % [id, n.get("tier")])
		for bend in n.get("bends", []):
			if not bend is Dictionary or not String(bend.get("side", "")) in ["left", "right"]:
				problems.append("node '%s': a bend needs \"side\": \"left\" or \"right\"" % id)
			elif float(bend.get("at", -1)) <= 0.0 or float(bend.get("at", -1)) >= float(n.get("length", 50.0)):
				problems.append("node '%s': bend at %s m is outside the segment" % [id, bend.get("at")])
		var length := float(n.get("length", 50.0))
		for ob in n.get("obstacles", []):
			var kind := String(ob.get("kind", ""))
			var lanes: Array = ob.get("lanes", [])
			var wires := kind == "pipe" and String(ob.get("look", "wires" if n.get("theme", "") in WIRE_THEMES else "pipe")) == "wires"
			if wires:
				var span := lanes.duplicate()
				span.sort()
				var contiguous := not span.is_empty() and int(span[-1]) - int(span[0]) == span.size() - 1
				if not contiguous or not span.size() in WIRE_LANES:
					problems.append("node '%s': live wires at %s m must span 3 or 4 neighbouring lanes" % [id, ob.get("at")])
			if kind == "tripwire" and n.get("theme", "") in NO_TRIPWIRE_THEMES:
				problems.append("node '%s': no tripwires here (nothing to mount the emitters on)" % id)
			if ob.has("look") and not String(ob["look"]) in LOOKS.get(kind, []):
				problems.append("node '%s': %s at %s m can't look like '%s'" % [id, kind, ob.get("at"), ob["look"]])
			if not kind in OBSTACLE_KINDS:
				problems.append("node '%s': unknown obstacle kind '%s'" % [id, kind])
			elif kind == "wall":
				# Wall cover is one piece, 1-2 neighbouring lanes wide.
				var sorted := lanes.duplicate()
				sorted.sort()
				if sorted.is_empty() or sorted.size() > 2 or (sorted.size() == 2 and int(sorted[1]) - int(sorted[0]) != 1):
					problems.append("node '%s': wall at %s m must cover 1 or 2 neighbouring lanes" % [id, ob.get("at")])
			elif kind == "box" and not String(ob.get("material", "wood")) in ["wood", "metal"]:
				problems.append("node '%s': box at %s m must be wood or metal" % [id, ob.get("at")])
			if kind == "wall":
				for e in n.get("enemies", []):
					var behind := float(e.get("at", 0)) - float(ob.get("at", 0))
					if int(e.get("lane", -1)) in lanes and behind >= 0.0 and behind < WALL_TROOPER_CLEARANCE:
						problems.append("node '%s': trooper at %s m is hidden right behind the wall at %s m" % [id, e.get("at"), ob.get("at")])
		# The quiet route (user): underground there are no enemies, tripwires or alarm boxes.
		if String(n.get("tier", "ground")) == "underground":
			if not n.get("enemies", []).is_empty():
				problems.append("node '%s': no enemies underground" % id)
			if not n.get("alarms", []).is_empty():
				problems.append("node '%s': no alarm boxes underground" % id)
			for ob in n.get("obstacles", []):
				if String(ob.get("kind", "")) == "tripwire":
					problems.append("node '%s': no tripwires underground (the alert can't change down there)" % id)
		# Zone doors (user): every ground or underground area you can enter straight on from the
		# same height starts with one; nothing else has one.
		if needs_zone_door(id) != n.has("marker"):
			problems.append("node '%s': %s" % [id, "needs a zone door (\"marker\": {\"at\": %d})" % ZONE_DOOR_AT if needs_zone_door(id) else "has a zone door but you never enter it straight on from the same height"])
		if n.has("marker"):
			var m_at := float(n["marker"].get("at", -1))
			if n.get("theme", "") in NO_TRIPWIRE_THEMES:
				problems.append("node '%s': no zone doors on open roofs" % id)
			if m_at <= 0.0 or m_at >= length:
				problems.append("node '%s': zone door at %s m is outside the area" % [id, m_at])
			for thing in n.get("obstacles", []) + n.get("enemies", []):
				var gap := float(thing.get("at", 0)) - m_at
				if gap > -MARKER_CLEAR_BEFORE and gap < MARKER_CLEAR_AFTER:
					problems.append("node '%s': %s at %s m is too close to the zone door at %s m" % [id, thing.get("kind"), thing.get("at"), m_at])
		problems.append_array(_forced_crossings(id, n.get("obstacles", [])))
		if bool(_mission.get("cover_exit_rule", true)):
			problems.append_array(_cover_exits(id, n.get("obstacles", []), t, reaction, int(_mission.get("authored_for_lanes", 5))))
		problems.append_array(_corner_walls(id, n.get("obstacles", []), corners_of(id)))
		problems.append_array(_overlaps(id, n.get("obstacles", []), n.get("enemies", [])))
		problems.append_array(_too_soon_in(id, ways_in.get(id, []), t, reaction))
		problems.append_array(_too_soon_on(id, t, reaction))
		for e in n.get("enemies", []):
			if not String(e.get("kind", "")) in ENEMY_KINDS:
				problems.append("node '%s': unknown enemy kind '%s'" % [id, e.get("kind")])
			if float(e.get("at", -1)) < 0.0 or float(e.get("at", -1)) > length:
				problems.append("node '%s': enemy at %s m is outside the segment" % [id, e.get("at")])
		# A room built into a side wall (the canteen's kitchen) needs a straight stretch of wall.
		var alcoves: Array = n.get("alcove", []) if n.get("alcove", []) is Array else [n["alcove"]]
		for al: Dictionary in alcoves:
			var a0 := float(al.get("at", -1))
			var a1 := a0 + float(al.get("length", 16.0))
			if a0 < MARKER_CLEAR_AFTER + ZONE_DOOR_AT or a1 > length - 2.0:
				problems.append("node '%s': the alcove at %s m must sit clear of the zone door and the end" % [id, al.get("at")])
			for bend in n.get("bends", []):
				var b := float(bend.get("at", 0))
				if a1 > b - 2.0 and a0 < b + BEND_RUN + 2.0:
					problems.append("node '%s': the alcove at %s m runs into the bend at %s m" % [id, al.get("at"), b])
		# An outdoor stretch (the dock's yard): its doors need straight wall, clear of the zone door.
		if n.has("outdoor"):
			var o0 := float(n["outdoor"].get("at", -1))
			var o1 := o0 + float(n["outdoor"].get("length", 40.0))
			if o0 < MARKER_CLEAR_AFTER + ZONE_DOOR_AT or o1 > length - 6.0:
				problems.append("node '%s': the outdoor stretch at %s m must sit clear of the zone door and the end" % [id, o0])
			for bend in n.get("bends", []):
				var b := float(bend.get("at", 0))
				for door in [o0, o1]:
					if door > b - 3.0 and door < b + BEND_RUN + 3.0:
						problems.append("node '%s': the outdoor stretch's door at %s m is on the bend at %s m" % [id, door, b])
			for ob in n.get("obstacles", []):
				if String(ob.get("kind", "")) == "tripwire" and float(ob.get("at", 0)) > o0 - 1.0 and float(ob.get("at", 0)) < o1 + 1.0:
					problems.append("node '%s': no tripwires in the outdoor stretch (nothing to mount them on)" % id)
		# Searchlights (user): only on the open roofs, not right outside a stairwell, 20 m apart.
		var lights: Array = n.get("searchlights", [])
		var entered_by_stairs := false
		var has_side_exit := false
		for edge in edges:
			if side_of(edge) != "straight":
				has_side_exit = true
		for from: StringName in _nodes:
			for edge in _nodes[from].get("next", []):
				if StringName(edge.get("to", "")) == id and via_of(edge) == "stairs":
					entered_by_stairs = true
		for i in lights.size():
			var s: Dictionary = lights[i]
			var s_at := float(s.get("at", -1))
			if String(n.get("tier", "ground")) != "roof":
				problems.append("node '%s': searchlights only on the roofs (open sky)" % id)
			if not String(s.get("side", "")) in ["left", "right"]:
				problems.append("node '%s': a searchlight needs \"side\": \"left\" or \"right\"" % id)
			if s_at <= 0.0 or s_at >= length:
				problems.append("node '%s': searchlight at %s m is outside the area" % [id, s.get("at")])
			if entered_by_stairs and s_at < STAIR_CLEAR_TO:
				problems.append("node '%s': searchlight at %s m is too close to the stairs' exit door (the door is %d m in: nothing before %d m)" % [id, s.get("at"), STAIRS_FLIGHT, STAIR_CLEAR_TO])
			if has_side_exit and s_at > length - SEARCHLIGHT_SPLIT_CLEAR:
				problems.append("node '%s': searchlight at %s m is too near the split (you'd have to choose between your exit and dodging it)" % [id, s.get("at")])
			for j in range(i + 1, lights.size()):
				if absf(float(lights[j].get("at", 0)) - s_at) < SEARCHLIGHT_GAP:
					problems.append("node '%s': searchlights at %s m and %s m are too close together" % [id, s.get("at"), lights[j].get("at")])
		# Snipers (user): roofs only, CAUTION and up, an open stretch to dodge in, away from the
		# searchlights, the stairs and the fork, and apart.
		var snipers: Array = n.get("snipers", [])
		for i in snipers.size():
			var s: Dictionary = snipers[i]
			var s_at := float(s.get("at", -1))
			var s_end := s_at + SNIPER_STRETCH
			if String(n.get("tier", "ground")) != "roof":
				problems.append("node '%s': snipers only on the roofs" % id)
			if not String(s.get("side", "")) in ["left", "right"]:
				problems.append("node '%s': a sniper needs \"side\": \"left\" or \"right\"" % id)
			if int(s.get("min_alert", 2)) < 2:
				problems.append("node '%s': snipers only at CAUTION and ALERT (min_alert 2 or 3)" % id)
			if s_at < 0.0 or s_end > length - SNIPER_END_CLEAR:
				problems.append("node '%s': sniper at %s m doesn't finish before the area's last %s m" % [id, s.get("at"), SNIPER_END_CLEAR])
			if entered_by_stairs and s_at < STAIR_CLEAR_TO:
				problems.append("node '%s': sniper at %s m is too close to the stairs' exit door (the door is %d m in: nothing before %d m)" % [id, s.get("at"), STAIRS_FLIGHT, STAIR_CLEAR_TO])
			for ob in n.get("obstacles", []):
				var ob_at := float(ob.get("at", 0))
				if ob_at >= s_at and ob_at <= s_end:
					problems.append("node '%s': sniper at %s m: obstacle at %s m in his stretch (a dodge must always be free)" % [id, s.get("at"), ob_at])
			for l in lights:
				var l_at := float(l.get("at", 0))
				if l_at > s_at - SNIPER_LIGHT_CLEAR and l_at < s_end + SNIPER_LIGHT_CLEAR:
					problems.append("node '%s': sniper at %s m is too near the searchlight at %s m (a dodge could step into its pool)" % [id, s.get("at"), l_at])
			for j in range(i + 1, snipers.size()):
				if absf(float(snipers[j].get("at", 0)) - s_at) < SNIPER_GAP:
					problems.append("node '%s': snipers at %s m and %s m are too close together" % [id, s.get("at"), snipers[j].get("at")])
		for a in n.get("alarms", []):
			if not String(a.get("side", "")) in ["left", "right"]:
				problems.append("node '%s': an alarm box needs \"side\": \"left\" or \"right\"" % id)
			if float(a.get("at", -1)) < 0.0 or float(a.get("at", -1)) > length:
				problems.append("node '%s': alarm box at %s m is outside the segment" % [id, a.get("at")])
		var sides_seen := {}
		for edge: Dictionary in edges:
			var to := StringName(edge.get("to", ""))
			if not _nodes.has(to):
				problems.append("node '%s' points to missing node '%s'" % [id, to])
				continue
			var side := side_of(edge)
			var via := via_of(edge)
			if not side in SIDES:
				problems.append("%s -> %s: unknown side '%s'" % [id, to, side])
			if side != "straight" and not via in VIAS:
				problems.append("%s -> %s: unknown via '%s'" % [id, to, via])
			# Two edges on one side are fine only if alert gates them apart; keep it simple and forbid it.
			if sides_seen.has(side):
				problems.append("node '%s' has two '%s' exits" % [id, side])
			sides_seen[side] = true
			var changes_tier := tier_of(to) != tier_of(id)
			if via == "corridor" and changes_tier:
				problems.append("%s -> %s: a corridor can't change height; use stairs" % [id, to])
			if side == "straight" and changes_tier:
				problems.append("%s -> %s: straight on can't change height" % [id, to])
			if via in ["stairs", "ladder"] and not changes_tier:
				problems.append("%s -> %s: %s must change height" % [id, to, via])
			# Tiers are stacked (underground, ground, roof): you can only climb or drop one at a time.
			if absi(tier_of(to) - tier_of(id)) > 1:
				problems.append("%s -> %s: stairs and ladders only move one level (tunnels - main level - rooftops)" % [id, to])
			if via == "stairs":
				var dest := node_data(to)
				for thing in dest.get("obstacles", []) + dest.get("enemies", []):
					if float(thing.get("at", 0)) < STAIR_CLEAR_TO:
						problems.append("%s -> %s: %s at %s m is too close to the stairs' exit door (the door is %d m in: nothing before %d m)" % [id, to, thing.get("kind"), thing.get("at"), STAIRS_FLIGHT, STAIR_CLEAR_TO])
			if via == "ladder" and String(node_data(to).get("end", "")) == "":
				problems.append("%s -> %s: ladders only lead to the end of the level" % [id, to])
			if side == "straight" and (edge.has("min_alert") or edge.has("max_alert")):
				problems.append("%s -> %s: straight on must always be open; gate a side exit instead" % [id, to])
		# Straight on is always open, so a last-minute lane change works. Only a dead end
		# (nothing but ladders) has no straight road.
		var needs_straight := false
		for edge: Dictionary in edges:
			if side_of(edge) != "straight" and via_of(edge) != "ladder":
				needs_straight = true
		if needs_straight and not sides_seen.has("straight"):
			problems.append("node '%s' has side exits but no straight road" % id)
	return problems


## The shortest distance on from the end of this node to the end of the mission (0 at the end),
## whatever the alert. For the HUD's progress rail.
func shortest_after(id: StringName) -> float:
	return _shortest_after(id, {})


func _shortest_after(id: StringName, seen: Dictionary) -> float:
	if end_type(id) != "" or seen.has(id):
		return 0.0
	seen[id] = true
	var best := INF
	for e in all_next(id):
		var to := StringName(e["to"])
		best = minf(best, length_of(to) + _shortest_after(to, seen.duplicate()))
	return 0.0 if best == INF else best


## The user's corner rule: no cover wall on the inside of a corner. corners: [{at, inside}].
static func _corner_walls(id: StringName, obstacles: Array, corners: Array) -> PackedStringArray:
	var problems := PackedStringArray()
	for c in corners:
		var inside: Array = INSIDE_LANES[c["inside"]]
		for ob in obstacles:
			if String(ob.get("kind", "")) != "wall":
				continue
			var gap := float(ob.get("at", 0)) - float(c["at"])
			if gap < -CORNER_CLEAR_BEFORE or gap > CORNER_CLEAR_AFTER:
				continue
			for lane in ob.get("lanes", []):
				if int(lane) in inside:
					problems.append("node '%s': wall at %s m is on the inside of the corner at %s m (it blocks the view round it)" % [id, ob.get("at"), c["at"]])
					break
	return problems


## Where a node's corners are: two per authored bend, and two at the start of a corridor
## turn-off into it.
func corners_of(id: StringName) -> Array:
	var out: Array = []
	var other := {"left": "right", "right": "left"}
	for bend in node_data(id).get("bends", []):
		var side := String(bend.get("side", "left"))
		if not side in other:
			continue
		out.append({"at": float(bend.get("at", 0)), "inside": side})
		out.append({"at": float(bend.get("at", 0)) + BEND_RUN, "inside": other[side]})
	for from: StringName in _nodes:
		for edge in _nodes[from].get("next", []):
			if StringName(edge.get("to", "")) == id and side_of(edge) in other and via_of(edge) == "corridor":
				out.append({"at": 0.0, "inside": side_of(edge)})
				out.append({"at": BEND_RUN, "inside": other[side_of(edge)]})
	return out


## Zone doors (user): a ground or underground area you can enter straight on from an area at the
## same height (not the helipad, not open roofs) starts with a double door. Arriving by stairs, you
## come in through the stairwell's own door instead, so the level skips it then.
func needs_zone_door(id: StringName) -> bool:
	var n := node_data(id)
	if String(n.get("tier", "ground")) == "roof" or String(n.get("end", "")) != "" or n.get("theme", "") in NO_TRIPWIRE_THEMES:
		return false
	for from: StringName in _nodes:
		for edge in _nodes[from].get("next", []):
			if StringName(edge.get("to", "")) == id and side_of(edge) == "straight" and tier_of(from) == tier_of(id):
				return true
	return false
