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
## Each lane is painted in its route's colour for this many metres before the decision point.
@export var fork_cue_length: float = 30.0
## LOCKED: junctions may slow the game but never pause it.
@export_range(0.4, 1.0) var junction_time_scale: float = 0.7

@export_group("Route splits")
## How far a side exit (corridor or stairs) turns off toward its side.
@export_range(0.0, 60.0) var fork_turn_degrees: float = 30.0
## Height between tiers (underground, ground, roof), in metres.
@export var tier_height: float = 4.0
## Stairs cover this many metres forward per metre of height.
@export var stairs_run: float = 3.0
## Ladders are a short, steep climb: this many metres forward.
@export var ladder_length: float = 3.0
## How much of each branch you can see before you commit.
@export var fork_preview_length: float = 30.0

@export_group("Capture")
## Missing the exit at a no-way-on end stops the player this far from the end.
@export var capture_stop_distance: float = 2.0
@export_range(1, 6) var capture_guards: int = 4
## Hands up, guards arrive, then the run ends after this many seconds.
@export var capture_duration: float = 1.8

@export_group("Shadows")
## How dark the centre of a blob shadow is (0 = none, 1 = black).
@export_range(0.0, 1.0) var shadow_opacity: float = 0.55
## How much of the shadow, from the edge in, is dithered away.
@export_range(0.05, 1.0) var shadow_softness: float = 0.5
## How far an obstacle's shadow spreads past its footprint, in metres.
@export var shadow_margin: float = 0.3
@export var player_shadow_size: float = 0.9
## The player's shadow shrinks to this scale at the top of a jump...
@export_range(0.1, 1.0) var player_shadow_min_scale: float = 0.5
## ...reached at this height in metres.
@export var player_shadow_fade_height: float = 2.0

@export_group("Combat")
@export var targeting_mode: TargetingMode = TargetingMode.HYBRID
@export var target_cone_degrees: float = 35.0
@export var target_range: float = 30.0
