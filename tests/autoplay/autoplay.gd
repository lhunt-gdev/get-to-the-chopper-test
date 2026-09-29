extends Node
## A simple bot that plays the prototype slice, so we know the route can be
## finished and the rules (alert gating, extraction, death) work end to end.
##   godot --headless --path . --fixed-fps 60 res://tests/autoplay/autoplay.tscn -- --scenario=left
## Scenarios:
##   naive       - never moves; should be killed
##   ground      - keeps to the middle lanes: straight on via MOTOR POOL
##   roof_quiet  - right-lane stairs to ROOFTOPS, jumps the tripwire, left-lane stairs down to
##                 TUNNEL (open at alert 1), then a ladder up
##   roof_loud   - trips the wire, so TUNNEL is sealed at alert 2 and the left lane carries on to
##                 ROOF EDGE; takes the right-lane ladder down
##   miss_ladder - as roof_loud, but stays in the middle at ROOF EDGE: should be captured
##   late_switch - heads for the right-lane stairs, then swipes back to the middle a few metres
##                 before the split: straight on must still be open, so MOTOR POOL

const LEVEL := preload("res://game/levels/prototype_slice/prototype_slice.tscn")
const LOOK_AHEAD := 9.0
const ACT_DISTANCE := 1.6

var scenario := "ground"
var _level: Node
var _player: Player
## Which side to lean toward at each junction, by node id (-1 left, 0 straight on, 1 right).
var _prefer := {}
var _jump_tripwires := true
var _cooldown := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scenario="):
			scenario = a.get_slice("=", 1)
	match scenario:
		"roof_quiet":
			_prefer = {&"compound_exit": 1, &"rooftops": -1, &"service_tunnel": -1}
		"roof_loud":
			_prefer = {&"compound_exit": 1, &"rooftops": -1, &"roof_edge": 1}
		"miss_ladder":
			_prefer = {&"compound_exit": 1, &"rooftops": -1, &"roof_edge": 0}
		"late_switch":
			_prefer = {&"compound_exit": 1}
	_jump_tripwires = not scenario in ["roof_loud", "miss_ladder"]
	_level = LEVEL.instantiate()
	add_child(_level)
	_player = _level.get_node("Player")
	GameState.run_ended.connect(_on_end)
	_level.start_run()
	get_tree().create_timer(60.0).timeout.connect(func() -> void: _report("timeout"))


func _physics_process(_delta: float) -> void:
	if not GameState.run_active or scenario == "naive":
		return
	var d := _player.distance_run()
	var obstacles: Array = _level._obstacles
	var lane_count: int = _player.tuning.lane_count

	# Last-minute change of mind: back to the middle just before the first split.
	if scenario == "late_switch" and _level._runner.current == &"compound_exit":
		var runner: RouteRunner = _level._runner
		var left_to_split := runner.graph.length_of(runner.current) - (d - runner.segment_start)
		if left_to_split < 4.0:
			_prefer[&"compound_exit"] = 0
			_cooldown = mini(_cooldown, 0)

	# Steering: avoid lanes with a truck coming up; lean to the preferred side at junctions.
	_cooldown -= 1
	if _cooldown <= 0:
		var best := _player.lane
		var best_score := -INF
		for lane in range(lane_count):
			var score := -absf(lane - _player.lane) * 0.5
			if _truck_ahead(obstacles, lane, d):
				score -= 100.0
			if not _level._runner._shown_labels.is_empty() or _junction_soon():
				var lean := int(_prefer.get(_level._runner.current, 0))
				score += lean * lane * 2.0
				# Straight on means keeping out of the outer lanes, which take the side exits.
				if lean == 0 and (lane == 0 or lane == lane_count - 1):
					score -= 50.0
			if score > best_score:
				best_score = score
				best = lane
		if best != _player.lane:
			_player.handle_swipe(Vector2i.RIGHT if best > _player.lane else Vector2i.LEFT)
			_cooldown = 5

	# Jumping and sliding.
	for o: Dictionary in obstacles:
		if o["done"] or absf(o["x"] - _player.track_x) > 0.8:
			continue
		var gap: float = o["at"] - d
		if gap < 0.0 or gap > ACT_DISTANCE:
			continue
		match o["pass"]:
			"jump":
				_player.handle_swipe(Vector2i.UP)
			"jump_or_alert":
				if _jump_tripwires:
					_player.handle_swipe(Vector2i.UP)
			"slide":
				_player.handle_swipe(Vector2i.DOWN)


func _truck_ahead(obstacles: Array, lane: int, d: float) -> bool:
	var x := _player.lane_x(lane)
	for o: Dictionary in obstacles:
		if o["pass"] == "dodge" and absf(o["x"] - x) < 0.1 and o["at"] + o["depth"] > d - 0.5 and o["at"] - d < LOOK_AHEAD:
			return true
	return false


func _junction_soon() -> bool:
	var runner: RouteRunner = _level._runner
	var into := _player.distance_run() - runner.segment_start
	var decision_at := runner.graph.length_of(runner.current) - _player.tuning.decision_lead
	return into > decision_at - _player.tuning.approach_window - 6.0 and into < decision_at


func _on_end(reason: StringName) -> void:
	_report(String(reason))


func _report(reason: String) -> void:
	print("RESULT scenario=%s reason=%s alert=%d route=%s" % [scenario, reason, GameState.alert_level, RunLog.route_summary()])
	get_tree().quit()
