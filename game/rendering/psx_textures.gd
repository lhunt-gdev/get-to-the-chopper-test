class_name PsxTextures
extends RefCounted
## Placeholder PS1-style textures, generated in code so the prototype needs no art files.
## Tiny, nearest-filtered, with colour baked in. Real art replaces these later.
## Each texture is cached by key, and the noise uses a fixed seed so it looks the same every run.

const SIZE := 32
const ROAD := Color("3a3a37")

static var _cache: Dictionary = {}


## One lane-width tile of road, with a dashed lane line down its left edge.
static func asphalt() -> Texture2D:
	if _cache.has("asphalt"):
		return _cache["asphalt"]
	var img := _start("asphalt", ROAD, 0.035)
	for y in range(0, 16):
		for x in range(0, 2):
			img.set_pixel(x, y, Color("b8b49a"))
	return _finish("asphalt", img)


## Plain concrete slabs, e.g. the helipad.
static func concrete() -> Texture2D:
	if _cache.has("concrete"):
		return _cache["concrete"]
	var img := _start("concrete", Color("6a6a62"), 0.04)
	for i in SIZE:
		img.set_pixel(i, 0, Color("55554e"))
		img.set_pixel(0, i, Color("55554e"))
	return _finish("concrete", img)


## A road lane painted in its route colour, with an arrow pointing to where it goes.
## dir: -1 left, 0 straight on, 1 right.
static func fork_lane(dir: int, color: Color) -> Texture2D:
	var key := "fork_%d_%s" % [dir, color.to_html()]
	if _cache.has(key):
		return _cache[key]
	var img := _start(key, ROAD.lerp(color, 0.3), 0.035)
	var paint := color.lightened(0.15)
	for y in SIZE:
		for x in SIZE:
			if _arrow(dir, x, y):
				img.set_pixel(x, y, paint)
			elif x < 2 and y < 16:  # keep the dashed lane line
				img.set_pixel(x, y, Color("b8b49a"))
	return _finish(key, img)


## Walls, one tile per 2 m x 2 m. pattern: "blocks", "brick", "corrugated" or "tile".
static func wall(pattern: String, color: Color) -> Texture2D:
	var key := "wall_%s_%s" % [pattern, color.to_html()]
	if _cache.has(key):
		return _cache[key]
	var img := _start(key, color, 0.04)
	var line := color.darkened(0.45)
	match pattern:
		"blocks":
			_courses(img, 8, 16, line)
		"brick":
			_courses(img, 4, 8, line)
		"tile":
			for i in SIZE:
				for j in range(0, SIZE, 8):
					img.set_pixel(i, j, line)
					img.set_pixel(j, i, line)
		"corrugated":
			for x in SIZE:
				for y in SIZE:
					var c := img.get_pixel(x, y)
					img.set_pixel(x, y, c.lightened(0.18) if (x / 2) % 2 == 0 else c.darkened(0.12))
	return _finish(key, img)


## Jump barriers: yellow and black hazard stripes.
static func hazard() -> Texture2D:
	if _cache.has("hazard"):
		return _cache["hazard"]
	var img := _start("hazard", Color.BLACK, 0.0)
	for y in SIZE:
		for x in SIZE:
			img.set_pixel(x, y, Color("d9b02a") if ((x + y) / 8) % 2 == 0 else Color("1c1c1a"))
	return _finish("hazard", img)


## Slide pipes: grey metal with rust patches and joint bands.
static func rust_pipe() -> Texture2D:
	if _cache.has("rust_pipe"):
		return _cache["rust_pipe"]
	var img := _start("rust_pipe", Color("7a7f86"), 0.05)
	var rng := _rng("rust_pipe_spots")
	for i in 14:
		var cx := rng.randi_range(0, SIZE - 1)
		var cy := rng.randi_range(0, SIZE - 1)
		var r := rng.randi_range(2, 4)
		for y in range(cy - r, cy + r + 1):
			for x in range(cx - r, cx + r + 1):
				if Vector2(x - cx, y - cy).length() <= r:
					img.set_pixel(posmod(x, SIZE), posmod(y, SIZE), Color("8a4a22").lightened(rng.randf_range(-0.1, 0.1)))
	for x in SIZE:
		for y in [0, 15, 16]:
			img.set_pixel(x, y, Color("3e4046"))
	return _finish("rust_pipe", img)


## Trucks: olive canvas with panel seams and a stencilled star.
static func truck() -> Texture2D:
	if _cache.has("truck"):
		return _cache["truck"]
	var img := _start("truck", Color("4a5a30"), 0.05)
	var seam := Color("2a3318")
	for i in SIZE:
		img.set_pixel(i, 0, seam)
		img.set_pixel(0, i, seam)
		img.set_pixel(16, i, seam)
	for y in range(10, 23):
		for x in range(2, 15):
			if absi(x - 8) + absi(y - 16) <= 5:
				img.set_pixel(x, y, Color("c8c8b0"))
	return _finish("truck", img)


# --- Helpers ----------------------------------------------------------------------

static func _rng(key: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	return rng


## A new image filled with noisy base colour.
static func _start(key: String, base: Color, amount: float) -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var rng := _rng(key)
	for y in SIZE:
		for x in SIZE:
			var n := rng.randf_range(-amount, amount)
			img.set_pixel(x, y, Color(base.r + n, base.g + n, base.b + n))
	return img


static func _finish(key: String, img: Image) -> Texture2D:
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


## Staggered courses of blocks or bricks.
static func _courses(img: Image, row_h: int, block_w: int, line: Color) -> void:
	for y in SIZE:
		var offset := (block_w / 2) * ((y / row_h) % 2)
		for x in SIZE:
			if y % row_h == 0 or (x + offset) % block_w == 0:
				img.set_pixel(x, y, line)


## A chunky arrow in a 32x32 tile. Small y is further down the road (away from the camera).
static func _arrow(dir: int, x: int, y: int) -> bool:
	if dir == 0:  # ^ straight on: a shaft and a head
		var shaft := absi(x - 16) <= 2 and y >= 13 and y <= 27
		var head := y >= 4 and y < 13 and absi(x - 16) <= y - 4
		return shaft or head
	# < or >: a chevron
	var fx := x if dir < 0 else SIZE - 1 - x
	var d := absi(y - 16)
	return d <= 9 and fx - 8 >= d and fx - 8 <= d + 4
