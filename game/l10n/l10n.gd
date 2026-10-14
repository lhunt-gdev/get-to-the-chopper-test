class_name L10n
extends RefCounted
## The game's languages (the decision log's "Languages: Luxembourgish first"): ENGLISH and
## LËTZEBUERGESCH. Every player-facing string is looked up by a stable id in Godot's translation
## system: t("MENU_SETTINGS"). The table is strings.csv here (the id, the English, where it shows,
## how much room it has, a note for the translator); each other language is a CSV of its own (lb.csv:
## the id and the Luxembourgish), and Godot imports them into .translation files (project.godot's
## internationalization/locale/translations). English is the source and the fallback: an id with an
## empty cell in a language shows its English. Ids, not the English, are the keys: a line can be
## reworded without losing its translation (the review sheet shows both), the same English word can be
## two Luxembourgish ones, and an id never matches a name or a sign that a Label or Label3D would
## otherwise translate on its own.
##
## Text built from parts is one whole template with {named} places, filled in by f(): word order
## differs between languages. Not translated: the cast's names (CROSS, ARDBALLS, VESPER, BISHOP,
## CONDOR, VORHALT), the signs in the level (EXIT...), the players' own names, numbers and times, and
## the licence texts (LICENCES: they stay word for word).
##
## For testing fit there's a pseudo-language, PSEUDO ("xx"): every string about 35% longer and in
## accented capitals (pseudo()), so overflow and missing letters show. Never in SETTINGS: only
## use_pseudo() (the tests, tests/l10n/render_screens.gd) or the --pseudo-locale command-line argument
## turns it on.

## The languages a player can pick, each named in its own language (SETTINGS' LANGUAGE).
const LANGUAGES := {"en": "ENGLISH", "lb": "LËTZEBUERGESCH"}
## The source language (and the fallback), and the test-only pseudo-language.
const SOURCE := "en"
const PSEUDO := "xx"
## The table (the English, and the notes), and each language's file, by language.
const TABLE := "res://game/l10n/strings.csv"
const FILES := {"lb": "res://game/l10n/lb.csv"}
## The pseudo-language's accents: each plain capital's accented ones (taken in turn), and the letters
## it lengthens a word with.
const ACCENTED := {"A": "ÄÂ", "E": "ËÉÈÊ", "I": "Î", "O": "ÖÔ", "U": "ÜÛ", "C": "Ç"}
const LONGER := "ËÄÖÜÉÈÊÂÛÇÎÔ"
## How much longer the pseudo-language makes each word.
const PSEUDO_GROWTH := 0.35

static var _pseudo: Translation


## The string with this id in the current language (its English if it has none yet).
static func t(id: String) -> String:
	return String(TranslationServer.translate(id))


## The template with this id, its {named} places filled in from `args` ({"n": 2, "mission": ...}).
static func f(id: String, args: Dictionary) -> String:
	return t(id).format(args)


## Whether the table has this id (one made from data, like an area's, may not: the TEST RANGE's).
static func has(id: String) -> bool:
	return String(TranslationServer.translate(id)) != id


## The string with this id, or `fallback` if the table has none.
static func t_or(id: String, fallback: String) -> String:
	var s := t(id)
	return fallback if s == id else s


## A difficulty (RouteGraph.SETTINGS: "easy"...), in words; and its one letter (the mission select).
static func setting_name(setting: String) -> String:
	return t_or("SETTING_" + setting.to_upper(), setting.to_upper())


static func setting_letter(setting: String) -> String:
	return t_or("SETTING_%s_LETTER" % setting.to_upper(), setting.substr(0, 1).to_upper())


## The language a LANGUAGE setting means: the one picked ("en", "lb"), or while it's unset (or not one
## of LANGUAGES), the phone's own (detect()).
static func language_for(setting: String) -> String:
	return setting if LANGUAGES.has(setting) else detect()


## The phone's (or the computer's) language, as one of LANGUAGES: Luxembourgish for "lb" (lb, lb-LU),
## English for anything else. On the web it's the browser's (navigator.language), read through
## JavaScriptBridge; elsewhere the system's.
static func detect() -> String:
	var code := ""
	if OS.has_feature("web"):
		var got = JavaScriptBridge.eval("navigator.language || ''", true)
		code = String(got) if got is String else ""
	if code == "":
		code = OS.get_locale_language()
	return language_of(code)


## A locale code ("lb-LU", "en_GB", "de") as one of LANGUAGES (SOURCE for any other).
static func language_of(code: String) -> String:
	var lang := code.strip_edges().to_lower().replace("_", "-").get_slice("-", 0)
	return lang if LANGUAGES.has(lang) else SOURCE


## Shows the game in the language a LANGUAGE setting means (language_for), straight away (the screens
## rebuild themselves: Frontend). The --pseudo-locale command-line argument keeps it in PSEUDO.
static func apply(setting: String) -> void:
	if "--pseudo-locale" in OS.get_cmdline_user_args():
		use_pseudo()
		return
	TranslationServer.set_locale(language_for(setting))


## The language shown now ("en", "lb", or PSEUDO).
static func current() -> String:
	return TranslationServer.get_locale().get_slice("_", 0)


## Switches to the pseudo-language (made the first time from the English: pseudo()).
static func use_pseudo() -> void:
	if _pseudo == null:
		_pseudo = Translation.new()
		_pseudo.locale = PSEUDO
		var en := TranslationServer.get_translation_object(SOURCE)
		if en != null:
			for id in en.get_message_list():
				_pseudo.add_message(id, pseudo(String(en.get_message(id))))
		TranslationServer.add_translation(_pseudo)
	TranslationServer.set_locale(PSEUDO)


## Text in the pseudo-language: every A E I O U C in an accented capital (the ones the font has, taken
## in turn), each word PSEUDO_GROWTH longer with more of them; its {places}, symbols, numbers and line
## breaks as they were.
static func pseudo(text: String) -> String:
	var out := ""
	var word := 0  # letters in the word so far
	var turn := 0
	var i := 0
	while i <= text.length():
		var ch := text[i] if i < text.length() else ""
		var letter := ch != "" and ch.to_upper() != ch.to_lower()
		if not letter and word > 0:
			for k in roundi(word * PSEUDO_GROWTH):
				out += LONGER[(turn + k) % LONGER.length()]
			turn += 1
			word = 0
		if ch == "{":
			var close := text.find("}", i)
			if close > i:
				out += text.substr(i, close - i + 1)  # a {place}, as it is
				i = close + 1
				continue
		if letter:
			var up := ch.to_upper()
			var choices: String = ACCENTED.get(up, "")
			out += choices[turn % choices.length()] if choices != "" else up
			word += 1
		else:
			out += ch
		i += 1
	return out


## A table's rows (strings.csv, or a language's file), read straight from the CSV: each one a
## Dictionary of its columns by their names ("keys", "en", "_where"...), in order. (The tests and the
## review sheet; the game itself reads the imported translations.)
static func read_table(path: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return out
	var head := file.get_csv_line()
	while not file.eof_reached():
		var line := file.get_csv_line()
		if line.size() < 1 or (line.size() == 1 and line[0] == ""):
			continue
		var row := {}
		for c in head.size():
			row[head[c]] = line[c] if c < line.size() else ""
		out.append(row)
	return out
