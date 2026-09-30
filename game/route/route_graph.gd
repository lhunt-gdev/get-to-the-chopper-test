class_name RouteGraph
extends RefCounted
## An authored mission route stored as data: segments (nodes) joined by
## directed edges. Routes are authored, never procedural (LOCKED).
##
## JSON format (see game/levels/prototype_slice/route.json):
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
## objects in the same lane (user rule: nothing overlaps).
const DEPTHS := {"barrier": 0.3, "pipe": 0.3, "tripwire": 0.1, "box": 0.9, "wall": 1.0, "trooper": 0.5}
const MIN_GAP := 1.0
## Optional per-obstacle "look" (overrides the area's default look; gameplay is unchanged).
const LOOKS := {"pipe": ["pipe", "wires"], "box": ["crate", "desk", "cabinet"], "barrier": ["cabinet", "blockade"]}
## Themes whose slide obstacles are live wires (unless "look" says otherwise).
const WIRE_THEMES := ["office"]
## Live wires span only this many neighbouring lanes (user rule: never all 5).
const WIRE_LANES := [3, 4]
const VIAS := ["corridor", "stairs", "ladder"]
## Height tiers, in tier steps (Tuning.tier_height metres each).
const TIERS := {"roof": 1, "ground": 0, "underground": -1}

var start_id: StringName = &""
var _nodes: Dictionary = {}  # StringName -> Dictionary


static func from_json_file(path: String) -> RouteGraph:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("RouteGraph: cannot open %s (is *.json in the export include filter?)" % path)
		return null
	return from_dict(JSON.parse_string(f.get_as_text()))


static func from_dict(data: Dictionary) -> RouteGraph:
	var g := RouteGraph.new()
	g.start_id = StringName(data.get("start", ""))
	for n: Dictionary in data.get("nodes", []):
		g._nodes[StringName(n["id"])] = n
	return g


func has_node_id(id: StringName) -> bool:
	return _nodes.has(id)


func node_data(id: StringName) -> Dictionary:
	return _nodes.get(id, {})


func length_of(id: StringName) -> float:
	return float(node_data(id).get("length", 50.0))


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


## Objects that would overlap: two things sharing a lane closer than their depths plus MIN_GAP.
static func _overlaps(id: StringName, obstacles: Array, enemies: Array) -> PackedStringArray:
	var things: Array[Dictionary] = []
	for o in obstacles:
		things.append({"what": String(o.get("kind", "")), "at": float(o.get("at", 0)), "lanes": o.get("lanes", [])})
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


## Returns a list of problems. Empty means the graph is valid.
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if not _nodes.has(start_id):
		problems.append("start node '%s' does not exist" % start_id)
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
		problems.append_array(_forced_crossings(id, n.get("obstacles", [])))
		problems.append_array(_overlaps(id, n.get("obstacles", []), n.get("enemies", [])))
		for e in n.get("enemies", []):
			if String(e.get("kind", "")) != "rifle_trooper":
				problems.append("node '%s': unknown enemy kind '%s'" % [id, e.get("kind")])
			if float(e.get("at", -1)) < 0.0 or float(e.get("at", -1)) > length:
				problems.append("node '%s': enemy at %s m is outside the segment" % [id, e.get("at")])
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
