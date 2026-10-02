extends Node3D
## Walking skeleton for the first playable: auto-run, swipes, lanes, obstacles,
## alert-gated branching that physically splits the road, run log, extraction and capture.
## Placeholder boxes throughout.
## Not built yet: enemies, FIRE, cover, alarm boxes, chopper timer, route map screen.
##
## The rules work in route space (distance along the route + lane), exactly as before.
## Only drawing is 3D. Each segment has its own frame (where it starts, which way it faces) and
## is a chain of straight "legs": a side branch turns out, then runs parallel to the main road,
## and a route heading for the end angles back to the centre line. Stairs and ladders climb at
## the start. The player and camera follow all of it.
##
## Straight on stays open until the split, so every open branch ahead is built in full and the
## one you don't take is thrown away when you commit. Branches closed by alert get a lockdown door.

const ROUTE_PATH := "res://game/levels/prototype_slice/route.json"
const START_ALERT := 1
const CEILING_Y := 4.6
## Scale (user: "doors should not be smaller than the player"). People here, the player and the
## guards, are about 1.95 m tall, and the world is built round them: a door is half a metre taller
## than a person, a zone door taller still. Every door uses these.
const DOOR_H := 2.5
const DOOR_W := 1.15
## The zone doors (double doors, the barred checkpoint gates, the warehouse shutter).
const GATE_H := 3.1
## A halfway marker's double doorway spans this many middle lanes.
const MARKER_LANES := 3
## Height of a stairwell's ceiling above the stairs.
const STAIR_HEADROOM := 2.9
## Lowest point of the live wires' drape: about head height, so you duck (slide) under them.
const WIRE_LOW := 1.85
## How far before a halfway marker the outer lanes are steered into its doorway.
const MARKER_FUNNEL := 8.0
## A roller shutter starts rolling up when you're this far (m) from it, so you run in underneath.
const SHUTTER_OPEN_AHEAD := 11.0
## Over the last this-many metres of the extraction area you're steered into the centre lane, so you
## always run straight into the chopper.
const CHOPPER_FUNNEL := 15.0
## How far behind you (m) the road and its obstacles are kept: the Alert 3 squad starts 25 m back.
const BEHIND_KEEP := 50.0

## Obstacle kinds: size, height off the ground, look, and how to get past it.
## "tex" names a PsxTextures function; without one the obstacle is flat "color".
const KINDS := {
	"barrier": {"size": Vector3(0.9, 0.5, 0.3), "y": 0.25, "tex": "hazard", "pass": "jump"},
	"pipe": {"size": Vector3(0.9, 0.3, 0.3), "y": 1.3, "tex": "rust_pipe", "pass": "slide"},
	"tripwire": {"size": Vector3(1.0, 0.05, 0.05), "y": 0.3, "color": Color("ff3030"), "pass": "jump_or_alert", "shadow": false},
	## Contextual cover (LOCKED): run into it and you take cover; swipe early to go round it.
	## Box cover: a metal or wood crate ("material" in route.json), one per lane. You crouch behind it.
	"box": {"size": Vector3(0.9, 1.2, 0.9), "y": 0.6, "tex": "crate_wood", "pass": "cover", "crouch": true},
	## Wall cover: floor to ceiling, one piece across 1-2 lanes. You stand behind it. It's solid:
	## what's behind it is a surprise, but never a trooper right behind it (route validation).
	"wall": {"size": Vector3(1.0, 4.0, 1.0), "y": 2.0, "tex": "cover_wall", "pass": "cover", "one_piece": true},
}

## How each area looks, picked by "theme" in route.json. Placeholder art, so you can tell where you are.
## Optional keys: "wall_tex" / "ceiling_tex" name a PsxTextures function (instead of a wall
## pattern); "skins" give this area its own look for obstacles, e.g. {"pipe": "duct"}; the
## gameplay (jump / slide / cover) never changes. "stair_wall" / "stair_door": how a stairwell looks
## where it opens into this area (every area should set its own).
const THEMES := {
	"compound": {"wall": "blocks", "color": Color("77776c"), "height": 3.0, "ground": "asphalt"},
	# MGS PS1-style complex / office interior.
	"office": {"wall": "office", "ambient": Color(0.19, 0.23, 0.26), "lamps": "ceiling", "fog_color": Color("10171a"),
			"wall_tex": "office_wall", "ceiling_tex": "office_ceiling", "stair_wall": "office_wall", "stair_door": "door", "color": Color("6f7a82"),
			"height": CEILING_Y, "ground": "office_floor", "ceiling": true, "wall_decor": true,
			"skins": {"barrier_looks": ["cabinet", "blockade"], "pipe": "wires", "box_look": "office",
					"wall": "office_wall"}},
	# Open night sky: no walls or ceiling, a low lip at the roof edge, the city all around.
	"rooftops": {"wall": "brick", "ambient": Color(0.2, 0.24, 0.36), "moon": Color(0.32, 0.38, 0.58), "lamps": "posts", "snow": true,
			"stair_wall": "roof_hut", "stair_door": "steel_door", "color": Color("6a4436"), "height": 1.2, "ground": "gravel", "no_walls": true,
			"lip": 0.35, "sky": true, "fog": 0.012, "fog_color": Color("121828"),
			"skins": {"barrier_looks": ["vent"], "pipe": "double_pipe", "box_look": "roof_vent",
					"wall_looks": ["hvac"]}},
	"tunnel": {"wall": "tile", "wall_tex": "tunnel_wall", "ceiling_tex": "tunnel_ceiling", "ambient": Color(0.19, 0.23, 0.2), "lamps": "bulbs", "fog_color": Color("0b100d"),
			"stair_wall": "tunnel_wall", "stair_door": "steel_door", "marker_door": "bars", "color": Color("4d5c52"), "height": CEILING_Y, "ground": "asphalt", "ceiling": true},
	# SECURITY WING (user reference): cold grey steel panels, big grey-green floor tiles with hazard
	# stripes across, CCTV monitor banks, wall cameras and keycard readers, a glass guard booth
	# with a red beacon, steel cabinets for cover, and a barred checkpoint gate for its zone door.
	"security": {"wall": "office", "wall_tex": "security_wall", "ceiling_tex": "office_ceiling", "ambient": Color(0.13, 0.17, 0.18),
			"lamps": "ceiling", "fog_color": Color("0d1315"), "stair_wall": "security_wall", "stair_door": "steel_door",
			"marker_door": "bars", "marker_light": Color(1.0, 0.16, 0.1), "color": Color("3e4447"), "height": CEILING_Y,
			"ground": "security_floor", "ceiling": true, "wall_decor": "security", "floor_stripes": true, "ceiling_vents": true,
			"skins": {"barrier_looks": ["turnstile"], "pipe": "wires", "box_look": "cabinets", "wall": "security_wall"}},
	# STAFF CANTEEN (user reference): warm yellow light, beige walls over a dark band, big pale floor
	# tiles; a kitchen alcove in the side wall (serving counter, sneeze guard, fridges, menu boards),
	# snack machines, notice boards, plants and bins along the walls; tables for box cover, toppled
	# chairs for barriers, and rows of drinks machines (red, blue, orange) for cover walls (user).
	"canteen": {"wall": "office", "wall_tex": "canteen_wall", "ceiling_tex": "office_ceiling", "ambient": Color(0.24, 0.21, 0.15),
			"lamps": "ceiling", "lamp_color": Color(1.0, 0.88, 0.6), "fog_color": Color("17140c"), "stair_wall": "canteen_wall",
			"stair_door": "door", "color": Color("3a3c3e"), "height": CEILING_Y, "ground": "canteen_floor", "ceiling": true,
			"wall_decor": "canteen", "ceiling_vents": true, "litter": true,
			"skins": {"barrier_looks": ["pizza"], "pipe": "bunting", "box_look": "table", "wall_looks": ["vending", "pillar"],
					"pillar": "canteen_pillar", "wall": "canteen_wall"}},
	# WAREHOUSE (user reference): a dark open roof with red cross beams and a hazard-striped crane
	# rail, dome lamps hanging on cables, tall pallet racking full of crates along both walls, a
	# concrete floor with yellow lines; crates, steel cases and drums on pallets for box cover,
	# stacked pallets to jump, a girder hanging on chains to duck under, crate stacks and
	# forklifts for cover walls.
	"warehouse": {"wall": "office", "wall_tex": "warehouse_wall", "ceiling_tex": "warehouse_ceiling", "ambient": Color(0.14, 0.16, 0.18),
			"lamps": "pendant", "fog_color": Color("0b0d0f"), "stair_wall": "warehouse_wall", "stair_door": "steel_door",
			"color": Color("2e3640"), "height": CEILING_Y, "ground": "warehouse_floor", "ceiling": true, "wall_decor": "warehouse",
			"floor_lines": true, "overhead": "crane", "exit_door": "shutter",
			"skins": {"barrier_looks": ["pallets"], "pipe": "girder", "box_look": "warehouse", "wall_looks": ["crate_stack", "forklift"],
					"wall": "warehouse_wall"}},
	# LOADING DOCK (user reference): grey concrete block walls, dark steel columns, red pipes along
	# the ceiling, hanging tube lights; loading bays in the side walls with their roll-up doors up and
	# a night yard outside (a trailer backed up, a lamp post, a fence, the city); hazard bands across
	# the floor; crates, cases and red drums for cover, bumper blocks to jump, a height bar on chains
	# to duck under, forklifts and crate stacks for cover walls.
	"dock": {"wall": "office", "wall_tex": "dock_wall", "ceiling_tex": "concrete", "ambient": Color(0.15, 0.17, 0.18),
			"lamps": "ceiling", "lamp_color": Color(0.85, 1.0, 0.92), "fog_color": Color("0c0f10"), "stair_wall": "dock_wall",
			"stair_door": "steel_door", "color": Color("30363a"), "height": CEILING_Y, "ground": "warehouse_floor", "ceiling": true,
			"wall_decor": "dock", "floor_stripes": true, "overhead": "pipes", "drum_color": Color("8a2418"),
			"skins": {"barrier_looks": ["bumper"], "pipe": "girder", "box_look": "warehouse", "wall_looks": ["forklift", "crate_stack"],
					"wall": "dock_wall"}},
	# MAIN FLOOR LOBBY (user reference): a tall two-storey atrium (a 9 m ceiling) with a mezzanine and
	# glass balustrades along both sides, a decorative grand staircase up one wall, dark granite,
	# the company logo lit on its wall, lifts, plants, sofas and a polished checker floor; the
	# reception desk across two lanes and planters / sofas for box cover, speed gates to jump,
	# a hanging banner to duck under, stone columns for cover walls.
	"lobby": {"wall": "office", "wall_tex": "lobby_wall", "ceiling_tex": "lobby_ceiling", "ceiling_y": 9.0, "ambient": Color(0.2, 0.2, 0.23),
			"lamps": "atrium", "fog_color": Color("100f12"), "stair_wall": "lobby_wall", "stair_door": "door", "color": Color("2a2c30"),
			"height": 9.0, "ground": "lobby_floor", "ceiling": true, "wall_decor": "lobby", "mezzanine": true,
			"skins": {"barrier_looks": ["speedgate"], "pipe": "banner", "box_look": "lobby", "wall": "lobby_column"}},
	"gate": {"wall": "blocks", "color": Color("8a8470"), "height": 4.0, "ground": "asphalt"},
	"helipad": {"wall": "blocks", "ambient": Color(0.22, 0.26, 0.38), "moon": Color(0.3, 0.36, 0.55), "lamps": "helipad", "snow": true,
			"color": Color("5c5c55"), "height": 0.6, "ground": "concrete"},
}
## The light out in an outdoor stretch of an indoor area (the LOADING DOCK's yard): night sky.
const OUTDOOR_LIGHT := {"ambient": Color(0.24, 0.27, 0.36), "moon": Color(0.34, 0.4, 0.6), "fog": 0.016, "fog_color": Color("121828")}
const DEAD_END_COLOR := Color("b03a2e")
## Render layer for stairwell structure (see _build_stairwell). Everything else is on layer 1.
const STAIRWELL_LAYER := 2
## Collision layer for things you can't see or shoot through (see _sees()).
const SIGHT_LAYER := 16
const GUARD_COLOR := Color("4a5260")
## Light in an area with no "ambient" of its own.
const DEFAULT_AMBIENT := Color(0.4, 0.42, 0.44)
## Where the moonlight comes from (upper left, a little behind).
const MOON_DIR := Vector3(-0.45, 1.0, 0.35)

@export var tuning: Tuning

## Retry skips the title card so the loop stays fast.
static var _skip_title := false

var _started := false
var _graph: RouteGraph
var _obstacles: Array[Dictionary] = []
## Segments along the path taken, in order. Each one:
##   {id, node, start, end, length, dy, ramp_len, edge, legs: [{start, xf}],
##    branches: {key: segment}, locked: {key: Node3D}}
var _segments: Array[Dictionary] = []
## The segment the player is on, whose split is still ahead.
var _current: Dictionary = {}
## Troopers and alarm boxes: {node: RifleTrooper|AlarmBox, owner: segment node, seg: segment}.
var _combatants: Array[Dictionary] = []
## Roof searchlights: {node: Searchlight, owner: segment node, seg: segment}.
var _lights: Array[Dictionary] = []
var _fire_held := false
var _fire_cooldown := 0.0
## HYBRID / TAP_TO_TARGET: the enemy the player last tapped.
var _tapped: Node3D = null
var _shot_tracer: MeshInstance3D
var _clock: ExtractionClock
## How far the camera follows the player across the road (0.6 normally, 1.0 beside a wall).
var _camera_follow := 0.6
var _sky: Node3D
var _env: Environment
var _fog_default := 0.045
## Branches not taken, kept as scenery until the player passes: {node, gone_at}.
var _retired: Array[Dictionary] = []
## Was the camera on a stairwell's security camera last frame? (So leaving it is a hard cut back.)
var _was_cctv := false
var _fog_color_default := Color(0.16, 0.17, 0.15)
## The opening camera pan: seconds left (0 once it's over or skipped).
var _intro_left := 0.0
## Doors you burst through (the start room and every stairwell): {node, at, owner, seg}. Each
## bursts open when you reach it, but only on the route you're actually on.
var _doors: Array[Dictionary] = []
## Halfway markers built so far: {at (route distance), seg}. See _build_marker.
var _markers: Array[Dictionary] = []
## Cover walls, in route space: {at, x0, x1, seg, owner}. Used to find the wall you're in cover
## behind, so you lean round its edge (line of sight itself is real rays: see _sees()).
var _blockers: Array[Dictionary] = []
## Mood lighting: the lamps, the area's ambient and moonlight (see Ambience).
var _ambience: Ambience
## All the sound (see AudioDirector).
var _audio: AudioDirector
## The menus (main menu, settings, pause, end screens).
var _frontend: Frontend
## The main menu is up (the camera sways slowly in front of you; no input reaches the game).
var _menu_open := false
var _menu_t := 0.0
## SCREEN SHAKE setting.
var _shake_on := true
## The swipe distance before the SWIPE setting scales it.
var _swipe_base := 0.0
## Footsteps: metres run since the last one; whether you were in the air last frame.
var _stride_left := 0.0
var _was_airborne := false
var _last_alert := START_ALERT
## Snow drifting round the camera on the night rooftops.
var _snow: CPUParticles3D
## Red aviation lights on the city's towers, all blinking together.
var _beacon_mat: StandardMaterial3D
## The last area name captioned, so ROOFTOPS into ROOFTOPS doesn't caption twice.
var _last_area := ""
## Camera jolt after the door bash (1 at impact, decays to 0).
var _shake := 0.0
## Where the camera would be without any shake (the smoothed follow position).
var _cam_base := Transform3D.IDENTITY
## Obstacles can't trip you again until this game time (seconds into the run), after a stumble.
var _stumble_grace_until := -1.0
## The Alert 3 pursuit squad: its guards (chasing, down, or falling back), whether one is out for
## this spell at Alert 3, and the rear-view CCTV camera that watches them.
var _squad: Array[PursuitGuard] = []
var _squad_on := false
var _squad_caught := false
var _squad_shaken := false
var _rear_vp: SubViewport
var _rear_cam: Camera3D

@onready var _player: Player = $Player
@onready var _camera: Camera3D = $Camera3D
@onready var _input: SwipeInput = $SwipeInput
@onready var _runner: RouteRunner = $RouteRunner
@onready var _hud: Hud = $Hud
@onready var _world: Node3D = $World


func _ready() -> void:
	Engine.time_scale = 1.0
	_graph = RouteGraph.from_json_file(ROUTE_PATH)
	for problem in _graph.validate():
		push_error("route.json: " + problem)

	_input.swiped.connect(_on_swipe)
	_input.tapped.connect(_on_tap)
	_input.fire_pressed.connect(_on_fire)
	_input.fire_released.connect(set_fire_held.bind(false))
	_hud.setup(tuning)
	_frontend = Frontend.new()
	_frontend.name = "Frontend"
	add_child(_frontend)
	_frontend.mission_title = String(RouteGraph.from_json_file(ROUTE_PATH).mission().get("title", "MISSION 1"))
	_frontend.start_requested.connect(_begin_intro)
	_frontend.resume_requested.connect(_resume)
	_frontend.retry_requested.connect(func() -> void:
		get_tree().paused = false
		_retry())
	_frontend.menu_requested.connect(func() -> void:
		get_tree().paused = false
		_skip_title = false
		get_tree().reload_current_scene())
	_hud.pause_pressed.connect(_pause)
	_build_sky()
	_ambience = Ambience.new()
	_ambience.name = "Ambience"
	_ambience.tuning = tuning
	add_child(_ambience)
	_audio = AudioDirector.new()
	_audio.name = "Audio"
	_audio.tuning = tuning
	add_child(_audio)
	_audio.set_world(_world)
	_build_snow()
	# A faint cool fill from just behind you, so you (and what's right ahead) read in the dark.
	var fill := Node3D.new()
	_camera.add_child(fill)
	fill.position = Vector3(0, 0.3, -1.5)
	_ambience.add_lamp(fill, Color(0.5, 0.58, 0.68) * 0.55, 6.5, {"alert": false})
	_clock = ExtractionClock.new()
	_clock.name = "ExtractionClock"
	_clock.tuning = tuning
	add_child(_clock)
	_clock.configure(_graph.mission().get("chopper", {}))  # this mission's own timeline, if it has one
	_clock.stage_changed.connect(_on_chopper_stage)
	_shot_tracer = _box(self, Vector3(0.05, 0.05, 1.0), Vector3.ZERO, Color("fff0b0"))
	_shot_tracer.material_override = PsxMaterials.glow(Color("fff0b0"))
	_shot_tracer.top_level = true
	_shot_tracer.visible = false
	_runner.segment_needed.connect(_on_segment_needed)
	_runner.junction_approaching.connect(_on_junction_approaching)
	_runner.junction_cleared.connect(_on_junction_cleared)
	_runner.mission_end_reached.connect(_on_mission_end)
	_runner.dead_end_reached.connect(_end.bind(&"dead_end"))
	_runner.capture_reached.connect(_on_capture_reached)
	_runner.node_entered.connect(_on_node_entered)
	GameState.run_ended.connect(_on_run_ended)
	GameState.alert_changed.connect(_on_alert_changed.unbind(1))

	_promote(_make_segment(_graph.start_id, 0.0, {}, Transform3D.IDENTITY))
	# The mission starts in an office room behind a closed door into the first area.
	_build_start_room(_segments[0])
	_player.distance = -tuning.start_offset
	_place_player()
	_update_environment(0.0)
	_ambience.snap()  # start in the area's own light, not fading in from bright
	if _skip_title:
		_update_camera(1.0)
		start_run()
	else:
		# The main menu, over the camera swaying slowly in front of you, with the theme playing.
		_menu_open = true
		_frontend.show_main()
		_hud.set_playing(false)
		_hud.set_letterbox(true)
		_audio.play_menu_music()
		_update_camera(1.0)
	_frontend.clicked.connect(func() -> void: _audio.play("tick", -2.0, 0.0, "UI"))
	Settings.changed.connect(_apply_settings)
	_apply_settings()


## START MISSION: the menu goes, and the opening pan plays round to behind you with the mission
## title; when it ends, the run starts (the door bash). A tap during the pan skips it.
func _begin_intro() -> void:
	_menu_open = false
	_frontend.hide_all()
	_intro_left = tuning.intro_pan_time
	_hud.show_mission_title(String(_graph.mission().get("title", "")))


func _pause() -> void:
	if not GameState.run_active or get_tree().paused:
		return
	set_fire_held(false)
	get_tree().paused = true
	_frontend.show_pause()


func _resume() -> void:
	_frontend.hide_all()
	get_tree().paused = false


## The player's settings (see the Settings autoload), applied now and whenever they change.
func _apply_settings() -> void:
	match String(Settings.get_value("aim")):
		"auto":
			tuning.targeting_mode = Tuning.TargetingMode.AUTO_PRIORITY
		"tap":
			tuning.targeting_mode = Tuning.TargetingMode.TAP_TO_TARGET
		_:
			tuning.targeting_mode = Tuning.TargetingMode.HYBRID
	tuning.fire_on_left = String(Settings.get_value("fire_side")) == "left"
	if _swipe_base <= 0.0:
		_swipe_base = tuning.swipe_min_fraction
	tuning.swipe_min_fraction = _swipe_base * {"low": 1.4, "medium": 1.0, "high": 0.7}.get(String(Settings.get_value("swipe")), 1.0)
	_ambience.brightness_scale = float(Settings.get_value("brightness")) / 100.0
	_shake_on = bool(Settings.get_value("screen_shake"))
	_hud.set_retro_filter(bool(Settings.get_value("retro_filter")))
	_hud.redraw_fire()


## How far through the mission you are, 0 to 1: the distance run, against the distance run plus
## the shortest way on from here to the chopper.
func _progress() -> float:
	return _progress_at(_player.distance_run())


## The same, for a point `at` on the road behind you (the squad): measured against your way on,
## so it sits on the rail just below you.
func _progress_at(at: float) -> float:
	var d := maxf(0.0, _player.distance_run())
	if _segments.is_empty():
		return 0.0
	var seg := _segment_at(d)
	var left := maxf(0.0, float(seg["end"]) - d) + _graph.shortest_after(seg["id"])
	return maxf(0.0, at) / maxf(d + left, 1.0)


## The squad's lead guard on the progress rail, while any of them are still chasing.
func _squad_progress() -> float:
	if _squad_caught:
		return -1.0
	var lead := -INF
	for g in _squad:
		if is_instance_valid(g) and g.is_chasing():
			lead = maxf(lead, g.at)
	return _progress_at(lead) if lead > -INF else -1.0


func start_run() -> void:
	if _started:
		return
	_started = true
	_menu_open = false
	_frontend.hide_all()
	_intro_left = 0.0  # a tap during the pan skips it
	_hud.hide_title()
	_hud.set_playing(true)
	_audio.stop_menu_music(1.5)
	_audio.play("codec", -4.0, 0.0, "UI")
	_hud.set_letterbox(false, tuning.letterbox_time)
	GameState.start_run(START_ALERT)
	_runner.begin(_graph, false)
	_clock.start()


func _physics_process(delta: float) -> void:
	if _intro_left > 0.0:
		_intro_left -= delta
		if _intro_left <= 0.0 and not _started:
			start_run()  # the pan has ended behind the player: go
	if GameState.run_active:
		for door in _doors:
			var reach := SHUTTER_OPEN_AHEAD if door.get("shutter", false) else 0.9
			if not door.get("done", false) and _player.distance_run() >= door["at"] - reach and door["seg"].get("promoted", false):
				door["done"] = true
				if door.get("shutter", false):
					_raise_shutter(door["node"])
				else:
					_bash_door(door["node"], door.get("swing", 1.0))
				if door.has("sound"):
					_audio.play(door["sound"], 0.0, 0.05)
		_funnel_to_markers()
		_update_footsteps(delta)
		_runner.update(_player.distance_run(), _player.lane)
		_check_obstacles()
		_update_combat(delta)
		if GameState.run_active:
			_update_squad(delta)
		if GameState.run_active:
			_update_searchlights(delta)
		_despawn_behind()
	_place_player()
	_update_camera(delta)
	_update_rear_camera()
	_update_environment(delta)
	_hud.show_clock(_clock.fraction(), _clock.lift_fraction())
	_hud.show_progress(_progress())
	_hud.show_squad_progress(_squad_progress())


## The night sky and the far city skyline, centred on the camera so they always stay far away.
## Only seen where there's no ceiling or walls in the way (the rooftops, the helipad).
func _build_sky() -> void:
	_sky = Node3D.new()
	_sky.name = "Sky"
	add_child(_sky)
	var dome := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 140.0
	sphere.height = 280.0
	sphere.radial_segments = 16
	sphere.rings = 8
	dome.mesh = sphere
	var sky_mat := StandardMaterial3D.new()
	sky_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sky_mat.cull_mode = BaseMaterial3D.CULL_FRONT  # we're inside it
	sky_mat.disable_fog = true
	sky_mat.albedo_texture = PsxTextures.night_sky()
	sky_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	dome.material_override = sky_mat
	_sky.add_child(dome)
	var ring := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 120.0
	cyl.bottom_radius = 120.0
	cyl.height = 40.0
	cyl.radial_segments = 24
	cyl.cap_top = false
	cyl.cap_bottom = false
	ring.mesh = cyl
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	ring_mat.disable_fog = true
	ring_mat.albedo_texture = PsxTextures.skyline()
	ring_mat.uv1_scale = Vector3(6, 1, 1)
	ring_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	ring.material_override = ring_mat
	ring.position.y = -8.0  # the skyline's tops sit a little above eye level
	_sky.add_child(ring)
	# Below the skyline, the dark city carries on all the way down: no bottom edge to see.
	var base := MeshInstance3D.new()
	var base_cyl := CylinderMesh.new()
	base_cyl.top_radius = 119.0
	base_cyl.bottom_radius = 119.0
	base_cyl.height = 120.0
	base_cyl.radial_segments = 24
	base_cyl.cap_top = false
	base.mesh = base_cyl
	var base_mat := StandardMaterial3D.new()
	base_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	base_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	base_mat.disable_fog = true
	base_mat.albedo_color = Color("080a10")
	base.material_override = base_mat
	base.position.y = -8.0 - 20.0 - 60.0 + 2.0  # its top tucks just inside the skyline's lower edge
	_sky.add_child(base)
	_camera.far = 170.0
	_env = $WorldEnvironment.environment
	_fog_default = _env.fog_density
	_fog_color_default = _env.fog_light_color


## Snow drifting down round the camera (the night rooftops; Shadow Moses). The flakes stay put in
## the world while the emitter follows the camera, so you run through them.
func _build_snow() -> void:
	_snow = CPUParticles3D.new()
	_snow.name = "Snow"
	_snow.local_coords = false
	_snow.amount = 260
	_snow.lifetime = 4.0
	_snow.preprocess = 4.0
	_snow.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_snow.emission_box_extents = Vector3(9.0, 1.0, 12.0)
	_snow.direction = Vector3(0.3, -1.0, 0.0)
	_snow.spread = 12.0
	_snow.gravity = Vector3(0.2, -1.2, 0.0)
	_snow.initial_velocity_min = 0.8
	_snow.initial_velocity_max = 1.6
	var flake := QuadMesh.new()
	flake.size = Vector2(0.06, 0.06)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_color = Color("c8d4e8")
	flake.material = mat
	_snow.mesh = flake
	_snow.emitting = false
	add_child(_snow)
	_beacon_mat = StandardMaterial3D.new()
	_beacon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beacon_mat.disable_fog = true
	_beacon_mat.albedo_color = Color("ff3020")


## Fog thins out where there's open sky (so you can see the city), and closes in again indoors.
func _update_environment(delta: float) -> void:
	if _env == null:
		return
	var seg := _segment_at(_player.distance_run())
	var theme := _theme(seg["id"]) if _player.distance_run() >= 0.0 else THEMES["office"]
	if _is_outdoor(seg, _player.distance_run() - seg["start"] + 2.0):
		theme = theme.merged(OUTDOOR_LIGHT, true)  # out in the dock's yard: moonlight, thinner fog
	var fog: float = theme.get("fog", _fog_default)
	var fog_color: Color = theme.get("fog_color", _fog_color_default)
	var k := clampf(delta * 1.5, 0.0, 1.0)
	_env.fog_density = lerpf(_env.fog_density, fog, k)
	_env.fog_light_color = _env.fog_light_color.lerp(fog_color, k)
	# In a stairwell the view is the stairwell's security camera.
	var seg_here := _segment_at(_player.distance_run())
	_hud.set_cctv(in_stairwell(), "CAM %02d" % (absi(hash(seg_here["id"])) % 40 + 1), _clock.elapsed)
	_audio.set_cctv(in_stairwell())
	_audio.set_area(String(_graph.node_data(seg_here["id"]).get("theme", "office")) if _player.distance_run() >= 0.0 else "office")
	_sky.global_position = _camera.global_position
	# Mood lighting: the area's own ambient and moonlight, and the lamps nearest where you look.
	_ambience.set_area(theme.get("ambient", DEFAULT_AMBIENT), theme.get("moon", Color.BLACK), MOON_DIR)
	var focus := _camera.global_position - _camera.global_basis.z * 8.0
	_ambience.update(delta, focus, GameState.alert_level if GameState.run_active else START_ALERT)
	var edges := _ambience.screen_alert()
	_hud.set_grade(edges.x, edges.y)
	_snow.emitting = theme.get("snow", false)
	_snow.visible = not in_stairwell()  # it follows the camera: none inside, in front of the security camera
	_snow.global_position = _camera.global_position - _camera.global_basis.z * 6.0 + Vector3(0, 5.0, 0)
	if _beacon_mat:
		_beacon_mat.albedo_color = Color("ff3020") if fmod(Time.get_ticks_msec() / 1000.0, 1.6) < 0.5 else Color("401010")


## The chopper's stages: a message under the clock, the helicopter lifting, and THE CHOPPER LEFT.
func _on_chopper_stage(stage: ExtractionClock.Stage) -> void:
	RunLog.record_event("chopper", {"stage": ExtractionClock.MESSAGES[stage]})
	match stage:
		ExtractionClock.Stage.INBOUND:
			_audio.play("squelch", -4.0, 0.0, "UI")
			_hud.show_chopper_message(ExtractionClock.MESSAGES[stage], Color("f0e8c8"), tuning.chopper_message_time, false)
		ExtractionClock.Stage.LANDED:
			_audio.play("squelch", -4.0, 0.0, "UI")
			_hud.show_chopper_message(ExtractionClock.MESSAGES[stage], Color("9fd36b"), tuning.chopper_message_time, false)
		ExtractionClock.Stage.LIFTING_OFF:
			_warn_lift_off()
			_hud.show_chopper_message(ExtractionClock.MESSAGES[stage], Color("ff4b3a"), 0.0, true)
			for c in get_tree().get_nodes_in_group("chopper"):
				c.create_tween().tween_property(c, "position:y", c.position.y + 2.5,
						_clock.gone_at - _clock.lifts_at)
		ExtractionClock.Stage.GONE:
			for c in get_tree().get_nodes_in_group("chopper"):
				c.visible = false
			_end(GameState.END_CHOPPER_LEFT)


# --- Route frames -------------------------------------------------------------------
# A segment's node sits where the segment starts, facing along it (-Z). Its legs are straight
# pieces, each with a transform in the segment node's space. A point `into` metres along the
# segment and `x` across is at leg.xf * (x, y + height(into), -(into - leg.start)).

## Height above the segment's start, `into` metres along it (stairs and ladders climb at the start).
static func _height(seg: Dictionary, into: float) -> float:
	if seg["ramp_len"] <= 0.0:
		return seg["dy"]
	return seg["dy"] * clampf(into / seg["ramp_len"], 0.0, 1.0)


static func _leg_index(seg: Dictionary, into: float) -> int:
	var legs: Array = seg["legs"]
	for i in range(legs.size() - 1, -1, -1):
		if legs[i]["start"] <= into:
			return i
	return 0


## The frame on the centre line `into` metres along, in leg `i` (segment node space).
static func _frame_in_leg(seg: Dictionary, i: int, into: float) -> Transform3D:
	var leg: Dictionary = seg["legs"][i]
	var xf: Transform3D = leg["xf"]
	return Transform3D(xf.basis, xf * Vector3(0, _height(seg, into), -(into - leg["start"])))


static func _frame_at(seg: Dictionary, into: float) -> Transform3D:
	return _frame_in_leg(seg, _leg_index(seg, into), into)


static func _turns(edge: Dictionary) -> bool:
	return RouteGraph.side_of(edge) != "straight" and RouteGraph.via_of(edge) != "ladder"


static func _key(edge: Dictionary) -> String:
	return "%s:%s" % [RouteGraph.side_of(edge), edge.get("to", "")]


func _turn_angle() -> float:
	return deg_to_rad(tuning.fork_turn_degrees)


## For a side exit: the outer lane you leave the main road from, and the branch lane it becomes.
## The branch sits beside the main road, overlapping only that outer lane, so your outer lane
## becomes the branch lane nearest the main road (right exit: lane 4 -> branch lane 0).
func _handover_lanes(edge: Dictionary) -> Vector2i:
	var last := tuning.lane_count - 1
	return Vector2i(0, last) if RouteGraph.side_of(edge) == "left" else Vector2i(last, 0)


## Where a segment reached by `edge` from `prev` starts (world space), and which way it faces.
## A side exit turns toward its side, pivoting on the outer lane so a player there doesn't jump.
func _frame_after(prev: Dictionary, edge: Dictionary) -> Transform3D:
	var t: Transform3D = prev["node"].transform * _frame_in_leg(prev, prev["legs"].size() - 1, prev["length"])
	var from_x := 0.0
	var to_x := 0.0
	var yaw := 0.0
	if _turns(edge):
		var lanes := _handover_lanes(edge)
		from_x = _player.lane_x(lanes.x)
		to_x = _player.lane_x(lanes.y)
		yaw = _turn_angle() * (1.0 if RouteGraph.side_of(edge) == "left" else -1.0)
	var basis := t.basis.rotated(Vector3.UP, yaw)
	return Transform3D(basis, t * Vector3(from_x, 0, 0) - basis * Vector3(to_x, 0, 0))


## The legs of a segment starting at world transform `xf`: turn out, run parallel, head back to centre.
func _plan_legs(seg: Dictionary, xf: Transform3D) -> Array[Dictionary]:
	var length: float = seg["length"]
	var angle := _turn_angle()
	var legs: Array[Dictionary] = [{"start": 0.0, "xf": Transform3D.IDENTITY}]
	var at := 0.0
	var local := Transform3D.IDENTITY
	if _turns(seg["edge"]) and angle > 0.01:
		# Out at the turn angle, then straighten up parallel to the road you left.
		at = minf(tuning.branch_out_length, length * 0.5)
		var yaw := angle * (-1.0 if RouteGraph.side_of(seg["edge"]) == "left" else 1.0)
		local = Transform3D(local.basis.rotated(Vector3.UP, yaw), local * Vector3(0, 0, -at))
		legs.append({"start": at, "xf": local})
	# Authored bends: the same shape with no choice. Out to one side, then straight again.
	if angle > 0.01:
		for bend: Dictionary in _graph.node_data(seg["id"]).get("bends", []):
			var b := float(bend["at"])
			var out := tuning.branch_out_length
			if b < at or b + out > length:
				push_warning("%s: bend at %s m doesn't fit" % [seg["id"], b])
				continue
			var yaw := angle * (1.0 if String(bend.get("side", "left")) == "left" else -1.0)
			var turned := Transform3D(local.basis.rotated(Vector3.UP, yaw), local * Vector3(0, 0, -(b - at)))
			legs.append({"start": b, "xf": turned})
			local = Transform3D(local.basis, turned * Vector3(0, 0, -out))
			legs.append({"start": b + out, "xf": local})
			at = b + out
	if _heads_for_end(seg["id"]) and angle > 0.01:
		# Angle back to the centre line (world x = 0), then run straight into the end.
		var offset := (xf * local * Vector3(0, 0, -(length - at))).x
		var room := length - at - tuning.converge_tail - 2.0
		var run := minf(absf(offset) / sin(angle), room)
		if absf(offset) > 0.5 and run > 3.0:
			var bend_at := length - tuning.converge_tail - run
			var yaw := angle * signf(offset)  # positive yaw heads toward -x
			var p := local * Vector3(0, 0, -(bend_at - at))
			var bent := Transform3D(local.basis.rotated(Vector3.UP, yaw), p)
			legs.append({"start": bend_at, "xf": bent})
			var q := bent * Vector3(0, 0, -run)
			legs.append({"start": bend_at + run, "xf": Transform3D(local.basis, q)})
	return legs


## True if any exit from this node leads to the end of the level.
func _heads_for_end(id: StringName) -> bool:
	for edge in _graph.all_next(id):
		if _graph.end_type(StringName(edge["to"])) != "":
			return true
	return false


## The shape of a segment: how far it climbs, over how long, and how it was reached.
func _segment_shape(id: StringName, edge: Dictionary, from_id: StringName) -> Dictionary:
	var dy := 0.0
	var ramp_len := 0.0
	if not edge.is_empty():
		dy = (_graph.tier_of(id) - _graph.tier_of(from_id)) * tuning.tier_height
		if dy != 0.0:
			ramp_len = tuning.ladder_length if RouteGraph.via_of(edge) == "ladder" else absf(dy) * tuning.stairs_run
	return {"id": id, "from_id": from_id, "length": _graph.length_of(id), "dy": dy, "ramp_len": ramp_len, "edge": edge,
			"branches": {}, "locked": {}}


func _segment_at(distance: float) -> Dictionary:
	for i in range(_segments.size() - 1, -1, -1):
		if _segments[i]["start"] <= distance:
			return _segments[i]
	return _segments[0]


func _place_player() -> void:
	var seg := _segment_at(_player.distance_run())
	var into: float = _player.distance_run() - seg["start"]
	var f: Transform3D = seg["node"].global_transform * _frame_at(seg, into)
	_player.global_transform = Transform3D(f.basis, f * Vector3(_player.track_x, 0, 0))


# --- Segments and branches ----------------------------------------------------------

## Builds a whole segment (road, walls, obstacles...) starting at world transform xf.
func _make_segment(id: StringName, start: float, edge: Dictionary, xf: Transform3D, from_id: StringName = &"") -> Dictionary:
	var seg := _segment_shape(id, edge, from_id if from_id != &"" else id)
	seg["start"] = start
	seg["end"] = start + seg["length"]
	seg["legs"] = _plan_legs(seg, xf)
	var node := Node3D.new()
	node.name = String(id)
	_world.add_child(node)
	node.transform = xf
	seg["node"] = node

	var length: float = seg["length"]
	var road_end := length
	if _is_authored_fork(id):
		road_end = maxf(seg["ramp_len"], length - tuning.decision_lead - tuning.fork_cue_length)
	_build_surfaces(node, seg, road_end, 0.0, 0.0)
	if _theme(id).get("sky", false):
		_build_city(node, seg)
	_build_lamps(node, seg)

	var authored_lanes := 5
	var jumps_seen := 0  # jump obstacles alternate through the area's looks
	var walls_seen := 0  # so do walls
	for ob: Dictionary in _graph.node_data(id).get("obstacles", []):
		var kind: Dictionary = KINDS.get(ob["kind"], {})
		if kind.is_empty():
			push_warning("Unknown obstacle kind '%s' in %s" % [ob["kind"], id])
			continue
		var lanes := {}
		for l in ob.get("lanes", []):
			lanes[_remap_lane(int(l), authored_lanes)] = true
		var at := float(ob["at"])
		var size: Vector3 = kind["size"] * Vector3(tuning.lane_width, 1, 1)
		var y: float = kind["y"]
		# Each area has its own look for the same gameplay (THEMES "skins"); "look" in route.json
		# overrides it for one obstacle (e.g. the odd small pipe on the main floor).
		var tex_name: String = _skin(id, ob["kind"], kind.get("tex", ""))
		var jump_look := ""
		if ob["kind"] == "barrier":
			var looks: Array = _theme(id).get("skins", {}).get("barrier_looks", [])
			jump_look = ob.get("look", looks[jumps_seen % looks.size()] if not looks.is_empty() else "")
			jumps_seen += 1
			if jump_look == "cabinet":
				tex_name = "cabinet"
		if ob["kind"] == "box":
			var metal := String(ob.get("material", "wood")) == "metal"
			tex_name = _skin(id, "box_metal", "crate_metal") if metal else _skin(id, "box_wood", "crate_wood")
			if ob.has("look"):  # e.g. the odd wooden crate among the office furniture
				tex_name = {"crate": "crate_wood", "desk": "desk", "cabinet": "cabinet"}.get(ob["look"], tex_name)
		var span_look: String = ob.get("look", _skin(id, ob["kind"], ob["kind"]))
		if ob["kind"] == "wall":
			# Floor to ceiling: up to the ceiling indoors, a tall column outside.
			size.y = _ceil(id) if _theme(id).get("ceiling", false) else kind["size"].y
			y = size.y / 2.0
		var one_piece: Node3D = null
		if ob["kind"] in ["pipe", "tripwire"]:
			# Built per run of neighbouring lanes, anchored to a wall, the floor or the ceiling.
			one_piece = _build_spans(node, seg, span_look if ob["kind"] == "pipe" else "tripwire", lanes.keys(), at, y)
		elif kind.get("one_piece", false):
			var sorted: Array = lanes.keys()
			sorted.sort()
			var x0 := _player.lane_x(sorted[0]) - tuning.lane_width / 2.0 + 0.05
			var x1 := _player.lane_x(sorted[-1]) + tuning.lane_width / 2.0 - 0.05
			# A wall in an edge lane runs right into the side wall: no gap down the side (user rule).
			var side_wall := tuning.lane_count * tuning.lane_width / 2.0 + 1.0
			if sorted[0] == 0:
				x0 = -side_wall
			if sorted[-1] == tuning.lane_count - 1:
				x1 = side_wall
			var wall_looks: Array = _theme(id).get("skins", {}).get("wall_looks", [])
			if String(ob.get("look", "")) == "booth":
				# The SECURITY WING's guard booth: cover like a wall, but a 3 m deep glass booth.
				one_piece = _build_booth(node, seg, at, x0, x1)
				_solid_box(node, _frame_at(seg, at) * Transform3D(Basis.IDENTITY, Vector3((x0 + x1) / 2.0, CEILING_Y / 2.0, -1.0)),
						Vector3(x1 - x0, CEILING_Y, 3.0))  # you can't see or shoot through it
			elif not wall_looks.is_empty() and String(wall_looks[walls_seen % wall_looks.size()]) in ["crate_stack", "forklift"]:
				# The WAREHOUSE: a stack of crates, or a forklift with its load up.
				one_piece = _build_warehouse_wall(node, seg, at, x0, x1, wall_looks[walls_seen % wall_looks.size()])
				walls_seen += 1
				_solid_box(node, _frame_at(seg, at) * Transform3D(Basis.IDENTITY, Vector3((x0 + x1) / 2.0, 1.5, 0)),
						Vector3(x1 - x0, 3.0, 1.0))  # you can't see or shoot through it
			elif not wall_looks.is_empty() and String(wall_looks[walls_seen % wall_looks.size()]) == "vending":
				# The STAFF CANTEEN: a row of drinks machines (user).
				one_piece = _build_vending_wall(node, seg, at, x0, x1)
				walls_seen += 1
				_solid_box(node, _frame_at(seg, at) * Transform3D(Basis.IDENTITY, Vector3((x0 + x1) / 2.0, 1.15, 0)),
						Vector3(x1 - x0, 2.3, 1.0))  # you can't see or shoot through them
			elif not wall_looks.is_empty() and String(wall_looks[walls_seen % wall_looks.size()]) != "pillar":
				# Outdoors with no walls to lean on: an electrical cabinet or a stack of open vent pipes.
				one_piece = _build_roof_wall(node, seg, at, x0, x1, wall_looks[walls_seen % wall_looks.size()])
				walls_seen += 1
				_solid_box(node, _frame_at(seg, at) * Transform3D(Basis.IDENTITY, Vector3((x0 + x1) / 2.0, 1.3, 0)),
						Vector3(x1 - x0, 2.6, 1.0))  # you can't see or shoot through it
			else:
				if not wall_looks.is_empty():
					walls_seen += 1  # a plain wall ("pillar") in a rotation of looks
					tex_name = _skin(id, "pillar", tex_name)
				var w := _item_box(node, seg, at, Vector3((x0 + x1) / 2.0, y, 0), Vector3(x1 - x0, size.y, size.z), Color.WHITE)
				w.material_override = PsxMaterials.textured(_obstacle_texture(tex_name), Vector2(3, 2))
				_make_solid(w)
				one_piece = w
			# Solid: shots don't go through it, only round its edge (see Sightlines).
			_blockers.append({"at": start + at, "x0": x0, "x1": x1, "seg": seg, "owner": node})
		var box_look: String = ob.get("look", _skin(id, "box_look", "")) if ob["kind"] == "box" else ""
		var reception: Node3D = null
		for lane: int in lanes:
			var x := _player.lane_x(lane)
			var mesh: Node3D = one_piece
			if jump_look == "cabinet":
				_scatter_papers(node, seg, at, x, lane)
			if jump_look == "speedgate":
				mesh = _build_speedgate(node, seg, at, x, lane)
			elif jump_look == "bumper":
				mesh = _build_bumper(node, seg, at, x, lane)
			elif jump_look == "pallets":
				mesh = _build_pallet_stack(node, seg, at, x, lane)
			elif jump_look in ["pizza", "chairs"]:
				mesh = _build_canteen_jump(node, seg, at, x, lane, jump_look)
			elif jump_look == "turnstile":
				mesh = _build_turnstile(node, seg, at, x, lane)
			elif jump_look == "blockade":
				mesh = _build_blockade(node, seg, at, x, lane)
			elif jump_look == "vent":
				mesh = _build_vent_shaft(node, seg, at, x)
			elif box_look == "reception":
				# One desk across the whole run of lanes, built once (user: across two lanes).
				if lane == lanes.keys().min():
					var run: Array = lanes.keys()
					reception = _build_reception(node, seg, at, _player.lane_x(run.min()) - tuning.lane_width / 2.0 + 0.05,
							_player.lane_x(run.max()) + tuning.lane_width / 2.0 - 0.05)
				mesh = reception
			elif box_look in ["office", "cabinets"]:
				mesh = _build_office_box(node, seg, at, x, lane, box_look == "cabinets" or String(ob.get("material", "wood")) == "metal")
			elif box_look == "lobby":
				mesh = _build_lobby_box(node, seg, at, x, lane, String(ob.get("material", "wood")) == "metal")
			elif box_look == "warehouse":
				mesh = _build_warehouse_box(node, seg, at, x, lane, String(ob.get("material", "wood")) == "metal")
			elif box_look == "table":
				# One long table across the whole run of lanes, built once (user: two lanes wide).
				if lane == lanes.keys().min():
					var trun: Array = lanes.keys()
					reception = _build_canteen_table(node, seg, at, _player.lane_x(trun.min()) - tuning.lane_width / 2.0 + 0.05,
							_player.lane_x(trun.max()) + tuning.lane_width / 2.0 - 0.05, trun.min())
				mesh = reception
			elif box_look == "roof_vent":
				mesh = _build_roof_vent(node, seg, at, x, lane)
			elif mesh == null:
				var m := _item_box(node, seg, at, Vector3(x, y, 0), size, kind.get("color", Color.WHITE))
				if tex_name != "":
					# BoxMesh lays its six faces out on a 3x2 grid, so this puts one tile on each face.
					m.material_override = PsxMaterials.textured(_obstacle_texture(tex_name), Vector2(3, 2))
				mesh = m
			# "group": every lane of one obstacle, so a tripwire trips once however you cross it.
			_obstacles.append({"x": x, "at": start + at, "depth": size.z, "kind": ob["kind"], "pass": kind["pass"],
					"crouch": kind.get("crouch", false), "done": false, "mesh": mesh, "owner": node, "group": ob})
		if kind.get("shadow", true):
			_obstacle_shadows(node, seg, lanes.keys(), at, size)

	# Troopers stand in a lane and face you. Alarm boxes are on a wall, facing the road.
	for e: Dictionary in _graph.node_data(id).get("enemies", []):
		if e.get("kind", "") == "security_trooper":
			# The alarm runner: stands in his lane facing you, until he spots you and runs for it.
			var sec := SecurityTrooper.new(tuning)
			sec.at = start + float(e["at"])
			sec.x = _player.lane_x(_remap_lane(int(e.get("lane", 2)), authored_lanes))
			sec.min_alert = int(e.get("min_alert", 1))
			sec.max_alert = int(e.get("max_alert", 1))
			# His alarm is on the wall on his side of the road (the left, from the middle lane).
			sec.wall_x = (1.0 if sec.x > 0.0 else -1.0) * (tuning.lane_count * tuning.lane_width / 2.0 - 0.15)
			node.add_child(sec)
			sec.transform = _frame_at(seg, float(e["at"])) * Transform3D(Basis(Vector3.UP, PI), Vector3(sec.x, 0, 0))
			_connect_security(sec)
			_combatants.append({"node": sec, "owner": node, "seg": seg})
			continue
		if e.get("kind", "") == "rusher_dog":
			# The Rusher: a guard dog standing in its lane, facing you, until it charges.
			var dog := RusherDog.new(tuning)
			dog.at = start + float(e["at"])
			dog.x = _player.lane_x(_remap_lane(int(e.get("lane", 2)), authored_lanes))
			dog.min_alert = int(e.get("min_alert", 1))
			dog.max_alert = int(e.get("max_alert", 3))
			node.add_child(dog)
			dog.transform = _frame_at(seg, float(e["at"])) * Transform3D(Basis(Vector3.UP, PI), Vector3(dog.x, 0, 0))
			_connect_dog_sounds(dog)
			_combatants.append({"node": dog, "owner": node, "seg": seg})
			continue
		if e.get("kind", "") != "rifle_trooper":
			push_warning("Unknown enemy kind '%s' in %s" % [e.get("kind"), id])
			continue
		var t := RifleTrooper.new(tuning)
		t.at = start + float(e["at"])
		t.x = _player.lane_x(_remap_lane(int(e.get("lane", 2)), authored_lanes))
		t.min_alert = int(e.get("min_alert", 1))
		t.max_alert = int(e.get("max_alert", 3))
		node.add_child(t)
		t.transform = _frame_at(seg, float(e["at"])) * Transform3D(Basis(Vector3.UP, PI), Vector3(t.x, 0, 0))
		t.knocked_down.connect(func() -> void: RunLog.record_event("trooper_down", {"node": id}))
		_connect_trooper_sounds(t)
		_combatants.append({"node": t, "owner": node, "seg": seg})
	# Searchlights (roofs): on the next building over, sweeping a pool of light across the lanes.
	for s: Dictionary in _graph.node_data(id).get("searchlights", []):
		var light := Searchlight.new()
		light.at = start + float(s["at"])
		light.side = -1 if String(s.get("side", "left")) == "left" else 1
		light.phase = fmod(float(s["at"]) * 0.137, 1.0)  # neighbouring lights out of step
		node.add_child(light)
		light.transform = _frame_at(seg, float(s["at"]))
		_ambience.add_lamp(light.pool, Color(0.8, 0.88, 1.0) * 1.6, 4.5, {"alert": false})
		light.spotted.connect(_on_searchlight_spotted.bind(light))
		_lights.append({"node": light, "owner": node, "seg": seg})
	for a: Dictionary in _graph.node_data(id).get("alarms", []):
		var box := AlarmBox.new()
		box.at = start + float(a["at"])
		var s := -1.0 if String(a.get("side", "left")) == "left" else 1.0
		node.add_child(box)
		var ax := s * (tuning.lane_count * tuning.lane_width / 2.0 + 0.45)  # out on the kerb, in front of the pillars
		box.x = ax
		box.transform = _frame_at(seg, float(a["at"])) * Transform3D(Basis(Vector3.UP, -s * PI / 2.0), Vector3(ax, 1.8, 0))
		box.destroyed.connect(_on_alarm_destroyed.bind(id))
		box.destroyed.connect(func() -> void: _audio.play_at("alarm_break", box.global_position + Vector3.UP * 1.8))
		box.beeped.connect(func(live: bool) -> void:
			if live and GameState.run_active:  # beeps while you can shoot it
				_audio.play_at("beep", box.global_position + Vector3.UP * 1.8, -6.0, 0.0, 25.0))
		# It sits on a metal control box standing on the floor, never floating (user).
		var stand := _item_box(node, seg, float(a["at"]), Vector3(ax, 0.675, 0), Vector3(0.55, 1.35, 0.72), Color.WHITE)
		stand.material_override = PsxMaterials.textured(PsxTextures.cabinet(), Vector2(3, 2))
		_item_box(node, seg, float(a["at"]), Vector3(ax, 1.37, 0), Vector3(0.6, 0.05, 0.78), Color("4e5358"))  # top plate
		_combatants.append({"node": box, "owner": node, "seg": seg})

	# The zone door into this area (not when you come in up or down the stairs: the stairwell has
	# its own door).
	if _graph.node_data(id).has("marker") and RouteGraph.via_of(edge) != "stairs":
		_build_marker(node, seg, float(_graph.node_data(id)["marker"].get("at", length / 2.0)))
	if not _has_straight(id) and _graph.end_type(id) == "":
		_build_dead_end(node, seg)
	if RouteGraph.via_of(edge) == "ladder":
		_build_ladder(node, seg, RouteGraph.side_of(edge))
	if _graph.end_type(id) == "extract":
		_spawn_chopper(node, _frame_at(seg, length) * Transform3D(Basis.IDENTITY, Vector3(0, 0, -3.0)))
	return seg


## The player is now on this segment: build every branch it can lead to, and its fork cue.
func _promote(seg: Dictionary) -> void:
	seg["promoted"] = true  # its troopers and alarm boxes come alive
	_segments.append(seg)
	_current = seg
	_build_branches()
	_build_fork_cue()


## Keeps the current segment's branches in step with alert: each open exit is built in full,
## each exit closed by alert gets a lockdown door. Doors slam if the branch was open a moment ago.
func _build_branches() -> void:
	if _current.is_empty():
		return
	var seg := _current
	var id: StringName = seg["id"]
	var branches: Dictionary = seg["branches"]
	var locked: Dictionary = seg["locked"]
	var open := {}
	for edge in _graph.available_next(id, GameState.alert_level):
		open[_key(edge)] = edge
	for edge in _graph.all_next(id):
		var key := _key(edge)
		if open.has(key):
			if locked.has(key):
				_open_door(locked[key])
				locked.erase(key)
			if not branches.has(key):
				branches[key] = _make_segment(StringName(edge["to"]), seg["end"], edge, _frame_after(seg, edge), id)
				_cut_openings(seg, branches[key])
		elif not locked.has(key):
			var slam := branches.has(key)
			if slam:
				_discard(branches[key])
				branches.erase(key)
			locked[key] = _build_locked_stub(seg, edge, slam)
	# The straight road opens up on each side that has a side exit, open or locked.
	for key in branches:
		_cut_openings(seg, branches[key])


## Throws away a branch that wasn't taken (and its obstacles).
func _discard(branch: Dictionary) -> void:
	var node: Node3D = branch["node"]
	_obstacles = _obstacles.filter(func(o: Dictionary) -> bool: return o["owner"] != node)
	_combatants = _combatants.filter(func(c: Dictionary) -> bool: return c["owner"] != node)
	_lights = _lights.filter(func(l: Dictionary) -> bool: return l["owner"] != node)
	_doors = _doors.filter(func(dr: Dictionary) -> bool: return dr["owner"] != node)
	_blockers = _blockers.filter(func(b: Dictionary) -> bool: return b["owner"] != node)
	node.queue_free()


func _on_segment_needed(id: StringName, _start: float, edge: Dictionary) -> void:
	var key := _key(edge)
	var branches: Dictionary = _current["branches"]
	var chosen: Dictionary = branches.get(key, {})
	if chosen.is_empty():  # shouldn't happen; build it now rather than fail
		chosen = _make_segment(id, _current["end"], edge, _frame_after(_current, edge), _current["id"])
	# The branches you didn't take stay standing as scenery until you're well past (nothing pops
	# out in front of you); they just stop being part of the game.
	var gone_at: float = _current["end"] + tuning.fork_scenery_keep
	for k in branches:
		if k != key:
			_retire(branches[k]["node"], gone_at)
	for k in _current["locked"]:
		_retire(_current["locked"][k], gone_at)
	branches.clear()
	_current["locked"].clear()
	_promote(chosen)


## A branch not taken: its obstacles, troopers and doors go at once; its scenery stays until
## the player reaches `gone_at`.
func _retire(node: Node3D, gone_at: float) -> void:
	_obstacles = _obstacles.filter(func(o: Dictionary) -> bool: return o["owner"] != node)
	_doors = _doors.filter(func(dr: Dictionary) -> bool: return dr["owner"] != node)
	_blockers = _blockers.filter(func(b: Dictionary) -> bool: return b["owner"] != node)
	for c in _combatants:
		if c["owner"] == node and (c["node"] is RifleTrooper or c["node"] is RusherDog or c["node"] is SecurityTrooper):
			c["node"].visible = false  # nobody left standing on a road you didn't take
	_combatants = _combatants.filter(func(c: Dictionary) -> bool: return c["owner"] != node)
	_lights = _lights.filter(func(l: Dictionary) -> bool: return l["owner"] != node)
	_retired.append({"node": node, "gone_at": gone_at})


## Entering a side branch: move the player into the branch's own lanes (same spot in the world).
func _on_node_entered(id: StringName) -> void:
	var area := _graph.display_name(id)
	if area != _last_area:  # MGS-style location caption
		_last_area = area
		_hud.show_area(area)
		_audio.type_ticks(area.length(), 0.04)
	var seg: Dictionary = _segments.back()
	if seg["id"] != _runner.current or not _turns(seg["edge"]):
		return
	var lanes := _handover_lanes(seg["edge"])
	_player.shift_lanes(lanes.y - lanes.x)


## LIFTING OFF: warning beeps every couple of seconds until it's gone (or you're on board).
func _warn_lift_off() -> void:
	if not GameState.run_active or _clock.stage != ExtractionClock.Stage.LIFTING_OFF:
		return
	_audio.play("warn", -6.0, 0.0, "UI")
	get_tree().create_timer(1.8).timeout.connect(_warn_lift_off)


## Footsteps on whatever's underfoot (and a landing after a jump), while you're running.
func _update_footsteps(delta: float) -> void:
	var airborne := _player.is_airborne()
	if _was_airborne and not airborne:
		_audio.play("land", -6.0, 0.08)
		_stride_left = tuning.stride
	_was_airborne = airborne
	if airborne or _player.in_cover or _player.halted or _player.is_sliding():
		return
	_stride_left -= tuning.run_speed * delta
	if _stride_left > 0.0:
		return
	_stride_left = tuning.stride
	var d := _player.distance_run()
	var surface := "office"
	if d >= 0.0:
		var seg := _segment_at(d)
		var into: float = d - seg["start"]
		if _is_stairs(seg) and into < seg["ramp_len"]:
			surface = "stairs"
		else:
			surface = {"office_floor": "office", "security_floor": "office", "canteen_floor": "office", "warehouse_floor": "concrete", "lobby_floor": "office", "asphalt": "tunnel", "gravel": "gravel"}.get(_theme(seg["id"])["ground"], "concrete")
	_audio.play("step_%s_%d" % [surface, randi() % SoundBank.STEP_VARIANTS], -10.0, 0.06)


## The dog's sounds: barking as it's about to charge, the bite, and a yelp when it's shot.
func _connect_dog_sounds(dog: RusherDog) -> void:
	dog.barked.connect(func() -> void: _audio.play_at("bark", dog.global_position + Vector3.UP * 0.8, 0.0, 0.06))
	dog.bit.connect(func() -> void: _audio.play("bite", 0.0, 0.05))
	dog.yelped.connect(func() -> void:
		RunLog.record_event("dog_down", {"node": _runner.current})
		_audio.play_at("yelp", dog.global_position + Vector3.UP * 0.6, 0.0, 0.06)
		_audio.play_at("hit", dog.global_position + Vector3.UP * 0.6, -2.0, 0.08))


## The alarm runner: his shout as he spots you and runs, being hit and going down, and the alarm
## if he gets there. The HUD bar tracks his run.
func _connect_security(sec: SecurityTrooper) -> void:
	var head := func() -> Vector3: return sec.global_position + Vector3.UP * 1.5
	sec.spotted.connect(func() -> void:
		sec.reparent(_world)  # he outruns the area he stood in
		RunLog.record_event("runner_spotted", {"node": _runner.current})
		_audio.play_at("spotted", head.call(), -3.0)
		_hud.show_chopper_message("STOP THE RUNNER", Color("ffb347"), 3.0, false)
		_hud.show_runner(0.0))
	sec.wounded.connect(func() -> void: _audio.play_at("hit", head.call(), 0.0, 0.08))
	sec.knocked_down.connect(func() -> void:
		RunLog.record_event("runner_down", {"node": _runner.current})
		_audio.play_at("grunt_%d" % (randi() % 3), head.call(), -2.0, 0.05)
		get_tree().create_timer(0.3).timeout.connect(func() -> void:
			if is_instance_valid(sec):
				_audio.play_at("fall", sec.global_position, -2.0, 0.05))
		if sec.alarm_at > 0.0:  # he was on his way
			_hud.show_runner(-1.0)
			_hud.show_chopper_message("RUNNER DOWN", Color("9fd36b"), 2.5, false))
	sec.raised.connect(func() -> void:
		RunLog.record_event("runner_alarm", {"node": _runner.current})
		_hud.show_runner(-1.0)
		_hud.show_chopper_message("ALARM RAISED", Color("ff4b3a"), 2.5, false)
		_build_runner_alarm(sec)
		GameState.raise_alert())


## Where the runner raised the alarm: a red panel on the wall, flashing.
func _build_runner_alarm(sec: SecurityTrooper) -> void:
	var seg := _runner_segment(sec.at)
	if seg.is_empty():
		return  # round a split you didn't take: you only hear about it
	var px := signf(sec.wall_x) * (tuning.lane_count * tuning.lane_width / 2.0 + 0.45)
	var panel := _item_box(seg["node"], seg, sec.at - seg["start"], Vector3(px, 1.7, 0), Vector3(0.14, 0.45, 0.4), Color.WHITE)
	panel.material_override = PsxMaterials.glow(Color("ff3020"))
	_ambience.add_lamp(panel, Color(1.0, 0.15, 0.1) * 1.6, 5.0, {"blink": 0.5, "alert": false})
	_audio.play_at("klaxon", panel.global_position, -4.0)


## A trooper's sounds: the "!" when he starts aiming, his shots, being hit, and going down.
func _connect_trooper_sounds(t: RifleTrooper) -> void:
	var head := func() -> Vector3: return t.global_position + Vector3.UP * 1.5
	t.aimed.connect(func() -> void: _audio.play_at("spotted", head.call(), -3.0))
	t.fired.connect(func(_hit: bool) -> void: _audio.play_at("gun_trooper", head.call(), -2.0, 0.06))
	t.wounded.connect(func() -> void: _audio.play_at("hit", head.call(), 0.0, 0.08))
	t.knocked_down.connect(func() -> void:
		_audio.play_at("grunt_%d" % (randi() % 3), head.call(), -2.0, 0.05)
		get_tree().create_timer(0.3).timeout.connect(func() -> void:
			if is_instance_valid(t):
				_audio.play_at("fall", t.global_position, -2.0, 0.05)))


func _on_alert_changed() -> void:
	# Alert up: a sting (and the klaxon at full alert); down: a falling blip. The music follows.
	var level := GameState.alert_level
	if GameState.run_active:
		if level > _last_alert:
			_audio.play("alert_up", -2.0)
			if level >= 3:
				_audio.play("klaxon", -6.0)
		elif level < _last_alert:
			_audio.play("alert_down", -2.0, 0.0, "UI")
	_last_alert = level
	_audio.set_alert(level)
	# Alert 3: the pursuit squad comes after you; below it, they fall back.
	if GameState.run_active and level >= 3 and not _squad_on:
		_spawn_squad()
	elif level < 3 and _squad_on:
		_squad_fall_back()
	_build_branches()
	_build_fork_cue()


func _is_authored_fork(id: StringName) -> bool:
	return _graph.end_type(id) == "" and RouteGraph.is_choice(_graph.all_next(id))


func _has_straight(id: StringName) -> bool:
	for edge in _graph.all_next(id):
		if RouteGraph.side_of(edge) == "straight":
			return true
	return false


## How far into a branch its walls must stay open where it overlaps the next road over.
func _overlap_clear() -> float:
	var angle := _turn_angle()
	var half := tuning.lane_count * tuning.lane_width / 2.0 + 1.0  # centre to wall
	var inner_wall_x := absf(_player.lane_x(tuning.lane_count - 1)) - (half - absf(_player.lane_x(0)))
	if angle <= 0.01:
		return tuning.branch_out_length
	return minf((half - inner_wall_x) / sin(angle) + 1.0, tuning.branch_out_length)


## Opens the walls between neighbouring branches of `seg`, where they overlap near the split.
func _cut_openings(seg: Dictionary, branch: Dictionary) -> void:
	var side := RouteGraph.side_of(branch["edge"])
	var clear := _overlap_clear()
	var sides := {}
	for edge in _graph.all_next(seg["id"]):
		if _turns(edge):
			sides[RouteGraph.side_of(edge)] = true
	var open_l := 0.0
	var open_r := 0.0
	var holes := {}
	if side == "straight":
		# A corridor branch needs the wall open where it overlaps; a stairwell only needs a hole
		# where its narrow tube passes through the wall, so nothing else shows the outside.
		for edge in _graph.all_next(seg["id"]):
			if not _turns(edge):
				continue
			var s := -1 if RouteGraph.side_of(edge) == "left" else 1
			if RouteGraph.via_of(edge) == "stairs":
				holes[s] = _stairwell_hole(seg, edge, branch, s)
			elif s < 0:
				open_l = clear
			else:
				open_r = clear
	elif _turns(branch["edge"]) and RouteGraph.via_of(branch["edge"]) != "stairs":
		open_l = clear if side == "right" else 0.0
		open_r = clear if side == "left" else 0.0
	branch["holes"] = holes
	_rebuild_walls(branch, open_l, open_r)


## Where a stairwell leaving `seg` by `edge` passes through the side wall of `road` (on `side`):
## the stretch [from, to] metres along `road` to leave out of that wall.
func _stairwell_hole(seg: Dictionary, edge: Dictionary, road: Dictionary, side: int) -> Vector2:
	var tube := _frame_after(seg, edge)
	var road_xf: Transform3D = road["node"].transform
	var wall_x := side * (tuning.lane_count * tuning.lane_width / 2.0 + 1.0)
	var lane_x := _player.lane_x(_handover_lanes(edge).y)
	var hw := tuning.lane_width / 2.0 + 0.25
	var zs: Array[float] = []
	for off in [-hw, hw]:
		# Two points along this stairwell wall, in the road's own frame; where does it cross the wall?
		var a := road_xf.affine_inverse() * (tube * Vector3(lane_x + off, 0, 0))
		var b := road_xf.affine_inverse() * (tube * Vector3(lane_x + off, 0, -10.0))
		if absf(b.x - a.x) > 0.001:
			var t := (wall_x - a.x) / (b.x - a.x)
			zs.append(-lerpf(a.z, b.z, t))
	if zs.is_empty():
		return Vector2.ZERO
	return Vector2(maxf(0.0, zs.min() - 0.15), zs.max() + 0.15)


func _rebuild_walls(seg: Dictionary, open_l: float, open_r: float) -> void:
	var key := "%s %s" % [Vector2(open_l, open_r), seg.get("holes", {})]
	if seg.get("walls_key", "") == key:
		return
	seg["walls_key"] = key
	seg["open"] = Vector2(open_l, open_r)
	var node: Node3D = seg["node"]
	var old := node.get_node_or_null("Walls")
	if old:
		node.remove_child(old)
		old.queue_free()
	var walls := Node3D.new()
	walls.name = "Walls"
	node.add_child(walls)
	_build_walls(walls, seg, open_l, open_r)


# --- World building -----------------------------------------------------------

## Road, stairs and ceiling for one segment. Walls go in their own node so openings can change.
## The road stops at road_end (the fork cue paints the rest).
func _build_surfaces(parent: Node3D, seg: Dictionary, road_end: float, open_l: float, open_r: float) -> void:
	var id: StringName = seg["id"]
	var length: float = seg["length"]
	var ramp: float = seg["ramp_len"]
	var road_w := tuning.lane_count * tuning.lane_width
	var theme := _theme(id)
	var via := RouteGraph.via_of(seg["edge"])

	for piece in _pieces(seg, 0.0, road_end):
		var on_ramp: bool = piece.y <= ramp + 0.001 and ramp > 0.0
		if on_ramp and via == "ladder":
			# A ladder is a single lane, with a drop either side of it.
			var lane := 0 if RouteGraph.side_of(seg["edge"]) == "left" else tuning.lane_count - 1
			_strip(parent, seg, piece.x, piece.y, _player.lane_x(lane), tuning.lane_width, 0.0, PsxTextures.stairs(), 1.0)
		elif on_ramp:
			# Stairs are one lane wide, in the lane you took them from (user decision).
			_strip(parent, seg, piece.x, piece.y, _player.lane_x(_stair_lane(seg)), tuning.lane_width, 0.0, PsxTextures.stairs(), 1.0)
		else:
			_strip(parent, seg, piece.x, piece.y, 0.0, road_w, 0.0, _ground(id), float(tuning.lane_count), _ground_tile(id))
	if _is_stairs(seg):
		_build_stairwell(parent, seg)
	# Patches under (and over) each bend, from both legs' side, so the outside corner has no gap
	# in the floor or the ceiling.
	var has_ceiling: bool = theme.get("ceiling", false)
	for i in range(1, seg["legs"].size()):
		var j: float = seg["legs"][i]["start"]
		if j >= ramp:
			# 3 m either side of the bend, but never back over the stairs (it would cut through
			# the stairwell).
			var back := minf(3.0, j - ramp)
			var plen := back + 3.0
			var shift := -(3.0 - back) / 2.0  # forward (-Z) by what was cut off the back
			for k in [i - 1, i]:
				var patch := _plane(parent, Vector2(road_w + 2.0, plen), Vector3.ZERO, _ground(id), Vector2(tuning.lane_count, plen / 4.0))
				patch.transform = _frame_in_leg(seg, k, j) * Transform3D(Basis.IDENTITY, Vector3(0, -0.02, shift))
				if has_ceiling and not _is_outdoor(seg, j):
					var cap := _plane(parent, Vector2(road_w + 2.0, plen), Vector3.ZERO, _ceiling_texture(theme), Vector2(road_w / 2.0, plen / 2.0))
					cap.transform = _frame_in_leg(seg, k, j) * Transform3D(Basis(Vector3.FORWARD, PI), Vector3(0, _ceil(id) + 0.02, shift))
	if theme.get("ceiling", false):
		for span in _cut_spans([Vector2(ramp, length)], _outdoor(seg)):  # open sky over any outdoor stretch
			for piece in _pieces(seg, span.x, span.y):
				var roof := _strip(parent, seg, piece.x, piece.y, 0.0, road_w + 2.0, _ceil(id),
						_ceiling_texture(theme), road_w / 2.0, 2.0)
				roof.rotate_object_local(Vector3.FORWARD, PI)  # face down
	var walls := Node3D.new()
	walls.name = "Walls"
	parent.add_child(walls)
	seg["open"] = Vector2(open_l, open_r)
	_build_walls(walls, seg, open_l, open_r)


## [from, to] with a hole (a stairwell passing through the wall) taken out.
## The stretch of this area that runs outdoors ("outdoor" in route.json: the LOADING DOCK's yard,
## user): [from, to], or ZERO.
func _outdoor(seg: Dictionary) -> Vector2:
	var o: Dictionary = _graph.node_data(seg["id"]).get("outdoor", {})
	if o.is_empty():
		return Vector2.ZERO
	return Vector2(float(o["at"]), float(o["at"]) + float(o.get("length", 40.0)))


func _is_outdoor(seg: Dictionary, z: float) -> bool:
	var o := _outdoor(seg)
	return o != Vector2.ZERO and z > o.x - 0.3 and z < o.y + 0.3


## _pieces over [a, b] leaving out [cut.x, cut.y].
func _pieces_except(seg: Dictionary, a: float, b: float, cut: Vector2) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for span in _cut_spans([Vector2(a, b)], cut):
		out.append_array(_pieces(seg, span.x, span.y))
	return out


## Spans with [cut.x, cut.y] taken out of them (ZERO: none).
static func _cut_spans(spans: Array[Vector2], cut: Vector2) -> Array[Vector2]:
	if cut == Vector2.ZERO:
		return spans
	var out: Array[Vector2] = []
	for s in spans:
		if cut.y <= s.x or cut.x >= s.y:
			out.append(s)
			continue
		if cut.x > s.x:
			out.append(Vector2(s.x, cut.x))
		if cut.y < s.y:
			out.append(Vector2(cut.y, s.y))
	return out


static func _wall_spans(from: float, to: float, hole: Vector2) -> Array[Vector2]:
	if hole.y <= hole.x or hole.y <= from or hole.x >= to:
		return [Vector2(from, to)]
	var out: Array[Vector2] = []
	if hole.x > from:
		out.append(Vector2(from, hole.x))
	if hole.y < to:
		out.append(Vector2(hole.y, to))
	return out


## At each bend, the walls of the two legs don't meet on the outside of the corner. A short wall
## (height h, from the floor) joins them, from where one leg's wall ends to where the next begins.
func _join_bends(parent: Node3D, seg: Dictionary, side: int, wx: float, from: float, h: float, mat: Material) -> void:
	for k in range(1, seg["legs"].size()):
		var j: float = seg["legs"][k]["start"]
		if j < from or _is_outdoor(seg, j):
			continue
		var a := _frame_in_leg(seg, k - 1, j) * Vector3(wx, 0, 0)
		var b := _frame_in_leg(seg, k, j) * Vector3(wx, 0, 0)
		var l := a.distance_to(b)
		if l < 0.05:
			continue
		var m := _box(parent, Vector3(0.25, h, l + 0.3), Vector3.ZERO, Color.WHITE)
		m.material_override = mat
		m.transform = Transform3D(Basis.looking_at((b - a).normalized(), Vector3.UP), (a + b) / 2.0 + Vector3(0, h / 2.0, 0))


## Kerbs, walls and pillars either side, leaving the first open_l / open_r metres open.
func _build_walls(parent: Node3D, seg: Dictionary, open_l: float, open_r: float) -> void:
	var length: float = seg["length"]
	var ramp: float = seg["ramp_len"]
	var road_w := tuning.lane_count * tuning.lane_width
	var theme := _theme(seg["id"])
	var h: float = theme["height"]
	var wall_tex := _wall_texture(theme)
	var via := RouteGraph.via_of(seg["edge"])
	if theme.get("no_walls", false):
		_build_roof_edges(parent, seg, open_l, open_r)
		return
	for side in [-1, 1]:
		var open := open_l if side < 0 else open_r
		var wx: float = side * (road_w / 2.0 + 1.0)
		var hole: Vector2 = seg.get("holes", {}).get(side, Vector2.ZERO)
		# An opening in this wall with a room behind it (the canteen's kitchen, the dock's bays), as
		# well as any stairwell hole.
		var alcove := _alcove(seg, side)
		if alcove != Vector2.ZERO and alcove.x < hole.y + 1.0 and alcove.y > hole.x - 1.0:
			alcove = Vector2.ZERO  # it would run into the stairwell: leave the wall whole there
		for span in _cut_spans(_cut_spans(_wall_spans(open, length, hole), alcove), _outdoor(seg)):
			for piece in _pieces(seg, span.x, span.y):
				var on_ramp: bool = piece.y <= ramp + 0.001 and ramp > 0.0
				if on_ramp:
					continue  # a ladder has none (you see the drop); stairs have their own stairwell
				_strip(parent, seg, piece.x, piece.y, side * (road_w / 2.0 + 0.5), 1.0, 0.02, PsxTextures.concrete(), 1.0, 2.0)
				_wall(parent, seg, piece.x, piece.y, wx, side, h, wall_tex)
		# At every bend, a short wall joins the two legs' walls, so no gap shows the outside.
		_join_bends(parent, seg, side, wx, maxf(open, ramp), h, PsxMaterials.textured(wall_tex, Vector2(1, h / 2.0)))
		# Pillars every 5 m, alternating light and dark, give a sense of speed. Big ones hide bend corners.
		var ph := maxf(h, 1.2)
		for i in range(ceili(maxf(open, ramp) / 5.0) * 5, int(length), 5):
			if (i > hole.x - 0.5 and i < hole.y + 0.5) or (i > alcove.x - 0.5 and i < alcove.y + 0.5) or _is_outdoor(seg, i) \
					or (theme.get("mezzanine", false) and side < 0 and i > 34 and i < 50):  # the lobby's grand staircase
				continue
			var c: Color = theme["color"].lightened(0.25) if (i / 5) % 2 == 0 else theme["color"].darkened(0.5)
			_item_box(parent, seg, i, Vector3(side * (road_w / 2.0 + 0.8), ph / 2.0, 0), Vector3(0.35, ph, 0.35), c)
		for k in range(1, seg["legs"].size()):
			var j: float = seg["legs"][k]["start"]
			if j >= maxf(open, ramp) and not _is_outdoor(seg, j):
				_item_box(parent, seg, j, Vector3(side * (road_w / 2.0 + 1.0), ph / 2.0, 0), Vector3(1.0, ph, 1.0), theme["color"].darkened(0.5))
		if theme.get("wall_decor", false):
			_wall_decor(parent, seg, side, maxf(open, ramp), length)
		if alcove != Vector2.ZERO:
			if String(_alcove_data(seg, side).get("kind", "kitchen")) == "bay":
				_build_bay(parent, seg, side, alcove)
			else:
				_build_kitchen(parent, seg, side, alcove)
	if theme.get("floor_stripes", false):
		_floor_stripes(parent, seg, ramp)
	if theme.get("mezzanine", false):
		_build_mezzanine(parent, seg, ramp)
	if _outdoor(seg) != Vector2.ZERO:
		_build_yard(parent, seg, _outdoor(seg))
	if theme.get("floor_lines", false):
		_floor_lines(parent, seg, ramp)
	if theme.get("overhead", "") == "crane":
		_warehouse_overhead(parent, seg, ramp)
	if theme.get("overhead", "") == "pipes":
		_dock_overhead(parent, seg, ramp)
	if theme.get("ceiling_vents", false):
		_ceiling_vents(parent, seg, ramp)
	if theme.get("litter", false):
		_canteen_litter(parent, seg, ramp)
	_make_solid(parent)  # corridor walls, bend joins and pillars block line of sight


func _is_stairs(seg: Dictionary) -> bool:
	return RouteGraph.via_of(seg["edge"]) == "stairs" and seg["ramp_len"] > 0.0


## The one lane the stairs run in: the lane you come onto them from.
func _stair_lane(seg: Dictionary) -> int:
	return _handover_lanes(seg["edge"]).y


## True while the player is in a stairwell (between its doors): locked to the stair lane, and dark.
func in_stairwell() -> bool:
	var d := _player.distance_run()
	var seg := _segment_at(d)
	var into: float = d - seg["start"]
	return _is_stairs(seg) and into > -0.2 and into < seg["ramp_len"] + 0.3


## A narrow stairwell over a one-lane flight: concrete-block walls either side, a roof slab over it,
## and a door at each end that you burst through (the office door from the start room). Where the
## stairs meet the roof, the top of the stairwell is a narrow rooftop hut around that door.
func _build_stairwell(outer: Node3D, seg: Dictionary) -> void:
	# All of it on its own render layer: as you burst out, the camera leaves it out while it pulls
	# back to its normal spot behind you (which is inside this stairwell for a few metres).
	var parent := Node3D.new()
	parent.name = "Stairwell"
	outer.add_child(parent)
	_build_stairwell_parts(parent, seg)
	_make_solid(parent)  # its walls, slabs and doors (not the sheared inner tube)
	_set_render_layer(parent, STAIRWELL_LAYER)


func _set_render_layer(node: Node, layer: int) -> void:
	if node is VisualInstance3D:
		node.layers = layer
	for c in node.get_children():
		_set_render_layer(c, layer)


func _build_stairwell_parts(parent: Node3D, seg: Dictionary) -> void:
	var ramp: float = seg["ramp_len"]
	var x := _player.lane_x(_stair_lane(seg))
	var hw := tuning.lane_width / 2.0 + 0.05
	var bottom := minf(0.0, seg["dy"])
	# Each end looks like the area it opens into (user): the entrance half like where you came
	# from, the exit half like where you're going. Indoors, each half reaches that area's
	# ceiling, so it's built into the building; on the roof, the half is a hut 3 m tall.
	var themes := [_theme(seg.get("from_id", seg["id"])), _theme(seg["id"])]
	var ends := [0.0, ramp]
	var tops: Array[float] = []
	for half in 2:
		var indoor: bool = themes[half].get("ceiling", false)
		tops.append(_height(seg, ends[half]) + (CEILING_Y if indoor else 3.0))
	for half in 2:
		var top: float = tops[half]
		var hmat := PsxMaterials.textured(_stair_wall_texture(themes[half]), Vector2(2, 3))
		var hz := ramp * (0.25 + 0.5 * half)  # centre of this half
		var hh := _height(seg, hz)
		for side in [-1, 1]:
			_item_box(parent, seg, hz, Vector3(x + side * (hw + 0.1), (bottom + top) / 2.0 - hh, 0),
					Vector3(0.2, top - bottom, ramp / 2.0 + 0.2), Color.WHITE).material_override = hmat
		_item_box(parent, seg, hz, Vector3(x, top + 0.12 - hh, 0), Vector3(tuning.lane_width + 0.7, 0.24, ramp / 2.0 + 0.3), Color.WHITE) \
				.material_override = PsxMaterials.textured(PsxTextures.concrete(), Vector2(2, 2))
	# Inside, it's one clean tube between the doors: walls and a ceiling that follow the stairs, in
	# one stairwell texture, so none of the outside (the halves above, the areas' walls and floors
	# it passes through) shows in the security-camera view.
	var slope := _frame_at(seg, 0.1).origin.distance_to(_frame_at(seg, ramp - 0.1).origin)
	var inner := tuning.lane_width / 2.0 + 0.03
	var tube_mat := PsxMaterials.textured(PsxTextures.stairwell(), Vector2(3.0 * slope / 2.0, 2.0))
	for side in [-1, 1]:
		_slope_box(parent, seg, 0.1, ramp - 0.1, x + side * (inner + 0.02), -0.4, 0.04, STAIR_HEADROOM + 0.4).material_override = tube_mat
	_slope_box(parent, seg, 0.1, ramp - 0.1, x, STAIR_HEADROOM, inner * 2.0 + 0.1, 0.05).material_override = \
			PsxMaterials.textured(PsxTextures.concrete(), Vector2(3.0 * slope / 4.0, 2.0))
	# A dim lamp on the ceiling, a little before the exit door.
	_item_box(parent, seg, ramp - 1.6, Vector3(x, STAIR_HEADROOM - 0.05, 0), Vector3(0.3, 0.08, 0.3), Color.WHITE).material_override = \
			PsxMaterials.glow(Color("c8b890"))
	var lamp := Node3D.new()
	parent.add_child(lamp)
	lamp.transform = _frame_at(seg, ramp - 1.6) * Transform3D(Basis.IDENTITY, Vector3(x, STAIR_HEADROOM - 0.6, 0))
	_ambience.add_lamp(lamp, Color(1.0, 0.85, 0.6), 5.0)
	# A green exit sign over each door, on the side you run up to it from.
	for into in [0.02, ramp - 0.38]:
		_item_box(parent, seg, into, Vector3(x, DOOR_H + 0.2, 0), Vector3(0.5, 0.15, 0.04), Color.WHITE).material_override = \
				PsxMaterials.glow(Color("40d070"))
	_build_door(parent, seg, 0.2, x, tops[0], themes[0])
	_build_door(parent, seg, ramp - 0.2, x, tops[1], themes[1])
	# Built in: joined to the walls of the area at each indoor end.
	var edge := tuning.lane_count * tuning.lane_width / 2.0 + 1.0
	# The stairwell is in the branch's inside lane; the side wall it runs out through (the area
	# you came from) is toward the branch's middle.
	var outward := -1.0 if x > 0.0 else 1.0
	if not themes[0].get("no_walls", false):
		# Entrance: close the gap between the stairwell and the side wall it runs out through.
		var mat0 := PsxMaterials.textured(_stair_wall_texture(themes[0]), Vector2(1, 2))
		_item_box(parent, seg, 0.2, Vector3(x + outward * (hw + 0.2 + 0.75), tops[0] / 2.0, 0), Vector3(1.5, tops[0], 0.25), Color.WHITE) \
				.material_override = mat0
	if not themes[1].get("no_walls", false):
		# Exit: an end wall right across the area, side wall to side wall, with the door in it.
		var mat1 := PsxMaterials.textured(_stair_wall_texture(themes[1]), Vector2(3, 2))
		var h1 := _height(seg, ramp - 0.2)
		var wall_h: float = tops[1] - h1
		for span in [Vector2(-edge, x - hw - 0.1), Vector2(x + hw + 0.1, edge)]:
			if span.y - span.x > 0.05:
				_item_box(parent, seg, ramp - 0.2, Vector3((span.x + span.y) / 2.0, wall_h / 2.0, 0), Vector3(span.y - span.x, wall_h, 0.3), Color.WHITE) \
						.material_override = mat1


## Makes the solid things under `root` (walls, doors, stairwell blocks) block line of sight: an
## invisible collision box on each wall-sized box or upright plane. Skips small fittings, glowing
## lamps and signs, and sheared or mirrored pieces (physics can't take those). See _sees().
func _make_solid(root: Node) -> void:
	if root is MeshInstance3D:
		_solid_mesh(root)
	for m in root.find_children("*", "MeshInstance3D", true, false):
		_solid_mesh(m)


func _solid_mesh(m: MeshInstance3D) -> void:
	if m.has_meta("solid") or m.material_override is StandardMaterial3D:
		return
	var size := Vector3.ZERO
	if m.mesh is BoxMesh:
		size = (m.mesh as BoxMesh).size
	elif m.mesh is PlaneMesh and (m.mesh as PlaneMesh).orientation == PlaneMesh.FACE_Z:
		var p: Vector2 = (m.mesh as PlaneMesh).size
		size = Vector3(p.x, p.y, 0.06)
	else:
		return
	if maxf(size.x, maxf(size.y, size.z)) < 0.9:
		return
	var b := m.global_transform.basis
	if absf(b.x.length() - 1.0) > 0.01 or absf(b.y.length() - 1.0) > 0.01 or absf(b.z.length() - 1.0) > 0.01 \
			or absf(b.x.dot(b.y)) > 0.01 or absf(b.y.dot(b.z)) > 0.01 or b.determinant() < 0.0:
		return
	m.set_meta("solid", true)
	_solid_box(m, Transform3D.IDENTITY, size)


## An invisible box (for line of sight only) under `parent`, at `xf` in its space.
func _solid_box(parent: Node3D, xf: Transform3D, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = SIGHT_LAYER
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)
	body.transform = xf


## True if nothing solid is between two points: what you can see, you can shoot (and be shot from).
func _sees(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, SIGHT_LAYER)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Where your shots come from: your chest.
func _gun_origin() -> Vector3:
	return _route_point(_player.distance_run(), _player.track_x, 1.3)


## In cover behind a wall you can't shoot at all (user decision: no shooting from behind walls).
## Behind a box (low cover) you still shoot over it.
func _behind_wall() -> bool:
	return _player.in_cover and Sightlines.cover_wall(_player.distance_run(), _player.track_x, _live_blockers()) != null


## A box sheared to follow a slope (stairs): vertical sides and ends, its bottom running from
## `into0` to `into1` at `y` above the route there, `size_x` across and `size_y` tall.
func _slope_box(parent: Node3D, seg: Dictionary, into0: float, into1: float, x: float, y: float,
		size_x: float, size_y: float) -> MeshInstance3D:
	var f0 := _frame_at(seg, into0)
	var p0 := f0 * Vector3(x, y, 0)
	var p1 := _frame_at(seg, into1) * Vector3(x, y, 0)
	var m := MeshInstance3D.new()
	m.mesh = BoxMesh.new()  # a unit box, stretched and sheared by its transform
	parent.add_child(m)
	var up := f0.basis.y
	m.transform = Transform3D(Basis(f0.basis.x * size_x, up * size_y, p1 - p0), (p0 + p1) / 2.0 + up * size_y / 2.0)
	return m


func _stair_wall_texture(theme: Dictionary) -> Texture2D:
	return _obstacle_texture(theme.get("stair_wall", "roof_hut"))


## A doorway across one lane at `into` (lintel up to `top`), with a door on a hinge that the
## player bursts through (see _doors).
func _build_door(parent: Node3D, seg: Dictionary, into: float, x: float, top: float, theme: Dictionary) -> void:
	var dw := tuning.lane_width - 0.1
	var dh := DOOR_H
	var h := _height(seg, into)
	var frame := _frame_at(seg, into)
	_item_box(parent, seg, into, Vector3(x, (dh + top - h) / 2.0, 0), Vector3(tuning.lane_width + 0.3, top - h - dh, 0.25), Color.WHITE) \
			.material_override = PsxMaterials.textured(_stair_wall_texture(theme), Vector2(2, 2))
	# A door frame, so the doorway reads as part of the wall it's in.
	for s in [-1, 1]:
		_item_box(parent, seg, into, Vector3(x + s * (dw / 2.0 + 0.04), dh / 2.0, 0), Vector3(0.08, dh, 0.3), Color("3a3e42"))
	_item_box(parent, seg, into, Vector3(x, dh + 0.04, 0), Vector3(dw + 0.16, 0.08, 0.3), Color("3a3e42"))
	var hinge := Node3D.new()
	parent.add_child(hinge)
	hinge.transform = frame * Transform3D(Basis.IDENTITY, Vector3(x - dw / 2.0, 0, 0))
	var panel := _box(hinge, Vector3(dw - 0.04, dh - 0.02, 0.07), Vector3(dw / 2.0, dh / 2.0, 0), Color.WHITE)
	panel.material_override = PsxMaterials.textured(_obstacle_texture(theme.get("stair_door", "door")), Vector2(3, 2))
	if not seg.get("no_doors", false):  # a locked-down branch's doors never open
		var door := {"node": hinge, "at": seg["start"] + into, "owner": seg["node"], "seg": seg,
				"sound": "door_steel" if theme.get("stair_door", "door") == "steel_door" else "door_wood"}
		_doors.append(door)


## Open-sky areas (rooftops): no side walls. The roofing runs out to a low lip at the edge, and
## below it the building's own front drops away into the dark. The stairwell coming up from the
## building (the ramp) keeps its walls.
func _build_roof_edges(parent: Node3D, seg: Dictionary, open_l: float, open_r: float) -> void:
	var length: float = seg["length"]
	var ramp: float = seg["ramp_len"]
	var road_w := tuning.lane_count * tuning.lane_width
	var theme := _theme(seg["id"])
	var via := RouteGraph.via_of(seg["edge"])
	var edge := road_w / 2.0 + 1.0
	var lip: float = theme.get("lip", 0.3)
	for side in [-1, 1]:
		var open := open_l if side < 0 else open_r
		var hole: Vector2 = seg.get("holes", {}).get(side, Vector2.ZERO)
		for piece in _pieces(seg, open, length):
			var on_ramp: bool = piece.y <= ramp + 0.001 and ramp > 0.0
			if on_ramp:
				continue  # the stairwell (or ladder) has its own walls
			# Roofing out to the edge, the lip, and the building's front dropping away below.
			_strip(parent, seg, piece.x, piece.y, side * (road_w / 2.0 + 0.5), 1.0, 0.0, PsxTextures.gravel(), 1.0, tuning.lane_width)
			var i := _leg_index(seg, (piece.x + piece.y) / 2.0)
			var mid := (piece.x + piece.y) / 2.0
			var l: float = piece.y - piece.x
			for span in _wall_spans(piece.x, piece.y, hole):  # the lip stops where a stairwell crosses it
				var sm := (span.x + span.y) / 2.0
				_item_box(parent, seg, sm, Vector3(side * (edge - 0.1), lip / 2.0, 0), Vector3(0.2, lip, span.y - span.x + 0.2), Color("5e5e58"))
			var front := _plane(parent, Vector2(l, 30.0), Vector3.ZERO, PsxTextures.building_night(), Vector2(l / 4.0, 30.0 / 4.0), PlaneMesh.FACE_Z)
			front.material_override = PsxMaterials.textured(PsxTextures.building_night(), Vector2(l / 4.0, 30.0 / 4.0), true)
			var leg: Dictionary = seg["legs"][i]
			front.transform = Transform3D(leg["xf"].basis * Basis(Vector3.UP, -side * PI / 2.0),
					leg["xf"] * Vector3(side * edge, _height(seg, mid) - 15.0, -(mid - leg["start"])))
		_join_bends(parent, seg, side, side * (edge - 0.1), maxf(open, ramp), lip, PsxMaterials.flat(Color("5e5e58")))


## Office walls: now and then a door, a window or a notice board between the pillars.
func _wall_decor(parent: Node3D, seg: Dictionary, side: int, from: float, to: float) -> void:
	if str(_theme(seg["id"]).get("wall_decor", "")) == "lobby":
		_lobby_decor(parent, seg, side, from, to)
		return
	if str(_theme(seg["id"]).get("wall_decor", "")) == "dock":
		_dock_decor(parent, seg, side, from, to)
		return
	if str(_theme(seg["id"]).get("wall_decor", "")) == "warehouse":
		_warehouse_racks(parent, seg, side, from, to)
		return
	if str(_theme(seg["id"]).get("wall_decor", "")) == "canteen":
		_canteen_decor(parent, seg, side, from, to)
		return
	if str(_theme(seg["id"]).get("wall_decor", "")) == "security":
		_security_decor(parent, seg, side, from, to)
		return
	var face := side * (tuning.lane_count * tuning.lane_width / 2.0 + 1.0 - 0.03)
	for i in range(ceili(from / 5.0) * 5, int(to) - 3, 5):
		var at := i + 2.5
		var near_bend := false
		for leg in seg["legs"]:
			if absf(leg["start"] - at) < 1.3:
				near_bend = true
		if near_bend:
			continue
		# (width, height, centre height, texture); about half the gaps get something.
		var pick := absi(hash([seg["id"], i, side])) % 7
		var item: Array = []
		match pick:
			0, 1:
				item = [DOOR_W, DOOR_H, DOOR_H / 2.0, PsxTextures.door()]
			2, 3:
				item = [1.6, 1.1, 1.8, PsxTextures.office_window()]
			4:
				item = [1.1, 0.75, 1.5, PsxTextures.notice_board()]
		if item.is_empty():
			continue
		var m := _item_box(parent, seg, at, Vector3(face, item[2], 0), Vector3(0.05, item[1], item[0]), Color.WHITE)
		m.material_override = PsxMaterials.textured(item[3], Vector2(3, 2))


## The SECURITY WING's walls (user reference), in 3D: steel doors in frames with a red alarm light
## over them and a keycard reader beside; banks of four CCTV monitors on a bracket, angled toward
## you; security cameras on arms looking down the corridor at you; and the odd lone card reader.
## One thing in most 5 m gaps between the pillars. (The guard booth is a cover wall: _build_booth.)
func _security_decor(parent: Node3D, seg: Dictionary, side: int, from: float, to: float) -> void:
	var face := side * (tuning.lane_count * tuning.lane_width / 2.0 + 1.0 - 0.03)
	var red := PsxMaterials.glow(Color(1.0, 0.18, 0.12))
	var dark := Color("26292b")
	var steel := Color("3a3f42")
	for i in range(ceili(from / 5.0) * 5, int(to) - 3, 5):
		var at := i + 2.5
		var near_bend := false
		for leg in seg["legs"]:
			if absf(leg["start"] - at) < 1.3:
				near_bend = true
		if near_bend:
			continue
		# Everything for this gap hangs off one holder on the wall: x out from the wall (-side is
		# toward the road), y up, z along the road (+z back toward you).
		var holder := Node3D.new()
		parent.add_child(holder)
		holder.transform = _frame_at(seg, at) * Transform3D(Basis.IDENTITY, Vector3(face, 0, 0))
		var out := -float(side)
		# A set rhythm (so the monitor banks and cameras turn up often), shifted per wall.
		match (i / 5 + (2 if side > 0 else 0) + absi(hash(seg["id"])) % 3) % 6:
			0, 1:  # a steel door in a frame, a red alarm light over it, a card reader beside
				_box(holder, Vector3(0.06, DOOR_H, DOOR_W), Vector3(out * 0.03, DOOR_H / 2.0, 0), Color.WHITE).material_override = \
						PsxMaterials.textured(PsxTextures.steel_door(), Vector2(3, 2))
				for dz in [-(DOOR_W / 2.0 + 0.05), DOOR_W / 2.0 + 0.05]:
					_box(holder, Vector3(0.12, DOOR_H + 0.1, 0.1), Vector3(out * 0.06, (DOOR_H + 0.1) / 2.0, dz), steel)
				_box(holder, Vector3(0.12, 0.1, DOOR_W + 0.2), Vector3(out * 0.06, DOOR_H + 0.05, 0), steel)
				_box(holder, Vector3(0.14, 0.16, 0.34), Vector3(out * 0.09, DOOR_H + 0.26, 0), dark)
				_box(holder, Vector3(0.06, 0.1, 0.26), Vector3(out * 0.17, DOOR_H + 0.26, 0), Color.WHITE).material_override = red
				_card_reader(holder, out, 0.85, red)
			2:  # a bank of four CCTV monitors on a bracket, turned a little toward you
				_box(holder, Vector3(0.06, 0.4, 0.06), Vector3(out * 0.62, CEILING_Y - 0.2, 0), dark)  # the rod from the ceiling
				_box(holder, Vector3(0.7, 0.06, 0.08), Vector3(out * 0.32, CEILING_Y - 0.04, 0), dark)  # its ceiling rail
				var bank := Node3D.new()
				holder.add_child(bank)
				bank.position = Vector3(out * 0.62, CEILING_Y - 0.4 - 0.7, 0)  # its top just under the ceiling
				bank.scale = Vector3.ONE * 1.25
				bank.rotation.y = side * 0.45  # facing across the road and back toward you
				_box(bank, Vector3(0.32, 1.12, 1.62), Vector3(0, 0, 0), Color("1a1c1e"))  # housing
				for k in 4:
					var sz := 0.38 * (1.0 if k % 2 == 0 else -1.0)
					var sy := 0.26 * (1.0 if k < 2 else -1.0)
					var scr := _box(bank, Vector3(0.04, 0.46, 0.7), Vector3(out * 0.17, sy, sz), Color.WHITE)
					scr.material_override = PsxMaterials.textured(PsxTextures.cctv_screen(k), Vector2(3, 2), true)
				_box(bank, Vector3(0.06, 0.05, 1.62), Vector3(out * 0.17, 0.0, 0), Color("2a2d30"))  # bezels
				_box(bank, Vector3(0.06, 1.12, 0.05), Vector3(out * 0.17, 0, 0), Color("2a2d30"))
			3:  # a security camera on an arm, looking down the corridor at you
				_box(holder, Vector3(0.12, 0.22, 0.16), Vector3(out * 0.06, CEILING_Y - 0.4, 0), dark)  # wall plate
				_box(holder, Vector3(0.5, 0.06, 0.06), Vector3(out * 0.3, CEILING_Y - 0.36, 0), dark)  # the arm
				var cam := Node3D.new()
				holder.add_child(cam)
				cam.position = Vector3(out * 0.58, CEILING_Y - 0.44, 0)
				cam.rotation = Vector3(0.32, -side * 0.5, 0)  # tipped down, turned toward the road
				cam.scale = Vector3.ONE * 1.4
				_box(cam, Vector3(0.2, 0.18, 0.5), Vector3(0, 0, 0.05), Color("c4c8c8"))  # body
				_box(cam, Vector3(0.26, 0.04, 0.6), Vector3(0, 0.11, 0.08), Color("9a9ea0"))  # sun hood
				_box(cam, Vector3(0.14, 0.12, 0.04), Vector3(0, 0, 0.31), Color("101214"))  # lens
				_box(cam, Vector3(0.04, 0.04, 0.02), Vector3(0.06, -0.06, 0.32), Color.WHITE).material_override = red
			4:  # a lone keycard reader
				_card_reader(holder, out, 0.0, red)


## An opening in this side wall with a room behind it ("alcove" in route.json: the canteen's
## kitchen): the stretch [from, to] along the area, or ZERO.
func _alcove(seg: Dictionary, side: int) -> Vector2:
	var a := _alcove_data(seg, side)
	if a.is_empty():
		return Vector2.ZERO
	return Vector2(float(a["at"]), float(a["at"]) + float(a.get("length", 16.0)))


## The alcove on this side ("alcove" in route.json: one, or a list, one per side at most), or {}.
func _alcove_data(seg: Dictionary, side: int) -> Dictionary:
	var raw = _graph.node_data(seg["id"]).get("alcove", [])
	var list: Array = raw if raw is Array else [raw]
	for a in list:
		if a is Dictionary and (-1 if String(a.get("side", "right")) == "left" else 1) == side:
			return a
	return {}


## The STAFF CANTEEN's kitchen (user reference), built into the side wall behind the opening: a
## serving counter along the opening with a glass sneeze guard and trays of food under warm
## lights, three lit menu boards on the header above, and behind it steel fridges, a range with a
## hood, a prep table, stacked pizza boxes, white tiles and its own warm light.
func _build_kitchen(parent: Node3D, seg: Dictionary, side: int, span: Vector2) -> void:
	var wx := side * (tuning.lane_count * tuning.lane_width / 2.0 + 1.0)  # the wall's line
	var depth := 4.0
	var mid := (span.x + span.y) / 2.0
	var L := span.y - span.x
	var inx := func(d: float) -> float: return wx + side * d  # d metres back from the opening
	var tile := PsxMaterials.textured(PsxTextures.kitchen_tile(), Vector2(maxf(1.0, L / 2.0), 2))
	var steel := Color("8a9094")
	var dark := Color("2a2d30")
	# The room: floor, ceiling, back and end walls, a header over the opening.
	_item_box(parent, seg, mid, Vector3(inx.call(depth / 2.0), 0.0, 0), Vector3(depth, 0.06, L), Color.WHITE).material_override = \
			PsxMaterials.textured(PsxTextures.canteen_floor(), Vector2(depth / 1.4, L / 1.4))
	_item_box(parent, seg, mid, Vector3(inx.call(depth / 2.0), CEILING_Y, 0), Vector3(depth + 0.2, 0.08, L), Color.WHITE).material_override = \
			PsxMaterials.textured(PsxTextures.office_ceiling(), Vector2(depth / 1.5, L / 1.5))
	_item_box(parent, seg, mid, Vector3(inx.call(depth), CEILING_Y / 2.0, 0), Vector3(0.12, CEILING_Y, L), Color.WHITE).material_override = tile
	for z in [span.x, span.y]:
		_item_box(parent, seg, z, Vector3(inx.call(depth / 2.0), CEILING_Y / 2.0, 0), Vector3(depth, CEILING_Y, 0.12), Color.WHITE).material_override = tile
		_item_box(parent, seg, z, Vector3(wx, CEILING_Y / 2.0, 0), Vector3(0.5, CEILING_Y, 0.5), theme_color(seg).darkened(0.5))  # the opening's pillars
	_item_box(parent, seg, mid, Vector3(wx, (2.9 + CEILING_Y) / 2.0, 0), Vector3(0.3, CEILING_Y - 2.9, L), Color.WHITE).material_override = \
			PsxMaterials.textured(PsxTextures.canteen_wall(), Vector2(L / 2.0, 1))
	# Three lit menu boards on the header, facing the road.
	for k in 3:
		var bz := mid + (k - 1) * 2.0
		_item_box(parent, seg, bz, Vector3(wx - side * 0.17, 3.45, 0), Vector3(0.04, 0.8, 1.7), dark)
		_item_box(parent, seg, bz, Vector3(wx - side * 0.2, 3.45, 0), Vector3(0.02, 0.7, 1.6), Color.WHITE).material_override = \
				PsxMaterials.textured(PsxTextures.menu_board(k), Vector2(3, 2), true)
	# The serving counter along the opening, its sneeze guard, the food under warm lights.
	var cl := L - 1.2
	_item_box(parent, seg, mid, Vector3(inx.call(0.45), 0.47, 0), Vector3(0.8, 0.94, cl), Color("4a4e52"))
	_item_box(parent, seg, mid, Vector3(inx.call(0.45), 0.96, 0), Vector3(0.9, 0.05, cl + 0.1), steel)
	_item_box(parent, seg, mid, Vector3(inx.call(0.3), 1.26, 0), Vector3(0.03, 0.42, cl - 1.0), Color.WHITE).material_override = \
			PsxMaterials.glass(Color(0.7, 0.82, 0.86, 0.25))
	_item_box(parent, seg, mid, Vector3(inx.call(0.42), 1.48, 0), Vector3(0.36, 0.04, cl - 1.0), steel)
	_item_box(parent, seg, mid, Vector3(inx.call(0.5), 1.45, 0), Vector3(0.2, 0.03, cl - 1.2), Color.WHITE).material_override = \
			PsxMaterials.glow(Color("ffd890"))  # the heat lamps
	var foods := [Color("d8902a"), Color("6aa040"), Color("e0d0a0"), Color("8a4a24"), Color("c84a2a")]
	var fz := span.x + 1.1
	var n := 0
	while fz < span.y - 1.1:
		_item_box(parent, seg, fz, Vector3(inx.call(0.55), 1.02, 0), Vector3(0.42, 0.07, 0.55), foods[n % foods.size()])
		fz += 0.7
		n += 1
	# Behind: fridges, a range with a hood, a prep table, pizza boxes.
	for fz2 in [span.x + 1.4, span.x + 2.5, span.y - 1.4]:
		_item_box(parent, seg, fz2, Vector3(inx.call(depth - 0.5), 1.1, 0), Vector3(0.8, 2.2, 1.0), Color.WHITE).material_override = \
				PsxMaterials.textured(PsxTextures.fridge(), Vector2(3, 2))
	_item_box(parent, seg, mid + 1.2, Vector3(inx.call(depth - 0.45), 0.45, 0), Vector3(0.8, 0.9, 1.4), steel)  # range
	_item_box(parent, seg, mid + 1.2, Vector3(inx.call(depth - 0.08), 0.5, 0), Vector3(0.02, 0.4, 1.0), dark)  # oven door glass
	_item_box(parent, seg, mid + 1.2, Vector3(inx.call(depth - 0.4), 2.6, 0), Vector3(0.9, 0.5, 1.5), steel.darkened(0.2))  # hood
	_item_box(parent, seg, mid - 1.0, Vector3(inx.call(2.1), 0.45, 0), Vector3(0.9, 0.9, 1.8), steel)  # prep table
	for k in 4:
		_item_box(parent, seg, span.y - 2.4, Vector3(inx.call(0.5), 1.02 + k * 0.08, 0), Vector3(0.48, 0.07, 0.48), Color("c8a46a"))  # pizza boxes
	for k in 2:  # its own lights
		_item_box(parent, seg, mid + (k - 0.5) * L * 0.5, Vector3(inx.call(depth / 2.0), CEILING_Y - 0.05, 0), Vector3(0.5, 0.05, 1.4), Color.WHITE).material_override = \
				PsxMaterials.glow(Color("fff0c8"))
	var light := Node3D.new()
	parent.add_child(light)
	light.transform = _frame_at(seg, mid) * Transform3D(Basis.IDENTITY, Vector3(inx.call(1.6), 3.0, 0))
	_ambience.add_lamp(light, Color(1.0, 0.86, 0.55) * 1.8, 7.0, {"alert": false})


func theme_color(seg: Dictionary) -> Color:
	return _theme(seg["id"])["color"]


## The STAFF CANTEEN's walls (user reference): snack machines, notice boards with posters, a
## potted plant and a bin, doors with card readers; on a set rhythm, never in the kitchen opening.
func _canteen_decor(parent: Node3D, seg: Dictionary, side: int, from: float, to: float) -> void:
	var face := side * (tuning.lane_count * tuning.lane_width / 2.0 + 1.0 - 0.03)
	var red := PsxMaterials.glow(Color(1.0, 0.18, 0.12))
	var kitchen := _alcove(seg, side)
	for i in range(ceili(from / 5.0) * 5, int(to) - 3, 5):
		var at := i + 2.5
		if kitchen != Vector2.ZERO and at > kitchen.x - 2.0 and at < kitchen.y + 2.0:
			continue
		var near_bend := false
		for leg in seg["legs"]:
			if absf(leg["start"] - at) < 1.3:
				near_bend = true
		if near_bend:
			continue
		var holder := Node3D.new()
		parent.add_child(holder)
		holder.transform = _frame_at(seg, at) * Transform3D(Basis.IDENTITY, Vector3(face, 0, 0))
		var out := -float(side)
		match (i / 5 + (1 if side > 0 else 3)) % 5:
			0:  # a snack machine against the wall
				_box(holder, Vector3(0.75, 2.2, 1.0), Vector3(out * 0.38, 1.1, 0), Color("1e2430"))
				var front := _box(holder, Vector3(0.03, 1.95, 0.86), Vector3(out * 0.76, 1.1, 0), Color.WHITE)
				front.material_override = PsxMaterials.textured(PsxTextures.vending_front(1), Vector2(3, 2), true)
			1:  # a notice board with papers and a poster
				_box(holder, Vector3(0.05, 0.95, 1.5), Vector3(out * 0.03, 1.6, 0), Color("5a4a36"))
				_box(holder, Vector3(0.02, 0.85, 1.4), Vector3(out * 0.06, 1.6, 0), Color.WHITE).material_override = \
						PsxMaterials.textured(PsxTextures.notice_board(), Vector2(3, 2))
			2:  # a potted plant and a bin
				_box(holder, Vector3(0.45, 0.5, 0.45), Vector3(out * 0.32, 0.25, -0.35), Color("3a3a36"))
				for k in 5:
					var leaf := _box(holder, Vector3(0.08, 0.6, 0.22), Vector3(out * 0.32, 0.8, -0.35), Color("3a6a2a").lightened(0.08 * (k % 3)))
					leaf.rotation = Vector3(0.5 * cos(k * 1.3), k * 1.25, 0.5 * sin(k * 1.3))
				var bin := MeshInstance3D.new()
				var cyl := CylinderMesh.new()
				cyl.top_radius = 0.24
				cyl.bottom_radius = 0.2
				cyl.height = 0.7
				cyl.radial_segments = 10
				bin.mesh = cyl
				bin.material_override = PsxMaterials.flat(Color("5a6064"))
				holder.add_child(bin)
				bin.position = Vector3(out * 0.3, 0.35, 0.45)
			3:  # a door with a card reader
				_box(holder, Vector3(0.06, DOOR_H, DOOR_W), Vector3(out * 0.03, DOOR_H / 2.0, 0), Color.WHITE).material_override = \
						PsxMaterials.textured(PsxTextures.door(), Vector2(3, 2))
				_box(holder, Vector3(0.12, DOOR_H + 0.1, DOOR_W + 0.2), Vector3(out * 0.0, (DOOR_H + 0.1) / 2.0, 0), Color("3a3c3e"))
				_card_reader(holder, out, 0.85, red)


## Litter on the canteen floor (user reference): dropped trays, papers, paper cups, coffee spills.
func _canteen_litter(parent: Node3D, seg: Dictionary, from: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seg["id"]) + 7
	var half := tuning.lane_count * tuning.lane_width / 2.0 - 0.3
	var at := maxf(from, 30.0)
	while at < float(seg["length"]) - 4.0:
		var x := rng.randf_range(-half, half)
		match rng.randi() % 4:
			0:
				_item_box(parent, seg, at, Vector3(x, 0.012, 0), Vector3(0.6, 0.004, 0.42), Color("3a2414"))  # spill
			1:
				var tray := _item_box(parent, seg, at, Vector3(x, 0.02, 0), Vector3(0.42, 0.02, 0.32), Color("c4c8c4"))
				tray.rotation.y += rng.randf_range(-0.6, 0.6)
			2:
				var sheet := _item_box(parent, seg, at, Vector3(x, 0.01, 0), Vector3(0.3, 0.005, 0.22), Color("e4e0d4"))
				sheet.rotation.y += rng.randf_range(-1.0, 1.0)
			3:
				var cup := _item_box(parent, seg, at, Vector3(x, 0.05, 0), Vector3(0.1, 0.1, 0.13), Color("c42020"))
				cup.rotation = Vector3(0, rng.randf_range(0, TAU), PI / 2.0)  # knocked over
		at += rng.randf_range(4.0, 8.0)


## A WAREHOUSE dome lamp hanging on its cable over the road: a dark shade, a bright bulb, and a
## cone of cold light down through the haze.
func _pendant_lamp(parent: Node3D, seg: Dictionary, z: float, failing: bool) -> void:
	var y := CEILING_Y - 1.0
	_item_box(parent, seg, z, Vector3(0, (y + CEILING_Y) / 2.0, 0), Vector3(0.03, CEILING_Y - y, 0.03), Color("1a1a1a"))  # cable
	var shade := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.12
	cone.bottom_radius = 0.42
	cone.height = 0.32
	cone.radial_segments = 10
	cone.cap_bottom = false
	shade.mesh = cone
	shade.material_override = PsxMaterials.flat(Color("2a2e30"))
	parent.add_child(shade)
	shade.transform = _frame_at(seg, z) * Transform3D(Basis.IDENTITY, Vector3(0, y, 0))
	var on := PsxMaterials.glow(Color("eef4ee"))
	var bulb := _item_box(parent, seg, z, Vector3(0, y - 0.14, 0), Vector3(0.26, 0.06, 0.26), Color.WHITE)
	bulb.material_override = on
	var haze := MeshInstance3D.new()
	var beam := CylinderMesh.new()
	beam.top_radius = 0.35
	beam.bottom_radius = 1.6
	beam.height = 2.6
	beam.radial_segments = 10
	beam.cap_top = false
	beam.cap_bottom = false
	haze.mesh = beam
	haze.material_override = PsxMaterials.beam(Color(0.85, 0.92, 1.0, 0.07))
	parent.add_child(haze)
	haze.transform = _frame_at(seg, z) * Transform3D(Basis.IDENTITY, Vector3(0, y - 1.45, 0))
	var at := Node3D.new()
	parent.add_child(at)
	at.transform = _frame_at(seg, z) * Transform3D(Basis.IDENTITY, Vector3(0, y - 1.0, 0))
	_ambience.add_lamp(at, Color(0.85, 0.95, 1.0) * 2.0, 8.0, {"flicker": 0.3 if failing else 0.0,
			"fixture": bulb, "on_mat": on, "off_mat": PsxMaterials.flat(Color("6a6e70"))})


## The WAREHOUSE's walls (user reference): tall pallet racking in the strip beside the road, the
## pillars as its uprights (with yellow-and-black guards at their feet), three shelf levels of
## beams, and on every shelf crates, cases and boxes on pallets.
func _warehouse_racks(parent: Node3D, seg: Dictionary, side: int, from: float, to: float) -> void:
	var road_half := tuning.lane_count * tuning.lane_width / 2.0
	var front := side * (road_half + 0.12)
	var back := side * (road_half + 0.95)
	var mid := (front + back) / 2.0
	var beam := Color("3a4450")
	var guard := PsxMaterials.textured(PsxTextures.hazard(), Vector2(1, 1))
	for i in range(ceili(from / 5.0) * 5, int(to) - 4, 5):
		var near_bend := false
		for leg in seg["legs"]:
			if leg["start"] > i - 1.0 and leg["start"] < i + 6.0:
				near_bend = true
		if near_bend:
			continue
		var at := i + 2.5
		_item_box(parent, seg, i, Vector3(side * (road_half + 0.8), 0.3, 0.0), Vector3(0.42, 0.6, 0.42), Color.WHITE).material_override = guard
		for level in 3:
			var y := 0.0 if level == 0 else 1.45 * level
			if level > 0:
				for bx in [front, back]:
					_item_box(parent, seg, at, Vector3(bx, y, 0), Vector3(0.1, 0.12, 4.9), beam)
				_item_box(parent, seg, at, Vector3(mid, y + 0.07, 0), Vector3(0.84, 0.03, 4.8), Color("2a2e32"))  # the shelf deck
			var rng := RandomNumberGenerator.new()
			rng.seed = hash([seg["id"], i, side, level])
			var z := -2.2
			while z < 2.0:
				var w := rng.randf_range(1.0, 1.5)
				if z + w > 2.3:
					break
				var slot := Node3D.new()
				parent.add_child(slot)
				slot.transform = _frame_at(seg, at) * Transform3D(Basis.IDENTITY, Vector3(mid, y + (0.13 if level > 0 else 0.0), z + w / 2.0))
				slot.rotation.y = PI / 2.0  # pallets face the road
				if rng.randf() < 0.85:
					_pallet(slot, Vector3.ZERO, w - 0.08, 0.8)
					var h := rng.randf_range(0.6, 1.1)
					_stock(slot, Vector3(0, 0.14, 0), Vector3(w - 0.15, h, 0.72), rng.randi() % 4)
				z += w + 0.05


## The WAREHOUSE roof structure (user reference): red steel cross beams every 10 m, and a
## yellow-and-black crane rail down one side of the road with a trolley and a hook.
func _warehouse_overhead(parent: Node3D, seg: Dictionary, from: float) -> void:
	var road_w := tuning.lane_count * tuning.lane_width
	var length: float = seg["length"]
	var z := maxf(from, 12.0)
	while z < length - 2.0:
		_item_box(parent, seg, z, Vector3(0, CEILING_Y - 0.25, 0), Vector3(road_w + 2.0, 0.34, 0.3), Color("6a2a22"))
		z += 10.0
	var rail := PsxMaterials.textured(PsxTextures.hazard(), Vector2(1, 6))
	for piece in _pieces(seg, maxf(from, 12.0), length - 2.0):
		var mid := (piece.x + piece.y) / 2.0
		_item_box(parent, seg, mid, Vector3(1.6, CEILING_Y - 0.55, 0), Vector3(0.36, 0.3, piece.y - piece.x), Color.WHITE).material_override = rail
	var hz := minf(length * 0.6, length - 6.0)
	_item_box(parent, seg, hz, Vector3(1.6, CEILING_Y - 0.85, 0), Vector3(0.7, 0.36, 0.9), Color("d8a020"))  # trolley
	_item_box(parent, seg, hz, Vector3(1.6, CEILING_Y - 1.55, 0), Vector3(0.04, 1.1, 0.04), Color("2a2a2a"))  # cable
	_item_box(parent, seg, hz, Vector3(1.6, CEILING_Y - 2.2, 0), Vector3(0.22, 0.26, 0.12), Color("2a2a2a"))  # hook block
	_item_box(parent, seg, hz, Vector3(1.6, CEILING_Y - 2.42, 0.06), Vector3(0.06, 0.2, 0.18), Color("8a8a84"))  # the hook


## Yellow lines painted along the edges of the road, and across it now and then (the WAREHOUSE).
func _floor_lines(parent: Node3D, seg: Dictionary, from: float) -> void:
	var road_half := tuning.lane_count * tuning.lane_width / 2.0
	var yellow := PsxTextures.wall("blocks", Color("c9a227"))
	for piece in _pieces(seg, from, float(seg["length"])):
		for s in [-1.0, 1.0]:
			_strip(parent, seg, piece.x, piece.y, s * (road_half - 0.15), 0.12, 0.013, yellow, 1.0, 4.0)
	var at := maxf(from, 14.0) + 4.0
	while at < float(seg["length"]) - 4.0:
		var ok := true
		for leg in seg["legs"]:
			if absf(leg["start"] - at) < 1.5:
				ok = false
		if ok:
			_strip(parent, seg, at, at + 0.12, 0.0, road_half * 2.0, 0.013, yellow, 1.0, 4.0)
		at += 18.0


## A LOADING DOCK bay (user reference), built into the side wall behind the opening: two roll-up
## doors rolled up under a hazard-striped header, a pillar between, steel dock-leveller plates on
## the floor, yellow-and-black bumper posts, and outside a night yard: asphalt, a trailer backed up
## to the first door with its tail lights on, a lamp post, crates on pallets, a chain-link fence,
## and the city's lit windows on the skyline beyond.
func _build_bay(parent: Node3D, seg: Dictionary, side: int, span: Vector2) -> void:
	var road_half := tuning.lane_count * tuning.lane_width / 2.0
	var wx := side * (road_half + 1.0)
	var mid := (span.x + span.y) / 2.0
	var L := span.y - span.x
	var out := func(d: float) -> float: return wx + side * d  # d metres outside the wall line
	var dh := 3.4  # the doorways' height
	var hazard := PsxMaterials.textured(PsxTextures.hazard(), Vector2(L / 0.8, 1))
	var steel := Color("3e4448")
	# The header over the doorways, a hazard band along its bottom, and the rolled-up doors in it.
	_item_box(parent, seg, mid, Vector3(wx, (dh + CEILING_Y) / 2.0, 0), Vector3(0.4, CEILING_Y - dh, L), Color.WHITE).material_override = \
			PsxMaterials.textured(PsxTextures.dock_wall(), Vector2(L / 2.0, 1))
	_item_box(parent, seg, mid, Vector3(wx - side * 0.21, dh + 0.12, 0), Vector3(0.03, 0.24, L), Color.WHITE).material_override = hazard
	for k in 2:
		var dz := mid + (k - 0.5) * L / 2.0
		_item_box(parent, seg, dz, Vector3(out.call(0.05), dh + 0.42, 0), Vector3(0.5, 0.5, L / 2.0 - 0.6), steel)  # the rolled door
		_item_box(parent, seg, dz, Vector3(out.call(0.0), dh - 0.08, 0), Vector3(0.12, 0.14, L / 2.0 - 0.6), Color.WHITE).material_override = \
				PsxMaterials.textured(PsxTextures.roller_shutter(), Vector2(3, 1))  # its bottom edge, just showing
		# The dock leveller: a steel plate across the strip beside the road, in the doorway.
		_item_box(parent, seg, dz, Vector3(side * (road_half + 0.5), 0.02, 0), Vector3(1.0, 0.04, L / 2.0 - 0.8), Color.WHITE).material_override = \
				PsxMaterials.textured(PsxTextures.vent(), Vector2(2, 4))
	for z in [span.x, mid, span.y]:  # the pillars, and bumper posts beside each doorway
		_item_box(parent, seg, z, Vector3(wx, dh / 2.0, 0), Vector3(0.6, dh, 0.6), theme_color(seg))
		for dz in [-0.45, 0.45]:
			if (z == span.x and dz < 0) or (z == span.y and dz > 0):
				continue
			_item_box(parent, seg, z + dz, Vector3(side * (road_half + 0.6), 0.55, 0), Vector3(0.28, 1.1, 0.28), Color.WHITE).material_override = \
					PsxMaterials.textured(PsxTextures.hazard(), Vector2(1, 2))
	# Outside: the yard.
	var depth := 18.0
	var yard_len := L + 12.0
	_item_box(parent, seg, mid, Vector3(out.call(depth / 2.0), -0.02, 0), Vector3(depth, 0.04, yard_len), Color.WHITE).material_override = \
			PsxMaterials.textured(PsxTextures.asphalt(), Vector2(depth / 4.0, yard_len / 4.0))
	# The trailer backed up to the first door: a box body on its axles, tail lights toward you.
	var tz := mid - L / 4.0
	_item_box(parent, seg, tz, Vector3(out.call(4.6), 2.15, 0), Vector3(7.6, 2.5, 2.4), Color("b8bcbc"))
	_item_box(parent, seg, tz, Vector3(out.call(0.85), 2.15, 0), Vector3(0.1, 2.4, 2.3), Color("8a8e90"))  # the doors at the back
	for s in [-1.0, 1.0]:
		_item_box(parent, seg, tz + s * 1.0, Vector3(out.call(0.82), 1.05, 0), Vector3(0.06, 0.16, 0.26), Color.WHITE).material_override = \
				PsxMaterials.glow(Color(1.0, 0.15, 0.1))
		for ax in [2.0, 3.2, 7.5]:
			_item_box(parent, seg, tz + s * 0.95, Vector3(out.call(ax), 0.45, 0), Vector3(0.9, 0.9, 0.35), Color("141414"))  # wheels
	_item_box(parent, seg, tz, Vector3(out.call(9.4), 1.6, 0), Vector3(2.0, 2.6, 2.4), Color("a83020"))  # the cab
	_item_box(parent, seg, tz, Vector3(out.call(8.4), 1.95, 0), Vector3(0.05, 0.9, 2.0), Color("26343e"))  # its windscreen
	# A lamp post with its orange light, crates on pallets, a chain-link fence, the skyline.
	var lz := mid + L / 4.0
	_item_box(parent, seg, lz, Vector3(out.call(9.0), 3.0, 0), Vector3(0.14, 6.0, 0.14), Color("2e3236"))
	var head := _item_box(parent, seg, lz, Vector3(out.call(8.6), 6.0, 0), Vector3(0.5, 0.12, 0.3), Color.WHITE)
	head.material_override = PsxMaterials.glow(Color("ffc070"))
	_ambience.add_lamp(head, Color(1.0, 0.64, 0.3) * 1.6, 12.0, {"alert": false})
	for k in 2:
		var holder := Node3D.new()
		parent.add_child(holder)
		holder.transform = _frame_at(seg, lz + 1.2 + k * 1.4) * Transform3D(Basis.IDENTITY, Vector3(out.call(4.0 + k * 1.6), 0, 0))
		_pallet(holder, Vector3.ZERO, 1.2, 1.0)
		_stock(holder, Vector3(0, 0.14, 0), Vector3(1.0, 0.9 + 0.2 * k, 0.9), k + 2)
	_item_box(parent, seg, mid, Vector3(out.call(13.0), 1.2, 0), Vector3(0.05, 2.4, yard_len), Color("3a4044"))  # the fence
	for z in range(int(mid - yard_len / 2.0), int(mid + yard_len / 2.0), 3):
		_item_box(parent, seg, float(z), Vector3(out.call(13.0), 1.25, 0), Vector3(0.08, 2.5, 0.08), Color("2a2e30"))
	var sky := _item_box(parent, seg, mid, Vector3(out.call(depth), 4.5, 0), Vector3(0.1, 9.0, yard_len + 6.0), Color.WHITE)
	sky.material_override = PsxMaterials.textured(PsxTextures.skyline(), Vector2(yard_len / 8.0, 1), true)


## The LOADING DOCK's walls (user reference): steel doors with a window and a red card reader,
## warm wall lamps, vents, red drums, crates on pallets, on a set rhythm; never in a bay.
func _dock_decor(parent: Node3D, seg: Dictionary, side: int, from: float, to: float) -> void:
	var face := side * (tuning.lane_count * tuning.lane_width / 2.0 + 1.0 - 0.03)
	var red := PsxMaterials.glow(Color(1.0, 0.18, 0.12))
	var bay := _alcove(seg, side)
	var lamps := 0
	for i in range(ceili(from / 5.0) * 5, int(to) - 3, 5):
		var at := i + 2.5
		if (bay != Vector2.ZERO and at > bay.x - 2.0 and at < bay.y + 2.0) or _is_outdoor(seg, at):
			continue
		var near_bend := false
		for leg in seg["legs"]:
			if absf(leg["start"] - at) < 1.3:
				near_bend = true
		if near_bend:
			continue
		var holder := Node3D.new()
		parent.add_child(holder)
		holder.transform = _frame_at(seg, at) * Transform3D(Basis.IDENTITY, Vector3(face, 0, 0))
		var out := -float(side)
		match (i / 5 + (2 if side > 0 else 0)) % 5:
			0:  # a steel door, a card reader, a warm lamp over it
				_box(holder, Vector3(0.06, DOOR_H, DOOR_W), Vector3(out * 0.03, DOOR_H / 2.0, 0), Color.WHITE).material_override = \
						PsxMaterials.textured(PsxTextures.steel_door(), Vector2(3, 2))
				_card_reader(holder, out, 0.9, red)
				var lamp := _box(holder, Vector3(0.14, 0.2, 0.2), Vector3(out * 0.08, DOOR_H + 0.4, 0), Color.WHITE)
				lamp.material_override = PsxMaterials.glow(Color("ffd890"))
				if lamps < 2:
					_ambience.add_lamp(lamp, Color(1.0, 0.8, 0.5) * 0.9, 3.5, {"alert": false})
					lamps += 1
			1:  # a vent grille
				_box(holder, Vector3(0.05, 0.7, 1.2), Vector3(out * 0.02, 2.6, 0), Color.WHITE).material_override = \
						PsxMaterials.textured(PsxTextures.vent(), Vector2(3, 2))
			2:  # red drums
				for dz in [-0.3, 0.3]:
					_drum(holder, Vector3(out * 0.35, 0, dz), Color("8a2418"))
			3:  # crates on a pallet against the wall
				_pallet(holder, Vector3(out * 0.5, 0, 0), 0.9, 1.3)
				_stock(holder, Vector3(out * 0.5, 0.14, 0), Vector3(0.8, 0.8, 1.2), 1)
				_stock(holder, Vector3(out * 0.5, 0.94, 0.1), Vector3(0.6, 0.45, 0.6), 2)


## The LOADING DOCK's ceiling (user reference): red pipes along it near both walls, and dark
## steel beams across every 10 m.
func _dock_overhead(parent: Node3D, seg: Dictionary, from: float) -> void:
	var road_w := tuning.lane_count * tuning.lane_width
	var length: float = seg["length"]
	for piece in _pieces_except(seg, maxf(from, 12.0), length - 1.0, _outdoor(seg)):
		var mid := (piece.x + piece.y) / 2.0
		for s in [-1.0, 1.0]:
			_item_box(parent, seg, mid, Vector3(s * (road_w / 2.0 - 0.3), CEILING_Y - 0.35, 0), Vector3(0.22, 0.22, piece.y - piece.x), Color("8a2a20"))
	var z := maxf(from, 12.0)
	while z < length - 2.0:
		if not _is_outdoor(seg, z):
			_item_box(parent, seg, z, Vector3(0, CEILING_Y - 0.15, 0), Vector3(road_w + 2.0, 0.3, 0.35), Color("2a2e32"))
		z += 10.0


## LOADING DOCK jump obstacle: a low concrete bumper block with yellow-and-black stripes.
func _build_bumper(parent: Node3D, seg: Dictionary, at: float, x: float, _lane: int) -> Node3D:
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.transform = _frame_at(seg, at) * Transform3D(Basis.IDENTITY, Vector3(x, 0, 0))
	_box(holder, Vector3(tuning.lane_width - 0.2, 0.42, 0.5), Vector3(0, 0.21, 0), Color("7a7e7c"))
	_box(holder, Vector3(tuning.lane_width - 0.18, 0.24, 0.02), Vector3(0, 0.24, 0.26), Color.WHITE).material_override = \
			PsxMaterials.textured(PsxTextures.hazard(), Vector2(2, 1))
	_box(holder, Vector3(tuning.lane_width - 0.24, 0.06, 0.44), Vector3(0, 0.45, 0), Color("8a8e8c"))  # chamfered top
	return holder


## The LOADING DOCK's yard (user: "a part of the loading bay go outside"): over [o.x, o.y] the road
## runs out of the building through a big raised roll-up door and back in through another. Out
## here: open night sky, asphalt with lane lines, a wide apron each side with lorries parked along
## the road (tail and marker lights on), lamp posts throwing orange light, crates and pallets, and a
## chain-link fence; the building's front wall towers over each door.
func _build_yard(parent: Node3D, seg: Dictionary, o: Vector2) -> void:
	var road_half := tuning.lane_count * tuning.lane_width / 2.0
	var asphalt := PsxTextures.yard_asphalt()  # no lane lines out here (user)
	for piece in _pieces(seg, o.x, o.y):
		_strip(parent, seg, piece.x, piece.y, 0.0, road_half * 2.0, 0.006, asphalt, float(tuning.lane_count), 4.0)
		for s in [-1.0, 1.0]:
			_strip(parent, seg, piece.x, piece.y, s * (road_half + 6.5), 13.0, 0.0, asphalt, 3.0, 4.0)  # the apron
	# The building's front wall at each door, with the door rolled up and a lamp over it.
	for z in [o.x, o.y]:
		var facade := PsxMaterials.textured(PsxTextures.dock_wall(), Vector2(4, 2))
		var span := road_half + 13.0
		for s in [-1.0, 1.0]:
			_item_box(parent, seg, z, Vector3(s * (road_half + 0.6 + (span - road_half - 0.6) / 2.0), 4.5, 0),
					Vector3(span - road_half - 0.6, 9.0, 0.5), Color.WHITE).material_override = facade
		_item_box(parent, seg, z, Vector3(0, (3.8 + 9.0) / 2.0, 0), Vector3(road_half * 2.0 + 1.3, 9.0 - 3.8, 0.5), Color.WHITE).material_override = facade
		_item_box(parent, seg, z, Vector3(0, 4.1, 0), Vector3(road_half * 2.0 + 1.0, 0.55, 0.7), Color("3e4448"))  # the rolled-up door
		_item_box(parent, seg, z, Vector3(0, 3.82, 0), Vector3(road_half * 2.0 + 1.0, 0.1, 0.72), Color.WHITE).material_override = \
				PsxMaterials.textured(PsxTextures.hazard(), Vector2(10, 1))
		var lamp := _item_box(parent, seg, z, Vector3(0, 4.6, 0.4 if z == o.x else -0.4), Vector3(0.6, 0.2, 0.2), Color.WHITE)
		lamp.material_override = PsxMaterials.glow(Color("ffd890"))
		_ambience.add_lamp(lamp, Color(1.0, 0.8, 0.5) * 1.4, 7.0, {"alert": false})
	# Lorries backed up to the road, three each side, so you see their backs (user).
	var lorries := [[o.x + 9.0, -1.0], [o.x + 12.4, -1.0], [o.x + 15.8, -1.0], [o.x + 23.0, 1.0], [o.x + 26.4, 1.0], [o.x + 29.8, 1.0]]
	for i in lorries.size():
		var l: Array = lorries[i]
		if l[0] + 2.0 < o.y:
			_lorry(parent, seg, l[0], int(l[1]), i)  # each with its own story
	# Lamp posts, alternating sides.
	var z := o.x + 6.0
	var n := 0
	while z < o.y - 4.0:
		var s := -1.0 if n % 2 == 0 else 1.0
		_item_box(parent, seg, z, Vector3(s * (road_half + 0.7), 3.0, 0), Vector3(0.14, 6.0, 0.14), Color("2e3236"))
		_item_box(parent, seg, z, Vector3(s * (road_half + 0.3), 6.0, 0), Vector3(0.9, 0.08, 0.1), Color("2e3236"))
		var head := _item_box(parent, seg, z, Vector3(s * road_half, 5.92, 0), Vector3(0.4, 0.12, 0.26), Color.WHITE)
		head.material_override = PsxMaterials.glow(Color("ffc070"))
		_ambience.add_lamp(head, Color(1.0, 0.64, 0.3) * 1.6, 11.0, {"alert": false})
		z += 13.0
		n += 1
	# Crates and pallets on the aprons, and the fence round the yard.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seg["id"]) + 11
	for c in [[o.x + 24.0, -1.0], [o.x + 31.0, -1.0], [o.x + 8.0, 1.0], [o.x + 13.0, 1.0]]:  # in the gaps between the lorries
		var cz: float = c[0]
		var holder := Node3D.new()
		parent.add_child(holder)
		var sx: float = c[1] * (road_half + rng.randf_range(3.0, 6.0))
		holder.transform = _frame_at(seg, cz) * Transform3D(Basis(Vector3.UP, rng.randf_range(-0.4, 0.4)), Vector3(sx, 0, 0))
		_pallet(holder, Vector3.ZERO, 1.2, 1.0)
		_stock(holder, Vector3(0, 0.14, 0), Vector3(1.0, rng.randf_range(0.6, 1.1), 0.9), rng.randi() % 4)
	for piece in _pieces(seg, o.x, o.y):
		var mid := (piece.x + piece.y) / 2.0
		for s in [-1.0, 1.0]:
			_item_box(parent, seg, mid, Vector3(s * (road_half + 12.5), 1.3, 0), Vector3(0.04, 2.6, piece.y - piece.x), Color("3a4044"))
	var post := o.x + 1.5
	while post < o.y:
		for s in [-1.0, 1.0]:
			_item_box(parent, seg, post, Vector3(s * (road_half + 12.5), 1.35, 0), Vector3(0.08, 2.7, 0.08), Color("2a2e30"))
		post += 3.0


## A lorry backed up to the road on `side` (-1 left, 1 right) at `z`: a box trailer on its wheels,
## the cab at the far end, side markers, its back toward the road. `story` (user: "think about
## storytelling with object placement") says what's going on round it, a delivery cut short:
##   0 half unloaded: doors open, cargo still inside under a dim light, a loaded pallet behind it
##     with a pallet jack and a clipboard on a crate;
##   1 sealed: doors shut, wheel chocks in;
##   2 unloaded in a hurry: doors open, nearly empty, a dropped crate split open, boxes spilled, a
##     cone knocked over;
##   3 just arrived: doors shut, a cone set out behind it;
##   4 being loaded: doors open, cargo inside, two stacked pallets waiting at the back, a pallet jack;
##   5 sealed.
func _lorry(parent: Node3D, seg: Dictionary, z: float, side: int, story: int) -> void:
	var holder := Node3D.new()
	parent.add_child(holder)
	var tl := 9.0
	var road_half := tuning.lane_count * tuning.lane_width / 2.0
	# The trailer runs out from the road: its local +z (the back) turned to face the road.
	holder.transform = _frame_at(seg, z) * Transform3D(Basis(Vector3.UP, -side * PI / 2.0), Vector3(side * (road_half + 1.6 + tl / 2.0), 0, 0))
	var white := Color("c4c8c8")
	var open := story in [0, 2, 4]
	var back := tl / 2.0
	if open:
		# Hollow, so you can see in: floor, roof, sides, front; dark inside, a dim light.
		_box(holder, Vector3(2.5, 0.1, tl), Vector3(0, 1.05, 0), Color("5a5650"))  # floor
		_box(holder, Vector3(2.5, 0.08, tl), Vector3(0, 3.76, 0), white)  # roof
		for s in [-1.0, 1.0]:
			_box(holder, Vector3(0.06, 2.8, tl), Vector3(s * 1.22, 2.4, 0), white)
		_box(holder, Vector3(2.5, 2.8, 0.06), Vector3(0, 2.4, -back + 0.03), white)
		_box(holder, Vector3(2.36, 2.6, 0.02), Vector3(0, 2.4, -back + 0.08), Color("1e1e1c"))  # the dark inside face
		_box(holder, Vector3(0.6, 0.04, 0.2), Vector3(0, 3.7, 0), Color.WHITE).material_override = PsxMaterials.glow(Color("d8d0a8"))
		for s in [-1.0, 1.0]:  # the rear doors, swung right round against the sides
			var hinge := Node3D.new()
			holder.add_child(hinge)
			hinge.position = Vector3(s * 1.25, 0, back)
			hinge.rotation.y = s * 1.75
			_box(hinge, Vector3(1.2, 2.6, 0.05), Vector3(-s * 0.6, 2.4, 0), Color("9a9ea0"))
	else:
		_box(holder, Vector3(2.5, 2.8, tl), Vector3(0, 2.4, 0), white)  # the box trailer
		_box(holder, Vector3(2.4, 2.6, 0.06), Vector3(0, 2.4, back + 0.02), Color("9a9ea0"))  # rear doors
		_box(holder, Vector3(0.05, 2.5, 0.08), Vector3(0, 2.4, back + 0.06), Color("5a5e60"))  # the split between them
		for s in [-1.0, 1.0]:
			_box(holder, Vector3(0.04, 0.5, 0.06), Vector3(s * 0.35, 2.0, back + 0.08), Color("3a3e40"))  # locking bars
	_box(holder, Vector3(2.52, 0.12, tl), Vector3(0, 1.0, 0), Color("4a4e52"))  # chassis rail
	_box(holder, Vector3(2.5, 0.16, 0.2), Vector3(0, 0.82, back + 0.05), Color("2a2a2a"))  # rear bumper
	for s in [-1.0, 1.0]:
		_box(holder, Vector3(0.24, 0.16, 0.05), Vector3(s * 0.95, 1.08, back + 0.08), Color.WHITE).material_override = \
				PsxMaterials.glow(Color(1.0, 0.15, 0.1))  # tail lights, toward the road
		for wz in [back - 1.2, back - 2.4, -back - 1.4]:
			_box(holder, Vector3(0.35, 0.9, 0.9), Vector3(s * 1.0, 0.45, wz), Color("141414"))
		for mz in [-3.0, 0.0, 3.0]:
			_box(holder, Vector3(0.04, 0.08, 0.14), Vector3(s * 1.27, 1.2, mz), Color.WHITE).material_override = \
					PsxMaterials.glow(Color("ff9a30"))  # side markers
	_box(holder, Vector3(2.4, 2.7, 2.2), Vector3(0, 1.75, -back - 1.4), Color("2a4a7a"))  # the cab, at the far end
	# What is going on round it.
	match story:
		0:  # half unloaded
			for k in 3:
				_stock(holder, Vector3((k - 1) * 0.75, 1.1, -back + 1.0 + (k % 2) * 0.9), Vector3(0.7, 0.8 + 0.2 * (k % 2), 0.8), k)
			_stock(holder, Vector3(-0.3, 1.1, -back + 2.6), Vector3(0.9, 1.4, 0.9), 1)
			_pallet(holder, Vector3(0.4, 0, back + 0.75), 1.1, 0.95)
			_stock(holder, Vector3(0.4, 0.14, back + 0.75), Vector3(0.95, 0.8, 0.85), 2)
			_box(holder, Vector3(0.3, 0.02, 0.22), Vector3(0.45, 0.95, back + 0.7), Color("e8e4d8")).rotation.y = 0.3  # the clipboard
			_pallet_jack(holder, Vector3(-0.75, 0, back + 0.85))
		1, 5:  # sealed: wheel chocks
			for s in [-1.0, 1.0]:
				_box(holder, Vector3(0.25, 0.22, 0.3), Vector3(s * 1.0, 0.11, back - 0.55), Color("d8a020"))
		2:  # unloaded in a hurry
			_stock(holder, Vector3(0.5, 1.1, -back + 0.9), Vector3(0.8, 0.9, 0.8), 3)
			var crate := _stock(holder, Vector3(-0.4, 0, back + 0.8), Vector3(0.95, 0.7, 0.85), 0)
			crate.rotation = Vector3(0.0, 0.4, 0.12)  # dropped, landed on its edge
			var lid := _box(holder, Vector3(1.0, 0.06, 0.9), Vector3(0.45, 0.06, back + 1.1), Color.WHITE)
			lid.material_override = PsxMaterials.textured(PsxTextures.crate_wood(), Vector2(3, 2))
			lid.rotation.y = -0.6  # its lid, knocked off
			for k in 3:
				var b := _stock(holder, Vector3(0.3 + k * 0.35, 0, back + 0.5 + (k % 2) * 0.4), Vector3(0.4, 0.3, 0.35), 2)
				b.rotation = Vector3(0, k * 0.9, (PI / 2.0) if k == 1 else 0.0)  # spilled cardboard boxes
			_cone(holder, Vector3(-1.0, 0, back + 1.2), true)
		3:  # just arrived
			_cone(holder, Vector3(0.9, 0, back + 0.9), false)
		4:  # being loaded
			for k in 2:
				_stock(holder, Vector3((k - 0.5) * 0.9, 1.1, -back + 1.0), Vector3(0.8, 1.0, 0.8), k + 1)
			for k in 2:
				_pallet(holder, Vector3((k - 0.5) * 1.15, 0, back + 0.75), 1.05, 0.95)
				_stock(holder, Vector3((k - 0.5) * 1.15, 0.14, back + 0.75), Vector3(0.9, 0.7, 0.85), 1 if k == 0 else 3)
				_stock(holder, Vector3((k - 0.5) * 1.15, 0.84, back + 0.75), Vector3(0.75, 0.5, 0.7), 2)
			_pallet_jack(holder, Vector3(1.4, 0, back + 0.3))


## A hand pallet jack: two forks, a body, a long handle tilted back.
func _pallet_jack(parent: Node3D, pos: Vector3) -> void:
	var red := Color("b02a1e")
	for dx in [-0.18, 0.18]:
		_box(parent, Vector3(0.14, 0.08, 1.1), pos + Vector3(dx, 0.05, -0.2), Color("3a3a3a"))  # forks
	_box(parent, Vector3(0.5, 0.3, 0.25), pos + Vector3(0, 0.2, 0.42), red)
	var handle := _box(parent, Vector3(0.06, 1.1, 0.06), pos + Vector3(0, 0.75, 0.6), red)
	handle.rotation.x = 0.35


## A traffic cone, standing or knocked over.
func _cone(parent: Node3D, pos: Vector3, knocked: bool) -> void:
	var cone := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = 0.04
	m.bottom_radius = 0.18
	m.height = 0.6
	m.radial_segments = 8
	cone.mesh = m
	cone.material_override = PsxMaterials.flat(Color("e06010"))
	parent.add_child(cone)
	cone.position = pos + Vector3(0, 0.3 if not knocked else 0.17, 0)
	if knocked:
		cone.rotation = Vector3(0, 0.8, PI / 2.0)
	_box(parent, Vector3(0.38, 0.04, 0.38), pos + (Vector3(0, 0.02, 0) if not knocked else Vector3(-0.32, 0.17, 0.05)), Color("1a1a1a"))  # its base


## The LOADING DOCK yard's duck-under (outdoors there's no ceiling to hang a chain from): a
## height-restriction gantry, a hazard-striped bar on two posts at head height.
func _build_gantry(parent: Node3D, seg: Dictionary, at: float, ends: Array) -> Node3D:
	var frame := _frame_at(seg, at)
	var e0: float = ends[0]["x"]
	var e1: float = ends[1]["x"]
	var gy := WIRE_LOW - 0.1
	var bar := _box(parent, Vector3(e1 - e0 + 0.3, 0.3, 0.2), Vector3.ZERO, Color.WHITE)
	bar.transform = frame * Transform3D(Basis.IDENTITY, Vector3((e0 + e1) / 2.0, gy, 0))
	bar.material_override = PsxMaterials.textured(PsxTextures.hazard(), Vector2((e1 - e0) / 0.8, 1))
	for px in [e0 - 0.1, e1 + 0.1]:
		_box(parent, Vector3(0.16, gy + 0.15, 0.16), Vector3.ZERO, Color("3a3e40")).transform = \
				frame * Transform3D(Basis.IDENTITY, Vector3(px, (gy + 0.15) / 2.0, 0))
	return bar


## MAIN FLOOR LOBBY jump obstacle (user: "the walk through barrier can be a full lane jump
## blocker"): a speed gate in each lane, a steel post with a red light either side and glass
## flaps closed across the lane.
func _build_speedgate(parent: Node3D, seg: Dictionary, at: float, x: float, lane: int) -> Node3D:
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.transform = _frame_at(seg, at) * Transform3D(Basis.IDENTITY, Vector3(x, 0, 0))
	var steel := Color("8a8e94")
	var red := PsxMaterials.glow(Color(1.0, 0.16, 0.12))
	var hw := tuning.lane_width / 2.0 - 0.1
	for s in [-1.0, 1.0]:
		if s < 0 or lane == tuning.lane_count - 1 or true:
			_box(holder, Vector3(0.16, 0.95, 0.5), Vector3(s * hw, 0.47, 0), steel)  # the gate posts
			_box(holder, Vector3(0.18, 0.04, 0.52), Vector3(s * hw, 0.96, 0), Color("4a4e52"))  # top
			_box(holder, Vector3(0.1, 0.08, 0.12), Vector3(s * hw, 0.85, 0.22), Color.WHITE).material_override = red
		# A glass flap from each post, meeting in the middle.
		_box(holder, Vector3(hw - 0.12, 0.42, 0.03), Vector3(s * (hw / 2.0), 0.5, 0), Color.WHITE).material_override = \
				PsxMaterials.glass(Color(0.7, 0.82, 0.86, 0.3))
		_box(holder, Vector3(hw - 0.12, 0.03, 0.04), Vector3(s * (hw / 2.0), 0.72, 0), steel)  # its top edge
	return holder


## The MAIN FLOOR LOBBY's reception desk (user: across two lanes, as cover): a long granite-fronted
## counter with a pale top, monitors and a keyboard, a desk lamp and a phone. You crouch behind it.
func _build_reception(parent: Node3D, seg: Dictionary, at: float, x0: float, x1: float) -> Node3D:
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.transform = _frame_at(seg, at)
	var w := x1 - x0
	var cx := (x0 + x1) / 2.0
	_box(holder, Vector3(w, 1.05, 0.9), Vector3(cx, 0.52, 0), Color.WHITE).material_override = \
			PsxMaterials.textured(PsxTextures.lobby_wall(), Vector2(w / 1.4, 1))
	_box(holder, Vector3(w + 0.1, 0.06, 1.0), Vector3(cx, 1.08, 0), Color("c8c4b8"))  # the counter top
	_box(holder, Vector3(w - 0.2, 0.05, 0.5), Vector3(cx, 0.78, -0.55), Color("6a5a48"))  # the desk behind it
	for k in 2:
		var mx := x0 + w * (0.28 + 0.44 * k)
		_box(holder, Vector3(0.5, 0.34, 0.05), Vector3(mx, 1.32, -0.2), Color("141618"))  # monitors
		_box(holder, Vector3(0.44, 0.28, 0.02), Vector3(mx, 1.32, -0.17), Color.WHITE).material_override = \
				PsxMaterials.textured(PsxTextures.cctv_screen(k + 2), Vector2(3, 2), true)
		_box(holder, Vector3(0.08, 0.14, 0.08), Vector3(mx, 1.15, -0.22), Color("141618"))
	_box(holder, Vector3(0.4, 0.03, 0.15), Vector3(cx, 1.12, -0.05), Color("2a2c2e"))  # keyboard
	_box(holder, Vector3(0.2, 0.08, 0.16), Vector3(x1 - 0.4, 1.15, -0.1), Color("1e2022"))  # phone
	_box(holder, Vector3(0.04, 0.4, 0.04), Vector3(x0 + 0.35, 1.3, -0.25), Color("8a8e94"))  # desk lamp
	var shade := _box(holder, Vector3(0.22, 0.1, 0.18), Vector3(x0 + 0.35, 1.5, -0.2), Color.WHITE)
	shade.material_override = PsxMaterials.glow(Color("ffe0a0"))
	return holder


## MAIN FLOOR LOBBY box cover: a concrete planter with a shrub (wood), or a black leather sofa
## (metal) with a tall plant in a pot behind it, so it stands tall enough to hide you crouching
## (scale pass, user).
func _build_lobby_box(parent: Node3D, seg: Dictionary, at: float, x: float, lane: int, metal: bool) -> Node3D:
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.transform = _frame_at(seg, at) * Transform3D(Basis.IDENTITY, Vector3(x, 0, 0))
	if not metal:
		_box(holder, Vector3(1.0, 0.75, 0.9), Vector3(0, 0.37, 0), Color("6a6c6e"))
		_box(holder, Vector3(0.9, 0.05, 0.8), Vector3(0, 0.74, 0), Color("2a2018"))  # soil
		for k in 7:
			var leaf := _box(holder, Vector3(0.12, 0.6, 0.3), Vector3(0.22 * cos(k * 0.9), 1.05, 0.18 * sin(k * 0.9)), Color("2e5a26").lightened(0.06 * (k % 3)))
			leaf.rotation = Vector3(0.5 * sin(k * 1.7), k * 0.9, 0.5 * cos(k * 1.3))
	else:
		var black := Color("1a1a1c")
		_box(holder, Vector3(1.2, 0.42, 0.8), Vector3(0, 0.25, 0), black)  # seat
		_box(holder, Vector3(1.2, 0.5, 0.18), Vector3(0, 0.72, -0.31), black)  # back
		for s in [-1.0, 1.0]:
			_box(holder, Vector3(0.16, 0.62, 0.8), Vector3(s * 0.6, 0.31, 0), black.lightened(0.05))  # arms
		_box(holder, Vector3(1.0, 0.04, 0.6), Vector3(0, 0.47, 0.05), Color("26262a"))  # cushion seams
		# The tall plant behind it: a pot on the floor, a trunk, and leaves up to about 1.7 m.
		var px := 0.3 if lane % 2 == 0 else -0.3
		_box(holder, Vector3(0.45, 0.5, 0.45), Vector3(px, 0.25, -0.65), Color("5a5c5e"))
		_box(holder, Vector3(0.06, 0.8, 0.06), Vector3(px, 0.9, -0.65), Color("4a3a28"))
		for k in 9:
			var leaf := _box(holder, Vector3(0.12, 0.7, 0.3), Vector3(px + 0.18 * cos(k * 0.7), 1.2 + 0.05 * (k % 3), -0.65 + 0.16 * sin(k * 0.7)),
					Color("2e5a26").lightened(0.05 * (k % 3)))
			leaf.rotation = Vector3(0.55 * sin(k * 1.7), k * 0.7, 0.55 * cos(k * 1.3))
	return holder


## MAIN FLOOR LOBBY duck-under: a corporate banner hung on cables from the high ceiling, its bottom
## edge at head height across the blocked lanes.
func _build_banner(parent: Node3D, seg: Dictionary, at: float, ends: Array) -> Node3D:
	var frame := _frame_at(seg, at)
	var e0: float = ends[0]["x"]
	var e1: float = ends[1]["x"]
	var bottom := WIRE_LOW - 0.15
	var h := 1.3
	var banner := _box(parent, Vector3(e1 - e0, h, 0.04), Vector3.ZERO, Color.WHITE)
	banner.transform = frame * Transform3D(Basis.IDENTITY, Vector3((e0 + e1) / 2.0, bottom + h / 2.0, 0))
	banner.material_override = PsxMaterials.textured(PsxTextures.company_logo(), Vector2(maxf(1.0, (e1 - e0) / 2.5), 1))
	_box(parent, Vector3(e1 - e0 + 0.1, 0.06, 0.08), Vector3.ZERO, Color("8a8e94")).transform = \
			frame * Transform3D(Basis.IDENTITY, Vector3((e0 + e1) / 2.0, bottom + h + 0.03, 0))  # the top bar
	var top := _ceil(seg["id"])
	for cx in [e0 + 0.2, e1 - 0.2]:
		var len := top - (bottom + h)
		_box(parent, Vector3(0.03, len, 0.03), Vector3.ZERO, Color("2a2c2e")).transform = \
				frame * Transform3D(Basis.IDENTITY, Vector3(cx, bottom + h + len / 2.0, 0))  # its cables
	return banner


## A MAIN FLOOR LOBBY ceiling light: a big recessed panel glowing high up in the coffered ceiling,
## its light reaching the floor.
func _atrium_lamp(parent: Node3D, seg: Dictionary, z: float, failing: bool) -> void:
	var top := _ceil(seg["id"])
	var on := PsxMaterials.glow(Color("f4ecd8"))
	var panel := _item_box(parent, seg, z, Vector3(0, top - 0.05, 0), Vector3(1.6, 0.06, 2.4), Color.WHITE)
	panel.material_override = on
	_item_box(parent, seg, z, Vector3(0, top - 0.02, 0), Vector3(1.9, 0.04, 2.7), Color("1a1c1e"))  # the coffer
	var at := Node3D.new()
	parent.add_child(at)
	at.transform = _frame_at(seg, z) * Transform3D(Basis.IDENTITY, Vector3(0, 4.5, 0))
	_ambience.add_lamp(at, Color(1.0, 0.94, 0.82) * 2.1, 9.0, {"flicker": 0.3 if failing else 0.0,
			"fixture": panel, "on_mat": on, "off_mat": PsxMaterials.flat(Color("6a6a66"))})


## The MAIN FLOOR LOBBY's mezzanine (user: "a bit more open and 2 storied"): a first-floor balcony
## along both side walls at 4.6 m over the strip beside the road, with a glass balustrade and a
## steel rail, downlights underneath, lit office windows on the upper wall; and a decorative grand
## staircase up the left wall to it (environmental storytelling only: you can't take it).
func _build_mezzanine(parent: Node3D, seg: Dictionary, from: float) -> void:
	var road_half := tuning.lane_count * tuning.lane_width / 2.0
	var floor_y := CEILING_Y
	var length: float = seg["length"]
	var glass := PsxMaterials.glass(Color(0.62, 0.78, 0.84, 0.25))
	var stairs := Vector2(36.0, 48.0)  # where the grand staircase climbs the left wall
	for piece in _pieces(seg, maxf(from, 10.0), length - 1.0):
		var mid := (piece.x + piece.y) / 2.0
		var l := piece.y - piece.x
		for s in [-1.0, 1.0]:
			var mx: float = s * (road_half + 0.5)
			_item_box(parent, seg, mid, Vector3(mx, floor_y - 0.2, 0), Vector3(1.0, 0.4, l), Color("3a3c40"))  # the slab
			_item_box(parent, seg, mid, Vector3(s * (road_half + 0.02), floor_y + 0.52, 0), Vector3(0.03, 0.95, l), Color.WHITE).material_override = glass
			_item_box(parent, seg, mid, Vector3(s * (road_half + 0.02), floor_y + 1.02, 0), Vector3(0.08, 0.06, l), Color("6a5040"))  # the handrail
	# Downlights under the balcony, office windows on the upper wall, the odd plant up there.
	var z := maxf(from, 10.0) + 2.5
	var n := 0
	while z < length - 2.0:
		var on_bend := false
		for leg in seg["legs"]:
			if absf(leg["start"] - z) < 1.5:
				on_bend = true
		if not on_bend:
			for s in [-1.0, 1.0]:
				_item_box(parent, seg, z, Vector3(s * (road_half + 0.5), floor_y - 0.42, 0), Vector3(0.2, 0.03, 0.2), Color.WHITE).material_override = \
						PsxMaterials.glow(Color("ffe0a0"))
				var win := _item_box(parent, seg, z, Vector3(s * (road_half + 0.96), floor_y + 1.9, 0), Vector3(0.05, 1.4, 2.4), Color.WHITE)
				win.material_override = PsxMaterials.textured(PsxTextures.office_window(), Vector2(3, 2), n % 3 == 0)
				if n % 4 == 1:
					_item_box(parent, seg, z + 1.6, Vector3(s * (road_half + 0.7), floor_y + 0.25, 0), Vector3(0.4, 0.5, 0.4), Color("5a5c5e"))
					_item_box(parent, seg, z + 1.6, Vector3(s * (road_half + 0.7), floor_y + 0.75, 0), Vector3(0.5, 0.6, 0.5), Color("2e5a26"))
		z += 5.0
		n += 1
	# The grand staircase up the left wall: steps rising along the strip to the balcony.
	var steps := 18
	var run := stairs.y - stairs.x
	for k in steps:
		var sz := stairs.x + run * (k + 0.5) / steps
		var sy := floor_y * (k + 1) / float(steps)
		_item_box(parent, seg, sz, Vector3(-(road_half + 0.55), sy / 2.0, 0), Vector3(0.9, sy, run / steps + 0.02), Color("4a4c50"))
		_item_box(parent, seg, sz, Vector3(-(road_half + 0.55), sy, 0), Vector3(0.92, 0.04, run / steps + 0.04), Color("8a8c90"))  # tread
	# Its glass balustrade, stepped, and a sloping handrail.
	for k in range(0, steps, 3):
		var sz := stairs.x + run * (k + 1.5) / steps
		var sy := floor_y * (k + 1.5) / float(steps)
		_item_box(parent, seg, sz, Vector3(-(road_half + 0.08), sy + 0.5, 0), Vector3(0.03, 0.9, run * 3.0 / steps), Color.WHITE).material_override = glass
	var hand := _item_box(parent, seg, (stairs.x + stairs.y) / 2.0, Vector3(-(road_half + 0.08), floor_y / 2.0 + 1.0, 0), Vector3(0.07, 0.06, sqrt(run * run + floor_y * floor_y)), Color("6a5040"))
	hand.rotate_object_local(Vector3.RIGHT, atan2(floor_y, run))


## The MAIN FLOOR LOBBY's ground-floor walls (user reference): the company logo lit by uplights,
## lift doors with call buttons, warm wall lights, tall plants, black sofas and bins; never on the
## grand staircase.
func _lobby_decor(parent: Node3D, seg: Dictionary, side: int, from: float, to: float) -> void:
	var face := side * (tuning.lane_count * tuning.lane_width / 2.0 + 1.0 - 0.03)
	var stairs := Vector2(34.0, 50.0)
	var lamps := 0
	for i in range(ceili(from / 5.0) * 5, int(to) - 3, 5):
		var at := i + 2.5
		if side < 0 and at > stairs.x and at < stairs.y:
			continue
		var near_bend := false
		for leg in seg["legs"]:
			if absf(leg["start"] - at) < 1.3:
				near_bend = true
		if near_bend:
			continue
		var holder := Node3D.new()
		parent.add_child(holder)
		holder.transform = _frame_at(seg, at) * Transform3D(Basis.IDENTITY, Vector3(face, 0, 0))
		var out := -float(side)
		match (i / 5 + (1 if side > 0 else 3)) % 5:
			0:  # the company logo, lit from below
				_box(holder, Vector3(0.05, 2.0, 3.0), Vector3(out * 0.03, 2.4, 0), Color.WHITE).material_override = \
						PsxMaterials.textured(PsxTextures.company_logo(), Vector2(3, 2), true)
				for dz in [-1.0, 1.0]:
					var up := _box(holder, Vector3(0.12, 0.08, 0.2), Vector3(out * 0.12, 1.2, dz), Color.WHITE)
					up.material_override = PsxMaterials.glow(Color("ffe0a0"))
				if lamps < 2:
					var glow := Node3D.new()
					holder.add_child(glow)
					glow.position = Vector3(out * 0.6, 2.2, 0)
					_ambience.add_lamp(glow, Color(1.0, 0.82, 0.55) * 1.2, 4.0, {"alert": false})
					lamps += 1
			1:  # lift doors with a call panel and a floor indicator
				for dz in [-0.45, 0.45]:
					_box(holder, Vector3(0.05, DOOR_H, 0.88), Vector3(out * 0.03, DOOR_H / 2.0, dz), Color("6a6e74"))
				_box(holder, Vector3(0.08, DOOR_H + 0.2, 2.1), Vector3(out * 0.0, (DOOR_H + 0.2) / 2.0, 0), Color("3a3c40"))  # its frame
				_box(holder, Vector3(0.04, 0.16, 0.5), Vector3(out * 0.06, DOOR_H + 0.4, 0), Color.WHITE).material_override = PsxMaterials.glow(Color("ff8a3a"))
				_box(holder, Vector3(0.04, 0.3, 0.14), Vector3(out * 0.06, 1.2, 1.25), Color("8a8e94"))  # call buttons
			2:  # a warm wall light and a tall plant
				var sconce := _box(holder, Vector3(0.12, 0.35, 0.2), Vector3(out * 0.08, 2.6, 0), Color.WHITE)
				sconce.material_override = PsxMaterials.glow(Color("ffd890"))
				_box(holder, Vector3(0.5, 0.7, 0.5), Vector3(out * 0.32, 0.35, 0.8), Color("5a5c5e"))
				for k in 6:
					var leaf := _box(holder, Vector3(0.1, 0.8, 0.26), Vector3(out * 0.32, 1.2, 0.8), Color("2e5a26").lightened(0.05 * (k % 3)))
					leaf.rotation = Vector3(0.45 * sin(k * 1.3), k * 1.05, 0.45 * cos(k * 1.3))
			3:  # a black sofa against the wall and a bin
				var black := Color("1a1a1c")
				_box(holder, Vector3(0.7, 0.42, 1.8), Vector3(out * 0.4, 0.25, 0), black)
				_box(holder, Vector3(0.18, 0.5, 1.8), Vector3(out * 0.08, 0.7, 0), black)
				_box(holder, Vector3(0.3, 0.6, 0.3), Vector3(out * 0.25, 0.3, 1.3), Color("5a6064"))


## Office box cover, built to the player's scale (it used to be a 1.2 m cube with a desk or
## cabinet painted on). Wood: a desk at desk height, its modesty panel toward you, a chunky CRT
## monitor and a tray of papers on top (the monitor makes it tall enough to crouch behind), the
## chair pushed in behind. Metal: two four-drawer filing cabinets side by side, a box file on top.
func _build_office_box(parent: Node3D, seg: Dictionary, at: float, x: float, lane: int, metal: bool) -> Node3D:
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.transform = _frame_at(seg, at) * Transform3D(Basis.IDENTITY, Vector3(x, 0, 0))
	var flip := 1.0 if lane % 2 == 0 else -1.0
	if metal:
		var grey := Color("6a7076")
		for dx in [-0.24, 0.24]:
			_box(holder, Vector3(0.46, 1.32, 0.62), Vector3(dx, 0.66, 0), grey)
			for k in 4:  # the drawer fronts and their handles, toward you
				_box(holder, Vector3(0.4, 0.28, 0.02), Vector3(dx, 0.18 + k * 0.32, 0.315), grey.lightened(0.12))
				_box(holder, Vector3(0.12, 0.03, 0.03), Vector3(dx, 0.26 + k * 0.32, 0.33), Color("2a2c2e"))
		_box(holder, Vector3(0.3, 0.22, 0.36), Vector3(-0.2 * flip, 1.43, 0.02), Color("2a4a7a"))  # a box file
		return holder
	var wood := Color("6a5038")
	_box(holder, Vector3(1.2, 0.05, 0.72), Vector3(0, 0.76, 0), wood)  # the top
	_box(holder, Vector3(1.16, 0.6, 0.03), Vector3(0, 0.44, 0.3), wood.darkened(0.2))  # modesty panel, toward you
	for dx in [-0.57, 0.57]:
		_box(holder, Vector3(0.05, 0.74, 0.7), Vector3(dx, 0.37, 0), wood.darkened(0.3))  # the ends
	_box(holder, Vector3(0.4, 0.66, 0.62), Vector3(0.38 * flip, 0.37, 0), wood.darkened(0.1))  # drawer pedestal
	# A beige CRT monitor turned a little, its screen away from you (you're looking at its back).
	var crt := Node3D.new()
	holder.add_child(crt)
	crt.position = Vector3(-0.18 * flip, 0.78, -0.05)
	crt.rotation.y = 0.25 * flip
	_box(crt, Vector3(0.42, 0.38, 0.4), Vector3(0, 0.21, 0), Color("c8c0a8"))
	_box(crt, Vector3(0.3, 0.26, 0.2), Vector3(0, 0.2, 0.28), Color("b8b098"))  # the tube's back
	_box(crt, Vector3(0.3, 0.04, 0.26), Vector3(0, 0.02, 0), Color("a8a088"))  # its stand
	_box(holder, Vector3(0.45, 0.03, 0.16), Vector3(-0.15 * flip, 0.8, -0.25), Color("d0c8b0"))  # keyboard
	for k in 3:  # a tray of papers
		_box(holder, Vector3(0.3, 0.02, 0.22), Vector3(0.35 * flip, 0.8 + k * 0.025, 0.05), Color("e8e4d8"))
	# The chair, pushed in on the far side.
	var chair := Color("2e3a4a")
	_box(holder, Vector3(0.46, 0.08, 0.44), Vector3(-0.1 * flip, 0.48, -0.62), chair)
	_box(holder, Vector3(0.44, 0.5, 0.07), Vector3(-0.1 * flip, 0.82, -0.86), chair)
	_box(holder, Vector3(0.06, 0.44, 0.06), Vector3(-0.1 * flip, 0.22, -0.62), Color("1e1e1e"))
	_box(holder, Vector3(0.5, 0.04, 0.5), Vector3(-0.1 * flip, 0.03, -0.62), Color("1e1e1e"))
	return holder


## A keycard reader on the wall: a dark box with a slot and a red LED, `dz` along the road.
func _card_reader(holder: Node3D, out: float, dz: float, red: Material) -> void:
	_box(holder, Vector3(0.08, 0.3, 0.18), Vector3(out * 0.04, 1.25, dz), Color("1e2022"))
	_box(holder, Vector3(0.02, 0.02, 0.12), Vector3(out * 0.09, 1.2, dz), Color("4a4e50"))  # the slot
	_box(holder, Vector3(0.02, 0.04, 0.08), Vector3(out * 0.09, 1.34, dz), Color.WHITE).material_override = red


## Air vent grilles in the ceiling between the lights (the SECURITY WING's ceiling).
func _ceiling_vents(parent: Node3D, seg: Dictionary, from: float) -> void:
	var at := maxf(from, 10.0) + 4.0
	while at < float(seg["length"]) - 3.0:
		for sx in [-1.9, 1.9]:
			var v := _item_box(parent, seg, at, Vector3(sx, CEILING_Y - 0.03, 0), Vector3(0.9, 0.04, 0.55), Color.WHITE)
			v.material_override = PsxMaterials.textured(PsxTextures.vent(), Vector2(3, 2))
		at += 10.0


## Hazard stripes painted across the floor every so often (the SECURITY WING's checkpoints).
func _floor_stripes(parent: Node3D, seg: Dictionary, from: float) -> void:
	var road_w := tuning.lane_count * tuning.lane_width
	var at := maxf(from, 14.0) + 6.0
	while at < float(seg["length"]) - 4.0:
		var leg_ok := true
		for leg in seg["legs"]:
			if absf(leg["start"] - at) < 1.5:
				leg_ok = false
		if leg_ok:
			_strip(parent, seg, at, at + 0.6, 0.0, road_w, 0.012, PsxTextures.hazard(), road_w / 0.6, 0.6)
		at += 24.0


## Splits [a, b] where legs bend and where stairs end, so each piece is one straight slope.
static func _pieces(seg: Dictionary, a: float, b: float) -> Array[Vector2]:
	var cuts: Array[float] = [a, b]
	for leg in seg["legs"]:
		if leg["start"] > a and leg["start"] < b:
			cuts.append(leg["start"])
	if seg["ramp_len"] > a and seg["ramp_len"] < b:
		cuts.append(seg["ramp_len"])
	cuts.sort()
	var out: Array[Vector2] = []
	for i in cuts.size() - 1:
		if cuts[i + 1] - cuts[i] > 0.01:
			out.append(Vector2(cuts[i], cuts[i + 1]))
	return out


## A flat strip lying along one piece of a segment, `x` across and `y` up, following any slope.
func _strip(parent: Node3D, seg: Dictionary, a: float, b: float, x: float, width: float, y: float,
		tex: Texture2D, tiles_x: float, tile_len: float = 4.0) -> MeshInstance3D:
	var i := _leg_index(seg, (a + b) / 2.0)
	var pa := _frame_in_leg(seg, i, a) * Vector3(x, y, 0)
	var pb := _frame_in_leg(seg, i, b) * Vector3(x, y, 0)
	var l := pa.distance_to(pb)
	var back := (pa - pb) / l
	var right: Vector3 = seg["legs"][i]["xf"].basis.x
	var m := _plane(parent, Vector2(width, l), Vector3.ZERO, tex, Vector2(tiles_x, l / tile_len))
	m.transform = Transform3D(Basis(right, back.cross(right), back), (pa + pb) / 2.0)
	return m


## A wall along one piece of a segment, facing the road, covering any climb.
func _wall(parent: Node3D, seg: Dictionary, a: float, b: float, x: float, side: int, h: float, tex: Texture2D) -> void:
	var i := _leg_index(seg, (a + b) / 2.0)
	var leg: Dictionary = seg["legs"][i]
	var ha := _height(seg, a)
	var hb := _height(seg, b)
	var y0 := minf(ha, hb)
	var y1 := maxf(ha, hb) + h
	var l := b - a
	var xf: Transform3D = leg["xf"]
	var m := _plane(parent, Vector2(l, y1 - y0), Vector3.ZERO, tex, Vector2(l / 2.0, (y1 - y0) / 2.0), PlaneMesh.FACE_Z)
	# Shift the pattern so a tile's bottom row (skirting, grime) sits on the floor, whatever the height.
	var rows := (y1 - y0) / 2.0
	m.material_override = PsxMaterials.textured(tex, Vector2(l / 2.0, rows), false, Vector2(0, ceilf(rows) - rows))
	m.transform = Transform3D(xf.basis * Basis(Vector3.UP, -side * PI / 2.0),
			xf * Vector3(x, (y0 + y1) / 2.0, -((a + b) / 2.0 - leg["start"])))


## A box at a point on a segment (`local` is across, up and forward from the centre line there).
func _item_box(parent: Node3D, seg: Dictionary, into: float, local: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var m := _box(parent, size, Vector3.ZERO, color)
	m.transform = _frame_at(seg, into) * Transform3D(Basis.IDENTITY, local)
	return m


## Pipes and tripwires, one piece per run of neighbouring lanes, never left floating:
## - a run that reaches the road edge carries on into the side wall (a mounting plate for a pipe,
##   an emitter box for a tripwire);
## - a run that stops mid-road ends on the floor (a pipe bends down to a foot, a tripwire ends on
##   an emitter post).
## Pipes get a nut where each lane's pipe joins the next. Returns the node to hide when tripped.
func _build_spans(parent: Node3D, seg: Dictionary, kind: String, lanes: Array, at: float, y: float) -> Node3D:
	lanes.sort()
	var runs: Array[Array] = []
	for lane: int in lanes:
		if runs.is_empty() or lane != runs[-1][-1] + 1:
			runs.append([lane])
		else:
			runs[-1].append(lane)
	var road_w := tuning.lane_count * tuning.lane_width
	var wall_x := road_w / 2.0 + 1.0
	var last := tuning.lane_count - 1
	var beam: MeshInstance3D = null
	var holder := Node3D.new()  # tripwire beams go in one node, so they hide together
	parent.add_child(holder)
	var metal := Color("4a4e54")
	for run in runs:
		var ends := [
			{"x": -wall_x if run[0] == 0 else _player.lane_x(run[0]) - tuning.lane_width / 2.0 + 0.2, "wall": run[0] == 0},
			{"x": wall_x if run[-1] == last else _player.lane_x(run[-1]) + tuning.lane_width / 2.0 - 0.2, "wall": run[-1] == last},
		]
		var x0: float = ends[0]["x"]
		var x1: float = ends[1]["x"]
		if kind == "pipe":
			var p := _item_box(parent, seg, at, Vector3((x0 + x1) / 2.0, y, 0), Vector3(x1 - x0, 0.3, 0.3), Color.WHITE)
			p.material_override = PsxMaterials.textured(PsxTextures.rust_pipe(), Vector2(3, 2))
			beam = p
			for k in range(1, run.size()):  # nuts where one lane's pipe joins the next
				_item_box(parent, seg, at, Vector3(_player.lane_x(run[k]) - tuning.lane_width / 2.0, y, 0), Vector3(0.14, 0.44, 0.44), metal)
			for e in ends:
				var ex: float = e["x"]
				if e["wall"]:
					_item_box(parent, seg, at, Vector3(ex, y, 0), Vector3(0.1, 0.62, 0.62), metal)  # wall plate
				else:
					_item_box(parent, seg, at, Vector3(ex, y, 0), Vector3(0.38, 0.38, 0.38), metal)  # elbow
					var down := _item_box(parent, seg, at, Vector3(ex, y / 2.0, 0), Vector3(0.3, y, 0.3), Color.WHITE)
					down.material_override = PsxMaterials.textured(PsxTextures.rust_pipe(), Vector2(3, 2))
					_item_box(parent, seg, at, Vector3(ex, 0.04, 0), Vector3(0.55, 0.08, 0.55), metal)  # foot
		elif kind == "double_pipe":
			# Rooftop pipework: two pipes, one above the other, in the room one pipe takes, clamped
			# at every lane joint and standing on a frame at each end (no walls up here).
			var pipe_mat := PsxMaterials.textured(PsxTextures.rust_pipe(), Vector2(3, 2))
			for dy in [-0.09, 0.09]:
				var p := _item_box(parent, seg, at, Vector3((x0 + x1) / 2.0, y + dy, 0), Vector3(x1 - x0, 0.15, 0.15), Color.WHITE)
				p.material_override = pipe_mat
				beam = p
			for k in range(1, run.size()):
				_item_box(parent, seg, at, Vector3(_player.lane_x(run[k]) - tuning.lane_width / 2.0, y, 0), Vector3(0.1, 0.44, 0.24), metal)
			var open_sky: bool = _theme(seg["id"]).get("no_walls", false)
			for e in ends:
				var ex: float = e["x"]
				if e["wall"] and open_sky:
					# At the roof edge: carry on over the lip, bend, and run down the side of the building.
					var out := ex + signf(ex) * 0.35
					for dy in [-0.09, 0.09]:
						var ext := _item_box(parent, seg, at, Vector3((ex + out) / 2.0, y + dy, 0), Vector3(absf(out - ex) + 0.15, 0.15, 0.15), Color.WHITE)
						ext.material_override = pipe_mat
						var drop := 6.0
						var down := _item_box(parent, seg, at, Vector3(out + signf(ex) * (0.09 + dy), y + dy - drop / 2.0, 0),
								Vector3(0.15, drop, 0.15), Color.WHITE)
						down.material_override = pipe_mat
					_item_box(parent, seg, at, Vector3(ex, y, 0), Vector3(0.1, 0.44, 0.24), metal)  # clamp over the lip
					continue
				_item_box(parent, seg, at, Vector3(ex, y, 0), Vector3(0.12, 0.44, 0.26), metal)  # end clamp
				for dz in [-0.14, 0.14]:
					_item_box(parent, seg, at, Vector3(ex, (y + 0.2) / 2.0, dz), Vector3(0.07, y + 0.2, 0.07), metal)  # legs
				_item_box(parent, seg, at, Vector3(ex, 0.03, 0), Vector3(0.3, 0.06, 0.5), metal)  # foot
		elif kind == "banner":
			beam = _build_banner(parent, seg, at, ends)
		elif kind == "girder":
			beam = _build_gantry(parent, seg, at, ends) if _is_outdoor(seg, at) else _build_girder(parent, seg, at, y, ends)
		elif kind == "bunting":
			beam = _build_bunting(parent, seg, at, ends)
		elif kind == "wires":
			beam = _build_wires(parent, seg, at, y, ends)
		else:
			# Thick enough to stay at least a pixel tall at the low internal resolution, far off.
			var b := _item_box(holder, seg, at, Vector3((x0 + x1) / 2.0, y, 0), Vector3(x1 - x0, 0.1, 0.06), Color("ff3030"))
			b.material_override = PsxMaterials.glow(Color("ff3030"))  # a laser: it glows
			beam = b
			for e in ends:
				var ex: float = e["x"]
				if e["wall"]:
					ex -= signf(ex) * 0.2  # stands just proud of the wall, so it reads against it
				else:
					_item_box(parent, seg, at, Vector3(ex, y / 2.0, 0), Vector3(0.12, y, 0.12), metal)  # emitter post
				# A light housing with a bright red lens facing along the beam.
				var em := _item_box(parent, seg, at, Vector3(ex, y, 0), Vector3(0.4, 0.34, 0.34), Color("a8acb2"))
				_box(em, Vector3(0.44, 0.14, 0.14), Vector3.ZERO, Color("ff2a2a"))
	# Hiding the holder hides every beam of a tripwire at once.
	return holder if kind == "tripwire" else beam


## Live electrical wires hanging low across a run of lanes (the main floor's slide obstacle):
## three cables in one smooth drape. Over the blocked lanes they sag low (you have to slide). At a
## wall they end in a junction box; where they stop mid-road they curve up to a hook in the ceiling
## just beyond the end, well above head height by the next lane. A cut wire dangles with a bend in
## it, and sparks where they're broken.
func _build_wires(parent: Node3D, seg: Dictionary, at: float, y: float, ends: Array) -> Node3D:
	var frame := _frame_at(seg, at)
	y = WIRE_LOW  # they hang at head height (playtest: at pipe height they looked far too low)
	var top := y + 0.2   # height at the edge of the blocked lanes
	var low := y - 0.08  # lowest point, mid-run (still too low to run under)
	var reach := 1.3     # how far past a mid-road end the ceiling hook is
	# Edges of the blocked lanes (a wall end is the wall itself) and where each end is anchored.
	var e0: float = ends[0]["x"] if ends[0]["wall"] else ends[0]["x"] - 0.2
	var e1: float = ends[1]["x"] if ends[1]["wall"] else ends[1]["x"] + 0.2
	var a0 := e0 if ends[0]["wall"] else e0 - reach
	var a1 := e1 if ends[1]["wall"] else e1 + reach
	var mid := (e0 + e1) / 2.0
	var half := (e1 - e0) / 2.0
	var slope := 2.0 * (top - low) / half  # steepness at the lane edge, carried on into the rise
	var black := Color("141414")
	var first: MeshInstance3D = null
	var steps := maxi(8, ceili((a1 - a0) / 0.3))
	for c in 3:
		var dz: float = [-0.1, 0.0, 0.1][c]
		var dy: float = [0.0, 0.06, -0.05][c]
		var prev := Vector3.ZERO
		for i in steps + 1:
			var x := lerpf(a0, a1, float(i) / steps)
			var h := _wire_height(x, e0, e1, mid, half, top, low, slope, reach)
			var p := Vector3(x, h + dy * clampf((CEILING_Y - h) / 1.0, 0.0, 1.0), dz)
			if i > 0:
				var piece := _cable(parent, frame, prev, p, 0.04, black if c != 1 else Color("5a3a12"))
				if first == null:
					first = piece
			prev = p
	for e in ends:
		var ex: float = e["x"]
		if e["wall"]:
			var jb := _box(parent, Vector3(0.24, 0.42, 0.42), Vector3.ZERO, Color("5a5f66"))  # junction box
			jb.transform = frame * Transform3D(Basis.IDENTITY, Vector3(ex - signf(ex) * 0.1, top, 0))
			var stripe := _box(jb, Vector3(0.26, 0.08, 0.44), Vector3.ZERO, Color("c9a227"))
			stripe.position.y = 0.12
		else:
			var hook := a0 if ex < mid else a1
			_box(parent, Vector3(0.18, 0.12, 0.3), Vector3.ZERO, Color("5a5f66")).transform = \
					frame * Transform3D(Basis.IDENTITY, Vector3(hook, CEILING_Y - 0.06, 0))  # ceiling hook
	_torn_ceiling(parent, seg, at, e0, e1)
	# A cut wire dangling from the ceiling with a lazy bend in it, sparking at its end.
	var cut_x := lerpf(e0, e1, 0.3)
	var tip := Vector3(cut_x + 0.18, top - 0.1, 0.25)
	var prev_cut := Vector3(cut_x, CEILING_Y, 0.25)
	for i in range(1, 7):
		var t := i / 6.0
		var p := Vector3(cut_x + 0.18 * t * t + 0.12 * sin(t * PI), lerpf(CEILING_Y, tip.y, t), 0.25)
		_cable(parent, frame, prev_cut, p, 0.04, black)
		prev_cut = p
	tip = prev_cut
	for spot in [tip, Vector3(lerpf(e0, e1, 0.65), low + 0.02, 0.0)]:
		var s := Sparks.new(4, hash(Vector2(at, spot.x)))
		parent.add_child(s)
		s.transform = frame * Transform3D(Basis.IDENTITY, spot)
		_audio.attach_loop(s, "crackle", -10.0, 10.0, 2.0)
	return first


## Where the wires have torn through the ceiling: dark gaps where tiles are missing above them,
## and the fallen tiles lying on the floor below (flat debris, nothing to jump or slide).
func _torn_ceiling(parent: Node3D, seg: Dictionary, at: float, e0: float, e1: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seg["id"], at])
	var tile_mat := PsxMaterials.textured(PsxTextures.office_ceiling(), Vector2(1.5, 1.0))  # one tile a face
	var void_col := Color("0b0c0c")
	var holes := clampi(int((e1 - e0) / 1.4), 2, 4)
	for i in holes:
		# A missing tile: the dark void above, with the odd joist or duct showing through.
		var hx := lerpf(e0 + 0.5, e1 - 0.5, (i + 0.5) / holes) + rng.randf_range(-0.2, 0.2)
		var hz := rng.randf_range(-0.6, 0.6)
		_item_box(parent, seg, at + hz, Vector3(hx, CEILING_Y - 0.015, 0), Vector3(0.92, 0.02, 0.92), void_col)
		if rng.randf() < 0.6:
			_item_box(parent, seg, at + hz, Vector3(hx + rng.randf_range(-0.25, 0.25), CEILING_Y - 0.05, 0), Vector3(0.06, 0.06, 0.9), Color("2c2e2e"))
		# Its tile, down on the floor below: flat, or broken in two, or propped on another.
		var fx := hx + rng.randf_range(-0.35, 0.35)
		var fz := hz + rng.randf_range(-0.8, 0.8)
		var tile := _item_box(parent, seg, at + fz, Vector3(fx, 0.02, 0), Vector3(0.9, 0.03, 0.9), Color.WHITE)
		tile.material_override = tile_mat
		tile.rotate_object_local(Vector3.UP, rng.randf_range(-0.6, 0.6))
		if rng.randf() < 0.5:
			var half := _item_box(parent, seg, at + fz + 0.3, Vector3(fx + 0.4, 0.08, 0), Vector3(0.5, 0.03, 0.85), Color.WHITE)
			half.material_override = tile_mat
			half.rotate_object_local(Vector3.UP, rng.randf_range(-1.0, 1.0))
			half.rotate_object_local(Vector3.FORWARD, 0.18)  # resting on the other tile
	# Crumbs of tile scattered round.
	for i in 6:
		_item_box(parent, seg, at + rng.randf_range(-1.2, 1.2), Vector3(rng.randf_range(e0, e1), 0.015, 0),
				Vector3(rng.randf_range(0.06, 0.16), 0.02, rng.randf_range(0.06, 0.14)), Color("8a8e8a"))


## The wires' drape: a parabola over the blocked lanes (lowest mid-run, `top` at their edges);
## past a mid-road end it keeps curving up at the same steepness to the ceiling hook.
## The STAFF CANTEEN's duck-under obstacle (user): a string of triangle bunting, hung at head height
## on the same drape as the live wires (low over the blocked lanes, up to a hook past a mid-road
## end), with little flags in party colours hanging off it.
func _build_bunting(parent: Node3D, seg: Dictionary, at: float, ends: Array) -> Node3D:
	var frame := _frame_at(seg, at)
	var y := WIRE_LOW
	var top := y + 0.2
	var low := y - 0.08
	var reach := 1.3
	var e0: float = ends[0]["x"] if ends[0]["wall"] else ends[0]["x"] - 0.2
	var e1: float = ends[1]["x"] if ends[1]["wall"] else ends[1]["x"] + 0.2
	var a0 := e0 if ends[0]["wall"] else e0 - reach
	var a1 := e1 if ends[1]["wall"] else e1 + reach
	var mid := (e0 + e1) / 2.0
	var half := (e1 - e0) / 2.0
	var slope := 2.0 * (top - low) / half
	var colours := [Color("d83a2a"), Color("e8c040"), Color("2a6ad8"), Color("40a050"), Color("e8e4dc")]
	var first: MeshInstance3D = null
	var steps := maxi(8, ceili((a1 - a0) / 0.3))
	var prev := Vector3.ZERO
	for i in steps + 1:
		var x := lerpf(a0, a1, float(i) / steps)
		var p := Vector3(x, _wire_height(x, e0, e1, mid, half, top, low, slope, reach), 0)
		if i > 0:
			var piece := _cable(parent, frame, prev, p, 0.025, Color("e8e0c8"))
			if first == null:
				first = piece
		prev = p
	# The flags: point-down triangles every ~0.32 m along the low stretch.
	var n := 0
	var fx := e0 + 0.12
	while fx < e1 - 0.08:
		var h := _wire_height(fx, e0, e1, mid, half, top, low, slope, reach)
		var flag := MeshInstance3D.new()
		var prism := PrismMesh.new()
		prism.size = Vector3(0.24, 0.26, 0.015)
		flag.mesh = prism
		flag.material_override = PsxMaterials.flat(colours[n % colours.size()])
		parent.add_child(flag)
		flag.transform = frame * Transform3D(Basis(Vector3.FORWARD, PI), Vector3(fx, h - 0.14, 0))  # point down
		fx += 0.32
		n += 1
	for e in ends:
		if not e["wall"]:
			var hook := a0 if float(e["x"]) < mid else a1
			_box(parent, Vector3(0.1, 0.08, 0.1), Vector3.ZERO, Color("6a6e70")).transform = \
					frame * Transform3D(Basis.IDENTITY, Vector3(hook, CEILING_Y - 0.04, 0))
	return first


static func _wire_height(x: float, e0: float, e1: float, mid: float, half: float, top: float, low: float,
		slope: float, reach: float) -> float:
	if x >= e0 and x <= e1:
		var u := (x - mid) / half
		return low + (top - low) * u * u
	var s := (e0 - x) if x < e0 else (x - e1)  # metres past the edge, toward the hook
	var a := (CEILING_Y - top - slope * reach) / (reach * reach)
	return minf(CEILING_Y, top + slope * s + a * s * s)


## A thin straight cable between two points given in `frame` (a place on the route).
func _cable(parent: Node3D, frame: Transform3D, a: Vector3, b: Vector3, thick: float, color: Color) -> MeshInstance3D:
	var m := _box(parent, Vector3(thick, thick, maxf(a.distance_to(b), 0.01)), Vector3.ZERO, color)
	var pa := frame * a
	var pb := frame * b
	var up := Vector3.UP if absf((pb - pa).normalized().y) < 0.99 else Vector3.RIGHT
	m.transform = Transform3D(Basis.looking_at(pb - pa, up), (pa + pb) / 2.0)
	return m


## Loose sheets of paper around a low filing cabinet, as if it was tipped over or shoved aside
## in a hurry: mostly on the floor in front of and behind it, a couple on top.
func _scatter_papers(parent: Node3D, seg: Dictionary, at: float, x: float, lane: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seg["id"], at, lane])
	var frame := _frame_at(seg, at)
	for i in 9:
		var on_top := i < 2
		var p := Vector3(x + rng.randf_range(-0.6, 0.6), 0.51 if on_top else 0.012,
				rng.randf_range(-0.25, 0.25) if on_top else rng.randf_range(-1.8, 1.4))
		if not on_top and absf(p.z) < 0.25:
			p.z = 0.35 * signf(p.z + 0.001)  # not inside the cabinet
		var sheet := _box(parent, Vector3(0.21, 0.006, 0.29), Vector3.ZERO, Color("e6e2d6") if i % 4 else Color("d8d2b8"))
		sheet.transform = frame * Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)), p)


## Rooftop ventilation shaft (a jump obstacle): a louvred galvanised box with a cap on top.
func _build_vent_shaft(parent: Node3D, seg: Dictionary, at: float, x: float) -> Node3D:
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.transform = _frame_at(seg, at) * Transform3D(Basis.IDENTITY, Vector3(x, 0, 0))
	var body := _box(holder, Vector3(tuning.lane_width * 0.86, 0.44, 0.55), Vector3(0, 0.22, 0), Color.WHITE)
	body.material_override = PsxMaterials.textured(PsxTextures.vent(), Vector2(3, 2))
	_box(holder, Vector3(tuning.lane_width * 0.92, 0.06, 0.62), Vector3(0, 0.47, 0), Color("6e7478"))  # cap
	return holder


## Rooftop box cover: a small ventilation opening (a hooded vent), with light steam coming out.
func _build_roof_vent(parent: Node3D, seg: Dictionary, at: float, x: float, lane: int) -> Node3D:
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.transform = _frame_at(seg, at) * Transform3D(Basis.IDENTITY, Vector3(x, 0, 0))
	var body := _box(holder, Vector3(0.9, 0.95, 0.9), Vector3(0, 0.475, 0), Color.WHITE)
	body.material_override = PsxMaterials.textured(PsxTextures.vent(), Vector2(3, 2))
	for c in 4:  # corner posts holding the hood up, leaving the opening between
		_box(holder, Vector3(0.06, 0.2, 0.06), Vector3(0.4 * (1 if c % 2 else -1), 1.05, 0.4 * (1 if c < 2 else -1)), Color("5e6468"))
	_box(holder, Vector3(1.05, 0.08, 1.05), Vector3(0, 1.19, 0), Color("6e7478"))  # hood
	var steam := Steam.new(4, hash([seg["id"], at, lane]))
	holder.add_child(steam)
	steam.position = Vector3(0, 1.1, 0)
	_audio.attach_loop(steam, "steam", -12.0, 10.0, 2.0)
	return holder


## Rooftop wall cover (no walls up here): a big air-conditioning unit across x0..x1, on a base
## frame, with condenser grilles down the sides and fans on top. You stand behind it like a wall.
func _build_roof_wall(parent: Node3D, seg: Dictionary, at: float, x0: float, x1: float, _look: String) -> Node3D:
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.transform = _frame_at(seg, at)
	var edge := tuning.lane_count * tuning.lane_width / 2.0 + 1.0
	x0 = maxf(x0, -edge + 0.3)  # stays on the roof, inside the lip
	x1 = minf(x1, edge - 0.3)
	var w := x1 - x0
	var cx := (x0 + x1) / 2.0
	var dark := Color("3a3a36")
	_box(holder, Vector3(w, 0.14, 1.25), Vector3(cx, 0.07, 0), dark)  # base frame
	var body := _box(holder, Vector3(w - 0.08, 2.2, 1.15), Vector3(cx, 0.14 + 1.1, 0), Color.WHITE)  # taller than you: you stand behind it
	body.material_override = PsxMaterials.textured(PsxTextures.hvac(), Vector2(3, 2))
	_box(holder, Vector3(w, 0.06, 1.2), Vector3(cx, 2.37, 0), Color("7e7e74"))  # top panel
	var fans := maxi(1, roundi(w / 1.3))
	for i in fans:
		var fx := x0 + w * (i + 0.5) / fans
		var fan := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.45
		cyl.bottom_radius = 0.45
		cyl.height = 0.2
		cyl.radial_segments = 10
		fan.mesh = cyl
		fan.material_override = PsxMaterials.flat(Color("2e2e2a"))
		holder.add_child(fan)
		fan.position = Vector3(fx, 2.5, 0)
		for r in 2:  # the grille over the fan
			var bar := _box(holder, Vector3(0.86, 0.03, 0.05), Vector3(fx, 2.61, 0), Color("8a8a80"))
			bar.rotation.y = r * PI / 2.0
	# Refrigerant pipes from the unit down into the roof.
	for dz in [-0.2, 0.0]:
		_box(holder, Vector3(0.07, 0.9, 0.07), Vector3(x0 + 0.2, 0.6, 0.62 + dz * 0.3), Color("a86a3a"))
	return holder


## The city around an open-sky area: neighbouring buildings' roofs close by on both sides (some
## higher, most lower, with a water tank or air-con unit), and taller towers further out for depth.
func _build_city(parent: Node3D, seg: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seg["id"])
	var length: float = seg["length"]
	var edge := tuning.lane_count * tuning.lane_width / 2.0 + 1.0
	var facade := PsxMaterials.textured(PsxTextures.building_night(), Vector2(3, 2), true)  # lit windows at night
	var roofing := PsxMaterials.textured(PsxTextures.gravel(), Vector2(6, 4))
	# Keep neighbours clear of the stairwell coming up and of any side exit leading off this roof.
	var exit_sides := {}
	for e in _graph.all_next(seg["id"]):
		if _turns(e):
			exit_sides[-1 if RouteGraph.side_of(e) == "left" else 1] = true
	# The rest of the mission (the building, the other routes) runs along the centre line (world
	# x = 0). Only build city on the side of this roof facing away from it, so nothing ends up
	# inside another area.
	var mid_frame: Transform3D = seg["node"].transform * _frame_at(seg, length / 2.0)
	for side in [-1, 1]:
		var outward := (mid_frame * Vector3(side * 20.0, 0, 0)).x - mid_frame.origin.x
		if signf(outward) != signf(mid_frame.origin.x) and absf(mid_frame.origin.x) > 1.0:
			continue
		if absf(mid_frame.origin.x) <= 1.0:
			continue  # right over the centre line: no room either side
		var z: float = seg["ramp_len"] + 2.0
		var until := length - tuning.decision_lead - tuning.fork_cue_length if exit_sides.has(side) else length
		while z < until:
			var blen := rng.randf_range(12.0, 24.0)
			var inner := edge + rng.randf_range(3.0, 6.0)
			var bw := rng.randf_range(8.0, 14.0)
			var top := rng.randf_range(-3.5, 1.2)
			var mid := z + blen / 2.0
			var at := clampf(mid, 0.0, length)
			var x: float = side * (inner + bw / 2.0)
			_item_box(parent, seg, at, Vector3(x, top - 20.0, mid - at), Vector3(bw, 40.0, blen), Color.WHITE).material_override = facade
			_item_box(parent, seg, at, Vector3(x, top + 0.02, mid - at), Vector3(bw, 0.04, blen), Color.WHITE).material_override = roofing
			if rng.randf() < 0.5:
				_item_box(parent, seg, at, Vector3(x, top + 1.2, mid - at), Vector3(1.8, 2.4, 1.8), Color("5a4a3a"))  # water tank
			else:
				_item_box(parent, seg, at, Vector3(x + rng.randf_range(-2, 2), top + 0.6, mid - at), Vector3(2.2, 1.2, 1.4), Color("8a9094"))  # air-con
			z += blen + rng.randf_range(2.0, 5.0)
		# Towers further out, for scale.
		var tz := rng.randf_range(0.0, 12.0)
		while tz < length:
			var fw := rng.randf_range(8.0, 16.0)
			var tall := rng.randf_range(6.0, 34.0)
			var tx: float = side * rng.randf_range(32.0, 70.0)
			var t_at := clampf(tz, 0.0, length)
			_item_box(parent, seg, t_at, Vector3(tx, tall / 2.0 - 25.0, tz - t_at), Vector3(fw, tall + 50.0, fw), Color.WHITE).material_override = facade
			if tall > 14.0:  # tall ones carry a blinking red aviation light
				_item_box(parent, seg, t_at, Vector3(tx, tall + 0.3, tz - t_at), Vector3(0.6, 0.6, 0.6), Color.WHITE).material_override = _beacon_mat
			tz += rng.randf_range(14.0, 26.0)


## A makeshift blockade across one lane: a door on its side, with a chair tipped over behind it.
## Still exactly a jump obstacle; just a different look (main floor).
func _build_blockade(parent: Node3D, seg: Dictionary, at: float, x: float, lane: int) -> Node3D:
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.transform = _frame_at(seg, at) * Transform3D(Basis.IDENTITY, Vector3(x, 0, 0))
	var tilt := 0.07 if lane % 2 == 0 else -0.06
	var door := _box(holder, Vector3(tuning.lane_width * 0.94, 0.5, 0.07), Vector3(0, 0.25, 0), Color.WHITE)
	door.material_override = PsxMaterials.textured(PsxTextures.door(), Vector2(3, 2))
	door.rotation.z = tilt
	# The chair, on its side: seat standing up, back lying flat, legs sticking out.
	var chair := Node3D.new()
	holder.add_child(chair)
	chair.position = Vector3(0.25 if lane % 2 == 0 else -0.25, 0, -0.35)
	chair.rotation.y = 0.5 if lane % 2 == 0 else -0.4
	var plastic := Color("3e4c5c")
	_box(chair, Vector3(0.44, 0.44, 0.05), Vector3(0, 0.22, 0), plastic)       # seat
	_box(chair, Vector3(0.44, 0.05, 0.42), Vector3(0, 0.03, -0.2), plastic)    # back, flat on the floor
	for lx in [-0.19, 0.19]:
		_box(chair, Vector3(0.03, 0.03, 0.4), Vector3(lx, 0.4, 0.2), Color("8a8f96"))  # legs
	return holder


## The SECURITY WING's guard booth (user reference), as wall cover across x0..x1: a glass booth
## standing out into the corridor, about 3 m deep (front face at `at`, running on down the
## route), floor to ceiling. A dark steel base, steel posts, tinted windows into a lit room (a desk, a monitor, a
## chair, a strip light), a steel header up to the ceiling with a red beacon on it. You take cover at its
## front like any wall, and you can't see or shoot through it.
func _build_booth(parent: Node3D, seg: Dictionary, at: float, x0: float, x1: float) -> Node3D:
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.transform = _frame_at(seg, at)
	var edge := tuning.lane_count * tuning.lane_width / 2.0 + 1.0
	x0 = maxf(x0, -edge)
	x1 = minf(x1, edge)
	var w := x1 - x0
	var cx := (x0 + x1) / 2.0
	var depth := 3.0
	var z0 := 0.5  # front face (toward you)
	var zc := z0 - depth / 2.0
	var steel := Color("34393c")
	var trim := Color("5e6468")
	var base_h := 0.95
	var top := CEILING_Y - 0.6  # the windows' top; a steel header runs from there up to the ceiling
	# The base: a solid steel skirt all round, with a hazard band along the front.
	_box(holder, Vector3(w, base_h, depth), Vector3(cx, base_h / 2.0, zc), steel)
	_box(holder, Vector3(w + 0.02, 0.18, 0.04), Vector3(cx, 0.12, z0 + 0.01), Color.WHITE).material_override = \
			PsxMaterials.textured(PsxTextures.hazard(), Vector2(w / 0.6, 1))
	_box(holder, Vector3(w + 0.04, 0.06, depth + 0.04), Vector3(cx, base_h, zc), trim)  # sill
	# The room inside: a back wall, a desk with a lit monitor, a chair, a strip light.
	var ix0 := x0 + 0.1
	var ix1 := x1 - 0.1
	var inner := (ix0 + ix1) / 2.0
	_box(holder, Vector3(ix1 - ix0, top - base_h, 0.05), Vector3(inner, (base_h + top) / 2.0, z0 - depth + 0.08), Color("4a5054"))
	_box(holder, Vector3(minf(1.6, w - 0.4), 0.06, 0.6), Vector3(inner, base_h + 0.32, z0 - 0.6), Color("5a5e60"))  # desk top
	var screen := _box(holder, Vector3(0.5, 0.36, 0.05), Vector3(inner - 0.3, base_h + 0.6, z0 - 0.75), Color.WHITE)
	screen.material_override = PsxMaterials.textured(PsxTextures.cctv_screen(1), Vector2(3, 2), true)
	_box(holder, Vector3(0.56, 0.42, 0.12), Vector3(inner - 0.3, base_h + 0.6, z0 - 0.82), Color("1a1c1e"))  # its case
	_box(holder, Vector3(0.45, 0.5, 0.45), Vector3(inner + 0.4, base_h + 0.25, z0 - 1.4), Color("202326"))  # chair
	_box(holder, Vector3(0.45, 0.55, 0.06), Vector3(inner + 0.4, base_h + 0.75, z0 - 1.65), Color("202326"))
	var strip := _box(holder, Vector3(minf(1.8, w - 0.4), 0.05, 0.12), Vector3(inner, top - 0.08, zc), Color.WHITE)
	strip.material_override = PsxMaterials.glow(Color("d8e4d8"))
	# Windows: front, back and the side facing the road (the other side is against the wall or open).
	var glass := PsxMaterials.glass(Color(0.55, 0.72, 0.78, 0.22))
	var wh := top - base_h
	var wy := (base_h + top) / 2.0
	_box(holder, Vector3(w - 0.1, wh, 0.03), Vector3(cx, wy, z0), Color.WHITE).material_override = glass
	for sx in [x0, x1]:
		if absf(sx) < edge - 0.05:  # a side out in the corridor (not against the wall)
			_box(holder, Vector3(0.03, wh, depth - 0.1), Vector3(sx, wy, zc), Color.WHITE).material_override = glass
	# Steel posts at the corners and a mullion mid-front; a steel header up to the ceiling.
	for px in [x0 + 0.05, cx, x1 - 0.05]:
		_box(holder, Vector3(0.1, wh, 0.1), Vector3(px, wy, z0), steel)
	for px in [x0 + 0.05, x1 - 0.05]:
		_box(holder, Vector3(0.1, wh, 0.1), Vector3(px, wy, z0 - depth + 0.05), steel)
	_box(holder, Vector3(w + 0.1, CEILING_Y - top, depth + 0.1), Vector3(cx, (top + CEILING_Y) / 2.0, zc), steel)
	_box(holder, Vector3(w + 0.14, 0.05, depth + 0.14), Vector3(cx, top + 0.02, zc), trim)  # trim under the header
	_box(holder, Vector3(w, 0.08, 0.08), Vector3(cx, 2.6, z0), steel)  # a transom bar across the front glass
	# The red beacon on the front of the header, toward the corridor.
	var bx := x0 + 0.4 if absf(x0) < absf(x1) else x1 - 0.4
	_box(holder, Vector3(0.36, 0.36, 0.08), Vector3(bx, top + 0.3, z0 + 0.08), Color("2a2d30"))
	var beacon := _box(holder, Vector3(0.28, 0.28, 0.16), Vector3(bx, top + 0.3, z0 + 0.16), Color.WHITE)
	beacon.material_override = PsxMaterials.glow(Color(1.0, 0.16, 0.1))
	_ambience.add_lamp(beacon, Color(1.0, 0.16, 0.1) * 1.3, 4.0, {"alert": false})
	# A keycard reader by the door on the corridor side.
	_box(holder, Vector3(0.1, 0.26, 0.14), Vector3(bx, 1.35, z0 + 0.06), Color("1e2022"))
	_box(holder, Vector3(0.06, 0.04, 0.02), Vector3(bx, 1.42, z0 + 0.14), Color.WHITE).material_override = PsxMaterials.glow(Color(1.0, 0.18, 0.12))
	return holder


## The SECURITY WING's checkpoint turnstile, one per lane (a jump obstacle, user reference): a
## waist-high steel housing with a hazard band, a card post, and a three-armed rotor with one arm
## across the lane at hip height (built to the player's scale, like the lobby's speed gates).
func _build_turnstile(parent: Node3D, seg: Dictionary, at: float, x: float, lane: int) -> Node3D:
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.transform = _frame_at(seg, at) * Transform3D(Basis.IDENTITY, Vector3(x, 0, 0))
	var side := -1.0 if lane % 2 == 0 else 1.0
	var hx := side * (tuning.lane_width * 0.5 - 0.22)
	var steel := Color("3e4447")
	_box(holder, Vector3(0.34, 0.92, 0.62), Vector3(hx, 0.46, 0), steel)  # housing
	_box(holder, Vector3(0.36, 0.14, 0.64), Vector3(hx, 0.1, 0), Color.WHITE).material_override = \
			PsxMaterials.textured(PsxTextures.hazard(), Vector2(1, 1))
	_box(holder, Vector3(0.36, 0.04, 0.64), Vector3(hx, 0.94, 0), Color("8a9094"))  # top plate
	_box(holder, Vector3(0.08, 0.3, 0.08), Vector3(hx, 1.1, -0.18), Color("8a9094"))  # card post
	_box(holder, Vector3(0.1, 0.06, 0.1), Vector3(hx, 1.27, -0.18), Color.WHITE).material_override = PsxMaterials.glow(Color(1.0, 0.2, 0.12))
	var arm := _box(holder, Vector3(tuning.lane_width - 0.45, 0.05, 0.05), Vector3(-side * 0.2, 0.8, 0), Color("c8ccce"))  # the arm across
	arm.rotation.z = 0.0
	for a in [-1.0, 1.0]:  # the rotor's other two arms, angled down and away
		var other := _box(holder, Vector3(0.45, 0.05, 0.05), Vector3(hx - side * 0.2, 0.68, a * 0.08), Color("c8ccce"))
		other.rotation = Vector3(a * 0.9, 0, side * 0.6)
	return holder


## STAFF CANTEEN cover wall (user): a row of drinks machines across x0..x1, one per lane, in red,
## blue or orange. Tall enough to stand behind; you can't see or shoot through them.
func _build_vending_wall(parent: Node3D, seg: Dictionary, at: float, x0: float, x1: float) -> Node3D:
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.transform = _frame_at(seg, at)
	var edge := tuning.lane_count * tuning.lane_width / 2.0 + 1.0
	x0 = maxf(x0, -edge + 0.1)
	x1 = minf(x1, edge - 0.1)
	var n := maxi(1, roundi((x1 - x0) / tuning.lane_width))
	var mw := (x1 - x0) / n
	var tints := [Color("c41e1e"), Color("1e4ac4"), Color("e0700f")]
	for i in n:
		var cx := x0 + mw * (i + 0.5)
		var tint: Color = tints[absi(hash([seg["id"], at, i])) % tints.size()]
		_box(holder, Vector3(mw - 0.08, 2.2, 0.9), Vector3(cx, 1.1, 0), tint.darkened(0.35))  # cabinet
		var front := _box(holder, Vector3(mw - 0.2, 1.95, 0.03), Vector3(cx, 1.1, 0.46), Color.WHITE)
		front.material_override = PsxMaterials.textured(PsxTextures.vending_front(0, tint), Vector2(3, 2), true)
		_box(holder, Vector3(mw - 0.06, 0.12, 0.92), Vector3(cx, 0.06, 0), Color("1a1a1a"))  # plinth
		_box(holder, Vector3(mw - 0.06, 0.06, 0.92), Vector3(cx, 2.22, 0), tint.darkened(0.6))  # top trim
	return holder


## STAFF CANTEEN box cover: one long canteen table across the run of lanes x0..x1 (user: two lanes
## wide, for scale), built once for the run. Place settings (tray, plate, cup) down it, chairs both
## sides (some pulled out toward you), and in each lane something tall on it, a big drinks
## dispenser or a stack of trays, so it stands tall enough to hide you crouching behind it.
func _build_canteen_table(parent: Node3D, seg: Dictionary, at: float, x0: float, x1: float, lane0: int) -> Node3D:
	var holder := Node3D.new()
	parent.add_child(holder)
	var cx := (x0 + x1) / 2.0
	holder.transform = _frame_at(seg, at) * Transform3D(Basis.IDENTITY, Vector3(cx, 0, 0))
	var w := x1 - x0 - 0.1
	var lanes := maxi(1, roundi((x1 - x0) / tuning.lane_width))
	var wood := Color("a07a46")
	var leg := Color("2a2c2e")
	_box(holder, Vector3(w, 0.07, 0.86), Vector3(0, 0.76, 0), wood)
	_box(holder, Vector3(w + 0.02, 0.03, 0.88), Vector3(0, 0.72, 0), wood.darkened(0.4))
	var legs_x: Array = [-(w / 2.0 - 0.08), w / 2.0 - 0.08]
	if lanes > 1:
		legs_x.append(0.0)
	for lx in legs_x:
		for lz in [-0.36, 0.36]:
			_box(holder, Vector3(0.06, 0.72, 0.06), Vector3(lx, 0.36, lz), leg)
	for i in lanes:
		var mx := -w / 2.0 + w * (i + 0.5) / lanes  # the middle of this lane's stretch of table
		var flip := 1.0 if (lane0 + i) % 2 == 0 else -1.0
		_box(holder, Vector3(0.44, 0.03, 0.32), Vector3(mx + 0.25 * flip, 0.81, 0.12), Color("c8ccc8"))  # tray
		_box(holder, Vector3(0.16, 0.02, 0.16), Vector3(mx + 0.25 * flip, 0.83, 0.12), Color("e8e8e0"))  # plate
		var cup := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.05
		cyl.bottom_radius = 0.04
		cyl.height = 0.13
		cyl.radial_segments = 8
		cup.mesh = cyl
		cup.material_override = PsxMaterials.flat(Color("c42020") if i % 2 == 0 else Color("e8e4d8"))
		holder.add_child(cup)
		cup.position = Vector3(mx - 0.4 * flip, 0.86, 0.2)
		var tall := mx - 0.12 * flip
		if (lane0 + i) % 2 == 0:
			# The drinks dispenser: a steel base, a clear tank of orange squash, a lid, a tap toward you.
			_box(holder, Vector3(0.36, 0.12, 0.32), Vector3(tall, 0.86, -0.12), Color("8a9094"))
			_box(holder, Vector3(0.32, 0.36, 0.28), Vector3(tall, 1.1, -0.12), Color.WHITE).material_override = \
					PsxMaterials.glass(Color(1.0, 0.55, 0.15, 0.55))
			_box(holder, Vector3(0.24, 0.24, 0.2), Vector3(tall, 1.06, -0.12), Color("d86a1a"))  # the squash inside
			_box(holder, Vector3(0.36, 0.06, 0.32), Vector3(tall, 1.31, -0.12), Color("6a7076"))  # lid
			_box(holder, Vector3(0.06, 0.06, 0.08), Vector3(tall, 0.96, 0.07), Color("2a2c2e"))  # tap
		else:
			for k in 9:  # a stack of trays, a couple askew
				var tr := _box(holder, Vector3(0.44, 0.025, 0.32), Vector3(tall, 0.81 + k * 0.03, -0.16), Color("c8ccc8").darkened(0.06 * (k % 2)))
				tr.rotation.y = 0.12 * sin(k * 2.1)
		# A chair each side of this stretch: the near one pulled out toward you, or pushed in.
		var pulled := absi(hash([seg["id"], at, i])) % 2 == 0
		_canteen_chair(holder, Vector3(mx + 0.3 * flip, 0, 0.62 if pulled else 0.5), 0.15 * flip, false)
		_canteen_chair(holder, Vector3(mx - 0.2 * flip, 0, -0.55), 0.0, false)
	return holder


## A blue plastic canteen chair at `pos` (turned `yaw`), or lying on its side.
func _canteen_chair(parent: Node3D, pos: Vector3, yaw: float, on_side: bool) -> void:
	var chair := Node3D.new()
	parent.add_child(chair)
	chair.position = pos
	chair.rotation.y = yaw
	var blue := Color("2c3e5c")
	var steel := Color("8a8f96")
	_box(chair, Vector3(0.44, 0.05, 0.42), Vector3(0, 0.45, 0), blue)      # seat
	_box(chair, Vector3(0.44, 0.42, 0.05), Vector3(0, 0.7, -0.2), blue)    # back
	for lx in [-0.19, 0.19]:
		for lz in [-0.18, 0.18]:
			_box(chair, Vector3(0.03, 0.45, 0.03), Vector3(lx, 0.22, lz), steel)
	if on_side:
		chair.rotation.z = PI / 2.0
		chair.position.y += 0.22


## STAFF CANTEEN jump obstacles (user), one per lane: a stack of pizza boxes on a trolley, or
## (alternating) a canteen bench knocked over with a chair on its side.
func _build_canteen_jump(parent: Node3D, seg: Dictionary, at: float, x: float, lane: int, look: String) -> Node3D:
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.transform = _frame_at(seg, at) * Transform3D(Basis.IDENTITY, Vector3(x, 0, 0))
	if look == "pizza":
		var card := Color("c8a46a")
		for s in 2:  # two stacks side by side
			var sx := (s - 0.5) * 0.56
			var count := 6 if (lane + s) % 2 == 0 else 5
			for k in count:
				var b := _box(holder, Vector3(0.5, 0.075, 0.5), Vector3(sx + (0.02 if k % 2 else -0.02), 0.04 + k * 0.078, 0.0), card if k % 3 != 2 else card.darkened(0.12))
				b.rotation.y = 0.05 * (k % 3 - 1)
			_box(holder, Vector3(0.3, 0.005, 0.2), Vector3(sx, 0.04 + count * 0.078, 0.0), Color("b02a1e"))  # the printed logo
	else:
		var wood := Color("a07a46")
		var bench := Node3D.new()  # a bench tipped onto its side: seat facing you
		holder.add_child(bench)
		bench.rotation.x = -PI / 2.0 + 0.15
		bench.position = Vector3(0, 0.22, 0)
		_box(bench, Vector3(1.2, 0.36, 0.06), Vector3(0, 0, 0), wood)
		for lx in [-0.5, 0.5]:
			_box(bench, Vector3(0.05, 0.05, 0.44), Vector3(lx, 0.0, -0.22), Color("2a2c2e"))  # legs, sticking out
		_canteen_chair(holder, Vector3(0.25 if lane % 2 == 0 else -0.25, 0, -0.45), 0.6, true)
	return holder


## A wooden pallet at `pos` (its top at pos.y + 0.14), `w` x `d`.
func _pallet(parent: Node3D, pos: Vector3, w: float, d: float) -> void:
	var wood := Color("9a7444")
	for k in 5:  # deck boards
		_box(parent, Vector3(w, 0.03, d / 5.0 - 0.03), pos + Vector3(0, 0.125, -d / 2.0 + d / 5.0 * (k + 0.5)), wood)
	for bx in [-w / 2.0 + 0.08, 0.0, w / 2.0 - 0.08]:  # blocks and stringers
		_box(parent, Vector3(0.12, 0.08, d), pos + Vector3(bx, 0.06, 0), wood.darkened(0.3))
	_box(parent, Vector3(w, 0.02, d), pos + Vector3(0, 0.01, 0), wood.darkened(0.2))


## A box of the warehouse's stock at `pos` (sitting on it): wood crate, olive crate, cardboard
## or steel case, picked by `kind`.
func _stock(parent: Node3D, pos: Vector3, size: Vector3, kind: int) -> MeshInstance3D:
	var tex: Texture2D = [PsxTextures.crate_wood(), PsxTextures.olive_crate(), PsxTextures.cardboard_box(), PsxTextures.steel_case()][kind % 4]
	var m := _box(parent, size, pos + Vector3(0, size.y / 2.0, 0), Color.WHITE)
	m.material_override = PsxMaterials.textured(tex, Vector2(3, 2))
	return m


## An oil drum standing at `pos`, in `colour`, with two rolled ribs and a lid.
func _drum(parent: Node3D, pos: Vector3, colour: Color) -> void:
	var drum := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.24
	cyl.bottom_radius = 0.24
	cyl.height = 0.88
	cyl.radial_segments = 10
	drum.mesh = cyl
	drum.material_override = PsxMaterials.flat(colour)
	parent.add_child(drum)
	drum.position = pos + Vector3(0, 0.44, 0)
	for ry in [0.3, 0.6]:
		var rib := MeshInstance3D.new()
		var r := CylinderMesh.new()
		r.top_radius = 0.25
		r.bottom_radius = 0.25
		r.height = 0.03
		r.radial_segments = 10
		rib.mesh = r
		rib.material_override = PsxMaterials.flat(colour.darkened(0.35))
		parent.add_child(rib)
		rib.position = pos + Vector3(0, ry, 0)


## WAREHOUSE box cover: a wooden crate on a pallet (wood), or a steel case or a cluster of blue
## drums on a pallet (metal).
func _build_warehouse_box(parent: Node3D, seg: Dictionary, at: float, x: float, lane: int, metal: bool) -> Node3D:
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.transform = _frame_at(seg, at) * Transform3D(Basis.IDENTITY, Vector3(x, 0, 0))
	_pallet(holder, Vector3.ZERO, 1.2, 1.0)
	if not metal:
		_stock(holder, Vector3(0, 0.14, 0), Vector3(1.0, 0.95, 0.9), 0)
	elif lane % 2 == 0:
		_stock(holder, Vector3(0, 0.14, 0), Vector3(1.05, 0.9, 0.85), 3)
	else:
		for dx in [-0.27, 0.27]:
			for dz in [-0.24, 0.24]:
				_drum(holder, Vector3(dx, 0.14, dz), _theme(seg["id"]).get("drum_color", Color("26365a")))
	return holder


## WAREHOUSE jump obstacle: a stack of four empty pallets.
func _build_pallet_stack(parent: Node3D, seg: Dictionary, at: float, x: float, lane: int) -> Node3D:
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.transform = _frame_at(seg, at) * Transform3D(Basis.IDENTITY, Vector3(x, 0, 0))
	for k in 3:
		var p := Node3D.new()
		holder.add_child(p)
		p.position = Vector3(0.03 * ((k + lane) % 3 - 1), k * 0.15, 0)
		p.rotation.y = 0.04 * ((k + lane) % 3 - 1)
		_pallet(p, Vector3.ZERO, 1.2, 0.95)
	return holder


## WAREHOUSE cover wall across x0..x1: a stack of crates three high on pallets, or a forklift with
## its load raised (any width left over gets a crate stack). You can't see or shoot through it.
func _build_warehouse_wall(parent: Node3D, seg: Dictionary, at: float, x0: float, x1: float, look: String) -> Node3D:
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.transform = _frame_at(seg, at)
	var edge := tuning.lane_count * tuning.lane_width / 2.0 + 0.9
	x0 = maxf(x0, -edge)
	x1 = minf(x1, edge)
	var stack_from := x0
	if look == "forklift":
		var fw := 1.3
		var fx := x0 + fw / 2.0 + 0.05
		stack_from = x0 + fw + 0.15
		var yellow := Color("d8a020")
		_box(holder, Vector3(fw, 0.7, 1.8), Vector3(fx, 0.55, -0.4), yellow)  # body
		_box(holder, Vector3(fw, 0.5, 0.5), Vector3(fx, 0.75, -1.2), Color("2a2a2a"))  # counterweight
		for wz in [0.3, -1.1]:
			for s in [-1.0, 1.0]:
				_box(holder, Vector3(0.2, 0.45, 0.45), Vector3(fx + s * (fw / 2.0 - 0.05), 0.23, wz), Color("1a1a1a"))  # wheels
		for s in [-1.0, 1.0]:  # the cage over the seat
			_box(holder, Vector3(0.06, 1.3, 0.06), Vector3(fx + s * 0.55, 1.55, -0.2), Color("2a2a2a"))
			_box(holder, Vector3(0.06, 1.3, 0.06), Vector3(fx + s * 0.55, 1.55, -1.0), Color("2a2a2a"))
		_box(holder, Vector3(1.16, 0.06, 0.9), Vector3(fx, 2.2, -0.6), Color("2a2a2a"))
		_box(holder, Vector3(0.5, 0.5, 0.5), Vector3(fx, 1.1, -0.7), Color("303030"))  # seat
		for s in [-1.0, 1.0]:  # the mast, toward you
			_box(holder, Vector3(0.1, 2.6, 0.12), Vector3(fx + s * 0.42, 1.3, 0.55), Color("3a3a3a"))
			_box(holder, Vector3(0.12, 0.06, 1.0), Vector3(fx + s * 0.25, 1.45, 1.05), Color("2a2a2a"))  # forks
		_pallet(holder, Vector3(fx, 1.48, 1.05), 1.15, 0.95)
		_stock(holder, Vector3(fx, 1.62, 1.05), Vector3(1.05, 0.8, 0.85), 1)  # the load, raised
	if x1 - stack_from > 0.6:
		var n := maxi(1, roundi((x1 - stack_from) / 1.25))
		var cw := (x1 - stack_from) / n
		for i in n:
			var cx := stack_from + cw * (i + 0.5)
			_pallet(holder, Vector3(cx, 0, 0), cw - 0.05, 1.0)
			var y := 0.14
			for k in 3:
				var sz := Vector3(cw - 0.12 - 0.05 * k, 1.0 - 0.08 * k, 0.95 - 0.05 * k)
				_stock(holder, Vector3(cx, y, 0), sz, absi(hash([seg["id"], at, i, k])) % 4)
				y += sz.y
	return holder


## WAREHOUSE duck-under (user reference): a hazard-striped steel girder hanging from chains at head
## height across the blocked lanes, the chains running up to the crane.
func _build_girder(parent: Node3D, seg: Dictionary, at: float, y: float, ends: Array) -> Node3D:
	var frame := _frame_at(seg, at)
	var e0: float = ends[0]["x"]
	var e1: float = ends[1]["x"]
	var gy := WIRE_LOW - 0.1  # head height, like the live wires (user: it hung too low at pipe height)
	var beam := _box(parent, Vector3(e1 - e0, 0.32, 0.26), Vector3.ZERO, Color.WHITE)
	beam.transform = frame * Transform3D(Basis.IDENTITY, Vector3((e0 + e1) / 2.0, gy, 0))
	beam.material_override = PsxMaterials.textured(PsxTextures.hazard(), Vector2((e1 - e0) / 0.8, 1))
	for flange in [-0.16, 0.16]:
		_box(parent, Vector3(e1 - e0, 0.04, 0.34), Vector3.ZERO, Color("2a2a2a")).transform = \
				frame * Transform3D(Basis.IDENTITY, Vector3((e0 + e1) / 2.0, gy + flange, 0))
	for cx in [e0 + 0.3, e1 - 0.3]:
		var links := int((CEILING_Y - gy - 0.2) / 0.16)
		for k in links:  # a chain: alternate links turned 90 degrees
			var link := _box(parent, Vector3(0.05, 0.14, 0.02 if k % 2 == 0 else 0.05), Vector3.ZERO, Color("6a6a64"))
			link.transform = frame * Transform3D(Basis.IDENTITY, Vector3(cx, gy + 0.22 + k * 0.16, 0))
	return beam


## The office room the mission starts in, behind the first segment (negative distances), with a
## closed door into it: side and back walls, floor, ceiling, a desk, a chair, a filing cabinet,
## and the odd window / notice board. The door is bashed open at the start of the run.
func _build_start_room(seg: Dictionary) -> void:
	var room := Node3D.new()
	room.name = "StartRoom"
	seg["node"].add_child(room)
	var L := tuning.start_room_length
	var road_w := tuning.lane_count * tuning.lane_width
	var half := road_w / 2.0 + 1.0
	var theme: Dictionary = THEMES["office"]
	var wall_tex := _wall_texture(theme)
	_strip(room, seg, -L, 0.0, 0.0, half * 2.0, 0.0, PsxTextures.office_floor(), float(tuning.lane_count), tuning.lane_width)
	var roof := _strip(room, seg, -L, 0.0, 0.0, half * 2.0, CEILING_Y, PsxTextures.office_ceiling(), road_w / 2.0, 2.0)
	roof.rotate_object_local(Vector3.FORWARD, PI)
	_ceiling_lamp(room, seg, -L / 2.0, false)
	for side in [-1, 1]:
		_wall(room, seg, -L, 0.0, side * half, side, CEILING_Y, wall_tex)
	var office := PsxMaterials.textured(wall_tex, Vector2(3, 2))
	_item_box(room, seg, -L, Vector3(0, CEILING_Y / 2.0, 0.15), Vector3(half * 2.0, CEILING_Y, 0.3), Color.WHITE).material_override = office
	# The front wall, with a doorway in the player's lane.
	var dx := _player.lane_x(tuning.lane_count / 2)
	var dw := DOOR_W + 0.05
	var dh := DOOR_H
	var front := -0.15
	var left_w := dx - dw / 2.0 + half
	var right_w := half - (dx + dw / 2.0)
	_item_box(room, seg, 0.0, Vector3(-half + left_w / 2.0, CEILING_Y / 2.0, front), Vector3(left_w, CEILING_Y, 0.3), Color.WHITE).material_override = office
	_item_box(room, seg, 0.0, Vector3(half - right_w / 2.0, CEILING_Y / 2.0, front), Vector3(right_w, CEILING_Y, 0.3), Color.WHITE).material_override = office
	_item_box(room, seg, 0.0, Vector3(dx, (dh + CEILING_Y) / 2.0, front), Vector3(dw, CEILING_Y - dh, 0.3), Color.WHITE).material_override = office
	# The door hangs on a hinge at the left of the doorway.
	var hinge := Node3D.new()
	room.add_child(hinge)
	hinge.transform = _frame_at(seg, 0.0) * Transform3D(Basis.IDENTITY, Vector3(dx - dw / 2.0, 0, front))
	var panel := _box(hinge, Vector3(dw - 0.04, dh - 0.02, 0.07), Vector3(dw / 2.0, dh / 2.0, 0), Color.WHITE)
	panel.material_override = PsxMaterials.textured(PsxTextures.door(), Vector2(3, 2))
	_doors.append({"node": hinge, "at": 0.0, "owner": seg["node"], "seg": seg, "sound": "door_wood"})
	_make_solid(room)
	# Furniture, clear of the player's lane.
	_item_box(room, seg, -8.0, Vector3(_player.lane_x(0), 0.38, 0), Vector3(1.4, 0.76, 0.8), Color.WHITE).material_override = \
			PsxMaterials.textured(PsxTextures.desk(), Vector2(3, 2))
	_item_box(room, seg, -8.9, Vector3(_player.lane_x(0) + 0.2, 0.25, 0), Vector3(0.45, 0.5, 0.45), Color("3e4c5c"))  # chair
	_item_box(room, seg, -10.5, Vector3(_player.lane_x(tuning.lane_count - 1), 0.65, 0), Vector3(0.9, 1.3, 0.7), Color.WHITE).material_override = \
			PsxMaterials.textured(PsxTextures.cabinet(), Vector2(3, 2))
	_item_box(room, seg, -6.0, Vector3(-(half - 0.03), 1.65, 0), Vector3(0.05, 0.9, 1.6), Color.WHITE).material_override = \
			PsxMaterials.textured(PsxTextures.office_window(), Vector2(3, 2))
	_item_box(room, seg, -9.0, Vector3(half - 0.03, 1.5, 0), Vector3(0.05, 0.75, 1.1), Color.WHITE).material_override = \
			PsxMaterials.textured(PsxTextures.notice_board(), Vector2(3, 2))


## The lamps that light an area (MGS-style: the light comes from fixtures you can see, with
## dark between them). Office: fluorescent panels down the ceiling. Tunnel: caged sodium bulbs
## on alternate walls, with a conduit along each wall. Rooftops: sodium lamp posts at the roof
## edge and a searchlight sweeping across from a neighbouring building. Every few lamps one is
## failing and flickers.
func _build_lamps(parent: Node3D, seg: Dictionary) -> void:
	var theme := _theme(seg["id"])
	var length: float = seg["length"]
	var ramp: float = seg["ramp_len"]
	var edge := tuning.lane_count * tuning.lane_width / 2.0 + 1.0
	var n := 0
	match theme.get("lamps", ""):
		"atrium":
			var z := ramp + 4.0
			while z < length - 1.0:
				_atrium_lamp(parent, seg, z, n % tuning.flicker_every == 3)
				z += tuning.office_lamp_spacing * 1.2
				n += 1
		"pendant":
			var z := ramp + 4.0
			while z < length - 1.0:
				_pendant_lamp(parent, seg, z, n % tuning.flicker_every == 3)
				z += tuning.office_lamp_spacing * 1.25
				n += 1
		"ceiling":
			var z := ramp + 3.0
			while z < length - 1.0:
				if not _is_outdoor(seg, z):
					_ceiling_lamp(parent, seg, z, n % tuning.flicker_every == 3)
				z += tuning.office_lamp_spacing
				n += 1
		"bulbs":
			for piece in _pieces(seg, ramp, length):
				for side in [-1, 1]:
					var mid := (piece.x + piece.y) / 2.0
					_item_box(parent, seg, mid, Vector3(side * (edge - 0.1), 2.95, 0), Vector3(0.12, 0.12, piece.y - piece.x), Color("2c302c"))
			var z := ramp + 4.0
			while z < length - 1.0:
				var side := -1 if n % 2 == 0 else 1
				var bulb := _item_box(parent, seg, z, Vector3(side * (edge - 0.25), 2.55, 0), Vector3(0.2, 0.2, 0.2), Color.WHITE)
				var on := PsxMaterials.glow(Color("ffb060"))
				bulb.material_override = on
				# The cage and the bracket to the wall.
				_item_box(parent, seg, z, Vector3(side * (edge - 0.25), 2.55, 0), Vector3(0.28, 0.04, 0.28), Color("202420"))
				_item_box(parent, seg, z, Vector3(side * (edge - 0.25), 2.72, 0), Vector3(0.3, 0.06, 0.3), Color("202420"))
				_item_box(parent, seg, z, Vector3(side * (edge - 0.13), 2.72, 0), Vector3(0.26, 0.05, 0.05), Color("202420"))
				var at := Node3D.new()
				parent.add_child(at)
				at.transform = _frame_at(seg, z) * Transform3D(Basis.IDENTITY, Vector3(side * (edge - 0.7), 2.3, 0))
				_ambience.add_lamp(at, Color(1.0, 0.6, 0.28) * 1.7, 8.5, {"flicker": 0.25 if n % tuning.flicker_every == 2 else 0.0,
						"fixture": bulb, "on_mat": on, "off_mat": PsxMaterials.flat(Color("4a3a2a"))})
				z += tuning.tunnel_lamp_spacing
				n += 1
		"posts":
			var z := ramp + 6.0
			var holes: Dictionary = seg.get("holes", {})
			while z < length - 2.0:
				var side := -1 if n % 2 == 0 else 1
				var hole: Vector2 = holes.get(side, Vector2.ZERO)
				if z < hole.x - 2.0 or z > hole.y + 2.0:
					_lamp_post(parent, seg, z, side * (edge - 0.3), -side)
				z += tuning.roof_lamp_spacing
				n += 1
		"helipad":
			for side in [-1, 1]:
				_lamp_post(parent, seg, length * 0.4, side * (edge - 0.3), -side)


## A fluorescent ceiling panel with its pool of cold white light.
func _ceiling_lamp(parent: Node3D, seg: Dictionary, z: float, failing: bool) -> void:
	var tube := _item_box(parent, seg, z, Vector3(0, CEILING_Y - 0.04, 0), Vector3(0.5, 0.05, 1.5), Color.WHITE)
	var warm: Color = _theme(seg["id"]).get("lamp_color", Color(0.88, 1.0, 0.9))  # the area's light colour
	var on := PsxMaterials.glow(Color("e8f4e8").lerp(warm, 0.6))
	tube.material_override = on
	_item_box(parent, seg, z, Vector3(0, CEILING_Y - 0.02, 0), Vector3(0.62, 0.03, 1.62), Color("5a6064"))  # housing
	var at := Node3D.new()
	parent.add_child(at)
	at.transform = _frame_at(seg, z) * Transform3D(Basis.IDENTITY, Vector3(0, CEILING_Y - 1.6, 0))
	_ambience.add_lamp(at, warm * 2.0, 7.0, {"flicker": 0.3 if failing else 0.0,
			"fixture": tube, "on_mat": on, "off_mat": PsxMaterials.flat(Color("7a8480"))})


## A sodium lamp post at the roof edge, its head arching in over the roof.
func _lamp_post(parent: Node3D, seg: Dictionary, z: float, x: float, inward: int) -> void:
	var metal := Color("2e3236")
	_item_box(parent, seg, z, Vector3(x, 1.6, 0), Vector3(0.12, 3.2, 0.12), metal)
	_item_box(parent, seg, z, Vector3(x + inward * 0.35, 3.2, 0), Vector3(0.8, 0.08, 0.1), metal)
	var head := _item_box(parent, seg, z, Vector3(x + inward * 0.7, 3.12, 0), Vector3(0.34, 0.1, 0.22), Color.WHITE)
	head.material_override = PsxMaterials.glow(Color("ffc070"))
	var at := Node3D.new()
	parent.add_child(at)
	at.transform = _frame_at(seg, z) * Transform3D(Basis.IDENTITY, Vector3(x + inward * 1.0, 2.8, 0))
	_ambience.add_lamp(at, Color(1.0, 0.64, 0.3) * 1.3, 9.5)


## A zone door (the start of an area; it was the halfway marker): a wall right across, side wall to side wall and up
## to the ceiling, with a double door over the middle lanes that you burst through. Office doors on
## the main floor, barred gates in the tunnel. The outer lanes are funnelled in just before it.
func _build_marker(outer: Node3D, seg: Dictionary, at: float) -> void:
	var parent := Node3D.new()  # all of it in one node, so it can be made solid in one go
	parent.name = "Marker"
	outer.add_child(parent)
	var theme := _theme(seg["id"])
	var edge := tuning.lane_count * tuning.lane_width / 2.0 + 1.0
	var top: float = _ceil(seg["id"]) if theme.get("ceiling", false) else maxf(theme["height"], GATE_H + 0.5)
	var ow := MARKER_LANES * tuning.lane_width - 0.1  # the doorway
	var dh := GATE_H
	var wall := PsxMaterials.textured(_stair_wall_texture(theme), Vector2(3, 2))
	for s in [-1, 1]:
		var w := edge - ow / 2.0 - 0.08
		_item_box(parent, seg, at, Vector3(s * (ow / 2.0 + 0.08 + w / 2.0), top / 2.0, 0), Vector3(w, top, 0.3), Color.WHITE).material_override = wall
		_item_box(parent, seg, at, Vector3(s * (ow / 2.0 + 0.04), dh / 2.0, 0), Vector3(0.08, dh, 0.34), Color("3a3e42"))
	_item_box(parent, seg, at, Vector3(0, (dh + top) / 2.0, 0), Vector3(ow + 0.16, top - dh, 0.3), Color.WHITE).material_override = wall
	_item_box(parent, seg, at, Vector3(0, dh + 0.04, 0), Vector3(ow + 0.16, 0.08, 0.34), Color("3a3e42"))
	var barred := String(theme.get("marker_door", "office")) == "bars"
	if theme.has("marker_light"):
		# A warning light over the gate (the SECURITY WING's checkpoint), facing you.
		var light := _item_box(parent, seg, at, Vector3(0, dh + 0.3, 0.2), Vector3(0.5, 0.22, 0.12), Color.WHITE)
		light.material_override = PsxMaterials.glow(theme["marker_light"])
		_ambience.add_lamp(light, theme["marker_light"] * 1.2, 4.0, {"alert": false})
		for s in [-1, 1]:  # hazard stripes on the posts
			_item_box(parent, seg, at, Vector3(s * (ow / 2.0 + 0.04), 0.35, 0.18), Vector3(0.1, 0.7, 0.02), Color.WHITE).material_override = \
					PsxMaterials.textured(PsxTextures.hazard(), Vector2(1, 2))
	# Leaving the WAREHOUSE (user): a roller shutter that rolls up as you come, not doors.
	if String(_theme(seg.get("from_id", seg["id"])).get("exit_door", "")) == "shutter":
		_build_shutter(parent, seg, at, ow, dh)
		_make_solid(parent)
		_markers.append({"at": seg["start"] + at, "seg": seg})
		return
	var leaf_w := ow / 2.0
	var door_mat := PsxMaterials.textured(PsxTextures.door(), Vector2(3, 2))
	var bar := Color("2c3034")
	for s in [-1, 1]:
		# Hinged at the doorway's side, the leaf reaching in to meet the other one in the middle.
		var hinge := Node3D.new()
		parent.add_child(hinge)
		hinge.transform = _frame_at(seg, at) * Transform3D(Basis.IDENTITY, Vector3(s * ow / 2.0, 0, 0))
		var mid: float = -s * leaf_w / 2.0
		if barred:
			# A prison gate: a frame of flat rails with round-ish bars between.
			for y in [0.12, dh / 2.0, dh - 0.12]:
				_box(hinge, Vector3(leaf_w - 0.04, 0.1, 0.06), Vector3(mid, y, 0), bar)
			for e in [0.05, leaf_w - 0.05]:
				_box(hinge, Vector3(0.08, dh - 0.04, 0.06), Vector3(-s * e, dh / 2.0, 0), bar)
			var bars := 5
			for i in bars:
				var bx: float = -s * (leaf_w * (i + 1) / (bars + 1))
				_box(hinge, Vector3(0.04, dh - 0.1, 0.04), Vector3(bx, dh / 2.0, 0), Color("4a4f54"))
		else:
			var panel := _box(hinge, Vector3(leaf_w - 0.03, dh - 0.02, 0.07), Vector3(mid, dh / 2.0, 0), Color.WHITE)
			panel.material_override = door_mat
			if s > 0:
				panel.scale.x = -1.0  # the right leaf is the left one mirrored: handle in the middle
			_box(hinge, Vector3(0.05, 0.3, 0.1), Vector3(-s * (leaf_w - 0.15), 1.05, 0), Color("b8b08a"))  # push bar
		if not seg.get("no_doors", false):
			# Each leaf swings away from you round its own hinge: the left one way, the right the other.
			var door := {"node": hinge, "at": seg["start"] + at, "owner": seg["node"], "seg": seg, "swing": -s}
			if s < 0:  # one crash for the pair
				door["sound"] = "door_bars" if barred else "door_wood"
			_doors.append(door)
		# Each leaf blocks line of sight until it swings open (the mirrored office leaf can't carry
		# a collision box of its own, so the hinge does).
		_solid_box(hinge, Transform3D(Basis.IDENTITY, Vector3(mid, dh / 2.0, 0)), Vector3(leaf_w, dh, 0.1))
	# Over the doorway: a red emergency lamp at the tunnel gates, a green exit sign at office doors.
	var sign_col := Color("ff3a28") if barred else Color("40d070")
	var sign := _item_box(parent, seg, at - 0.2, Vector3(0, dh + 0.3, 0), Vector3(0.7 if not barred else 0.3, 0.18 if not barred else 0.25, 0.06), Color.WHITE)
	sign.material_override = PsxMaterials.glow(sign_col)
	var glow_at := Node3D.new()
	parent.add_child(glow_at)
	glow_at.transform = _frame_at(seg, at - 1.0) * Transform3D(Basis.IDENTITY, Vector3(0, dh + 0.2, 0))
	_ambience.add_lamp(glow_at, sign_col * (1.2 if barred else 0.7), 5.0 if barred else 3.5, {"alert": false})
	_make_solid(parent)  # the wall either side and over the doorway
	_markers.append({"at": seg["start"] + at, "seg": seg})


## The WAREHOUSE's exit (user reference): a steel roller shutter across the doorway, its roll
## housing above, guide rails, hazard posts and an amber warning light. It rolls up as you come.
func _build_shutter(parent: Node3D, seg: Dictionary, at: float, ow: float, dh: float) -> void:
	var shutter := Node3D.new()
	parent.add_child(shutter)
	shutter.transform = _frame_at(seg, at)
	var curtain := _box(shutter, Vector3(ow, dh, 0.08), Vector3(0, dh / 2.0, 0), Color.WHITE)
	curtain.material_override = PsxMaterials.textured(PsxTextures.roller_shutter(), Vector2(ow / 1.6, dh / 1.0))
	_solid_box(shutter, Transform3D(Basis.IDENTITY, Vector3(0, dh / 2.0, 0)), Vector3(ow, dh, 0.1))
	_item_box(parent, seg, at, Vector3(0, dh + 0.2, 0.1), Vector3(ow + 0.3, 0.42, 0.45), Color("3e4448"))  # roll housing
	for s in [-1.0, 1.0]:
		_item_box(parent, seg, at, Vector3(s * (ow / 2.0 + 0.06), dh / 2.0, 0), Vector3(0.12, dh, 0.16), Color("2a2e30"))  # guide rail
		_item_box(parent, seg, at, Vector3(s * (ow / 2.0 + 0.25), 0.5, 0.25), Vector3(0.16, 1.0, 0.16), Color.WHITE).material_override = \
				PsxMaterials.textured(PsxTextures.hazard(), Vector2(1, 2))  # hazard post
	var amber := Color(1.0, 0.6, 0.12)
	var lamp := _item_box(parent, seg, at, Vector3(ow / 2.0 + 0.3, dh + 0.25, 0.35), Vector3(0.22, 0.22, 0.22), Color.WHITE)
	lamp.material_override = PsxMaterials.glow(amber)
	_ambience.add_lamp(lamp, amber * 1.2, 4.0, {"alert": false, "blink": 0.8})
	if not seg.get("no_doors", false):
		_doors.append({"node": shutter, "at": seg["start"] + at, "owner": seg["node"], "seg": seg, "shutter": true,
				"sound": "door_steel"})


## Up it goes: the shutter rolls up into its housing.
func _raise_shutter(shutter: Node3D) -> void:
	RunLog.record_event("door_bash", {})
	var tween := shutter.create_tween()
	tween.tween_property(shutter, "position:y", shutter.position.y + GATE_H - 0.05, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## Forced movement. The outer lanes can't get through a halfway marker's doorway: just before one,
## anyone out there is steered in to the nearest lane that can. And at the very end you're steered
## into the centre lane, lined up with the chopper.
func _funnel_to_markers() -> void:
	if _player.in_cover:
		return
	var d := _player.distance_run()
	var mid: int = (tuning.lane_count - 1) / 2
	var reach := (MARKER_LANES - 1) / 2
	for m in _markers:
		if m["seg"].get("promoted", false) and d >= m["at"] - MARKER_FUNNEL and d <= m["at"] + 0.3:
			_player.lane = clampi(_player.lane, mid - reach, mid + reach)
	# The run to the chopper: into the centre lane, lined up with it.
	var seg := _segment_at(d)
	if _graph.end_type(seg["id"]) == "extract" and seg.get("promoted", false) and d >= float(seg["end"]) - CHOPPER_FUNNEL:
		_player.lane = mid


## Out of the room: the door flies open off its hinge and the camera jolts.
func _bash_door(door: Node3D, swing: float = 1.0) -> void:
	RunLog.record_event("door_bash", {})
	_shake = 1.0 if _shake_on else 0.0  # SCREEN SHAKE setting
	# Swings away from the player, out into the lobby, as if shouldered open.
	var tween := door.create_tween()
	tween.tween_property(door, "rotation:y", door.rotation.y + 1.9 * swing, 0.16).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(door, "rotation:z", door.rotation.z + 0.1 * swing, 0.16)


## Where there is no way straight on: a wall across the middle lanes. Only the outer lanes (ladders) get out.
func _build_dead_end(parent: Node3D, seg: Dictionary) -> void:
	var length: float = seg["length"]
	var theme := _theme(seg["id"])
	var h: float = CEILING_Y if theme.get("ceiling", false) else maxf(theme["height"], 1.2)
	var w := (tuning.lane_count - 2) * tuning.lane_width
	var wall := _item_box(parent, seg, length, Vector3(0, h / 2.0, -0.2), Vector3(w, h, 0.4), Color.WHITE)
	wall.material_override = PsxMaterials.textured(_wall_texture(theme), Vector2(3, 2))
	_make_solid(wall)


## Rails and rungs up (or down) the ladder lane at the start of the segment the ladder leads to.
func _build_ladder(parent: Node3D, seg: Dictionary, side: String) -> void:
	var lane := 0 if side == "left" else tuning.lane_count - 1
	var x := _player.lane_x(lane)
	var ramp: float = seg["ramp_len"]
	var metal := Color("8a8f96")
	var f0 := _frame_in_leg(seg, 0, 0.0)
	var f1 := _frame_in_leg(seg, 0, ramp)
	for rail in [-1, 1]:
		var p0 := f0 * Vector3(x + rail * 0.45, 0.9, 0)
		var p1 := f1 * Vector3(x + rail * 0.45, 0.9, 0)
		var post := _box(parent, Vector3(0.08, 0.08, p0.distance_to(p1)), Vector3.ZERO, metal)
		post.transform = Transform3D(Basis.looking_at(p1 - p0), (p0 + p1) / 2.0)
	for i in 8:
		var t := (i + 0.5) / 8.0
		_item_box(parent, seg, ramp * t, Vector3(x, 0.9, 0), Vector3(0.9, 0.06, 0.06), metal)
	if seg["dy"] > 0.0:
		_build_ladder_shaft(parent, seg, x)


## Climbing out (a ladder up from the tunnel): a shaft round the ladder, closed off from the rest
## of the tunnel's end, and the ground above floored over round the hatch, so going up you never
## see through to the sky or the void, only up the shaft.
func _build_ladder_shaft(parent: Node3D, seg: Dictionary, x: float) -> void:
	var ramp: float = seg["ramp_len"]
	var dy: float = seg["dy"]
	var w := tuning.lane_width
	var edge := tuning.lane_count * w / 2.0 + 1.0
	var below := _theme(seg.get("from_id", seg["id"]))
	var mid := ramp / 2.0
	var shaft := PsxMaterials.textured(_wall_texture(below), Vector2(3.0 * (ramp + 0.4) / 2.0, 2.0 * dy / 2.0))
	for side in [-1, 1]:
		_item_box(parent, seg, mid, Vector3(x + side * (w / 2.0 + 0.12), dy / 2.0 - _height(seg, mid), 0),
				Vector3(0.2, dy, ramp + 0.4), Color.WHITE).material_override = shaft
	# The tunnel's end beside the shaft, out to its side wall.
	var out := signf(x)
	var from := absf(x) + w / 2.0 + 0.2
	if edge + 0.2 - from > 0.05:
		_item_box(parent, seg, 0.0, Vector3(out * (from + edge + 0.2) / 2.0, CEILING_Y / 2.0, 0), Vector3(edge + 0.2 - from, CEILING_Y, 0.3),
				Color.WHITE).material_override = PsxMaterials.textured(_wall_texture(below), Vector2(1, 2))
	# The ground round the hatch: the middle lanes and this side's edge. (The other ladder's lane
	# stays open: it's floored by its own branch, which leaves its own hatch open.)
	var ground := PsxMaterials.textured(_ground(seg["id"]), Vector2(3.0, 2.0))
	var inner := (tuning.lane_count - 2) * w / 2.0
	var hatch_lo := absf(x) - w / 2.0
	var outer_from := absf(x) + w / 2.0
	var y := dy - 0.03 - _height(seg, mid)
	_item_box(parent, seg, mid, Vector3(0, y, 0), Vector3(inner * 2.0, 0.06, ramp + 0.1), Color.WHITE).material_override = ground
	_item_box(parent, seg, mid, Vector3(out * (outer_from + edge + 0.2) / 2.0, y, 0), Vector3(edge + 0.2 - outer_from, 0.06, ramp + 0.1),
			Color.WHITE).material_override = ground
	# Hazard edging round the hatch.
	var hz := PsxMaterials.textured(PsxTextures.hazard(), Vector2(3.0, 2.0))
	for e in [hatch_lo, absf(x) + w / 2.0]:
		_item_box(parent, seg, mid, Vector3(out * e, dy + 0.01 - _height(seg, mid), 0), Vector3(0.12, 0.04, ramp + 0.1), Color.WHITE).material_override = hz


## The first few metres of a branch closed by alert, behind a lockdown shutter.
func _build_locked_stub(seg: Dictionary, edge: Dictionary, slam: bool) -> Node3D:
	var stub := _segment_shape(StringName(edge["to"]), edge, seg["id"])
	var xf := _frame_after(seg, edge)
	stub["legs"] = _plan_legs(stub, xf)  # planned at full length, so it bends where the real one would
	stub["length"] = minf(stub["length"], tuning.locked_stub_length)
	stub["start"] = seg["end"]
	stub["no_doors"] = true  # you can't go this way, so its stairwell doors never open
	var node := Node3D.new()
	node.name = "Locked_" + String(edge["to"])
	_world.add_child(node)
	node.transform = xf
	stub["node"] = node
	var side := RouteGraph.side_of(edge)
	var clear := _overlap_clear()
	_build_surfaces(node, stub, stub["length"], clear if side == "right" else 0.0, clear if side == "left" else 0.0)

	# The shutter covers the way in: the whole road, or just the one-lane stairwell door.
	var stairs := _is_stairs(stub)
	var width := tuning.lane_width + 0.4 if stairs else tuning.lane_count * tuning.lane_width + 2.2
	var cx := _player.lane_x(_stair_lane(stub)) if stairs else 0.0
	var h := DOOR_H + 0.1 if stairs else maxf(_theme(stub["id"])["height"], 3.0)
	var door := Node3D.new()
	door.name = "LockdownDoor"
	node.add_child(door)
	var f := _frame_at(stub, 0.05 if stairs else 1.5)
	door.transform = f * Transform3D(Basis.IDENTITY, Vector3(cx, 0, 0))
	var panel := _box(door, Vector3(width, h, 0.3), Vector3(0, h / 2.0, 0), Color.WHITE)
	panel.material_override = PsxMaterials.textured(PsxTextures.wall("corrugated", Color("5a5f66")), Vector2(3, 2))
	var band := _box(door, Vector3(width + 0.05, 0.5, 0.34), Vector3(0, 0.25, 0), Color.WHITE)
	band.material_override = PsxMaterials.textured(PsxTextures.hazard(), Vector2(6, 2))
	door.add_child(_sign_label("LOCKDOWN", DEAD_END_COLOR, width * 0.8, Vector3(0, h * 0.6, 0.2)))
	door.set_meta("closed_y", door.position.y)
	door.set_meta("open_y", door.position.y + h + 0.3)
	_make_solid(door)  # shut, you can't see (or shoot) past it
	if slam:
		door.position.y = door.get_meta("open_y")
		door.create_tween().tween_property(door, "position:y", door.get_meta("closed_y"), tuning.lockdown_close_time) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	return node


## Alert fell and a locked branch reopened: lift its door, then drop the stub (the full branch replaces it).
func _open_door(stub: Node3D) -> void:
	var door := stub.get_node_or_null("LockdownDoor")
	if door == null:
		stub.queue_free()
		return
	var tween := door.create_tween()
	tween.tween_property(door, "position:y", door.get_meta("open_y"), tuning.lockdown_close_time)
	tween.tween_callback(stub.queue_free)


## Paints each lane in its exit's colour with arrows and puts a sign over the split.
## The exits on offer depend on alert, so this is rebuilt whenever alert changes.
func _build_fork_cue() -> void:
	if _current.is_empty():
		return
	var seg := _current
	var node: Node3D = seg["node"]
	var old := node.get_node_or_null("ForkCue")
	if old:
		node.remove_child(old)
		old.queue_free()
	var id: StringName = seg["id"]
	if not _is_authored_fork(id):
		return

	var cue := Node3D.new()
	cue.name = "ForkCue"
	node.add_child(cue)
	var length: float = seg["length"]
	var road_w := tuning.lane_count * tuning.lane_width
	var cue_start := maxf(seg["ramp_len"], length - tuning.decision_lead - tuning.fork_cue_length)
	var opts := _graph.available_next(id, GameState.alert_level)
	var choice := RouteGraph.is_choice(opts)

	# The floor up to the split is plain floor (user decision: no lane paint or arrows; the sign
	# overhead and the prompt say where each lane goes).
	for piece in _pieces(seg, cue_start, length):
		_strip(cue, seg, piece.x, piece.y, 0.0, road_w, 0.0, _ground(id), float(tuning.lane_count), _ground_tile(id))
	if not choice:
		return

	# Sign gantry at the split: one panel per exit, over the lanes that take it.
	# Panels sit above the camera (y 3.4) so it never flies through them, and under any ceiling.
	var post_h := CEILING_Y if _theme(id).get("ceiling", false) else 5.6
	var at := length - tuning.decision_lead
	for s in [-1, 1]:
		_item_box(cue, seg, at, Vector3(s * (road_w / 2.0 + 0.3), post_h / 2.0, 0), Vector3(0.3, post_h, 0.3), Color("2e2e2a"))
	_item_box(cue, seg, at, Vector3(0, post_h - 0.2, 0), Vector3(road_w + 0.9, 0.25, 0.25), Color("2e2e2a"))
	for group in _lane_groups(opts):
		var x0 := _player.lane_x(group["from"]) - tuning.lane_width / 2.0
		var x1 := _player.lane_x(group["to"]) + tuning.lane_width / 2.0
		var edge: Dictionary = group["edge"]
		var color := DEAD_END_COLOR if edge.is_empty() else Hud.side_color(RouteGraph.side_of(edge))
		var text := "DEAD END" if edge.is_empty() else _graph.edge_label(id, edge)
		_item_box(cue, seg, at, Vector3((x0 + x1) / 2.0, post_h - 0.6, 0), Vector3(x1 - x0 - 0.15, 0.8, 0.12), color.darkened(0.55))
		var label := _sign_label(text, color, x1 - x0 - 0.2, Vector3.ZERO)
		cue.add_child(label)
		label.transform = _frame_at(seg, at) * Transform3D(Basis.IDENTITY, Vector3((x0 + x1) / 2.0, post_h - 0.6, 0.08))


## Runs of neighbouring lanes that take the same exit, left to right: [{from, to, edge}].
## edge is empty for lanes with no way on (the dead end between two ladders).
func _lane_groups(opts: Array[Dictionary]) -> Array[Dictionary]:
	var groups: Array[Dictionary] = []
	for lane in tuning.lane_count:
		var edge := RouteGraph.pick_edge(lane, tuning.lane_count, opts)
		if not groups.is_empty() and groups[-1]["edge"] == edge:
			groups[-1]["to"] = lane
		else:
			groups.append({"from": lane, "to": lane, "edge": edge})
	return groups


## A sign's text, shrunk to fit its panel.
func _sign_label(text: String, color: Color, width: float, pos: Vector3) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.modulate = color.lightened(0.3)
	label.outline_modulate = Color.BLACK
	label.font_size = 40
	label.outline_size = 8
	# About 0.6 font sizes per character across; never bigger than the default.
	label.pixel_size = minf(0.012, width / (text.length() * label.font_size * 0.62))
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	label.position = pos
	return label


## How high this area's ceiling is (the MAIN FLOOR LOBBY is a two-storey atrium).
func _ceil(id: StringName) -> float:
	return float(_theme(id).get("ceiling_y", CEILING_Y))


func _theme(id: StringName) -> Dictionary:
	return THEMES.get(_graph.node_data(id).get("theme", ""), THEMES["compound"])


func _ground(id: StringName) -> Texture2D:
	match _theme(id)["ground"]:
		"lobby_floor":
			return PsxTextures.lobby_floor()
		"warehouse_floor":
			return PsxTextures.warehouse_floor()
		"canteen_floor":
			return PsxTextures.canteen_floor()
		"security_floor":
			return PsxTextures.security_floor()
		"asphalt":
			return PsxTextures.asphalt()
		"office_floor":
			return PsxTextures.office_floor()
		"gravel":
			return PsxTextures.gravel()
	return PsxTextures.concrete()


## How long one floor tile is along the road (office tiles and roofing are square, one lane wide).
func _ground_tile(id: StringName) -> float:
	return tuning.lane_width if _theme(id)["ground"] in ["office_floor", "security_floor", "canteen_floor", "warehouse_floor", "lobby_floor", "gravel"] else 4.0


func _wall_texture(theme: Dictionary) -> Texture2D:
	if theme.has("wall_tex"):
		return _obstacle_texture(theme["wall_tex"])
	return PsxTextures.wall(theme["wall"], theme["color"])


func _ceiling_texture(theme: Dictionary) -> Texture2D:
	return _obstacle_texture(theme["ceiling_tex"]) if theme.has("ceiling_tex") else _wall_texture(theme)


## This area's look for an obstacle (see THEMES "skins"), or the default.
func _skin(id: StringName, what: String, default: String) -> String:
	return _theme(id).get("skins", {}).get(what, default)


## A blob shadow directly under an obstacle, one per run of neighbouring lanes, because
## overlapping shadows multiply into dark seams. Under an overhead pipe the gap to its shadow says "duck".
func _obstacle_shadows(parent: Node3D, seg: Dictionary, lanes: Array, at: float, size: Vector3) -> void:
	lanes.sort()
	var runs: Array[Array] = []
	for lane: int in lanes:
		if runs.is_empty() or lane != runs[-1][-1] + 1:
			runs.append([lane])
		else:
			runs[-1].append(lane)
	for run in runs:
		var x0 := _player.lane_x(run[0]) - size.x / 2.0
		var x1 := _player.lane_x(run[-1]) + size.x / 2.0
		var s := MeshInstance3D.new()
		s.mesh = PsxMaterials.shadow_mesh(Vector2(x1 - x0, size.z) + Vector2.ONE * tuning.shadow_margin * 2.0)
		s.material_override = PsxMaterials.shadow(true, tuning)
		parent.add_child(s)
		s.transform = _frame_at(seg, at) * Transform3D(Basis.IDENTITY, Vector3((x0 + x1) / 2.0, 0.03, 0))


func _obstacle_texture(name: String) -> Texture2D:
	match name:
		"hazard":
			return PsxTextures.hazard()
		"rust_pipe":
			return PsxTextures.rust_pipe()
		"crate_wood":
			return PsxTextures.crate_wood()
		"crate_metal":
			return PsxTextures.crate_metal()
		"cover_wall":
			return PsxTextures.cover_wall()
		"canteen_wall":
			return PsxTextures.canteen_wall()
		"lobby_wall":
			return PsxTextures.lobby_wall()
		"lobby_column":
			return PsxTextures.lobby_column()
		"lobby_ceiling":
			return PsxTextures.lobby_ceiling()
		"dock_wall":
			return PsxTextures.dock_wall()
		"concrete":
			return PsxTextures.concrete()
		"warehouse_wall":
			return PsxTextures.warehouse_wall()
		"warehouse_ceiling":
			return PsxTextures.warehouse_ceiling()
		"canteen_pillar":
			return PsxTextures.canteen_pillar()
		"kitchen_tile":
			return PsxTextures.kitchen_tile()
		"security_wall":
			return PsxTextures.security_wall()
		"cctv_monitors":
			return PsxTextures.cctv_monitors()
		"booth_window":
			return PsxTextures.booth_window()
		"office_wall":
			return PsxTextures.office_wall()
		"office_ceiling":
			return PsxTextures.office_ceiling()
		"cabinet":
			return PsxTextures.cabinet()
		"desk":
			return PsxTextures.desk()
		"door":
			return PsxTextures.door()
		"steel_door":
			return PsxTextures.steel_door()
		"roof_hut":
			return PsxTextures.wall("blocks", Color("7c7c72"))
		"tunnel_wall":
			return PsxTextures.tunnel_wall()
		"tunnel_ceiling":
			return PsxTextures.tunnel_ceiling()
	push_warning("Unknown obstacle texture '%s'" % name)
	return PsxTextures.concrete()


func _spawn_chopper(parent: Node3D, xf: Transform3D) -> void:
	var chopper := Node3D.new()
	chopper.name = "Chopper"
	parent.add_child(chopper)
	chopper.transform = xf
	chopper.add_to_group("chopper")
	_audio.attach_loop(chopper, "rotor", 0.0, 90.0, 12.0)  # heard as you get near
	# Built late (with the helipad), so catch up if it's already lifting off.
	if _clock and _clock.stage == ExtractionClock.Stage.LIFTING_OFF:
		var t := (_clock.elapsed - _clock.lifts_at) / (_clock.gone_at - _clock.lifts_at)
		chopper.position.y += 2.5 * t
		chopper.create_tween().tween_property(chopper, "position:y", xf.origin.y + 2.5, _clock.gone_at - _clock.elapsed)
	_box(chopper, Vector3(2.2, 1.6, 4.5), Vector3(0, 1.2, 0), Color("2f3b2a"))
	_box(chopper, Vector3(0.5, 0.5, 4.0), Vector3(0, 1.6, 4.0), Color("2f3b2a"))
	# A blinking red light on the tail, and a white one under the nose lighting the pad.
	var tail := _box(chopper, Vector3(0.18, 0.18, 0.18), Vector3(0, 1.95, 5.9), Color.WHITE)
	tail.material_override = PsxMaterials.glow(Color("ff3020"))
	_ambience.add_lamp(tail, Color(1.0, 0.15, 0.1) * 1.5, 5.0, {"blink": 1.1, "alert": false, "fixture": tail,
			"on_mat": PsxMaterials.glow(Color("ff3020")), "off_mat": PsxMaterials.flat(Color("401010"))})
	var nose := Node3D.new()
	chopper.add_child(nose)
	nose.position = Vector3(0, 1.0, -3.0)
	_ambience.add_lamp(nose, Color(0.9, 0.95, 1.0) * 1.2, 7.0, {"alert": false})
	var rotor := _box(chopper, Vector3(9.0, 0.08, 0.35), Vector3(0, 2.2, 0), Color("111111"))
	var tween := rotor.create_tween().set_loops()
	tween.tween_property(rotor, "rotation:y", TAU, 0.35).from(0.0)


func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	m.mesh = mesh
	m.material_override = PsxMaterials.flat(color)
	m.position = pos
	parent.add_child(m)
	return m


## A flat, textured surface. It is subdivided about every 2 m, because affine (PS1) texturing
## warps badly across big triangles.
func _plane(parent: Node3D, size: Vector2, pos: Vector3, tex: Texture2D, uv_scale: Vector2,
		orientation: PlaneMesh.Orientation = PlaneMesh.FACE_Y) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.orientation = orientation
	mesh.size = size
	mesh.subdivide_width = maxi(0, ceili(size.x / 2.0) - 1)
	mesh.subdivide_depth = maxi(0, ceili(size.y / 2.0) - 1)
	m.mesh = mesh
	m.material_override = PsxMaterials.textured(tex, uv_scale)
	m.position = pos
	parent.add_child(m)
	return m


func _remap_lane(lane: int, authored: int) -> int:
	if tuning.lane_count == authored:
		return lane
	return clampi(roundi(lane * float(tuning.lane_count - 1) / (authored - 1)), 0, tuning.lane_count - 1)


func _despawn_behind() -> void:
	var d := _player.distance_run()
	# Kept a while behind you: the Alert 3 squad runs (and trips) on the road behind you.
	while _segments.size() > 1 and _segments[0]["end"] < d - BEHIND_KEEP:
		_segments.pop_front()["node"].queue_free()
	for r in _retired:
		if d > r["gone_at"] and is_instance_valid(r["node"]):
			r["node"].queue_free()
	_retired = _retired.filter(func(r: Dictionary) -> bool: return is_instance_valid(r["node"]) and d <= r["gone_at"])
	_obstacles = _obstacles.filter(func(o: Dictionary) -> bool: return o["at"] > d - BEHIND_KEEP)
	_combatants = _combatants.filter(func(c: Dictionary) -> bool:
		return is_instance_valid(c["node"]) and c["node"].at > d - 10.0)


# --- Rules ------------------------------------------------------------------------

func _check_obstacles() -> void:
	var d := _player.distance_run()
	var half_hit := tuning.lane_width * 0.5 + 0.15
	for o in _obstacles:
		if o["pass"] == "cover":
			# Reaching cover in its lane puts you in cover, just in front of it. It's the lane you're
			# heading for that counts, so once you swipe away you're out, even mid-slide.
			var stop_at: float = o["at"] - o["depth"] / 2.0 - tuning.cover_stop_gap
			if not _player.in_cover and d >= stop_at and d < o["at"] and absf(o["x"] - _player.lane_x(_player.lane)) < 0.1:
				_player.enter_cover(stop_at, o["crouch"])
				_audio.play("cover", -2.0, 0.05)  # MGS's wall press
				RunLog.record_event("cover", {"node": _runner.current})
			continue
		if o["done"] or absf(o["at"] - d) > o["depth"] / 2.0 + 0.2:
			continue
		if absf(o["x"] - _player.track_x) > half_hit:
			continue
		match o["pass"]:
			"jump":
				if _player.clears_low_obstacle():
					continue
			"slide":
				if _player.is_sliding():
					continue
			"jump_or_alert":
				if _player.clears_low_obstacle():
					continue
				for other in _obstacles:  # the whole wire trips (and vanishes) at once
					if other["group"] == o["group"]:
						other["done"] = true
				o["mesh"].visible = false
				_audio.play("zap", -4.0, 0.05)
				RunLog.record_event("tripwire", {"node": _runner.current})
				GameState.raise_alert()
				continue
		o["done"] = true
		_stumble(o)
		return


## Ran into a jump or slide obstacle: a stumble, not the end of the run. You're stunned and
## slowed (the chopper clock makes that cost something) and lose obstacle_damage HP. A short grace
## afterwards stops one fumble chaining into the next.
func _stumble(o: Dictionary) -> void:
	if _clock.elapsed < _stumble_grace_until:
		return
	_stumble_grace_until = _clock.elapsed + tuning.obstacle_grace
	RunLog.record_event("stumble", {"kind": o["kind"], "node": _runner.current})
	_player.stumble()
	var here := _player.global_position + Vector3(0, 1.2, 0)
	_audio.play("stumble", -2.0, 0.06)
	if o["pass"] == "slide" and _skin(_runner.current, "pipe", "pipe") == "wires":
		# Zapped by the live wires: a burst of sparks on the player.
		_audio.play("zap", -2.0, 0.05)
		var s := Sparks.new(6, Time.get_ticks_msec())
		_world.add_child(s)
		s.global_position = here
		get_tree().create_timer(0.6).timeout.connect(s.queue_free)
	elif o["pass"] == "jump" and o["mesh"] is Node3D:
		# Knocked it over as you went through.
		var m: Node3D = o["mesh"]
		m.create_tween().tween_property(m, "rotation:x", m.rotation.x - 1.2, 0.25).set_ease(Tween.EASE_OUT)
	for i in tuning.obstacle_damage:
		_damage_player(String(o["kind"]))


# --- Combat -----------------------------------------------------------------------

## Troopers aim and shoot, alarm boxes open and close their windows, and FIRE shoots.
func _update_combat(delta: float) -> void:
	var d := _player.distance_run()
	var alert := GameState.alert_level
	var half_hit := tuning.lane_width * 0.5 + 0.15
	for c in _combatants:
		var n = c["node"]  # RifleTrooper or AlarmBox
		if not is_instance_valid(n):
			continue
		if not c["seg"].get("promoted", false):
			# On a branch ahead: not acting yet, but shown (and committed once seen) by the same
			# alert rules, so you never see a trooper that isn't there, or lose one you've seen.
			if n is RifleTrooper or n is RusherDog or n is SecurityTrooper:
				n.note_seen(tuning, alert, d)
				n.visible = n.is_active(alert)
			continue
		if n is AlarmBox:
			n.update(delta, tuning, d)
			continue
		if n is SecurityTrooper:
			_update_security(delta, n, d, alert)
			continue
		if n is RusherDog:
			_update_dog(delta, n, d, alert)
			if not GameState.run_active:
				return
			continue
		var t: RifleTrooper = n
		# He only aims at you if he can see you (rays against the walls), and only bothers in range.
		var ahead: float = t.at - d
		if ahead > 0.5 and ahead <= tuning.trooper_aim_range + 1.0:
			t.sight_clear = _sees(t.global_position + Vector3.UP * 1.3, _player.global_position + Vector3.UP * 1.1)
		var shot := t.update(delta, tuning, alert, d, _player.track_x, _player.in_cover,
				_player.global_position, _route_point)
		if shot == RifleTrooper.Shot.MISSED:
			RunLog.record_event("trooper_missed", {"node": _runner.current, "in_cover": _player.in_cover})
		if shot == RifleTrooper.Shot.HIT:
			_damage_player("shot")
		# Running into a live trooper knocks him down, and it costs you a hit.
		if t.is_targetable(alert) and absf(t.at - d) < 0.5 and absf(t.x - _player.track_x) <= half_hit:
			t.knock_down()
			_damage_player("ran_into_trooper")
		if not GameState.run_active:
			return
	_hud.show_cover_hint(_player.in_cover)

	_fire_cooldown -= delta
	_hud.set_firing(_fire_held)
	if _fire_held and _fire_cooldown <= 0.0 and not _player.halted:
		_fire_cooldown = tuning.fire_interval
		_shoot()


## The Rusher: it charges down the route at you, round walls and over low obstacles. If it gets
## you, it's a hit and a stumble (cover doesn't help); dodge out of its lane and it runs past.
func _update_dog(delta: float, dog: RusherDog, d: float, alert: int) -> void:
	var lows: Array = []
	if dog.state in [RusherDog.State.CHARGE, RusherDog.State.PASSED]:
		for o in _obstacles:
			if o["kind"] in ["barrier", "box"] and absf(o["at"] - dog.at) < 2.0:
				lows.append({"at": o["at"], "x": o["x"]})
	var contact := dog.update(delta, tuning, alert, d, _player.track_x, _player.in_cover, _live_blockers(), lows, _route_point)
	if contact == RusherDog.Contact.BIT:
		RunLog.record_event("dog_bite", {"node": _runner.current})
		_player.in_cover = false  # it drags you out of cover
		_damage_player("dog")
		if GameState.run_active:
			RunLog.record_event("stumble", {"kind": "dog", "node": _runner.current})
			_player.stumble()
	elif contact == RusherDog.Contact.MISSED:
		RunLog.record_event("dog_dodged", {"node": _runner.current})


## The alarm runner: he runs on ahead of you, round walls, over low obstacles and under pipes,
## to his alarm. Running into him knocks him down (he's unarmed, so it doesn't cost you a hit).
func _update_security(delta: float, sec: SecurityTrooper, d: float, alert: int) -> void:
	var walls: Array = []
	var lows: Array = []
	var highs: Array = []
	var seg := _runner_segment(sec.at)
	if sec.is_running() and not seg.is_empty():
		var owner: Node3D = seg["node"]
		for b in _blockers:
			if b["owner"] == owner and absf(b["at"] - sec.at) < 8.0:
				walls.append(b)
		for o in _obstacles:
			if o["owner"] == owner and absf(o["at"] - sec.at) < 2.0:
				if o["pass"] == "slide":
					highs.append({"at": o["at"], "x": o["x"]})
				elif o["kind"] in ["barrier", "box"]:
					lows.append({"at": o["at"], "x": o["x"]})
	sec.update(delta, tuning, alert, d, walls, lows, highs, _runner_point)
	if sec.is_running():
		sec.x = move_toward(sec.x, _through_doors(sec.at, sec.x), 7.0 * delta)  # through the zone doors
	if sec.is_running() and sec.state == SecurityTrooper.State.RUN:
		_hud.show_runner(sec.progress())
	if sec.is_alive() and sec.visible and absf(sec.at - d) < 0.6 \
			and absf(sec.x - _player.track_x) <= tuning.lane_width * 0.5 + 0.15:
		sec.knock_down()


## Where the alarm runner is in the world: on the road you're on, or on the straight-on branch
## just ahead of it (he keeps straight on). null where that stretch isn't built.
func _runner_point(at: float, x: float, y: float) -> Variant:
	var seg := _runner_segment(at)
	if seg.is_empty():
		return null
	return seg["node"].global_transform * _frame_at(seg, at - seg["start"]) * Vector3(x, y, 0)


func _runner_segment(at: float) -> Dictionary:
	if _segments.is_empty() or at < _segments[0]["start"]:
		return {}
	if at <= _current["end"]:
		return _segment_at(at)
	var branches: Dictionary = _current["branches"]
	for k in branches:
		var b: Dictionary = branches[k]
		if String(k).begins_with("straight:") and at <= b["end"]:
			return b
	return {}


## The roof searchlights sweep; one only catches you on the road you're actually on (those on a
## branch ahead sweep, but can't see you yet).
func _update_searchlights(delta: float) -> void:
	var d := _player.distance_run()
	for l in _lights:
		var light: Searchlight = l["node"]
		if not is_instance_valid(light):
			continue
		var here: bool = l["seg"].get("promoted", false)
		light.update(delta, d if here else -INF, _player.track_x)
	_lights = _lights.filter(func(l: Dictionary) -> bool: return is_instance_valid(l["node"]) and l["node"].at > d - 20.0)


## A searchlight's caught you: the "!" sting, and the alert goes up one level.
func _on_searchlight_spotted(light: Searchlight) -> void:
	RunLog.record_event("searchlight", {"node": _runner.current})
	_audio.play_at("spotted", light.global_position + Vector3.UP * 1.5, -2.0)
	_hud.show_chopper_message("SPOTTED", Color("ff4b3a"), 2.0, false)
	GameState.raise_alert()


## Alert 3: a squad comes after you from behind, one guard in each lane.
func _spawn_squad() -> void:
	_squad_on = true
	_squad_shaken = false
	var d := _player.distance_run()
	for i in tuning.lane_count:
		var g := PursuitGuard.new(tuning)
		g.at = d - tuning.squad_start_gap - (i % 2) * 1.5  # a ragged line, not a wall of men
		g.x = _player.lane_x(i)
		g.home_x = g.x
		g.set_seed(i * 7919 + int(d))  # repeatable: the same run, the same squad
		_world.add_child(g)
		g.update(0.0, tuning.run_speed, [], [], _route_point)  # placed before it's drawn
		_squad.append(g)
	RunLog.record_event("squad", {"node": _runner.current, "size": tuning.lane_count})
	_audio.play("squelch", -4.0, 0.0, "UI")
	_hud.show_chopper_message("SQUAD ON YOUR TAIL", Color("ff4b3a"), 3.0, false)
	_set_rear_cctv(true)


## Alert's dropped below 3: they pull up and give up the chase.
func _squad_fall_back() -> void:
	_squad_on = false
	var any := false
	for g in _squad:
		if is_instance_valid(g) and g.is_chasing():
			g.give_up()
			any = true
	if any and GameState.run_active:
		_hud.show_chopper_message("SQUAD FALLING BACK", Color("9fd36b"), 2.5, false)
	get_tree().create_timer(2.5).timeout.connect(func() -> void:
		if not _squad_on:
			_set_rear_cctv(false))


## The squad runs on after you at your run speed (so it only gains while you're slowed). Each
## guard jumps barriers and slides under pipes in his lane, but runs into any cover in it and
## is out. If one reaches you, you're caught.
func _update_squad(delta: float) -> void:
	if _squad.is_empty() or _squad_caught:
		return
	var d := _player.distance_run()
	var chasing := 0
	for g in _squad:
		if not is_instance_valid(g):
			continue
		if g.is_chasing():
			g.x = move_toward(g.x, _squad_lane_target(g), 7.0 * delta)
		var lows: Array = []
		var highs: Array = []
		var covers: Array = []
		for o in _obstacles:
			if absf(o["at"] - g.at) < 2.0 and absf(o["x"] - g.x) < 0.9:
				var pass_kind := String(o["pass"])
				if pass_kind in ["jump", "slide"]:
					# He jumps it or slides under it if he gets the timing right; if not, it's
					# as good as a wall: he trips over it or runs into it.
					if not g.spots("t%.1f:%.1f" % [o["at"], o["x"]], tuning.squad_timing_chance):
						covers.append(o)
					elif pass_kind == "jump":
						lows.append(o)
					else:
						highs.append(o)
				elif pass_kind == "cover":
					covers.append(o)
		var before := g.at
		g.update(delta, tuning.run_speed, lows, highs, _route_point)
		if not g.is_chasing():
			continue
		for o in covers:
			if PursuitGuard.runs_into(before, g.at, g.x, o["at"], o["x"], tuning.lane_width):
				g.fall()
				RunLog.record_event("squad_out", {"node": _runner.current})
				_audio.play("fall", -9.0, 0.08)
				_audio.play("grunt_%d" % (randi() % 3), -10.0, 0.05)
				break
		if not g.is_chasing():
			continue
		chasing += 1
		if PursuitGuard.catches(g.at, d, tuning.squad_catch_distance):
			_caught_by_squad()
			return
	_hud.set_rear_count(chasing)
	if chasing == 0 and _squad_on and not _squad_shaken:
		# Every one of them ran into cover. (No new squad until alert drops and comes back to 3.)
		_squad_shaken = true
		_hud.show_chopper_message("SQUAD SHAKEN OFF", Color("9fd36b"), 2.5, false)
		get_tree().create_timer(2.5).timeout.connect(func() -> void:
			if _squad_shaken:
				_set_rear_cctv(false))
	# Those left far behind are gone.
	for g in _squad:
		if is_instance_valid(g) and g.at < d - 60.0:
			g.queue_free()
	_squad = _squad.filter(func(g: PursuitGuard) -> bool: return is_instance_valid(g) and not g.is_queued_for_deletion())


## Where a squad guard heads across the road: his own lane, unless cover is coming up in it and
## he's spotted it (squad_dodge_chance), when he swerves into a clear neighbouring lane round it.
## If he hasn't spotted it, or both sides are blocked too, he keeps going: into it.
func _squad_lane_target(g: PursuitGuard) -> float:
	return _through_doors(g.at, _squad_cover_target(g))


## Zone doors only open across the middle lanes: anyone (the squad, the alarm runner) coming up to
## one squeezes in toward the middle.
func _through_doors(at: float, x: float) -> float:
	var reach := (MARKER_LANES - 1) / 2 * tuning.lane_width
	for m in _markers:
		if at >= m["at"] - MARKER_FUNNEL and at <= m["at"] + 0.5:
			return clampf(x, -reach, reach)
	return x


func _squad_cover_target(g: PursuitGuard) -> float:
	for o in _obstacles:
		if o["pass"] != "cover" or absf(o["x"] - g.home_x) > 0.9:
			continue
		var ahead: float = o["at"] - g.at
		if ahead < -0.8 or ahead > 6.0:
			continue
		if not g.spots("%.1f:%.1f" % [o["at"], o["x"]], tuning.squad_dodge_chance):
			return g.home_x
		# The nearest clear lane, up to two over (nearer first, then toward the middle).
		var edge := tuning.lane_count * tuning.lane_width / 2.0
		var sides: Array[float] = []
		for k in [1, -1, 2, -2]:
			sides.append(g.home_x + k * tuning.lane_width)
		sides.sort_custom(func(a: float, b: float) -> bool:
			var da := roundi(absf(a - g.home_x) / tuning.lane_width)
			var db := roundi(absf(b - g.home_x) / tuning.lane_width)
			return da < db or (da == db and absf(a) < absf(b)))
		for sx in sides:
			if absf(sx) < edge and not _cover_at(o["at"], sx):
				return sx
		return g.home_x
	return g.home_x


## Is there cover across the road at x, around `at`?
func _cover_at(at: float, x: float) -> bool:
	for o in _obstacles:
		if o["pass"] == "cover" and absf(o["at"] - at) < 1.5 and absf(o["x"] - x) < 0.5:
			return true
	return false


## Caught: they grab you, close round you, and it's CAPTURED.
func _caught_by_squad() -> void:
	_squad_caught = true
	RunLog.record_event("squad_caught", {"node": _runner.current})
	Engine.time_scale = 1.0
	_hud.clear_junction()
	_hud.show_chopper_message("CAUGHT", Color("ff4b3a"), 3.0, false)
	_player.in_cover = false
	_player.surrender()
	_place_player()
	var behind := _player.global_transform
	var i := 0
	for g in _squad:
		if not is_instance_valid(g) or not g.is_chasing():
			continue
		g.grab()
		var side := -1.0 if i % 2 == 0 else 1.0
		var spot := Vector3(side * (1.2 + (i / 2) * 0.9), 0, 1.3 + (i / 2) * 0.8)
		g.create_tween().tween_property(g, "global_transform", behind * Transform3D(Basis.IDENTITY, spot), 0.35).set_ease(Tween.EASE_OUT)
		i += 1
	_audio.play("squelch", -4.0, 0.0, "UI")
	get_tree().create_timer(tuning.capture_duration).timeout.connect(_end.bind(GameState.END_CAPTURED))


## The rear-view CCTV: a second, low-res camera above you looking back down the route, shown in
## the HUD's monitor under the clock. Only renders while it's on.
func _set_rear_cctv(on: bool) -> void:
	if on and _rear_vp == null:
		_rear_vp = SubViewport.new()
		_rear_vp.name = "RearCctv"
		_rear_vp.size = tuning.squad_cctv_size
		add_child(_rear_vp)
		_rear_cam = Camera3D.new()
		_rear_cam.fov = 30.0  # a long lens, like a zoomed security camera: the squad reads at 25 m
		_rear_cam.far = 70.0
		# Its own copy of the world's look, with thinner fog (kept in step below): the squad 30 m
		# back would vanish in the corridor fog otherwise.
		_rear_cam.environment = _env.duplicate()
		_rear_vp.add_child(_rear_cam)
		_rear_cam.current = true
	if _rear_vp == null:
		return
	_rear_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	_hud.show_rear(_rear_vp.get_texture() if on else null)
	_update_rear_camera()


func _update_rear_camera() -> void:
	if _rear_cam == null or _rear_vp.render_target_update_mode == SubViewport.UPDATE_DISABLED or _segments.is_empty():
		return
	var d := _player.distance_run()
	var eye := _route_point(d + 0.8, 0.0, 2.4)
	var look := _route_point(d - tuning.squad_start_gap, 0.0, 0.9)
	_rear_cam.global_transform = Transform3D(Basis.IDENTITY, eye).looking_at(look, Vector3.UP)
	# A tracking box over each guard still chasing (mirrored, like the picture).
	var marks: Array = []
	for g in _squad:
		if is_instance_valid(g) and g.is_chasing():
			var p := g.global_position + Vector3.UP * 1.0
			if not _rear_cam.is_position_behind(p):
				var uv := _rear_cam.unproject_position(p) / Vector2(_rear_vp.size)
				var dist := _rear_cam.global_position.distance_to(p)
				marks.append([1.0 - uv.x, uv.y, clampf(260.0 / maxf(dist, 1.0), 6.0, 30.0)])
	_hud.set_rear_marks(marks)
	var env := _rear_cam.environment
	env.fog_density = _env.fog_density * 0.35
	env.fog_light_color = _env.fog_light_color
	env.ambient_light_color = _env.ambient_light_color


## An alarm box hit lowers alert by one level; that can lift a lockdown door.
func _on_alarm_destroyed(node_id: StringName) -> void:
	RunLog.record_event("alarm_hit", {"node": node_id})
	GameState.lower_alert()


func _damage_player(why: String) -> void:
	if not _player.take_hit():
		return
	RunLog.record_event("player_hit", {"by": why, "node": _runner.current, "left": _player.hits_left})
	_audio.play("player_hit", 0.0, 0.05)
	_hud.show_hit()
	_hud.show_hp(_player.hits_left, tuning.player_hits)
	if _player.hits_left <= 0:
		_end(&"killed")


## World position of a point on the route: `d` metres along, `x` across, `y` up.
func _route_point(d: float, x: float, y: float) -> Vector3:
	var seg := _segment_at(d)
	return seg["node"].global_transform * _frame_at(seg, d - seg["start"]) * Vector3(x, y, 0)


## What FIRE would hit right now (used by the bots, too).
func fire_target() -> Node3D:
	var alert := GameState.alert_level
	var candidates: Array[Node3D] = []
	if _behind_wall():
		return null  # no shooting from behind a wall
	# Only what you can see: a ray from your gun to him, against the walls (low cover has no
	# collision, so you shoot over it).
	var gun := _gun_origin()
	for c in _combatants:
		var n = c["node"]  # RifleTrooper or AlarmBox
		if is_instance_valid(n) and c["seg"].get("promoted", false) and n.is_targetable(alert) \
				and n.is_visible_in_tree() and _sees(gun, n.global_position + Vector3.UP * _aim_height(n)):
			candidates.append(n)
	var origin := _player.global_position + Vector3(0, 1.2, 0)
	var forward := -_player.global_transform.basis.z
	if _tapped != null and (not is_instance_valid(_tapped) or not _tapped.call("is_targetable", alert)):
		_tapped = null
	return Targeting.pick(candidates, origin, forward, tuning, _tapped)


## Where on a target you aim: a trooper's chest, a dog's body, an alarm box's face.
func _aim_height(n: Node3D) -> float:
	if n is SecurityTrooper:
		return 1.2
	if n is RifleTrooper:
		return 1.15
	if n is RusherDog:
		return 0.55
	return 0.0


## The blockers on the path you're on (a branch ahead isn't in play until you're on it).
func _live_blockers() -> Array:
	return _blockers.filter(func(b: Dictionary) -> bool: return b["seg"].get("promoted", false))


func set_fire_held(held: bool) -> void:
	_fire_held = held and GameState.run_active


func _shoot() -> void:
	if _behind_wall():
		return  # no shooting from behind a wall: not even into it
	_audio.play("gun", -3.0, 0.05)
	_hud.fire_kick()
	var from := _player.global_transform * Vector3(0.25, 1.2, -0.4)
	var target := fire_target()
	var to := from + (-_player.global_transform.basis.z) * 20.0
	if target != null:
		to = target.global_position + Vector3.UP * _aim_height(target)
		target.call("hit")
	else:
		# Nothing to hit: the shot stops at the first wall in the way, not through it.
		var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, SIGHT_LAYER))
		if not hit.is_empty():
			to = hit["position"]
	_shot_tracer.global_transform = Transform3D(Basis.looking_at(to - from) * Basis.from_scale(Vector3(1, 1, from.distance_to(to))), (from + to) / 2.0)
	_shot_tracer.visible = true
	get_tree().create_timer(0.05).timeout.connect(func() -> void: _shot_tracer.visible = false)


func _end(reason: StringName) -> void:
	GameState.end_run(reason, _runner.current)


func _on_mission_end(end_type: String) -> void:
	_end(GameState.END_EXTRACTED if end_type == "extract" else StringName(end_type))


## Missed the way out: stop, hands up, guards close in from behind, then CAPTURED.
func _on_capture_reached() -> void:
	Engine.time_scale = 1.0
	_hud.clear_junction()
	_player.surrender()
	_place_player()
	var behind := _player.global_transform
	for i in tuning.capture_guards:
		# Alternate sides, working outward, and keep clear of the middle so the camera can see.
		var side := -1.0 if i % 2 == 0 else 1.0
		var spot := Vector3(side * (1.3 + (i / 2) * 1.0), 0, 1.4 + (i / 2) * 0.9)
		var guard := _make_guard()
		_world.add_child(guard)
		# Face the player, and run in from further back.
		guard.global_transform = behind * Transform3D(Basis.IDENTITY, spot + Vector3(0, 0, 7.0))
		var tween := guard.create_tween()
		tween.tween_interval(0.12 * i)
		tween.tween_property(guard, "global_position", behind * spot, 0.5).set_ease(Tween.EASE_OUT)
	get_tree().create_timer(tuning.capture_duration).timeout.connect(_end.bind(GameState.END_CAPTURED))


func _make_guard() -> Node3D:
	var guard := Node3D.new()
	guard.name = "Guard"
	_box(guard, Vector3(0.55, 1.6, 0.35), Vector3(0, 0.8, 0), GUARD_COLOR)
	_box(guard, Vector3(0.4, 0.3, 0.4), Vector3(0, 1.75, 0), GUARD_COLOR.darkened(0.4))
	_box(guard, Vector3(0.1, 0.1, 0.8), Vector3(0.2, 1.1, -0.4), Color("1c1c1a"))  # rifle, aimed at the player
	var s := MeshInstance3D.new()
	s.mesh = PsxMaterials.shadow_mesh(Vector2(0.8, 0.6))
	s.material_override = PsxMaterials.shadow(false, tuning)
	s.position.y = 0.03
	guard.add_child(s)
	return guard


func _on_junction_approaching(options: Array[Dictionary]) -> void:
	Engine.time_scale = tuning.junction_time_scale
	_hud.show_junction(options)


func _on_junction_cleared() -> void:
	Engine.time_scale = 1.0
	_hud.clear_junction()


func _on_run_ended(reason: StringName) -> void:
	_set_rear_cctv(false)
	Engine.time_scale = 1.0
	_clock.stop()
	_fire_held = false
	_hud.set_firing(false)
	_hud.show_cover_hint(false)
	_hud.show_end(reason, RunLog.route_summary())
	# The end screen, a moment later (so you see what happened): the result, the debrief and the
	# route taken (the LOCKED post-run route record).
	var count := func(kind: String) -> int: return RunLog.events.filter(func(e: Dictionary) -> bool: return e["kind"] == kind).size()
	var stats := {"time": _clock.elapsed, "hits": count.call("player_hit"), "downed": count.call("trooper_down") + count.call("dog_down") + count.call("runner_down"),
			"alert": GameState.alert_level, "route": RunLog.route_summary().split(" > ")}
	get_tree().create_timer(1.1).timeout.connect(func() -> void: _frontend.show_end(reason, stats))
	_audio.fade_loops(2.5)
	_audio.stop_music()
	_audio.play("jingle" if reason == GameState.END_EXTRACTED else "gameover", -2.0, 0.0, "UI")


func _on_swipe(dir: Vector2i) -> void:
	if _menu_open or _frontend.is_open():
		return  # the menus have their own buttons
	if not _started:
		start_run()
	elif GameState.run_active and _player.distance_run() > 0.3 and not in_stairwell():
		var was_airborne := _player.is_airborne()
		var was_sliding := _player.is_sliding()
		_player.handle_swipe(dir)  # (no swipes until through the start door, or in a stairwell)
		if dir == Vector2i.UP and not was_airborne and _player.is_airborne():
			_audio.play("jump", -4.0, 0.08)
		elif dir == Vector2i.DOWN and not was_sliding and _player.is_sliding():
			_audio.play("slide", -4.0, 0.08)


func _on_tap(pos: Vector2) -> void:
	if _menu_open or _frontend.is_open():
		return
	if not _started:
		start_run()  # a tap during the opening pan skips it
	elif not GameState.run_active:
		return  # the end screen has its own buttons
	elif tuning.targeting_mode != Tuning.TargetingMode.AUTO_PRIORITY:
		_tapped = _enemy_near_screen(pos)


## Tap-to-target (proposal under test): the live trooper drawn nearest the tap, if close enough.
func _enemy_near_screen(pos: Vector2) -> Node3D:
	var best: Node3D = null
	var best_d := tuning.tap_target_radius_px
	for c in _combatants:
		var n = c["node"]
		if not (n is RifleTrooper or n is RusherDog or n is SecurityTrooper) or not n.is_targetable(GameState.alert_level):
			continue
		var p: Vector3 = n.global_position + Vector3(0, 1.0, 0)
		if _camera.is_position_behind(p):
			continue
		var d := _camera.unproject_position(p).distance_to(pos)
		if d < best_d:
			best_d = d
			best = n
	return best


func _on_fire() -> void:
	if _menu_open or _frontend.is_open():
		return
	if not _started:
		start_run()
	elif not GameState.run_active:
		return
	else:
		set_fire_held(true)


func _retry() -> void:
	_skip_title = true
	get_tree().reload_current_scene()


# --- Camera -----------------------------------------------------------------------

## Behind and above the player, in the frame of the leg they're on, eased so turns and
## climbs swing smoothly rather than snapping. Normally it sits a little toward the middle of the
## road; near a wall (walls are solid and lane-aligned) it moves right behind the player, so it
## never ends up inside one.
func _update_camera(delta: float) -> void:
	var d := _player.distance_run()
	var seg := _segment_at(d)
	var into: float = d - seg["start"]
	var f: Transform3D = seg["node"].global_transform * _frame_at(seg, into)
	var x := _player.track_x
	var near_wall := in_stairwell()  # a narrow stairwell: the camera goes right behind you
	for o in _obstacles:
		if o["kind"] == "wall" and o["at"] > d - 7.0 and o["at"] < d + 1.5:
			near_wall = true
			break
	_camera_follow = move_toward(_camera_follow, 1.0 if near_wall else 0.6, delta * 3.0)
	var eye_local := Vector3(x * _camera_follow, 3.4, 5.5)
	var look_local := Vector3(x * 0.8, 1.0, -10.0)
	# In a stairwell: hard cut to its security camera, high in the far corner, looking back down
	# the flight at the player. Hard cut back to the normal camera when you're out.
	if in_stairwell():
		var ramp: float = seg["ramp_len"]
		# Up in the corner just inside the exit door, under the ceiling, looking back down the stairs.
		var cam_at := ramp - 0.4
		var lane_x := _player.lane_x(_stair_lane(seg))
		var cf: Transform3D = seg["node"].global_transform * _frame_at(seg, cam_at)
		var cam_pos := cf * Vector3(lane_x + 0.5, STAIR_HEADROOM - 0.3, 0)
		# As you pass under it, it stops tilting down (it never looks straight down): it keeps
		# looking at least a couple of metres back down the stairs.
		var target := _player.global_position + Vector3(0, 1.0, 0)
		var back := cf * Vector3(lane_x, 0, 2.2)
		var flat := Vector2(target.x - cam_pos.x, target.z - cam_pos.z)
		if flat.length() < 2.2:
			target = Vector3(back.x, target.y, back.z)
		_camera.global_transform = Transform3D(Basis.IDENTITY, cam_pos).looking_at(target, Vector3.UP)
		_cam_base = _camera.global_transform
		_was_cctv = true
		return
	var snap := _was_cctv
	_was_cctv = false
	# Just out of a stairwell, the play camera behind you is still inside it: leave it out for now.
	var just_out: bool = _is_stairs(seg) and into > seg["ramp_len"] - 0.4 and into < seg["ramp_len"] + 6.5
	_camera.cull_mask = 0xFFFFF & ~STAIRWELL_LAYER if just_out else 0xFFFFF
	if _menu_open:
		# Behind the main menu: in front of you, swaying slowly from side to side.
		_menu_t += delta
		var sway := 0.7 * sin(_menu_t * 0.22)
		eye_local = Vector3(x + sin(sway) * 3.3, 1.55, -cos(sway) * 3.3)
		look_local = Vector3(x, 1.25, 0.0)
		_camera.global_transform = Transform3D(Basis.IDENTITY, f * eye_local).looking_at(f * look_local, Vector3.UP)
		_cam_base = _camera.global_transform
		return
	if _intro_left > 0.0 and not _started:
		# Opening pan: from in front of the player (looking back at them) round the side to the
		# play camera behind them, where it ends exactly.
		var e := smoothstep(0.0, 1.0, 1.0 - _intro_left / tuning.intro_pan_time)
		var angle := PI * e
		var r := lerpf(3.0, 5.5, e * e)
		eye_local = Vector3(x + sin(angle) * r * 0.75, lerpf(1.5, 3.4, e), -cos(angle) * r)
		# Keep the player framed for most of the pan; only turn to look ahead at the very end.
		look_local = Vector3(x, 1.3, 0.0).lerp(look_local, smoothstep(0.75, 1.0, e))
		_camera.global_transform = Transform3D(Basis.IDENTITY, f * eye_local).looking_at(f * look_local, Vector3.UP)
		_cam_base = _camera.global_transform
		return
	var eye := f * eye_local
	var look := f * look_local
	var target := Transform3D(Basis.IDENTITY, eye).looking_at(look, Vector3.UP)
	# The smoothed camera, kept apart from the shake so the smoothing can't swallow it.
	_cam_base = target if snap else _cam_base.interpolate_with(target, clampf(delta * 8.0, 0.0, 1.0))
	_camera.global_transform = _cam_base
	if _shake > 0.0:
		# Impact: a punch forward, then a hard shake with a little roll, settling over ~0.45 s.
		_shake = maxf(0.0, _shake - delta / 0.45)
		var s := _shake * _shake
		var b := _cam_base.basis
		var punch := -b.z * 0.35 * s
		var jitter := (b.x * randf_range(-1, 1) + b.y * randf_range(-1, 1)) * 0.22 * s
		_camera.global_transform = Transform3D(
				b.rotated(b.z, randf_range(-0.06, 0.06) * s).rotated(b.x, randf_range(-0.04, 0.04) * s),
				_cam_base.origin + punch + jitter)
