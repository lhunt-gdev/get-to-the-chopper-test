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
	_test_chopper_stages()
	_test_seen_troopers_stay()
	_test_mission_layout()
	_test_trooper_tiers()
	_test_swipe_direction()
	_test_sounds()
	await _test_targeting_priority()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		printerr("FAIL: " + msg)


func _test_sounds() -> void:
	var bad: Array[String] = []
	var unlooped: Array[String] = []
	for name in SoundBank.all_names():
		var s := SoundBank.get_stream(name)
		if s == null or s.data.size() < 64:
			bad.append(name)
		elif name in SoundBank.LOOPS and s.loop_mode != AudioStreamWAV.LOOP_FORWARD:
			unlooped.append(name)
	_check(bad.is_empty(), "every sound builds (bad: %s)" % [bad])
	_check(unlooped.is_empty(), "ambience, music and other loops loop (not: %s)" % [unlooped])


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
	_check(g.available_next(&"building_main_floor", 1).size() == 2, "tunnel open at alert 1")
	_check(g.available_next(&"building_main_floor", 2).size() == 1, "tunnel sealed at alert 2")


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


## Every route must reach the end; areas in several stretches show once in the summary.
func _test_mission_layout() -> void:
	var loop := RouteGraph.from_dict({"start": "a", "nodes": [
		{"id": "a", "next": [{"to": "b"}, {"to": "c", "side": "left", "via": "corridor"}]},
		{"id": "b", "end": "extract"},
		{"id": "c", "next": [{"to": "d"}]},
		{"id": "d", "next": [{"to": "c"}]},
	]})
	var problems := " ".join(loop.validate())
	_check("node 'c' can never reach the end" in problems, "a branch that never reaches the end is rejected")
	var cramped := RouteGraph.from_dict({"start": "a", "nodes": [
		{"id": "a", "tier": "ground", "next": [{"to": "e"}, {"to": "r", "side": "right", "via": "stairs"}]},
		{"id": "r", "tier": "roof", "length": 60, "next": [{"to": "e", "side": "left", "via": "ladder"}],
			"obstacles": [{"kind": "barrier", "lanes": [2], "at": 15}, {"kind": "box", "lanes": [1], "at": 25}]},
		{"id": "e", "tier": "ground", "end": "extract"},
	]})
	problems = " ".join(cramped.validate())
	_check("barrier at 15" in problems and "too close to the stairs' exit" in problems, "nothing right outside a stairwell's exit door")
	_check(not "box at 25" in problems, "things further on after the stairs are fine")
	_check(not "node 'a' can never" in problems, "a node with one good route is fine")
	var marked := RouteGraph.from_dict({"start": "a", "nodes": [
		{"id": "a", "tier": "ground", "theme": "office", "length": 100, "marker": {"at": 50}, "next": [{"to": "e"}],
			"obstacles": [{"kind": "box", "lanes": [1], "at": 46}, {"kind": "box", "lanes": [2], "at": 65}, {"kind": "box", "lanes": [1], "at": 72}],
			"enemies": [{"kind": "rifle_trooper", "lane": 2, "at": 53}]},
		{"id": "r", "tier": "ground", "theme": "rooftops", "length": 60, "marker": {"at": 30}, "next": [{"to": "e"}]},
		{"id": "e", "tier": "ground", "end": "extract"},
	]})
	problems = " ".join(marked.validate())
	_check("box at 46" in problems and "rifle_trooper at 53" in problems, "nothing right by a halfway marker's doors")
	_check("box at 65" in problems, "nothing too soon after a halfway marker (you burst through blind)")
	_check(not "box at 72" in problems, "things further on after a halfway marker are fine")
	_check("no halfway marker on open roofs" in problems, "no halfway marker on the rooftops")
	var g := RouteGraph.from_json_file("res://game/levels/prototype_slice/route.json")
	_check(g.display_name(&"rooftops_far") == "ROOFTOPS", "the far rooftops show as ROOFTOPS")
	var run_log: Node = root.get_node_or_null("RunLog")  # an autoload; not a global name in -s scripts
	if run_log == null:
		_check(false, "RunLog autoload is available")
		return
	run_log.begin()
	run_log.enter_node(&"rooftops", g.display_name(&"rooftops"))
	run_log.enter_node(&"rooftops_far", g.display_name(&"rooftops_far"))
	run_log.enter_node(&"helipad", g.display_name(&"helipad"))
	_check(run_log.route_summary() == "ROOFTOPS > HELIPAD", "two stretches of rooftops show once: %s" % run_log.route_summary())


## Every route has a trooper set per alert level, with fewer at Alert 1 than at 2, and at 2 than at 3.
func _test_trooper_tiers() -> void:
	var g := RouteGraph.from_json_file("res://game/levels/prototype_slice/route.json")
	for id in ["main_floor_lobby", "building_main_floor", "rooftops", "rooftops_far", "service_tunnel", "main_floor_exit"]:
		var counts := [0, 0, 0]
		for e in g.node_data(StringName(id)).get("enemies", []):
			for alert in [1, 2, 3]:
				if alert >= int(e.get("min_alert", 1)) and alert <= int(e.get("max_alert", 3)):
					counts[alert - 1] += 1
		_check(counts[0] >= 1 and counts[0] < counts[1] and counts[1] < counts[2],
				"%s: more troopers at each alert level (%s)" % [id, counts])


## Dropping the alert never makes a trooper you've already seen vanish.
func _test_seen_troopers_stay() -> void:
	var t := Tuning.new()
	var near := RifleTrooper.new(t)
	near.at = 100.0
	near.min_alert = 2
	near.note_seen(t, 2, 100.0 - t.trooper_commit_distance + 5.0)  # alert 2, in sight
	_check(near.is_active(1), "a seen alert-2 trooper stays when alert drops to 1")
	var far := RifleTrooper.new(t)
	far.at = 100.0
	far.min_alert = 2
	far.note_seen(t, 2, 100.0 - t.trooper_commit_distance - 20.0)  # alert 2, but not in sight yet
	_check(not far.is_active(1), "an unseen alert-2 trooper goes when alert drops to 1")
	var unseen := RifleTrooper.new(t)
	unseen.at = 100.0
	unseen.min_alert = 2
	unseen.note_seen(t, 1, 95.0)  # close, but never active (alert 1)
	_check(not unseen.is_active(1), "a trooper who was never active doesn't appear by being close")
	for n in [near, far, unseen]:
		n.free()


func _test_chopper_stages() -> void:
	var t := Tuning.new()
	var l := t.chopper_lands_at
	var f := t.chopper_lifts_at
	var gone := t.chopper_gone_at
	_check(ExtractionClock.stage_at(0.0, l, f, gone) == ExtractionClock.Stage.INBOUND, "chopper inbound at the start")
	_check(ExtractionClock.stage_at(l, l, f, gone) == ExtractionClock.Stage.LANDED, "chopper landed on time")
	_check(ExtractionClock.stage_at(f + 0.1, l, f, gone) == ExtractionClock.Stage.LIFTING_OFF, "chopper lifting off")
	_check(ExtractionClock.stage_at(gone, l, f, gone) == ExtractionClock.Stage.GONE, "chopper gone at the end")
	_check(l < f and f < gone, "default chopper stages in order")
	var g := RouteGraph.from_json_file("res://game/levels/prototype_slice/route.json")
	_check(float(g.mission().get("chopper", {}).get("gone_at", 0)) == 68.0, "this mission sets its own chopper time")
	var bad := RouteGraph.from_dict({"start": "a", "chopper": {"lands_at": 30, "lifts_at": 20, "gone_at": 40},
			"nodes": [{"id": "a", "end": "extract"}]})
	_check("chopper times must be" in " ".join(bad.validate()), "a mission's chopper times must be in order")


func _test_trooper_rules() -> void:
	var w := 1.4
	_check(RifleTrooper.shot_hits(0.0, 0.0, false, w), "trooper hits you in the lane he aimed at")
	_check(not RifleTrooper.shot_hits(1.4, 0.0, false, w), "change lane before the shot and he misses")
	_check(RifleTrooper.shot_hits(0.5, 0.0, false, w), "halfway through a lane change you're still hit")
	_check(not RifleTrooper.shot_hits(0.0, 0.0, true, w), "cover blocks the shot")
	# Line of sight is rays against the walls (in play); here, finding the wall you're in cover
	# behind, so your shots lean out round it.
	var walls := [{"at": 20.0, "x0": 1.4, "x1": 4.5}]  # a wall across the two right lanes
	_check(Sightlines.cover_wall(18.6, 2.8, walls) != null, "in cover just behind a wall, that's the wall you lean round")
	_check(Sightlines.cover_wall(18.6, -2.8, walls) == null, "a wall in other lanes isn't yours")
	_check(Sightlines.cover_wall(10.0, 2.8, walls) == null, "not in cover behind a wall 10 m away")
	# The Rusher: dodge out of its lane and it misses; cover doesn't help.
	_check(RusherDog.bites(0.0, 0.0, false, w), "the dog gets you in the lane it's coming down")
	_check(not RusherDog.bites(1.4, 0.0, false, w), "dodge a lane over and it runs past")
	_check(RusherDog.bites(1.4, 0.0, true, w), "in cover it gets round to you anyway")
	var tt := Tuning.new()
	_check(RusherDog.windup_time(tt, 1) > RusherDog.windup_time(tt, 3), "at higher alert the dog barks for less time before charging")
	_check(RusherDog.trigger_distance(tt, 3) > RusherDog.trigger_distance(tt, 1), "at higher alert it notices you further off")
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
	var bad_cover := RouteGraph.from_dict({"start": "a", "nodes": [
		{"id": "a", "length": 50, "end": "extract", "obstacles": [
			{"kind": "wall", "lanes": [0, 1, 2], "at": 10},
			{"kind": "wall", "lanes": [0, 3], "at": 20},
			{"kind": "box", "lanes": [2], "at": 30, "material": "glass"},
			{"kind": "truck", "lanes": [2], "at": 40}]},
	]})
	problems = " ".join(bad_cover.validate())
	_check("wall at 10 m must cover 1 or 2" in problems, "a wall wider than 2 lanes is rejected")
	_check("wall at 20 m must cover 1 or 2" in problems, "a wall across non-neighbouring lanes is rejected")
	_check("box at 30 m must be wood or metal" in problems, "a box must be wood or metal")
	_check("unknown obstacle kind 'truck'" in problems, "trucks are gone")
	var ambush := RouteGraph.from_dict({"start": "a", "nodes": [
		{"id": "a", "length": 80, "end": "extract",
			"obstacles": [{"kind": "wall", "lanes": [3, 4], "at": 20}],
			"enemies": [{"kind": "rifle_trooper", "lane": 4, "at": 28}, {"kind": "rifle_trooper", "lane": 2, "at": 24},
				{"kind": "rifle_trooper", "lane": 3, "at": 50}]},
	]})
	problems = " ".join(ambush.validate())
	_check("trooper at 28 m is hidden right behind the wall" in problems, "no trooper right behind a wall")
	_check(not "trooper at 24 m" in problems, "a trooper in another lane is fine")
	_check(not "trooper at 50 m" in problems, "a trooper well behind a wall is fine")
	var squeeze := RouteGraph.from_dict({"start": "a", "nodes": [
		{"id": "a", "length": 100, "end": "extract", "obstacles": [
			{"kind": "wall", "lanes": [0, 1], "at": 20}, {"kind": "box", "lanes": [2], "at": 21},
			{"kind": "pipe", "lanes": [3, 4], "at": 22},
			{"kind": "wall", "lanes": [0, 1], "at": 50}, {"kind": "barrier", "lanes": [2, 3, 4], "at": 51},
			{"kind": "wall", "lanes": [3, 4], "at": 70}, {"kind": "box", "lanes": [2], "at": 70},
			{"kind": "barrier", "lanes": [0, 1], "at": 80},
			{"kind": "tripwire", "lanes": [0, 1, 2, 3, 4], "at": 73}]},
	]})
	problems = " ".join(squeeze.validate())
	_check("pipe at 22" in problems, "cover on 3 lanes + a pipe in the open lanes is rejected (forced swipe-and-jump)")
	_check(not "barrier at 51" in problems, "cover on only 2 lanes leaves room: a barrier nearby is fine")
	_check(not "barrier at 80" in problems, "a barrier well after the cover is fine")
	_check(not "tripwire" in problems, "a tripwire next to cover is fine (it only raises alert)")
	var stacked := RouteGraph.from_dict({"start": "roof", "nodes": [
		{"id": "roof", "tier": "roof", "next": [{"to": "sewer_straight"}, {"to": "sewer", "side": "left", "via": "stairs"}]},
		{"id": "sewer_straight", "tier": "roof", "end": "extract"},
		{"id": "sewer", "tier": "underground", "end": "extract"},
	]})
	_check("only move one level" in " ".join(stacked.validate()), "no stairs from the roof straight into a tunnel")
	var crowded := RouteGraph.from_dict({"start": "a", "nodes": [
		{"id": "a", "length": 60, "end": "extract",
			"obstacles": [{"kind": "box", "lanes": [2], "at": 20}, {"kind": "barrier", "lanes": [1, 2], "at": 20.8},
				{"kind": "pipe", "lanes": [3], "at": 20.5}],
			"enemies": [{"kind": "rifle_trooper", "lane": 2, "at": 40}, {"kind": "rifle_trooper", "lane": 3, "at": 40.2}]},
	]})
	problems = " ".join(crowded.validate())
	_check("box at 20.0 m overlaps barrier at 20.8 m" in problems, "objects in the same lane can't overlap")
	_check(not "pipe at 20.5" in problems, "objects in different lanes can sit side by side")
	_check(not "trooper at 40.2" in problems, "troopers in different lanes can stand side by side")
	var wired := RouteGraph.from_dict({"start": "a", "nodes": [
		{"id": "a", "theme": "office", "length": 90, "end": "extract", "obstacles": [
			{"kind": "pipe", "lanes": [0, 1, 2, 3, 4], "at": 10},
			{"kind": "pipe", "lanes": [0, 1], "at": 25},
			{"kind": "pipe", "lanes": [1, 2, 3], "at": 40},
			{"kind": "pipe", "lanes": [0, 1, 2, 3], "at": 55},
			{"kind": "pipe", "lanes": [0, 1, 2, 3, 4], "at": 70, "look": "pipe"}]},
	]})
	problems = " ".join(wired.validate())
	_check("live wires at 10 m must span 3 or 4" in problems, "live wires can't cross all 5 lanes")
	_check("live wires at 25 m must span 3 or 4" in problems, "live wires need at least 3 lanes")
	_check(not "at 40 m" in problems and not "at 55 m" in problems, "live wires across 3 or 4 lanes are fine")
	_check(not "at 70 m" in problems, "an ordinary pipe can still cross all 5 lanes")


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
