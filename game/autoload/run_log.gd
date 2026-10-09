extends Node
## Records the route actually travelled in a run and what the player has
## discovered across runs. Feeds the post-run route map (LOCKED: show the path
## taken and where the run ended; the map grows through discovery).

const DISCOVERY_PATH := "user://discovery.json"
## Each mission keeps its own map (the route map's discoveries kept per mission): mission 1's starts
## empty, and a save from before missions (one map for the old 19-area level, all of whose areas are
## the TEST RANGE's now) is filed under the test range, since those finds are of that layout.
const OLD_SAVE_MISSION := &"test_range"
## In `discovered`: an area he's seen to its end (gone on from it, or got out there).
const FULL := 1.0e6

## Route node ids visited this run, in order.
var visited: Array[StringName] = []
## What each visited area is called on screen (several route nodes can share a name, e.g. two
## stretches of ROOFTOPS).
var visited_names: PackedStringArray = []
## Timestamped gameplay events this run (alert changes, hits, choices...).
var events: Array[Dictionary] = []
var end_reason: StringName = &""
var end_node: StringName = &""
## Every area the player has ever reached, and how far into it he's got (m; FULL once he's seen its
## end), so the route map shows only what he's seen, for the mission being played (set_mission).
## Persists between sessions.
var discovered: Dictionary = {}
## Whose map `discovered` is (the route file's "mission"), and every mission's: {mission: {id: m}}.
var mission: StringName = &""
var _by_mission: Dictionary = {}
## Where the maps are saved ("" keeps them in memory only). Written as every run ends (finish).
var save_path := DISCOVERY_PATH


func _ready() -> void:
	load_from(save_path)


## Every mission's map from the save at `path` (none there, or broken: nothing found yet), saved
## there from now on ("" keeps them in memory only: the bots, so a bot run never touches the
## player's).
func load_from(path: String) -> void:
	save_path = path
	var data: Variant = null
	if SaveFile.exists(path):
		var json := JSON.new()  # (read quietly: a broken file is an empty map, not an error)
		if json.parse(SaveFile.read_text(path)) == OK:
			data = json.data
	load_saved(data)


## The mission being played, so the areas found are its own: the same area id in another mission
## (a zone moved on to mission 2 keeps its id) is a find of that mission's, not this one's.
func set_mission(id: StringName) -> void:
	_by_mission[mission] = discovered
	mission = id
	if not _by_mission.has(id):
		_by_mission[id] = {}
	discovered = _by_mission[id]


func begin() -> void:
	visited.clear()
	visited_names.clear()
	events.clear()
	end_reason = &""
	end_node = &""


func enter_node(id: StringName, display_name: String = "") -> void:
	if not visited.is_empty():
		discovered[visited[-1]] = FULL  # he went on from it, so he saw its end
	visited.append(id)
	visited_names.append(display_name if display_name != "" else String(id).to_upper().replace("_", " "))
	if not discovered.has(id):
		discovered[id] = 0.0
		record_event("discovered", {"node": id})
	record_event("enter", {"node": id})


func record_event(kind: String, data: Dictionary = {}) -> void:
	events.append({"t_ms": Time.get_ticks_msec(), "kind": kind, "data": data})


## The run's over, `into` metres into `at_node` (all of it if he got out).
func finish(reason: StringName, at_node: StringName, into: float = 0.0) -> void:
	end_reason = reason
	end_node = at_node
	if discovered.has(at_node):
		discovered[at_node] = maxf(float(discovered[at_node]), FULL if reason == &"extracted" else into)
	record_event("end", {"reason": reason, "node": at_node})
	_save_discovery()


## The run's numbers for the end screen's tally, counted from this run's events: enemies down,
## hits taken, things run into (obstacles stumbled into, dog trips), alarms set off (tripwires,
## searchlights, alarm runners who got away), alarms stopped (alarm boxes shot, runners dropped on
## their way, before they reached their panel),
## the highest alert, and the areas reached for the first time.
func tally() -> Dictionary:
	var n := func(kinds: Array) -> int: return events.filter(func(e: Dictionary) -> bool: return e["kind"] in kinds).size()
	var top := 1
	var new_areas := {}
	for e in events:
		if e["kind"] == "alert":
			top = maxi(top, int(e["data"].get("level", 1)))
		elif e["kind"] == "discovered":
			new_areas[StringName(e["data"].get("node", ""))] = true
	return {
		"downed": n.call(["trooper_down", "dog_down", "runner_down", "boss_down"]),
		"hits": n.call(["player_hit"]),
		"run_into": n.call(["stumble"]),
		"alarms_set_off": n.call(["tripwire", "searchlight", "runner_alarm"]),
		"alarms_stopped": n.call(["alarm_hit", "runner_stopped"]),
		"top_alert": top,
		"new_areas": new_areas.size(),
		"new_area_ids": new_areas,
	}


## The route as the player saw it: area names, with back-to-back repeats (one area in several
## stretches) shown once.
func route_summary() -> String:
	var parts := PackedStringArray()
	for n in visited_names:
		if parts.is_empty() or parts[-1] != n:
			parts.append(n)
	return " > ".join(parts)


## Every mission's map from a save (as save_data() gives it): {"missions": {mission: {id: metres}}};
## or a save from before missions, one map (the old level's), filed under the test range.
func load_saved(data: Variant) -> void:
	_by_mission.clear()
	if data is Dictionary and data.get("missions") is Dictionary:  # each mission's own map
		for m_id in data["missions"]:
			_by_mission[StringName(m_id)] = _areas_from(data["missions"][m_id])
	elif data is Array or data is Dictionary:  # one map, from before missions: the test range's
		_by_mission[OLD_SAVE_MISSION] = _areas_from(data)
	if not _by_mission.has(mission):
		_by_mission[mission] = {}
	discovered = _by_mission[mission]


## One mission's map as saved: {id: metres}, or (the first format) a list of the areas reached, all
## taken as seen to their end.
static func _areas_from(data: Variant) -> Dictionary:
	var out := {}
	if data is Array:
		for id in data:
			out[StringName(id)] = FULL
	elif data is Dictionary:
		for id in data:
			var m = data[id]
			out[StringName(id)] = float(m) if (m is float or m is int) else FULL
	return out


## What's saved: every mission's map that has anything on it.
func save_data() -> Dictionary:
	_by_mission[mission] = discovered
	var missions := {}
	for m_id in _by_mission:
		var areas := {}
		for id in _by_mission[m_id]:
			areas[String(id)] = float(_by_mission[m_id][id])
		if not areas.is_empty():
			missions[String(m_id)] = areas
	return {"missions": missions}


## Writes every mission's map now (SaveFile: safely; a failed write is a warning). True if it's on
## the device.
func _save_discovery() -> bool:
	if save_path == "":
		return false
	return SaveFile.write_text(save_path, JSON.stringify(save_data()))
