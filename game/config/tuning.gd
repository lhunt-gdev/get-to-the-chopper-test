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
## The route is committed this many metres before the split. Small, so a last-minute lane
## change still counts: every open branch is already built.
@export var decision_lead: float = 1.0
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
## A side branch turns out for this many metres, then runs parallel to the main road.
@export var branch_out_length: float = 14.0
## A route heading for the end angles back toward the centre line, then runs straight for this long.
@export var converge_tail: float = 6.0
## How much of a locked-down branch you can see behind its door.
@export var locked_stub_length: float = 10.0
## How long a lockdown door takes to slam shut.
@export var lockdown_close_time: float = 0.7

@export_group("Chopper countdown")
## Seconds from the start of the run. INBOUND until it lands, LANDED until it starts lifting off,
## LIFTING OFF until it's gone. Reaching the helipad any time before it's gone extracts you.
@export var chopper_lands_at: float = 15.0
@export var chopper_lifts_at: float = 48.0
@export var chopper_gone_at: float = 58.0
## How long a stage's message stays under the clock (LIFTING OFF stays until the end).
@export var chopper_message_time: float = 3.0

@export_group("Intro")
## Length of the start room, and how far behind its door the player starts (metres).
@export var start_room_length: float = 14.0
@export var start_offset: float = 6.0
## How long the opening camera pan takes, front of the player round to behind.
@export var intro_pan_time: float = 3.5

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
## FIRE button radius as a fraction of screen width (bottom-right corner).
@export_range(0.06, 0.25) var fire_button_fraction: float = 0.13
## Seconds between shots while FIRE is held. Placeholder weapon: unlimited ammo.
@export var fire_interval: float = 0.2
## A tap within this many screen pixels of an enemy targets it (HYBRID / TAP_TO_TARGET).
@export var tap_target_radius_px: float = 28.0

@export_group("Damage (placeholder, Point 4 OPEN)")
@export_range(1, 10) var player_hits: int = 3
## Can't be hit again for this long after a hit.
@export var hit_invulnerable_time: float = 1.0

@export_group("Stumbles (placeholder, Point 4 OPEN)")
## Running into a jump/slide obstacle stuns you for this long (no swipes)...
@export var obstacle_stun_time: float = 0.5
## ...drops you to this fraction of run speed...
@export_range(0.1, 1.0) var obstacle_slow_factor: float = 0.5
## ...which recovers to full speed over this many seconds after the stun.
@export var obstacle_slow_recover: float = 1.2
## HP lost per stumble (0 = time cost only).
@export_range(0, 3) var obstacle_damage: int = 1
## After a stumble, other obstacles can't trip you for this long.
@export var obstacle_grace: float = 1.0

@export_group("Rifle Trooper")
@export var trooper_health: int = 2
## Starts aiming when you're this close (he only shoots forward, down the route at you).
@export var trooper_aim_range: float = 25.0
## Seconds from "!" to shot, at alert 1 / 2 / 3. Higher alert, less time to dodge.
@export var trooper_aim_time_alert1: float = 1.0
@export var trooper_aim_time_alert2: float = 0.8
@export var trooper_aim_time_alert3: float = 0.6
## Pause between one shot and aiming again.
@export var trooper_refire: float = 1.2
## Once an active trooper is this close (about as far as you can see through the fog), he stays,
## even if alert later drops below his level. No one vanishes in front of you.
@export var trooper_commit_distance: float = 40.0

@export_group("Cover")
## You stop this far in front of cover.
@export var cover_stop_gap: float = 0.7

@export_group("Alarm box")
## The box can be shot while it's between these distances ahead of you.
@export var alarm_window_near: float = 3.0
@export var alarm_window_far: float = 20.0
