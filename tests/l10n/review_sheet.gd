extends SceneTree
## The review sheet for a translation (the decision log's "Languages: Luxembourgish first"): every
## string of game/l10n/strings.csv, as a CSV and a simple HTML table: its id, the English, the
## language's words so far, where it shows, the most letters it can have (from its _fit), and the note
## for the translator. Runs headless:
##   godot --headless --path . -s res://tests/l10n/review_sheet.gd -- --out=C:/somewhere [--lang=lb] [--sync]
## --sync first brings the language's file (lb.csv) in line with strings.csv: an id new there gets an
## empty cell (the English shows until it's filled), one gone from there goes, and its words so far are
## kept, in strings.csv's order. The sheets themselves are made, not kept in the repo.

const NAMES := {"lb": "Lëtzebuergesch"}


func _initialize() -> void:
	var out := "user://l10n_review"
	var lang := "lb"
	var sync := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.get_slice("=", 1)
		elif a.begins_with("--lang="):
			lang = a.get_slice("=", 1)
		elif a == "--sync":
			sync = true
	if not L10n.FILES.has(lang):
		printerr("review sheet: no language '%s' (%s)" % [lang, ", ".join(L10n.FILES.keys())])
		quit(1)
		return
	var table := L10n.read_table(L10n.TABLE)
	var words := {}
	for row in L10n.read_table(L10n.FILES[lang]):
		words[row["keys"]] = String(row.get(lang, ""))
	if sync:
		_sync(table, words, lang)
	DirAccess.make_dir_recursive_absolute(out)
	var head := ["key", "English", "%s (current)" % NAMES.get(lang, lang), "where it appears", "max letters", "note for the translator"]
	var rows := []
	for row in table:
		rows.append([row["keys"], row["en"], words.get(row["keys"], ""), row["_where"], most_letters(String(row["_fit"])), row["_note"]])
	var csv := FileAccess.open(out.path_join("review_%s.csv" % lang), FileAccess.WRITE)
	csv.store_csv_line(PackedStringArray(head))
	for r in rows:
		csv.store_csv_line(PackedStringArray(r))
	csv.close()
	var html := FileAccess.open(out.path_join("review_%s.html" % lang), FileAccess.WRITE)
	html.store_string(_html(head, rows, lang))
	html.close()
	var filled := rows.filter(func(r: Array) -> bool: return String(r[2]) != "").size()
	print("review sheet: %d strings, %d in %s so far, in %s" % [rows.size(), filled, lang, ProjectSettings.globalize_path(out) if out.begins_with("user://") else out])
	quit()


## The most letters a string can have, in words, from its _fit (strings.csv): every letter of the
## pixel font is 6 px across at 8 px (12 at 16).
static func most_letters(fit: String) -> String:
	if fit == "brief":
		return "%d rows of %d, the speaker's [NAME] included" % [Briefing.ROWS, Briefing.COLS]
	if fit == "tag":
		return "%d (up to %d: the line count beside it then makes way)" % [Briefing.TAG_MOST, Briefing.TAG_LONGEST]
	var size := int(fit.get_slice(":", 0))
	var room := float(fit.get_slice(":", 1).get_slice("x", 0))
	var lines := int(fit.get_slice("x", 1)) if fit.contains("x") else 1
	var small := floori(room / 6.0)
	if size == 16:
		return "%d in big letters (up to %d: then in small ones)" % [floori(room / 12.0), small]
	if lines > 1:
		return "%d a line, %d lines at most" % [small, lines]
	return str(small)


## The language's file, in line with strings.csv (see the top).
func _sync(table: Array, words: Dictionary, lang: String) -> void:
	var file := FileAccess.open(L10n.FILES[lang], FileAccess.WRITE)
	file.store_csv_line(PackedStringArray(["keys", lang]))
	for row in table:
		file.store_csv_line(PackedStringArray([row["keys"], words.get(row["keys"], "")]))
	file.close()
	print("review sheet: %s brought in line with strings.csv (%d ids)" % [L10n.FILES[lang], table.size()])


func _html(head: Array, rows: Array, lang: String) -> String:
	var out := PackedStringArray()
	out.append("<!doctype html>\n<html lang=\"%s\">\n<head>\n<meta charset=\"utf-8\">\n<title>HOT EXFIL: %s review</title>" % [lang, NAMES.get(lang, lang)])
	out.append("<style>\nbody { font-family: sans-serif; margin: 16px; background: #fff; color: #111; }\n"
			+ "table { border-collapse: collapse; width: 100%; font-size: 14px; }\n"
			+ "th, td { border: 1px solid #ccc; padding: 4px 6px; text-align: left; vertical-align: top; }\n"
			+ "th { background: #eee; position: sticky; top: 0; }\n"
			+ "td:first-child { font-family: monospace; font-size: 12px; color: #555; }\n"
			+ "td.empty { background: #fff4d6; }\n</style>\n</head>\n<body>")
	out.append("<h1>HOT EXFIL: %s review sheet</h1>" % NAMES.get(lang, lang))
	out.append("<p>An empty %s cell shows the English in the game until it's filled. {Words in braces} are filled in by the game: keep them (the max letters count the whole line as shown, their words included). Names (CROSS, ARDBALLS, VESPER, BISHOP, CONDOR, VORHALT) and the arrows ◀ ▶ ▲ ▼ stay as they are.</p>" % NAMES.get(lang, lang))
	out.append("<table>\n<tr>%s</tr>" % "".join(head.map(func(h: String) -> String: return "<th>%s</th>" % _esc(h))))
	for r: Array in rows:
		var cells := PackedStringArray()
		for i in r.size():
			cells.append("<td%s>%s</td>" % [" class=\"empty\"" if i == 2 and String(r[i]) == "" else "", _esc(String(r[i]))])
		out.append("<tr>%s</tr>" % "".join(cells))
	out.append("</table>\n</body>\n</html>\n")
	return "\n".join(out)


static func _esc(s: String) -> String:
	return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")
