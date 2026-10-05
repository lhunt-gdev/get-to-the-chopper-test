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
