extends Node3D
## Walking skeleton for the first playable: auto-run, swipes, lanes, obstacles,
## alert-gated branching, run log, extraction. Placeholder boxes throughout.
## Not built yet: enemies, FIRE, cover, alarm boxes, chopper timer, route map screen.

const ROUTE_PATH := "res://game/levels/prototype_slice/route.json"
const START_ALERT := 1

## Obstacle kinds: size, height off the ground, colour, and how to get past it.
const KINDS := {
	"barrier": {"size": Vector3(0.9, 0.5, 0.3), "y": 0.25, "color": Color("c9a227"), "pass": "jump"},
	"pipe": {"size": Vector3(0.9, 0.3, 0.3), "y": 1.3, "color": Color("7a7f86"), "pass": "slide"},
	"truck": {"size": Vector3(0.95, 2.2, 3.0), "y": 1.1, "color": Color("3d4a2a"), "pass": "dodge"},
	"tripwire": {"size": Vector3(1.0, 0.05, 0.05), "y": 0.3, "color": Color("ff3030"), "pass": "jump_or_alert"},
}

@export var tuning: Tuning

## Retry skips the title card so the loop stays fast.
static var _skip_title := false

var _started := false
var _graph: RouteGraph
var _obstacles: Array[Dictionary] = []
var _segments: Array[Dictionary] = []  # {node: Node3D, end: float}

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

	_box(seg, Vector3(road_w + 1.0, 0.2, length), Vector3(0, -0.1, -(start + length / 2.0)), Color("4a4a44"))
	# Edge posts every 5 m give a sense of speed.
	for i in range(0, int(length), 5):
		var z := -(start + i)
		var c := Color("8a8a80") if (i / 5) % 2 == 0 else Color("2e2e2a")
		_box(seg, Vector3(0.3, 1.2, 0.3), Vector3(-(road_w / 2.0 + 0.6), 0.6, z), c)
		_box(seg, Vector3(0.3, 1.2, 0.3), Vector3(road_w / 2.0 + 0.6, 0.6, z), c)

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
			var mesh := _box(seg, size, Vector3(x, kind["y"], -at), kind["color"])
			_obstacles.append({"x": x, "at": at, "depth": size.z, "kind": ob["kind"], "pass": kind["pass"], "done": false, "mesh": mesh})

	if _graph.end_type(id) == "extract":
		_spawn_chopper(seg, start + length + 3.0)

	_segments.append({"node": seg, "end": start + length})


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
