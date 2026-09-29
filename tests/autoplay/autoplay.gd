extends Node
## A simple bot that plays the prototype slice, so we know the route can be
## finished and the rules (alert gating, extraction, death, capture, combat) work end to end.
##   godot --headless --path . --fixed-fps 60 res://tests/autoplay/autoplay.tscn -- --scenario=ground
## Every bot but "naive" holds FIRE while there's a trooper to shoot (and only shoots the alarm
## box in roof_alarm). Scenarios:
##   naive       - never moves or shoots; should be killed
##   ground      - keeps to the middle lanes: straight on via MOTOR POOL
##   roof_quiet  - right-lane stairs to ROOFTOPS, jumps the tripwire, left-lane stairs down to
##                 TUNNEL (open at alert 1), then a ladder up
##   roof_loud   - trips the wire, so TUNNEL is sealed at alert 2 and the left lane carries on to
##                 ROOF EDGE; takes the right-lane ladder down
##   miss_ladder - as roof_loud, but stays in the middle at ROOF EDGE: should be captured
##   late_switch - heads for the right-lane stairs, then swipes back to the middle a few metres
##                 before the split: straight on must still be open, so MOTOR POOL
##   cover       - runs into the cover block, holds fire until it's safe to shoot from cover,
##                 kills the trooper from there, breaks cover and goes on untouched
##   roof_alarm  - trips the wire (alert 2, TUNNEL locked down), shoots the alarm box on the
##                 rooftops (back to alert 1, the door lifts) and takes the TUNNEL after all

const LEVEL := preload("res://game/levels/prototype_slice/prototype_slice.tscn")
const LOOK_AHEAD := 9.0
const ACT_DISTANCE := 1.6
const COVER_AT := 22.0

var scenario := "ground"
var _level: Node
var _player: Player
## Which side to lean toward at each junction, by node id (-1 left, 0 straight on, 1 right).
var _prefer := {}
var _jump_tripwires := true
var _cooldown := 0
var _took_cover := false
var _cover_frames := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scenario="):
			scenario = a.get_slice("=", 1)
	match scenario:
		"roof_quiet", "roof_alarm":
			_prefer = {&"compound_exit": 1, &"rooftops": -1, &"service_tunnel": -1}
		"roof_loud":
			_prefer = {&"compound_exit": 1, &"rooftops": -1, &"roof_edge": 1}
		"miss_ladder":
			_prefer = {&"compound_exit": 1, &"rooftops": -1, &"roof_edge": 0}
		"late_switch":
			_prefer = {&"compound_exit": 1}
	_jump_tripwires = not scenario in ["roof_loud", "miss_ladder", "roof_alarm"]
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

	_shoot()
	if _player.in_cover:
		_took_cover = true
		_cover_frames += 1
		# Break cover once nobody ahead is alive to shoot at us.
		if not _trooper_ahead(d):
			_player.handle_swipe(Vector2i.RIGHT if _player.lane < lane_count / 2 else Vector2i.LEFT)
		return

	# Last-minute change of mind: back to the middle just before the first split.
	if scenario == "late_switch" and _level._runner.current == &"compound_exit":
		var runner: RouteRunner = _level._runner
		var left_to_split := runner.graph.length_of(runner.current) - (d - runner.segment_start)
		if left_to_split < 4.0:
			_prefer[&"compound_exit"] = 0
			_cooldown = mini(_cooldown, 0)

	# Steering: avoid lanes with a truck (or cover) coming up; lean to the preferred side at junctions.
	_cooldown -= 1
	if _cooldown <= 0:
		var best := _player.lane
		var best_score := -INF
		for lane in range(lane_count):
			var score := -absf(lane - _player.lane) * 0.5
			if _blocked_ahead(obstacles, lane, d):
				score -= 100.0
			if scenario == "cover" and d < COVER_AT and not _took_cover:
				score -= absf(lane - 1) * 200.0  # head for the cover block's lane
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


## Hold FIRE while there's something worth shooting.
func _shoot() -> void:
	var target: Node3D = _level.fire_target()
	var want := target != null
	if target is AlarmBox and scenario != "roof_alarm":
		want = false
	if scenario == "cover" and not _player.in_cover and _level._runner.current == &"compound_exit":
		want = false  # prove the cover works: only shoot once we're behind it...
	if scenario == "cover" and _player.in_cover and _cover_frames < 90:
		want = false  # ...and only after he's had a shot at us (1.5 s)
	_level.set_fire_held(want)


func _trooper_ahead(d: float) -> bool:
	for c in _level._combatants:
		var n = c["node"]
		if n is RifleTrooper and n.is_targetable(GameState.alert_level) and n.at > d and n.at - d < _player.tuning.trooper_aim_range + 2.0:
			return true
	return false


func _blocked_ahead(obstacles: Array, lane: int, d: float) -> bool:
	var x := _player.lane_x(lane)
	for o: Dictionary in obstacles:
		var blocks: bool = o["pass"] == "dodge" or (o["pass"] == "cover" and scenario != "cover")
		if blocks and absf(o["x"] - x) < 0.1 and o["at"] + o["depth"] > d - 0.5 and o["at"] - d < LOOK_AHEAD:
			return true
	return false


func _junction_soon() -> bool:
	var runner: RouteRunner = _level._runner
	var into := _player.distance_run() - runner.segment_start
	var decision_at := runner.graph.length_of(runner.current) - _player.tuning.decision_lead
	return into > decision_at - _player.tuning.approach_window - 6.0 and into < decision_at


func _on_end(reason: StringName) -> void:
	_report(String(reason))


func _count(kind: String) -> int:
	return RunLog.events.filter(func(e: Dictionary) -> bool: return e["kind"] == kind).size()


func _report(reason: String) -> void:
	print("RESULT scenario=%s reason=%s alert=%d route=%s | covers=%d hits=%d missed=%d alarms=%d" % [scenario, reason,
			GameState.alert_level, RunLog.route_summary(), _count("cover"), _count("player_hit"), _count("trooper_missed"), _count("alarm_hit")])
	get_tree().quit()
