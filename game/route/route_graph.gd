class_name RouteGraph
extends RefCounted
## An authored mission route stored as data: segments (nodes) joined by
## directed edges. Routes are authored, never procedural (LOCKED).
##
## JSON format (see game/levels/prototype_slice/route.json):
##   start: node id
##   nodes: [{ id, length, obstacles: [...], next: [{ to, label, min_alert, max_alert }], end }]
## An edge can be gated by alert level, so the routes on offer change with alert (LOCKED).

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


## The outgoing edges open at this alert level, in authored left-to-right order.
func available_next(id: StringName, alert_level: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for edge: Dictionary in node_data(id).get("next", []):
		if alert_level < int(edge.get("min_alert", 1)):
			continue
		if alert_level > int(edge.get("max_alert", 3)):
			continue
		out.append(edge)
	return out


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
		for edge: Dictionary in edges:
			if not _nodes.has(StringName(edge.get("to", ""))):
				problems.append("node '%s' points to missing node '%s'" % [id, edge.get("to", "")])
	return problems


## Maps the player's lane onto one of the open routes: the lanes are split
## evenly left to right. With 2 routes and 5 lanes, lanes 0-2 go left and 3-4 go right.
static func pick_by_lane(lane: int, lane_count: int, option_count: int) -> int:
	if option_count <= 1:
		return 0
	return clampi(floori(float(lane) * option_count / lane_count), 0, option_count - 1)
