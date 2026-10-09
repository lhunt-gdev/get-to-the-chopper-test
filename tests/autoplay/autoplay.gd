extends Node
## A simple bot that plays the level, so we know the route can be
## finished and the rules (alert gating, extraction, death, capture, combat) work end to end.
##   godot --headless --path . --fixed-fps 60 res://tests/autoplay/autoplay.tscn -- --scenario=ground
## It plays mission 1, COLD CALL, unless --route=test_range picks the TEST RANGE
## (tests/fixtures/test_range.json: the full 19-area level from before mission 1, kept for the bots
## that test what mission 1 leaves out: the dogs, the alarm runner, the snipers, the searchlights,
## the pursuit squad). The same scenario can play either; each route has its own lanes and wires
## for it (_setup_mission_1, _setup_test_range).
## It plays MEDIUM (where the chopper times were tuned) unless --setting=easy|medium|hard picks
## another (route.json "settings"); RESULT ends setting=, bosshp= (the boss's hits on it) and opened=
## (what getting out opened in the mission select; every bot starts on a fresh in-memory save).
## Every bot but "naive" holds FIRE while there's a trooper to shoot (alarm boxes only in the
## alarm scenarios). Scenarios (mission 1 unless it says test range):
##   naive        - never moves or shoots; should be killed. It watches his death (the play camera
##                  kept, normal time, none of him through the ground, the end conversation opening
##                  only once he's still), taps through the end conversation (SIGNAL LOST: see
##                  below), and watches the end screen typing and counting to its end: RESULT ends
##                  death=ok end=typed
##   naive_skip   - as naive, but presses SKIP in the end conversation, and taps the end screen
##                  while it's typing: everything at once (end=skipped)
##   menu_start   - as ground, but through the real main menu: START pressed 2.3 s in (mid gun
##                  check), the mission select and mission 1's screen (_select_mission: it clicks
##                  what's locked, BACK and in again, then EASY: RESULT ends select=ok(easy)), then
##                  (still mid gun check), the mission briefing (it taps through every line, some typed out, some
##                  tapped part way), the opening pan, then the run. It watches CROSS's ready stance
##                  hand over to the run: RESULT ends intro=ok (no joint jumping, the pistol never
##                  at the camera, no camera cut, never standing, control at the pan's end, every
##                  texture made ahead of time made before it, none in the run) and
##                  brief=ok (every line shown; a tap finished a line or showed the next, one tap
##                  counting once; nothing of the run started under it)
##   intro_skip   - as menu_start, but picks mission 1 HARD on its screen (it has got out
##                  of EASY and MEDIUM), presses SKIP in the briefing's second line, then taps 0.3 s
##                  into the pan to skip it (control at once)
##   ground       - keeps to the middle lanes: straight on through the CANTEEN to the EXIT
##   tunnel_quiet - jumps the wires, takes the SECURITY WING's left-lane stairs down to the TUNNEL
##                  (open at alert 1), through the BOILER ROOM to its left ladder up
##   tunnel_loud  - runs through the WING's wire: the basement stairs lock (alert 2), so the left
##                  lane carries straight on to the CANTEEN
##   tunnel_alarm - runs through the MAIN FLOOR's wire, shoots the WING's alarm box (back to alert
##                  1, the door opens) and takes the basement stairs after all
##   tunnel_miss_ladder - as tunnel_quiet, but stays in the middle at the BOILER ROOM's end: captured
##   fire_escape  - jumps the MAIN FLOOR's wire, runs through the WING's (alert 2: the fire escape
##                  opens), up it to the ROOFTOPS, the ROOF EDGE's right ladder down
##   miss_ladder  - as fire_escape, but stays in the middle at the ROOF EDGE: captured
##   fire_shut    - quiet, heads for the fire escape: shut (its padlock), eased a lane in, straight on
##   fire_closes  - runs through the MAIN FLOOR's wire (the fire escape opens), heads for it, shoots
##                  the WING's box: back to alert 1, the fire door shuts again, straight on
##   roof_calm    - up the fire escape, shoots the ROOFTOPS' box: back to alert 1 at the pad
##   roof_down    - (test range) right-lane stairs up to the ROOFTOPS, then left-lane stairs back
##                  down into the SECURITY WING
##   warehouse_drop - (test range) main route to the WAREHOUSE, then its left-lane stairs down into
##                  the PUMP STATION and the STORM DRAIN's ladder up
##   roof_loud    - (test range) runs through the first wire (alert 2), up to the ROOFTOPS,
##                  straight on to the ROOF EDGE, right-lane ladder down
##   late_switch  - heads for the side stairs (mission 1: the WING's basement stairs; test range:
##                  the LOBBY's stairs up), then swipes back to the middle a few metres before the
##                  split: straight on must still be open
##   cover        - runs into the first cover, holds fire until it's safe to shoot from cover,
##                  kills the trooper from there, breaks cover and goes on untouched
##   camper       - takes cover and never leaves it: the chopper should leave without us
##   ground_loud  - main route, runs through both wires and ignores the alarm boxes: Alert 3 (on
##                  the test range, the squad comes after us; mission 1 has none)
##   ground_alarms - main route, runs through both wires, shoots every alarm box: back to Alert 1
##   stumble_once - main route, but runs straight into the first barrier: a stumble (1 HP, a
##                  little time), not the end of the run
##   dog_bite     - (test range) runs through the lobby wire (Alert 2: the dogs come out), main
##                  route, never shoots the EXIT's guard dog and holds its lane when
##                  it charges: bitten (a hit and a stumble), and still gets out
##   dog_dodge    - (test range) as dog_bite, but swipes out of the dog's lane when it barks:
##                  it runs past
##   runner_escapes - (test range) main route, never shoots the alarm runner: he gets to his alarm
##   roof_spotted - (test range) roof route at Alert 1, never dodging the searchlights: spotted
##   sniper_hit   - (test range) as roof_loud (Alert 2: the roof snipers are out), but holds its
##                  lane when the first sniper locks on: hit once; it dodges the rest
## Every bot dodges a roof sniper once his laser locks (one lane to the free side, then it holds
## until he's fired). RESULT ends snipers=hit/dodged/out of view on a tall phone when he locked.
##   squad_caught - (test range) trips both main-route wires (Alert 3, the squad comes after us),
##                  then takes the next cover and stays in it: the squad catches up, CAPTURED
##   boss_hit     - main route; at the chopper, steps into one of the boss's swept lanes for his
##                  first sweep: hit once; it dodges the rest and takes him down
##   boss_hold_fire - main route; at the chopper it dodges every sweep but never shoots the boss:
##                  he blocks the way until the chopper leaves without us
##   boss_tap     - main route; at the chopper it switches to TAP ONLY aiming and taps the boss
##                  (low on his body, off-centre): FIRE shoots him, and it takes him down
##   boss_skip    - main route; it taps at once in the boss's KO replay (too soon: nothing), then
##                  two seconds in: skipped, it runs on
## Every KO replay is watched: RESULT ends ko=shots shown/skipped/ok, ok when it ended with time back
## to normal, the camera back (its field of view, behind us), the HUD back (FIRE showing, REPLAY
## gone), the chopper's clock not moved, us not moved, the boss in view on a tall phone through it,
## his death really shown (every shot ended by its part of his death, not its timeout), and no
## early tap skipping it.
## The zone doors the alarm runner goes through are watched in every scenario (user: "the big doors
## should open and close for him, so he doesn't just faze through them"): each must be open
## (its leaves out of his way, or its shutter up) by the time he's at it, and shut again by the time
## we get there, then burst open by us as ever (its leaves where a shut door's go, no further; the
## shutter right up). RESULT ends gates=opened for him/shut again when we got there/ok, only when
## he opened one.
## Every bot that gets to the helipad fights the boss: while his minigun spins up it steps to the
## nearest of his 2 free lanes, and holds FIRE (he's the target). RESULT ends boss=down/hits/attacks.
## His pattern is fixed for each scenario (a seed from its name), so a run repeats.
## The end-of-mission conversation (TALK: naive, naive_skip, ground, boss_skip, miss_ladder,
## squad_caught, camper, boss_hold_fire stay on after the run for it): it must open when the ending
## has played out (killed: once he's lain still for the hold; else the end screen's 1.1 s), be the
## one for the ending, and get nothing of the run going under it (a swipe, FIRE, a tap or the pause
## button doing nothing; no clock), with the ambience ducked and no sting yet; killed: CROSS's signal
## lost the whole way (his card static, SIGNAL LOST, his waveform flat) and he never speaks. The bot
## taps through it (the odd lines part way, then a tap for the next once each is all there) or
## presses SKIP in its first line; then the debrief must open as it closes, with its title, the
## ambience back and the end's sting playing. RESULT ends talk=ending/tapped or skipped/ok.

const LEVEL := preload("res://game/levels/prototype_slice/prototype_slice.tscn")
const LOOK_AHEAD := 9.0
const ACT_DISTANCE := 1.6
const COVER_AT := 22.0
## The bots that stay on after the run for the end-of-mission conversation and the debrief, and how
## they get through the conversation: tap through every line, or SKIP.
const TALK := {"naive": "tapped", "naive_skip": "skipped", "ground": "tapped", "boss_skip": "skipped", "miss_ladder": "tapped",
		"squad_caught": "skipped", "camper": "tapped", "boss_hold_fire": "skipped"}

var scenario := "ground"
## The mission's setting it plays (--setting=easy|medium|hard).
var setting := RouteGraph.DEFAULT_SETTING
## What was open in its (in-memory) progress as it started, so RESULT can say what getting out opened.
var _open_before: Array = []
## The bot's own save files (its progress, its route map) and what was found on the device as the
## run ended (RESULT's saved=: ok, or bad(...); none if it never ended).
var _save_files: Array = []
var _saved := "none"
## The menu bots' picks, in the mission select and then the mission's screen: [mission, setting].
## menu_start, on a fresh save, first tries what's locked (mission 2's row, mission 1 MEDIUM and
## HARD: nothing may happen), then the one open, mission 1 EASY; intro_skip picks mission 1 HARD (open for it: see _ready), which builds
## the area under the menu again for HARD (its MAIN FLOOR has HARD's extra wire).
const MENU_PICKS := {"menu_start": [1, "easy"], "intro_skip": [1, "hard"]}
## Which route the level plays (--route=): mission 1 (the default), or the TEST RANGE.
var route := "mission_1"
const ROUTES := {"mission_1": "res://game/levels/prototype_slice/route.json", "test_range": "res://tests/fixtures/test_range.json"}
## late_switch: the area whose side exit it heads for, before it changes its mind.
var _late_at: StringName = &""
## The areas where an alarm scenario shoots the alarm boxes (none elsewhere).
var _alarm_in: Array = []
## boss_hit: how many of the boss's attacks have finished (it takes the hit in the first).
var _boss_attacks_seen := 0
## The boss we're fighting was ever out of sight (the twin on a ladder route's other helipad
## standing in for him, say): RESULT then says boss=HIDDEN, so no expectation passes.
var _boss_hidden := false
## naive / naive_skip: watching his death and the end screen, and what it found.
var _death := {}
var _death_report := ""
## TALK: watching the end-of-mission conversation and the debrief opening after it, and the verdict.
var _talk := {}
var _talk_report := ""
## menu_start / intro_skip: watching the menu, START, the pan and the run's first second, and what
## it found.
var _intro := {}
var _intro_report := ""
## The boss's KO replay: the chopper's clock and our distance as it started (and our distance as it
## last showed), its frames and those with the boss out of view, and the verdict once it's over.
var _ko_from := {}
var _ko_frames := 0
var _ko_unseen := 0
var _ko_ok := "-"
var _ko_early := false
var _play_fov := 70.0
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
## sniper_hit: the sniper it holds its lane for (the first to lock on), and whether it has (a
## freed sniper compares equal to null, so the flag is what counts once he's gone).
var _held_for: Object = null
var _held_once := false
## Snipers seen locking (by instance id), and how many were out of view on a tall phone screen
## (19.5:9: 270x585, the narrowest view the game gets) when they did.
var _locks_seen := {}
var _unseen := 0
## The zone doors seen open for the alarm runner: {gate (the level's), burst (the frame we burst
## through it, or -1)}; how many were shut again when we got there; and what went wrong, if anything.
var _gates: Array[Dictionary] = []
var _gates_shut := 0
var _gates_bad := ""
var _frame := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scenario="):
			scenario = a.get_slice("=", 1)
		elif a.begins_with("--route="):
			route = a.get_slice("=", 1)
		elif a.begins_with("--setting="):
			setting = a.get_slice("=", 1)
	# The bots never touch the player's saved progress: theirs is kept in memory, fresh each run
	# (only mission 1 EASY open). intro_skip has got out of mission 1 on EASY and MEDIUM, so HARD is
	# open for it to pick.
	Progress.load_from("")
	if scenario == "intro_skip":
		Progress.record_extraction(1, "easy")
		Progress.record_extraction(1, "medium")
	_open_before = Progress.to_data()["unlocked"]
	# The auto-save (user: "auto save itself after the player finishes a run"), checked as the game
	# does it: from here its progress and its route map are written to the bot's own files (never the
	# player's: those are left alone), which must be on the device as the run ends (RESULT's saved=).
	# Its route map starts empty.
	var tag := "%s_%s_%d" % [scenario, route, OS.get_process_id()]
	_save_files = ["user://bot_progress_%s.json" % tag, "user://bot_discovery_%s.json" % tag]
	_remove_save_files()
	Progress.save_path = _save_files[0]
	RunLog.load_from("")
	RunLog.save_path = _save_files[1]
	if scenario in ["menu_start", "intro_skip"]:
		setting = MENU_PICKS[scenario][1]
	if route == "test_range":
		_setup_test_range()
	else:
		_setup_mission_1()
	_level = LEVEL.instantiate()
	_level.route_path = ROUTES.get(route, ROUTES["mission_1"])
	# The setting it plays (--setting=; MEDIUM, where the chopper times were tuned, by default). The
	# menu bots start the level on MEDIUM, as the game does, and pick theirs in the mission select.
	_level.setting = RouteGraph.DEFAULT_SETTING if scenario in ["menu_start", "intro_skip"] else setting
	# (menu_start and intro_skip run the ground route: the same boss)
	_level.boss_seed = absi(hash("ground" if scenario in ["menu_start", "intro_skip"] else scenario)) % 100000
	add_child(_level)
	_player = _level.get_node("Player")
	GameState.run_ended.connect(_on_end)
	if scenario in ["menu_start", "intro_skip"]:
		_intro = {"f": 0}  # (the main menu is up: START comes in _watch_intro)
	else:
		_level.start_run()
	get_tree().create_timer(200.0).timeout.connect(func() -> void: _report("timeout"))


## Mission 1's ways (see the top): its one junction is at the end of the SECURITY WING (left: the
## basement stairs, open while quiet; right: the fire escape, open once the alarm is up), and its
## ladders at the end of the ROOF EDGE and the BOILER ROOM. Its wires: the MAIN FLOOR's and the
## WING's; its alarm boxes: the MAIN FLOOR's, the WING's (before its wire), the ROOFTOPS' and the EXIT's.
func _setup_mission_1() -> void:
	_late_at = &"security_wing"
	match scenario:
		"tunnel_quiet":
			_prefer = {&"security_wing": -1, &"boiler_room": -1}
		"tunnel_loud":
			_prefer = {&"security_wing": -1}
			_trip_in = [&"security_wing"]
		"tunnel_alarm":
			_prefer = {&"security_wing": -1, &"boiler_room": -1}
			_trip_in = [&"building_main_floor"]
			_alarm_in = [&"security_wing"]
		"tunnel_miss_ladder":
			_prefer = {&"security_wing": -1, &"boiler_room": 0}
		"fire_escape":
			_prefer = {&"security_wing": 1, &"roof_edge": 1}
			_trip_in = [&"security_wing"]
		"miss_ladder":
			_prefer = {&"security_wing": 1, &"roof_edge": 0}
			_trip_in = [&"security_wing"]
		"fire_shut":
			_prefer = {&"security_wing": 1}
		"fire_closes":
			_prefer = {&"security_wing": 1}
			_trip_in = [&"building_main_floor"]
			_alarm_in = [&"security_wing"]
		"roof_calm":
			_prefer = {&"security_wing": 1, &"roof_edge": -1}
			_trip_in = [&"security_wing"]
			_alarm_in = [&"rooftops"]
		"late_switch":
			_prefer = {&"security_wing": -1}
		"ground_loud":
			_trip_in = [&"building_main_floor", &"security_wing"]
		"ground_alarms":
			_trip_in = [&"building_main_floor", &"security_wing"]
			_alarm_in = [&"building_main_floor", &"security_wing", &"main_floor_exit"]


## The TEST RANGE (today's full 19-area level, kept for the bots: tests/fixtures/test_range.json),
## for what mission 1 leaves out: its first junction is at the end of the LOBBY (right: stairs up).
func _setup_test_range() -> void:
	_late_at = &"main_floor_lobby"
	match scenario:
		"roof_down":
			_prefer = {&"main_floor_lobby": 1, &"rooftops": -1}
		"roof_loud", "sniper_hit":
			_prefer = {&"main_floor_lobby": 1, &"roof_edge": 1}
			_trip_in = [&"main_floor_lobby"]
		"roof_spotted":
			_prefer = {&"main_floor_lobby": 1, &"roof_edge": 1}
		"warehouse_drop":
			_prefer = {&"warehouse": -1, &"storm_drain": -1}
		"dog_bite", "dog_dodge":
			_trip_in = [&"main_floor_lobby"]
		"ground_loud", "squad_caught":
			_trip_in = [&"main_floor_lobby", &"building_main_floor"]


func _physics_process(_delta: float) -> void:
	if not GameState.run_active or scenario in ["naive", "naive_skip"]:
		return
	var d := _player.distance_run()
	var obstacles: Array = _level._obstacles
	var lane_count: int = _player.tuning.lane_count

	if _watch_ko():
		return  # (the KO replay: we just watch)
	_shoot()
	_watch_gates()
	if d < 0.3 or _level.in_stairwell():
		return  # in the start room or a stairwell: no swipes until we're through the door
	if _level._boss_fight != null and is_instance_valid(_level._boss_fight) and _level._boss_fight.state == Boss.State.SPINDOWN:
		_boss_attacks_seen = maxi(_boss_attacks_seen, _count("boss_attack"))
	if _level._boss_fight != null and is_instance_valid(_level._boss_fight) and not _level._boss_fight.is_visible_in_tree():
		_boss_hidden = true
	if _boss_standoff():
		return  # facing the boss: lane steps only (FIRE is held by _shoot: he's the target)
	if _player.in_cover:
		_took_cover = true
		_cover_frames += 1
		# Break cover once nobody ahead is alive to shoot at us.
		var hiding := scenario == "squad_caught" and GameState.alert_level >= 3
		if scenario != "camper" and not hiding and not _trooper_ahead(d):
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
	if scenario == "late_switch" and _level._runner.current == _late_at:
		var runner: RouteRunner = _level._runner
		var left_to_split := runner.graph.length_of(runner.current) - (d - runner.segment_start)
		if left_to_split < 4.0:
			_prefer[_late_at] = 0
			_cooldown = mini(_cooldown, 0)

	# A roof sniper's laser has locked on: step one lane to the free side, then hold until he's fired
	# (never back through the locked lane). sniper_hit holds its lane for the first one.
	var sn: Sniper = _locked_sniper()
	if sn != null and not _locks_seen.has(sn.get_instance_id()):
		_locks_seen[sn.get_instance_id()] = true
		if not _in_phone_view(sn.scope_position()):
			_unseen += 1
	if sn != null:
		var in_line := absf(_player.lane_x(_player.lane) - sn.locked_x) < _player.tuning.lane_width * 0.5
		if scenario == "sniper_hit" and (not _held_once or (is_instance_valid(_held_for) and _held_for == sn)):
			_held_for = sn
			_held_once = true
		elif in_line:
			var to := _dodge_lane(obstacles, d)
			if to != _player.lane:
				_player.handle_swipe(Vector2i.RIGHT if to > _player.lane else Vector2i.LEFT)
		_cooldown = maxi(_cooldown, 3)

	# Steering: avoid lanes with cover (walls, boxes) coming up; lean to the preferred side at junctions.
	_cooldown -= 1
	if _cooldown <= 0:
		var best := _player.lane
		var best_score := -INF
		for lane in range(lane_count):
			var score := -absf(lane - _player.lane) * 0.5
			if _lit_ahead(lane, d):
				score -= 60.0  # a searchlight's pool will be there when we get there
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


## The boss at the chopper: while his minigun spins up, step toward the nearest of his 2 free
## lanes (a lane a frame, ties toward the middle), then hold through the sweep and the spin-down.
## boss_hit steps into a swept lane for his first sweep instead.
func _boss_standoff() -> bool:
	if not _player.standoff:
		return false
	var boss: Boss = _level._boss_fight
	if boss == null or not is_instance_valid(boss) or boss.state != Boss.State.SPINUP:
		return true
	var mid := (_player.tuning.lane_count - 1) / 2.0
	var want_hit := scenario == "boss_hit" and _boss_attacks_seen == 0
	var to := _player.lane
	var best := INF
	for l in _player.tuning.lane_count:
		if boss.free_lanes.has(l) == want_hit:
			continue
		var cost := absf(l - _player.lane) * 10.0 + absf(l - mid)
		if cost < best:
			best = cost
			to = l
	if to != _player.lane:
		_player.handle_swipe(Vector2i.RIGHT if to > _player.lane else Vector2i.LEFT)
	return true


## The boss's KO replay: true while it's on. boss_skip taps two seconds in.
func _watch_ko() -> bool:
	var ko: int = _level._ko
	if ko < 0 and _ko_from.is_empty():
		_play_fov = _level._camera.fov
	if ko >= 0:
		if _ko_from.is_empty():
			_ko_from = {"clock": _level._clock.elapsed, "d": _player.distance_run()}
		_ko_from["d_last"] = _player.distance_run()
		_ko_frames += 1
		var boss: Boss = _level._boss_fight
		if not _in_phone_view(boss._rig.chest.global_position) and not _in_phone_view(boss._rig.hips.global_position):
			_ko_unseen += 1
		if scenario == "boss_skip" and _ko_frames == 10:
			_level._on_tap(Vector2(135, 300))  # (too soon: no skip)
			_ko_early = _level._ko < 0
		if scenario == "boss_skip" and _ko_frames == 120:
			_level._on_tap(Vector2(135, 300))
		return true
	if not _ko_from.is_empty() and _ko_ok == "-":
		var cam: Camera3D = _level._camera
		var rel: Vector3 = _player.to_local(cam.global_position)
		var cam_back: bool = get_viewport().get_camera_3d() == cam and is_equal_approx(cam.fov, _play_fov) and rel.z > 2.0 and rel.length() < 8.0
		var hud = _level._hud
		var hud_back: bool = hud._fire.visible and (hud._replay == null or not hud._replay.visible)
		var timed_out := RunLog.events.filter(func(e: Dictionary) -> bool: return e["kind"] == "ko_shot_end" and e.get("timed_out", false)).size()
		var boss: Boss = _level._boss_fight
		var shown_to: float = Boss.DEATH_END if _level._ko_skipped else float(KoReplay.shots(_player.tuning)[-1]["to"])
		var shown: bool = timed_out == 0 and boss.death_t >= shown_to - 0.001
		var ok: bool = Engine.time_scale == 1.0 and cam_back and hud_back and shown and not _ko_early \
				and absf(_level._clock.elapsed - float(_ko_from["clock"])) < 0.05 \
				and is_equal_approx(float(_ko_from["d_last"]), float(_ko_from["d"])) and not _player.standoff \
				and _ko_unseen <= _ko_frames / 20
		_ko_ok = "ok" if ok else "bad(ts=%.2f cam=%s fov=%.0f/%.0f rel=%s hud=%s shown=%s(%d,%.2f) early=%s clock=%.2f/%.2f d=%.2f/%.2f unseen=%d/%d)" % [
				Engine.time_scale, cam_back, cam.fov, _play_fov, rel, hud_back, shown, timed_out, boss.death_t, _ko_early,
				_level._clock.elapsed, _ko_from["clock"], _ko_from["d_last"], _ko_from["d"], _ko_unseen, _ko_frames]
	return false


## Hold FIRE while there's something worth shooting.
func _shoot() -> void:
	if scenario == "boss_tap" and _player.standoff:
		# TAP ONLY from here: nothing's shot till it's tapped. Tap him (at his knees, a little off
		# to the side), as a player would.
		_level.tuning.targeting_mode = Tuning.TargetingMode.TAP_TO_TARGET
		var boss: Boss = _level._boss_fight
		if boss != null and is_instance_valid(boss) and boss.is_targetable(GameState.alert_level) and _level._tapped != boss:
			var cam: Camera3D = _level._camera
			_level._on_tap(cam.unproject_position(boss.global_position + Vector3.UP * 0.6) + Vector2(10.0, 0.0))
	var target: Node3D = _level.fire_target()
	var want := target != null
	if target is Boss and scenario == "boss_hold_fire":
		want = false  # he blocks the way: the chopper leaves without us
	if target is AlarmBox and not _may_shoot_alarm():
		want = false
	if target is SecurityTrooper and scenario == "runner_escapes":
		# Let him go, but still deal with the riflemen: tap one to override the auto-aim.
		var rifle := _rifleman_in_range()
		if rifle != null:
			_level._tapped = rifle
			target = _level.fire_target()
		want = target != null and not target is SecurityTrooper  # let him go
	if target is RusherDog and scenario in ["dog_bite", "dog_dodge"] and _level._runner.current == &"main_floor_exit":
		want = false  # leave the EXIT's dog to bite or be dodged (shoot the rest)
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
		if n is RusherDog and n.state in [RusherDog.State.WINDUP, RusherDog.State.CHARGE] and n.at > d and _level._runner.current == &"main_floor_exit":
			return n
	return null


func _blocked_ahead(obstacles: Array, lane: int, d: float) -> bool:
	var x := _player.lane_x(lane)
	for o: Dictionary in obstacles:
		var seeking_cover := (scenario in ["cover", "camper"] and not _took_cover) or (scenario == "squad_caught" and GameState.alert_level >= 3)
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
	_saved = _check_saved(reason)
	if TALK.has(scenario):
		# Stay on for the end-of-mission conversation and the debrief (_watch_talk).
		_talk = {"reason": String(reason), "how": TALK[scenario], "f": 0, "bad": "", "open_f": -1, "dead_f": -1, "closed_f": -1,
				"debrief_f": -1, "count": 0, "lines": 0, "tapped": 0, "skipped": 0, "seen": {}, "full": {}}
	if reason == GameState.END_KILLED and scenario in ["naive", "naive_skip"]:
		# Watch his death and the end screen (_process) before reporting.
		_death = {"reason": String(reason), "fov": _level._camera.fov, "cam": _level._camera, "frames": 0, "low": INF,
				"bad": "", "open_at": -1, "dead_at": -1, "deb_at": -1, "tapped": false}
		return
	if not _talk.is_empty():
		return  # (it reports once the debrief opens)
	_report(String(reason))


## naive / naive_skip: his death, the end conversation, then the end screen, frame by frame.
func _process(_delta: float) -> void:
	_watch_intro()
	_watch_talk()
	if _death.is_empty() or _death.has("done"):
		return
	var d := _death
	d["frames"] += 1
	var f: int = d["frames"]
	var fe = _level._frontend
	var open: bool = fe.is_open()
	if int(d["open_at"]) < 0:
		# Dying: the play camera, as it was; normal time; none of him through the ground.
		if get_viewport().get_camera_3d() != d["cam"] or not is_equal_approx(_level._camera.fov, d["fov"]) or Engine.time_scale != 1.0:
			d["bad"] += " camera/time"
		var rig: SoldierRig = _player._rig
		for p in rig._rag_points():
			d["low"] = minf(d["low"], _player.to_local(rig.global_transform * (p as Vector3)).y)
		if _player.is_dead() and int(d["dead_at"]) < 0:
			d["dead_at"] = f
		if open:
			d["open_at"] = f  # (the end conversation: _watch_talk takes it through to the debrief)
			if not _player.is_dead():
				d["bad"] += " opened-before-he-was-still"
	else:
		if int(d["deb_at"]) < 0:
			if not fe.in_debrief():
				if f > int(d["open_at"]) + 3600:
					d["bad"] += " no-debrief"
					d["deb_at"] = f
				return
			d["deb_at"] = f
		if scenario == "naive_skip" and not d["tapped"] and f >= int(d["deb_at"]) + 30:
			# A tap on the screen, clear of the buttons, into the end screen's skip area (a headless run
			# doesn't route a pushed tap to the controls; the unit test checks the area covers the screen).
			d["tapped"] = true
			var tap := InputEventMouseButton.new()
			tap.button_index = MOUSE_BUTTON_LEFT
			tap.pressed = true
			tap.position = Vector2(135, 300)
			for n in fe.find_children("*", "", true, false):
				if n is Control and n.get_class() == "Control" and (n as Control).mouse_filter == Control.MOUSE_FILTER_STOP and n.has_signal("pressed"):
					n._gui_input(tap)
			d["skip_at"] = f
			return
		var done := _end_screen_done()
		if done.is_empty() and f < int(d["deb_at"]) + 900:
			return
		if scenario == "naive_skip" and (not d.has("skip_at") or f > int(d["skip_at"]) + 2):
			d["bad"] += " skip-not-at-once"
		d["done"] = true
		var ok: bool = String(d["bad"]) == "" and float(d["low"]) > -0.04 and int(d["dead_at"]) > 0 and done == "ok"
		_death_report = " death=%s end=%s" % ["ok" if ok else "bad(%s low=%.3f dead=%d open=%d)" % [d["bad"], d["low"], d["dead_at"], d["open_at"]],
				("skipped" if scenario == "naive_skip" else "typed") + ("" if done == "ok" else "/" + done)]
		_report(String(d["reason"]))


## TALK, every frame after the run: the end-of-mission conversation (see the top), then the debrief.
func _watch_talk() -> void:
	if _talk.is_empty() or _talk.has("done"):
		return
	var t := _talk
	t["f"] += 1
	var f: int = t["f"]
	var fe = _level._frontend
	var killed: bool = t["reason"] == String(GameState.END_KILLED)
	# Nothing of the run once it's over (whatever's pressed: see _drive_talk); the sting waits.
	if GameState.run_active or get_tree().paused or _level._fire_held or _level._clock.running:
		_talk_bad(t, "run-after-end")
	if int(t["debrief_f"]) < 0 and not fe.in_debrief() and _sting_playing():
		_talk_bad(t, "sting-before-debrief")
	if _player.is_dead() and int(t["dead_f"]) < 0:
		t["dead_f"] = f
	if int(t["open_f"]) < 0:
		if fe.in_end_talk():
			t["open_f"] = f
			# When the ending's played out: killed, once he's lain still for the hold; else the end
			# screen's moment (1.1 s).
			var want := int(t["dead_f"]) + roundi(_player.tuning.death_hold * 60.0) if killed else 66
			if (killed and (not _player.is_dead() or int(t["dead_f"]) < 0)) or absi(f - want) > 4:
				_talk_bad(t, "opened-at-%d-not-%d" % [f, want])
		elif fe.is_open() or f > 3600:
			_talk_bad(t, "no-conversation")
			_talk_verdict(t)
		return
	if int(t["debrief_f"]) < 0:
		if fe.in_debrief():
			t["debrief_f"] = f
			# The debrief as the conversation closes, its title, the ambience back, the sting now.
			if int(t["closed_f"]) < 0 or f - int(t["closed_f"]) > 2:
				_talk_bad(t, "debrief-not-as-it-closed")
			var want_title := String((fe.get_script() as GDScript).get_script_constant_map()["END_TITLES"][StringName(t["reason"])][0])
			if not fe.find_children("*", "Label", true, false).any(func(l: Label) -> bool: return l.text == want_title):
				_talk_bad(t, "no-debrief-title")
			if _level._audio._amb_duck != 0.0:
				_talk_bad(t, "ambience-still-ducked")
			if not _sting_playing():
				_talk_bad(t, "no-sting")
			_talk_verdict(t)
			return
		if not fe.in_end_talk() or f > int(t["open_f"]) + 3600:
			_talk_bad(t, "conversation-went-without-a-debrief")
			_talk_verdict(t)
			return
		_drive_talk(t, f, killed)


## The end conversation itself: what must hold while it's up, and the bot reading it (tapping
## through, as a phone delivers a tap, or SKIP in its first line).
func _drive_talk(t: Dictionary, f: int, killed: bool) -> void:
	var fe = _level._frontend
	var br: Briefing = null
	for n in fe.find_children("*", "", true, false):
		if n is Briefing:
			br = n
	if br == null:
		return
	if int(t["count"]) == 0:
		t["count"] = br.line_count()
		if br.conversation_id() != String(t["reason"]):
			_talk_bad(t, "the-%s-conversation" % br.conversation_id())
		br.finished.connect(func() -> void: t["closed_f"] = int(t["f"]))
	if _level._audio._amb_duck >= 0.0:
		_talk_bad(t, "ambience-not-ducked")
	# Nothing reaches the ended run under it: a swipe, FIRE, a tap at the level, the pause button.
	if f == int(t["open_f"]) + 30:
		var lane := _player.lane
		_level._on_swipe(Vector2i.LEFT)
		_level._on_fire()
		_level._on_tap(Vector2(135, 240))
		_level._pause()
		if _player.lane != lane or _level._fire_held or get_tree().paused or not fe.in_end_talk():
			_talk_bad(t, "input-reached-the-run")
	# Killed (user: "Signal lost"): CROSS's card static the whole way, SIGNAL LOST, his waveform
	# flat, and he never speaks.
	var lost_ok: bool = br.signal_lost() and br.speaker() != "cross" and br.wave_peak("right", Briefing.WAVE_MOST) == 0.0 \
			and (br.power("right") < 1.0 or br.is_closing() or br.static_on("right") >= Briefing.LOST_STATIC - 0.001)
	if killed and not lost_ok:
		_talk_bad(t, "signal-not-lost")
	elif not killed and br.signal_lost():
		_talk_bad(t, "signal-lost")
	if not br.is_talking():
		return
	var i := br.line_index()
	t["lines"] = maxi(int(t["lines"]), i + 1)
	if not t["seen"].has(i):
		t["seen"][i] = f
	var since: int = f - int(t["seen"][i])
	if t["how"] == "skipped":
		if since == 20 and int(t["skipped"]) == 0:
			br.skip_button.pressed.emit()
			t["skipped"] += 1
		return
	if not br.line_done():
		if i % 2 == 1 and since == 15:
			_tap_briefing(br)  # (part way: it must finish the line, nothing more)
			if not br.line_done() or br.line_index() != i:
				_talk_bad(t, "tap-on-line-%d-didn't-just-finish-it" % (i + 1))
		return
	if not t["full"].has(i):
		t["full"][i] = f
	if f - int(t["full"][i]) < 15:
		return  # (reading it)
	_tap_briefing(br)
	t["tapped"] += 1


func _talk_bad(t: Dictionary, what: String) -> void:
	if not String(t["bad"]).contains(what):
		t["bad"] += " " + what


## The verdict, once the debrief has opened (or it went wrong): RESULT's talk=; the bots other than
## naive / naive_skip report now (those go on to watch the end screen).
func _talk_verdict(t: Dictionary) -> void:
	t["done"] = true
	var n: int = t["count"]
	var read_ok: bool = int(t["lines"]) == n and int(t["tapped"]) == n if t["how"] == "tapped" else int(t["lines"]) == 1 and int(t["skipped"]) == 1
	var ok: bool = String(t["bad"]) == "" and n >= 3 and read_ok
	_talk_report = " talk=%s/%s/%s" % [t["reason"], t["how"], "ok" if ok else "bad(lines %d/%d tapped %d skipped %d open %d dead %d closed %d debrief %d%s)" % [
			t["lines"], n, t["tapped"], t["skipped"], t["open_f"], t["dead_f"], t["closed_f"], t["debrief_f"], t["bad"]]]
	if _death.is_empty():
		_report(String(t["reason"]))


## The end's sting (the extraction jingle or the game-over sting) playing.
func _sting_playing() -> bool:
	var stings := [SoundBank.get_stream("jingle"), SoundBank.get_stream("gameover")]
	for p: AudioStreamPlayer in _level._audio._pool:
		if p.playing and p.stream in stings:
			return true
	return false


## The end screen typed and counted to its end, with the exact words ("ok"), or what isn't ("": not
## done yet).
func _end_screen_done() -> String:
	var fe = _level._frontend
	var tally: Tally = null
	var title: Label = null
	var typers := []
	for n in fe.find_children("*", "", true, false):
		if n is Tally:
			tally = n
		elif n is Label and (n as Label).text == "KILLED IN ACTION":
			title = n
		elif n.has_method("finish") and n.has_method("is_done") and not n is Tally:
			typers.append(n)
	if tally == null or title == null or typers.is_empty():
		return ""
	if not tally.is_done():
		return ""
	for t in typers:
		if not t.is_done():
			return ""
	if title.visible_characters != -1 and title.visible_characters < title.text.length():
		return "title-not-typed"
	return "ok"


func _count(kind: String) -> int:
	return RunLog.events.filter(func(e: Dictionary) -> bool: return e["kind"] == kind).size()


## Whether a point is in the camera's view on a tall phone (270x585, the narrowest the game gets).
func _in_phone_view(p: Vector3) -> bool:
	var cam: Camera3D = _level._camera
	var c := cam.global_transform.affine_inverse() * p
	if c.z >= 0.0:
		return false
	var half_v := tan(deg_to_rad(cam.fov) / 2.0)
	var half_h := half_v * 270.0 / 585.0
	return absf(c.x / -c.z) <= half_h * 0.9 and absf(c.y / -c.z) <= half_v * 0.95


## A sniper on our area whose laser has locked on (null if none).
func _locked_sniper() -> Sniper:
	for s: Dictionary in _level._snipers:
		var sn: Sniper = s["node"]
		if is_instance_valid(sn) and s["seg"].get("promoted", false) and sn.is_locked():
			return sn
	return null


## The lane next to ours to dodge into: free of cover and searchlight pools, toward the middle.
func _dodge_lane(obstacles: Array, d: float) -> int:
	var lane_count: int = _player.tuning.lane_count
	var best := _player.lane
	var best_score := -INF
	for to in [_player.lane - 1, _player.lane + 1]:
		if to < 0 or to >= lane_count:
			continue
		var score := -absf(to - (lane_count - 1) / 2.0)
		if _blocked_ahead(obstacles, to, d):
			score -= 100.0
		if _lit_ahead(to, d):
			score -= 60.0
		if score > best_score:
			best_score = score
			best = to
	return best


## Every frame of the run: the zone doors the alarm runner goes through (see the top).
func _watch_gates() -> void:
	_frame += 1
	for g: Dictionary in _level._gates:
		if g["state"] != _level.Gate.SHUT and _watched(g) < 0:
			_gates.append({"gate": g, "burst": -1})
	for w in _gates:
		var g: Dictionary = w["gate"]
		var sec = g["by"]
		# He's at it (his front at the door): it must be out of his way by now.
		if g["state"] == _level.Gate.OPEN and is_instance_valid(sec) and sec.is_running() \
				and absf(float(g["at"]) - 0.35 - sec.at) < 0.2 and is_instance_valid(g["node"]):
			var open: float = _level._gate_open_part(g)
			if open < 0.9:
				_gate_wrong("late %.2f open at %.1f" % [open, g["at"]])
		if g["state"] == _level.Gate.BURST and int(w["burst"]) < 0:
			w["burst"] = _frame
			if g["was"] == _level.Gate.SHUT:
				_gates_shut += 1
			elif not is_instance_valid(sec) or sec.is_alive():
				_gate_wrong("not shut at %.1f (%d)" % [g["at"], g["was"]])  # (only held open for him lying in it)
		if int(w["burst"]) >= 0 and _frame == int(w["burst"]) + 50:
			# Burst open by us as ever: its leaves where a shut door's go (no further), the shutter up.
			var sh = g["shutter"]
			if sh != null:
				if is_instance_valid(sh["node"]) and absf(sh["node"].position.y - (float(sh["shut_y"]) + _level.GATE_H - 0.05)) > 0.01:
					_gate_wrong("shutter at %.2f" % sh["node"].position.y)
			else:
				for leaf: Dictionary in g["leaves"]:
					var shut: Vector3 = leaf["shut"]
					if not is_instance_valid(leaf["node"]):
						continue
					var r: Vector3 = leaf["node"].rotation
					if absf(angle_difference(shut.y + 1.9 * float(leaf["swing"]), r.y)) > 0.01 or absf(angle_difference(shut.z + 0.1 * float(leaf["swing"]), r.z)) > 0.01:
						_gate_wrong("leaf at %.2f/%.2f" % [angle_difference(shut.y, r.y), angle_difference(shut.z, r.z)])


## The gate's place in _gates (by identity: they're dictionaries), or -1.
func _watched(g: Dictionary) -> int:
	for i in _gates.size():
		if is_same(_gates[i]["gate"], g):
			return i
	return -1


func _gate_wrong(what: String) -> void:
	if _gates_bad == "":
		_gates_bad = what


func _gates_report() -> String:
	if _gates.is_empty():
		return ""
	return " gates=%d/%d/%s" % [_gates.size(), _gates_shut, "ok" if _gates_bad == "" else "bad(%s)" % _gates_bad]


func _report(reason: String) -> void:
	print("RESULT scenario=%s reason=%s alert=%d route=%s | covers=%d hits=%d missed=%d alarms=%d stumbles=%d doors=%d dogs=%d/%d/%d runner=%d/%d squad=%d/%d lights=%d time=%.1f snipers=%d/%d/%d" % [scenario, reason,
			GameState.alert_level, RunLog.route_summary(), _count("cover"), _count("player_hit"), _count("trooper_missed"), _count("alarm_hit"), _count("stumble"), _count("door_bash"),
			_count("dog_bite"), _count("dog_dodged"), _count("dog_down"), _count("runner_down"), _count("runner_alarm"), _count("squad_out"), _count("squad_caught"), _count("searchlight"), _level._clock.elapsed,
			_count("sniper_hit"), _count("sniper_dodged"), _unseen]
			+ (" boss=HIDDEN" if _boss_hidden else " boss=%d/%d/%d" % [_count("boss_down"), _count("boss_hit"), _count("boss_attack")])
			+ " ko=%d/%d/%s" % [_count("ko_shot"), 1 if _level._ko_skipped else 0, _ko_ok] + _death_report + _talk_report + _intro_report + _gates_report() + " setting=%s bosshp=%d opened=%s saved=%s" % [_level._graph.setting, _boss_hp(), _opened(), _saved])
	_remove_save_files()
	get_tree().quit()


## menu_start / intro_skip, every frame from the menu to a second into the run: START 2.3 s in
## (mid gun check), the briefing (_watch_briefing), then the pan; intro_skip taps 0.3 s into the
## pan. Checks: no joint jumping (from his second frame: the first replaces the set he's built in
## before it's drawn), the pistol never at the camera, the camera never cutting, never standing
## before the run, and control when it should come after the pan starts (LOCKED: "short beats,
## control back immediately": the briefing is before control, the user's own request).
func _watch_intro() -> void:
	if _intro.is_empty() or _intro.has("done"):
		return
	var d := _intro
	d["f"] += 1
	var f: int = d["f"]
	var rig: SoldierRig = _player._rig
	if f == 138:
		_level._frontend.briefing_done.connect(func() -> void: d["pan"] = int(d["f"]))  # (the pan starts)
		_select_mission(d)  # (START MISSION, the mission select, the pick: the briefing opens)
		d["start"] = f
	if d.has("start") and not d.has("pan"):
		_watch_briefing(d, f)
	if scenario == "intro_skip" and d.has("pan") and f == int(d["pan"]) + 18:
		_level._on_tap(Vector2(135, 240))
	if GameState.run_active and not d.has("run"):
		d["run"] = f
		# The level's textures made ahead of time: all made by now, and it's stopped making them.
		d["warm"] = _level._to_warm.size() - _level._warm_next + (1 if _level.is_processing() else 0)
	var now: Array = [rig.hips.position]
	for j in rig._all_joints():
		now.append(j.quaternion)
	if f > 2:
		for k in range(1, now.size()):
			d["step"] = maxf(float(d.get("step", 0.0)), (d["prev"][k] as Quaternion).angle_to(now[k]))
		if not d.has("run"):
			d["cam"] = maxf(float(d.get("cam", 0.0)), (d["eye"] as Vector3).distance_to(_level._camera.global_position))
	d["prev"] = now
	d["eye"] = _level._camera.global_position
	if not d.has("run") and not rig._idle_on:
		d["stood"] = int(d.get("stood", 0)) + 1
	var m := rig._muzzle.global_transform
	d["gun"] = minf(float(d.get("gun", 180.0)), rad_to_deg((-m.basis.z).angle_to(_level._camera.global_position - m.origin)))
	if not d.has("run") or f < int(d["run"]) + 60:
		return
	d["done"] = true
	var want := int(round(_player.tuning.intro_pan_time * 60.0)) if scenario == "menu_start" else 18
	var took := int(d["run"]) - int(d.get("pan", -100000))
	var ok: bool = float(d["step"]) < 0.25 and float(d["gun"]) > 35.0 and float(d["cam"]) < 0.25 and not d.has("stood") and absi(took - want) <= 1 \
			and int(d["warm"]) == 0 and _level._to_warm.is_empty()
	_intro_report = " intro=ok" if ok else " intro=bad(step %.2f, gun %.0f, cam %.2f m, stood %d, control after %d frames, textures left %d)" % [
			d["step"], d["gun"], d["cam"], d.get("stood", 0), took, d["warm"]]
	var b: Dictionary = d.get("brief", {})
	var lines: int = b.get("count", -1)
	var brief_ok: bool = String(b.get("bad", "?")) == "" and d.has("pan") and b.get("closed", 0) == 1
	if scenario == "menu_start":
		# Every line; the odd ones tapped part way (finished), every one but the last followed by a tap
		# showing the next.
		brief_ok = brief_ok and b.get("lines", 0) == lines and b.get("finished", 0) == floori(lines / 2.0) and b.get("advanced", 0) == lines - 1
	else:
		brief_ok = brief_ok and b.get("lines", 0) == 2 and b.get("advanced", 0) == 1 and b.get("skipped", 0) == 1
	_intro_report += " brief=ok" if brief_ok else " brief=bad(lines %d/%d finished %d advanced %d skipped %d closed %d%s)" % [
			b.get("lines", 0), lines, b.get("finished", 0), b.get("advanced", 0), b.get("skipped", 0), b.get("closed", 0), b.get("bad", "?")]
	_intro_report += " select=%s" % d.get("select", "bad(never)")


## menu_start / intro_skip: START MISSION pressed on the main menu must open the mission select,
## listing all nine missions (2 to 9 COMING SOON, greyed and not pickable; no settings on it now: user,
## "The menu is too cramped"); a click on mission 1's row must open its own screen, with EASY,
## MEDIUM and HARD. menu_start, on a fresh save, first clicks mission 2's row (nothing may happen),
## then on mission 1's screen clicks what's locked (MEDIUM and HARD: each greyed with its padlock,
## and a click on it, or choosing it, does nothing), goes BACK to the select and into mission 1
## again; then each bot clicks its pick (MENU_PICKS): the briefing must open, on the level built for
## that setting (HARD: the MAIN FLOOR built under the menu built again, with HARD's extra wire). The
## clicks go in as a phone's would (a press and a release where the button is on screen). RESULT
## ends select=ok(setting) or select=bad(...).
func _select_mission(d: Dictionary) -> void:
	var fe = _level._frontend
	var bad := PackedStringArray()
	for b in fe.find_children("*", "Button", true, false):
		if (b as Button).text == "START MISSION":
			(b as Button).pressed.emit()
	if not fe.in_missions():
		bad.append("no-select")
	var rows := 0
	for n in fe.find_children("*", "", true, false):
		if n is Frontend.MissionRow and not n.is_queued_for_deletion():
			rows += 1
			if n.built != (n.number == 1) or n.playable() != (n.number == 1) or n.disabled == n.playable():
				bad.append("row-%d" % n.number)
	if rows != 9:
		bad.append("rows-%d" % rows)
	if fe.chip(1, "easy") != null:
		bad.append("settings-on-select")
	var pick: Array = MENU_PICKS[scenario]
	if scenario == "menu_start":
		var two: Frontend.MissionRow = fe.mission_row(2)
		if two == null:
			bad.append("no-row-2")
		else:
			_click(two.get_global_rect().get_center())
			if not fe.in_missions():
				bad.append("2-opened")
	_open_row(fe, pick[0], bad)
	if scenario == "menu_start":
		for locked in [[1, "medium"], [1, "hard"]]:
			var c: Frontend.SettingChip = fe.chip(locked[0], locked[1])
			if c == null or not c.disabled or c.open:
				bad.append("%d-%s-not-locked" % locked)
				continue
			_click(c.get_global_rect().get_center())
			if fe.choose(locked[0], locked[1]) or not fe.in_mission() or _level._graph.setting != RouteGraph.DEFAULT_SETTING:
				bad.append("%d-%s-picked" % locked)
		# BACK to the select, and into mission 1 again.
		var back: Button = null
		for b in fe.find_children("*", "Button", true, false):
			if (b as Button).text == "BACK" and not b.is_queued_for_deletion():
				back = b
		if back == null:
			bad.append("no-back")
		else:
			_click(back.get_global_rect().get_center())
			if not fe.in_missions():
				bad.append("back-not-to-select")
			_open_row(fe, pick[0], bad)
	var chosen: Frontend.SettingChip = fe.chip(pick[0], pick[1])
	if chosen == null or chosen.disabled:
		bad.append("pick-locked")
	else:
		if chosen.best >= 0.0:
			bad.append("best-on-fresh-save")
		_click(chosen.get_global_rect().get_center())
	if not fe.in_briefing() or _level._graph.setting != String(pick[1]) or Progress.last != Progress.key(pick[0], pick[1]):
		bad.append("pick-didn't-start-it(%s)" % _level._graph.setting)
	if pick[1] == "hard":
		var wire := false
		for o in _level._obstacles:
			if o["kind"] == "tripwire" and is_equal_approx(float(o["group"].get("at", 0)), 127.0) and o["group"].get("min_setting", "") == "hard":
				wire = true
		if not wire:
			bad.append("hard-not-built")
	d["select"] = "ok(%s)" % pick[1] if bad.is_empty() else "bad(%s)" % ",".join(bad)


## In the mission select, a click on mission n's row: its screen must open, with its three settings.
func _open_row(fe: Node, n: int, bad: PackedStringArray) -> void:
	var row: Frontend.MissionRow = fe.mission_row(n)
	if row == null or row.disabled:
		bad.append("row-%d-not-pickable" % n)
		return
	_click(row.get_global_rect().get_center())
	if not fe.in_mission() or fe.mission_shown() != n:
		bad.append("row-%d-didn't-open" % n)
	for s in RouteGraph.SETTINGS:
		if fe.chip(n, s) == null:
			bad.append("no-%d-%s" % [n, s])


## A tap as a phone gives one, at `p` on screen: a press and a release (the GUI's click).
func _click(p: Vector2) -> void:
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = p
		e.global_position = p
		get_viewport().push_input(e, true)  # (in the game's own 270-wide pixels)


## The mission briefing, between START and the pan. menu_start reads it the way a player taps
## through it (each tap a touch and the click emulated from it, in the same frame, as a phone gives
## one): the odd lines it taps part way (that tap must finish the line, nothing more), the even ones
## it lets type out; once a line is all there it waits a moment, then a tap must show the next.
## intro_skip reads the first line the same way, then presses SKIP in the second. While it's up
## nothing of the run may start (no run, the clock at 0, no pan, the menu still up under it, CROSS's
## ready loop going), and the level's own input (a swipe, FIRE, a tap) mustn't start it. The last
## tap (or SKIP) is timed so the pan starts 2.3 s into CROSS's loop (mid gun check), where START
## used to be.
func _watch_briefing(d: Dictionary, f: int) -> void:
	var b: Dictionary = d.get("brief", {"bad": "", "lines": 0, "finished": 0, "advanced": 0, "skipped": 0, "closed": 0, "seen": {}, "full": {}})
	d["brief"] = b
	var rig: SoldierRig = _player._rig
	var stray := ""
	if GameState.run_active or _level._started:
		stray = "run"
	elif _level._clock.elapsed > 0.0:
		stray = "clock"
	elif _level._intro_left > 0.0:
		stray = "pan"
	elif not _level._menu_open or not rig._idle_on:
		stray = "menu/loop"
	if stray != "" and not String(b["bad"]).contains(stray):
		b["bad"] += " %s-under-it" % stray
	if f == int(d["start"]) + 90:
		_level._on_swipe(Vector2i.UP)
		_level._on_fire()
		_level._on_tap(Vector2(135, 240))
		_level.set_fire_held(false)
		if _level._started:
			b["bad"] += " input-started-it"
	var br: Briefing = null
	for n in _level._frontend.find_children("*", "", true, false):
		if n is Briefing:
			br = n
	if br == null:
		return
	if not b.has("count"):
		b["count"] = br.line_count()
		br.finished.connect(func() -> void: b["closed"] += 1)
	if not br.is_talking():
		return
	var i := br.line_index()
	b["lines"] = maxi(int(b["lines"]), i + 1)
	if not b["seen"].has(i):
		b["seen"][i] = f
	var since: int = f - int(b["seen"][i])
	if scenario == "intro_skip" and i >= 1:
		if since >= 20 and _pan_due(rig):
			br.skip_button.pressed.emit()
			b["skipped"] += 1
		return
	if not br.line_done():
		if i % 2 == 1 and since == 20:
			_tap_briefing(br)
			if br.line_done() and br.line_index() == i:
				b["finished"] += 1
			else:
				b["bad"] += " tap-on-line-%d-didn't-just-finish-it" % (i + 1)
		return
	if not b["full"].has(i):
		b["full"][i] = f
	if f - int(b["full"][i]) < 20:
		return  # (reading it)
	if i == br.line_count() - 1:
		if _pan_due(rig):
			_tap_briefing(br)
			if not br.is_closing():
				b["bad"] += " last-tap-didn't-close"
		return
	_tap_briefing(br)
	if br.line_index() == i + 1 and br.shown() == 0:
		b["advanced"] += 1
	else:
		b["bad"] += " tap-on-line-%d-didn't-show-the-next" % (i + 1)


## One tap on the briefing as a phone delivers it: the touch, and the click emulated from it.
func _tap_briefing(br: Briefing) -> void:
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.pressed = true
	touch.position = Vector2(135, 300)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = touch.position
	click.device = InputEvent.DEVICE_ID_EMULATION
	br._gui_input(touch)
	br._gui_input(click)


## Whether closing the briefing now starts the pan 2.3 s into CROSS's loop (mid gun check).
func _pan_due(rig: SoldierRig) -> bool:
	return absf(fposmod(rig._idle_t + Briefing.CLOSE_TIME, SoldierRig.IDLE_LOOP) - 2.3) < 0.03


## The alarm scenarios shoot alarm boxes only in their own areas (_alarm_in): tunnel_alarm and
## fire_closes the WING's (to lift the basement door, or shut the fire escape), roof_calm the
## ROOFTOPS', ground_alarms every one on its way.
func _may_shoot_alarm() -> bool:
	return _level._runner.current in _alarm_in


## A live rifleman ahead within shooting range (runner_escapes taps him instead of the runner).
func _rifleman_in_range() -> Node3D:
	var d := _player.distance_run()
	for c in _level._combatants:
		var n = c["node"]
		if n is RifleTrooper and c["seg"].get("promoted", false) and n.is_targetable(GameState.alert_level) \
				and n.at > d and n.at - d < _player.tuning.target_range:
			return n
	return null


## Will a searchlight's pool be on this lane when we reach it? (roof_spotted doesn't care.)
func _lit_ahead(lane: int, d: float) -> bool:
	if scenario == "roof_spotted":
		return false
	for l in _level._lights:
		var light: Searchlight = l["node"]
		if not is_instance_valid(light) or light.caught or not l["seg"].get("promoted", false):
			continue
		var ahead: float = light.at - d
		if ahead > -Searchlight.POOL_HALF_LENGTH and ahead < 14.0:
			var px := light.x_in(maxf(ahead, 0.0) / _player.tuning.run_speed)
			if absf(_player.lane_x(lane) - px) < Searchlight.POOL_RADIUS + 0.5:
				return true
	return false


## How many hits the boss on the pad takes on this setting (0 if none was built).
func _boss_hp() -> int:
	for b in _level._bosses:
		if is_instance_valid(b["node"]):
			return b["node"].max_health
	return 0


## The auto-save, as the run ends (`reason`, any ending): the progress and the route map must be on
## the device by now (the bot's own files), no temp file left, each just as the game holds it; and
## the progress's best time: on mission 1, getting out (each bot's first time out on its setting)
## sets it to the run's time; any other ending sets none. "ok", or "bad(what)".
func _check_saved(reason: StringName) -> String:
	var bad := PackedStringArray()
	var held := [Progress.to_data(), RunLog.save_data()]
	for i in 2:
		var p: String = _save_files[i]
		if not FileAccess.file_exists(p) or FileAccess.file_exists(p + SaveFile.TMP):
			bad.append("%s-not-written" % ["progress", "map"][i])
			continue
		if JSON.parse_string(FileAccess.get_file_as_string(p)) != JSON.parse_string(JSON.stringify(held[i])):
			bad.append("%s-differs" % ["progress", "map"][i])
	var best: Dictionary = held[0].get("best", {})
	var k := Progress.key(1, _level._graph.setting)
	if route == "mission_1" and reason == GameState.END_EXTRACTED:
		if not best.has(k) or absf(float(best[k]) - _level._clock.elapsed) > 0.001 or best.size() != 1:
			bad.append("best(%s)" % [best])
	elif not best.is_empty():
		bad.append("best-without-extraction(%s)" % [best])
	if RunLog.save_data()["missions"].is_empty():
		bad.append("map-empty")
	return "ok" if bad.is_empty() else "bad(%s)" % ",".join(bad)


func _remove_save_files() -> void:
	for p in _save_files:
		for f in [p, p + SaveFile.TMP]:
			if FileAccess.file_exists(f):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


## What the run opened in the mission select (Progress.record_extraction): RESULT's opened=, "-" for
## nothing.
func _opened() -> String:
	var now: Array = Progress.to_data()["unlocked"].filter(func(k: String) -> bool: return not k in _open_before)
	return ",".join(now) if not now.is_empty() else "-"
