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
