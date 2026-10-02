class_name PsxTextures
extends RefCounted
## Placeholder PS1-style textures, generated in code so the prototype needs no art files.
## 64 px tiles in the MGS1 manner: bevelled panels and seams, blotchy grime that builds up at the
## bottom, rust and water streaks, rivets and grilles, worn military stencils, and a reduced
## palette per texture (like the PS1's colour tables). Nearest-filtered up close, with mipmaps so
## the detail doesn't sparkle far off. Real art replaces these later.
## Each texture is cached by key, and the noise uses a fixed seed so it looks the same every run.
## Rows run top to bottom (y = 0 is the top of a wall).

const SIZE := 64
const ROAD := Color("3a3a37")
## Levels per colour channel after generating (PS1 colour-table look).
const LEVELS := 28

static var _cache: Dictionary = {}

## A 3x5 pixel stencil font (rows top to bottom, 1 = paint).
const GLYPHS := {
	"0": ["111", "101", "101", "101", "111"], "1": ["010", "110", "010", "010", "111"],
	"2": ["111", "001", "111", "100", "111"], "3": ["111", "001", "111", "001", "111"],
	"4": ["101", "101", "111", "001", "001"], "5": ["111", "100", "111", "001", "111"],
	"6": ["111", "100", "111", "101", "111"], "7": ["111", "001", "001", "010", "010"],
	"8": ["111", "101", "111", "101", "111"], "9": ["111", "101", "111", "001", "111"],
	"A": ["010", "101", "111", "101", "101"], "B": ["110", "101", "110", "101", "110"],
	"C": ["011", "100", "100", "100", "011"], "D": ["110", "101", "101", "101", "110"],
	"E": ["111", "100", "110", "100", "111"], "F": ["111", "100", "110", "100", "100"],
	"G": ["011", "100", "101", "101", "011"], "H": ["101", "101", "111", "101", "101"],
	"I": ["111", "010", "010", "010", "111"], "K": ["101", "101", "110", "101", "101"],
	"L": ["100", "100", "100", "100", "111"], "M": ["101", "111", "111", "101", "101"],
	"N": ["110", "101", "101", "101", "101"], "O": ["111", "101", "101", "101", "111"],
	"P": ["110", "101", "110", "100", "100"], "R": ["110", "101", "110", "101", "101"],
	"S": ["011", "100", "010", "001", "110"], "T": ["111", "010", "010", "010", "010"],
	"U": ["101", "101", "101", "101", "111"], "V": ["101", "101", "101", "101", "010"],
	"W": ["101", "101", "111", "111", "101"], "X": ["101", "101", "010", "101", "101"],
	"Y": ["101", "101", "010", "010", "010"], "-": ["000", "000", "111", "000", "000"],
}


## One lane-width tile of road (4 m long): worn asphalt with cracks and oil stains, and a dashed
## lane line down its left edge.
static func asphalt() -> Texture2D:
	if _cache.has("asphalt"):
		return _cache["asphalt"]
	var img := _start("asphalt", ROAD, 0.05)
	_aggregate(img, "asphalt_stones", 260, 0.07)
	_blotches(img, "asphalt_oil", 3, 4, 8, Color("1e1e1c"), 0.35)
	_cracks(img, "asphalt_cracks", 3, 22, 0.6)
	var rng := _rng("asphalt_line")
	for y in range(0, 32):
		for x in range(0, 3):
			if rng.randf() > 0.12:  # worn paint
				_blend(img, x, y, Color("b8b49a"), 0.85)
	return _finish("asphalt", img)


## Concrete slabs (the helipad, kerbs, slabs): stained, with recessed joints.
static func concrete() -> Texture2D:
	if _cache.has("concrete"):
		return _cache["concrete"]
	var img := _start("concrete", Color("6a6a62"), 0.05)
	_aggregate(img, "concrete_stones", 140, 0.05)
	_blotches(img, "concrete_stains", 3, 5, 10, Color("4a4a44"), 0.3)
	_cracks(img, "concrete_cracks", 2, 14, 0.7)
	_groove_h(img, 0, 0, SIZE)
	_groove_v(img, 0, 0, SIZE)
	return _finish("concrete", img)


## Stairs: four concrete steps per tile, each with a worn light nosing and a dark riser, and
## the middle of each tread worn paler by feet.
static func stairs() -> Texture2D:
	if _cache.has("stairs"):
		return _cache["stairs"]
	var img := _start("stairs", Color("6e6e66"), 0.04)
	for step in 4:
		var y0 := step * 16
		for x in SIZE:
			var wear := 1.0 + 0.08 * (1.0 - absf(x - SIZE / 2.0) / (SIZE / 2.0))
			for y in range(y0 + 3, y0 + 12):
				_shade(img, x, y, wear)
			_put(img, x, y0, Color("b0b0a0"))
			_put(img, x, y0 + 1, Color("94948a"))
			_put(img, x, y0 + 2, Color("7c7c74"))
			for y in range(y0 + 12, y0 + 16):
				_shade(img, x, y, 0.55 - 0.05 * (y - y0 - 12))
	return _finish("stairs", img)


## Walls, one tile per 2 m x 2 m. pattern: "blocks", "brick", "corrugated" or "tile".
static func wall(pattern: String, color: Color) -> Texture2D:
	var key := "wall_%s_%s" % [pattern, color.to_html()]
	if _cache.has(key):
		return _cache[key]
	var img := _start(key, color, 0.045)
	match pattern:
		"blocks":
			_courses(img, key, 16, 32)
		"brick":
			_courses(img, key, 8, 16)
		"tile":
			_tiles(img, 16, 8, color.darkened(0.45))
		"corrugated":
			for x in SIZE:
				var k := 1.0 + 0.16 * sin(x * TAU / 6.0)
				for y in SIZE:
					_shade(img, x, y, k)
	_streaks(img, key + "_streaks", 5, color.darkened(0.6), 0.3)
	_grime_bottom(img, key, 38, 0.4)
	return _finish(key, img)


## The service tunnel's walls: old glazed tiles above a dark green band, grimy lower tiles, and
## water and rust running down from the joints.
static func tunnel_wall() -> Texture2D:
	if _cache.has("tunnel_wall"):
		return _cache["tunnel_wall"]
	var img := _start("tunnel_wall", Color("70847a"), 0.04)
	var grout := Color("39443e")
	_tiles(img, 16, 8, grout)
	for y in range(40, SIZE):
		for x in SIZE:
			_shade(img, x, y, 0.62)
	for x in SIZE:
		for y in range(38, 43):
			_put(img, x, y, Color("2d4636"))
		_shade(img, x, 38, 1.5)
		_shade(img, x, 42, 0.6)
	_streaks(img, "tunnel_wall_water", 7, Color("26302a"), 0.45)
	_streaks(img, "tunnel_wall_rust", 3, Color("6a3a1c"), 0.35)
	_blotches(img, "tunnel_wall_damp", 3, 4, 9, Color("2a3830"), 0.3)
	_grime_bottom(img, "tunnel_wall", 44, 0.55)
	return _finish("tunnel_wall", img)


## Inside a stairwell: painted blockwork, pale above and dark green-grey below a yellow line
## (the paint line runs parallel to the stairs, like a real stairwell), scuffed near the steps.
static func stairwell() -> Texture2D:
	if _cache.has("stairwell"):
		return _cache["stairwell"]
	var img := _start("stairwell", Color("8c9088"), 0.035)
	_courses(img, "stairwell", 16, 32)
	for y in range(40, SIZE):
		for x in SIZE:
			_put(img, x, y, img.get_pixel(x, y).lerp(Color("485650"), 0.75))
	for x in SIZE:
		_put(img, x, 38, Color("c9a227"))
		_put(img, x, 39, Color("a8861e"))
	_blotches(img, "stairwell_scuffs", 5, 1, 3, Color("2a302c"), 0.4, Rect2i(0, 52, SIZE, 12))
	_streaks(img, "stairwell_streaks", 3, Color("5a5e56"), 0.25)
	_grime_bottom(img, "stairwell", 46, 0.3)
	return _finish("stairwell", img)


## The service tunnel's ceiling: stained concrete between cast ribs, with a conduit and a
## cable tray running along it.
static func tunnel_ceiling() -> Texture2D:
	if _cache.has("tunnel_ceiling"):
		return _cache["tunnel_ceiling"]
	var img := _start("tunnel_ceiling", Color("4e524c"), 0.05)
	_aggregate(img, "tunnel_ceiling_stones", 160, 0.05)
	_blotches(img, "tunnel_ceiling_damp", 4, 4, 9, Color("2a302a"), 0.35)
	for x in SIZE:
		for y in range(0, 6):  # a rib across the tunnel
			_put(img, x, y, Color("5e625a"))
		_shade(img, x, 0, 1.3)
		_shade(img, x, 5, 0.55)
		_shade(img, x, 6, 0.7)
	for y in SIZE:
		for x in range(20, 23):  # conduit
			_put(img, x, y, Color("3a3e3a") if x != 20 else Color("6a6e68"))
		for x in range(40, 50):  # cable tray
			_put(img, x, y, Color("2c2e2c") if x in [40, 49] else Color("3c3a34").lightened(0.06 * ((y / 3) % 2)))
	_streaks(img, "tunnel_ceiling_rust", 3, Color("5a3a1c"), 0.3)
	return _finish("tunnel_ceiling", img)


## Jump barriers: worn yellow and black hazard stripes, chipped to bare metal, dirty edges.
static func hazard() -> Texture2D:
	if _cache.has("hazard"):
		return _cache["hazard"]
	var img := _start("hazard", Color.BLACK, 0.0)
	for y in SIZE:
		for x in SIZE:
			img.set_pixel(x, y, Color("d4aa2a") if ((x + y) / 11) % 2 == 0 else Color("1e1e1b"))
	_noise(img, "hazard", 16, 0.06)
	_blotches(img, "hazard_chips", 7, 1, 3, Color("6a6c6e"), 0.8)
	_scratches(img, "hazard_scratch", 10)
	_frame(img, 2)
	_grime_bottom(img, "hazard", 40, 0.35)
	return _finish("hazard", img)


## Slide pipes: grey metal with rust eating in, and bolted flanges.
static func rust_pipe() -> Texture2D:
	if _cache.has("rust_pipe"):
		return _cache["rust_pipe"]
	var img := _start("rust_pipe", Color("7a7f86"), 0.05)
	_rust(img, "rust_pipe", 0.08)
	for x in SIZE:
		for y in [0, 1, 30, 31, 32, 33]:
			_put(img, x, y, Color("3e4046"))
		_shade(img, x, 29, 0.7)
		_shade(img, x, 34, 1.3)
	for x in range(4, SIZE, 12):
		_rivet(img, x, 31)
	_streaks(img, "rust_pipe_run", 4, Color("6a3a1c"), 0.4)
	return _finish("rust_pipe", img)


## Office / complex wall (MGS PS1 style): blue-grey panels with recessed seams and screws, a dado
## rail, a darker kick panel scuffed by feet, a power socket, and dirt along the floor.
static func office_wall() -> Texture2D:
	if _cache.has("office_wall"):
		return _cache["office_wall"]
	var img := _start("office_wall", Color("717c84"), 0.03)
	for y in 42:
		for x in SIZE:
			_shade(img, x, y, 1.06 - 0.1 * y / 42.0)  # a little lighter near the top
	for x in SIZE:
		for y in range(46, SIZE):
			_put(img, x, y, img.get_pixel(x, y).darkened(0.3))
	for y in range(0, 46):
		_groove_v(img, 0, y, y + 1)
		_groove_v(img, 32, y, y + 1)
	_groove_h(img, 0, 0, SIZE)
	for x in SIZE:
		_put(img, x, 42, Color("a8b4bc"))
		_put(img, x, 43, Color("8e9aa2"))
		_put(img, x, 44, Color("5a646c"))
		_put(img, x, 45, Color("3e464c"))
	for p in [Vector2i(4, 4), Vector2i(28, 4), Vector2i(36, 4), Vector2i(60, 4), Vector2i(4, 38), Vector2i(28, 38), Vector2i(36, 38), Vector2i(60, 38)]:
		_rivet(img, p.x, p.y)
	_bevel(img, Rect2i(0, 46, 32, 18), 1.15, 0.75)
	_bevel(img, Rect2i(32, 46, 32, 18), 1.15, 0.75)
	# A power socket on the kick panel.
	_fill(img, Rect2i(12, 50, 6, 5), Color("b8bcb4"))
	_bevel(img, Rect2i(12, 50, 6, 5), 1.1, 0.7)
	_put(img, 14, 52, Color("2a2c2a"))
	_put(img, 16, 52, Color("2a2c2a"))
	_blotches(img, "office_wall_scuffs", 5, 1, 3, Color("30363a"), 0.4, Rect2i(0, 54, SIZE, 10))
	_grime_bottom(img, "office_wall", 50, 0.35)
	return _finish("office_wall", img)


## Office floor: linoleum tiles (four per lane width) each a slightly different shade, with
## grout lines, scuffs and a waxy sheen, and a darker seam where lanes meet.
static func office_floor() -> Texture2D:
	if _cache.has("office_floor"):
		return _cache["office_floor"]
	var img := _start("office_floor", Color("61645e"), 0.03)
	var rng := _rng("office_floor_tiles")
	for ty in 2:
		for tx in 2:
			var k := rng.randf_range(0.93, 1.07)
			for y in range(ty * 32, ty * 32 + 32):
				for x in range(tx * 32, tx * 32 + 32):
					_shade(img, x, y, k)
			_bevel(img, Rect2i(tx * 32, ty * 32, 32, 32), 1.1, 0.8)
	for i in SIZE:  # sheen
		_shade(img, i, (i + 20) % SIZE, 1.08)
		_shade(img, i, (i + 21) % SIZE, 1.05)
	_blotches(img, "office_floor_scuffs", 7, 1, 2, Color("3e403c"), 0.45)
	for y in SIZE:
		for x in range(0, 3):
			_put(img, x, y, Color("3c3e3a"))  # lane seam
	return _finish("office_floor", img)


## Office ceiling: acoustic tiles on a metal T-bar grid, perforated, with a water stain and an
## air vent. (The lights are real fixtures now, not painted on.)
static func office_ceiling() -> Texture2D:
	if _cache.has("office_ceiling"):
		return _cache["office_ceiling"]
	var img := _start("office_ceiling", Color("8a8e8a"), 0.025)
	var rng := _rng("office_ceiling_holes")
	for y in range(2, SIZE, 3):
		for x in range(2, SIZE, 3):
			if rng.randf() < 0.55:
				_shade(img, x + rng.randi_range(-1, 0), y, 0.8)
	for i in SIZE:
		for j in [0, 32]:
			_put(img, i, j, Color("b4b8b4"))
			_put(img, j, i, Color("b4b8b4"))
			_shade(img, i, j + 1, 0.65)
			_shade(img, j + 1, i, 0.7)
	# A brown water stain on one tile, a vent grille in another.
	_blotches(img, "office_ceiling_stain", 1, 6, 8, Color("7a6a4c"), 0.35, Rect2i(36, 36, 24, 24))
	_fill(img, Rect2i(8, 40, 16, 14), Color("6a6e6c"))
	for y in range(42, 53, 2):
		for x in range(9, 23):
			_put(img, x, y, Color("2c302e"))
	_bevel(img, Rect2i(8, 40, 16, 14), 1.2, 0.7)
	return _finish("office_ceiling", img)


## Gravel roofing: pebbles of several greys and browns, each lit from above, over dark tar, and
## a tarred membrane seam down the left edge (lanes meet there, so the lanes still read).
static func gravel() -> Texture2D:
	if _cache.has("gravel"):
		return _cache["gravel"]
	var img := _start("gravel", Color("45453f"), 0.05)
	var rng := _rng("gravel_pebbles")
	var tones := [Color("6e6c66"), Color("7a766c"), Color("5c5a54"), Color("6a6258"), Color("848078")]
	for i in 520:
		var x := rng.randi_range(0, SIZE - 1)
		var y := rng.randi_range(0, SIZE - 1)
		var c: Color = tones[rng.randi() % tones.size()]
		_put(img, x, y, c.lightened(0.15))
		if rng.randf() < 0.5:
			_put(img, x + 1, y, c)
		_put(img, x + 1, y + 1, c.darkened(0.45))
	for y in SIZE:
		for x in range(0, 3):
			_put(img, x, y, Color("33332f") if x < 2 else Color("3e3e39"))
	return _finish("gravel", img)


## Rooftop ventilation shaft: galvanised sheet with louvre slats, a riveted frame and rust
## running down from the slats.
static func vent() -> Texture2D:
	if _cache.has("vent"):
		return _cache["vent"]
	var img := _start("vent", Color("8c9296"), 0.035)
	for y in range(5, SIZE - 5):
		var r := (y - 5) % 7
		for x in range(5, SIZE - 5):
			if r == 0:
				_put(img, x, y, Color("b8bec2"))
			elif r == 1:
				_shade(img, x, y, 1.05)
			elif r >= 5:
				_put(img, x, y, Color("2e3236") if r == 6 else Color("454a4e"))
	_frame(img, 5)
	for p in [Vector2i(2, 2), Vector2i(SIZE - 4, 2), Vector2i(2, SIZE - 4), Vector2i(SIZE - 4, SIZE - 4), Vector2i(SIZE / 2, 2), Vector2i(SIZE / 2, SIZE - 4)]:
		_rivet(img, p.x, p.y)
	_streaks(img, "vent_rust", 4, Color("6a3a1c"), 0.3)
	_grime_bottom(img, "vent", 44, 0.3)
	return _finish("vent", img)


## Rooftop air-conditioning unit side: panels with a dense condenser grille, service screws, a
## stencilled unit number and weather staining.
static func hvac() -> Texture2D:
	if _cache.has("hvac"):
		return _cache["hvac"]
	var img := _start("hvac", Color("9a9a8e"), 0.035)
	for y in range(12, SIZE - 8):
		for x in range(4, SIZE - 4):
			if x == 32 or x == 31:
				continue
			var r := y % 3
			_put(img, x, y, Color("3c3c36") if r == 0 else (Color("5c5c54") if r == 1 else img.get_pixel(x, y).darkened(0.1)))
	_bevel(img, Rect2i(4, 12, 27, SIZE - 20), 0.7, 1.2)  # the grille is set in: dark top, light bottom
	_bevel(img, Rect2i(33, 12, 27, SIZE - 20), 0.7, 1.2)
	_frame(img, 3)
	_groove_v(img, 31, 0, SIZE)
	for p in [Vector2i(6, 6), Vector2i(26, 6), Vector2i(37, 6), Vector2i(57, 6), Vector2i(6, SIZE - 5), Vector2i(57, SIZE - 5)]:
		_rivet(img, p.x, p.y)
	_stencil(img, "AC-3", 9, 4, Color("2c2c28"), 0.8)
	_streaks(img, "hvac_rust", 5, Color("6a4a2a"), 0.3)
	_grime_bottom(img, "hvac", 46, 0.35)
	return _finish("hvac", img)


## A building at night: dark facade with floor bands and a grid of windows, some lit warm, some
## by cold fluorescent light, some with the blinds half down.
static func building_night() -> Texture2D:
	if _cache.has("building_night"):
		return _cache["building_night"]
	var img := _start("building_night", Color("1a1d24"), 0.02)
	var rng := _rng("building_windows")
	for wy in range(3, SIZE, 8):
		for x in SIZE:
			_shade(img, x, wy - 3, 0.7)  # floor band
		for wx in range(2, SIZE, 8):
			var roll := rng.randf()
			var lit := roll < 0.34
			var c := Color("2a3040")
			if lit:
				c = Color("d8b870").darkened(rng.randf_range(0.0, 0.35)) if rng.randf() < 0.7 else Color("a8c4c8").darkened(rng.randf_range(0.0, 0.3))
			var blinds := lit and rng.randf() < 0.35
			for y in range(wy, wy + 5):
				for x in range(wx, wx + 5):
					var px := c
					if blinds and (y - wy) < 3 and (y - wy) % 2 == 0:
						px = c.darkened(0.45)
					_put(img, x, y, px)
			if not lit:
				_put(img, wx, wy, Color("3a4458"))  # a glint of reflection
	return _finish("building_night", img)


## Night sky for a dome (u around, v top to bottom): near-black overhead, a faint orange city
## glow at the horizon, and stars in the upper part.
static func night_sky() -> Texture2D:
	if _cache.has("night_sky"):
		return _cache["night_sky"]
	# High enough resolution that one star pixel is a point on the big dome, not a square metre.
	var w := 1024
	var h := 512
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var rng := _rng("night_sky_stars")
	for y in h:
		var t := float(y) / (h - 1)  # 0 top, 1 bottom
		var c := Color("04060c").lerp(Color("141a2c"), smoothstep(0.1, 0.5, t))
		c = c.lerp(Color("3a2c34"), smoothstep(0.42, 0.52, t) * (1.0 - smoothstep(0.52, 0.62, t)))
		# Below the horizon it's the dark city, never sky, whatever the camera's height.
		c = c.lerp(Color("07080c"), smoothstep(0.55, 0.62, t))
		for x in w:
			img.set_pixel(x, y, c)
	for i in 900:
		var sy := rng.randi_range(0, int(h * 0.44))
		img.set_pixel(rng.randi_range(0, w - 1), sy, Color("e8ecff").darkened(rng.randf_range(0.2, 0.75)))
	var tex := ImageTexture.create_from_image(img)
	_cache["night_sky"] = tex
	return tex


## A city skyline strip for a distant ring: building silhouettes with lit windows, and clear sky
## (alpha 0) above them.
static func skyline() -> Texture2D:
	if _cache.has("skyline"):
		return _cache["skyline"]
	var w := 128
	var h := 32
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := _rng("skyline_blocks")
	var x := 0
	while x < w:
		var bw := rng.randi_range(4, 11)
		var top := rng.randi_range(4, 22)
		var base := Color("080a10").lightened(rng.randf_range(0.0, 0.05))
		for bx in range(x, mini(x + bw, w)):
			for y in range(top, h):
				var window := (bx - x) % 3 == 1 and (y - top) % 3 == 1 and rng.randf() < 0.3
				img.set_pixel(bx, y, Color("d0b060") if window else base)
		x += bw
	var tex := ImageTexture.create_from_image(img)
	_cache["skyline"] = tex
	return tex


## Office window onto a dark room: a bevelled frame, blinds half down, glass with a pale
## reflection streak.
static func office_window() -> Texture2D:
	if _cache.has("office_window"):
		return _cache["office_window"]
	var img := _start("office_window", Color("26343e"), 0.03)
	for y in SIZE:
		for x in SIZE:
			_shade(img, x, y, 1.15 - 0.3 * y / SIZE)
	for y in range(4, 30):  # blinds
		for x in range(4, SIZE - 4):
			_put(img, x, y, Color("9aa29e") if y % 3 != 2 else Color("5a625e"))
	for i in range(0, 34):
		for w in 2:
			_blend(img, 10 + i + w, 60 - i, Color("6a8494"), 0.6)
			_blend(img, 18 + i + w, 60 - i, Color("5a7282"), 0.35)
	_frame(img, 4, Color("8a949a"))
	for y in range(4, SIZE - 4):
		_put(img, 31, y, Color("8a949a"))
		_put(img, 32, y, Color("6a7478"))
	return _finish("office_window", img)


## Notice board: cork in a frame, with pinned sheets (typed lines, a photo, a yellow memo).
static func notice_board() -> Texture2D:
	if _cache.has("notice_board"):
		return _cache["notice_board"]
	var img := _start("notice_board", Color("8a6a40"), 0.06)
	_aggregate(img, "notice_board_cork", 400, 0.12)
	var rng := _rng("notice_board_papers")
	for i in 6:
		var px := rng.randi_range(5, SIZE - 20)
		var py := rng.randi_range(5, SIZE - 22)
		var paper := Color("e4e0d4") if i % 3 != 2 else Color("e8d890")
		_fill(img, Rect2i(px + 1, py + 1, 14, 18), Color("4a3a24"))  # shadow
		_fill(img, Rect2i(px, py, 14, 18), paper)
		if i == 4:
			_fill(img, Rect2i(px + 2, py + 2, 10, 8), Color("4a5058"))  # a photo
		for ly in range(py + 3, py + 16, 2):
			for lx in range(px + 2, px + 12 - (ly % 5)):
				_put(img, lx, ly, paper.darkened(0.4))
		_put(img, px + 6, py, Color("c83a2a"))
		_put(img, px + 7, py, Color("ff7a6a"))
	_frame(img, 3, Color("5a4a36"))
	return _finish("notice_board", img)


## Steel access door (roofs, tunnels): riveted grey plate with two recessed panels, a small
## wired-glass window, a stencilled "B2", a hazard kick plate and rust at the bottom.
static func steel_door() -> Texture2D:
	if _cache.has("steel_door"):
		return _cache["steel_door"]
	var img := _start("steel_door", Color("6a7076"), 0.035)
	_bevel(img, Rect2i(8, 6, 48, 20), 0.75, 1.2)
	_bevel(img, Rect2i(8, 30, 48, 20), 0.75, 1.2)
	_fill(img, Rect2i(22, 9, 18, 13), Color("22303a"))
	for y in range(9, 22):
		for x in range(22, 40):
			if (x + y) % 4 == 0 or (x - y) % 4 == 0:
				_put(img, x, y, Color("4a5a64"))  # wire mesh
	_bevel(img, Rect2i(21, 8, 20, 15), 0.6, 1.3)
	_stencil(img, "B2", 12, 36, Color("d8c890"), 0.75)
	for y in range(52, SIZE - 3):
		for x in range(3, SIZE - 3):
			_put(img, x, y, Color("c9a227") if ((x + y) / 5) % 2 == 0 else Color("1c1c1a"))
	_scratches(img, "steel_door_kick", 5, Rect2i(3, 52, SIZE - 6, 9))
	for x in range(46, 56):
		_put(img, x, 28, Color("c8ccd0"))
		_put(img, x, 29, Color("5a5e62"))
	for y in range(6, 50, 8):
		_rivet(img, 3, y)
		_rivet(img, SIZE - 5, y)
	_frame(img, 2, Color("40454a"))
	_streaks(img, "steel_door_rust", 3, Color("6a3a1c"), 0.3)
	_grime_bottom(img, "steel_door", 46, 0.3)
	return _finish("steel_door", img)


## Office door: pale grey-green, a wired-glass window, a push plate and handle, a metal kick
## plate and scuffs. (No lettering: the right-hand leaf of a double door is this, mirrored.)
static func door() -> Texture2D:
	if _cache.has("door"):
		return _cache["door"]
	var img := _start("door", Color("8e9a92"), 0.03)
	_bevel(img, Rect2i(8, 36, 48, 14), 1.15, 0.8)
	_fill(img, Rect2i(14, 10, 16, 18), Color("32424a"))
	for y in range(10, 28):
		for x in range(14, 30):
			if (x + y) % 5 == 0 or (x - y) % 5 == 0:
				_put(img, x, y, Color("4a5e68"))
			if x - y == 8 or x - y == 9:
				_put(img, x, y, Color("6a8290"))  # reflection
	_bevel(img, Rect2i(13, 9, 18, 20), 0.6, 1.3)
	_fill(img, Rect2i(50, 26, 3, 10), Color("b8bcb8"))  # push plate
	_bevel(img, Rect2i(50, 26, 3, 10), 1.2, 0.7)
	for x in range(46, 54):
		_put(img, x, 31, Color("d0d4d0"))
		_put(img, x, 32, Color("50585a"))
	_fill(img, Rect2i(4, 54, SIZE - 8, 7), Color("a8acaa"))
	_bevel(img, Rect2i(4, 54, SIZE - 8, 7), 1.2, 0.7)
	_scratches(img, "door_kick", 6, Rect2i(4, 54, SIZE - 8, 7))
	_frame(img, 3, Color("5a645e"))
	_grime_bottom(img, "door", 48, 0.25)
	return _finish("door", img)


## Metal filing cabinet: four drawers, each with a recessed handle, a label card and the odd
## dent, dirtier near the floor.
static func cabinet() -> Texture2D:
	if _cache.has("cabinet"):
		return _cache["cabinet"]
	var img := _start("cabinet", Color("7c8288"), 0.03)
	for d in 4:
		var y0 := d * 16
		_bevel(img, Rect2i(3, y0 + 1, SIZE - 6, 14), 1.2, 0.65)
		_fill(img, Rect2i(26, y0 + 8, 12, 3), Color("2e3236"))
		for x in range(26, 38):
			_put(img, x, y0 + 7, Color("c8ccd0"))
		_fill(img, Rect2i(28, y0 + 3, 8, 3), Color("dcd8c8"))
		_put(img, 29, y0 + 4, Color("6a6a60"))
		_put(img, 31, y0 + 4, Color("6a6a60"))
		_put(img, 33, y0 + 4, Color("6a6a60"))
	_blotches(img, "cabinet_dents", 3, 1, 3, Color("50565c"), 0.4)
	_frame(img, 2, Color("4e5358"))
	_grime_bottom(img, "cabinet", 40, 0.3)
	return _finish("cabinet", img)


## Office desk: a wood-effect top with grain over a grey modesty panel.
static func desk() -> Texture2D:
	if _cache.has("desk"):
		return _cache["desk"]
	var img := _start("desk", Color("5e6268"), 0.03)
	_grain(img, "desk_grain", Rect2i(0, 0, SIZE, 14), Color("8a6a44"))
	for x in SIZE:
		_put(img, x, 14, Color("3a3024"))
		_put(img, x, 15, Color("2a2420"))
	_bevel(img, Rect2i(2, 17, 29, SIZE - 19), 1.15, 0.75)
	_bevel(img, Rect2i(33, 17, 29, SIZE - 19), 1.15, 0.75)
	for p in [Vector2i(5, 20), Vector2i(27, 20), Vector2i(36, 20), Vector2i(58, 20)]:
		_rivet(img, p.x, p.y)
	_grime_bottom(img, "desk", 44, 0.3)
	return _finish("desk", img)


## Wooden crate: grained planks with dark gaps, a nailed frame and a diagonal brace, and a faded
## stencilled lot number.
static func crate_wood() -> Texture2D:
	if _cache.has("crate_wood"):
		return _cache["crate_wood"]
	var img := _start("crate_wood", Color("8a6238"), 0.04)
	_grain(img, "crate_wood_grain", Rect2i(0, 0, SIZE, SIZE), Color("8a6238"))
	for y in SIZE:
		if y % 16 == 15:
			for x in SIZE:
				_put(img, x, y, Color("3a2612"))
				_shade(img, x, y - 1, 0.8)
	_stencil(img, "B-12", 10, 46, Color("2a1a0c"), 0.65)
	var frame := Color("6a4826")
	for y in SIZE:
		for x in SIZE:
			if x < 6 or x > SIZE - 7 or y < 6 or y > SIZE - 7 or absi(x - y) <= 2:
				var c := frame.lightened(0.04 * sin(y * 0.9 + x * 0.3))
				_put(img, x, y, c)
	_bevel(img, Rect2i(0, 0, SIZE, 6), 1.2, 0.7)
	_bevel(img, Rect2i(0, SIZE - 6, SIZE, 6), 1.2, 0.7)
	_bevel(img, Rect2i(0, 0, 6, SIZE), 1.2, 0.7)
	_bevel(img, Rect2i(SIZE - 6, 0, 6, SIZE), 1.2, 0.7)
	for p in [Vector2i(2, 2), Vector2i(SIZE - 4, 2), Vector2i(2, SIZE - 4), Vector2i(SIZE - 4, SIZE - 4), Vector2i(8, 8), Vector2i(SIZE - 10, SIZE - 10)]:
		_put(img, p.x, p.y, Color("2a2a2a"))
		_put(img, p.x + 1, p.y + 1, Color("9a9a90"))
	_grime_bottom(img, "crate_wood", 44, 0.3)
	return _finish("crate_wood", img)


## Metal crate: ribbed steel with riveted top and bottom bars, a yellow stencil band with its
## number, rust at the edges.
static func crate_metal() -> Texture2D:
	if _cache.has("crate_metal"):
		return _cache["crate_metal"]
	var img := _start("crate_metal", Color("5e666e"), 0.04)
	for x in SIZE:
		var k: float = [1.25, 1.1, 1.0, 1.0, 0.95, 0.9, 0.75, 0.65][x % 8]
		for y in SIZE:
			_shade(img, x, y, k)
	for y in range(26, 38):
		for x in range(6, SIZE - 6):
			_put(img, x, y, Color("c9a227").darkened(0.05 * ((x % 8) / 4)))
	_stencil(img, "05", 24, 27, Color("1c1c1a"), 0.9, 2)
	for y in [0, 1, 2, 3, 4, 5, SIZE - 6, SIZE - 5, SIZE - 4, SIZE - 3, SIZE - 2, SIZE - 1]:
		for x in SIZE:
			_put(img, x, y, Color("3a3f44"))
	_bevel(img, Rect2i(0, 0, SIZE, 6), 1.3, 0.6)
	_bevel(img, Rect2i(0, SIZE - 6, SIZE, 6), 1.3, 0.6)
	for x in range(4, SIZE, 10):
		_rivet(img, x, 2)
		_rivet(img, x, SIZE - 4)
	_rust(img, "crate_metal", 0.0)
	_streaks(img, "crate_metal_rust", 3, Color("6a3a1c"), 0.3)
	return _finish("crate_metal", img)


## Wall cover: a concrete-block column with a worn yellow and black band at the bottom.
static func cover_wall() -> Texture2D:
	if _cache.has("cover_wall"):
		return _cache["cover_wall"]
	var img := _start("cover_wall", Color("7c7c72"), 0.045)
	_courses(img, "cover_wall", 16, 32)
	_streaks(img, "cover_wall_streaks", 4, Color("4a4a44"), 0.3)
	for x in SIZE:
		for y in range(SIZE - 9, SIZE):
			_put(img, x, y, Color("c9a227") if ((x + y) / 6) % 2 == 0 else Color("1c1c1a"))
	_scratches(img, "cover_wall_band", 6, Rect2i(0, SIZE - 9, SIZE, 9))
	_grime_bottom(img, "cover_wall", 40, 0.3)
	return _finish("cover_wall", img)


# --- Helpers ----------------------------------------------------------------------

## Security wing wall (user reference): cold grey steel-and-concrete panels, a dark grey band
## along the bottom with a steel kick rail, a seam down the middle, rivets, and grime.
static func security_wall() -> Texture2D:
	if _cache.has("security_wall"):
		return _cache["security_wall"]
	var img := _start("security_wall", Color("7e8486"), 0.035)
	for y in 40:
		for x in SIZE:
			_shade(img, x, y, 1.04 - 0.08 * y / 40.0)
	_bevel(img, Rect2i(0, 0, 32, 40), 1.12, 0.78)
	_bevel(img, Rect2i(32, 0, 32, 40), 1.12, 0.78)
	for x in SIZE:  # a steel rail between the panels and the dark band
		_put(img, x, 40, Color("b0b6b8"))
		_put(img, x, 41, Color("8c9294"))
		_put(img, x, 42, Color("3a3e40"))
	for y in range(43, SIZE):
		for x in SIZE:
			_put(img, x, y, img.get_pixel(x, y).darkened(0.48))
	_bevel(img, Rect2i(0, 43, 64, 21), 1.1, 0.8)
	for p in [Vector2i(3, 3), Vector2i(28, 3), Vector2i(35, 3), Vector2i(60, 3), Vector2i(3, 36), Vector2i(28, 36), Vector2i(35, 36), Vector2i(60, 36)]:
		_rivet(img, p.x, p.y)
	_blotches(img, "security_wall_scuffs", 4, 1, 3, Color("2e3234"), 0.4, Rect2i(0, 50, SIZE, 14))
	_streaks(img, "security_wall_damp", 2, Color("4a5050"), 0.18)
	_grime_bottom(img, "security_wall", 52, 0.3)
	return _finish("security_wall", img)


## Security wing floor (user reference): big grey-green concrete tiles, one lane wide, with dark
## grout lines and worn, slightly mottled faces.
static func security_floor() -> Texture2D:
	if _cache.has("security_floor"):
		return _cache["security_floor"]
	var img := _start("security_floor", Color("5c625a"), 0.04)
	var rng := _rng("security_floor_tiles")
	for ty in 2:
		var k := rng.randf_range(0.94, 1.06)
		for y in range(ty * 32, ty * 32 + 32):
			for x in SIZE:
				_shade(img, x, y, k)
		_bevel(img, Rect2i(0, ty * 32, SIZE, 32), 1.08, 0.85)
	_noise(img, "security_floor_mottle", 4, 0.05)
	for i in SIZE:
		for g in 2:
			_put(img, g, i, Color("2a2e2a"))  # grout between lanes
			_put(img, i, g, Color("2e322e"))  # and between tiles
	_cracks(img, "security_floor_cracks", 2, 10, 0.75)
	_blotches(img, "security_floor_scuffs", 6, 1, 2, Color("3a3e38"), 0.4)
	return _finish("security_floor", img)


## A bank of four CCTV monitors in a black frame (user reference): grey-blue footage of empty
## corridors, scanlines, and a red REC dot on one.
static func cctv_monitors() -> Texture2D:
	if _cache.has("cctv_monitors"):
		return _cache["cctv_monitors"]
	var img := _start("cctv_monitors", Color("1a1c1e"), 0.02)
	var rng := _rng("cctv_monitors_feeds")
	for sy in 2:
		for sx in 2:
			var r := Rect2i(4 + sx * 30, 4 + sy * 30, 26, 26)
			_fill(img, r, Color("5a6a78"))
			# A corridor in perspective: dark floor and walls, a lit far end.
			var vx := r.position.x + 13 + rng.randi_range(-3, 3)
			var vy := r.position.y + 11
			for y in range(r.position.y, r.end.y):
				for x in range(r.position.x, r.end.x):
					var d := absf(float(x - vx)) / maxf(1.0, absf(float(y - vy)) + 1.0)
					if y > vy and d < 1.4:
						_put(img, x, y, Color("3e4a54"))  # floor
					elif d > 1.6:
						_shade(img, x, y, 0.78)  # walls
			_fill(img, Rect2i(vx - 2, vy - 3, 4, 4), Color("b8c8d4"))
			for y in range(r.position.y, r.end.y, 2):
				for x in range(r.position.x, r.end.x):
					_shade(img, x, y, 0.85)  # scanlines
			_bevel(img, r, 0.6, 1.25)
	_put(img, 8, 8, Color("ff3a2a"))
	_put(img, 9, 8, Color("ff3a2a"))
	return _finish("cctv_monitors", img)


## One CCTV screen (the 3D monitor banks): grey-blue footage of a corridor in perspective, a lit
## far end, scanlines and a timestamp bar. `view` picks one of a few different corridors.
static func cctv_screen(view: int) -> Texture2D:
	var key := "cctv_screen_%d" % view
	if _cache.has(key):
		return _cache[key]
	var img := _start(key, Color("5e7080"), 0.04)
	var vx: int = 32 + [0, -9, 8, -4][view % 4]
	var vy: int = 26 + [0, 4, -3, 2][view % 4]
	for y in SIZE:
		for x in SIZE:
			var d := absf(float(x - vx)) / maxf(1.0, absf(float(y - vy)) + 1.0)
			if y > vy and d < 1.3:
				_put(img, x, y, Color("3e4c58"))  # floor
			elif y < vy and d < 1.1:
				_put(img, x, y, Color("6c7e8c"))  # ceiling
			elif d > 1.5:
				_shade(img, x, y, 0.72)  # walls
	_fill(img, Rect2i(vx - 4, vy - 6, 8, 8), Color("c0d0dc"))  # the lit far end
	if view % 2 == 1:
		_fill(img, Rect2i(vx + 6, vy + 6, 3, 9), Color("2a3036"))  # someone standing there
	for y in range(0, SIZE, 2):
		for x in SIZE:
			_shade(img, x, y, 0.82)  # scanlines
	_fill(img, Rect2i(2, SIZE - 8, 26, 5), Color("1e2428"))  # timestamp bar
	for x in range(4, 26, 3):
		_put(img, x, SIZE - 6, Color("d8e0e4"))
	if view == 0:
		_fill(img, Rect2i(SIZE - 8, 3, 4, 4), Color("ff3a2a"))  # REC
	return _finish(key, img)


## The guard booth's window (user reference): through the glass, a dim room with a desk, a lit
## monitor and a chair; a steel frame with a horizontal bar and a reflection streak.
static func booth_window() -> Texture2D:
	if _cache.has("booth_window"):
		return _cache["booth_window"]
	var img := _start("booth_window", Color("1e262c"), 0.03)
	for y in SIZE:
		for x in SIZE:
			_shade(img, x, y, 0.8 + 0.4 * y / SIZE)
	_fill(img, Rect2i(6, 40, 52, 6), Color("3a3e40"))  # the desk
	_fill(img, Rect2i(6, 46, 52, 14), Color("2a2e30"))
	_fill(img, Rect2i(14, 26, 14, 12), Color("101214"))  # a monitor...
	_fill(img, Rect2i(16, 28, 10, 8), Color("7a96a8"))  # ...lit
	_fill(img, Rect2i(19, 38, 4, 2), Color("1a1c1e"))
	_fill(img, Rect2i(38, 30, 10, 12), Color("181a1c"))  # a chair back
	_fill(img, Rect2i(44, 20, 14, 3), Color("c8c0a0"))  # a strip light at the back
	for i in range(0, 40):  # a reflection across the glass
		_blend(img, 8 + i, 50 - i, Color("8aa0ac"), 0.35)
		_blend(img, 9 + i, 50 - i, Color("8aa0ac"), 0.2)
	for x in SIZE:
		_put(img, x, 32, Color("6a7074"))
		_put(img, x, 33, Color("3a3e40"))
	_frame(img, 3, Color("4a5054"))
	return _finish("booth_window", img)


## STAFF CANTEEN wall (user reference): warm beige plaster panels over a dark grey band with a
## steel rail, a little grubby.
static func canteen_wall() -> Texture2D:
	if _cache.has("canteen_wall"):
		return _cache["canteen_wall"]
	var img := _start("canteen_wall", Color("8c8676"), 0.035)
	for y in 38:
		for x in SIZE:
			_shade(img, x, y, 1.05 - 0.1 * y / 38.0)
	_groove_v(img, 0, 0, 38)
	_groove_v(img, 32, 0, 38)
	for x in SIZE:
		_put(img, x, 38, Color("b4ae9c"))
		_put(img, x, 39, Color("6c685c"))
	for y in range(40, SIZE):
		for x in SIZE:
			_put(img, x, y, img.get_pixel(x, y).darkened(0.55))
	_bevel(img, Rect2i(0, 40, 64, 24), 1.1, 0.8)
	_blotches(img, "canteen_wall_stains", 3, 2, 4, Color("6a5a3c"), 0.25, Rect2i(0, 0, SIZE, 38))
	_grime_bottom(img, "canteen_wall", 54, 0.3)
	return _finish("canteen_wall", img)


## STAFF CANTEEN floor: big pale beige-grey tiles, one lane wide, with dark grout and wear.
static func canteen_floor() -> Texture2D:
	if _cache.has("canteen_floor"):
		return _cache["canteen_floor"]
	var img := _start("canteen_floor", Color("8a8676"), 0.035)
	var rng := _rng("canteen_floor_tiles")
	for ty in 2:
		var k := rng.randf_range(0.95, 1.05)
		for y in range(ty * 32, ty * 32 + 32):
			for x in SIZE:
				_shade(img, x, y, k)
		_bevel(img, Rect2i(0, ty * 32, SIZE, 32), 1.06, 0.88)
	_noise(img, "canteen_floor_mottle", 4, 0.04)
	for i in SIZE:
		for g in 2:
			_put(img, g, i, Color("3c3a32"))
			_put(img, i, g, Color("44423a"))
	_blotches(img, "canteen_floor_scuffs", 6, 1, 2, Color("5a5648"), 0.4)
	return _finish("canteen_floor", img)


## A vending machine's front: `kind` 0 = a drinks machine in `tint` (red, blue or orange; a big can
## logo and buttons),
## 1 = the snack machine (rows of coloured packets behind glass, a keypad).
static func vending_front(kind: int, tint: Color = Color("c41e1e")) -> Texture2D:
	var key := "vending_%d_%s" % [kind, tint.to_html(false)]
	if _cache.has(key):
		return _cache[key]
	var img := _start(key, tint if kind == 0 else Color("1c2230"), 0.03)
	if kind == 0:
		for y in SIZE:
			for x in range(4, 46):
				_shade(img, x, y, 1.1 - 0.25 * absf(x - 25) / 21.0)
		# A white wave and a can shape.
		for i in 44:
			var y := 30 + int(sin(i * 0.25) * 6.0)
			for w in 3:
				_put(img, 4 + i % 42, y + w, Color("f0e8e0"))
		_fill(img, Rect2i(18, 12, 12, 14), Color("e8e0d8"))
		_fill(img, Rect2i(19, 13, 10, 12), tint.darkened(0.1))
		_fill(img, Rect2i(48, 6, 12, 40), Color("2a1a1a"))  # the button panel
		for b in 6:
			_fill(img, Rect2i(50, 9 + b * 6, 8, 4), Color("e8e0c8") if b % 2 == 0 else Color("e8c040"))
		_fill(img, Rect2i(12, 52, 30, 8), Color("101010"))  # the drop slot
	else:
		var colours := [Color("e8c040"), Color("e05030"), Color("40a0e0"), Color("60c060"), Color("e8e0d0"), Color("c060c0")]
		var rng := _rng("vending_snacks")
		for row in 6:
			for col in 5:
				_fill(img, Rect2i(4 + col * 8, 4 + row * 9, 6, 7), colours[rng.randi_range(0, colours.size() - 1)])
				_put(img, 4 + col * 8, 4 + row * 9, Color("f8f0e0"))
			for x in range(3, 44):
				_put(img, x, 11 + row * 9, Color("8a909a"))  # shelf
		_fill(img, Rect2i(48, 8, 12, 22), Color("3a404a"))  # keypad
		for k in 9:
			_put(img, 50 + (k % 3) * 3, 11 + (k / 3) * 4, Color("c8d0d8"))
		_fill(img, Rect2i(6, 56, 34, 6), Color("08080a"))
	_frame(img, 2, Color("2a2a2a"))
	return _finish(key, img)


## A menu board over the serving counter: a lit food picture (`item` 0 burger, 1 noodles, 2 soup)
## and lines of prices, on black.
static func menu_board(item: int) -> Texture2D:
	var key := "menu_board_%d" % item
	if _cache.has(key):
		return _cache[key]
	var img := _start(key, Color("141414"), 0.02)
	match item:
		0:
			_fill(img, Rect2i(8, 18, 20, 5), Color("d8a050"))  # bun
			_fill(img, Rect2i(7, 23, 22, 3), Color("60a040"))  # lettuce
			_fill(img, Rect2i(8, 26, 20, 4), Color("6a3a1e"))  # patty
			_fill(img, Rect2i(8, 30, 20, 4), Color("d8a050"))
		1:
			_fill(img, Rect2i(6, 24, 24, 10), Color("e8e8e0"))  # bowl
			for i in 5:
				_fill(img, Rect2i(8 + i * 4, 18 + i % 2, 2, 8), Color("e8c060"))  # noodles
			_fill(img, Rect2i(10, 20, 6, 3), Color("d04030"))
		2:
			_fill(img, Rect2i(6, 24, 24, 10), Color("e8e8e0"))
			_fill(img, Rect2i(8, 22, 20, 4), Color("c86a30"))  # soup
	for ly in range(16, 40, 6):
		for lx in range(36, 58):
			if lx % 7 != 6:
				_put(img, lx, ly, Color("e8e4d8"))
	_frame(img, 3, Color("4a4a46"))
	return _finish(key, img)


## STAFF CANTEEN pillar (cover walls, user reference): dark grey concrete with a pale band round
## the middle and a darker foot, chipped at the edges.
static func canteen_pillar() -> Texture2D:
	if _cache.has("canteen_pillar"):
		return _cache["canteen_pillar"]
	var img := _start("canteen_pillar", Color("4a4c4e"), 0.04)
	for y in range(22, 34):
		for x in SIZE:
			_put(img, x, y, Color("8e8a7c"))  # the pale band
	for x in SIZE:
		_put(img, x, 21, Color("2e3032"))
		_put(img, x, 34, Color("2e3032"))
	for y in range(52, SIZE):
		for x in SIZE:
			_shade(img, x, y, 0.7)
	_bevel(img, Rect2i(0, 0, SIZE, SIZE), 1.1, 0.8)
	_blotches(img, "canteen_pillar_chips", 4, 1, 2, Color("6a6c6c"), 0.5)
	_grime_bottom(img, "canteen_pillar", 50, 0.3)
	return _finish("canteen_pillar", img)


## Kitchen back wall: white glazed tiles, grout, a grease stain.
static func kitchen_tile() -> Texture2D:
	if _cache.has("kitchen_tile"):
		return _cache["kitchen_tile"]
	var img := _start("kitchen_tile", Color("c8c8bc"), 0.03)
	_tiles(img, 16, 16, Color("8a8a7e"))
	_blotches(img, "kitchen_grease", 2, 3, 6, Color("a08a5a"), 0.3)
	return _finish("kitchen_tile", img)


## A stainless-steel fridge door: brushed vertical grain, a long handle, a vent at the bottom.
static func fridge() -> Texture2D:
	if _cache.has("fridge"):
		return _cache["fridge"]
	var img := _start("fridge", Color("a4aaac"), 0.02)
	var rng := _rng("fridge_grain")
	for x in SIZE:
		var k := rng.randf_range(0.92, 1.08)
		for y in SIZE:
			_shade(img, x, y, k)
	_bevel(img, Rect2i(2, 2, 60, 26), 1.12, 0.8)
	_bevel(img, Rect2i(2, 30, 60, 26), 1.12, 0.8)
	for y in range(6, 24):
		_put(img, 54, y, Color("e0e4e4"))
		_put(img, 55, y, Color("6a7072"))
	for y in range(34, 52):
		_put(img, 54, y, Color("e0e4e4"))
		_put(img, 55, y, Color("6a7072"))
	for y in range(58, 63, 2):
		for x in range(6, 58):
			_put(img, x, y, Color("3a3e40"))
	return _finish("fridge", img)


static func _rng(key: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	return rng


## A new image: base colour with blotchy (large-scale) and fine noise, so surfaces look dirty and
## uneven rather than evenly speckled.
static func _start(key: String, base: Color, amount: float) -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	img.fill(base)
	if amount > 0.0:
		_noise(img, key, 16, amount * 1.4)
		_noise(img, key + "_fine", 4, amount * 0.7)
		var rng := _rng(key + "_grain")
		for y in SIZE:
			for x in SIZE:
				_shade(img, x, y, 1.0 + rng.randf_range(-amount, amount))
	return img


## Posterise to the PS1-style palette, add mipmaps (for distance only; up close it's still
## unfiltered pixels) and cache.
static func _finish(key: String, img: Image) -> Texture2D:
	for y in SIZE:
		for x in SIZE:
			var c := img.get_pixel(x, y)
			img.set_pixel(x, y, Color(roundf(c.r * LEVELS) / LEVELS, roundf(c.g * LEVELS) / LEVELS, roundf(c.b * LEVELS) / LEVELS))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


## Tileable value noise added to brightness: `cell` pixels between random values.
static func _noise(img: Image, key: String, cell: int, amount: float) -> void:
	var rng := _rng(key + "_noise%d" % cell)
	var g := SIZE / cell
	var v := PackedFloat32Array()
	v.resize(g * g)
	for i in g * g:
		v[i] = rng.randf_range(-1.0, 1.0)
	for y in SIZE:
		var fy := float(y) / cell
		var y0 := int(fy) % g
		var y1 := (y0 + 1) % g
		var ty := smoothstep(0.0, 1.0, fy - floorf(fy))
		for x in SIZE:
			var fx := float(x) / cell
			var x0 := int(fx) % g
			var x1 := (x0 + 1) % g
			var tx := smoothstep(0.0, 1.0, fx - floorf(fx))
			var n := lerpf(lerpf(v[y0 * g + x0], v[y0 * g + x1], tx), lerpf(v[y1 * g + x0], v[y1 * g + x1], tx), ty)
			_shade(img, x, y, 1.0 + n * amount)


static func _put(img: Image, x: int, y: int, c: Color) -> void:
	img.set_pixel(posmod(x, SIZE), posmod(y, SIZE), c)


## Multiply a pixel's brightness (k < 1 darker).
static func _shade(img: Image, x: int, y: int, k: float) -> void:
	var px := posmod(x, SIZE)
	var py := posmod(y, SIZE)
	var c := img.get_pixel(px, py)
	img.set_pixel(px, py, Color(c.r * k, c.g * k, c.b * k))


static func _blend(img: Image, x: int, y: int, c: Color, a: float) -> void:
	var px := posmod(x, SIZE)
	var py := posmod(y, SIZE)
	img.set_pixel(px, py, img.get_pixel(px, py).lerp(c, a))


static func _fill(img: Image, r: Rect2i, c: Color) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			_put(img, x, y, c)


## A raised panel: light top and left edges, dark bottom and right (swap the numbers for a
## recess).
static func _bevel(img: Image, r: Rect2i, light: float, dark: float) -> void:
	for x in range(r.position.x, r.end.x):
		_shade(img, x, r.position.y, light)
		_shade(img, x, r.end.y - 1, dark)
	for y in range(r.position.y + 1, r.end.y - 1):
		_shade(img, r.position.x, y, light)
		_shade(img, r.end.x - 1, y, dark)


## A bevelled border `w` pixels wide round the whole tile, optionally recoloured.
static func _frame(img: Image, w: int, color: Color = Color(0, 0, 0, 0)) -> void:
	for y in SIZE:
		for x in SIZE:
			if x < w or x >= SIZE - w or y < w or y >= SIZE - w:
				if color.a > 0.0:
					_put(img, x, y, color.lightened(0.03 * sin(x * 1.7 + y)))
				else:
					_shade(img, x, y, 0.8)
	_bevel(img, Rect2i(0, 0, SIZE, SIZE), 1.3, 0.6)
	_bevel(img, Rect2i(w - 1, w - 1, SIZE - 2 * w + 2, SIZE - 2 * w + 2), 0.6, 1.25)


## A recessed seam: a dark line with a light line after it.
static func _groove_h(img: Image, y: int, x0: int, x1: int) -> void:
	for x in range(x0, x1):
		_shade(img, x, y, 0.55)
		_shade(img, x, y + 1, 1.2)


static func _groove_v(img: Image, x: int, y0: int, y1: int) -> void:
	for y in range(y0, y1):
		_shade(img, x, y, 0.55)
		_shade(img, x + 1, y, 1.2)


## A rivet or screw head: lit on top, shadow below right.
static func _rivet(img: Image, x: int, y: int) -> void:
	_shade(img, x, y, 1.55)
	_shade(img, x + 1, y, 1.2)
	_shade(img, x, y + 1, 1.1)
	_shade(img, x + 1, y + 1, 0.55)
	_shade(img, x + 2, y + 1, 0.75)
	_shade(img, x + 1, y + 2, 0.75)


## Dirt building up toward the bottom of a wall from row `from_y`.
static func _grime_bottom(img: Image, key: String, from_y: int, strength: float) -> void:
	var rng := _rng(key + "_grime")
	for y in range(from_y, SIZE):
		var t := pow(float(y - from_y) / (SIZE - from_y), 1.4)
		for x in SIZE:
			_shade(img, x, y, 1.0 - strength * t * rng.randf_range(0.6, 1.0))


## Streaks running down from the top or from seams (water, rust): each fades as it goes.
static func _streaks(img: Image, key: String, count: int, tint: Color, strength: float) -> void:
	var rng := _rng(key)
	for i in count:
		var x := rng.randi_range(0, SIZE - 1)
		var y0: int = [0, 0, 16, 32, 38][rng.randi() % 5] + rng.randi_range(0, 3)
		var length := rng.randi_range(10, 34)
		var w := 1 + rng.randi() % 2
		for j in length:
			var a := strength * (1.0 - float(j) / length)
			if rng.randf() < 0.15:
				x += rng.randi_range(-1, 1)
			for k in w:
				_blend(img, x + k, y0 + j, tint, a)


## Soft blotches (stains, oil, damp, chipped paint), optionally only inside `area`.
static func _blotches(img: Image, key: String, count: int, r_min: int, r_max: int, tint: Color, strength: float,
		area: Rect2i = Rect2i(0, 0, SIZE, SIZE)) -> void:
	var rng := _rng(key)
	for i in count:
		var cx := rng.randi_range(area.position.x, area.end.x - 1)
		var cy := rng.randi_range(area.position.y, area.end.y - 1)
		var r := rng.randi_range(r_min, r_max)
		for y in range(cy - r, cy + r + 1):
			for x in range(cx - r, cx + r + 1):
				var d := Vector2(x - cx, y - cy).length() / maxf(r, 0.5)
				if d <= 1.0 and rng.randf() < 1.1 - d * 0.5:
					_blend(img, x, y, tint, strength * (1.0 - d * 0.6))


## Hairline cracks: dark random walks.
static func _cracks(img: Image, key: String, count: int, length: int, dark: float) -> void:
	var rng := _rng(key)
	for i in count:
		var p := Vector2i(rng.randi_range(0, SIZE - 1), rng.randi_range(0, SIZE - 1))
		var dir := Vector2i([-1, 0, 1][rng.randi() % 3], 1)
		for j in length:
			_shade(img, p.x, p.y, dark)
			if rng.randf() < 0.35:
				dir.x = clampi(dir.x + rng.randi_range(-1, 1), -1, 1)
			p += dir


## Short scratches through paint: light on dark, dark on light.
static func _scratches(img: Image, key: String, count: int, area: Rect2i = Rect2i(0, 0, SIZE, SIZE)) -> void:
	var rng := _rng(key)
	for i in count:
		var x := rng.randi_range(area.position.x, area.end.x - 1)
		var y := rng.randi_range(area.position.y, area.end.y - 1)
		var dx: int = [-1, 1][rng.randi() % 2]
		for j in rng.randi_range(3, 7):
			var c := img.get_pixel(posmod(x, SIZE), posmod(y, SIZE))
			_shade(img, x, y, 1.6 if c.get_luminance() < 0.3 else 0.65)
			x += dx
			if rng.randf() < 0.4:
				y += 1


## Tiny stones in concrete, asphalt and cork: single light or dark pixels.
static func _aggregate(img: Image, key: String, count: int, amount: float) -> void:
	var rng := _rng(key)
	for i in count:
		_shade(img, rng.randi_range(0, SIZE - 1), rng.randi_range(0, SIZE - 1), 1.0 + (amount * 3.0 if i % 2 else -amount * 3.0))


## Rust eating into metal where the blotchy noise is high.
static func _rust(img: Image, key: String, amount: float) -> void:
	var rust := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	rust.fill(Color(0.5, 0.5, 0.5))
	_noise(rust, key + "_rust", 8, 0.9)
	var rng := _rng(key + "_rust_px")
	for y in SIZE:
		for x in SIZE:
			var n := rust.get_pixel(x, y).r
			if n > 0.62 - amount:
				_blend(img, x, y, Color("7a4020").lightened(rng.randf_range(-0.1, 0.12)), clampf((n - 0.5) * 2.5, 0.3, 0.9))


## Wood grain across a rect: streaky horizontal bands.
static func _grain(img: Image, key: String, r: Rect2i, wood: Color) -> void:
	var rng := _rng(key)
	var phase := rng.randf_range(0.0, TAU)
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var g := sin(y * 1.3 + sin(x * 0.18 + phase) * 2.2 + sin(x * 0.05) * 3.0)
			_put(img, x, y, wood.darkened(0.12 * (g * 0.5 + 0.5)).lightened(rng.randf_range(0.0, 0.04)))


## Staggered courses of blocks or bricks, each unit bevelled and a slightly different shade.
static func _courses(img: Image, key: String, row_h: int, block_w: int) -> void:
	var rng := _rng(key + "_courses")
	for row in SIZE / row_h:
		var offset := (block_w / 2) * (row % 2)
		for b in range(-1, SIZE / block_w + 1):
			var x0 := b * block_w + offset
			var k := rng.randf_range(0.92, 1.08)
			for y in range(row * row_h, row * row_h + row_h):
				for x in range(x0, x0 + block_w):
					if x >= 0 and x < SIZE:
						_shade(img, x, y, k)
			var r := Rect2i(x0, row * row_h, block_w, row_h)
			for x in range(r.position.x, r.end.x):
				_shade(img, x, r.position.y, 0.55)  # mortar line
				_shade(img, x, r.position.y + 1, 1.18)
			for y in range(r.position.y, r.end.y):
				_shade(img, r.position.x, y, 0.6)
				_shade(img, r.position.x + 1, y, 1.12)
				_shade(img, r.end.x - 1, y, 0.85)


## Glazed tiles (w x h px): grout lines, and a glint at each tile's top-left corner.
static func _tiles(img: Image, w: int, h: int, grout: Color) -> void:
	for y in SIZE:
		for x in SIZE:
			var offset := (w / 2) * ((y / h) % 2)
			var lx := (x + offset) % w
			var ly := y % h
			if lx == 0 or ly == 0:
				_put(img, x, y, grout)
			elif lx == 1 and ly == 1:
				_shade(img, x, y, 1.35)
			elif ly == 1 or lx == 1:
				_shade(img, x, y, 1.1)
			elif ly == h - 1 or lx == w - 1:
				_shade(img, x, y, 0.85)


## Worn stencil lettering in the 3x5 font; `scale` makes each font pixel bigger.
static func _stencil(img: Image, text: String, x: int, y: int, color: Color, alpha: float, scale: int = 1) -> void:
	var rng := _rng("stencil_" + text)
	var cx := x
	for ch in text:
		if GLYPHS.has(ch):
			var rows: Array = GLYPHS[ch]
			for gy in 5:
				for gx in 3:
					if rows[gy][gx] == "1":
						for sy in scale:
							for sx in scale:
								if rng.randf() > 0.12:  # worn
									_blend(img, cx + gx * scale + sx, y + gy * scale + sy, color, alpha)
		cx += 4 * scale
