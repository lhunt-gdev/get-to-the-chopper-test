extends Node3D
## Walking skeleton for the first playable: auto-run, swipes, lanes, obstacles,
## alert-gated branching that physically splits the road, run log, extraction and capture.
## Placeholder boxes throughout.
## Not built yet: enemies, FIRE, cover, alarm boxes, chopper timer, route map screen.
##
## The rules work in route space (distance along the route + lane), exactly as before.
## Only drawing is 3D. Each segment has its own frame (where it starts, which way it faces) and
## is a chain of straight "legs": a side branch turns out, then runs parallel to the main road,
## and a route heading for the end angles back to the centre line. Stairs and ladders climb at
## the start. The player and camera follow all of it.
##
## Straight on stays open until the split, so every open branch ahead is built in full and the
## one you don't take is thrown away when you commit. Branches closed by alert get a lockdown door.

const ROUTE_PATH := "res://game/levels/prototype_slice/route.json"
const START_ALERT := 1
const CEILING_Y := 4.6

## Obstacle kinds: size, height off the ground, look, and how to get past it.
## "tex" names a PsxTextures function; without one the obstacle is flat "color".
const KINDS := {
	"barrier": {"size": Vector3(0.9, 0.5, 0.3), "y": 0.25, "tex": "hazard", "pass": "jump"},
	"pipe": {"size": Vector3(0.9, 0.3, 0.3), "y": 1.3, "tex": "rust_pipe", "pass": "slide"},
	"tripwire": {"size": Vector3(1.0, 0.05, 0.05), "y": 0.3, "color": Color("ff3030"), "pass": "jump_or_alert", "shadow": false},
	## Contextual cover (LOCKED): run into it and you take cover; swipe early to go round it.
	## Box cover: a metal or wood crate ("material" in route.json), one per lane. You crouch behind it.
	"box": {"size": Vector3(0.9, 1.2, 0.9), "y": 0.6, "tex": "crate_wood", "pass": "cover", "crouch": true},
	## Wall cover: floor to ceiling, one piece across 1-2 lanes. You stand behind it. It's solid:
	## what's behind it is a surprise, but never a trooper right behind it (route validation).
	"wall": {"size": Vector3(1.0, 4.0, 1.0), "y": 2.0, "tex": "cover_wall", "pass": "cover", "one_piece": true},
}

## How each area looks, picked by "theme" in route.json. Placeholder art, so you can tell where you are.
## Optional keys: "wall_tex" / "ceiling_tex" name a PsxTextures function (instead of a wall
## pattern); "skins" give this area its own look for obstacles, e.g. {"pipe": "duct"}; the
## gameplay (jump / slide / cover) never changes.
const THEMES := {
	"compound": {"wall": "blocks", "color": Color("77776c"), "height": 3.0, "ground": "asphalt"},
	# MGS PS1-style complex / office interior.
	"office": {"wall": "office", "wall_tex": "office_wall", "ceiling_tex": "office_ceiling", "color": Color("6f7a82"),
			"height": CEILING_Y, "ground": "office_floor", "ceiling": true, "wall_decor": true,
			"skins": {"barrier_looks": ["cabinet", "blockade"], "pipe": "wires", "box_metal": "cabinet", "box_wood": "desk",
					"wall": "office_wall"}},
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
## Segments along the path taken, in order. Each one:
##   {id, node, start, end, length, dy, ramp_len, edge, legs: [{start, xf}],
##    branches: {key: segment}, locked: {key: Node3D}}
var _segments: Array[Dictionary] = []
## The segment the player is on, whose split is still ahead.
var _current: Dictionary = {}
## Troopers and alarm boxes: {node: RifleTrooper|AlarmBox, owner: segment node, seg: segment}.
var _combatants: Array[Dictionary] = []
var _fire_held := false
var _fire_cooldown := 0.0
## HYBRID / TAP_TO_TARGET: the enemy the player last tapped.
var _tapped: Node3D = null
var _shot_tracer: MeshInstance3D
var _clock: ExtractionClock
## How far the camera follows the player across the road (0.6 normally, 1.0 beside a wall).
var _camera_follow := 0.6
## Obstacles can't trip you again until this game time (seconds into the run), after a stumble.
var _stumble_grace_until := -1.0

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
	_input.fire_released.connect(set_fire_held.bind(false))
	_hud.setup(tuning)
	_clock = ExtractionClock.new()
	_clock.name = "ExtractionClock"
	_clock.tuning = tuning
	add_child(_clock)
	_clock.stage_changed.connect(_on_chopper_stage)
	_shot_tracer = _box(self, Vector3(0.05, 0.05, 1.0), Vector3.ZERO, Color("fff0b0"))
	_shot_tracer.top_level = true
	_shot_tracer.visible = false
	_runner.segment_needed.connect(_on_segment_needed)
	_runner.junction_approaching.connect(_on_junction_approaching)
	_runner.junction_cleared.connect(_on_junction_cleared)
	_runner.mission_end_reached.connect(_on_mission_end)
	_runner.dead_end_reached.connect(_end.bind(&"dead_end"))
	_runner.capture_reached.connect(_on_capture_reached)
	_runner.node_entered.connect(_on_node_entered)
	GameState.run_ended.connect(_on_run_ended)
	GameState.alert_changed.connect(_on_alert_changed.unbind(1))

	_promote(_make_segment(_graph.start_id, 0.0, {}, Transform3D.IDENTITY))
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
	_clock.start()


func _physics_process(delta: float) -> void:
	if GameState.run_active:
		_runner.update(_player.distance_run(), _player.lane)
		_check_obstacles()
		_update_combat(delta)
		_despawn_behind()
	_place_player()
	_update_camera(delta)
	_hud.show_clock(_clock.fraction())


## The chopper's stages: a message under the clock, the helicopter lifting, and THE CHOPPER LEFT.
func _on_chopper_stage(stage: ExtractionClock.Stage) -> void:
	RunLog.record_event("chopper", {"stage": ExtractionClock.MESSAGES[stage]})
	match stage:
		ExtractionClock.Stage.INBOUND:
			_hud.show_chopper_message(ExtractionClock.MESSAGES[stage], Color("f0e8c8"), tuning.chopper_message_time, false)
		ExtractionClock.Stage.LANDED:
			_hud.show_chopper_message(ExtractionClock.MESSAGES[stage], Color("9fd36b"), tuning.chopper_message_time, false)
		ExtractionClock.Stage.LIFTING_OFF:
			_hud.show_chopper_message(ExtractionClock.MESSAGES[stage], Color("ff4b3a"), 0.0, true)
			for c in get_tree().get_nodes_in_group("chopper"):
				c.create_tween().tween_property(c, "position:y", c.position.y + 2.5,
						tuning.chopper_gone_at - tuning.chopper_lifts_at)
		ExtractionClock.Stage.GONE:
			for c in get_tree().get_nodes_in_group("chopper"):
				c.visible = false
			_end(GameState.END_CHOPPER_LEFT)


# --- Route frames -------------------------------------------------------------------
# A segment's node sits where the segment starts, facing along it (-Z). Its legs are straight
# pieces, each with a transform in the segment node's space. A point `into` metres along the
# segment and `x` across is at leg.xf * (x, y + height(into), -(into - leg.start)).

## Height above the segment's start, `into` metres along it (stairs and ladders climb at the start).
static func _height(seg: Dictionary, into: float) -> float:
	if seg["ramp_len"] <= 0.0:
		return seg["dy"]
	return seg["dy"] * clampf(into / seg["ramp_len"], 0.0, 1.0)


static func _leg_index(seg: Dictionary, into: float) -> int:
	var legs: Array = seg["legs"]
	for i in range(legs.size() - 1, -1, -1):
		if legs[i]["start"] <= into:
			return i
	return 0


## The frame on the centre line `into` metres along, in leg `i` (segment node space).
static func _frame_in_leg(seg: Dictionary, i: int, into: float) -> Transform3D:
	var leg: Dictionary = seg["legs"][i]
	var xf: Transform3D = leg["xf"]
	return Transform3D(xf.basis, xf * Vector3(0, _height(seg, into), -(into - leg["start"])))


static func _frame_at(seg: Dictionary, into: float) -> Transform3D:
	return _frame_in_leg(seg, _leg_index(seg, into), into)


static func _turns(edge: Dictionary) -> bool:
	return RouteGraph.side_of(edge) != "straight" and RouteGraph.via_of(edge) != "ladder"


static func _key(edge: Dictionary) -> String:
	return "%s:%s" % [RouteGraph.side_of(edge), edge.get("to", "")]


func _turn_angle() -> float:
	return deg_to_rad(tuning.fork_turn_degrees)


## For a side exit: the outer lane you leave the main road from, and the branch lane it becomes.
## The branch sits beside the main road, overlapping only that outer lane, so your outer lane
## becomes the branch lane nearest the main road (right exit: lane 4 -> branch lane 0).
func _handover_lanes(edge: Dictionary) -> Vector2i:
	var last := tuning.lane_count - 1
	return Vector2i(0, last) if RouteGraph.side_of(edge) == "left" else Vector2i(last, 0)


## Where a segment reached by `edge` from `prev` starts (world space), and which way it faces.
## A side exit turns toward its side, pivoting on the outer lane so a player there doesn't jump.
func _frame_after(prev: Dictionary, edge: Dictionary) -> Transform3D:
	var t: Transform3D = prev["node"].transform * _frame_in_leg(prev, prev["legs"].size() - 1, prev["length"])
	var from_x := 0.0
	var to_x := 0.0
	var yaw := 0.0
	if _turns(edge):
		var lanes := _handover_lanes(edge)
		from_x = _player.lane_x(lanes.x)
		to_x = _player.lane_x(lanes.y)
		yaw = _turn_angle() * (1.0 if RouteGraph.side_of(edge) == "left" else -1.0)
	var basis := t.basis.rotated(Vector3.UP, yaw)
	return Transform3D(basis, t * Vector3(from_x, 0, 0) - basis * Vector3(to_x, 0, 0))


## The legs of a segment starting at world transform `xf`: turn out, run parallel, head back to centre.
func _plan_legs(seg: Dictionary, xf: Transform3D) -> Array[Dictionary]:
	var length: float = seg["length"]
	var angle := _turn_angle()
	var legs: Array[Dictionary] = [{"start": 0.0, "xf": Transform3D.IDENTITY}]
	var at := 0.0
	var local := Transform3D.IDENTITY
	if _turns(seg["edge"]) and angle > 0.01:
		# Out at the turn angle, then straighten up parallel to the road you left.
		at = minf(tuning.branch_out_length, length * 0.5)
		var yaw := angle * (-1.0 if RouteGraph.side_of(seg["edge"]) == "left" else 1.0)
		local = Transform3D(local.basis.rotated(Vector3.UP, yaw), local * Vector3(0, 0, -at))
		legs.append({"start": at, "xf": local})
	# Authored bends: the same shape with no choice. Out to one side, then straight again.
	if angle > 0.01:
		for bend: Dictionary in _graph.node_data(seg["id"]).get("bends", []):
			var b := float(bend["at"])
			var out := tuning.branch_out_length
			if b < at or b + out > length:
				push_warning("%s: bend at %s m doesn't fit" % [seg["id"], b])
				continue
			var yaw := angle * (1.0 if String(bend.get("side", "left")) == "left" else -1.0)
			var turned := Transform3D(local.basis.rotated(Vector3.UP, yaw), local * Vector3(0, 0, -(b - at)))
			legs.append({"start": b, "xf": turned})
			local = Transform3D(local.basis, turned * Vector3(0, 0, -out))
			legs.append({"start": b + out, "xf": local})
			at = b + out
	if _heads_for_end(seg["id"]) and angle > 0.01:
		# Angle back to the centre line (world x = 0), then run straight into the end.
		var offset := (xf * local * Vector3(0, 0, -(length - at))).x
		var room := length - at - tuning.converge_tail - 2.0
		var run := minf(absf(offset) / sin(angle), room)
		if absf(offset) > 0.5 and run > 3.0:
			var bend_at := length - tuning.converge_tail - run
			var yaw := angle * signf(offset)  # positive yaw heads toward -x
			var p := local * Vector3(0, 0, -(bend_at - at))
			var bent := Transform3D(local.basis.rotated(Vector3.UP, yaw), p)
			legs.append({"start": bend_at, "xf": bent})
			var q := bent * Vector3(0, 0, -run)
			legs.append({"start": bend_at + run, "xf": Transform3D(local.basis, q)})
	return legs


## True if any exit from this node leads to the end of the level.
func _heads_for_end(id: StringName) -> bool:
	for edge in _graph.all_next(id):
		if _graph.end_type(StringName(edge["to"])) != "":
			return true
	return false


## The shape of a segment: how far it climbs, over how long, and how it was reached.
func _segment_shape(id: StringName, edge: Dictionary, from_id: StringName) -> Dictionary:
	var dy := 0.0
	var ramp_len := 0.0
	if not edge.is_empty():
		dy = (_graph.tier_of(id) - _graph.tier_of(from_id)) * tuning.tier_height
		if dy != 0.0:
			ramp_len = tuning.ladder_length if RouteGraph.via_of(edge) == "ladder" else absf(dy) * tuning.stairs_run
	return {"id": id, "length": _graph.length_of(id), "dy": dy, "ramp_len": ramp_len, "edge": edge,
			"branches": {}, "locked": {}}


func _segment_at(distance: float) -> Dictionary:
	for i in range(_segments.size() - 1, -1, -1):
		if _segments[i]["start"] <= distance:
			return _segments[i]
	return _segments[0]


func _place_player() -> void:
	var seg := _segment_at(_player.distance_run())
	var into: float = _player.distance_run() - seg["start"]
	var f: Transform3D = seg["node"].global_transform * _frame_at(seg, into)
	_player.global_transform = Transform3D(f.basis, f * Vector3(_player.track_x, 0, 0))


# --- Segments and branches ----------------------------------------------------------

## Builds a whole segment (road, walls, obstacles...) starting at world transform xf.
func _make_segment(id: StringName, start: float, edge: Dictionary, xf: Transform3D, from_id: StringName = &"") -> Dictionary:
	var seg := _segment_shape(id, edge, from_id if from_id != &"" else id)
	seg["start"] = start
	seg["end"] = start + seg["length"]
	seg["legs"] = _plan_legs(seg, xf)
	var node := Node3D.new()
	node.name = String(id)
	_world.add_child(node)
	node.transform = xf
	seg["node"] = node

	var length: float = seg["length"]
	var road_end := length
	if _is_authored_fork(id):
		road_end = maxf(seg["ramp_len"], length - tuning.decision_lead - tuning.fork_cue_length)
	_build_surfaces(node, seg, road_end, 0.0, 0.0)

	var authored_lanes := 5
	var jumps_seen := 0  # jump obstacles alternate through the area's looks
	for ob: Dictionary in _graph.node_data(id).get("obstacles", []):
		var kind: Dictionary = KINDS.get(ob["kind"], {})
		if kind.is_empty():
			push_warning("Unknown obstacle kind '%s' in %s" % [ob["kind"], id])
			continue
		var lanes := {}
		for l in ob.get("lanes", []):
			lanes[_remap_lane(int(l), authored_lanes)] = true
		var at := float(ob["at"])
		var size: Vector3 = kind["size"] * Vector3(tuning.lane_width, 1, 1)
		var y: float = kind["y"]
		# Each area has its own look for the same gameplay (THEMES "skins"); "look" in route.json
		# overrides it for one obstacle (e.g. the odd small pipe on the main floor).
		var tex_name: String = _skin(id, ob["kind"], kind.get("tex", ""))
		var jump_look := ""
		if ob["kind"] == "barrier":
			var looks: Array = _theme(id).get("skins", {}).get("barrier_looks", [])
			jump_look = ob.get("look", looks[jumps_seen % looks.size()] if not looks.is_empty() else "")
			jumps_seen += 1
			if jump_look == "cabinet":
				tex_name = "cabinet"
		if ob["kind"] == "box":
			var metal := String(ob.get("material", "wood")) == "metal"
			tex_name = _skin(id, "box_metal", "crate_metal") if metal else _skin(id, "box_wood", "crate_wood")
			if ob.has("look"):  # e.g. the odd wooden crate among the office furniture
				tex_name = {"crate": "crate_wood", "desk": "desk", "cabinet": "cabinet"}.get(ob["look"], tex_name)
		var span_look: String = ob.get("look", _skin(id, ob["kind"], ob["kind"]))
		if ob["kind"] == "wall":
			# Floor to ceiling: up to the ceiling indoors, a tall column outside.
			size.y = CEILING_Y if _theme(id).get("ceiling", false) else kind["size"].y
			y = size.y / 2.0
		var one_piece: Node3D = null
		if ob["kind"] in ["pipe", "tripwire"]:
			# Built per run of neighbouring lanes, anchored to a wall, the floor or the ceiling.
			one_piece = _build_spans(node, seg, span_look if ob["kind"] == "pipe" else "tripwire", lanes.keys(), at, y)
		elif kind.get("one_piece", false):
			var sorted: Array = lanes.keys()
			sorted.sort()
			var x0 := _player.lane_x(sorted[0]) - tuning.lane_width / 2.0 + 0.05
			var x1 := _player.lane_x(sorted[-1]) + tuning.lane_width / 2.0 - 0.05
			# A wall in an edge lane runs right into the side wall: no gap down the side (user rule).
			var side_wall := tuning.lane_count * tuning.lane_width / 2.0 + 1.0
			if sorted[0] == 0:
				x0 = -side_wall
			if sorted[-1] == tuning.lane_count - 1:
				x1 = side_wall
			var w := _item_box(node, seg, at, Vector3((x0 + x1) / 2.0, y, 0), Vector3(x1 - x0, size.y, size.z), Color.WHITE)
			w.material_override = PsxMaterials.textured(_obstacle_texture(tex_name), Vector2(3, 2))
			one_piece = w
		for lane: int in lanes:
			var x := _player.lane_x(lane)
			var mesh: Node3D = one_piece
			if jump_look == "cabinet":
				_scatter_papers(node, seg, at, x, lane)
			if jump_look == "blockade":
				mesh = _build_blockade(node, seg, at, x, lane)
			elif mesh == null:
				var m := _item_box(node, seg, at, Vector3(x, y, 0), size, kind.get("color", Color.WHITE))
				if tex_name != "":
					# BoxMesh lays its six faces out on a 3x2 grid, so this puts one tile on each face.
					m.material_override = PsxMaterials.textured(_obstacle_texture(tex_name), Vector2(3, 2))
				mesh = m
			# "group": every lane of one obstacle, so a tripwire trips once however you cross it.
			_obstacles.append({"x": x, "at": start + at, "depth": size.z, "kind": ob["kind"], "pass": kind["pass"],
					"crouch": kind.get("crouch", false), "done": false, "mesh": mesh, "owner": node, "group": ob})
		if kind.get("shadow", true):
			_obstacle_shadows(node, seg, lanes.keys(), at, size)

	# Troopers stand in a lane and face you. Alarm boxes are on a wall, facing the road.
	for e: Dictionary in _graph.node_data(id).get("enemies", []):
		if e.get("kind", "") != "rifle_trooper":
			push_warning("Unknown enemy kind '%s' in %s" % [e.get("kind"), id])
			continue
		var t := RifleTrooper.new(tuning)
		t.at = start + float(e["at"])
		t.x = _player.lane_x(_remap_lane(int(e.get("lane", 2)), authored_lanes))
		t.min_alert = int(e.get("min_alert", 1))
		t.max_alert = int(e.get("max_alert", 3))
		node.add_child(t)
		t.transform = _frame_at(seg, float(e["at"])) * Transform3D(Basis(Vector3.UP, PI), Vector3(t.x, 0, 0))
		t.knocked_down.connect(func() -> void: RunLog.record_event("trooper_down", {"node": id}))
		_combatants.append({"node": t, "owner": node, "seg": seg})
	for a: Dictionary in _graph.node_data(id).get("alarms", []):
		var box := AlarmBox.new()
		box.at = start + float(a["at"])
		var s := -1.0 if String(a.get("side", "left")) == "left" else 1.0
		node.add_child(box)
		box.transform = _frame_at(seg, float(a["at"])) * Transform3D(Basis(Vector3.UP, -s * PI / 2.0),
				Vector3(s * (tuning.lane_count * tuning.lane_width / 2.0 + 0.45), 1.8, 0))  # out on the kerb, in front of the pillars
		box.destroyed.connect(_on_alarm_destroyed.bind(id))
		_combatants.append({"node": box, "owner": node, "seg": seg})

	if not _has_straight(id) and _graph.end_type(id) == "":
		_build_dead_end(node, seg)
	if RouteGraph.via_of(edge) == "ladder":
		_build_ladder(node, seg, RouteGraph.side_of(edge))
	if _graph.end_type(id) == "extract":
		_spawn_chopper(node, _frame_at(seg, length) * Transform3D(Basis.IDENTITY, Vector3(0, 0, -3.0)))
	return seg


## The player is now on this segment: build every branch it can lead to, and its fork cue.
func _promote(seg: Dictionary) -> void:
	seg["promoted"] = true  # its troopers and alarm boxes come alive
	_segments.append(seg)
	_current = seg
	_build_branches()
	_build_fork_cue()


## Keeps the current segment's branches in step with alert: each open exit is built in full,
## each exit closed by alert gets a lockdown door. Doors slam if the branch was open a moment ago.
func _build_branches() -> void:
	if _current.is_empty():
		return
	var seg := _current
	var id: StringName = seg["id"]
	var branches: Dictionary = seg["branches"]
	var locked: Dictionary = seg["locked"]
	var open := {}
	for edge in _graph.available_next(id, GameState.alert_level):
		open[_key(edge)] = edge
	for edge in _graph.all_next(id):
		var key := _key(edge)
		if open.has(key):
			if locked.has(key):
				_open_door(locked[key])
				locked.erase(key)
			if not branches.has(key):
				branches[key] = _make_segment(StringName(edge["to"]), seg["end"], edge, _frame_after(seg, edge), id)
				_cut_openings(seg, branches[key])
		elif not locked.has(key):
			var slam := branches.has(key)
			if slam:
				_discard(branches[key])
				branches.erase(key)
			locked[key] = _build_locked_stub(seg, edge, slam)
	# The straight road opens up on each side that has a side exit, open or locked.
	for key in branches:
		_cut_openings(seg, branches[key])


## Throws away a branch that wasn't taken (and its obstacles).
func _discard(branch: Dictionary) -> void:
	var node: Node3D = branch["node"]
	_obstacles = _obstacles.filter(func(o: Dictionary) -> bool: return o["owner"] != node)
	_combatants = _combatants.filter(func(c: Dictionary) -> bool: return c["owner"] != node)
	node.queue_free()


func _on_segment_needed(id: StringName, _start: float, edge: Dictionary) -> void:
	var key := _key(edge)
	var branches: Dictionary = _current["branches"]
	var chosen: Dictionary = branches.get(key, {})
	if chosen.is_empty():  # shouldn't happen; build it now rather than fail
		chosen = _make_segment(id, _current["end"], edge, _frame_after(_current, edge), _current["id"])
	for k in branches:
		if k != key:
			_discard(branches[k])
	for k in _current["locked"]:
		_current["locked"][k].queue_free()
	branches.clear()
	_current["locked"].clear()
	# Now that there's only one way on, close up the walls you could see the other branches through.
	_rebuild_walls(chosen, 0.0, 0.0)
	_promote(chosen)


## Entering a side branch: move the player into the branch's own lanes (same spot in the world).
func _on_node_entered(_id: StringName) -> void:
	var seg: Dictionary = _segments.back()
	if seg["id"] != _runner.current or not _turns(seg["edge"]):
		return
	var lanes := _handover_lanes(seg["edge"])
	_player.shift_lanes(lanes.y - lanes.x)


func _on_alert_changed() -> void:
	_build_branches()
	_build_fork_cue()


func _is_authored_fork(id: StringName) -> bool:
	return _graph.end_type(id) == "" and RouteGraph.is_choice(_graph.all_next(id))


func _has_straight(id: StringName) -> bool:
	for edge in _graph.all_next(id):
		if RouteGraph.side_of(edge) == "straight":
			return true
	return false


## How far into a branch its walls must stay open where it overlaps the next road over.
func _overlap_clear() -> float:
	var angle := _turn_angle()
	var half := tuning.lane_count * tuning.lane_width / 2.0 + 1.0  # centre to wall
	var inner_wall_x := absf(_player.lane_x(tuning.lane_count - 1)) - (half - absf(_player.lane_x(0)))
	if angle <= 0.01:
		return tuning.branch_out_length
	return minf((half - inner_wall_x) / sin(angle) + 1.0, tuning.branch_out_length)


## Opens the walls between neighbouring branches of `seg`, where they overlap near the split.
func _cut_openings(seg: Dictionary, branch: Dictionary) -> void:
	var side := RouteGraph.side_of(branch["edge"])
	var clear := _overlap_clear()
	var sides := {}
	for edge in _graph.all_next(seg["id"]):
		if _turns(edge):
			sides[RouteGraph.side_of(edge)] = true
	var open_l := 0.0
	var open_r := 0.0
	if side == "straight":
		open_l = clear if sides.has("left") else 0.0
		open_r = clear if sides.has("right") else 0.0
	elif _turns(branch["edge"]):
		open_l = clear if side == "right" else 0.0
		open_r = clear if side == "left" else 0.0
	_rebuild_walls(branch, open_l, open_r)


func _rebuild_walls(seg: Dictionary, open_l: float, open_r: float) -> void:
	if seg.get("open", Vector2(-1, -1)) == Vector2(open_l, open_r):
		return
	seg["open"] = Vector2(open_l, open_r)
	var node: Node3D = seg["node"]
	var old := node.get_node_or_null("Walls")
	if old:
		node.remove_child(old)
		old.queue_free()
	var walls := Node3D.new()
	walls.name = "Walls"
	node.add_child(walls)
	_build_walls(walls, seg, open_l, open_r)


# --- World building -----------------------------------------------------------

## Road, stairs and ceiling for one segment. Walls go in their own node so openings can change.
## The road stops at road_end (the fork cue paints the rest).
func _build_surfaces(parent: Node3D, seg: Dictionary, road_end: float, open_l: float, open_r: float) -> void:
	var id: StringName = seg["id"]
	var length: float = seg["length"]
	var ramp: float = seg["ramp_len"]
	var road_w := tuning.lane_count * tuning.lane_width
	var theme := _theme(id)
	var via := RouteGraph.via_of(seg["edge"])

	for piece in _pieces(seg, 0.0, road_end):
		var on_ramp: bool = piece.y <= ramp + 0.001 and ramp > 0.0
		if on_ramp and via == "ladder":
			# A ladder is a single lane, with a drop either side of it.
			var lane := 0 if RouteGraph.side_of(seg["edge"]) == "left" else tuning.lane_count - 1
			_strip(parent, seg, piece.x, piece.y, _player.lane_x(lane), tuning.lane_width, 0.0, PsxTextures.stairs(), 1.0)
		elif on_ramp:
			_strip(parent, seg, piece.x, piece.y, 0.0, road_w, 0.0, PsxTextures.stairs(), float(tuning.lane_count))
		else:
			_strip(parent, seg, piece.x, piece.y, 0.0, road_w, 0.0, _ground(id), float(tuning.lane_count), _ground_tile(id))
	# Patches under each bend, so the outside corner has no gap.
	for i in range(1, seg["legs"].size()):
		var j: float = seg["legs"][i]["start"]
		if j >= ramp:
			var patch := _plane(parent, Vector2(road_w + 2.0, 4.0), Vector3.ZERO, _ground(id), Vector2(tuning.lane_count, 1.0))
			patch.transform = _frame_in_leg(seg, i - 1, j) * Transform3D(Basis.IDENTITY, Vector3(0, -0.02, 0))
	if theme.get("ceiling", false):
		for piece in _pieces(seg, ramp, length):
			var roof := _strip(parent, seg, piece.x, piece.y, 0.0, road_w + 2.0, CEILING_Y,
					_ceiling_texture(theme), road_w / 2.0, 2.0)
			roof.rotate_object_local(Vector3.FORWARD, PI)  # face down
	var walls := Node3D.new()
	walls.name = "Walls"
	parent.add_child(walls)
	seg["open"] = Vector2(open_l, open_r)
	_build_walls(walls, seg, open_l, open_r)


## Kerbs, walls and pillars either side, leaving the first open_l / open_r metres open.
func _build_walls(parent: Node3D, seg: Dictionary, open_l: float, open_r: float) -> void:
	var length: float = seg["length"]
	var ramp: float = seg["ramp_len"]
	var road_w := tuning.lane_count * tuning.lane_width
	var theme := _theme(seg["id"])
	var h: float = theme["height"]
	var wall_tex := _wall_texture(theme)
	var via := RouteGraph.via_of(seg["edge"])
	for side in [-1, 1]:
		var open := open_l if side < 0 else open_r
		var wx: float = side * (road_w / 2.0 + 1.0)
		for piece in _pieces(seg, open, length):
			var on_ramp: bool = piece.y <= ramp + 0.001 and ramp > 0.0
			if on_ramp and via == "ladder":
				continue  # no walls by a ladder: you can see the drop
			if not on_ramp:
				_strip(parent, seg, piece.x, piece.y, side * (road_w / 2.0 + 0.5), 1.0, 0.02, PsxTextures.concrete(), 1.0, 2.0)
			_wall(parent, seg, piece.x, piece.y, wx, side, h, wall_tex)
		# Pillars every 5 m, alternating light and dark, give a sense of speed. Big ones hide bend corners.
		var ph := maxf(h, 1.2)
		for i in range(ceili(maxf(open, ramp) / 5.0) * 5, int(length), 5):
			var c: Color = theme["color"].lightened(0.25) if (i / 5) % 2 == 0 else theme["color"].darkened(0.5)
			_item_box(parent, seg, i, Vector3(side * (road_w / 2.0 + 0.8), ph / 2.0, 0), Vector3(0.35, ph, 0.35), c)
		for k in range(1, seg["legs"].size()):
			var j: float = seg["legs"][k]["start"]
			if j >= maxf(open, ramp):
				_item_box(parent, seg, j, Vector3(side * (road_w / 2.0 + 1.0), ph / 2.0, 0), Vector3(1.0, ph, 1.0), theme["color"].darkened(0.5))
		if theme.get("wall_decor", false):
			_wall_decor(parent, seg, side, maxf(open, ramp), length)


## Office walls: now and then a door, a window or a notice board between the pillars.
func _wall_decor(parent: Node3D, seg: Dictionary, side: int, from: float, to: float) -> void:
	var face := side * (tuning.lane_count * tuning.lane_width / 2.0 + 1.0 - 0.03)
	for i in range(ceili(from / 5.0) * 5, int(to) - 3, 5):
		var at := i + 2.5
		var near_bend := false
		for leg in seg["legs"]:
			if absf(leg["start"] - at) < 1.3:
				near_bend = true
		if near_bend:
			continue
		# (width, height, centre height, texture); about half the gaps get something.
		var pick := absi(hash([seg["id"], i, side])) % 7
		var item: Array = []
		match pick:
			0, 1:
				item = [1.0, 2.1, 1.05, PsxTextures.door()]
			2, 3:
				item = [1.6, 0.9, 1.65, PsxTextures.office_window()]
			4:
				item = [1.1, 0.75, 1.5, PsxTextures.notice_board()]
		if item.is_empty():
			continue
		var m := _item_box(parent, seg, at, Vector3(face, item[2], 0), Vector3(0.05, item[1], item[0]), Color.WHITE)
		m.material_override = PsxMaterials.textured(item[3], Vector2(3, 2))


## Splits [a, b] where legs bend and where stairs end, so each piece is one straight slope.
static func _pieces(seg: Dictionary, a: float, b: float) -> Array[Vector2]:
	var cuts: Array[float] = [a, b]
	for leg in seg["legs"]:
		if leg["start"] > a and leg["start"] < b:
			cuts.append(leg["start"])
	if seg["ramp_len"] > a and seg["ramp_len"] < b:
		cuts.append(seg["ramp_len"])
	cuts.sort()
	var out: Array[Vector2] = []
	for i in cuts.size() - 1:
		if cuts[i + 1] - cuts[i] > 0.01:
			out.append(Vector2(cuts[i], cuts[i + 1]))
	return out


## A flat strip lying along one piece of a segment, `x` across and `y` up, following any slope.
func _strip(parent: Node3D, seg: Dictionary, a: float, b: float, x: float, width: float, y: float,
		tex: Texture2D, tiles_x: float, tile_len: float = 4.0) -> MeshInstance3D:
	var i := _leg_index(seg, (a + b) / 2.0)
	var pa := _frame_in_leg(seg, i, a) * Vector3(x, y, 0)
	var pb := _frame_in_leg(seg, i, b) * Vector3(x, y, 0)
	var l := pa.distance_to(pb)
	var back := (pa - pb) / l
	var right: Vector3 = seg["legs"][i]["xf"].basis.x
	var m := _plane(parent, Vector2(width, l), Vector3.ZERO, tex, Vector2(tiles_x, l / tile_len))
	m.transform = Transform3D(Basis(right, back.cross(right), back), (pa + pb) / 2.0)
	return m


## A wall along one piece of a segment, facing the road, covering any climb.
func _wall(parent: Node3D, seg: Dictionary, a: float, b: float, x: float, side: int, h: float, tex: Texture2D) -> void:
	var i := _leg_index(seg, (a + b) / 2.0)
	var leg: Dictionary = seg["legs"][i]
	var ha := _height(seg, a)
	var hb := _height(seg, b)
	var y0 := minf(ha, hb)
	var y1 := maxf(ha, hb) + h
	var l := b - a
	var xf: Transform3D = leg["xf"]
	var m := _plane(parent, Vector2(l, y1 - y0), Vector3.ZERO, tex, Vector2(l / 2.0, (y1 - y0) / 2.0), PlaneMesh.FACE_Z)
	m.transform = Transform3D(xf.basis * Basis(Vector3.UP, -side * PI / 2.0),
			xf * Vector3(x, (y0 + y1) / 2.0, -((a + b) / 2.0 - leg["start"])))


## A box at a point on a segment (`local` is across, up and forward from the centre line there).
func _item_box(parent: Node3D, seg: Dictionary, into: float, local: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var m := _box(parent, size, Vector3.ZERO, color)
	m.transform = _frame_at(seg, into) * Transform3D(Basis.IDENTITY, local)
	return m


## Pipes and tripwires, one piece per run of neighbouring lanes, never left floating:
## - a run that reaches the road edge carries on into the side wall (a mounting plate for a pipe,
##   an emitter box for a tripwire);
## - a run that stops mid-road ends on the floor (a pipe bends down to a foot, a tripwire ends on
##   an emitter post).
## Pipes get a nut where each lane's pipe joins the next. Returns the node to hide when tripped.
func _build_spans(parent: Node3D, seg: Dictionary, kind: String, lanes: Array, at: float, y: float) -> Node3D:
	lanes.sort()
	var runs: Array[Array] = []
	for lane: int in lanes:
		if runs.is_empty() or lane != runs[-1][-1] + 1:
			runs.append([lane])
		else:
			runs[-1].append(lane)
	var road_w := tuning.lane_count * tuning.lane_width
	var wall_x := road_w / 2.0 + 1.0
	var last := tuning.lane_count - 1
	var beam: MeshInstance3D = null
	var holder := Node3D.new()  # tripwire beams go in one node, so they hide together
	parent.add_child(holder)
	var metal := Color("4a4e54")
	for run in runs:
		var ends := [
			{"x": -wall_x if run[0] == 0 else _player.lane_x(run[0]) - tuning.lane_width / 2.0 + 0.2, "wall": run[0] == 0},
			{"x": wall_x if run[-1] == last else _player.lane_x(run[-1]) + tuning.lane_width / 2.0 - 0.2, "wall": run[-1] == last},
		]
		var x0: float = ends[0]["x"]
		var x1: float = ends[1]["x"]
		if kind == "pipe":
			var p := _item_box(parent, seg, at, Vector3((x0 + x1) / 2.0, y, 0), Vector3(x1 - x0, 0.3, 0.3), Color.WHITE)
			p.material_override = PsxMaterials.textured(PsxTextures.rust_pipe(), Vector2(3, 2))
			beam = p
			for k in range(1, run.size()):  # nuts where one lane's pipe joins the next
				_item_box(parent, seg, at, Vector3(_player.lane_x(run[k]) - tuning.lane_width / 2.0, y, 0), Vector3(0.14, 0.44, 0.44), metal)
			for e in ends:
				var ex: float = e["x"]
				if e["wall"]:
					_item_box(parent, seg, at, Vector3(ex, y, 0), Vector3(0.1, 0.62, 0.62), metal)  # wall plate
				else:
					_item_box(parent, seg, at, Vector3(ex, y, 0), Vector3(0.38, 0.38, 0.38), metal)  # elbow
					var down := _item_box(parent, seg, at, Vector3(ex, y / 2.0, 0), Vector3(0.3, y, 0.3), Color.WHITE)
					down.material_override = PsxMaterials.textured(PsxTextures.rust_pipe(), Vector2(3, 2))
					_item_box(parent, seg, at, Vector3(ex, 0.04, 0), Vector3(0.55, 0.08, 0.55), metal)  # foot
		elif kind == "wires":
			beam = _build_wires(parent, seg, at, y, ends)
		else:
			# Thick enough to stay at least a pixel tall at the low internal resolution, far off.
			var b := _item_box(holder, seg, at, Vector3((x0 + x1) / 2.0, y, 0), Vector3(x1 - x0, 0.1, 0.06), Color("ff3030"))
			beam = b
			for e in ends:
				var ex: float = e["x"]
				if e["wall"]:
					ex -= signf(ex) * 0.2  # stands just proud of the wall, so it reads against it
				else:
					_item_box(parent, seg, at, Vector3(ex, y / 2.0, 0), Vector3(0.12, y, 0.12), metal)  # emitter post
				# A light housing with a bright red lens facing along the beam.
				var em := _item_box(parent, seg, at, Vector3(ex, y, 0), Vector3(0.4, 0.34, 0.34), Color("a8acb2"))
				_box(em, Vector3(0.44, 0.14, 0.14), Vector3.ZERO, Color("ff2a2a"))
	# Hiding the holder hides every beam of a tripwire at once.
	return holder if kind == "tripwire" else beam


## Live electrical wires hanging low across a run of lanes (the main floor's slide obstacle):
## three cables in one smooth drape. Over the blocked lanes they sag low (you have to slide). At a
## wall they end in a junction box; where they stop mid-road they curve up to a hook in the ceiling
## just beyond the end, well above head height by the next lane. A cut wire dangles with a bend in
## it, and sparks where they're broken.
func _build_wires(parent: Node3D, seg: Dictionary, at: float, y: float, ends: Array) -> Node3D:
	var frame := _frame_at(seg, at)
	var top := y + 0.2   # height at the edge of the blocked lanes
	var low := y - 0.08  # lowest point, mid-run (still too low to run under)
	var reach := 1.3     # how far past a mid-road end the ceiling hook is
	# Edges of the blocked lanes (a wall end is the wall itself) and where each end is anchored.
	var e0: float = ends[0]["x"] if ends[0]["wall"] else ends[0]["x"] - 0.2
	var e1: float = ends[1]["x"] if ends[1]["wall"] else ends[1]["x"] + 0.2
	var a0 := e0 if ends[0]["wall"] else e0 - reach
	var a1 := e1 if ends[1]["wall"] else e1 + reach
	var mid := (e0 + e1) / 2.0
	var half := (e1 - e0) / 2.0
	var slope := 2.0 * (top - low) / half  # steepness at the lane edge, carried on into the rise
	var black := Color("141414")
	var first: MeshInstance3D = null
	var steps := maxi(8, ceili((a1 - a0) / 0.3))
	for c in 3:
		var dz: float = [-0.1, 0.0, 0.1][c]
		var dy: float = [0.0, 0.06, -0.05][c]
		var prev := Vector3.ZERO
		for i in steps + 1:
			var x := lerpf(a0, a1, float(i) / steps)
			var h := _wire_height(x, e0, e1, mid, half, top, low, slope, reach)
			var p := Vector3(x, h + dy * clampf((CEILING_Y - h) / 1.0, 0.0, 1.0), dz)
			if i > 0:
				var piece := _cable(parent, frame, prev, p, 0.04, black if c != 1 else Color("5a3a12"))
				if first == null:
					first = piece
			prev = p
	for e in ends:
		var ex: float = e["x"]
		if e["wall"]:
			var jb := _box(parent, Vector3(0.24, 0.42, 0.42), Vector3.ZERO, Color("5a5f66"))  # junction box
			jb.transform = frame * Transform3D(Basis.IDENTITY, Vector3(ex - signf(ex) * 0.1, top, 0))
			var stripe := _box(jb, Vector3(0.26, 0.08, 0.44), Vector3.ZERO, Color("c9a227"))
			stripe.position.y = 0.12
		else:
			var hook := a0 if ex < mid else a1
			_box(parent, Vector3(0.18, 0.12, 0.3), Vector3.ZERO, Color("5a5f66")).transform = \
					frame * Transform3D(Basis.IDENTITY, Vector3(hook, CEILING_Y - 0.06, 0))  # ceiling hook
	# A cut wire dangling from the ceiling with a lazy bend in it, sparking at its end.
	var cut_x := lerpf(e0, e1, 0.3)
	var tip := Vector3(cut_x + 0.18, top - 0.1, 0.25)
	var prev_cut := Vector3(cut_x, CEILING_Y, 0.25)
	for i in range(1, 7):
		var t := i / 6.0
		var p := Vector3(cut_x + 0.18 * t * t + 0.12 * sin(t * PI), lerpf(CEILING_Y, tip.y, t), 0.25)
		_cable(parent, frame, prev_cut, p, 0.04, black)
		prev_cut = p
	tip = prev_cut
	for spot in [tip, Vector3(lerpf(e0, e1, 0.65), low + 0.02, 0.0)]:
		var s := Sparks.new(4, hash(Vector2(at, spot.x)))
		parent.add_child(s)
		s.transform = frame * Transform3D(Basis.IDENTITY, spot)
	return first


## The wires' drape: a parabola over the blocked lanes (lowest mid-run, `top` at their edges);
## past a mid-road end it keeps curving up at the same steepness to the ceiling hook.
static func _wire_height(x: float, e0: float, e1: float, mid: float, half: float, top: float, low: float,
		slope: float, reach: float) -> float:
	if x >= e0 and x <= e1:
		var u := (x - mid) / half
		return low + (top - low) * u * u
	var s := (e0 - x) if x < e0 else (x - e1)  # metres past the edge, toward the hook
	var a := (CEILING_Y - top - slope * reach) / (reach * reach)
	return minf(CEILING_Y, top + slope * s + a * s * s)


## A thin straight cable between two points given in `frame` (a place on the route).
func _cable(parent: Node3D, frame: Transform3D, a: Vector3, b: Vector3, thick: float, color: Color) -> MeshInstance3D:
	var m := _box(parent, Vector3(thick, thick, maxf(a.distance_to(b), 0.01)), Vector3.ZERO, color)
	var pa := frame * a
	var pb := frame * b
	var up := Vector3.UP if absf((pb - pa).normalized().y) < 0.99 else Vector3.RIGHT
	m.transform = Transform3D(Basis.looking_at(pb - pa, up), (pa + pb) / 2.0)
	return m


## Loose sheets of paper around a low filing cabinet, as if it was tipped over or shoved aside
## in a hurry: mostly on the floor in front of and behind it, a couple on top.
func _scatter_papers(parent: Node3D, seg: Dictionary, at: float, x: float, lane: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seg["id"], at, lane])
	var frame := _frame_at(seg, at)
	for i in 9:
		var on_top := i < 2
		var p := Vector3(x + rng.randf_range(-0.6, 0.6), 0.51 if on_top else 0.012,
				rng.randf_range(-0.25, 0.25) if on_top else rng.randf_range(-1.8, 1.4))
		if not on_top and absf(p.z) < 0.25:
			p.z = 0.35 * signf(p.z + 0.001)  # not inside the cabinet
		var sheet := _box(parent, Vector3(0.21, 0.006, 0.29), Vector3.ZERO, Color("e6e2d6") if i % 4 else Color("d8d2b8"))
		sheet.transform = frame * Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)), p)


## A makeshift blockade across one lane: a door on its side, with a chair tipped over behind it.
## Still exactly a jump obstacle; just a different look (main floor).
func _build_blockade(parent: Node3D, seg: Dictionary, at: float, x: float, lane: int) -> Node3D:
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.transform = _frame_at(seg, at) * Transform3D(Basis.IDENTITY, Vector3(x, 0, 0))
	var tilt := 0.07 if lane % 2 == 0 else -0.06
	var door := _box(holder, Vector3(tuning.lane_width * 0.94, 0.5, 0.07), Vector3(0, 0.25, 0), Color.WHITE)
	door.material_override = PsxMaterials.textured(PsxTextures.door(), Vector2(3, 2))
	door.rotation.z = tilt
	# The chair, on its side: seat standing up, back lying flat, legs sticking out.
	var chair := Node3D.new()
	holder.add_child(chair)
	chair.position = Vector3(0.25 if lane % 2 == 0 else -0.25, 0, -0.35)
	chair.rotation.y = 0.5 if lane % 2 == 0 else -0.4
	var plastic := Color("3e4c5c")
	_box(chair, Vector3(0.44, 0.44, 0.05), Vector3(0, 0.22, 0), plastic)       # seat
	_box(chair, Vector3(0.44, 0.05, 0.42), Vector3(0, 0.03, -0.2), plastic)    # back, flat on the floor
	for lx in [-0.19, 0.19]:
		_box(chair, Vector3(0.03, 0.03, 0.4), Vector3(lx, 0.4, 0.2), Color("8a8f96"))  # legs
	return holder


## Where there is no way straight on: a wall across the middle lanes. Only the outer lanes (ladders) get out.
func _build_dead_end(parent: Node3D, seg: Dictionary) -> void:
	var length: float = seg["length"]
	var theme := _theme(seg["id"])
	var h: float = CEILING_Y if theme.get("ceiling", false) else maxf(theme["height"], 1.2)
	var w := (tuning.lane_count - 2) * tuning.lane_width
	var wall := _item_box(parent, seg, length, Vector3(0, h / 2.0, -0.2), Vector3(w, h, 0.4), Color.WHITE)
	wall.material_override = PsxMaterials.textured(_wall_texture(theme), Vector2(3, 2))


## Rails and rungs up (or down) the ladder lane at the start of the segment the ladder leads to.
func _build_ladder(parent: Node3D, seg: Dictionary, side: String) -> void:
	var lane := 0 if side == "left" else tuning.lane_count - 1
	var x := _player.lane_x(lane)
	var ramp: float = seg["ramp_len"]
	var metal := Color("8a8f96")
	var f0 := _frame_in_leg(seg, 0, 0.0)
	var f1 := _frame_in_leg(seg, 0, ramp)
	for rail in [-1, 1]:
		var p0 := f0 * Vector3(x + rail * 0.45, 0.9, 0)
		var p1 := f1 * Vector3(x + rail * 0.45, 0.9, 0)
		var post := _box(parent, Vector3(0.08, 0.08, p0.distance_to(p1)), Vector3.ZERO, metal)
		post.transform = Transform3D(Basis.looking_at(p1 - p0), (p0 + p1) / 2.0)
	for i in 8:
		var t := (i + 0.5) / 8.0
		_item_box(parent, seg, ramp * t, Vector3(x, 0.9, 0), Vector3(0.9, 0.06, 0.06), metal)


## The first few metres of a branch closed by alert, behind a lockdown shutter.
func _build_locked_stub(seg: Dictionary, edge: Dictionary, slam: bool) -> Node3D:
	var stub := _segment_shape(StringName(edge["to"]), edge, seg["id"])
	var xf := _frame_after(seg, edge)
	stub["legs"] = _plan_legs(stub, xf)  # planned at full length, so it bends where the real one would
	stub["length"] = minf(stub["length"], tuning.locked_stub_length)
	var node := Node3D.new()
	node.name = "Locked_" + String(edge["to"])
	_world.add_child(node)
	node.transform = xf
	stub["node"] = node
	var side := RouteGraph.side_of(edge)
	var clear := _overlap_clear()
	_build_surfaces(node, stub, stub["length"], clear if side == "right" else 0.0, clear if side == "left" else 0.0)

	var road_w := tuning.lane_count * tuning.lane_width
	var h := maxf(_theme(stub["id"])["height"], 3.0)
	var door := Node3D.new()
	door.name = "LockdownDoor"
	node.add_child(door)
	var f := _frame_at(stub, 1.5)
	door.transform = f
	var panel := _box(door, Vector3(road_w + 2.2, h, 0.3), Vector3(0, h / 2.0, 0), Color.WHITE)
	panel.material_override = PsxMaterials.textured(PsxTextures.wall("corrugated", Color("5a5f66")), Vector2(3, 2))
	var band := _box(door, Vector3(road_w + 2.25, 0.5, 0.34), Vector3(0, 0.25, 0), Color.WHITE)
	band.material_override = PsxMaterials.textured(PsxTextures.hazard(), Vector2(6, 2))
	door.add_child(_sign_label("LOCKDOWN", DEAD_END_COLOR, road_w * 0.8, Vector3(0, h * 0.6, 0.2)))
	door.set_meta("closed_y", door.position.y)
	door.set_meta("open_y", door.position.y + h + 0.3)
	if slam:
		door.position.y = door.get_meta("open_y")
		door.create_tween().tween_property(door, "position:y", door.get_meta("closed_y"), tuning.lockdown_close_time) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	return node


## Alert fell and a locked branch reopened: lift its door, then drop the stub (the full branch replaces it).
func _open_door(stub: Node3D) -> void:
	var door := stub.get_node_or_null("LockdownDoor")
	if door == null:
		stub.queue_free()
		return
	var tween := door.create_tween()
	tween.tween_property(door, "position:y", door.get_meta("open_y"), tuning.lockdown_close_time)
	tween.tween_callback(stub.queue_free)


## Paints each lane in its exit's colour with arrows and puts a sign over the split.
## The exits on offer depend on alert, so this is rebuilt whenever alert changes.
func _build_fork_cue() -> void:
	if _current.is_empty():
		return
	var seg := _current
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
		for piece in _pieces(seg, cue_start, length):
			_strip(cue, seg, piece.x, piece.y, _player.lane_x(lane), tuning.lane_width, 0.0, tex, 1.0,
					_ground_tile(id) if tex == _ground(id) else 4.0)
	if not choice:
		return

	# Sign gantry at the split: one panel per exit, over the lanes that take it.
	# Panels sit above the camera (y 3.4) so it never flies through them, and under any ceiling.
	var post_h := CEILING_Y if _theme(id).get("ceiling", false) else 5.6
	var at := length - tuning.decision_lead
	for s in [-1, 1]:
		_item_box(cue, seg, at, Vector3(s * (road_w / 2.0 + 0.3), post_h / 2.0, 0), Vector3(0.3, post_h, 0.3), Color("2e2e2a"))
	_item_box(cue, seg, at, Vector3(0, post_h - 0.2, 0), Vector3(road_w + 0.9, 0.25, 0.25), Color("2e2e2a"))
	for group in _lane_groups(opts):
		var x0 := _player.lane_x(group["from"]) - tuning.lane_width / 2.0
		var x1 := _player.lane_x(group["to"]) + tuning.lane_width / 2.0
		var edge: Dictionary = group["edge"]
		var color := DEAD_END_COLOR if edge.is_empty() else Hud.side_color(RouteGraph.side_of(edge))
		var text := "DEAD END" if edge.is_empty() else String(edge.get("label", edge["to"]))
		_item_box(cue, seg, at, Vector3((x0 + x1) / 2.0, post_h - 0.6, 0), Vector3(x1 - x0 - 0.15, 0.8, 0.12), color.darkened(0.55))
		var label := _sign_label(text, color, x1 - x0 - 0.2, Vector3.ZERO)
		cue.add_child(label)
		label.transform = _frame_at(seg, at) * Transform3D(Basis.IDENTITY, Vector3((x0 + x1) / 2.0, post_h - 0.6, 0.08))


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
	match _theme(id)["ground"]:
		"asphalt":
			return PsxTextures.asphalt()
		"office_floor":
			return PsxTextures.office_floor()
	return PsxTextures.concrete()


## How long one floor tile is along the road (office tiles are square, one lane wide).
func _ground_tile(id: StringName) -> float:
	return tuning.lane_width if _theme(id)["ground"] == "office_floor" else 4.0


func _wall_texture(theme: Dictionary) -> Texture2D:
	if theme.has("wall_tex"):
		return _obstacle_texture(theme["wall_tex"])
	return PsxTextures.wall(theme["wall"], theme["color"])


func _ceiling_texture(theme: Dictionary) -> Texture2D:
	return _obstacle_texture(theme["ceiling_tex"]) if theme.has("ceiling_tex") else _wall_texture(theme)


## This area's look for an obstacle (see THEMES "skins"), or the default.
func _skin(id: StringName, what: String, default: String) -> String:
	return _theme(id).get("skins", {}).get(what, default)


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
		parent.add_child(s)
		s.transform = _frame_at(seg, at) * Transform3D(Basis.IDENTITY, Vector3((x0 + x1) / 2.0, 0.03, 0))


func _obstacle_texture(name: String) -> Texture2D:
	match name:
		"hazard":
			return PsxTextures.hazard()
		"rust_pipe":
			return PsxTextures.rust_pipe()
		"crate_wood":
			return PsxTextures.crate_wood()
		"crate_metal":
			return PsxTextures.crate_metal()
		"cover_wall":
			return PsxTextures.cover_wall()
		"office_wall":
			return PsxTextures.office_wall()
		"office_ceiling":
			return PsxTextures.office_ceiling()
		"cabinet":
			return PsxTextures.cabinet()
		"desk":
			return PsxTextures.desk()
		"door":
			return PsxTextures.door()
	push_warning("Unknown obstacle texture '%s'" % name)
	return PsxTextures.concrete()


func _spawn_chopper(parent: Node3D, xf: Transform3D) -> void:
	var chopper := Node3D.new()
	chopper.name = "Chopper"
	parent.add_child(chopper)
	chopper.transform = xf
	chopper.add_to_group("chopper")
	# Built late (with the helipad), so catch up if it's already lifting off.
	if _clock and _clock.stage == ExtractionClock.Stage.LIFTING_OFF:
		var t := (_clock.elapsed - tuning.chopper_lifts_at) / (tuning.chopper_gone_at - tuning.chopper_lifts_at)
		chopper.position.y += 2.5 * t
		chopper.create_tween().tween_property(chopper, "position:y", xf.origin.y + 2.5, tuning.chopper_gone_at - _clock.elapsed)
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
	_combatants = _combatants.filter(func(c: Dictionary) -> bool:
		return is_instance_valid(c["node"]) and c["node"].at > d - 10.0)


# --- Rules ------------------------------------------------------------------------

func _check_obstacles() -> void:
	var d := _player.distance_run()
	var half_hit := tuning.lane_width * 0.5 + 0.15
	for o in _obstacles:
		if o["pass"] == "cover":
			# Reaching cover in its lane puts you in cover, just in front of it. It's the lane you're
			# heading for that counts, so once you swipe away you're out, even mid-slide.
			var stop_at: float = o["at"] - o["depth"] / 2.0 - tuning.cover_stop_gap
			if not _player.in_cover and d >= stop_at and d < o["at"] and absf(o["x"] - _player.lane_x(_player.lane)) < 0.1:
				_player.enter_cover(stop_at, o["crouch"])
				RunLog.record_event("cover", {"node": _runner.current})
			continue
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
				for other in _obstacles:  # the whole wire trips (and vanishes) at once
					if other["group"] == o["group"]:
						other["done"] = true
				o["mesh"].visible = false
				RunLog.record_event("tripwire", {"node": _runner.current})
				GameState.raise_alert()
				continue
		o["done"] = true
		_stumble(o)
		return


## Ran into a jump or slide obstacle: a stumble, not the end of the run. You're stunned and
## slowed (the chopper clock makes that cost something) and lose obstacle_damage HP. A short grace
## afterwards stops one fumble chaining into the next.
func _stumble(o: Dictionary) -> void:
	if _clock.elapsed < _stumble_grace_until:
		return
	_stumble_grace_until = _clock.elapsed + tuning.obstacle_grace
	RunLog.record_event("stumble", {"kind": o["kind"], "node": _runner.current})
	_player.stumble()
	var here := _player.global_position + Vector3(0, 1.2, 0)
	if o["pass"] == "slide" and _skin(_runner.current, "pipe", "pipe") == "wires":
		# Zapped by the live wires: a burst of sparks on the player.
		var s := Sparks.new(6, Time.get_ticks_msec())
		_world.add_child(s)
		s.global_position = here
		get_tree().create_timer(0.6).timeout.connect(s.queue_free)
	elif o["pass"] == "jump" and o["mesh"] is Node3D:
		# Knocked it over as you went through.
		var m: Node3D = o["mesh"]
		m.create_tween().tween_property(m, "rotation:x", m.rotation.x - 1.2, 0.25).set_ease(Tween.EASE_OUT)
	for i in tuning.obstacle_damage:
		_damage_player(String(o["kind"]))


# --- Combat -----------------------------------------------------------------------

## Troopers aim and shoot, alarm boxes open and close their windows, and FIRE shoots.
func _update_combat(delta: float) -> void:
	var d := _player.distance_run()
	var alert := GameState.alert_level
	var half_hit := tuning.lane_width * 0.5 + 0.15
	for c in _combatants:
		var n = c["node"]  # RifleTrooper or AlarmBox
		if not is_instance_valid(n):
			continue
		if not c["seg"].get("promoted", false):
			# On a branch ahead: not acting yet, but shown (and committed once seen) by the same
			# alert rules, so you never see a trooper that isn't there, or lose one you've seen.
			if n is RifleTrooper:
				n.note_seen(tuning, alert, d)
				n.visible = n.is_active(alert)
			continue
		if n is AlarmBox:
			n.update(delta, tuning, d)
			continue
		var t: RifleTrooper = n
		var shot := t.update(delta, tuning, alert, d, _player.track_x, _player.in_cover,
				_player.global_position, _route_point)
		if shot == RifleTrooper.Shot.MISSED:
			RunLog.record_event("trooper_missed", {"node": _runner.current, "in_cover": _player.in_cover})
		if shot == RifleTrooper.Shot.HIT:
			_damage_player("shot")
		# Running into a live trooper knocks him down, and it costs you a hit.
		if t.is_targetable(alert) and absf(t.at - d) < 0.5 and absf(t.x - _player.track_x) <= half_hit:
			t.knock_down()
			_damage_player("ran_into_trooper")
		if not GameState.run_active:
			return
	_hud.show_cover_hint(_player.in_cover)

	_fire_cooldown -= delta
	_hud.set_firing(_fire_held)
	if _fire_held and _fire_cooldown <= 0.0 and not _player.halted:
		_fire_cooldown = tuning.fire_interval
		_shoot()


## An alarm box hit lowers alert by one level; that can lift a lockdown door.
func _on_alarm_destroyed(node_id: StringName) -> void:
	RunLog.record_event("alarm_hit", {"node": node_id})
	GameState.lower_alert()


func _damage_player(why: String) -> void:
	if not _player.take_hit():
		return
	RunLog.record_event("player_hit", {"by": why, "node": _runner.current, "left": _player.hits_left})
	_hud.show_hit()
	_hud.show_hp(_player.hits_left, tuning.player_hits)
	if _player.hits_left <= 0:
		_end(&"killed")


## World position of a point on the route: `d` metres along, `x` across, `y` up.
func _route_point(d: float, x: float, y: float) -> Vector3:
	var seg := _segment_at(d)
	return seg["node"].global_transform * _frame_at(seg, d - seg["start"]) * Vector3(x, y, 0)


## What FIRE would hit right now (used by the bots, too).
func fire_target() -> Node3D:
	var alert := GameState.alert_level
	var candidates: Array[Node3D] = []
	for c in _combatants:
		var n = c["node"]  # RifleTrooper or AlarmBox
		if is_instance_valid(n) and c["seg"].get("promoted", false) and n.is_targetable(alert):
			candidates.append(n)
	var origin := _player.global_position + Vector3(0, 1.2, 0)
	var forward := -_player.global_transform.basis.z
	if _tapped != null and (not is_instance_valid(_tapped) or not _tapped.call("is_targetable", alert)):
		_tapped = null
	return Targeting.pick(candidates, origin, forward, tuning, _tapped)


func set_fire_held(held: bool) -> void:
	_fire_held = held and GameState.run_active


func _shoot() -> void:
	var from := _player.global_transform * Vector3(0.25, 1.2, -0.4)
	var target := fire_target()
	var to := from + (-_player.global_transform.basis.z) * 20.0
	if target != null:
		to = target.global_position + Vector3(0, 1.1 if target is RifleTrooper else 0.0, 0)
		target.call("hit")
	_shot_tracer.global_transform = Transform3D(Basis.looking_at(to - from) * Basis.from_scale(Vector3(1, 1, from.distance_to(to))), (from + to) / 2.0)
	_shot_tracer.visible = true
	get_tree().create_timer(0.05).timeout.connect(func() -> void: _shot_tracer.visible = false)


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
	var behind := _player.global_transform
	for i in tuning.capture_guards:
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
	_clock.stop()
	_fire_held = false
	_hud.set_firing(false)
	_hud.show_cover_hint(false)
	_hud.show_end(reason, RunLog.route_summary())


func _on_swipe(dir: Vector2i) -> void:
	if not _started:
		start_run()
	elif GameState.run_active:
		_player.handle_swipe(dir)


func _on_tap(pos: Vector2) -> void:
	if not _started:
		start_run()
	elif not GameState.run_active:
		_retry()
	elif tuning.targeting_mode != Tuning.TargetingMode.AUTO_PRIORITY:
		_tapped = _enemy_near_screen(pos)


## Tap-to-target (proposal under test): the live trooper drawn nearest the tap, if close enough.
func _enemy_near_screen(pos: Vector2) -> Node3D:
	var best: Node3D = null
	var best_d := tuning.tap_target_radius_px
	for c in _combatants:
		var n = c["node"]
		if not (n is RifleTrooper) or not n.is_targetable(GameState.alert_level):
			continue
		var p: Vector3 = n.global_position + Vector3(0, 1.0, 0)
		if _camera.is_position_behind(p):
			continue
		var d := _camera.unproject_position(p).distance_to(pos)
		if d < best_d:
			best_d = d
			best = n
	return best


func _on_fire() -> void:
	if not _started:
		start_run()
	elif not GameState.run_active:
		_retry()
	else:
		set_fire_held(true)


func _retry() -> void:
	_skip_title = true
	get_tree().reload_current_scene()


# --- Camera -----------------------------------------------------------------------

## Behind and above the player, in the frame of the leg they're on, eased so turns and
## climbs swing smoothly rather than snapping. Normally it sits a little toward the middle of the
## road; near a wall (walls are solid and lane-aligned) it moves right behind the player, so it
## never ends up inside one.
func _update_camera(delta: float) -> void:
	var d := _player.distance_run()
	var seg := _segment_at(d)
	var into: float = d - seg["start"]
	var f: Transform3D = seg["node"].global_transform * _frame_at(seg, into)
	var x := _player.track_x
	var near_wall := false
	for o in _obstacles:
		if o["kind"] == "wall" and o["at"] > d - 7.0 and o["at"] < d + 1.5:
			near_wall = true
			break
	_camera_follow = move_toward(_camera_follow, 1.0 if near_wall else 0.6, delta * 3.0)
	var eye := f * Vector3(x * _camera_follow, 3.4, 5.5)
	var look := f * Vector3(x * 0.8, 1.0, -10.0)
	var target := Transform3D(Basis.IDENTITY, eye).looking_at(look, Vector3.UP)
	_camera.global_transform = _camera.global_transform.interpolate_with(target, clampf(delta * 8.0, 0.0, 1.0))
