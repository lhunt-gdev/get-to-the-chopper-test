extends Node
## Global run state.
##
## LOCKED design rule: alert changes enemy pressure and can change which routes
## are open. No alert level is universally optimal.

signal alert_changed(level: int)
signal run_started
signal run_ended(reason: StringName)

const MIN_ALERT := 1
const MAX_ALERT := 3

## Why a run ended. Each should read clearly on the route map.
const END_EXTRACTED := &"extracted"
const END_KILLED := &"killed"
const END_CAPTURED := &"captured"
const END_CHOPPER_LEFT := &"chopper_left"

var alert_level: int = MIN_ALERT
var run_active: bool = false


func start_run(starting_alert: int = MIN_ALERT) -> void:
	alert_level = clampi(starting_alert, MIN_ALERT, MAX_ALERT)
	run_active = true
	RunLog.begin()
	run_started.emit()
	alert_changed.emit(alert_level)


func raise_alert() -> void:
	set_alert(alert_level + 1)


## Alarm boxes: current recommendation is a hit lowers alert by ONE level.
func lower_alert() -> void:
	set_alert(alert_level - 1)


func set_alert(level: int) -> void:
	level = clampi(level, MIN_ALERT, MAX_ALERT)
	if level == alert_level:
		return
	alert_level = level
	RunLog.record_event("alert", {"level": level})
	alert_changed.emit(level)


func end_run(reason: StringName, at_node: StringName) -> void:
	if not run_active:
		return
	run_active = false
	RunLog.finish(reason, at_node)
	run_ended.emit(reason)
