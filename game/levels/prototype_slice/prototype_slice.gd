extends Node3D
## Walking skeleton for the first playable: auto-run, swipes, lanes, obstacles,
## alert-gated branching that physically splits the road, run log, extraction and capture.
## Placeholder boxes throughout.
## Not built yet: enemies, FIRE, cover, alarm boxes, chopper timer, route map screen.
##
## The rules work in route space (distance along the route + lane), exactly as before.
## Only drawing is 3D: each segment has its own frame (position, heading, height), so side
## exits can turn off and stairs and ladders can climb, and the player and camera follow.

const ROUTE_PATH := "res://game/levels/prototype_slice/route.json"
const START_ALERT := 1
const CEILING_Y := 4.6

## Obstacle kinds: size, height off the ground, look, and how to get past it.
## "tex" names a PsxTextures function; without one the obstacle is flat "color".
const KINDS := {
	"barrier": {"size": Vector3(0.9, 0.5, 0.3), "y": 0.25, "tex": "hazard", "pass": "jump"},
	"pipe": {"size": Vector3(0.9, 0.3, 0.3), "y": 1.3, "tex": "rust_pipe", "pass": "slide"},
	"truck": {"size": Vector3(0.95, 2.2, 3.0), "y": 1.1, "tex": "truck", "pass": "dodge"},
	"tripwire": {"size": Vector3(1.0, 0.05, 0.05), "y": 0.3, "color": Color("ff3030"), "pass": "jump_or_alert", "shadow": false},
}

## How each area looks, picked by "theme" in route.json. Placeholder art, so you can tell where you are.
const THEMES := {
	"compound": {"wall": "blocks", "color": Color("77776c"), "height": 3.0, "ground": "asphalt"},
	"motor_pool": {"wall": "corrugated", "color": Color("56613f"), "height": 3.5, "ground": "asphalt"},
	"rooftops": {"wall": "brick", "color": Color("7a4a38"), "height": 1.0, "ground": "concrete"},
	"tunnel": {"wall": "tile", "color": Color("4d5c52"), "height": 3.2, "ground": "asphalt", "ceiling": true},
	"gate": {"wall": "blocks", "color": Color("8a8470"), "height": 4.0, "ground": "asphalt"},
	"helipad": {"wall": "blocks", "color": Color("5c5c55"), "height": 0.6, "ground": "concrete"},
}
const DEAD_END_COLOR := Color("b03a2e")
const GUARD_COLOR := Color("4a5260")

@export var tuning: Tuning

## Retry skips the title card so the loop stays fast.
static var _skip_title := false

var _started := false
var _graph: RouteGraph
var _obstacles: Array[Dictionary] = []
## Segments along the path taken, in order. Each: {id, node, start, end, length, dy, ramp_len, edge}.
var _segments: Array[Dictionary] = []
## The segment whose fork is still ahead of the player (always the newest one).
var _fork_segment: Dictionary = {}

@onready var _player: Player = $Player
@onready var _camera: Camera3D = $Camera3D
@onready var _input: SwipeInput = $SwipeInput
@onready var _runner: RouteRunner = $RouteRunner
@onready var _hud: Hud = $Hud
@onready var _world: Node3D = $World


func _ready() -> void:
	Engine.time_scale = 1.0
	_graph = RouteGraph.from_json_file(ROUTE_PATH)
	for problem in _graph.validate():
		push_error("route.json: " + problem)

	_input.swiped.connect(_on_swipe)
	_input.tapped.connect(_on_tap)
	_input.fire_pressed.connect(_on_fire)
	_runner.segment_needed.connect(_spawn_segment)
	_runner.junction_approaching.connect(_on_junction_approaching)
	_runner.junction_cleared.connect(_on_junction_cleared)
	_runner.mission_end_reached.connect(_on_mission_end)
	_runner.dead_end_reached.connect(_end.bind(&"dead_end"))
	_runner.capture_reached.connect(_on_capture_reached)
	_runner.node_entered.connect(_on_node_entered)
	GameState.run_ended.connect(_on_run_ended)
	GameState.alert_changed.connect(_build_fork_cue.unbind(1))

	_spawn_segment(_graph.start_id, 0.0, {})
	_place_player()
	_update_camera(1.0)
	if _skip_title:
		start_run()
	else:
		_hud.show_title()


func start_run() -> void:
	if _started:
		return
	_started = true
	_hud.hide_title()
	GameState.start_run(START_ALERT)
	_runner.begin(_graph, false)


func _physics_process(delta: float) -> void:
	if GameState.run_active:
		_runner.update(_player.distance_run(), _player.lane)
		_check_obstacles()
		_despawn_behind()
	_place_player()
	_update_camera(delta)


# --- Route frames -------------------------------------------------------------------
# A segment's node sits where the segment starts, facing along it (-Z), at its starting height.
# Inside it, a point `into` metres along and `x` across is at local (x, height(into), -into).

## Height above the segment's start, `into` metres along it (stairs and ladders climb at the start).
static func _height(seg: Dictionary, into: float) -> float:
	if seg["ramp_len"] <= 0.0:
		return seg["dy"]
	return seg["dy"] * clampf(into / seg["ramp_len"], 0.0, 1.0)


func _local(seg: Dictionary, into: float, x: float, y: float = 0.0) -> Vector3:
	return Vector3(x, y + _height(seg, into), -into)


static func _turns(edge: Dictionary) -> bool:
	return RouteGraph.side_of(edge) != "straight" and RouteGraph.via_of(edge) != "ladder"


## For a side exit: the outer lane you leave the main road from, and the branch lane it becomes.
## The branch sits beside the main road, overlapping only that outer lane, so your outer lane
## becomes the branch lane nearest the main road (right exit: lane 4 -> branch lane 0).
func _handover_lanes(edge: Dictionary) -> Vector2i:
	var last := tuning.lane_count - 1
	return Vector2i(0, last) if RouteGraph.side_of(edge) == "left" else Vector2i(last, 0)


## Where a segment reached by `edge` from `prev` starts, and which way it faces.
## A side exit turns toward its side, pivoting on the outer lane so a player there doesn't jump.
func _frame_after(prev: Dictionary, edge: Dictionary) -> Transform3D:
	var t: Transform3D = prev["node"].transform
	var from_x := 0.0
	var to_x := 0.0
	var yaw := 0.0
	if _turns(edge):
		var lanes := _handover_lanes(edge)
		from_x = _player.lane_x(lanes.x)
		to_x = _player.lane_x(lanes.y)
		yaw = deg_to_rad(tuning.fork_turn_degrees) * (1.0 if RouteGraph.side_of(edge) == "left" else -1.0)
	var pivot := t * _local(prev, prev["length"], from_x)
	var basis := t.basis.rotated(Vector3.UP, yaw)
	return Transform3D(basis, pivot - basis * Vector3(to_x, 0, 0))


## Entering a side branch: move the player into the branch's own lanes (same spot in the world).
func _on_node_entered(_id: StringName) -> void:
	var seg: Dictionary = _segments.back()
	if seg["id"] != _runner.current or not _turns(seg["edge"]):
		return
	var lanes := _handover_lanes(seg["edge"])
	_player.shift_lanes(lanes.y - lanes.x)


## The shape of a segment: how far it climbs, over how long, and how it was reached.
func _segment_shape(id: StringName, edge: Dictionary, from_id: StringName) -> Dictionary:
	var dy := 0.0
	var ramp_len := 0.0
	if not edge.is_empty():
		dy = (_graph.tier_of(id) - _graph.tier_of(from_id)) * tuning.tier_height
		if dy != 0.0:
			ramp_len = tuning.ladder_length if RouteGraph.via_of(edge) == "ladder" else absf(dy) * tuning.stairs_run
	return {"id": id, "length": _graph.length_of(id), "dy": dy, "ramp_len": ramp_len, "edge": edge}


func _segment_at(distance: float) -> Dictionary:
	for i in range(_segments.size() - 1, -1, -1):
		if _segments[i]["start"] <= distance:
			return _segments[i]
	return _segments[0]


func _place_player() -> void:
	var seg := _segment_at(_player.distance_run())
	var t: Transform3D = seg["node"].global_transform
	var into: float = _player.distance_run() - seg["start"]
	_player.global_transform = Transform3D(t.basis, t * _local(seg, into, _player.track_x))


# --- World building -----------------------------------------------------------

func _spawn_segment(id: StringName, start: float, edge: Dictionary) -> void:
	var prev: Dictionary = _segments.back() if not _segments.is_empty() else {}
	var seg := _segment_shape(id, edge, prev.get("id", id))
	seg["start"] = start
	seg["end"] = start + seg["length"]
	var node := Node3D.new()
	node.name = String(id)
	_world.add_child(node)
	node.transform = Transform3D.IDENTITY if prev.is_empty() else _frame_after(prev, edge)
	seg["node"] = node

	# The branches you didn't take were only previews; the one you did take is now built for real.
	if not _fork_segment.is_empty():
		var previews: Node = _fork_segment["node"].get_node_or_null("ForkCue/Previews")
		if previews:
			previews.queue_free()

	var length: float = seg["length"]
	var road_end := length
	if _is_authored_fork(id):
		road_end = maxf(seg["ramp_len"], length - tuning.decision_lead - tuning.fork_cue_length)
	_build_surfaces(node, seg, road_end, 0.0, 0.0)

	var authored_lanes := 5
	for ob: Dictionary in _graph.node_data(id).get("obstacles", []):
		var kind: Dictionary = KINDS.get(ob["kind"], {})
		if kind.is_empty():
			push_warning("Unknown obstacle kind '%s' in %s" % [ob["kind"], id])
			continue
		var lanes := {}
		for l in ob.get("lanes", []):
			lanes[_remap_lane(int(l), authored_lanes)] = true
		var at_local := float(ob["at"])
		var size: Vector3 = kind["size"] * Vector3(tuning.lane_width, 1, 1)
		for lane: int in lanes:
			var x := _player.lane_x(lane)
			var mesh := _box(node, size, _local(seg, at_local, x, kind["y"]), kind.get("color", Color.WHITE))
			if kind.has("tex"):
				# BoxMesh lays its six faces out on a 3x2 grid, so this puts one tile on each face.
				mesh.material_override = PsxMaterials.textured(_obstacle_texture(kind["tex"]), Vector2(3, 2))
			_obstacles.append({"x": x, "at": start + at_local, "depth": size.z, "kind": ob["kind"], "pass": kind["pass"], "done": false, "mesh": mesh})
		if kind.get("shadow", true):
			_obstacle_shadows(node, seg, lanes.keys(), at_local, size)

	if not _has_straight(id) and _graph.end_type(id) == "":
		_build_dead_end(node, seg)
	if RouteGraph.via_of(edge) == "ladder":
		_build_ladder(node, seg, RouteGraph.side_of(edge))
	if _graph.end_type(id) == "extract":
		_spawn_chopper(node, _local(seg, length + 3.0, 0.0))

	_segments.append(seg)
	_fork_segment = seg
	_build_fork_cue()


func _is_authored_fork(id: StringName) -> bool:
	return _graph.end_type(id) == "" and RouteGraph.is_choice(_graph.all_next(id))


func _has_straight(id: StringName) -> bool:
	for edge in _graph.all_next(id):
		if RouteGraph.side_of(edge) == "straight":
			return true
	return false


## Road, kerbs, walls, pillars and ceiling for one segment (or a preview of one), in its own frame.
## The road stops at road_end (the fork cue paints the rest). open_left/open_right leave that many
## metres of wall out at the start, where a branch overlaps its neighbours.
func _build_surfaces(parent: Node3D, seg: Dictionary, road_end: float, open_left: float, open_right: float) -> void:
	var id: StringName = seg["id"]
	var length: float = seg["length"]
	var dy: float = seg["dy"]
	var ramp: float = seg["ramp_len"]
	var road_w := tuning.lane_count * tuning.lane_width
	var theme := _theme(id)
	var h: float = theme["height"]
	var wall_tex := PsxTextures.wall(theme["wall"], theme["color"])
	var via := RouteGraph.via_of(seg["edge"])

	# Stairs span the road. A ladder is a single lane, with a drop either side of it.
	if ramp > 0.0:
		if via == "ladder":
			var lane := 0 if RouteGraph.side_of(seg["edge"]) == "left" else tuning.lane_count - 1
			_ramp(parent, _player.lane_x(lane), tuning.lane_width, ramp, dy, PsxTextures.stairs(), 1.0)
		else:
			_ramp(parent, 0.0, road_w, ramp, dy, PsxTextures.stairs(), float(tuning.lane_count))
	var flat := road_end - ramp
	if flat > 0.0:
		_plane(parent, Vector2(road_w, flat), Vector3(0, dy, -(ramp + flat / 2.0)), _ground(id),
				Vector2(tuning.lane_count, flat / 4.0))

	for side in [-1, 1]:
		var open := open_left if side < 0 else open_right
		var wx: float = side * (road_w / 2.0 + 1.0)
		# Stairwell walls cover the whole climb. Ladders have none: you can see the drop.
		if ramp > 0.0 and via != "ladder" and open < ramp:
			_wall(parent, wx, side, maxf(open, 0.0), ramp, minf(0.0, dy), maxf(0.0, dy) + h, wall_tex)
		var z0 := maxf(ramp, open)
		if z0 < length:
			var kerb_len := length - z0
			_plane(parent, Vector2(1.0, kerb_len), Vector3(side * (road_w / 2.0 + 0.5), dy + 0.02, -(z0 + kerb_len / 2.0)),
					PsxTextures.concrete(), Vector2(1.0, kerb_len / 2.0))
			_wall(parent, wx, side, z0, length, dy, dy + h, wall_tex)
			# Pillars every 5 m, alternating light and dark, give a sense of speed.
			var ph := maxf(h, 1.2)
			for i in range(ceili(z0 / 5.0) * 5, int(length), 5):
				var c: Color = theme["color"].lightened(0.25) if (i / 5) % 2 == 0 else theme["color"].darkened(0.5)
				_box(parent, Vector3(0.35, ph, 0.35), Vector3(side * (road_w / 2.0 + 0.8), dy + ph / 2.0, -i), c)
	if theme.get("ceiling", false) and length > ramp:
		var roof := _plane(parent, Vector2(road_w + 2.0, length - ramp), Vector3(0, dy + CEILING_Y, -(ramp + length) / 2.0),
				wall_tex, Vector2(road_w / 2.0, (length - ramp) / 2.0))
		roof.rotation.x = PI  # face down


## A wall along one side, from z0 to z1 metres along and y0 to y1 high, facing the road.
func _wall(parent: Node3D, x: float, side: int, z0: float, z1: float, y0: float, y1: float, tex: Texture2D) -> void:
	var l := z1 - z0
	var wh := y1 - y0
	var wall := _plane(parent, Vector2(l, wh), Vector3(x, (y0 + y1) / 2.0, -(z0 + z1) / 2.0), tex,
			Vector2(l / 2.0, wh / 2.0), PlaneMesh.FACE_Z)
	wall.rotation.y = -side * PI / 2.0


## A sloped strip from the segment start, climbing dy over run metres.
func _ramp(parent: Node3D, x: float, width: float, run: float, dy: float, tex: Texture2D, tiles_x: float) -> void:
	var slope := sqrt(run * run + dy * dy)
	var r := _plane(parent, Vector2(width, slope), Vector3(x, dy / 2.0, -run / 2.0), tex, Vector2(tiles_x, slope / 2.0))
	r.rotation.x = atan2(dy, run)


## Where there is no way straight on: a wall across the middle lanes. Only the outer lanes (ladders) get out.
func _build_dead_end(parent: Node3D, seg: Dictionary) -> void:
	var length: float = seg["length"]
	var theme := _theme(seg["id"])
	var h: float = CEILING_Y if theme.get("ceiling", false) else maxf(theme["height"], 1.2)
	var w := (tuning.lane_count - 2) * tuning.lane_width
	var wall := _box(parent, Vector3(w, h, 0.4), _local(seg, length + 0.2, 0.0, h / 2.0), Color.WHITE)
	wall.material_override = PsxMaterials.textured(PsxTextures.wall(theme["wall"], theme["color"]), Vector2(3, 2))


## Rails and rungs up (or down) the ladder lane at the start of the segment the ladder leads to.
func _build_ladder(parent: Node3D, seg: Dictionary, side: String) -> void:
	var lane := 0 if side == "left" else tuning.lane_count - 1
	var x := _player.lane_x(lane)
	var ramp: float = seg["ramp_len"]
	var dy: float = seg["dy"]
	var metal := Color("8a8f96")
	for rail in [-1, 1]:
		for i in 6:
			var t0 := i / 6.0
			var t1 := (i + 1) / 6.0
			var p0 := Vector3(x + rail * 0.45, dy * t0 + 0.9, -ramp * t0)
			var p1 := Vector3(x + rail * 0.45, dy * t1 + 0.9, -ramp * t1)
			var post := _box(parent, Vector3(0.08, 0.08, p0.distance_to(p1)), Vector3.ZERO, metal)
			post.transform = Transform3D(Basis.looking_at(p1 - p0), (p0 + p1) / 2.0)
	for i in 8:
		var t := (i + 0.5) / 8.0
		_box(parent, Vector3(0.9, 0.06, 0.06), Vector3(x, dy * t + 0.9, -ramp * t), metal)


## Paints each lane in its exit's colour with arrows, puts a sign over the commit point, and shows
## the first stretch of each branch so you can see the road split. The exits on offer depend on
## alert, so this is rebuilt whenever alert changes.
func _build_fork_cue() -> void:
	if _fork_segment.is_empty():
		return
	var seg := _fork_segment
	var node: Node3D = seg["node"]
	var old := node.get_node_or_null("ForkCue")
	if old:
		node.remove_child(old)
		old.queue_free()
	var id: StringName = seg["id"]
	if not _is_authored_fork(id):
		return

	var cue := Node3D.new()
	cue.name = "ForkCue"
	node.add_child(cue)
	var length: float = seg["length"]
	var road_w := tuning.lane_count * tuning.lane_width
	var cue_start := maxf(seg["ramp_len"], length - tuning.decision_lead - tuning.fork_cue_length)
	var cue_len := length - cue_start
	var decision_at := length - tuning.decision_lead
	var y: float = seg["dy"]
	var opts := _graph.available_next(id, GameState.alert_level)
	var choice := RouteGraph.is_choice(opts)

	# Lanes. With only the straight road open, the road is just road again.
	for lane in tuning.lane_count:
		var tex := _ground(id)
		if choice:
			var edge := RouteGraph.pick_edge(lane, tuning.lane_count, opts)
			if not edge.is_empty():
				var side := RouteGraph.side_of(edge)
				tex = PsxTextures.fork_lane(Hud.side_dir(side), Hud.side_color(side))
		_plane(cue, Vector2(tuning.lane_width, cue_len), Vector3(_player.lane_x(lane), y, -(cue_start + cue_len / 2.0)),
				tex, Vector2(1, cue_len / 4.0))
	if not choice:
		return

	# Sign gantry over the commit point: one panel per exit, over the lanes that take it.
	# Panels sit above the camera (y 3.4) so it never flies through them, and under any ceiling.
	var post_h := CEILING_Y if _theme(id).get("ceiling", false) else 5.6
	var dz := -decision_at
	for s in [-1, 1]:
		_box(cue, Vector3(0.3, post_h, 0.3), Vector3(s * (road_w / 2.0 + 0.3), y + post_h / 2.0, dz), Color("2e2e2a"))
	_box(cue, Vector3(road_w + 0.9, 0.25, 0.25), Vector3(0, y + post_h - 0.2, dz), Color("2e2e2a"))
	for group in _lane_groups(opts):
		var x0 := _player.lane_x(group["from"]) - tuning.lane_width / 2.0
		var x1 := _player.lane_x(group["to"]) + tuning.lane_width / 2.0
		var edge: Dictionary = group["edge"]
		var color := DEAD_END_COLOR if edge.is_empty() else Hud.side_color(RouteGraph.side_of(edge))
		var text := "DEAD END" if edge.is_empty() else String(edge.get("label", edge["to"]))
		_box(cue, Vector3(x1 - x0 - 0.15, 0.8, 0.12), Vector3((x0 + x1) / 2.0, y + post_h - 0.6, dz), color.darkened(0.55))
		cue.add_child(_sign_label(text, color, x1 - x0 - 0.2, Vector3((x0 + x1) / 2.0, y + post_h - 0.6, dz + 0.08)))

	# Previews of each branch, so you can see where the road goes before you commit.
	var previews := Node3D.new()
	previews.name = "Previews"
	cue.add_child(previews)
	var sides := {}
	for edge in opts:
		sides[RouteGraph.side_of(edge)] = true
	# A side branch overlaps the main road's outer lane at the split. Until it has turned clear,
	# leave out the walls between them (the branch's inner wall, the main road's wall on that side).
	var angle := deg_to_rad(tuning.fork_turn_degrees)
	var half := road_w / 2.0 + 1.0  # centre to wall
	var inner_wall_x := absf(_player.lane_x(tuning.lane_count - 1)) - (half - absf(_player.lane_x(0)))
	var clear := tuning.fork_preview_length if angle <= 0.01 else (half - inner_wall_x) / sin(angle) + 1.0
	for edge in opts:
		var side := RouteGraph.side_of(edge)
		var shape := _segment_shape(StringName(edge["to"]), edge, id)
		shape["length"] = minf(shape["length"], tuning.fork_preview_length)
		var stub := Node3D.new()
		previews.add_child(stub)
		stub.transform = node.transform.affine_inverse() * _frame_after(seg, edge)
		var open_l := 0.0
		var open_r := 0.0
		if side == "straight":
			open_l = clear if sides.has("left") else 0.0
			open_r = clear if sides.has("right") else 0.0
		elif _turns(edge):
			open_l = clear if side == "right" else 0.0
			open_r = clear if side == "left" else 0.0
			stub.position.y -= 0.01  # where the branch overlaps the outer lane, the main road wins
		_build_surfaces(stub, shape, shape["length"], open_l, open_r)
		if RouteGraph.via_of(edge) == "ladder":
			_build_ladder(stub, shape, side)


## Runs of neighbouring lanes that take the same exit, left to right: [{from, to, edge}].
## edge is empty for lanes with no way on (the dead end between two ladders).
func _lane_groups(opts: Array[Dictionary]) -> Array[Dictionary]:
	var groups: Array[Dictionary] = []
	for lane in tuning.lane_count:
		var edge := RouteGraph.pick_edge(lane, tuning.lane_count, opts)
		if not groups.is_empty() and groups[-1]["edge"] == edge:
			groups[-1]["to"] = lane
		else:
			groups.append({"from": lane, "to": lane, "edge": edge})
	return groups


## A sign's text, shrunk to fit its panel.
func _sign_label(text: String, color: Color, width: float, pos: Vector3) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.modulate = color.lightened(0.3)
	label.outline_modulate = Color.BLACK
	label.font_size = 40
	label.outline_size = 8
	# About 0.6 font sizes per character across; never bigger than the default.
	label.pixel_size = minf(0.012, width / (text.length() * label.font_size * 0.62))
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	label.position = pos
	return label


func _theme(id: StringName) -> Dictionary:
	return THEMES.get(_graph.node_data(id).get("theme", ""), THEMES["compound"])


func _ground(id: StringName) -> Texture2D:
	return PsxTextures.asphalt() if _theme(id)["ground"] == "asphalt" else PsxTextures.concrete()


## A blob shadow directly under an obstacle, one per run of neighbouring lanes, because
## overlapping shadows multiply into dark seams. Under an overhead pipe the gap to its shadow says "duck".
func _obstacle_shadows(parent: Node3D, seg: Dictionary, lanes: Array, at: float, size: Vector3) -> void:
	lanes.sort()
	var runs: Array[Array] = []
	for lane: int in lanes:
		if runs.is_empty() or lane != runs[-1][-1] + 1:
			runs.append([lane])
		else:
			runs[-1].append(lane)
	for run in runs:
		var x0 := _player.lane_x(run[0]) - size.x / 2.0
		var x1 := _player.lane_x(run[-1]) + size.x / 2.0
		var s := MeshInstance3D.new()
		s.mesh = PsxMaterials.shadow_mesh(Vector2(x1 - x0, size.z) + Vector2.ONE * tuning.shadow_margin * 2.0)
		s.material_override = PsxMaterials.shadow(true, tuning)
		s.position = _local(seg, at, (x0 + x1) / 2.0, 0.03)
		parent.add_child(s)


func _obstacle_texture(name: String) -> Texture2D:
	match name:
		"hazard":
			return PsxTextures.hazard()
		"rust_pipe":
			return PsxTextures.rust_pipe()
		"truck":
			return PsxTextures.truck()
	push_warning("Unknown obstacle texture '%s'" % name)
	return PsxTextures.concrete()


func _spawn_chopper(parent: Node3D, pos: Vector3) -> void:
	var chopper := Node3D.new()
	chopper.name = "Chopper"
	parent.add_child(chopper)
	chopper.position = pos
	_box(chopper, Vector3(2.2, 1.6, 4.5), Vector3(0, 1.2, 0), Color("2f3b2a"))
	_box(chopper, Vector3(0.5, 0.5, 4.0), Vector3(0, 1.6, 4.0), Color("2f3b2a"))
	var rotor := _box(chopper, Vector3(9.0, 0.08, 0.35), Vector3(0, 2.2, 0), Color("111111"))
	var tween := rotor.create_tween().set_loops()
	tween.tween_property(rotor, "rotation:y", TAU, 0.35).from(0.0)


func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	m.mesh = mesh
	m.material_override = PsxMaterials.flat(color)
	m.position = pos
	parent.add_child(m)
	return m


## A flat, textured surface. It is subdivided about every 2 m, because affine (PS1) texturing
## warps badly across big triangles.
func _plane(parent: Node3D, size: Vector2, pos: Vector3, tex: Texture2D, uv_scale: Vector2,
		orientation: PlaneMesh.Orientation = PlaneMesh.FACE_Y) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.orientation = orientation
	mesh.size = size
	mesh.subdivide_width = maxi(0, ceili(size.x / 2.0) - 1)
	mesh.subdivide_depth = maxi(0, ceili(size.y / 2.0) - 1)
	m.mesh = mesh
	m.material_override = PsxMaterials.textured(tex, uv_scale)
	m.position = pos
	parent.add_child(m)
	return m


func _remap_lane(lane: int, authored: int) -> int:
	if tuning.lane_count == authored:
		return lane
	return clampi(roundi(lane * float(tuning.lane_count - 1) / (authored - 1)), 0, tuning.lane_count - 1)


func _despawn_behind() -> void:
	var d := _player.distance_run()
	while _segments.size() > 1 and _segments[0]["end"] < d - 15.0:
		_segments.pop_front()["node"].queue_free()
	_obstacles = _obstacles.filter(func(o: Dictionary) -> bool: return o["at"] > d - 10.0)


# --- Rules ------------------------------------------------------------------------

func _check_obstacles() -> void:
	var d := _player.distance_run()
	var half_hit := tuning.lane_width * 0.5 + 0.15
	for o in _obstacles:
		if o["done"] or absf(o["at"] - d) > o["depth"] / 2.0 + 0.2:
			continue
		if absf(o["x"] - _player.track_x) > half_hit:
			continue
		match o["pass"]:
			"jump":
				if _player.clears_low_obstacle():
					continue
			"slide":
				if _player.is_sliding():
					continue
			"jump_or_alert":
				if _player.clears_low_obstacle():
					continue
				o["done"] = true
				o["mesh"].visible = false
				RunLog.record_event("tripwire", {"node": _runner.current})
				GameState.raise_alert()
				continue
		o["done"] = true
		RunLog.record_event("hit", {"kind": o["kind"], "node": _runner.current})
		_end(&"killed")
		return


func _end(reason: StringName) -> void:
	GameState.end_run(reason, _runner.current)


func _on_mission_end(end_type: String) -> void:
	_end(GameState.END_EXTRACTED if end_type == "extract" else StringName(end_type))


## Missed the way out: stop, hands up, guards close in from behind, then CAPTURED.
func _on_capture_reached() -> void:
	Engine.time_scale = 1.0
	_hud.clear_junction()
	_player.surrender()
	_place_player()
	var n := tuning.capture_guards
	var behind := _player.global_transform
	for i in n:
		# Alternate sides, working outward, and keep clear of the middle so the camera can see.
		var side := -1.0 if i % 2 == 0 else 1.0
		var spot := Vector3(side * (1.3 + (i / 2) * 1.0), 0, 1.4 + (i / 2) * 0.9)
		var guard := _make_guard()
		_world.add_child(guard)
		# Face the player, and run in from further back.
		guard.global_transform = behind * Transform3D(Basis.IDENTITY, spot + Vector3(0, 0, 7.0))
		var tween := guard.create_tween()
		tween.tween_interval(0.12 * i)
		tween.tween_property(guard, "global_position", behind * spot, 0.5).set_ease(Tween.EASE_OUT)
	get_tree().create_timer(tuning.capture_duration).timeout.connect(_end.bind(GameState.END_CAPTURED))


func _make_guard() -> Node3D:
	var guard := Node3D.new()
	guard.name = "Guard"
	_box(guard, Vector3(0.55, 1.6, 0.35), Vector3(0, 0.8, 0), GUARD_COLOR)
	_box(guard, Vector3(0.4, 0.3, 0.4), Vector3(0, 1.75, 0), GUARD_COLOR.darkened(0.4))
	_box(guard, Vector3(0.1, 0.1, 0.8), Vector3(0.2, 1.1, -0.4), Color("1c1c1a"))  # rifle, aimed at the player
	var s := MeshInstance3D.new()
	s.mesh = PsxMaterials.shadow_mesh(Vector2(0.8, 0.6))
	s.material_override = PsxMaterials.shadow(false, tuning)
	s.position.y = 0.03
	guard.add_child(s)
	return guard


func _on_junction_approaching(options: Array[Dictionary]) -> void:
	Engine.time_scale = tuning.junction_time_scale
	_hud.show_junction(options)


func _on_junction_cleared() -> void:
	Engine.time_scale = 1.0
	_hud.clear_junction()


func _on_run_ended(reason: StringName) -> void:
	Engine.time_scale = 1.0
	_hud.show_end(reason, RunLog.route_summary())


func _on_swipe(dir: Vector2i) -> void:
	if not _started:
		start_run()
	elif GameState.run_active:
		_player.handle_swipe(dir)


func _on_tap(_pos: Vector2) -> void:
	if not _started:
		start_run()
	elif not GameState.run_active:
		_retry()
	# TODO(targeting): when enemies exist, tap-to-target raycasts from the camera here.


func _on_fire() -> void:
	if not _started:
		start_run()
	elif not GameState.run_active:
		_retry()


func _retry() -> void:
	_skip_title = true
	get_tree().reload_current_scene()


# --- Camera -----------------------------------------------------------------------

## Behind and above the player, in the frame of the segment they're on, eased so turns and
## climbs swing smoothly rather than snapping.
func _update_camera(delta: float) -> void:
	var seg := _segment_at(_player.distance_run())
	var t: Transform3D = seg["node"].global_transform
	var into: float = _player.distance_run() - seg["start"]
	var h := _height(seg, into)
	var x := _player.track_x
	var eye := t * Vector3(x * 0.6, h + 3.4, -into + 5.5)
	var look := t * Vector3(x * 0.8, h + 1.0, -into - 10.0)
	var target := Transform3D(Basis.IDENTITY, eye).looking_at(look, Vector3.UP)
	_camera.global_transform = _camera.global_transform.interpolate_with(target, clampf(delta * 8.0, 0.0, 1.0))
