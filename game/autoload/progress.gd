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
func record_run(n: int, setting: String, reason: StringName, time: float) -> Dictionary:
	var was := best_time(n, setting)
	var out := {"unlocked": [], "new_best": false, "best": was, "was": was}
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
	return {"version": 2, "unlocked": u, "cleared": c, "best": b, "last": last}


## From a save (as to_data gives it). Anything it can't read (a missing or broken file, a key that
## isn't "N:setting" for a real mission and setting, a best time that isn't a time) is left out, and
## mission 1 EASY is always open. A save from before best times (version 1: no "best") loads as it
## was, with no best times.
func from_data(data: Variant) -> void:
	_unlocked.clear()
	_cleared.clear()
	_best.clear()
	last = FIRST
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
