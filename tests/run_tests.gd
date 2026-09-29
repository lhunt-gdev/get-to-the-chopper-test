extends SceneTree
## Minimal dependency-free test runner. Run headless:
##   godot --headless --path . -s res://tests/run_tests.gd
## Exits with code 1 if any check fails (CI blocks the deploy).

var _failures := 0
var _checks := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame  # let the root viewport enter the tree
	_test_route_json_is_valid()
	_test_alert_gating()
	_test_pick_edge()
	_test_route_rules()
	_test_trooper_rules()
	_test_swipe_direction()
	await _test_targeting_priority()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		printerr("FAIL: " + msg)


func _test_route_json_is_valid() -> void:
	var g := RouteGraph.from_json_file("res://game/levels/prototype_slice/route.json")
	_check(g != null, "route.json loads")
	if g == null:
		return
	var problems := g.validate()
	_check(problems.is_empty(), "route.json valid: %s" % ", ".join(problems))
	_check(g.end_type(&"helipad") == "extract", "helipad is an extraction end")


func _test_alert_gating() -> void:
	var g := RouteGraph.from_json_file("res://game/levels/prototype_slice/route.json")
	_check(g.available_next(&"rooftops", 1).size() == 2, "tunnel open at alert 1")
	_check(g.available_next(&"rooftops", 2).size() == 1, "tunnel sealed at alert 2")


func _test_pick_edge() -> void:
	var straight := {"to": "a"}
	var left := {"to": "b", "side": "left", "via": "corridor"}
	var right := {"to": "c", "side": "right", "via": "stairs"}
	var three: Array[Dictionary] = [straight, left, right]
	_check(RouteGraph.pick_edge(0, 5, three) == left, "far-left lane takes the left exit")
	_check(RouteGraph.pick_edge(4, 5, three) == right, "far-right lane takes the right exit")
	for lane in [1, 2, 3]:
		_check(RouteGraph.pick_edge(lane, 5, three) == straight, "middle lane %d carries straight on" % lane)
	var no_left: Array[Dictionary] = [straight, right]
	_check(RouteGraph.pick_edge(0, 5, no_left) == straight, "far-left with no left exit carries straight on")
	var ladders: Array[Dictionary] = [left, right]
	_check(RouteGraph.pick_edge(2, 5, ladders).is_empty(), "middle lane with no straight exit: no way on (capture)")
	var only_straight: Array[Dictionary] = [straight]
	_check(not RouteGraph.is_choice(only_straight), "a single straight road is not a choice")
	_check(RouteGraph.is_choice(ladders), "ladders are a choice")


func _test_trooper_rules() -> void:
	var w := 1.4
	_check(RifleTrooper.shot_hits(0.0, 0.0, false, w), "trooper hits you in the lane he aimed at")
	_check(not RifleTrooper.shot_hits(1.4, 0.0, false, w), "change lane before the shot and he misses")
	_check(RifleTrooper.shot_hits(0.5, 0.0, false, w), "halfway through a lane change you're still hit")
	_check(not RifleTrooper.shot_hits(0.0, 0.0, true, w), "cover blocks the shot")
	var t := Tuning.new()
	_check(RifleTrooper.aim_time(t, 1) > RifleTrooper.aim_time(t, 2) and RifleTrooper.aim_time(t, 2) > RifleTrooper.aim_time(t, 3),
			"higher alert, less time to dodge")


func _test_route_rules() -> void:
	var bad := RouteGraph.from_dict({"start": "a", "nodes": [
		{"id": "a", "tier": "ground", "next": [{"to": "b", "side": "left", "via": "corridor"}, {"to": "c"}]},
		{"id": "b", "tier": "roof", "end": "extract"},
		{"id": "c", "tier": "ground", "next": [{"to": "a", "side": "right", "via": "ladder"}]},
	]})
	var problems := " ".join(bad.validate())
	_check("use stairs" in problems, "a corridor that changes height is rejected")
	_check("ladder must change height" in problems, "a ladder on one level is rejected")
	_check("ladders only lead to the end" in problems, "a ladder that isn't to the end is rejected")
	var no_straight := RouteGraph.from_dict({"start": "a", "nodes": [
		{"id": "a", "next": [{"to": "b", "side": "left", "via": "corridor"}, {"to": "c", "max_alert": 1}]},
		{"id": "b", "end": "extract"},
		{"id": "c", "end": "extract"},
		{"id": "d", "next": [{"to": "b", "side": "right", "via": "corridor"}]},
	]})
	problems = " ".join(no_straight.validate())
	_check("straight on must always be open" in problems, "an alert-gated straight road is rejected")
	_check("node 'd' has side exits but no straight road" in problems, "side exits without a straight road are rejected")


func _test_swipe_direction() -> void:
	_check(SwipeInput.direction_of(Vector2(30, 5)) == Vector2i.RIGHT, "swipe right")
	_check(SwipeInput.direction_of(Vector2(-30, 5)) == Vector2i.LEFT, "swipe left")
	_check(SwipeInput.direction_of(Vector2(3, -30)) == Vector2i.UP, "swipe up")
	_check(SwipeInput.direction_of(Vector2(3, 30)) == Vector2i.DOWN, "swipe down")


class FakeEnemy extends Node3D:
	var priority := 0
	func get_threat_priority() -> int:
		return priority


func _test_targeting_priority() -> void:
	var tuning := Tuning.new()
	var near := FakeEnemy.new()
	var alarm := FakeEnemy.new()
	alarm.priority = 100
	root.add_child(near)
	root.add_child(alarm)
	await process_frame
	near.global_position = Vector3(0, 0, -5)
	alarm.global_position = Vector3(1, 0, -20)
	var enemies: Array[Node3D] = [near, alarm]
	var fwd := Vector3.FORWARD

	tuning.targeting_mode = Tuning.TargetingMode.AUTO_PRIORITY
	_check(Targeting.pick(enemies, Vector3.ZERO, fwd, tuning) == alarm, "auto: urgent threat beats nearest")
	alarm.priority = 0
	_check(Targeting.pick(enemies, Vector3.ZERO, fwd, tuning) == near, "auto: nearest wins a tie")

	tuning.targeting_mode = Tuning.TargetingMode.HYBRID
	_check(Targeting.pick(enemies, Vector3.ZERO, fwd, tuning, alarm) == alarm, "hybrid: tap overrides")

	tuning.targeting_mode = Tuning.TargetingMode.TAP_TO_TARGET
	_check(Targeting.pick(enemies, Vector3.ZERO, fwd, tuning) == null, "tap mode: no tap, no shot")

	var behind := FakeEnemy.new()
	root.add_child(behind)
	await process_frame
	behind.global_position = Vector3(0, 0, 5)
	_check(not Targeting.in_cone(behind.global_position, Vector3.ZERO, fwd, tuning), "enemy behind is out of cone")
	for n in [near, alarm, behind]:
		n.queue_free()
