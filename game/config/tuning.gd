class_name Tuning
extends Resource
## Every number worth playtesting lives here, not in code.
## Edit res://game/config/default_tuning.tres in the Inspector.

enum TargetingMode {
	AUTO_PRIORITY,  ## Controls v1 as locked: FIRE hits the most urgent threat.
	TAP_TO_TARGET,  ## Proposal under test: tapping an enemy marks it as the target.
	HYBRID,         ## Auto-priority by default; a tap overrides until that target dies.
}

@export_group("Lanes")
## 5 is the proposal under test. Try 3 for comparison.
@export_range(3, 7, 2) var lane_count: int = 5
@export var lane_width: float = 1.4

@export_group("Run")
@export var run_speed: float = 11.0
@export var lane_change_speed: float = 14.0
@export var jump_velocity: float = 7.5
@export var gravity: float = 22.0
## Player feet must be above this to clear a low barrier.
@export var jump_clear_height: float = 0.6
@export var slide_duration: float = 0.6

@export_group("Swipe")
## Minimum swipe length as a fraction of screen width.
@export_range(0.02, 0.3) var swipe_min_fraction: float = 0.08
@export var tap_max_ms: int = 200

@export_group("Junctions")
## The route is committed this many metres before the segment ends.
@export var decision_lead: float = 18.0
## The junction prompt and slowdown start this far before the decision point.
@export var approach_window: float = 14.0
## LOCKED: junctions may slow the game but never pause it.
@export_range(0.4, 1.0) var junction_time_scale: float = 0.7

@export_group("Combat")
@export var targeting_mode: TargetingMode = TargetingMode.HYBRID
@export var target_cone_degrees: float = 35.0
@export var target_range: float = 30.0
