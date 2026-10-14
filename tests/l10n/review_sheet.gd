extends SceneTree
## The review sheet for a translation (the decision log's "Languages: Luxembourgish first"): every
## string of game/l10n/strings.csv, as a CSV and an HTML page for the native-speaker reviewer: its id,
## the English, the language's words so far, where it shows, the most letters it can have (from its
## _fit), and the note for the translator. The page is grouped by screen, with a short how-to at the
## top in English and the language, the jokes (a note starting "JOKE:") and the unsure lines (a note
## with "UNSURE") marked, and the words wanted outside the table (EXTRA: the HTML shell's TURN YOUR
## PHONE UPRIGHT picture) at the end. Runs headless:
##   godot --headless --path . -s res://tests/l10n/review_sheet.gd -- [--out=C:/somewhere] [--lang=lb] [--sync]
## It writes <lang>_review.csv and <lang>_review.html into docs/l10n (or --out). They're kept in the
## repo for the reviewer to open: run it again after a change to strings.csv or lb.csv. (docs/l10n has a
## .gdignore: Godot would otherwise import the review CSV as a translation.)
## --sync first brings the language's file (lb.csv) in line with strings.csv: an id new there gets an
## empty cell (the English shows until it's filled), one gone from there goes, and its words so far are
## kept, in strings.csv's order.

const NAMES := {"lb": "Lëtzebuergesch"}
const OUT := "res://docs/l10n"

## The screens the page groups the strings by: each id goes under the first group with a prefix it
## starts with (or a matching id); the last catches the rest.
const GROUPS := [
	{"title": "Main menu, pause menu and common buttons", "lb": "Haaptmenü, Paus a Knäpp", "ids": ["LANGUAGE_NAME", "MENU_", "COMMON_", "PAUSE_"]},
	{"title": "Settings", "lb": "Astellungen", "ids": ["SETTINGS_", "AIM_", "TRIGGER_", "SWIPE_", "MOVE_"]},
	{"title": "Controls", "lb": "Steierung", "ids": ["CONTROLS_"]},
	{"title": "Mission select and a mission's screen", "lb": "Missiounen", "ids": ["MISSION", "COMING_SOON", "SETTING_", "CHIP_"]},
	{"title": "Briefing and the end conversations (the jokes are here)", "lb": "Briefing an d'Gespréicher um Enn", "ids": ["BRIEF_", "M1_"]},
	{"title": "In the run: the HUD", "lb": "Am Spill: d'Uzeeg", "ids": ["HUD_"]},
	{"title": "In the run: the area names and the ways", "lb": "Am Spill: d'Zonen an d'Weeër", "ids": ["AREA_", "WAY_"]},
	{"title": "First-time tips", "lb": "Tipps fir den Ufank", "ids": ["TIP_"]},
	{"title": "Debrief (the end screen) and the scoreboard", "lb": "Bilan a Klassement", "ids": ["END_", "DEBRIEF_", "TALLY_", "SCORE_", "TIER_"]},
	{"title": "Name entry", "lb": "Numm aginn", "ids": ["NEW_ENTRY", "NAME_", "KEY_"]},
	{"title": "Credits, licences and the end of the demo", "lb": "Credits, Lizenzen an d'Enn vun der Demo", "ids": ["CREDITS_", "LICENCES_", "DEMO_"]},
	{"title": "iPhone: the save tip on the main menu", "lb": "iPhone: den Tipp fir de Spillstand", "ids": ["IOS_"]},
	{"title": "Everything else", "lb": "De Rescht", "ids": [""]},
]

## The how-to at the top of the page, in English and in the language.
const INTRO := {
	"en": "<p>Hello! This is every piece of text in HOT EXFIL, in English and in %s. To change a line, either edit the %s column in <b>%s_review.csv</b> (it opens in Excel or LibreOffice) and send the file back, or just write the corrections in a reply: the key (for example MENU_SETTINGS) and the new words.</p>"
		+ "<p>The screen is small: <b>max letters</b> says how many letters a line can have, spaces included (the game always shows capitals). Words in {braces} are filled in by the game: keep them. The names (CROSS, ARDBALLS, VESPER, BISHOP, CONDOR, VORHALT, HOT EXFIL) and the arrows ◀ ▶ ▲ ▼ stay as they are.</p>"
		+ "<p>The <span class=\"joke\">yellow</span> rows are jokes: the note says what the English joke is and what the %s version does. They were adapted, not translated word for word, so a funnier idea is always welcome. Rows marked <span class=\"tag unsure\">UNSURE</span> are the words the translation is least sure of.</p>",
	"lb": "<p>Moien! Hei sinn all d'Texter aus dem Spill HOT EXFIL, op Englesch an op Lëtzebuergesch. Fir eppes ze verbesseren, ännert entweder d'Kolonn „Lëtzebuergesch“ am Fichier <b>lb_review.csv</b> (e geet mat Excel oder LibreOffice op) a schéckt de Fichier zeréck, oder schreift d'Korrekturen einfach an eng Äntwert: de Schlëssel (z. B. MENU_SETTINGS) an den neien Text.</p>"
		+ "<p>De Bildschierm ass kleng: <b>max letters</b> seet, wéi vill Buschtawen eng Zeil héchstens hu kann, d'Espacen abegraff (d'Spill weist ëmmer Groussbuschtawen). Wierder an {Klameren} fëllt d'Spill selwer aus: loosst se stoen. D'Nimm (CROSS, ARDBALLS, VESPER, BISHOP, CONDOR, VORHALT, HOT EXFIL) an d'Feiler ◀ ▶ ▲ ▼ bleiwen esou.</p>"
		+ "<p>Déi <span class=\"joke\">giel</span> Zeile si Witzer: an der Notiz steet, wat de Witz op Englesch ass a wat déi lëtzebuergesch Versioun mécht. Si sinn ugepasst an net Wuert fir Wuert iwwersat, eng méi witzeg Iddi ass also ëmmer wëllkomm. Bei den Zeile mat <span class=\"tag unsure\">UNSURE</span> ass d'Iwwersetzung sech am mannste sécher.</p>",
}

## Words the language needs outside strings.csv (they aren't the game's text), shown at the end of
## the page: each its English, its words in the language, where and why.
const EXTRA := {
	"lb": [
		{"en": "TURN YOUR PHONE UPRIGHT", "words": "DRÉI DÄIN HANDY SENKRECHT",
			"where": "The web build's black screen when a phone is held sideways (a picture in the HTML shell: export_presets.cfg's head_include, made from these words). Not in the game's table: the picture is redrawn from these words later.",
			"note": "\"dréien\" = turn, \"senkrecht\" = upright, vertical (lod.lu); \"Handy\" = mobile phone. 25 letters, like the English (23)."},
	],
}


func _initialize() -> void:
	var out := ProjectSettings.globalize_path(OUT)
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
	var name: String = NAMES.get(lang, lang)
	var head := ["key", "English", name, "where it appears", "max letters", "note"]
	var rows := []
	for row in table:
		rows.append([row["keys"], row["en"], words.get(row["keys"], ""), row["_where"], most_letters(String(row["_fit"])), row["_note"]])
	var csv := FileAccess.open(out.path_join("%s_review.csv" % lang), FileAccess.WRITE)
	csv.store_buffer(PackedByteArray([0xEF, 0xBB, 0xBF]))  # (UTF-8's mark first, so Excel reads the accents right)
	csv.store_csv_line(PackedStringArray(head))
	for r in rows:
		csv.store_csv_line(PackedStringArray(r))
	csv.close()
	var html := FileAccess.open(out.path_join("%s_review.html" % lang), FileAccess.WRITE)
	html.store_string(_html(head, rows, lang))
	html.close()
	var filled := rows.filter(func(r: Array) -> bool: return String(r[2]) != "").size()
	print("review sheet: %d strings, %d in %s so far, in %s" % [rows.size(), filled, lang, out])
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


## The group (GROUPS) an id goes under.
static func group_of(id: String) -> int:
	for i in GROUPS.size():
		for p: String in GROUPS[i]["ids"]:
			if id.begins_with(p):
				return i
	return GROUPS.size() - 1


## The language's file, in line with strings.csv (see the top).
func _sync(table: Array, words: Dictionary, lang: String) -> void:
	var file := FileAccess.open(L10n.FILES[lang], FileAccess.WRITE)
	file.store_csv_line(PackedStringArray(["keys", lang]))
	for row in table:
		file.store_csv_line(PackedStringArray([row["keys"], words.get(row["keys"], "")]))
	file.close()
	print("review sheet: %s brought in line with strings.csv (%d ids)" % [L10n.FILES[lang], table.size()])


func _html(head: Array, rows: Array, lang: String) -> String:
	var name: String = NAMES.get(lang, lang)
	var out := PackedStringArray()
	out.append("<!doctype html>\n<html lang=\"%s\">\n<head>\n<meta charset=\"utf-8\">\n<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n<title>HOT EXFIL: %s review</title>" % [lang, name])
	out.append("<style>\n"
			+ "body { font-family: system-ui, sans-serif; margin: 16px auto; max-width: 1200px; padding: 0 16px; background: #fff; color: #111; line-height: 1.4; }\n"
			+ "h1 { margin-bottom: 4px; } h2 { margin-top: 32px; border-bottom: 2px solid #333; padding-bottom: 2px; } h2 small { font-weight: normal; color: #666; }\n"
			+ ".intro { display: grid; grid-template-columns: 1fr 1fr; gap: 24px; background: #f3f6f6; padding: 4px 16px; border-radius: 6px; }\n"
			+ "@media (max-width: 800px) { .intro { grid-template-columns: 1fr; } }\n"
			+ "nav { margin: 16px 0; } nav a { margin-right: 12px; white-space: nowrap; }\n"
			+ "table { border-collapse: collapse; width: 100%; font-size: 14px; }\n"
			+ "th, td { border: 1px solid #ccc; padding: 4px 6px; text-align: left; vertical-align: top; }\n"
			+ "th { background: #eee; }\n"
			+ "td.key { font-family: monospace; font-size: 11px; color: #555; word-break: break-all; width: 9em; }\n"
			+ "td.lang { font-weight: bold; } td.empty { background: #fde2e2; } td.max { white-space: nowrap; font-size: 12px; }\n"
			+ "td.where, td.note { font-size: 12px; color: #333; }\n"
			+ "tr.joke td, span.joke { background: #fff3b0; } tr.joke td.key { border-left: 4px solid #e0b000; }\n"
			+ ".tag { display: inline-block; font-size: 10px; font-weight: bold; padding: 0 4px; border-radius: 3px; margin-right: 4px; }\n"
			+ ".tag.joke { background: #e0b000; color: #000; } .tag.unsure { background: #d33; color: #fff; }\n"
			+ ".over { color: #c00; font-weight: bold; }\n"
			+ "</style>\n</head>\n<body>")
	out.append("<h1>HOT EXFIL: %s review sheet</h1>" % name)
	var jokes := rows.filter(func(r: Array) -> bool: return String(r[5]).contains("JOKE:")).size()
	var unsure := rows.filter(func(r: Array) -> bool: return String(r[5]).contains("UNSURE")).size()
	out.append("<p>%d lines, %d of them jokes, %d marked unsure.</p>" % [rows.size(), jokes, unsure])
	out.append("<div class=\"intro\"><div><h3>English</h3>%s</div><div><h3>%s</h3>%s</div></div>"
			% [INTRO["en"] % [name, name, lang, name], name, INTRO.get(lang, "")])
	var by_group := {}
	for r: Array in rows:
		var g := group_of(String(r[0]))
		if not by_group.has(g):
			by_group[g] = []
		by_group[g].append(r)
	var links := PackedStringArray()
	for g in GROUPS.size():
		if by_group.has(g):
			links.append("<a href=\"#g%d\">%s</a>" % [g, _esc(GROUPS[g]["title"])])
	if EXTRA.has(lang):
		links.append("<a href=\"#extra\">Words outside the game's table</a>")
	out.append("<nav>%s</nav>" % " · ".join(links))
	for g in GROUPS.size():
		if not by_group.has(g):
			continue
		out.append("<h2 id=\"g%d\">%s <small>/ %s</small></h2>" % [g, _esc(GROUPS[g]["title"]), _esc(GROUPS[g]["lb"]) if lang == "lb" else ""])
		out.append("<table>\n<tr>%s</tr>" % "".join(head.map(func(h: String) -> String: return "<th>%s</th>" % _esc(h))))
		for r: Array in by_group[g]:
			out.append(_row(r))
		out.append("</table>")
	if EXTRA.has(lang):
		out.append("<h2 id=\"extra\">Words outside the game's table <small>/ Texter ausserhalb vum Spill</small></h2>")
		out.append("<table>\n<tr><th>English</th><th>%s</th><th>where it appears</th><th>note</th></tr>" % _esc(name))
		for e: Dictionary in EXTRA[lang]:
			out.append("<tr><td>%s</td><td class=\"lang\">%s</td><td class=\"where\">%s</td><td class=\"note\">%s</td></tr>"
					% [_esc(e["en"]), _esc(e["words"]), _esc(e["where"]), _esc(e["note"])])
		out.append("</table>")
	out.append("</body>\n</html>\n")
	return "\n".join(out)


## A string's row: a joke's highlighted, an unsure one tagged; the words' length by the most it can
## have (a simple one-line limit only: the game's tests check the rest).
func _row(r: Array) -> String:
	var note := String(r[5])
	var joke := note.contains("JOKE:")
	var tags := ""
	if joke:
		tags += "<span class=\"tag joke\">JOKE</span>"
	if note.contains("UNSURE"):
		tags += "<span class=\"tag unsure\">UNSURE</span>"
	var words := String(r[2])
	var most := String(r[4])
	var count := ""
	if words != "":
		var n := words.length()
		count = "<br><span%s>now %d</span>" % [" class=\"over\"" if most.is_valid_int() and n > int(most) else "", n]
	return "<tr%s><td class=\"key\">%s</td><td>%s</td><td class=\"lang%s\">%s</td><td class=\"where\">%s</td><td class=\"max\">%s%s</td><td class=\"note\">%s%s</td></tr>" % [
			" class=\"joke\"" if joke else "", _esc(r[0]), _esc(r[1]), " empty" if words == "" else "", _esc(words), _esc(r[3]),
			_esc(most), count, tags, _esc(note)]


static func _esc(s: String) -> String:
	return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")
