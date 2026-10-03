extends Node
## Records the route actually travelled in a run and what the player has
## discovered across runs. Feeds the post-run route map (LOCKED: show the path
## taken and where the run ended; the map grows through discovery).

const DISCOVERY_PATH := "user://discovery.json"
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
## end), so the route map shows only what he's seen. Persists between sessions.
var discovered: Dictionary = {}


func _ready() -> void:
	_load_discovery()


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
		"downed": n.call(["trooper_down", "dog_down", "runner_down"]),
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


func _load_discovery() -> void:
	if not FileAccess.file_exists(DISCOVERY_PATH):
		return
	var f := FileAccess.open(DISCOVERY_PATH, FileAccess.READ)
	var data: Variant = JSON.parse_string(f.get_as_text())
	if data is Array:  # the first format: the areas reached, all taken as seen to the end
		for id in data:
			discovered[StringName(id)] = FULL
	elif data is Dictionary:
		for id in data:
			var m = data[id]
			discovered[StringName(id)] = float(m) if (m is float or m is int) else FULL


func _save_discovery() -> void:
	var f := FileAccess.open(DISCOVERY_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("RunLog: could not save discovery (%s)" % FileAccess.get_open_error())
		return
	var out := {}
	for id in discovered.keys():
		out[String(id)] = float(discovered[id])
	f.store_string(JSON.stringify(out))
