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

## Mission 1, COLD CALL: the level the game plays. The bots can play another route file in its place
## (route_path: the TEST RANGE, tests/fixtures/test_range.json, today's full 19-area level, kept so
## they keep testing what mission 1 leaves out: the dogs, the alarm runner, the snipers...).
const ROUTE_PATH := "res://game/levels/prototype_slice/route.json"
## The mission briefing after START (Briefing): the conversation's script, and the end-of-mission
## conversations (one for each ending, played after the run and before the debrief).
const BRIEFING_PATH := "res://game/levels/prototype_slice/briefing.json"
const START_ALERT := 1
const CEILING_Y := 4.6
## Scale (user: "doors should not be smaller than the player"). People here, the player and the
## guards, are about 1.95 m tall, and the world is built round them: a door is half a metre taller
## than a person, a zone door taller still. Every door uses these.
const DOOR_H := 2.5
const DOOR_W := 1.15
## The zone doors (double doors, the barred checkpoint gates, the warehouse shutter): tall enough
## that the camera (3.4 m up behind you) passes under the lintel instead of through it.
const GATE_H := 3.5
## How far under the ceiling a WAREHOUSE dome lamp's shade hangs (its middle), and a SEWER tube
## lamp (m): high enough that the camera passes half a metre under them (_pendant_lamp, _sewer_tubes).
const PENDANT_DROP := 0.5
const TUBE_DROP := 0.45
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
## You burst through a door when you're this far (m) short of it (but see SHUTTER_OPEN_AHEAD).
const BASH_AHEAD := 0.9
## The alarm runner's zone doors (user: "when the alert guard is running, the big doors should open
## and close for him, so he doesn't just faze through them"): he shoves the leaves open (radians,
## about square to the wall: your bash flings them on to 1.9) and they swing shut behind him; a
## roller shutter rolls up for him and drops behind him. Timings: SecurityTrooper's DOOR_ constants.
const GATE_PUSH := 1.55
## Zone doors further ahead of you than this (m), deep in the fog, are left shut as he goes through:
## nobody can see them, so nothing's spent on them.
const GATE_VIEW := 70.0
## A zone door, for the alarm runner: shut; open (he's shoved it, or is shoving it); swinging shut
## behind him; or yours (you've burst through it: he's done with it).
enum Gate { SHUT, OPEN, CLOSING, BURST }
## Where the alarm runner isn't on anything built in front of you (_runner_segment): one empty
## dictionary for every such answer, not a new one each frame.
const NOWHERE := {}
## Over the last this-many metres of the extraction area you're steered toward the chopper: into the
## centre lane, except past the downed boss's body (the lane beside it) till you're by him.
const CHOPPER_FUNNEL := 15.0
## The boss (user design) waits this far before the end of the extraction area (in front of the
## chopper, between you and its door).
const BOSS_FROM_END := 2.0
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
	# ROOFTOPS (user reference): the office building's roof: cracked paving out to a low parapet,
	# short lamp posts lighting the walkway, air-con units and ducts, a green electrical cabinet,
	# raised roof blocks with ladders, a hazard band, a roof hut.
	"rooftops": {"wall": "brick", "ambient": Color(0.19, 0.21, 0.32), "moon": Color(0.21, 0.24, 0.4), "lamps": "roof_posts", "snow": true,
			"stair_wall": "roof_hut", "stair_door": "steel_door", "color": Color("6a4436"), "height": 1.2, "ground": "roof_paving", "no_walls": true,
			"lip": 0.8, "sky": true, "fog": 0.012, "fog_color": Color("121828"), "low_wall": true, "wide_roof": 5.0, "office_roof": true,
			"skins": {"barrier_looks": ["vent"], "pipe": "double_pipe", "box_look": "condenser",
					"wall_looks": ["hvac"]}},
	# WATER TOWERS (user reference): the rooftops, with big rusty water tanks on steel stands either
	# side, one pair joined by a pipe arching over the road; paving slabs, a chain-link railing along
	# the edges, low lamp boxes; condensers for box cover, low pipe runs to jump.
	"towers": {"wall": "brick", "ambient": Color(0.19, 0.21, 0.32), "moon": Color(0.21, 0.24, 0.4), "lamps": "bollards", "snow": true,
			"stair_wall": "roof_hut", "stair_door": "steel_door", "color": Color("6a4436"), "height": 1.2, "ground": "roof_paving", "no_walls": true,
			"lip": 0.35, "sky": true, "fog": 0.012, "fog_color": Color("121828"), "railing": true, "city_near": false, "towers": true,
			"skins": {"barrier_looks": ["floor_pipe"], "pipe": "double_pipe", "box_look": "condenser",
					"wall_looks": ["hvac"]}},
	# GANTRY (user reference): a steel catwalk bridge high over the city: grating, hazard-striped
	# railings, portal frames overhead with floodlights, lit windows far below; a hazard-painted
	# I-beam to jump, steel equipment cases for box cover.
	"gantry": {"wall": "brick", "ambient": Color(0.17, 0.19, 0.285), "moon": Color(0.16, 0.19, 0.32), "lamps": "none", "snow": true,
			"stair_wall": "roof_hut", "stair_door": "steel_door", "color": Color("3a3e40"), "height": 1.2, "ground": "grating", "no_walls": true,
			"lip": 0.35, "sky": true, "fog": 0.012, "fog_color": Color("121828"), "bridge": true, "city_near": false,
			"skins": {"barrier_looks": ["ibeam"], "pipe": "double_pipe", "box_look": "gantry_case",
					"wall_looks": ["hvac"]}},
	# SKYLIGHTS (user reference): a wider gravel roof lined with big pitched glass skylights, the
	# warm-lit rooms below showing through; air-con boxes and vent stacks; condensers for box cover.
	"skylights": {"wall": "brick", "ambient": Color(0.19, 0.21, 0.32), "moon": Color(0.21, 0.24, 0.4), "lamps": "none", "snow": true,
			"stair_wall": "roof_hut", "stair_door": "steel_door", "color": Color("6a4436"), "height": 1.2, "ground": "gravel", "no_walls": true,
			"lip": 0.35, "sky": true, "fog": 0.012, "fog_color": Color("121828"), "wide_roof": 7.0, "skylights": true,
			"skins": {"barrier_looks": ["vent"], "pipe": "double_pipe", "box_look": "condenser",
					"wall_looks": ["hvac"]}},
	# ANTENNA FARM (user reference): the wider roof crowded with lattice antenna towers, satellite
	# dishes and equipment cabinets, cable trays along the walkway, a chain-link fence at the edge.
	"antennas": {"wall": "brick", "ambient": Color(0.19, 0.21, 0.32), "moon": Color(0.21, 0.24, 0.4), "lamps": "none", "snow": true,
			"stair_wall": "roof_hut", "stair_door": "steel_door", "color": Color("6a4436"), "height": 1.2, "ground": "roof_paving", "no_walls": true,
			"lip": 0.35, "sky": true, "fog": 0.012, "fog_color": Color("121828"), "wide_roof": 7.0, "railing": true, "antennas": true,
			"skins": {"barrier_looks": ["cable_tray"], "pipe": "double_pipe", "box_look": "equip",
					"wall_looks": ["hvac"]}},
	# ROOF EDGE (user reference): a gravel roof along the building's very edge: a tall parapet with
	# red warning lights on the city side, big air-con units and a roof hut on the wider other side.
	"edge": {"wall": "brick", "ambient": Color(0.19, 0.21, 0.32), "moon": Color(0.21, 0.24, 0.4), "lamps": "none", "snow": true,
			"stair_wall": "roof_hut", "stair_door": "steel_door", "color": Color("6a4436"), "height": 1.2, "ground": "gravel", "no_walls": true,
			"lip": 0.85, "sky": true, "fog": 0.012, "fog_color": Color("121828"), "parapet": true, "wide_roof": 6.0, "wide_side": 1,
			"skins": {"barrier_looks": ["vent"], "pipe": "double_pipe", "box_look": "equip",
					"wall_looks": ["hvac"]}},
	# SERVICE TUNNEL (user reference): pale concrete panels and pillars, caged warm bulkhead lamps,
	# a rusty pipe and cable trays along the walls, an air duct down the ceiling, drainage grates,
	# lockers, crates and tool carts; crates on pallets, low pipe runs, rusty pipes to duck.
	"service": {"wall": "tile", "wall_tex": "service_wall", "ceiling_tex": "concrete", "ambient": Color(0.13, 0.126, 0.11), "lamps": "none",
			"fog_color": Color("0d0c0a"), "stair_wall": "service_wall", "stair_door": "steel_door", "marker_door": "bars",
			"color": Color("5a5850"), "height": CEILING_Y, "ground": "service_floor", "ceiling": true, "wall_decor": "service",
			"pillar_every": 6, "pillar_tex": "service_wall", "overhead": "service", "floor_stripes": true,
			"skins": {"barrier_looks": ["floor_pipe"], "box_look": "warehouse"}},
	# BOILER ROOM (user reference): a high plant hall with boiler bays off both sides (glowing
	# fireboxes, gauges, valve wheels, pipes and steam, catwalks), steel plate floor, hall lamps;
	# crates, cases and drums for box cover, safety rails to jump, rusty pipes to duck.
	"boiler": {"wall": "tile", "wall_tex": "boiler_wall", "ceiling_tex": "boiler_wall", "ceiling_y": 7.5, "ambient": Color(0.31, 0.29, 0.26),
			"lamps": "hall", "fog_color": Color("0e0b09"), "stair_wall": "boiler_wall", "stair_door": "steel_door", "marker_door": "steel",
			"color": Color("3e3c3a"), "height": 7.5, "ground": "steel_plate", "ceiling": true, "pillar_every": 10, "pillar_tex": "boiler_wall",
			"floor_stripes": true,
			"skins": {"barrier_looks": ["safety_rail"], "box_look": "warehouse"}},
	# SEWER (user reference): a walkway along an open sewage channel under greenish light: mossy brick,
	# stone pillars, yellow wall lamps, rusty pipes, water pouring into the channel, hanging tubes;
	# crates, cases and drums for box cover, low pipe runs to jump, rusty pipes to duck.
	"sewer": {"wall": "tile", "wall_tex": "sewer_wall", "ceiling_tex": "concrete", "ambient": Color(0.2, 0.24, 0.18), "lamps": "tubes",
			"fog_color": Color("0b0f09"), "stair_wall": "sewer_wall", "stair_door": "steel_door", "marker_door": "bars",
			"color": Color("4a4e44"), "height": CEILING_Y, "ground": "sewer_floor", "ceiling": true, "wall_decor": "sewer",
			"pillar_every": 8, "pillar_tex": "sewer_wall",
			"skins": {"barrier_looks": ["floor_pipe"], "box_look": "warehouse"}},
	# PUMP STATION (user reference): like the BOILER ROOM and SEWER (user: keep the lower zones
	# consistent): a high hall with pump bays on the left (blue pumps on plinths, big blue pipes to the
	# ceiling, red valve wheels, panels, a catwalk) and a teal water basin on the right (sluice gates,
	# yellow railings), blue pipes across overhead, cool hanging lamps.
	"pump": {"wall": "tile", "wall_tex": "service_wall", "ceiling_tex": "boiler_wall", "ceiling_y": 7.5, "ambient": Color(0.12, 0.135, 0.145),
			"lamps": "hall", "lamp_color": Color(0.85, 0.95, 1.0), "fog_color": Color("0a0d0f"), "stair_wall": "service_wall", "stair_door": "steel_door",
			"marker_door": "steel", "color": Color("4a4e52"), "height": 7.5, "ground": "service_floor", "ceiling": true,
			"pillar_every": 10, "pillar_tex": "service_wall", "overhead": "pump", "floor_stripes": true,
			"skins": {"barrier_looks": ["safety_rail"], "box_look": "warehouse"}},
	# STORM DRAIN (user reference): running along the bottom of a wide drainage channel in shallow
	# water: stained concrete walls up to raised ledges with hazard lips and railings, yellow ladders,
	# outfalls pouring water, buttresses, warm wall lamps, a big pipe up high; weirs to jump.
	"drain": {"wall": "tile", "wall_tex": "drain_wall", "ceiling_tex": "concrete", "ceiling_y": 6.0, "ambient": Color(0.2, 0.21, 0.18),
			"lamps": "hall", "fog_color": Color("0b0c0a"), "stair_wall": "drain_wall", "stair_door": "steel_door", "marker_door": "bars",
			"color": Color("5a5c54"), "height": 6.0, "ground": "sewer_floor", "ceiling": true, "pillar_every": 8, "pillar_tex": "drain_wall",
			"drain_water": true,
			"skins": {"barrier_looks": ["weir"], "box_look": "warehouse"}},
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
	"lobby": {"wall": "office", "wall_tex": "lobby_wall", "ceiling_tex": "lobby_ceiling", "ceiling_y": 9.0, "ambient": Color(0.38, 0.38, 0.43),
			"lamps": "atrium", "fog_color": Color("18171c"), "stair_wall": "lobby_wall", "stair_door": "door", "color": Color("2a2c30"),
			"height": 9.0, "ground": "lobby_floor", "ceiling": true, "wall_decor": "lobby", "mezzanine": true,
			"skins": {"barrier_looks": ["speedgate"], "pipe": "banner", "box_look": "lobby", "wall": "lobby_column"}},
	# MAIN FLOOR EXIT (user reference): the way out at night. Glass walls between big granite pillars
	# with the night city outside, warm cube lamps on the pillars, a polished dark granite floor, a dark
	# beamed ceiling, planters and benches along the glass; speed gates to jump, planters for box
	# cover, a hanging green EXIT sign to duck under, granite pillars for cover walls; a glass front
	# with sliding doors at the end.
	"exit": {"wall": "office", "wall_tex": "exit_granite", "ceiling_tex": "exit_ceiling", "ambient": Color(0.3, 0.32, 0.4),
			"lamps": "ceiling", "lamp_color": Color(0.82, 1.0, 0.9), "fog_color": Color("12141e"), "stair_wall": "exit_granite",
			"stair_door": "door", "color": Color("3a3e40"), "height": CEILING_Y, "ground": "exit_floor", "ceiling": true,
			"wall_decor": "exit", "glass_walls": true, "pillar_every": 10, "pillar_tex": "exit_granite", "glass_front": true,
			"skins": {"barrier_looks": ["speedgate"], "pipe": "exit_sign", "box_look": "planter", "wall": "exit_granite"}},
	"gate": {"wall": "blocks", "color": Color("8a8470"), "height": 4.0, "ground": "asphalt"},
	# HELIPAD (user reference): a wide rooftop pad at night, the landing ring and H, red edge lights,
	# floodlight masts, a railing round the edge, supply crates; the chopper broadside on the pad.
	"helipad": {"wall": "blocks", "ambient": Color(0.3, 0.355, 0.52), "moon": Color(0.38, 0.46, 0.7), "lamps": "pad", "snow": true,
			"color": Color("5c5c55"), "height": 0.6, "ground": "helipad_slab", "open_deck": true},
}
## The light out in an outdoor stretch of an indoor area (the LOADING DOCK's yard): night sky.
const OUTDOOR_LIGHT := {"ambient": Color(0.24, 0.27, 0.36), "moon": Color(0.34, 0.4, 0.6), "fog": 0.016, "fog_color": Color("121828")}
const DEAD_END_COLOR := Color("b03a2e")
## Paint and steel with a wall texture of their own (PsxTextures.wall): the WAREHOUSE's yellow floor
## lines (_floor_lines) and a lockdown shutter (_lockdown_shutter). And the STAFF CANTEEN's drinks
## machines: red, blue and orange (_build_vending_wall). Their textures are made ahead of time with
## the rest (_warm_textures).
const LINE_PAINT := Color("c9a227")
const LOCKDOWN_STEEL := Color("5a5f66")
const VENDING_TINTS := [Color("c41e1e"), Color("1e4ac4"), Color("e0700f")]
## Milliseconds of making textures ahead of time per frame (see _warm_textures): one a frame, or a
## few small ones.
const WARM_BUDGET_MS := 4.0
## The same under the mission briefing and the opening pan, where a hitch matters far less than in
## the run: three times as fast, so they're all made before it (the sounds go on alongside, and
## then faster themselves: AudioDirector.HURRY_BUDGET_MS).
const WARM_HURRY_MS := 12.0
## The arrows in to a stairs door (see _build_door_cues): their centres, metres before the door,
## far to near (the order they light in); their size, across the lane, along it and the stroke;
## and how far they're tipped up off the floor (lying flat, the play camera saw thin slivers).
const DOOR_ARROWS_AT := [10.0, 7.0, 4.0]
const DOOR_ARROW_SIZE := Vector3(1.15, 1.6, 0.46)
const DOOR_ARROW_TILT := 35.0
## The padlock at a locked stairs door (see _door_padlock): how far out in front of the middle of
## the door it floats, and how high its middle is: on the top half of the door, under the green
## exit sign over it, so both read.
const DOOR_LOCK_BEFORE := 0.8
const DOOR_LOCK_Y := 1.85
## How far into a stairwell the door you go in by stands, and how far its way in reaches: the back
## of the frame round that door (0.3 m deep). A locked stairs door is built to there and no further
## (_build_stairwell_parts).
const STAIR_DOOR_AT := 0.2
const STAIR_MOUTH := STAIR_DOOR_AT + 0.15
## A locked stairs door stands across the outer lane at the split, as it does open (user,
## 2026-10-08: "Locked doors can nudge CROSS into the next lane, that sounds fine."): how far
## before the split he's eased out of that lane (_ease_past_locked_doors), and how far past the
## furthest the door reaches before he may go back into it (his body's half depth and a little).
const DOOR_NUDGE_AHEAD := 5.0
const DOOR_PAST := 0.5
## Render layer for stairwell structure (see _build_stairwell). Everything else is on layer 1.
const STAIRWELL_LAYER := 2
## Just out of a stairwell, how far past the end of the flight the play camera must be before the
## stairwell is drawn again (_cam_over_flight).
const STAIRWELL_CLEAR := 0.3
## Going down a ladder (see _update_camera): how far back from you the camera keeps to the height
## of the route, and how much higher it rises as you go down (for each metre you drop).
const LADDER_DOWN_CAM_BACK := 7.0
const LADDER_DOWN_CAM_RISE := 0.3
## Render layer for the wall over a tunnel's end where you climb out by ladder: the camera, still
## down in the tunnel behind you as you come up, leaves it out (see _update_camera).
const CLIMB_LAYER := 4
## Render layer for the landing round the camera just out of a stairwell (see _build_landing). It's
## only shown then, for the play camera, in place of the stairwell it leaves out; the rear CCTV
## leaves this layer out.
const LANDING_LAYER := 8
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
## The route file played (ROUTE_PATH unless a bot picks another: --route=). Static, so Retry keeps it.
static var route_path := ROUTE_PATH
## The mission's setting played (RouteGraph.SETTINGS; user: "an easy medium and hard for each
## level"): picked in the main menu's mission select (or by a bot: --setting=). Static, so Retry keeps
## it (user: RETRY on the same setting). MEDIUM, where the bots' chopper times were tuned, until one's
## picked.
static var setting := RouteGraph.DEFAULT_SETTING
## Another mission was picked in the mission select: its level loads, and opens on its briefing.
static var _brief_on_load := false

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
## Roof snipers (CAUTION and ALERT): {node: Sniper, owner: segment node, seg: segment}. Not
## combatants: auto-aim never picks them (LOCKED roster: you dodge him, you don't shoot him).
var _snipers: Array[Dictionary] = []
## Snipers over a road you didn't take: {node, tier}. Hidden once you go into another level: the
## block under his nest runs down through the levels below, so it would stand in your corridor.
var _retired_snipers: Array[Dictionary] = []
## The boss at the chopper ({node, owner, seg}), and him once the fight's started.
var _bosses: Array[Dictionary] = []
var _boss_fight: Boss = null
## The boss's minigun pattern (his free lanes, his sweeps' directions): -1, a new one every run; the
## bots set one, so their runs repeat.
var boss_seed := -1
## The boss's KO replay (KoReplay; user): which shot is on (0..2; -1 when it isn't), its shots, real
## seconds into it and into this shot, whether it was skipped; and what it gives back at the end:
## whether the chopper's clock was running, and the camera's field of view. The camera cuts back
## hard (_cam_snap) rather than swinging round from the last shot.
var _ko := -1
var _ko_shots: Array[Dictionary] = []
var _ko_real := 0.0
var _ko_shot_real := 0.0
var _ko_skipped := false
var _ko_skip_asked := false
var _ko_clock_was := false
var _ko_fov := 70.0
var _cam_snap := false
## The chopper's climb as it lifts off (held while the KO replay stops the clock).
var _lift_tweens: Array[Tween] = []
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
## Branches not taken, kept as scenery until the player passes: {node, gone_at}, and for a
## stairwell, "plug": what walls up the hole it leaves in your road's wall when it goes.
var _retired: Array[Dictionary] = []
## Taking the stairs: the road on past them, hidden once the stairwell's camera has cut in (see
## _on_segment_needed).
var _hide_at_cut: Array[Node3D] = []
## The straight road on past the stairs you've taken, until that cut ({} otherwise): the alarm
## runner running on down it is still in front of you till then (_runner_segment).
var _road_past: Dictionary = {}
## Was the camera on a stairwell's security camera last frame? (So leaving it is a hard cut back.)
var _was_cctv := false
## The landing shown round the camera just out of a stairwell (see _build_landing), or null.
var _landing_shown: Node3D = null
var _fog_color_default := Color(0.16, 0.17, 0.15)
## The opening camera pan: seconds left (0 once it's over or skipped).
var _intro_left := 0.0
## Doors you burst through (the start room and every stairwell): {node, at, owner, seg}. Each
## bursts open when you reach it, but only on the route you're actually on.
var _doors: Array[Dictionary] = []
## Halfway markers built so far: {at (route distance), seg}. See _build_marker.
var _markers: Array[Dictionary] = []
## The lanes locked stairs doors stand across (see _bar_lane): {stub (the door's node), lane, from,
## to (route distance)}. Dropped as the door opens, or (the next time one's added) once you're past.
var _door_bars: Array[Dictionary] = []
## The zone doors ahead that the alarm runner may go through (see _runner_gates): {node (the
## Marker), frame (its doorway's, in its segment), at, owner, leaves [{node (hinge), swing,
## shut (its rotation shut)}] or shutter {node, shut_y}, bars, sweep (how far on past the door its
## leaves swing, m), half_w (half the doorway), state (Gate), by (the runner it's open for), tween,
## was (its state when you got there), quiet (he'd left it open: you run on through)}. Each one's
## leaves (or shutter) in _doors carries it as "gate". Gone once you've burst through it.
var _gates: Array[Dictionary] = []
## Cover walls, in route space: {at, x0, x1, seg, owner}. Used to find the wall you're in cover
## behind, so you lean round its edge (line of sight itself is real rays: see _sees()).
var _blockers: Array[Dictionary] = []
## Mood lighting: the lamps, the area's ambient and moonlight (see Ambience).
var _ambience: Ambience
## The start room's own lamps (the cold light at its open window, the desk lamp, the computer's
## glow), shown only while the camera is in the room (_light_start_room).
var _room_lamps: Node3D
## All the sound (see AudioDirector).
var _audio: AudioDirector
## The menus (main menu, settings, pause, end screens).
var _frontend: Frontend
## The main menu is up (the camera sways slowly in front of you; no input reaches the game). It
## stays up under the mission briefing, so everything carries on as under the menu.
var _menu_open := false
## The mission briefing's script (Briefing.load_file()), with the end-of-mission conversations.
var _briefing: Dictionary = {}
var _menu_t := 0.0
## Where the menu camera's sway had got to at START (the opening pan eases out of it: IntroCamera).
var _pan_sway := 0.0
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
## How far down into a slide the cutout's hole has gone with him (0..1: Cutout.slide_toward).
var _cut_slide := 0.0
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
## The stairs doors' arrow meshes, one per width (_arrow_mesh).
var _arrow_meshes := {}
## The textures to make ahead of time (_warm_textures), and the next one's place in the list.
var _to_warm: Array[Callable] = []
var _warm_next := 0

@onready var _player: Player = $Player
@onready var _camera: Camera3D = $Camera3D
@onready var _input: SwipeInput = $SwipeInput
@onready var _runner: RouteRunner = $RouteRunner
@onready var _hud: Hud = $Hud
@onready var _world: Node3D = $World


func _ready() -> void:
	Engine.time_scale = 1.0
	if not setting in RouteGraph.SETTINGS:
		setting = RouteGraph.DEFAULT_SETTING
	_load_route()
	# The route map grows with this mission's own finds (each mission keeps its own map).
	RunLog.set_mission(StringName(_graph.mission().get("mission", "")))
	# The route's stairs rule keeps the 20 m after each flight's exit door clear, counting the
	# flight as RouteGraph.STAIRS_FLIGHT long: the flights built here (_segment_shape) must be that.
	if not is_equal_approx(tuning.tier_height * tuning.stairs_run, RouteGraph.STAIRS_FLIGHT):
		push_error("Tuning: a flight of stairs is now %s m (tier_height x stairs_run), but RouteGraph.STAIRS_FLIGHT says %s m" \
				% [tuning.tier_height * tuning.stairs_run, RouteGraph.STAIRS_FLIGHT])

	_input.swiped.connect(_on_swipe)
	_input.tapped.connect(_on_tap)
	_input.fire_pressed.connect(_on_fire)
	_input.fire_released.connect(set_fire_held.bind(false))
	_hud.setup(tuning)
	_frontend = Frontend.new()
	_frontend.name = "Frontend"
	add_child(_frontend)
	_frontend.mission_title = String(_graph.mission().get("title", "MISSION 1"))
	_briefing = Briefing.load_file(BRIEFING_PATH)
	for problem in Briefing.problems(_briefing):
		push_error("briefing.json: " + problem)
	_frontend.start_requested.connect(_on_mission_picked)
	_frontend.briefing_done.connect(_begin_intro)
	_frontend.resume_requested.connect(_resume)
	_frontend.retry_requested.connect(func() -> void:
		get_tree().paused = false
		_retry())
	_frontend.menu_requested.connect(func() -> void:
		get_tree().paused = false
		_skip_title = false
		GameState.abandon_run()  # (quit mid-run: the menu starts fresh)
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
	# His muzzle flash lights him and what's round him for a moment (user: a cool looking flash).
	_ambience.add_lamp(_player.muzzle_light(), SoldierRig.FLASH_LIGHT, SoldierRig.FLASH_LIGHT_RANGE, {"alert": false, "own_slot": true})
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
	_player.death_beat.connect(func(beat: String) -> void:
		if beat == "down":  # (he hits the ground)
			_audio.play_at("fall", _player.to_global(Vector3(0.0, 0.3, -1.0)), 1.0, 0.04)
			_audio.play_at("player_hit", _player.to_global(Vector3(0.0, 0.3, -1.0)), -6.0, 0.04))
	# His gun check under the menu: the slide, the magazine, the slap, at his hands. (Not under the
	# briefing: the codec's ticks and static are what you hear then.)
	_player.ready_beat.connect(func(sound: String) -> void:
		if _frontend.in_briefing():
			return
		_audio.play_at(sound, _player.to_global(Vector3(0.0, 1.4, -0.35)), -3.0 if sound == "mag_slap" else -6.0, 0.04))
	GameState.alert_changed.connect(_on_alert_changed.unbind(1))

	_promote(_make_segment(_graph.start_id, 0.0, {}, Transform3D.IDENTITY))
	# The mission starts in an office room behind a closed door into the first area.
	_build_start_room(_segments[0])
	_player.distance = -tuning.start_offset
	_place_player()
	_update_environment(0.0)
	_ambience.snap()  # start in the area's own light, not fading in from bright
	_warm_textures()
	if _skip_title:
		_make_warm(INF)  # (Retry: no menu to make them under)
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
		_warm_door_cues()
	_frontend.clicked.connect(func() -> void: _audio.play("tick", -2.0, 0.0, "UI"))
	# The end screen's tally counting up, Doom style: a tick per step, a thunk as each row lands.
	_frontend.tally_ticked.connect(func() -> void: _audio.play("tick", -6.0, 0.04, "UI"))
	_frontend.tally_landed.connect(func() -> void: _audio.play("thunk", -3.0, 0.03, "UI"))
	_frontend.typed.connect(func() -> void: _audio.play("tick", -8.0, 0.05, "UI"))
	_frontend.briefing_cue.connect(func(sound: String, db: float) -> void: _audio.play(sound, db, 0.0, "UI"))
	_frontend.debrief_opened.connect(_on_debrief_opened)
	Settings.changed.connect(_apply_settings)
	_apply_settings()
	if _brief_on_load and not _skip_title:
		_brief_on_load = false  # (another mission picked in the mission select: its level, then its briefing)
		_open_briefing()


## The route played, for the setting played (only what's in that setting, its chopper and its boss:
## RouteGraph.for_setting), checked against every route rule at that setting's own reaction floor
## (the fair-reaction and cover-exit rules: RouteGraph.reaction_for).
func _load_route() -> void:
	_graph = RouteGraph.from_json_file(route_path, setting)
	for problem in _graph.validate(tuning, RouteGraph.reaction_for(_graph.setting)):  # (timed with this run and jump)
		push_error("route.json (%s): %s" % [_graph.setting, problem])


## The mission select's pick (Frontend: an open mission and setting). Mission n's level is built for
## that setting, then its briefing opens. The same level as the one under the
## menu: the setting is swapped in place (_use_setting); another mission's level (none is built yet
## but mission 1) is loaded fresh for it, and its briefing opens once it's up.
func _on_mission_picked(n: int, which: String) -> void:
	Progress.remember_pick(n, which)
	var path := String(Progress.MISSIONS[n - 1].get("route", route_path)) if n >= 1 and n <= Progress.MISSIONS.size() else route_path
	if path != route_path:
		route_path = path
		setting = which
		_brief_on_load = true
		get_tree().reload_current_scene()
		return
	_use_setting(which)
	_open_briefing()


## Plays `which` setting from here: the route read for it, the chopper's timeline from it, and what's
## built ahead under the menu (the area after the first: the first is the same on every setting, a
## route rule) built again if it differs on this setting. Before the run (the menu and the briefing).
func _use_setting(which: String) -> void:
	if which == _graph.setting or not which in RouteGraph.SETTINGS or _started:
		return
	var was := _graph
	setting = which
	_load_route()
	_clock.configure(_graph.mission().get("chopper", {}))
	var seg := _current
	for key in seg["branches"].keys():
		var id: StringName = seg["branches"][key]["id"]
		if JSON.stringify(was.node_data(id)) != JSON.stringify(_graph.node_data(id)):
			_discard(seg["branches"][key])
			seg["branches"].erase(key)
	_build_branches()  # (the ones just thrown away, built again for this setting)


## A mission picked: the mission briefing first (user: a codec conversation to read before the run),
## over the menu's scene as it was: the camera swaying, CROSS in his ready loop, no run, no clock
## (all of that starts with start_run, after the pan). Its end (SKIP, or a tap after its last line)
## starts the opening pan. With no lines to play, straight to the pan. Retry never gets here (it
## skips the menu, the briefing and the pan). The menu music, if it's still being built, goes back to
## the normal pace (AudioDirector.leave_menu): these frames make the level's textures.
func _open_briefing() -> void:
	_audio.leave_menu()
	if Briefing.lines_of(_briefing).is_empty():
		_begin_intro()
		return
	_frontend.show_briefing(_briefing)
	_audio.duck_menu_music(true)


## After the briefing: the menu goes, and the opening pan plays round to behind you with the mission
## title; when it ends, the run starts (the door bash). A tap during the pan skips it.
func _begin_intro() -> void:
	_audio.duck_menu_music(false)
	_menu_open = false
	_frontend.hide_all()
	_intro_left = tuning.intro_pan_time
	_pan_sway = IntroCamera.sway(_menu_t)
	_player.intro_pan = 0.0  # (his ready stance settles, then sets for the run as the camera comes round)
	_hud.show_mission_title(String(_graph.mission().get("title", "")))


func _pause() -> void:
	if not GameState.run_active or get_tree().paused or _ko >= 0 or _player.halted:
		return  # (caught: his capture, its conversation and the debrief follow)
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
	# The textures not made yet (START, the briefing and the pan all tapped through), made now, all
	# at once: a hitch here, before he's yours, is far less harmful than one in the run, and none is
	# ever made in the run. The sounds still to build go on at the normal pace (AudioDirector).
	_make_warm(INF)
	_audio.build_ms = AudioDirector.BUILD_BUDGET_MS
	set_process(false)
	GameState.start_run(START_ALERT)
	_runner.begin(_graph, false)
	_clock.start()


## Each frame until the run starts, the warm-up: some of the textures made ahead of time
## (_warm_textures). Under the main menu, none while the sounds are still being built, so the two
## never weigh on the same frame. Under the mission briefing and the opening pan, they're made
## whatever the sounds are doing, WARM_HURRY_MS a frame, and once they're all made the sounds go
## faster (AudioDirector.HURRY_BUDGET_MS). start_run makes any textures left.
func _process(_delta: float) -> void:
	var hurry := _frontend.in_briefing() or _intro_left > 0.0
	if _warm_next < _to_warm.size():
		if hurry:
			_make_warm(WARM_HURRY_MS)
		elif not _audio.building():
			_make_warm(WARM_BUDGET_MS)
	else:
		_audio.build_ms = AudioDirector.HURRY_BUDGET_MS if hurry else AudioDirector.BUILD_BUDGET_MS
		if not _audio.building():
			set_process(false)


func _physics_process(delta: float) -> void:
	if _intro_left > 0.0:
		_intro_left -= delta
		_player.intro_pan = clampf(1.0 - _intro_left / tuning.intro_pan_time, 0.0, 1.0)
		if _intro_left <= 0.0 and not _started:
			start_run()  # the pan has ended behind the player: go
	if GameState.run_active and _ko >= 0:
		_update_ko(delta)
	elif GameState.run_active:
		for door in _doors:
			var reach := SHUTTER_OPEN_AHEAD if door.get("shutter", false) else BASH_AHEAD
			if not door.get("done", false) and _player.distance_run() >= door["at"] - reach and door["seg"].get("promoted", false):
				door["done"] = true
				# A zone door the alarm runner may have been through: yours now, from wherever he left
				# it, bursting open just as a shut one does (if it's still standing open, you run on
				# through it: no crash).
				var quiet := _gate_yours(door["gate"]) if door.has("gate") else false
				if door.get("shutter", false):
					_raise_shutter(door["node"], door.get("shut_y", door["node"].position.y))
				else:
					_bash_door(door["node"], door.get("swing", 1.0), door.get("roll", 0.1), door.get("shut"), quiet)
					if door.has("sight"):  # (its line-of-sight block swings open as the door always did)
						_swing_open(door["sight"], 1.0, 0.1)
				if door.has("sound") and not quiet:
					_audio.play(door["sound"], 0.0, 0.05)
		_funnel_to_markers()
		_ease_past_locked_doors()
		_update_footsteps(delta)
		_runner.update(_player.distance_run(), _player.lane)
		_check_obstacles()
		_update_combat(delta)
		if GameState.run_active:
			_update_squad(delta)
		if GameState.run_active:
			_update_searchlights(delta)
		if GameState.run_active:
			_update_snipers(delta)
		if GameState.run_active:
			_update_boss(delta)
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
	# The sky only where open sky can be in view: it's drawn 120 m out, so down a longer hall
	# indoors its skyline stood in front of the far end wall (the LOBBY: the user's gaps).
	_sky.visible = _sky_in_view(seg_here)
	# Mood lighting: the area's own ambient and moonlight, and the lamps nearest where you look (and,
	# while the rear-view CCTV is up, the lamps it shows behind you as well).
	_ambience.set_area(theme.get("ambient", DEFAULT_AMBIENT), theme.get("moon", Color.BLACK), MOON_DIR)
	_light_start_room()
	var rear := _rear_cam if _rear_cam != null and _rear_vp.render_target_update_mode != SubViewport.UPDATE_DISABLED else null
	_ambience.update(delta, _camera, GameState.alert_level if GameState.run_active else START_ALERT, rear)
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
				var lift: Tween = c.create_tween()
				lift.tween_property(c, "position:y", c.position.y + 2.5, _clock.gone_at - _clock.lifts_at)
				_lift_tweens.append(lift)
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


## How far along a segment a point (in the segment node's space) is, on the leg it's beside.
static func _into_of(seg: Dictionary, p: Vector3) -> float:
	var legs: Array = seg["legs"]
	for i in range(legs.size() - 1, -1, -1):
		var into: float = float(legs[i]["start"]) - ((legs[i]["xf"] as Transform3D).affine_inverse() * p).z
		if into >= float(legs[i]["start"]) or i == 0:
			return into
	return 0.0


## How far the road turns where leg i starts (radians, left +); 0 for the first leg, or past the last.
static func _turn_at(seg: Dictionary, i: int) -> float:
	var legs: Array = seg["legs"]
	if i <= 0 or i >= legs.size():
		return 0.0
	var before: Transform3D = legs[i - 1]["xf"]
	var after: Transform3D = legs[i]["xf"]
	return before.basis.x.signed_angle_to(after.basis.x, Vector3.UP)


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
	# The road it's on, by where that road starts (route m): straight on from the segment you're on,
	# the same road as that one; off to a side (up or down stairs, down a ladder), a new road from
	# here. The alarm runner keeps to his own (_runner_segment).
	var on_from: bool = not edge.is_empty() and RouteGraph.side_of(edge) == "straight" \
			and not _current.is_empty() and _current["id"] == from_id
	seg["road"] = _current["road"] if on_from else start
	seg["legs"] = _plan_legs(seg, xf)
	var node := Node3D.new()
	node.name = String(id)
	_world.add_child(node)
	node.transform = xf
	seg["node"] = node
	var open := Vector2.ZERO
	if from_id != &"" and not _current.is_empty() and _current["id"] == from_id:
		# A branch of the fork you're on: where its walls open onto the next road over, and on the
		# straight road on past a stairwell, where it passes out through this road's side, known
		# before anything is built along it (the holes were only cut once it was all built, so the
		# WATER TOWERS' roof clutter and lamp pools stood in the stairwell down from the ROOFTOPS:
		# the user's stairs). So its walls are built once, as they'll stay: _cut_openings works the
		# same out again and leaves them. (Built first with no openings, every branch's walls were
		# built twice: the biggest part of the hitch as the branches are built at each fork.)
		open = _openings(_current, seg)

	var length: float = seg["length"]
	_build_surfaces(node, seg, open.x, open.y)
	if _theme(id).get("sky", false):
		_build_city(node, seg)
	if _theme(id).get("office_roof", false):
		_office_roof_decor(node, seg)
		_far_masts(node, seg, 8)
	if _theme(id).get("towers", false):
		_water_towers(node, seg)
		_walkway_clutter(node, seg, 5.5, float(seg["ramp_len"]) + 4.0, length - 3.0)
	if _theme(id).get("skylights", false):
		_skylights(node, seg)
		_walkway_clutter(node, seg, 6.5, float(seg["ramp_len"]) + 3.0, length - 3.0)
		_roof_hut(node, seg, length - 6.0, -(tuning.lane_count * tuning.lane_width / 2.0 + 3.4), 1)
		_far_masts(node, seg, 5)
	if _theme(id).get("antennas", false):
		_antenna_farm(node, seg)
		_far_masts(node, seg, 12)
		_roof_hut(node, seg, length - 8.0, -(tuning.lane_count * tuning.lane_width / 2.0 + 3.6), 1)
	_build_lamps(node, seg)
	# A high-ceilinged area (the LOBBY, the BOILER ROOM) meets lower ones at its ends: wall over the
	# join, from the usual ceiling up to its own, so no sky shows through the gap above.
	if _theme(id).get("ceiling", false) and _ceil(id) > CEILING_Y + 0.1:
		var head_w := tuning.lane_count * tuning.lane_width + 2.6
		for hz in [0.0, length]:
			var bottom := CEILING_Y - 0.05
			if hz > 0.0 and _climbs_out(id):
				# The STORM DRAIN's end, where the ladders go up: down to the deck's height over the
				# ladder shafts (a slot of sky showed above them), and left out by the camera as you
				# climb (it would stand across the hatch in front of it: the user's gaps).
				bottom = tuning.tier_height - 0.05
			var head_h := _ceil(id) + 0.05 - bottom
			var head := _item_box(node, seg, hz, Vector3(0, bottom + head_h / 2.0, 0), Vector3(head_w, head_h, 0.3), Color.WHITE)
			head.material_override = PsxMaterials.textured(_wall_texture(_theme(id)), Vector2(head_w / 2.0, head_h / 2.0))
			if hz > 0.0 and _climbs_out(id):
				head.layers = CLIMB_LAYER

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
			elif jump_look == "weir":
				mesh = _build_weir(node, seg, at, x, lane)
			elif jump_look == "safety_rail":
				mesh = _build_safety_rail(node, seg, at, x, lane)
			elif jump_look == "cable_tray":
				mesh = _build_cable_tray(node, seg, at, x, lane)
			elif jump_look == "ibeam":
				mesh = _build_ibeam(node, seg, at, x, lane)
			elif jump_look == "floor_pipe":
				mesh = _build_floor_pipe(node, seg, at, x, lane)
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
			elif box_look == "planter":
				mesh = _build_exit_box(node, seg, at, x, lane)
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
			elif box_look == "equip":
				mesh = _build_equip_box(node, seg, at, x, lane)
			elif box_look == "gantry_case":
				mesh = _build_gantry_case(node, seg, at, x, lane)
			elif box_look == "condenser":
				mesh = _build_condenser(node, seg, at, x, lane)
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
			_connect_security(sec, seg["road"])
			# He keeps to the road this area is on (_runner_segment): "place" puts him on it (made
			# here, once, not every frame).
			_combatants.append({"node": sec, "owner": node, "seg": seg, "place": _runner_point.bind(seg["road"])})
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
	# Snipers (roofs, CAUTION and ALERT; user design): his spot is where he starts on you; his nest
	# is ahead of it, out to one side and up, on the next building over.
	for s: Dictionary in _graph.node_data(id).get("snipers", []):
		var sn := Sniper.new(tuning)
		var into := float(s["at"])
		sn.at = start + into
		sn.side = -1 if String(s.get("side", "right")) == "left" else 1
		sn.min_alert = int(s.get("min_alert", 2))
		var here := _frame_at(seg, into)
		var nest_into := minf(into + float(s.get("ahead", tuning.sniper_nest_ahead)), float(seg["length"]) - 1.0)
		var out := float(s.get("out", tuning.sniper_nest_out))
		var up := float(s.get("up", tuning.sniper_nest_up)) + _height(seg, nest_into) - _height(seg, into)
		# Straight on from his spot, not along the road: a bend on the way can't swing him off screen.
		sn.nest = Transform3D(Basis.IDENTITY, Vector3(sn.side * out, up, -(nest_into - into)))
		node.add_child(sn)
		sn.transform = here
		sn.tracking.connect(_on_sniper_tracking)
		sn.locked.connect(_on_sniper_locked.bind(sn))
		sn.fired.connect(_on_sniper_fired.bind(sn))
		_snipers.append({"node": sn, "owner": node, "seg": seg})
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
	# The MAIN FLOOR EXIT's glass front with its sliding doors (not with the walls: they can be rebuilt).
	if _theme(id).get("glass_front", false) and _graph.all_next(id).size() == 1:
		_build_exit_front(node, seg)
	if not _has_straight(id) and _graph.end_type(id) == "":
		_build_dead_end(node, seg)
	if RouteGraph.via_of(edge) == "ladder":
		_build_ladder(node, seg, RouteGraph.side_of(edge))
	if _graph.end_type(id) == "extract":
		_spawn_chopper(node, _frame_at(seg, length) * Transform3D(Basis.IDENTITY, Vector3(0, 0, -3.0)))
		_spawn_boss(node, seg, length)
	_cache_sky(seg)
	return seg


## The boss (user design): waiting in front of the chopper, in the middle lane, facing you.
func _spawn_boss(node: Node3D, seg: Dictionary, length: float) -> void:
	var into := length - BOSS_FROM_END
	var boss := Boss.new(tuning)
	boss.configure(_graph.mission().get("boss", {}))  # (the setting's: his hits and spin-ups)
	boss.at = float(seg["start"]) + into
	boss.set_seed(boss_seed if boss_seed >= 0 else randi())
	node.add_child(boss)
	boss.transform = _frame_at(seg, into) * Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	# A floodlight on him from in front (your side, high up), so he reads from the standoff line.
	# His (he faces you): it goes out with him if this pad's not the one you take.
	var lamp := Node3D.new()
	boss.add_child(lamp)
	lamp.position = Vector3(0, 3.2, -2.5)
	_ambience.add_lamp(lamp, Color(1.0, 0.92, 0.8) * 1.4, 6.0, {"alert": false})
	# His minigun's flash lights him and the deck round him (user): a warm light, flickering with it.
	_ambience.add_lamp(boss.flash_lamp, Color(1.0, 0.72, 0.38) * 3.6, 8.5, {"alert": false, "second_slot": true})
	# His minigun's roar, on while the gun fires (it stops over the free lanes).
	boss.fire_sound = _audio.attach_loop(boss, "minigun_fire", 0.0, 45.0, 6.0)
	boss.fire_sound.position = Vector3(0, 1.2, -0.5)
	boss.fire_sound.stop()
	boss.spinning_up.connect(func() -> void:
		RunLog.record_event("boss_attack", {"node": _runner.current})
		_audio.play_at("minigun_spin", boss.global_position + Vector3.UP * 1.2, 0.0, 0.03))
	boss.wounded.connect(func() -> void: _audio.play_at("hit", boss.global_position + Vector3.UP * 1.5, -1.0, 0.08))
	boss.defeated.connect(func() -> void:
		RunLog.record_event("boss_down", {"node": _runner.current})
		_hud.show_boss(-1.0)
		_ko_begin(boss))  # (you run on to the chopper once it's over)
	boss.death_beat.connect(_on_boss_death_beat.bind(boss))
	# Both ladders down a roof lead to the same helipad (built twice, in the same place): one boss
	# stands there, not two inside each other; the fork shows the one on the pad you come onto.
	for b in _bosses:
		if is_instance_valid(b["node"]) and (b["node"] as Node3D).global_position.distance_to(boss.global_position) < 0.5:
			boss.visible = false
	_bosses.append({"node": boss, "owner": node, "seg": seg})


## The player is now on this segment: build every branch it can lead to, and its fork cue.
func _promote(seg: Dictionary) -> void:
	seg["promoted"] = true  # its troopers and alarm boxes come alive
	_segments.append(seg)
	_current = seg
	_build_branches()
	_build_fork_cue()


## Keeps the current segment's branches in step with alert: each open exit is built in full,
## each exit closed by alert gets a lockdown door (a shutter slams if the branch was open a moment
## ago), or, for a stairs door, that door, shut, just where it stands open (_build_locked_stub).
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
	_show_lock_plugs(seg)
	_cache_sky(seg)  # (its branches have changed)


## While a stairs door is locked, only its way in is built (_build_locked_stub), so the hole its
## stairwell passes out through in the side wall of the straight road on is walled up: the hole's
## plug (_hole_plug), shown. It's hidden again as the door reopens and its stairwell comes back
## through the hole.
func _show_lock_plugs(seg: Dictionary) -> void:
	for road: Dictionary in seg["branches"].values():
		if RouteGraph.side_of(road["edge"]) != "straight":
			continue
		for edge in _graph.all_next(seg["id"]):
			var plug := _hole_plug(road, edge)
			if plug:
				var stub: Node3D = seg["locked"].get(_key(edge))
				plug.visible = stub != null and stub.has_meta("stairs_door")


## Throws away a branch that wasn't taken (and its obstacles).
func _discard(branch: Dictionary) -> void:
	var node: Node3D = branch["node"]
	_obstacles = _obstacles.filter(func(o: Dictionary) -> bool: return o["owner"] != node)
	_combatants = _combatants.filter(func(c: Dictionary) -> bool: return c["owner"] != node)
	_lights = _lights.filter(func(l: Dictionary) -> bool: return l["owner"] != node)
	_snipers = _snipers.filter(func(s: Dictionary) -> bool: return s["owner"] != node)
	_bosses = _bosses.filter(func(b: Dictionary) -> bool: return b["owner"] != node)
	_doors = _doors.filter(func(dr: Dictionary) -> bool: return dr["owner"] != node)
	_drop_gates(node, false)
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
	for b in _bosses:
		if b["owner"] == chosen["node"] and is_instance_valid(b["node"]):
			b["node"].visible = true  # (the pad you come onto: its boss, if its twin stood in for him)
	var took_stairs := RouteGraph.via_of(chosen["edge"]) == "stairs"
	for k in branches:
		if k != key:
			var branch: Dictionary = branches[k]
			# (When a stairwell goes, the hole it passed through in your road's wall is walled up.)
			_retire(branch["node"], gone_at, _hole_plug(chosen, branch["edge"]))
			if RouteGraph.via_of(branch["edge"]) == "stairs":
				# Up or down the stairs you didn't take, the area is a floor above or below you: all
				# you can see of it is its stairwell, through the hole in your wall. The rest goes now,
				# or its tall halls and blocks stick through yours (the PUMP STATION's basin wall and
				# ceiling cut through the LOADING DOCK: the user's gaps).
				_hide_but_stairwell(branch["node"])
			elif took_stairs:
				# The road on past the stairs you took is still on your floor, in front of you, until
				# you're through the door: hidden here, a metre short of it, it went to the void for
				# the last few frames before the stairwell's camera cut in (its floor, walls, door and
				# lamps, at every stairs door). So it goes as that camera cuts in (_on_node_entered),
				# still well before you're out on the other floor, where its tall blocks would stick
				# through yours (a WATER TOWERS tower's base stood in the SECURITY WING: the user's gaps).
				_hide_at_cut.append(branch["node"])
				if RouteGraph.side_of(branch["edge"]) == "straight":
					_road_past = branch  # (the alarm runner on it goes with it)
	for k in _current["locked"]:
		_retire(_current["locked"][k], gone_at, _hole_plug(chosen, _edge_of(_current, k)))
	branches.clear()
	_current["locked"].clear()
	_cache_sky(_current)  # (its last metre: no branches now)
	_promote(chosen)


## Every child of a branch's node but its stairwell, hidden (see _on_segment_needed).
func _hide_but_stairwell(node: Node3D) -> void:
	for c in node.get_children():
		if c is Node3D and c.name != "Stairwell":
			(c as Node3D).visible = false


## The exit from `seg` that `key` (_key) names.
func _edge_of(seg: Dictionary, key: String) -> Dictionary:
	for edge in _graph.all_next(seg["id"]):
		if _key(edge) == key:
			return edge
	return {}


## What walls up the hole that the stairwell out by `edge` passes through in the side wall of
## `road` (the straight road on), built with that wall and hidden (_build_walls); null if none.
func _hole_plug(road: Dictionary, edge: Dictionary) -> Node3D:
	if edge.is_empty() or RouteGraph.via_of(edge) != "stairs" or not _turns(edge) or RouteGraph.side_of(road["edge"]) != "straight":
		return null
	return road["node"].get_node_or_null("Walls/" + _plug_name(-1 if RouteGraph.side_of(edge) == "left" else 1))


static func _plug_name(side: int) -> String:
	return "HolePlugLeft" if side < 0 else "HolePlugRight"


## A branch not taken: its obstacles, troopers and doors go at once; its scenery stays until
## the player reaches `gone_at`. `plug`: shown when it goes (see _hole_plug).
func _retire(node: Node3D, gone_at: float, plug: Node3D = null) -> void:
	_obstacles = _obstacles.filter(func(o: Dictionary) -> bool: return o["owner"] != node)
	_doors = _doors.filter(func(dr: Dictionary) -> bool: return dr["owner"] != node)
	_drop_gates(node)
	_blockers = _blockers.filter(func(b: Dictionary) -> bool: return b["owner"] != node)
	for c in _combatants:
		if c["owner"] == node and (c["node"] is RifleTrooper or c["node"] is RusherDog or c["node"] is SecurityTrooper):
			c["node"].visible = false  # nobody left standing on a road you didn't take
	_combatants = _combatants.filter(func(c: Dictionary) -> bool: return c["owner"] != node)
	_lights = _lights.filter(func(l: Dictionary) -> bool: return l["owner"] != node)
	for s in _snipers:
		if s["owner"] == node and is_instance_valid(s["node"]):
			s["node"].stand_down()  # he lies low over a road you didn't take
			_retired_snipers.append({"node": s["node"], "tier": _graph.tier_of(StringName(s["seg"]["id"]))})
	_snipers = _snipers.filter(func(s: Dictionary) -> bool: return s["owner"] != node)
	for b in _bosses:
		if b["owner"] == node and is_instance_valid(b["node"]):
			b["node"].visible = false  # (the helipad you didn't come up onto: one boss, not two)
	_bosses = _bosses.filter(func(b: Dictionary) -> bool: return b["owner"] != node)
	_retired.append({"node": node, "gone_at": gone_at, "plug": plug})


## Entering a side branch: move the player into the branch's own lanes (same spot in the world).
func _on_node_entered(id: StringName) -> void:
	# Through a stairs door: this frame the stairwell's camera cuts in (in_stairwell(), the same
	# distance), so the road on past the door goes now, out of sight (and the alarm runner on it).
	for n in _hide_at_cut:
		if is_instance_valid(n):
			_hide_but_stairwell(n)
	_hide_at_cut.clear()
	_road_past = {}
	for r in _retired_snipers:
		if is_instance_valid(r["node"]) and _graph.tier_of(id) != r["tier"]:
			r["node"].visible = false  # you're down the stairs: his nest's block would be in your way
	_retired_snipers = _retired_snipers.filter(func(r: Dictionary) -> bool: return is_instance_valid(r["node"]) and r["node"].visible)
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
	if _ko < 0:
		_audio.play("warn", -6.0, 0.0, "UI")  # (quiet through the boss's KO replay: the clock's stopped)
	get_tree().create_timer(1.8).timeout.connect(_warn_lift_off)


## Footsteps on whatever's underfoot (and a landing after a jump), while you're running.
func _update_footsteps(delta: float) -> void:
	var airborne := _player.is_airborne()
	if _was_airborne and not airborne:
		_audio.play("land", -6.0, 0.08)
		_stride_left = tuning.stride
	_was_airborne = airborne
	if airborne or _player.in_cover or _player.standoff or _player.halted or _player.is_sliding():
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
			surface = {"office_floor": "office", "security_floor": "office", "canteen_floor": "office", "warehouse_floor": "concrete", "lobby_floor": "office", "asphalt": "tunnel", "service_floor": "tunnel", "steel_plate": "concrete", "sewer_floor": "tunnel", "gravel": "gravel"}.get(_theme(seg["id"])["ground"], "concrete")
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
## if he gets there. The HUD bar tracks his run. `road`: the road he's on (_runner_segment). Take
## the stairs off it ahead of him and he runs on to his alarm out of sight, on his own floor, and
## still raises it if he gets there: it's the building's alarm, wherever you are (the bar keeps
## tracking him, so it doesn't come out of nowhere). The stairs are no way out of him.
func _connect_security(sec: SecurityTrooper, road: float) -> void:
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
		if sec.alarm_at > 0.0 and sec.at < sec.alarm_at:  # dropped on his way, before his panel
			RunLog.record_event("runner_stopped", {"node": _runner.current})
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
		_build_runner_alarm(sec, road)
		GameState.raise_alert())


## Where the runner raised the alarm: a red panel on the wall, flashing. `road`: his (see
## _connect_security).
func _build_runner_alarm(sec: SecurityTrooper, road: float, klaxon: bool = true) -> void:
	var seg := _runner_segment(sec.at, road)
	if seg.is_empty():
		return  # off the road you're on, or not built yet: you only hear about it
	sec.panel_built = true
	var px := signf(sec.wall_x) * (tuning.lane_count * tuning.lane_width / 2.0 + 0.45)
	var panel := _item_box(seg["node"], seg, sec.at - seg["start"], Vector3(px, 1.7, 0), Vector3(0.14, 0.45, 0.4), Color.WHITE)
	panel.material_override = PsxMaterials.glow(Color("ff3020"))
	_ambience.add_lamp(panel, Color(1.0, 0.15, 0.1) * 1.6, 5.0, {"blink": 0.5, "alert": false})
	if klaxon:
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
	# Alert 3: the pursuit squad comes after you; below it, they fall back. Only in a mission that
	# has them ("squad" in route.json, on unless it says false): mission 1 has the basics only, and
	# the squad arrives in its own mission later.
	if GameState.run_active and level >= 3 and not _squad_on and bool(_graph.mission().get("squad", true)):
		_spawn_squad()
	elif level < 3 and _squad_on:
		_squad_fall_back()
	_build_branches()
	_build_fork_cue()


func _is_authored_fork(id: StringName) -> bool:
	return _graph.end_type(id) == "" and RouteGraph.is_choice(_graph.all_next(id))


## True if an area has open sky to see: no ceiling, glass walls (the MAIN FLOOR EXIT) or an
## outdoor stretch (the LOADING DOCK's yard).
func _open_sky(id: StringName) -> bool:
	var theme := _theme(id)
	return not theme.get("ceiling", false) or theme.get("glass_walls", false) or _graph.node_data(id).has("outdoor")


## True if open sky can be in view from `seg`: in it, or in an area it leads straight on to (up or
## down a stairwell you can't see through to the other end), or back up the flight down you're on,
## through the door you burst open at its top. Asked every frame (the menu too), so it's worked out
## as `seg` is built and as its branches change (_cache_sky): this only reads it.
func _sky_in_view(seg: Dictionary) -> bool:
	var d := _player.distance_run()
	if d < 0.0:
		return false  # the start room
	return seg["sky"] or d - float(seg["start"]) < float(seg["sky_flight"])


## Works out what _sky_in_view reads, for `seg` with the branches it has now: seg["sky"], open sky
## in it or straight on from it; seg["sky_flight"], how far into it the flight down from open sky
## at its start runs (to where you're out of the stairwell, as in_stairwell()), or -INF if none.
## Down from the ROOFTOPS into the SECURITY WING, the stairwell's camera looks back up the flight at
## the roof door you've just burst open: through it, with no sky, was the flat colour of the void
## where the stars had been.
func _cache_sky(seg: Dictionary) -> void:
	var sky := _open_sky(seg["id"])
	for b: Dictionary in seg["branches"].values():
		if RouteGraph.via_of(b["edge"]) != "stairs" and _open_sky(b["id"]):
			sky = true
	seg["sky"] = sky
	var down_from_sky: bool = _is_stairs(seg) and float(seg["dy"]) < 0.0 and _open_sky(seg["from_id"])
	seg["sky_flight"] = float(seg["ramp_len"]) + 0.3 if down_from_sky else -INF


## True if every way on from this area is a ladder up (the STORM DRAIN's end).
func _climbs_out(id: StringName) -> bool:
	var nexts := _graph.all_next(id)
	if nexts.is_empty():
		return false
	for edge in nexts:
		if RouteGraph.via_of(edge) != "ladder" or _graph.tier_of(StringName(edge["to"])) <= _graph.tier_of(id):
			return false
	return true


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
## (Built with the branch, they're already right: _rebuild_walls leaves them.)
func _cut_openings(seg: Dictionary, branch: Dictionary) -> void:
	var open := _openings(seg, branch)
	_rebuild_walls(branch, open.x, open.y)


## How far from its start `branch` of `seg` leaves its left and right walls open, where it overlaps
## the next road over (x, y); and, on the straight road on, where the stairwells out of `seg` pass
## out through its sides (_stair_holes: branch["holes"]).
func _openings(seg: Dictionary, branch: Dictionary) -> Vector2:
	var side := RouteGraph.side_of(branch["edge"])
	var clear := _overlap_clear()
	var sides := {}
	for edge in _graph.all_next(seg["id"]):
		if _turns(edge):
			sides[RouteGraph.side_of(edge)] = true
	var open_l := 0.0
	var open_r := 0.0
	branch["holes"] = {}
	branch["holes_up"] = {}
	if side == "straight":
		# A corridor branch needs the wall open where it overlaps; a stairwell only needs a hole
		# where its narrow tube passes through the wall, so nothing else shows the outside.
		_stair_holes(seg, branch)
		for edge in _graph.all_next(seg["id"]):
			if not _turns(edge) or RouteGraph.via_of(edge) == "stairs":
				continue
			if RouteGraph.side_of(edge) == "left":
				open_l = clear
			else:
				open_r = clear
	elif _turns(branch["edge"]) and RouteGraph.via_of(branch["edge"]) != "stairs":
		open_l = clear if side == "right" else 0.0
		open_r = clear if side == "left" else 0.0
	return Vector2(open_l, open_r)


## The holes the stairwells leaving `seg` need in the side walls of `road`, the straight road on
## (see _stairwell_hole): road["holes"], by side, road["holes_up"], which of them climb, and
## road["hole_bands"], where each stairwell crosses the road (_stairwell_band).
func _stair_holes(seg: Dictionary, road: Dictionary) -> void:
	var holes := {}
	var holes_up := {}
	var bands := {}
	for edge in _graph.all_next(seg["id"]):
		if _turns(edge) and RouteGraph.via_of(edge) == "stairs":
			var s := -1 if RouteGraph.side_of(edge) == "left" else 1
			holes[s] = _stairwell_hole(seg, edge, road, s)
			holes_up[s] = _graph.tier_of(StringName(edge["to"])) > _graph.tier_of(seg["id"])
			bands[s] = _stairwell_band(seg, edge, road)
	road["holes"] = holes
	road["holes_up"] = holes_up
	road["hole_bands"] = bands


## The ground a stairwell leaving `seg` by `edge` covers as it crosses `road`, from its door on and
## 5 cm in from its walls' outer faces (so whatever meets it runs on under them): (x across, metres
## along `road`) in `road`'s first leg, as _stairwell_hole works it out. (Starting a metre before
## the stairwell, it would take the floor out in front of the door too, where the stairwell has
## none.) It starts 5 cm into `road`: the road before it, which it also crosses, isn't cut, so a cut
## meeting the joint between them would leave a point in the middle of that road's end, and a
## hairline crack there under the PS1 vertex snap (see _cut_ground).
func _stairwell_band(seg: Dictionary, edge: Dictionary, road: Dictionary) -> PackedVector2Array:
	var to_road: Transform3D = (road["node"].transform as Transform3D).affine_inverse() * _frame_after(seg, edge)
	var lane_x := _player.lane_x(_handover_lanes(edge).y)
	var hw := tuning.lane_width / 2.0 + 0.2
	var band := PackedVector2Array()
	for p in [Vector3(lane_x - hw, 0, -0.2), Vector3(lane_x + hw, 0, -0.2), Vector3(lane_x + hw, 0, -30.0), Vector3(lane_x - hw, 0, -30.0)]:
		var q: Vector3 = to_road * p
		band.append(Vector2(q.x, -q.z))
	var on := PackedVector2Array([Vector2(-1000.0, 0.05), Vector2(1000.0, 0.05), Vector2(1000.0, 1000.0), Vector2(-1000.0, 1000.0)])
	var cut := Geometry2D.intersect_polygons(band, on)
	return cut[0] if not cut.is_empty() else PackedVector2Array()


## Where the ground of `seg`, the straight road on past a fork, is laid cut round the stairwells
## that go down out of that fork and cross it (_cut_ground): its first `x` metres, left out of the
## floor's first piece (_build_surfaces), which ends at `y`. ZERO if there are none (or the cut
## wouldn't fit before its first bend or an outdoor stretch, or the road's a catwalk bridge or an
## open deck: their walls lay no cut ground, so those metres would be left a hole in the floor).
func _ground_cut(seg: Dictionary) -> Vector2:
	var theme := _theme(seg["id"])
	if seg["ramp_len"] > 0.0 or theme.get("bridge", false) or theme.get("open_deck", false):
		return Vector2.ZERO
	var reach := 0.0
	var bands: Dictionary = seg.get("hole_bands", {})
	for s in bands:
		if seg.get("holes_up", {}).get(s, false) or (bands[s] as PackedVector2Array).size() < 3:
			continue
		var out := _roof_reach(seg["id"], s) + 0.15  # the road, its kerb (or roof edge) and the wall line
		var ground := PackedVector2Array([Vector2(-out, 0.0), Vector2(out, 0.0), Vector2(out, seg["length"]), Vector2(-out, seg["length"])])
		for poly in Geometry2D.intersect_polygons(bands[s], ground):
			for p in poly:
				reach = maxf(reach, p.y)
	if reach <= 0.0:
		return Vector2.ZERO
	reach += 0.05
	var first := _pieces_except(seg, 0.0, seg["length"], _outdoor(seg))
	if first.is_empty() or first[0].x > 0.001 or first[0].y < reach + 0.5:
		return Vector2.ZERO
	return Vector2(reach, first[0].y)


## The road's hole plugs (_hole_plug), by side: one hidden node in `parent` for each side wall a
## stairwell passes out through, for what walls up its hole while the stairwell isn't there.
func _make_plugs(parent: Node3D, seg: Dictionary) -> Dictionary:
	var plugs := {}
	for side in [-1, 1]:
		var hole: Vector2 = seg.get("holes", {}).get(side, Vector2.ZERO)
		if hole.y > hole.x:
			var plug := Node3D.new()
			plug.name = _plug_name(side)
			plug.visible = false
			parent.add_child(plug)
			plugs[side] = plug
	return plugs


## A flat strip of ground over [a, b] along `seg` (one piece of it, so on one leg: _pieces), from x0
## to x1 across, `y` up, cut round the stairwells down out through it (seg["hole_bands"]): the parts
## beside them in `parent`, the part over each in its plug (`plugs`, by side). Textured as a whole
## strip of it would be (_strip): `tiles_x` across, a tile every `tile_len` along, from the end of
## the piece it's part of (`end`), so the pattern carries straight on into the rest. In cells as
## wide as that strip's (_plane) and up to a metre long, so no triangle is big enough for the PS1
## texturing to warp, and each piece has the same points along its edges as whatever it meets
## there: a point in the middle of a neighbour's edge left a hairline crack of the void beside it
## under the PS1 vertex snap (across the kerb where a stairwell's hole started, once the hole was
## walled up). For the same reason an end at a bend (or just short of one) is cut on the corner's
## line, as a strip's is (_mitre), to meet the next leg's ground on the same points.
func _cut_ground(parent: Node3D, plugs: Dictionary, seg: Dictionary, a: float, b: float, x0: float, x1: float, y: float,
		tex: Texture2D, tiles_x: float, tile_len: float, end: float) -> void:
	var leg := _leg_index(seg, (a + b) / 2.0)
	var bands := {}
	for s in seg.get("hole_bands", {}):
		if not seg.get("holes_up", {}).get(s, false) and (seg["hole_bands"][s] as PackedVector2Array).size() >= 3:
			bands[s] = _band_on_leg(seg, leg, seg["hole_bands"][s])
	var beside: Array[PackedVector2Array] = []
	var over := {}
	for s in bands:
		over[s] = []
	var reach := maxf(absf(x0), absf(x1))  # (how far out the strip goes, as _strip gives _mitre)
	var bent := _near_bend(seg, leg, a, b, reach)
	var cols := maxi(1, ceili((x1 - x0) / 2.0 - 0.01))
	var rows := maxi(1, ceili(b - a - 0.01))
	for r in rows:
		var r0 := lerpf(a, b, float(r) / rows)
		var r1 := lerpf(a, b, float(r + 1) / rows)
		for c in cols:
			var c0 := lerpf(x0, x1, float(c) / cols)
			var c1 := lerpf(x0, x1, float(c + 1) / cols)
			var cell := PackedVector2Array([Vector2(c0, r0), Vector2(c1, r0), Vector2(c1, r1), Vector2(c0, r1)])
			if bent:
				# (Its first two points are on a row that may be the piece's first, the last two on one
				# that may be its last.)
				for k in 4:
					var row := (-1 if r == 0 else 0) if k < 2 else (1 if r == rows - 1 else 0)
					cell[k] = Vector2(cell[k].x, _mitred(seg, leg, a, b, reach, cell[k].x, cell[k].y, row))
			var left: Array[PackedVector2Array] = [cell]
			for s in bands:
				var rest: Array[PackedVector2Array] = []
				for poly in left:
					rest.append_array(Geometry2D.clip_polygons(poly, bands[s]))
					(over[s] as Array).append_array(Geometry2D.intersect_polygons(poly, bands[s]))
				left = rest
			beside.append_array(left)
	var uv := func(p: Vector2) -> Vector2: return Vector2((p.x - x0) / (x1 - x0) * tiles_x, (end - p.y) / tile_len)
	_flat_polys(parent, seg, leg, beside, y, tex, uv)
	for s in over:
		if plugs.has(s):
			_flat_polys(plugs[s], seg, leg, over[s], y, tex, uv)


## A stairwell's band (_stairwell_band: x across, metres along the road's first leg) as the same
## ground in leg i's own terms (x across it, metres along the road on it).
static func _band_on_leg(seg: Dictionary, i: int, band: PackedVector2Array) -> PackedVector2Array:
	if i == 0:
		return band
	var leg: Dictionary = seg["legs"][i]
	var to_leg: Transform3D = (leg["xf"] as Transform3D).affine_inverse() * (seg["legs"][0]["xf"] as Transform3D)
	var out := PackedVector2Array()
	for p in band:
		var q := to_leg * Vector3(p.x, 0.0, -p.y)
		out.append(Vector2(q.x, float(leg["start"]) - q.z))
	return out


## Is a piece [a, b] of leg i at a bend, or just short of one, so _mitre would cut its ends on the
## corner's line (a strip reaching `reach` out from the centre line)? See _mitred.
static func _near_bend(seg: Dictionary, i: int, a: float, b: float, reach: float) -> bool:
	var legs: Array = seg["legs"]
	var ta := tan(_turn_at(seg, i) / 2.0)
	var tb := tan(_turn_at(seg, i + 1) / 2.0)
	var e: float = legs[i + 1]["start"] if i + 1 < legs.size() else INF
	return (absf(ta) > 1e-4 and a - float(legs[i]["start"]) < reach * absf(ta) + 0.01) \
			or (absf(tb) > 1e-4 and e - b < reach * absf(tb) + 0.01)


## Where a point `x` across, `into` along a piece [a, b] of leg i goes once the piece's ends are cut
## on the corners' lines, by _mitre's rule for a strip reaching `reach` out from the centre line:
## on its first row (`row` -1) onto the line at a bend at a, on its last (`row` 1) onto the line
## at a bend at b, and anywhere between (`row` 0) kept from running past either line. Away from
## any bend, where it was.
static func _mitred(seg: Dictionary, i: int, a: float, b: float, reach: float, x: float, into: float, row: int) -> float:
	var legs: Array = seg["legs"]
	var s: float = legs[i]["start"]
	var e: float = legs[i + 1]["start"] if i + 1 < legs.size() else INF
	var ta := tan(_turn_at(seg, i) / 2.0)
	var tb := tan(_turn_at(seg, i + 1) / 2.0)
	var near_a := absf(ta) > 1e-4 and a - s < reach * absf(ta) + 0.01
	var near_b := absf(tb) > 1e-4 and e - b < reach * absf(tb) + 0.01
	if not (near_a or near_b):
		return into
	var lo := a
	var hi := b
	if near_a:
		lo = s - x * ta if absf(a - s) < 0.005 else maxf(a, s - x * ta)
	if near_b:
		hi = e + x * tb if absf(b - e) < 0.005 else minf(b, e + x * tb)
	hi = maxf(hi, lo)
	if row < 0:
		return lo
	if row > 0:
		return hi
	return clampf(into, lo, hi)


## The floor's first metres past a stairwell down out of the fork before this road, left out of the
## floor laid in _build_surfaces (seg["ground_cut"]), laid here cut round it (_cut_ground), the part
## over it in the hole's plug: so the steps show through the open door, and with the stairwell
## gone (or its door locked) the floor's whole.
func _cut_floor(parent: Node3D, plugs: Dictionary, seg: Dictionary) -> void:
	var cut: Vector2 = seg.get("ground_cut", Vector2.ZERO)
	if cut.x <= 0.0:
		return
	var id: StringName = seg["id"]
	var half := tuning.lane_count * tuning.lane_width / 2.0
	_cut_ground(parent, plugs, seg, 0.0, cut.x, -half, half, 0.0, _ground(id), float(tuning.lane_count), _ground_tile(id), cut.y)


## The plugs over the stairwell holes in a road's walls block no sight, as the holes they fill
## never did: marked so _make_solid gives them no block.
func _unsolid_plugs(walls: Node3D) -> void:
	for s in [-1, 1]:
		var plug := walls.get_node_or_null(_plug_name(s))
		if plug:
			for m in plug.find_children("*", "MeshInstance3D", true, false):
				m.set_meta("solid", true)


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


## Where the door into the stairwell out of `seg` by `edge` stands, open or locked (it's in the
## same place either way: _build_locked_stub): a frame in `seg`'s node's space, on the floor in the
## middle of its doorway, its front (+z) toward you. It stands across the outer lane at the split,
## turned toward its side as the stairwell is.
func _stair_door_frame(seg: Dictionary, edge: Dictionary) -> Transform3D:
	var xf := _frame_after(seg, edge)
	var stairs := _segment_shape(StringName(edge["to"]), edge, seg["id"])
	stairs["legs"] = _plan_legs(stairs, xf)
	return (seg["node"].transform as Transform3D).affine_inverse() * xf * _frame_at(stairs, STAIR_DOOR_AT) \
			* Transform3D(Basis.IDENTITY, Vector3(_player.lane_x(_stair_lane(stairs)), 0, 0))


## Builds a segment's walls again with these openings, unless they were built with them already
## (_walls_key).
func _rebuild_walls(seg: Dictionary, open_l: float, open_r: float) -> void:
	var key := _walls_key(seg, open_l, open_r)
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


## The openings and stairwell holes a segment's walls are built with (see _rebuild_walls).
static func _walls_key(seg: Dictionary, open_l: float, open_r: float) -> String:
	return "%s %s" % [Vector2(open_l, open_r), seg.get("holes", {})]


# --- World building -----------------------------------------------------------

## Road, stairs and ceiling for one segment. Walls go in their own node so openings can change.
## The road runs the whole length, up to a fork too (the fork cue only adds its sign), except over
## an outdoor stretch, where the yard's asphalt is the floor (_build_yard): laid over the road a
## hair up, the two fought for the whole yard (the user's corners).
func _build_surfaces(parent: Node3D, seg: Dictionary, open_l: float, open_r: float) -> void:
	var id: StringName = seg["id"]
	var length: float = seg["length"]
	var ramp: float = seg["ramp_len"]
	var road_w := tuning.lane_count * tuning.lane_width
	var theme := _theme(id)
	var via := RouteGraph.via_of(seg["edge"])

	# Past a stairwell down out of the fork before this road, its first metres of floor are laid
	# with its walls, cut round the stairwell (_cut_ground): left whole, the floor ran on through the
	# top of the flight, a flat floor over the first steps seen through the door as you opened it,
	# as the floor at the top of the stairs up had stuck in (user: "I think the floor still sticks in
	# at the top of the stairs going up").
	var cut := _ground_cut(seg)
	seg["ground_cut"] = cut
	for piece in _pieces_except(seg, 0.0, length, _outdoor(seg)):
		if cut.x > 0.0 and piece.x < cut.x:
			piece.x = cut.x
		var on_ramp: bool = piece.y <= ramp + 0.001 and ramp > 0.0
		if on_ramp and via == "ladder":
			# A ladder is a single lane, with a drop either side of it.
			var lane := 0 if RouteGraph.side_of(seg["edge"]) == "left" else tuning.lane_count - 1
			_strip(parent, seg, piece.x, piece.y, _player.lane_x(lane), tuning.lane_width, 0.0, PsxTextures.stairs(), 1.0)
		elif on_ramp:
			# Stairs are one lane wide, in the lane you took them from (user decision): on 5 cm in
			# under the stairwell's walls each side (a slot down each side showed the void under
			# the flight: the user's gaps). On the stairwell's render layer: just out at the bottom of
			# a flight down, the camera leaves the stairwell out, and the last steps stood up bare out
			# of the landing's floor behind you (the user's stairs).
			_strip(parent, seg, piece.x, piece.y, _player.lane_x(_stair_lane(seg)), tuning.lane_width + 0.1, 0.0, PsxTextures.stairs(), 1.0) \
					.layers = STAIRWELL_LAYER
		else:
			_strip(parent, seg, piece.x, piece.y, 0.0, road_w, 0.0, _ground(id), float(tuning.lane_count), _ground_tile(id))
	if _is_stairs(seg):
		_build_stairwell(parent, seg)
		_build_landing(parent, seg)
	# At the bends the floor and ceiling strips are mitred, so the outside of the corner has no gap
	# to fill (_mitre). The patches that filled it, 2 cm under the floor and over the ceiling,
	# showed through in shards under the PS1 vertex snap: the user's corner popping, and one stuck
	# in at the top of the stairs up to the ROOFTOPS ("I think the floor still sticks in at the top
	# of the stairs going up"). They also stood behind the hairline cracks the snap opens along the
	# floor's and ceiling's edges, the kerbs and the bend's joining wall and pillar. So round each
	# bend there's still a floor under the floor and a ceiling over the ceiling, but 0.15 m away (as
	# far as the walls run on past them, _wall), where the snap can't bring them through (it would
	# take 45 m off, deep in the fog): only those cracks show them. Mitred too, they don't overlap.
	# (Not quite out to the wall line on a roof: past its edge they'd stick out of the building. No
	# ceiling one behind glass walls: you'd see its edge through them.)
	var walled: bool = not theme.get("no_walls", false)
	var back_w := road_w + (2.3 if walled else 1.8)
	var legs: Array = seg["legs"]
	for k in range(1, legs.size()):
		var j: float = legs[k]["start"]
		if j < ramp or j >= length:  # (a locked stub is cut short of its bends)
			continue
		var from := maxf(maxf(j - 3.0, float(legs[k - 1]["start"])), ramp)
		var to := minf(minf(j + 3.0, length), float(legs[k + 1]["start"]) if k + 1 < legs.size() else length)
		for span in [Vector2(from, j), Vector2(j, to)]:
			if span.y - span.x < 0.05:
				continue
			var outdoor := _is_outdoor(seg, (span.x + span.y) / 2.0)
			_strip(parent, seg, span.x, span.y, 0.0, back_w, -0.15, PsxTextures.yard_asphalt() if outdoor else _ground(id),
					tuning.lane_count * back_w / road_w, _ground_tile(id))
			if theme.get("ceiling", false) and not outdoor and not theme.get("glass_walls", false):
				_strip(parent, seg, span.x, span.y, 0.0, back_w, _ceil(id) + 0.15, _ceiling_texture(theme), back_w / 2.0, 2.0, true)
	if theme.get("ceiling", false):
		for span in _cut_spans([Vector2(ramp, length)], _outdoor(seg)):  # open sky over any outdoor stretch
			for piece in _pieces(seg, span.x, span.y):
				# (The walls run on 0.15 m above it, so its edges don't just meet their tops: see _wall.)
				_strip(parent, seg, piece.x, piece.y, 0.0, road_w + 2.0, _ceil(id),
						_ceiling_texture(theme), road_w / 2.0, 2.0, true)
	var walls := Node3D.new()
	walls.name = "Walls"
	parent.add_child(walls)
	seg["open"] = Vector2(open_l, open_r)
	seg["walls_key"] = _walls_key(seg, open_l, open_r)  # (so _cut_openings doesn't build them all again)
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
## `tuck`: it runs on that far under the floor and over its top as well, as the walls do (_wall),
## its line-of-sight block staying h tall.
func _join_bends(parent: Node3D, seg: Dictionary, side: int, wx: float, from: float, h: float, mat: Material,
		tuck: float = 0.0) -> void:
	for k in range(1, seg["legs"].size()):
		var j: float = seg["legs"][k]["start"]
		if j < from or _is_outdoor(seg, j):
			continue
		var m := _join_at(parent, seg, k, wx, -tuck, h + 2.0 * tuck, mat)
		if m and tuck > 0.0:
			m.set_meta("solid", true)
			_solid_box(m, Transform3D.IDENTITY, Vector3(0.25, h, (m.mesh as BoxMesh).size.z))


## The join at bend k (see _join_bends): from y0 up, h tall, at wx across. Returns it, or null if
## the two legs' ends meet there anyway.
func _join_at(parent: Node3D, seg: Dictionary, k: int, wx: float, y0: float, h: float, mat: Material) -> MeshInstance3D:
	var j: float = seg["legs"][k]["start"]
	var a := _frame_in_leg(seg, k - 1, j) * Vector3(wx, 0, 0)
	var b := _frame_in_leg(seg, k, j) * Vector3(wx, 0, 0)
	var l := a.distance_to(b)
	if l < 0.05:
		return null
	var m := _box(parent, Vector3(0.25, h, l + 0.3), Vector3.ZERO, Color.WHITE)
	m.material_override = mat
	m.transform = Transform3D(Basis.looking_at((b - a).normalized(), Vector3.UP), (a + b) / 2.0 + Vector3(0, y0 + h / 2.0, 0))
	return m


## Kerbs, walls and pillars either side, leaving the first open_l / open_r metres open.
func _build_walls(parent: Node3D, seg: Dictionary, open_l: float, open_r: float) -> void:
	var length: float = seg["length"]
	var ramp: float = seg["ramp_len"]
	var road_w := tuning.lane_count * tuning.lane_width
	var theme := _theme(seg["id"])
	var h: float = theme["height"]
	var wall_tex := _wall_texture(theme)
	var via := RouteGraph.via_of(seg["edge"])
	if theme.get("bridge", false):  # the GANTRY: a catwalk bridge, nothing under it but the drop
		_build_gantry_bridge(parent, seg, ramp)
		return
	if theme.get("no_walls", false):
		_build_roof_edges(parent, seg, open_l, open_r)
		return
	if theme.get("open_deck", false):
		_build_helipad(parent, seg, ramp)
		return
	var plugs := _make_plugs(parent, seg)
	_cut_floor(parent, plugs, seg)
	var tuck := 0.05 if theme.get("glass_walls", false) else 0.15  # (the kerb's, under the wall: see below)
	for side in [-1, 1]:
		var open := open_l if side < 0 else open_r
		var wx: float = side * (road_w / 2.0 + 1.0)
		var hole: Vector2 = seg.get("holes", {}).get(side, Vector2.ZERO)
		var down: bool = hole.y > hole.x and not seg.get("holes_up", {}).get(side, false)
		# Past a stairwell down out through this wall, the kerb's first metres are laid cut round it
		# (_cut_ground), with the floor's (_cut_floor); the rest as a strip, from where they stop.
		var cut_to: float = seg.get("ground_cut", Vector2.ZERO).x if down else 0.0
		if cut_to <= open:
			cut_to = 0.0
		var kerb_end := length  # (where the kerb piece the cut runs into ends, for its texture)
		var kerb_x := Vector2(minf(side * (road_w / 2.0 - 0.1), side * (road_w / 2.0 + 1.0 + tuck)),
				maxf(side * (road_w / 2.0 - 0.1), side * (road_w / 2.0 + 1.0 + tuck)))  # (across, from and to)
		# An opening in this wall with a room behind it (the canteen's kitchen, the dock's bays), as
		# well as any stairwell hole.
		var alcoves: Array[Dictionary] = []
		for a in _alcoves(seg, side):
			var sp: Vector2 = a["span"]
			if not (sp.x < hole.y + 1.0 and sp.y > hole.x - 1.0):  # one running into a stairwell: leave the wall whole there
				alcoves.append(a)
		var spans := _wall_spans(open, length, hole)
		for a in alcoves:
			spans = _cut_spans(spans, a["span"])
			# The canteen's kitchen and the STORM DRAIN's ledges have no floor of their own between
			# the road and the opening: the kerb runs on across them, up to the wall's line (the
			# kitchen's floor and the channel wall start there), or it's a hole down to the void.
			if String(a["kind"]) in ["kitchen", "ledge"]:
				for piece in _pieces(seg, a["span"].x, a["span"].y):
					if not (piece.y <= ramp + 0.001 and ramp > 0.0):
						_strip(parent, seg, piece.x, piece.y, side * (road_w / 2.0 + 0.425), 1.15, 0.02, PsxTextures.concrete(), 1.15, 2.0)
		for span in _cut_spans(spans, _outdoor(seg)):
			for piece in _pieces(seg, span.x, span.y):
				var on_ramp: bool = piece.y <= ramp + 0.001 and ramp > 0.0
				if on_ramp:
					continue  # a ladder has none (you see the drop); stairs have their own stairwell
				# The kerb: 0.1 m over the road's edge and 0.15 m on under the wall, so neither edge
				# just meets the next surface (it showed a sparkling hairline of the outside, the
				# whole length of every corridor: the user's gaps). (Under a glass wall, only as far as
				# its skirting hides it.)
				for k in _cut_spans([piece], Vector2(open, cut_to) if cut_to > 0.0 else Vector2.ZERO):
					_strip(parent, seg, k.x, k.y, side * (road_w / 2.0 + (0.9 + tuck) / 2.0), 1.1 + tuck, 0.02, PsxTextures.concrete(), 1.1 + tuck, 2.0)
					if cut_to > 0.0 and absf(k.x - cut_to) < 0.001:
						kerb_end = k.y
				if theme.get("glass_walls", false):
					_glass_wall(parent, seg, piece.x, piece.y, wx, side, h)
				else:
					_wall(parent, seg, piece.x, piece.y, wx, side, h, wall_tex)
		# Where a stairwell passes out through this wall: what walls up the hole once the stairwell's
		# gone (_despawn_behind), built now with the wall and hidden, so nothing's rebuilt mid-run:
		# the wall over it (3 cm out, running on behind the wall either side, so no seam opens), the
		# kerb (and floor) under the tube, and any pillar it left out. None of it blocks sight (see
		# the end).
		var plug: Node3D = plugs.get(side)
		if cut_to > 0.0:
			# Down a stairwell, the kerb runs up to the tube's walls (under them), not across: there it
			# would stand across the top of the flight, inside. Cut off square at the hole, it left a
			# wedge of the void in the floor beside the tube, at the bottom of the screen (the SECURITY
			# WING's and the LOADING DOCK's first metres: the user's gaps). The part under the tube is
			# the plug's. And it's cut from the start of the road on (the tube crosses the kerb before
			# the hole, and stood up through it over the first steps), to past the tube, so no piece of
			# it ends at the hole with a point in the middle of the next one's end.
			_cut_ground(parent, plugs, seg, open, cut_to, kerb_x.x, kerb_x.y, 0.02, PsxTextures.concrete(), 1.1 + tuck, 2.0, kerb_end)
		if plug:
			# Behind the wall at the hole's far end the wall over it runs on a metre: 15 cm wasn't
			# enough, and a line of sight from far back, grazing the wall, slipped between the two
			# there (a slit of the void beside the floating padlock, with the door locked).
			var leg_end: float = length
			for leg in seg["legs"]:
				if leg["start"] > hole.y:
					leg_end = minf(leg_end, leg["start"])
			var o := _outdoor(seg)
			if o != Vector2.ZERO and o.x >= hole.y:
				leg_end = minf(leg_end, o.x)
			var run_on := 0.15 if theme.get("glass_walls", false) else 1.0  # (through glass you'd see it)
			for span in _cut_spans([Vector2(maxf(hole.x, open), minf(hole.y, length))], _outdoor(seg)):
				for piece in _pieces(seg, span.x, span.y):
					if piece.y <= ramp + 0.001 and ramp > 0.0:
						continue
					if not down:
						# Up a stairwell, the kerb runs on across the hole (it was cut with the wall, and
						# you looked down past the tube into the drop: the user's gaps). Under the tube it's
						# under the flight, which climbs away above it.
						_strip(parent, seg, piece.x, piece.y, side * (road_w / 2.0 + 0.525), 1.25, 0.02, PsxTextures.concrete(), 1.25, 2.0)
					elif cut_to <= 0.0:
						# (No room to cut it from the start: just across the hole, the part under the tube the plug's.)
						_cut_ground(parent, plugs, seg, piece.x, piece.y, kerb_x.x, kerb_x.y, 0.02, PsxTextures.concrete(), 1.1 + tuck, 2.0, piece.y)
					var a := piece.x - 0.15 if is_equal_approx(piece.x, hole.x) and hole.x - 0.15 >= open else piece.x
					var b := piece.y
					if is_equal_approx(piece.y, hole.y):
						b = maxf(piece.y, minf(hole.y + run_on, leg_end))
					if theme.get("glass_walls", false):
						_glass_wall(plug, seg, a, b, wx + side * 0.03, side, h)
					else:
						_wall(plug, seg, a, b, wx + side * 0.03, side, h, wall_tex, false)
		# At every bend, a short wall joins the two legs' walls, so no gap shows the outside. It runs
		# on into the floor and ceiling as the walls do: just meeting them, it showed hairlines of the
		# void at its foot and top under the PS1 vertex snap, once the bend patches no longer stood
		# behind them (the user's corners).
		_join_bends(parent, seg, side, wx, maxf(open, ramp), h, PsxMaterials.textured(wall_tex, Vector2(1, h / 2.0)), 0.15)
		if theme.get("glass_walls", false):
			# Out through the glass, the city backdrop joined the same way (it parted in a wedge at the
			# MAIN FLOOR EXIT's bends, sky and void showing through: the user's gaps). Only for looks.
			var city := PsxMaterials.textured(PsxTextures.city_backdrop(), Vector2(1, 1), true)
			for k in range(1, seg["legs"].size()):
				var j: float = seg["legs"][k]["start"]
				if j >= maxf(open, ramp) and not _is_outdoor(seg, j):
					var cj := _join_at(parent, seg, k, side * (road_w / 2.0 + 11.0), -0.5, 7.5, city)
					if cj:
						cj.set_meta("solid", true)
		# Pillars every 5 m, alternating light and dark, give a sense of speed. Big ones hide bend corners.
		var ph := maxf(h, 1.2)
		var every: int = int(theme.get("pillar_every", 5))
		for i in range(ceili(maxf(open, ramp) / float(every)) * every, int(length), every):
			var in_alcove := false
			for a in alcoves:
				if i > a["span"].x - 0.5 and i < a["span"].y + 0.5:
					in_alcove = true
			if in_alcove or _is_outdoor(seg, i) \
					or (theme.get("mezzanine", false) and side < 0 and i > 34 and i < 50):  # the lobby's grand staircase
				continue
			var holder := parent
			if i > hole.x - 0.5 and i < hole.y + 0.5:
				# Where a stairwell passes out: in the hole's plug, if any (none at 0, hole or not).
				if plug == null or i < 1:
					continue
				holder = plug
			if theme.has("pillar_tex"):  # big textured pillars (the MAIN FLOOR EXIT's granite)
				_item_box(holder, seg, i, Vector3(side * (road_w / 2.0 + 0.6), ph / 2.0, 0), Vector3(0.8, ph, 0.8), Color.WHITE).material_override = \
						PsxMaterials.textured(_obstacle_texture(theme["pillar_tex"]), Vector2(1, ph / 2.0))
				continue
			var c: Color = theme["color"].lightened(0.25) if (i / 5) % 2 == 0 else theme["color"].darkened(0.5)
			_item_box(holder, seg, i, Vector3(side * (road_w / 2.0 + 0.8), ph / 2.0, 0), Vector3(0.35, ph, 0.35), c)
		for k in range(1, seg["legs"].size()):
			var j: float = seg["legs"][k]["start"]
			if j >= maxf(open, ramp) and not _is_outdoor(seg, j):
				# (Into the floor and ceiling too, like the join; its line-of-sight block as it was.)
				var bp := _item_box(parent, seg, j, Vector3(side * (road_w / 2.0 + 1.0), ph / 2.0, 0), Vector3(1.0, ph + 0.3, 1.0), theme["color"].darkened(0.5))
				bp.set_meta("solid", true)
				_solid_box(bp, Transform3D.IDENTITY, Vector3(1.0, ph, 1.0))
				# At the bend just past the bottom of a flight down, the pillar on the stairwell's side (the
				# inside of the turn) swung back beside the exit door: it stood half in the doorway, a
				# dark slab filling the side of the screen as you burst out, and the stairwell's camera
				# sat inside it (the user's stairs). The walls close that corner anyway, so it isn't
				# drawn there. (Its line-of-sight block stays, as it always was.)
				if _is_stairs(seg) and j < ramp + 3.0 and side * _player.lane_x(_stair_lane(seg)) > 0.0:
					bp.visible = false
		# Where this area's wall takes over from the last one's (its start, or the end of the stairs
		# up or down into it), a pilaster over the joint: the two walls only butted there, and a
		# hairline of the outside showed up the corner (the user's gaps). Only for looks: it's left
		# out of line of sight, so nothing in play changes.
		var w0 := maxf(0.0, ramp)
		var in_alcove0 := false
		for a in alcoves:
			if a["span"].x < w0 + 0.6:
				in_alcove0 = true
		var hole0 := hole.y > hole.x and hole.x < w0 + 0.6 and hole.y > w0 - 0.6
		if open <= w0 + 0.01 and not hole0 and not in_alcove0 and not _is_outdoor(seg, w0):
			var pil := _item_box(parent, seg, w0, Vector3(side * (road_w / 2.0 + 1.0), ph / 2.0, 0), Vector3(0.5, ph + 0.3, 0.5), Color.WHITE)
			pil.material_override = PsxMaterials.textured(_obstacle_texture(theme["pillar_tex"]) if theme.has("pillar_tex") else wall_tex, Vector2(1, (ph + 0.3) / 2.0))
			pil.set_meta("solid", true)
		if theme.get("wall_decor", false):
			var first := parent.get_child_count()
			_wall_decor(parent, seg, side, maxf(open, ramp), length)
			if hole.y > hole.x:
				# Nothing on the wall where a stairwell passes out through it: an office window, a steel
				# door and its card reader hung in the open hole, slicing through the stairwell beside
				# its door (the user's stairs). Built and hidden, so line of sight is as it was.
				for c in parent.get_children().slice(first):
					if c is Node3D:
						var at := _into_of(seg, (c as Node3D).position)
						if at > hole.x - 1.0 and at < hole.y + 1.0:
							(c as Node3D).visible = false
		# Each room is built a straight piece at a time: the road can turn under one (an authored bend is
		# kept clear of rooms, but an area heading for the end angles back to the centre line).
		var rooms: Array[Dictionary] = []
		for a in alcoves:
			for pc in _pieces(seg, a["span"].x, a["span"].y):
				rooms.append({"span": pc, "kind": a["kind"]})
		for a in rooms:
			match String(a["kind"]):
				"bay":
					_build_bay(parent, seg, side, a["span"])
				"boiler":
					_build_boiler_bay(parent, seg, side, a["span"])
				"channel":
					_build_sewer_channel(parent, seg, side, a["span"])
				"pumps":
					_build_boiler_bay(parent, seg, side, a["span"], true)
				"basin":
					_build_sewer_channel(parent, seg, side, a["span"], true)
				"ledge":
					_build_drain_side(parent, seg, side, a["span"])
				_:
					_build_kitchen(parent, seg, side, a["span"])
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
	if theme.get("drain_water", false):
		_drain_water(parent, seg)
	if theme.get("overhead", "") == "pump":
		_pump_overhead(parent, seg, ramp)
	if theme.get("overhead", "") == "service":
		_service_overhead(parent, seg, ramp)
	if theme.get("ceiling_vents", false):
		_ceiling_vents(parent, seg, ramp)
	if theme.get("litter", false):
		_canteen_litter(parent, seg, ramp)
	_unsolid_plugs(parent)
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
## `mouth`: only its way in, its door shut (a locked stairs door: _build_locked_stub).
func _build_stairwell(outer: Node3D, seg: Dictionary, mouth: bool = false) -> void:
	# All of it on its own render layer: as you burst out, the camera leaves it out while it pulls
	# back to its normal spot behind you (which is inside this stairwell for a few metres).
	var parent := Node3D.new()
	parent.name = "Stairwell"
	outer.add_child(parent)
	_build_stairwell_parts(parent, seg, mouth)
	_make_solid(parent)  # its walls, slabs and doors (not the sheared inner tube)
	_set_render_layer(parent, STAIRWELL_LAYER)


## Just out of a stairwell, the play camera 5.5 m behind you is still back over the end of the
## flight, where the area itself hasn't started (its floor, walls and ceiling begin where the
## stairs end), with the stairwell left out (_update_camera): it looked out into the night sky
## above and the void below, and on the roof the building's lit front showed under it (the user's
## stairs and gaps). So the area carries on back round it for those few metres, flat at the
## landing's height: its floor, kerbs, walls and ceiling; on a roof, its roofing out to the lip,
## and the building's front below. It's only shown then (_update_camera): any other time it would
## stand through the stairwell, and through the area you came from.
func _build_landing(outer: Node3D, seg: Dictionary) -> void:
	var landing := Node3D.new()
	landing.name = "Landing"
	outer.add_child(landing)
	landing.visible = false
	seg["landing"] = landing  # (found by _update_camera every frame just out, without a lookup by name)
	var id: StringName = seg["id"]
	var theme := _theme(id)
	var ramp: float = seg["ramp_len"]
	var y: float = seg["dy"]  # the landing's height
	var road_w := tuning.lane_count * tuning.lane_width
	var half := road_w / 2.0 + 1.0
	# Back to behind the camera, and on 0.3 m under the area's own surfaces (a hair below or
	# behind them, so the two never fight), so no edge just meets another.
	for piece in _pieces(seg, maxf(0.0, ramp - 6.6), ramp + 0.3):
		var under := piece.x > ramp - 0.001
		if theme.get("no_walls", false):
			_flat_strip(landing, seg, piece, 0.0, road_w, y - 0.01, _ground(id), float(tuning.lane_count), _ground_tile(id))
			for side in [-1, 1]:
				var wide: float = theme.get("wide_roof", 0.0) if int(theme.get("wide_side", side)) == side else 0.0
				var edge := half + wide
				var strip_tex := _ground(id) if theme.get("railing", false) or theme.get("low_wall", false) else PsxTextures.gravel()
				_flat_strip(landing, seg, piece, side * (road_w / 2.0 + (1.0 + wide) / 2.0), 1.0 + wide, y - 0.01, strip_tex,
						(1.0 + wide) / tuning.lane_width, tuning.lane_width)
				if under:
					continue
				var mid := (piece.x + piece.y) / 2.0
				var l := piece.y - piece.x
				var lip: float = theme.get("lip", 0.3)
				var lip_box := _item_box(landing, seg, mid, Vector3(side * (edge - 0.1), y + lip / 2.0 - _height(seg, mid), 0), Vector3(0.34, lip, l + 0.2), Color("5e5e58"))
				if theme.get("low_wall", false):
					lip_box.material_override = PsxMaterials.textured(PsxTextures.concrete(), Vector2(maxf(1.0, l / 2.0), 1))
				var front := _flat_wall(landing, seg, piece, side * edge, side, y - 30.0, y)
				front.material_override = PsxMaterials.textured(PsxTextures.building_night(), Vector2(l / 4.0, 30.0 / 4.0), true)
		else:
			var h: float = theme["height"]
			_flat_strip(landing, seg, piece, 0.0, road_w + 2.0, y - 0.01, _ground(id), tuning.lane_count * (road_w + 2.0) / road_w, _ground_tile(id))
			_flat_strip(landing, seg, piece, 0.0, road_w + 2.0, y + _ceil(id) + 0.01, _ceiling_texture(theme), road_w / 2.0, 2.0, true)
			var tex := _wall_texture(theme)
			for side in [-1, 1]:
				if not under:
					_flat_strip(landing, seg, piece, side * (road_w / 2.0 + 0.525), 1.25, y + 0.02, PsxTextures.concrete(), 1.25, 2.0)
				var wall := _flat_wall(landing, seg, piece, side * (half + 0.01), side, y - 0.15, y + h + 0.15)
				var rows := (h + 0.15) / 2.0  # (a tile's bottom row on the floor, as in _wall)
				wall.material_override = PsxMaterials.textured(tex, Vector2((piece.y - piece.x) / 2.0, (h + 0.3) / 2.0), false, Vector2(0, ceilf(rows) - rows))
	_set_render_layer(landing, LANDING_LAYER)


## A flat strip over one piece of a segment at height `y` (from the segment's start), whatever
## the route's slope there; `down` faces it down (a ceiling).
func _flat_strip(parent: Node3D, seg: Dictionary, piece: Vector2, x: float, width: float, y: float, tex: Texture2D,
		tiles_x: float, tile_len: float, down: bool = false) -> MeshInstance3D:
	var mid := (piece.x + piece.y) / 2.0
	var l := piece.y - piece.x
	var m := _plane(parent, Vector2(width, l), Vector3.ZERO, tex, Vector2(tiles_x, l / tile_len))
	m.transform = _frame_at(seg, mid) * Transform3D(Basis(Vector3.FORWARD, PI) if down else Basis.IDENTITY, Vector3(x, y - _height(seg, mid), 0))
	return m


## One flat mesh in the shapes of `polys` (points (x across, metres along) a segment, all on its
## leg `leg`), `y` over the road, facing up, its texture placed by `uv` (a point to its UV, in
## tiles). Nothing if there are none. (Never solid: it's no box or upright plane.)
func _flat_polys(parent: Node3D, seg: Dictionary, leg: int, polys: Array, y: float, tex: Texture2D, uv: Callable) -> void:
	var up: Vector3 = _frame_in_leg(seg, leg, 0.0).basis.y
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for poly: PackedVector2Array in polys:
		var tris := Geometry2D.triangulate_polygon(poly)
		for t in range(0, tris.size(), 3):
			var ids := [tris[t], tris[t + 1], tris[t + 2]]
			var pts: Array[Vector3] = []
			for k in ids:
				pts.append(_frame_in_leg(seg, leg, poly[k].y) * Vector3(poly[k].x, y, 0))
			if (pts[1] - pts[0]).cross(pts[2] - pts[0]).dot(up) > 0.0:  # (a front face winds clockwise)
				ids = [ids[0], ids[2], ids[1]]
				var p1 := pts[1]
				pts[1] = pts[2]
				pts[2] = p1
			for k in 3:
				st.set_normal(up)
				st.set_uv(uv.call(poly[ids[k]]))
				st.add_vertex(pts[k])
			any = true
	if not any:
		return
	var m := MeshInstance3D.new()
	m.mesh = st.commit()
	m.material_override = PsxMaterials.textured(tex)
	parent.add_child(m)


## An upright plane over one piece of a segment, from height y0 to y1 (from the segment's start),
## at `x`, facing the road. (Its material is the caller's.)
func _flat_wall(parent: Node3D, seg: Dictionary, piece: Vector2, x: float, side: int, y0: float, y1: float) -> MeshInstance3D:
	var mid := (piece.x + piece.y) / 2.0
	var l := piece.y - piece.x
	var m := _plane(parent, Vector2(l, y1 - y0), Vector3.ZERO, PsxTextures.concrete(), Vector2.ONE, PlaneMesh.FACE_Z)
	m.transform = _frame_at(seg, mid) * Transform3D(Basis(Vector3.UP, -side * PI / 2.0), Vector3(x, (y0 + y1) / 2.0 - _height(seg, mid), 0))
	return m


func _set_render_layer(node: Node, layer: int) -> void:
	if node is VisualInstance3D:
		node.layers = layer
	for c in node.get_children():
		_set_render_layer(c, layer)


## The stairwell's parts (_build_stairwell). `mouth`: only its way in, for a locked stairs door
## (user, 2026-10-08: "I don't want the locked door to be tucked beside the lane, keep it the same
## as the unlocked door"): its door, shut, in its doorway, the green exit sign over it and the wall
## from it to the side wall, built by the very lines that build an open one's, so open or locked
## the door looks the same and stands in the same place; and the front ends of its side walls (and
## of the roof slab over them, seen only on a roof), as far as the back of the doorway (STAIR_MOUTH),
## their texture as on the whole wall (_cut_to_mouth). Nothing is built behind the door, and nothing
## blocks sight but what an open one's way in blocks there.
func _build_stairwell_parts(parent: Node3D, seg: Dictionary, mouth: bool = false) -> void:
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
	var sight_tops: Array[float] = []  # where its line-of-sight blocks stop (see below)
	for half in 2:
		var indoor: bool = themes[half].get("ceiling", false)
		# The exit half reaches the hall you come out into's own ceiling: down into the PUMP
		# STATION's 7.5 m hall, its end wall stopped at 4.6 m and the hall was open above it
		# (the user's gaps). (The entrance half stays at the usual ceiling: built up to a taller
		# hall's it would stand up through the floor above, and that hall's end wall covers it.)
		var up := _ceil(seg["id"]) if half == 1 else CEILING_Y
		tops.append(_height(seg, ends[half]) + (up if indoor else 3.0))
		# Its walls, end wall and lintel still block sight only up to the usual ceiling, as they
		# always have: the taller wall is only there to be seen.
		sight_tops.append(_height(seg, ends[half]) + (CEILING_Y if indoor else 3.0))
	for half in (1 if mouth else 2):
		var top: float = tops[half]
		var hmat := PsxMaterials.textured(_stair_wall_texture(themes[half]), Vector2(2, 3))
		var hz := ramp * (0.25 + 0.5 * half)  # centre of this half
		var hh := _height(seg, hz)
		for side in [-1, 1]:
			var wall := _item_box(parent, seg, hz, Vector3(x + side * (hw + 0.1), (bottom + top) / 2.0 - hh, 0),
					Vector3(0.2, top - bottom, ramp / 2.0 + 0.2), Color.WHITE)
			wall.material_override = hmat
			if mouth:
				_cut_to_mouth(wall, hz)
			else:
				_sight_as_before(wall, top - sight_tops[half])
		var slab := _item_box(parent, seg, hz, Vector3(x, sight_tops[half] + 0.12 - hh, 0), Vector3(tuning.lane_width + 0.7, 0.24, ramp / 2.0 + 0.3), Color.WHITE)
		slab.material_override = PsxMaterials.textured(PsxTextures.concrete(), Vector2(2, 2))
		# Indoors its underside is the area's own ceiling height, so it only fought the ceiling over
		# the stair door (the user's corners); the tube has its own ceiling inside, and above the
		# area's it's never seen. So only the roof hut shows one. (Hidden, it still blocks sight
		# as it always has: so it stays on the usual ceiling's top, even over a half that now
		# reaches a taller hall's.)
		slab.visible = not themes[half].get("ceiling", false)
		if mouth:
			_cut_to_mouth(slab, hz)
	if mouth:
		_build_stairwell_way_in(parent, seg, x, hw, themes[0], tops[0], sight_tops[0])
		return
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
	# A dim lamp on the ceiling, a little before the exit door. (Just under it: level, its top went
	# up through the sloping ceiling at its low end, and the edge flickered.)
	_item_box(parent, seg, ramp - 1.6, Vector3(x, STAIR_HEADROOM - 0.1, 0), Vector3(0.3, 0.08, 0.3), Color.WHITE).material_override = \
			PsxMaterials.glow(Color("c8b890"))
	var lamp := Node3D.new()
	parent.add_child(lamp)
	lamp.transform = _frame_at(seg, ramp - 1.6) * Transform3D(Basis.IDENTITY, Vector3(x, STAIR_HEADROOM - 0.6, 0))
	_ambience.add_lamp(lamp, Color(1.0, 0.85, 0.6), 5.0)
	_build_stairwell_way_in(parent, seg, x, hw, themes[0], tops[0], sight_tops[0])
	# A green exit sign over the exit door too, on the side you run up to it from.
	_item_box(parent, seg, ramp - 0.38, Vector3(x, DOOR_H + 0.2, 0), Vector3(0.5, 0.15, 0.04), Color.WHITE).material_override = \
			PsxMaterials.glow(Color("40d070"))
	_build_door(parent, seg, ramp - 0.2, x, tops[1], themes[1], sight_tops[1])
	# Built in at the exit too, joined to the walls of the area there.
	var edge := tuning.lane_count * tuning.lane_width / 2.0 + 1.0
	if not themes[1].get("no_walls", false):
		# Exit: an end wall right across the area, side wall to side wall, with the door in it.
		var mat1 := PsxMaterials.textured(_stair_wall_texture(themes[1]), Vector2(3, 2))
		var h1 := _height(seg, ramp - 0.2)
		var wall_h: float = tops[1] - h1
		for span in [Vector2(-edge, x - hw - 0.1), Vector2(x + hw + 0.1, edge)]:
			if span.y - span.x > 0.05:
				var end_wall := _item_box(parent, seg, ramp - 0.2, Vector3((span.x + span.y) / 2.0, wall_h / 2.0, 0), Vector3(span.y - span.x, wall_h, 0.3), Color.WHITE)
				end_wall.material_override = mat1
				_sight_as_before(end_wall, tops[1] - sight_tops[1])


## A stairwell's way in, open or locked (_build_stairwell_parts): the green exit sign over its
## door, on the side you run up to it from; the door itself in its doorway; and, built in, a wall
## closing the gap between the stairwell and the side wall it runs out through (the stairwell is in
## the branch's inside lane: that wall, of the area you take it from, is toward the branch's middle).
## `x`: the stairwell's lane, `hw` its half width, and the area's look and heights at its way in.
func _build_stairwell_way_in(parent: Node3D, seg: Dictionary, x: float, hw: float, theme: Dictionary, top: float,
		sight_top: float) -> void:
	_item_box(parent, seg, 0.02, Vector3(x, DOOR_H + 0.2, 0), Vector3(0.5, 0.15, 0.04), Color.WHITE).material_override = \
			PsxMaterials.glow(Color("40d070"))
	_build_door(parent, seg, STAIR_DOOR_AT, x, top, theme, sight_top)
	if not theme.get("no_walls", false):
		var outward := -1.0 if x > 0.0 else 1.0
		_item_box(parent, seg, STAIR_DOOR_AT, Vector3(x + outward * (hw + 0.2 + 0.75), top / 2.0, 0), Vector3(1.5, top, 0.25), Color.WHITE) \
				.material_override = PsxMaterials.textured(_stair_wall_texture(theme), Vector2(1, 2))


## A locked stairs door's piece of its stairwell's wall or roof slab (_build_stairwell_parts), `m`,
## a box centred `into` metres into the stairwell: cut down to its front end, as far as the back of
## the doorway (STAIR_MOUTH), the rest of it left out (_box_front: its texture as on the whole
## box). It blocks sight as the whole one does there: a box as long as what's left.
func _cut_to_mouth(m: MeshInstance3D, into: float) -> void:
	var size := (m.mesh as BoxMesh).size
	var keep := STAIR_MOUTH - (into - size.z / 2.0)
	m.mesh = _box_front(size, keep)
	m.set_meta("solid", true)
	_solid_box(m, Transform3D(Basis.IDENTITY, Vector3(0, 0, (size.z - keep) / 2.0)), Vector3(size.x, size.y, keep))


## A box's mesh (`size`, as a BoxMesh) cut down to its front (+z) `keep` metres, with its texture
## laid just as on the whole box: what's left looks exactly like that end of the whole one. (A
## BoxMesh's texture runs over each face end to end, so a short one would have it squashed.)
static func _box_front(size: Vector3, keep: float) -> ArrayMesh:
	var box := BoxMesh.new()
	box.size = size
	var a := box.get_mesh_arrays()
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
	var t := keep / size.z
	var back := size.z / 2.0 - keep
	var moved := v.duplicate()
	for i in v.size():
		if v[i].z > 0.0:
			continue
		# A corner on the back end: it comes forward to the cut. On a face that runs along the box,
		# its texture there is what the whole face has at the cut: on from the front corner it pairs
		# with (the same face, across and up), that part of the way to the back.
		for j in v.size():
			if v[j].z > 0.0 and n[j].is_equal_approx(n[i]) and is_equal_approx(v[j].x, v[i].x) and is_equal_approx(v[j].y, v[i].y):
				uv[i] = uv[j].lerp(uv[i], t)
				break
		moved[i].z = back
	a[Mesh.ARRAY_VERTEX] = moved
	a[Mesh.ARRAY_TEX_UV] = uv
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	return mesh


## For a stairwell piece built `taller` metres higher than it used to be (only to be seen): it
## keeps the line-of-sight block it always had, that much lower at the top. (Nothing if it isn't:
## _make_solid gives it its own.)
func _sight_as_before(m: MeshInstance3D, taller: float) -> void:
	if taller < 0.001:
		return
	var size := (m.mesh as BoxMesh).size
	m.set_meta("solid", true)
	_solid_box(m, Transform3D(Basis.IDENTITY, Vector3(0, -taller / 2.0, 0)), Vector3(size.x, size.y - taller, size.z))


## Makes the solid things under `root` (walls, doors, stairwell blocks) block line of sight: an
## invisible collision box on each wall-sized box or upright plane. Skips small fittings, glowing
## lamps and signs, glass (you see through it), and sheared or mirrored pieces (physics can't take
## those). See _sees().
func _make_solid(root: Node) -> void:
	if root is MeshInstance3D:
		_solid_mesh(root)
	for m in root.find_children("*", "MeshInstance3D", true, false):
		_solid_mesh(m)


func _solid_mesh(m: MeshInstance3D) -> void:
	if m.has_meta("solid") or m.material_override is StandardMaterial3D or PsxMaterials.is_glass(m.material_override):
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
## `into0` to `into1` at `y` above the route there, `size_x` across and `size_y` tall. Cut about
## every half metre each way: one 12 m face of two triangles, the stairwell's walls and ceiling
## swam in streaks and bands as its camera panned, under the PS1's affine texturing ("check the
## stairs going up and down for any texture popping", user); cut every metre, the ceiling right
## over the camera still zigzagged. (Its texture is laid as before.)
func _slope_box(parent: Node3D, seg: Dictionary, into0: float, into1: float, x: float, y: float,
		size_x: float, size_y: float) -> MeshInstance3D:
	var f0 := _frame_at(seg, into0)
	var p0 := f0 * Vector3(x, y, 0)
	var p1 := _frame_at(seg, into1) * Vector3(x, y, 0)
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()  # a unit box, stretched and sheared by its transform
	box.subdivide_width = maxi(0, ceili(size_x / 0.5) - 1)
	box.subdivide_height = maxi(0, ceili(size_y / 0.5) - 1)
	box.subdivide_depth = maxi(0, ceili(p0.distance_to(p1) / 0.5) - 1)
	m.mesh = box
	parent.add_child(m)
	var up := f0.basis.y
	m.transform = Transform3D(Basis(f0.basis.x * size_x, up * size_y, p1 - p0), (p0 + p1) / 2.0 + up * size_y / 2.0)
	return m


func _stair_wall_texture(theme: Dictionary) -> Texture2D:
	return _obstacle_texture(theme.get("stair_wall", "roof_hut"))


## A doorway across one lane at `into` (lintel up to `top`), with a door on a hinge that the
## player bursts through (see _doors). Its line of sight is blocked up to `sight_top`.
func _build_door(parent: Node3D, seg: Dictionary, into: float, x: float, top: float, theme: Dictionary,
		sight_top: float) -> void:
	var h := _height(seg, into)
	var parts := _doorway(parent, _frame_at(seg, into), x, top - h, theme, sight_top - h)
	var hinge: Node3D = parts[0]
	var sight: Node3D = parts[1]
	if not seg.get("no_doors", false):  # a locked-down branch's doors never open
		# It flies open flat against the stairwell's wall, without the usual roll: swung on past it,
		# it went 0.3 m out through the wall, and its top corner tipped back through the frame (the
		# user's stairs).
		var door := {"node": hinge, "at": seg["start"] + into, "owner": seg["node"], "seg": seg, "swing": 0.82, "roll": 0.0,
				"sight": sight, "sound": "door_steel" if theme.get("stair_door", "door") == "steel_door" else "door_wood"}
		_doors.append(door)


## A stairwell's doorway, `x` across `frame` (at the floor, its front toward +z): the wall over it
## up to `top`, a frame round it and its door (the area's "stair_door"), shut, on a hinge at its
## left edge. Its line of sight is blocked up to `sight_top` (both heights from the floor there).
## Returns the hinge and the door's line-of-sight block, on a hinge of its own.
func _doorway(parent: Node3D, frame: Transform3D, x: float, top: float, theme: Dictionary, sight_top: float) -> Array[Node3D]:
	var dw := tuning.lane_width - 0.1
	var dh := DOOR_H
	# The wall over the door starts halfway up the frame's top: its underside was level with the
	# frame's, and the two flickered over the doorway in the stairwell's camera (the user's stairs).
	# (It blocks sight from the top of the door up to `sight_top`, as it always has.)
	var lintel := _box(parent, Vector3(tuning.lane_width + 0.3, top - dh - 0.04, 0.25), Vector3.ZERO, Color.WHITE)
	lintel.transform = frame * Transform3D(Basis.IDENTITY, Vector3(x, (dh + 0.04 + top) / 2.0, 0))
	lintel.material_override = PsxMaterials.textured(_stair_wall_texture(theme), Vector2(2, 2))
	lintel.set_meta("solid", true)
	_solid_box(lintel, Transform3D(Basis.IDENTITY, Vector3(0, (sight_top - top) / 2.0 - 0.02, 0)), Vector3(tuning.lane_width + 0.3, sight_top - dh, 0.25))
	# A door frame, so the doorway reads as part of the wall it's in.
	for s in [-1, 1]:
		_box(parent, Vector3(0.08, dh, 0.3), Vector3.ZERO, Color("3a3e42")).transform = \
				frame * Transform3D(Basis.IDENTITY, Vector3(x + s * (dw / 2.0 + 0.04), dh / 2.0, 0))
	_box(parent, Vector3(dw + 0.16, 0.08, 0.3), Vector3.ZERO, Color("3a3e42")).transform = \
			frame * Transform3D(Basis.IDENTITY, Vector3(x, dh + 0.04, 0))
	var hinge := Node3D.new()
	parent.add_child(hinge)
	hinge.transform = frame * Transform3D(Basis.IDENTITY, Vector3(x - dw / 2.0, 0, 0))
	# Shut, its edges just tucked in behind the frame (a 2 cm slit of sky showed down each side in
	# the stairwell's camera: the user's gaps).
	var panel := _box(hinge, Vector3(dw + 0.02, dh + 0.02, 0.07), Vector3(dw / 2.0, dh / 2.0, 0), Color.WHITE)
	panel.material_override = PsxMaterials.textured(_obstacle_texture(theme.get("stair_door", "door")), Vector2(3, 2))
	# Its line-of-sight block is the door it always was: its old size, on a hinge of its own that
	# swings open as the door always did (the door itself now stops flat against the wall: _build_door).
	panel.set_meta("solid", true)
	var sight := Node3D.new()
	parent.add_child(sight)
	sight.transform = hinge.transform
	_solid_box(sight, Transform3D(Basis.IDENTITY, Vector3(dw / 2.0, dh / 2.0, 0)), Vector3(dw - 0.04, dh - 0.02, 0.07))
	return [hinge, sight]


## Open-sky areas (rooftops): no side walls. The roofing runs out to a low lip at the edge, and
## below it the building's own front drops away into the dark. The stairwell coming up from the
## building (the ramp) keeps its walls.
func _build_roof_edges(parent: Node3D, seg: Dictionary, open_l: float, open_r: float) -> void:
	var length: float = seg["length"]
	var ramp: float = seg["ramp_len"]
	var road_w := tuning.lane_count * tuning.lane_width
	var theme := _theme(seg["id"])
	var via := RouteGraph.via_of(seg["edge"])
	var lip: float = theme.get("lip", 0.3)
	# Where a stairwell crosses the edge, what walls up its way down once it's gone (_despawn_behind),
	# built hidden, so nothing's rebuilt mid-run: the lip over it, and the roofing and the building's
	# front where they'd stand through the top of the flight (_cut_floor and below).
	var plugs := _make_plugs(parent, seg)
	_cut_floor(parent, plugs, seg)
	for side in [-1, 1]:
		# The SKYLIGHTS' roof runs out further; the ROOF EDGE's only on its "wide_side".
		var wide: float = theme.get("wide_roof", 0.0) if int(theme.get("wide_side", side)) == side else 0.0
		var edge := road_w / 2.0 + 1.0 + wide
		var open := open_l if side < 0 else open_r
		var hole: Vector2 = seg.get("holes", {}).get(side, Vector2.ZERO)
		var plug: Node3D = plugs.get(side)
		var down: bool = hole.y > hole.x and not seg.get("holes_up", {}).get(side, false)
		# Down a stairwell from the roof before, the roofing out to the edge is laid cut round it over
		# its first metres, as the floor is (_cut_floor), and the building's front below is left out
		# where the flight passes down through it: both stood up through its first steps, seen through
		# the door as it opened. (The front only there: it's under the roofing, seen from nowhere else.)
		var cut_to: float = seg.get("ground_cut", Vector2.ZERO).x if down else 0.0
		if cut_to <= open:
			cut_to = 0.0
		var band: PackedVector2Array = seg.get("hole_bands", {}).get(side, PackedVector2Array())
		var strip_end := length  # (where the roofing piece the cut runs into ends, for its texture)
		var strip_tex := _ground(seg["id"]) if theme.get("railing", false) or theme.get("low_wall", false) else PsxTextures.gravel()
		for piece in _pieces(seg, open, length):
			var on_ramp: bool = piece.y <= ramp + 0.001 and ramp > 0.0
			if on_ramp:
				continue  # the stairwell (or ladder) has its own walls
			# (Where the band crosses this piece's front, on this piece's own leg.)
			var front_cut := _band_across(_band_on_leg(seg, _leg_index(seg, (piece.x + piece.y) / 2.0), band), side * edge) \
					if down else Vector2.ZERO
			# Roofing out to the edge, the lip, and the building's front dropping away below.
			for k in _cut_spans([piece], Vector2(open, cut_to) if cut_to > 0.0 else Vector2.ZERO):
				_strip(parent, seg, k.x, k.y, side * (road_w / 2.0 + (1.0 + wide) / 2.0), 1.0 + wide, 0.0, strip_tex, (1.0 + wide) / tuning.lane_width, tuning.lane_width)
				if cut_to > 0.0 and absf(k.x - cut_to) < 0.001:
					strip_end = k.y
			for span in _wall_spans(piece.x, piece.y, hole):  # the lip stops where a stairwell crosses it
				_roof_lip(parent, seg, span, side, edge, lip)
			if plug and hole.x < piece.y and hole.y > piece.x:
				_roof_lip(plug, seg, Vector2(maxf(hole.x, piece.x), minf(hole.y, piece.y)), side, edge, lip)
			for span in _wall_spans(piece.x, piece.y, front_cut):
				_roof_front(parent, seg, span, piece, side, edge)
			if plug and front_cut.x < piece.y and front_cut.y > piece.x:
				_roof_front(plug, seg, Vector2(maxf(front_cut.x, piece.x), minf(front_cut.y, piece.y)), piece, side, edge)
		if cut_to > 0.0:
			_cut_ground(parent, plugs, seg, open, cut_to, minf(side * road_w / 2.0, side * edge), maxf(side * road_w / 2.0, side * edge), 0.0,
					strip_tex, (1.0 + wide) / tuning.lane_width, tuning.lane_width, strip_end)
		_join_bends(parent, seg, side, side * (edge - 0.1), maxf(open, ramp), lip, PsxMaterials.flat(Color("5e5e58")))
		# ...and the building's front below, joined the same way round the outside of each bend (the
		# two legs' fronts parted in a wedge there: the user's gaps).
		var front_join := PsxMaterials.textured(PsxTextures.building_night(), Vector2(3, 6), true)
		for k in range(1, seg["legs"].size()):
			if float(seg["legs"][k]["start"]) >= maxf(open, ramp):
				_join_at(parent, seg, k, side * edge, -30.02, 30.0, front_join)
	_roof_steps(parent, seg)
	if theme.get("parapet", false):
		_roof_edge_decor(parent, seg)
		_far_masts(parent, seg, 8)
	_unsolid_plugs(parent)


## The building's front below a roof's edge over `span` of `piece` (a straight piece of the road), on
## `side`, `edge` out from the centre line: 30 m of it down from the roofing, facing the road,
## textured as one over the whole piece would be.
func _roof_front(parent: Node3D, seg: Dictionary, span: Vector2, piece: Vector2, side: int, edge: float) -> void:
	var leg: Dictionary = seg["legs"][_leg_index(seg, (piece.x + piece.y) / 2.0)]
	var mid := (span.x + span.y) / 2.0
	var l: float = span.y - span.x
	var front := _plane(parent, Vector2(l, 30.0), Vector3.ZERO, PsxTextures.building_night(), Vector2(l / 4.0, 30.0 / 4.0), PlaneMesh.FACE_Z)
	# (Its pattern runs along the piece on the left side of the road and back along it on the right.)
	var shift := (span.x - piece.x) / 4.0 if side < 0 else (piece.y - span.y) / 4.0
	front.material_override = PsxMaterials.textured(PsxTextures.building_night(), Vector2(l / 4.0, 30.0 / 4.0), true, Vector2(shift, 0.0))
	front.transform = Transform3D(leg["xf"].basis * Basis(Vector3.UP, -side * PI / 2.0),
			leg["xf"] * Vector3(side * edge, _height(seg, mid) - 15.0, -(mid - leg["start"])))


## Where a stairwell's band (_stairwell_band) crosses the line `x` across the road: from and to,
## metres along; ZERO if it doesn't.
static func _band_across(band: PackedVector2Array, x: float) -> Vector2:
	var lo := INF
	var hi := -INF
	for k in band.size():
		var p := band[k]
		var q := band[(k + 1) % band.size()]
		if (p.x - x) * (q.x - x) <= 0.0 and absf(q.x - p.x) > 1e-6:
			var at := lerpf(p.y, q.y, (x - p.x) / (q.x - p.x))
			lo = minf(lo, at)
			hi = maxf(hi, at)
	return Vector2(lo, hi) if hi > lo else Vector2.ZERO


## A roof's lip along its edge over span (x..y), on `side`, `edge` out from the centre line: the
## area's own (a low concrete parapet, a tall one with red lights, or a kerb with a railing).
func _roof_lip(parent: Node3D, seg: Dictionary, span: Vector2, side: int, edge: float, lip: float) -> void:
	var theme := _theme(seg["id"])
	if theme.get("low_wall", false):  # the ROOFTOPS: a low concrete parapet
		_low_wall(parent, seg, span, side * (edge - 0.1), lip)
		return
	if theme.get("parapet", false):  # the ROOF EDGE: a tall parapet with red lights
		_roof_parapet(parent, seg, span, side * (edge - 0.1), lip, side)
		return
	_item_box(parent, seg, (span.x + span.y) / 2.0, Vector3(side * (edge - 0.1), lip / 2.0, 0), Vector3(0.2, lip, span.y - span.x + 0.2), Color("5e5e58"))
	if theme.get("railing", false):  # a chain-link railing along the edge (WATER TOWERS)
		_roof_railing(parent, seg, span, side * (edge - 0.1), lip)


## How far out from the centre line an area's roofing reaches on `side` (a walled area or the
## GANTRY's catwalk: to the usual wall line).
func _roof_reach(id: StringName, side: int) -> float:
	var theme := _theme(id)
	var reach := tuning.lane_count * tuning.lane_width / 2.0 + 1.0
	if theme.get("no_walls", false) and int(theme.get("wide_side", side)) == side:
		reach += float(theme.get("wide_roof", 0.0))
	return reach


## Where a wider roof meets a narrower one, or ends at the ladders down to the helipad: a lip
## across the step, the roof's edge carried round the corner, and the building's end wall below
## it. The roofing just stopped there, open to the drop (the user's gaps). At the start of a roof
## reached by the stairs (the ROOFTOPS), the same beside the stairwell's hut, out past the road.
func _roof_steps(parent: Node3D, seg: Dictionary) -> void:
	var id: StringName = seg["id"]
	var theme := _theme(id)
	var length: float = seg["length"]
	var ramp: float = seg["ramp_len"]
	var road_half := tuning.lane_count * tuning.lane_width / 2.0
	var lip: float = theme.get("lip", 0.3)
	var front := PsxMaterials.textured(PsxTextures.building_night(), Vector2(3, 2), true)
	for side in [-1, 1]:
		var edge := _roof_reach(id, side)
		# The end: as far across as the roof (or roofs) carrying on from it reach.
		var inner := edge
		var ladders := false
		for e in _graph.all_next(id):
			if RouteGraph.via_of(e) == "ladder":
				inner = minf(inner, road_half)  # beside the ladder lane
				ladders = true
			elif RouteGraph.side_of(e) == "straight" and _graph.tier_of(StringName(e["to"])) == _graph.tier_of(id):
				inner = minf(inner, _roof_reach(StringName(e["to"]), side))
		var steps: Array[Vector3] = []  # (into, from x, to x)
		if edge - inner > 0.05:
			steps.append(Vector3(length, inner, edge))
		# The start: up the stairs, out past the road beside the hut; after a narrower roof, the step.
		var start_inner := edge
		if _is_stairs(seg):
			start_inner = road_half + 1.0
		elif RouteGraph.side_of(seg["edge"]) == "straight" and not seg["edge"].is_empty() and seg["dy"] == 0.0:
			start_inner = _roof_reach(seg["from_id"], side)
		if edge - start_inner > 0.05:
			steps.append(Vector3(ramp if _is_stairs(seg) else 0.0, start_inner, edge))
		for st in steps:
			var at := st.x
			var inward := -1.0 if at > 0.0 and is_equal_approx(at, length) else 1.0  # into the roof from that end
			var w := st.z - st.y
			var cx: float = side * (st.y + st.z) / 2.0
			var l := _item_box(parent, seg, at, Vector3(cx, lip / 2.0, -inward * 0.1), Vector3(w + 0.2, lip, 0.2), Color("5e5e58"))
			if theme.get("low_wall", false):
				l.material_override = PsxMaterials.textured(PsxTextures.concrete(), Vector2(maxf(1.0, w / 2.0), 1))
			if not (inward < 0.0 and ladders):  # (down the ladders, the helipad builds the wall under the end)
				_item_box(parent, seg, at, Vector3(cx, -15.02, inward * 0.2), Vector3(w + 0.4, 30.0, 0.4), Color.WHITE).material_override = front


## A chain-link railing along a roof edge over span (x..y), on top of the lip: posts every 2 m,
## a top and a middle rail, and the mesh between (see-through).
func _roof_railing(parent: Node3D, seg: Dictionary, span: Vector2, x: float, lip: float) -> void:
	var steel := Color("3a3c3e")
	var mid := (span.x + span.y) / 2.0
	var l := span.y - span.x
	for y in [lip + 0.45, lip + 0.95]:
		_item_box(parent, seg, mid, Vector3(x, y, 0), Vector3(0.05, 0.05, l), steel)
	_item_box(parent, seg, mid, Vector3(x, lip + 0.48, 0), Vector3(0.02, 0.9, l), Color.WHITE).material_override = \
			PsxMaterials.glass(Color(0.14, 0.16, 0.18, 0.45))  # the mesh
	var p := ceilf(span.x / 2.0) * 2.0
	while p <= span.y:
		_item_box(parent, seg, p, Vector3(x, lip + 0.5, 0), Vector3(0.06, 1.0, 0.06), steel)
		p += 2.0


## Office walls: now and then a door, a window or a notice board between the pillars.
func _wall_decor(parent: Node3D, seg: Dictionary, side: int, from: float, to: float) -> void:
	if str(_theme(seg["id"]).get("wall_decor", "")) == "sewer":
		_sewer_decor(parent, seg, side, from, to)
		return
	if str(_theme(seg["id"]).get("wall_decor", "")) == "service":
		_service_decor(parent, seg, side, from, to)
		return
	if str(_theme(seg["id"]).get("wall_decor", "")) == "exit":
		_exit_decor(parent, seg, side, from, to)
		return
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
## cone of cold light down through the haze. It hangs high, its bulb half a metre over the camera
## (3.4 m up behind him, in any lane): hung lower, the camera flew through every shade and bulb in
## the middle lane. Its light shines from where it always did, 2 m under the ceiling, so the floor
## is lit as before; the haze, which the camera still passes through, fades out near the lens.
func _pendant_lamp(parent: Node3D, seg: Dictionary, z: float, failing: bool) -> void:
	var y := CEILING_Y - PENDANT_DROP
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
	var haze_top := y - 0.15
	var haze_bottom := -0.2  # just under the floor, so its end never shows (user)
	beam.top_radius = 0.35
	beam.bottom_radius = 0.35 + 0.48 * (haze_top - haze_bottom)
	beam.height = haze_top - haze_bottom
	beam.radial_segments = 10
	beam.cap_top = false
	beam.cap_bottom = false
	haze.mesh = beam
	haze.material_override = PsxMaterials.beam(Color(0.85, 0.92, 1.0, 0.07))
	parent.add_child(haze)
	haze.transform = _frame_at(seg, z) * Transform3D(Basis.IDENTITY, Vector3(0, (haze_top + haze_bottom) / 2.0, 0))
	var at := Node3D.new()
	parent.add_child(at)
	at.transform = _frame_at(seg, z) * Transform3D(Basis.IDENTITY, Vector3(0, CEILING_Y - 2.0, 0))
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
## yellow-and-black crane rail down one side of the road with a trolley and a hook. The rail runs
## over the road's edge, out past where the camera ever goes (2.8 m out at most): over the lanes,
## the camera in the outside lane flew through the trolley and right by the hook's cable.
func _warehouse_overhead(parent: Node3D, seg: Dictionary, from: float) -> void:
	var road_w := tuning.lane_count * tuning.lane_width
	var cx := road_w / 2.0 - 0.2  # the rail's line (m out from the middle)
	var length: float = seg["length"]
	var z := maxf(from, 12.0)
	while z < length - 2.0:
		_item_box(parent, seg, z, Vector3(0, CEILING_Y - 0.25, 0), Vector3(road_w + 2.0, 0.34, 0.3), Color("6a2a22"))
		z += 10.0
	var rail := PsxMaterials.textured(PsxTextures.hazard(), Vector2(1, 6))
	for piece in _pieces(seg, maxf(from, 12.0), length - 2.0):
		var mid := (piece.x + piece.y) / 2.0
		_item_box(parent, seg, mid, Vector3(cx, CEILING_Y - 0.55, 0), Vector3(0.36, 0.3, piece.y - piece.x), Color.WHITE).material_override = rail
	var hz := minf(length * 0.6, length - 6.0)
	_item_box(parent, seg, hz, Vector3(cx, CEILING_Y - 0.85, 0), Vector3(0.7, 0.36, 0.9), Color("d8a020"))  # trolley
	_item_box(parent, seg, hz, Vector3(cx, CEILING_Y - 1.55, 0), Vector3(0.04, 1.1, 0.04), Color("2a2a2a"))  # cable
	_item_box(parent, seg, hz, Vector3(cx, CEILING_Y - 2.2, 0), Vector3(0.22, 0.26, 0.12), Color("2a2a2a"))  # hook block
	_item_box(parent, seg, hz, Vector3(cx, CEILING_Y - 2.42, 0.06), Vector3(0.06, 0.2, 0.18), Color("8a8a84"))  # the hook


## Yellow lines painted along the edges of the road, and across it now and then (the WAREHOUSE).
func _floor_lines(parent: Node3D, seg: Dictionary, from: float) -> void:
	var road_half := tuning.lane_count * tuning.lane_width / 2.0
	var yellow := PsxTextures.wall("blocks", LINE_PAINT)
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
	# It's the floor out here, at floor level: the road is left out under it (_build_surfaces), and
	# meets it at the doors on the same points. (6 mm over the road, the paler floor showed through
	# in triangles, worst at the yard's bends: the user's corners.)
	for piece in _pieces(seg, o.x, o.y):
		_strip(parent, seg, piece.x, piece.y, 0.0, road_half * 2.0, 0.0, asphalt, float(tuning.lane_count), 4.0)
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
	# The fence joined round the outside of a bend in the yard, as the walls are indoors (it parted
	# in a wedge there: the user's gaps). (Only for looks: out of line of sight.)
	for k in range(1, seg["legs"].size()):
		var j: float = seg["legs"][k]["start"]
		if j > o.x and j < o.y:
			for s in [-1.0, 1.0]:
				var fj := _join_at(parent, seg, k, s * (road_half + 12.5), 0.0, 2.6, PsxMaterials.flat(Color("3a4044")))
				if fj:
					fj.set_meta("solid", true)


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
## edge at head height across the blocked lanes. The cables dither away as the camera comes close
## (PsxMaterials.lens_faded): from the next lane it passes right by one.
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
		var cable := _box(parent, Vector3(0.03, len, 0.03), Vector3.ZERO, Color("2a2c2e"))  # its cables
		cable.transform = frame * Transform3D(Basis.IDENTITY, Vector3(cx, bottom + h + len / 2.0, 0))
		cable.material_override = PsxMaterials.lens_faded(Color("2a2c2e"))  # (the camera passes right by them)
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


## MAIN FLOOR EXIT (user reference): a glass wall along one piece of the hall instead of a solid
## one: a granite skirting, tall panes of glass in dark mullions, a dark header under the ceiling.
## Outside, the night city: a dark plaza out to a backdrop of lit buildings against the night sky,
## close enough that nothing else in the mission shows through the glass.
func _glass_wall(parent: Node3D, seg: Dictionary, a: float, b: float, wx: float, side: int, h: float) -> void:
	var l := b - a
	var mid := (a + b) / 2.0
	var frame := Color("1e2224")
	_item_box(parent, seg, mid, Vector3(wx, 0.12, 0), Vector3(0.14, 0.24, l), Color.WHITE).material_override = \
			PsxMaterials.textured(PsxTextures.exit_granite(), Vector2(l / 2.0, 1))  # skirting
	_item_box(parent, seg, mid, Vector3(wx, (0.24 + h - 0.3) / 2.0, 0), Vector3(0.04, h - 0.54, l), Color.WHITE).material_override = \
			PsxMaterials.glass(Color(0.5, 0.62, 0.78, 0.14))
	_item_box(parent, seg, mid, Vector3(wx, h - 0.15, 0), Vector3(0.16, 0.3, l), frame)  # header
	_item_box(parent, seg, mid, Vector3(wx, 0.27, 0), Vector3(0.1, 0.06, l), frame)  # sill rail
	var z := ceilf(a / 2.5) * 2.5
	while z < b:
		_item_box(parent, seg, z, Vector3(wx, h / 2.0, 0), Vector3(0.08, h, 0.08), frame)  # mullions
		z += 2.5
	# Outside: the plaza, then the city against the sky (one opaque, unlit backdrop).
	var out := 10.0
	_strip(parent, seg, a, b, wx + side * out / 2.0, out, -0.03, PsxTextures.yard_asphalt(), out / 4.0, 4.0)
	var i := _leg_index(seg, mid)
	var leg: Dictionary = seg["legs"][i]
	var y0 := -0.5
	var bh := 7.5  # sized so the sky shows over the skyline through the top of the glass
	var city := _plane(parent, Vector2(l, bh), Vector3.ZERO, PsxTextures.city_backdrop(), Vector2(l / 15.0, 1.0), PlaneMesh.FACE_Z)
	city.material_override = PsxMaterials.textured(PsxTextures.city_backdrop(), Vector2(l / 15.0, 1.0), true, Vector2(a / 15.0, 0))
	city.transform = Transform3D(leg["xf"].basis * Basis(Vector3.UP, -side * PI / 2.0),
			leg["xf"] * Vector3(wx + side * out, y0 + bh / 2.0, -(mid - leg["start"])))
	# A row of lamp posts out on the plaza, their light on the paving.
	var p := ceilf(a / 15.0) * 15.0 + 7.0
	while p < b - 1.0:
		_item_box(parent, seg, p, Vector3(wx + side * 5.5, 1.8, 0), Vector3(0.1, 3.6, 0.1), Color("2a2e32"))
		_item_box(parent, seg, p, Vector3(wx + side * 5.5, 3.65, 0), Vector3(0.3, 0.14, 0.3), Color.WHITE).material_override = \
				PsxMaterials.glow(Color("ffc880"))
		_item_box(parent, seg, p, Vector3(wx + side * 5.5, 0.0, 0), Vector3(2.4, 0.01, 2.4), Color.WHITE).material_override = \
				PsxMaterials.glass(Color(1.0, 0.75, 0.4, 0.12))  # its pool of light
		p += 15.0


## MAIN FLOOR EXIT walls (user reference), between the big granite pillars: a warm cube lamp on each
## pillar facing the road (its reflection on the polished floor), and against the glass a concrete
## planter of bushes or a wooden bench, in turn. Dark beams across the ceiling at the pillars.
func _exit_decor(parent: Node3D, seg: Dictionary, side: int, from: float, to: float) -> void:
	var road_half := tuning.lane_count * tuning.lane_width / 2.0
	var every: int = int(_theme(seg["id"]).get("pillar_every", 10))
	var lamps := 0
	for i in range(ceili(from / float(every)) * every, int(to), every):
		var near_bend := false
		for leg in seg["legs"]:
			if absf(leg["start"] - i) < 1.3:
				near_bend = true
		if near_bend:
			continue
		var sconce := _item_box(parent, seg, i, Vector3(side * (road_half + 0.16), 2.7, 0), Vector3(0.3, 0.3, 0.3), Color.WHITE)
		sconce.material_override = PsxMaterials.glow(Color("ffd890"))
		if lamps < 4:
			_ambience.add_lamp(sconce, Color(1.0, 0.8, 0.5) * 1.1, 4.5, {"alert": false})
			lamps += 1
		# Its reflection in the polished floor: a faint warm streak running out toward you.
		_item_box(parent, seg, i + 0.9, Vector3(side * (road_half - 0.35), 0.012, 0), Vector3(0.32, 0.004, 1.6), Color.WHITE).material_override = \
				PsxMaterials.glass(Color(1.0, 0.82, 0.5, 0.16))
		if side < 0:  # one dark beam across the ceiling per pillar pair
			_item_box(parent, seg, i, Vector3(0, CEILING_Y - 0.2, 0), Vector3(road_half * 2.0 + 2.0, 0.4, 0.45), Color("1a1c1e"))
		var at := float(i) + every / 2.0
		if at > to - 2.0:
			continue
		var holder := Node3D.new()
		parent.add_child(holder)
		holder.transform = _frame_at(seg, at) * Transform3D(Basis.IDENTITY, Vector3(side * (road_half + 0.55), 0, 0))
		if (i / every + (1 if side > 0 else 0)) % 2 == 0:
			_exit_planter(holder, 2.6, 0.7, absi(hash([seg["id"], i, side])))
		else:  # a granite bench with a wooden seat
			_box(holder, Vector3(0.6, 0.38, 1.9), Vector3(0, 0.19, 0), Color.WHITE).material_override = \
					PsxMaterials.textured(PsxTextures.exit_granite(), Vector2(3, 1))
			_box(holder, Vector3(0.66, 0.07, 2.0), Vector3(0, 0.42, 0), Color("8a6234"))


## A concrete planter trough of `length` along z (local), bushes heaped in it to about `height`
## above its rim. Used along the walls and as box cover.
func _exit_planter(holder: Node3D, length: float, depth: float, seed_v: int) -> void:
	var rim := 0.72
	_box(holder, Vector3(depth, rim, length), Vector3(0, rim / 2.0, 0), Color("7a7c78"))
	_box(holder, Vector3(depth - 0.12, 0.04, length - 0.12), Vector3(0, rim, 0), Color("2a2018"))  # soil
	var n := maxi(4, int(length * 3.0))
	for k in n:
		var t := (k + 0.5) / n
		var r := float((seed_v + k * 37) % 7) / 7.0
		var bush := _box(holder, Vector3(depth * 0.6, 0.42 + 0.2 * r, length / n * 1.8), Vector3((r - 0.5) * depth * 0.3, rim + 0.22 + 0.1 * r,
				-length / 2.0 + t * length), Color("2a4a22").lightened(0.06 * ((seed_v + k) % 3)))
		bush.rotation = Vector3(0.3 * (r - 0.5), 0.5 * r, 0.25 * (0.5 - r))


## MAIN FLOOR EXIT box cover: a big concrete planter heaped with bushes, tall enough to hide behind.
func _build_exit_box(parent: Node3D, seg: Dictionary, at: float, x: float, lane: int) -> Node3D:
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.transform = _frame_at(seg, at) * Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(x, 0, 0))
	_exit_planter(holder, 1.15, 0.9, absi(hash([seg["id"], at, lane])))
	return holder


## MAIN FLOOR EXIT duck-under: a big green EXIT sign hanging on rods from the ceiling across the
## blocked lanes, its bottom edge at head height. The rods dither away as the camera comes close
## (PsxMaterials.lens_faded): from the next lane it passes right by one.
func _build_exit_sign(parent: Node3D, seg: Dictionary, at: float, ends: Array) -> Node3D:
	var frame := _frame_at(seg, at)
	var e0: float = ends[0]["x"]
	var e1: float = ends[1]["x"]
	var w := e1 - e0
	var bottom := WIRE_LOW - 0.15
	var h := 0.6
	var cx := (e0 + e1) / 2.0
	var sign := _box(parent, Vector3(w, h, 0.14), Vector3.ZERO, Color("1a1e1c"))
	sign.transform = frame * Transform3D(Basis.IDENTITY, Vector3(cx, bottom + h / 2.0, 0))
	var face := _box(parent, Vector3(w - 0.1, h - 0.1, 0.02), Vector3.ZERO, Color.WHITE)
	face.transform = frame * Transform3D(Basis.IDENTITY, Vector3(cx, bottom + h / 2.0, 0.08))
	face.material_override = PsxMaterials.glow(Color("1f9a4a"))
	var label := _sign_label("EXIT  >>", Color("e8fff0"), w * 0.7, Vector3(0, 0, 0.1))
	sign.add_child(label)
	label.modulate = Color("f4fff8")
	var top := _ceil(seg["id"])
	for rx in [e0 + 0.3, e1 - 0.3]:
		var rod := top - (bottom + h)
		var hanger := _box(parent, Vector3(0.04, rod, 0.04), Vector3.ZERO, Color("2a2c2e"))
		hanger.transform = frame * Transform3D(Basis.IDENTITY, Vector3(rx, bottom + h + rod / 2.0, 0))
		hanger.material_override = PsxMaterials.lens_faded(Color("2a2c2e"))  # (the camera passes right by them)
	var glow := Node3D.new()
	parent.add_child(glow)
	glow.transform = frame * Transform3D(Basis.IDENTITY, Vector3(cx, bottom - 0.4, 0.6))
	_ambience.add_lamp(glow, Color(0.4, 1.0, 0.6) * 0.8, 3.5, {"alert": false})
	return sign


## The MAIN FLOOR EXIT's way out (user reference): a glass front across the end of the hall, granite
## pillars at its ends, a glass transom over three big glass doors across the whole road that you
## burst through, swinging out (user), and a green EXIT sign over the middle.
func _build_exit_front(parent: Node3D, seg: Dictionary) -> void:
	var z: float = float(seg["length"]) - 0.3
	var road_half := tuning.lane_count * tuning.lane_width / 2.0
	var frame := Color("1e2224")
	var granite := PsxMaterials.textured(PsxTextures.exit_granite(), Vector2(1, 2))
	for s in [-1.0, 1.0]:
		_item_box(parent, seg, z, Vector3(s * (road_half + 0.5), CEILING_Y / 2.0, 0), Vector3(1.0, CEILING_Y, 0.8), Color.WHITE).material_override = granite
	var dh := GATE_H
	_item_box(parent, seg, z, Vector3(0, dh + 0.08, 0), Vector3(road_half * 2.0, 0.16, 0.2), frame)  # the door head
	_item_box(parent, seg, z, Vector3(0, (dh + 0.16 + CEILING_Y) / 2.0, 0), Vector3(road_half * 2.0, CEILING_Y - dh - 0.16, 0.04), Color.WHITE) \
			.material_override = PsxMaterials.glass(Color(0.5, 0.62, 0.78, 0.16))  # transom
	_item_box(parent, seg, z, Vector3(0, CEILING_Y - 0.12, 0), Vector3(road_half * 2.0, 0.24, 0.2), frame)
	var exit := _item_box(parent, seg, z + 0.15, Vector3(0, dh + 0.42, 0), Vector3(0.8, 0.3, 0.06), Color.WHITE)
	exit.material_override = PsxMaterials.glow(Color("30c060"))
	exit.add_child(_sign_label("EXIT", Color("e8fff0"), 0.6, Vector3(0, 0, 0.04)))
	# Three big glass doors across the whole road (user): the left and middle ones hinged on their
	# left edge, the right one on its right edge. You burst through, and they swing out ahead of you.
	var dw := road_half * 2.0 / 3.0
	for k in 3:
		var hinge_x := -road_half + dw * k if k < 2 else road_half
		var reach := 1.0 if k < 2 else -1.0  # which way the door runs from its hinge
		var hinge := Node3D.new()
		parent.add_child(hinge)
		hinge.transform = _frame_at(seg, z) * Transform3D(Basis.IDENTITY, Vector3(hinge_x, 0, 0))
		var cx := reach * dw / 2.0
		_box(hinge, Vector3(dw - 0.08, dh - 0.12, 0.03), Vector3(cx, dh / 2.0, 0), Color.WHITE).material_override = \
				PsxMaterials.glass(Color(0.55, 0.68, 0.82, 0.22))
		for ex in [0.04, dw - 0.04]:  # the frame round it
			_box(hinge, Vector3(0.08, dh - 0.04, 0.07), Vector3(reach * ex, dh / 2.0, 0), frame)
		for ey in [0.06, dh - 0.06]:
			_box(hinge, Vector3(dw - 0.04, 0.12, 0.07), Vector3(cx, ey, 0), frame)
		_box(hinge, Vector3(dw - 0.5, 0.06, 0.08), Vector3(cx, 1.05, 0.06), Color("b8b8b0"))  # push bar
		if not seg.get("no_doors", false):
			var door := {"node": hinge, "at": seg["start"] + z, "owner": seg["node"], "seg": seg, "swing": reach}
			if k == 0:  # one crash for the three
				door["sound"] = "door_steel"
			_doors.append(door)


## The HELIPAD (user reference): a wide rooftop pad at night instead of side walls. The deck runs
## out well past the road on both sides and on past its end, under the chopper (which stands 3 m
## past the end). Paving in big slabs, hazard lines along the road's edges and a hazard band across
## where the pad starts, the yellow landing ring with a white H, red edge lights round it and two
## on posts by the way in, floodlight masts at the corners, a railing and low parapet round the
## edge, and the building's front dropping away below. Supply crates, a red crate, a concrete
## block, a bollard and utility cabinets along the sides.
func _build_helipad(parent: Node3D, seg: Dictionary, from: float) -> void:
	var L: float = seg["length"]
	var road_half := tuning.lane_count * tuning.lane_width / 2.0
	var half := road_half + 8.5  # the deck's half width
	var zc := L + 3.0  # the pad's centre, under the chopper
	var far := L + 13.0
	var slab := PsxTextures.helipad_slab()
	var front := PsxMaterials.textured(PsxTextures.building_night(), Vector2(3, 2), true)
	# The deck: out from the road on each side, and across beyond the road's end.
	for s in [-1.0, 1.0]:
		var w := half - road_half
		_strip(parent, seg, from, L, s * (road_half + w / 2.0), w, 0.0, slab, w / tuning.lane_width, tuning.lane_width)
	_strip(parent, seg, L, far, 0.0, half * 2.0, 0.0, slab, half * 2.0 / tuning.lane_width, tuning.lane_width)
	# Come to by a ladder, the deck runs right back to where the ladder starts, flat at the deck's
	# height (not up the ladder's slope): up out of the STORM DRAIN, out past the hatch's own floor
	# (_build_ladder_shaft); down from the ROOF EDGE, across the whole deck and on 6 m back under
	# the roof's end, where the camera behind you comes down (with nothing there, the bottom of
	# the screen was void: the user's gaps). A hair under the deck where they overlap, so the two
	# never fight.
	var by_ladder := RouteGraph.via_of(seg["edge"]) == "ladder" and from > 0.0
	var dy: float = seg["dy"]
	var start := from  # where the deck's edges start
	if by_ladder:
		start = -6.0 if dy < 0.0 else 0.0
		var fl := from + 0.1 - start
		var fz := start + fl / 2.0
		var fills: Array[Vector2] = []  # (centre x, width)
		if dy < 0.0:
			fills.append(Vector2(0.0, half * 2.0))
		else:
			var hatch_edge := road_half + 1.2  # the hatch's floor runs out this far
			for s in [-1.0, 1.0]:
				fills.append(Vector2(s * (hatch_edge + half) / 2.0, half - hatch_edge))
		for f in fills:
			var fill := _plane(parent, Vector2(f.y, fl), Vector3.ZERO, slab, Vector2(f.y / tuning.lane_width, fl / tuning.lane_width))
			fill.transform = _frame_at(seg, fz) * Transform3D(Basis.IDENTITY, Vector3(f.x, dy - 0.01 - _height(seg, fz), 0))
	# Its thickness, and the building's front dropping away below its edges.
	var mid := (start + far) / 2.0
	for s in [-1.0, 1.0]:
		_item_box(parent, seg, mid, Vector3(s * (half + 0.2), -10.0, 0), Vector3(0.4, 20.0, far - start), Color.WHITE).material_override = front
	_item_box(parent, seg, far + 0.2, Vector3(0, -10.0, 0), Vector3(half * 2.0 + 0.8, 20.0, 0.4), Color.WHITE).material_override = front
	if by_ladder and dy < 0.0:  # (and below the deck's near edge, back under the roof)
		_item_box(parent, seg, start, Vector3(0, dy - 10.02 - _height(seg, start), 0.2), Vector3(half * 2.0 + 0.8, 20.0, 0.4), Color.WHITE).material_override = front
	# The parapet and railing round the edge.
	var rail := Color("8a8e90")
	for s in [-1.0, 1.0]:
		_item_box(parent, seg, mid, Vector3(s * half, 0.15, 0), Vector3(0.3, 0.3, far - start), Color("5c5e5c"))
		for y in [0.65, 1.1]:
			_item_box(parent, seg, mid, Vector3(s * half, y, 0), Vector3(0.05, 0.05, far - start), rail)
	_item_box(parent, seg, far, Vector3(0, 0.15, 0), Vector3(half * 2.0, 0.3, 0.3), Color("5c5e5c"))
	for y in [0.65, 1.1]:
		_item_box(parent, seg, far, Vector3(0, y, 0), Vector3(half * 2.0, 0.05, 0.05), rail)
	var p := ceilf(start / 2.0) * 2.0
	while p <= far:
		for s in [-1.0, 1.0]:  # (at the deck's height, along the ladder too)
			_item_box(parent, seg, p, Vector3(s * half, 0.55 + dy - _height(seg, p), 0), Vector3(0.06, 1.1, 0.06), rail)
		p += 2.0
	var x := -half + 1.0
	while x < half:
		_item_box(parent, seg, far, Vector3(x, 0.55, 0), Vector3(0.06, 1.1, 0.06), rail)
		x += 2.0
	# Hazard lines along the road's edges up to the pad, and a hazard band across where it starts.
	var hz := PsxTextures.hazard()
	var band := zc - 7.5
	for s in [-1.0, 1.0]:
		if band - 0.5 > from:
			_strip(parent, seg, from, band - 0.5, s * (road_half - 0.1), 0.2, 0.008, hz, 1.0, 0.8)
	_strip(parent, seg, band - 0.35, band, 0.0, road_half * 2.0 - 0.4, 0.008, hz, 10.0, 0.35)
	# The landing ring and the H, read from the way in.
	var yellow := PsxMaterials.flat(Color("d8b020"))
	var ring_r := 5.6
	var bits := 32
	for k in bits:
		var a := TAU * k / bits
		var seg_len := TAU * ring_r / bits + 0.05
		var b := _item_box(parent, seg, zc - ring_r * cos(a), Vector3(ring_r * sin(a), 0.01, 0), Vector3(seg_len, 0.012, 0.3), Color.WHITE)
		b.material_override = yellow
		b.rotation.y += a  # along the ring
	var white := Color("e8e8e0")
	for s in [-1.0, 1.0]:
		_item_box(parent, seg, zc, Vector3(s * 1.1, 0.012, 0), Vector3(0.55, 0.012, 3.4), white)
	_item_box(parent, seg, zc, Vector3(0, 0.012, 0), Vector3(1.7, 0.012, 0.55), white)
	# Red edge lights round the ring, and two on posts either side of the way in.
	var red_on := PsxMaterials.glow(Color("ff2a18"))
	var lit := 0
	for k in 12:
		var a := TAU * (k + 0.5) / 12
		var l := _item_box(parent, seg, zc - (ring_r + 0.9) * cos(a), Vector3((ring_r + 0.9) * sin(a), 0.12, 0), Vector3(0.3, 0.24, 0.3), Color.WHITE)
		l.material_override = red_on
		if k % 3 == 0 and lit < 4:
			_ambience.add_lamp(l, Color(1.0, 0.18, 0.1) * 0.9, 3.0, {"alert": false})
			lit += 1
	for s in [-1.0, 1.0]:
		_item_box(parent, seg, band - 0.8, Vector3(s * (road_half + 0.45), 0.4, 0), Vector3(0.45, 0.8, 0.45), Color("4a4c4e"))
		var head := _item_box(parent, seg, band - 0.8, Vector3(s * (road_half + 0.45), 0.92, 0), Vector3(0.4, 0.24, 0.4), Color.WHITE)
		head.material_override = red_on
		_ambience.add_lamp(head, Color(1.0, 0.18, 0.1) * 1.1, 3.5, {"alert": false})
	# Floodlight masts at the corners of the pad.
	for c in [[-1.0, zc - 9.0], [1.0, zc - 9.0], [-1.0, zc + 8.5], [1.0, zc + 8.5]]:
		var mx: float = c[0] * (half - 1.2)
		var mz: float = c[1]
		_item_box(parent, seg, mz, Vector3(mx, 3.4, 0), Vector3(0.16, 6.8, 0.16), Color("6a6e70"))
		_item_box(parent, seg, mz, Vector3(mx, 6.9, 0), Vector3(1.2, 0.1, 0.2), Color("4a4e50"))
		for k in 4:
			var lamp := _item_box(parent, seg, mz, Vector3(mx + (k % 2 - 0.5) * 0.55, 7.15 + (k / 2) * 0.4, 0.05), Vector3(0.42, 0.32, 0.12), Color.WHITE)
			lamp.material_override = PsxMaterials.glow(Color("f4f0dc"))
			if k == 0:
				_ambience.add_lamp(lamp, Color(0.95, 0.95, 0.85) * 1.6, 14.0, {"alert": false})
	# Along the sides: stacked military crates on the right, a red crate, a concrete block and a
	# yellow bollard on the left, grey utility cabinets by the railing.
	var olive := PsxMaterials.textured(PsxTextures.olive_crate(), Vector2(3, 2))
	for k in 5:
		var holder := Node3D.new()
		parent.add_child(holder)
		var cz := band - 1.5 - k * 1.25
		if cz < from + 1.0:
			break
		holder.transform = _frame_at(seg, cz) * Transform3D(Basis(Vector3.UP, 0.06 * (k % 3 - 1)), Vector3(road_half + 1.2 + (k % 2) * 0.15, 0, 0))
		_box(holder, Vector3(1.1, 0.9, 1.1), Vector3(0, 0.45, 0), Color.WHITE).material_override = olive
		if k % 2 == 0:
			_box(holder, Vector3(1.0, 0.8, 1.0), Vector3(0.05, 1.3, 0.05), Color.WHITE).material_override = olive
	var red_crate := _item_box(parent, seg, band - 2.0, Vector3(-(road_half + 2.6), 0.4, 0), Vector3(0.9, 0.8, 0.8), Color.WHITE)
	red_crate.material_override = PsxMaterials.flat(Color("7a2a20"))
	_item_box(parent, seg, band - 1.2, Vector3(-(road_half + 1.3), 0.45, 0), Vector3(1.0, 0.9, 1.0), Color("6e706c"))  # concrete block
	_item_box(parent, seg, band - 4.0, Vector3(-(road_half + 0.5), 0.45, 0), Vector3(0.22, 0.9, 0.22), Color("d8b020"))  # bollard
	_item_box(parent, seg, band - 4.0, Vector3(-(road_half + 0.5), 0.75, 0), Vector3(0.24, 0.08, 0.24), Color("1a1a1a"))
	for c in [[-1.0, zc + 6.0], [1.0, zc - 4.0]]:
		_item_box(parent, seg, c[1], Vector3(c[0] * (half - 0.8), 0.8, 0), Vector3(0.7, 1.6, 1.2), Color.WHITE).material_override = \
				PsxMaterials.textured(PsxTextures.cabinet(), Vector2(3, 2))


## The chopper (user reference, built to the player's scale): a military transport helicopter about
## 13 m long with a 15 m rotor, broadside on the pad, nose to the left, tail to the right, its cabin
## door slid open toward you with a dim light inside, so you run straight in. Local +z is toward you.
func _build_chopper_model(chopper: Node3D) -> void:
	var body := Color("3a4036")
	var dark := Color("262a24")
	var glass := Color("16242c")
	# The cabin, belly and nose; the door opening sits in the middle, right in front of you.
	_box(chopper, Vector3(4.6, 2.0, 2.5), Vector3(0.5, 1.75, 0), body)  # cabin
	_box(chopper, Vector3(4.4, 0.25, 2.2), Vector3(0.5, 0.65, 0), dark)  # belly
	_box(chopper, Vector3(1.7, 1.6, 2.1), Vector3(-2.65, 1.65, 0), body)  # nose
	var screen := _box(chopper, Vector3(1.0, 0.08, 1.9), Vector3(-2.85, 2.35, 0), glass)  # windscreen, sloping
	screen.rotation.z = 0.55
	_box(chopper, Vector3(0.5, 0.9, 1.8), Vector3(-3.55, 1.4, 0), body.darkened(0.1))  # chin
	for s in [-1.0, 1.0]:
		_box(chopper, Vector3(1.2, 0.7, 0.04), Vector3(-2.6, 2.05, s * 1.06), glass)  # cockpit side windows
	_box(chopper, Vector3(0.3, 0.12, 1.4), Vector3(-2.1, 1.75, 0), Color.WHITE).material_override = \
			PsxMaterials.glow(Color("2a8a4a"))  # the instrument panel glowing through the glass
	# The door: slid back, the dark cabin inside with a dim light, a gun on its mount.
	_box(chopper, Vector3(2.0, 1.7, 0.04), Vector3(0.0, 1.7, 1.26), Color("0e100e"))  # the opening
	_box(chopper, Vector3(1.9, 1.75, 0.06), Vector3(1.95, 1.72, 1.3), body.lightened(0.06))  # the door, slid back
	_box(chopper, Vector3(0.7, 0.5, 0.02), Vector3(1.95, 2.1, 1.34), glass)  # its window
	_box(chopper, Vector3(1.9, 0.05, 0.1), Vector3(0.95, 2.62, 1.3), Color("6a6e66"))  # door rail
	var inside := _box(chopper, Vector3(0.3, 0.06, 0.3), Vector3(0.0, 2.45, 0.6), Color.WHITE)
	inside.material_override = PsxMaterials.glow(Color("c8a060"))
	_ambience.add_lamp(inside, Color(1.0, 0.75, 0.45) * 0.9, 3.0, {"alert": false})
	_box(chopper, Vector3(0.08, 0.08, 0.9), Vector3(-0.85, 1.75, 1.45), Color("141414"))  # door gun barrel
	_box(chopper, Vector3(0.2, 0.2, 0.35), Vector3(-0.85, 1.75, 0.95), Color("1e1e1e"))  # its body
	_box(chopper, Vector3(0.05, 0.75, 0.05), Vector3(-0.85, 1.35, 0.95), Color("2a2a2a"))  # its post
	# The engine housing on top, the exhaust, the mast and rotor.
	_box(chopper, Vector3(3.0, 0.65, 1.7), Vector3(0.7, 3.07, 0), body.darkened(0.08))
	_box(chopper, Vector3(0.5, 0.35, 0.5), Vector3(2.35, 3.05, 0.45), dark)  # exhaust
	_box(chopper, Vector3(0.22, 0.6, 0.22), Vector3(0.6, 3.65, 0), dark)  # mast
	var rotor := Node3D.new()
	chopper.add_child(rotor)
	rotor.position = Vector3(0.6, 3.98, 0)
	_box(rotor, Vector3(0.6, 0.18, 0.6), Vector3.ZERO, dark)  # hub
	for k in 4:  # four blades
		var arm := Node3D.new()
		rotor.add_child(arm)
		arm.rotation.y = k * PI / 2.0
		_box(arm, Vector3(7.6, 0.06, 0.42), Vector3(3.9, 0, 0), Color("141414"))
	var spin := rotor.create_tween().set_loops()
	spin.tween_property(rotor, "rotation:y", TAU, 0.35).from(0.0)
	# The tail boom, fin, stabiliser and tail rotor, to the right.
	_box(chopper, Vector3(3.6, 0.85, 1.0), Vector3(4.6, 2.2, 0), body)
	_box(chopper, Vector3(3.8, 0.55, 0.62), Vector3(8.3, 2.25, 0), body)
	var fin := _box(chopper, Vector3(1.0, 2.2, 0.18), Vector3(10.0, 3.2, 0), body)
	fin.rotation.z = -0.3
	_box(chopper, Vector3(0.9, 0.06, 2.6), Vector3(9.2, 2.35, 0), body.darkened(0.05))  # stabiliser
	var tail_rotor := Node3D.new()
	chopper.add_child(tail_rotor)
	tail_rotor.position = Vector3(10.3, 3.6, 0.22)
	for k in 2:
		var tb := _box(tail_rotor, Vector3(0.18, 2.4, 0.04), Vector3.ZERO, Color("141414"))
		tb.rotation.z = k * PI / 2.0
	var tspin := tail_rotor.create_tween().set_loops()
	tspin.tween_property(tail_rotor, "rotation:z", TAU, 0.2).from(0.0)
	# Skids.
	for s in [-1.0, 1.0]:
		_box(chopper, Vector3(6.2, 0.1, 0.1), Vector3(0.2, 0.08, s * 1.25), Color("4a4e48"))
		for sx in [-1.4, 2.0]:
			var strut := _box(chopper, Vector3(0.09, 0.62, 0.09), Vector3(sx, 0.38, s * 1.12), Color("4a4e48"))
			strut.rotation.x = -s * 0.25
	# Lights: a blinking red one on the fin, a red beacon on top, the landing light lighting the pad.
	var tail := _box(chopper, Vector3(0.18, 0.18, 0.18), Vector3(10.35, 4.25, 0), Color.WHITE)
	tail.material_override = PsxMaterials.glow(Color("ff3020"))
	_ambience.add_lamp(tail, Color(1.0, 0.15, 0.1) * 1.5, 5.0, {"blink": 1.1, "alert": false, "fixture": tail,
			"on_mat": PsxMaterials.glow(Color("ff3020")), "off_mat": PsxMaterials.flat(Color("401010"))})
	_box(chopper, Vector3(0.2, 0.14, 0.2), Vector3(0.7, 3.47, 0), Color.WHITE).material_override = PsxMaterials.glow(Color("ff3020"))
	var land := Node3D.new()
	chopper.add_child(land)
	land.position = Vector3(0, 1.2, 3.0)
	_ambience.add_lamp(land, Color(0.9, 0.95, 1.0) * 1.2, 7.0, {"alert": false})


## The WATER TOWERS (user reference): big water tanks on steel stands on the roof sections either
## side of the walkway, alternating sides, clear of bends (their corners) and of the searchlights'
## buildings. The first spot with room both sides gets a pair, joined by a big pipe arching high
## over the road.
func _water_towers(parent: Node3D, seg: Dictionary) -> void:
	var length: float = seg["length"]
	var lights: Array = _graph.node_data(seg["id"]).get("searchlights", [])
	var clear := func(z: float, side: int) -> bool:
		for leg in seg["legs"]:
			if absf(float(leg["start"]) - z) < 14.0 and float(leg["start"]) > 0.0:
				return false
		for l in lights:
			if (-1 if String(l.get("side", "left")) == "left" else 1) == side and absf(float(l["at"]) - z) < 10.0:
				return false
		return z > float(seg["ramp_len"]) + 8.0 and z < length - 8.0
	var z := 16.0
	var side := -1
	var paired := false
	var n := 0
	while z < length - 8.0:
		if not paired and clear.call(z, -1) and clear.call(z, 1) and z > 30.0:
			_water_tower(parent, seg, z, -1, true)
			_water_tower(parent, seg, z, 1, false)
			_tower_arch(parent, seg, z)
			paired = true
		elif clear.call(z, side) and n == 3:
			# A roof hut on its own roof section, its lit door toward the road (user reference).
			var hut := Node3D.new()
			parent.add_child(hut)
			hut.transform = _frame_at(seg, z) * Transform3D(Basis.IDENTITY, Vector3(side * _tower_x(), 0, 0))
			_box(hut, Vector3(7.0, 0.3, 7.0), Vector3(0, -1.35, 0), Color.WHITE).material_override = PsxMaterials.textured(PsxTextures.helipad_slab(), Vector2(15, 10))
			_box(hut, Vector3(6.9, 20.0, 6.9), Vector3(0, -11.5, 0), Color.WHITE).material_override = PsxMaterials.textured(PsxTextures.building_night(), Vector2(3, 2), true)
			_roof_hut(parent, seg, z, side * (_tower_x() - 1.0), -side)
		elif clear.call(z, side):
			_water_tower(parent, seg, z, side, n % 2 == 0)
		side = -side
		n += 1
		z += 24.0


## How far out from the road's centre a water tower stands (on the next roof section, past the
## roof's own front).
func _tower_x() -> float:
	return tuning.lane_count * tuning.lane_width / 2.0 + 1.0 + 3.6


## One water tower at `z` on `side`: a lower roof section under it (the building below dropping
## away), four legs with cross-bracing, a railed platform, the rusty tank and its lid, a ladder
## up the side facing the road, a lamp on the stand, a red light on top if `beacon`.
func _water_tower(parent: Node3D, seg: Dictionary, z: float, side: int, beacon: bool) -> void:
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.transform = _frame_at(seg, z) * Transform3D(Basis.IDENTITY, Vector3(side * _tower_x(), 0, 0))
	var steel := Color("3a3c3e")
	var ys := -1.2  # the lower roof section
	var yt := 4.4  # the tank's platform
	_box(holder, Vector3(7.0, 0.3, 7.0), Vector3(0, ys - 0.15, 0), Color.WHITE).material_override = \
			PsxMaterials.textured(PsxTextures.helipad_slab(), Vector2(15, 10))
	_box(holder, Vector3(6.9, 20.0, 6.9), Vector3(0, ys - 10.3, 0), Color.WHITE).material_override = \
			PsxMaterials.textured(PsxTextures.building_night(), Vector2(3, 2), true)
	var lh := yt - ys
	for cx in [-1.9, 1.9]:
		for cz in [-1.9, 1.9]:
			_box(holder, Vector3(0.26, lh, 0.26), Vector3(cx, ys + lh / 2.0, cz), steel)
	# Cross-bracing on all four faces, in two tiers, and a tie round the middle.
	var mid_y := ys + lh * 0.45
	for tier in [[ys + 0.2, mid_y], [mid_y, yt - 0.1]]:
		var y0: float = tier[0]
		var y1: float = tier[1]
		var th := y1 - y0
		var diag := sqrt(3.8 * 3.8 + th * th)
		var ang := atan2(th, 3.8)
		for f in [-1.9, 1.9]:
			for d in [-1.0, 1.0]:
				var b1 := _box(holder, Vector3(diag, 0.08, 0.08), Vector3(0, (y0 + y1) / 2.0, f), steel)
				b1.rotation.z = d * ang
				var b2 := _box(holder, Vector3(0.08, 0.08, diag), Vector3(f, (y0 + y1) / 2.0, 0), steel)
				b2.rotation.x = d * ang
	for f in [-1.9, 1.9]:
		_box(holder, Vector3(3.8, 0.14, 0.14), Vector3(0, mid_y, f), steel)
		_box(holder, Vector3(0.14, 0.14, 3.8), Vector3(f, mid_y, 0), steel)
	# The platform and its railing.
	_box(holder, Vector3(6.0, 0.14, 6.0), Vector3(0, yt, 0), Color("4a4c4e"))
	for f in [-2.95, 2.95]:
		_box(holder, Vector3(6.0, 0.05, 0.05), Vector3(0, yt + 1.0, f), steel)
		_box(holder, Vector3(0.05, 0.05, 6.0), Vector3(f, yt + 1.0, 0), steel)
		for p in [-2.95, 0.0, 2.95]:
			_box(holder, Vector3(0.05, 1.0, 0.05), Vector3(p, yt + 0.5, f), steel)
			_box(holder, Vector3(0.05, 1.0, 0.05), Vector3(f, yt + 0.5, p), steel)
	# The tank, its lid, a hatch, and the pipe out of its bottom.
	var tank := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 2.7
	cyl.bottom_radius = 2.7
	cyl.height = 5.2
	cyl.radial_segments = 14
	tank.mesh = cyl
	tank.material_override = PsxMaterials.textured(PsxTextures.rust_tank(), Vector2(5, 1.5))
	holder.add_child(tank)
	tank.position = Vector3(0, yt + 0.07 + 2.6, 0)
	var lid := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.3
	cone.bottom_radius = 2.8
	cone.height = 0.6
	cone.radial_segments = 14
	lid.mesh = cone
	lid.material_override = PsxMaterials.flat(Color("5a5856"))
	holder.add_child(lid)
	lid.position = Vector3(0, yt + 5.27 + 0.3, 0)
	_box(holder, Vector3(0.5, 0.25, 0.5), Vector3(0, yt + 6.0, 0), Color("4a4846"))  # hatch
	_box(holder, Vector3(0.36, yt - ys, 0.36), Vector3(0, ys + (yt - ys) / 2.0, 0), Color("4a4846"))  # outlet pipe
	# The ladder up the road side, from the roof section to the lid.
	var lx := -side * 3.1
	var top := yt + 5.4
	for rz in [-0.24, 0.24]:
		_box(holder, Vector3(0.06, top - ys, 0.06), Vector3(lx, ys + (top - ys) / 2.0, rz), steel)
	var ry := ys + 0.3
	while ry < top:
		_box(holder, Vector3(0.05, 0.05, 0.48), Vector3(lx, ry, 0), steel)
		ry += 0.36
	# A lamp on the stand facing the road, and a red light on top.
	var lamp := _box(holder, Vector3(0.2, 0.18, 0.36), Vector3(-side * 2.05, yt - 0.35, 0.8), Color.WHITE)
	lamp.material_override = PsxMaterials.glow(Color("ffd890"))
	_ambience.add_lamp(lamp, Color(1.0, 0.8, 0.5) * 1.3, 6.0, {"alert": false})
	_halo(holder, lamp.position + Vector3(-side * 0.15, 0, 0), Color(1.0, 0.75, 0.4, 0.5), 1.6)
	if beacon:
		var red := _box(holder, Vector3(0.2, 0.2, 0.2), Vector3(0, yt + 6.25, 0), Color.WHITE)
		red.material_override = _beacon_mat if _beacon_mat else PsxMaterials.glow(Color("ff3020"))
		_halo(holder, red.position, Color(1.0, 0.15, 0.08, 0.6), 2.2)


## A big pipe between the pair of water towers at `z`, arching high over the road (well above the
## camera), into each tank's side, with flanges, and a drop pipe down to the roof on each side.
func _tower_arch(parent: Node3D, seg: Dictionary, z: float) -> void:
	var y := 7.6
	var inner := _tower_x() - 2.7
	var grey := Color("4a4c4c")
	_pipe_x(parent, _frame_at(seg, z) * Transform3D(Basis.IDENTITY, Vector3(0, y, 0)), inner * 2.0, 0.36, grey)
	for fx in [-inner * 0.5, 0.0, inner * 0.5]:
		_pipe_x(parent, _frame_at(seg, z) * Transform3D(Basis.IDENTITY, Vector3(fx, y, 0)), 0.16, 0.44, grey.darkened(0.2))  # flanges
	var edge := tuning.lane_count * tuning.lane_width / 2.0 + 0.6
	for s in [-1.0, 1.0]:
		_item_box(parent, seg, z + 1.0, Vector3(s * edge, y / 2.0, 0), Vector3(0.4, y, 0.4), grey)  # drop pipe
		_item_box(parent, seg, z + 0.5, Vector3(s * edge, y, 0), Vector3(0.44, 0.44, 1.4), grey)  # its elbow into the main
		_item_box(parent, seg, z + 1.0, Vector3(s * edge, 0.2, 0), Vector3(0.6, 0.4, 0.6), Color("5a5c5a"))  # its foot


## A cylinder lying along x (a pipe across the road), `length` long, centred on `xf`.
func _pipe_x(parent: Node3D, xf: Transform3D, length: float, radius: float, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = length
	cyl.radial_segments = 10
	m.mesh = cyl
	m.material_override = PsxMaterials.flat(color)
	parent.add_child(m)
	m.transform = xf * Transform3D(Basis(Vector3.FORWARD, PI / 2.0), Vector3.ZERO)
	return m


## WATER TOWERS box cover: a grey air-con condenser unit, grilles down its sides and a fan on top,
## tall enough to crouch behind.
func _build_condenser(parent: Node3D, seg: Dictionary, at: float, x: float, _lane: int) -> Node3D:
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.transform = _frame_at(seg, at) * Transform3D(Basis.IDENTITY, Vector3(x, 0, 0))
	_box(holder, Vector3(1.05, 0.1, 0.9), Vector3(0, 0.05, 0), Color("2e3032"))  # its frame
	_box(holder, Vector3(1.0, 1.15, 0.85), Vector3(0, 0.67, 0), Color.WHITE).material_override = \
			PsxMaterials.textured(PsxTextures.hvac(), Vector2(3, 2))
	_box(holder, Vector3(1.02, 0.05, 0.87), Vector3(0, 1.26, 0), Color("7e807c"))  # top panel
	var fan := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.34
	cyl.bottom_radius = 0.34
	cyl.height = 0.06
	cyl.radial_segments = 10
	fan.mesh = cyl
	fan.material_override = PsxMaterials.flat(Color("1e2022"))
	holder.add_child(fan)
	fan.position = Vector3(0, 1.3, 0)
	for r in 2:
		var bar := _box(holder, Vector3(0.66, 0.03, 0.04), Vector3(0, 1.34, 0), Color("8a8c88"))
		bar.rotation.y = r * PI / 2.0
	return holder


## WATER TOWERS jump: a low run of pipes across the lane on concrete sleepers.
func _build_floor_pipe(parent: Node3D, seg: Dictionary, at: float, x: float, _lane: int) -> Node3D:
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.transform = _frame_at(seg, at) * Transform3D(Basis.IDENTITY, Vector3(x, 0, 0))
	for sx in [-0.5, 0.5]:
		_box(holder, Vector3(0.24, 0.22, 0.7), Vector3(sx, 0.11, 0), Color("6e706c"))  # sleepers
	var w := tuning.lane_width + 0.02  # meets the next lane's run
	_pipe_x(holder, Transform3D(Basis.IDENTITY, Vector3(0, 0.36, -0.12)), w, 0.14, Color("6a5a48"))
	_pipe_x(holder, Transform3D(Basis.IDENTITY, Vector3(0, 0.36, 0.16)), w, 0.11, Color("4a4c4c"))
	_pipe_x(holder, Transform3D(Basis.IDENTITY, Vector3(0, 0.6, 0.02)), w, 0.09, Color("8a8e90"))
	return holder


## Low concrete lamp boxes along the walkway's edges (WATER TOWERS), each with a warm glowing face
## toward the road, alternating sides.
func _bollard_lamps(parent: Node3D, seg: Dictionary) -> void:
	var road_half := tuning.lane_count * tuning.lane_width / 2.0
	var z := float(seg["ramp_len"]) + 6.0
	var n := 0
	var holes: Dictionary = seg.get("holes", {})
	while z < float(seg["length"]) - 2.0:
		var side := -1 if n % 2 == 0 else 1
		var hole: Vector2 = holes.get(side, Vector2.ZERO)
		if z < hole.x - 2.0 or z > hole.y + 2.0:
			_item_box(parent, seg, z, Vector3(side * (road_half + 0.45), 0.28, 0), Vector3(0.45, 0.56, 0.45), Color("6a6c68"))
			var face := _item_box(parent, seg, z, Vector3(side * (road_half + 0.22), 0.32, 0), Vector3(0.02, 0.2, 0.26), Color.WHITE)
			face.material_override = PsxMaterials.glow(Color("ffd890"))
			_halo_at(parent, seg, z, Vector3(side * (road_half + 0.16), 0.32, 0), Color(1.0, 0.72, 0.38, 0.55), 1.1)
			_pool_at(parent, seg, z, side * (road_half - 0.5), Color(1.0, 0.68, 0.32, 0.32), 2.4)
			var at := Node3D.new()
			parent.add_child(at)
			at.transform = _frame_at(seg, z) * Transform3D(Basis.IDENTITY, Vector3(side * (road_half - 0.4), 0.6, 0))
			_ambience.add_lamp(at, Color(1.0, 0.78, 0.45) * 1.0, 4.0)
		z += 9.0
		n += 1


## The GANTRY (user reference): a steel catwalk bridge high over the city, instead of a roof edge.
## Grating out to the railings, hazard-striped railings with braces, girders and cross beams under
## the deck, steel portal frames overhead every 6 m with floodlights angled down onto the walkway,
## and blocks of lit windows far below.
func _build_gantry_bridge(parent: Node3D, seg: Dictionary, from: float) -> void:
	var length: float = seg["length"]
	var road_half := tuning.lane_count * tuning.lane_width / 2.0
	var edge := road_half + 1.0
	var steel := Color("2e3234")
	var grate := PsxTextures.grating()
	for piece in _pieces(seg, from, length):
		var mid := (piece.x + piece.y) / 2.0
		var l: float = piece.y - piece.x
		for s in [-1.0, 1.0]:
			_strip(parent, seg, piece.x, piece.y, s * (road_half + 0.5), 1.0, 0.0, grate, 1.0, tuning.lane_width)
			# Under the deck: a girder along each edge.
			_item_box(parent, seg, mid, Vector3(s * (edge - 0.2), -0.45, 0), Vector3(0.3, 0.8, l), steel)
			# The railing: hazard-striped top rail, a middle rail.
			var top := _item_box(parent, seg, mid, Vector3(s * (edge - 0.1), 1.1, 0), Vector3(0.12, 0.12, l), Color.WHITE)
			top.material_override = PsxMaterials.textured(PsxTextures.hazard(), Vector2(l / 1.2, 1))
			_item_box(parent, seg, mid, Vector3(s * (edge - 0.1), 0.6, 0), Vector3(0.05, 0.05, l), steel)
			_item_box(parent, seg, mid, Vector3(s * (edge - 0.1), 0.08, 0), Vector3(0.06, 0.16, l), steel)  # kick plate
	# Posts and braces every 2 m, cross beams under the deck every 3 m.
	var p := ceilf(from / 2.0) * 2.0
	var k := 0
	while p <= length:
		for s in [-1.0, 1.0]:
			_item_box(parent, seg, p, Vector3(s * (edge - 0.1), 0.55, 0), Vector3(0.1, 1.1, 0.1), steel)
			var brace := _item_box(parent, seg, p + 1.0, Vector3(s * (edge - 0.1), 0.55, 0), Vector3(0.05, 0.05, 2.2), steel)
			brace.rotation.x += (0.45 if k % 2 == 0 else -0.45)
		p += 2.0
		k += 1
	p = ceilf(from / 3.0) * 3.0
	while p <= length:
		_item_box(parent, seg, p, Vector3(0, -0.4, 0), Vector3(edge * 2.0, 0.3, 0.25), steel)
		p += 3.0
	# Portal frames overhead, top beams along both sides, X-bracing in alternate bays.
	var fh := 5.4
	var f := ceilf((from + 3.0) / 6.0) * 6.0
	var n := 0
	var lit := 0
	while f < length - 1.0:
		for s in [-1.0, 1.0]:
			_item_box(parent, seg, f, Vector3(s * (edge - 0.05), fh / 2.0, 0), Vector3(0.32, fh, 0.32), steel)
		_item_box(parent, seg, f, Vector3(0, fh, 0), Vector3(edge * 2.0 + 0.3, 0.36, 0.32), steel)
		if f + 6.0 < length - 1.0:
			for s in [-1.0, 1.0]:
				_item_box(parent, seg, f + 3.0, Vector3(s * (edge - 0.05), fh - 0.1, 0), Vector3(0.22, 0.22, 6.0), steel)  # top beam
				if n % 2 == 0:  # X-bracing above the railing, in the side of the frame
					var bh := fh - 1.6
					var ang := atan2(bh, 6.0)
					for d in [-1.0, 1.0]:
						var x_brace := _item_box(parent, seg, f + 3.0, Vector3(s * (edge - 0.05), 1.4 + bh / 2.0, 0), Vector3(0.1, 0.1, sqrt(36.0 + bh * bh)), steel)
						x_brace.rotation.x += d * ang
			_item_box(parent, seg, f + 3.0, Vector3(0, fh + 0.05, 0), Vector3(0.14, 0.14, 6.0), steel)  # a spine beam
			var roof := _item_box(parent, seg, f + 3.0, Vector3(0, fh + 0.2, 0), Vector3(edge * 2.0, 0.04, 6.0), Color.WHITE)
			roof.material_override = PsxMaterials.textured(PsxTextures.grating(), Vector2(3.0 * edge * 2.0 / 1.4, 2.0 * 6.0 / 1.4))  # grating overhead
		# A floodlight on alternate columns, angled down and in over the walkway.
		if n % 2 == 0:
			var s := -1.0 if (n / 2) % 2 == 0 else 1.0
			var head := Node3D.new()
			parent.add_child(head)
			head.transform = _frame_at(seg, f + 0.3) * Transform3D(Basis.IDENTITY, Vector3(s * (edge - 0.35), 4.7, 0))
			head.rotation.z += -s * 0.6
			var housing := _box(head, Vector3(0.8, 0.26, 0.62), Vector3.ZERO, Color("1e2022"))
			var lens := _box(head, Vector3(0.7, 0.04, 0.52), Vector3(0, -0.14, 0), Color.WHITE)
			lens.material_override = PsxMaterials.glow(Color("f4f0dc"))
			housing.name = "Housing"
			_halo(head, Vector3(0, -0.2, 0), Color(1.0, 0.96, 0.82, 0.5), 2.0)
			var aim := s * (edge - 0.35) - s * 2.4
			_beam_cone(parent, seg, f + 0.3, Vector3(s * (edge - 0.5), 4.55, 0), Vector3(aim, 0.0, 0), 0.3, 1.6, Color(1.0, 0.96, 0.85, 0.09))
			_pool_at(parent, seg, f + 0.3, aim, Color(1.0, 0.95, 0.8, 0.3), 2.6)
			if lit < 6:
				var at := Node3D.new()
				parent.add_child(at)
				at.transform = _frame_at(seg, f + 0.3) * Transform3D(Basis.IDENTITY, Vector3(s * (edge - 2.0), 3.2, 0))
				_ambience.add_lamp(at, Color(1.0, 0.96, 0.84) * 2.2, 9.0)
				lit += 1
		f += 6.0
		n += 1
	_side_catwalks(parent, seg, from)
	_far_masts(parent, seg, 8)
	# Blocks of lit windows far below, either side.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seg["id"]) + 3
	var facade := PsxMaterials.textured(PsxTextures.building_night(), Vector2(3, 2), true)
	var roofing := PsxMaterials.textured(PsxTextures.gravel(), Vector2(6, 4))
	for s in [-1.0, 1.0]:
		var z := from + rng.randf_range(0.0, 6.0)
		while z < length:
			var blen := rng.randf_range(10.0, 20.0)
			var bw := rng.randf_range(8.0, 14.0)
			var top := rng.randf_range(-22.0, -9.0)
			var bx: float = s * (edge + rng.randf_range(4.0, 9.0) + bw / 2.0)
			var at := minf(z + blen / 2.0, length)
			_item_box(parent, seg, at, Vector3(bx, top - 20.0, z + blen / 2.0 - at), Vector3(bw, 40.0, blen), Color.WHITE).material_override = facade
			_item_box(parent, seg, at, Vector3(bx, top + 0.02, z + blen / 2.0 - at), Vector3(bw, 0.04, blen), Color.WHITE).material_override = roofing
			z += blen + rng.randf_range(3.0, 8.0)


## Other catwalks running alongside the GANTRY, out either side and lower (user reference): a
## grating deck, hazard-striped railings, frames, a column down into the dark every so often, and a
## lamp with its glow now and then.
func _side_catwalks(parent: Node3D, seg: Dictionary, from: float) -> void:
	var length: float = seg["length"]
	var steel := Color("2a2e30")
	for s in [-1.0, 1.0]:
		var cx: float = s * (tuning.lane_count * tuning.lane_width / 2.0 + 13.0)
		var y := -3.0 if s < 0 else -5.5
		for piece in _pieces(seg, from, length):
			var mid := (piece.x + piece.y) / 2.0
			var l: float = piece.y - piece.x
			_item_box(parent, seg, mid, Vector3(cx, y, 0), Vector3(2.6, 0.12, l), Color.WHITE).material_override = \
					PsxMaterials.textured(PsxTextures.grating(), Vector2(3.0 * 2, 2.0 * l / 1.4))
			for e in [-1.3, 1.3]:
				_item_box(parent, seg, mid, Vector3(cx + e, y + 1.05, 0), Vector3(0.08, 0.08, l), Color.WHITE).material_override = \
						PsxMaterials.textured(PsxTextures.hazard(), Vector2(l / 1.2, 1))
			_item_box(parent, seg, mid, Vector3(cx, y - 0.4, 0), Vector3(0.4, 0.6, l), steel)
		var f := from + 4.0
		var k := 0
		while f < length:
			for e in [-1.3, 1.3]:
				_item_box(parent, seg, f, Vector3(cx + e, y + 1.7, 0), Vector3(0.14, 3.4, 0.14), steel)
			_item_box(parent, seg, f, Vector3(cx, y + 3.4, 0), Vector3(2.8, 0.18, 0.18), steel)
			if k % 3 == 0:  # a column down into the dark
				_item_box(parent, seg, f, Vector3(cx, y - 15.0, 0), Vector3(0.5, 30.0, 0.5), steel)
			if k % 2 == 1:
				var lamp := _item_box(parent, seg, f, Vector3(cx - s * 1.2, y + 3.1, 0), Vector3(0.3, 0.14, 0.3), Color.WHITE)
				lamp.material_override = PsxMaterials.glow(Color("ffd890"))
				_halo_at(parent, seg, f, Vector3(cx - s * 1.2, y + 3.0, 0), Color(1.0, 0.75, 0.4, 0.5), 1.8)
			f += 6.0
			k += 1


## GANTRY jump: a steel I-beam lying across the lane, painted with hazard stripes.
func _build_ibeam(parent: Node3D, seg: Dictionary, at: float, x: float, _lane: int) -> Node3D:
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.transform = _frame_at(seg, at) * Transform3D(Basis.IDENTITY, Vector3(x, 0, 0))
	var w := tuning.lane_width + 0.02
	var steel := Color("3a3e40")
	_box(holder, Vector3(w, 0.06, 0.4), Vector3(0, 0.03, 0), steel)  # bottom flange
	_box(holder, Vector3(w, 0.4, 0.08), Vector3(0, 0.26, 0), steel)  # web
	var top := _box(holder, Vector3(w, 0.07, 0.42), Vector3(0, 0.48, 0), Color.WHITE)  # top flange, painted
	top.material_override = PsxMaterials.textured(PsxTextures.hazard(), Vector2(3, 2))
	for sx in [-0.45, 0.45]:
		_box(holder, Vector3(0.1, 0.05, 0.36), Vector3(sx, 0.53, 0), Color("6a6e70"))  # lifting lugs
	return holder


## GANTRY box cover: a steel equipment case on a grating skid, hazard tape on its corners.
func _build_gantry_case(parent: Node3D, seg: Dictionary, at: float, x: float, _lane: int) -> Node3D:
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.transform = _frame_at(seg, at) * Transform3D(Basis.IDENTITY, Vector3(x, 0, 0))
	_box(holder, Vector3(1.0, 0.12, 0.9), Vector3(0, 0.06, 0), Color("2e3234"))  # skid
	_box(holder, Vector3(0.95, 1.12, 0.82), Vector3(0, 0.68, 0), Color.WHITE).material_override = \
			PsxMaterials.textured(PsxTextures.steel_case(), Vector2(3, 2))
	for cx in [-0.47, 0.47]:
		_box(holder, Vector3(0.04, 1.12, 0.12), Vector3(cx, 0.68, 0.36), Color.WHITE).material_override = \
				PsxMaterials.textured(PsxTextures.hazard(), Vector2(1, 3))
	_box(holder, Vector3(0.3, 0.06, 0.08), Vector3(0, 1.27, 0), Color("1e2022"))  # handle
	return holder


## The SKYLIGHTS (user reference): runs of big pitched glass skylights along both sides of the
## walkway on the wider roof, each on a concrete curb with the warm-lit room below showing through
## and a warm pool of light thrown onto the walkway; air-con boxes and vent stacks in the gaps.
func _skylights(parent: Node3D, seg: Dictionary) -> void:
	var length: float = seg["length"]
	var road_half := tuning.lane_count * tuning.lane_width / 2.0
	var unit := 9.0
	var lit := 0
	for side in [-1, 1]:
		var z := float(seg["ramp_len"]) + 6.0 + (0.0 if side < 0 else 4.0)
		var n := 0
		while z + unit < length - 3.0:
			var near_bend := false
			for leg in seg["legs"]:
				if float(leg["start"]) > 0.0 and absf(float(leg["start"]) - (z + unit / 2.0)) < unit / 2.0 + 6.0:
					near_bend = true
			if not near_bend:
				_skylight(parent, seg, z + unit / 2.0, side * (road_half + 3.9), unit, lit < 6)
				lit += 1
				# In the gap after it: an air-con box or a pair of vent stacks, near the walkway.
				var gz := z + unit + 1.2
				if gz < length - 2.0:
					if n % 2 == 0:
						_item_box(parent, seg, gz, Vector3(side * (road_half + 1.5), 0.55, 0), Vector3(1.2, 1.1, 1.1), Color.WHITE).material_override = \
								PsxMaterials.textured(PsxTextures.hvac(), Vector2(3, 2))
					else:
						_item_box(parent, seg, gz, Vector3(side * (road_half + 1.5), 0.2, 0), Vector3(0.9, 0.4, 0.6), Color("5a5c5a"))
						for dz in [-0.15, 0.15]:
							_item_box(parent, seg, gz + dz, Vector3(side * (road_half + 1.5), 0.75, 0), Vector3(0.16, 0.8, 0.16), Color("8a7a5a"))
							_item_box(parent, seg, gz + dz, Vector3(side * (road_half + 1.5), 1.18, 0), Vector3(0.22, 0.08, 0.22), Color("5a4e3a"))
			z += unit + 2.6
			n += 1


## One skylight: a concrete curb `length` long at `x`, the lit room below seen through it, a glass
## ridge on top in a metal frame (ridge, eaves, rafters), and a warm light out onto the walkway.
func _skylight(parent: Node3D, seg: Dictionary, z: float, x: float, length: float, lamp: bool) -> void:
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.transform = _frame_at(seg, z) * Transform3D(Basis.IDENTITY, Vector3(x, 0, 0))
	var w := 5.0
	var curb := 0.55
	var rise := 2.2
	var frame := Color("3a3c3a")
	_box(holder, Vector3(w + 0.3, curb, length + 0.3), Vector3(0, curb / 2.0, 0), Color("4e504c"))
	var room := _box(holder, Vector3(w - 0.1, 0.02, length - 0.1), Vector3(0, curb + 0.01, 0), Color.WHITE)
	room.material_override = PsxMaterials.textured(PsxTextures.skylight_room(), Vector2(3, 2), true)
	var spill := MeshInstance3D.new()  # the light spilling up out of the room, under the glass
	var sp := PlaneMesh.new()
	sp.size = Vector2(w * 1.6, length * 1.15)
	spill.mesh = sp
	spill.material_override = PsxMaterials.pool(Color(1.0, 0.82, 0.45, 0.55))
	holder.add_child(spill)
	spill.position = Vector3(0, curb + 0.05, 0)
	for dz in [-length / 3.0, 0.0, length / 3.0]:
		_halo(holder, Vector3(0, curb + 0.6, dz), Color(1.0, 0.8, 0.45, 0.22), 3.6)
	var outside := MeshInstance3D.new()  # its warm light on the gravel toward the walkway
	var op := PlaneMesh.new()
	op.size = Vector2(4.0, length)
	outside.mesh = op
	outside.material_override = PsxMaterials.pool(Color(1.0, 0.7, 0.35, 0.3))
	holder.add_child(outside)
	outside.position = Vector3(-signf(x) * (w / 2.0 + 1.2), 0.03, 0)
	var glass := MeshInstance3D.new()
	glass.mesh = _prism_mesh(w, rise, length)
	glass.material_override = PsxMaterials.glass(Color(0.75, 0.82, 0.86, 0.22))
	holder.add_child(glass)
	glass.position = Vector3(0, curb, 0)
	_box(holder, Vector3(0.12, 0.12, length), Vector3(0, curb + rise, 0), frame)  # ridge
	for e in [-1.0, 1.0]:
		_box(holder, Vector3(0.12, 0.1, length), Vector3(e * w / 2.0, curb + 0.05, 0), frame)  # eaves
	var slope := sqrt(w * w / 4.0 + rise * rise)
	var ang := atan2(rise, w / 2.0)
	var rz := -length / 2.0
	while rz <= length / 2.0 + 0.01:
		for e in [-1.0, 1.0]:
			var r := _box(holder, Vector3(slope, 0.07, 0.07), Vector3(e * w / 4.0, curb + rise / 2.0, rz), frame)
			r.rotation.z = -e * ang
		rz += 1.5
	if lamp:
		var at := Node3D.new()
		holder.add_child(at)
		at.position = Vector3(-signf(x) * 1.0, curb + 1.0, 0)
		_ambience.add_lamp(at, Color(1.0, 0.82, 0.5) * 1.3, 7.0, {"alert": false})


## A ridge of glass: two slopes meeting at the top and a gable at each end (a triangular prism
## `w` wide, `h` high, `l` long, its base on y = 0).
func _prism_mesh(w: float, h: float, l: float) -> ArrayMesh:
	var a := Vector3(-w / 2.0, 0, -l / 2.0)
	var b := Vector3(w / 2.0, 0, -l / 2.0)
	var c := Vector3(w / 2.0, 0, l / 2.0)
	var d := Vector3(-w / 2.0, 0, l / 2.0)
	var r1 := Vector3(0, h, -l / 2.0)
	var r2 := Vector3(0, h, l / 2.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for tri in [[a, r1, r2], [a, r2, d], [b, c, r2], [b, r2, r1], [a, b, r1], [d, r2, c]]:
		for v in tri:
			st.add_vertex(v)
	st.generate_normals()
	return st.commit()


## An arrow (a chevron) `w` across, DOOR_ARROW_SIZE.y long, lying flat and pointing forward (-Z),
## centred on its origin; the arms are DOOR_ARROW_SIZE.z thick along it. One per width, shared.
func _arrow_mesh(w: float) -> ArrayMesh:
	if _arrow_meshes.has(w):
		return _arrow_meshes[w]
	var d := DOOR_ARROW_SIZE.y
	var t := DOOR_ARROW_SIZE.z
	var tip := Vector3(0, 0, -d / 2.0)
	var tip_in := Vector3(0, 0, -d / 2.0 + t)
	var r := Vector3(w / 2.0, 0, d / 2.0 - t)
	var r_in := Vector3(w / 2.0, 0, d / 2.0)
	var l := Vector3(-w / 2.0, 0, d / 2.0 - t)
	var l_in := Vector3(-w / 2.0, 0, d / 2.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for tri in [[tip, r, r_in], [tip, r_in, tip_in], [tip, tip_in, l_in], [tip, l_in, l]]:
		for v in tri:
			st.add_vertex(v)
	_arrow_meshes[w] = st.commit()
	return _arrow_meshes[w]


## The ANTENNA FARM (user reference): on the wider roof either side of the walkway, tall lattice
## antenna towers and big satellite dishes, in turn; equipment cabinets with small warm lamps close
## to the walkway; cable trays along both its edges. All clear of bends (their corners).
func _antenna_farm(parent: Node3D, seg: Dictionary) -> void:
	var length: float = seg["length"]
	var road_half := tuning.lane_count * tuning.lane_width / 2.0
	var clear := func(z: float, room: float) -> bool:
		for leg in seg["legs"]:
			if float(leg["start"]) > 0.0 and absf(float(leg["start"]) - z) < room:
				return false
		return z > float(seg["ramp_len"]) + 5.0 and z < length - 4.0
	for side in [-1, 1]:
		var z := float(seg["ramp_len"]) + (10.0 if side < 0 else 21.0)
		var n := 0
		while z < length - 6.0:
			if clear.call(z, 10.0):
				if n % 2 == 0:
					_antenna_tower(parent, seg, z, side * (road_half + 5.2), 10.0 + 4.0 * float((n / 2) % 2))
				else:
					_satellite_dish(parent, seg, z, side)
			z += 22.0
			n += 1
		# Equipment cabinets close to the walkway, a lamp on some.
		var c := float(seg["ramp_len"]) + (6.0 if side < 0 else 12.0)
		var k := 0
		while c < length - 3.0:
			if clear.call(c, 7.0):
				_equipment_cabinet(parent, seg, c, side * (road_half + 1.75), side, k % 2 == 0)
			c += 12.0
			k += 1
	# Cable trays along both edges of the walkway.
	for piece in _pieces(seg, float(seg["ramp_len"]) + 1.0, length):
		var mid := (piece.x + piece.y) / 2.0
		for side in [-1.0, 1.0]:
			for dy in [0.0, 1.0]:
				_item_box(parent, seg, mid, Vector3(side * (road_half + 0.32 + dy * 0.12), 0.16 + dy * 0.05, 0), Vector3(0.09, 0.09, piece.y - piece.x), Color("1a1c1e"))
		var b := ceilf(piece.x / 2.5) * 2.5
		while b < piece.y:
			for side in [-1.0, 1.0]:
				_item_box(parent, seg, b, Vector3(side * (road_half + 0.38), 0.06, 0), Vector3(0.45, 0.12, 0.22), Color("b08a30"))
			b += 2.5


## A tapering lattice antenna tower `height` tall at x: four legs leaning in, ties and zig-zag
## bracing on every face, three white cell panels and a small dish near the top, a blinking red
## light on top. Its foot on a low concrete plinth.
func _antenna_tower(parent: Node3D, seg: Dictionary, z: float, x: float, height: float) -> void:
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.transform = _frame_at(seg, z) * Transform3D(Basis.IDENTITY, Vector3(x, 0, 0))
	var steel := Color("7a7e82")
	var base := 1.5  # half the width at the foot
	var tip := 0.5  # ... and at the top
	_box(holder, Vector3(2.8, 0.3, 2.8), Vector3(0, 0.15, 0), Color("5e605c"))
	var lean := atan2(base - tip, height)
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			var leg := _box(holder, Vector3(0.24, height / cos(lean), 0.24), Vector3(cx * (base + tip) / 2.0, 0.3 + height / 2.0, cz * (base + tip) / 2.0), steel)
			leg.rotation = Vector3(-cz * lean, 0, cx * lean)  # leaning in toward the top
	var levels := int(height / 2.0)
	for i in levels + 1:
		var y := 0.3 + height * i / levels
		var hw := base + (tip - base) * float(i) / levels
		for f in [-1.0, 1.0]:
			_box(holder, Vector3(hw * 2.0, 0.12, 0.12), Vector3(0, y, f * hw), steel)
			_box(holder, Vector3(0.12, 0.12, hw * 2.0), Vector3(f * hw, y, 0), steel)
		if i < levels:  # zig-zag bracing up each face
			var y2 := 0.3 + height * (i + 1) / levels
			var hw2 := base + (tip - base) * float(i + 1) / levels
			var rise := y2 - y
			var dir := 1.0 if i % 2 == 0 else -1.0
			var span := hw + hw2
			var len_d := sqrt(span * span + rise * rise)
			var ang := atan2(rise, span)
			for f in [-1.0, 1.0]:
				var d1 := _box(holder, Vector3(len_d, 0.1, 0.1), Vector3(0, (y + y2) / 2.0, f * (hw + hw2) / 2.0), steel)
				d1.rotation.z = dir * ang
				var d2 := _box(holder, Vector3(0.1, 0.1, len_d), Vector3(f * (hw + hw2) / 2.0, (y + y2) / 2.0, 0), steel)
				d2.rotation.x = -dir * ang
	# The antennas: white cell panels round the top, a small dish, the red light.
	var top := 0.3 + height
	for k in 3:
		var a := TAU * k / 3.0 + 0.4
		var panel := _box(holder, Vector3(0.5, 2.0, 0.18), Vector3(cos(a) * (tip + 0.4), top - 1.2, sin(a) * (tip + 0.4)), Color("d8d8d0"))
		panel.rotation.y = -a + PI / 2.0
	var dish := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.55
	cone.bottom_radius = 0.1
	cone.height = 0.25
	cone.radial_segments = 10
	dish.mesh = cone
	dish.material_override = PsxMaterials.flat(Color("c8c8c0"))
	holder.add_child(dish)
	dish.position = Vector3(-signf(x) * (tip + 0.5), top - 2.6, 0)
	dish.rotation.z = signf(x) * 1.2
	_box(holder, Vector3(0.06, 0.06, 0.06) * 3.0, Vector3(0, top + 0.6, 0), steel)
	_box(holder, Vector3(0.05, 1.2, 0.05), Vector3(0, top + 0.3, 0), steel)  # the mast on top
	var red := _box(holder, Vector3(0.22, 0.22, 0.22), Vector3(0, top + 1.0, 0), Color.WHITE)
	red.material_override = _beacon_mat if _beacon_mat else PsxMaterials.glow(Color("ff3020"))
	_halo(holder, red.position, Color(1.0, 0.15, 0.08, 0.65), 2.8)
	var mid_red := _box(holder, Vector3(0.18, 0.18, 0.18), Vector3(tip + 0.5, 0.3 + height * 0.55, 0), Color.WHITE)
	mid_red.material_override = _beacon_mat if _beacon_mat else PsxMaterials.glow(Color("ff3020"))
	_halo(holder, mid_red.position, Color(1.0, 0.15, 0.08, 0.5), 1.8)


## A big satellite dish on `side`: a concrete plinth, a yoke mount, the dish tilted up at the sky
## (and a little toward the road), its feed arm out to the focus.
func _satellite_dish(parent: Node3D, seg: Dictionary, z: float, side: int) -> void:
	var road_half := tuning.lane_count * tuning.lane_width / 2.0
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.transform = _frame_at(seg, z) * Transform3D(Basis.IDENTITY, Vector3(side * (road_half + 4.2), 0, 0))
	var grey := Color("6a6c6a")
	_box(holder, Vector3(2.4, 0.9, 2.4), Vector3(0, 0.45, 0), Color("5e605c"))  # plinth
	_box(holder, Vector3(0.7, 1.1, 0.7), Vector3(0, 1.45, 0), grey)  # pedestal
	for dz in [-0.55, 0.55]:
		_box(holder, Vector3(0.14, 0.8, 0.14), Vector3(0, 2.3, dz), grey)  # the yoke
	var tilt := Node3D.new()
	holder.add_child(tilt)
	tilt.position = Vector3(0, 2.6, 0)
	tilt.rotation = Vector3(0.0, 0.0, side * 0.75)  # tipped up, its face toward the road and the sky
	var dish := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 2.6
	cone.bottom_radius = 0.4
	cone.height = 0.7
	cone.radial_segments = 16
	dish.mesh = cone
	dish.material_override = PsxMaterials.flat(Color("d0d0c8"))
	tilt.add_child(dish)
	dish.position = Vector3(0, 0.3, 0)
	_box(tilt, Vector3(0.6, 0.25, 0.6), Vector3(0, 0.05, 0), grey)  # its back
	for k in 3:  # the feed arm's struts out to the focus
		var a := TAU * k / 3.0
		var strut := _box(tilt, Vector3(0.05, 1.6, 0.05), Vector3(cos(a) * 0.7, 1.1, sin(a) * 0.7), Color("3a3c3e"))
		strut.rotation = Vector3(sin(a) * 0.4, 0, -cos(a) * 0.4)
	_box(tilt, Vector3(0.24, 0.3, 0.24), Vector3(0, 1.85, 0), Color("3a3c3e"))  # the feed


## An equipment cabinet near the walkway: grey steel with vent grilles, its door toward the road,
## a small warm lamp on its front corner if `lamp`.
func _equipment_cabinet(parent: Node3D, seg: Dictionary, z: float, x: float, side: int, lamp: bool) -> void:
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.transform = _frame_at(seg, z) * Transform3D(Basis.IDENTITY, Vector3(x, 0, 0))
	_box(holder, Vector3(1.3, 0.12, 1.5), Vector3(0, 0.06, 0), Color("4a4c4a"))  # its base
	_box(holder, Vector3(1.2, 1.35, 1.4), Vector3(0, 0.79, 0), Color.WHITE).material_override = \
			PsxMaterials.textured(PsxTextures.hvac(), Vector2(3, 2))
	_box(holder, Vector3(1.24, 0.06, 1.44), Vector3(0, 1.49, 0), Color("6e706c"))
	_box(holder, Vector3(0.02, 1.0, 0.04), Vector3(-side * 0.61, 0.8, 0), Color("2a2c2e"))  # the door's edge
	if lamp:
		var l := _box(holder, Vector3(0.22, 0.14, 0.12), Vector3(-side * 0.64, 0.35, 0.55), Color.WHITE)
		l.material_override = PsxMaterials.glow(Color("ffd890"))
		_halo(holder, l.position + Vector3(-side * 0.1, 0, 0), Color(1.0, 0.72, 0.38, 0.55), 1.3)
		var lp := MeshInstance3D.new()
		var lpm := PlaneMesh.new()
		lpm.size = Vector2(3.6, 3.6)
		lp.mesh = lpm
		lp.material_override = PsxMaterials.pool(Color(1.0, 0.68, 0.32, 0.32))
		holder.add_child(lp)
		lp.position = Vector3(-side * 1.6, 0.03, 0.4)
		var at := Node3D.new()
		holder.add_child(at)
		at.position = Vector3(-side * 1.2, 0.6, 0.6)
		_ambience.add_lamp(at, Color(1.0, 0.8, 0.5) * 0.9, 3.5, {"alert": false})


## ANTENNA FARM box cover: a grey equipment cabinet with vent grilles and a small lamp.
func _build_equip_box(parent: Node3D, seg: Dictionary, at: float, x: float, lane: int) -> Node3D:
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.transform = _frame_at(seg, at) * Transform3D(Basis.IDENTITY, Vector3(x, 0, 0))
	_box(holder, Vector3(1.0, 0.1, 0.9), Vector3(0, 0.05, 0), Color("4a4c4a"))
	_box(holder, Vector3(0.95, 1.18, 0.82), Vector3(0, 0.69, 0), Color.WHITE).material_override = \
			PsxMaterials.textured(PsxTextures.hvac(), Vector2(3, 2))
	_box(holder, Vector3(0.98, 0.05, 0.86), Vector3(0, 1.3, 0), Color("6e706c"))
	var l := _box(holder, Vector3(0.18, 0.12, 0.08), Vector3(0.3 if lane % 2 == 0 else -0.3, 0.3, 0.44), Color.WHITE)
	l.material_override = PsxMaterials.glow(Color("ffd890"))
	return holder


## ANTENNA FARM jump: a bundle of cables in a tray crossing the lane on yellow blocks.
func _build_cable_tray(parent: Node3D, seg: Dictionary, at: float, x: float, _lane: int) -> Node3D:
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.transform = _frame_at(seg, at) * Transform3D(Basis.IDENTITY, Vector3(x, 0, 0))
	var w := tuning.lane_width + 0.02
	for sx in [-0.45, 0.45]:
		_box(holder, Vector3(0.3, 0.2, 0.6), Vector3(sx, 0.1, 0), Color("b08a30"))  # blocks
	_box(holder, Vector3(w, 0.05, 0.5), Vector3(0, 0.22, 0), Color("5a5e60"))  # the tray
	for k in 4:
		var cz := -0.17 + k * 0.11
		_pipe_x(holder, Transform3D(Basis.IDENTITY, Vector3(0, 0.31 + (k % 2) * 0.06, cz)), w, 0.06, Color("16181a"))
	for sz in [-0.25, 0.25]:
		_box(holder, Vector3(w, 0.18, 0.03), Vector3(0, 0.33, sz), Color("5a5e60"))  # its sides
	return holder


## The ROOF EDGE's parapet (user reference) over span (x..y) at x: a tall concrete wall, pillars
## every 4 m each topped with a glowing red warning light, and a steel handrail between them.
func _roof_parapet(parent: Node3D, seg: Dictionary, span: Vector2, x: float, lip: float, side: int) -> void:
	var mid := (span.x + span.y) / 2.0
	var concrete := PsxMaterials.textured(PsxTextures.concrete(), Vector2(maxf(1.0, (span.y - span.x) / 2.0), 1))
	_item_box(parent, seg, mid, Vector3(x, lip + 0.04, 0), Vector3(0.42, 0.08, span.y - span.x + 0.2), Color("7a7a74"))  # coping
	_item_box(parent, seg, mid, Vector3(x, lip / 2.0, 0), Vector3(0.36, lip, span.y - span.x + 0.2), Color.WHITE).material_override = concrete
	_item_box(parent, seg, mid, Vector3(x - side * 0.05, lip + 0.42, 0), Vector3(0.07, 0.07, span.y - span.x), Color("4a4e52"))  # handrail
	var red := PsxMaterials.glow(Color("ff2a18"))
	var p := ceilf(span.x / 4.0) * 4.0
	var lit := 0
	while p <= span.y:
		_item_box(parent, seg, p, Vector3(x, (lip + 0.5) / 2.0, 0), Vector3(0.5, lip + 0.5, 0.5), Color.WHITE).material_override = concrete
		_item_box(parent, seg, p, Vector3(x, lip + 0.52, 0), Vector3(0.56, 0.05, 0.56), Color("7a7a74"))
		var light := _item_box(parent, seg, p, Vector3(x, lip + 0.68, 0), Vector3(0.22, 0.26, 0.22), Color.WHITE)
		light.material_override = red
		_halo_at(parent, seg, p, Vector3(x, lip + 0.7, 0), Color(1.0, 0.12, 0.06, 0.6), 1.7)
		_pool_at(parent, seg, p, x - side * 0.9, Color(1.0, 0.15, 0.08, 0.22), 1.6)
		if lit < 3 and int(p) % 12 == 0:
			_ambience.add_lamp(light, Color(1.0, 0.16, 0.1) * 0.9, 3.0, {"alert": false})
			lit += 1
		p += 4.0


## The ROOF EDGE's wide side (user reference): big air-con units on steel stands, utility boxes near
## the walkway, and one roof access hut with a lit door, a lamp over it and a red light on a mast.
## Clear of the last stretch before the ladders down.
func _roof_edge_decor(parent: Node3D, seg: Dictionary) -> void:
	var side := int(_theme(seg["id"]).get("wide_side", 1))
	var road_half := tuning.lane_count * tuning.lane_width / 2.0
	var until := float(seg["length"]) - tuning.decision_lead - tuning.fork_cue_length
	var hvac := PsxMaterials.textured(PsxTextures.hvac(), Vector2(3, 2))
	var z := float(seg["ramp_len"]) + 8.0
	var n := 0
	var hut_done := false
	while z < until - 4.0:
		var holder := Node3D.new()
		parent.add_child(holder)
		holder.transform = _frame_at(seg, z) * Transform3D(Basis.IDENTITY, Vector3(side * (road_half + 2.9), 0, 0))
		if not hut_done and n == 2:
			# The roof hut: concrete walls, a flat roof, a steel door toward the road with its lamp,
			# vents, and a mast with a red light.
			_box(holder, Vector3(3.2, 2.9, 3.6), Vector3(0.4 * side, 1.45, 0), Color.WHITE).material_override = \
					PsxMaterials.textured(PsxTextures.concrete(), Vector2(3, 2))
			_box(holder, Vector3(3.4, 0.15, 3.8), Vector3(0.4 * side, 2.97, 0), Color("4e504c"))
			var door := _box(holder, Vector3(0.06, DOOR_H - 0.3, 1.0), Vector3(0.4 * side - side * 1.62, (DOOR_H - 0.3) / 2.0, 0), Color.WHITE)
			door.material_override = PsxMaterials.textured(PsxTextures.steel_door(), Vector2(3, 2))
			var lamp := _box(holder, Vector3(0.16, 0.16, 0.5), Vector3(0.4 * side - side * 1.68, DOOR_H + 0.05, 0), Color.WHITE)
			lamp.material_override = PsxMaterials.glow(Color("ffd890"))
			_ambience.add_lamp(lamp, Color(1.0, 0.8, 0.5) * 1.3, 6.0, {"alert": false})
			_box(holder, Vector3(0.06, 0.6, 0.8), Vector3(0.4 * side - side * 1.62, 2.2, 1.2), Color.WHITE).material_override = \
					PsxMaterials.textured(PsxTextures.vent(), Vector2(3, 2))
			_box(holder, Vector3(0.08, 1.8, 0.08), Vector3(0.4 * side + side * 0.8, 3.95, -1.0), Color("3a3c3e"))  # the mast
			var red := _box(holder, Vector3(0.2, 0.2, 0.2), Vector3(0.4 * side + side * 0.8, 4.95, -1.0), Color.WHITE)
			red.material_override = _beacon_mat if _beacon_mat else PsxMaterials.glow(Color("ff3020"))
			hut_done = true
		else:
			# A big air-con unit on a steel stand, and a utility box in front of it near the walkway.
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					_box(holder, Vector3(0.1, 0.45, 0.1), Vector3(sx * 1.2, 0.22, sz * 1.0), Color("3a3c3e"))
			_box(holder, Vector3(2.6, 0.08, 2.2), Vector3(0, 0.47, 0), Color("3a3c3e"))
			_box(holder, Vector3(2.5, 2.2 + 0.3 * (n % 2), 2.1), Vector3(0, 0.51 + (2.2 + 0.3 * (n % 2)) / 2.0, 0), Color.WHITE).material_override = hvac
			_box(holder, Vector3(0.9, 0.9, 0.8), Vector3(-side * 2.2, 0.45, 1.6), Color.WHITE).material_override = hvac
			if n % 2 == 0:
				var wl := _box(holder, Vector3(0.12, 0.14, 0.3), Vector3(-side * 1.27, 1.6, 0.6), Color.WHITE)
				wl.material_override = PsxMaterials.glow(Color("ffd890"))
				_halo(holder, wl.position + Vector3(-side * 0.1, 0, 0), Color(1.0, 0.72, 0.38, 0.55), 1.4)
				var wp := MeshInstance3D.new()
				var wpm := PlaneMesh.new()
				wpm.size = Vector2(4.4, 4.4)
				wp.mesh = wpm
				wp.material_override = PsxMaterials.pool(Color(1.0, 0.68, 0.32, 0.3))
				holder.add_child(wp)
				wp.position = Vector3(-side * 3.0, 0.03, 0.6)
				_ambience.add_lamp(wl, Color(1.0, 0.8, 0.5) * 1.2, 5.0, {"alert": false})
		z += 13.0
		n += 1


## A soft glow round a light (see PsxMaterials.halo), `size` across, at `pos` in `parent`. It fades
## out as the camera comes within a few metres (PsxMaterials.lamp_halo), so it never flashes the
## screen as the camera passes a lamp.
func _halo(parent: Node3D, pos: Vector3, color: Color, size: float) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	m.mesh = q
	m.material_override = PsxMaterials.lamp_halo(color)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)
	m.position = pos
	return m


## ...the same at a point along a segment.
func _halo_at(parent: Node3D, seg: Dictionary, z: float, local: Vector3, color: Color, size: float) -> void:
	var at := Node3D.new()
	parent.add_child(at)
	at.transform = _frame_at(seg, z) * Transform3D(Basis.IDENTITY, local)
	_halo(at, Vector3.ZERO, color, size)


## A pool of light on the ground, `radius` across its glow, at a point along a segment (x across).
func _pool_at(parent: Node3D, seg: Dictionary, z: float, x: float, color: Color, radius: float) -> void:
	var m := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(radius * 2.0, radius * 2.0)
	m.mesh = plane
	m.material_override = PsxMaterials.pool(color)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)
	m.transform = _frame_at(seg, z) * Transform3D(Basis.IDENTITY, Vector3(x, 0.03, 0))


## A cone of light in the air from `from` to `to` (segment-local points at `z`), like a
## floodlight's beam through the haze: wide at the bottom, fading toward it.
func _beam_cone(parent: Node3D, seg: Dictionary, z: float, from: Vector3, to: Vector3, r_top: float, r_bottom: float, color: Color) -> void:
	var m := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	var dir := (from - to).normalized()
	var length := from.distance_to(to)
	# Tilted, its end ring would stick half out of the ground (user): carry it on until the ring's
	# top is under the ground, widening at the same rate.
	var tilt_sin := sqrt(maxf(0.0, 1.0 - dir.y * dir.y))
	var extra := (r_bottom * tilt_sin + 0.15) / maxf(absf(dir.y), 0.2)
	to -= dir * extra
	r_bottom += (r_bottom - r_top) * extra / length
	cyl.top_radius = r_top
	cyl.bottom_radius = r_bottom
	cyl.height = from.distance_to(to)
	cyl.radial_segments = 10
	cyl.cap_top = false
	cyl.cap_bottom = false
	m.mesh = cyl
	m.material_override = PsxMaterials.beam(color)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)
	m.transform = _frame_at(seg, z) * Transform3D(Basis(Quaternion(Vector3.UP, dir)), (from + to) / 2.0)


## A roof access hut at `z`, `x` (the roofs, user reference): concrete walls and a flat roof, a
## steel door facing the road (`face` -1 left, 1 right) with a warm lamp and its glow and pool over
## it, a vent, and a mast with a blinking red light.
func _roof_hut(parent: Node3D, seg: Dictionary, z: float, x: float, face: int) -> void:
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.transform = _frame_at(seg, z) * Transform3D(Basis.IDENTITY, Vector3(x, 0, 0))
	var front := face * 1.6
	_box(holder, Vector3(3.2, 2.9, 3.6), Vector3(0, 1.45, 0), Color.WHITE).material_override = \
			PsxMaterials.textured(PsxTextures.concrete(), Vector2(3, 2))
	_box(holder, Vector3(3.4, 0.15, 3.8), Vector3(0, 2.97, 0), Color("4e504c"))
	_box(holder, Vector3(0.06, DOOR_H - 0.3, 1.0), Vector3(front + face * 0.02, (DOOR_H - 0.3) / 2.0, 0), Color.WHITE).material_override = \
			PsxMaterials.textured(PsxTextures.steel_door(), Vector2(3, 2))
	var lamp := _box(holder, Vector3(0.16, 0.16, 0.5), Vector3(front + face * 0.08, DOOR_H + 0.05, 0), Color.WHITE)
	lamp.material_override = PsxMaterials.glow(Color("ffd890"))
	_halo(holder, lamp.position + Vector3(face * 0.1, 0, 0), Color(1.0, 0.75, 0.4, 0.55), 1.6)
	_ambience.add_lamp(lamp, Color(1.0, 0.8, 0.5) * 1.6, 7.0, {"alert": false})
	var pool := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(4.0, 4.0)
	pool.mesh = plane
	pool.material_override = PsxMaterials.pool(Color(1.0, 0.7, 0.35, 0.35))
	holder.add_child(pool)
	pool.position = Vector3(front + face * 1.6, 0.03, 0)
	_box(holder, Vector3(0.06, 0.6, 0.8), Vector3(front + face * 0.02, 2.2, 1.2), Color.WHITE).material_override = \
			PsxMaterials.textured(PsxTextures.vent(), Vector2(3, 2))
	_box(holder, Vector3(0.08, 1.8, 0.08), Vector3(-face * 0.8, 3.95, -1.0), Color("3a3c3e"))  # the mast
	var red := _box(holder, Vector3(0.2, 0.2, 0.2), Vector3(-face * 0.8, 4.95, -1.0), Color.WHITE)
	red.material_override = _beacon_mat if _beacon_mat else PsxMaterials.glow(Color("ff3020"))
	_halo(holder, red.position, Color(1.0, 0.15, 0.08, 0.6), 1.4)


## Gear crowded along a roof walkway's edges (the references are packed with it): air-con boxes,
## utility boxes, a red-and-white hose box, vent stacks, with a small warm lamp and its pool on
## some. Every `every` m, alternating sides, in the strip between the road and the roof's edge.
func _walkway_clutter(parent: Node3D, seg: Dictionary, every: float, from: float, until: float) -> void:
	var road_half := tuning.lane_count * tuning.lane_width / 2.0
	var hvac := PsxMaterials.textured(PsxTextures.hvac(), Vector2(3, 2))
	var z := from
	var n := 0
	while z < until:
		var near_bend := false
		for leg in seg["legs"]:
			if float(leg["start"]) > 0.0 and absf(float(leg["start"]) - z) < 5.0:
				near_bend = true
		var side := -1 if n % 2 == 0 else 1
		var hole: Vector2 = seg.get("holes", {}).get(side, Vector2.ZERO)
		if not near_bend and (z < hole.x - 2.0 or z > hole.y + 2.0):
			var x := side * (road_half + 0.55)
			match (n + absi(hash(seg["id"]))) % 4:
				0:
					_item_box(parent, seg, z, Vector3(x, 0.45, 0), Vector3(0.8, 0.9, 1.1), Color.WHITE).material_override = hvac
				1:
					_item_box(parent, seg, z, Vector3(x, 0.35, 0), Vector3(0.7, 0.7, 0.9), Color("6a6e70"))
					_item_box(parent, seg, z, Vector3(x - side * 0.36, 0.45, 0), Vector3(0.02, 0.3, 0.4), Color("2a2c2e"))
				2:
					var box := _item_box(parent, seg, z, Vector3(x, 0.3, 0), Vector3(0.5, 0.6, 0.9), Color("c42a20"))
					box.name = "HoseBox"
					_item_box(parent, seg, z, Vector3(x - side * 0.26, 0.3, 0), Vector3(0.02, 0.18, 0.86), Color("e8e4dc"))  # its white band
				3:
					_item_box(parent, seg, z, Vector3(x, 0.18, 0), Vector3(0.6, 0.36, 0.7), Color("5a5c5a"))
					for dz in [-0.16, 0.16]:
						_item_box(parent, seg, z + dz, Vector3(x, 0.7, 0), Vector3(0.14, 0.7, 0.14), Color("8a7a5a"))
			if n % 3 == 0:  # a small warm lamp on it, its glow and its pool on the walkway
				var lx := x - side * 0.42
				var lamp := _item_box(parent, seg, z + 0.3, Vector3(lx, 0.62, 0), Vector3(0.06, 0.12, 0.22), Color.WHITE)
				lamp.material_override = PsxMaterials.glow(Color("ffd890"))
				_halo_at(parent, seg, z + 0.3, Vector3(lx - side * 0.05, 0.62, 0), Color(1.0, 0.72, 0.38, 0.5), 0.9)
				_pool_at(parent, seg, z + 0.3, lx - side * 1.0, Color(1.0, 0.7, 0.35, 0.28), 1.8)
				_ambience.add_lamp(lamp, Color(1.0, 0.78, 0.45) * 1.0, 3.5, {"alert": false})
		z += every
		n += 1


## Lattice masts on the skyline far out either side, each with a red light and its glow, so the
## night is dotted with red like the references.
func _far_masts(parent: Node3D, seg: Dictionary, count: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seg["id"]) + 17
	var length: float = seg["length"]
	for k in count:
		var side := -1.0 if k % 2 == 0 else 1.0
		var z := rng.randf_range(10.0, length + 20.0)
		var x := side * rng.randf_range(24.0, 46.0)
		var tall := rng.randf_range(10.0, 22.0)
		var base := rng.randf_range(-6.0, 0.0)
		var at := minf(z, length)
		for cx in [-0.6, 0.6]:
			_item_box(parent, seg, at, Vector3(x + cx, base + tall / 2.0, -(z - at)), Vector3(0.14, tall, 0.14), Color("2a2c30"))
		for y in range(0, int(tall), 3):
			_item_box(parent, seg, at, Vector3(x, base + y + 1.5, -(z - at)), Vector3(1.2, 0.08, 0.08), Color("2a2c30"))
		var red := _item_box(parent, seg, at, Vector3(x, base + tall + 0.2, -(z - at)), Vector3(0.3, 0.3, 0.3), Color.WHITE)
		red.material_override = _beacon_mat if _beacon_mat else PsxMaterials.glow(Color("ff3020"))
		_halo_at(parent, seg, at, Vector3(x, base + tall + 0.2, -(z - at)), Color(1.0, 0.15, 0.08, 0.55), 2.4)


## The ROOFTOPS' low parapet over span (x..y) at x (user reference): a concrete wall to about knee
## height with a pale coping on top.
func _low_wall(parent: Node3D, seg: Dictionary, span: Vector2, x: float, lip: float) -> void:
	var mid := (span.x + span.y) / 2.0
	var l := span.y - span.x + 0.2
	_item_box(parent, seg, mid, Vector3(x, lip / 2.0, 0), Vector3(0.34, lip, l), Color.WHITE).material_override = \
			PsxMaterials.textured(PsxTextures.concrete(), Vector2(maxf(1.0, l / 2.0), 1))
	_item_box(parent, seg, mid, Vector3(x, lip + 0.04, 0), Vector3(0.44, 0.08, l), Color("7e7c76"))


## The ROOFTOPS' lamps (user reference): short posts along the walkway's edges, alternating sides,
## each with an angled head shining warm-white down onto the walkway, its glow and its pool.
func _roof_lamp_posts(parent: Node3D, seg: Dictionary) -> void:
	var road_half := tuning.lane_count * tuning.lane_width / 2.0
	var holes: Dictionary = seg.get("holes", {})
	var z := float(seg["ramp_len"]) + 5.0
	var n := 0
	var lit := 0
	while z < float(seg["length"]) - 2.0:
		var side := -1 if n % 2 == 0 else 1
		var hole: Vector2 = holes.get(side, Vector2.ZERO)
		if z < hole.x - 2.0 or z > hole.y + 2.0:
			var x := side * (road_half + 0.55)
			_item_box(parent, seg, z, Vector3(x, 0.8, 0), Vector3(0.12, 1.6, 0.12), Color("2a2c2e"))
			var head := Node3D.new()
			parent.add_child(head)
			head.transform = _frame_at(seg, z) * Transform3D(Basis.IDENTITY, Vector3(x - side * 0.18, 1.62, 0))
			head.rotation.z += side * 0.35  # tipped toward the walkway
			_box(head, Vector3(0.5, 0.16, 0.3), Vector3.ZERO, Color("1e2022"))
			var lens := _box(head, Vector3(0.42, 0.03, 0.24), Vector3(0, -0.09, 0), Color.WHITE)
			lens.material_override = PsxMaterials.glow(Color("f8f0d8"))
			_halo(head, Vector3(0, -0.12, 0), Color(1.0, 0.92, 0.75, 0.5), 1.5)
			_pool_at(parent, seg, z, x - side * 1.6, Color(1.0, 0.88, 0.65, 0.3), 2.8)
			var at := Node3D.new()
			parent.add_child(at)
			at.transform = _frame_at(seg, z) * Transform3D(Basis.IDENTITY, Vector3(x - side * 1.2, 1.2, 0))
			_ambience.add_lamp(at, Color(1.0, 0.92, 0.75) * 1.4, 6.0, {"flicker": 0.3 if lit % 5 == 4 else 0.0})
			lit += 1
		z += 8.0
		n += 1


## The ROOFTOPS beside the walkway (user reference): big air-con units with grilles on top and duct
## runs into them, a green electrical cabinet, raised roof blocks with ladders, a hazard band across
## the walkway, a roof hut near the end. Clear of the stairwells and bends.
func _office_roof_decor(parent: Node3D, seg: Dictionary) -> void:
	var length: float = seg["length"]
	var road_half := tuning.lane_count * tuning.lane_width / 2.0
	var hvac := PsxMaterials.textured(PsxTextures.hvac(), Vector2(3, 2))
	var grille := PsxMaterials.textured(PsxTextures.vent(), Vector2(3, 2))
	var duct := Color("8a8e90")
	var until := length - tuning.decision_lead - tuning.fork_cue_length - 2.0 if _is_authored_fork(seg["id"]) else length - 6.0
	for side in [-1, 1]:
		var hole: Vector2 = seg.get("holes", {}).get(side, Vector2.ZERO)
		var z := float(seg["ramp_len"]) + (8.0 if side < 0 else 13.0)
		var n := 0
		while z < until:
			var near := z > hole.x - 5.0 and z < hole.y + 5.0
			for leg in seg["legs"]:
				if float(leg["start"]) > 0.0 and absf(float(leg["start"]) - z) < 7.0:
					near = true
			if not near:
				var holder := Node3D.new()
				parent.add_child(holder)
				holder.transform = _frame_at(seg, z) * Transform3D(Basis.IDENTITY, Vector3(side * (road_half + 2.0), 0, 0))
				var out := float(side)
				match (n + (0 if side < 0 else 2)) % 4:
					0, 2:  # a big air-con unit with a grille on top, and its duct out to the parapet
						_box(holder, Vector3(2.2, 0.14, 2.9), Vector3(0, 0.07, 0), Color("3a3c3e"))
						_box(holder, Vector3(2.0, 1.6, 2.7), Vector3(0, 0.94, 0), Color.WHITE).material_override = hvac
						var top := _box(holder, Vector3(1.6, 0.04, 2.0), Vector3(0, 1.76, 0), Color.WHITE)
						top.material_override = grille
						_box(holder, Vector3(0.6, 0.6, 0.6), Vector3(out * 1.2, 0.95, -0.6), Color.WHITE).material_override = PsxMaterials.flat(duct)
						_box(holder, Vector3(2.2, 0.55, 0.55), Vector3(out * 2.4, 0.95, -0.6), Color.WHITE).material_override = PsxMaterials.flat(duct)  # duct run
						for dx in [1.8, 3.0]:
							_box(holder, Vector3(0.06, 0.7, 0.06), Vector3(out * dx, 0.35, -0.6), Color("3a3c3e"))  # its stands
					1:  # a green electrical cabinet and a small box beside it
						_box(holder, Vector3(1.0, 1.5, 1.4), Vector3(-out * 0.6, 0.75, 0), Color("2e4a30"))
						_box(holder, Vector3(0.02, 1.3, 0.04), Vector3(-out * 1.11, 0.75, 0), Color("1a2a1c"))  # the doors' split
						_box(holder, Vector3(0.02, 0.18, 0.26), Vector3(-out * 1.11, 1.15, 0.35), Color("e8e4dc"))  # its warning label
						_box(holder, Vector3(0.7, 0.6, 0.7), Vector3(out * 0.5, 0.3, 0.9), Color("6a6e70"))
					3:  # a raised roof block with a ladder up the side facing you
						_box(holder, Vector3(3.0, 2.6, 5.0), Vector3(out * 1.2, 1.3, 0), Color.WHITE).material_override = \
								PsxMaterials.textured(PsxTextures.concrete(), Vector2(3, 2))
						_box(holder, Vector3(3.1, 0.1, 5.1), Vector3(out * 1.2, 2.65, 0), Color("6a6c68"))
						for rz in [-0.22, 0.22]:
							_box(holder, Vector3(0.05, 3.2, 0.05), Vector3(-out * 0.32, 1.6, 2.0 + rz), Color("3a3c3e"))
						for ry in range(1, 9):
							_box(holder, Vector3(0.05, 0.04, 0.44), Vector3(-out * 0.32, ry * 0.36, 2.0), Color("3a3c3e"))
						var red := _box(holder, Vector3(0.18, 0.18, 0.18), Vector3(out * 2.3, 2.85, -2.0), Color.WHITE)
						red.material_override = _beacon_mat if _beacon_mat else PsxMaterials.glow(Color("ff3020"))
						_halo(holder, red.position, Color(1.0, 0.15, 0.08, 0.5), 1.4)
			z += 8.0
			n += 1
	# A hazard band across the walkway (a step in the roof), and a roof hut ahead near the end.
	var band := length * 0.55
	_strip(parent, seg, band - 0.35, band, 0.0, road_half * 2.0 + 1.6, 0.01, PsxTextures.hazard(), 10.0, 0.35)
	_roof_hut(parent, seg, until - 2.0, road_half + 3.4, -1)


## A cylinder lying along the road (a pipe down a wall), `length` long, centred on `xf`.
func _pipe_z(parent: Node3D, xf: Transform3D, length: float, radius: float, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = length
	cyl.radial_segments = 10
	m.mesh = cyl
	m.material_override = mat
	parent.add_child(m)
	m.transform = xf * Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3.ZERO)
	return m


## The SERVICE TUNNEL overhead and floor (user reference): concrete beams across at the pillars and a
## central air duct with grilles (both above the camera), a big rusty-red pipe on brackets along the
## left wall, a cable tray with red and black cables along the right, drainage grates along both
## edges of the floor.
func _service_overhead(parent: Node3D, seg: Dictionary, from: float) -> void:
	var length: float = seg["length"]
	var road_half := tuning.lane_count * tuning.lane_width / 2.0
	var wall := road_half + 1.0
	var rust := PsxMaterials.flat(Color("7a3420"))  # rusty red
	var duct := Color("6a6e70")
	var dark := Color("2a2c2e")
	for piece in _pieces(seg, from, length):
		var mid := (piece.x + piece.y) / 2.0
		var l: float = piece.y - piece.x
		var f := _frame_at(seg, mid)
		_pipe_z(parent, f * Transform3D(Basis.IDENTITY, Vector3(-(wall - 0.38), CEILING_Y - 0.7, 0)), l, 0.3, rust)
		_item_box(parent, seg, mid, Vector3(wall - 0.4, CEILING_Y - 0.85, 0), Vector3(0.5, 0.06, l), dark)  # cable tray
		for k in 3:
			var c := Color("8a2018") if k % 2 == 0 else Color("1a1a1a")
			_item_box(parent, seg, mid, Vector3(wall - 0.55 + k * 0.14, CEILING_Y - 0.78, 0), Vector3(0.08, 0.08, l), c)
		_item_box(parent, seg, mid, Vector3(wall - 0.25, CEILING_Y - 1.35, 0), Vector3(0.1, 0.1, l), dark)  # a lower conduit
		_item_box(parent, seg, mid, Vector3(-1.4, CEILING_Y - 0.56, 0), Vector3(1.0, 0.34, l), duct)  # the air duct, up out of the camera's way
		for s in [-1.0, 1.0]:  # drainage grates along the floor's edges, over the step up onto the kerb
			# (Laid under the kerb, they only showed where the vertex snap tipped them through it, and
			# on top of it, its edge's hairline crack showed past them.)
			_strip(parent, seg, piece.x, piece.y, s * road_half, 0.36, 0.028, PsxTextures.grating(), 1.0, 0.5)
	var b := ceilf(from / 3.0) * 3.0
	while b < length:  # pipe brackets
		_item_box(parent, seg, b, Vector3(-(wall - 0.3), CEILING_Y - 0.38, 0), Vector3(0.6, 0.06, 0.08), dark)
		_item_box(parent, seg, b, Vector3(-(wall - 0.62), CEILING_Y - 0.7, 0), Vector3(0.06, 0.7, 0.08), dark)
		b += 3.0
	var every: int = int(_theme(seg["id"]).get("pillar_every", 6))
	var z := ceilf(from / float(every)) * every
	while z < length:
		_item_box(parent, seg, z, Vector3(0, CEILING_Y - 0.18, 0), Vector3(wall * 2.0, 0.36, 0.5), Color("5a5850"))  # beam across
		var grille := _item_box(parent, seg, z + every / 2.0, Vector3(-1.4, CEILING_Y - 0.74, 0), Vector3(0.7, 0.02, 0.6), Color.WHITE)
		grille.material_override = PsxMaterials.textured(PsxTextures.vent(), Vector2(3, 2))
		z += every


## The SERVICE TUNNEL's walls (user reference): a caged warm bulkhead lamp on every pillar, both
## sides, with its glow and pool; between the pillars lockers, electrical boxes,
## crates, a tool cart, in turn.
func _service_decor(parent: Node3D, seg: Dictionary, side: int, from: float, to: float) -> void:
	var road_half := tuning.lane_count * tuning.lane_width / 2.0
	var face := side * (road_half + 0.2)  # the pillars' road face
	var every: int = int(_theme(seg["id"]).get("pillar_every", 6))
	var start := ceili(from / float(every)) * every
	var lit := 0
	for i in range(start, int(to), every):
		var near_bend := false
		for leg in seg["legs"]:
			if absf(float(leg["start"]) - i) < 1.3:
				near_bend = true
		if near_bend:
			continue
		var k := i / every
		if true:  # a lamp on every pillar (user: too dark to see the obstacles)
			var lamp := _item_box(parent, seg, i, Vector3(face - side * 0.1, 2.6, 0), Vector3(0.2, 0.36, 0.24), Color.WHITE)
			lamp.material_override = PsxMaterials.glow(Color("ffcf80"))
			for dy in [-0.1, 0.1]:  # its cage
				_item_box(parent, seg, i, Vector3(face - side * 0.21, 2.6 + dy, 0), Vector3(0.03, 0.03, 0.28), Color("2a2c2e"))
			_halo_at(parent, seg, i, Vector3(face - side * 0.25, 2.6, 0), Color(1.0, 0.72, 0.38, 0.55), 1.5)
			_pool_at(parent, seg, i, face - side * 1.4, Color(1.0, 0.7, 0.35, 0.3), 2.6)
			_ambience.add_lamp(lamp, Color(1.0, 0.8, 0.5) * 1.45, 7.5, {"flicker": 0.4 if lit % 6 == 5 else 0.0})
			lit += 1
		var at := float(i) + every / 2.0
		if at > to - 1.5:
			continue
		var holder := Node3D.new()
		parent.add_child(holder)
		holder.transform = _frame_at(seg, at) * Transform3D(Basis.IDENTITY, Vector3(side * (road_half + 0.7), 0, 0))
		var out := -float(side)
		match (k + absi(hash([seg["id"], side]))) % 4:
			0:  # a pair of grey-green lockers
				for dz in [-0.45, 0.45]:
					_box(holder, Vector3(0.5, 2.0, 0.86), Vector3(0, 1.0, dz), Color("4e5a50"))
					for vy in [1.75, 0.35]:
						_box(holder, Vector3(0.02, 0.1, 0.4), Vector3(out * 0.26, vy, dz), Color("2a302a"))  # vents
					_box(holder, Vector3(0.02, 0.2, 0.06), Vector3(out * 0.26, 1.0, dz + 0.3), Color("1a1e1a"))  # handle
			1:  # crates, wooden and olive
				_box(holder, Vector3(0.6, 0.7, 0.9), Vector3(0, 0.35, -0.3), Color.WHITE).material_override = \
						PsxMaterials.textured(PsxTextures.crate_wood(), Vector2(3, 2))
				_box(holder, Vector3(0.55, 0.6, 0.8), Vector3(0, 0.3, 0.6), Color.WHITE).material_override = \
						PsxMaterials.textured(PsxTextures.olive_crate(), Vector2(3, 2))
			2:  # an electrical box on the wall, conduit up from it
				_box(holder, Vector3(0.25, 1.2, 0.8), Vector3(side * 0.18, 1.5, 0), Color("6a6e6a"))
				_box(holder, Vector3(0.02, 1.0, 0.04), Vector3(side * 0.05, 1.5, 0), Color("2a2c2a"))
				_box(holder, Vector3(0.08, 2.0, 0.08), Vector3(side * 0.2, 3.1, 0.2), Color("2a2c2e"))
			3:  # a steel tool cart with toolboxes
				for cz in [-0.45, 0.45]:
					for cx in [-0.2, 0.2]:
						_box(holder, Vector3(0.04, 0.95, 0.04), Vector3(cx, 0.48, cz), Color("8a8e90"))  # legs
				for sy in [0.25, 0.92]:
					_box(holder, Vector3(0.48, 0.03, 0.96), Vector3(0, sy, 0), Color("8a8e90"))
				_box(holder, Vector3(0.36, 0.22, 0.5), Vector3(0, 1.05, -0.2), Color("a83020"))  # red toolbox
				_box(holder, Vector3(0.3, 0.2, 0.36), Vector3(0, 0.37, 0.2), Color("3a4a3a"))
				_box(holder, Vector3(0.3, 0.24, 0.36), Vector3(0, 0.39, -0.25), Color("a89a30"))


## Every alcove on this side ("alcove" in route.json: one, or a list), each as {"span", "kind"}.
func _alcoves(seg: Dictionary, side: int) -> Array[Dictionary]:
	var raw = _graph.node_data(seg["id"]).get("alcove", [])
	var list: Array = raw if raw is Array else [raw]
	var out: Array[Dictionary] = []
	for a in list:
		if a is Dictionary and (-1 if String(a.get("side", "right")) == "left" else 1) == side:
			var at := float(a["at"])
			out.append({"span": Vector2(at, at + float(a.get("length", 16.0))), "kind": String(a.get("kind", "kitchen"))})
	return out


## A BOILER ROOM bay (user reference) behind the opening `span` in this side wall: a room 7 m deep
## the hall's full height, its steel-plate floor, back and end walls, ceiling and beams; big rusty
## boilers on saddles with glowing fireboxes toward you, gauges, red valve wheels, pipes up to the
## ceiling (steam from some); control panels between them; yellow-and-black safety frames along
## the walkway; steel columns at the opening; a catwalk along the back under warm wall lamps.
func _build_boiler_bay(parent: Node3D, seg: Dictionary, side: int, span: Vector2, pumps: bool = false) -> void:
	var road_half := tuning.lane_count * tuning.lane_width / 2.0
	var wx := side * (road_half + 1.0)
	var depth := 7.0
	var top := _ceil(seg["id"])
	var mid := (span.x + span.y) / 2.0
	var L := span.y - span.x
	var out := func(d: float) -> float: return wx + side * d  # d metres back from the opening
	var wall_tex := PsxTextures.service_wall() if pumps else PsxTextures.boiler_wall()  # the PUMP STATION: pale concrete
	var wall := PsxMaterials.textured(wall_tex, Vector2(L / 2.0, top / 2.0))
	var dark := Color("2a2c2e")
	# The room.
	_strip(parent, seg, span.x, span.y, side * (road_half + (1.0 + depth) / 2.0), 1.0 + depth, 0.0, PsxTextures.service_floor() if pumps else PsxTextures.steel_plate(),
			(1.0 + depth) / tuning.lane_width, tuning.lane_width)
	_item_box(parent, seg, mid, Vector3(out.call(depth), top / 2.0, 0), Vector3(0.2, top, L + 2.4), Color.WHITE).material_override = wall
	for z in [span.x, span.y]:
		_item_box(parent, seg, z, Vector3(out.call(depth / 2.0), top / 2.0, 0), Vector3(depth, top, 0.2), Color.WHITE).material_override = \
				PsxMaterials.textured(wall_tex, Vector2(depth / 2.0, top / 2.0))
	_item_box(parent, seg, mid, Vector3(out.call(depth / 2.0), top + 0.05, 0), Vector3(depth + 0.2, 0.1, L + 2.4), Color("26282a"))
	var b := span.x + 3.0
	while b < span.y - 1.0:
		_item_box(parent, seg, b, Vector3(out.call(depth / 2.0), top - 0.3, 0), Vector3(depth, 0.4, 0.35), dark)  # beams
		b += 6.0
	# Steel columns at the opening, a hazard band at their feet.
	var c := span.x
	while c <= span.y + 0.01:
		_item_box(parent, seg, c, Vector3(wx, top / 2.0, 0), Vector3(0.5, top, 0.5), Color("3e4244"))
		_item_box(parent, seg, c, Vector3(wx, 0.4, 0), Vector3(0.54, 0.8, 0.54), Color.WHITE).material_override = \
				PsxMaterials.textured(PsxTextures.hazard(), Vector2(2, 2))
		c += L / maxf(1.0, roundf(L / 10.0))
	# The boilers, one to every 11 m or so, with a control panel between.
	var n := maxi(1, int((L - 2.0) / 11.0))
	var step := L / n
	for k in n:
		var bz := span.x + step * (k + 0.5)
		if pumps:
			_pump(parent, seg, bz, out.call(3.6), side, k, minf(step - 2.5, 8.5))
		else:
			_boiler(parent, seg, bz, out.call(3.6), side, k, minf(step - 2.5, 8.5))
		if k < n - 1:
			var panel := Node3D.new()
			parent.add_child(panel)
			panel.transform = _frame_at(seg, span.x + step * (k + 1)) * Transform3D(Basis.IDENTITY, Vector3(out.call(1.2), 0, 0))
			_box(panel, Vector3(0.8, 1.8, 1.1), Vector3(0, 0.9, 0), Color("4a4e52"))
			for ly in [1.45, 1.3]:
				for lz in [-0.25, 0.0, 0.25]:
					var l := _box(panel, Vector3(0.02, 0.06, 0.06), Vector3(-side * 0.41, ly, lz), Color.WHITE)
					l.material_override = PsxMaterials.glow(Color("ff3020") if (k + int(lz * 8.0)) % 2 == 0 else Color("40d060"))
			_box(panel, Vector3(0.02, 0.5, 0.7), Vector3(-side * 0.41, 0.8, 0), Color("2a2c2e"))  # its switchgear
	# Yellow-and-black safety frames along the walkway, in front of each boiler; at the pumps, a
	# yellow pipe railing along the whole bay.
	if pumps:
		_yellow_rail(parent, seg, span.x + 0.5, span.y - 0.5, side * (road_half + 0.55))
	for k in (0 if pumps else n):
		var fz := span.x + step * (k + 0.5)
		for dz in [-1.6, 1.6]:
			_item_box(parent, seg, fz + dz, Vector3(side * (road_half + 0.55), 0.55, 0), Vector3(0.12, 1.1, 0.12), Color.WHITE).material_override = \
					PsxMaterials.textured(PsxTextures.hazard(), Vector2(1, 3))
		_item_box(parent, seg, fz, Vector3(side * (road_half + 0.55), 1.05, 0), Vector3(0.12, 0.12, 3.3), Color.WHITE).material_override = \
				PsxMaterials.textured(PsxTextures.hazard(), Vector2(6, 1))
	# The catwalk along the back wall, its hazard railing, its supports, and warm lamps over it.
	var cy := 4.5
	_item_box(parent, seg, mid, Vector3(out.call(depth - 1.0), cy, 0), Vector3(2.0, 0.1, L - 0.4), Color.WHITE).material_override = \
			PsxMaterials.textured(PsxTextures.grating(), Vector2(3.0 * 2.0 / 1.4, 2.0 * L / 1.4))
	_item_box(parent, seg, mid, Vector3(out.call(depth - 2.0), cy + 1.0, 0), Vector3(0.08, 0.08, L - 0.4), Color.WHITE).material_override = \
			PsxMaterials.textured(PsxTextures.hazard(), Vector2(L / 1.2, 1))
	_item_box(parent, seg, mid, Vector3(out.call(depth - 2.0), cy + 0.5, 0), Vector3(0.05, 0.05, L - 0.4), dark)
	var p := span.x + 1.0
	var lit := 0
	while p < span.y - 0.5:
		_item_box(parent, seg, p, Vector3(out.call(depth - 2.0), cy + 0.5, 0), Vector3(0.06, 1.0, 0.06), Color("8a7a30"))
		_item_box(parent, seg, p, Vector3(out.call(depth - 2.0), cy / 2.0, 0), Vector3(0.14, cy, 0.14), dark)  # supports
		if int(p - span.x) % 8 == 1:
			var lamp := _item_box(parent, seg, p, Vector3(out.call(depth - 0.12), cy + 1.6, 0), Vector3(0.12, 0.3, 0.3), Color.WHITE)
			lamp.material_override = PsxMaterials.glow(Color("ffd890"))
			_halo_at(parent, seg, p, Vector3(out.call(depth - 0.25), cy + 1.6, 0), Color(1.0, 0.72, 0.38, 0.5), 1.4)
			if lit < 3:
				_ambience.add_lamp(lamp, Color(1.0, 0.78, 0.45) * 1.2, 6.0, {"alert": false})
				lit += 1
		p += 2.0


## One boiler in a bay at `z`, its axis along the road at x: a rusty horizontal drum on saddles,
## its glowing firebox toward the walkway, a gauge, a red valve wheel, pipes up to the ceiling
## (steam off some), `length` long.
func _boiler(parent: Node3D, seg: Dictionary, z: float, x: float, side: int, k: int, length: float) -> void:
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.transform = _frame_at(seg, z) * Transform3D(Basis.IDENTITY, Vector3(x, 0, 0))
	var face := -float(side)  # toward the walkway
	var r := 1.6
	var cy := 2.15
	_pipe_z(holder, Transform3D(Basis.IDENTITY, Vector3(0, cy, 0)), length, r, PsxMaterials.textured(PsxTextures.boiler_shell(), Vector2(5, 2)))
	for e in [-1.0, 1.0]:
		_pipe_z(holder, Transform3D(Basis.IDENTITY, Vector3(0, cy, e * (length / 2.0 - 0.15))), 0.3, r + 0.08, PsxMaterials.flat(Color("3a3836")))  # end bands
		_box(holder, Vector3(2.4, 0.8, 0.5), Vector3(0, 0.4, e * (length / 2.0 - 1.2)), Color("3a3c3e"))  # saddles
	# The firebox: a dark housing low on the walkway side, its grate glowing orange.
	_box(holder, Vector3(0.7, 1.1, 1.6), Vector3(face * (r - 0.1), 1.0, 0), Color("2a2826"))
	for s in 4:
		var slat := _box(holder, Vector3(0.04, 0.6, 0.2), Vector3(face * (r + 0.26), 1.0, -0.45 + s * 0.3), Color.WHITE)
		slat.material_override = PsxMaterials.glow(Color("ff7a20"))
	_halo(holder, Vector3(face * (r + 0.4), 1.0, 0), Color(1.0, 0.45, 0.12, 0.55), 2.4)
	var fire := Node3D.new()
	holder.add_child(fire)
	fire.position = Vector3(face * (r + 1.2), 1.0, 0)
	_ambience.add_lamp(fire, Color(1.0, 0.45, 0.15) * 1.8, 6.0, {"alert": false, "flicker": 0.25})
	var over := Node3D.new()  # a lamp up over it, so you see the boiler from the walkway
	holder.add_child(over)
	over.position = Vector3(face * 1.0, cy + r + 1.6, 0)
	_ambience.add_lamp(over, Color(1.0, 0.82, 0.55) * 1.4, 7.0, {"alert": false})
	var glow_floor := MeshInstance3D.new()
	var gp := PlaneMesh.new()
	gp.size = Vector2(3.6, 3.6)
	glow_floor.mesh = gp
	glow_floor.material_override = PsxMaterials.pool(Color(1.0, 0.42, 0.12, 0.35))
	holder.add_child(glow_floor)
	glow_floor.position = Vector3(face * (r + 1.0), 0.03, 0)
	# A pressure gauge and a red valve wheel on the walkway side.
	var gz := length / 2.0 - 1.4
	_box(holder, Vector3(0.3, 0.08, 0.08), Vector3(face * (r + 0.1), cy + 0.8, gz), Color("4a4846"))
	var gauge := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.22
	disc.bottom_radius = 0.22
	disc.height = 0.06
	disc.radial_segments = 12
	gauge.mesh = disc
	gauge.material_override = PsxMaterials.flat(Color("e8e4d8"))
	holder.add_child(gauge)
	gauge.position = Vector3(face * (r + 0.28), cy + 0.8, gz)
	gauge.rotation.z = PI / 2.0
	_box(holder, Vector3(0.02, 0.16, 0.02), Vector3(face * (r + 0.32), cy + 0.84, gz), Color("1a1a1a"))  # its needle
	var wheel := Node3D.new()
	holder.add_child(wheel)
	wheel.position = Vector3(face * (r + 0.35), cy + 0.2, -gz)
	var red := Color("a01e18")
	for s in 8:
		var a := TAU * s / 8.0
		var rim := _box(wheel, Vector3(0.06, 0.06, 0.22), Vector3(0, sin(a) * 0.32, cos(a) * 0.32), red)
		rim.rotation.x = -(a + PI / 2.0)  # along the rim
	for s in 2:
		var spoke := _box(wheel, Vector3(0.04, 0.64, 0.04), Vector3.ZERO, red)
		spoke.rotation.x = s * PI / 2.0
	_box(holder, Vector3(0.35, 0.1, 0.1), Vector3(face * (r + 0.15), cy + 0.2, -gz), Color("4a4846"))
	# Pipes up to the ceiling: rusty red or grey, with flanges, steam off some.
	var top := _ceil(seg["id"])
	for pz in [-length / 4.0, length / 4.0]:
		var rusty := (k + int(pz > 0.0)) % 2 == 0
		var pm := PsxMaterials.flat(Color("7a3420") if rusty else Color("5a5e60"))
		var ph := top - (cy + r)
		var pipe := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.26
		cyl.bottom_radius = 0.26
		cyl.height = ph
		cyl.radial_segments = 10
		pipe.mesh = cyl
		pipe.material_override = pm
		holder.add_child(pipe)
		pipe.position = Vector3(0.3 * face, cy + r + ph / 2.0 - 0.1, pz)
		var flange := MeshInstance3D.new()
		var fc := CylinderMesh.new()
		fc.top_radius = 0.36
		fc.bottom_radius = 0.36
		fc.height = 0.16
		fc.radial_segments = 10
		flange.mesh = fc
		flange.material_override = PsxMaterials.flat(Color("3a3836"))
		holder.add_child(flange)
		flange.position = Vector3(0.3 * face, cy + r + 1.2, pz)
	if k % 2 == 0:
		var steam := Steam.new(4, hash([seg["id"], z]))
		holder.add_child(steam)
		steam.position = Vector3(face * 0.6, cy + r + 0.1, 0)
		_audio.attach_loop(steam, "steam", -14.0, 10.0, 2.0)


## BOILER ROOM jump: a yellow-and-black safety rail across the lane, two posts and two rails.
func _build_safety_rail(parent: Node3D, seg: Dictionary, at: float, x: float, _lane: int) -> Node3D:
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.transform = _frame_at(seg, at) * Transform3D(Basis.IDENTITY, Vector3(x, 0, 0))
	var hz := PsxMaterials.textured(PsxTextures.hazard(), Vector2(4, 1))
	var w := tuning.lane_width - 0.1
	for sx in [-w / 2.0 + 0.06, w / 2.0 - 0.06]:
		_box(holder, Vector3(0.1, 0.6, 0.1), Vector3(sx, 0.3, 0), Color.WHITE).material_override = \
				PsxMaterials.textured(PsxTextures.hazard(), Vector2(1, 2))
		_box(holder, Vector3(0.24, 0.04, 0.24), Vector3(sx, 0.02, 0), Color("3a3c3e"))  # its foot
	_box(holder, Vector3(w, 0.1, 0.08), Vector3(0, 0.56, 0), Color.WHITE).material_override = hz
	_box(holder, Vector3(w, 0.08, 0.06), Vector3(0, 0.28, 0), Color.WHITE).material_override = hz
	return holder


## The BOILER ROOM's hall lamps (user reference): industrial lamps hanging on cables over the
## walkway from the high ceiling, each with its glow and pool; beams across the ceiling.
func _hall_lamps(parent: Node3D, seg: Dictionary) -> void:
	var top := _ceil(seg["id"])
	var road_half := tuning.lane_count * tuning.lane_width / 2.0
	var z := float(seg["ramp_len"]) + 6.0
	var n := 0
	while z < float(seg["length"]) - 2.0:
		var y := top - 2.0
		_item_box(parent, seg, z, Vector3(0, (y + top) / 2.0, 0), Vector3(0.03, top - y, 0.03), Color("1a1a1a"))
		_item_box(parent, seg, z, Vector3(0, y, 0), Vector3(0.7, 0.24, 0.5), Color("2a2c2e"))
		var lens := _item_box(parent, seg, z, Vector3(0, y - 0.13, 0), Vector3(0.6, 0.03, 0.42), Color.WHITE)
		lens.material_override = PsxMaterials.glow(Color("fff0c8"))
		_halo_at(parent, seg, z, Vector3(0, y - 0.25, 0), Color(1.0, 0.9, 0.7, 0.4), 2.2)
		_pool_at(parent, seg, z, 0.0, Color(1.0, 0.85, 0.6, 0.22), 3.4)
		var at := Node3D.new()
		parent.add_child(at)
		at.transform = _frame_at(seg, z) * Transform3D(Basis.IDENTITY, Vector3(0, y - 1.5, 0))
		_ambience.add_lamp(at, Color(_theme(seg["id"]).get("lamp_color", Color(1.0, 0.9, 0.7))) * 2.5, 11.0, {"flicker": 0.3 if n % 5 == 4 else 0.0})
		_item_box(parent, seg, z + 3.0, Vector3(0, top - 0.25, 0), Vector3(road_half * 2.0 + 2.0, 0.5, 0.4), Color("26282a"))  # a beam
		z += 12.0
		n += 1


## A SEWER channel (user reference) behind the opening `span` in this side wall: dark green water
## below the walkway's kerb with the lamps streaking on it, a stone ledge with yellow railings past
## it, the far brick wall with stone pillars and yellow wall lamps, a big rusty pipe along its
## ceiling, and water pouring from pipes in the far wall into the channel.
func _build_sewer_channel(parent: Node3D, seg: Dictionary, side: int, span: Vector2, basin: bool = false) -> void:
	var road_half := tuning.lane_count * tuning.lane_width / 2.0
	var mid := (span.x + span.y) / 2.0
	var L := span.y - span.x
	var kerb := road_half + 0.5  # the water starts here
	var water_w := 5.0
	var ledge := 1.6
	var back := kerb + water_w + ledge
	var top := _ceil(seg["id"])
	var wl := -0.55  # the water level
	var x := func(d: float) -> float: return side * d
	var brick := PsxTextures.service_wall() if basin else PsxTextures.sewer_wall()  # the PUMP STATION's basin: pale concrete
	var stone := Color("6a6a62") if basin else Color("5a5c52")
	# The kerb strip, the channel's sides and bottom, the water.
	_strip(parent, seg, span.x, span.y, x.call(road_half + 0.25), 0.5, 0.0, PsxTextures.service_floor() if basin else PsxTextures.sewer_floor(), 0.5 / tuning.lane_width, tuning.lane_width)
	if basin:  # a yellow railing along the walkway's edge
		_yellow_rail(parent, seg, span.x + 0.5, span.y - 0.5, x.call(kerb - 0.1))
	_item_box(parent, seg, mid, Vector3(x.call(kerb + 0.05), (wl - 0.7) / 2.0, 0), Vector3(0.1, 0.7 - wl + 0.02, L), Color.WHITE).material_override = \
			PsxMaterials.textured(brick, Vector2(L / 2.0, 1))
	_item_box(parent, seg, mid, Vector3(x.call(kerb + water_w / 2.0), -1.2, 0), Vector3(water_w, 0.1, L), Color("141a12"))  # bottom
	var water := _item_box(parent, seg, mid, Vector3(x.call(kerb + water_w / 2.0), wl, 0), Vector3(water_w, 0.02, L), Color.WHITE)
	water.material_override = PsxMaterials.glass(Color(0.04, 0.16, 0.17, 0.9) if basin else Color(0.04, 0.08, 0.05, 0.94))  # dark, still water (teal in the basin)
	if basin:  # sluice gates standing in the water, and concrete blocks
		var g := span.x + 6.0
		while g < span.y - 3.0:
			for gx in [kerb + water_w * 0.5, kerb + water_w * 0.5 + 1.2]:
				_item_box(parent, seg, g, Vector3(x.call(gx), 1.0, 0), Vector3(0.25, 3.2, 0.25), Color("2e3438"))
			_item_box(parent, seg, g, Vector3(x.call(kerb + water_w * 0.5 + 0.6), 0.6, 0), Vector3(1.0, 2.2, 0.12), Color("3a4248"))  # the gate
			_item_box(parent, seg, g, Vector3(x.call(kerb + water_w * 0.5 + 0.6), 2.7, 0), Vector3(1.6, 0.25, 0.4), Color("2e3438"))  # its winding gear
			_item_box(parent, seg, g + 4.0, Vector3(x.call(kerb + 1.2), wl + 0.3, 0), Vector3(1.4, 1.4, 1.4), Color("6a6a62"))  # a block
			g += 12.0
	_item_box(parent, seg, mid, Vector3(x.call(kerb + water_w + 0.05), (wl - 0.7) / 2.0, 0), Vector3(0.1, 0.7 - wl + 0.02, L), Color.WHITE).material_override = \
			PsxMaterials.textured(brick, Vector2(L / 2.0, 1))
	# The far ledge, its yellow railing, the far wall and the ceiling over it all.
	_strip(parent, seg, span.x, span.y, x.call(kerb + water_w + ledge / 2.0), ledge, 0.0, PsxTextures.sewer_floor(), ledge / tuning.lane_width, tuning.lane_width)
	_item_box(parent, seg, mid, Vector3(x.call(kerb + water_w + 0.15), 1.0, 0), Vector3(0.06, 0.06, L), Color("c8a020"))
	_item_box(parent, seg, mid, Vector3(x.call(kerb + water_w + 0.15), 0.55, 0), Vector3(0.05, 0.05, L), Color("c8a020"))
	_item_box(parent, seg, mid, Vector3(x.call(back), top / 2.0, 0), Vector3(0.2, top, L + 2.4), Color.WHITE).material_override = \
			PsxMaterials.textured(brick, Vector2(L / 2.0, top / 2.0))
	_item_box(parent, seg, mid, Vector3(x.call((road_half + 1.0 + back) / 2.0), top + 0.05, 0), Vector3(back - road_half - 1.0 + 0.2, 0.1, L + 2.4), Color("2e322a"))
	for z in [span.x, span.y]:  # the end walls, down into the channel
		_item_box(parent, seg, z, Vector3(x.call((road_half + 1.0 + back) / 2.0), (top + wl - 0.7) / 2.0, 0), Vector3(back - road_half - 1.0, top - wl + 0.7, 0.2), Color.WHITE).material_override = \
				PsxMaterials.textured(brick, Vector2(3, 2))
		# ...and under the walkway's edge, below the floor, from the channel's near side: open there,
		# it showed the void under the floor at each end of the channel (the user's gaps). (Only to
		# be seen: it adds no line-of-sight block.)
		var under := _item_box(parent, seg, z, Vector3(x.call((kerb + road_half + 1.0) / 2.0), (wl - 0.7 - 0.02) / 2.0, 0), Vector3(road_half + 1.0 - kerb + 0.02, 0.7 - wl - 0.02, 0.2), Color.WHITE)
		under.material_override = PsxMaterials.textured(brick, Vector2(1, 1))
		under.set_meta("solid", true)
	_pipe_z(parent, _frame_at(seg, mid) * Transform3D(Basis.IDENTITY, Vector3(x.call(kerb + water_w * 0.6), top - 0.7, 0)), L, 0.45,
			PsxMaterials.flat(Color("6a3a22")))
	# Stone pillars along the opening and the far wall, lamps on the far ones, railing posts.
	var p := span.x
	var n := 0
	var lit := 0
	while p <= span.y + 0.01:
		_item_box(parent, seg, p, Vector3(x.call(road_half + 1.0), top / 2.0, 0), Vector3(0.6, top, 0.6), stone)
		_item_box(parent, seg, p, Vector3(x.call(back - 0.3), top / 2.0, 0), Vector3(0.6, top, 0.6), stone)
		_item_box(parent, seg, p, Vector3(x.call(road_half + 1.0), top - 0.3, 0), Vector3(back - road_half - 1.0, 0.4, 0.4), Color("3a3e36"))  # a beam across
		if n % 2 == 1 and lit < 4:
			var lamp := _item_box(parent, seg, p, Vector3(x.call(back - 0.65), 2.4, 0), Vector3(0.12, 0.3, 0.24), Color.WHITE)
			lamp.material_override = PsxMaterials.glow(Color("f0e070"))
			_halo_at(parent, seg, p, Vector3(x.call(back - 0.8), 2.4, 0), Color(0.95, 0.85, 0.4, 0.5), 1.5)
			_ambience.add_lamp(lamp, Color(0.95, 0.88, 0.5) * 1.3, 6.0, {"alert": false})
			# Its light streaking on the water toward you.
			var streak := MeshInstance3D.new()
			var sp := PlaneMesh.new()
			sp.size = Vector2(0.7, 4.5)
			streak.mesh = sp
			streak.material_override = PsxMaterials.pool(Color(0.95, 0.85, 0.4, 0.32))
			parent.add_child(streak)
			streak.transform = _frame_at(seg, p + 2.0) * Transform3D(Basis.IDENTITY, Vector3(x.call(kerb + water_w * 0.55), wl + 0.03, 0))
			lit += 1
		for r in 3:  # ripples catching the light
			var rip := MeshInstance3D.new()
			var rp := PlaneMesh.new()
			rp.size = Vector2(0.18, 1.4)
			rip.mesh = rp
			rip.material_override = PsxMaterials.pool(Color(0.85, 0.95, 0.75, 0.28))
			parent.add_child(rip)
			rip.transform = _frame_at(seg, p + 1.5 + r * 2.2) * Transform3D(Basis.IDENTITY, Vector3(x.call(kerb + 0.8 + r * 1.4), wl + 0.03, 0))
		for q in [p + 2.0, p + 4.0]:
			if q < span.y:
				_item_box(parent, seg, q, Vector3(x.call(kerb + water_w + 0.15), 0.5, 0), Vector3(0.06, 1.0, 0.06), Color("c8a020"))
		# Water pouring from a pipe in the far wall, now and then.
		if not basin and n % 3 == 1 and p + 4.0 < span.y:
			var wz := p + 4.0
			_pipe_x(parent, _frame_at(seg, wz) * Transform3D(Basis.IDENTITY, Vector3(x.call(back - 0.5), 2.2, 0)), 1.0, 0.3, Color("6a3a22"))
			_waterfall(parent, seg, wz, Vector3(x.call(back - 1.0), 2.05, 0), Vector3(x.call(back - 1.35), wl, 0), 0.45)
			_halo_at(parent, seg, wz, Vector3(x.call(back - 1.1), wl + 0.25, 0), Color(0.8, 0.9, 0.8, 0.45), 2.0)
			_halo_at(parent, seg, wz, Vector3(x.call(back - 1.1), 1.2, 0), Color(0.8, 0.9, 0.8, 0.18), 1.4)
			var splash := MeshInstance3D.new()  # the churned water where it lands
			var spm := PlaneMesh.new()
			spm.size = Vector2(1.6, 1.6)
			splash.mesh = spm
			splash.material_override = PsxMaterials.pool(Color(0.8, 0.9, 0.82, 0.4))
			parent.add_child(splash)
			splash.transform = _frame_at(seg, wz) * Transform3D(Basis.IDENTITY, Vector3(x.call(back - 1.3), wl + 0.03, 0))
		p += 8.0
		n += 1


## The SEWER's walls on the walkway side (user reference): yellow wall lamps on the pillars with
## their glow and pools, vents, and crates, steel cases and rusty drums on pallets, papers on the
## floor; a rusty pipe along the wall up high.
func _sewer_decor(parent: Node3D, seg: Dictionary, side: int, from: float, to: float) -> void:
	var road_half := tuning.lane_count * tuning.lane_width / 2.0
	var wall := road_half + 1.0
	var spans: Array[Vector2] = [Vector2(from, to)]
	for a in _alcoves(seg, side):
		spans = _cut_spans(spans, a["span"])
	for sp in spans:
		for piece in _pieces(seg, sp.x, sp.y):
			_pipe_z(parent, _frame_at(seg, (piece.x + piece.y) / 2.0) * Transform3D(Basis.IDENTITY, Vector3(side * (wall - 0.35), CEILING_Y - 0.5, 0)),
					piece.y - piece.x, 0.28, PsxMaterials.flat(Color("6a3a22")))
		var every := 8
		var i := ceili(sp.x / float(every)) * every
		var lit := 0
		while i < sp.y - 1.0:
			var near_bend := false
			for leg in seg["legs"]:
				if absf(float(leg["start"]) - i) < 1.5:
					near_bend = true
			if not near_bend:
				var k := i / every
				if k % 2 == 0:
					var lamp := _item_box(parent, seg, i, Vector3(side * (road_half + 0.15), 2.5, 0), Vector3(0.12, 0.3, 0.24), Color.WHITE)
					lamp.material_override = PsxMaterials.glow(Color("f0e070"))
					_halo_at(parent, seg, i, Vector3(side * (road_half + 0.05), 2.5, 0), Color(0.95, 0.85, 0.4, 0.5), 1.4)
					_pool_at(parent, seg, i, side * (road_half - 0.8), Color(0.95, 0.85, 0.45, 0.28), 2.4)
					_ambience.add_lamp(lamp, Color(0.95, 0.88, 0.5) * 1.4, 6.0, {"flicker": 0.35 if lit % 4 == 3 else 0.0})
					lit += 1
				else:
					_item_box(parent, seg, i, Vector3(side * (wall - 0.03), 2.7, 0), Vector3(0.04, 0.6, 0.9), Color.WHITE).material_override = \
							PsxMaterials.textured(PsxTextures.vent(), Vector2(3, 2))
				var at := float(i) + every / 2.0
				if at < sp.y - 1.0:
					var holder := Node3D.new()
					parent.add_child(holder)
					holder.transform = _frame_at(seg, at) * Transform3D(Basis.IDENTITY, Vector3(side * (road_half + 0.6), 0, 0))
					match (k + absi(hash(seg["id"]))) % 3:
						0:  # steel cases on a pallet, one on top
							_pallet(holder, Vector3.ZERO, 0.8, 1.2)
							_box(holder, Vector3(0.7, 0.8, 1.1), Vector3(0, 0.54, 0), Color.WHITE).material_override = \
									PsxMaterials.textured(PsxTextures.steel_case(), Vector2(3, 2))
							_box(holder, Vector3(0.6, 0.5, 0.7), Vector3(0, 1.19, -0.15), Color.WHITE).material_override = \
									PsxMaterials.textured(PsxTextures.steel_case(), Vector2(3, 2))
						1:  # rusty drums
							for dz in [-0.3, 0.3]:
								_drum(holder, Vector3(0, 0, dz), Color("6a3420"))
						2:  # a crate, and papers on the floor by it
							_box(holder, Vector3(0.7, 0.7, 0.9), Vector3(0, 0.35, 0), Color.WHITE).material_override = \
									PsxMaterials.textured(PsxTextures.crate_wood(), Vector2(3, 2))
							for s in 2:
								var paper := _box(holder, Vector3(0.3, 0.005, 0.22), Vector3(-side * (0.7 + s * 0.4), 0.01, 0.4 * s), Color("d8d4c4"))
								paper.rotation.y = 0.6 * s - 0.3
			i += every


## The SEWER's fluorescent tubes hanging over the walkway, greenish-white, with their glow and
## pools; drain grates set in the walkway between them. They hang high, the tube 0.65 m over the
## camera and its glow fading out near the lens (hung lower, the camera flew through every one in
## the middle lane, the glow flashing the screen green); their light shines from where it always
## did, so the walkway is lit as before.
func _sewer_tubes(parent: Node3D, seg: Dictionary) -> void:
	var z := float(seg["ramp_len"]) + 5.0
	var n := 0
	while z < float(seg["length"]) - 2.0:
		var y := CEILING_Y - TUBE_DROP
		for dx in [-0.25, 0.25]:
			_item_box(parent, seg, z, Vector3(dx, (y + CEILING_Y) / 2.0, 0), Vector3(0.02, CEILING_Y - y, 0.02), Color("1a1a1a"))
		_item_box(parent, seg, z, Vector3(0, y, 0), Vector3(0.5, 0.12, 1.6), Color("2a2e2a"))
		var tube := _item_box(parent, seg, z, Vector3(0, y - 0.08, 0), Vector3(0.36, 0.04, 1.45), Color.WHITE)
		tube.material_override = PsxMaterials.glow(Color("dcf0c8"))
		_halo_at(parent, seg, z, Vector3(0, y - 0.15, 0), Color(0.8, 0.95, 0.7, 0.35), 2.2)
		_pool_at(parent, seg, z, 0.0, Color(0.75, 0.92, 0.65, 0.22), 3.2)
		var at := Node3D.new()
		parent.add_child(at)
		at.transform = _frame_at(seg, z) * Transform3D(Basis.IDENTITY, Vector3(0, CEILING_Y - 2.3, 0))  # (where it always shone from)
		_ambience.add_lamp(at, Color(0.8, 0.95, 0.72) * 1.6, 8.0, {"flicker": 0.35 if n % 4 == 2 else 0.0})
		var gz := z + 5.0
		if gz < float(seg["length"]) - 2.0:
			_strip(parent, seg, gz, gz + 0.8, -tuning.lane_width * 0.5 if n % 2 == 0 else tuning.lane_width * 0.5, 1.2, 0.008, PsxTextures.grating(), 1.0, 0.8)
		z += 10.0
		n += 1


## One PUMP STATION pump in a bay at `z` (user reference): a concrete plinth, a blue-grey motor
## housing with cooling ribs, the pump casing, a big blue pipe from it up to the ceiling with
## flanges and a red valve wheel, and a stub back into the wall.
func _pump(parent: Node3D, seg: Dictionary, z: float, x: float, side: int, k: int, length: float) -> void:
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.transform = _frame_at(seg, z) * Transform3D(Basis.IDENTITY, Vector3(x, 0, 0))
	var face := -float(side)
	var blue := Color("4a6070")
	var steel := Color("3a4650")
	var l := minf(length, 6.0)
	_box(holder, Vector3(3.0, 0.8, l), Vector3(0, 0.4, 0), Color.WHITE).material_override = \
			PsxMaterials.textured(PsxTextures.concrete(), Vector2(3, 2))
	_box(holder, Vector3(1.8, 1.5, l * 0.45), Vector3(0, 1.55, l * 0.22), blue)  # the motor
	for r in 5:  # its cooling ribs
		_box(holder, Vector3(1.9, 1.3, 0.05), Vector3(0, 1.55, l * 0.22 - l * 0.2 + r * l * 0.1), steel)
	var casing := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.8
	cyl.bottom_radius = 0.9
	cyl.height = 1.4
	cyl.radial_segments = 12
	casing.mesh = cyl
	casing.material_override = PsxMaterials.flat(blue.darkened(0.1))
	holder.add_child(casing)
	casing.position = Vector3(0, 1.5, -l * 0.25)
	var top := _ceil(seg["id"])
	var ph := top - 2.2
	var pipe := MeshInstance3D.new()
	var pc := CylinderMesh.new()
	pc.top_radius = 0.45
	pc.bottom_radius = 0.45
	pc.height = ph
	pc.radial_segments = 12
	pipe.mesh = pc
	pipe.material_override = PsxMaterials.flat(blue)
	holder.add_child(pipe)
	pipe.position = Vector3(0, 2.2 + ph / 2.0, -l * 0.25)
	for fy in [2.4, 4.6]:
		var flange := MeshInstance3D.new()
		var fc := CylinderMesh.new()
		fc.top_radius = 0.6
		fc.bottom_radius = 0.6
		fc.height = 0.18
		fc.radial_segments = 12
		flange.mesh = fc
		flange.material_override = PsxMaterials.flat(steel)
		holder.add_child(flange)
		flange.position = Vector3(0, fy, -l * 0.25)
	var wheel := Node3D.new()
	holder.add_child(wheel)
	wheel.position = Vector3(face * 0.75, 3.2, -l * 0.25)
	var red := Color("a01e18")
	for s in 8:
		var a := TAU * s / 8.0
		var rim := _box(wheel, Vector3(0.06, 0.06, 0.24), Vector3(0, sin(a) * 0.36, cos(a) * 0.36), red)
		rim.rotation.x = -(a + PI / 2.0)
	for s in 2:
		var spoke := _box(wheel, Vector3(0.04, 0.72, 0.04), Vector3.ZERO, red)
		spoke.rotation.x = s * PI / 2.0
	_box(holder, Vector3(0.3, 0.1, 0.1), Vector3(face * 0.55, 3.2, -l * 0.25), steel)
	_pipe_x(holder, Transform3D(Basis.IDENTITY, Vector3(-face * 1.4, 1.5, -l * 0.25)), 1.4, 0.4, blue)  # back into the wall
	var lamp := _box(holder, Vector3(0.05, 0.08, 0.08), Vector3(face * 0.92, 1.9, l * 0.3), Color.WHITE)  # a running light
	lamp.material_override = PsxMaterials.glow(Color("40d060") if k % 3 != 2 else Color("ff3020"))
	var over := Node3D.new()  # a lamp up over it, so you see the pump from the walkway
	holder.add_child(over)
	over.position = Vector3(face * 1.2, 4.6, 0)
	_ambience.add_lamp(over, Color(0.85, 0.95, 1.0) * 1.5, 7.0, {"alert": false})


## A yellow pipe railing along x over [a, b]: posts every 2 m, a top and a middle rail.
func _yellow_rail(parent: Node3D, seg: Dictionary, a: float, b: float, x: float) -> void:
	var yellow := Color("c8a020")
	var mid := (a + b) / 2.0
	_item_box(parent, seg, mid, Vector3(x, 1.05, 0), Vector3(0.07, 0.07, b - a), yellow)
	_item_box(parent, seg, mid, Vector3(x, 0.55, 0), Vector3(0.05, 0.05, b - a), yellow)
	var p := a
	while p <= b + 0.01:
		_item_box(parent, seg, p, Vector3(x, 0.52, 0), Vector3(0.07, 1.05, 0.07), yellow)
		p += 2.0


## The PUMP STATION overhead (user reference): big blue pipes across the hall high up, each with
## flanges and a red valve wheel, and red pipes along both sides of the ceiling.
func _pump_overhead(parent: Node3D, seg: Dictionary, from: float) -> void:
	var length: float = seg["length"]
	var top := _ceil(seg["id"])
	var road_half := tuning.lane_count * tuning.lane_width / 2.0
	for piece in _pieces(seg, from, length):
		var mid := (piece.x + piece.y) / 2.0
		for s in [-1.0, 1.0]:
			_pipe_z(parent, _frame_at(seg, mid) * Transform3D(Basis.IDENTITY, Vector3(s * (road_half + 0.7), top - 0.45, 0)), piece.y - piece.x, 0.12,
					PsxMaterials.flat(Color("8a2018")))
	var z := from + 18.0
	while z < length - 6.0:
		_pipe_x(parent, _frame_at(seg, z) * Transform3D(Basis.IDENTITY, Vector3(0, top - 1.3, 0)), road_half * 2.0 + 2.2, 0.55, Color("4a6070"))
		for fx in [-2.0, 2.0]:
			_pipe_x(parent, _frame_at(seg, z) * Transform3D(Basis.IDENTITY, Vector3(fx, top - 1.3, 0)), 0.2, 0.7, Color("3a4650"))
		var wheel := Node3D.new()
		parent.add_child(wheel)
		wheel.transform = _frame_at(seg, z) * Transform3D(Basis.IDENTITY, Vector3(0.6, top - 0.55, 0))
		for s in 8:
			var a := TAU * s / 8.0
			var rim := _box(wheel, Vector3(0.24, 0.06, 0.06), Vector3(cos(a) * 0.36, 0, sin(a) * 0.36), Color("a01e18"))
			rim.rotation.y = -(a + PI / 2.0)
		z += 30.0


## A STORM DRAIN side (user reference) behind the opening `span`: the channel wall up to a raised
## ledge with a hazard-striped lip and a railing, yellow ladders down the wall, outfall pipes in it
## pouring water into the channel, buttress pillars; the upper wall behind the ledge with warm lamps
## and a big pipe along it, cabinets and crates on the ledge.
func _build_drain_side(parent: Node3D, seg: Dictionary, side: int, span: Vector2) -> void:
	var road_half := tuning.lane_count * tuning.lane_width / 2.0
	var wl := road_half + 1.0  # the channel wall's line
	var ly := 2.3  # the ledge's height
	var lw := 2.6  # ...and depth
	var top := _ceil(seg["id"])
	var mid := (span.x + span.y) / 2.0
	var L := span.y - span.x
	var x := func(d: float) -> float: return side * d
	var concrete := PsxMaterials.textured(PsxTextures.drain_wall(), Vector2(L / 2.0, 1.2))
	var grey := Color("6a6e70")
	# The channel wall, the ledge, its lip, its railing; the upper wall and the ceiling over it.
	_item_box(parent, seg, mid, Vector3(x.call(wl), ly / 2.0, 0), Vector3(0.3, ly, L), Color.WHITE).material_override = concrete
	_item_box(parent, seg, mid, Vector3(x.call(wl + lw / 2.0), ly - 0.12, 0), Vector3(lw, 0.24, L), Color("4a4c46"))
	_strip(parent, seg, span.x, span.y, x.call(wl + lw / 2.0), lw, ly + 0.005, PsxTextures.sewer_floor(), lw / tuning.lane_width, tuning.lane_width)
	_item_box(parent, seg, mid, Vector3(x.call(wl + 0.12), ly + 0.02, 0), Vector3(0.24, 0.05, L), Color.WHITE).material_override = \
			PsxMaterials.textured(PsxTextures.hazard(), Vector2(L / 0.8, 1))
	for ry in [ly + 0.55, ly + 1.05]:
		_item_box(parent, seg, mid, Vector3(x.call(wl + 0.25), ry, 0), Vector3(0.05, 0.05, L), grey)
	_item_box(parent, seg, mid, Vector3(x.call(wl + lw), (ly + top) / 2.0, 0), Vector3(0.2, top - ly, L + 5.0), Color.WHITE).material_override = \
			PsxMaterials.textured(PsxTextures.drain_wall(), Vector2(L / 2.0, (top - ly) / 2.0))
	_item_box(parent, seg, mid, Vector3(x.call(wl + lw / 2.0), top + 0.05, 0), Vector3(lw + 0.4, 0.1, L + 5.0), Color("2e302a"))
	for z in [span.x, span.y]:
		_item_box(parent, seg, z, Vector3(x.call(wl + lw / 2.0), top / 2.0, 0), Vector3(lw, top, 0.3), Color.WHITE).material_override = \
				PsxMaterials.textured(PsxTextures.drain_wall(), Vector2(2, 3))
	_pipe_z(parent, _frame_at(seg, mid) * Transform3D(Basis.IDENTITY, Vector3(x.call(wl + lw - 0.6), top - 1.1, 0)), L, 0.5,
			PsxMaterials.flat(Color("5a5e5c")))
	# Every 8 m: a buttress, railing posts, a lamp on the upper wall (every other), and in turn a
	# ladder, an outfall pouring water, or a cabinet or crates on the ledge.
	var p := span.x + 4.0
	var n := 0
	var lit := 0
	while p < span.y - 1.0:
		_item_box(parent, seg, p, Vector3(x.call(wl - 0.1), top / 2.0, 0), Vector3(0.6, top, 0.8), Color("5a5c54"))  # buttress
		_item_box(parent, seg, p, Vector3(x.call(wl + lw / 2.0), top - 0.3, 0), Vector3(lw, 0.5, 0.6), Color("4a4c46"))  # beam over the ledge
		for q in [p + 2.0, p + 4.0, p + 6.0]:
			if q < span.y - 0.5:
				_item_box(parent, seg, q, Vector3(x.call(wl + 0.25), ly + 0.55, 0), Vector3(0.06, 1.1, 0.06), grey)
		if n % 2 == 0:
			var lamp := _item_box(parent, seg, p + 4.0, Vector3(x.call(wl + lw - 0.12), ly + 2.1, 0), Vector3(0.14, 0.26, 0.34), Color.WHITE)
			lamp.material_override = PsxMaterials.glow(Color("ffd890"))
			_halo_at(parent, seg, p + 4.0, Vector3(x.call(wl + lw - 0.3), ly + 2.1, 0), Color(1.0, 0.75, 0.4, 0.5), 1.6)
			_pool_at(parent, seg, p + 4.0, x.call(road_half - 1.0), Color(1.0, 0.72, 0.38, 0.22), 2.6)
			if lit < 4:
				_ambience.add_lamp(lamp, Color(1.0, 0.8, 0.5) * 1.6, 8.0, {"alert": false})
				lit += 1
		var at := p + 4.0
		if at < span.y - 1.5:
			match (n + (0 if side < 0 else 1)) % 3:
				0:  # a yellow ladder down the channel wall
					for rz in [-0.22, 0.22]:
						_item_box(parent, seg, at + rz, Vector3(x.call(wl - 0.2), (ly + 1.0) / 2.0, 0), Vector3(0.05, ly + 1.0, 0.05), Color("c8a020"))
					var r := 0.3
					while r < ly + 0.9:
						_item_box(parent, seg, at, Vector3(x.call(wl - 0.2), r, 0), Vector3(0.04, 0.04, 0.44), Color("c8a020"))
						r += 0.3
				1:  # an outfall in the wall pouring water into the channel
					_pipe_x(parent, _frame_at(seg, at) * Transform3D(Basis.IDENTITY, Vector3(x.call(wl - 0.1), 0.8, 0)), 0.5, 0.55, Color("3a3c38"))
					_pipe_x(parent, _frame_at(seg, at) * Transform3D(Basis.IDENTITY, Vector3(x.call(wl - 0.2), 0.8, 0)), 0.3, 0.42, Color("141614"))
					_waterfall(parent, seg, at, Vector3(x.call(wl - 0.35), 0.75, 0), Vector3(x.call(wl - 1.0), 0.0, 0), 0.6)
					_halo_at(parent, seg, at, Vector3(x.call(wl - 0.9), 0.15, 0), Color(0.8, 0.9, 0.8, 0.4), 1.6)
					_pool_at(parent, seg, at, x.call(wl - 1.2), Color(0.8, 0.9, 0.82, 0.3), 1.4)
				2:  # a utility cabinet and crates on the ledge
					_item_box(parent, seg, at, Vector3(x.call(wl + lw - 0.5), ly + 0.75, 0), Vector3(0.6, 1.5, 1.0), Color("7a7e80"))
					_item_box(parent, seg, at, Vector3(x.call(wl + lw - 1.05), ly + 1.0, 0.25), Vector3(0.02, 0.12, 0.08), Color.WHITE).material_override = \
							PsxMaterials.glow(Color("ff3020"))
					_item_box(parent, seg, at + 1.6, Vector3(x.call(wl + lw - 0.8), ly + 0.4, 0), Vector3(0.8, 0.8, 0.9), Color.WHITE).material_override = \
							PsxMaterials.textured(PsxTextures.crate_wood(), Vector2(3, 2))
		p += 8.0
		n += 1


## The STORM DRAIN's channel floor (user reference): shallow water over it the whole way, the
## lamps glinting on it, and grates across it now and then.
func _drain_water(parent: Node3D, seg: Dictionary) -> void:
	var road_half := tuning.lane_count * tuning.lane_width / 2.0
	var length: float = seg["length"]
	var from := float(seg["ramp_len"]) + 0.5
	for piece in _pieces(seg, from, length):
		var mid := (piece.x + piece.y) / 2.0
		_item_box(parent, seg, mid, Vector3(0, 0.035, 0), Vector3(road_half * 2.0 + 1.6, 0.01, piece.y - piece.x), Color.WHITE).material_override = \
				PsxMaterials.glass(Color(0.1, 0.13, 0.11, 0.5))
	var g := from + 14.0
	while g < length - 4.0:
		_strip(parent, seg, g, g + 0.9, 0.0, road_half * 2.0, 0.012, PsxTextures.grating(), 5.0, 0.9)
		g += 18.0
	var z := from + 3.0
	var k := 0
	while z < length - 2.0:  # glints of light on the water
		var gl := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(0.25, 1.6)
		gl.mesh = plane
		gl.material_override = PsxMaterials.pool(Color(1.0, 0.85, 0.55, 0.25))
		parent.add_child(gl)
		gl.transform = _frame_at(seg, z) * Transform3D(Basis.IDENTITY, Vector3(((k * 37) % 11 - 5) * 0.55, 0.05, 0))
		z += 2.3
		k += 1


## STORM DRAIN jump: a low concrete weir across the lane, water sheeting over its front.
func _build_weir(parent: Node3D, seg: Dictionary, at: float, x: float, _lane: int) -> Node3D:
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.transform = _frame_at(seg, at) * Transform3D(Basis.IDENTITY, Vector3(x, 0, 0))
	var w := tuning.lane_width + 0.02
	_box(holder, Vector3(w, 0.45, 0.6), Vector3(0, 0.225, 0), Color.WHITE).material_override = \
			PsxMaterials.textured(PsxTextures.drain_wall(), Vector2(3, 1))
	_box(holder, Vector3(w, 0.05, 0.64), Vector3(0, 0.47, 0), Color("4a4c46"))
	var sheet := MeshInstance3D.new()  # the water sheeting over it, flowing
	var q := QuadMesh.new()
	q.size = Vector2(w, 0.46)
	sheet.mesh = q
	sheet.material_override = PsxMaterials.water_fall(Color(0.82, 0.9, 0.86, 0.6), Vector2(w / 0.5, 0.5))
	holder.add_child(sheet)
	sheet.position = Vector3(0, 0.23, 0.31)
	_box(holder, Vector3(w, 0.02, 0.1), Vector3(0, 0.49, 0.28), Color.WHITE).material_override = PsxMaterials.glow(Color("c8d4c8"))  # its glinting lip
	return holder


## Water pouring from `top` down to `bottom` (segment-local points at `z`, across and up), as flat
## sheets with flowing water on them (user: a flat plane with animated water, not a block): one
## facing you, one turned side-on, so it reads from any angle.
func _waterfall(parent: Node3D, seg: Dictionary, z: float, top: Vector3, bottom: Vector3, width: float) -> void:
	var down := top - bottom
	var length := down.length()
	var y_axis := down / length
	var x_axis := y_axis.cross(Vector3.BACK).normalized()
	var basis := Basis(x_axis, y_axis, x_axis.cross(y_axis).normalized())
	var mat := PsxMaterials.water_fall(Color(0.82, 0.9, 0.86, 0.75), Vector2(width / 0.5, length / 1.0))
	for turn in [0.0, PI / 2.0]:
		var m := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(width, length)
		m.mesh = q
		m.material_override = mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(m)
		m.transform = _frame_at(seg, z) * Transform3D(basis * Basis(Vector3.UP, turn), (top + bottom) / 2.0)


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


## A flat strip lying along one piece of a segment, `x` across and `y` up, following any slope;
## `down` faces it down (a ceiling). An end at a bend is cut on the corner's bisector (_mitre).
func _strip(parent: Node3D, seg: Dictionary, a: float, b: float, x: float, width: float, y: float,
		tex: Texture2D, tiles_x: float, tile_len: float = 4.0, down: bool = false) -> MeshInstance3D:
	var i := _leg_index(seg, (a + b) / 2.0)
	var pa := _frame_in_leg(seg, i, a) * Vector3(x, y, 0)
	var pb := _frame_in_leg(seg, i, b) * Vector3(x, y, 0)
	var l := pa.distance_to(pb)
	var back := (pa - pb) / l
	var right: Vector3 = seg["legs"][i]["xf"].basis.x
	var m := _plane(parent, Vector2(width, l), Vector3.ZERO, tex, Vector2(tiles_x, l / tile_len))
	m.transform = Transform3D(Basis(right, back.cross(right), back), (pa + pb) / 2.0)
	if down:
		m.rotate_object_local(Vector3.FORWARD, PI)  # (before the mitre: turned over after it, its cut would be mirrored)
	_mitre(m, seg, i, a, b, absf(x) + width / 2.0)
	return m


## Every strip was cut square across its own leg, so at each bend the two legs' floors overlapped
## in a wedge on the inside of the corner, the same floor twice with its pattern 30 degrees apart,
## and parted in one on the outside, filled by patches a hair under the floor (and over the
## ceiling). Under the PS1 vertex snap the patches showed through in shards that changed every
## frame: the user's "There is a problem with the corners the floor texture over laps and causes
## popping". So a strip ending at a bend is cut on the corner's bisector: its outside runs on to
## the line, its inside stops at it, and the next leg's strip starts from the same line, on the
## same points (no overlap, no gap, nothing laid under). A square end just short of a bend is cut
## back to the line on the inside, so it can't poke over the next leg's floor. The rows between
## keep their places, and the texture runs on past the old square end. This is every flat strip:
## floors, ceilings, kerbs, roof edges, floor lines, the yard. `reach`: how far out from the
## centre line the strip goes. (Floors are never solid, so nothing in play changes.)
func _mitre(m: MeshInstance3D, seg: Dictionary, i: int, a: float, b: float, reach: float) -> void:
	var legs: Array = seg["legs"]
	var s: float = legs[i]["start"]
	var e: float = legs[i + 1]["start"] if i + 1 < legs.size() else INF
	# At a bend turning by d (left +), the point x across is on the corner's line at
	# into = bend - x tan(d/2) along the leg after it, and at bend + x tan(d/2) along the one before.
	var ta := tan(_turn_at(seg, i) / 2.0)
	var tb := tan(_turn_at(seg, i + 1) / 2.0)
	var near_a := absf(ta) > 1e-4 and a - s < reach * absf(ta) + 0.01
	var near_b := absf(tb) > 1e-4 and e - b < reach * absf(tb) + 0.01
	if not (near_a or near_b):
		return
	var at_a := near_a and absf(a - s) < 0.005
	var at_b := near_b and absf(b - e) < 0.005
	var pm := m.mesh as PlaneMesh
	var arrays := pm.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var to_leg: Transform3D = (legs[i]["xf"] as Transform3D).affine_inverse() * m.transform
	var from_leg := to_leg.affine_inverse()
	var half_l := pm.size.y / 2.0
	# (A row moves along the strip's own slope, which is none at a bend: bends are all past the
	# stairs. Not by the route's height: on the outside of the ROOFTOPS' first bend the mitre
	# takes a row back to 11.5 m along the leg after it, which is still past the bend, not on the
	# stairs that end at 12 m.)
	var slope := (_height(seg, b) - _height(seg, a)) / (b - a) if b > a else 0.0
	var moved := false
	for k in verts.size():
		var p := to_leg * verts[k]  # in the leg's frame: x across, `into` = start - z
		var into := s - p.z
		# This column's two ends: on the corner's line at a bend, else square but never past one.
		var lo := a
		var hi := b
		if near_a:
			lo = s - p.x * ta if at_a else maxf(a, s - p.x * ta)
		if near_b:
			hi = e + p.x * tb if at_b else minf(b, e + p.x * tb)
		hi = maxf(hi, lo)
		var to := clampf(into, lo, hi)
		if verts[k].z > half_l - 0.001:  # (the start row: local +z is back, toward a)
			to = lo
		elif verts[k].z < -half_l + 0.001:  # (the end row)
			to = hi
		if absf(to - into) < 1e-4:
			continue
		var q := from_leg * Vector3(p.x, p.y + (to - into) * slope, s - to)
		uvs[k] += Vector2((q.x - verts[k].x) / pm.size.x, (q.z - verts[k].z) / pm.size.y)  # (PlaneMesh's own mapping)
		verts[k] = q
		moved = true
	if not moved:
		return
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	m.mesh = mesh


## A wall along one piece of a segment, facing the road, covering any climb. It runs on 0.15 m
## below the floor and above the ceiling, so the corners overlap instead of just meeting (an
## edge that only meets another shows the outside through a hairline under the PS1 vertex snap:
## the user's gaps); its line-of-sight block stays the wall's own height (none if not `solid`).
func _wall(parent: Node3D, seg: Dictionary, a: float, b: float, x: float, side: int, h: float, tex: Texture2D,
		solid: bool = true) -> void:
	var i := _leg_index(seg, (a + b) / 2.0)
	var leg: Dictionary = seg["legs"][i]
	var ha := _height(seg, a)
	var hb := _height(seg, b)
	var y0 := minf(ha, hb)
	var y1 := maxf(ha, hb) + h
	var tuck := 0.15
	var l := b - a
	var xf: Transform3D = leg["xf"]
	var m := _plane(parent, Vector2(l, y1 - y0 + 2.0 * tuck), Vector3.ZERO, tex, Vector2(l / 2.0, (y1 - y0 + 2.0 * tuck) / 2.0), PlaneMesh.FACE_Z)
	# Shift the pattern so a tile's bottom row (skirting, grime) sits on the floor, whatever the height.
	var rows := (y1 - y0 + tuck) / 2.0  # the top of the plane down to the floor, in tiles
	m.material_override = PsxMaterials.textured(tex, Vector2(l / 2.0, (y1 - y0 + 2.0 * tuck) / 2.0), false, Vector2(0, ceilf(rows) - rows))
	var xf_wall := Transform3D(xf.basis * Basis(Vector3.UP, -side * PI / 2.0),
			xf * Vector3(x, (y0 + y1) / 2.0, -((a + b) / 2.0 - leg["start"])))
	m.transform = xf_wall
	m.set_meta("solid", true)  # (blocks sight over its own height only, as it always has)
	if solid:
		_wall_sight(parent, seg, a, b, x, side, h)


## The line-of-sight block of a _wall from `a` to `b`: the wall's own height, without its tucks.
func _wall_sight(parent: Node3D, seg: Dictionary, a: float, b: float, x: float, side: int, h: float) -> void:
	var leg: Dictionary = seg["legs"][_leg_index(seg, (a + b) / 2.0)]
	var ha := _height(seg, a)
	var hb := _height(seg, b)
	var y0 := minf(ha, hb)
	var y1 := maxf(ha, hb) + h
	var l := b - a
	if maxf(l, y1 - y0) < 0.9:
		return
	var xf: Transform3D = leg["xf"]
	_solid_box(parent, Transform3D(xf.basis * Basis(Vector3.UP, -side * PI / 2.0),
			xf * Vector3(x, (y0 + y1) / 2.0, -((a + b) / 2.0 - leg["start"]))), Vector3(l, y1 - y0, 0.06))


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
		elif kind == "exit_sign":
			beam = _build_exit_sign(parent, seg, at, ends)
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
## it, and sparks where they're broken. The cables dither away as the camera comes close
## (PsxMaterials.lens_faded): it passes right by the cut wire and the rise to a hook.
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
				var piece := _cable(parent, frame, prev, p, 0.04, black if c != 1 else Color("5a3a12"), true)
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
		_cable(parent, frame, prev_cut, p, 0.04, black, true)
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
## end), with little flags in party colours hanging off it. The string dithers away as the camera
## comes close (PsxMaterials.lens_faded): it passes right by its rise to the hook.
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
			var piece := _cable(parent, frame, prev, p, 0.025, Color("e8e0c8"), true)
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


## A thin straight cable between two points given in `frame` (a place on the route). lens: it
## dithers away as the camera comes close (PsxMaterials.lens_faded): one hanging where the camera
## passes (a duck-under's).
func _cable(parent: Node3D, frame: Transform3D, a: Vector3, b: Vector3, thick: float, color: Color, lens := false) -> MeshInstance3D:
	var m := _box(parent, Vector3(thick, thick, maxf(a.distance_to(b), 0.01)), Vector3.ZERO, color)
	if lens:
		m.material_override = PsxMaterials.lens_faded(color)
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
	var base_edge := tuning.lane_count * tuning.lane_width / 2.0 + 1.0
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
		var th := _theme(seg["id"])
		var edge := base_edge + (float(th.get("wide_roof", 0.0)) if int(th.get("wide_side", side)) == side else 0.0)
		var outward := (mid_frame * Vector3(side * 20.0, 0, 0)).x - mid_frame.origin.x
		if signf(outward) != signf(mid_frame.origin.x) and absf(mid_frame.origin.x) > 1.0:
			continue
		if absf(mid_frame.origin.x) <= 1.0:
			continue  # right over the centre line: no room either side
		var z: float = seg["ramp_len"] + 2.0
		var until := length - tuning.decision_lead - tuning.fork_cue_length if exit_sides.has(side) else length
		if not _theme(seg["id"]).get("city_near", true):
			until = z  # no near roofs here (the WATER TOWERS stand there): only the towers further out
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
				_halo_at(parent, seg, t_at, Vector3(tx, tall + 0.3, tz - t_at), Color(1.0, 0.15, 0.08, 0.5), 3.0)
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
	for i in n:
		var cx := x0 + mw * (i + 0.5)
		var tint: Color = VENDING_TINTS[absi(hash([seg["id"], at, i])) % VENDING_TINTS.size()]
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
## height across the blocked lanes, the chains running up to the crane. The chains dither away as
## the camera comes close (PsxMaterials.lens_faded): from the next lane it passes right by one.
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
			link.material_override = PsxMaterials.lens_faded(Color("6a6a64"))  # (the camera passes right by them)
			link.transform = frame * Transform3D(Basis.IDENTITY, Vector3(cx, gy + 0.22 + k * 0.16, 0))
	return beam


## The start room (user, 2026-10-07: "It needs to be a bit smaller and maybe have a window on the
## back wall with a slightly faded view of the city outside. It needs an office table and computer
## ... there could be a plant as well, make it look like a typical office, a bit messy where Cross
## has looked through filing cabinets and knocked the chair over, leave one of the windows open it
## gives a clue as to how Cross go[t] in for keen eyed players"). Half its width (m): 7 m wide,
## the road's own width, a metre narrower each side than the lobby it opens into. The opening
## pan's widest point (x +2.79, beside him on his right) stays 0.71 m inside its right wall; its
## length is Tuning's start_room_length (12 m: the pan ends on the play camera 5.5 m behind him,
## 0.5 m inside the back wall).
const START_ROOM_HALF := 3.5
## The back wall's three windows (behind him on the menu, between its title and its buttons): how
## wide, the sill and the head (m), and which is the open one (0: his left, the menu's right, the
## corner the opening pan looks across into).
const START_WIN_W := 1.4
const START_WIN_SILL := 0.9
const START_WIN_HEAD := 2.9
const START_WIN_OPEN := 0


## The office room the mission starts in, behind the first segment (negative distances): VORHALT's
## branch office at night, just after CROSS got in by its window and through its filing cabinets.
## Its own space: x across (+ his right), y up, z back from the door wall's room face (the back
## wall's face at L, CROSS at start_offset). The floor, ceiling and walls; the back wall with its
## windows and the night outside (_start_room_back); the furniture and the mess
## (_dress_start_room); the front wall (as wide and high as the lobby it opens into) with the door,
## bashed open at the start of the run. Everything still is merged (_merge_static): about 20 draws.
func _build_start_room(seg: Dictionary) -> void:
	var room := Node3D.new()
	room.name = "StartRoom"
	seg["node"].add_child(room)
	var L := tuning.start_room_length
	var road_w := tuning.lane_count * tuning.lane_width
	var half := START_ROOM_HALF
	var lobby_half := road_w / 2.0 + 1.0
	var theme: Dictionary = THEMES["office"]
	var wall_tex := _wall_texture(theme)
	# The floor and ceiling run on 0.15 m under the side walls and 0.3 m under the back wall (the
	# ceiling on into the front wall too); the side walls 0.15 m into the front wall: no edge just
	# meets another (the user's gaps).
	var fw := half * 2.0 + 0.3
	_strip(room, seg, -L - 0.3, 0.0, 0.0, fw, 0.0, PsxTextures.office_floor(), fw / tuning.lane_width, tuning.lane_width)
	_strip(room, seg, -L - 0.3, 0.3, 0.0, fw, CEILING_Y, PsxTextures.office_ceiling(), fw / 2.0, 2.0, true)
	_ceiling_lamp(room, seg, -L / 2.0, false)
	for side in [-1, 1]:
		_wall(room, seg, -L - 0.3, 0.15, side * half, side, CEILING_Y, wall_tex, false)
		_wall_sight(room, seg, -L, 0.0, side * half, side, CEILING_Y)
	# The front wall, with a doorway in the player's lane. It is the lobby's end wall too, so it is
	# as wide as the lobby (the road and a metre each side), a metre wider each side than the room.
	var office := PsxMaterials.textured(wall_tex, Vector2(3, 2))
	var dx := _player.lane_x(tuning.lane_count / 2)
	var dw := DOOR_W + 0.05
	var dh := DOOR_H
	var front := -0.15
	var left_w := dx - dw / 2.0 + lobby_half + 0.15
	var right_w := lobby_half + 0.15 - (dx + dw / 2.0)
	for s in [-1, 1]:
		var w: float = left_w if s < 0 else right_w
		var piece := _item_box(room, seg, 0.0, Vector3(s * (lobby_half + 0.15 - w / 2.0), (CEILING_Y - 0.15) / 2.0, front), Vector3(w, CEILING_Y + 0.15, 0.3), Color.WHITE)
		piece.material_override = office
		piece.set_meta("solid", true)  # (over the room only, as it always has)
		_solid_box(piece, Transform3D(Basis.IDENTITY, Vector3(-s * 0.075, 0.075, 0)), Vector3(w - 0.15, CEILING_Y, 0.3))
	# The wall over the door, solid up to the ceiling: the play camera (3.4 m up, 5.5 m behind him)
	# follows him out through it after the bash, and the cutout (Cutout) dissolves it round him there,
	# so no glass over the door is needed to keep him in view (the user's choice).
	_item_box(room, seg, 0.0, Vector3(dx, (dh + CEILING_Y) / 2.0, front), Vector3(dw, CEILING_Y - dh, 0.3), Color.WHITE).material_override = office
	# A threshold under the doorway, a hair below both floors where they meet in it (the seam
	# between them showed the void as you burst through: the user's gaps).
	_strip(room, seg, -0.3, 0.6, dx, dw + 0.4, -0.006, PsxTextures.office_floor(), 1.0, tuning.lane_width)
	# The door hangs on a hinge at the left of the doorway.
	var hinge := Node3D.new()
	room.add_child(hinge)
	hinge.transform = _frame_at(seg, 0.0) * Transform3D(Basis.IDENTITY, Vector3(dx - dw / 2.0, 0, front))
	var panel := _box(hinge, Vector3(dw - 0.04, dh - 0.02, 0.07), Vector3(dw / 2.0, dh / 2.0, 0), Color.WHITE)
	panel.material_override = PsxMaterials.textured(PsxTextures.door(), Vector2(3, 2))
	_doors.append({"node": hinge, "at": 0.0, "owner": seg["node"], "seg": seg, "sound": "door_wood"})
	_make_solid(room)
	# The window onto the next office (his glance in the menu's idle) and the notice board, on the
	# side walls (fittings: they block no line of sight of their own, as before).
	_item_box(room, seg, -6.0, Vector3(-(half - 0.03), 1.65, 0), Vector3(0.05, 0.9, 1.6), Color.WHITE).material_override = \
			PsxMaterials.textured(PsxTextures.office_window(), Vector2(3, 2))
	_item_box(room, seg, -7.4, Vector3(half - 0.03, 1.5, 0), Vector3(0.05, 0.75, 1.1), Color.WHITE).material_override = \
			PsxMaterials.textured(PsxTextures.notice_board(), Vector2(3, 2))
	# The still parts (merged at the end) and the live ones (what moves, the lamps' anchors, the
	# snow), both in the room's own space.
	var d := Node3D.new()
	d.name = "Dressing"
	room.add_child(d)
	d.transform = _frame_at(seg, 0.0)
	var live := Node3D.new()
	live.name = "DressingLive"
	room.add_child(live)
	live.transform = d.transform
	# The room's own lamps' anchors, in the same space: shown only while the camera is in the room
	# (_light_start_room).
	_room_lamps = Node3D.new()
	_room_lamps.name = "RoomLamps"
	live.add_child(_room_lamps)
	var cxs := _start_windows(L)
	_start_room_back(room, d, live, _room_lamps, seg, L, half, wall_tex, cxs)
	_dress_start_room(d, _room_lamps, L, half, cxs)
	_merge_static(d)


## The start room's own lamps (_room_lamps) are lit only while the camera is in the room: until
## it is out past the front wall's lobby face, following him into the lobby. Out there, nothing
## they light can be in view (all of them are at the back of the room, 11 m and more behind the
## door). Left on, they would hold three of the 12 slots the lighting gives the lamps nearest where
## the camera looks (Ambience) for the first 26 m of the lobby, and three of the lobby's lamps
## ahead would pop on there instead of fading in. A hidden lamp gets no slot. One transform a
## frame, no allocations; nothing once the room is gone.
func _light_start_room() -> void:
	if not is_instance_valid(_room_lamps):
		return
	var inside := _room_lamps.to_local(_camera.global_position).z > -0.3  # (the wall is 0.3 m thick)
	if _room_lamps.visible != inside:
		_room_lamps.visible = inside


## The back wall's windows' middles (m across, + his right): one behind him on the menu (it shows
## beside him as the camera sways) and one either side, a quarter of the menu camera's distance back
## to the wall out from him (about 90 px on the menu), clear of the side walls. At 12 m: -2.19, 0,
## +2.19. With three, at least one shows beside him at every sway (two left none for about a third
## of it).
func _start_windows(L: float) -> Array[float]:
	var side := minf(0.25 * (L - tuning.start_offset + IntroCamera.MENU_R), START_ROOM_HALF - START_WIN_W / 2.0 - 0.5)
	return [-side, 0.0, side]


## The back wall (user: "a window on the back wall with a slightly faded view of the city outside"),
## behind him on the main menu: one mesh with the three openings cut in it, their reveals carried
## round (_holed_wall); in each an aluminium frame with a transom (a fixed light over two
## casements), glass that takes the edge off the night outside, a sill board, a ledge outside with
## snow on it, and a venetian blind. THE OPEN ONE (on his left; "a clue as to how Cross got in for
## keen eyed players"): its outer casement swung in and creaking in the wind, its blind yanked up
## crooked on one cord and stirring in the draught, snow blown in on the sill (a boot print in it)
## and the floor, his boot prints in snow leading in off the sill and away into the room, a few
## flakes still blowing in, and the cold of the night falling in as a blue light; and the rope he
## came down on, in over its sill (_climbing_rope, with the dressing). Outside: the snowy
## plaza (the start room is on the ground floor: MAIN FLOOR), a lamp post, snow falling past the
## windows, and the night city (the MAIN FLOOR EXIT's backdrop under more sky), clear through the
## open casement and a little faded through the glass. The still parts go into `d` (merged), what
## moves into `live`, the lamp into `lamps`.
func _start_room_back(room: Node3D, d: Node3D, live: Node3D, lamps: Node3D, seg: Dictionary, L: float, half: float, wall_tex: Texture2D, cxs: Array[float]) -> void:
	var h := CEILING_Y
	var depth := 0.3
	var sill := START_WIN_SILL
	var head := START_WIN_HEAD
	var ww := START_WIN_W
	var transom := head - 0.6
	var holes: Array[Rect2] = []
	for cx in cxs:
		holes.append(Rect2(cx - ww / 2.0, sill, ww, head - sill))
	var face := Node3D.new()  # (x across, y up, z out the back from the wall's room face)
	face.name = "BackWall"
	room.add_child(face)
	face.transform = _frame_at(seg, -L)
	var wall := _holed_wall(face, half, h, depth, holes)
	wall.material_override = PsxMaterials.textured(wall_tex)
	# Its line of sight: the whole wall, as before (nothing to see or shoot through it).
	_solid_box(face, Transform3D(Basis.IDENTITY, Vector3(0, h / 2.0, depth / 2.0)), Vector3(half * 2.0, h, depth))
	var w := Node3D.new()  # the still parts, in the same space
	d.add_child(w)
	w.position = Vector3(0, 0, L)
	var mv := Node3D.new()  # the live ones
	live.add_child(mv)
	mv.position = Vector3(0, 0, L)
	var alu := Color("7c8488")
	var snow := Color("aeb8c6")
	var glass := PsxMaterials.glass(Color(0.55, 0.66, 0.8, 0.18))
	var slats := PsxTextures.blinds()
	var fz := 0.16  # the frame's middle, in the wall's thickness
	var add := func(size: Vector3, pos: Vector3, color: Color, basis := Basis.IDENTITY) -> MeshInstance3D:
		var b := _box(w, size, pos, color)
		b.basis = basis
		return b
	for i in cxs.size():
		var cx: float = cxs[i]
		var open := i == START_WIN_OPEN
		var x0 := cx - ww / 2.0
		var x1 := cx + ww / 2.0
		# The frame, its outer members 1 cm into the reveals all round (no hairline of the night
		# between frame and wall), the transom, and the mullion between the casements.
		add.call(Vector3(0.07, head - sill + 0.02, 0.07), Vector3(x0 + 0.025, (sill + head) / 2.0, fz), alu)
		add.call(Vector3(0.07, head - sill + 0.02, 0.07), Vector3(x1 - 0.025, (sill + head) / 2.0, fz), alu)
		add.call(Vector3(ww + 0.02, 0.07, 0.07), Vector3(cx, head - 0.025, fz), alu)
		add.call(Vector3(ww + 0.02, 0.07, 0.07), Vector3(cx, sill + 0.025, fz), alu)
		add.call(Vector3(ww - 0.06, 0.05, 0.07), Vector3(cx, transom, fz), alu)
		add.call(Vector3(0.05, transom - sill - 0.06, 0.07), Vector3(cx, (sill + transom) / 2.0, fz), alu)
		add.call(Vector3(ww + 0.14, 0.04, 0.22), Vector3(cx, sill, 0.02), Color("b8b4a8"))  # the sill board
		add.call(Vector3(ww + 0.2, 0.06, 0.18), Vector3(cx, sill - 0.05, depth + 0.07), Color("6a6e70"))  # the ledge outside
		add.call(Vector3(ww + 0.16, 0.03, 0.15), Vector3(cx, sill - 0.005, depth + 0.075), snow)  # snow on it
		add.call(Vector3(ww - 0.02, 0.06, 0.06), Vector3(cx, head - 0.03, 0.035), Color("d8d4c8"))  # the blind's head rail
		if not open:
			_box(w, Vector3(ww - 0.06, head - sill - 0.06, 0.01), Vector3(cx, (sill + head) / 2.0, fz + 0.01), Color.WHITE).material_override = glass
			# Its blind let down a way (half way over the one by the desk, further behind him).
			var drop := 0.5 if absf(cx) > 0.5 else 0.8
			var sheet := _plane(w, Vector2(ww - 0.04, drop), Vector3(cx, head - 0.06 - drop / 2.0, 0.04), slats, Vector2.ONE, PlaneMesh.FACE_Z)
			sheet.rotation.y = PI  # (facing the room)
			sheet.material_override = PsxMaterials.textured(slats, Vector2(1.0, drop / 0.4))
			add.call(Vector3(ww - 0.03, 0.025, 0.035), Vector3(cx, head - 0.06 - drop - 0.012, 0.04), Color("c8c4b8"))  # its bottom rail
			continue
		# THE OPEN ONE: its outer casement (toward the nearer side wall: `o`) swung in.
		var o := 1.0 if cx >= 0.0 else -1.0
		var gap := cx + o * ww / 4.0  # (the middle of the open half)
		_box(w, Vector3(ww - 0.06, head - transom - 0.04, 0.01), Vector3(cx, (transom + head) / 2.0, fz + 0.01), Color.WHITE).material_override = glass
		_box(w, Vector3(ww / 2.0 - 0.05, transom - sill - 0.06, 0.01), Vector3(cx - o * ww / 4.0, (sill + transom) / 2.0, fz + 0.01), Color.WHITE).material_override = glass
		# The blind, yanked up crooked on one cord: the inner end hauled up to a bunch of slats under
		# the head rail, the outer end still hanging, the slats fanned between, the bottom rail
		# askew. It swings out into the room in the draught and back, its pull cord with it.
		var blind := Node3D.new()
		mv.add_child(blind)
		blind.position = Vector3(x0 + 0.02, head - 0.06, 0.04)
		var bw := ww - 0.04
		var up := 0.12  # (the yanked end's drop)
		var hang := 0.62  # (the other end's)
		var dl := up if o > 0.0 else hang  # (at x0, then at x1)
		var dr := hang if o > 0.0 else up
		var kv := (up + hang) / 2.0 / 0.4
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_quad(st, Vector3(0, 0, 0), Vector3(bw, 0, 0), Vector3(bw, -dr, 0), Vector3(0, -dl, 0), Vector3.FORWARD,
				func(p: Vector3, _n: Vector3) -> Vector2: return Vector2(p.x / bw, -p.y / lerpf(dl, dr, p.x / bw) * kv))
		var fan := MeshInstance3D.new()
		fan.mesh = st.commit()
		fan.material_override = PsxMaterials.textured(slats)
		blind.add_child(fan)
		var cord := 0.05 if o > 0.0 else bw - 0.05
		_box_mesh(blind, [[Vector3(bw + 0.03, 0.025, 0.035), Vector3(bw / 2.0, -(dl + dr) / 2.0 - 0.012, 0), Basis(Vector3.BACK, -atan2(dr - dl, bw))],
				[Vector3(0.012, 1.0, 0.012), Vector3(cord, -0.5, -0.025)], [Vector3(0.03, 0.05, 0.03), Vector3(cord, -1.0, -0.025)]], PsxMaterials.flat(Color("c8c4b8")))
		var sway := blind.create_tween().set_loops()
		for k in [[-0.16, 1.3], [-0.03, 1.1], [-0.1, 0.9], [0.0, 1.2]]:
			sway.tween_property(blind, "rotation:x", k[0], k[1]).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		# The casement, hinged on the outer jamb, swung in, creaking a little in the wind.
		var cw := ww / 2.0 - 0.055
		var ch := transom - sill - 0.08
		var hinge := Node3D.new()
		mv.add_child(hinge)
		hinge.position = Vector3(cx + o * (ww / 2.0 - 0.06), sill + 0.05, fz)
		var swing := -o * deg_to_rad(62.0)
		hinge.rotation.y = swing
		_box_mesh(hinge, [[Vector3(0.05, ch, 0.05), Vector3(-o * 0.025, ch / 2.0, 0)], [Vector3(0.05, ch, 0.05), Vector3(-o * (cw - 0.025), ch / 2.0, 0)],
				[Vector3(cw, 0.05, 0.05), Vector3(-o * cw / 2.0, 0.025, 0)], [Vector3(cw, 0.05, 0.05), Vector3(-o * cw / 2.0, ch - 0.025, 0)],
				[Vector3(0.03, 0.12, 0.04), Vector3(-o * (cw - 0.03), ch / 2.0, -0.04)]], PsxMaterials.flat(alu))  # (and its handle)
		_box(hinge, Vector3(cw - 0.06, ch - 0.06, 0.01), Vector3(-o * cw / 2.0, ch / 2.0, 0), Color.WHITE).material_override = glass
		var creak := hinge.create_tween().set_loops()
		creak.tween_property(hinge, "rotation:y", swing - o * 0.05, 1.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		creak.tween_property(hinge, "rotation:y", swing + o * 0.02, 1.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		# Snow blown in on the sill board under the open casement, a boot print in it, and on the
		# floor below; and his boot prints in it, coming in off the sill and away across the room
		# toward the desk and its computer (smaller as the snow on his boots runs out), clear of the
		# papers. (A shade lighter than the snow: they read on the dark floor.)
		add.call(Vector3(ww / 2.0 - 0.06, 0.02, 0.18), Vector3(gap, sill + 0.025, 0.03), snow)
		add.call(Vector3(0.1, 0.006, 0.16), Vector3(gap - o * 0.03, sill + 0.034, 0.0), Color("3c4248"), Basis(Vector3.UP, 0.2))
		add.call(Vector3(0.5, 0.012, 0.22), Vector3(gap, 0.006, -0.16), snow)
		add.call(Vector3(0.2, 0.01, 0.12), Vector3(gap - o * 0.32, 0.005, -0.12), snow)
		var walk := Vector2(-o * 1.0, -0.85).normalized()  # (x, z): into the room, toward the desk
		var print_c := Color("c4ccd8")
		var yaw := atan2(walk.x, walk.y)
		for s in 5:
			var foot := Vector2(gap, -0.45) + walk * (0.36 * s) + Vector2(walk.y, -walk.x) * (0.09 if s % 2 == 0 else -0.09)
			var size := 1.0 - 0.12 * s
			var fwd := Vector3(walk.x, 0, walk.y) * size
			add.call(Vector3(0.105, 0.008, 0.16) * size, Vector3(foot.x, 0.004, foot.y) + fwd * 0.05, print_c, Basis(Vector3.UP, yaw))  # sole
			add.call(Vector3(0.085, 0.008, 0.07) * size, Vector3(foot.x, 0.004, foot.y) - fwd * 0.1, print_c, Basis(Vector3.UP, yaw))  # heel
		# A few flakes still blowing in.
		var drift := _snowfall(mv, 10, 2.6, Vector3(cw / 2.0 - 0.05, 0.55, 0.05), Vector3(0.0, -0.25, -1.0), Vector3(0.0, -0.32, 0.0), 0.3, 0.55)
		drift.name = "SnowIn"
		drift.spread = 22.0
		drift.position = Vector3(gap, (sill + transom) / 2.0 + 0.1, depth + 0.1)
		# The night coming in: cold light round the window, on the sill, the snow and the floor.
		var cold := Node3D.new()
		lamps.add_child(cold)
		cold.position = Vector3(cx + o * 0.2, 1.5, L - 0.7)
		_ambience.add_lamp(cold, Color(0.42, 0.52, 0.8) * 1.6, 3.6, {"alert": false})
	# Outside: the plaza out to the night city, a lamp post, and snow falling past the windows. The
	# city's skyline is placed for a level look out of the windows from the menu's camera (about 9 m
	# back from them): its towers just under the shut blinds, its sky over them. Every view out of the
	# windows, from the menu and the pan, lands within +-24 m of the middle (measured).
	var out := 30.0
	var wide := 50.0
	var ground := _plane(w, Vector2(wide, out + 0.3), Vector3(0, -0.04, depth + out / 2.0 - 0.15), PsxTextures.yard_asphalt(), Vector2(wide / 4.0, (out + 0.3) / 4.0))
	var gm := ground.mesh as PlaneMesh
	gm.subdivide_width = int(wide / 4.0) - 1  # (seen only far off through the glass: 4 m triangles do)
	gm.subdivide_depth = int(out / 4.0) - 1
	var bh := 13.0
	var city := MeshInstance3D.new()  # (one quad: no PS1 warping to break it up for)
	var quad := QuadMesh.new()
	quad.size = Vector2(wide, bh)
	city.mesh = quad
	w.add_child(city)
	city.position = Vector3(0, -2.25 + bh / 2.0, depth + out)
	city.rotation.y = PI  # (facing the room)
	city.material_override = PsxMaterials.backdrop(PsxTextures.city_view(), Vector2(wide / bh, 1.0))
	# A lamp post out on the plaza, seen from the menu through the window on his right (a warm light
	# out there, away from the open window).
	var lp := Vector3(7.5, 0, depth + 20.0)
	_box(w, Vector3(0.12, 3.2, 0.12), lp + Vector3(0, 1.6, 0), Color("2a2e32"))
	_box(w, Vector3(0.34, 0.14, 0.34), lp + Vector3(0, 3.25, 0), Color.WHITE).material_override = PsxMaterials.glow(Color("ffc880"))
	_box(w, Vector3(3.0, 0.01, 3.0), lp, Color.WHITE).material_override = PsxMaterials.glass(Color(1.0, 0.75, 0.4, 0.12))
	_halo(mv, lp + Vector3(0, 3.2, 0), Color(1.0, 0.75, 0.4, 0.4), 1.6)
	var fall := _snowfall(mv, 90, 7.0, Vector3(half + 1.0, 0.3, 2.0), Vector3(0.2, -1.0, 0.0), Vector3(0.1, -0.06, 0.0), 0.45, 0.75)
	fall.name = "SnowOut"
	fall.position = Vector3(0, h + 0.6, depth + 2.4)


## The start room's furniture and clutter: VORHALT's branch office at night, just after CROSS (the
## story the keen-eyed player can read: down a rope from above and in by the open window, its pot
## plant knocked off the sill; the computer tried, ACCESS DENIED; the filing cabinets gone through;
## the chair knocked over on his way to the door). In `d` (still, merged) and `lamps` (the lamps'
## anchors), the room's own space. Everything keeps clear of him, of his run to the door and of the
## menu's, the pan's and the play camera's paths and their views of him (measured: see the start
## room test). Against the back wall: the desk under the window on his right, its computer on, a
## desk lamp left on, a bin, a tall plant in the corner; the filing cabinets in the left corner,
## drawers pulled out, one dropped on the floor, files and sheets everywhere; radiators under the
## other two windows, the rope tied off round the open one's and its slack coiled over it. The
## chair knocked over behind him on his right. A VORHALT poster on the right wall; by the door a
## water cooler, a fire extinguisher, a coat stand and a wall clock (ten to three).
func _dress_start_room(d: Node3D, lamps: Node3D, L: float, half: float, cxs: Array[float]) -> void:
	var S := tuning.start_offset
	var open_x: float = cxs[START_WIN_OPEN]
	var shadows: Array[Array] = []  # [centre (x, z), size (x, z), yaw] under each piece standing on the floor
	# THE DESK under the window on his right, against the back wall: you sit at it facing the window,
	# so its screen faces the room (the menu's camera). Nudged in off the plant in the corner.
	var desk_x: float = minf(cxs[2], half - 1.45)
	_office_desk(d, lamps, Transform3D(Basis.IDENTITY, Vector3(desk_x, 0, L - 0.4)))
	shadows.append([Vector2(desk_x, L - 0.4), Vector2(1.6, 0.85), 0.0])
	# Its chair, knocked over behind him as he made for the door.
	_swivel_chair(d, Transform3D(Basis(Vector3.UP, -2.3), Vector3(1.55, 0, S + 1.3)), true)
	shadows.append([Vector2(1.55, S + 1.3), Vector2(0.9, 0.6), -2.3])
	# The bin by the desk, its paper spilled.
	_cyl(d, 0.15, 0.12, 0.32, Vector3(desk_x - 0.98, 0.16, L - 0.25), Color("2e3236"))
	_cyl(d, 0.13, 0.13, 0.02, Vector3(desk_x - 0.98, 0.3, L - 0.25), Color("d8d4c8"))
	for k in 2:
		_box(d, Vector3(0.08, 0.07, 0.08), Vector3(desk_x - 1.2 + k * 0.1, 0.035, L - 0.55 - k * 0.22), Color("e2ded2")).rotation = Vector3(0.6 * k, 0.9 + k, 0.4)
	# A tall plant (a yucca) in the corner past the desk.
	_potted_plant(d, Transform3D(Basis.IDENTITY, Vector3(half - 0.32, 0, L - 0.32)), 7)
	shadows.append([Vector2(half - 0.32, L - 0.32), Vector2(0.55, 0.55), 0.0])
	# THE FILING CABINETS gone through, in the left corner: one against the back wall in the corner
	# beside the open window, two along the side wall facing the room. Drawers pulled out (one right
	# out and dropped), files standing up in them, a box file tipped over on top.
	_filing_cabinet(d, Transform3D(Basis.IDENTITY, Vector3(-half + 0.26, 0, L - 0.32)), [0.42, 0.0, 0.22, 0.0])
	_filing_cabinet(d, Transform3D(Basis(Vector3.UP, -PI / 2.0), Vector3(-half + 0.32, 0, L - 0.9)), [0.0, -1.0, 0.0, 0.3])
	_filing_cabinet(d, Transform3D(Basis(Vector3.UP, -PI / 2.0), Vector3(-half + 0.32, 0, L - 1.42)), [0.38, 0.0, 0.0, 0.0])
	shadows.append([Vector2(-half + 0.26, L - 0.32), Vector2(0.55, 0.7), 0.0])
	shadows.append([Vector2(-half + 0.32, L - 1.16), Vector2(0.7, 1.05), 0.0])
	_dropped_drawer(d, Transform3D(Basis(Vector3.UP, 0.5), Vector3(-half + 1.0, 0, L - 2.05)))
	_box(d, Vector3(0.08, 0.3, 0.26), Vector3(-half + 0.26, 1.47, L - 0.36), Color("2a4a7a")).rotation.z = 1.2  # a box file, tipped over on top
	# Files and sheets all over the floor in front of them, a few drifted out toward the room.
	_paper_spill(d, Rect2(-half + 0.2, L - 3.6, 2.0, 2.4), 22, 9172, Vector2(-half + 0.6, L - 1.6))
	# (Round his feet, outside the metre he needs: the floor the menu shows under its buttons.)
	var strays: Array[Vector3] = [Vector3(-1.3, 0, S + 1.0), Vector3(-1.62, 0, S + 0.15), Vector3(-2.1, 0, S + 1.9),
			Vector3(-1.85, 0, S + 2.7), Vector3(1.25, 0, S + 0.35), Vector3(-1.2, 0, S - 1.6), Vector3(1.15, 0, S - 1.9)]
	for i in strays.size():
		var p := strays[i]
		_box(d, Vector3(0.21, 0.004, 0.29), Vector3(p.x, 0.016 + i * 0.001, p.z), Color("e6e2d6") if i % 3 else Color("d8d2b8")).rotation.y = p.x * 2.3 + p.z
	# Radiators under the open window and the one behind him; under the open one, the pot plant that
	# stood on its sill, knocked off as he climbed in: on its side, soil spilled, the plant out of it.
	for rx in [open_x, cxs[1]]:
		_box(d, Vector3(1.0, 0.56, 0.08), Vector3(rx, 0.4, L - 0.07), Color("aeb2ac"))
		_box(d, Vector3(1.0, 0.04, 0.1), Vector3(rx, 0.69, L - 0.07), Color("8e928c"))
	# The rope he came down on, in over the open window's sill, tied off round its radiator and its
	# slack coiled over it.
	_climbing_rope(d, L, open_x)
	var pot := _cyl(d, 0.09, 0.07, 0.14, Vector3(open_x + 0.38, 0.09, L - 0.4), Color("a4603c"))
	pot.rotation = Vector3(0.0, -0.7, PI / 2.0)
	_box(d, Vector3(0.34, 0.012, 0.22), Vector3(open_x + 0.22, 0.03, L - 0.5), Color("2c2218")).rotation.y = -0.5
	for k in 3:
		var leaf := _box(d, Vector3(0.05, 0.016, 0.2), Vector3(open_x + 0.1 - k * 0.03, 0.045, L - 0.6 + k * 0.03), Color("4a7a34"))
		leaf.rotation.y = 0.9 * k - 0.5
	# A VORHALT poster on the side wall by the desk.
	var poster := MeshInstance3D.new()
	var pq := QuadMesh.new()
	pq.size = Vector2(0.62, 0.86)
	poster.mesh = pq
	poster.material_override = PsxMaterials.textured(PsxTextures.vorhalt_poster(), Vector2.ONE)
	d.add_child(poster)
	poster.transform = Transform3D(Basis(Vector3.UP, -PI / 2.0), Vector3(half - 0.02, 1.62, L - 2.3))
	# BY THE DOOR (the play camera's view as he runs at it): a water cooler, a fire extinguisher, a
	# coat stand in the corner and the clock, off to the side (the camera comes through the wall over
	# the door after him).
	_water_cooler(d, Transform3D(Basis.IDENTITY, Vector3(-1.75, 0, 0.22)))
	shadows.append([Vector2(-1.75, 0.3), Vector2(0.45, 0.45), 0.0])
	_extinguisher(d, Vector3(1.2, 0, 0.09))
	_coat_stand(d, Transform3D(Basis(Vector3.UP, 0.4), Vector3(half - 0.42, 0, 0.5)))
	shadows.append([Vector2(half - 0.42, 0.5), Vector2(0.55, 0.55), 0.0])
	_wall_clock(d, Vector3(1.95, 3.05, 0.02), 2.0 + 50.0 / 60.0)
	# Contact shadows under what stands on the floor (one mesh, like the rest).
	for s in shadows:
		var sh := MeshInstance3D.new()
		sh.mesh = PsxMaterials.shadow_mesh(s[1] + Vector2.ONE * tuning.shadow_margin * 2.0)
		sh.material_override = PsxMaterials.shadow(true, tuning)
		d.add_child(sh)
		sh.transform = Transform3D(Basis(Vector3.UP, s[2]), Vector3(s[0].x, 0.03, s[0].y))


## The desk: a wood-effect top on a steel drawer pedestal and an end panel, its front toward -z
## (you sit at it facing +z). On it a beige CRT, on (VORHALT's log-in, ACCESS DENIED; its glow lights
## the desk), turned a little toward the room; the keyboard pushed askew, the mouse, a desk lamp left
## on (a warm pool), a mug, the phone and a stack of papers. The two lamps' anchors go in `lamps`
## (the same space as `parent`).
func _office_desk(parent: Node3D, lamps: Node3D, xf: Transform3D) -> void:
	var desk := Node3D.new()
	parent.add_child(desk)
	desk.transform = xf
	var wood := Color("6e5236")
	_box(desk, Vector3(1.5, 0.04, 0.74), Vector3(0, 0.74, 0), wood)
	_box(desk, Vector3(0.42, 0.7, 0.66), Vector3(0.5, 0.35, 0.02), Color.WHITE).material_override = \
			PsxMaterials.textured(PsxTextures.cabinet(), Vector2(3, 2))  # drawer pedestal
	_box(desk, Vector3(0.04, 0.72, 0.66), Vector3(-0.71, 0.36, 0.02), wood.darkened(0.3))  # end panel
	_box(desk, Vector3(1.0, 0.42, 0.02), Vector3(-0.2, 0.5, 0.32), wood.darkened(0.45))  # modesty panel
	var crt := Node3D.new()
	desk.add_child(crt)
	crt.position = Vector3(-0.12, 0.76, 0.1)
	crt.rotation.y = 0.3
	var beige := Color("c4bca2")
	_box(crt, Vector3(0.28, 0.03, 0.26), Vector3(0, 0.015, 0), beige.darkened(0.15))  # stand
	_box(crt, Vector3(0.42, 0.36, 0.36), Vector3(0, 0.21, 0), beige)
	_box(crt, Vector3(0.3, 0.26, 0.22), Vector3(0, 0.2, 0.28), beige.darkened(0.08))  # the tube's back
	var screen := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.32, 0.25)
	screen.mesh = q
	screen.material_override = PsxMaterials.textured(PsxTextures.crt_screen(), Vector2.ONE, true)
	crt.add_child(screen)
	screen.transform = Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0.215, -0.183))
	_box(desk, Vector3(0.44, 0.03, 0.15), Vector3(-0.22, 0.775, -0.2), Color("d0c8b0")).rotation.y = -0.25  # keyboard
	_box(desk, Vector3(0.06, 0.03, 0.1), Vector3(0.18, 0.775, -0.24), beige)  # mouse
	_cyl(desk, 0.045, 0.04, 0.1, Vector3(0.3, 0.81, -0.14), Color("e8e4d8"))  # mug
	_box(desk, Vector3(0.2, 0.07, 0.17), Vector3(-0.58, 0.795, 0.08), beige)  # phone
	_box(desk, Vector3(0.22, 0.045, 0.06), Vector3(-0.58, 0.85, 0.08), beige.darkened(0.12))  # its handset
	_box(desk, Vector3(0.3, 0.05, 0.22), Vector3(0.24, 0.785, 0.16), Color("e6e2d6")).rotation.y = 0.1  # papers
	# The desk lamp: base, two arms, the shade pointing down at the desk, the bulb under it.
	var green := Color("2c4a38")
	_box(desk, Vector3(0.14, 0.03, 0.14), Vector3(0.55, 0.775, 0.18), green)
	_box(desk, Vector3(0.025, 0.36, 0.025), Vector3(0.55, 0.94, 0.12), green).rotation.x = -0.35
	_box(desk, Vector3(0.025, 0.3, 0.025), Vector3(0.55, 1.12, -0.02), green).rotation.x = 1.0
	_box(desk, Vector3(0.14, 0.09, 0.18), Vector3(0.55, 1.06, -0.15), green).rotation.x = 0.45
	var bulb := _box(desk, Vector3(0.09, 0.02, 0.1), Vector3(0.55, 1.01, -0.17), Color.WHITE)
	bulb.rotation.x = 0.45
	bulb.material_override = PsxMaterials.glow(Color("ffd890"))
	for lamp in [[Vector3(0.55, 0.95, -0.25), Color(1.0, 0.76, 0.46) * 1.3, 1.9], [Vector3(-0.2, 1.0, -0.55), Color(0.4, 0.6, 1.0) * 1.0, 2.4]]:
		var at := Node3D.new()
		lamps.add_child(at)
		at.transform = xf * Transform3D(Basis.IDENTITY, lamp[0])
		_ambience.add_lamp(at, lamp[1], lamp[2], {"alert": false})


## An office swivel chair: seat, back on its post, gas lift, a star base with castors. Upright, it
## faces -z; `fallen`: knocked over on its side, resting on the floor.
func _swivel_chair(parent: Node3D, xf: Transform3D, fallen: bool) -> void:
	var chair := Node3D.new()
	parent.add_child(chair)
	chair.transform = xf
	var body := Node3D.new()
	chair.add_child(body)
	var cloth := Color("3a4a62")
	var black := Color("1c1c1e")
	_box(body, Vector3(0.48, 0.08, 0.46), Vector3(0, 0.5, 0), cloth)  # seat
	_box(body, Vector3(0.44, 0.52, 0.08), Vector3(0, 0.92, 0.25), cloth)  # back
	_box(body, Vector3(0.05, 0.22, 0.05), Vector3(0, 0.6, 0.24), black)  # its post
	_box(body, Vector3(0.06, 0.4, 0.06), Vector3(0, 0.27, 0), black)  # gas lift
	for k in 3:
		_box(body, Vector3(0.64, 0.04, 0.05), Vector3(0, 0.07, 0), black).rotation.y = k * PI / 3.0
	for k in 6:  # castors
		var a := k * PI / 3.0
		_box(body, Vector3(0.05, 0.05, 0.05), Vector3(cos(a) * 0.3, 0.025, sin(a) * 0.3), black)
	if fallen:
		body.rotation = Vector3(0.15, 0.0, deg_to_rad(82.0))
		_rest_on_floor(body)


## The open window's climbing rope (user, on making the clue louder: "add the climbing rope"): he
## came down from above on it. A bright orange climbing rope hangs down the outside of the building
## past the open casement, out of the night above the window (where nothing sees it end), is pulled
## in over the ledge's snow, the frame and the sill board, drops down the front of the radiator
## under the window and is tied off round it (a turn round the radiator and a fat knot on its
## front). Its slack is coiled beside the knot in three loops hung over the radiator, and its end
## hangs off the last loop to the floor and trails away toward the corner. It is 7 cm thick, far
## thicker than a real rope, because the main menu sees it from 9 m: there it is a 2 px orange line
## down the dark gap of the open casement and a tangle of orange loops on the pale radiator, plain
## to a keen eye and small beside him. In the open half of the window, clear of the casement swung
## in at its outer end, of the boot prints and of the knocked-off pot. In `d`, the room's space (z
## back from the door wall; the back wall's face at L, its outer face at L + 0.3); `cx` is the open
## window's middle. Lit by the window's cold light, and merged with the rest (no draw of its own).
func _climbing_rope(d: Node3D, L: float, cx: float) -> void:
	var o := 1.0 if cx >= 0.0 else -1.0  # (toward the open half: the nearer side wall)
	var sill := START_WIN_SILL
	var rx := cx + o * START_WIN_W * 0.16  # where it comes in, in the open half
	var thick := 0.07
	var r := thick / 2.0
	var rope := Color("ff6a0e")  # (saturated: under the window's cold blue light it is a deep orange)
	var top := 0.71 + r  # (over the radiator's cap)
	var front := L - 0.12 - r  # (down its front)
	var pts: Array[Vector3] = [
			Vector3(rx - o * 0.1, CEILING_Y + 3.0, L + 0.62),  # up into the night
			Vector3(rx, sill + 0.01 + r, L + 0.45),  # over the snow on the ledge outside
			Vector3(rx, sill + 0.06 + r, L + 0.16),  # over the frame's sill
			Vector3(rx, sill + 0.035 + r, L - 0.03),  # over the sill board's snow
			Vector3(rx, sill + 0.02 + r, L - 0.09 - r),  # its inner edge
			Vector3(rx, top - r * 0.6, front),  # the radiator's top
			Vector3(rx + o * 0.01, 0.46, front + 0.01)]  # down its front to the knot
	for i in pts.size() - 1:
		_cable(d, Transform3D.IDENTITY, pts[i], pts[i + 1], thick, rope)
	# Tied off: a turn round the radiator (under it and over its top) and the knot on its front.
	_box(d, Vector3(thick, 0.66, 0.14), Vector3(rx + o * 0.07, 0.4, L - 0.075), rope)
	var knot := _box(d, Vector3(0.14, 0.12, 0.09), Vector3(rx + o * 0.035, 0.43, L - 0.155), rope.darkened(0.15))
	knot.rotation.z = 0.35
	# The slack, coiled and hung over the radiator beside the knot (toward the window's middle): three
	# loops, each a U down its front from the cap (their backs hidden behind it), fanned out a little
	# and askew, the nearer ones in front. [middle (m from rx toward the middle), width, drop, tilt]
	var loops := [[0.17, 0.2, 0.42, 0.1], [0.26, 0.24, 0.34, -0.12], [0.35, 0.2, 0.47, 0.05]]
	var last := Vector3.ZERO
	for k in loops.size():
		var lp: Array = loops[k]
		var z := front - 0.004 - k * thick * 0.75
		var mid := rx - o * float(lp[0])
		var u0 := Vector3.ZERO
		for i in 9:  # (half an ellipse, top to bottom to top)
			var a := PI * i / 8.0
			var p := Vector3(mid + o * cos(a + float(lp[3])) * float(lp[1]) / 2.0, top - sin(a) * float(lp[2]), z)
			if i > 0:
				_cable(d, Transform3D.IDENTITY, u0, p, thick, rope)
			u0 = p
		last = u0
	# Its end, off the last loop and down to the floor, trailing away toward the corner past the knot
	# (lying 3.5 cm up its middle, so the floor's PS1 wobble never shows through it, as the papers).
	var tail: Array[Vector3] = [last, Vector3(last.x + o * 0.02, 0.035, L - 0.27), Vector3(rx + o * 0.12, 0.035, L - 0.33),
			Vector3(rx + o * 0.36, 0.035, L - 0.28), Vector3(rx + o * 0.52, 0.035, L - 0.38)]
	for i in tail.size() - 1:
		_cable(d, Transform3D.IDENTITY, tail[i], tail[i + 1], thick * 0.9, rope)


## Lifts (or lowers) `node` so the lowest point of its meshes sits on its parent's floor (y = 0).
func _rest_on_floor(node: Node3D) -> void:
	var low := INF
	for m in node.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D.IDENTITY
		var n: Node = m
		while n != node.get_parent():
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var box: AABB = (m as MeshInstance3D).get_aabb()
		for c in 8:
			low = minf(low, (xf * box.get_endpoint(c)).y)
	node.position.y -= low


## A four-drawer steel filing cabinet (0.48 x 1.32 x 0.62) standing on the floor, its front toward
## -z. `out`: how far each drawer is pulled out, top first (m; 0 shut; < 0 gone, an empty slot). A
## drawer that's out shows the files standing in it, one pulled half out and leaning.
func _filing_cabinet(parent: Node3D, xf: Transform3D, out: Array) -> void:
	var cab := Node3D.new()
	parent.add_child(cab)
	cab.transform = xf
	_box(cab, Vector3(0.48, 1.32, 0.62), Vector3(0, 0.66, 0), Color.WHITE).material_override = \
			PsxMaterials.textured(PsxTextures.cabinet(), Vector2(3, 2))
	for k in out.size():
		var o: float = out[k]
		if o == 0.0:
			continue
		var y := 1.32 - (k + 0.5) * 0.33
		_box(cab, Vector3(0.42, 0.29, 0.01), Vector3(0, y, -0.307), Color("121416"))  # the dark slot
		if o < 0.0:
			continue
		_drawer(cab, Vector3(0, y, -0.31 - o), o)


## A filing cabinet's drawer, its front's middle at `front` (local; front toward -z) and `depth`
## long behind it: the front (one drawer of the cabinet's texture), its steel sides, the files.
func _drawer(parent: Node3D, front: Vector3, depth: float) -> void:
	var f := _box(parent, Vector3(0.45, 0.31, 0.025), front, Color.WHITE)
	f.material_override = PsxMaterials.textured(PsxTextures.cabinet(), Vector2(3, 0.5))
	_box(parent, Vector3(0.4, 0.22, depth + 0.02), front + Vector3(0, -0.03, depth / 2.0), Color("5c6268"))
	_box(parent, Vector3(0.36, 0.07, maxf(depth - 0.04, 0.05)), front + Vector3(0, 0.1, depth / 2.0), Color("d8b878"))  # files
	var leaning := _box(parent, Vector3(0.3, 0.22, 0.02), front + Vector3(0.03, 0.18, depth * 0.35), Color("e8dcb0"))
	leaning.rotation.x = 0.4
	var sheet := _box(parent, Vector3(0.21, 0.004, 0.29), front + Vector3(-0.05, 0.13, -0.04), Color("ece8dc"))  # one half out over the front
	sheet.rotation = Vector3(-0.55, 0.2, 0.0)


## The drawer pulled right out and dropped, on its side on the floor, its files slid out of it.
func _dropped_drawer(parent: Node3D, xf: Transform3D) -> void:
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.transform = xf
	var dr := Node3D.new()
	holder.add_child(dr)
	dr.rotation = Vector3(0.0, 0.0, PI / 2.0 - 0.08)
	_drawer(dr, Vector3(0, 0, -0.25), 0.5)
	_rest_on_floor(dr)
	for k in 3:  # the files that slid out
		_box(holder, Vector3(0.24, 0.015, 0.32), Vector3(0.32 + k * 0.12, 0.035 + k * 0.012, -0.05 + k * 0.1), Color("c8a86a")).rotation.y = 0.5 * k - 0.3


## Sheets of paper and open files on the floor, `count` of them over `area` (x, z), more of them
## toward `heap` (where they came from), each a little above the last so none flickers through
## another. They lie 3.5 cm up: this far from the menu's camera (7 to 9 m), lying at 1.2 cm they
## broke up and popped through the floor as the PS1 snap wobbled the two (measured), as the door
## arrows did; 3.5 cm doesn't show from there.
func _paper_spill(parent: Node3D, area: Rect2, count: int, seed_v: int, heap: Vector2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	for i in count:
		var p := Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y))
		p = p.lerp(heap, rng.randf_range(0.0, 0.55))
		var folder := i % 6 == 5
		var size := Vector3(0.26, 0.012, 0.34) if folder else Vector3(0.21, 0.004, 0.29)
		var colour := Color("c8a86a") if folder else (Color("e6e2d6") if i % 4 else Color("d8d2b8"))
		var sheet := _box(parent, size, Vector3(p.x, 0.035 + i * 0.0008, p.y), colour)
		sheet.rotation = Vector3(0, rng.randf_range(0.0, TAU), 0)


## A tall potted plant (a yucca): a grey pot, soil, three canes of different heights, a spray of
## long leaves on each.
func _potted_plant(parent: Node3D, xf: Transform3D, seed_v: int) -> void:
	var plant := Node3D.new()
	parent.add_child(plant)
	plant.transform = xf
	_cyl(plant, 0.21, 0.16, 0.44, Vector3(0, 0.22, 0), Color("4e5052"))
	_cyl(plant, 0.19, 0.19, 0.02, Vector3(0, 0.43, 0), Color("2a2018"))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	for c in 3:
		var h := [1.05, 1.4, 0.8][c] as float
		var base := Vector3(rng.randf_range(-0.07, 0.07), 0.44, rng.randf_range(-0.07, 0.07))
		var lean := Vector3(rng.randf_range(-0.12, 0.12), 0, rng.randf_range(-0.12, 0.12))
		var tip := base + Vector3(0, h - 0.44, 0) + lean
		_cable(plant, Transform3D.IDENTITY, base, tip, 0.05, Color("6a5a3e"))
		for k in 7:
			var leaf := Node3D.new()
			plant.add_child(leaf)
			leaf.position = tip
			leaf.rotation = Vector3(0, k * TAU / 7.0 + c, 0)
			var blade := _box(leaf, Vector3(0.06, 0.5, 0.015), Vector3(0, 0.22, 0.1), Color("3e6a2e") if (k + c) % 2 else Color("2e5424"))
			blade.rotation.x = rng.randf_range(0.5, 1.25)


## A water cooler against the wall, its front toward +z: a white cabinet, the taps, the blue
## bottle upside down on top, a stack of paper cups on the side.
func _water_cooler(parent: Node3D, xf: Transform3D) -> void:
	var wc := Node3D.new()
	parent.add_child(wc)
	wc.transform = xf
	_box(wc, Vector3(0.32, 0.96, 0.32), Vector3(0, 0.48, 0), Color("d4d4cc"))
	_box(wc, Vector3(0.22, 0.2, 0.02), Vector3(0, 0.78, 0.165), Color("2a2c2e"))  # the recess
	_box(wc, Vector3(0.04, 0.05, 0.05), Vector3(-0.05, 0.86, 0.17), Color("2a5aa0"))  # taps
	_box(wc, Vector3(0.04, 0.05, 0.05), Vector3(0.05, 0.86, 0.17), Color("b02a20"))
	_cyl(wc, 0.14, 0.14, 0.42, Vector3(0, 1.2, 0), Color("6c9cc8"))
	_cyl(wc, 0.06, 0.06, 0.06, Vector3(0, 0.98, 0), Color("6c9cc8"))
	_cyl(wc, 0.035, 0.035, 0.3, Vector3(0.19, 0.95, 0.06), Color("e8e4d8"))


## A red fire extinguisher on its wall bracket, at `pos` against the wall (its front toward +z).
func _extinguisher(parent: Node3D, pos: Vector3) -> void:
	_box(parent, Vector3(0.1, 0.1, 0.04), pos + Vector3(0, 0.9, 0.0), Color("2a2a2a"))
	_cyl(parent, 0.075, 0.075, 0.44, pos + Vector3(0, 0.62, 0.08), Color("b01c1c"))
	_box(parent, Vector3(0.05, 0.08, 0.06), pos + Vector3(0, 0.88, 0.08), Color("1e1e1e"))
	_box(parent, Vector3(0.025, 0.3, 0.025), pos + Vector3(0.09, 0.66, 0.1), Color("1e1e1e"))  # hose
	_box(parent, Vector3(0.18, 0.18, 0.01), pos + Vector3(0, 1.22, 0.0), Color("c82018"))  # its sign


## A coat stand: a dark pole on a cross foot, hooks at the top, a trench coat hanging off one.
func _coat_stand(parent: Node3D, xf: Transform3D) -> void:
	var cs := Node3D.new()
	parent.add_child(cs)
	cs.transform = xf
	var wood := Color("2e2620")
	_box(cs, Vector3(0.045, 1.8, 0.045), Vector3(0, 0.9, 0), wood)
	for k in 2:
		_box(cs, Vector3(0.5, 0.04, 0.05), Vector3(0, 0.02, 0), wood).rotation.y = k * PI / 2.0
		_box(cs, Vector3(0.32, 0.025, 0.025), Vector3(0, 1.7, 0), wood).rotation.y = k * PI / 2.0 + PI / 4.0
	_box(cs, Vector3(0.07, 0.06, 0.07), Vector3(0, 1.83, 0), wood)
	var coat := _box(cs, Vector3(0.4, 0.95, 0.16), Vector3(0.0, 1.2, 0.13), Color("4a4636"))
	coat.rotation = Vector3(0.12, 0.0, 0.05)


## A round wall clock at `pos` (its face toward +z), its hands at `hours` (12-hour, decimal).
func _wall_clock(parent: Node3D, pos: Vector3, hours: float) -> void:
	_cyl(parent, 0.2, 0.2, 0.04, pos, Color("1c1e20")).rotation.x = PI / 2.0
	_cyl(parent, 0.17, 0.17, 0.046, pos, Color("e4e2d6")).rotation.x = PI / 2.0
	for hand in [[hours / 12.0, 0.1, 0.03], [fposmod(hours, 1.0), 0.15, 0.02]]:
		var a: float = hand[0] * TAU
		var m := _box(parent, Vector3(hand[2], hand[1], 0.01), pos + Vector3(sin(a), cos(a), 0) * hand[1] / 2.0 + Vector3(0, 0, 0.03), Color("121212"))
		m.rotation.z = -a


## A cylinder (`segments` sides, PS1 detail), its middle at `pos`.
func _cyl(parent: Node3D, r_top: float, r_bottom: float, h: float, pos: Vector3, color: Color, segments: int = 8) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bottom
	c.height = h
	c.radial_segments = segments
	c.rings = 1
	m.mesh = c
	m.material_override = PsxMaterials.flat(color)
	parent.add_child(m)
	m.position = pos
	return m


## Snow falling (the flakes of _build_snow): `amount` flakes living `life` s, from a box of
## `extents`, moving along `dir` at `v0`..`v1` m/s, pulled by `pull`. Already falling when built.
func _snowfall(parent: Node3D, amount: int, life: float, extents: Vector3, dir: Vector3, pull: Vector3, v0: float, v1: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.preprocess = life
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = extents
	p.direction = dir
	p.spread = 10.0
	p.gravity = pull
	p.initial_velocity_min = v0
	p.initial_velocity_max = v1
	p.mesh = _snow.mesh
	parent.add_child(p)
	return p


## Boxes merged into one mesh in `parent` (one draw call): each [size, position] or [size,
## position, basis], in its space.
func _box_mesh(parent: Node3D, boxes: Array, mat: Material) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in boxes:
		var box := BoxMesh.new()
		box.size = b[0]
		st.append_from(box, 0, Transform3D(b[2] if b.size() > 2 else Basis.IDENTITY, b[1]))
	var m := MeshInstance3D.new()
	m.mesh = st.commit()
	m.material_override = mat
	parent.add_child(m)
	return m


## A wall face with rectangular holes, and the reveals round each hole `depth` deep, as one mesh in
## `parent`'s space: the face at z = 0 facing -z (x across, y up), over x +-(half + 0.15) and y
## -0.15..h + 0.15 (tucked into the side walls, floor and ceiling like the walls). Cut on one grid
## (the holes' edges, and every 2 m or less), so every edge meets its neighbours on the same points
## (no T-joins to open into cracks under the PS1 snap). UVs in 2 m tiles, a tile's bottom row on
## the floor (as _wall), carried round into the reveals.
func _holed_wall(parent: Node3D, half: float, h: float, depth: float, holes: Array[Rect2]) -> MeshInstance3D:
	var xs: Array[float] = [-half - 0.15, half + 0.15]
	var ys: Array[float] = [-0.15, h + 0.15]
	for r in holes:
		xs.append_array([r.position.x, r.end.x])
		ys.append_array([r.position.y, r.end.y])
	xs = _grid(xs)
	ys = _grid(ys)
	var k0 := ceilf((h + 0.15) / 2.0)
	var uv := func(p: Vector3, n: Vector3) -> Vector2:
		if absf(n.y) > 0.5:
			return Vector2(p.x / 2.0, k0 - (p.y - p.z) / 2.0)
		return Vector2((p.x + absf(n.x) * p.z) / 2.0, k0 - p.y / 2.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in xs.size() - 1:
		for j in ys.size() - 1:
			var c := Vector2((xs[i] + xs[i + 1]) / 2.0, (ys[j] + ys[j + 1]) / 2.0)
			var in_hole := false
			for r in holes:
				if r.has_point(c):
					in_hole = true
			if not in_hole:
				_quad(st, Vector3(xs[i], ys[j], 0), Vector3(xs[i + 1], ys[j], 0), Vector3(xs[i + 1], ys[j + 1], 0), Vector3(xs[i], ys[j + 1], 0), Vector3.FORWARD, uv)
	for r in holes:
		for j in ys.size() - 1:
			if ys[j] >= r.position.y - 0.001 and ys[j + 1] <= r.end.y + 0.001:
				for side in [[r.position.x, Vector3.RIGHT], [r.end.x, Vector3.LEFT]]:
					var x: float = side[0]
					_quad(st, Vector3(x, ys[j], 0), Vector3(x, ys[j], depth), Vector3(x, ys[j + 1], depth), Vector3(x, ys[j + 1], 0), side[1], uv)
		for i in xs.size() - 1:
			if xs[i] >= r.position.x - 0.001 and xs[i + 1] <= r.end.x + 0.001:
				for side in [[r.position.y, Vector3.UP], [r.end.y, Vector3.DOWN]]:
					var y: float = side[0]
					_quad(st, Vector3(xs[i], y, 0), Vector3(xs[i + 1], y, 0), Vector3(xs[i + 1], y, depth), Vector3(xs[i], y, depth), side[1], uv)
	var m := MeshInstance3D.new()
	m.mesh = st.commit()
	parent.add_child(m)
	return m


## Sorted cut positions, the near-duplicates gone, and more put in so no gap is over `step`.
static func _grid(cuts: Array[float], step := 2.0) -> Array[float]:
	cuts.sort()
	var out: Array[float] = []
	for c in cuts:
		if not out.is_empty() and c - out[-1] < 0.001:
			continue
		if not out.is_empty():
			var a: float = out[-1]
			var n := ceili((c - a) / step - 0.01)
			for k in range(1, n):
				out.append(lerpf(a, c, float(k) / n))
		out.append(c)
	return out


## Two triangles a b c, a c d, wound to face `n` (a front face winds clockwise), UVs by `uv`.
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, uv: Callable) -> void:
	for tri in [[a, b, c], [a, c, d]]:
		var p: Array = tri
		if (p[1] - p[0]).cross(p[2] - p[0]).dot(n) > 0.0:
			p = [p[0], p[2], p[1]]
		for q: Vector3 in p:
			st.set_normal(n)
			st.set_uv(uv.call(q, n))
			st.add_vertex(q)


## Merges every mesh under `root` and frees the rest: scenery built from a couple of hundred little
## boxes drawn in about a dozen calls. Every plain-coloured (PsxMaterials.flat) part goes into one
## mesh textured with a palette of their colours, a texel each, each part's UVs on its own texel (so
## it's still lit, snapped and fogged exactly as before); the textured, glowing and see-through
## parts into one mesh per material. Only for things that never move or change on their own.
func _merge_static(root: Node3D) -> void:
	var tools := {}  # material -> SurfaceTool
	var palette: Array[Color] = []
	var flat: Array[Array] = []  # [mesh, transform, palette index]
	var stack: Array = [[root, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var top: Array = stack.pop_back()
		for c in (top[0] as Node).get_children():
			if not c is Node3D:
				continue
			var xf: Transform3D = top[1] * (c as Node3D).transform
			if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
				var mi := c as MeshInstance3D
				var mat := mi.material_override
				var col: Variant = mat.get_shader_parameter("albedo") if mat is ShaderMaterial else null
				if col is Color and (mat as ShaderMaterial).get_shader_parameter("albedo_texture") == null:
					var k := palette.find(col)
					if k < 0:
						palette.append(col)
						k = palette.size() - 1
					flat.append([mi.mesh, xf, k])
				else:
					if not tools.has(mat):
						var st := SurfaceTool.new()
						st.begin(Mesh.PRIMITIVE_TRIANGLES)
						tools[mat] = st
					(tools[mat] as SurfaceTool).append_from(mi.mesh, 0, xf)
			stack.append([c, xf])
	for c in root.get_children():
		root.remove_child(c)
		c.queue_free()
	for mat: Material in tools:
		var m := MeshInstance3D.new()
		m.mesh = (tools[mat] as SurfaceTool).commit()
		m.material_override = mat
		root.add_child(m)
	if flat.is_empty():
		return
	var side := 4
	while side * side < palette.size():
		side *= 2
	var img := Image.create(side, side, false, Image.FORMAT_RGB8)
	for k in palette.size():
		img.set_pixel(k % side, k / side, palette[k])
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var index := PackedInt32Array()
	for part in flat:
		var a := (part[0] as Mesh).surface_get_arrays(0)
		var xf: Transform3D = part[1]
		var nb := xf.basis.inverse().transposed()
		var uv := Vector2((int(part[2]) % side + 0.5) / side, (int(part[2]) / side + 0.5) / side)
		var base := verts.size()
		for v: Vector3 in a[Mesh.ARRAY_VERTEX]:
			verts.append(xf * v)
			uvs.append(uv)
		for n: Vector3 in a[Mesh.ARRAY_NORMAL]:
			norms.append((nb * n).normalized())
		var ii: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		if ii.is_empty():
			ii = PackedInt32Array(range(verts.size() - base))
		for i in ii:
			index.append(base + i)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = index
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# (The same palette, the same texture: a retry builds the room again, and every new texture is
	# another material kept in PsxMaterials' cache for good.)
	var key := ",".join(palette.map(func(c: Color) -> String: return c.to_html()))
	if not _palettes.has(key):
		_palettes[key] = ImageTexture.create_from_image(img)
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = PsxMaterials.textured(_palettes[key], Vector2.ONE)
	root.add_child(m)


## _merge_static's palette textures, by their colours.
static var _palettes := {}


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
		"bollards":
			_bollard_lamps(parent, seg)
		"roof_posts":
			_roof_lamp_posts(parent, seg)
		"hall":
			_hall_lamps(parent, seg)
		"tubes":
			_sewer_tubes(parent, seg)


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
	# The wall over the doorway starts in the middle of the frame's top bar: its underside level
	# with the bar's, the two fought along the top of every zone door (483 px seen from under it,
	# in the SECURITY WING: the user's popping). Line of sight as before, from the doorway's top.
	var over := _item_box(parent, seg, at, Vector3(0, (dh + 0.04 + top) / 2.0, 0), Vector3(ow + 0.16, top - dh - 0.04, 0.3), Color.WHITE)
	over.material_override = wall
	over.set_meta("solid", true)
	_solid_box(over, Transform3D(Basis.IDENTITY, Vector3(0, -0.02, 0)), Vector3(ow + 0.16, top - dh, 0.3))
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
	# The alarm runner pushes it open as he comes, and it shuts behind him (_runner_gates).
	var gate := {"node": parent, "frame": _frame_at(seg, at), "at": seg["start"] + at, "owner": seg["node"],
			"leaves": [], "shutter": null, "bars": barred, "sweep": 0.15, "half_w": ow / 2.0, "state": Gate.SHUT,
			"by": null, "tween": null, "was": Gate.SHUT, "quiet": false}
	if not seg.get("no_doors", false):
		_gates.append(gate)
	# Leaving the WAREHOUSE (user): a roller shutter that rolls up as you come, not doors.
	if String(_theme(seg.get("from_id", seg["id"])).get("exit_door", "")) == "shutter":
		_build_shutter(parent, seg, at, ow, dh, gate)
		_make_solid(parent)
		_markers.append({"at": seg["start"] + at, "seg": seg})
		return
	var leaf_w := ow / 2.0
	gate["sweep"] = leaf_w  # (the leaves swing out this far past the door)
	var door_mat := PsxMaterials.textured(PsxTextures.steel_door() if String(theme.get("marker_door", "")) == "steel" else PsxTextures.door(), Vector2(3, 2))
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
			# (From shut, wherever the alarm runner may have left it: "shut".)
			var door := {"node": hinge, "at": seg["start"] + at, "owner": seg["node"], "seg": seg, "swing": -s,
					"shut": hinge.rotation, "gate": gate}
			if s < 0:  # one crash for the pair
				door["sound"] = "door_bars" if barred else "door_wood"
			_doors.append(door)
			gate["leaves"].append({"node": hinge, "swing": -s, "shut": hinge.rotation})
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
func _build_shutter(parent: Node3D, seg: Dictionary, at: float, ow: float, dh: float, gate: Dictionary) -> void:
	var shutter := Node3D.new()
	parent.add_child(shutter)
	shutter.transform = _frame_at(seg, at)
	var curtain := _box(shutter, Vector3(ow, dh, 0.08), Vector3(0, dh / 2.0, 0), Color.WHITE)
	curtain.material_override = PsxMaterials.textured(PsxTextures.roller_shutter(), Vector2(ow / 1.6, dh / 1.0))
	_solid_box(shutter, Transform3D(Basis.IDENTITY, Vector3(0, dh / 2.0, 0)), Vector3(ow, dh, 0.1))
	_item_box(parent, seg, at, Vector3(0, dh + 0.2, 0.1), Vector3(ow + 0.3, 0.42, 0.45), Color("3e4448"))  # roll housing
	for s in [-1.0, 1.0]:
		# The guide rail, its face 1 cm into the doorway, in front of the door frame's post: level
		# with it, the two fought down the doorway's sides (the user's popping). Line of sight as before.
		var rail := _item_box(parent, seg, at, Vector3(s * (ow / 2.0 + 0.055), dh / 2.0, 0), Vector3(0.13, dh, 0.16), Color("2a2e30"))
		rail.set_meta("solid", true)
		_solid_box(rail, Transform3D(Basis.IDENTITY, Vector3(s * 0.005, 0, 0)), Vector3(0.12, dh, 0.16))
		_item_box(parent, seg, at, Vector3(s * (ow / 2.0 + 0.25), 0.5, 0.25), Vector3(0.16, 1.0, 0.16), Color.WHITE).material_override = \
				PsxMaterials.textured(PsxTextures.hazard(), Vector2(1, 2))  # hazard post
	var amber := Color(1.0, 0.6, 0.12)
	var lamp := _item_box(parent, seg, at, Vector3(ow / 2.0 + 0.3, dh + 0.25, 0.35), Vector3(0.22, 0.22, 0.22), Color.WHITE)
	lamp.material_override = PsxMaterials.glow(amber)
	_ambience.add_lamp(lamp, amber * 1.2, 4.0, {"alert": false, "blink": 0.8})
	if not seg.get("no_doors", false):
		_doors.append({"node": shutter, "at": seg["start"] + at, "owner": seg["node"], "seg": seg, "shutter": true,
				"sound": "door_steel", "shut_y": shutter.position.y, "gate": gate})
		gate["shutter"] = {"node": shutter, "shut_y": shutter.position.y}


## Up it goes: the shutter rolls up into its housing (from `shut_y`, its height shut: from wherever
## the alarm runner left it, all the way up, as ever).
func _raise_shutter(shutter: Node3D, shut_y: float) -> void:
	RunLog.record_event("door_bash", {})
	var tween := shutter.create_tween()
	tween.tween_property(shutter, "position:y", shut_y + GATE_H - 0.05, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## Forced movement. The outer lanes can't get through a halfway marker's doorway: just before one,
## anyone out there is steered in to the nearest lane that can. And at the very end you're steered
## into the centre lane, lined up with the chopper (after the boss, the lane beside his body, all
## the way to the chopper).
func _funnel_to_markers() -> void:
	if _player.in_cover or _player.standoff:
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
		if _boss_fight != null and is_instance_valid(_boss_fight) and not _boss_fight.is_alive():
			_player.lane = mid - 1 if _player.track_x <= 0.0 else mid + 1  # past his body, beside it


## Out of the room: the door flies open off its hinge and the camera jolts. `roll`: how far it
## tips as it goes, for each unit of `swing`. `shut`: the door's turn shut (see _swing_open).
## `quiet`: it's already standing open (the alarm runner's left it so), and you just run on
## through, sending it on round: no jolt.
func _bash_door(door: Node3D, swing: float = 1.0, roll: float = 0.1, shut: Variant = null, quiet: bool = false) -> void:
	RunLog.record_event("door_bash", {})
	if not quiet:
		_shake = 1.0 if _shake_on else 0.0  # SCREEN SHAKE setting
	_swing_open(door, swing, roll, shut)


## Swings away from the player, out into the lobby, as if shouldered open: to where it goes from
## `shut` (its turn shut; by default, as it is now), from wherever it is (a zone door the alarm
## runner's pushed open goes on round from there, not on as far again).
func _swing_open(hinge: Node3D, swing: float, roll: float, shut: Variant = null) -> void:
	var from: Vector3 = hinge.rotation if shut == null else shut
	var tween := hinge.create_tween()
	tween.tween_property(hinge, "rotation:y", from.y + 1.9 * swing, 0.16).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(hinge, "rotation:z", from.z + roll * swing, 0.16)


## Where there is no way straight on: a wall across the middle lanes. Only the outer lanes (ladders) get out.
func _build_dead_end(parent: Node3D, seg: Dictionary) -> void:
	var length: float = seg["length"]
	var theme := _theme(seg["id"])
	var h: float = CEILING_Y if theme.get("ceiling", false) else maxf(theme["height"], 1.2)
	var w := (tuning.lane_count - 2) * tuning.lane_width
	# Where the ladders go up out of it, only as high as the deck above (it stood 0.6 m up out of
	# the helipad's deck, by the hatch: the user's gaps; the wall over the end covers above it).
	var covered: bool = theme.get("ceiling", false) and _ceil(seg["id"]) > CEILING_Y + 0.1 and _climbs_out(seg["id"])
	var shown := minf(h, tuning.tier_height) if covered else h
	var wall := _item_box(parent, seg, length, Vector3(0, shown / 2.0, -0.2), Vector3(w, shown, 0.4), Color.WHITE)
	wall.material_override = PsxMaterials.textured(_wall_texture(theme), Vector2(3, 2))
	wall.set_meta("solid", true)
	_solid_box(wall, Transform3D(Basis.IDENTITY, Vector3(0, (h - shown) / 2.0, 0)), Vector3(w, h, 0.4))  # (its line of sight as before)


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
	# The tunnel's end beside the shaft, out to its side wall: up to the deck, not through it (it
	# stood 0.6 m up out of the deck by the hatch; the wall over the tunnel's end covers above).
	var out := signf(x)
	var from := absf(x) + w / 2.0 + 0.2
	var below_id: StringName = seg.get("from_id", seg["id"])
	var end_h := minf(CEILING_Y, dy) if _ceil(below_id) > CEILING_Y + 0.1 and _climbs_out(below_id) else CEILING_Y
	if edge + 0.2 - from > 0.05:
		_item_box(parent, seg, 0.0, Vector3(out * (from + edge + 0.2) / 2.0, end_h / 2.0, 0), Vector3(edge + 0.2 - from, end_h, 0.3),
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


## The first few metres of a branch closed by alert, behind a lockdown shutter; or, for a stairs
## door, that door, shut, just where it stands while it's open (user, 2026-10-08: "I don't want the
## locked door to be tucked beside the lane, keep it the same as the unlocked door, doors and walls
## don't move unless I say so"): its stairwell's way in, built by the same lines as an open one's
## (_build_stairwell, its mouth only), and none of the rest. It stands across the outer lane at the
## split, as it does open, so while it's locked he's eased out of that lane as he comes up to it
## (_bar_lane). The hole its stairwell passes out through in the side wall of the road on is walled
## up while it's locked (_show_lock_plugs). (The whole stub of a stairwell, built and hidden, blocked
## sight and shots where nothing was seen, so only the way in is built: it blocks sight just as an
## open one's does, and nothing else does.)
func _build_locked_stub(seg: Dictionary, edge: Dictionary, slam: bool) -> Node3D:
	var stub := _segment_shape(StringName(edge["to"]), edge, seg["id"])
	var xf := _frame_after(seg, edge)
	var node := Node3D.new()
	node.name = "Locked_" + String(edge["to"])
	_world.add_child(node)
	node.transform = xf
	stub["legs"] = _plan_legs(stub, xf)  # planned at full length, so it bends where the real one would
	stub["start"] = seg["end"]
	stub["no_doors"] = true  # you can't go this way, so its doors never open
	stub["node"] = node
	if _is_stairs(stub):
		_build_stairwell(node, stub, true)
		node.set_meta("stairs_door", true)
		_bar_lane(seg, edge, node)
		return node
	stub["length"] = minf(stub["length"], tuning.locked_stub_length)
	var side := RouteGraph.side_of(edge)
	var clear := _overlap_clear()
	_build_surfaces(node, stub, clear if side == "right" else 0.0, clear if side == "left" else 0.0)
	# The shutter covers the way in: the whole road.
	var door := _lockdown_shutter(node, "LockdownDoor", _frame_at(stub, 1.5), tuning.lane_count * tuning.lane_width + 2.2,
			maxf(_theme(stub["id"])["height"], 3.0))
	_make_solid(door)  # shut, you can't see (or shoot) past it
	if slam:
		door.position.y = door.get_meta("open_y")
		door.create_tween().tween_property(door, "position:y", door.get_meta("closed_y"), tuning.lockdown_close_time) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	return node


## A locked stairs door out of `seg` by `edge` (`stub`: _build_locked_stub) stands across the
## outer lane at the split, the one that takes it while it's open: from DOOR_NUDGE_AHEAD before the
## split until he's DOOR_PAST beyond the furthest any of it reaches, that lane is barred
## (_door_bars): he's eased out of it, a swipe back into it is refused (_ease_past_locked_doors),
## and anyone running after him keeps out of it too (_through_doors).
func _bar_lane(seg: Dictionary, edge: Dictionary, stub: Node3D) -> void:
	var d := _player.distance_run()
	_door_bars = _door_bars.filter(func(b: Dictionary) -> bool: return is_instance_valid(b["stub"]) and float(b["to"]) >= d)
	var end: Transform3D = seg["node"].global_transform * _frame_in_leg(seg, seg["legs"].size() - 1, seg["length"])
	var inv := end.affine_inverse()
	var reach := 0.0  # (m past the split)
	for m: MeshInstance3D in stub.find_children("*", "MeshInstance3D", true, false):
		var box := m.get_aabb()
		for k in 8:
			var at := inv * (m.global_transform * (box.position + box.size * Vector3(k & 1, (k >> 1) & 1, (k >> 2) & 1)))
			reach = maxf(reach, -at.z)
	_door_bars.append({"stub": stub, "lane": _handover_lanes(edge).x, "from": float(seg["end"]) - DOOR_NUDGE_AHEAD,
			"to": float(seg["end"]) + reach + DOOR_PAST})


## The lane a locked stairs door bars (_bar_lane) at route distance `d`, or -1.
func _barred_lane(d: float) -> int:
	for b: Dictionary in _door_bars:
		if d >= float(b["from"]) and d <= float(b["to"]):
			return b["lane"]
	return -1


## Forced movement past a locked stairs door (user, 2026-10-08: "Locked doors can nudge CROSS into
## the next lane, that sounds fine."): while it bars his lane (_bar_lane) he's moved a lane in, as
## a swipe would move him (the camera after him), early enough that he never touches the door, and
## a swipe back into that lane is refused (Player.barred_lane) till he's past it. Then nothing more:
## he stays in the lane he's in. (Stopped in cover there, he's left alone: he can't reach the door,
## and can only leave the cover a lane in.)
func _ease_past_locked_doors() -> void:
	var barred := _barred_lane(_player.distance_run())
	_player.barred_lane = barred
	if barred >= 0 and _player.lane == barred and not _player.in_cover and not _player.standoff:
		_player.lane = barred + (1 if barred == 0 else -1)


## A lockdown shutter, `width` by `h`, standing at `xf` (facing +z), its LOCKDOWN sign and hazard
## band on: it drops from above as it shuts and lifts back up as it opens (metas closed_y, open_y).
func _lockdown_shutter(parent: Node3D, called: String, xf: Transform3D, width: float, h: float) -> Node3D:
	var door := Node3D.new()
	door.name = called
	parent.add_child(door)
	door.transform = xf
	var panel := _box(door, Vector3(width, h, 0.3), Vector3(0, h / 2.0, 0), Color.WHITE)
	panel.material_override = PsxMaterials.textured(PsxTextures.wall("corrugated", LOCKDOWN_STEEL), Vector2(3, 2))
	var band := _box(door, Vector3(width + 0.05, 0.5, 0.34), Vector3(0, 0.25, 0), Color.WHITE)
	band.material_override = PsxMaterials.textured(PsxTextures.hazard(), Vector2(6, 2))
	door.add_child(_sign_label("LOCKDOWN", DEAD_END_COLOR, width * 0.8, Vector3(0, h * 0.6, 0.2)))
	door.set_meta("closed_y", door.position.y)
	door.set_meta("open_y", door.position.y + h + 0.3)
	return door


## Alert fell and a locked branch reopened: lift its door, then drop the stub (the full branch replaces it).
## A locked stairs door goes at once, and its lane is barred no more: the whole stairwell comes back
## in the same frame, its door the same door in the same place, so nothing moves (its padlock
## shrinks away: _build_door_cues).
func _open_door(stub: Node3D) -> void:
	var door := stub.get_node_or_null("LockdownDoor")
	if door == null:
		for k in _door_bars.size():
			if _door_bars[k]["stub"] == stub:
				_door_bars.remove_at(k)
				break
		stub.visible = false
		stub.queue_free()
		return
	var tween := door.create_tween()
	tween.tween_property(door, "position:y", door.get_meta("open_y"), tuning.lockdown_close_time)
	tween.tween_callback(stub.queue_free)


## The exits the sign over the split shows (_build_fork_cue), in their authored order: every one
## open at this alert, and every stairs door, open or locked. A locked one stands at the split all
## the same, the same door in the same place (_build_locked_stub), so the panel over its lane
## still says where it goes, as it does while it's open (user, 2026-10-08: "keep it the same as the
## unlocked door"); its padlock and dark arrows say it's locked (_build_door_cues).
func _signed_exits(id: StringName) -> Array[Dictionary]:
	var open := _graph.available_next(id, GameState.alert_level)
	var out: Array[Dictionary] = []
	for edge in _graph.all_next(id):
		if open.has(edge) or RouteGraph.via_of(edge) == "stairs":
			out.append(edge)
	return out


## Puts a sign over the split, a panel over the lanes each exit takes (the floor is the road's),
## and the arrows in to a stairs door or its padlock (_build_door_cues).
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
	var opts := _signed_exits(id)
	var choice := RouteGraph.is_choice(opts)

	# The floor up to the split is plain floor (user decision: no lane paint or arrows; the sign
	# overhead and the prompt say where each lane goes), so it's the area's own road, which runs
	# on to the end (_build_surfaces). (Laid here as a strip of its own, it was cut off the road
	# 0.6 m before a bend on the ROOF EDGE and in the STORM DRAIN, and the two fought there.)
	# The one exception, the user's own later request: three arrows in to each stairs door, or a
	# padlock while it's locked (user, 2026-10-07: "I think the doors going up and down need to be
	# more obvious maybe 3 arrows just before that").
	_build_door_cues(cue, seg, old)
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


## The stairs doors made obvious (user, 2026-10-07: "I think the doors going up and down need to
## be more obvious maybe 3 arrows just before that are a bit transparent and light up one after
## another, but if a door is locked there is a floating red lock in front of the door").
## While a door is open: three see-through teal arrows in its lane before it, tipped up toward the
## door, lit one after another toward it, over and over. While it's locked: the arrows dark and
## still, and a red padlock floating in front of the door. They're part of the fork cue, which is
## rebuilt as the alert changes, so they follow the door as it opens and shuts. A lock already
## there is kept as it is (it doesn't jump as it's rebuilt); one that's just shut pops in, and one
## that's just opened shrinks away as its stairwell comes back. None of it is solid, and none of it
## is in the game (nothing to hit, nothing that blocks a shot).
func _build_door_cues(cue: Node3D, seg: Dictionary, old: Node) -> void:
	var was: Dictionary = seg.get("door_cues", {})  # side -> open, as last built
	var now := {}
	var length: float = seg["length"]
	var w := minf(DOOR_ARROW_SIZE.x, tuning.lane_width - 0.2)
	var d := DOOR_ARROW_SIZE.y
	var a := deg_to_rad(DOOR_ARROW_TILT)
	# Tipped up about its back edge, which stays just off the floor where it lay.
	var tilt := Transform3D(Basis(Vector3.RIGHT, a), Vector3(0, 0.03 + d / 2.0 * sin(a), d / 2.0 * (1.0 - cos(a))))
	for door in _graph.stair_doors(seg["id"], GameState.alert_level):
		var side: String = door["side"]
		var open: bool = door["open"]
		now[side] = open
		var x := _player.lane_x(_handover_lanes(door["edge"]).x)  # the outer lane that takes it
		var n := DOOR_ARROWS_AT.size()
		for i in n:
			var arrow := MeshInstance3D.new()
			arrow.name = "DoorArrow_%s_%d" % [side, i]
			arrow.mesh = _arrow_mesh(w)
			arrow.material_override = PsxMaterials.door_arrow(i, n, UiKit.TEAL, true) if open \
					else PsxMaterials.door_arrow(i, n, UiKit.TEAL.darkened(0.55), false)
			arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			cue.add_child(arrow)
			arrow.transform = _frame_at(seg, length - float(DOOR_ARROWS_AT[i])) * Transform3D(Basis.IDENTITY, Vector3(x, 0, 0)) * tilt
		var had: Node3D = old.get_node_or_null("DoorLock_" + side) if old != null else null
		if not open and had != null and not was.get(side, false):
			old.remove_child(had)  # still locked: the same lock, mid-bob, carries on
			cue.add_child(had)
		elif not open:
			_door_padlock(cue, seg, side, door["edge"], was.get(side, false))
		elif had != null:
			# Just opened: the lock shrinks away (then it's gone).
			old.remove_child(had)
			cue.add_child(had)
			had.name = "Unlocking_" + side
			var t := had.create_tween()
			t.tween_property(had, "scale", Vector3.ONE * 0.01, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
			t.tween_callback(had.queue_free)
	seg["door_cues"] = now


## The floating padlock in front of a locked stairs door: a red body, a pale shackle, a dark
## keyhole front and back, and a soft red glow behind it, bobbing and swaying slowly, facing you
## down the road. It floats DOOR_LOCK_BEFORE out in front of the middle of the door (between the
## door and you), on the top half of the door, under its exit sign (DOOR_LOCK_Y). It dithers away as
## the camera comes close. No lamp of its own: one more lamp near the door could push a ceiling
## lamp out of the nearest 12 the lighting uses, and its pool would pop (Ambience). pop: the door
## was open a moment ago, so the lock pops in.
func _door_padlock(cue: Node3D, seg: Dictionary, side: String, edge: Dictionary, pop: bool) -> void:
	var at := Node3D.new()  # where it floats; the lock bobs and sways inside it
	at.name = "DoorLock_" + side
	cue.add_child(at)
	at.transform = Transform3D(_frame_at(seg, float(seg["length"])).basis,
			_stair_door_frame(seg, edge) * Vector3(0, DOOR_LOCK_Y, DOOR_LOCK_BEFORE))
	var lock := Node3D.new()
	at.add_child(lock)
	var red := PsxMaterials.near_fade(PsxMaterials.glow(UiKit.RED))
	var steel := PsxMaterials.near_fade(PsxMaterials.glow(UiKit.PAPER.darkened(0.2)))
	var hole := PsxMaterials.near_fade(PsxMaterials.glow(Color("2a0806")))
	var parts := [[Vector3(0.62, 0.5, 0.16), Vector3(0, -0.12, 0), red]]  # the body
	# The shackle: an arch of five bars over the body, its legs into the body's top.
	for s in [-1.0, 1.0]:
		parts.append([Vector3(0.09, 0.26, 0.09), Vector3(s * 0.2, 0.2, 0), steel])
		parts.append([Vector3(0.1, 0.1, 0.09), Vector3(s * 0.16, 0.37, 0), steel])
	parts.append([Vector3(0.26, 0.09, 0.09), Vector3(0, 0.41, 0), steel])
	# The keyhole, front and back: a round-ish head and a slot under it.
	for s in [-1.0, 1.0]:
		parts.append([Vector3(0.1, 0.1, 0.02), Vector3(0, -0.06, s * 0.085), hole])
		parts.append([Vector3(0.05, 0.14, 0.02), Vector3(0, -0.16, s * 0.085), hole])
	for p in parts:
		var b := _box(lock, p[0], p[1], Color.WHITE)
		b.material_override = p[2]
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var halo := _halo(at, Vector3(0, -0.05, -0.15), UiKit.RED * Color(1, 1, 1, 0.55), 1.7)
	halo.material_override = PsxMaterials.near_fade(halo.material_override as StandardMaterial3D, true)
	# Floating: a slow bob, and a sway either way.
	var bob := lock.create_tween().set_loops()
	bob.tween_property(lock, "position:y", 0.07, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	bob.tween_property(lock, "position:y", -0.07, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var sway := lock.create_tween().set_loops()
	sway.tween_property(lock, "rotation:y", 0.32, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	sway.tween_property(lock, "rotation:y", -0.32, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if pop:
		at.scale = Vector3.ONE * 0.01
		at.create_tween().tween_property(at, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## The stairs doors' arrows and padlock (_build_door_cues) are drawn in looks nothing else in the
## level uses: the arrows' own shader, and the lock's and its glow's fade as you come close. Each
## is put together the first time it's drawn, which on a phone could hitch the run at the first
## stairs door (the LOBBY's end). So one of each is drawn once at the start, under the menu, 1.5 m
## in front of the camera, where they all fade to nothing (the arrows within 6 m of it, the lock
## within 3.5 m), and then it goes. The plain halo and the sniper's glint go with them (clear: they
## add no light), so the first sniper and the squad's rifle lights don't hitch the run either.
func _warm_door_cues() -> void:
	var warm := Node3D.new()
	warm.name = "DoorCueWarmUp"
	_camera.add_child(warm)
	warm.position = Vector3(0, 0, -1.5)
	var arrow := MeshInstance3D.new()
	arrow.mesh = _arrow_mesh(minf(DOOR_ARROW_SIZE.x, tuning.lane_width - 0.2))
	arrow.material_override = PsxMaterials.door_arrow(0, DOOR_ARROWS_AT.size(), UiKit.TEAL, true)
	arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	warm.add_child(arrow)
	arrow.rotation.x = PI / 2.0  # (stood up, facing the camera: lying flat, it's edge on)
	var lock := _box(warm, Vector3(0.2, 0.2, 0.2), Vector3.ZERO, Color.WHITE)
	lock.material_override = PsxMaterials.near_fade(PsxMaterials.glow(UiKit.RED))
	lock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var halo := _halo(warm, Vector3.ZERO, UiKit.RED * Color(1, 1, 1, 0.55), 0.3)
	halo.material_override = PsxMaterials.near_fade(halo.material_override as StandardMaterial3D, true)
	# The plain glow round a light (PsxMaterials.halo: the sniper's muzzle flash, the squad's rifle-light
	# glare), which no lamp in the level draws now that their halos fade near the lens (lamp_halo), and
	# the sniper's glint (the same, keeping its scale): otherwise first drawn mid-run. Clear, so adding
	# their light here adds nothing. (Their materials are kept, so their shaders are too.)
	for keep_scale in [false, true]:
		var glow := _halo(warm, Vector3.ZERO, Color.WHITE, 0.3)
		glow.material_override = PsxMaterials.halo(Color(1, 1, 1, 0), keep_scale)
	RenderingServer.frame_post_draw.connect(warm.queue_free, CONNECT_ONE_SHOT)


## Every texture the level can draw with, made ahead of time. Otherwise building the next area's
## branches as you commit at a fork makes any it hasn't had yet, often ten or more at once, a few
## milliseconds each on a desktop and more on a phone, and that frame hitches. The first area's and
## its branches' are made as the level loads. The rest are made a few a frame (_process,
## WARM_BUDGET_MS) under the main menu, once the sounds are built; whatever's left when START comes,
## faster under the briefing and the pan (WARM_HURRY_MS); and if those are tapped through, all at
## once as the run starts (start_run), before he's yours: never in the run. Retry skips the menu, so
## there they're all made at once as the level loads (usually there are none left: they're kept
## from the first try). The list: every PsxTextures function made with nothing passed and every
## CCTV screen and menu board (PsxTextures.makers()), then those made from the level's own choices:
## the walls and stairwell walls of each area on the route, the floor lines, a lockdown shutter's
## steel and the drinks machines.
func _warm_textures() -> void:
	_to_warm = PsxTextures.makers()
	var themes := {}
	for n: Dictionary in _graph.mission().get("nodes", []):
		themes[n.get("theme", "")] = _theme(StringName(n["id"]))
	for theme: Dictionary in themes.values():
		_to_warm.append(_wall_texture.bind(theme))
		_to_warm.append(_stair_wall_texture.bind(theme))
	_to_warm.append(PsxTextures.wall.bind("blocks", LINE_PAINT))
	_to_warm.append(PsxTextures.wall.bind("corrugated", LOCKDOWN_STEEL))
	for tint: Color in VENDING_TINTS:
		_to_warm.append(PsxTextures.vending_front.bind(0, tint))
	_to_warm.append(PsxTextures.vending_front.bind(1))
	_warm_next = 0


## Makes the textures still to make (_warm_textures) for up to `budget_ms` (always at least one;
## one already made costs next to nothing). Once they're all made, the list is let go.
func _make_warm(budget_ms: float) -> void:
	var start := Time.get_ticks_usec()
	while _warm_next < _to_warm.size() and (Time.get_ticks_usec() - start) < budget_ms * 1000.0:
		_to_warm[_warm_next].call()
		_warm_next += 1
	if _warm_next >= _to_warm.size():
		_to_warm.clear()
		_warm_next = 0


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
		"exit_floor":
			return PsxTextures.exit_floor()
		"helipad_slab":
			return PsxTextures.helipad_slab()
		"service_floor":
			return PsxTextures.service_floor()
		"steel_plate":
			return PsxTextures.steel_plate()
		"sewer_floor":
			return PsxTextures.sewer_floor()
		"grating":
			return PsxTextures.grating()
		"roof_paving":
			return PsxTextures.roof_paving()
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
	return tuning.lane_width if _theme(id)["ground"] in ["office_floor", "security_floor", "canteen_floor", "warehouse_floor", "lobby_floor", "exit_floor", "helipad_slab", "grating", "roof_paving", "service_floor", "steel_plate", "sewer_floor", "gravel"] else 4.0


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
		"exit_granite":
			return PsxTextures.exit_granite()
		"service_wall":
			return PsxTextures.service_wall()
		"boiler_wall":
			return PsxTextures.boiler_wall()
		"sewer_wall":
			return PsxTextures.sewer_wall()
		"drain_wall":
			return PsxTextures.drain_wall()
		"exit_ceiling":
			return PsxTextures.exit_ceiling()
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
		var lift := chopper.create_tween()
		lift.tween_property(chopper, "position:y", xf.origin.y + 2.5, _clock.gone_at - _clock.elapsed)
		_lift_tweens.append(lift)
	_build_chopper_model(chopper)


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
## warps badly across big triangles. The rows are counted with a hair of slack: a 56 m ceiling
## strip measured as 56.000004 m gets the same 28 rows as the 56 m wall beside it, so their
## vertices meet along the corner (rows that don't line up open dotted cracks there under the
## PS1 vertex snap: the user's gaps).
func _plane(parent: Node3D, size: Vector2, pos: Vector3, tex: Texture2D, uv_scale: Vector2,
		orientation: PlaneMesh.Orientation = PlaneMesh.FACE_Y) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.orientation = orientation
	mesh.size = size
	mesh.subdivide_width = maxi(0, ceili(size.x / 2.0 - 0.01) - 1)
	mesh.subdivide_depth = maxi(0, ceili(size.y / 2.0 - 0.01) - 1)
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
			# A stairwell you didn't take (or its locked door), gone: wall up the hole it left in your
			# road's wall (it stood open on the outside: the user's gaps). The wall over it was built
			# with the rest, hidden, and is just shown: rebuilding the whole wall here, mid-run, cost
			# up to 10 ms (the LOADING DOCK's), a stall on a phone. Like the hole it fills, it's left
			# out of line of sight.
			var plug = r.get("plug")  # (untyped: it may have gone with its road)
			if is_instance_valid(plug):
				(plug as Node3D).visible = true
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
		if o["done"] or absf(o["at"] - d) > o["depth"] / 2.0 + RouteGraph.HIT_REACH:
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
			_update_security(delta, c, d, alert)
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
	_hud.show_cover_hint(_player.in_cover, _player.standoff)

	_fire_cooldown -= delta
	_hud.set_firing(_fire_held)
	_player.aiming = _fire_held  # CROSS raises his pistol
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
## `c`: his entry in _combatants.
func _update_security(delta: float, c: Dictionary, d: float, alert: int) -> void:
	var sec: SecurityTrooper = c["node"]
	var road: float = c["seg"]["road"]  # (his: the one the area he stood in is on)
	var walls: Array = []
	var lows: Array = []
	var highs: Array = []
	var seg := _runner_segment(sec.at, road)
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
	sec.update(delta, tuning, alert, d, walls, lows, highs, c["place"])
	if sec.state == SecurityTrooper.State.ALARM and not sec.panel_built and not _runner_segment(sec.at, road).is_empty():
		_build_runner_alarm(sec, road, false)  # his stretch is built now: the panel his hand's on
	if sec.is_running() and sec.alarm_at - sec.at > SecurityTrooper.TO_WALL:
		# Through the zone doors; not on the last stretch, where he cuts across to the wall his alarm's
		# on (it's short of the next door: he'd otherwise be pulled into the middle and stop ~2 m from
		# the panel, slamming nothing).
		sec.x = move_toward(sec.x, _through_doors(sec.at, sec.x), 7.0 * delta)
	if sec.is_running() and sec.state == SecurityTrooper.State.RUN and GameState.run_active:
		_hud.show_runner(sec.progress())  # (not once the run's over: the bar stays gone)
	if sec.is_alive() and sec.visible and absf(sec.at - d) < 0.6 \
			and absf(sec.x - _player.track_x) <= tuning.lane_width * 0.5 + 0.15:
		sec.knock_down()
	sec.push_at = null
	if not _gates.is_empty():
		_runner_gates(sec, road, d)


## The zone doors the alarm runner goes through (user: "when the alert guard is running, the big
## doors should open and close for him, so he doesn't just faze through them"). Each one on his
## way opens as he comes (a shove: its leaves swing on away from him; a shutter rolls up), and is
## shut again behind him before you can get there (you burst through it as ever: _gate_yours): the
## leaves swing shut once he's through and clear of them; a shutter drops as soon as he's under
## it, over his head (it starts rolling up for you SHUTTER_OPEN_AHEAD out, which can be as little
## as 0.3 s after he's at it: see SecurityTrooper's DOOR_ constants). It stays open while he's in
## its way: shot down in the doorway (or under a shutter as it drops), he's not shut in it. A door
## further ahead of you than GATE_VIEW, off in the fog, stays shut as he goes through: nobody can
## see it. `road`: his (_runner_segment).
## Line of sight: each leaf's (or the shutter's) sight box goes with it, as when you burst it
## open: while it's open for him, you can see and shoot him through the doorway, as you see him.
func _runner_gates(sec: SecurityTrooper, road: float, d: float) -> void:
	for g in _gates:
		var state: int = g["state"]
		if state == Gate.SHUT:
			if sec.state != SecurityTrooper.State.RUN or not sec.visible or float(g["at"]) - d > GATE_VIEW:
				continue
			var ahead := SecurityTrooper.SHUTTER_AHEAD if g["shutter"] != null else SecurityTrooper.DOOR_AHEAD
			if not SecurityTrooper.opens_door(sec.at, sec.alarm_at, g["at"], ahead):
				continue
			var on := _runner_segment(g["at"], road)
			if on.is_empty() or on["node"] != g["owner"]:
				continue  # (not on the road he's on)
			_gate_open(g, sec)
		elif state == Gate.OPEN and (not is_instance_valid(g["by"]) or g["by"] == sec):
			var shutter: bool = g["shutter"] != null
			if sec.is_running() and not shutter and sec.at < float(g["at"]) - 0.4:
				sec.push_at = _runner_point(g["at"], sec.x + 0.25, 1.25, road)  # (his hand out onto it as it goes)
			var in_way := SecurityTrooper.in_door_way(sec.at, sec.x, not sec.is_alive(), g["at"], g["sweep"], g["half_w"])
			if shutter and sec.is_running() and in_way:
				_gate_shut(g)  # he's under it: it drops behind him
			elif (sec.at > float(g["at"]) or not sec.is_running()) and not in_way:
				# Once he's through it (or stopped: down, or at his alarm), it shuts, unless he's in its way.
				_gate_shut(g)
		elif state == Gate.CLOSING and g["by"] == sec and not sec.is_running() \
				and SecurityTrooper.in_door_way(sec.at, sec.x, not sec.is_alive(), g["at"], g["sweep"], g["half_w"]):
			# Shot down under a shutter as it drops behind him: it stops where it is, over him, and
			# stands open as it would for him lying in the doorway.
			_gate_stop(g)
			g["state"] = Gate.OPEN


## He shoves it open: the leaves swing on away from him (to about square to the wall; no tip off
## their hinges, as your bash gives them), or the shutter rolls up. A soft push and a creak (bars:
## a rattle), at the door, quieter than your crash.
func _gate_open(g: Dictionary, sec: SecurityTrooper) -> void:
	_gate_stop(g)
	g["state"] = Gate.OPEN
	g["by"] = sec
	var t := (g["node"] as Node3D).create_tween().set_parallel(true)
	var sh: Variant = g["shutter"]
	if sh != null:
		t.tween_property(sh["node"], "position:y", float(sh["shut_y"]) + GATE_H - 0.05, SecurityTrooper.SHUTTER_UP_TIME) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	else:
		for leaf: Dictionary in g["leaves"]:
			t.tween_property(leaf["node"], "rotation:y", (leaf["shut"] as Vector3).y + GATE_PUSH * float(leaf["swing"]),
					SecurityTrooper.DOOR_PUSH_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	g["tween"] = t
	_audio.play_at("gate_push" if g["bars"] or sh != null else "door_push", _gate_point(g), -6.0, 0.08)


## Behind him, it swings shut (the shutter drops back down), and thuds home (bars: a clank).
func _gate_shut(g: Dictionary) -> void:
	_gate_stop(g)
	g["state"] = Gate.CLOSING
	var t := (g["node"] as Node3D).create_tween().set_parallel(true)
	var sh: Variant = g["shutter"]
	if sh != null:
		t.tween_property(sh["node"], "position:y", float(sh["shut_y"]), SecurityTrooper.SHUTTER_DOWN_TIME) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)  # (slow off the top, over his head, then a slam)
	else:
		for leaf: Dictionary in g["leaves"]:
			t.tween_property(leaf["node"], "rotation:y", (leaf["shut"] as Vector3).y, SecurityTrooper.DOOR_SHUT_TIME) \
					.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)  # (a door closer: faster as it goes)
	t.chain().tween_callback(func() -> void:
		g["state"] = Gate.SHUT
		g["tween"] = null
		if GameState.run_active:
			_audio.play_at("gate_shut" if g["bars"] or g["shutter"] != null else "door_shut", _gate_point(g), -4.0, 0.08))
	g["tween"] = t


## Whatever it was doing for him, it stops where it is.
func _gate_stop(g: Dictionary) -> void:
	var t: Variant = g["tween"]
	if t != null and (t as Tween).is_valid():
		(t as Tween).kill()
	g["tween"] = null


## You're at a zone door (each of its leaves asks): it's yours now. Whatever it was doing for the
## alarm runner stops where it is, and it bursts open from there to where a shut one goes. True if
## he'd left it more open than shut: you run on through it (no crash, no jolt).
func _gate_yours(g: Dictionary) -> bool:
	if g["state"] != Gate.BURST:
		g["was"] = g["state"]
		g["quiet"] = g["state"] != Gate.SHUT and _gate_open_part(g) > 0.5
		_gate_stop(g)
		g["state"] = Gate.BURST
		for i in _gates.size():
			if is_same(_gates[i], g):
				_gates.remove_at(i)
				break
	return g["quiet"]


## How far open it is: 0 shut, 1 as far as he opens it.
func _gate_open_part(g: Dictionary) -> float:
	var sh: Variant = g["shutter"]
	if sh != null:
		return ((sh["node"] as Node3D).position.y - float(sh["shut_y"])) / (GATE_H - 0.05)
	var leaf: Dictionary = g["leaves"][0]
	return absf(angle_difference((leaf["shut"] as Vector3).y, (leaf["node"] as Node3D).rotation.y)) / GATE_PUSH


## A road's zone doors going with it: not taken (its scenery stays a while: one standing open for
## him swings shut, unless he's lying in it), or thrown away (`shut` false: whatever they were
## doing just stops).
func _drop_gates(node: Node3D, shut: bool = true) -> void:
	for g in _gates:
		if g["owner"] == node:
			if not shut:
				_gate_stop(g)  # (its swing would otherwise hold on to it after the door's gone)
			elif g["state"] == Gate.OPEN:
				var by: Variant = g["by"]
				if not is_instance_valid(by) or not SecurityTrooper.in_door_way(by.at, by.x, not by.is_alive(),
						g["at"], g["sweep"], g["half_w"]):
					_gate_shut(g)
	_gates = _gates.filter(func(g: Dictionary) -> bool: return g["owner"] != node)


## The middle of a zone door's doorway, a little over head height (where its sounds come from).
func _gate_point(g: Dictionary) -> Vector3:
	return (g["node"] as Node3D).global_transform * (g["frame"] as Transform3D) * Vector3(0, 1.5, 0)


## Where the alarm runner is in the world, on his road (`road`: see _runner_segment). null where
## that isn't built in front of you (he's hidden there).
func _runner_point(at: float, x: float, y: float, road: float) -> Variant:
	var seg := _runner_segment(at, road)
	if seg.is_empty():
		return null
	return seg["node"].global_transform * _frame_at(seg, at - seg["start"]) * Vector3(x, y, 0)


## The stretch of route the alarm runner is on, `at` along it: on the road you're on, or on the
## straight-on branch just ahead of it (he keeps straight on), but only while that's his own road
## (`road`: where the road of the area he stood in starts, see _make_segment). Up or down stairs off
## it ahead of him, you're on another floor, and he isn't on yours (going by route distance alone
## put him there: running along the ROOFTOPS in front of you, and raising the alarm from them).
## The road on past those stairs stands in front of you until the stairwell's camera cuts in, and
## he's on it till then (_road_past). Empty (NOWHERE) where he's not on anything built in front of
## you: he's hidden, and runs on unseen.
func _runner_segment(at: float, road: float) -> Dictionary:
	if _segments.is_empty() or at < _segments[0]["start"]:
		return NOWHERE
	if at <= _current["end"]:
		var seg := _segment_at(at)
		if seg["road"] == road:
			return seg
	else:
		var branches: Dictionary = _current["branches"]
		for k in branches:
			var b: Dictionary = branches[k]
			if String(k).begins_with("straight:") and at <= b["end"]:
				if b["road"] == road:
					return b
				break
	if not _road_past.is_empty() and _road_past["road"] == road and at >= _road_past["start"] and at <= _road_past["end"]:
		return _road_past
	return NOWHERE


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


## The boss at the chopper: the standoff starts as you come within his range (the run stops; you
## step between lanes and fire); then, every frame, his minigun's cycle, its hits on you, and his
## health on the HUD. When he's down you run on to the chopper.
func _update_boss(delta: float) -> void:
	var d := _player.distance_run()
	for b in _bosses:
		var boss: Boss = b["node"]
		if not is_instance_valid(boss) or not b["seg"].get("promoted", false):
			continue
		if _boss_fight == null and boss.state == Boss.State.WAITING and d >= boss.at - tuning.boss_standoff:
			_start_boss_fight(boss)
		if boss != _boss_fight or not boss.is_alive():
			continue
		if boss.update(delta, GameState.alert_level, _player.distance_run(), _player.track_x, _route_point):
			RunLog.record_event("boss_hit", {"node": _runner.current})
			_damage_player("minigun")
			if not GameState.run_active:
				return
		if boss.is_alive():
			_hud.show_boss(float(boss.health) / float(boss.max_health))


func _start_boss_fight(boss: Boss) -> void:
	_boss_fight = boss
	_player.enter_standoff(boss.at - tuning.boss_standoff)
	if _squad_on:
		_squad_fall_back()  # (they hold back: it's his fight now)
	_hud.show_runner(-1.0)
	_hud.show_boss(1.0)
	RunLog.record_event("boss_fight", {"node": _runner.current})
	boss.begin(GameState.alert_level)


## The boss's KO replay (user: Tekken-style; KoReplay): the moment he's killed the game cuts close
## to him and slows right down; his death plays live, then twice more from new angles, under cinema
## bars, REPLAY blinking over the replays. The chopper's clock stops (you can't move), FIRE doesn't
## shoot, nothing can hurt you; a new tap, swipe or FIRE press skips the rest. Then a hard cut back to the camera behind
## you, and you run on to the chopper.
func _ko_begin(boss: Boss) -> void:
	_ko_shots = KoReplay.shots(tuning)
	_ko = 0
	_ko_real = 0.0
	_ko_skipped = false
	_ko_skip_asked = false
	set_fire_held(false)
	_ko_clock_was = _clock.running
	_clock.running = false
	_hold_lift_off(true)
	_ko_fov = _camera.fov
	_hud.set_playing(false)
	_hud.show_cover_hint(false)
	_hud.set_letterbox(true, 0.15)
	_ko_shot_start(boss)


func _ko_shot_start(boss: Boss) -> void:
	var shot: Dictionary = _ko_shots[_ko]
	_ko_shot_real = 0.0
	Engine.time_scale = float(shot["scale"])
	if _ko > 0:
		boss.replay_death(float(shot["from"]))
	_camera.fov = float(shot["fov"])
	_hud.show_replay(shot["replay"])
	_audio.play("slowmo", -2.0, 0.0)
	RunLog.record_event("ko_shot", {"shot": _ko})


## Every physics frame of the KO replay: on to the next shot when this one has shown its part of
## his death (or, failing that, has run its length in real time and a second more).
func _update_ko(delta: float) -> void:
	var boss := _boss_fight
	if boss == null or not is_instance_valid(boss):
		_ko_end()
		return
	var real := delta / maxf(Engine.time_scale, 0.01)
	_ko_real += real
	_ko_shot_real += real
	if _ko_skip_asked and boss.death_ready():
		_ko_skip()
		return
	var shot: Dictionary = _ko_shots[_ko]
	if boss.death_t >= float(shot["to"]) or _ko_shot_real > KoReplay.length(shot) + 1.0:
		RunLog.record_event("ko_shot_end", {"shot": _ko, "timed_out": boss.death_t < float(shot["to"])})
		_ko += 1
		if _ko >= _ko_shots.size():
			_ko_end()
		else:
			_ko_shot_start(boss)


## A tap (or swipe, or FIRE pressed) during the KO replay: after its first moment, straight to the
## end (he lies in his blood, the gun by him).
func _ko_skip() -> void:
	if _ko < 0 or _ko_real < tuning.boss_ko_skip_after:
		return
	if _boss_fight != null and is_instance_valid(_boss_fight) and not _boss_fight.death_ready():
		_ko_skip_asked = true  # (his ragdoll's still being worked out: skip the moment it's done)
		return
	_ko_skipped = true
	if _boss_fight != null and is_instance_valid(_boss_fight):
		_boss_fight.finish_death()
	_ko_end()


## The KO replay's over (or the run is): normal time, a hard cut back to the camera behind you, the
## HUD and the chopper's clock back; you run on.
func _ko_end() -> void:
	_ko = -1
	Engine.time_scale = 1.0
	_cam_snap = true
	_camera.fov = _ko_fov
	_shake = 0.0
	_hud.show_replay(false)
	_hud.set_letterbox(false, 0.15)
	_clock.running = _ko_clock_was
	_hold_lift_off(false)
	RunLog.record_event("ko_end", {"skipped": _ko_skipped})
	if GameState.run_active:
		_hud.set_playing(true)
		_player.end_standoff()  # the way to the chopper is clear


## The boss's death's sounds, heavy, each time it's shown (live and in the replays).
func _on_boss_death_beat(beat: String, boss: Boss) -> void:
	if not is_instance_valid(boss):
		return
	match beat:
		"hit":
			_audio.play_at("hit", boss.to_global(Vector3(0.0, 1.7, 0.0)), 2.0, 0.05)
		"let_go":
			_audio.play_at("grunt_%d" % (randi() % 3), boss.to_global(Vector3(0.0, 1.9, 0.0)), 0.0, 0.03)
		"gun_down":
			_audio.play_at("gun_drop", boss.to_global(Vector3(0.3, 0.2, -0.6)), 0.0, 0.04)
		"body_down":
			_audio.play_at("fall", boss.to_global(Vector3(0.0, 0.2, 2.0)), 2.0, 0.04)
			_audio.play_at("player_hit", boss.to_global(Vector3(0.0, 0.2, 2.0)), -2.0, 0.04)


## While the clock's stopped, a chopper already lifting off waits too (only its climb: its rotors
## and their sound go on).
func _hold_lift_off(on: bool) -> void:
	_lift_tweens = _lift_tweens.filter(func(t: Tween) -> bool: return t.is_valid())
	for t in _lift_tweens:
		if on:
			t.pause()
		else:
			t.play()


## The roof snipers: each starts on you when you reach his spot (if the alert's CAUTION or up),
## follows you, locks on and fires once. Only on the area you're on (one on a branch ahead waits).
func _update_snipers(delta: float) -> void:
	var d := _player.distance_run()
	for s in _snipers:
		var sn: Sniper = s["node"]
		if not is_instance_valid(sn) or not s["seg"].get("promoted", false):
			continue
		var shot := sn.update(delta, GameState.alert_level, d, _player.track_x, _player.in_cover, _route_point)
		if shot == Sniper.Shot.HIT:
			RunLog.record_event("sniper_hit", {"node": _runner.current})
			_damage_player("sniper")
			if not GameState.run_active:
				return
		elif shot == Sniper.Shot.MISSED:
			RunLog.record_event("sniper_dodged", {"node": _runner.current})
	_snipers = _snipers.filter(func(s: Dictionary) -> bool: return is_instance_valid(s["node"]) and s["node"].at > d - 60.0)


## A sniper's laser has come on, following you.
func _on_sniper_tracking() -> void:
	RunLog.record_event("sniper", {"node": _runner.current})
	_hud.show_chopper_message("SNIPER!", Color("ffb347"), 1.6, false)
	_audio.play("sniper_aim", -4.0, 0.0)


## Locked on: the beep (change lane now).
func _on_sniper_locked(_sn: Sniper) -> void:
	_audio.play("sniper_lock", -2.0, 0.0)


## He's fired: the crack from his nest, far off (a hit is the usual hit, from _update_snipers;
## a miss sparks off the roof where you were).
func _on_sniper_fired(hit: bool, where: Vector3, sn: Sniper) -> void:
	_audio.play("sniper_shot", -1.0, 0.04)
	if not hit:
		_audio.play_at("zap", where, -6.0, 0.1)
		_sparks(where)


## A shot glancing off the roof: a few sparks flying out and fading.
func _sparks(where: Vector3) -> void:
	for i in 6:
		var m := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.07, 0.07, 0.07)
		m.mesh = b
		m.material_override = PsxMaterials.glow(Color("ffd060"))
		m.top_level = true
		_world.add_child(m)
		m.global_position = where
		var a := TAU * i / 6.0 + 0.4
		var to := where + Vector3(cos(a) * 0.6, 0.3 + 0.25 * (i % 3), sin(a) * 0.6)
		var tw := m.create_tween()
		tw.tween_property(m, "global_position", to, 0.22).set_ease(Tween.EASE_OUT)
		tw.tween_callback(m.queue_free)


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
## one squeezes in toward the middle. And a locked stairs door stands across an outer lane: coming
## up to it, they keep out of that lane until they're past it, as you do (_bar_lane).
func _through_doors(at: float, x: float) -> float:
	var reach := (MARKER_LANES - 1) / 2 * tuning.lane_width
	for m in _markers:
		if at >= m["at"] - MARKER_FUNNEL and at <= m["at"] + 0.5:
			return clampf(x, -reach, reach)
	var barred := _barred_lane(at)
	if barred == 0:
		return maxf(x, _player.lane_x(1))
	if barred > 0:
		return minf(x, _player.lane_x(barred - 1))
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
		g.grab(behind * Vector3(0, 1.2, 0))  # at your back
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
		_rear_cam.cull_mask = 0xFFFFF & ~LANDING_LAYER  # (only the play camera just out of a stairwell draws that)
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
		_player.die(_free_ahead())  # (user: the game stops, his death plays, then the end screen)
		_end(&"killed")


## The ending has played out (killed: he lies still): the end-of-mission conversation for it (user:
## "Before the debrief"; Briefing.conversation()), under the cinema bars with the area's ambience
## ducked, then the debrief. Every run has it, Retry's too; SKIP or tapping through it goes straight
## to the debrief. An ending without a conversation (dead_end: no route can reach it) opens the
## debrief at once.
func _open_end(reason: StringName, stats: Dictionary) -> void:
	var talk := Briefing.conversation(_briefing, String(reason))
	if not Briefing.lines_of(talk).is_empty():
		_hud.set_letterbox(true, 0.3)
		_audio.duck_ambience(true)
	_frontend.show_end(reason, stats, talk)


## The debrief is up (after the conversation, or at once): the cinema bars go, the ambience comes
## back, and the end's sting plays now (not under the conversation): the extraction jingle, or the
## game-over sting.
func _on_debrief_opened(reason: StringName) -> void:
	_hud.set_letterbox(false, 0.15)
	_audio.duck_ambience(false)
	_audio.play("jingle" if reason == GameState.END_EXTRACTED else "gameover", -2.0, 0.0, "UI")


## How far the way ahead of him is clear (m), for his fall: to the nearest thing he'd fall into
## (an obstacle or cover in his lane, a pipe unless he's sliding under it, a door not yet open, an
## enemy just ahead).
func _free_ahead() -> float:
	_place_player()  # (where he is this frame: the level moves him after its own step)
	var d := _player.distance_run()
	var free := 99.0
	for o in _obstacles:
		if (o["pass"] == "slide" and _player.is_sliding()) or absf(float(o["x"]) - _player.track_x) > tuning.lane_width * 0.5 + 0.3:
			continue  # (he's under it, or it's not in his way)
		var near: float = float(o["at"]) - float(o["depth"]) / 2.0 - d
		if near > -0.3:
			free = minf(free, maxf(near, 0.0))
	for door in _doors:
		# Shut, it's a wall across the way (the run's over: it won't burst open now).
		if not door.get("done", false) and door["seg"].get("promoted", false):
			var to_door: float = float(door["at"]) - d
			if to_door > -0.3 and to_door < 6.0:
				free = minf(free, maxf(to_door, 0.0))
	for c in _combatants:
		var n = c["node"]
		if is_instance_valid(n) and n is Node3D and (n as Node3D).is_visible_in_tree():
			var rel := _player.to_local((n as Node3D).global_position)
			if rel.z < 0.3 and rel.z > -4.0 and absf(rel.x) < 0.9:
				free = minf(free, maxf(-rel.z - 0.3, 0.0))  # (to his near side)
	return free


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
	if _boss_fight != null and is_instance_valid(_boss_fight) and _boss_fight.is_targetable(alert):
		candidates.append(_boss_fight)  # (out in the open in front of the chopper)
	var origin := _player.global_position + Vector3(0, 1.2, 0)
	var forward := -_player.global_transform.basis.z
	if _tapped != null and (not is_instance_valid(_tapped) or not _tapped.call("is_targetable", alert)):
		_tapped = null
	return Targeting.pick(candidates, origin, forward, tuning, _tapped)


## Where on a target you aim: a trooper's chest, a dog's body, an alarm box's face.
func _aim_height(n: Node3D) -> float:
	if n is Boss:
		return Boss.CHEST
	if n is SecurityTrooper:
		return RifleTrooper.CHEST  # the scout's chest, as the guard's
	if n is RifleTrooper:
		return RifleTrooper.CHEST
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
	_player.fire_recoil()
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
	var muzzle := _player.muzzle_position()  # the tracer leaves his pistol
	_shot_tracer.global_transform = Transform3D(Basis.looking_at(to - muzzle) * Basis.from_scale(Vector3(1, 1, muzzle.distance_to(to))), (muzzle + to) / 2.0)
	_shot_tracer.visible = true
	get_tree().create_timer(0.05).timeout.connect(func() -> void: _shot_tracer.visible = false)


func _end(reason: StringName) -> void:
	GameState.end_run(reason, _runner.current, _player.distance_run() - _runner.segment_start)


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
	if _ko >= 0:
		_ko_end()
	Engine.time_scale = 1.0
	_clock.stop()
	_fire_held = false
	_player.aiming = false  # he lowers the pistol, however the run ended
	for s in _snipers:  # their lasers go out
		if is_instance_valid(s["node"]):
			s["node"].stand_down()
	for c in _combatants:  # the troopers lower their rifles, the dogs and the runner pull up
		if is_instance_valid(c["node"]) and (c["node"] is RifleTrooper or c["node"] is RusherDog or c["node"] is SecurityTrooper):
			c["node"].stand_down()
	if _boss_fight != null and is_instance_valid(_boss_fight):
		_boss_fight.stand_down()  # his gun spins down
	_hud.show_boss(-1.0)
	_hud.set_firing(false)
	_hud.show_cover_hint(false)
	_hud.show_end(reason, RunLog.route_summary())
	# A moment later (so you see what happened), the end-of-mission conversation, then the end
	# screen: the result, the debrief and the route taken (the LOCKED post-run route record).
	# The debrief: the route map (the areas and where in the last one it ended) and the tally.
	var stats := RunLog.tally()
	stats.merge({"time": _clock.elapsed, "alert": GameState.alert_level, "route": RunLog.route_summary().split(" > "),
			"spare": _clock.gone_at - _clock.elapsed if reason == GameState.END_EXTRACTED else -1.0,
			"graph": _graph, "visited": RunLog.visited.duplicate(), "discovered": RunLog.discovered.duplicate(),
			"end_into": _player.distance_run() - _runner.segment_start,
			"end_ramp": float(_current.get("ramp_len", 0.0)),
			"levels": RouteMap.levels_text(_graph, RunLog.visited)})
	# The auto-save (user: "auto save itself after the player finishes a run"), whatever the ending:
	# Progress writes the save now (the route map's finds were written as the run ended: RunLog.finish;
	# the settings, as each one changed). Got out: the unlocks (user: mission N+1 on this setting and
	# every easier one, and this mission's next setting up) and his best time here (the run time of
	# his fastest extraction). The debrief says what opened, and NEW BEST.
	var n := Progress.mission_number(StringName(_graph.mission().get("mission", "")))
	stats["mission"] = n
	stats["setting"] = _graph.setting
	var rec: Dictionary = Progress.record_run(n, _graph.setting, reason, _clock.elapsed)
	stats["unlocked"] = rec["unlocked"]
	stats["new_best"] = rec["new_best"]
	stats["was_best"] = rec["was"]
	if reason == GameState.END_KILLED and _player.dying:
		# Killed: his death plays out first (user), and he lies still a moment.
		_player.died.connect(func() -> void:
			get_tree().create_timer(tuning.death_hold, true, false, true).timeout.connect(func() -> void: _open_end(reason, stats)),
			CONNECT_ONE_SHOT)
	else:
		# (Captured: he's down with his hands up, the guards round him; extracted: at the chopper,
		# the boss's KO replay long over; the chopper gone.)
		get_tree().create_timer(1.1).timeout.connect(func() -> void: _open_end(reason, stats))
	_audio.fade_loops(2.5)
	_audio.stop_music()  # (the end's sting plays as the debrief opens: _on_debrief_opened)


func _on_swipe(dir: Vector2i) -> void:
	if _menu_open or _frontend.is_open():
		return  # the menus have their own buttons
	if _ko >= 0:
		_ko_skip()
		return
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
	if _ko >= 0:
		_ko_skip()
		return
	if not _started:
		start_run()  # a tap during the opening pan skips it
	elif not GameState.run_active:
		return  # the end screen has its own buttons
	elif tuning.targeting_mode != Tuning.TargetingMode.AUTO_PRIORITY:
		_tapped = _enemy_near_screen(pos)


## Tap-to-target (proposal under test): the live trooper drawn nearest the tap, if close enough; or
## the boss, tapped anywhere on him.
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
	# The boss (big, and alone at the chopper): nearest his body, feet to head.
	var boss := _boss_fight
	if boss != null and is_instance_valid(boss) and boss.is_targetable(GameState.alert_level):
		var feet := boss.global_position + Vector3.UP * 0.3
		var head := boss.global_position + Vector3.UP * (Boss.CHEST + 0.5)
		if not _camera.is_position_behind(feet) and not _camera.is_position_behind(head):
			var a := _camera.unproject_position(feet)
			var b := _camera.unproject_position(head)
			if Geometry2D.get_closest_point_to_segment(pos, a, b).distance_to(pos) < best_d:
				best = boss
	return best


func _on_fire() -> void:
	if _menu_open or _frontend.is_open():
		return
	if _ko >= 0:
		_ko_skip()  # (a new press: the FIRE held as he died doesn't count)
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

## The camera for this frame (_place_camera), and the cutout with it (Cutout): what stands between
## the camera and him dissolves, on the shots that take it. The hole goes with him: up with his
## jump, and down into a slide (eased, as he drops into it).
func _update_camera(delta: float) -> void:
	var shot := _place_camera(delta)
	_cut_slide = Cutout.slide_toward(_cut_slide, _player.is_sliding(), delta)
	Cutout.apply(_camera.global_position, _player.global_position, Cutout.on_for(shot),
			Cutout.lift(_player.jump_y, _cut_slide))


## Behind and above the player, in the frame of the leg they're on, eased so turns and
## climbs swing smoothly rather than snapping. Normally it sits a little toward the middle of the
## road; near a wall (walls are solid and lane-aligned) it moves right behind the player, so it
## never ends up inside one. Says which shot it set up (the cutout is on for some of them).
func _place_camera(delta: float) -> Cutout.Shot:
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
	# Down a ladder (off the ROOF EDGE onto the helipad): the camera stays up over the roof behind
	# you until it's out past the roof's end (7 m back: it sits 5.5 m behind you, and trails a
	# little more), rising a little as you go down so it sees you over the roof's edge, then comes
	# down after you. Following you down the ladder, it sank into the roof it was still over: the
	# paving smeared across the screen, the DEAD END wall hiding you, then the roof's underside.
	if RouteGraph.via_of(seg["edge"]) == "ladder" and float(seg["dy"]) < 0.0:
		eye_local.y += (_height(seg, into - LADDER_DOWN_CAM_BACK) - _height(seg, into)) * (1.0 + LADDER_DOWN_CAM_RISE)
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
		return Cutout.Shot.CCTV
	var snap := _was_cctv or _cam_snap
	_was_cctv = false
	_cam_snap = false
	# Just out of a stairwell, the play camera behind you is still inside it: leave it out for now,
	# and draw the landing round the camera instead (the area's floor, walls and ceiling, or its
	# roof, back over the end of the flight), or it looks out into the sky and the void (the user's
	# stairs and gaps). Climbing a ladder out of a tunnel, once the camera is up past the deck,
	# leave out the wall over the tunnel's end: it would stand across the hatch in front of it.
	# It's left out until the camera itself is out past the stairwell (_cam_over_flight): trailing
	# behind you as you run, it's still back behind the end wall at the bottom of a flight down for
	# a few frames after you're 6.5 m out, and that wall would fill the screen from behind.
	var ramp_len: float = seg["ramp_len"]
	var just_out: bool = _is_stairs(seg) and into > ramp_len - 0.4 \
			and (into < ramp_len + 6.5 or (into < ramp_len + 10.0 and _cam_over_flight(seg)))
	var climbing: bool = RouteGraph.via_of(seg["edge"]) == "ladder" and float(seg["dy"]) > 0.0 \
			and _height(seg, into) + 3.3 > float(seg["dy"]) and into < seg["ramp_len"] + 6.5
	var mask := 0xFFFFF
	if just_out:
		mask &= ~STAIRWELL_LAYER
	if climbing:
		mask &= ~CLIMB_LAYER
	_camera.cull_mask = mask
	var landing: Node3D = seg.get("landing") if just_out else null
	if landing != _landing_shown:
		if is_instance_valid(_landing_shown):
			_landing_shown.visible = false
		if landing:
			landing.visible = true
		_landing_shown = landing
	if _menu_open:
		# Behind the main menu: in front of you, swaying slowly from side to side.
		_menu_t += delta
		var at := IntroCamera.menu(IntroCamera.sway(_menu_t), x, get_viewport().get_visible_rect().size.y)
		eye_local = at[0]
		look_local = at[1]
		_camera.fov = at[2]  # (wider on a phone taller than the menu's layout: him the same size)
		_camera.global_transform = Transform3D(Basis.IDENTITY, f * eye_local).looking_at(f * look_local, Vector3.UP)
		_cam_base = _camera.global_transform
		return Cutout.Shot.MENU
	if _ko >= 0 and _boss_fight != null and is_instance_valid(_boss_fight):
		# The boss's KO replay: this shot's camera (cut to at each shot).
		var shot: Dictionary = _ko_shots[_ko]
		var u := KoReplay.progress(shot, _boss_fight.death_t)
		_camera.global_transform = _boss_fight.global_transform * KoReplay.camera(shot, u, _boss_fight.body_point())
		_cam_base = _camera.global_transform
		return Cutout.Shot.KO
	if _intro_left > 0.0 and not _started:
		# Opening pan: from in front of the player (looking back at them) round the side to the
		# play camera behind them, where it ends exactly (easing out of the menu's camera first).
		var e := smoothstep(0.0, 1.0, 1.0 - _intro_left / tuning.intro_pan_time)
		var at := IntroCamera.pan(e, x, _pan_sway, tuning.intro_from_menu, look_local, get_viewport().get_visible_rect().size.y)
		eye_local = at[0]
		look_local = at[1]
		_camera.fov = at[2]
		_camera.global_transform = Transform3D(Basis.IDENTITY, f * eye_local).looking_at(f * look_local, Vector3.UP)
		_cam_base = _camera.global_transform
		return Cutout.Shot.PAN
	var eye := f * eye_local
	var look := f * look_local
	var target := Transform3D(Basis.IDENTITY, eye).looking_at(look, Vector3.UP)
	# The smoothed camera, kept apart from the shake so the smoothing can't swallow it.
	_cam_base = target if snap else _cam_base.interpolate_with(target, clampf(delta * 8.0, 0.0, 1.0))
	_camera.global_transform = _cam_base
	# The play camera's view (a tap that skipped the pan as the menu's wider view eased out on a tall
	# phone: eased back with the rest of the camera).
	if _camera.fov != IntroCamera.FOV:
		var to := lerpf(_camera.fov, IntroCamera.FOV, clampf(delta * 8.0, 0.0, 1.0))
		_camera.fov = IntroCamera.FOV if snap or absf(to - IntroCamera.FOV) < 0.01 else to
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
	# Just out of a stairwell, the stairwell left out of the picture shows him (no cutout there).
	return Cutout.Shot.JUST_OUT if just_out else Cutout.Shot.PLAY


## True while the play camera is still back over the flight at the start of `seg`, short of
## STAIRWELL_CLEAR past its end (its walls run on 0.1 m past it, and its end wall stands just short
## of it). Where the camera was last frame: it only moves on toward him from there.
func _cam_over_flight(seg: Dictionary) -> bool:
	var end: Transform3D = seg["node"].global_transform * _frame_at(seg, seg["ramp_len"])
	return (end.affine_inverse() * _cam_base.origin).z > -STAIRWELL_CLEAR
