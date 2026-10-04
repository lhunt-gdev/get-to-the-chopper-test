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
	_test_squad_rules()
	_test_corner_rule()
	_test_searchlights()
	_test_swipe_direction()
	_test_sounds()
	_test_route_map()
	_test_tally()
	_test_snipers()
	await _test_targeting_priority()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		printerr("FAIL: " + msg)


## The post-run route map (LOCKED; design by the user): each area has one place, after every
## way into it; this run's line follows the levels and ends where it ended; areas seen only
## partway aren't drawn whole; and only ways into areas never reached get a lock.
func _test_route_map() -> void:
	var g := RouteGraph.from_json_file("res://game/levels/prototype_slice/route.json")
	var lay := RouteMap.layout(g)
	var placed := true
	var after_all_ways_in := true
	for id: StringName in lay:
		var span: Vector2 = lay[id]
		placed = placed and is_equal_approx(span.y - span.x, g.length_of(id))
		for e in g.all_next(id):
			var to := StringName(e["to"])
			after_all_ways_in = after_all_ways_in and lay[to].x >= span.y - 0.001
	_check(lay.size() == 19 and placed, "route map: every area placed, at its own length (%d areas)" % lay.size())
	_check(after_all_ways_in, "route map: each area starts after every way into it ends")
	_check(is_zero_approx(lay[&"main_floor_lobby"].x), "route map: the start is at the left")
	var run: Array[StringName] = [&"main_floor_lobby", &"rooftops", &"water_towers", &"gantry"]
	var line := RouteMap.run_line(g, lay, run, 40.0, 30.0)
	_check(line[0] == Vector2(0, 0), "route map: the run's line starts at the start, on the main level")
	_check(line[-1].is_equal_approx(Vector2(lay[&"gantry"].x + 40.0, 1)), "route map: it ends 40 m into the gantry, on the roof (%s)" % line[-1])
	var climbs := 0
	for i in range(1, line.size()):
		climbs += int(line[i].y > line[i - 1].y)
		_check(line[i].x >= line[i - 1].x - 0.001, "route map: the line never runs backwards")
	_check(climbs == 1, "route map: one climb, up the stairs to the roof")
	_check(RouteMap.levels_text(g, run) == "MAIN > ROOF", "route map: the route reads MAIN > ROOF")
	# Discovery: how far into each area he's ever got (the gantry only 40 m; he never saw its end).
	var found := {&"main_floor_lobby": 1.0e6, &"rooftops": 1.0e6, &"water_towers": 1.0e6, &"gantry": 40.0}
	var seen := RouteMap.seen_full(g, lay, found)
	_check(not seen.has(&"gantry") and seen.has(&"water_towers"), "route map: an area he's only seen part of isn't counted as seen to its end")
	found[&"gantry"] = 1.0e6
	_check(RouteMap.seen_full(g, lay, found).has(&"gantry"), "route map: ...until he has")
	found[&"gantry"] = 40.0
	var locks := RouteMap.locked_ways(g, seen, found)
	var lock_pairs := locks.map(func(w: Array) -> String: return "%s>%s" % w)
	_check("main_floor_lobby>building_main_floor" in lock_pairs and "rooftops>security_wing" in lock_pairs,
			"route map: locks on the ways not taken (%s)" % [lock_pairs])
	_check(not ("water_towers>gantry" in lock_pairs) and not ("gantry>skylights" in lock_pairs),
			"route map: no lock into an area he reached, nor off one he didn't see the end of")
	# A death on the real stairs (12 m) shows partway along the drawn ones (30 m here); one past them
	# shows past the drawn ones, on the new level.
	var up: Array[StringName] = [&"main_floor_lobby", &"rooftops"]
	var on_stairs := RouteMap.run_line(g, lay, up, 6.0, 30.0, 12.0)
	_check(on_stairs[-1].y > 0.4 and on_stairs[-1].y < 0.6, "route map: halfway up the real stairs is halfway up the drawn ones (%s)" % on_stairs[-1])
	var past := RouteMap.run_line(g, lay, up, 20.0, 30.0, 12.0)
	_check(past[-1].y == 1.0 and past[-1].x > lay[&"rooftops"].x + 30.0, "route map: past the stairs is on the roof, past the drawn stairs (%s)" % past[-1])
	# The end mark moves under the line rather than cover a lock.
	var locks_at: Array[Rect2] = [Rect2(Vector2(98, 86), Vector2(7, 9))]
	_check(RouteMap.end_mark_at(Vector2(100, 100), RouteMap.SKULL, locks_at).y > 100.0, "route map: the skull goes under the line when a lock is above")
	_check(RouteMap.end_mark_at(Vector2(100, 100), RouteMap.SKULL, [] as Array[Rect2]).y < 100.0, "route map: ...and above it otherwise")
	# RunLog records an area as seen to its end once he goes on from it.
	var log: Node = load("res://game/autoload/run_log.gd").new()
	log.begin()
	log.enter_node(&"main_floor_lobby")
	log.enter_node(&"rooftops")
	_check(log.discovered[&"main_floor_lobby"] >= 1.0e6 and is_zero_approx(log.discovered[&"rooftops"]),
			"route map: going on from an area marks it seen to its end; a new one starts at 0 m")
	log.free()
	# The end screen: a tap anywhere but the buttons skips the map and tally (the skip area covers
	# the screen).
	var fe: CanvasLayer = load("res://game/ui/menu/frontend.gd").new()
	root.add_child(fe)
	fe.show_end(&"killed", {"graph": g, "visited": up, "discovered": found, "end_into": 10.0, "time": 9.0})
	var skip_size := Vector2.ZERO
	for c in fe.find_children("*", "Control", true, false):
		if c.get_class() == "Control" and c.mouse_filter == Control.MOUSE_FILTER_STOP and c.get_script() != null and c.has_signal("pressed"):
			skip_size = (c as Control).size
	_check(skip_size == fe.get_viewport().get_visible_rect().size, "end screen: the tap-to-skip area covers the screen (%s)" % skip_size)
	fe.free()


## The Sniper (user design; LOCKED roster: a timed movement threat you dodge): his hit rule, a
## shorter window at ALERT, where he may go, and one go at him: quiet below CAUTION, then following,
## locking and firing, hitting a player who stays and missing one who changes lane.
func _test_snipers() -> void:
	_check(Sniper.shot_hits(0.0, 0.0, false, 1.4) and Sniper.shot_hits(0.6, 0.0, false, 1.4), "sniper: still in the locked lane, hit")
	_check(not Sniper.shot_hits(1.4, 0.0, false, 1.4), "sniper: a lane over, missed")
	_check(not Sniper.shot_hits(0.0, 0.0, true, 1.4), "sniper: in cover, missed (as with the troopers)")
	var tt := Tuning.new()
	_check(Sniper.window_for(3, tt.sniper_window_alert2, tt.sniper_window_alert3) < Sniper.window_for(2, tt.sniper_window_alert2, tt.sniper_window_alert3),
			"sniper: less time to dodge at ALERT")
	_check(is_equal_approx(tt.sniper_track_time, 1.0), "sniper: his laser follows you for a second (user)")
	var probe := Sniper.new(tt)
	_check(not probe.has_method("hit") and not probe.has_method("is_targetable") and not "health" in probe,
			"sniper: can't be shot or killed, only dodged (user; auto-aim and tap-to-target only pick combatants)")
	probe.free()
	# Where he may go.
	var base := {"id": "r", "tier": "roof", "length": 100, "obstacles": [], "searchlights": [], "next": [{"to": "e"}]}
	var rules := {
		"snipers only on the roofs": {"tier": "ground", "snipers": [{"at": 10, "side": "left"}]},
		"only at CAUTION and ALERT": {"snipers": [{"at": 10, "side": "left", "min_alert": 1}]},
		"obstacle at 20": {"snipers": [{"at": 10, "side": "left"}], "obstacles": [{"kind": "box", "lanes": [2], "at": 20}]},
		"too near the searchlight": {"snipers": [{"at": 10, "side": "left"}], "searchlights": [{"at": 40, "side": "right"}]},
		"doesn't finish before": {"snipers": [{"at": 60, "side": "left"}]},
		"too close together": {"length": 200, "snipers": [{"at": 10, "side": "left"}, {"at": 30, "side": "right"}]},
		"a sniper needs \"side\"": {"snipers": [{"at": 10}]},
	}
	for want in rules:
		var n := base.duplicate(true)
		n.merge(rules[want], true)
		var g := RouteGraph.from_dict({"start": "r", "nodes": [n, {"id": "e", "tier": "ground", "length": 30, "end": "extract"}]})
		var problems := " | ".join(g.validate())
		_check(problems.contains(want), "sniper rule '%s' (%s)" % [want, problems])
	# Into a roof by stairs: not on the flight or just off it (the stairs' clear exit).
	var stair_in := {"id": "s", "tier": "ground", "length": 60, "next": [{"to": "e"}, {"to": "r", "side": "left", "via": "stairs"}]}
	for at_m in [10.0, RouteGraph.STAIR_EXIT_CLEAR]:
		var rn := base.duplicate(true)
		rn["snipers"] = [{"at": at_m, "side": "left"}]
		var gs := RouteGraph.from_dict({"start": "s", "nodes": [stair_in, rn, {"id": "e", "tier": "ground", "length": 30, "end": "extract"}]})
		var close := " | ".join(gs.validate()).contains("sniper at %s m is too close to the stairs" % at_m)
		_check(close == (at_m < RouteGraph.STAIR_EXIT_CLEAR), "sniper: %s m into an area reached by stairs is %s" % [at_m, "too close" if at_m < RouteGraph.STAIR_EXIT_CLEAR else "fine"])
	var ok := base.duplicate(true)
	ok["snipers"] = [{"at": 10, "side": "left"}]
	var fine := RouteGraph.from_dict({"start": "r", "nodes": [ok, {"id": "e", "tier": "ground", "length": 30, "end": "extract"}]})
	_check(not " | ".join(fine.validate()).contains("sniper"), "sniper: a good spot passes")
	var real := RouteGraph.from_json_file("res://game/levels/prototype_slice/route.json")
	var count := 0
	for id in [&"water_towers", &"gantry", &"skylights", &"antenna_farm"]:
		count += real.node_data(id).get("snipers", []).size()
	_check(count == 4, "sniper: one in each of the four open roof stretches (%d)" % count)
	# One go at him: a straight road, route_point(d, x, y) = (x, y, -d). Still SNEAKING when you
	# reach his spot, CAUTION 2 m on (within START_LATE): the alert is all that holds him back.
	var road := func(d: float, x: float, y: float) -> Vector3: return Vector3(x, y, -d)
	for dodge in [false, true]:
		var sn := Sniper.new(tt)
		sn.at = 10.0
		root.add_child(sn)
		var d := 0.0
		var x := 0.0
		var shot := Sniper.Shot.NONE
		var quiet := true
		for f in 240:
			d += tt.run_speed / 60.0
			var alert := 1 if d < sn.at + 2.0 else 2
			if dodge and sn.is_locked():
				x = minf(x + tt.lane_change_speed / 60.0, tt.lane_width)
			var r := sn.update(1.0 / 60.0, alert, d, x, false, road)
			if alert == 1 and sn.state != Sniper.State.WAITING:
				quiet = false
			if r != Sniper.Shot.NONE:
				shot = r
				break
		_check(quiet, "sniper: quiet below CAUTION, even at his spot")
		_check(shot == (Sniper.Shot.MISSED if dodge else Sniper.Shot.HIT), "sniper: %s" % ("a lane change in the window, missed" if dodge else "stay in the lane, hit"))
		_check(sn.state == Sniper.State.DONE, "sniper: he fires once")
		sn.free()
	# Never above SNEAKING: he never starts, and he's done once you're past.
	var calm := Sniper.new(tt)
	calm.at = 10.0
	root.add_child(calm)
	var cd := 0.0
	var woke := false
	for f in 240:
		cd += tt.run_speed / 60.0
		if calm.update(1.0 / 60.0, 1, cd, 0.0, false, road) != Sniper.Shot.NONE or calm.state in [Sniper.State.TRACKING, Sniper.State.LOCKED]:
			woke = true
	_check(not woke and calm.state == Sniper.State.DONE, "sniper: never at SNEAKING (user: CAUTION and up)")
	calm.free()
	# The laser follows you for a second: a lane change while it's following doesn't shake it (it
	# lags, then catches up); it locks a second in, squarely on a lane, and fires the window later
	# (shorter at ALERT).
	for alert in [2, 3]:
		var sn := Sniper.new(tt)
		sn.at = 10.0
		root.add_child(sn)
		var d := 0.0
		var x := 0.0
		var t_track := -1
		var t_lock := -1
		var t_shot := -1
		var lagged := false
		var shot := Sniper.Shot.NONE
		for f in 240:
			d += tt.run_speed / 60.0
			if t_track >= 0 and f - t_track >= 18:
				x = minf(x + tt.lane_change_speed / 60.0, tt.lane_width)
			var r := sn.update(1.0 / 60.0, alert, d, x, false, road)
			if sn.is_tracking():
				if t_track < 0:
					t_track = f
				lagged = lagged or absf(sn.aim_x - x) > 0.05
			if sn.is_locked() and t_lock < 0:
				t_lock = f
			if r != Sniper.Shot.NONE:
				t_shot = f
				shot = r
				break
		var win := Sniper.window_for(alert, tt.sniper_window_alert2, tt.sniper_window_alert3)
		_check(lagged and is_equal_approx(sn.locked_x, tt.lane_width) and shot == Sniper.Shot.HIT,
				"sniper (alert %d): his laser follows you; a lane change while it's following doesn't shake it (user)" % alert)
		_check(absi((t_lock - t_track) - roundi(tt.sniper_track_time * 60.0)) <= 1, "sniper (alert %d): it locks after a second of following (%d frames)" % [alert, t_lock - t_track])
		_check(absi((t_shot - t_lock) - roundi(win * 60.0)) <= 1, "sniper (alert %d): he fires %.2f s after the lock (%d frames)" % [alert, win, t_shot - t_lock])
		sn.free()
	_check(is_equal_approx(Sniper.lane_centre(1.05, 1.4, 5), 1.4) and is_equal_approx(Sniper.lane_centre(0.58, 1.4, 5), 0.0) and is_equal_approx(Sniper.lane_centre(9.0, 1.4, 5), 2.8),
			"sniper: the lock lands squarely on a lane")


## The end screen's tally (user, after DOS Doom): plain counts only, the chopper's spare time only
## when he got out, and the numbers counting up to their totals.
func _test_tally() -> void:
	var stats := {"time": 61.2, "spare": 9.0, "downed": 4, "hits": 2, "run_into": 15, "alarms_set_off": 1,
			"alarms_stopped": 0, "top_alert": 2, "levels": "MAIN > BELOW", "new_areas": 3}
	var rows := Tally.rows_for(stats)
	_check(rows.size() == 10 and rows[1][0] == "CHOPPER TO SPARE", "tally: ten rows, with the chopper's spare time when he got out")
	stats["spare"] = -1.0
	_check(Tally.rows_for(stats).size() == 9, "tally: no spare time when he didn't")
	var texts := []
	for row in rows:
		texts.append(Tally.value_text(row, Tally.steps_of(row), Tally.steps_of(row)))
	_check(texts == ["1:01.2", "0:09", "4", "2", "15", "1", "0", "CAUTION", "MAIN > BELOW", "3"], "tally: final values (%s)" % [texts])
	_check(not ("%s" % [texts]).contains(" OF "), "tally: plain counts, no 'of N' totals (user)")
	_check(Tally.steps_of(rows[4]) == Tally.MAX_STEPS and Tally.value_text(rows[4], 6, 12) in ["7", "8"], "tally: a big count counts up in at most a dozen steps")
	_check(Tally.steps_of(rows[7]) == 0, "tally: a word lands at once")
	_check(Tally.value_text(["TIME", "time", 119.97, UiKit.PAPER], 10, 10) == "2:00.0", "tally: 1:59.97 reads 2:00.0, not 1:60.0")
	# The longest route through the levels fits beside its label (squeezed if it must be).
	var g := RouteGraph.from_json_file("res://game/levels/prototype_slice/route.json")
	var longest: Array[StringName] = [&"main_floor_lobby", &"rooftops", &"security_wing", &"staff_canteen", &"warehouse", &"pump_station", &"storm_drain", &"helipad"]
	var route := Tally.fit_value("ROUTE", RouteMap.levels_text(g, longest), 222.0)
	var f := UiKit.font()
	_check(route == "MAIN>ROOF>MAIN>BELOW>MAIN" and f.get_string_size("ROUTE", HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x + 6.0 + f.get_string_size(route, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x <= 222.0,
			"tally: the longest route fits beside ROUTE (%s)" % route)
	_check(Tally.fit_value("ROUTE", "MAIN > ROOF", 222.0) == "MAIN > ROOF", "tally: a short route keeps its spaces")


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
	_check("box at 46" in problems and "rifle_trooper at 53" in problems, "nothing right by a zone door")
	_check("box at 65" in problems, "nothing too soon after a zone door (you burst through blind)")
	_check(not "box at 72" in problems, "things further on after a zone door are fine")
	_check("no zone doors on open roofs" in problems, "no zone door on the rooftops")
	var g := RouteGraph.from_json_file("res://game/levels/prototype_slice/route.json")
	_check(g.display_name(&"roof_edge") == "ROOF EDGE", "an area with no name of its own shows its id as a name")
	var run_log: Node = root.get_node_or_null("RunLog")  # an autoload; not a global name in -s scripts
	if run_log == null:
		_check(false, "RunLog autoload is available")
		return
	run_log.begin()
	run_log.enter_node(&"rooftops", g.display_name(&"rooftops"))
	run_log.enter_node(&"rooftops_2", "ROOFTOPS")  # a second stretch with the same name
	run_log.enter_node(&"helipad", g.display_name(&"helipad"))
	_check(run_log.route_summary() == "ROOFTOPS > HELIPAD", "two stretches of rooftops show once: %s" % run_log.route_summary())


## Alert tiers (user direction): Alert 1 is sparse (at most 2 rifle guards a section, some with
## none), Alert 2 has more, Alert 3 no fewer; dogs only from Alert 2; one alarm runner, Alert 1 only.
func _test_trooper_tiers() -> void:
	var g := RouteGraph.from_json_file("res://game/levels/prototype_slice/route.json")
	var empty_at_1 := 0
	var runners := 0
	# Per height: obstacles per metre and rifle guards at Alert 2, summed over its areas.
	var density := {"ground": [0, 0.0, 0], "roof": [0, 0.0, 0], "underground": [0, 0.0, 0]}
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://game/levels/prototype_slice/route.json"))
	for node in data["nodes"]:
		var id := StringName(node["id"])
		if g.end_type(id) != "":
			continue
		var tier := String(node.get("tier", "ground"))
		density[tier][0] += node.get("obstacles", []).size()
		density[tier][1] += float(node.get("length", 50))
		var counts := [0, 0, 0]
		for e in node.get("enemies", []):
			match String(e.get("kind", "")):
				"rifle_trooper":
					for alert in [1, 2, 3]:
						if alert >= int(e.get("min_alert", 1)) and alert <= int(e.get("max_alert", 3)):
							counts[alert - 1] += 1
				"rusher_dog":
					_check(int(e.get("min_alert", 1)) >= 2, "%s: dogs only from Alert 2" % id)
				"security_trooper":
					runners += 1
					_check(int(e.get("max_alert", 3)) == 1, "%s: the alarm runner is Alert 1 only" % id)
		density[tier][2] += counts[1]
		if tier == "underground":
			_check(counts == [0, 0, 0], "%s: no guards underground (%s)" % [id, counts])
			# No lane is safe to stay in (user): every lane is blocked by a crate at least twice.
			var blocked := [0, 0, 0, 0, 0]
			for ob in node.get("obstacles", []):
				if String(ob.get("kind", "")) in ["box", "wall"]:
					for l in ob.get("lanes", []):
						blocked[int(l)] += 1
			_check(blocked.min() >= 2, "%s: every lane blocked by a crate at least twice, so you have to switch (%s)" % [id, blocked])
			continue
		# Alert 1 is sparse on the ground; the roofs have a few more guards at every level (user).
		var a1_ok: bool = counts[0] >= 3 and counts[0] <= 4 if tier == "roof" else counts[0] <= 2
		_check(a1_ok and counts[0] < counts[1] and counts[1] <= counts[2],
				"%s: Alert 1 %s, more at 2, no fewer at 3 (%s)" % [id, "3-4 on the roofs" if tier == "roof" else "sparse", counts])
		if counts[0] == 0:
			empty_at_1 += 1
	_check(empty_at_1 >= 1, "some sections have no guards at Alert 1")
	# Each height's character (user): underground more obstacles than ground, roofs far fewer;
	# roofs more guards than ground.
	var per_m := func(t: String) -> float: return density[t][0] / maxf(density[t][1], 1.0)
	var guards_per_m := func(t: String) -> float: return density[t][2] / maxf(density[t][1], 1.0)
	_check(per_m.call("underground") > per_m.call("ground"), "more obstacles underground than on the ground (%.3f vs %.3f a metre)" % [per_m.call("underground"), per_m.call("ground")])
	_check(per_m.call("roof") < per_m.call("ground") * 0.5, "far fewer obstacles on the roofs (%.3f vs %.3f a metre)" % [per_m.call("roof"), per_m.call("ground")])
	_check(guards_per_m.call("roof") > guards_per_m.call("ground"), "more guards on the roofs than the ground (%.3f vs %.3f a metre at Alert 2)" % [guards_per_m.call("roof"), guards_per_m.call("ground")])
	_check(runners == 1, "one alarm runner per run (%d)" % runners)
	# How far he's got: 0 where he set off, 1 at the alarm.
	_check(SecurityTrooper.run_progress(100.0, 330.0, 100.0) == 0.0, "the runner starts at 0")
	_check(is_equal_approx(SecurityTrooper.run_progress(100.0, 330.0, 215.0), 0.5), "halfway to his alarm is 0.5")
	_check(SecurityTrooper.run_progress(100.0, 330.0, 400.0) == 1.0, "at the alarm is 1")
	var tt := Tuning.new()
	_check(tt.security_speed < tt.run_speed and tt.security_speed > tt.run_speed * 0.85, "the runner is a little slower than you: you slowly close in")
	_check(tt.security_trigger_distance > tt.target_range, "he spots you from further off than you can shoot")
	_check(tt.security_alarm_distance >= 200.0, "he runs for a couple of sections, not just across the corridor")
	var sec := SecurityTrooper.new(tt)
	_check(sec.get_threat_priority() == 0, "a runner standing still isn't urgent")
	sec.state = SecurityTrooper.State.RUN
	_check(sec.get_threat_priority() > 60, "a running runner is shot before a charging dog or an aiming trooper")
	sec.free()


## The Alert 3 pursuit squad: each guard runs into cover in his own lane (and only his), and
## the squad catches you when one gets within reach. They start well back, out of reach.
func _test_squad_rules() -> void:
	var w := 1.4
	_check(PursuitGuard.runs_into(49.0, 49.7, 1.4, 50.0, 1.4, w), "a squad guard runs into cover in his lane")
	_check(not PursuitGuard.runs_into(49.0, 49.7, 0.0, 50.0, 1.4, w), "cover in the next lane doesn't stop him")
	_check(not PursuitGuard.runs_into(40.0, 40.2, 1.4, 50.0, 1.4, w), "cover further on hasn't been reached yet")
	_check(not PursuitGuard.runs_into(52.0, 52.2, 1.4, 50.0, 1.4, w), "cover he's already past is behind him")
	_check(PursuitGuard.catches(99.0, 100.0, 1.2), "one of them right behind you has caught you")
	_check(not PursuitGuard.catches(90.0, 100.0, 1.2), "10 m back hasn't")
	var tt := Tuning.new()
	_check(tt.squad_start_gap > tt.squad_catch_distance + 20.0, "the squad starts well back: run clean and they never get you")
	# Each guard decides once per obstacle whether he gets it right (a swerve, a jump, a slide).
	var pg := PursuitGuard.new(tt)
	pg.set_seed(42)
	var first := pg.spots("t50.0:1.4", 0.5)
	_check(pg.spots("t50.0:1.4", 0.5) == first, "a squad guard's timing on one obstacle doesn't change his mind halfway")
	_check(pg.spots("never", 0.0) == false and pg.spots("always", 1.0) == true, "timing chance 0 always fails, 1 always clears")
	_check(tt.squad_timing_chance > 0.5 and tt.squad_timing_chance < 1.0, "they mostly time jumps and slides right, but not always")
	pg.free()

## The user's corner rule: no cover wall on the inside of a corner (a bend has two: it turns
## toward its side, then back after RouteGraph.BEND_RUN m).
func _test_corner_rule() -> void:
	var make := func(walls: Array) -> String:
		var obstacles: Array = []
		for w in walls:
			obstacles.append({"kind": "wall", "lanes": w[1], "at": w[0]})
		var g := RouteGraph.from_dict({"start": "a", "nodes": [
			{"id": "a", "tier": "ground", "length": 120, "bends": [{"at": 50, "side": "left"}], "obstacles": obstacles,
				"next": [{"to": "b"}]},
			{"id": "b", "tier": "ground", "end": "extract"}]})
		return " ".join(g.validate())
	_check("inside of the corner" in make.call([[44, [0, 1]]]), "a wall in the left lanes just before a left-hand corner is rejected")
	_check(not "inside of the corner" in make.call([[44, [3, 4]]]), "on the outside of that corner it's fine")
	_check("inside of the corner" in make.call([[60, [3, 4]]]), "the bend's second corner turns back: its inside is the right")
	_check(not "inside of the corner" in make.call([[30, [0, 1]]]), "well before the corner it's fine")
	_check(not "inside of the corner" in make.call([[90, [0, 1]]]), "well after it, too")

## Roof searchlights (user): the pool sweeps over every lane, catches you only when you're in it,
## and they go only on the roofs.
func _test_searchlights() -> void:
	var lo := INF
	var hi := -INF
	for i in 68:
		var px := Searchlight.pool_x(i * Searchlight.PERIOD / 68.0, 0.0)
		lo = minf(lo, px)
		hi = maxf(hi, px)
	_check(lo <= -2.7 and hi >= 2.7, "a searchlight's pool sweeps from the outer lane to the outer lane")
	_check(Searchlight.in_pool(100.0, 1.4, 100.5, 1.0), "in the pool: spotted")
	_check(not Searchlight.in_pool(100.0, -1.4, 100.5, 1.0), "a lane away from the pool: not spotted")
	_check(not Searchlight.in_pool(95.0, 1.0, 100.5, 1.0), "the pool still ahead of you: not yet")
	var g := RouteGraph.from_dict({"start": "a", "nodes": [
		{"id": "a", "tier": "ground", "length": 100, "searchlights": [{"at": 50, "side": "left"}], "next": [{"to": "b"}]},
		{"id": "b", "tier": "ground", "end": "extract"}]})
	_check("searchlights only on the roofs" in " ".join(g.validate()), "no searchlights indoors")
	var real := RouteGraph.from_json_file("res://game/levels/prototype_slice/route.json")
	var lit := 0
	for id in [&"rooftops", &"water_towers", &"gantry", &"skylights", &"antenna_farm", &"roof_edge"]:
		if not real.node_data(id).get("searchlights", []).is_empty():
			lit += 1
	_check(lit == 6, "every roof area has a searchlight (%d of 6)" % lit)

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
	_check(float(g.mission().get("chopper", {}).get("gone_at", 0)) == 114.0, "this mission sets its own chopper time (scaled for the ~90 s level)")
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
