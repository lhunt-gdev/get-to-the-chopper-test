extends Node
## Which missions and settings the player can play (the main menu's mission select), saved on the
## device beside the settings (user://progress.json; on the web, the browser's storage). Autoload
## "Progress".
##
## The unlock rule (user, 2026-10-09): "In the menu there needs to be a mission select where the
## player can click to see all missions but they can only select a mission they have unlocked ... if
## they play mission one easy they only unlock mission two easy and so on but if they play mission one
## hard the unlock mission two easy, medium and hard." And: "Mission 1 only has easy unlocked to start.
## And completing on medium will only unlock easy and medium for next level." So getting out
## (extracted) of mission N on a setting opens mission N+1 on that setting and every easier one; and,
## so a mission's harder settings can be reached at all, the next setting up of mission N itself
## (EASY opens its MEDIUM, MEDIUM its HARD). Nothing ever locks again.
##
## Best times (user, 2026-10-09: the mission screen "shows the 3 difficulty options with the players
## best time if it's been set"): for each mission and setting, the run time of his fastest
## extraction; only an extraction counts, and only a faster one replaces it. Auto-save (user: "I'd
## like the game to auto save itself after the player finishes a run"): record_run() is called as
## every run ends, whatever the ending, and writes the save at once (SaveFile: a temp file, then a
## rename; a failed write is a warning, never a stop).
##
## The scoreboards (the decision log's "Scoring and the scoreboard"): a local top 10 for each mission
## and setting, kept in the same save. The cast's entries (VESPER, BISHOP, CONDOR, VORHALT, ARDBALLS)
## aren't saved: they're in the mission's own data (route.json "house", made from real bot runs by
## tests/house/make_house.sh), so they can be remade without touching the player's scores, and a wiped
## save gives back the cast's boards. Only the player's own entries are saved, each with its name,
## score, ending, highest alert, date, the run's raw tally numbers and the score's version
## (Score.VERSION): an entry from another version is scored again from its numbers as it loads. Ties:
## the older entry stays above (the cast are older than anything of his). NEW BEST is against his own
## entries only.

const PATH := "user://progress.json"
## The nine missions, in order (the decision log's "The story"; act 1 the compound, act 2 the
## harbour, act 3 the city tower). Only those with a "route" are built; the rest show as COMING SOON.
const MISSIONS := [
	{"id": "cold_call", "name": "COLD CALL", "route": "res://game/levels/prototype_slice/route.json"},
	{"id": "short_leash", "name": "SHORT LEASH"},
	{"id": "dead_air", "name": "DEAD AIR"},
	{"id": "nothing_to_declare", "name": "NOTHING TO DECLARE"},
	{"id": "sea_legs", "name": "SEA LEGS"},
	{"id": "fire_sale", "name": "FIRE SALE"},
	{"id": "glass_house", "name": "GLASS HOUSE"},
	{"id": "lights_out", "name": "LIGHTS OUT"},
	{"id": "hot_exfil", "name": "HOT EXFIL"},
]
## What a fresh save has open: mission 1 on EASY, nothing else.
const FIRST := "1:easy"

## Where it's saved ("" keeps it in memory only: the bots, so a bot run never touches the player's).
var save_path := PATH
## "N:setting" -> true for each one open, and each one got out of at least once.
var _unlocked := {}
var _cleared := {}
## "N:setting" -> his best time there (s): the run time of his fastest extraction.
var _best := {}
## The last one picked in the mission select ("N:setting"), so it's where the select opens.
var last := FIRST
## "N:setting" -> his own entries on that board (the ones in its top 10 with the cast), best first.
var _boards := {}
## The name the name entry is filled in with: the last one he used (user: CROSS the first time).
var last_name := DEFAULT_NAME
## The next entry's number (entries are told apart, and ties ordered, by it: older first).
var _seq := 1
## The cast's entries from each mission's route file, by "N:setting" (read once).
var _house_cache := {}

## A board's size, the name the first entry is filled in with, the longest name, and the letters a
## name can have (the name entry's keys: A-Z, 0-9, space, full stop, hyphen).
const BOARD_SIZE := 10
const DEFAULT_NAME := "CROSS"
const NAME_MAX := 8
const NAME_CHARS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .-"
## ...and the cast's too.
const CAST_CHARS := NAME_CHARS + "?"
## The endings an entry can have (GameState's END_ ones).
const ENDINGS := ["extracted", "killed", "captured", "chopper_left", "dead_end"]


func _ready() -> void:
	load_from(save_path)


## "N:setting", the key a mission's setting is kept under.
static func key(n: int, setting: String) -> String:
	return "%d:%s" % [n, setting]


## The mission's number (1 to 9) by its id (route.json's "mission"); 0 if it isn't one (the TEST
## RANGE), which unlocks nothing.
static func mission_number(id: StringName) -> int:
	for i in MISSIONS.size():
		if StringName(MISSIONS[i]["id"]) == id:
			return i + 1
	return 0


## Whether mission n is built yet (its level exists); the rest are COMING SOON.
static func is_built(n: int) -> bool:
	return n >= 1 and n <= MISSIONS.size() and MISSIONS[n - 1].has("route")


## The unlock rule (see the top): what getting out of mission n on `setting` opens, as [n, setting]
## pairs, in order (this mission's next setting up first, then the next mission's, easiest first).
static func unlocks_after(n: int, setting: String) -> Array:
	var rank := RouteGraph.SETTINGS.find(setting)
	var out := []
	if rank < 0 or n < 1 or n > MISSIONS.size():
		return out
	if rank + 1 < RouteGraph.SETTINGS.size():
		out.append([n, RouteGraph.SETTINGS[rank + 1]])
	if n < MISSIONS.size():
		for i in rank + 1:
			out.append([n + 1, RouteGraph.SETTINGS[i]])
	return out


func is_unlocked(n: int, setting: String) -> bool:
	return _unlocked.has(key(n, setting))


func is_cleared(n: int, setting: String) -> bool:
	return _cleared.has(key(n, setting))


## Whether it can be played now: open, and its mission built.
func is_playable(n: int, setting: String) -> bool:
	return is_built(n) and is_unlocked(n, setting) and setting in RouteGraph.SETTINGS


## His best time on mission n on `setting` (s): his fastest extraction's run time; -1 if he's never
## got out there.
func best_time(n: int, setting: String) -> float:
	return float(_best.get(key(n, setting), -1.0))


## A run of mission n on `setting` has ended (`reason`: GameState's END_ ones), after `time` s:
## the auto-save (user), called as every run ends, whatever the ending. Got out (extracted): it's
## cleared, what the rule opens is opened, and the time is his best there if it's his first or
## faster than his best. Whatever the ending, the save is written now. Returns what the debrief
## needs: "unlocked" (what's newly open, [n, setting] pairs), "new_best" (bool), "best" (his best
## there now, -1 if none), "was" (his best before this run, -1 if none) and "saved" (whether it's
## on the device: false when kept in memory, or the write failed).
##
## With the run's tally (stats: Score's numbers, and "top_alert"), its score goes on the board too
## (add_score: under the name last used); then also "score" (the run's), "rank" (its place on the
## board, 1 to 10; 0 if it didn't make it), "seq" (the entry's number, for the name entry: rename),
## "new_best_score" (bool: beat his own best there, or his first score above 0) and "score_was"
## (his best score there before, -1 if none).
func record_run(n: int, setting: String, reason: StringName, time: float, stats: Dictionary = {}) -> Dictionary:
	var was := best_time(n, setting)
	var out := {"unlocked": [], "new_best": false, "best": was, "was": was}
	if not stats.is_empty():
		out.merge(add_score(n, setting, reason, stats))
	if reason == &"extracted" and _valid(n, setting):
		out["unlocked"] = _extract(n, setting)
		if is_finite(time) and time > 0.0 and (was < 0.0 or time < was):
			_best[key(n, setting)] = time
			out["new_best"] = true
			out["best"] = time
	out["saved"] = save()
	return out


## He got out of mission n on `setting` (no time: record_run is the game's): it's cleared, and what
## the rule opens is opened. Saved at once. Returns what's newly open ([n, setting] pairs).
func record_extraction(n: int, setting: String) -> Array:
	if not _valid(n, setting):
		return []
	var news := _extract(n, setting)
	save()
	return news


static func _valid(n: int, setting: String) -> bool:
	return n >= 1 and n <= MISSIONS.size() and setting in RouteGraph.SETTINGS


## Cleared, and what the rule opens opened (not saved): what's newly open.
func _extract(n: int, setting: String) -> Array:
	_cleared[key(n, setting)] = true
	_unlocked[key(n, setting)] = true  # (got out of it, so it's open)
	var news := []
	for pair in unlocks_after(n, setting):
		var k := key(pair[0], pair[1])
		if not _unlocked.has(k):
			_unlocked[k] = true
			news.append(pair)
	return news


## A run's score onto mission n's board on `setting` (not saved: record_run saves), under the name
## last used: what record_run says about it ("score", "rank", "seq", "new_best_score", "score_was").
func add_score(n: int, setting: String, reason: StringName, stats: Dictionary) -> Dictionary:
	var score := Score.total(stats, setting)
	var out := {"score": score, "rank": 0, "seq": 0, "new_best_score": false, "score_was": best_score(n, setting)}
	if not _valid(n, setting):
		return out
	var entry := {"name": last_name, "score": score, "ending": String(reason), "alert": clampi(int(stats.get("top_alert", 1)), 1, 3),
			"date": Time.get_date_string_from_system(), "raw": Score.raw_of(stats), "v": Score.VERSION, "seq": _seq}
	_seq += 1
	out["seq"] = entry["seq"]
	out["new_best_score"] = score > 0 and score > int(out["score_was"])
	var k := key(n, setting)
	var mine: Array = _boards.get(k, [])
	mine.append(entry)
	_boards[k] = mine
	_trim(n, setting)
	var top := board(n, setting)
	for i in top.size():
		if not top[i]["house"] and int(top[i]["seq"]) == int(entry["seq"]):
			out["rank"] = i + 1
	return out


## Mission n's board on `setting`: its top 10, the cast's entries and his together, best first (ties:
## the older above). Each entry: name, score, ending, alert (1 to 3), date, raw, v, seq, and "house"
## (true for the cast's).
func board(n: int, setting: String) -> Array:
	var all: Array = []
	for e in house(n, setting):
		var c: Dictionary = e.duplicate(true)
		c["house"] = true
		all.append(c)
	for e in _boards.get(key(n, setting), []):
		var c: Dictionary = e.duplicate(true)
		c["house"] = false
		all.append(c)
	all.sort_custom(_before)
	return all.slice(0, BOARD_SIZE)


## Board order: the higher score first; on a tie, the older entry (the cast's are older than his).
static func _before(a: Dictionary, b: Dictionary) -> bool:
	if int(a["score"]) != int(b["score"]):
		return int(a["score"]) > int(b["score"])
	return int(a["seq"]) < int(b["seq"])


## Keeps only his entries still on the board (pushed off by better ones, they're gone, as on an
## arcade machine).
func _trim(n: int, setting: String) -> void:
	var k := key(n, setting)
	if not _boards.has(k):
		return
	var keep := {}
	for e in board(n, setting):
		if not e["house"]:
			keep[int(e["seq"])] = true
	var mine: Array = _boards[k].filter(func(e: Dictionary) -> bool: return keep.has(int(e["seq"])))
	mine.sort_custom(_before)
	_boards[k] = mine


## His best score on mission n on `setting` (his own entries only; -1 if he has none there).
func best_score(n: int, setting: String) -> int:
	var best := -1
	for e in _boards.get(key(n, setting), []):
		best = maxi(best, int(e["score"]))
	return best


## Where a score would go on the board now (1 to 10; 0 if it wouldn't make it): below every entry
## it doesn't beat (ties: the older above).
func rank_for(n: int, setting: String, score: int) -> int:
	var top := board(n, setting)
	for i in top.size():
		if score > int(top[i]["score"]):
			return i + 1
	return top.size() + 1 if top.size() < BOARD_SIZE else 0


## The name entry's OK: his entry `seq` on that board is called `name` (cleaned: clean_name), and
## it's the name the next one is filled in with. Saved at once. False if there's no such entry.
func rename(n: int, setting: String, seq: int, name: String) -> bool:
	var clean := clean_name(name)
	if clean == "":
		clean = last_name
	var found := false
	for e in _boards.get(key(n, setting), []):
		if int(e["seq"]) == seq:
			e["name"] = clean
			found = true
	if found:
		last_name = clean
		save()
	return found


## A name as a board keeps it: capitals, only the name entry's letters (NAME_CHARS; and the cast's
## "?" for one of theirs), no spaces at either end, up to NAME_MAX; "" if nothing's left.
static func clean_name(name: Variant, cast := false) -> String:
	if not (name is String or name is StringName):
		return ""
	var out := ""
	for ch in String(name).to_upper():
		if (CAST_CHARS if cast else NAME_CHARS).contains(ch):
			out += ch
	return out.strip_edges().substr(0, NAME_MAX).strip_edges()


## The cast's entries on mission n's board on `setting` (route.json "house"), each scored from its
## raw numbers (Score: so they follow the points as they change); [] for a mission not built.
func house(n: int, setting: String) -> Array:
	var k := key(n, setting)
	if _house_cache.has(k):
		return _house_cache[k]
	var out: Array = []
	if is_built(n):
		var path := String(MISSIONS[n - 1]["route"])
		var data = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		if data is Dictionary and data.get("house") is Dictionary:
			out = house_entries(data["house"].get(setting, []), setting)
	_house_cache[k] = out
	return out


## A route file's cast entries for one setting, read as board entries (scored from their raw numbers;
## older than any of his: seq below 1, in the file's order); the broken ones left out.
static func house_entries(list: Variant, setting: String) -> Array:
	var out: Array = []
	if not list is Array:
		return out
	for i in list.size():
		var e = _entry_from(list[i], setting)
		if e != null:
			e["seq"] = i - list.size()
			out.append(e)
	return out


## One saved entry, checked, and scored again from its raw numbers when its version isn't this one
## (or it has no score); null if it can't be read.
static func _entry_from(e: Variant, setting: String) -> Variant:
	if not e is Dictionary or not e.get("raw") is Dictionary:
		return null
	var name := clean_name(e.get("name", ""), true)
	if name == "" or not String(e.get("ending", "")) in ENDINGS:
		return null
	var raw: Dictionary = Score.raw_of(e["raw"])
	var score := int(e["score"]) if (e.get("score") is int or e.get("score") is float) else -1
	if int(e.get("v", 0)) != Score.VERSION or score < 0:
		score = Score.total(raw, setting)
	return {"name": name, "score": score, "ending": String(e["ending"]), "alert": clampi(int(e.get("alert", raw["top_alert"])), 1, 3),
			"date": String(e.get("date", "")), "raw": raw, "v": Score.VERSION, "seq": int(e.get("seq", 0))}


## The mission select's pick, remembered so it opens there next time.
func remember_pick(n: int, setting: String) -> void:
	var k := key(n, setting)
	if k != last:
		last = k
		save()


## A fresh start: only mission 1 EASY.
func reset() -> void:
	from_data({})


## What's saved.
func to_data() -> Dictionary:
	var u := _unlocked.keys()
	var c := _cleared.keys()
	u.sort()
	c.sort()
	var b := {}
	for k in _best:
		b[k] = _best[k]
	var boards := {}
	for k in _boards:
		if not _boards[k].is_empty():
			boards[k] = _boards[k].duplicate(true)
	return {"version": 3, "unlocked": u, "cleared": c, "best": b, "last": last, "boards": boards, "name": last_name, "seq": _seq}


## From a save (as to_data gives it). Anything it can't read (a missing or broken file, a key that
## isn't "N:setting" for a real mission and setting, a best time that isn't a time) is left out, and
## mission 1 EASY is always open. A save from before best times (version 1: no "best") loads as it
## was, with no best times; one from before the scoreboards (versions 1 and 2: no "boards") with no
## scores of his (the cast's boards only). An entry it can't read is left out; one scored with
## another version of the points is scored again from its raw numbers.
func from_data(data: Variant) -> void:
	_unlocked.clear()
	_cleared.clear()
	_best.clear()
	_boards.clear()
	last = FIRST
	last_name = DEFAULT_NAME
	_seq = 1
	if data is Dictionary:
		for list in [["unlocked", _unlocked], ["cleared", _cleared]]:
			var keys = data.get(list[0])
			if keys is Array:
				for k in keys:
					if _valid_key(k):
						list[1][String(k)] = true
			var best = data.get("best")
			if best is Dictionary:
				for k in best:
					var t = best[k]
					if _valid_key(k) and (t is float or t is int) and is_finite(float(t)) and float(t) > 0.0:
						_best[String(k)] = float(t)
						_cleared[String(k)] = true  # (a best time is an extraction)
		if _valid_key(data.get("last")) and _unlocked.has(String(data["last"])):
			last = String(data["last"])
		var top := 0
		var boards = data.get("boards")
		if boards is Dictionary:
			for k in boards:
				if not _valid_key(k) or not boards[k] is Array:
					continue
				var mine: Array = []
				for e in boards[k]:
					var entry = _entry_from(e, String(k).get_slice(":", 1))
					if entry != null and int(entry["seq"]) >= 1:
						mine.append(entry)
						top = maxi(top, int(entry["seq"]))
				mine.sort_custom(_before)
				_boards[String(k)] = mine
		var seq = data.get("seq")
		_seq = maxi(top + 1, int(seq) if (seq is int or seq is float) else 1)
		var name := clean_name(data.get("name", ""))
		if name != "":
			last_name = name
	_unlocked[FIRST] = true
	for k in _cleared:  # (got out of it, so it was open)
		_unlocked[k] = true


static func _valid_key(k: Variant) -> bool:
	if not (k is String or k is StringName):
		return false
	var parts := String(k).split(":")
	return parts.size() == 2 and parts[0].is_valid_int() and int(parts[0]) >= 1 and int(parts[0]) <= MISSIONS.size() \
			and parts[1] in RouteGraph.SETTINGS


## Loads the save at `path` (a fresh start if there's none, or it's broken).
func load_from(path: String) -> void:
	save_path = path
	var data: Variant = null
	if SaveFile.exists(path):
		var json := JSON.new()  # (read quietly: a broken file is a fresh start, not an error)
		if json.parse(SaveFile.read_text(path)) == OK:
			data = json.data
		if not data is Dictionary:
			push_warning("Progress: %s couldn't be read; starting fresh (it's replaced at the next save)" % path)
	from_data(data)


## Writes the save now (SaveFile: safely). True if it's on the device; false when it's kept in
## memory only (the bots) or the write failed (a warning: the game goes on, the old save stays).
func save() -> bool:
	if save_path == "":
		return false
	return SaveFile.write_text(save_path, JSON.stringify(to_data()))
