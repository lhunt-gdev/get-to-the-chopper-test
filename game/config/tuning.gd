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
## Branches you didn't take stay as scenery until you're this far past the split (no pop-out).
@export var fork_scenery_keep: float = 45.0
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
## FIRE BUTTON side (a setting, not tuning): true puts it bottom left.
var fire_on_left := false
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

@export_group("Ambience")
## Overall brightness: scales every area's ambient light, moonlight and lamps (1 = as authored).
## Playtest (user): 1.0 was a little hard to see things.
@export_range(0.5, 2.0, 0.05) var brightness: float = 1.5
## Lamps further than this from where the camera looks fade out (hidden in the fog).
@export var lamp_fade_far: float = 34.0
## How fast the lamps and screen edges pulse red at ALERT.
@export var alert_pulse_speed: float = 5.0
## Metres between office ceiling lights / tunnel wall lamps / rooftop lamp posts.
@export var office_lamp_spacing: float = 7.0
@export var tunnel_lamp_spacing: float = 8.0
@export var roof_lamp_spacing: float = 18.0
## Every how-many-th lamp is a failing one that flickers.
@export var flicker_every: int = 5
## Seconds the letterbox bars take to slide away when the run starts.
@export var letterbox_time: float = 0.5

@export_group("Audio")
## Loudness of each part of the mix, in dB (0 = as built).
@export var sfx_volume_db: float = 0.0
@export var ambience_volume_db: float = -16.0  # playtest (user): -8 was far too loud
@export var music_volume_db: float = -6.0
@export var ui_volume_db: float = -4.0
## Metres run between footsteps.
@export var stride: float = 3.0

@export_group("Rusher")
## How close you get (m) before the dog barks, at alert 1; it's this much further at each level up.
@export var rusher_trigger_distance: float = 22.0
@export var rusher_trigger_per_alert: float = 3.0
## Seconds it barks before it charges (your warning to dodge), by alert level.
@export var rusher_windup_alert1: float = 0.6
@export var rusher_windup_alert2: float = 0.45
@export var rusher_windup_alert3: float = 0.35
## How fast it sprints at you (m/s; you're running at it too).
@export var rusher_speed: float = 10.0

@export_group("Security Trooper")
## How close you get (m) before the alarm runner spots you and runs for it: further than you can
## shoot (target_range), so you have to close in on him.
@export var security_trigger_distance: float = 40.0
## How far (m, route distance) he runs from where he spotted you to the alarm: about two sections.
@export var security_alarm_distance: float = 230.0
## How fast he sprints (m/s). A little slower than you, so you slowly close in (walls, bends,
## stumbles and cover lose you ground).
@export var security_speed: float = 10.0
## Seconds he takes to turn and go after he's spotted you (the "!").
@export var security_startle_time: float = 0.25
## Hits to bring him down.
@export var security_health: int = 2

@export_group("Squad")
## How far behind you (m) the Alert 3 squad starts. They run at your run speed, so they only
## gain on you when you slow down (cover, stumbles, bites).
@export var squad_start_gap: float = 25.0
## How close (m) one of them has to get to grab you: CAPTURED.
@export var squad_catch_distance: float = 1.2
## The chance (0..1) a squad guard spots cover coming up in his lane and swerves round it.
## Otherwise he runs into it and he's out.
@export_range(0.0, 1.0) var squad_dodge_chance: float = 0.85
## The chance (0..1) a squad guard times a jump (barrier) or a slide (pipe) right. Otherwise he
## trips over it or runs into it, and he's out.
@export_range(0.0, 1.0) var squad_timing_chance: float = 0.9
## The rear-view CCTV's picture size (pixels; it's scaled up 1:1 in a small monitor under the clock).
@export var squad_cctv_size: Vector2i = Vector2i(128, 72)

@export_group("Sniper")
## How long his laser follows you before it locks (s; user: "for a second").
@export var sniper_track_time: float = 1.0
## How fast it slides after you across the lanes while following (m/s; a lane change is 14).
@export var sniper_follow_speed: float = 7.0
## Your window to dodge once it's locked (s), at CAUTION and at ALERT (LOCKED: alert changes the
## pressure).
@export var sniper_window_alert2: float = 0.6
@export var sniper_window_alert3: float = 0.45
## Where his nest is from his spot: how far straight on, out to the side and up (m): far enough on
## that he stays in view while he follows you and locks on, even on a tall phone screen.
@export var sniper_nest_ahead: float = 75.0
@export var sniper_nest_out: float = 15.0
@export var sniper_nest_up: float = 7.0
