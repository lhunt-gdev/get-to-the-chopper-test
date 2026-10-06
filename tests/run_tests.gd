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
	_test_boss()
	_test_boss_ko()
	_test_cross_death()
	_test_end_typing()
	_test_briefing()
	_test_end_talk()
	_test_cross_ready()
	_test_cross_eased()
	_test_intro_camera()
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
	amb.update(1.0 / 60.0, Vector3.ZERO, 1)
	var before := amb.slot_nodes.slice(0, Ambience.SLOTS)
	flash_boss.flash_lamp.visible = true
	flash_boss.flash_lamp.set_meta("power", 0.7)
	amb.update(1.0 / 60.0, Vector3.ZERO, 1)
	_check(amb.slot_nodes.slice(0, Ambience.SLOTS) == before and before.all(func(x) -> bool: return x != null)
			and amb.slot_nodes[Ambience.SLOTS + 1] == flash_boss.flash_lamp and is_equal_approx(amb.slot_lit[Ambience.SLOTS + 1], 0.7),
			"boss: his flash lights in a slot of its own, no level lamp put out (user)")
	flash_boss.flash_lamp.visible = false
	amb.update(1.0 / 60.0, Vector3.ZERO, 1)
	_check(amb.slot_nodes[Ambience.SLOTS + 1] == null, "boss: his flash's slot is dark when it's out")
	for n in near_lamps:
		n.queue_free()
	flash_boss.queue_free()
	amb.queue_free()
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
	_check(lines.size() >= 8 and who.has("cross") and who.has("general") and who.has("briefer"),
			"briefing: placeholder lines for CROSS, the General and the briefer (%d lines)" % lines.size())
	_check(String(lines[0]["text"]).begins_with("[BISHOP] ") and _said_by(lines, "briefer").begins_with("[VESPER] "),
			"briefing: a line starts with its speaker's name, the codenames set in the cast (%s)" % lines[0]["text"])
	for id in ["cross", "general", "briefer"]:
		_check(load(String(data["cast"][id]["portrait"])) is Texture2D, "briefing: %s's picture loads" % id)
	# Each name set once: rename the General in the cast and every line follows.
	var renamed: Dictionary = data.duplicate(true)
	renamed["cast"]["general"]["name"] = "VIPER"
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
	fe.show_briefing(data)
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
				"end talk %s: its own conversation, %d placeholder lines and a tag (%s)" % [id, lines.size(), talk.get("title", "")])
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
	var g := RouteGraph.from_json_file("res://game/levels/prototype_slice/route.json")
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
	var lens := [INF, -INF, INF]  # (x least and most at sway 0, y least at any sway: 480 high)
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
		for sw in [-0.7, 0.0, 0.7]:
			for l in _rd_lenses(lp):
				lens[2] = minf(lens[2], _rd_screen(l, sw, 480.0).y)
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
	_check(lens[1] - lens_x0 > 18.0 and lens_x0 - lens[0] > 18.0 and lens[2] > 168.0,
			"CROSS ready: his eyes sweep far enough to see on a phone (%+.0f / %+.0f px), under the title (y %.0f)" % [lens[1] - lens_x0, lens[0] - lens_x0, lens[2]])
	_check(gun_px < 290.0 and rest_px[0] < 290.0 and rest_px[1] < 315.0,
			"CROSS ready: the gun check above the menu's buttons (y %.0f; START's top at 290); his hands at the ready above them on a 480-high screen (y %.0f), on a tall phone at most just behind START's top edge (y %.0f)" % [gun_px, rest_px[0], rest_px[1]])
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
	for i in 41:
		var s := -0.7 + i * 0.035
		var p := IntroCamera.pan(0.0, 0.0, s, fm, play)
		var m := IntroCamera.menu(s, 0.0)
		no_cut = no_cut and (p[0] as Vector3).distance_to(m[0]) < 1e-4 and (p[1] as Vector3).distance_to(m[1]) < 1e-4
	_check(no_cut, "the opening pan: START doesn't cut, it starts exactly where the menu's camera was")
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


## A point (him at the origin) on the menu's camera swayed `s`, on a 270 x `h` phone screen (px).
func _rd_screen(p: Vector3, s: float, h: float) -> Vector2:
	var c := IntroCamera.menu(s, 0.0)
	var cam := Transform3D(Basis.IDENTITY, c[0]).looking_at(c[1], Vector3.UP)
	var q := cam.affine_inverse() * p
	var f := (h / 2.0) / tan(deg_to_rad(35.0))
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
