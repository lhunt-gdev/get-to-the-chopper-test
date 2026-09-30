extends Node
## Records the route actually travelled in a run and what the player has
## discovered across runs. Feeds the post-run route map (LOCKED: show the path
## taken and where the run ended; the map grows through discovery).

const DISCOVERY_PATH := "user://discovery.json"

## Route node ids visited this run, in order.
var visited: Array[StringName] = []
## What each visited area is called on screen (several route nodes can share a name, e.g. two
## stretches of ROOFTOPS).
var visited_names: PackedStringArray = []
## Timestamped gameplay events this run (alert changes, hits, choices...).
var events: Array[Dictionary] = []
var end_reason: StringName = &""
var end_node: StringName = &""
## Every node id the player has ever reached. Persists between sessions.
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
	visited.append(id)
	visited_names.append(display_name if display_name != "" else String(id).to_upper().replace("_", " "))
	if not discovered.has(id):
		discovered[id] = true
		record_event("discovered", {"node": id})
	record_event("enter", {"node": id})


func record_event(kind: String, data: Dictionary = {}) -> void:
	events.append({"t_ms": Time.get_ticks_msec(), "kind": kind, "data": data})


func finish(reason: StringName, at_node: StringName) -> void:
	end_reason = reason
	end_node = at_node
	record_event("end", {"reason": reason, "node": at_node})
	_save_discovery()


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
	if data is Array:
		for id in data:
			discovered[StringName(id)] = true


func _save_discovery() -> void:
	var f := FileAccess.open(DISCOVERY_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("RunLog: could not save discovery (%s)" % FileAccess.get_open_error())
		return
	var ids: Array[String] = []
	for id in discovered.keys():
		ids.append(String(id))
	f.store_string(JSON.stringify(ids))
