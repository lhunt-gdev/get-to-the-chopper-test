extends SceneTree
## A sheet of the pixel font (UiKit.GLYPHS) to look at: every letter big on a grid (the accented
## capitals and the typeset punctuation among them), then Luxembourgish words in it at 4x, 2x and its
## own size, in the menus' colours. Runs headless (it draws the letters' pixels itself):
##   godot --headless --path . -s res://tests/l10n/glyph_sheet.gd -- --out=C:/somewhere/glyphs.png

const SAMPLES := [
	"LËTZEBUERGESCH ÄNNERUNGEN MÉI",
	"ÉIERT KËSCHT ÜBER BÖSCH FÊTE ÂGE",
	"ÇA VA? CÔTE DÛR ÎLE È",
	"„MOIEN“ «MERCI» D’SPILL – 1…9",
]
const INK := Color("050808")
const BACK := Color("081214")


func _initialize() -> void:
	var out := "user://glyphs.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.get_slice("=", 1)
	var chars: Array = UiKit.GLYPHS.keys()
	var cols := 16
	var big := 6
	var cell := Vector2i(8 * big, 11 * big)
	var rows := ceili(float(chars.size()) / cols)
	var height := 12 + rows * cell.y + 16
	for k in [4, 2, 1]:
		height += SAMPLES.size() * 11 * k + 12
	var img := Image.create(cols * cell.x + 24, height, false, Image.FORMAT_RGBA8)
	img.fill(BACK)
	# Every letter, big, on a grid (each cell's 5x7 box faint behind it, its rows under the line too).
	for i in chars.size():
		var at := Vector2i(12 + (i % cols) * cell.x, 12 + (i / cols) * cell.y)
		img.fill_rect(Rect2i(at, Vector2i(5 * big, 7 * big)), Color("102326"))
		_glyph(img, chars[i], at, big, UiKit.PAPER)
	var y := 12 + rows * cell.y + 16
	# Words in it: 4x, 2x and its own size, in the menus' paper and teal.
	for k in [4, 2, 1]:
		for line: String in SAMPLES:
			_text(img, line, Vector2i(12, y), k, UiKit.TEAL if k == 2 else UiKit.PAPER)
			y += 11 * k
		y += 12
	img.save_png(out)
	print("saved ", ProjectSettings.globalize_path(out) if out.begins_with("user://") else out)
	quit()


## Letter `ch` at `at` (its cell's top left), each pixel `k` across.
func _glyph(img: Image, ch: String, at: Vector2i, k: int, col: Color) -> void:
	var art: Array = UiKit.GLYPHS.get(ch, UiKit.GLYPHS.get(ch.to_upper(), []))
	for gy in art.size():
		for gx in 5:
			if String(art[gy])[gx] == "#":
				img.fill_rect(Rect2i(at + Vector2i(gx, gy) * k, Vector2i(k, k)), col)


## A line of text, from `at`, each pixel `k` across (6 a letter, as the font's advance).
func _text(img: Image, text: String, at: Vector2i, k: int, col: Color) -> void:
	for i in text.length():
		_glyph(img, text[i], at + Vector2i(i * 6 * k, 0), k, col)
