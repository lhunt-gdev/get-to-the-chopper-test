extends Node
## A simple bot that plays the prototype slice, so we know the route can be
## finished and the rules (alert gating, extraction, death, capture, combat) work end to end.
##   godot --headless --path . --fixed-fps 60 res://tests/autoplay/autoplay.tscn -- --scenario=ground
## Every bot but "naive" holds FIRE while there's a trooper to shoot (alarm boxes only in the
## alarm scenarios). Scenarios:
##   naive        - never moves or shoots; should be killed
##   ground       - keeps to the middle lanes: straight on through the main floor to the EXIT
##   tunnel_quiet - jumps the wires, takes MAIN FLOOR's left-lane stairs down to the TUNNEL
##                  (open at alert 1), then a ladder up
##   tunnel_loud  - runs through MAIN FLOOR's wire: the TUNNEL locks down (alert 2), so the left
##                  lane carries straight on to the EXIT
##   tunnel_alarm - runs through MAIN FLOOR's wire, shoots its alarm box (back to alert 1, the
##                  door lifts) and takes the TUNNEL after all
##   roof_down    - right-lane stairs up to the ROOFTOPS, then left-lane stairs back down into
##                  BUILDING MAIN FLOOR
##   roof_loud    - runs through the first wire (alert 2), up to the ROOFTOPS, straight on to the
##                  far end, right-lane ladder down
##   miss_ladder  - as roof_loud, but stays in the middle at the end of the ROOFTOPS: captured
##   late_switch  - heads for the right-lane stairs, then swipes back to the middle a few metres
##                  before the split: straight on must still be open, so MAIN FLOOR
##   cover        - runs into the first cover, holds fire until it's safe to shoot from cover,
##                  kills the trooper from there, breaks cover and goes on untouched
##   camper       - takes cover and never leaves it: the chopper should leave without us
##   ground_loud  - main route, runs through both wires and ignores the alarm boxes: Alert 3
##   ground_alarms - main route, runs through both wires, shoots both alarm boxes: back to Alert 1
##   stumble_once - main route, but runs straight into the first barrier: a stumble (1 HP, a
##                  little time), not the end of the run
##   dog_bite     - main route, but never shoots the lobby's guard dog and holds its lane when
##                  it charges: bitten (a hit and a stumble), and still gets out
##   dog_dodge    - main route, never shoots the dog, and swipes out of its lane when it barks:
##                  it runs past

const LEVEL := preload("res://game/levels/prototype_slice/prototype_slice.tscn")
const LOOK_AHEAD := 9.0
const ACT_DISTANCE := 1.6
const COVER_AT := 22.0

var scenario := "ground"
var _level: Node
var _player: Player
## Which side to lean toward at each junction, by node id (-1 left, 0 straight on, 1 right).
var _prefer := {}
## Segments where the bot runs through the tripwire instead of jumping it.
var _trip_in: Array = []
var _cooldown := 0
var _took_cover := false
var _cover_frames := 0
## stumble_once: the obstacle it deliberately doesn't jump (null until chosen).
var _fumble: Variant = null


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scenario="):
			scenario = a.get_slice("=", 1)
	match scenario:
		"tunnel_quiet":
			_prefer = {&"building_main_floor": -1, &"service_tunnel": -1}
		"tunnel_loud":
			_prefer = {&"building_main_floor": -1}
			_trip_in = [&"building_main_floor"]
		"tunnel_alarm":
			_prefer = {&"building_main_floor": -1, &"service_tunnel": -1}
			_trip_in = [&"building_main_floor"]
		"roof_down":
			_prefer = {&"main_floor_lobby": 1, &"rooftops": -1}
		"roof_loud":
			_prefer = {&"main_floor_lobby": 1, &"rooftops_far": 1}
			_trip_in = [&"main_floor_lobby"]
		"miss_ladder":
			_prefer = {&"main_floor_lobby": 1, &"rooftops_far": 0}
			_trip_in = [&"main_floor_lobby"]
		"late_switch":
			_prefer = {&"main_floor_lobby": 1}
		"ground_loud", "ground_alarms":
			_trip_in = [&"main_floor_lobby", &"building_main_floor"]
	_level = LEVEL.instantiate()
	add_child(_level)
	_player = _level.get_node("Player")
	GameState.run_ended.connect(_on_end)
	_level.start_run()
	get_tree().create_timer(150.0).timeout.connect(func() -> void: _report("timeout"))


func _physics_process(_delta: float) -> void:
	if not GameState.run_active or scenario == "naive":
		return
	var d := _player.distance_run()
	var obstacles: Array = _level._obstacles
	var lane_count: int = _player.tuning.lane_count

	_shoot()
	if d < 0.3 or _level.in_stairwell():
		return  # in the start room or a stairwell: no swipes until we're through the door
	if _player.in_cover:
		_took_cover = true
		_cover_frames += 1
		# Break cover once nobody ahead is alive to shoot at us.
		if scenario != "camper" and not _trooper_ahead(d):
			_player.handle_swipe(Vector2i.RIGHT if _player.lane < lane_count / 2 else Vector2i.LEFT)
		return

	# The guard dog: dog_dodge swipes out of the lane it's coming down; dog_bite holds its lane.
	var dog := _charging_dog(d)
	if dog != null and scenario == "dog_bite":
		_cooldown = 5
	if dog != null and scenario == "dog_dodge" and absf(dog.locked_x - _player.lane_x(_player.lane)) < 0.1 and _cooldown <= 0:
		var to := _player.lane - 1 if _player.lane > 0 and not _blocked_ahead(obstacles, _player.lane - 1, d) else _player.lane + 1
		_player.handle_swipe(Vector2i.LEFT if to < _player.lane else Vector2i.RIGHT)
		_cooldown = 30

	# Last-minute change of mind: back to the middle just before the first split.
	if scenario == "late_switch" and _level._runner.current == &"main_floor_lobby":
		var runner: RouteRunner = _level._runner
		var left_to_split := runner.graph.length_of(runner.current) - (d - runner.segment_start)
		if left_to_split < 4.0:
			_prefer[&"main_floor_lobby"] = 0
			_cooldown = mini(_cooldown, 0)

	# Steering: avoid lanes with cover (walls, boxes) coming up; lean to the preferred side at junctions.
	_cooldown -= 1
	if _cooldown <= 0:
		var best := _player.lane
		var best_score := -INF
		for lane in range(lane_count):
			var score := -absf(lane - _player.lane) * 0.5
			if _blocked_ahead(obstacles, lane, d):
				score -= 100.0
			if scenario in ["cover", "camper"] and d < COVER_AT and not _took_cover:
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
				if scenario == "stumble_once" and (_fumble == null or _fumble == o):
					_fumble = o  # run straight into this one
					continue
				_player.handle_swipe(Vector2i.UP)
			"jump_or_alert":
				if not _level._runner.current in _trip_in:
					_player.handle_swipe(Vector2i.UP)
			"slide":
				_player.handle_swipe(Vector2i.DOWN)


## Hold FIRE while there's something worth shooting.
func _shoot() -> void:
	var target: Node3D = _level.fire_target()
	var want := target != null
	if target is AlarmBox and not _may_shoot_alarm():
		want = false
	if target is RusherDog and scenario in ["dog_bite", "dog_dodge"]:
		want = false  # leave the dog to bite or be dodged
	if scenario in ["cover", "camper"] and not _player.in_cover and not _took_cover:
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


## A dog ahead that has barked or is charging at us, or null.
func _charging_dog(d: float) -> RusherDog:
	for c in _level._combatants:
		var n = c["node"]
		if n is RusherDog and n.state in [RusherDog.State.WINDUP, RusherDog.State.CHARGE] and n.at > d:
			return n
	return null


func _blocked_ahead(obstacles: Array, lane: int, d: float) -> bool:
	var x := _player.lane_x(lane)
	for o: Dictionary in obstacles:
		var seeking_cover := scenario in ["cover", "camper"] and not _took_cover
		var blocks: bool = o["pass"] == "cover" and not seeking_cover
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
	print("RESULT scenario=%s reason=%s alert=%d route=%s | covers=%d hits=%d missed=%d alarms=%d stumbles=%d doors=%d dogs=%d/%d/%d time=%.1f" % [scenario, reason,
			GameState.alert_level, RunLog.route_summary(), _count("cover"), _count("player_hit"), _count("trooper_missed"), _count("alarm_hit"), _count("stumble"), _count("door_bash"),
			_count("dog_bite"), _count("dog_dodged"), _count("dog_down"), _level._clock.elapsed])
	get_tree().quit()


## tunnel_alarm only shoots MAIN FLOOR's box (the one that can lift the TUNNEL door).
func _may_shoot_alarm() -> bool:
	match scenario:
		"ground_alarms":
			return true
		"tunnel_alarm":
			return _level._runner.current == &"building_main_floor"
	return false
