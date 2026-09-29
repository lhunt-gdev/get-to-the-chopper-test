extends Node3D
## Walking skeleton for the first playable: auto-run, swipes, lanes, obstacles,
## alert-gated branching, run log, extraction. Placeholder boxes throughout.
## Not built yet: enemies, FIRE, cover, alarm boxes, chopper timer, route map screen.

const ROUTE_PATH := "res://game/levels/prototype_slice/route.json"
const START_ALERT := 1

## Obstacle kinds: size, height off the ground, look, and how to get past it.
## "tex" names a PsxTextures function; without one the obstacle is flat "color".
const KINDS := {
	"barrier": {"size": Vector3(0.9, 0.5, 0.3), "y": 0.25, "tex": "hazard", "pass": "jump"},
	"pipe": {"size": Vector3(0.9, 0.3, 0.3), "y": 1.3, "tex": "rust_pipe", "pass": "slide"},
	"truck": {"size": Vector3(0.95, 2.2, 3.0), "y": 1.1, "tex": "truck", "pass": "dodge"},
	"tripwire": {"size": Vector3(1.0, 0.05, 0.05), "y": 0.3, "color": Color("ff3030"), "pass": "jump_or_alert"},
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

@export var tuning: Tuning

## Retry skips the title card so the loop stays fast.
static var _skip_title := false

var _started := false
var _graph: RouteGraph
var _obstacles: Array[Dictionary] = []
var _segments: Array[Dictionary] = []  # {node: Node3D, end: float}
var _fork_segment: Dictionary = {}  # {id, start, node}: the segment whose fork is still ahead

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
	GameState.run_ended.connect(_on_run_ended)
	GameState.alert_changed.connect(_build_fork_cue.unbind(1))

	_spawn_segment(_graph.start_id, 0.0)
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
	_update_camera(delta)


# --- World building -----------------------------------------------------------

func _spawn_segment(id: StringName, start: float) -> void:
	var length := _graph.length_of(id)
	var seg := Node3D.new()
	seg.name = String(id)
	_world.add_child(seg)
	var road_w := tuning.lane_count * tuning.lane_width
	var theme := _theme(id)

	# The road stops where the fork cue starts, if there is one. The cue paints the rest.
	var road_len := length
	if _graph.end_type(id) == "" and _graph.node_data(id).get("next", []).size() >= 2:
		road_len = maxf(0.0, length - tuning.decision_lead - tuning.fork_cue_length)
	var ground := _ground(id)
	if road_len > 0.0:
		_plane(seg, Vector2(road_w, road_len), Vector3(0, 0, -(start + road_len / 2.0)), ground,
				Vector2(tuning.lane_count, road_len / 4.0))

	# Kerbs and walls either side.
	var wall_tex := PsxTextures.wall(theme["wall"], theme["color"])
	var h: float = theme["height"]
	for side in [-1, 1]:
		var x: float = side * (road_w / 2.0 + 0.5)
		_plane(seg, Vector2(1.0, length), Vector3(x, 0.02, -(start + length / 2.0)), PsxTextures.concrete(),
				Vector2(1.0, length / 2.0))
		var wall := _plane(seg, Vector2(length, h), Vector3(side * (road_w / 2.0 + 1.0), h / 2.0, -(start + length / 2.0)),
				wall_tex, Vector2(length / 2.0, h / 2.0), PlaneMesh.FACE_Z)
		wall.rotation.y = -side * PI / 2.0  # face the road
	if theme.get("ceiling", false):
		var roof := _plane(seg, Vector2(road_w + 2.0, length), Vector3(0, 4.6, -(start + length / 2.0)),
				wall_tex, Vector2(road_w / 2.0, length / 2.0))
		roof.rotation.x = PI  # face down
	# Pillars every 5 m, alternating light and dark, give a sense of speed.
	for i in range(0, int(length), 5):
		var z := -(start + i)
		var c: Color = theme["color"].lightened(0.25) if (i / 5) % 2 == 0 else theme["color"].darkened(0.5)
		for side in [-1, 1]:
			_box(seg, Vector3(0.35, maxf(h, 1.2), 0.35), Vector3(side * (road_w / 2.0 + 0.8), maxf(h, 1.2) / 2.0, z), c)

	var authored_lanes := 5
	for ob: Dictionary in _graph.node_data(id).get("obstacles", []):
		var kind: Dictionary = KINDS.get(ob["kind"], {})
		if kind.is_empty():
			push_warning("Unknown obstacle kind '%s' in %s" % [ob["kind"], id])
			continue
		var lanes := {}
		for l in ob.get("lanes", []):
			lanes[_remap_lane(int(l), authored_lanes)] = true
		for lane: int in lanes:
			var at: float = start + float(ob["at"])
			var size: Vector3 = kind["size"] * Vector3(tuning.lane_width, 1, 1)
			var x := _player.lane_x(lane)
			var mesh := _box(seg, size, Vector3(x, kind["y"], -at), kind.get("color", Color.WHITE))
			if kind.has("tex"):
				# BoxMesh lays its six faces out on a 3x2 grid, so this puts one tile on each face.
				mesh.material_override = PsxMaterials.textured(_obstacle_texture(kind["tex"]), Vector2(3, 2))
			_obstacles.append({"x": x, "at": at, "depth": size.z, "kind": ob["kind"], "pass": kind["pass"], "done": false, "mesh": mesh})

	if _graph.end_type(id) == "extract":
		_spawn_chopper(seg, start + length + 3.0)

	_segments.append({"node": seg, "end": start + length})
	# The newest segment is always the one whose fork is still ahead of the player.
	_fork_segment = {"id": id, "start": start, "node": seg}
	_build_fork_cue()


## Paints each lane in its route's colour with arrows, and puts a sign over the commit point.
## The routes on offer depend on alert, so this is rebuilt whenever alert changes.
func _build_fork_cue() -> void:
	if _fork_segment.is_empty():
		return
	var seg: Node3D = _fork_segment["node"]
	var old := seg.get_node_or_null("ForkCue")
	if old:
		seg.remove_child(old)
		old.queue_free()
	var id: StringName = _fork_segment["id"]
	if _graph.end_type(id) != "" or _graph.node_data(id).get("next", []).size() < 2:
		return

	var cue := Node3D.new()
	cue.name = "ForkCue"
	seg.add_child(cue)
	var length := _graph.length_of(id)
	var road_w := tuning.lane_count * tuning.lane_width
	var cue_start: float = _fork_segment["start"] + maxf(0.0, length - tuning.decision_lead - tuning.fork_cue_length)
	var cue_len: float = _fork_segment["start"] + length - cue_start
	var decision_z: float = -(_fork_segment["start"] + length - tuning.decision_lead)
	var opts := _graph.available_next(id, GameState.alert_level)

	# Lanes. With one open route, the road is just road again.
	for lane in tuning.lane_count:
		var tex := _ground(id)
		if opts.size() >= 2:
			var idx := RouteGraph.pick_by_lane(lane, tuning.lane_count, opts.size())
			tex = PsxTextures.fork_lane(Hud.route_dir(idx, opts.size()), Hud.route_color(idx))
		_plane(cue, Vector2(tuning.lane_width, cue_len), Vector3(_player.lane_x(lane), 0, -(cue_start + cue_len / 2.0)),
				tex, Vector2(1, cue_len / 4.0))
	if opts.size() < 2:
		return

	# Sign gantry over the commit point: one panel per route, over the lanes that lead there.
	# Panels sit above the camera (y 3.4) so it never flies through them. The lanes show direction.
	var post_h := 5.6
	for side in [-1, 1]:
		_box(cue, Vector3(0.3, post_h, 0.3), Vector3(side * (road_w / 2.0 + 0.3), post_h / 2.0, decision_z), Color("2e2e2a"))
	_box(cue, Vector3(road_w + 0.9, 0.25, 0.25), Vector3(0, post_h - 0.2, decision_z), Color("2e2e2a"))
	for idx in opts.size():
		var lanes := range(tuning.lane_count).filter(func(l: int) -> bool:
			return RouteGraph.pick_by_lane(l, tuning.lane_count, opts.size()) == idx)
		var x0 := _player.lane_x(lanes[0]) - tuning.lane_width / 2.0
		var x1 := _player.lane_x(lanes[-1]) + tuning.lane_width / 2.0
		var color := Hud.route_color(idx)
		_box(cue, Vector3(x1 - x0 - 0.15, 0.9, 0.12), Vector3((x0 + x1) / 2.0, post_h - 0.8, decision_z), color.darkened(0.55))
		var label := Label3D.new()
		label.text = String(opts[idx].get("label", opts[idx]["to"]))
		label.modulate = color.lightened(0.3)
		label.outline_modulate = Color.BLACK
		label.font_size = 40
		label.outline_size = 8
		label.pixel_size = 0.012
		label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		label.width = (x1 - x0) / label.pixel_size
		label.autowrap_mode = TextServer.AUTOWRAP_WORD
		label.position = Vector3((x0 + x1) / 2.0, post_h - 0.8, decision_z + 0.08)
		cue.add_child(label)


func _theme(id: StringName) -> Dictionary:
	return THEMES.get(_graph.node_data(id).get("theme", ""), THEMES["compound"])


func _ground(id: StringName) -> Texture2D:
	return PsxTextures.asphalt() if _theme(id)["ground"] == "asphalt" else PsxTextures.concrete()


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


func _spawn_chopper(parent: Node3D, at: float) -> void:
	var chopper := Node3D.new()
	chopper.name = "Chopper"
	parent.add_child(chopper)
	chopper.position = Vector3(0, 0, -at)
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
		if absf(o["x"] - _player.position.x) > half_hit:
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

func _update_camera(delta: float) -> void:
	var p := _player.position
	var target := Vector3(p.x * 0.6, 3.4, p.z + 5.5)
	_camera.position = _camera.position.lerp(target, clampf(delta * 8.0, 0.0, 1.0))
	_camera.look_at(Vector3(p.x * 0.8, 1.0, p.z - 10.0))
