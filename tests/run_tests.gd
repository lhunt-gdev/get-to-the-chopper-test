extends SceneTree
## Minimal dependency-free test runner. Run headless:
##   godot --headless --path . -s res://tests/run_tests.gd
## Exits with code 1 if any check fails (CI blocks the deploy).

## Mission 1, COLD CALL (the level the game plays), and the TEST RANGE (the full 19-area level from
## before mission 1, kept for the bots and the tests of what mission 1 leaves out).
const MISSION_1 := "res://game/levels/prototype_slice/route.json"
const TEST_RANGE := "res://tests/fixtures/test_range.json"

var _failures := 0
var _checks := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame  # let the root viewport enter the tree
	_test_route_json_is_valid()
	_test_alert_gating()
	_test_door_cues()
	_test_pick_edge()
	_test_route_rules()
	_test_stair_exit_clear()
	_test_fair_reaction()
	_test_trooper_rules()
	_test_chopper_stages()
	_test_seen_troopers_stay()
	_test_mission_layout()
	_test_trooper_tiers()
	_test_runner_doors()
	_test_squad_rules()
	_test_corner_rule()
	_test_searchlights()
	_test_swipe_direction()
	_test_sounds()
	await _test_sound_turns()
	_test_menu_music_pace()
	_test_texture_makers()
	_test_route_map()
	_test_mission_1()
	_test_cover_exit_rule()
	_test_settings()
	_test_unlock_rule()
	_test_progress_save()
	_test_best_times()
	_test_auto_save()
	_test_save_file()
	await _test_mission_select()
	_test_tally()
	_test_snipers()
	_test_boss()
	_test_boss_ko()
	_test_cross_death()
	_test_end_typing()
	_test_briefing()
	_test_end_talk()
	_test_cross_ready()
	_test_cross_eased()
	_test_intro_camera()
	_test_start_room()
	_test_cutout()
	_test_lamp_slots()
	_test_lamp_views()
	_test_hanging()
	await _test_locked_doors()
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
	var g := RouteGraph.from_json_file(TEST_RANGE)  # (the 19-area layout: every kind of way)
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


## The boss at the chopper (user design): his minigun always leaves 2 random lanes free; its rounds
## fan out from the tip of the gun, never into a free lane, and one that reaches you is a hit (once
## an attack); alert shortens the spin-up; a new pattern for a new seed; the flash lights up; the
## cases pile up on the deck; his stance has his feet planted; he's down after boss_health hits.
func _test_boss() -> void:
	var tt := Tuning.new()
	var pairs := {}
	var ok := true
	for i in 5:
		for j in 4:
			var f := Boss.pick_free_lanes((i + 0.5) / 5.0, (j + 0.5) / 4.0, 5)
			ok = ok and f.size() == 2 and f[0] != f[1] and f[0] >= 0 and f[0] <= 4 and f[1] >= 0 and f[1] <= 4
			pairs["%d%d" % [mini(f[0], f[1]), maxi(f[0], f[1])]] = true
	_check(ok, "boss: always 2 different free lanes (user)")
	_check(pairs.size() == 10, "boss: any 2 of the 5 lanes can be the free ones")
	_check(Boss.pick_free_lanes(0.0, 0.0, 5) == [0, 1] and Boss.pick_free_lanes(0.999, 0.999, 5).max() <= 4, "boss: free lanes at the ends")
	var free: Array[int] = [1, 3]
	var rad := tt.boss_round_hit_radius
	_check(Boss.round_hits(0.3, 0.0, 0.0, rad) and not Boss.round_hits(0.5, 0.0, 0.0, rad),
			"boss: a round reaching you near you, hit; one further off, not")
	_check(Boss.round_hits(0.6, 1.4, 0.0, rad), "boss: stepping across where a round reaches, hit")
	_check(not Boss.round_hits(-0.6, 1.4, 0.0, rad), "boss: stepping toward a round but not to it, not hit")
	var clean := true
	var x_try := -4.0
	while x_try <= 4.0:
		if Boss.fires_at(x_try, free, tt.lane_width, tt.lane_count):
			for l in free:
				clean = clean and absf(x_try - (l - 2) * tt.lane_width) >= tt.lane_width * 0.5 - 0.001
		x_try += 0.01
	_check(clean and rad < tt.lane_width * 0.5 - 0.1,
			"boss: he never fires into a free lane, so standing in one no round comes near you (user: 2 lanes always free)")
	_check(Boss.lane_of(0.69, 1.4, 5) == 2 and Boss.lane_of(0.71, 1.4, 5) == 3 and Boss.lane_of(9.0, 1.4, 5) == 4, "boss: you're in the nearest lane")
	var times := [tt.boss_spinup_alert1, tt.boss_spinup_alert2, tt.boss_spinup_alert3]
	_check(Boss.spinup_for(1, times) > Boss.spinup_for(2, times) and Boss.spinup_for(2, times) > Boss.spinup_for(3, times),
			"boss: less warning at higher alert (LOCKED: alert changes the pressure)")
	# A new pattern every run (user: "2 random lanes"): the first attacks differ between seeds.
	var patterns := {}
	for sd in 8:
		var b := Boss.new(tt)
		b.set_seed(sd * 7919 + 1)
		var p := ""
		for k in 4:
			b._spin_up(1)
			p += "%d%d%d" % [b.free_lanes[0], b.free_lanes[1], b.sweep_dir]
		patterns[p] = true
		b.free()
	_check(patterns.size() >= 6, "boss: a different pattern for a different seed (%d of 8)" % patterns.size())
	# A fight on a straight road: in a free lane every spin-up, never hit; standing in a swept lane,
	# hit once a sweep (its rounds reach you once). He stands on the road at 20 m, facing you.
	var road := func(d: float, x: float, y: float) -> Vector3: return Vector3(x, y, -d)
	for dodge in [true, false]:
		var boss := Boss.new(tt)
		boss.at = 20.0
		boss.set_seed(3)
		root.add_child(boss)
		boss.global_transform = Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, -20.0))
		var spread := 0.0
		var gaps_clean := true
		var lit := false
		var flash_wrong := false
		var muzzle_ok := true
		_check(not boss.is_targetable(1), "boss: not a target till the fight starts")
		boss.begin(1)
		_check(boss.is_targetable(1), "boss: a target once it's on")
		var hits := 0
		var sweeps := 0
		var x := 0.0
		var was := boss.state
		for f in roundi(60.0 * 3.0 * (tt.boss_spinup_alert1 + tt.boss_sweep_time + tt.boss_spindown_time)):
			if boss.state == Boss.State.SPINUP:
				var stay := 2 if not boss.free_lanes.has(2) else (0 if not boss.free_lanes.has(0) else 1)
				x = boss.lane_x(boss.free_lanes[0] if dodge else stay)
			var fired_before := boss._round_next
			if boss.update(1.0 / 60.0, 1, 20.0 - tt.boss_standoff, x, road):
				hits += 1
			if was == Boss.State.SWEEP and boss.state != Boss.State.SWEEP:
				sweeps += 1
			was = boss.state
			lit = lit or boss.flash_lamp.visible
			# (the rig still says firing for the frame the sweep ends on, after the flash is put out)
			flash_wrong = flash_wrong or boss.flash_lamp.visible != (boss.state == Boss.State.SWEEP and boss._rig.is_firing())
			# The rounds in the air: fired from the tip of the gun, spread across the lanes (the fan),
			# never toward a free lane's middle.
			if boss._round_next != fired_before:
				var newest: Dictionary = boss._rounds[(boss._round_next + Boss.MAX_ROUNDS - 1) % Boss.MAX_ROUNDS]
				muzzle_ok = muzzle_ok and (newest["from"] as Vector3).distance_to(boss._rig.muzzle_position()) < 0.05
			var lo := INF
			var hi := -INF
			for r: Dictionary in boss._rounds:
				if r["live"]:
					lo = minf(lo, r["x"])
					hi = maxf(hi, r["x"])
					for l in boss.free_lanes:
						gaps_clean = gaps_clean and absf(float(r["x"]) - boss.lane_x(l)) >= tt.lane_width * 0.5 - 0.001
			if hi > lo:
				spread = maxf(spread, hi - lo)
		_check(sweeps == 3, "boss: three attacks in three cycles' time (%d)" % sweeps)
		if dodge:
			_check(hits == 0, "boss: dodging into a free lane each time, never hit (%d)" % hits)
			_check(muzzle_ok, "boss: every round leaves from the tip of his gun (user)")
			_check(spread > 2.5, "boss: the rounds in the air fan out across the lanes as he sweeps (%.1f m)" % spread)
			_check(gaps_clean, "boss: no round in the fan heads for a free lane (the gaps where it reaches you)")
			_check(lit and not flash_wrong, "boss: the gun's flash is lit while it fires and dark otherwise (user)")
			var down := 0
			for c: Dictionary in boss._cases:
				if c["live"] and c["resting"] and absf((c["pos"] as Vector3).y - Boss.CASE_SIZE.y * 0.5) < 0.001:
					down += 1
			_check(boss.cases_out() > 40 and down > 20, "boss: the cases fly out and lie on the deck (%d out, %d down) (user)" % [boss.cases_out(), down])
		else:
			_check(hits == 3, "boss: standing in a swept lane, hit once a sweep (%d)" % hits)
		var downs := [0]
		boss.defeated.connect(func() -> void: downs[0] += 1)
		for i in tt.boss_health - 1:
			boss.hit()
		_check(boss.is_alive(), "boss: still up one hit short")
		boss.hit()
		boss.hit()
		_check(not boss.is_alive() and not boss.is_targetable(1) and downs[0] == 1, "boss: down after %d hits, once" % tt.boss_health)
		boss.queue_free()
	# The flash lights him in a lamp slot of its own: never one of the 12 nearest level lamps put out
	# (they stay as they were), lit as brightly as its flicker says, however far from the focus.
	var amb := Ambience.new()
	amb.tuning = tt
	root.add_child(amb)
	var view_cam := Camera3D.new()  # looking at them from 8 m off (its focus on them)
	root.add_child(view_cam)
	view_cam.position = Vector3(0.0, 0.0, Ambience.FOCUS_AHEAD)
	var near_lamps: Array[Node3D] = []
	for i in Ambience.SLOTS:
		var n := Node3D.new()
		root.add_child(n)
		n.position = Vector3(i * 0.1, 1.0, 0.0)
		amb.add_lamp(n, Color.WHITE, 5.0, {"alert": false})
		near_lamps.append(n)
	var flash_boss := Boss.new(tt)
	root.add_child(flash_boss)
	amb.add_lamp(flash_boss.flash_lamp, Color.ORANGE, 8.0, {"alert": false, "second_slot": true})
	flash_boss.flash_lamp.global_position = Vector3(0, 1, -100)
	amb.update(1.0 / 60.0, view_cam, 1)
	var before := amb.slot_nodes.slice(0, Ambience.SLOTS)
	flash_boss.flash_lamp.visible = true
	flash_boss.flash_lamp.set_meta("power", 0.7)
	amb.update(1.0 / 60.0, view_cam, 1)
	_check(amb.slot_nodes.slice(0, Ambience.SLOTS) == before and before.all(func(x) -> bool: return x != null)
			and amb.slot_nodes[Ambience.SLOTS + 1] == flash_boss.flash_lamp and is_equal_approx(amb.slot_lit[Ambience.SLOTS + 1], 0.7),
			"boss: his flash lights in a slot of its own, no level lamp put out (user)")
	flash_boss.flash_lamp.visible = false
	amb.update(1.0 / 60.0, view_cam, 1)
	_check(amb.slot_nodes[Ambience.SLOTS + 1] == null, "boss: his flash's slot is dark when it's out")
	for n in near_lamps:
		n.queue_free()
	flash_boss.queue_free()
	amb.queue_free()
	view_cam.queue_free()
	# His stance (user: "a cool action ready stance"): down low, both feet planted where they go, flat
	# on the deck, and still planted as he turns to sweep.
	var rig := GuardRig.new(GuardRifle.Kind.MINIGUN, Boss.MODEL, "BOSS")
	root.add_child(rig)
	var planted := true
	var flat := true
	for aim_x in [0.0, -4.0, 4.0]:
		for f in 30:
			rig.animate(1.0 / 30.0, {"brace": true, "aim": true, "spin": 1.0, "target": rig.global_transform * Vector3(aim_x, 1.0, -14.0)})
		for side in [-1, 1]:
			var foot: Vector2 = GuardRig.BRACE_FEET[side]
			var at := rig._in_rig(rig.ankles[side]).origin
			planted = planted and at.distance_to(Vector3(foot.x, (rig._ankle_rest[side] as Vector3).y, foot.y)) < 0.01
			var sole := rig._in_rig(rig.ankles[side].get_node(String(rig.ankles[side].name) + "Flat"))
			flat = flat and sole.basis.orthonormalized().y.dot(Vector3.UP) > 0.999
	_check(planted and flat, "boss: braced, his feet stay planted and flat as he turns")
	_check(rig.hips.position.y < rig._hip_y - GuardRig.BRACE_DROP + 0.02, "boss: braced, he's down low")
	rig.queue_free()


## The boss's KO replay (user: Tekken-style): his death is the same at the same moment however often
## it's shown; he drops the minigun, twists round twice in the air, lands face up a couple of metres
## back in one pool of blood, the gun in front of where he stood, clear of the lane you run past in;
## and the three shots: slowed, each a different angle, each with him in view on a tall phone, the
## camera under the chopper's rotor, short enough (about 9 s), skippable.
func _test_boss_ko() -> void:
	var tt := Tuning.new()
	var boss := Boss.new(tt)
	root.add_child(boss)
	boss.global_transform = Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, -20.0))
	for f in 20:
		boss._rig.animate(0.05, boss._stance())
	var downs := [0]
	boss.defeated.connect(func() -> void: downs[0] += 1)
	for i in tt.boss_health:
		boss.hit()
	_check(boss.death_t == 0.0 and downs[0] == 1, "boss KO: killed, his death starts (once)")
	# Killed between sweeps (barrels still), they stay still: they spin down from how fast they were.
	var barrels_still := boss._rig._barrels.rotation.z
	boss.replay_death(0.6)
	_check(is_equal_approx(boss._rig._barrels.rotation.z, barrels_still), "boss KO: killed with his barrels still, they don't start spinning")
	# The same moment, the same pose: shown, run on, wound back.
	var pose_at := func(t: float) -> Array:
		boss.replay_death(t)
		var out := [boss._rig.hips.position]
		for j in boss._rig._all_joints():
			out.append(j.quaternion)
		out.append(boss._rig.rifle.transform)
		return out
	var first: Array = pose_at.call(0.5)
	pose_at.call(1.7)
	var again: Array = pose_at.call(0.5)
	var same := first.size() == again.size()
	for i in first.size():
		same = same and (str(first[i]) == str(again[i]))
	_check(same, "boss KO: his death at the same moment is the same pose, replayed (user: 3 angles)")
	# Through it: the turns about himself, and how he ends.
	var face_down := 0
	var was_up := 1.0
	var t := 0.0
	while t <= Boss.DEATH_END:
		boss.replay_death(t)
		var up := (-boss._rig.chest.global_transform.basis.z.normalized()).y
		if was_up > 0.0 and up < 0.0:
			face_down += 1
		was_up = up
		t += 1.0 / 120.0
	var hips := boss.body_point()
	# Nothing through the deck on the way (his limbs as he twists low; the gun's barrels as it lands).
	# Also, like a ragdoll (user): no joint flips round from one moment to the next, his waist never
	# wrings round, and once he's down he settles still.
	var lowest := INF
	var gun_lowest := INF
	var lowest_at := ""
	var names := ["elbow L", "wrist L", "fingers L", "elbow R", "wrist R", "fingers R", "knee L", "ankle L", "toe L", "knee R", "ankle R", "toe R", "skull"]
	var worst_step := 0.0
	var worst_waist := 0.0
	var was_q: Array = []
	var lying_from: Array = []
	var lying_moved := 0.0
	t = 0.0
	while t <= Boss.DEATH_END:
		boss.replay_death(t)
		var r: GuardRig = boss._rig
		var pts: Array = r._rag_points()
		for i in pts.size():
			var y := boss.to_local(r.global_transform * (pts[i] as Vector3)).y
			if y < lowest:
				lowest = y
				lowest_at = "%s at %.2f" % [names[i], t]
		gun_lowest = minf(gun_lowest, minf(boss.to_local(r.muzzle_position()).y, boss.to_local(r.rifle.global_position).y))
		var qs: Array = []
		for j in r._all_joints():
			qs.append(j.quaternion)
		if t > 0.02 and not was_q.is_empty():
			for k in qs.size():
				worst_step = maxf(worst_step, (was_q[k] as Quaternion).angle_to(qs[k]))
		was_q = qs
		worst_waist = maxf(worst_waist, r.spine.quaternion.get_angle())
		if t >= 1.8:
			var here: Array = []
			for i in pts.size():
				here.append(r.global_transform * (pts[i] as Vector3))
			if lying_from.is_empty():
				lying_from = here
			for i in here.size():
				lying_moved = maxf(lying_moved, (here[i] as Vector3).distance_to(lying_from[i]))
		t += 1.0 / 120.0
	boss.replay_death(Boss.DEATH_END)
	_check(lowest > -0.03, "boss KO: none of him goes through the deck, toes, fingertips and skull too (%.2f m, %s)" % [lowest, lowest_at])
	_check(worst_step < 1.2, "boss KO: no joint flips round from one moment to the next (%.2f rad in 1/120 s)" % worst_step)
	_check(worst_waist < 1.1, "boss KO: his waist bends but never wrings round (%.2f rad)" % worst_waist)
	_check(lying_moved < 0.08, "boss KO: down, he settles still (%.2f m)" % lying_moved)
	_check(gun_lowest > -0.02, "boss KO: the minigun lands on the deck, not through it (%.2f m)" % gun_lowest)
	var hands_down: bool = boss.to_local(boss._rig.wrists[-1].global_position).y < 0.2 and boss.to_local(boss._rig.wrists[1].global_position).y < 0.2
	_check(hands_down, "boss KO: lying dead, his hands lie on the deck")
	hips = boss.body_point()
	_check(face_down == 2, "boss KO: he twists round twice in the air (user: 'one or twice') (%d)" % face_down)
	_check(was_up > 0.9 and hips.y < 0.4 and hips.z > 1.6, "boss KO: he lands face up (user), on the deck, blasted back (%.2f up, at %s)" % [was_up, hips])
	var gun := boss.to_local(boss._rig.rifle.global_position)
	var muzzle := boss.to_local(boss._rig.muzzle_position())
	_check(gun.y < 0.3 and muzzle.y < 0.3 and gun.z < 0.0 and absf(muzzle.x) < 1.4 - 0.45 and absf(gun.x) < 1.4 - 0.45,
			"boss KO: the minigun's dropped, on the deck in front of where he stood, clear of the lane you run past in (%s, %s)" % [gun, muzzle])
	var pools := 0
	for c in boss.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).material_override is ShaderMaterial \
				and ((c as MeshInstance3D).material_override as ShaderMaterial).shader == Blood.POOL_SHADER:
			pools += 1
	boss.replay_death(0.0)
	boss.finish_death()
	_check(pools == 1 and downs[0] == 1, "boss KO: one pool of blood and one death, however often it's replayed")
	# The shots: slowed, three angles, him in view on a tall phone (270x585, between the cinema bars),
	# under the rotor; the gun's landing in view in at least one, his hands as he lies in the last.
	var plan := KoReplay.shots(tt)
	var total := 0.0
	var in_view := true
	var under_rotor := true
	var slowed := true
	var angles: Array[float] = []
	var gun_seen := false
	var bars := 1.0 - 2.0 * 44.0 / 585.0  # (the cinema bars, Hud.LETTERBOX)
	var seen := func(cam: Transform3D, fov: float, p: Vector3) -> bool:
		var half_v := tan(deg_to_rad(fov) / 2.0)
		var c := cam.affine_inverse() * p
		return c.z < 0.0 and absf(c.x / -c.z) <= half_v * 270.0 / 585.0 and absf(c.y / -c.z) <= half_v * bars
	for si in plan.size():
		var shot: Dictionary = plan[si]
		total += KoReplay.length(shot)
		slowed = slowed and float(shot["scale"]) < 1.0
		var fov := float(shot["fov"])
		for u in [0.0, 0.25, 0.5, 0.75, 1.0]:
			boss.replay_death(lerpf(float(shot["from"]), float(shot["to"]), u))
			var cam := KoReplay.camera(shot, u, boss.body_point())
			under_rotor = under_rotor and cam.origin.y < 3.7
			for p: Vector3 in [boss.to_local(boss._rig.chest.global_position), boss.body_point()]:
				in_view = in_view and seen.call(cam, fov, p)
			if si == plan.size() - 1 and u == 1.0:
				for w in [-1, 1]:
					in_view = in_view and seen.call(cam, fov, boss.to_local(boss._rig.wrists[w].global_position))
		if float(shot["from"]) <= GuardRig.GUN_LAND and float(shot["to"]) >= GuardRig.GUN_LAND:
			boss.replay_death(GuardRig.GUN_LAND)
			var cam_g := KoReplay.camera(shot, KoReplay.progress(shot, GuardRig.GUN_LAND), boss.body_point())
			gun_seen = gun_seen or (seen.call(cam_g, fov, boss.to_local(boss._rig.rifle.global_position))
					and seen.call(cam_g, fov, boss.to_local(boss._rig.muzzle_position())))
		var from_cam: Vector3 = shot["cam"][0]
		angles.append(atan2(from_cam.x, -from_cam.z))
	var apart := absf(angle_difference(angles[0], angles[1])) > 0.8 and absf(angle_difference(angles[1], angles[2])) > 0.8
	_check(plan.size() == 3 and slowed and apart, "boss KO: three slowed shots from three angles (user: like Tekken)")
	_check(in_view, "boss KO: he's in view in every shot on a tall phone (and his hands as he lies there)")
	_check(gun_seen, "boss KO: the minigun's seen hitting the deck (user: 'he drops the minigun')")
	_check(under_rotor, "boss KO: the cameras stay under the chopper's rotor")
	_check(total <= 10.0, "boss KO: about 9 s in all (%.1f; LOCKED: cinematic beats short; the bots check the tap to skip)" % total)
	boss.queue_free()


## CROSS's death (user: "a momentum ragdoll", slowed a little): from running, standing, in the air,
## short of a crate, blocked (and right at the barrier he hit) and sliding, he ends face down where
## his momentum (and the way ahead) carries him, or on his back (knocked back, or slumped from a
## slide); none of him through the ground or ever into what's in front of him, no joint flipping
## round, lying still; his pistol on the ground, not past what's in front of him; the same at the
## same moment; about 2.5 s to the end screen. How he falls is the game's own (SoldierRig.fall_for).
func _test_cross_death() -> void:
	var tt := Tuning.new()
	# [name, lift m, pose, speed m/s, room m]
	var cases := [["running", 0.0, "run", 11.0, 99.0], ["standing", 0.0, "stand", 0.0, 99.0], ["in the air", 0.9, "jump", 11.0, 99.0],
			["short of a crate", 0.0, "run", 11.0, 1.8], ["blocked", 0.0, "run", 11.0, 0.9], ["at the barrier", 0.0, "run", 11.0, 0.05],
			["sliding", 0.0, "slide", 11.0, 99.0], ["sliding, a dog ahead", 0.0, "slide", 11.0, 1.5]]
	var all_ok := true
	var worst := ""
	for c in cases:
		var r := SoldierRig.new()
		root.add_child(r)
		for f in 30:
			r.animate(1.0 / 60.0, {"run": 1.0 if c[2] == "run" else 0.0, "sliding": c[2] == "slide", "airborne": c[2] == "jump", "aim": true})
		var fall := SoldierRig.fall_for(float(c[3]), float(c[4]), c[2] == "slide", tt)
		var back: bool = fall["back"]
		var face_up: bool = back or fall["slide"]
		var travel: float = fall["travel"]
		var from := r.death_start({"travel": travel / SoldierRig.SIZE, "lift": float(c[1]) / SoldierRig.SIZE, "room": float(c[4]) / SoldierRig.SIZE,
				"back": back, "slide": fall["slide"]})
		var end := r.death_end()
		var land := r.death_land()
		var lowest := INF
		var step := 0.0
		var was := []
		var lying := []
		var moved := 0.0
		var t := 0.0
		var real := 0.0
		var pistol_low := INF
		# How far forward any of him reaches (each point's own size): as he was hit, all through his fall
		# (never further into what's in front of him than he already was) and once he's down.
		var start_ahead := _reach_ahead(r)
		var ahead_fall := -INF
		var ahead := -INF
		while t < end:
			t = minf(t + (1.0 / 60.0) * lerpf(tt.death_slow, 1.0, smoothstep(0.0, land, t)), end)
			real += 1.0 / 60.0
			r.pose_death(t, from)
			var pts: Array = r._rag_points()
			for p in pts:
				lowest = minf(lowest, (p as Vector3).y * SoldierRig.SIZE)
			ahead_fall = maxf(ahead_fall, _reach_ahead(r))
			if t >= land:
				ahead = maxf(ahead, _reach_ahead(r))
			pistol_low = minf(pistol_low, r._in_rig(r.wrists[1].get_node("Pistol")).origin.y * SoldierRig.SIZE)
			var qs := []
			for j in r._all_joints():
				qs.append(j.quaternion)
			if not was.is_empty() and t > 0.02:
				for k in qs.size():
					step = maxf(step, (was[k] as Quaternion).angle_to(qs[k]))
			was = qs
			if t >= end - 0.3:
				if lying.is_empty():
					lying = pts
				for k in pts.size():
					moved = maxf(moved, (pts[k] as Vector3).distance_to(lying[k]) * SoldierRig.SIZE)
		var face := (r._in_rig(r.chest).basis * Vector3.FORWARD).normalized().y
		var hz := -r.hips.position.z * SoldierRig.SIZE * (-1.0 if back else 1.0)
		var pistol := r._in_rig(r.wrists[1].get_node("Pistol")).origin * SoldierRig.SIZE
		# Face down where his run carries him (on his back, knocked back or from a slide), and all of
		# him, all the way down, behind what's in front of him.
		var ok := (face > 0.8 if face_up else face < -0.8) and absf(hz - travel) < 0.25 and lowest > -0.04 and step < 1.2 and moved < 0.02 \
				and pistol.y < 0.1 and pistol_low > -0.02 and -pistol.z <= float(c[4]) + 0.05 and ahead <= float(c[4]) + 0.05 \
				and ahead_fall <= maxf(float(c[4]), start_ahead) + 0.05 \
				and real + tt.death_hold < 3.2
		# The same at the same moment.
		r.pose_death(0.4, from)
		var a := str(r.hips.position) + str(r.spine.quaternion) + str(r.wrists[1].quaternion)
		r.pose_death(1.2, from)
		r.pose_death(0.4, from)
		ok = ok and a == str(r.hips.position) + str(r.spine.quaternion) + str(r.wrists[1].quaternion)
		if not ok:
			all_ok = false
			worst += " %s(face %.2f, at %.2f of %.2f m, low %.3f, step %.2f, moved %.3f, pistol %s, ahead %.2f, %.2f in the fall from %.2f, %.1f s)" 					% [c[0], face, hz, travel, lowest, step, moved, pistol, ahead, ahead_fall, start_ahead, real]
		r.queue_free()
	_check(all_ok, "CROSS's death: face down where his run carries him (blocked, knocked back onto his back; mid-slide, slumped onto his back), nothing through the ground or ever into what's in front of him, no flips, still, the pistol down, about 2.5 s (user)" + worst)


## How far forward of where he was killed any of him reaches (m; each ragdoll point with its own size).
func _reach_ahead(r: SoldierRig) -> float:
	var pts: Array = r._rag_points()
	var most := -INF
	for k in pts.size():
		most = maxf(most, (-(pts[k] as Vector3).z + SoldierRig.RAG_RADIUS[k]) * SoldierRig.SIZE)
	return most


## The end screen types and counts (user: "the text in this screen to type in and the numbers to
## count up"): every row's label types out, each number counts up from 0 (a 1 takes long enough to
## see), each word types out, a tick a letter, the same final words as before; the title types; a
## skip shows it all at once.
func _test_end_typing() -> void:
	var rows := Tally.rows_for({"time": 61.2, "spare": 9.0, "downed": 1, "hits": 2, "run_into": 15, "alarms_set_off": 1,
			"alarms_stopped": 0, "top_alert": 2, "levels": "MAIN > BELOW", "new_areas": 3})
	var t := Tally.new()
	t.rows = rows
	t.size = Vector2(222, Tally.ROW_H * rows.size())
	root.add_child(t)
	var typed := [0]
	var lands := [0]
	t.typed.connect(func() -> void: typed[0] += 1)
	t.landed.connect(func() -> void: lands[0] += 1)
	var letters := 0
	for row in rows:
		letters += String(row[0]).replace(" ", "").length()
		if String(row[1]) == "text":
			letters += Tally.fit_value(row[0], String(row[2]), 222.0).replace(" ", "").length()
	# The ENEMIES DOWN row (a 1): how long from its label typed to its landing.
	var frames := 0
	var one_from := -1
	var one_for := 0
	while not t.is_done() and frames < 6000:
		t._process(1.0 / 60.0)
		frames += 1
		if t._row == 2 and t._typed >= String(rows[2][0]).length() and one_from < 0:
			one_from = frames
		if t._row == 3 and one_from >= 0 and one_for == 0:
			one_for = frames - one_from
	_check(t.is_done() and typed[0] == letters and lands[0] == rows.size(),
			"end screen: every label and word types out, a tick a letter (%d of %d), each row lands (%d)" % [typed[0], letters, lands[0]])
	_check(one_for >= int(Tally.MIN_COUNT * 60.0) - 1, "end screen: a count of 1 rolls slowly enough to see (%d frames)" % one_for)
	_check(frames / 60.0 < 12.0, "end screen: the whole tally types and counts in a reasonable time (%.1f s)" % (frames / 60.0))
	t.queue_free()
	# Skipped part way: all at once, one thunk.
	var t2 := Tally.new()
	t2.rows = rows
	t2.size = Vector2(222, Tally.ROW_H * rows.size())
	root.add_child(t2)
	var lands2 := [0]
	t2.landed.connect(func() -> void: lands2[0] += 1)
	for f in 40:
		t2._process(1.0 / 60.0)
	var before: int = lands2[0]
	t2.skip()
	t2.skip()
	_check(t2.is_done() and lands2[0] == before + 1, "end screen: a tap shows the whole tally at once (one thunk)")
	t2.queue_free()
	# The title and subtitle type out, in order, a tick a letter; finish() shows them at once.
	var shown := {"a": -1, "b": -1}
	var ty := Typer.new()
	ty.add("KILLED IN ACTION", 0.05, func(n: int) -> void: shown["a"] = n)
	ty.add("AGENT DOWN", 0.03, func(n: int) -> void: shown["b"] = n)
	root.add_child(ty)
	var ticks := [0]
	ty.typed.connect(func() -> void: ticks[0] += 1)
	var order_ok: bool = shown["a"] == 0 and shown["b"] == 0
	for f in 30:
		ty._process(1.0 / 60.0)
		order_ok = order_ok and (shown["b"] == 0 or shown["a"] == 16)
	var mid: bool = shown["a"] > 0 and not ty.is_done()
	ty.finish()
	_check(order_ok and mid and ty.is_done() and shown["a"] == 16 and shown["b"] == 10 and ticks[0] > 0,
			"end screen: the title types out, then the subtitle; a tap shows them at once")
	ty.queue_free()


## The mission briefing after START (user): a conversation, CROSS's card on the right and whoever
## he's talking to on the left, each line typing out with its speaker's name first, the speaker's card
## lit and forward and the listener's dimmed and pushed back, a new caller's card flipping over through
## static; a tap finishes the line being typed, the next tap shows the next line, SKIP ends it. The
## script is data, each name set once.
func _test_briefing() -> void:
	var was_scale := Engine.time_scale
	Engine.time_scale = 1.0
	var dt := 1.0 / 60.0
	# The script.
	var data := Briefing.load_file("res://game/levels/prototype_slice/briefing.json")
	var problems := Briefing.problems(data)
	_check(problems.is_empty(), "briefing: the script is valid: known speakers, pictures, only letters the font has, every line fits the box (%s)" % ", ".join(problems))
	var lines := Briefing.lines_of(data)
	var who := {}
	for l in lines:
		who[l["who"]] = true
	_check(lines.size() >= 4 and who.has("cross") and who.has("general") and who.has("briefer"),
			"briefing: mission 1's lines for CROSS, the General and the briefer (%d lines)" % lines.size())
	_check(String(lines[0]["text"]).begins_with("[BISHOP] ") and _said_by(lines, "briefer").begins_with("[VESPER] "),
			"briefing: a line starts with its speaker's name, the codenames set in the cast (%s)" % lines[0]["text"])
	for id in ["cross", "general", "briefer"]:
		_check(load(String(data["cast"][id]["portrait"])) is Texture2D, "briefing: %s's picture loads" % id)
	# Each name set once: rename the General in the cast and every line follows.
	var renamed: Dictionary = data.duplicate(true)
	renamed["cast"]["general"]["name"] = "VIPER"
	(renamed["lines"] as Array).append({"who": "cross", "text": "I hear you, {general}."})  # (a line naming him)
	var said := " ".join(Briefing.lines_of(renamed).map(func(l: Dictionary) -> String: return l["text"]))
	_check(said.contains("[VIPER] ") and said.contains("you, VIPER.") and not said.contains("BISHOP"),
			"briefing: the General's name is set once, in the cast ({general} in a line follows it)")
	# What it catches: a speaker not in the cast, an empty line, a name not in the cast, a letter the
	# font hasn't got, a line too long for the box; and no CROSS.
	var bad := {"cast": data["cast"], "lines": [
		{"who": "colonel", "text": "Hello."},
		{"who": "general", "text": "  "},
		{"who": "general", "text": "Ask {colonel}."},
		{"who": "general", "text": "Café."},
		{"who": "general", "text": "word ".repeat(45)},
		{"who": "general", "text": "It’s “fine” — really…"},
	]}
	var found := Briefing.problems(bad)
	_check(found.size() == 5, "briefing: a bad script is caught line by line (%s)" % ", ".join(found))
	_check(not Briefing.problems({"cast": {"general": data["cast"]["general"]}, "lines": []}).is_empty(), "briefing: a script without CROSS is caught")
	# A codename too long for its name plate (user: still unsure about BISHOP).
	var long_cast: Dictionary = data["cast"].duplicate(true)
	long_cast["general"]["name"] = "GENERAL BISHOP"
	var too_long := Briefing.problems({"cast": long_cast, "lines": data["lines"]})
	_check(too_long.size() == 1 and too_long[0].contains("12 letters"), "briefing: a codename too long for its name plate is caught (%s)" % ", ".join(too_long))
	_check(Briefing.plain("It’s “fine” — really…") == "It's \"fine\" - really...", "briefing: curly quotes, dashes and ... from a word processor made plain")
	_check(Briefing.wrap_rows("AAAA BBBB CCCC", 9) == [[0, 9], [10, 4]] and Briefing.wrap_rows("ABCDEFGHIJ", 4) == [[0, 4], [4, 4], [8, 2]],
			"briefing: lines wrap at spaces (a word too long for a row is split)")
	for s in ["codec", "codec_open", "codec_static", "codec_close"]:
		_check(s in SoundBank.all_names(), "briefing: its sound '%s' is built with the rest" % s)
	# On screen: a frontend screen of its own.
	var fe: CanvasLayer = load("res://game/ui/menu/frontend.gd").new()
	root.add_child(fe)
	var cues: Array[String] = []
	var done := [0]
	var ticks := [0]
	fe.briefing_cue.connect(func(s: String, _db: float) -> void: cues.append(s))
	fe.briefing_done.connect(func() -> void: done[0] += 1)
	fe.typed.connect(func() -> void: ticks[0] += 1)
	var clicks := [0]
	fe.clicked.connect(func() -> void: clicks[0] += 1)
	# (how it plays, on a conversation of its own, so the script can change: the General calls, CROSS
	# answers, the General twice more, then the briefer comes on)
	var demo := {"cast": data["cast"], "lines": [
		{"who": "general", "text": "Cross. You're in. Listen carefully, we don't have long."},
		{"who": "cross", "text": "I hear you, {general}. Where's my ride out?"},
		{"who": "general", "text": "A chopper, on the helipad. It won't wait for you."},
		{"who": "general", "text": "{briefer} has the layout. {briefer}, go ahead."},
		{"who": "briefer", "text": "Three ways to the pad: the main floor, the roofs or the tunnels."},
		{"who": "cross", "text": "Understood."},
	]}
	fe.show_briefing(demo)
	var br: Briefing = null
	for c in fe.find_children("*", "", true, false):
		if c is Briefing:
			br = c
	_check(br != null and fe.in_briefing() and fe.is_open(), "briefing: START opens it as a menu screen (so the level's own input stays shut out)")
	if br == null:
		fe.free()
		Engine.time_scale = was_scale
		return
	var view: Vector2 = fe.get_viewport().get_visible_rect().size
	_check(br.size == view and br.mouse_filter == Control.MOUSE_FILTER_STOP, "briefing: a tap anywhere is 'next' (it covers the screen: %s)" % br.size)
	_check(br.frame_rect("right").get_center().x > view.x / 2.0 and br.frame_rect("left").get_center().x < view.x / 2.0,
			"briefing: CROSS's card on the right, the other on the left (user)")
	var skip_rect := Rect2(br.skip_button.position, br.skip_button.size)
	_check(br.skip_button.focus_mode == Control.FOCUS_NONE and Rect2(Vector2.ZERO, view).encloses(skip_rect),
			"briefing: SKIP on screen, never focused (Space / Enter are 'next')")
	for v: Vector2 in [Vector2(270, 480), Vector2(270, 585)]:
		var lay := Briefing.layout(v)
		var inside := Rect2(0, 44, v.x, v.y - 88)  # (between the cinema bars, Hud.LETTERBOX)
		var l: Rect2 = lay["left"]
		var r: Rect2 = lay["right"]
		var box: Rect2 = lay["text"]
		_check(r.get_center().x > v.x / 2.0 and l.get_center().x < v.x / 2.0 and l.size == r.size,
				"briefing %dx%d: CROSS's card on the right, the other on the left, the same size" % [v.x, v.y])
		# The cards whole (slanted, tilted, in their frames) between the cinema bars; the other's card
		# over the speech and CROSS's under it, neither's frame into it.
		var whole := Briefing.RIM + Briefing.EDGE
		var lo := Briefing.card_outline(l, "left", whole)
		var ro := Briefing.card_outline(r, "right", whole)
		var cards_in := true
		for pt in lo + ro:
			cards_in = cards_in and inside.has_point(pt)
		var l_low := -INF
		for pt in Briefing.card_outline(l, "left", Briefing.RIM):
			l_low = maxf(l_low, pt.y)
		var r_high := INF
		var r_left := INF
		for pt in Briefing.card_outline(r, "right", Briefing.RIM):
			r_high = minf(r_high, pt.y)
			r_left = minf(r_left, pt.x)
		_check(cards_in and inside.encloses(box) and l_low < box.position.y and r_high > box.end.y,
				"briefing %dx%d: both cards whole and the speech between the cinema bars, the other's card over the speech, CROSS's under it" % [v.x, v.y])
		# A name plate holds the longest name a script may have, on the screen between the bars.
		var plates_in := true
		for side in ["left", "right"]:
			plates_in = plates_in and inside.encloses(Briefing.plate_rect(lay[side], side, Briefing.NAME_MOST, v.x))
		_check(plates_in, "briefing %dx%d: a %d-letter name fits its plate, on the screen" % [v.x, v.y, Briefing.NAME_MOST])
		# The waveforms (user): the length of their plate, under the caller's and over CROSS's, on the
		# screen, clear of the speech's band; long enough for the longest name.
		var waves_ok := Briefing.WAVE_MOST * Briefing.WAVE_STEP >= Briefing.plate_rect(lay["left"], "left", Briefing.NAME_MOST, v.x).size.x
		for letters in [3, 6, Briefing.NAME_MOST]:
			var lp := Briefing.plate_rect(lay["left"], "left", letters, v.x)
			var rp := Briefing.plate_rect(lay["right"], "right", letters, v.x)
			var lw := Briefing.wave_rect(lp, "left")
			var rw := Briefing.wave_rect(rp, "right")
			waves_ok = waves_ok and lw.position.y >= lp.end.y and rw.end.y <= rp.position.y and lw.size.x == lp.size.x and rw.size.x == rp.size.x \
					and lw.position.x == lp.position.x and rw.position.x == rp.position.x and inside.encloses(lw) and inside.encloses(rw) \
					and not lw.intersects(lay["text"]) and not rw.intersects(lay["text"])
		_check(waves_ok, "briefing %dx%d: the speech waveforms the length of their name plates, under the caller's and over CROSS's (user), clear of the speech" % [v.x, v.y])
		var sk: Rect2 = lay["skip"]
		_check(sk.position.y >= 0.0 and sk.end.y <= 44.0 and sk.end.x <= v.x and sk.size.y >= 30.0 and sk.size.x >= 60.0,
				"briefing %dx%d: SKIP up in the top bar (where the pause button is in the run), %dx%d to tap" % [v.x, v.y, sk.size.x, sk.size.y])
		# The rows: a full row of letters on its strip (with the block's lean) fits across the band, and
		# all of them under the speaker's bar fit down it.
		_check(Briefing.strip_reach() <= box.size.x and box.position.x >= 0.0 and box.end.x <= v.x
				and Briefing.RAIL_H + Briefing.RAIL_GAP + (Briefing.ROWS - 1) * Briefing.ROW_H + Briefing.STRIP_H <= box.size.y,
				"briefing %dx%d: %d rows of %d letters fit the speech's band (%d px of %d across)" % [v.x, v.y, Briefing.ROWS, Briefing.COLS, Briefing.strip_reach(), box.size.x])
		# TAP, under the longest line or under CROSS's, stays clear of CROSS's card and on the screen.
		var hints_ok := true
		for top in [true, false]:
			var hr := Briefing.hint_rect(box, Briefing.ROWS, top, "TAP TO CONTINUE")
			hints_ok = hints_ok and inside.encloses(hr) and hr.end.x < r_left
		_check(hints_ok, "briefing %dx%d: TAP under the speech, clear of CROSS's card" % [v.x, v.y])
	_check(cues.size() == 1 and cues[0] == "codec", "briefing: it opens with the codec's call (%s)" % [cues])
	# The opening: a tap does nothing until the first line; the faces switch on; the first line.
	br.tap()
	var f := 0
	while not br.is_talking() and f < 300:
		br._process(dt)
		f += 1
	_check(br.line_index() == 0 and f <= ceili(Briefing.FIRST_LINE_AT * 60.0) + 1 and br.power("left") == 1.0 and br.power("right") == 1.0,
			"briefing: it opens in %.1f s, both faces on, the first line typing" % (f / 60.0))
	_check(cues.has("codec_open"), "briefing: the cards coming in play the codec's opening sound")
	# A tick a letter (spaces silent), the speaker lit and the listener dimmed.
	ticks[0] = 0
	while not br.line_done() and f < 3000:
		br._process(dt)
		f += 1
	_check(ticks[0] == br.line().replace(" ", "").length(), "briefing: a line types a letter at a time, a tick a letter (%d of %d)" % [ticks[0], br.line().replace(" ", "").length()])
	_check(br.speaker() == "general" and br.left_who() == "general" and br.lit("left") == 1.0 and br.lit("right") == Briefing.DIMMED,
			"briefing: the General speaking: his face lit, CROSS's dimmed")
	_check(br.wave_peak("left") > 0.25 and br.wave_peak("right") < 0.1,
			"briefing: the General's waveform moving as he speaks, CROSS's flat (user; %.2f, %.2f)" % [br.wave_peak("left"), br.wave_peak("right")])
	_check(_card_scale(br, "left") == 1.0 and is_equal_approx(_card_scale(br, "right"), Briefing.BACK_SCALE),
			"briefing: the General's card forward, CROSS's pushed back (%.2f, %.2f)" % [_card_scale(br, "left"), _card_scale(br, "right")])
	# A tap just as the line finished typing on its own was meant to finish it: nothing more.
	br.tap()
	_check(br.line_index() == 0 and br.line_done(), "briefing: a tap as a line finishes typing on its own doesn't skip to the next (%.1f s grace)" % Briefing.GRACE)
	for i in ceili(Briefing.GRACE * 60.0) + 1:
		br._process(dt)
	# One tap (a touch and the click emulated from it, in the same frame) on a whole line: the next.
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.pressed = true
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	br._gui_input(touch)
	br._gui_input(click)
	_check(br.line_index() == 1 and br.shown() == 0, "briefing: a tap on a whole line shows the next (one tap, a touch and its click, counts once)")
	for i in 20:
		br._process(dt)
	_check(br.speaker() == "cross" and br.lit("right") == 1.0 and br.lit("left") == Briefing.DIMMED and not cues.has("codec_static"),
			"briefing: CROSS answering: his face lit, the General's dimmed, no static (the same caller)")
	_check(br.wave_peak("right") > 0.25 and br.wave_peak("left", 6) < 0.1,
			"briefing: CROSS's waveform moving as he speaks, the General's gone flat (user; %.2f, %.2f)" % [br.wave_peak("right"), br.wave_peak("left", 6)])
	_check(_card_scale(br, "right") == 1.0 and is_equal_approx(_card_scale(br, "left"), Briefing.BACK_SCALE),
			"briefing: CROSS's card forward now, the General's pushed back")
	# A tap part way through a line finishes it (and only that).
	_check(not br.line_done(), "briefing: (CROSS's line still typing)")
	br._tap_frame = -1  # (a later frame)
	br._gui_input(touch)
	_check(br.line_done() and br.line_index() == 1, "briefing: a tap while a line types shows the whole line, nothing more")
	br._tap_frame = -1
	br._gui_input(touch)
	_check(br.line_index() == 2, "briefing: the tap after one that finished a line shows the next at once (no grace after a tap)")
	# On to the briefer: a burst of static on the left card, which flips over edge-on and back, her
	# face coming through it.
	while br.line_index() < 4:
		br.tap()
	_check(br.line_index() == 4 and br.speaker() == "briefer" and cues.count("codec_static") == 1, "briefing: the briefer on: static (%s)" % [cues])
	var peak := 0.0
	var right_static := 0.0
	var thinnest := 1.0
	var right_thinnest := 1.0
	for i in 40:
		br._process(dt)
		peak = maxf(peak, br.static_on("left"))
		right_static = maxf(right_static, br.static_on("right"))
		thinnest = minf(thinnest, absf(br._pics["left"].scale.x / br._pics["left"].scale.y))
		right_thinnest = minf(right_thinnest, absf(br._pics["right"].scale.x / br._pics["right"].scale.y))
	_check(peak > 0.9 and br.static_on("left") == 0.0 and right_static == 0.0 and br.left_who() == "briefer" and br.lit("left") == 1.0,
			"briefing: the static bursts on the left card only (%.2f) and clears on her face, lit" % peak)
	_check(thinnest < 0.1 and right_thinnest == 1.0 and is_equal_approx(br._pics["left"].scale.x, br._pics["left"].scale.y),
			"briefing: the left card flips over for her (edge-on at %.2f) and back; CROSS's doesn't" % thinnest)
	# SKIP ends it, once (pressed twice, and a tap as it closes).
	br.skip_button.pressed.emit()
	br.skip_button.pressed.emit()
	br.tap()
	for i in 60:
		br._process(dt)
	_check(done[0] == 1 and cues.count("codec_close") == 1 and clicks[0] == 2, "briefing: SKIP closes it once (%d), with the codec's closing sound and a button's click" % done[0])
	fe.free()
	# Tapped through to the end: every line once, and a tap after the last closes it.
	var fe2: CanvasLayer = load("res://game/ui/menu/frontend.gd").new()
	root.add_child(fe2)
	var done2 := [0]
	fe2.briefing_done.connect(func() -> void: done2[0] += 1)
	fe2.show_briefing(data)
	var br2: Briefing = null
	for c in fe2.find_children("*", "", true, false):
		if c is Briefing:
			br2 = c
	var shown := {}
	f = 0
	while done2[0] == 0 and f < 6000:
		br2._process(dt)
		f += 1
		if br2.is_talking():
			shown[br2.line_index()] = true
			if br2.line_done():
				br2.tap()
	_check(done2[0] == 1 and shown.size() == lines.size(), "briefing: tapped through, every line shown (%d of %d) and it closes once" % [shown.size(), lines.size()])
	fe2.free()
	Engine.time_scale = was_scale


## How big a briefing card is drawn (1: forward, Briefing.BACK_SCALE: pushed back).
func _card_scale(br: Briefing, side: String) -> float:
	return snappedf(br._pics[side].scale.y, 0.0001)


## The first line in the script that `who` says ("" if none).
func _said_by(lines: Array, who: String) -> String:
	for l in lines:
		if l["who"] == who:
			return l["text"]
	return ""


## The end-of-mission conversations (user: "the same briefing convo but for when the player
## successfully gets to the chopper and when the players dies/gets captured"): one for each ending,
## in the briefing's file, each valid and its codenames from the cast; after the run the conversation
## plays, then the debrief opens (tapped through, or SKIP), once; never the opening pan. Killed
## (user: "Signal lost"): CROSS's card static under SIGNAL LOST, his waveform flat the whole way, and
## he never speaks. An ending with no conversation (dead_end: no route in this mission can reach it)
## opens the debrief at once.
func _test_end_talk() -> void:
	var was_scale := Engine.time_scale
	Engine.time_scale = 1.0
	var data := Briefing.load_file("res://game/levels/prototype_slice/briefing.json")
	var main := ["extracted", "killed", "captured", "chopper_left"]
	# The script: every conversation valid (Briefing.problems checks them all), one for each ending.
	_check(Briefing.problems(data).is_empty(), "end talk: every conversation in the script is valid (%s)" % ", ".join(Briefing.problems(data)))
	for id: String in main:
		var talk := Briefing.conversation(data, id)
		var lines := Briefing.lines_of(talk)
		var who := {}
		for l in lines:
			who[l["who"]] = true
		_check(lines.size() >= 3 and lines.size() <= 6 and String(talk.get("title", "")) != "" and talk.get("id") == id,
				"end talk %s: its own conversation, %d lines and a tag (%s)" % [id, lines.size(), talk.get("title", "")])
		_check(who.has("general") and who.has("briefer") and (who.has("cross") != (id == "killed")),
				"end talk %s: BISHOP and VESPER speak; CROSS %s" % [id, "doesn't (his signal's lost)" if id == "killed" else "does"])
		_check(bool(talk.get("signal_lost", false)) == (id == "killed"), "end talk %s: CROSS's signal lost only when he's killed" % id)
		# Its tag in the top bar, clear of where we are and SKIP on the narrowest phone.
		var tag_end := 8.0 + String(talk["title"]).length() * 6.0 + 14.0
		var count_w := ("%d/%d" % [lines.size(), lines.size()]).length() * 6.0 + 14.0
		_check(tag_end + 4.0 + count_w < Briefing.layout(Vector2(270, 480))["skip"].position.x,
				"end talk %s: its tag '%s' fits the top bar beside the count and SKIP" % [id, talk["title"]])
	_check(Briefing.conversation(data, "dead_end").is_empty() and Briefing.lines_of(Briefing.conversation(data, "dead_end")).is_empty(),
			"end talk: none for dead_end (the debrief opens at once)")
	_check(Briefing.conversation(data, Briefing.BRIEFING)["lines"] == data["lines"] and not Briefing.conversation(data).has("endings"),
			"end talk: the START briefing is still the file's own lines")
	# Each codename set once: rename the General and the briefer in the cast and the endings follow.
	var renamed: Dictionary = data.duplicate(true)
	renamed["cast"]["general"]["name"] = "VIPER"
	renamed["cast"]["briefer"]["name"] = "ROOK"
	(renamed["endings"]["captured"]["lines"] as Array).append({"who": "cross", "text": "Sorry, {general}. Tell {briefer} too."})  # (a line naming them)
	var said := ""
	for id: String in main:
		said += " ".join(Briefing.lines_of(Briefing.conversation(renamed, id)).map(func(l: Dictionary) -> String: return l["text"]))
	_check(said.contains("[VIPER] ") and said.contains("[ROOK] ") and said.contains(", VIPER.") and not said.contains("BISHOP") and not said.contains("VESPER"),
			"end talk: the codenames set once, in the cast ({general} and {briefer} in the endings follow them)")
	# What it catches in an ending: CROSS speaking with his signal lost, an ending the game hasn't got,
	# a tag too long for the top bar or with no words, a letter the font hasn't got, a line too long.
	var bad: Dictionary = data.duplicate(true)
	bad["endings"]["killed"]["lines"].append({"who": "cross", "text": "I'm still here."})
	bad["endings"]["extract"] = {"title": "OUT", "lines": [{"who": "general", "text": "Typo."}]}
	bad["endings"]["captured"]["title"] = "AGENT CAPTURED BY THE ENEMY"
	bad["endings"]["chopper_left"]["title"] = " "
	bad["endings"]["extracted"]["lines"][0]["text"] = "Café."
	bad["endings"]["extracted"]["lines"][1]["text"] = "word ".repeat(45)
	var found := Briefing.problems(bad)
	var lost_line := "killed line %d" % bad["endings"]["killed"]["lines"].size()
	_check(found.size() == 6 and found.any(func(p: String) -> bool: return p.begins_with(lost_line) and p.contains("signal is lost")),
			"end talk: a bad ending is caught, CROSS speaking when he's killed among it (%s)" % ", ".join(found))
	_check(Briefing.lines_of(Briefing.conversation(bad, "killed")).all(func(l: Dictionary) -> bool: return l["who"] != "cross"),
			"end talk: CROSS never speaks with his signal lost, even with a line of his in the file")
	var old := {"cast": data["cast"], "lines": data["lines"]}
	_check(Briefing.problems(old).is_empty() and Briefing.conversation(old, "killed").is_empty(),
			"end talk: a script with only the briefing still works (no conversations after the run)")
	# dead_end can't happen in this mission: wherever you are, at any alert, there's a way on.
	var g := RouteGraph.from_json_file(MISSION_1)
	var stuck: Array[String] = []
	for id: StringName in g._nodes:
		for alert in [1, 2, 3]:
			if g.end_type(id) == "" and g.available_next(id, alert).is_empty():
				stuck.append("%s@%d" % [id, alert])
	_check(stuck.is_empty(), "end talk: no dead end in this mission (every area has a way on at every alert: %s)" % ", ".join(stuck))
	# After the run: each ending's conversation, tapped through, then the debrief; once, never the pan.
	for id: String in main:
		var r := _end_talk_run(data, id, false)
		_check(r["opened"] and r["shown"] == r["count"] and r["count"] >= 3 and r["debrief"] == 1 and r["reason"] == id and r["pan"] == 0 \
				and r["title"] != "" and r["order"],
				"end talk %s: the conversation, every line (%d of %d), then the debrief once (%d, as %s, titled %s), not the pan (%d)" % [
				id, r["shown"], r["count"], r["debrief"], r["reason"], r["order"], r["pan"]])
		_check(r["cues"].count("codec") == 1 and r["cues"].count("codec_open") == 1 and r["cues"].count("codec_close") == 1,
				"end talk %s: the codec's sounds, as the briefing's (%s)" % [id, r["cues"]])
		_check(r["guarded"], "end talk %s: the debrief's RETRY and MAIN MENU wait a moment (a tap meant for the conversation can't press them)" % id)
		if id == "killed":
			_check(r["lost"] and r["cross_spoke"] == 0 and r["static_min"] >= Briefing.LOST_STATIC - 0.001 and r["wave_max"] == 0.0 and r["lit_max"] <= Briefing.DIMMED + 0.001,
					"end talk killed: SIGNAL LOST: CROSS's card static the whole way (%.2f), his waveform flat (%.2f), dimmed (%.2f), and he never speaks (%d)" % [
					r["static_min"], r["wave_max"], r["lit_max"], r["cross_spoke"]])
			_check(r["cues"].count("codec_static") >= 1, "end talk killed: static as CROSS's card comes on (%s)" % [r["cues"]])
		else:
			_check(not r["lost"] and r["cross_spoke"] > 0 and r["static_min"] == 0.0 and r["wave_max"] > 0.25,
					"end talk %s: CROSS on his card and speaking (his waveform up to %.2f)" % [id, r["wave_max"]])
		# SKIP: straight to the debrief, once.
		var s := _end_talk_run(data, id, true)
		_check(s["opened"] and s["shown"] <= 1 and s["debrief"] == 1 and s["pan"] == 0 and s["order"] and s["skip_frames"] >= 0 \
				and s["skip_frames"] <= ceili(Briefing.CLOSE_TIME * 60.0) + 2,
				"end talk %s: SKIP goes straight to the debrief (%d frames), once" % [id, s["skip_frames"]])
	# No conversation for an ending: the debrief at once.
	var fe: CanvasLayer = load("res://game/ui/menu/frontend.gd").new()
	root.add_child(fe)
	var opened: Array[StringName] = []
	fe.debrief_opened.connect(func(reason: StringName) -> void: opened.append(reason))
	fe.show_end(&"dead_end", {}, Briefing.conversation(data, "dead_end"))
	_check(fe.in_debrief() and opened.size() == 1 and opened[0] == &"dead_end", "end talk: no conversation for dead_end: the debrief at once (%s)" % [opened])
	# RETRY and MAIN MENU on the debrief, as before.
	var asked := {"retry": 0, "menu": 0}
	fe.retry_requested.connect(func() -> void: asked["retry"] += 1)
	fe.menu_requested.connect(func() -> void: asked["menu"] += 1)
	for b in fe.find_children("*", "Button", true, false):
		if (b as Button).text in ["RETRY", "MAIN MENU"]:
			(b as Button).pressed.emit()
	_check(asked["retry"] == 1 and asked["menu"] == 1, "end talk: RETRY and MAIN MENU on the debrief after it (%s)" % [asked])
	fe.free()
	Engine.time_scale = was_scale


## One end-of-mission conversation on a frontend, as the level shows it after the run: tapped through
## (the odd lines tapped part way, then a tap for the next once each is all there) or SKIPped as its
## first line types. What it saw.
func _end_talk_run(data: Dictionary, id: String, skip: bool) -> Dictionary:
	var dt := 1.0 / 60.0
	var fe: CanvasLayer = load("res://game/ui/menu/frontend.gd").new()
	root.add_child(fe)
	var out := {"opened": false, "shown": 0, "count": 0, "debrief": 0, "reason": "", "pan": 0, "cues": [], "lost": false,
			"cross_spoke": 0, "static_min": 1.0, "wave_max": 0.0, "lit_max": 0.0, "title": "", "order": true, "skip_frames": -1, "guarded": false}
	fe.debrief_opened.connect(func(reason: StringName) -> void:
		out["debrief"] += 1
		out["reason"] = String(reason)
		out["order"] = out["order"] and fe.in_debrief())
	fe.briefing_done.connect(func() -> void: out["pan"] += 1)
	fe.briefing_cue.connect(func(c: String, _db: float) -> void: out["cues"].append(c))
	fe.show_end(StringName(id), {"time": 30.0}, Briefing.conversation(data, id))
	var br: Briefing = null
	for c in fe.find_children("*", "", true, false):
		if c is Briefing:
			br = c
	out["opened"] = br != null and fe.in_end_talk() and fe.is_open() and not fe.in_debrief() and not fe.in_briefing() and br.conversation_id() == id
	if br == null:
		fe.free()
		return out
	out["count"] = br.line_count()
	out["lost"] = br.signal_lost()
	out["title"] = br.title()
	var seen := {}
	var f := 0
	var skipped_at := -1
	while out["debrief"] == 0 and f < 6000:
		br._process(dt)
		f += 1
		if br.is_talking():
			seen[br.line_index()] = true
			if br.speaker() == "cross":
				out["cross_spoke"] += 1
		if br.power("right") >= 1.0 and not br.is_closing():
			out["static_min"] = minf(out["static_min"], br.static_on("right"))
			out["wave_max"] = maxf(out["wave_max"], br.wave_peak("right", Briefing.WAVE_MOST))
		if br.power("right") > 0.0:
			out["lit_max"] = maxf(out["lit_max"], br.lit("right"))  # (from his card's first light)
		if skip:
			if br.is_talking() and skipped_at < 0 and br.shown() > 3:
				br.skip_button.pressed.emit()
				skipped_at = f
		elif br.is_talking():
			if br.line_index() % 2 == 1 and br.shown() == 6:
				br.tap()  # (part way: the whole line)
			elif br.line_done() and f % 12 == 0:
				br.tap()
	out["shown"] = seen.size()
	out["skip_frames"] = f - skipped_at if skipped_at >= 0 else -1
	# The debrief: the end screen's title for this ending.
	var want: String = (load("res://game/ui/menu/frontend.gd") as GDScript).get_script_constant_map()["END_TITLES"][StringName(id)][0]  # (not by class name: it needs the autoloads)
	var titled := false
	for c in fe.find_children("*", "Label", true, false):
		titled = titled or (c as Label).text == want
	out["order"] = out["order"] and titled and fe.in_debrief()
	# RETRY and MAIN MENU wait a moment after the conversation (a tap meant for it can't press them).
	var guarded := true
	for c in fe.find_children("*", "Button", true, false):
		if (c as Button).text in ["RETRY", "MAIN MENU"]:
			guarded = guarded and (c as Button).disabled and (c as Button).mouse_filter == Control.MOUSE_FILTER_IGNORE
	out["guarded"] = guarded
	fe.free()
	return out


## CROSS ready under the menu (user: "an active stance, alarmed mode, he checks his gun and he's
## looking around ... his start stance can't be standing still it will need to match the stance he
## has in this animation"): the same moment, the same pose; the loop with no joint jumping, his feet
## planted, nothing through the floor, his arms under the shrug; the pistol never at the camera (the
## menu's, the pan's, or catching up after a skip); the gun check; the looking around big enough to
## see on a phone, framed between the title and the buttons; START settling him into the set; the
## run growing out of it rear leg first with no joint jumping, from any moment (and from the set
## Retry and the bots start in), then exactly the run; his standing pose as before.
func _test_cross_ready() -> void:
	var dt := 1.0 / 60.0
	var tt := Tuning.new()
	var play_look := Vector3(0.0, 1.0, -10.0)
	# The same moment, the same pose.
	var r := _rd_rig()
	_rd_at(r, 2.3)
	var a := _rd_str(r)
	_rd_at(r, 11.0)
	_rd_at(r, 2.3)
	var x := _rd_rig()
	var y := _rd_rig()
	for k in 400:
		x.animate(dt, {"ready": true})
		y.animate(dt, {"ready": true})
	_check(a == _rd_str(r) and _rd_str(x) == _rd_str(y), "CROSS ready: the same moment, the same pose (no randomness)")
	x.queue_free()
	y.queue_free()

	# Twice round the loop (across where it wraps).
	var lp := _rd_rig()
	lp.animate(0.0, {"ready": true})
	var prev := _rd_snap(lp)
	var worst := 0.0
	var hips := 0.0
	var feet := 0.0
	var flat := 1.0
	var low := INF
	var raised := 0.0
	var clear := 180.0
	var dip := 90.0
	var head_y := 0.0
	var neck_y := 0.0
	var turn := 0.0
	var look := [0.0, 0.0]
	var lens := [INF, -INF, INF]  # (x least and most at sway 0, y least at any sway: 480 and 585 high)
	var top_px := INF  # (the top of his head at its highest on screen: any sway, 480 and 585 high)
	var lens_x0 := 0.0
	var gun_px := -INF  # (lowest of the pistol and both hands on screen in the check: 480 and 585)
	var rest_px := [-INF, -INF]  # (both hands at the ready, the whole loop outside the check: 480, 585)
	var steps := []  # (each joint's turn, the last two frames: for a pop a frame long)
	var pops := []
	var wrist := [0.0, 0.0, 0.0]  # (worst bend off the forearm, deg: either hand at the ready, the gun hand and the left in the check)
	var vest := -INF  # (deepest an elbow or forearm goes into his vest, rig units)
	for f in int(2.0 * SoldierRig.IDLE_LOOP / dt) + 2:
		lp.animate(dt, {"ready": true})
		var now := _rd_snap(lp)
		worst = maxf(worst, _rd_step(prev, now))
		hips = maxf(hips, (prev[0] as Vector3).distance_to(now[0]))
		# A pop: a joint turning in one frame more than twice what it turns the frames either side
		# (a snapped head eases out, so it doesn't count; a joint jumping does).
		var turns := []
		for k in range(1, now.size()):
			turns.append((prev[k] as Quaternion).angle_to(now[k]))
		steps.append(turns)
		if steps.size() > 3:
			steps.pop_front()
		if steps.size() == 3:
			for k in turns.size():
				var m: float = steps[1][k]
				if m > 0.08 and m > 2.0 * maxf(steps[0][k], steps[2][k]):
					pops.append("%s %.3f at %.2f s" % [lp._all_joints()[k].name, m, lp._idle_t - dt])
		prev = now
		for side in [-1, 1]:
			var f2: Vector2 = SoldierRig.IDLE_FEET[side]
			feet = maxf(feet, lp._in_rig(lp.ankles[side]).origin.distance_to(Vector3(f2.x, (lp._ankle_rest[side] as Vector3).y, f2.y)))
			flat = minf(flat, _rd_sole(lp, side).y.dot(Vector3.UP))
			raised = maxf(raised, _rd_raise(lp, side))
		for p in lp._rag_points():
			low = minf(low, (p as Vector3).y * SoldierRig.SIZE)
		var s := -0.7
		while s <= 0.7001:
			clear = minf(clear, _rd_clear(lp, IntroCamera.menu(s, 0.0)[0]))
			s += 0.05
		dip = minf(dip, _rd_dip(lp))
		head_y = maxf(head_y, absf(lp.head.rotation.y))
		neck_y = maxf(neck_y, absf(lp.neck.rotation.y))
		turn = maxf(turn, absf(lp.hips.rotation.y + lp.spine.rotation.y + lp.chest.rotation.y))
		var fwd := lp._in_rig(lp.head).basis * Vector3.FORWARD
		var yaw := atan2(-fwd.x, -fwd.z)
		look = [maxf(look[0], yaw), minf(look[1], yaw)]
		var lz := _rd_lenses(lp)
		var mid: Vector3 = ((lz[0] as Vector3) + (lz[1] as Vector3)) / 2.0
		var px := _rd_screen(mid, 0.0, 480.0)
		if f == 0:
			lens_x0 = px.x
		lens = [minf(lens[0], px.x), maxf(lens[1], px.x), lens[2]]
		# (the top of his head: the middle of his skull and 17 cm up, the top of his hair on the model:
		# cross.glb's head-skinned vertices sit 2-4.5 cm above the skull's 16 cm sphere, so this reads
		# a fraction of a px high, never low)
		var crown := _rd_world(lp, lp._in_rig(lp.head) * SoldierRig.RAG_SKULL) + Vector3.UP * 0.17
		for sw in [-0.7, -0.35, 0.0, 0.35, 0.7]:
			for h in [480.0, 585.0]:
				for l in _rd_lenses(lp):
					lens[2] = minf(lens[2], _rd_screen(l, sw, h).y)
				top_px = minf(top_px, _rd_screen(crown, sw, h).y)
		var t := lp._idle_t
		if t > 1.0 and t < 5.0:
			wrist = [wrist[0], maxf(wrist[1], _rd_bend(lp, 1)), maxf(wrist[2], _rd_bend(lp, -1))]
		else:
			wrist[0] = maxf(wrist[0], maxf(_rd_bend(lp, 1), _rd_bend(lp, -1)))
		var chi := lp._in_rig(lp.chest).orthonormalized().affine_inverse()
		for side in [-1, 1]:
			var el := chi * lp._in_rig(lp.elbows[side]).origin
			var wr := chi * lp._in_rig(lp.wrists[side]).origin
			for k in 4:
				vest = maxf(vest, lp._in_vest(el.lerp(wr, k / 4.0), SoldierRig.IDLE_LIMB.x if k == 0 else SoldierRig.IDLE_LIMB.y))
		if (t > 1.6 and t < 4.4) or t < 1.0 or t > 5.0:
			var hands := [_rd_hand(lp, -1), _rd_hand(lp, 1)]
			var gun_at := _rd_world(lp, lp._in_rig(lp._pistol).origin)
			for sw in [-0.7, 0.0, 0.7]:
				for hi in 2:
					var h := 480.0 if hi == 0 else 585.0
					if t > 1.6 and t < 4.4:
						for p in hands + [gun_at]:
							gun_px = maxf(gun_px, _rd_screen(p, sw, h).y)
					elif t < 1.0 or t > 5.0:
						for p in hands:
							rest_px[hi] = maxf(rest_px[hi], _rd_screen(p, sw, h).y)
	# The wrap itself.
	_rd_at(lp, SoldierRig.IDLE_LOOP - dt)
	var before := _rd_snap(lp)
	lp.animate(dt, {"ready": true})
	var wrap := _rd_step(before, _rd_snap(lp))
	_check(worst < 0.25 and wrap < 0.05 and hips < 0.01 and pops.is_empty(),
			"CROSS ready: loops with no joint jumping (worst %.3f rad a frame, %.3f at the wrap; pops: %s)" % [worst, wrap, pops])
	_check(feet < 0.01 and flat > 0.999 and low > -0.03,
			"CROSS ready: his feet planted and flat, nothing through the floor (off %.4f, flat %.4f, lowest %.3f m)" % [feet, flat, low])
	_check(raised < SoldierRig.SHRUG_FROM, "CROSS ready: his arms never raised past the shrug (%.2f rad)" % raised)
	_check(clear > 35.0 and dip > 35.0, "CROSS ready: the pistol never at the menu's camera (user; %.1f° off at closest, %.1f° down at least)" % [clear, dip])
	_check(look[0] > 1.0 and look[1] < -1.3 and head_y < 0.8 and neck_y < 0.35 and turn < 0.6,
			"CROSS ready: he looks around, far each way (user; %.2f / %.2f rad), no neck or waist wringing (%.2f, %.2f, %.2f)" % [look[0], look[1], head_y, neck_y, turn])
	var rule: float = (load("res://game/ui/menu/frontend.gd") as GDScript).call("title_rule")  # (not by class name: it needs the autoloads)
	_check(lens[1] - lens_x0 > 18.0 and lens_x0 - lens[0] > 18.0 and lens[2] > rule + 16.0 and top_px > rule + 6.0,
			"CROSS ready: his eyes sweep far enough to see on a phone (%+.0f / %+.0f px); his head clear under the title (user: \"moved down a little more so he is clear of the text\"): its top at y %.0f at the highest, his eyes %.0f, on a 480-high screen and a tall phone (the title's red rule at %.0f)" % [lens[1] - lens_x0, lens[0] - lens_x0, top_px, lens[2], rule])
	_check(gun_px < 290.0 and rest_px[0] < 305.0 and rest_px[1] < 305.0 and absf(rest_px[0] - rest_px[1]) < 6.0,
			"CROSS ready: the gun check above the menu's buttons (y %.0f; START's top at 290); his hands at the ready at most just behind START's top edge (y %.0f on a 480-high screen, %.0f on a tall phone: the same)" % [gun_px, rest_px[0], rest_px[1]])
	_check(wrist[0] < 30.0 and wrist[1] < 64.0 and wrist[2] < 37.0 and vest < 0.025,
			"CROSS ready: his wrists within a real wrist's range (user: \"his hand position/rotation it looks a little off\"): at the ready %.0f° off the forearm (was ~90°), in the check the gun hand %.0f° and the left %.0f°; elbows clear of his vest (%.3f)" % [wrist[0], wrist[1], wrist[2], vest])
	lp.queue_free()

	# The check's sounds (user: "add them"): each once a loop, in order, as the loop passes it.
	var heard := []
	var sn := _rd_rig()
	sn.idle_beat.connect(func(sound: String) -> void: heard.append(sound))
	for f in int(SoldierRig.IDLE_LOOP / dt) + 2:
		sn.animate(dt, {"ready": true})
	_check(heard == ["slide_back", "slide_home", "mag_out", "mag_slap"], "CROSS ready: the check's sounds, each once a loop, in order (user: \"add them\"): %s" % [heard])
	sn.queue_free()

	# The gun check: the slide eased back, his left hand over it, his eyes on it, the gun up under
	# his chin; the slap (his hand up into the grip, the gun jolting); both hands on it at rest.
	_rd_at(r, 2.3)
	var slide := r._slide.position.z
	var pr := r._in_rig(r._pistol)
	var top := pr * (SoldierRig.IDLE_TOP_AT + Vector3(0.0, 0.0, r._slide.position.z))
	var left := r._in_rig(r.wrists[-1]) * (r._hand_mid[-1] as Vector3)
	var eyes := (r._in_rig(r.head).basis * Vector3.FORWARD).normalized()
	var high := pr.origin.y * SoldierRig.SIZE
	var press := slide >= 0.02 and left.distance_to(top) < 0.06 and eyes.y < -0.5 and high > 1.4 and high < 1.55
	_rd_at(r, 4.40)
	var hand_low := _rd_hand(r, -1).y
	_rd_at(r, 4.46)
	var gun_was := r._in_rig(r._pistol).origin.y
	_rd_at(r, 4.50)
	var slap := _rd_hand(r, -1).y - hand_low > 0.05 and (r._in_rig(r._pistol).origin.y - gun_was) * SoldierRig.SIZE > 0.008
	_rd_at(r, 0.5)
	var both := _rd_hand(r, -1).distance_to(_rd_hand(r, 1)) < 0.08
	_check(press and slap and both, "CROSS ready: he checks his gun (user): the press check (slide %.3f, hand %.3f off, eyes %.2f, gun %.2f m up), the slap, both hands on it" % [
			slide, left.distance_to(top), eyes.y, high])

	# START at every half second of the loop: he settles (never jumping, the slide let go at once,
	# eyes and hands back on the door and the grip by 0.5 s) and sets as the pan goes round, the
	# pistol off every pan camera (the cut and the eased start); the set lower, forward, the rear
	# heel up about the ball of his foot.
	var base := _rd_rig()
	_rd_at(base, 0.0)
	var settle := 0.0
	var settle_ok := true
	var pan_clear := 180.0
	var set_ok := true
	for i in 32:
		var st := _rd_rig()
		_rd_at(st, i * 0.5)
		var p0 := _rd_snap(st)
		for k in 210:
			var u := (k + 1) / 210.0
			st.animate(dt, {"ready": true, "pan": u})
			var now := _rd_snap(st)
			settle = maxf(settle, _rd_step(p0, now))
			p0 = now
			if k == 5:
				settle_ok = settle_ok and st._slide.position.z < 0.001
			if k == 31:
				var fw := (st._in_rig(st.head).basis * Vector3.FORWARD).normalized()
				settle_ok = settle_ok and absf(atan2(-fw.x, -fw.z)) < 0.1 and float(st._idle_c["w"]) > 0.999
			var e := smoothstep(0.0, 1.0, u)
			for s0 in [-0.7, 0.0, 0.7]:
				for fm in [0.0, tt.intro_from_menu]:
					pan_clear = minf(pan_clear, _rd_clear(st, IntroCamera.pan(e, 0.0, s0, fm, play_look)[0]))
		var ball := Vector3(SoldierRig.IDLE_FEET[1].x, (st._ankle_rest[1] as Vector3).y, SoldierRig.IDLE_FEET[1].y) + Basis(Vector3.UP, SoldierRig.IDLE_TOES[1]) * SoldierRig.IDLE_BALL
		var ank := st._in_rig(st.ankles[1]).origin
		var now_ball := ank + _rd_sole(st, 1) * SoldierRig.IDLE_BALL
		set_ok = set_ok and st.hips.position.y < base.hips.position.y - 0.025 and st.hips.position.z < base.hips.position.z - 0.06 \
				and ank.y > (st._ankle_rest[1] as Vector3).y + 0.03 and now_ball.distance_to(ball) < 0.01
		st.queue_free()
	_check(settle < 0.25 and settle_ok and set_ok, "CROSS ready: START settles him (never jumping: %.3f rad) and sets him for the run as the camera comes round" % settle)
	_check(pan_clear > 35.0, "CROSS ready: the pistol never at the opening pan's camera (%.1f° off at closest)" % pan_clear)

	# A tap that skips the pan, then the camera catching up as he runs: the pistol never at it.
	var skip_clear := 180.0
	for s0 in [-0.7, 0.7]:
		for t0 in [1.95, 3.7, 4.44, 10.3]:
			for skip in [0.02, 0.3, 1.2, 2.5]:
				var sk := _rd_rig()
				_rd_at(sk, t0)
				var cam := Transform3D()
				for k in int(round(skip * 60.0)):
					var u := (k + 1) / 210.0
					sk.animate(dt, {"ready": true, "pan": u})
					var c := IntroCamera.pan(smoothstep(0.0, 1.0, u), 0.0, s0, tt.intro_from_menu, play_look)
					cam = Transform3D(Basis.IDENTITY, c[0]).looking_at(c[1], Vector3.UP)
					skip_clear = minf(skip_clear, _rd_clear(sk, cam.origin))
				var d := 0.0
				for k in 60:
					d += tt.run_speed * dt
					sk.position = Vector3(0.0, 0.0, -d)
					sk.animate(dt, {"run": 1.0})
					var target := Transform3D(Basis.IDENTITY, Vector3(0.0, 3.4, 5.5 - d)).looking_at(Vector3(0.0, 1.0, -10.0 - d), Vector3.UP)
					cam = cam.interpolate_with(target, clampf(dt * 8.0, 0.0, 1.0))
					skip_clear = minf(skip_clear, _rd_clear(sk, cam.origin))
				sk.queue_free()
	_check(skip_clear > 35.0, "CROSS ready: the pistol never at the camera catching up after a skipped pan (%.1f° off at closest)" % skip_clear)

	# Into the run (user: "his start stance can't be standing still"): from 16 moments of the loop,
	# the check, the alarm, mid-settle, mid-set, the pan's end and the set Retry and the bots start
	# in: the stride at once, his rear (right) foot up first, no joint jumping, the slide home, then
	# exactly the run; FIRE still brings the gun up level and straight ahead.
	var starts := []
	for i in 16:
		starts.append([float(i), -1])
	starts.append_array([[1.95, -1], [3.7, -1], [4.44, -1], [7.25, -1], [10.3, -1], [1.95, 12], [3.7, 126], [10.3, 210], [0.0, -2]])
	var launch := 0.0
	var launch_ok := true
	var let_go := 0.0
	var fire := 0.0
	for st in starts:
		var g := _rd_rig()
		if int(st[1]) == -2:
			g.pose_set()
		else:
			_rd_at(g, float(st[0]))
			for k in int(st[1]):
				g.animate(dt, {"ready": true, "pan": (k + 1) / 210.0})
		var p0 := _rd_snap(g)
		for k in 36:
			g.animate(dt, {"run": 1.0})
			var now := _rd_snap(g)
			launch = maxf(launch, _rd_step(p0, now))
			p0 = now
			if k == 0:
				launch_ok = launch_ok and is_equal_approx(g._run, 1.0)
			if k == 5:
				launch_ok = launch_ok and g._in_rig(g.ankles[1]).origin.y > g._in_rig(g.ankles[-1]).origin.y and g._slide.position.z < 0.001
		var plain := SoldierRig.new()
		root.add_child(plain)
		plain._phase = g._phase
		plain._run = g._run
		g.animate(dt, {"run": 1.0})
		plain.animate(dt, {"run": 1.0})
		var ga := _rd_snap(g)
		var pa := _rd_snap(plain)
		for k in range(1, ga.size()):
			let_go = maxf(let_go, (Basis(ga[k] as Quaternion).get_euler() - Basis(pa[k] as Quaternion).get_euler()).abs().length())
		plain.queue_free()
		g.queue_free()
		var q := _rd_rig()
		if int(st[1]) == -2:
			q.pose_set()
		else:
			_rd_at(q, float(st[0]))
		for k in 6:
			q.animate(dt, {"run": 1.0})
		q.animate(dt, {"run": 1.0, "aim": true})
		q.recoil()
		fire = maxf(fire, rad_to_deg((q._in_rig(q._muzzle).basis * Vector3.FORWARD).angle_to(Vector3.FORWARD)))
		q.queue_free()
	_check(launch < 0.25 and launch_ok and let_go < 0.001 and fire < 2.0,
			"CROSS springs into the run from his stance, rear leg first, no joint jumping (user: %.3f rad, was 0.870 from standing), then exactly the run; FIRE level ahead (%.1f°)" % [launch, fire])

	# His standing pose as before (wall cover, the boss standoff, after the run): a rig never in the
	# stance stands exactly as it did.
	var sd := SoldierRig.new()
	root.add_child(sd)
	sd.animate(dt, {"run": 0.0})
	var got := _rd_snap(sd)
	sd._reset()
	sd._pose_stand()
	sd._shrug()
	var want := _rd_snap(sd)
	var same := not sd._idle_on
	for k in range(1, got.size()):
		same = same and (got[k] as Quaternion).is_equal_approx(want[k])
	_check(same and (got[0] as Vector3).is_equal_approx(want[0]), "CROSS ready: his standing pose (wall cover, the standoff, after the run) as before")
	sd.queue_free()
	base.queue_free()
	r.queue_free()


## The camera before the run (IntroCamera): START doesn't cut (the pan starts exactly where the
## menu's camera was and eases onto the approved path), then exactly the pan the user approved
## ("keep the current values"), never turning back, ending exactly on the play camera.
func _test_intro_camera() -> void:
	var tt := Tuning.new()
	var play := Vector3(0.0, 1.0, -10.0)
	var fm := tt.intro_from_menu
	var no_cut := fm > 0.0
	for h in [480.0, 585.0, 640.0]:
		for i in 41:
			var s := -0.7 + i * 0.035
			var p := IntroCamera.pan(0.0, 0.0, s, fm, play, h)
			var m := IntroCamera.menu(s, 0.0, h)
			no_cut = no_cut and (p[0] as Vector3).distance_to(m[0]) < 1e-4 and (p[1] as Vector3).distance_to(m[1]) < 1e-4 and absf(float(p[2]) - float(m[2])) < 1e-4
	_check(no_cut, "the opening pan: START doesn't cut, it starts exactly where the menu's camera was (and with its view, on a tall phone too)")
	# A tall phone: the menu's view opened up to keep him the size he is on a 480-high screen, eased
	# back to the play camera's as the pan leaves the menu, never jumping, then exactly the play view.
	var tall := is_equal_approx(IntroCamera.menu_fov(480.0), IntroCamera.FOV) and is_equal_approx(IntroCamera.menu_look(480.0), IntroCamera.MENU_LOOK)
	tall = tall and IntroCamera.menu_fov(585.0) > IntroCamera.FOV + 5.0 and IntroCamera.menu_look(585.0) < IntroCamera.MENU_LOOK
	var last_fov := INF
	var fov_step := 0.0
	for k in 101:
		var v := float(IntroCamera.pan(k / 100.0, 0.0, 0.4, fm, play, 585.0)[2])
		tall = tall and v <= last_fov + 1e-5 and (k / 100.0 < fm or is_equal_approx(v, IntroCamera.FOV))
		if k > 0:
			fov_step = maxf(fov_step, last_fov - v)
		last_fov = v
	_check(tall and fov_step < 1.0, "the opening pan on a tall phone: the menu's wider view (%.1f°) eases back to the play camera's (%.0f°) as it leaves the menu, at most %.2f° a step, then exactly it" % [IntroCamera.menu_fov(585.0), IntroCamera.FOV, fov_step])
	var approved := true
	for e in [0.0, 0.25, 0.5, 0.75, 1.0]:
		var angle: float = PI * e
		var rr := lerpf(3.0, 5.5, e * e)
		var eye := Vector3(sin(angle) * rr * 0.75, lerpf(1.5, 3.4, e), -cos(angle) * rr)
		var at := Vector3(0.0, 1.3, 0.0).lerp(play, smoothstep(0.75, 1.0, e))
		var p := IntroCamera.pan(e, 0.0, 0.6, 0.0, play)
		approved = approved and (p[0] as Vector3).distance_to(eye) < 1e-4 and (p[1] as Vector3).distance_to(at) < 1e-4
	for s in [-0.7, 0.0, 0.7]:
		for k in 66:
			var e := fm + k * (1.0 - fm) / 65.0
			var a := IntroCamera.pan(e, 0.0, s, fm, play)
			var b := IntroCamera.pan(e, 0.0, s, 0.0, play)
			approved = approved and (a[0] as Vector3).distance_to(b[0]) < 1e-4 and (a[1] as Vector3).distance_to(b[1]) < 1e-4
	var end := IntroCamera.pan(1.0, 0.0, 0.5, fm, play)
	approved = approved and (end[0] as Vector3).distance_to(Vector3(0.0, 3.4, 5.5)) < 1e-4 and (end[1] as Vector3).distance_to(play) < 1e-4
	var forward := true
	for s in [-0.7, 0.0, 0.7]:
		var last := -INF
		for k in 100:
			var p := IntroCamera.pan(k / 100.0, 0.0, s, fm, play)
			var ang := atan2((p[0] as Vector3).x, -(p[0] as Vector3).z)
			forward = forward and ang >= last - 1e-5
			last = ang
	_check(approved and forward, "the opening pan: then exactly the approved path (user: \"keep the current values\"), never turning back, ending on the play camera")


## The start room (user, 2026-10-07: "a bit smaller ... a window on the back wall"): it holds every
## camera before the run (the menu at every sway on a 480-high screen and a tall phone, the opening
## pan from every sway, eased off the menu or cut, and the play camera it ends on), each at least
## 0.5 m inside its side and back walls and 0.35 m under its ceiling, with the door wall 0.5 m
## ahead; and the back wall's windows land between the menu's title (y 180) and its buttons (y 290).
func _test_start_room() -> void:
	var tt := Tuning.new()
	var k: Dictionary = (load("res://game/levels/prototype_slice/prototype_slice.gd") as Script).get_script_constant_map()
	var half: float = k["START_ROOM_HALF"]
	var top: float = k["CEILING_Y"]
	var S := tt.start_offset
	var L := tt.start_room_length
	var play_look := Vector3(0.0, 1.0, -10.0)
	var worst := INF
	var at := ""
	var eyes: Array[Vector3] = []
	for h in [480.0, 585.0]:
		var s := -IntroCamera.SWAY
		while s <= IntroCamera.SWAY + 1e-4:
			eyes.append(IntroCamera.menu(s, 0.0, h)[0])
			s += 0.05
		for s0 in [-0.7, -0.35, 0.0, 0.35, 0.7]:
			for fm in [0.0, tt.intro_from_menu]:
				for i in 101:
					eyes.append(IntroCamera.pan(i / 100.0, 0.0, s0, fm, play_look, h)[0])
	eyes.append(Vector3(0.0, 3.4, 5.5))  # (the play camera at the run's start, and on Retry)
	for e in eyes:
		var z := S + e.z  # (back from the door wall's face)
		var m := minf(minf(half - absf(e.x), L - z), minf(z, (top - 0.35) - e.y + 0.5))
		if m < worst:
			worst = m
			at = "x %+.2f y %.2f z %.2f" % [e.x, e.y, z]
	_check(worst >= 0.5, "start room: every camera before the run 0.5 m or more inside its walls (closest %.2f m, at %s)" % [worst, at])
	var cx: float = minf(0.25 * (L - S + IntroCamera.MENU_R), half - float(k["START_WIN_W"]) / 2.0 - 0.5)
	var ok := cx > 1.5
	var hi := INF
	var lo := -INF
	for h in [480.0, 585.0]:
		var s := -IntroCamera.SWAY
		while s <= IntroCamera.SWAY + 1e-4:
			for x in [-cx, 0.0, cx]:
				for side in [-0.5, 0.5]:  # (its corners on screen)
					var wx: float = x + side * float(k["START_WIN_W"])
					var head := _rd_screen(Vector3(wx, float(k["START_WIN_HEAD"]), L - S), s, h)
					var sill := _rd_screen(Vector3(wx, float(k["START_WIN_SILL"]), L - S), s, h)
					if head.x >= 0.0 and head.x <= 270.0:
						ok = ok and head.y > 180.0 and sill.y < 290.0
						hi = minf(hi, head.y)
						lo = maxf(lo, sill.y)
			s += 0.05
	_check(ok, "start room: its back windows between the menu's title and its buttons at every sway, on a 480-high screen and a tall phone (y %.0f to %.0f)" % [hi, lo])


## The lighting's lamp slots (Ambience): the 12 lamps nearest a point 8 m in front of the camera,
## but one whose pool can't reach anything in view (behind the camera, off to the side) comes after
## every one that can; with more lamps in view than slots, one that gets a slot or loses one while
## you'd see it fades in or out over EASE s instead of popping, and one holding a slot keeps it
## over one less than STICK m nearer; a camera cut just sets them.
func _test_lamp_slots() -> void:
	var tt := Tuning.new()
	var amb := Ambience.new()
	amb.tuning = tt
	root.add_child(amb)
	var cam := Camera3D.new()  # at the origin, looking down -z
	root.add_child(cam)
	var b := tt.brightness
	var dt := 1.0 / 60.0
	var made: Array[Node3D] = []
	var add := func(p: Vector3) -> Node3D:
		var n := Node3D.new()
		root.add_child(n)
		n.position = p
		amb.add_lamp(n, Color.WHITE, 5.0, {"alert": false})
		made.append(n)
		return n
	var lit_of := func(n: Node3D) -> float:
		var i: int = amb.slot_nodes.find(n)
		return amb.slot_lit[i] if i >= 0 and i < Ambience.SLOTS else -1.0  # (-1: no slot)
	var tick := func(frames: int) -> void:
		for f in frames:
			amb.update(dt, cam, 1)
	var ease_frames := ceili(Ambience.EASE / dt)
	var full := func(n: Node3D) -> float:  # how lit it is with its slot, all the way on
		return b * clampf((tt.lamp_fade_far - n.global_position.distance_to(cam.global_position - cam.global_basis.z * Ambience.FOCUS_AHEAD)) / 10.0, 0.0, 1.0)
	var ahead: Array[Node3D] = []
	for i in Ambience.SLOTS:
		ahead.append(add.call(Vector3(0.0, 1.0, -10.0 - 2.0 * i)))  # 2 .. 24 m from the focus
	var behind: Node3D = add.call(Vector3(0.0, 1.0, 10.0))  # 18 m from the focus, 10 m behind the lens (its pool 5 m)
	tick.call(1)
	var ok: bool = lit_of.call(behind) < 0.0
	for n in ahead:
		ok = ok and is_equal_approx(lit_of.call(n), full.call(n))
	_check(ok, "lamps: one whose pool can't reach the view (10 m behind the camera) gives its slot to the 12 ahead, all lit full")
	# Slots to spare: one out of view still has one, as before.
	ahead[0].visible = false
	tick.call(1)
	_check(is_equal_approx(lit_of.call(behind), b) and lit_of.call(ahead[0]) < 0.0, "lamps: with a slot to spare, one out of view still has it, lit as before")
	ahead[0].visible = true
	tick.call(1)
	# A lamp ahead, faded in by distance (32 m off: 0.2) but waiting for a slot, gets one: it comes on
	# from dark over EASE s, not at once.
	var far: Node3D = add.call(Vector3(0.0, 1.0, -40.0))
	tick.call(1)
	var waits: bool = lit_of.call(far) < 0.0
	ahead[5].visible = false
	var seq: Array[float] = []
	for f in ease_frames + 3:
		tick.call(1)
		seq.append(lit_of.call(far))
	var fade_far := clampf((tt.lamp_fade_far - far.position.distance_to(Vector3(0.0, 0.0, -Ambience.FOCUS_AHEAD))) / 10.0, 0.0, 1.0)
	var eased: bool = waits and fade_far > 0.1 and seq[0] >= 0.0 and seq[0] < 0.05 * b
	for i in range(1, seq.size()):
		eased = eased and seq[i] >= seq[i - 1] - 1e-6
	eased = eased and is_equal_approx(seq[seq.size() - 1], fade_far * b) and seq[ease_frames - 3] < fade_far * b
	_check(eased, "lamps: one faded in by distance that gets a slot comes on over %.1f s (from %.2f to %.2f), not at once" % [Ambience.EASE, seq[0], seq[seq.size() - 1]])
	ahead[5].visible = true
	tick.call(ease_frames + 2)
	# A lamp nearer than the farthest held by more than STICK: the farthest goes off over EASE s, still
	# in its slot, and the new one only gets it then, coming on from dark.
	var farthest_held := func() -> Node3D:
		var w: Node3D = null
		for n in amb.slot_nodes.slice(0, Ambience.SLOTS):
			if n != null and (w == null or (n as Node3D).position.z < w.position.z):
				w = n
		return w
	var farthest: Node3D = farthest_held.call()
	var near: Node3D = add.call(Vector3(0.0, 1.0, -10.5))
	var out: Array[float] = []
	var new_in := -1
	for f in ease_frames + 10:
		tick.call(1)
		out.append(lit_of.call(farthest))
		if new_in < 0 and lit_of.call(near) >= 0.0:
			new_in = f
	var gone := out.find(-1.0)
	var goes: bool = out[0] > 0.8 * b and out[0] < b and gone > 0 and gone <= ease_frames + 1 and new_in == gone
	for i in range(1, gone if gone > 0 else out.size()):
		goes = goes and out[i] < out[i - 1]
	tick.call(ease_frames)
	goes = goes and is_equal_approx(lit_of.call(near), full.call(near))
	_check(goes, "lamps: one losing its slot in view goes off over %.1f s (%d frames), and the nearer one gets the slot then (frame %d), coming on from dark" % [Ambience.EASE, gone, new_in])
	# STICK: a lamp just 0.5 m nearer than the farthest held doesn't take its slot at once, nor one
	# swinging either side of it every few frames; one staying nearer gets it after STICK_TIME s.
	farthest = farthest_held.call()
	var spare: Node3D = null  # (a lamp in view without a slot: the one that went off)
	for n in made:
		if n.visible and n != behind and lit_of.call(n) < 0.0:
			spare = n
	var focus := Vector3(0.0, 0.0, -Ambience.FOCUS_AHEAD)
	var d_far := farthest.position.distance_to(focus)
	var way := Vector3(0.3, 1.0, -(d_far - 0.5)).normalized()  # (from the focus, ahead and a little aside)
	var swings := true
	for f in 120:  # 2 s, 0.3 m nearer, then 0.3 m farther, every 3 frames
		spare.position = focus + way * (d_far + (0.3 if (f / 3) % 2 == 0 else -0.3))
		tick.call(1)
		swings = swings and is_equal_approx(lit_of.call(farthest), full.call(farthest)) and lit_of.call(spare) < 0.0
	spare.position = focus + way * (d_far + 0.5)  # (back out of the way a moment)
	tick.call(2)
	spare.position = focus + way * (d_far - 0.5)
	tick.call(floori(Ambience.STICK_TIME / dt) - 2)  # (just under STICK_TIME)
	var sticks: bool = lit_of.call(spare) < 0.0 and is_equal_approx(lit_of.call(farthest), full.call(farthest))
	tick.call(ceili((Ambience.STICK_TIME + 2.0 * Ambience.EASE) / dt) + 4)
	sticks = sticks and is_equal_approx(lit_of.call(spare), full.call(spare)) and lit_of.call(farthest) < 0.0
	_check(spare != null and swings and sticks, "lamps: one holding a slot keeps it over one swinging 0.3 m either side of it, and over one 0.5 m nearer for %.2f s (STICK %.1f m); then the nearer one gets it" % [Ambience.STICK_TIME, Ambience.STICK])
	# A cut (the camera 200 m on in a frame): the slots are just set, every new lamp lit full at once.
	var there: Array[Node3D] = []
	for i in Ambience.SLOTS:
		there.append(add.call(Vector3(0.0, 1.0, -210.0 - 2.0 * i)))
	cam.position = Vector3(0.0, 0.0, -200.0)
	tick.call(1)
	var cut := true
	for n in there:
		cut = cut and is_equal_approx(lit_of.call(n), full.call(n))
	_check(cut, "lamps: a camera cut sets the slots at once (the new place's 12 lamps lit full on its first frame)")
	for n in made:
		n.queue_free()
	cam.queue_free()
	amb.queue_free()


## What the lamp slots (Ambience) count as in view, and the rear-view CCTV: whether a lamp's pool
## reaches into a camera's picture is that camera's own frustum (Camera3D.get_frustum), whatever its
## lens, shape and turn; while the rear monitor is up, a lamp behind the camera that it shows ranks by
## its distance from the focus with the lamps ahead (as every lamp did before lamps out of view went
## last), so it takes the farthest one's slot, and without it comes last again, going off at once (a
## lamp on the screen never waits for it to fade) while the farthest comes back on from dark; and an
## update makes nothing new, not even for a moment, with the rear camera or without.
func _test_lamp_views() -> void:
	# The view test against Camera3D.get_frustum: a play camera (portrait, turned), a long-lens CCTV in
	# its own 128x72 picture, and one keeping its width.
	var rear_vp := SubViewport.new()
	rear_vp.size = Vector2i(128, 72)
	root.add_child(rear_vp)
	var play := Camera3D.new()
	root.add_child(play)
	play.position = Vector3(1.0, 3.4, 5.5)
	play.rotation = Vector3(-0.35, 0.4, 0.05)
	var cctv := Camera3D.new()
	cctv.fov = 30.0
	cctv.far = 70.0
	rear_vp.add_child(cctv)
	cctv.position = Vector3(0.0, 2.4, -1.0)
	cctv.rotation = Vector3(-0.1, PI, 0.0)
	var wide := Camera3D.new()
	wide.keep_aspect = Camera3D.KEEP_WIDTH
	wide.fov = 50.0
	wide.near = 0.3
	wide.far = 40.0
	root.add_child(wide)
	wide.rotation = Vector3(0.2, -1.1, 0.0)
	var view := Ambience.View.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var wrong := 0
	var ins := 0
	var outs := 0
	for c: Camera3D in [play, cctv, wide]:
		view.aim(c)
		var planes := c.get_frustum()
		for k in 600:
			var p := c.global_position + Vector3(rng.randf_range(-45, 45), rng.randf_range(-20, 20), rng.randf_range(-45, 45))
			var r := rng.randf_range(0.5, 12.0)
			var want := true
			var edge := INF
			for side in planes:
				want = want and side.distance_to(p) < r
				edge = minf(edge, absf(side.distance_to(p) - r))
			if edge > 0.001 and view.reaches(p, r) != want:
				wrong += 1
			ins += int(want)
			outs += int(not want)
	_check(wrong == 0 and ins > 100 and outs > 100, "lamps: a pool reaching into the picture is the camera's own frustum, for a play camera, a long-lens CCTV and one keeping its width (%d of %d differ)" % [wrong, ins + outs])
	# The rear monitor: 12 lamps ahead, 2 to 24 m from the focus, and one 6 m behind the camera (14 m
	# from the focus), which only the rear camera sees.
	var tt := Tuning.new()
	var b := tt.brightness
	var amb := Ambience.new()
	amb.tuning = tt
	root.add_child(amb)
	var cam := Camera3D.new()  # at the origin, looking down -z
	root.add_child(cam)
	cctv.position = Vector3(0.0, 2.0, -1.0)
	cctv.rotation = Vector3(-0.08, PI, 0.0)  # looking back, past the camera
	var made: Array[Node3D] = []
	for i in Ambience.SLOTS:
		var n := Node3D.new()
		root.add_child(n)
		n.position = Vector3(0.0, 1.0, -10.0 - 2.0 * i)
		amb.add_lamp(n, Color.WHITE, 5.0, {"alert": false})
		made.append(n)
	var behind := Node3D.new()
	root.add_child(behind)
	behind.position = Vector3(0.0, 1.0, 6.0)
	amb.add_lamp(behind, Color.WHITE, 5.0, {"alert": false})
	var farthest: Node3D = made[-1]
	var dt := 1.0 / 60.0
	var lit_of := func(n: Node3D) -> float:
		var i: int = amb.slot_nodes.find(n)
		return amb.slot_lit[i] if i >= 0 and i < Ambience.SLOTS else -1.0  # (-1: no slot)
	var tick := func(frames: int, with_rear: Camera3D) -> void:
		for f in frames:
			amb.update(dt, cam, 1, with_rear)
	tick.call(30, null)
	var without: bool = lit_of.call(behind) < 0.0 and lit_of.call(farthest) > 0.0
	var seen_rear := Ambience.View.new()
	seen_rear.aim(cctv)
	view.aim(cam)
	var only_rear := seen_rear.reaches(behind.position, 5.0) and not view.reaches(behind.position, 5.0)
	tick.call(ceili((Ambience.STICK_TIME + 2.0 * Ambience.EASE) / dt) + 4, cctv)
	var fade_behind := clampf((tt.lamp_fade_far - behind.position.distance_to(Vector3(0.0, 0.0, -Ambience.FOCUS_AHEAD))) / 10.0, 0.0, 1.0)
	var with_rear_up: bool = is_equal_approx(lit_of.call(behind), fade_behind * b) and lit_of.call(farthest) < 0.0
	_check(only_rear and without and with_rear_up, "lamps: with the rear monitor up, a lamp behind the camera that it shows ranks by its distance with the lamps ahead and takes the farthest one's slot; without it, it comes last")
	# The monitor still up, its lamp further back (28 m from the focus) loses its slot to the farthest
	# one ahead: it goes off at once, so the farthest comes on from dark that frame, nothing waiting.
	var full_far := clampf((tt.lamp_fade_far - farthest.position.distance_to(Vector3(0.0, 0.0, -Ambience.FOCUS_AHEAD))) / 10.0, 0.0, 1.0) * b
	behind.position = Vector3(0.0, 1.0, 20.0)
	var back_in: Array[float] = []
	var gone_at_once := true
	for f in ceili(Ambience.EASE / dt) + 2:
		tick.call(1, cctv)
		back_in.append(lit_of.call(farthest))
		gone_at_once = gone_at_once and lit_of.call(behind) < 0.0
	var eases: bool = back_in[0] >= 0.0 and back_in[0] < 0.2 * b and is_equal_approx(back_in[-1], full_far)
	# The monitor gone, with its lamp back in a slot: it goes off at once too.
	behind.position = Vector3(0.0, 1.0, 6.0)
	tick.call(ceili((Ambience.STICK_TIME + 2.0 * Ambience.EASE) / dt) + 4, cctv)
	var retaken: bool = lit_of.call(behind) > 0.0
	tick.call(1, null)
	gone_at_once = gone_at_once and retaken and lit_of.call(behind) < 0.0
	_check(gone_at_once and eases, "lamps: a lamp only the rear monitor shows goes off at once when it loses its slot, or when the monitor goes (nothing on the screen waits for it), and the farthest one ahead comes on from dark that frame (%.2f to %.2f)" % [back_in[0], back_in[-1]])
	# Nothing made in an update (memory held at a new high, then any allocation would raise it): first
	# a check that this catches one.
	tick.call(3, cctv)
	var make := func() -> void:
		var a := []
		a.resize(8)
	var caught := _allocates(make)
	var main_only := amb.update.bind(dt, cam, 1, null)
	var both := amb.update.bind(dt, cam, 1, cctv)
	var made_new := 0
	for k in 5:
		made_new += _allocates(main_only) + _allocates(both)
	_check(caught > 0 and made_new == 0, "lamps: an update makes nothing new, with the rear monitor up or not (%d bytes over 10 updates; a new array caught: %d)" % [made_new, caught])
	for n in made:
		n.queue_free()
	behind.queue_free()
	for n: Node in [play, wide, cam, rear_vp, amb]:
		n.queue_free()


## How much memory `c` takes while it runs, however briefly (bytes): the memory in use is first
## brought up to its highest yet (held while `c` runs), so anything `c` makes raises the highest.
func _allocates(c: Callable) -> int:
	var hold := PackedByteArray()
	hold.resize(OS.get_static_memory_peak_usage() - OS.get_static_memory_usage() + 65536)
	var before := OS.get_static_memory_peak_usage()
	c.call()
	var grew := OS.get_static_memory_peak_usage() - before
	hold = PackedByteArray()
	return grew


## Things hanging where the camera passes (3.4 m up, 5.5 m behind him, anywhere from 2.8 m left to
## 2.8 m right): the WAREHOUSE's dome lamps and the SEWER's tubes hang half a metre or more over it
## (their light still shines from where it did); a duck-under's cables, chains and rods dither away
## near the lens (PsxMaterials.lens_faded, the PS1 shader's lens_fade); a light in the air (a beam, a
## lamp's halo) fades out near it. The boss's tracers and the guards' glare keep their halo as it was.
func _test_hanging() -> void:
	var k: Dictionary = (load("res://game/levels/prototype_slice/prototype_slice.gd") as Script).get_script_constant_map()
	var top: float = k["CEILING_Y"]
	var cam_y := 3.4  # (the play camera's height over the floor: _place_camera)
	var bulb: float = top - float(k["PENDANT_DROP"]) - 0.17  # the dome lamp's bulb, its lowest point
	var tube: float = top - float(k["TUBE_DROP"]) - 0.10  # the sewer tube's glowing face
	_check(bulb - cam_y >= 0.5 and tube - cam_y >= 0.5 and bulb < top - 0.3, "hanging lamps: the warehouse's dome lamps (bulb at %.2f m) and the sewer's tubes (%.2f m) hang 0.5 m or more over the camera (%.1f m), still under the ceiling" % [bulb, tube, cam_y])
	var c := Color("2a2c2e")
	var lf := PsxMaterials.lens_faded(c)
	var plain = PsxMaterials.flat(c).get_shader_parameter("lens_fade")
	var faded: bool = lf.shader == PsxMaterials.SHADER and lf.get_shader_parameter("albedo") == c and is_equal_approx(float(lf.get_shader_parameter("lens_fade")), PsxMaterials.LENS_FADE)
	faded = faded and (plain == null or float(plain) == 0.0) and lf != PsxMaterials.flat(c) and PsxMaterials.lens_faded(c) == lf
	faded = faded and PsxMaterials.SHADER.code.contains("uniform float lens_fade = 0.0;") and PsxMaterials.SHADER.code.contains("2.0 - 2.0 * distance(world_pos, CAMERA_POSITION_WORLD) / lens_fade")
	_check(faded, "hanging lamps: a duck-under's hangers are their own colour, dithering away nearer the lens than %.1f m (gone at %.1f); plain colours never" % [PsxMaterials.LENS_FADE, PsxMaterials.LENS_FADE / 2.0])
	var beam := PsxMaterials.beam(Color(1, 1, 1, 0.1))
	var halo := PsxMaterials.lamp_halo(Color(1, 0.8, 0.5, 0.5))
	var air: bool = beam.distance_fade_mode == BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA and is_equal_approx(beam.distance_fade_min_distance, PsxMaterials.BEAM_FADE.x) \
			and is_equal_approx(beam.distance_fade_max_distance, PsxMaterials.BEAM_FADE.y)
	air = air and halo.distance_fade_mode == BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA and is_equal_approx(halo.distance_fade_min_distance, PsxMaterials.HALO_FADE.x) \
			and is_equal_approx(halo.distance_fade_max_distance, PsxMaterials.HALO_FADE.y) and halo.billboard_mode == BaseMaterial3D.BILLBOARD_ENABLED
	air = air and PsxMaterials.halo(Color(1, 0.8, 0.5, 0.5)).distance_fade_mode == BaseMaterial3D.DISTANCE_FADE_DISABLED
	_check(air, "hanging lamps: a beam fades out nearer the lens than %.1f m (none of it within %.1f), a lamp's halo nearer than %.1f m (none within %.1f); other halos as they were" % [PsxMaterials.BEAM_FADE.y, PsxMaterials.BEAM_FADE.x, PsxMaterials.HALO_FADE.y, PsxMaterials.HALO_FADE.x])


## The cutout (Cutout; user: "anything in front of the camera between the lens and Cross is
## faded/dissolved out"), the user's pick: a round hole 2.5 m round his chest (5 m across at his
## distance; it was 1.8 m, too tight round him), the same size on screen all the way to the lens (a
## cone), fully open in the middle and dithered over the outer 30% of its radius; only nearer the
## lens than him, with a short fade; never the floor under him; up with his jump, and down into a
## slide (eased over 0.12 s); on for the menu, the opening pan and the play camera, off on the
## stairwells' security cameras, just out of a stairwell and in the boss's KO replay. CROSS's own
## materials never dissolve (his pistol and his hit flash too); a guard's and the level's do, its
## glass too (the same hole).
func _test_cutout() -> void:
	var feet := Vector3(2.0, 3.0, -40.0)
	var eye := feet + Vector3(0.6, 3.4, 5.5)  # the play camera, behind and above him
	Cutout.aim(eye, feet, true)
	var chest := Cutout.centre(feet, 0.0)
	var depth := eye.distance_to(chest)
	var side := (chest - eye).cross(Vector3.UP).normalized()  # square to the view of him
	# s of the way from the lens to his chest, k radii off the line to it (as seen from the lens).
	var at := func(s: float, k: float) -> Vector3: return eye + (chest - eye) * s + side * (Cutout.RADIUS * k * s)
	var cone := chest.is_equal_approx(feet + Vector3(0, 1.25, 0)) and is_equal_approx(Cutout.RADIUS, 2.5) and is_equal_approx(Cutout.EDGE, 0.3)
	for s in [0.15, 0.4, 0.7]:
		cone = cone and is_equal_approx(_cut_cover(at.call(s, 0.0)), 1.0) and is_equal_approx(_cut_cover(at.call(s, 0.69)), 1.0)
		cone = cone and absf(_cut_cover(at.call(s, 0.85)) - 0.5) < 0.01 and _cut_cover(at.call(s, 1.01)) == 0.0
	_check(cone, "the cutout: a round hole round his chest, 2.5 m in radius at his distance (5 m across), as big on screen all the way to the lens (a cone), open in the middle and dithered over the outer 30%")
	# How far along the line to him a pixel is dissolved: up to his chest less 0.35 m, fading over 0.35 m.
	var stop := (depth - Cutout.MARGIN) / depth
	var fade := Cutout.DEPTH_FADE / depth
	var near := is_equal_approx(_cut_cover(at.call(stop - fade * 1.05, 0.0)), 1.0) and absf(_cut_cover(at.call(stop - fade * 0.5, 0.0)) - 0.5) < 0.01
	near = near and _cut_cover(at.call(stop + 0.01, 0.0)) == 0.0 and _cut_cover(at.call(1.0, 0.0)) == 0.0 and _cut_cover(at.call(1.3, 0.0)) == 0.0
	_check(near, "the cutout: only what's nearer the lens than him (less 0.35 m, fading over 0.35 m): never him, nor anything beyond him")
	# The floor under him: nothing lower than 6 cm over his feet, jumping too, the camera even below it.
	var floor_kept := is_equal_approx(Cutout.misc.x, feet.y + 0.06)
	Cutout.aim(eye, feet, true, Cutout.lift(1.28, 0.0))
	floor_kept = floor_kept and is_equal_approx(Cutout.misc.x, feet.y + 0.06)
	var low := feet + Vector3(0.0, -1.0, 5.0)
	Cutout.aim(low, feet, true)
	var to := chest - low
	floor_kept = floor_kept and _cut_cover(low + to * 0.4) == 0.0 and is_equal_approx(_cut_cover(low + to * 0.6), 1.0)
	_check(floor_kept, "the cutout: the floor under him never dissolves (nothing lower than 6 cm over his feet), jumping or not, even with the camera below it")
	# It goes with him: up with his jump; down 0.65 m into a slide, eased over 0.12 s (and back).
	Cutout.aim(eye, feet, true, Cutout.lift(1.28, 0.0))
	var up := feet + Vector3(0.0, 1.25 + 1.28, 0.0)
	var follows := Vector3(Cutout.fwd.x, Cutout.fwd.y, Cutout.fwd.z).is_equal_approx((up - eye).normalized())
	follows = follows and is_equal_approx(_cut_cover(eye + (up - eye) * 0.5), 1.0)
	var dt := 1.0 / 60.0
	var slide := 0.0
	var eased := true
	var frames := 0
	while slide < 1.0 and frames < 30:
		var was := slide
		slide = Cutout.slide_toward(slide, true, dt)
		eased = eased and slide > was
		frames += 1
	var back := 0
	while slide > 0.0 and back < 30:
		slide = Cutout.slide_toward(slide, false, dt)
		back += 1
	follows = follows and eased and frames == ceili(0.12 / dt - 0.001) and back == frames
	follows = follows and is_equal_approx(Cutout.lift(0.0, 1.0), -0.65) and is_equal_approx(Cutout.lift(0.4, 0.5), 0.4 - 0.325)
	Cutout.aim(eye, feet, true, Cutout.lift(0.0, 1.0))
	var down := feet + Vector3(0.0, 1.25 - 0.65, 0.0)
	follows = follows and Vector3(Cutout.fwd.x, Cutout.fwd.y, Cutout.fwd.z).is_equal_approx((down - eye).normalized())
	_check(follows, "the cutout: the hole goes with him, up with his jump and 0.65 m down into a slide, eased over 0.12 s (%d frames) either way" % frames)
	# On for the menu, the opening pan and the play camera; off on the CCTV, just out, the KO replay.
	var shots := Cutout.on_for(Cutout.Shot.PLAY) and Cutout.on_for(Cutout.Shot.MENU) and Cutout.on_for(Cutout.Shot.PAN)
	shots = shots and not Cutout.on_for(Cutout.Shot.CCTV) and not Cutout.on_for(Cutout.Shot.JUST_OUT) and not Cutout.on_for(Cutout.Shot.KO)
	Cutout.aim(eye, feet, false)
	shots = shots and Cutout.cam.w == 0.0 and _cut_cover(at.call(0.4, 0.0)) == 0.0
	Cutout.aim(chest + Vector3(0.0, 0.0, 0.3), feet, true)  # right at the lens: off
	shots = shots and Cutout.cam.w == 0.0
	_check(shots, "the cutout: on for the menu, the opening pan and the play camera; off on the stairwells' security cameras, just out of a stairwell and in the boss's KO replay (and with him right at the lens)")
	# CROSS never: his body, his pistol and his hit flash; the guards and the level as they were.
	var cross := SoldierRig.new()
	cross.keep_solid()
	var solid := 0
	var all_solid := true
	for mi: MeshInstance3D in cross._meshes:
		if _psx(mi.material_override):
			solid += 1
			all_solid = all_solid and _cut_solid(mi.material_override)
	var pistol := 0
	for mi: MeshInstance3D in cross._pistol.find_children("*", "MeshInstance3D", true, false):
		if _psx(mi.material_override):
			pistol += 1
			all_solid = all_solid and _cut_solid(mi.material_override)
	cross.flash()
	for mi: MeshInstance3D in cross._meshes:
		all_solid = all_solid and (not _psx(mi.material_override) or _cut_solid(mi.material_override))
	cross.tick_flash(0.2)
	for i in cross._meshes.size():
		all_solid = all_solid and cross._meshes[i].material_override == cross._materials[i]
		all_solid = all_solid and (not _psx(cross._materials[i]) or _cut_solid(cross._materials[i]))
	var guard := GuardRig.new(GuardRifle.Kind.CARBINE)
	var guard_cut := 0
	for mi: MeshInstance3D in guard._meshes:
		if _psx(mi.material_override) and not _cut_solid(mi.material_override):
			guard_cut += 1
	var level_cut := not _cut_solid(PsxMaterials.flat(Color("d83a2a"))) and not _cut_solid(PsxMaterials.flat(Color("1c1c1e")))
	_check(solid > 0 and pistol >= 5 and all_solid and guard_cut > 0 and level_cut, "the cutout: CROSS never dissolves (%d of his materials, %d of them his pistol's, and his hit flash); a guard's (%d) and the level's do" % [solid, pistol, guard_cut])
	_test_cutout_figures(guard, eye, feet)
	cross.free()
	guard.free()
	# The glass goes with the frames round it: its shader cuts with the PS1 surface's own code.
	var inc := "#include \"res://assets/shaders/psx/psx_cutout.gdshaderinc\""
	var glass := PsxMaterials.glass(Color(0.55, 0.68, 0.82, 0.22))
	var same := PsxMaterials.is_glass(glass) and not PsxMaterials.is_glass(PsxMaterials.flat(Color("1c1c1e")))
	for sh: Shader in [PsxMaterials.SHADER, PsxMaterials.GLASS_SHADER]:
		same = same and sh.code.contains(inc) and sh.code.contains("cutout_drops(") and not sh.code.contains("float bayer4(")
	_check(same, "the cutout: glass dissolves as the PS1 surfaces round it do (the same hole on the same dither, from one shared include), so a pane never hangs over CROSS once its frame has gone")


## The cutout and the guards (and the dogs): one standing between the camera and CROSS dissolves all
## the way down, boots and all (his materials have no floor rule: PsxMaterials.figure), while the
## level keeps it (the floor under him stays); once he's down his body never dissolves (a guard who
## falls, the boss killed, a dog shot: SoldierRig.keep_solid, DogRig.keep_solid), what hangs on him
## too (a radio), so it doesn't melt away as you run past it; one still on his feet keeps
## dissolving. `live`: a guard on his feet; `eye` and `feet`: the play camera and CROSS, as aimed.
func _test_cutout_figures(live: GuardRig, eye: Vector3, feet: Vector3) -> void:
	var guard := GuardRig.new(GuardRifle.Kind.CARBINE)
	var dog := DogRig.new()
	var figures := 0
	var to_floor := true
	for mi: MeshInstance3D in live._meshes + dog._meshes:
		if _psx(mi.material_override):
			figures += 1
			to_floor = to_floor and _cut_to_floor(mi.material_override) and not _cut_solid(mi.material_override)
	var tile := ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGB8))
	var level_floor := not _cut_to_floor(PsxMaterials.flat(Color("1c1c1e"))) and not _cut_to_floor(PsxMaterials.textured(tile))
	# The boots of a guard 1.4 m in front of him, toward the camera: 2 cm over the floor.
	Cutout.aim(eye, feet, true)
	var boot := feet + Vector3(eye.x - feet.x, 0.0, eye.z - feet.z).normalized() * 1.4 + Vector3.UP * 0.02
	var boot_cut := _cut_cover(boot, false)
	var floor_kept := _cut_cover(boot, true)
	var lit_code: String = PsxMaterials.SHADER.code
	var inc := FileAccess.get_file_as_string("res://assets/shaders/psx/psx_cutout.gdshaderinc")
	var shader := lit_code.contains("uniform bool cutout_floor = true;") and lit_code.contains("FRAGCOORD.xy, cutout_floor)") 			and inc.contains("(keep_floor && at.y <= cutout_misc.x)") and PsxMaterials.GLASS_SHADER.code.contains("FRAGCOORD.xy, true)")
	_check(figures >= 3 and to_floor and level_floor and boot_cut > 0.5 and floor_kept == 0.0 and shader,
			"the cutout: a guard or a dog between the camera and CROSS dissolves all the way down (%d materials, boots and paws: %.2f of a boot cut), while the level's floor under him stays (%.2f)" % [figures, boot_cut, floor_kept])
	# Down: solid, his rifle and his radio too; the boss killed; a dog shot.
	var radio := MeshInstance3D.new()
	radio.mesh = BoxMesh.new()
	radio.material_override = PsxMaterials.flat(Color("1c1c1a"))
	guard.chest.add_child(radio)
	var cut_before := not _cut_solid(radio.material_override)
	guard.fall()
	var boss := GuardRig.new(GuardRifle.Kind.MINIGUN)
	boss.death_start({"travel": 0.2, "lift": 0.0, "room": 50.0, "back": false, "slide": false})
	dog.fall()
	var down := 0
	var all_down := cut_before
	for body: Node in [guard, boss, dog]:
		for mi: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):
			if _psx(mi.material_override):
				down += 1
				all_down = all_down and _cut_solid(mi.material_override)
	var still_cut := 0
	for mi: MeshInstance3D in live._meshes:
		if _psx(mi.material_override) and not _cut_solid(mi.material_override):
			still_cut += 1
	_check(down >= 7 and all_down and still_cut == figures - dog._meshes.size(),
			"the cutout: once down, a body never dissolves (%d materials: a guard who fell, his rifle and his radio, the boss killed, a dog shot), and one still on his feet still does (%d)" % [down, still_cut])
	guard.free()
	boss.free()
	dog.free()


## The shaders' cutout (psx_cutout.gdshaderinc), worked out the same way from what Cutout set: how
## much of a pixel at `p` is dissolved (0 none .. 1 all of it; the shader drops it where this beats
## the dither). keep_floor false: a material without the floor rule (a guard's, a dog's).
func _cut_cover(p: Vector3, keep_floor := true) -> float:
	var c := Cutout.cam
	if c.w <= 0.0 or (keep_floor and p.y <= Cutout.misc.x):
		return 0.0
	var v := p - Vector3(c.x, c.y, c.z)
	var f := Vector3(Cutout.fwd.x, Cutout.fwd.y, Cutout.fwd.z)
	var along := v.dot(f)
	var near := (Cutout.misc.y - along) * Cutout.misc.z
	if near <= 0.0 or along <= 0.01:
		return 0.0
	var d := (v / along - f).length() * Cutout.fwd.w
	return clampf((1.0 - d) * Cutout.misc.w, 0.0, 1.0) * minf(near, 1.0)


func _psx(m: Material) -> bool:
	return m is ShaderMaterial and (m as ShaderMaterial).shader == PsxMaterials.SHADER


## A PS1 material the cutout never dissolves (its "cutout" switched off: PsxMaterials.solid).
func _cut_solid(m: Material) -> bool:
	var v: Variant = (m as ShaderMaterial).get_shader_parameter("cutout")
	return typeof(v) == TYPE_BOOL and not v


## A PS1 material the cutout dissolves all the way to the floor (its floor rule off: PsxMaterials.figure).
func _cut_to_floor(m: Material) -> bool:
	var v: Variant = (m as ShaderMaterial).get_shader_parameter("cutout_floor")
	return typeof(v) == TYPE_BOOL and not v


## CROSS's pose changes eased (user, 2026-10-06: "adding easy to the key frames"; the decision log,
## "CROSS's animations eased"): into and out of a jump, a slide, cover (a box, a wall), the stumble,
## a stop and the surrender (caught with the gun up), no joint jumps (each frame's worst turn under
## half the old one-frame snap), the new pose three quarters there at once (the run's changes within
## 0.1 s), then exactly it; on the ground his boots never lower than at either end; a shot's re-pose
## doesn't move a change on; killed mid-change, his death starts from his legs as the pose has them
## (as it always has); FIRE held through a jump points the gun level ahead all the way; the guard
## (GuardRig) never eases.
func _test_cross_eased() -> void:
	var dt := 1.0 / 60.0
	var run := {"run": 1.0}
	# [name, state, frames (long enough to settle: the longest change is 0.3 s), most frames to three
	# quarters there]: a stop comes as his run dies away, as in the game
	var seq := [["takeoff", {"run": 1.0, "airborne": true, "rising": true}, 20, 6],
		["apex", {"run": 1.0, "airborne": true, "rising": false}, 20, 8], ["landing", run, 24, 6],
		["slide", {"run": 1.0, "sliding": true}, 24, 6], ["slide out", run, 24, 6],
		["box cover", {"cover": "crouch"}, 24, 7], ["out of it", run, 24, 6],
		["wall cover", {"cover": "stand"}, 24, 7], ["out of that", run, 24, 6],
		["stumble", {"run": 0.5, "stun": 1.0}, 30, 3], ["over it", {"run": 0.5}, 24, 6],
		["stop", {"run": 0.0}, 40, 9], ["go", run, 24, 6], ["aiming", {"run": 1.0, "aim": true}, 20, 0],
		["caught", {"surrender": true}, 40, 10]]
	var r := _rd_rig()
	r.pose_set()
	for k in 40:
		r.animate(dt, run)
	var p := _rd_rig()  # (the pose itself, not eased: what he showed at once before)
	var ok := true
	var worst := ""
	for c in seq:
		var s: Dictionary = c[1]
		var key: String = r._pose_was
		var was := _rd_snap(r)
		var at := -1
		var snap := 0.0
		var step := 0.0
		var read := -1
		var gap := 0.0
		var low_was := 0.0
		var lows := INF
		var dip := 0.0
		for k in int(c[2]):
			var st := s.duplicate()
			if s.has("stun"):
				st["stun"] = maxf(0.0, 1.0 - k / 30.0)
			var low_before := r._sole_low()
			p._phase = r._phase
			p._run = r._run
			p._aim = r._aim
			p._kick = r._kick
			p._pose_was = ""
			r.animate(dt, st)
			p.animate(dt, st)
			var shown := _rd_snap(r)
			var raw := _rd_snap(p)
			gap = maxf(_rd_step(shown, raw), (shown[0] as Vector3).distance_to(raw[0]))
			if at < 0 and r._pose_was != key:
				at = k
				snap = _rd_step(was, raw)
				low_was = low_before
			if at >= 0:
				step = maxf(step, _rd_step(was, shown))
				if read < 0 and gap <= 0.25 * snap + 0.002:
					read = k - at
				lows = minf(lows, p._sole_low())
				dip = minf(dip, r._sole_low() - minf(low_was, lows))
			was = shown
		var ground: bool = c[0] not in ["takeoff", "apex", "landing"]
		var good: bool = gap < 0.002 and (at >= 0 or c[0] == "aiming") and (snap < 0.3 or (step < 0.5 * snap and read >= 0 and read <= int(c[3]))) \
				and (not ground or dip > -0.005)
		if not good:
			ok = false
			worst += " %s (snap %.2f, worst step %.2f, 3/4 there after %d frames, left %.4f, boots %.3f lower)" % [c[0], snap, step, read, gap, -dip]
	# A shot mid-change (the arm up and re-posed at once: animate with no time passing) doesn't move
	# the change on.
	r.animate(dt, run)
	r.animate(dt, {"run": 1.0, "airborne": true, "rising": true})
	r.animate(dt, {"run": 1.0, "airborne": true, "rising": true})
	var t0: Array = r._change_t.duplicate()
	var legs := _rd_snap(r)
	r.recoil()
	var after := _rd_snap(r)
	var held: bool = r._change_t == t0 and float(t0[0]) > 0.0 and (legs[0] as Vector3).is_equal_approx(after[0])
	for k in [1, 10, 11, 12, 17, 18, 19]:  # (his hips and legs)
		held = held and (legs[k] as Quaternion).is_equal_approx(after[k])
	# Killed part way down into a slide: his death works his fall out from his legs as the slide has
	# them, as it always has.
	var d := _rd_rig()
	d.pose_set()
	for k in 40:
		d.animate(dt, run)
	var sl := {"run": 1.0, "sliding": true}
	for k in 3:
		d.animate(dt, sl)
	var e := _rd_rig()
	e._phase = d._phase
	e._run = d._run
	e.animate(0.0, sl)
	var from := d.death_start({"travel": 1.0, "lift": 0.0, "room": 50.0, "back": false, "slide": true})
	var ej := e._all_joints()
	var dead: bool = (from["hips"] as Vector3).is_equal_approx(e.hips.position)
	for k in [0, 9, 10, 11, 16, 17, 18]:  # (his hips and legs)
		dead = dead and (from["joints"][k] as Quaternion).angle_to(ej[k].quaternion) < 0.002
	# ...but what's shown carries on: killed a frame down onto a knee behind a box, the first frame of
	# his death eases on from the last frame he showed (no snap as he's hit).
	var c := _rd_rig()
	c.pose_set()
	for k in 40:
		c.animate(dt, run)
	c.animate(dt, {"run": 0.0, "cover": "crouch"})
	var last_shown := _rd_snap(c)
	var cf := c.death_start({"travel": 0.2, "lift": 0.0, "room": 50.0, "back": false, "slide": false})
	c.pose_death(dt * 0.5, cf)
	var first := _rd_snap(c)
	var snap := 0.0
	for k in [1, 10, 11, 12, 17, 18, 19]:  # (his hips and legs)
		snap = maxf(snap, (last_shown[k] as Quaternion).angle_to(first[k]))
	dead = dead and snap < 0.5 and (last_shown[0] as Vector3).distance_to(first[0]) < 0.1
	c.queue_free()
	# FIRE held through a jump and its landing: the gun level ahead all the way.
	var q := _rd_rig()
	q.pose_set()
	var off := 0.0
	for k in 100:
		var air := k >= 40 and k < 80
		q.animate(dt, {"run": 1.0, "aim": true, "airborne": air, "rising": k < 60})
		if k >= 20:
			off = maxf(off, rad_to_deg((q._in_rig(q._muzzle).basis * Vector3.FORWARD).angle_to(Vector3.FORWARD)))
	var g := GuardRig.new()
	root.add_child(g)
	for k in 30:
		g.animate(dt, {"run": 1.0, "aim": k > 20, "airborne": k > 5 and k < 15, "rising": k < 10, "duck": k > 15 and k < 20})
	_check(ok and held and dead and off < 0.5 and g._pose_was == "" and g._change_t == [-1.0, -1.0, -1.0],
			"CROSS's pose changes ease (user: \"adding easy to the key frames\"): no joint jumping, there at once, then exactly the pose, his boots no lower; a shot doesn't move one on (%s); killed mid-change, his death from his legs as the pose has them, what's shown easing onto it (%s); FIRE level ahead through a jump (%.2f°); guards as they were" % [held, dead, off] + worst)
	g.queue_free()
	q.queue_free()
	e.queue_free()
	d.queue_free()
	p.queue_free()
	r.queue_free()


func _rd_rig() -> SoldierRig:
	var r := SoldierRig.new()
	root.add_child(r)
	return r


## The stance at `t` s into its loop (and its breath), held there.
func _rd_at(r: SoldierRig, t: float) -> void:
	r._idle_t = t
	r._idle_b = t
	r._idle_go = -1.0
	r.animate(0.0, {"ready": true})


func _rd_snap(r: SoldierRig) -> Array:
	var out: Array = [r.hips.position]
	for j in r._all_joints():
		out.append(j.quaternion)
	return out


func _rd_str(r: SoldierRig) -> String:
	return str(_rd_snap(r)) + str(r._slide.position)


func _rd_step(a: Array, b: Array) -> float:
	var worst := 0.0
	for k in range(1, a.size()):
		worst = maxf(worst, (a[k] as Quaternion).angle_to(b[k]))
	return worst


func _rd_sole(r: SoldierRig, side: int) -> Basis:
	var an: Node3D = r.ankles[side]
	return r._in_rig(an.get_node(String(an.name) + "Flat")).basis.orthonormalized()


## How far an arm is raised (rad from straight down, in his chest's axes), as the shrug measures it.
func _rd_raise(r: SoldierRig, side: int) -> float:
	var arm_in: Node3D = r.elbows[side].get_parent()
	var arm: Vector3 = r.clavicles[side].basis * (r.shoulders[side].basis * (arm_in.basis * (r.elbows[side] as Node3D).position))
	return acos(clampf(-arm.normalized().y, -1.0, 1.0))


## How far `side`'s hand is bent off the line of its forearm (deg).
func _rd_bend(r: SoldierRig, side: int) -> float:
	var el := r._in_rig(r.elbows[side]).origin
	var wr := r._in_rig(r.wrists[side])
	return rad_to_deg((wr.origin - el).angle_to(wr.basis * (r._hand_run[side] as Vector3)))


func _rd_world(r: SoldierRig, p: Vector3) -> Vector3:
	return p * SoldierRig.SIZE + r.position


func _rd_hand(r: SoldierRig, side: int) -> Vector3:
	return _rd_world(r, r._in_rig(r.wrists[side]) * (r._hand_mid[side] as Vector3))


func _rd_lenses(r: SoldierRig) -> Array:
	var out := []
	for n in r.head.get_children():
		if n is MeshInstance3D:
			out.append(_rd_world(r, r._in_rig(n).origin))
	return out


## How far the barrel points from a camera at `eye` (degrees).
func _rd_clear(r: SoldierRig, eye: Vector3) -> float:
	var m := r._in_rig(r._muzzle)
	return rad_to_deg((m.basis * Vector3.FORWARD).angle_to(eye - _rd_world(r, m.origin)))


## How far the barrel points down (degrees).
func _rd_dip(r: SoldierRig) -> float:
	var b := (r._in_rig(r._muzzle).basis * Vector3.FORWARD).normalized()
	return rad_to_deg(asin(clampf(-b.y, -1.0, 1.0)))


## A point (him at the origin) on the menu's camera swayed `s`, on a 270 x `h` phone screen (px;
## the menu's own view for that height).
func _rd_screen(p: Vector3, s: float, h: float) -> Vector2:
	var c := IntroCamera.menu(s, 0.0, h)
	var cam := Transform3D(Basis.IDENTITY, c[0]).looking_at(c[1], Vector3.UP)
	var q := cam.affine_inverse() * p
	var f := (h / 2.0) / tan(deg_to_rad(float(c[2]) / 2.0))
	return Vector2(135.0 + q.x / -q.z * f, h / 2.0 - q.y / -q.z * f)


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
	for at_m in [10.0, RouteGraph.STAIR_CLEAR_TO - 1.0, RouteGraph.STAIR_CLEAR_TO]:
		var rn := base.duplicate(true)
		rn["snipers"] = [{"at": at_m, "side": "left"}]
		var gs := RouteGraph.from_dict({"start": "s", "nodes": [stair_in, rn, {"id": "e", "tier": "ground", "length": 30, "end": "extract"}]})
		var close := " | ".join(gs.validate()).contains("sniper at %s m is too close to the stairs" % at_m)
		_check(close == (at_m < RouteGraph.STAIR_CLEAR_TO), "sniper: %s m into an area reached by stairs is %s" % [at_m, "too close" if at_m < RouteGraph.STAIR_CLEAR_TO else "fine"])
	var ok := base.duplicate(true)
	ok["snipers"] = [{"at": 10, "side": "left"}]
	var fine := RouteGraph.from_dict({"start": "r", "nodes": [ok, {"id": "e", "tier": "ground", "length": 30, "end": "extract"}]})
	_check(not " | ".join(fine.validate()).contains("sniper"), "sniper: a good spot passes")
	var real := RouteGraph.from_json_file(TEST_RANGE)  # (snipers: not in mission 1)
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
	var g := RouteGraph.from_json_file(TEST_RANGE)  # (its longest way: not in mission 1)
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


## The sounds are built in the background a few milliseconds a frame, under the main menu
## (SoundBank.work: the menu stuttered while one sound took up to 57 ms in a go). Every Synth op
## stops when a turn's time is up and carries on in the next. Built that way, in the smallest turns
## there are (one chunk each), every op and every kind of sound comes out exactly as it does built
## at once; and a sound asked for while it's half built is finished there and then.
func _test_sound_turns() -> void:
	var ops := ["tone", "noise", "lowpass", "highpass", "resonate", "echo", "crush", "drive", "gain", "normalize", "loopify", "swell", "mix_in", "to_stream"]
	var differ: Array[String] = []
	var unsplit: Array[String] = []
	for op: String in ops:
		var at_once := await _turns_synth()
		await _turns_op(at_once, op)  # (nothing pacing it: it never waits)
		var paced := await _turns_synth()
		var took := _in_turns(func() -> void: await _turns_op(paced, op))
		if paced.s != at_once.s or (op == "to_stream" and (paced.get_meta("wav") as AudioStreamWAV).data != (at_once.get_meta("wav") as AudioStreamWAV).data):
			differ.append(op)
		if took < 2:
			unsplit.append(op)
	_check(differ.is_empty() and unsplit.is_empty(), "sound turns: every Synth op, in turns of a chunk each, gives the samples it gives at once (differ: %s, not split: %s)" % [differ, unsplit])
	# Every sound (so a recipe missing an await shows): built in the background, against built at once
	# (by _test_sounds, just before).
	var names := SoundBank.all_names()
	var want := {}
	for name: String in names:
		want[name] = SoundBank.get_stream(name).data
		SoundBank._cache.erase(name)
		SoundBank.queue(name)
	var turns := 0
	while SoundBank.building() and turns < 100000:
		SoundBank.work(0.0)
		turns += 1
	var wrong: Array[String] = []
	for name: String in names:
		if not SoundBank.has(name) or SoundBank.get_stream(name).data != want[name]:
			wrong.append(name)
	_check(wrong.is_empty() and turns > 100 * names.size(), "sound turns: sounds built in the background in turns of a chunk each are the sounds built at once (%d turns; differ: %s)" % [turns, wrong])
	SoundBank._cache.erase("door_bars")
	SoundBank.queue("door_bars")
	for i in 3:
		SoundBank.work(0.0)
	var half: bool = SoundBank._building == "door_bars" and not SoundBank.has("door_bars")
	var asked := SoundBank.get_stream("door_bars")
	_check(half and asked != null and asked.data == want["door_bars"] and not SoundBank.building() and Synth.pace.go.get_connections().is_empty(),
			"sound turns: a sound asked for half built is finished at once, the same sound, and nothing is left waiting")


## A short buffer (a few chunks) with something in it, made at once.
func _turns_synth() -> Synth:
	var syn := Synth.create(0.15, Synth.CHUNK * 20, 5)
	await syn.tone(0.0, 0.15, 220.0, 330.0, 0.5, Synth.Wave.SQUARE, 0.01, 2.0)
	await syn.noise(0.02, 0.1, 0.4, 4000.0, 300.0, 0.002, 5.0)
	return syn


func _turns_op(syn: Synth, op: String) -> void:
	match op:
		"tone":
			await syn.tone(0.01, 0.13, 300.0, 900.0, 0.5, Synth.Wave.SAW, 0.01, 3.0)
		"noise":
			await syn.noise(0.0, 0.14, 0.6, 3000.0, 200.0, 0.005, 4.0)
		"lowpass":
			await syn.lowpass(1500.0)
		"highpass":
			await syn.highpass(400.0)
		"resonate":
			await syn.resonate(900.0, 4.0, 0.7)
		"echo":
			await syn.echo(0.02, 0.4, 0.5)
		"crush":
			await syn.crush(8, 3)
		"drive":
			await syn.drive(1.7)
		"gain":
			await syn.gain(0.6)
		"normalize":
			await syn.normalize(0.8)
		"loopify":
			await syn.loopify(0.06)
		"swell":
			await syn.swell(2.0, 0.4)
		"mix_in":
			var other := Synth.create(0.12, syn.rate, 9)
			await other.noise(0.0, 0.12, 0.5)
			await syn.mix_in(other, 0.02, 0.7)
		"to_stream":
			syn.set_meta("wav", await syn.to_stream(true))


## Runs `work` (a coroutine of Synth ops) in turns of one chunk each, as the background would with
## no time to spare; the number of turns it took.
func _in_turns(work: Callable) -> int:
	var done := [false]
	Synth.pace.until_usec = 1  # (always past: every op waits after each chunk)
	(func() -> void:
		await work.call()
		done[0] = true).call()
	var turns := 1
	while not done[0] and turns < 100000:
		Synth.pace.go.emit()
		turns += 1
	Synth.pace.until_usec = 0
	return turns


## The menu music is built faster (AudioDirector.MENU_MUSIC_BUDGET_MS) only while the main menu
## itself is up and the music isn't built yet. From START (leave_menu) on, under the briefing and the
## opening pan, the sounds go at the level's pace (build_ms), as those frames make the textures too:
## the music, still building, starts a little later.
func _test_menu_music_pace() -> void:
	var built: Variant = SoundBank._cache.get("music_menu")
	SoundBank._cache.erase("music_menu")
	var script := load("res://game/audio/audio_director.gd") as GDScript  # (by path: it needs the autoloads)
	var k := script.get_script_constant_map()
	var build: float = k["BUILD_BUDGET_MS"]
	var hurry: float = k["HURRY_BUDGET_MS"]
	var menu_ms: float = k["MENU_MUSIC_BUDGET_MS"]
	var a: Node = script.new()  # (not in the tree: nothing plays or builds)
	a.set("_menu_music", AudioStreamPlayer.new())
	var first: float = a.frame_budget_ms()
	a.play_menu_music()
	var menu: float = a.frame_budget_ms()
	a.leave_menu()
	var brief: float = a.frame_budget_ms()
	a.build_ms = hurry
	var pan: float = a.frame_budget_ms()
	a.build_ms = build
	_check(first == build and menu == menu_ms,
			"menu music pace: built at %.0f ms a frame while the main menu is up (%.0f before; got %.1f, %.1f)" % [menu_ms, build, menu, first])
	_check(brief == build and pan == hurry,
			"menu music pace: from START, the level's pace, %.0f ms then %.0f (got %.1f, %.1f)" % [build, hurry, brief, pan])
	a.play_menu_music()
	SoundBank._cache["music_menu"] = built if built != null else AudioStreamWAV.new()
	var done: float = a.frame_budget_ms()
	SoundBank._cache.erase("music_menu")
	a.stop_menu_music()
	var stopped: float = a.frame_budget_ms()
	_check(done == build and stopped == build,
			"menu music pace: once it's built, or stopped (the run), the normal pace (got %.1f, %.1f)" % [done, stopped])
	if built != null:
		SoundBank._cache["music_menu"] = built
	(a.get("_menu_music") as Node).free()
	a.free()


## The level makes every texture ahead of time, under the main menu, from PsxTextures.makers(): each
## texture made with nothing passed (found by name), and every CCTV screen and menu board. Nothing
## else: not the helpers, not those made from the caller's choices, not makers() itself.
func _test_texture_makers() -> void:
	var makers := PsxTextures.makers()
	var count := {}
	var bad: Array[String] = []
	for c: Callable in makers:
		if not c.is_valid():
			bad.append(c.get_method())
		count[c.get_method()] = int(count.get(c.get_method(), 0)) + 1
	_check(bad.is_empty(), "the texture warm-up can call every one (not: %s)" % [bad])
	for want in ["asphalt", "hazard", "lobby_floor", "grating", "roller_shutter", "water_streaks", "city_backdrop", "drain_wall"]:
		_check(count.get(want, 0) == 1, "the texture warm-up makes %s once" % want)
	_check(count.get("cctv_screen", 0) == PsxTextures.CCTV_VIEWS, "the texture warm-up makes every CCTV screen")
	_check(count.get("menu_board", 0) == PsxTextures.MENU_ITEMS, "the texture warm-up makes every menu board")
	for not_one in ["makers", "wall", "vending_front", "_finish", "_rng"]:
		_check(not count.has(not_one), "the texture warm-up leaves out %s" % not_one)
	_check(not makers.is_empty() and makers[0].call() is Texture2D, "a texture warm-up maker makes a texture")


func _test_route_json_is_valid() -> void:
	for path in [MISSION_1, TEST_RANGE]:
		var g := RouteGraph.from_json_file(path)
		_check(g != null, "%s loads" % path)
		if g == null:
			continue
		# (the game's run and jump; mission 1 on every setting, each at its own reaction floor)
		var problems := RouteGraph.validate_settings(JSON.parse_string(FileAccess.get_file_as_string(path)), load("res://game/config/default_tuning.tres") as Tuning)
		_check(problems.is_empty(), "%s valid: %s" % [path, ", ".join(problems)])
		_check(g.end_type(&"helipad") == "extract", "helipad is an extraction end (%s)" % path)
	# The test range is today's 19-area level, frozen for the bots: the cover-exit rule came after it
	# and is left off there (its 41 known spots, mostly the old underground rows, stay as they were).
	var range_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TEST_RANGE))
	_check(range_data.get("cover_exit_rule", true) == false and range_data.get("mission", "") == "test_range", "the test range keeps its old layout (cover-exit rule off there only)")
	var with_rule := range_data.duplicate(true)
	with_rule["cover_exit_rule"] = true
	var spots := " | ".join(RouteGraph.from_dict(with_rule).validate(load("res://game/config/default_tuning.tres") as Tuning))
	_check(spots.contains("out of the box at 96.0 m in lane 0 into lane 1, the barrier at 100.0 m comes too soon"),
			"cover-exit rule: the old SECURITY WING's crate at 96 m, beside the barrier at 100 m, is caught")


## Which ways are open at each alert (LOCKED: alert can change which routes are open). Mission 1:
## the SECURITY WING's basement stairs open only at SNEAKING, its fire escape only from CAUTION up,
## straight on always. The test range: the MAIN FLOOR's tunnel stairs, sealed above SNEAKING.
func _test_alert_gating() -> void:
	var g := RouteGraph.from_json_file(MISSION_1)
	var sides := func(alert: int) -> Array:
		var out := []
		for e in g.available_next(&"security_wing", alert):
			out.append(RouteGraph.side_of(e))
		out.sort()
		return out
	_check(sides.call(1) == ["left", "straight"], "mission 1: at SNEAKING the wing's basement stairs and straight on are open (%s)" % [sides.call(1)])
	_check(sides.call(2) == ["right", "straight"] and sides.call(3) == ["right", "straight"],
			"mission 1: at CAUTION and ALERT the fire escape and straight on are open (%s, %s)" % [sides.call(2), sides.call(3)])
	var t := RouteGraph.from_json_file(TEST_RANGE)
	_check(t.available_next(&"building_main_floor", 1).size() == 2, "test range: tunnel open at alert 1")
	_check(t.available_next(&"building_main_floor", 2).size() == 1, "test range: tunnel sealed at alert 2")
	# An exit with min_alert opens as the alert rises; one with max_alert shuts (pick_edge then
	# carries an outer lane straight on).
	var right := RouteGraph.pick_edge(4, 5, g.available_next(&"security_wing", 1))
	_check(RouteGraph.side_of(right) == "straight", "mission 1: the far-right lane carries straight on while the fire escape is shut")
	var left := RouteGraph.pick_edge(0, 5, g.available_next(&"security_wing", 2))
	_check(RouteGraph.side_of(left) == "straight", "mission 1: the far-left lane carries straight on once the basement stairs lock")


## The stairs doors' cues (user, 2026-10-07: "3 arrows just before that are a bit transparent and
## light up one after another, but if a door is locked there is a floating red lock in front of
## the door"): which doors there are, on which side, and whether each is open at each alert.
## Ladders aren't doors, so they get none. Mission 1's two doors are off one area, the SECURITY
## WING; its fire escape is the first door locked while it's quiet.
func _test_door_cues() -> void:
	# [file, area, [[side, open at alert 1, 2, 3]...], areas with no stairs door]
	var cases := [
		[MISSION_1, &"security_wing", [["left", [true, false, false]], ["right", [false, true, true]]],
				[&"main_floor_lobby", &"building_main_floor", &"rooftops", &"roof_edge", &"boiler_room", &"service_tunnel", &"staff_canteen", &"main_floor_exit"]],
		[TEST_RANGE, &"main_floor_lobby", [["right", [true, true, true]]], [&"security_wing", &"roof_edge", &"storm_drain", &"service_tunnel"]],
		[TEST_RANGE, &"rooftops", [["left", [true, true, true]]], []],
		[TEST_RANGE, &"building_main_floor", [["left", [true, false, false]]], []],
		[TEST_RANGE, &"warehouse", [["left", [true, false, false]]], []],
	]
	for c in cases:
		var g := RouteGraph.from_json_file(c[0])
		var want_doors: Array = c[2]
		for alert in [1, 2, 3]:
			var got := g.stair_doors(c[1], alert)
			_check(got.size() == want_doors.size(), "%s has %d stairs door(s) (alert %d)" % [c[1], want_doors.size(), alert])
			if got.size() != want_doors.size():
				continue
			for k in got.size():
				_check(got[k]["side"] == want_doors[k][0], "%s's stairs door %d is on the %s" % [c[1], k, want_doors[k][0]])
				_check(RouteGraph.via_of(got[k]["edge"]) == "stairs", "%s's door leads to stairs" % c[1])
				var want: bool = want_doors[k][1][alert - 1]
				_check(got[k]["open"] == want, "%s's %s stairs door %s at alert %d" % [c[1], want_doors[k][0], "open" if want else "locked", alert])
		for id in c[3]:
			for alert in [1, 2, 3]:
				_check(g.stair_doors(id, alert).is_empty(), "%s has no stairs door (alert %d)" % [id, alert])
	# (A locked door, built and run past in the real level: _test_locked_doors.)


## A locked stairs door (user, 2026-10-08: "I don't want the locked door to be tucked beside the
## lane, keep it the same as the unlocked door, doors and walls don't move unless I say so", then
## "Locked doors can nudge CROSS into the next lane, that sounds fine"), in the real level, at the
## MAIN FLOOR's TUNNEL door and the WAREHOUSE's PUMPS door. Locked, the door is the open stairwell's
## way in: every mesh of it where one of the open one's is, in the same look, the same box or (the
## stairwell's side walls and roof slab) the same box cut short at the back of the doorway, its
## front end just as the whole one's; nothing of it further in; its sight boxes the open one's
## there; the sign over the split as it is open; the padlock out in front of the middle of the
## door; the hole in the wall walled up. Then CROSS, run up to it in its lane at 60 Hz: eased out of
## that lane before he's at the door, the camera after him, a swipe back refused till he's past
## it, then left alone; never touching the door or the padlock; and the squad kept out of that lane
## there too.
func _test_locked_doors() -> void:
	var gs := root.get_node("GameState")
	var was_alert: int = gs.alert_level
	var was_active: bool = gs.run_active
	var level_script: GDScript = load("res://game/levels/prototype_slice/prototype_slice.gd")
	# The test range: the MAIN FLOOR's TUNNEL door and the WAREHOUSE's PUMPS door, locked above
	# SNEAKING.
	level_script.route_path = TEST_RANGE
	var level := await _locked_doors_level(gs, true)
	for zone in [[&"building_main_floor"], [&"security_wing", &"staff_canteen", &"warehouse"]]:
		await _locked_doors_walk(level, gs, zone)
		await _locked_door_checks(level, gs)
	_check(await _squad_at_alert_3(level, gs) == 5, "squad switch: on the test range, ALERT sends the squad after him (5)")
	level.queue_free()
	await process_frame
	# Mission 1: the SECURITY WING's two doors, one each side of the one split. The basement stairs
	# (left) lock at CAUTION; the fire escape (right) is locked while it's quiet and opens at CAUTION:
	# the same door shut, its padlock in front of it, as the basement door's.
	level_script.route_path = MISSION_1
	level = await _locked_doors_level(gs, false)
	await _locked_doors_walk(level, gs, [&"building_main_floor", &"security_wing"])
	await _locked_door_checks(level, gs, "left", 1, 2)
	await _locked_door_checks(level, gs, "right", 2, 1)
	# Mission 1 has the basics only ("squad": false): ALERT sends nobody after him.
	var squad := await _squad_at_alert_3(level, gs)
	_check(squad == 0 and not level._squad_on, "squad switch: in mission 1, ALERT sends no squad (%d)" % squad)
	level.queue_free()
	await process_frame
	gs.alert_level = was_alert
	gs.run_active = was_active


## How many of the pursuit squad come after him as the alert reaches 3 mid-run (then back to 1).
func _squad_at_alert_3(level: Node, gs: Node) -> int:
	gs.run_active = true
	gs.set_alert(3)
	await process_frame
	var n: int = level._squad.size()
	gs.set_alert(1)
	await process_frame
	gs.run_active = false
	return n


## The real level, stepped by hand (_test_locked_doors).
func _locked_doors_level(gs: Node, warm_ups: bool) -> Node:
	gs.alert_level = 1
	var level: Node = (load("res://game/levels/prototype_slice/prototype_slice.tscn") as PackedScene).instantiate()
	root.add_child(level)
	if warm_ups:
		_check_warm_ups(level)
	await process_frame
	await process_frame
	level.set_physics_process(false)  # (stepped by hand below)
	level._player.set_physics_process(false)
	return level

## On straight from area to area, at SNEAKING, to the last area in `zone`.
## On straight from area to area, at SNEAKING, to the last of .
func _locked_doors_walk(level: Node, gs: Node, zone: Array) -> void:
	gs.set_alert(1)
	for want: StringName in zone:
		var cur: Dictionary = level._current
		for e: Dictionary in level._graph.all_next(cur["id"]):
			if StringName(e["to"]) == want and RouteGraph.side_of(e) == "straight":
				level._player.distance = float(cur["end"]) - 1.0
				level._on_segment_needed(want, cur["end"], e)
				level._on_node_entered(want)
				level._runner.current = want
				level._runner.segment_start = cur["end"]
		await process_frame


## Under the menu, as the level starts, each look the run would otherwise first draw in the middle of
## it is drawn once in front of the camera (_warm_door_cues), so a phone builds its shader then: with
## the stairs doors' arrows and padlock, the plain halo (the sniper's muzzle flash, the squad's
## rifle-light glare) and the one keeping its scale (the sniper's glint), both clear (they add no
## light: nothing shows). Each the same look as theirs, to the shader.
func _check_warm_ups(level: Node) -> void:
	var looks := {}  # each warmed halo's look -> its alpha
	var warm: Node = level._camera.get_node_or_null("DoorCueWarmUp")
	if warm != null:
		for mi: MeshInstance3D in warm.find_children("*", "MeshInstance3D", true, false):
			if mi.material_override is StandardMaterial3D:
				looks[_halo_look(mi.material_override)] = (mi.material_override as StandardMaterial3D).albedo_color.a
	var sniper := Sniper.new(Tuning.new())
	root.add_child(sniper)
	var squad := GuardRig.new(GuardRifle.Kind.CARBINE_LIGHT)
	var theirs: Array[Material] = [sniper._flash.material_override, sniper._glint.material_override]
	for mi: MeshInstance3D in squad.light().find_children("*", "MeshInstance3D", true, false):
		if mi.material_override is StandardMaterial3D and (mi.material_override as StandardMaterial3D).billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED:
			theirs.append(mi.material_override)
	var warmed := theirs.size() == 3
	for m in theirs:
		var look := _halo_look(m)
		warmed = warmed and looks.has(look) and looks[look] == 0.0
	_check(warmed, "warm-ups: under the menu, the plain halo (the sniper's flash, the squad's rifle-light glare) and the sniper's glint are drawn once, clear (%d looks warmed)" % looks.size())
	sniper.free()
	squad.free()


## What picks a StandardMaterial3D's shader (the look; its colour doesn't).
static func _halo_look(m: StandardMaterial3D) -> String:
	return "%d %d %d %d %d %d %d %d %d %s" % [m.shading_mode, m.blend_mode, m.transparency, m.cull_mode, m.depth_draw_mode, m.billboard_mode,
			int(m.billboard_keep_scale), m.distance_fade_mode, int(m.disable_fog), m.albedo_texture != null]


## A mesh's look and place, kept (the open stairwell goes as its door locks): {xf, mesh, mat}.
static func _mesh_snap(root_node: Node) -> Array:
	var out := []
	for m: MeshInstance3D in root_node.find_children("*", "MeshInstance3D", true, false):
		out.append({"xf": m.global_transform, "mesh": m.mesh, "mat": m.material_override})
	return out


## Every line-of-sight box under `root_node`: [{xf, size}].
static func _sight_snap(root_node: Node) -> Array:
	var out := []
	for b: StaticBody3D in root_node.find_children("*", "StaticBody3D", true, false):
		for c in b.get_children():
			if c is CollisionShape3D:
				out.append({"xf": (c as CollisionShape3D).global_transform, "size": ((c as CollisionShape3D).shape as BoxShape3D).size})
	return out


static func _same_xf(a: Transform3D, b: Transform3D) -> bool:
	return a.origin.distance_to(b.origin) < 0.0005 and a.basis.x.distance_to(b.basis.x) < 0.0005 \
			and a.basis.y.distance_to(b.basis.y) < 0.0005 and a.basis.z.distance_to(b.basis.z) < 0.0005


## True if the box `size` at `xf` is all inside the box `in_size` at `in_xf` (to a millimetre).
static func _box_inside(xf: Transform3D, size: Vector3, in_xf: Transform3D, in_size: Vector3) -> bool:
	var to := in_xf.affine_inverse()
	for c in 8:
		var q: Vector3 = to * (xf * (size * (Vector3(c & 1, (c >> 1) & 1, (c >> 2) & 1) - Vector3.ONE * 0.5)))
		if absf(q.x) > in_size.x / 2.0 + 0.001 or absf(q.y) > in_size.y / 2.0 + 0.001 or absf(q.z) > in_size.z / 2.0 + 0.001:
			return false
	return true


func _locked_door_checks(level: Node, gs: Node, side: String = "left", open_alert: int = 1, locked_alert: int = 2) -> void:
	gs.set_alert(open_alert)
	await process_frame
	var k: Dictionary = (level.get_script() as GDScript).get_script_constant_map()
	var seg: Dictionary = level._current
	var id: StringName = seg["id"]
	var area := "%s (%s door)" % [String(id).to_upper(), side]
	var t: Tuning = level.tuning
	var edge := {}
	for e: Dictionary in level._graph.all_next(id):
		if RouteGraph.via_of(e) == "stairs" and RouteGraph.side_of(e) == side:
			edge = e
	var key: String = level._key(edge)
	var split: float = seg["end"]
	var road: Transform3D = seg["node"].global_transform * level._frame_in_leg(seg, seg["legs"].size() - 1, seg["length"])
	var to_road := road.affine_inverse()
	var cue_labels := func() -> Array:
		var out := []
		for n in seg["node"].get_node("ForkCue").get_children():
			if n is Label3D:
				out.append([(n as Label3D).text, (n as Node3D).global_position])
		return out
	# Open, as it was built: its stairwell's meshes and sight boxes, and the sign over the split.
	var open_meshes := _mesh_snap(seg["branches"][key]["node"].get_node("Stairwell"))
	var open_sights := _sight_snap(seg["branches"][key]["node"].get_node("Stairwell"))
	var open_labels: Array = cue_labels.call()
	gs.set_alert(locked_alert)
	await process_frame
	var stub: Node3D = seg["locked"].get(key)
	_check(stub != null and stub.has_node("Stairwell"), "%s: locked, its stairs door is the stairwell's way in" % area)
	if stub == null:
		return
	var from_stub := stub.global_transform.affine_inverse()
	var exact := 0
	var cut := 0
	var odd := PackedStringArray()
	var deepest := -INF
	for m: MeshInstance3D in stub.find_children("*", "MeshInstance3D", true, false):
		var a := m.get_aabb()
		for c in 8:
			deepest = maxf(deepest, -(from_stub * (m.global_transform * (a.position + a.size * Vector3(c & 1, (c >> 1) & 1, (c >> 2) & 1)))).z)
		var twin := {}
		for om: Dictionary in open_meshes:
			if _same_xf(m.global_transform, om["xf"]) and m.material_override == om["mat"]:
				twin = om
		if twin.is_empty() or not twin["mesh"] is BoxMesh:
			odd.append("%s (no twin)" % m.name)
		elif m.mesh is BoxMesh and (m.mesh as BoxMesh).size.is_equal_approx((twin["mesh"] as BoxMesh).size):
			exact += 1
		elif m.mesh is ArrayMesh:
			# Cut short: its front end vertex for vertex as the whole box's, texture and all.
			var whole: Array = (twin["mesh"] as BoxMesh).get_mesh_arrays()
			var mine: Array = (m.mesh as ArrayMesh).surface_get_arrays(0)
			var wv: PackedVector3Array = whole[Mesh.ARRAY_VERTEX]
			var mv: PackedVector3Array = mine[Mesh.ARRAY_VERTEX]
			var wu: PackedVector2Array = whole[Mesh.ARRAY_TEX_UV]
			var mu: PackedVector2Array = mine[Mesh.ARRAY_TEX_UV]
			var front_same := wv.size() == mv.size()
			for i in mini(wv.size(), mv.size()):
				if wv[i].z > 0.0 and (not wv[i].is_equal_approx(mv[i]) or not wu[i].is_equal_approx(mu[i])):
					front_same = false
			if front_same:
				cut += 1
			else:
				odd.append("%s (cut, its front end not the whole one's)" % m.name)
		else:
			odd.append("%s (another mesh)" % m.name)
	_check(odd.is_empty() and exact == 7 and cut == 3,
			"%s: locked, every mesh of its door is one of the open stairwell's, in its place and look: the door, its frame and the wall over it, the exit sign and the wall to the side wall the same boxes, the side walls' and slab's front ends cut from the same boxes (%d same, %d cut; %s)" % [area, exact, cut, ", ".join(odd)])
	_check(deepest <= float(k["STAIR_MOUTH"]) + 0.001,
			"%s: locked, nothing is built behind the door (%.3f m into the stairwell, the doorway's back at %.2f)" % [area, deepest, k["STAIR_MOUTH"]])
	# Its sight boxes: the open way in's (the doorway's, the door's and the wall's to the side wall),
	# and the cut walls' and slab's, inside the whole ones' and as long as what's left of them.
	var sights := _sight_snap(stub)
	var bad_sight := 0
	var same_sight := 0
	for s: Dictionary in sights:
		var ok := false
		for os: Dictionary in open_sights:
			if _same_xf(s["xf"], os["xf"]) and (s["size"] as Vector3).is_equal_approx(os["size"]):
				ok = true
				same_sight += 1
				break
			if _box_inside(s["xf"], s["size"], os["xf"], os["size"]):
				ok = true
				break
		if not ok:
			bad_sight += 1
	var mouth_open := 0  # the open stairwell's boxes all within its way in: each must be the locked one's too
	for os: Dictionary in open_sights:
		var all_in := true
		for c in 8:
			var q: Vector3 = os["xf"] * ((os["size"] as Vector3) * (Vector3(c & 1, (c >> 1) & 1, (c >> 2) & 1) - Vector3.ONE * 0.5))
			all_in = all_in and -(from_stub * q).z <= float(k["STAIR_MOUTH"]) + 0.001
		if all_in:
			mouth_open += 1
	_check(bad_sight == 0 and same_sight == mouth_open and mouth_open == 6,
			"%s: locked, its door blocks sight as the open one's way in does there, and nothing else does (%d boxes, %d the open way in's of %d, %d not the open stairwell's)" % [area, sights.size(), same_sight, mouth_open, bad_sight])
	var labels: Array = cue_labels.call()
	var same_signs := labels.size() == open_labels.size() and labels.size() >= 2
	for i in mini(labels.size(), open_labels.size()):
		same_signs = same_signs and labels[i][0] == open_labels[i][0] and (labels[i][1] as Vector3).distance_to(open_labels[i][1]) < 0.001
	_check(same_signs, "%s: locked, the sign over the split is as it is open (%s; open %s)" % [area, labels.map(func(l): return l[0]), open_labels.map(func(l): return l[0])])
	var lock: Node3D = seg["node"].get_node("ForkCue").get_node_or_null("DoorLock_" + RouteGraph.side_of(edge))
	var in_door := Vector3.INF
	if lock != null:
		in_door = (level._stair_door_frame(seg, edge) as Transform3D).affine_inverse() * (seg["node"].global_transform.affine_inverse() * lock.global_position)
	_check(lock != null and absf(in_door.x) < 0.001 and absf(in_door.z - float(k["DOOR_LOCK_BEFORE"])) < 0.001 and absf(in_door.y - float(k["DOOR_LOCK_Y"])) < 0.001,
			"%s: locked, the padlock floats %.1f m out in front of the middle of the door, %.2f m up (%s)" % [area, k["DOOR_LOCK_BEFORE"], k["DOOR_LOCK_Y"], in_door])
	var road_on: Dictionary = {}
	for b: Dictionary in seg["branches"].values():
		if RouteGraph.side_of(b["edge"]) == "straight":
			road_on = b
	var plug: Node3D = level._hole_plug(road_on, edge)
	_check(plug != null and plug.visible, "%s: locked, the hole its stairwell passes out through is walled up" % area)

	# CROSS run up to it in its lane (the outer lane on its side), at 60 Hz.
	var p: Node3D = level._player
	var lane: int = level._handover_lanes(edge).x
	var into := lane + (1 if lane == 0 else -1)  # the next lane in
	var bar: Dictionary = {}
	for b: Dictionary in level._door_bars:
		if b["stub"] == stub:
			bar = b
	_check(not bar.is_empty() and int(bar["lane"]) == lane, "%s: locked, its door bars the lane it stands across" % area)
	if bar.is_empty():
		return
	gs.run_active = true
	level._menu_open = false  # (the play camera, not the menu's)
	level._cam_snap = true
	p.distance = split - 20.0
	p.lane = lane
	p.track_x = p.lane_x(lane)
	p.set("_speed_mul", 1.0)
	p.set("_stun_left", 0.0)
	var body := 0.35  # (half his width, arms and all)
	var dt := 1.0 / 60.0
	var left_at := INF  # where he left the lane
	var out_at := INF  # where he was all the way into the next one
	var refused := false
	var stays := false
	var allowed := false
	var closest := INF  # his clearance from the door (or the padlock)
	var cam_x := -INF  # the camera's x in the road's frame a metre before the split
	var door_meshes: Array = []
	for m: MeshInstance3D in stub.find_children("*", "MeshInstance3D", true, false):
		if m.is_visible_in_tree():
			door_meshes.append(m)
	var lock_at: Vector3 = to_road * lock.global_position if lock != null else Vector3.INF
	while p.distance < float(bar["to"]) + 3.0:
		var was: float = p.distance
		level._ease_past_locked_doors()
		if p.lane != lane and left_at == INF:
			left_at = was
		p._physics_process(dt)
		level._place_player()
		level._update_camera(dt)
		var d: float = p.distance
		if absf(p.track_x - p.lane_x(into)) < 0.001 and out_at == INF:
			out_at = d
		if d >= split - 1.0 and cam_x == -INF:
			cam_x = (to_road * level._camera.global_position).x
		if d >= split - 2.0 and not refused and d < float(bar["to"]):
			p.handle_swipe(Vector2i.LEFT if lane == 0 else Vector2i.RIGHT)
			refused = p.lane == into
		if d > float(bar["to"]) and not allowed:
			level._ease_past_locked_doors()
			stays = p.lane == into and p.barred_lane == -1
			p.handle_swipe(Vector2i.LEFT if lane == 0 else Vector2i.RIGHT)
			allowed = p.lane == lane
		# His clearance from each piece of the door below his head, and from the padlock.
		var at: Vector3 = p.global_position
		for m: MeshInstance3D in door_meshes:
			var a := m.get_aabb()
			var q: Vector3 = m.global_transform.affine_inverse() * at
			var low: float = (m.global_transform * a.position).y
			if low > at.y + 1.9:
				continue
			var dx := maxf(maxf(a.position.x - q.x, q.x - a.end.x), 0.0)
			var dz := maxf(maxf(a.position.z - q.z, q.z - a.end.z), 0.0)
			closest = minf(closest, Vector2(dx, dz).length() - body)
		var me: Vector3 = to_road * at
		closest = minf(closest, Vector2(maxf(absf(me.x - lock_at.x) - 0.31, 0.0), maxf(absf(me.z - lock_at.z) - 0.2, 0.0)).length() - body)
	gs.run_active = false
	_check(split - left_at <= float(k["DOOR_NUDGE_AHEAD"]) and split - left_at > float(k["DOOR_NUDGE_AHEAD"]) - t.run_speed * dt - 0.001,
			"%s: locked, CROSS in its lane is eased out of it %.1f m before the split (at %.2f m)" % [area, k["DOOR_NUDGE_AHEAD"], split - left_at])
	var front: float = 0.0  # how far before the split the door reaches
	for m: MeshInstance3D in door_meshes:
		var a := m.get_aabb()
		for c in 8:
			front = maxf(front, (to_road * (m.global_transform * (a.position + a.size * Vector3(c & 1, (c >> 1) & 1, (c >> 2) & 1)))).z)
	_check(split - out_at > front + body, "%s: locked, he's all the way into the next lane %.2f m before the split, before he's at the door (it reaches %.2f m before it)" % [area, split - out_at, front])
	_check(absf(cam_x - p.lane_x(into) * 0.6) < 0.25, "%s: locked, the camera follows him over as it does a lane change (%.2f, his lane %.2f)" % [area, cam_x, p.lane_x(into)])
	_check(refused, "%s: locked, a swipe back into its lane before he's past the door is refused" % area)
	_check(stays and allowed, "%s: locked, past the door he stays in the lane he's in, and may swipe back (stays %s, allowed %s)" % [area, stays, allowed])
	_check(closest > 0.0, "%s: locked, running past it CROSS never touches the door or its padlock (%.2f m clear at the closest)" % [area, closest])
	# The squad (and the alarm runner) keep out of that lane there too, and only there.
	var guard_x: float = level._through_doors(split - 2.0, p.lane_x(lane))
	_check(absf(guard_x - p.lane_x(into)) < 0.001 and is_equal_approx(level._through_doors(split - 8.0, p.lane_x(lane)), p.lane_x(lane))
			and level._barred_lane(float(bar["to"]) + 0.1) == -1,
			"%s: locked, anyone after him keeps out of its lane by the door, and only there" % area)
	# Unlocked, the bar's gone and the whole stairwell is back.
	gs.set_alert(open_alert)
	await process_frame
	_check(level._barred_lane(split - 2.0) != lane and seg["branches"].has(key), "%s: unlocked, its lane is free and its stairwell is back" % area)


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
			"obstacles": [{"kind": "barrier", "lanes": [2], "at": 15}, {"kind": "box", "lanes": [1], "at": 35}]},
		{"id": "e", "tier": "ground", "end": "extract"},
	]})
	problems = " ".join(cramped.validate())
	_check("barrier at 15" in problems and "too close to the stairs' exit" in problems, "nothing right outside a stairwell's exit door")
	_check(not "box at 35" in problems, "things further on after the stairs are fine")
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
	var g := RouteGraph.from_json_file(MISSION_1)
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
## Mission 1 has the basics only (user, approving its zones: no dogs, alarm runner, snipers,
## searchlights or pursuit squad); the test range keeps today's one runner and its dogs.
func _test_trooper_tiers() -> void:
	_trooper_tiers_in(MISSION_1, 0, false)
	_trooper_tiers_in(TEST_RANGE, 1, true)
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


func _trooper_tiers_in(path: String, want_runners: int, has_dogs: bool) -> void:
	var g := RouteGraph.from_json_file(path)
	var empty_at_1 := 0
	var runners := 0
	var dogs := 0
	# Per height: obstacles per metre and rifle guards at Alert 2, summed over its areas.
	var density := {"ground": [0, 0.0, 0], "roof": [0, 0.0, 0], "underground": [0, 0.0, 0]}
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
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
					dogs += 1
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
	_check(runners == want_runners, "%s: %d alarm runner(s) per run (%d)" % [path, want_runners, runners])
	_check((dogs > 0) == has_dogs, "%s: %s (%d)" % [path, "dogs from Alert 2" if has_dogs else "no dogs", dogs])



## The alarm runner's zone doors (user: "when the alert guard is running, the big doors should open
## and close for him, so he doesn't just faze through them"): he opens one only on his way through
## it, it's out of his way before he's at it, it never shuts on him (in it on his feet, or shot
## down in the doorway; a shutter drops behind him over his head), and it's shut again before you
## can get to it, at the least lead he ever has on you (the bot runner_escapes watches the real
## thing: gates=1/1/ok).
func _test_runner_doors() -> void:
	var tt := Tuning.new()
	var level: Dictionary = (load("res://game/levels/prototype_slice/prototype_slice.gd") as GDScript).get_script_constant_map()
	_check(level.has("GATE_H") and level.has("BASH_AHEAD") and level.has("SHUTTER_OPEN_AHEAD"), "the level's door constants load")
	if not level.has("GATE_H") or not level.has("BASH_AHEAD") or not level.has("SHUTTER_OPEN_AHEAD"):
		return
	var door := 200.0
	var leaf := 1.5 * tt.lane_width - 0.05  # a double door's leaf: half its three-lane doorway
	var ahead := SecurityTrooper.DOOR_AHEAD
	_check(SecurityTrooper.opens_door(door - ahead + 0.1, 400.0, door, ahead), "he shoves a zone door open as he comes")
	_check(not SecurityTrooper.opens_door(door - ahead - 1.0, 400.0, door, ahead), "not from further off")
	_check(not SecurityTrooper.opens_door(door + 0.5, 400.0, door, ahead), "not one he's through")
	_check(not SecurityTrooper.opens_door(door - 1.0, door - 0.5, door, ahead), "not one past his alarm (he stops short of it)")
	# Out of his way before he's at it (his front at the door): the leaves' push (eased out) is all
	# but done; a shutter's up over his head as he comes under it (his front 0.15 m short of it).
	var push := sin(PI / 2.0 * minf((ahead - 0.35) / tt.security_speed / SecurityTrooper.DOOR_PUSH_TIME, 1.0))
	_check(push > 0.95, "the leaves are right open before he's at them (%.2f of the way)" % push)
	var open_h: float = float(level["GATE_H"]) - 0.05  # (as far as he rolls one up)
	var up := sin(PI / 2.0 * minf((SecurityTrooper.SHUTTER_AHEAD - 0.5) / tt.security_speed / SecurityTrooper.SHUTTER_UP_TIME, 1.0)) * open_h
	_check(up > 2.2, "a shutter's up over his head before he's under it (%.2f m)" % up)
	# It never shuts on him.
	_check(SecurityTrooper.in_door_way(door, 0.0, false, door, leaf, leaf), "in the doorway, it's held open")
	_check(SecurityTrooper.in_door_way(door + leaf, 1.4, false, door, leaf, leaf), "still among its leaves, it's held open")
	_check(not SecurityTrooper.in_door_way(door + leaf + 0.5, 0.0, false, door, leaf, leaf), "through and clear of its leaves, it shuts")
	_check(SecurityTrooper.in_door_way(door - 1.0, 0.0, true, door, leaf, leaf), "shot down just short of it, he falls into the doorway: it stays open")
	_check(SecurityTrooper.in_door_way(door + 1.0, 0.0, true, door, leaf, leaf), "shot down among its leaves: it stays open")
	_check(not SecurityTrooper.in_door_way(door - SecurityTrooper.BODY_DOWN - 0.3, 0.0, true, door, leaf, leaf), "shot down further back, he falls clear of it: it shuts")
	_check(not SecurityTrooper.in_door_way(door + 1.0, 3.35, false, door, leaf, leaf), "at an alarm on the wall beside the doorway, he's clear of it")
	# A shutter (0.15 m deep) drops as soon as he's under it, slow enough off the top to stay over
	# his head until he's out from under it.
	_check(SecurityTrooper.in_door_way(door - 0.45, 0.0, false, door, 0.15, leaf), "coming under a shutter, he's in its way: it starts down behind him")
	_check(not SecurityTrooper.in_door_way(door + 0.55, 0.0, false, door, 0.15, leaf), "a metre on, he's out from under it")
	var over := SecurityTrooper.shutter_over_him(tt.security_speed, up, 0.15)
	_check(over > 2.2, "a shutter dropping behind him is still over his head as he comes out from under it (%.2f m)" % over)
	# Shut again before you can get to it. The least he's ever ahead of you: he spots you 40 m off
	# (a frame's run short of that, at worst), stands startled while you close in (a frame longer, at
	# worst), then runs on to his alarm, and you close on him by the difference in speed all the way.
	var lead := tt.security_trigger_distance - tt.run_speed * (tt.security_startle_time + 2.0 / 60.0) \
			- (tt.run_speed - tt.security_speed) * tt.security_alarm_distance / tt.security_speed
	_check(lead > 13.0, "he's always well ahead of you (%.2f m at the least)" % lead)
	# You burst through a door's leaves BASH_AHEAD short of them...
	var to_leaves := (lead - float(level["BASH_AHEAD"])) / tt.run_speed
	var shut := SecurityTrooper.door_shut_after(leaf, tt.security_speed, SecurityTrooper.DOOR_SHUT_TIME)
	_check(shut < to_leaves - 0.2, "a door he's been through is shut %.2f s after him, well before you can get to it (%.2f s)" % [shut, to_leaves])
	# ...but a shutter starts rolling up for you SHUTTER_OPEN_AHEAD out: it's down before then (a
	# few frames' slack, for its last frame and the state change after it).
	var to_shutter := (lead - float(level["SHUTTER_OPEN_AHEAD"])) / tt.run_speed
	var down := SecurityTrooper.shutter_shut_after(tt.security_speed)
	_check(down < to_shutter - 0.05, "a shutter's down %.2f s after him, before it starts rolling up for you (%.2f s)" % [down, to_shutter])


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
	var real := RouteGraph.from_json_file(TEST_RANGE)  # (searchlights: not in mission 1)
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
	# Each mission sets its own timeline: mission 1 on MEDIUM, the shipping setting (lands 28 s,
	# lifts off 96 s, gone 106 s: a clean ground run of about 81 s arrives 15 s before lift-off), the
	# test range as it was (114 s, for its ~90 s routes).
	var ch: Dictionary = RouteGraph.from_json_file(MISSION_1).mission().get("chopper", {})
	_check(float(ch.get("lands_at", 0)) == 28.0 and float(ch.get("lifts_at", 0)) == 96.0 and float(ch.get("gone_at", 0)) == 106.0,
			"mission 1 sets its own chopper times: 28 / 96 / 106 s (%s)" % ch)
	var g := RouteGraph.from_json_file(TEST_RANGE)
	_check(float(g.mission().get("chopper", {}).get("gone_at", 0)) == 114.0, "the test range keeps its own chopper time (scaled for the ~90 s level)")
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


## The stairs' clear exit (user, 2026-10-07: "Rule that after the player exits the stairs up or
## down objects can not be placed right outside, it's unfair as player can not react quick enough
## to avoid."): nothing of any kind within RouteGraph.STAIR_EXIT_CLEAR m after a flight's exit
## door, up or down. The flight is the area's first RouteGraph.STAIRS_FLIGHT m, so the door is that
## far in: 1 m short of the clear stretch's end is refused, right at its end is fine.
func _test_stair_exit_clear() -> void:
	var tuning := load("res://game/config/default_tuning.tres") as Tuning
	_check(tuning != null and is_equal_approx(tuning.tier_height * tuning.stairs_run, RouteGraph.STAIRS_FLIGHT),
			"the stairs rule's flight is %s m, as long as the level builds it (tier_height x stairs_run)" % RouteGraph.STAIRS_FLIGHT)
	var defaults := Tuning.new()
	_check(is_equal_approx(defaults.tier_height * defaults.stairs_run, RouteGraph.STAIRS_FLIGHT), "...and as long as Tuning's defaults make it")
	_check(is_equal_approx(RouteGraph.STAIR_EXIT_CLEAR, RouteGraph.MARKER_CLEAR_AFTER), "a stairs door gets the same room after it as a zone door")
	_check(is_equal_approx(RouteGraph.STAIR_CLEAR_TO, RouteGraph.STAIRS_FLIGHT + RouteGraph.STAIR_EXIT_CLEAR),
			"the clear stretch counts from the exit door, not from the start of the flight")
	var end := {"id": "e", "tier": "ground", "end": "extract"}
	# Up: from the ground onto a roof. Down: from a roof to the ground.
	var flights := {
		"up": func(dest: Dictionary) -> RouteGraph: return RouteGraph.from_dict({"start": "a", "nodes": [
			{"id": "a", "tier": "ground", "length": 60, "next": [{"to": "e"}, {"to": "d", "side": "right", "via": "stairs"}]},
			dest.merged({"tier": "roof", "next": [{"to": "e", "side": "left", "via": "ladder"}]}), end]}),
		"down": func(dest: Dictionary) -> RouteGraph: return RouteGraph.from_dict({"start": "a", "nodes": [
			{"id": "a", "tier": "roof", "length": 60, "next": [{"to": "r"}, {"to": "d", "side": "left", "via": "stairs"}]},
			{"id": "r", "tier": "roof", "length": 60, "next": [{"to": "e", "side": "left", "via": "ladder"}]},
			dest.merged({"tier": "ground", "next": [{"to": "e"}]}), end]}),
	}
	# [the list it's in, the thing, what the rule calls it]. Searchlights and snipers only go on roofs.
	var things := [
		["obstacles", {"kind": "barrier", "lanes": [2]}, "barrier"],
		["obstacles", {"kind": "pipe", "lanes": [1, 2, 3]}, "pipe"],
		["obstacles", {"kind": "tripwire", "lanes": [2]}, "tripwire"],
		["obstacles", {"kind": "box", "lanes": [2]}, "box"],
		["obstacles", {"kind": "wall", "lanes": [2]}, "wall"],
		["enemies", {"kind": "rifle_trooper", "lane": 2}, "rifle_trooper"],
		["enemies", {"kind": "rusher_dog", "lane": 2}, "rusher_dog"],
		["enemies", {"kind": "security_trooper", "lane": 2}, "security_trooper"],  # the alarm runner
		["searchlights", {"side": "left"}, "searchlight"],
		["snipers", {"side": "left"}, "sniper"],
	]
	var cases := [[RouteGraph.STAIR_CLEAR_TO - 1.0, true], [RouteGraph.STAIR_CLEAR_TO, false]]
	for way in flights:
		for t in things:
			if way == "down" and t[0] in ["searchlights", "snipers"]:
				continue
			for c in cases:
				var item: Dictionary = t[1].merged({"at": c[0]})
				var g: RouteGraph = flights[way].call({"id": "d", "length": 120, t[0]: [item]})
				var refused := " | ".join(g.validate()).contains("%s at %s m is too close to the stairs' exit door" % [t[2], c[0]])
				_check(refused == c[1], "stairs %s: a %s %s m in (%s m after the exit door) is %s" % [way, t[2], c[0],
						c[0] - RouteGraph.STAIRS_FLIGHT, "refused" if c[1] else "fine"])
	# What the old rule let through (20 m from the start of the area: 8 m after the door) is out now.
	var old := RouteGraph.STAIR_EXIT_CLEAR + 1.0
	var g_old: RouteGraph = flights["down"].call({"id": "d", "length": 120, "obstacles": [{"kind": "barrier", "lanes": [2], "at": old}]})
	_check(" | ".join(g_old.validate()).contains("barrier at %s m is too close to the stairs' exit door" % old),
			"stairs: a barrier %s m in, only %s m after the exit door, is refused now" % [old, old - RouteGraph.STAIRS_FLIGHT])


## The fair-reaction rule (user, 2026-10-08, on a slide right after a jump: "But it only works as long
## as there is still time for the player to land and swipe."): between two obstacles you have to act
## on in the same lane, there is always time to land if you must, then a swipe's reaction time
## (RouteGraph.REACTION_HARD, HARD's floor). For every pair of kinds (a barrier or a tripwire to jump,
## a pipe to slide under), one 0.5 m too close is refused and one just far enough is fine; the gaps
## follow Tuning; the real Player, stepped at 60 Hz, makes every gap whichever way he got past the
## first; cover between them, another lane, a side exit's other lanes and a ladder don't count; the
## join into the next area does.
func _test_fair_reaction() -> void:
	var t := Tuning.new()
	var kinds := ["barrier", "tripwire", "pipe"]
	var lanes_of := {"barrier": [1, 2], "tripwire": [0, 1, 2, 3, 4], "pipe": [1, 2, 3]}
	var area := func(obstacles: Array) -> RouteGraph:
		return RouteGraph.from_dict({"start": "a", "nodes": [{"id": "a", "tier": "ground", "length": 100, "end": "extract", "obstacles": obstacles}]})
	for a: String in kinds:
		for b: String in kinds:
			var gap := RouteGraph.reaction_gap(a, b, t)
			for c in [[gap - 0.5, true], [gap, false]]:
				var at: float = 40.0 + c[0]
				var g: RouteGraph = area.call([{"kind": a, "lanes": lanes_of[a], "at": 40.0}, {"kind": b, "lanes": lanes_of[b], "at": at}])
				var refused := " | ".join(g.validate(t)).contains("%s at %s m is too soon after the %s at 40.0 m" % [b, at, a])
				_check(refused == c[1], "fair reaction: a %s %.2f m after a %s in its lane is %s (%.2f m needed)" % [b, c[0], a,
						"refused" if c[1] else "fine", gap])
	# From the physics: two jumps need the whole jump (the latest one over the first: you land last)
	# and the reaction; two slides only the reaction; a jump after a slide its lift too; a slide after a
	# jump the drop from the air; each plus a frame (swipes are read, and hits checked, once a frame).
	var air := 2.0 * t.jump_velocity / t.gravity
	var up := (t.jump_velocity - sqrt(t.jump_velocity ** 2 - 2.0 * t.gravity * t.jump_clear_height)) / t.gravity
	var react := RouteGraph.REACTION_HARD + 1.0 / Engine.physics_ticks_per_second
	var zone := RouteGraph.DEPTHS["barrier"] + 2.0 * RouteGraph.HIT_REACH
	_check(is_equal_approx(RouteGraph.reaction_gap("barrier", "barrier", t), t.run_speed * (air + react)),
			"fair reaction: two barriers need the whole jump and the reaction (%.2f m)" % RouteGraph.reaction_gap("barrier", "barrier", t))
	_check(is_equal_approx(RouteGraph.reaction_gap("pipe", "pipe", t), zone + t.run_speed * react),
			"fair reaction: two pipes need only the reaction (%.2f m)" % RouteGraph.reaction_gap("pipe", "pipe", t))
	_check(is_equal_approx(RouteGraph.reaction_gap("pipe", "barrier", t), zone + t.run_speed * (react + up)),
			"fair reaction: a barrier after a pipe needs the reaction and the jump's lift (%.2f m)" % RouteGraph.reaction_gap("pipe", "barrier", t))
	var j_s := RouteGraph.reaction_gap("barrier", "pipe", t)
	_check(j_s > RouteGraph.reaction_gap("pipe", "pipe", t) and j_s < RouteGraph.reaction_gap("pipe", "pipe", t) + t.run_speed * 0.2,
			"fair reaction: a pipe after a barrier needs the reaction and the drop from the air, no landing (%.2f m)" % j_s)
	var fast := Tuning.new()
	fast.run_speed = 22.0
	_check(is_equal_approx(RouteGraph.reaction_gap("barrier", "barrier", fast), 2.0 * RouteGraph.reaction_gap("barrier", "barrier", t)),
			"fair reaction: twice the run speed, twice the room between two barriers")
	var floaty := Tuning.new()
	floaty.jump_velocity = 9.0
	_check(RouteGraph.reaction_gap("barrier", "barrier", floaty) > RouteGraph.reaction_gap("barrier", "barrier", t),
			"fair reaction: a longer jump needs more room before the next one")
	_check(is_equal_approx(RouteGraph.reaction_gap("pipe", "pipe", t, RouteGraph.REACTION_HARD + 0.1),
			RouteGraph.reaction_gap("pipe", "pipe", t) + 0.1 * t.run_speed), "fair reaction: a slower swipe needs that much more road")
	_check(RouteGraph.REACTION_HARD < RouteGraph.REACTION_MEDIUM and RouteGraph.REACTION_MEDIUM < RouteGraph.REACTION_EASY,
			"fair reaction: MEDIUM and EASY give you more time than HARD")
	# The rule's depths and reach are the level's own (KINDS, and _check_obstacles' HIT_REACH).
	var kinds_built: Dictionary = (load("res://game/levels/prototype_slice/prototype_slice.gd") as GDScript).get_script_constant_map()["KINDS"]
	for k: String in kinds:
		_check(is_equal_approx(kinds_built[k]["size"].z, RouteGraph.DEPTHS[k]), "fair reaction: a %s is as deep as the level builds it" % k)
	var level_src := FileAccess.get_file_as_string("res://game/levels/prototype_slice/prototype_slice.gd")
	_check(level_src.contains("> o[\"depth\"] / 2.0 + RouteGraph.HIT_REACH:"), "fair reaction: the level's hit test reaches RouteGraph.HIT_REACH past an obstacle")
	# The real Player, 60 times a second, for every pair: at the rule's gap there is always a swipe in
	# time for the second (made a reaction time after he's past the first, and down if it's a jump
	# after a jump), however he got past the first; 0.5 m less and some way past the first leaves none.
	var gs := root.get_node("GameState")
	var was_active: bool = gs.run_active
	gs.run_active = true
	var p: Node3D = (load("res://game/player/player.gd") as GDScript).new()  # (by path: it needs the autoloads)
	p.tuning = load("res://game/config/default_tuning.tres") as Tuning
	root.add_child(p)
	p.set_physics_process(false)
	p.set_process(false)
	for a: String in kinds:
		for b: String in kinds:
			var gap := RouteGraph.reaction_gap(a, b, p.tuning)
			var at_gap := _fair_sim(p, a, b, gap)
			var closer := _fair_sim(p, a, b, gap - 0.5)
			_check(at_gap.x == 0 and at_gap.y > 20, "fair reaction, the real player: a %s %.2f m after a %s, every way past it (%d) leaves time (%d don't)"
					% [b, gap, a, at_gap.y, at_gap.x])
			_check(closer.x > 0, "fair reaction, the real player: 0.5 m closer, some way past the %s leaves no time for the %s" % [a, b])
	p.free()
	gs.run_active = was_active
	# Only what's in the same lane counts, cover between them stops you first, and a sidestep is no
	# way out (the next lanes free beside the second doesn't help).
	var near := RouteGraph.reaction_gap("barrier", "barrier", t) - 2.0
	var g2: RouteGraph = area.call([{"kind": "barrier", "lanes": [2], "at": 30.0}, {"kind": "barrier", "lanes": [2], "at": 30.0 + near},
			{"kind": "barrier", "lanes": [1], "at": 60.0}, {"kind": "pipe", "lanes": [2], "at": 62.0},
			{"kind": "barrier", "lanes": [3], "at": 80.0}, {"kind": "box", "lanes": [3], "at": 83.0}, {"kind": "barrier", "lanes": [3], "at": 86.0}])
	var found := " | ".join(g2.validate(t))
	_check(found.contains("barrier at %s m is too soon after the barrier at 30.0 m in lane 2 " % (30.0 + near)),
			"fair reaction: a barrier in only one lane is still too soon (a sidestep is no way out)")
	_check(not found.contains("pipe at 62.0 m is too soon"), "fair reaction: a pipe in the next lane is no pair")
	_check(not found.contains("barrier at 86.0 m is too soon"), "fair reaction: cover between them stops you first, so they're no pair")
	# The join into the next area: straight on, every lane; a left exit only from lane 0, which becomes
	# the branch's lane 4; up a ladder you climb.
	var joined := RouteGraph.from_dict({"start": "a", "nodes": [
		{"id": "a", "tier": "ground", "length": 100, "obstacles": [{"kind": "barrier", "lanes": [0, 2], "at": 98.0}],
			"next": [{"to": "b"}, {"to": "c", "side": "left", "via": "corridor"}]},
		{"id": "b", "tier": "ground", "length": 60, "end": "extract", "obstacles": [{"kind": "pipe", "lanes": [2], "at": 2.0}]},
		{"id": "c", "tier": "ground", "length": 60, "end": "extract", "obstacles": [
			{"kind": "pipe", "lanes": [4], "at": 3.0}, {"kind": "pipe", "lanes": [0], "at": 4.0}]},
	]})
	found = " | ".join(joined.validate(t))
	_check(found.contains("node 'a' into 'b': pipe at 2.0 m into 'b' is too soon after the barrier at 98.0 m in lane 2 "),
			"fair reaction: straight on into the next area, the pair across the join is refused")
	_check(found.contains("node 'a' into 'c': pipe at 3.0 m into 'c' is too soon after the barrier at 98.0 m in lane 0 "),
			"fair reaction: at a left exit, lane 0 runs on into the branch's lane 4")
	_check(not found.contains("pipe at 4.0 m into 'c'"), "fair reaction: ...and the branch's lane 0 isn't the lane you came in on")
	var climbed := RouteGraph.from_dict({"start": "a", "nodes": [
		{"id": "a", "tier": "ground", "length": 100, "obstacles": [{"kind": "barrier", "lanes": [0], "at": 98.0}],
			"next": [{"to": "b"}, {"to": "e", "side": "left", "via": "ladder"}]},
		{"id": "b", "tier": "ground", "length": 60, "end": "extract"},
		{"id": "e", "tier": "roof", "length": 60, "end": "extract", "obstacles": [{"kind": "pipe", "lanes": [0, 4], "at": 2.0}]},
	]})
	_check(not " | ".join(climbed.validate(t)).contains("too soon"), "fair reaction: up a ladder you climb, so there's no pair across it")
	_test_one_jump(t, area)
	_test_one_jump_across(t, area)


## The fair-reaction rule's one-jump pairs over the join into the next area, timed as inside one
## area: a wire at the end of one area and a barrier at the start of the next that one jump clears
## are one obstacle, and what follows them (a pipe to slide, a barrier to jump) is timed from the
## pair, passing and failing at the same gaps as the same layout inside one area, and told once, as
## the pair across the join. Coming in another way that runs nothing on into the barrier, or up a
## ladder, the barrier stands alone, and the same pipe is too soon after it.
func _test_one_jump_across(t: Tuning, area: Callable) -> void:
	var react := RouteGraph.REACTION_HARD + 1.0 / Engine.physics_ticks_per_second
	var pipe_after := RouteGraph.DEPTHS["barrier"] / 2.0 + RouteGraph.HIT_REACH + t.run_speed * react + RouteGraph.DEPTHS["pipe"] / 2.0 + RouteGraph.HIT_REACH
	var barrier_after := RouteGraph.reaction_gap("tripwire", "barrier", t) - 2.0  # (from the wire, as after its first)
	var joined := func(a_obs: Array, b_obs: Array) -> RouteGraph:
		return RouteGraph.from_dict({"start": "a", "nodes": [
			{"id": "a", "tier": "ground", "length": 100, "obstacles": a_obs, "next": [{"to": "b"}]},
			{"id": "b", "tier": "ground", "length": 60, "end": "extract", "obstacles": b_obs}]})
	var wire := {"kind": "tripwire", "lanes": [0, 1, 2, 3, 4], "at": 99.0}
	var bar := {"kind": "barrier", "lanes": [2], "at": 1.0}
	for follow: Array in [["pipe", pipe_after], ["barrier", barrier_after]]:
		var kind: String = follow[0]
		for c in [[0.0, false], [-0.5, true]]:
			var gap: float = follow[1] + c[0]
			var inside: RouteGraph = area.call([{"kind": "tripwire", "lanes": [0, 1, 2, 3, 4], "at": 40.0}, {"kind": "barrier", "lanes": [2], "at": 42.0},
					{"kind": kind, "lanes": [2], "at": 42.0 + gap}])
			var across: RouteGraph = joined.call([wire], [bar, {"kind": kind, "lanes": [2], "at": 1.0 + gap}])
			var one := " | ".join(inside.validate(t))
			var two := " | ".join(across.validate(t))
			var told := "%.2f m apart, %.2f m needed" % [gap, follow[1]]
			var in_one := one.contains("%s at %s m is too soon after the tripwire at 40.0 m and the barrier at 42.0 m (one jump clears both) in lane 2 (%s" % [kind, 42.0 + gap, told])
			var in_two := two.contains("node 'a' into 'b': %s at %s m into 'b' is too soon after the tripwire at 99.0 m and the barrier at 1.0 m into 'b' (one jump clears both) in lane 2 (%s" % [kind, 1.0 + gap, told])
			_check(in_one == c[1] and in_two == c[1] and two.count("too soon") == (1 if c[1] else 0),
					"one jump over a join: a %s %.2f m after the pair's barrier is %s, as inside one area (told from the pair, across the join)" % [kind, gap, "too soon" if c[1] else "fine"])
	# Another way into the same area that runs nothing on into it (a branch with nothing at its end),
	# and a ladder up into it: the barrier stands alone, so the pipe the pair allows is too soon.
	_check(pipe_after < RouteGraph.reaction_gap("barrier", "pipe", t), "one jump over a join: a lone barrier needs more road before a pipe than the pair does")
	var lone := "node 'b': pipe at %s m is too soon after the barrier at 1.0 m in lane 2 " % (1.0 + pipe_after)
	var two_ways := RouteGraph.from_dict({"start": "a", "nodes": [
		{"id": "a", "tier": "ground", "length": 100, "obstacles": [wire], "next": [{"to": "b"}, {"to": "c", "side": "left", "via": "corridor"}]},
		{"id": "c", "tier": "ground", "length": 60, "next": [{"to": "b"}]},
		{"id": "b", "tier": "ground", "length": 60, "end": "extract", "obstacles": [bar, {"kind": "pipe", "lanes": [2], "at": 1.0 + pipe_after}]}]})
	var found := " | ".join(two_ways.validate(t))
	_check(found.contains(lone) and not found.contains("node 'a' into 'b': pipe"), "one jump over a join: in by another way, with nothing run on, the barrier stands alone and the pipe is too soon after it")
	var laddered := RouteGraph.from_dict({"start": "a", "nodes": [
		{"id": "a", "tier": "ground", "length": 100, "obstacles": [wire], "next": [{"to": "b"}, {"to": "c", "side": "left", "via": "corridor"}]},
		{"id": "c", "tier": "ground", "length": 60, "next": [{"to": "b", "side": "left", "via": "ladder"}]},
		{"id": "b", "tier": "roof", "length": 60, "end": "extract", "obstacles": [bar, {"kind": "pipe", "lanes": [2], "at": 1.0 + pipe_after}]}]})
	_check(" | ".join(laddered.validate(t)).contains(lone), "one jump over a join: up a ladder into it, the barrier stands alone too")


## The fair-reaction rule's one-jump pairs (user: "there is still time for the player to land and
## swipe": if one jump clears both, there's no landing between them to need time for). Obstacles to
## jump close enough for one jump to keep his feet above jump_clear_height over both stretches (less a
## frame: he can only take off on one) count as one; just too far apart for that, the second needs
## the whole reaction_gap. Pipes never pair up (a slide is its own swipe). What comes after the pair
## is timed from the pair's end; the real Player, stepped at 60 Hz, clears every pair the rule allows
## in one jump, and none 0.5 m further apart.
func _test_one_jump(t: Tuning, area: Callable) -> void:
	var lanes_of := {"barrier": [1, 2], "tripwire": [0, 1, 2, 3, 4]}
	var root_ := sqrt(t.jump_velocity ** 2 - 2.0 * t.gravity * t.jump_clear_height)
	var above := 2.0 * root_ / t.gravity  # his feet above clear height, s
	_check(is_equal_approx(RouteGraph.one_jump_reach(t), t.run_speed * (above - 1.0 / Engine.physics_ticks_per_second)),
			"one jump: it carries him over %.2f m of road above clear height, less a frame's run" % RouteGraph.one_jump_reach(t))
	for a: String in ["barrier", "tripwire"]:
		for b: String in ["barrier", "tripwire"]:
			var most := RouteGraph.one_jump_gap(a, b, t)
			_check(most > 1.5 and most < RouteGraph.reaction_gap(a, b, t) - 5.0,
					"one jump: a %s up to %.2f m after a %s clears with it; from there to %.2f m apart is too close for two" % [b, most, a, RouteGraph.reaction_gap(a, b, t)])
			for c in [[most, false], [most + 0.05, true]]:
				var at: float = 40.0 + c[0]
				var g: RouteGraph = area.call([{"kind": a, "lanes": lanes_of[a], "at": 40.0}, {"kind": b, "lanes": lanes_of[b], "at": at}])
				var found := " | ".join(g.validate(t))
				_check(found.contains("%s at %s m is too soon after the %s at 40.0 m" % [b, at, a]) == c[1],
						"one jump: a %s %.2f m after a %s is %s" % [b, c[0], a, "too far for one jump and too close for two: refused" if c[1] else "one jump over both: fine"])
	# The LOADING DOCK's: the wire at 38 m in every lane, the bumper blocks 2 m behind it in three.
	var dock: RouteGraph = area.call([{"kind": "tripwire", "lanes": [0, 1, 2, 3, 4], "at": 38.0}, {"kind": "barrier", "lanes": [0, 1, 2], "at": 40.0}])
	_check(not " | ".join(dock.validate(t)).contains("too soon"), "one jump: the dock's wire and bumper blocks 2 m apart are one jump")
	# Only jumps pair up: a slide is a swipe of its own, so 2 m is too close whatever the order.
	for pair in [["pipe", "pipe"], ["barrier", "pipe"], ["pipe", "barrier"], ["pipe", "tripwire"]]:
		var g: RouteGraph = area.call([{"kind": pair[0], "lanes": [2], "at": 40.0}, {"kind": pair[1], "lanes": [2], "at": 42.0}])
		_check(" | ".join(g.validate(t)).contains("%s at 42.0 m is too soon after the %s at 40.0 m" % [pair[1], pair[0]]),
				"one jump: a %s 2 m after a %s is still refused (no one jump over a slide)" % [pair[1], pair[0]])
	# After a pair, the next one is timed from the pair, as after its first: the latest jump that clears
	# them both is the latest over the first, and he's past the second still in it. Before it, as before
	# its first.
	var after := 40.0 + RouteGraph.reaction_gap("tripwire", "barrier", t)
	for c in [[after, false], [after - 0.5, true]]:
		var g: RouteGraph = area.call([{"kind": "tripwire", "lanes": [2], "at": 40.0}, {"kind": "barrier", "lanes": [2], "at": 42.0},
				{"kind": "barrier", "lanes": [2], "at": c[0]}])
		var found := " | ".join(g.validate(t))
		_check(found.contains("barrier at %s m is too soon after the tripwire at 40.0 m and the barrier at 42.0 m (one jump clears both) in lane 2 (%.2f m apart, %.2f m needed"
				% [c[0], c[0] - 42.0, after - 42.0]) == c[1], "one jump: a barrier %.2f m after the pair's wire is %s (told from the pair's last one)" % [c[0] - 40.0, "too soon" if c[1] else "fine"])
	# A slide after it: the swipe can't come till he's past the pair's last one. The latest jump over
	# the pair is down by the time the reaction is up, so he slides from the ground.
	var up := (t.jump_velocity - root_) / t.gravity
	var pair_end := 42.0 + RouteGraph.DEPTHS["barrier"] / 2.0 + RouteGraph.HIT_REACH
	var pair_start := 40.0 - RouteGraph.DEPTHS["tripwire"] / 2.0 - RouteGraph.HIT_REACH
	var left_in_air := 2.0 * t.jump_velocity / t.gravity - up - (pair_end - pair_start) / t.run_speed
	var slide_at := pair_end + t.run_speed * (RouteGraph.REACTION_HARD + 1.0 / Engine.physics_ticks_per_second) + RouteGraph.DEPTHS["pipe"] / 2.0 + RouteGraph.HIT_REACH
	_check(left_in_air < RouteGraph.REACTION_HARD, "one jump: the latest jump over the pair is down %.2f s after it, inside the reaction" % left_in_air)
	for c in [[slide_at, false], [slide_at - 0.5, true]]:
		var g: RouteGraph = area.call([{"kind": "tripwire", "lanes": [2], "at": 40.0}, {"kind": "barrier", "lanes": [2], "at": 42.0},
				{"kind": "pipe", "lanes": [2], "at": c[0]}])
		_check(" | ".join(g.validate(t)).contains("pipe at %s m is too soon after the tripwire at 40.0 m and the barrier at 42.0 m (one jump clears both)" % c[0]) == c[1],
				"one jump: a pipe %.2f m after the pair's last one is %s" % [c[0] - 42.0, "too soon" if c[1] else "fine"])
	var before := 40.0 - RouteGraph.reaction_gap("pipe", "tripwire", t)
	for c in [[before, false], [before + 0.5, true]]:
		var g: RouteGraph = area.call([{"kind": "pipe", "lanes": [2], "at": c[0]}, {"kind": "tripwire", "lanes": [2], "at": 40.0},
				{"kind": "barrier", "lanes": [2], "at": 42.0}])
		var found := " | ".join(g.validate(t))
		_check(found.contains("tripwire at 40.0 m and the barrier at 42.0 m (one jump clears both) is too soon after the pipe at %s m" % c[0]) == c[1],
				"one jump: the pair %.2f m after a pipe is %s" % [40.0 - c[0], "too soon" if c[1] else "fine"])
	# Three in a row that one jump can't clear together: the third is too soon after the pair.
	var three: RouteGraph = area.call([{"kind": "barrier", "lanes": [2], "at": 40.0}, {"kind": "barrier", "lanes": [2], "at": 42.0},
			{"kind": "barrier", "lanes": [2], "at": 45.5}])
	_check(" | ".join(three.validate(t)).contains("barrier at 45.5 m is too soon after the barrier at 40.0 m and the barrier at 42.0 m (one jump clears both)"),
			"one jump: three barriers over more road than one jump covers are refused")
	var three_close: RouteGraph = area.call([{"kind": "tripwire", "lanes": [2], "at": 40.0}, {"kind": "tripwire", "lanes": [2], "at": 41.5},
			{"kind": "tripwire", "lanes": [2], "at": 43.0}])
	_check(not " | ".join(three_close.validate(t)).contains("too soon"), "one jump: three wires inside one jump's reach are one jump")
	# The real Player at 60 Hz: for every pair, at the rule's furthest apart some take-off frame clears
	# both at every frame alignment of the road; 0.5 m further apart, none does at any.
	var gs := root.get_node("GameState")
	var was_active: bool = gs.run_active
	gs.run_active = true
	var p: Node3D = (load("res://game/player/player.gd") as GDScript).new()  # (by path: it needs the autoloads)
	p.tuning = load("res://game/config/default_tuning.tres") as Tuning
	root.add_child(p)
	p.set_physics_process(false)
	p.set_process(false)
	for a: String in ["barrier", "tripwire"]:
		for b: String in ["barrier", "tripwire"]:
			var most := RouteGraph.one_jump_gap(a, b, p.tuning)
			var at_most := _one_jump_sim(p, a, b, most)
			var further := _one_jump_sim(p, a, b, most + 0.5)
			_check(at_most == 5, "one jump, the real player: a %s %.2f m after a %s, one jump clears both at %d of 5 alignments" % [b, most, a, at_most])
			_check(further == 0, "one jump, the real player: 0.5 m further apart, no jump clears both (%d of 5)" % further)
	p.free()
	gs.run_active = was_active


## For _test_one_jump: player `p` (a Player) runs at a `first` and a `second` obstacle to jump, `gap` m
## apart in his lane, stepped at 60 Hz, with the road at 5 alignments to his frames. Returns how many
## alignments have a take-off frame whose one jump clears both (the level's hit test, _check_obstacles).
func _one_jump_sim(p: Node3D, first: String, second: String, gap: float) -> int:
	var dt := 1.0 / 60.0
	var t: Tuning = p.tuning
	var step := t.run_speed * dt
	var reach_a: float = RouteGraph.DEPTHS[first] / 2.0 + RouteGraph.HIT_REACH
	var reach_b: float = RouteGraph.DEPTHS[second] / 2.0 + RouteGraph.HIT_REACH
	var start := 20.0  # (where he starts, fixed: the road moves under his frames)
	var cleared := 0
	for k in 5:
		var at_a := 30.0 + step * k / 5.0
		var at_b := at_a + gap
		var any := false
		for fa in range(int((at_a - 8.0 - start) / step), int((at_a - start) / step) + 1):
			p.distance = start
			p.jump_y = 0.0
			p.set("_y_velocity", 0.0)
			p.set("_slide_left", 0.0)
			p.set("_stun_left", 0.0)
			p.set("_speed_mul", 1.0)
			p.lane = t.lane_count / 2
			p.track_x = p.lane_x(p.lane)
			var hit := false
			var f := 0
			while p.distance <= at_b + reach_b and not hit:
				if f == fa:
					p.handle_swipe(Vector2i.UP)
				p._physics_process(dt)
				for o in [[at_a, reach_a], [at_b, reach_b]]:
					if absf(o[0] - p.distance) <= o[1] and not p.clears_low_obstacle():
						hit = true
				f += 1
			if not hit:
				any = true
				break
		if any:
			cleared += 1
	return cleared


## For _test_fair_reaction: player `p` (a Player) runs at a `first` obstacle and then a `second`, `gap`
## m apart in his lane, stepped at 60 Hz. For every frame his swipe for the first could come on that gets
## him past it, his swipe for the second may come no sooner than RouteGraph.REACTION_HARD after the
## moment he left the first one's stretch (and for a jump after a jump, after the moment he's down, and
## once he is). Returns (ways past the first that leave no swipe in time for the second, ways past it).
## The hit test is the level's (_check_obstacles).
func _fair_sim(p: Node3D, first: String, second: String, gap: float) -> Vector2i:
	var dt := 1.0 / 60.0
	var t: Tuning = p.tuning
	var at_a := 30.0
	var at_b := at_a + gap
	var reach_a: float = RouteGraph.DEPTHS[first] / 2.0 + RouteGraph.HIT_REACH
	var reach_b: float = RouteGraph.DEPTHS[second] / 2.0 + RouteGraph.HIT_REACH
	var swipe := func(kind: String) -> void: p.handle_swipe(Vector2i.UP if RouteGraph.ACTIONS[kind] == "jump" else Vector2i.DOWN)
	var passes := func(kind: String) -> bool: return p.clears_low_obstacle() if RouteGraph.ACTIONS[kind] == "jump" else p.is_sliding()
	var put := func(s: Array) -> void:
		p.distance = s[0]
		p.jump_y = s[1]
		p.set("_y_velocity", s[2])
		p.set("_slide_left", s[3])
		p.set("_stun_left", 0.0)
		p.set("_speed_mul", 1.0)
		p.lane = t.lane_count / 2
		p.track_x = p.lane_x(p.lane)
	var stuck := 0
	var ways := 0
	for fa in range(int((at_a - 10.0) / (t.run_speed * dt)), int((at_a + 1.0) / (t.run_speed * dt))):
		put.call([0.0, 0.0, 0.0, 0.0])
		var states: Array = []  # his state before each frame's swipe
		var hit_a := false
		var left_at := -1.0
		var down_at := -1.0
		var down_frame := -1
		var was_up := false
		var b_hits := 1 << 30  # the first frame the second trips him if he doesn't swipe for it
		var f := 0
		while p.distance < at_b + 1.0:
			states.append([p.distance, p.jump_y, p.get("_y_velocity"), p.get("_slide_left")])
			if f == fa:
				swipe.call(first)
			var d0: float = p.distance
			var y0: float = p.jump_y
			var vy0: float = p.get("_y_velocity")
			p._physics_process(dt)
			if absf(at_a - p.distance) <= reach_a and not passes.call(first):
				hit_a = true
			if b_hits > f and absf(at_b - p.distance) <= reach_b and not passes.call(second):
				b_hits = f
			if left_at < 0.0 and p.distance > at_a + reach_a:
				left_at = (f + (at_a + reach_a - d0) / (p.distance - d0)) * dt  # (within the frame's step)
			if f >= fa and p.is_airborne():
				was_up = true
			elif f >= fa and down_frame < 0 and (was_up or RouteGraph.ACTIONS[first] != "jump"):
				down_frame = f
				var v1 := vy0 - t.gravity * dt
				down_at = (f + (y0 / (-v1 * dt) if v1 < 0.0 else 0.0)) * dt
			f += 1
		if hit_a:
			continue
		ways += 1
		var from := left_at
		var soonest := 0
		if RouteGraph.ACTIONS[first] == "jump" and RouteGraph.ACTIONS[second] == "jump":
			from = maxf(left_at, down_at)
			soonest = down_frame + 1  # (an up swipe only works on the ground)
		soonest = maxi(soonest, ceili((from + RouteGraph.REACTION_HARD) / dt - 0.0001))
		var made_it := false
		for fb in range(soonest, mini(b_hits + 1, states.size())):
			put.call(states[fb])
			swipe.call(second)
			var hit_b := false
			while p.distance <= at_b + reach_b:
				p._physics_process(dt)
				if absf(at_b - p.distance) <= reach_b and not passes.call(second):
					hit_b = true
					break
			if not hit_b:
				made_it = true
				break
		if not made_it:
			stuck += 1
	return Vector2i(stuck, ways)


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
	# (Each of these tests one rule, so the cover-exit rule, which these spots would also break, is off.)
	var squeeze := RouteGraph.from_dict({"start": "a", "cover_exit_rule": false, "nodes": [
		{"id": "a", "length": 100, "end": "extract", "obstacles": [
			{"kind": "wall", "lanes": [0, 1], "at": 20}, {"kind": "box", "lanes": [2], "at": 21},
			{"kind": "pipe", "lanes": [3, 4], "at": 22},
			{"kind": "wall", "lanes": [0, 1], "at": 50}, {"kind": "barrier", "lanes": [2, 3, 4], "at": 51},
			{"kind": "wall", "lanes": [3, 4], "at": 70}, {"kind": "box", "lanes": [2], "at": 70},
			{"kind": "barrier", "lanes": [0, 1], "at": 86},  # (13 m after the tripwire: time to land and jump again)
			{"kind": "tripwire", "lanes": [0, 1, 2, 3, 4], "at": 73}]},
	]})
	problems = " ".join(squeeze.validate())
	_check("pipe at 22" in problems, "cover on 3 lanes + a pipe in the open lanes is rejected (forced swipe-and-jump)")
	_check(not "barrier at 51" in problems, "cover on only 2 lanes leaves room: a barrier nearby is fine")
	_check(not "barrier at 86" in problems, "a barrier well after the cover is fine")
	_check(not "tripwire" in problems, "a tripwire next to cover is fine (it only raises alert)")
	var stacked := RouteGraph.from_dict({"start": "roof", "nodes": [
		{"id": "roof", "tier": "roof", "next": [{"to": "sewer_straight"}, {"to": "sewer", "side": "left", "via": "stairs"}]},
		{"id": "sewer_straight", "tier": "roof", "end": "extract"},
		{"id": "sewer", "tier": "underground", "end": "extract"},
	]})
	_check("only move one level" in " ".join(stacked.validate()), "no stairs from the roof straight into a tunnel")
	var crowded := RouteGraph.from_dict({"start": "a", "cover_exit_rule": false, "nodes": [
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


## Mission 1, COLD CALL (user, approving its zones: "You have the go ahead now."): 10 areas, one
## junction at the end of the SECURITY WING (straight on, the basement stairs, the fire escape), the
## basics only, the squad off; the ways in order of length; its route map; and its finds kept apart
## from every other mission's.
func _test_mission_1() -> void:
	var g := RouteGraph.from_json_file(MISSION_1)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MISSION_1))
	_check(g._nodes.size() == 10 and data.get("mission", "") == "cold_call" and data.get("squad", true) == false,
			"mission 1: 10 areas, its own id, and no pursuit squad (%d areas, %s, squad %s)" % [g._nodes.size(), data.get("mission"), data.get("squad")])
	var extras := PackedStringArray()
	var side_exits := PackedStringArray()
	for n: Dictionary in data["nodes"]:
		for e in n.get("enemies", []):
			if String(e.get("kind", "")) != "rifle_trooper":
				extras.append("%s: %s" % [n["id"], e["kind"]])
		for what in ["snipers", "searchlights"]:
			if not n.get(what, []).is_empty():
				extras.append("%s: %s" % [n["id"], what])
		for e in n.get("next", []):
			if RouteGraph.side_of(e) != "straight":
				side_exits.append("%s %s %s" % [n["id"], RouteGraph.side_of(e), RouteGraph.via_of(e)])
	_check(extras.is_empty(), "mission 1: rifle troopers only, no snipers or searchlights (%s)" % ", ".join(extras))
	side_exits.sort()
	_check(side_exits == PackedStringArray(["boiler_room left ladder", "boiler_room right ladder", "roof_edge left ladder", "roof_edge right ladder",
			"security_wing left stairs", "security_wing right stairs"]),
			"mission 1: its only side exits are the WING's two stairs and the two ladder ends (%s)" % ", ".join(side_exits))
	# The ways to the pad: the roof shortest (the loud way is the quick one), then the basement, then
	# straight on.
	var way := func(ids: Array) -> float:
		var m := 0.0
		for id in ids:
			m += g.length_of(id)
		return m
	var ground: float = way.call([&"main_floor_lobby", &"building_main_floor", &"security_wing", &"staff_canteen", &"main_floor_exit"])
	var below: float = way.call([&"main_floor_lobby", &"building_main_floor", &"security_wing", &"service_tunnel", &"boiler_room"])
	var roof: float = way.call([&"main_floor_lobby", &"building_main_floor", &"security_wing", &"rooftops", &"roof_edge"])
	_check(roof < below and below <= ground and is_equal_approx(ground, 790.0) and is_equal_approx(below, 780.0) and is_equal_approx(roof, 710.0),
			"mission 1: the ways to the pad, roof < basement <= ground (%d, %d, %d m)" % [roof, below, ground])
	# The WING's box comes before its wire: holding FIRE shoots a box in range, and one after the wire
	# would quietly undo it and shut the fire escape again.
	var wing := g.node_data(&"security_wing")
	var wire_at := INF
	for ob in wing.get("obstacles", []):
		if String(ob.get("kind", "")) == "tripwire":
			wire_at = minf(wire_at, float(ob["at"]))
	var boxes_after := 0
	for a in wing.get("alarms", []):
		if float(a.get("at", 0)) > wire_at:
			boxes_after += 1
	_check(wire_at < INF and wing.get("alarms", []).size() == 1 and boxes_after == 0, "mission 1: the WING's alarm box comes before its wire")
	# The far lanes free for the last 20 m before the junction, so both stairs can be reached.
	var in_way := PackedStringArray()
	for ob in wing.get("obstacles", []):
		if float(ob.get("at", 0)) > g.length_of(&"security_wing") - 20.0 and (0 in ob.get("lanes", []) or 4 in ob.get("lanes", [])):
			in_way.append("%s at %s" % [ob["kind"], ob["at"]])
	_check(in_way.is_empty(), "mission 1: the WING's outer lanes are clear for its last 20 m (%s)" % ", ".join(in_way))
	# The map: 10 areas; after a ground run, the only locks are the two ways off the WING.
	var lay := RouteMap.layout(g)
	_check(lay.size() == 10, "mission 1's map: 10 areas (%d)" % lay.size())
	var found := {}
	for id in [&"main_floor_lobby", &"building_main_floor", &"security_wing", &"staff_canteen", &"main_floor_exit", &"helipad"]:
		found[id] = 1.0e6
	var locks := RouteMap.locked_ways(g, RouteMap.seen_full(g, lay, found), found).map(func(w: Array) -> String: return "%s>%s" % w)
	locks.sort()
	_check(locks == ["security_wing>rooftops", "security_wing>service_tunnel"], "mission 1's map: after a ground run, a lock up and a lock down off the WING, nothing else (%s)" % [locks])
	var run: Array[StringName] = [&"main_floor_lobby", &"building_main_floor", &"security_wing", &"rooftops", &"roof_edge", &"helipad"]
	_check(RouteMap.levels_text(g, run) == "MAIN > ROOF > MAIN", "mission 1's map: the fire escape's route reads MAIN > ROOF > MAIN (%s)" % RouteMap.levels_text(g, run))
	# Finds are kept per mission: mission 1's map starts empty, and a save from before missions (the
	# old level's map) is filed under the test range.
	var log: Node = load("res://game/autoload/run_log.gd").new()
	log.load_saved({"main_floor_lobby": 1.0e6, "warehouse": 1.0e6, "gantry": 40.0})
	log.set_mission(&"cold_call")
	_check(log.discovered.is_empty(), "map per mission: mission 1 starts with nothing found, whatever the old save had")
	log.set_mission(&"test_range")
	_check(log.discovered.size() == 3 and is_equal_approx(float(log.discovered[&"gantry"]), 40.0), "map per mission: the old save's finds are the test range's (%s)" % log.discovered)
	log.set_mission(&"cold_call")
	log.begin()
	log.enter_node(&"main_floor_lobby")
	log.enter_node(&"building_main_floor")
	var saved: Dictionary = log.save_data()
	_check(saved["missions"]["cold_call"].size() == 2 and saved["missions"]["test_range"].size() == 3, "map per mission: each mission's finds saved under its own name (%s)" % saved)
	var back: Node = load("res://game/autoload/run_log.gd").new()
	back.load_saved(JSON.parse_string(JSON.stringify(saved)))
	back.set_mission(&"test_range")
	var range_found: int = back.discovered.size()
	back.set_mission(&"cold_call")
	_check(back.discovered.size() == 2 and range_found == 3 and back.discovered.has(&"building_main_floor"), "map per mission: and loaded back the same")
	log.free()
	back.free()


## The cover-exit rule (route validation; the fair-reaction rule's floor, out of cover): stepping
## sideways out of a crate's cover puts you back at full speed in the next lane, so a barrier or pipe
## first in that lane must leave a swipe's reaction (and a jump's lift) before it can trip you. A
## crate beside it, where you'd stop again, is fine; so is the far side of a wall's lanes.
func _test_cover_exit_rule() -> void:
	var t := Tuning.new()
	var need_jump := RouteGraph.cover_exit_gap("barrier", t)
	var need_slide := RouteGraph.cover_exit_gap("pipe", t)
	_check(need_jump > need_slide and absf(need_slide - (RouteGraph.REACTION_HARD + 1.0 / 60.0) * t.run_speed) < 0.01,
			"cover exit: a slide needs the swipe's reaction, a jump that and its lift (%.2f, %.2f m)" % [need_slide, need_jump])
	# Where you stop in cover in front of a crate at 40 m, and where a barrier's stretch starts.
	var stop := 40.0 - RouteGraph.DEPTHS["box"] / 2.0 - t.cover_stop_gap
	var just_fair := stop + need_jump + RouteGraph.DEPTHS["barrier"] / 2.0 + RouteGraph.HIT_REACH + 0.01
	var area := func(obs: Array) -> String:
		var g := RouteGraph.from_dict({"start": "a", "nodes": [{"id": "a", "length": 100, "end": "extract", "obstacles": obs}]})
		return " | ".join(g.validate(t))
	var beside: String = area.call([{"kind": "box", "lanes": [2], "at": 40}, {"kind": "barrier", "lanes": [1], "at": 40}])
	_check(beside.contains("out of the box at 40 m in lane 2 into lane 1, the barrier at 40 m comes too soon"), "cover exit: a barrier right beside a crate is rejected (%s)" % beside)
	_check(area.call([{"kind": "box", "lanes": [2], "at": 40}, {"kind": "barrier", "lanes": [1, 3], "at": just_fair}]) == "", "cover exit: one far enough on is fine")
	_check(area.call([{"kind": "box", "lanes": [2], "at": 40}, {"kind": "barrier", "lanes": [1], "at": just_fair - 0.1}]).contains("comes too soon"), "cover exit: ...and a little less is not")
	_check(area.call([{"kind": "box", "lanes": [2], "at": 40}, {"kind": "box", "lanes": [1], "at": 40.5}, {"kind": "barrier", "lanes": [1], "at": 44}]).contains("into lane 3") == false,
			"cover exit: a crate beside it (you stop again) is fine, and the lane the other way is checked on its own")
	_check(area.call([{"kind": "box", "lanes": [2], "at": 40}, {"kind": "pipe", "lanes": [3], "at": 30}]) == "", "cover exit: something behind you doesn't count")
	_check(area.call([{"kind": "wall", "lanes": [3, 4], "at": 40}, {"kind": "barrier", "lanes": [4], "at": 44}]) == "",
			"cover exit: a wall's own lanes are no way out (you'd stop again), so nothing there counts")
	var off := RouteGraph.from_dict({"start": "a", "cover_exit_rule": false, "nodes": [{"id": "a", "length": 100, "end": "extract",
			"obstacles": [{"kind": "box", "lanes": [2], "at": 40}, {"kind": "barrier", "lanes": [1], "at": 40}]}]})
	_check(not " | ".join(off.validate(t)).contains("comes too soon"), "cover exit: a route can switch it off (the frozen test range)")


## Mission 1's settings (route.json "settings"; user: "an easy medium and hard for each level"): the
## same layout, less time and more pressure going up; each setting passes every route rule at its own
## reaction floor ("on easy levels the gaps between objects will be larger"); objects by setting; and
## the settings' own rules.
func _test_settings() -> void:
	var t := load("res://game/config/default_tuning.tres") as Tuning
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MISSION_1))
	var all := RouteGraph.validate_settings(data, t)
	_check(all.is_empty(), "settings: mission 1 passes every route rule on every setting, each at its own floor (%s)" % " | ".join(all))
	_check(RouteGraph.reaction_for("hard") == RouteGraph.REACTION_HARD and RouteGraph.reaction_for("medium") == RouteGraph.REACTION_MEDIUM
			and RouteGraph.reaction_for("easy") == RouteGraph.REACTION_EASY and RouteGraph.reaction_for("") == RouteGraph.REACTION_HARD,
			"settings: each is held to its own reaction floor (a route without settings to HARD's)")
	# The numbers (user): EASY lifts about 108 (about 27 s to spare on a clean ground run), MEDIUM's
	# are today's, HARD's about 86; the boss about 20, 30 and 40 hits.
	var want := {"easy": [28, 108, 118, 20], "medium": [28, 96, 106, 30], "hard": [28, 86, 96, 40]}
	var g := {}
	for s in RouteGraph.SETTINGS:
		g[s] = RouteGraph.from_dict(data, s)
		var ch: Dictionary = g[s].mission()["chopper"]
		var boss: Dictionary = g[s].mission()["boss"]
		_check(g[s].setting == s and [int(ch["lands_at"]), int(ch["lifts_at"]), int(ch["gone_at"]), int(boss["health"])] == want[s],
				"settings: %s's chopper and boss (%s, %s)" % [s, ch, boss])
	var spin := func(s: String) -> Array: return g[s].mission()["boss"]["spinup"]
	var slower := true
	for i in 3:
		slower = slower and float(spin.call("easy")[i]) > float(spin.call("medium")[i]) and float(spin.call("hard")[i]) <= float(spin.call("medium")[i])
	_check(slower, "settings: EASY's boss spins up slower than MEDIUM's, HARD's no slower")
	_check(RouteGraph.from_dict(data).setting == RouteGraph.DEFAULT_SETTING and RouteGraph.from_json_file(TEST_RANGE).setting == "",
			"settings: a route with settings is read as MEDIUM unless one is asked; the test range has none")
	# EASY is today's layout (user: "So this would be mission 1 easy") and MEDIUM the same; HARD adds a
	# wire before the junction and guards at CAUTION and ALERT on the way straight on.
	var count := func(gr: RouteGraph, what: String, kind: String, min_alert: int) -> int:
		var n := 0
		for id in gr._nodes:
			for x in gr.node_data(id).get(what, []):
				if String(x.get("kind", "")) == kind and int(x.get("min_alert", 1)) >= min_alert:
					n += 1
		return n
	var same := true
	for id in g["easy"]._nodes:
		same = same and JSON.stringify(g["easy"].node_data(id)) == JSON.stringify(g["medium"].node_data(id))
	_check(same, "settings: EASY and MEDIUM have the same layout, guards and wires")
	var wires := [count.call(g["medium"], "obstacles", "tripwire", 1), count.call(g["hard"], "obstacles", "tripwire", 1)]
	var guards := [count.call(g["medium"], "enemies", "rifle_trooper", 1), count.call(g["hard"], "enemies", "rifle_trooper", 1)]
	var loud := [count.call(g["medium"], "enemies", "rifle_trooper", 2), count.call(g["hard"], "enemies", "rifle_trooper", 2)]
	_check(wires[1] == wires[0] + 1 and guards[1] - guards[0] == 4 and loud[1] - loud[0] == 4,
			"settings: HARD has one more wire and four more guards, all at CAUTION or ALERT (wires %s, guards %s, at CAUTION+ %s)" % [wires, guards, loud])
	var extra_where := {}
	for id in g["hard"]._nodes:
		if JSON.stringify(g["hard"].node_data(id)) != JSON.stringify(g["medium"].node_data(id)):
			extra_where[String(id)] = true
	_check(extra_where.size() == 3 and extra_where.has("building_main_floor") and extra_where.has("staff_canteen") and extra_where.has("main_floor_exit"),
			"settings: HARD's extras are on the MAIN FLOOR (its wire) and on the way straight on (%s), not the roof or the first area" % [extra_where.keys()])
	_check(JSON.stringify(g["easy"].node_data(g["easy"].start_id)) == JSON.stringify(g["hard"].node_data(g["hard"].start_id)),
			"settings: the first area is the same on every setting (it's built under the menu)")
	# Every setting starts at SNEAKING (the level starts every run at its START_ALERT).
	_check(load("res://game/levels/prototype_slice/prototype_slice.gd").START_ALERT == 1, "settings: every setting starts at SNEAKING")
	# Which settings a thing is in.
	_check(RouteGraph.in_setting({}, "easy") and RouteGraph.in_setting({}, "hard")
			and not RouteGraph.in_setting({"min_setting": "hard"}, "medium") and RouteGraph.in_setting({"min_setting": "medium"}, "hard")
			and not RouteGraph.in_setting({"max_setting": "easy"}, "medium") and RouteGraph.in_setting({"max_setting": "medium"}, "easy")
			and RouteGraph.in_setting({"settings": ["easy", "hard"]}, "hard") and not RouteGraph.in_setting({"settings": ["easy", "hard"]}, "medium"),
			"settings: min_setting, max_setting and settings pick what's there on each")
	# The settings' own rules.
	var broken := func(edit: Callable) -> String:
		var d: Dictionary = data.duplicate(true)
		edit.call(d)
		return " | ".join(RouteGraph.validate_settings(d, t))
	_check(broken.call(func(d: Dictionary) -> void: d["settings"].erase("hard")).contains("the hard setting is missing"), "settings: all three must be there")
	_check(broken.call(func(d: Dictionary) -> void: d["settings"]["extreme"] = d["settings"]["hard"]).contains("unknown setting 'extreme'"), "settings: only easy, medium and hard")
	_check(broken.call(func(d: Dictionary) -> void: d["settings"]["hard"]["chopper"]["lifts_at"] = 100).contains("hard: the chopper waits longer than on medium"),
			"settings: a harder setting never gives more time")
	_check(broken.call(func(d: Dictionary) -> void: d["settings"]["medium"]["boss"]["health"] = 10).contains("medium: the boss takes fewer hits than on easy"),
			"settings: a harder setting's boss never takes fewer hits")
	_check(broken.call(func(d: Dictionary) -> void: d["settings"]["hard"]["boss"]["spinup"] = [2.0, 0.8, 0.7]).contains("hard: the boss spins up slower than on medium"),
			"settings: a harder setting's boss never spins up slower")
	_check(broken.call(func(d: Dictionary) -> void: d["settings"]["easy"]["chopper"]["gone_at"] = 50).contains("easy: its chopper times must be"),
			"settings: each one's chopper times in order")
	_check(broken.call(func(d: Dictionary) -> void: d["settings"]["easy"]["boss"].erase("spinup")).contains("easy: the boss needs"), "settings: each has its boss")
	_check(broken.call(func(d: Dictionary) -> void: d["settings"]["hard"]["start_alert"] = 2).contains("every setting starts at SNEAKING"), "settings: none starts above SNEAKING")
	_check(broken.call(func(d: Dictionary) -> void: d["nodes"][1]["enemies"][0]["min_setting"] = "nightmare").contains("unknown setting 'nightmare'"),
			"settings: an object's setting must be a real one")
	_check(broken.call(func(d: Dictionary) -> void: d["nodes"][0]["obstacles"][0]["min_setting"] = "hard").contains("the first area is built under the main menu"),
			"settings: nothing in the first area by setting")
	# Each setting at its own floor: a gap HARD allows and EASY doesn't.
	var tight: Dictionary = data.duplicate(true)
	for n in tight["nodes"]:
		if n["id"] == "building_main_floor":
			for ob in n["obstacles"]:
				if String(ob["kind"]) == "tripwire" and not ob.has("min_setting"):
					ob["at"] = 53  # (where it was: 7 m after the pipe)
	var floors := " | ".join(RouteGraph.validate_settings(tight, t))
	_check(floors.contains("[EASY]") and floors.contains("[MEDIUM]") and not floors.contains("[HARD]"),
			"settings: each setting is held to its own floor (a 7 m pipe-to-wire gap is fine on HARD, not on EASY or MEDIUM)")
	# The boss takes the setting's hits and spin-ups.
	var boss := Boss.new(t)
	boss.configure(g["easy"].mission()["boss"])
	_check(boss.health == 20 and boss.max_health == 20 and is_equal_approx(float(boss._spinup[0]), 1.4), "settings: the boss takes the setting's hits and spin-ups")
	boss.configure({})
	_check(boss.health == 20, "settings: a setting without a boss leaves him as he is")
	boss.free()


## The unlock rule (user): getting out of mission N on a setting opens mission N+1 on that setting and
## every easier one, and mission N's next setting up. Every mission, every setting.
func _test_unlock_rule() -> void:
	var P: GDScript = load("res://game/autoload/progress.gd")
	var s: Array = RouteGraph.SETTINGS
	var every := true
	var told := PackedStringArray()
	for n in range(1, 10):
		for r in 3:
			var want := []
			if r < 2:
				want.append([n, s[r + 1]])
			if n < 9:
				for e in r + 1:
					want.append([n + 1, s[e]])
			var got: Array = P.unlocks_after(n, s[r])
			if got != want:
				every = false
				told.append("%d %s: %s" % [n, s[r], got])
	_check(every, "unlocks: every mission and setting opens what the rule says (%s)" % ", ".join(told))
	# The user's own cases.
	_check(P.unlocks_after(1, "easy") == [[1, "medium"], [2, "easy"]], "unlocks: mission 1 EASY opens its MEDIUM and mission 2 EASY only")
	_check(P.unlocks_after(1, "medium") == [[1, "hard"], [2, "easy"], [2, "medium"]], "unlocks: MEDIUM opens mission 2 EASY and MEDIUM (and its own HARD)")
	_check(P.unlocks_after(1, "hard") == [[2, "easy"], [2, "medium"], [2, "hard"]], "unlocks: HARD opens all of mission 2")
	_check(P.unlocks_after(9, "hard") == [] and P.unlocks_after(9, "easy") == [[9, "medium"]], "unlocks: the last mission only opens its own next setting")
	_check(P.unlocks_after(0, "easy") == [] and P.unlocks_after(10, "easy") == [] and P.unlocks_after(1, "extreme") == [], "unlocks: nothing for what isn't a mission or setting")
	var p: Node = P.new()
	p.load_from("")
	var fresh := 0
	for n in range(1, 10):
		for x in s:
			if p.is_unlocked(n, x):
				fresh += 1
	_check(fresh == 1 and p.is_unlocked(1, "easy") and p.is_playable(1, "easy") and not p.is_playable(1, "medium"),
			"unlocks: at the very start only mission 1 EASY is open")
	_check(p.record_extraction(1, "easy") == [[1, "medium"], [2, "easy"]] and p.is_unlocked(1, "medium") and p.is_cleared(1, "easy") and not p.is_cleared(1, "medium"),
			"unlocks: getting out of mission 1 EASY opens what it should, and it's cleared")
	_check(p.record_extraction(1, "easy") == [], "unlocks: getting out again opens nothing new")
	_check(p.record_extraction(1, "hard") == [[2, "medium"], [2, "hard"]], "unlocks: only what's newly open is told")
	_check(p.is_unlocked(2, "easy") and not p.is_playable(2, "easy") and not P.is_built(2) and P.is_built(1),
			"unlocks: mission 2 is open but not playable until it's built (COMING SOON)")
	_check(p.record_extraction(0, "easy") == [] and p.record_extraction(1, "nope") == [], "unlocks: the test range (no mission) opens nothing")
	_check(P.mission_number(&"cold_call") == 1 and P.mission_number(&"test_range") == 0 and P.MISSIONS.size() == 9
			and P.MISSIONS.map(func(m: Dictionary) -> String: return m["name"]) == ["COLD CALL", "SHORT LEASH", "DEAD AIR", "NOTHING TO DECLARE", "SEA LEGS",
			"FIRE SALE", "GLASS HOUSE", "LIGHTS OUT", "HOT EXFIL"], "unlocks: the nine missions, by the story's names")
	p.free()


## The progress save (user://, beside the settings): kept and read back; a missing or broken file, or
## one with nonsense in it, gives a fresh start (mission 1 EASY), never a crash.
func _test_progress_save() -> void:
	var P: GDScript = load("res://game/autoload/progress.gd")
	var path := "user://test_progress_%d.json" % randi()
	var a: Node = P.new()
	a.load_from(path)  # (missing: fresh)
	_check(a.is_unlocked(1, "easy") and not a.is_unlocked(1, "medium") and not FileAccess.file_exists(path), "progress: no file is a fresh start")
	a.record_extraction(1, "medium")
	a.remember_pick(1, "hard")
	var b: Node = P.new()
	b.load_from(path)
	_check(FileAccess.file_exists(path) and b.to_data() == a.to_data() and b.is_unlocked(2, "medium") and b.is_cleared(1, "medium") and b.last == "1:hard",
			"progress: saved at once and read back the same (%s)" % b.to_data())
	for junk in ["{not json", "[1, 2, 3]", "", "{\"unlocked\": \"1:hard\"}"]:
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(junk)
		f.close()
		var c: Node = P.new()
		c.load_from(path)
		_check(c.is_unlocked(1, "easy") and not c.is_unlocked(1, "hard") and c.last == "1:easy", "progress: a broken save (%s) is a fresh start" % junk)
		c.free()
	var d: Node = P.new()
	d.from_data({"unlocked": ["1:easy", "1:medium", "10:easy", "2:extreme", 5, "x", "3:hard"], "cleared": ["4:easy"], "last": "5:easy"})
	_check(d.is_unlocked(1, "medium") and d.is_unlocked(3, "hard") and not d.is_unlocked(10, "easy") and d.is_unlocked(4, "easy") and d.is_cleared(4, "easy")
			and d.to_data()["unlocked"].size() == 4 and d.last == "1:easy",
			"progress: only real missions and settings are kept, a cleared one is open, and the last pick only if it's open (%s)" % d.to_data())
	var e: Node = P.new()
	e.from_data({"unlocked": []})
	_check(e.is_unlocked(1, "easy"), "progress: mission 1 EASY is always open")
	var mem: Node = P.new()
	mem.load_from("")
	mem.record_extraction(1, "easy")
	_check(mem.save_path == "", "progress: kept in memory only when it's told to (the bots)")
	for n in [a, b, d, e, mem]:
		n.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Best times (user: each setting shows "the players best time if it's been set"): the run time of
## his fastest extraction, per mission and setting. Only an extraction counts (killed, captured and
## the chopper leaving never set one), only a faster time replaces it, and each setting keeps its
## own. And a save from before best times (version 1) still loads, with none.
func _test_best_times() -> void:
	var P: GDScript = load("res://game/autoload/progress.gd")
	var p: Node = P.new()
	p.load_from("")
	_check(p.best_time(1, "easy") < 0.0 and p.best_time(1, "hard") < 0.0, "best times: a fresh save has none")
	for why in [&"killed", &"captured", &"chopper_left", &"dead_end"]:
		var r: Dictionary = p.record_run(1, "easy", why, 50.0)
		_check(not r["new_best"] and p.best_time(1, "easy") < 0.0 and not p.is_cleared(1, "easy") and r["unlocked"].is_empty(),
				"best times: %s sets no best time and clears nothing (%s)" % [why, r])
	var first: Dictionary = p.record_run(1, "easy", &"extracted", 90.0)
	_check(first["new_best"] and is_equal_approx(first["best"], 90.0) and first["was"] < 0.0 and is_equal_approx(p.best_time(1, "easy"), 90.0)
			and first["unlocked"] == [[1, "medium"], [2, "easy"]] and p.is_cleared(1, "easy"),
			"best times: the first extraction is the best, and it unlocks as before (%s)" % first)
	var slower: Dictionary = p.record_run(1, "easy", &"extracted", 95.5)
	_check(not slower["new_best"] and is_equal_approx(p.best_time(1, "easy"), 90.0) and is_equal_approx(slower["was"], 90.0),
			"best times: a slower extraction doesn't replace it")
	var same: Dictionary = p.record_run(1, "easy", &"extracted", 90.0)
	_check(not same["new_best"], "best times: the same time isn't a new best")
	var faster: Dictionary = p.record_run(1, "easy", &"extracted", 81.4)
	_check(faster["new_best"] and is_equal_approx(faster["was"], 90.0) and is_equal_approx(p.best_time(1, "easy"), 81.4),
			"best times: a faster extraction replaces it (%s)" % faster)
	p.record_run(1, "easy", &"killed", 10.0)
	_check(is_equal_approx(p.best_time(1, "easy"), 81.4), "best times: a quick death after doesn't touch it")
	var med: Dictionary = p.record_run(1, "medium", &"extracted", 99.0)
	_check(med["new_best"] and is_equal_approx(p.best_time(1, "medium"), 99.0) and is_equal_approx(p.best_time(1, "easy"), 81.4) and p.best_time(1, "hard") < 0.0,
			"best times: each setting keeps its own")
	_check(not p.record_run(1, "easy", &"extracted", 0.0)["new_best"] and not p.record_run(1, "easy", &"extracted", -3.0)["new_best"]
			and not p.record_run(1, "easy", &"extracted", INF)["new_best"] and is_equal_approx(p.best_time(1, "easy"), 81.4),
			"best times: a time that isn't one is never a best")
	_check(not p.record_run(0, "easy", &"extracted", 30.0)["new_best"] and not p.record_run(1, "extreme", &"extracted", 30.0)["new_best"],
			"best times: the test range (no mission) and a setting that isn't one keep none")
	# Kept in the save, and read back the same.
	var data: Dictionary = p.to_data()
	_check(data["version"] == 2 and data["best"] is Dictionary and is_equal_approx(float(data["best"]["1:easy"]), 81.4) and data["best"].size() == 2,
			"best times: in the save, by mission and setting (%s)" % [data["best"]])
	var q: Node = P.new()
	q.from_data(JSON.parse_string(JSON.stringify(data)))
	_check(is_equal_approx(q.best_time(1, "easy"), 81.4) and is_equal_approx(q.best_time(1, "medium"), 99.0) and q.to_data() == p.to_data(),
			"best times: read back from the save the same")
	# A save from before best times (version 1: no "best"): its unlocks and cleared marks as they were, no best times.
	var old: Node = P.new()
	old.from_data(JSON.parse_string('{"version": 1, "unlocked": ["1:easy", "1:medium", "2:easy"], "cleared": ["1:easy"], "last": "1:medium"}'))
	_check(old.is_unlocked(1, "medium") and old.is_unlocked(2, "easy") and old.is_cleared(1, "easy") and old.last == "1:medium"
			and old.best_time(1, "easy") < 0.0 and old.to_data()["best"].is_empty(),
			"best times: an old save (version 1) loads as it was, with no best times")
	var first_old: Dictionary = old.record_run(1, "easy", &"extracted", 88.0)
	_check(first_old["new_best"] and first_old["was"] < 0.0, "best times: ...and its next extraction is its first best")
	# Nonsense in the best times is left out; a best time means it was got out of (cleared, open).
	var junk: Node = P.new()
	junk.from_data({"unlocked": [], "best": {"1:hard": 70.5, "1:easy": "fast", "2:medium": -1, "10:easy": 50, "x": 3, "1:medium": 0}})
	_check(junk.to_data()["best"].keys() == ["1:hard"] and junk.is_cleared(1, "hard") and junk.is_unlocked(1, "hard"),
			"best times: only real times for real missions and settings are kept (%s)" % [junk.to_data()["best"]])
	junk.from_data({"best": [1, 2]})
	_check(junk.to_data()["best"].is_empty() and junk.is_unlocked(1, "easy"), "best times: a best list that isn't one is none")
	for n in [p, q, old, junk]:
		n.free()


## The auto-save (user: "I'd like the game to auto save itself after the player finishes a run"):
## record_run (called as every run ends) writes the save to the device whatever the ending:
## extracted, killed, captured, the chopper gone (and the test range's, no mission, too). What's
## written is what's kept. Kept in memory only (the bots), nothing is written.
func _test_auto_save() -> void:
	var P: GDScript = load("res://game/autoload/progress.gd")
	var path := "user://test_autosave_%d.json" % randi()
	var p: Node = P.new()
	p.load_from(path)
	for case in [[1, &"killed"], [1, &"captured"], [1, &"chopper_left"], [1, &"extracted"], [0, &"extracted"], [1, &"dead_end"]]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		var r: Dictionary = p.record_run(case[0], "easy", case[1], 77.7)
		var back: Node = P.new()
		back.load_from(path)
		_check(r["saved"] and FileAccess.file_exists(path) and not FileAccess.file_exists(path + SaveFile.TMP) and back.to_data() == p.to_data(),
				"auto-save: written as the run ends (mission %d, %s), and read back the same" % case)
		back.free()
	var back2: Node = P.new()
	back2.load_from(path)
	_check(is_equal_approx(back2.best_time(1, "easy"), 77.7) and back2.is_cleared(1, "easy") and back2.is_unlocked(2, "easy"),
			"auto-save: the best time, the cleared mark and the unlocks are on the device")
	back2.free()
	var mem: Node = P.new()
	mem.load_from("")
	_check(not mem.record_run(1, "easy", &"extracted", 60.0)["saved"], "auto-save: kept in memory only (the bots), nothing written")
	# A write that fails (somewhere it can't write) is a warning, the game goes on.
	var bad: Node = P.new()
	bad.load_from("user://no_such_folder_%d/progress.json" % randi())
	var r2: Dictionary = bad.record_run(1, "easy", &"extracted", 60.0)
	_check(not r2["saved"] and r2["new_best"] and bad.is_cleared(1, "easy"), "auto-save: a failed write doesn't break anything (it's still recorded for the session)")
	# The route map's finds are written as the run ends too (RunLog.finish), safely.
	var RL: GDScript = load("res://game/autoload/run_log.gd")
	var rl1: Node = RL.new()
	var dpath := "user://test_discovery_%d.json" % randi()
	rl1.load_from(dpath)
	rl1.set_mission(&"cold_call")
	rl1.begin()
	rl1.enter_node(&"main_floor_lobby")
	rl1.finish(&"killed", &"main_floor_lobby", 12.0)
	var log2: Node = RL.new()
	log2.load_from(dpath)
	log2.set_mission(&"cold_call")
	_check(FileAccess.file_exists(dpath) and is_equal_approx(float(log2.discovered.get(&"main_floor_lobby", -1.0)), 12.0),
			"auto-save: the route map's finds are written as the run ends, and read back (%s)" % [log2.discovered])
	var log3: Node = RL.new()
	log3.load_from("")
	log3.set_mission(&"cold_call")
	log3.begin()
	log3.enter_node(&"main_floor_lobby")
	log3.finish(&"killed", &"main_floor_lobby", 5.0)
	_check(log3.save_path == "" and log3.discovered.has(&"main_floor_lobby"), "auto-save: the route map kept in memory only when it's told to (the bots)")
	for n in [p, mem, bad, rl1, log2, log3]:
		n.free()
	for f in [path, dpath]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f + SaveFile.TMP))


## SaveFile, how every save is written: a temp file, then a rename over the save, so it's never left
## half-written; a save over an old one replaces it; a save whose rename never happened (the game
## stopped between the two) is still found, in its .tmp; somewhere it can't write is false, not a
## crash.
func _test_save_file() -> void:
	var path := "user://test_savefile_%d.txt" % randi()
	_check(SaveFile.read_text(path) == "" and not SaveFile.exists(path), "save file: none there reads as nothing")
	_check(SaveFile.write_text(path, "one") and FileAccess.get_file_as_string(path) == "one" and not FileAccess.file_exists(path + SaveFile.TMP),
			"save file: written, with no temp file left")
	_check(SaveFile.write_text(path, "two") and SaveFile.read_text(path) == "two" and not FileAccess.file_exists(path + SaveFile.TMP),
			"save file: a new save replaces the old one")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var f := FileAccess.open(path + SaveFile.TMP, FileAccess.WRITE)
	f.store_string("three")
	f.close()
	_check(SaveFile.exists(path) and SaveFile.read_text(path) == "three", "save file: stopped before its rename, the new save is read from its .tmp")
	_check(SaveFile.write_text(path, "four") and SaveFile.read_text(path) == "four" and not FileAccess.file_exists(path + SaveFile.TMP),
			"save file: ...and the next save tidies it up")
	_check(not SaveFile.write_text("user://no_such_folder_%d/x.txt" % randi(), "x") and not SaveFile.write_text("", "x"),
			"save file: somewhere it can't write is false, not a crash")
	# The settings are written the same way, and read back.
	var cfg := ConfigFile.new()
	cfg.set_value("settings", "aim", "tap")
	SaveFile.write_text(path, cfg.encode_to_text())
	var back := ConfigFile.new()
	_check(back.parse(SaveFile.read_text(path)) == OK and back.get_value("settings", "aim", "") == "tap", "save file: the settings' format writes and reads back")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## The mission select, then each mission's screen (user: "The menu is too cramped. There would be
## another screen after the mission select that shows the 3 difficulty options with the players best
## time if it's been set. They click the difficulty they want to play and the game starts."). START
## MISSION opens the select: all nine missions listed (no settings on it now), the ones not built
## COMING SOON and not pickable, each with a mark per setting (cleared, open or locked). A tap on
## mission 1 opens its screen: EASY / MEDIUM / HARD, a locked one greyed with its padlock and not
## pickable (by a tap or otherwise), each with his best time ("--" if none); a tap on an open one
## starts that mission on that setting; BACK goes back to the select, and its BACK to the main menu.
## Laid out to fit a 480-high screen and a tall phone's 585, nothing overlapping. And the debrief
## says what an extraction opened, and NEW BEST.
func _test_mission_select() -> void:
	var prog: Node = root.get_node("Progress")  # (the autoload the menu reads)
	var saved: Dictionary = prog.to_data()
	var saved_path: String = prog.save_path
	prog.load_from("")  # (a fresh save, in memory: the player's own is left alone)
	# (Frontend by its file, at run time: it reads the Progress autoload, which this script can't name)
	var FE: GDScript = load("res://game/ui/menu/frontend.gd")
	var fe = FE.new()
	root.add_child(fe)
	var picks := []
	fe.start_requested.connect(func(n: int, s: String) -> void: picks.append([n, s]))
	fe.show_main()
	await process_frame
	var start := _menu_button(fe, "START MISSION")
	_check(start != null, "mission select: the main menu still has START MISSION")
	start.pressed.emit()
	await process_frame
	_check(fe.in_missions() and picks.is_empty(), "mission select: START MISSION opens it (and starts nothing yet)")
	var rows: Array = fe.find_children("*", "", true, false).filter(func(n: Node) -> bool: return n.get_script() == FE.MissionRow and not n.is_queued_for_deletion())
	var names := rows.map(func(r: Node) -> String: return r.title)
	_check(rows.size() == 9 and names[0] == "COLD CALL" and names[8] == "HOT EXFIL", "mission select: all nine missions listed (%s)" % [names])
	_check(rows.all(func(r: Node) -> bool: return r.built == (r.number == 1)), "mission select: only mission 1 is built; 2 to 9 are COMING SOON")
	_check(fe.chip(1, "easy") == null, "mission select: no settings on it now (they're on the mission's screen)")
	var row1 = fe.mission_row(1)
	_check(row1.playable() and not row1.disabled and row1.unlocked == [true, false, false] and row1.cleared == [false, false, false],
			"mission select: mission 1 can be picked; its marks: EASY open, MEDIUM and HARD locked, none cleared")
	_check(range(2, 10).all(func(n: int) -> bool: return fe.mission_row(n).disabled and fe.mission_row(n).focus_mode == Control.FOCUS_NONE),
			"mission select: 2 to 9 greyed and not pickable")
	_check(row1.has_focus(), "mission select: it opens with mission 1 picked out (focus)")
	# A mission not built can't be opened: not by a tap, not by open_mission().
	_tap_at(fe.mission_row(2).get_global_rect().get_center())
	_check(not fe.open_mission(2) and fe.in_missions(), "mission select: a mission not built yet can't be opened")
	_check(not fe.choose(1, "easy") and picks.is_empty(), "mission select: nothing starts from the select itself")
	# A tap on mission 1 opens its screen.
	_tap_at(row1.get_global_rect().get_center())
	await process_frame
	_check(fe.in_mission() and fe.mission_shown() == 1 and picks.is_empty(), "mission screen: a tap on mission 1 opens its screen (nothing started yet)")
	_check(_has_label(fe, "COLD CALL") and RouteGraph.SETTINGS.all(func(s: String) -> bool: return fe.chip(1, s) != null),
			"mission screen: its name, and EASY / MEDIUM / HARD")
	var open := []
	var locked_ok := true
	for s in RouteGraph.SETTINGS:
		var c = fe.chip(1, s)
		if c.playable():
			open.append(s)
		elif not c.disabled or c.focus_mode != Control.FOCUS_NONE or c.open:
			locked_ok = false
	_check(open == ["easy"] and locked_ok and fe.chip(1, "medium").needs == "EASY" and fe.chip(1, "hard").needs == "MEDIUM",
			"mission screen: a fresh save has only EASY pickable; MEDIUM and HARD locked (padlocked), saying what opens them (%s)" % [open])
	_check(RouteGraph.SETTINGS.all(func(s: String) -> bool: return fe.chip(1, s).best < 0.0), "mission screen: no best times on a fresh save")
	# A locked one can't be picked: not by a tap where it is, not by its press, not by choose().
	var locked = fe.chip(1, "medium")
	_tap_at(locked.get_global_rect().get_center())
	locked.pressed.emit()
	_check(not fe.choose(1, "medium") and picks.is_empty() and fe.in_mission(), "mission screen: a locked setting can't be picked")
	var easy = fe.chip(1, "easy")
	_check(easy.has_focus(), "mission screen: it opens with the open one picked out (focus)")
	# BACK: the select (mission 1 still picked out), then the main menu.
	_menu_button(fe, "BACK").pressed.emit()
	await process_frame
	_check(fe.in_missions() and fe.mission_row(1) != null and fe.mission_row(1).has_focus(), "mission screen: BACK returns to the mission select")
	_menu_button(fe, "BACK").pressed.emit()
	await process_frame
	_check(_menu_button(fe, "START MISSION") != null and not fe.in_missions(), "mission select: BACK returns to the main menu")
	# Through again: START MISSION, mission 1, EASY: a tap starts it on EASY.
	_menu_button(fe, "START MISSION").pressed.emit()
	await process_frame
	_tap_at(fe.mission_row(1).get_global_rect().get_center())
	await process_frame
	_tap_at(fe.chip(1, "easy").get_global_rect().get_center())
	_check(picks == [[1, "easy"]], "mission screen: a tap on EASY starts mission 1 on EASY (%s)" % [picks])
	# With best times: got out of EASY (81.4 s) and MEDIUM was a death. The marks, the best times.
	prog.load_from("")
	prog.record_run(1, "easy", &"extracted", 81.4)
	prog.record_run(1, "medium", &"killed", 40.0)
	fe.show_main()
	await process_frame
	_menu_button(fe, "START MISSION").pressed.emit()
	await process_frame
	_check(fe.mission_row(1).cleared == [true, false, false] and fe.mission_row(1).unlocked == [true, true, false],
			"mission select: after EASY, mission 1's marks show EASY cleared and MEDIUM open")
	var rb: Array = fe.mission_row(1).best
	_check(rb.size() == 3 and is_equal_approx(rb[0], 81.4) and rb[1] < 0.0 and rb[2] < 0.0, "mission select: mission 1's row has his best times (EASY 81.4 s, none on MEDIUM or HARD)")
	_check(FE.MissionRow.best_text(81.4) == "1:21" and FE.MissionRow.best_text(59.97) == "0:59" and FE.MissionRow.best_text(-1.0) == "--",
			"mission select: a row's best time reads to the second, never better than he did (1:21; -- for none)")
	# The row's line of times ("E 1:21  M 1:21  H 1:21", all three set: its widest likely) clears the marks.
	var rf := UiKit.font()
	var times_end := 40.0 + 3.0 * (12.0 + rf.get_string_size("9:59", HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x) + 2.0 * 10.0
	_check(times_end + 6.0 <= 242.0 - 10.0 - 3.0 * FE.MissionRow.MARK.x - 2.0 * FE.MissionRow.MARK_GAP,
			"mission select: a row's three best times clear its marks (%d px)" % times_end)
	_check(fe.open_mission(1) and fe.in_mission(), "mission select: open_mission(1) opens its screen")
	await process_frame
	var e = fe.chip(1, "easy")
	var m = fe.chip(1, "medium")
	_check(is_equal_approx(e.best, 81.4) and e.cleared and m.best < 0.0 and m.playable() and not m.cleared and not fe.chip(1, "hard").playable(),
			"mission screen: EASY shows his best (81.4 s), MEDIUM open with none (the death set none), HARD locked")
	_check(FE.time_text(81.4) == "1:21.4" and FE.time_text(59.97) == "1:00.0" and FE.time_text(5.0) == "0:05.0", "mission screen: a best time reads as the tally's TIME (1:21.4)")
	picks.clear()
	_tap_at(m.get_global_rect().get_center())
	_check(picks == [[1, "medium"]], "mission screen: ...and a tap on MEDIUM starts it")
	# It fits: the select's nine rows and BACK, and the mission's three buttons, its line and BACK,
	# on a 480-high screen and a tall phone's 585.
	for h in [480.0, 585.0]:
		var step: float = FE.mission_step(h)
		var back_bottom: float = FE.MISSION_TOP + 9.0 * step + 6.0 + 20.0
		_check(back_bottom <= h - 8.0 and step >= FE.MISSION_ROW_MIN, "mission select: fits a %d-high screen (BACK's bottom at %d)" % [h, back_bottom])
		var end: float = FE.setting_top(h) + 3.0 * FE.SETTING_H + 2.0 * FE.SETTING_GAP
		_check(FE.setting_top(h) >= 84.0 and end + 36.0 + 20.0 <= h - 8.0, "mission screen: fits a %d-high screen (BACK's bottom at %d)" % [h, end + 56.0])
	# Nothing overlaps (the 8 px font is 6 px a letter, the 16 px 12): on a mission row, the longest
	# name clears COMING SOON and the marks; on a setting button, the longest status clears the
	# padlock, and the name and NOT CLEARED YET clear the longest time.
	var f := UiKit.font()
	var row_w := 270.0 - 28.0
	var longest := 0.0
	for mi in Progress.MISSIONS:
		longest = maxf(longest, f.get_string_size(String(mi["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x)
	var marks_x: float = row_w - 10.0 - 3.0 * FE.MissionRow.MARK.x - 2.0 * FE.MissionRow.MARK_GAP
	var soon_x: float = row_w - 10.0 - f.get_string_size("COMING SOON", HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
	_check(40.0 + longest + 6.0 <= minf(marks_x, soon_x), "mission select: the longest name (%d px) clears the marks and COMING SOON" % longest)
	var right: float = row_w - FE.SettingChip.SLANT - 12.0
	var status_end: float = FE.SettingChip.SLANT + 8.0 + f.get_string_size("CLEAR MEDIUM TO UNLOCK", HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
	var time_x: float = right - f.get_string_size("99:59.9", HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	var name_end: float = FE.SettingChip.SLANT + 12.0 + f.get_string_size("MEDIUM", HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	var nc_end: float = FE.SettingChip.SLANT + 8.0 + f.get_string_size("NOT CLEARED YET", HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
	_check(status_end + 6.0 <= right - 15.0 and name_end + 6.0 <= time_x and nc_end + 6.0 <= time_x,
			"mission screen: the setting's name and status clear its best time and padlock")
	# The debrief says what opened.
	_check(FE.unlock_lines([[1, "medium"], [2, "easy"]], 1) == PackedStringArray(["MEDIUM UNLOCKED", "MISSION 2: EASY UNLOCKED"])
			and FE.unlock_lines([[2, "easy"], [2, "medium"], [2, "hard"]], 1) == PackedStringArray(["MISSION 2: EASY + MEDIUM + HARD UNLOCKED"])
			and FE.unlock_lines([], 1).is_empty(), "debrief: what an extraction opened, in words")
	_check(FE.best_line(true, -1.0) == "NEW BEST TIME" and FE.best_line(true, 90.0) == "NEW BEST TIME - WAS 1:30.0" and FE.best_line(false, 90.0) == "",
			"debrief: a new best time, in words")
	fe.show_end(&"extracted", {"time": 70.0, "mission": 1, "setting": "easy", "unlocked": [[1, "medium"], [2, "easy"]], "new_best": true, "was_best": 90.0})
	await process_frame
	var said := _debrief_lines(fe)
	var fits := true
	for l in said:
		fits = fits and f.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x <= 242.0
	_check(said == PackedStringArray(["NEW BEST TIME - WAS 1:30.0", "MEDIUM UNLOCKED", "MISSION 2: EASY UNLOCKED"]) and fits,
			"debrief: after a faster extraction it says NEW BEST, then what unlocked (%s)" % said)
	fe.show_end(&"extracted", {"time": 95.0, "mission": 1, "setting": "easy", "unlocked": [], "new_best": false, "was_best": 90.0})
	await process_frame
	_check(_debrief_lines(fe).is_empty(), "debrief: a slower one says nothing of a best (%s)" % _debrief_lines(fe))
	fe.show_end(&"killed", {"time": 30.0, "mission": 1, "setting": "easy", "unlocked": [], "new_best": false, "was_best": -1.0})
	await process_frame
	_check(_debrief_lines(fe).is_empty(), "debrief: killed, nothing of a best or unlocks")
	fe.free()
	prog.from_data(saved)
	prog.save_path = saved_path


## The debrief's lines under its buttons (a new best, the unlocks), typed out in full.
func _debrief_lines(fe: Node) -> PackedStringArray:
	for ty in fe.find_children("*", "", true, false):
		if ty is Typer:
			ty.finish()
	var said := PackedStringArray()
	for l in fe.find_children("*", "Label", true, false):
		var t := (l as Label).text
		if (t.contains("UNLOCKED") or t.contains("NEW BEST")) and not l.is_queued_for_deletion():
			said.append(t)
	return said


## Whether a label with exactly this text is up on the menu.
func _has_label(fe: Node, text: String) -> bool:
	for l in fe.find_children("*", "Label", true, false):
		if (l as Label).text == text and not l.is_queued_for_deletion():
			return true
	return false


## The menu's button with this text, on the screen up now (null if none).
func _menu_button(fe: Node, text: String) -> Button:
	for b in fe.find_children("*", "Button", true, false):
		if (b as Button).text == text and not b.is_queued_for_deletion():
			return b
	return null


## A tap as a phone gives one, at `p` in the game's own pixels: a press and a release.
func _tap_at(p: Vector2) -> void:
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = p
		e.global_position = p
		root.push_input(e, true)
