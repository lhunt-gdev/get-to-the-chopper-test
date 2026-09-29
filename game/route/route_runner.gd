class_name RouteRunner
extends Node
## Walks the player through a RouteGraph as they run. It works out which segment
## they are in, shows junction choices, and commits the route choice from their lane.
## It knows nothing about meshes: the level listens to its signals and builds the world.

signal segment_needed(id: StringName, start_distance: float)
signal node_entered(id: StringName)
signal junction_approaching(options: Array[Dictionary])
signal junction_cleared
signal mission_end_reached(end_type: String)
signal dead_end_reached  ## Every exit was closed at the current alert level.

@export var tuning: Tuning

var graph: RouteGraph
var current: StringName = &""
var segment_start: float = 0.0

var _committed: StringName = &""
var _shown_labels: PackedStringArray = []
var _finished: bool = false


## spawn_first = false when the level already built the first segment (e.g. behind a title card).
func begin(g: RouteGraph, spawn_first: bool = true) -> void:
	graph = g
	_finished = false
	if spawn_first:
		segment_needed.emit(g.start_id, 0.0)
	_enter(g.start_id, 0.0)


func update(distance: float, player_lane: int) -> void:
	if _finished or graph == null:
		return
	var seg_len := graph.length_of(current)
	var into := distance - segment_start

	if graph.end_type(current) != "":
		if into >= seg_len:
			_finished = true
			mission_end_reached.emit(graph.end_type(current))
		return

	if _committed == &"":
		var decision_at := seg_len - tuning.decision_lead
		var opts := graph.available_next(current, GameState.alert_level)
		if into >= decision_at - tuning.approach_window:
			_show_if_changed(opts)
		if into >= decision_at:
			if opts.is_empty():
				_finished = true
				dead_end_reached.emit()
				return
			var idx := RouteGraph.pick_by_lane(player_lane, tuning.lane_count, opts.size())
			_committed = StringName(opts[idx]["to"])
			RunLog.record_event("choice", {"from": current, "to": _committed, "lane": player_lane})
			if not _shown_labels.is_empty():
				_shown_labels = []
				junction_cleared.emit()
			segment_needed.emit(_committed, segment_start + seg_len)

	if into >= seg_len and _committed != &"":
		_enter(_committed, segment_start + seg_len)


func _enter(id: StringName, start: float) -> void:
	current = id
	segment_start = start
	_committed = &""
	_shown_labels = []
	RunLog.enter_node(id)
	node_entered.emit(id)


func _show_if_changed(opts: Array[Dictionary]) -> void:
	if opts.size() < 2:
		if not _shown_labels.is_empty():
			_shown_labels = []
			junction_cleared.emit()
		return
	var labels := PackedStringArray()
	for o in opts:
		labels.append(String(o.get("label", o["to"])))
	if labels != _shown_labels:
		_shown_labels = labels
		junction_approaching.emit(opts)
