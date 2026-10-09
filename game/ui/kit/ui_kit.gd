class_name UiKit
extends RefCounted
## The game's UI look, shared by the HUD and every menu: a sleek espionage style that mixes MGS1
## (codec panels, thin teal outlines, scanlines), GoldenEye N64 (dossier menus, red danger accents)
## and GTA (bold, slanted, chunky blocks). All text is a 5x7 pixel font made here in code, used at
## whole-pixel sizes (8, 16, 24) so it stays crisp at 270x480.

const TEAL := Color("62d6c0")
const TEAL_DIM := Color("2e6e66")
const PANEL := Color(0.03, 0.07, 0.08, 0.86)
const PANEL_SOLID := Color("081214")
const PAPER := Color("e8e0c8")
const DIM := Color("7d8f8f")
const RED := Color("e0402e")
const AMBER := Color("f0b040")
const GREEN := Color("8fd36b")
const INK := Color("050808")

## 5x7 glyphs, rows top to bottom ("#" = ink). Lowercase draws as uppercase.
const GLYPHS := {
	"A": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
	"B": ["####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."],
	"C": [".###.", "#...#", "#....", "#....", "#....", "#...#", ".###."],
	"D": ["####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."],
	"E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
	"F": ["#####", "#....", "#....", "####.", "#....", "#....", "#...."],
	"G": [".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".####"],
	"H": ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
	"I": [".###.", "..#..", "..#..", "..#..", "..#..", "..#..", ".###."],
	"J": ["..###", "...#.", "...#.", "...#.", "...#.", "#..#.", ".##.."],
	"K": ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"],
	"L": ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
	"M": ["#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#"],
	"N": ["#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#", "#...#"],
	"O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
	"P": ["####.", "#...#", "#...#", "####.", "#....", "#....", "#...."],
	"Q": [".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#"],
	"R": ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
	"S": [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
	"T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
	"U": ["#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
	"V": ["#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#.."],
	"W": ["#...#", "#...#", "#...#", "#.#.#", "#.#.#", "##.##", "#...#"],
	"X": ["#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#"],
	"Y": ["#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."],
	"Z": ["#####", "....#", "...#.", "..#..", ".#...", "#....", "#####"],
	"0": [".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."],
	"1": ["..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."],
	"2": [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"],
	"3": ["####.", "....#", "....#", ".###.", "....#", "....#", "####."],
	"4": ["...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."],
	"5": ["#####", "#....", "####.", "....#", "....#", "#...#", ".###."],
	"6": [".###.", "#....", "#....", "####.", "#...#", "#...#", ".###."],
	"7": ["#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."],
	"8": [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
	"9": [".###.", "#...#", "#...#", ".####", "....#", "....#", ".###."],
	" ": [".....", ".....", ".....", ".....", ".....", ".....", "....."],
	".": [".....", ".....", ".....", ".....", ".....", ".##..", ".##.."],
	",": [".....", ".....", ".....", ".....", ".##..", "..#..", ".#..."],
	":": [".....", ".##..", ".##..", ".....", ".##..", ".##..", "....."],
	";": [".....", ".##..", ".##..", ".....", ".##..", "..#..", ".#..."],
	"!": ["..#..", "..#..", "..#..", "..#..", "..#..", ".....", "..#.."],
	"?": [".###.", "#...#", "....#", "...#.", "..#..", ".....", "..#.."],
	"-": [".....", ".....", ".....", "#####", ".....", ".....", "....."],
	"+": [".....", "..#..", "..#..", "#####", "..#..", "..#..", "....."],
	"=": [".....", ".....", "#####", ".....", "#####", ".....", "....."],
	"/": ["....#", "....#", "...#.", "..#..", ".#...", "#....", "#...."],
	"'": ["..#..", "..#..", ".#...", ".....", ".....", ".....", "....."],
	"\"": [".#.#.", ".#.#.", ".....", ".....", ".....", ".....", "....."],
	"(": ["...#.", "..#..", ".#...", ".#...", ".#...", "..#..", "...#."],
	")": [".#...", "..#..", "...#.", "...#.", "...#.", "..#..", ".#..."],
	"<": ["...#.", "..#..", ".#...", "#....", ".#...", "..#..", "...#."],
	">": [".#...", "..#..", "...#.", "....#", "...#.", "..#..", ".#..."],
	"^": ["..#..", ".#.#.", "#...#", ".....", ".....", ".....", "....."],
	"%": ["##...", "##..#", "...#.", "..#..", ".#...", "#..##", "...##"],
	"#": [".#.#.", ".#.#.", "#####", ".#.#.", "#####", ".#.#.", ".#.#."],
	"_": [".....", ".....", ".....", ".....", ".....", ".....", "#####"],
	"*": [".....", "#.#.#", ".###.", "#####", ".###.", "#.#.#", "....."],
	"&": [".##..", "#..#.", "#.#..", ".#...", "#.#.#", "#..#.", ".##.#"],
	"@": [".###.", "#...#", "#.###", "#.#.#", "#.###", "#....", ".###."],
	"[": [".###.", ".#...", ".#...", ".#...", ".#...", ".#...", ".###."],
	"]": [".###.", "...#.", "...#.", "...#.", "...#.", "...#.", ".###."],
	"●": [".....", ".###.", "#####", "#####", "#####", ".###.", "....."],
	"▶": [".#...", ".##..", ".###.", ".####", ".###.", ".##..", ".#..."],
}
## Each glyph cell: 5 wide plus 1 spacing, 7 tall plus 1 below.
const CELL := Vector2i(6, 9)

static var _font: FontFile
static var _theme: Theme


## The pixel font (built once). Its base size is 8; use 8, 16 or 24 for crisp text.
static func font() -> FontFile:
	if _font != null:
		return _font
	var chars := GLYPHS.keys()
	var cols := 16
	var rows := ceili(float(chars.size()) / cols)
	var img := Image.create(cols * CELL.x, rows * CELL.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	var f := FontFile.new()
	f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	f.fixed_size = 8
	f.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_INTEGER_ONLY
	f.generate_mipmaps = false
	var size := Vector2i(8, 0)
	for i in chars.size():
		var ch: String = chars[i]
		var rows_art: Array = GLYPHS[ch]
		var cx := (i % cols) * CELL.x
		var cy := (i / cols) * CELL.y
		for gy in 7:
			for gx in 5:
				if rows_art[gy][gx] == "#":
					img.set_pixel(cx + gx, cy + gy, Color.WHITE)
		var codes: Array[int] = [ch.unicode_at(0)]
		if ch.length() == 1 and ch >= "A" and ch <= "Z":
			codes.append(ch.to_lower().unicode_at(0))
		for code in codes:
			f.set_glyph_advance(0, 8, code, Vector2(CELL.x, 0))
			f.set_glyph_offset(0, size, code, Vector2(0, -7))
			f.set_glyph_size(0, size, code, Vector2(5, 7))
			f.set_glyph_uv_rect(0, size, code, Rect2(cx, cy, 5, 7))
			f.set_glyph_texture_idx(0, size, code, 0)
	f.set_texture_image(0, size, 0, img)
	f.set_cache_ascent(0, 8, 7.0)
	f.set_cache_descent(0, 8, 2.0)
	_font = f
	return f


## The theme every menu uses: the pixel font, slanted GTA-style buttons with a teal edge,
## dark codec panels.
static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 8
	var normal := _button_box(Color(0.03, 0.08, 0.09, 0.9), TEAL_DIM)
	var hover := _button_box(Color(0.05, 0.16, 0.16, 0.95), TEAL)
	var pressed := _button_box(Color(0.35, 0.08, 0.05, 0.95), RED)
	var disabled := _button_box(Color(0.03, 0.05, 0.05, 0.7), Color("223333"))
	for state in ["normal", "focus"]:
		t.set_stylebox(state, "Button", normal if state == "normal" else hover)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_color("font_color", "Button", PAPER)
	t.set_color("font_hover_color", "Button", TEAL)
	t.set_color("font_pressed_color", "Button", PAPER)
	t.set_color("font_focus_color", "Button", TEAL)
	t.set_font_size("font_size", "Button", 8)
	# A smaller, tighter button for settings rows ("CompactButton").
	t.set_type_variation("CompactButton", "Button")
	var cn := _button_box(Color(0.03, 0.08, 0.09, 0.9), TEAL_DIM, true)
	var ch := _button_box(Color(0.05, 0.16, 0.16, 0.95), TEAL, true)
	var cp := _button_box(Color(0.35, 0.08, 0.05, 0.95), RED, true)
	t.set_stylebox("normal", "CompactButton", cn)
	t.set_stylebox("focus", "CompactButton", ch)
	t.set_stylebox("hover", "CompactButton", ch)
	t.set_stylebox("pressed", "CompactButton", cp)
	t.set_color("font_color", "Label", PAPER)
	t.set_color("font_outline_color", "Label", INK)
	t.set_constant("outline_size", "Label", 2)
	var slider := StyleBoxFlat.new()
	slider.bg_color = Color("16292b")
	slider.content_margin_top = 2
	slider.content_margin_bottom = 2
	t.set_stylebox("slider", "HSlider", slider)
	var fill := StyleBoxFlat.new()
	fill.bg_color = TEAL
	fill.content_margin_top = 2
	fill.content_margin_bottom = 2
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	t.set_icon("grabber", "HSlider", _grabber(PAPER))
	t.set_icon("grabber_highlight", "HSlider", _grabber(TEAL))
	_theme = t
	return t


static func _button_box(bg: Color, edge: Color, compact: bool = false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = edge
	s.set_border_width_all(1)
	s.border_width_left = 3  # a heavier leading edge, like a tab on a file
	s.skew = Vector2(0.25, 0)  # slanted, GTA-style
	# Compact (settings rows): the same look, just short: almost no padding above and below.
	s.content_margin_left = 6 if compact else 10
	s.content_margin_right = 6 if compact else 10
	s.content_margin_top = 3 if compact else 5
	s.content_margin_bottom = 2 if compact else 4
	return s


static func _grabber(c: Color) -> ImageTexture:
	var img := Image.create(6, 10, false, Image.FORMAT_RGBA8)
	img.fill(c)
	for y in 10:
		img.set_pixel(0, y, INK)
		img.set_pixel(5, y, INK)
	return ImageTexture.create_from_image(img)


## A codec-style panel: dark fill, a chamfered top-right corner, a thin outline in `accent`, a
## brighter bar down the left and faint scanlines.
static func panel(ci: CanvasItem, r: Rect2, accent: Color = TEAL, fill: Color = PANEL, cut: float = 6.0) -> void:
	var p := r.position
	var e := r.end
	var pts := PackedVector2Array([p, Vector2(e.x - cut, p.y), Vector2(e.x, p.y + cut), e, Vector2(p.x, e.y)])
	ci.draw_colored_polygon(pts, fill)
	var y := p.y + 2.0
	while y < e.y - 1.0:
		ci.draw_line(Vector2(p.x + 2.0, y), Vector2(e.x - 1.0, y), Color(accent, 0.06), 1.0)
		y += 2.0
	pts.append(p)
	ci.draw_polyline(pts, Color(accent, 0.9), 1.0)
	ci.draw_rect(Rect2(p.x, p.y, 2.0, r.size.y), accent)


## A text label in the pixel font.
static func label(text: String, size: int = 8, color: Color = PAPER, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", 2 if size <= 8 else 3)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## A small padlock (5 x 7 px, like a letter; `scale` times that, like the 16 px text at 2), top left
## at `p`: the mission select's and the mission screen's locked settings.
static func draw_padlock(ci: CanvasItem, p: Vector2, c: Color, scale: int = 1) -> void:
	for px: Vector2i in PADLOCK:
		ci.draw_rect(Rect2(p + Vector2(px * scale), Vector2.ONE * scale), c)


## The padlock's pixels: its shackle (rows 0-2), then its body with a keyhole.
const PADLOCK: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0),
	Vector2i(1, 1), Vector2i(3, 1), Vector2i(1, 2), Vector2i(3, 2),
	Vector2i(0, 3), Vector2i(1, 3), Vector2i(2, 3), Vector2i(3, 3), Vector2i(4, 3),
	Vector2i(0, 4), Vector2i(1, 4), Vector2i(3, 4), Vector2i(4, 4),
	Vector2i(0, 5), Vector2i(1, 5), Vector2i(3, 5), Vector2i(4, 5),
	Vector2i(0, 6), Vector2i(1, 6), Vector2i(2, 6), Vector2i(3, 6), Vector2i(4, 6),
]
