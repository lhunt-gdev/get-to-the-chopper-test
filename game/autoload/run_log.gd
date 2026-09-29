extends Node
## Records the route actually travelled in a run and what the player has
## discovered across runs. Feeds the post-run route map (LOCKED: show the path
## taken and where the run ended; the map grows through discovery).

const DISCOVERY_PATH := "user://discovery.json"

## Route node ids visited this run, in order.
var visited: Array[StringName] = []
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
	events.clear()
	end_reason = &""
	end_node = &""


func enter_node(id: StringName) -> void:
	visited.append(id)
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


func route_summary() -> String:
	var parts := PackedStringArray()
	for id in visited:
		parts.append(String(id).to_upper().replace("_", " "))
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
