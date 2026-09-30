class_name ExtractionClock
extends Node
## The chopper's timeline: INBOUND -> LANDED -> LIFTING OFF -> GONE, on game time from the start
## of the run. The HUD shows it as an analog dial with a message under it; when the chopper is
## gone, the level ends the run (THE CHOPPER LEFT).
##
## Each mission can set its own timeline ("chopper" in its route.json); Tuning is the default.

signal stage_changed(stage: Stage)

enum Stage { INBOUND, LANDED, LIFTING_OFF, GONE }

const MESSAGES := {
	Stage.INBOUND: "CHOPPER INBOUND",
	Stage.LANDED: "CHOPPER LANDED",
	Stage.LIFTING_OFF: "CHOPPER LIFTING OFF",
	Stage.GONE: "",
}

@export var tuning: Tuning

## Seconds into the run. Set from Tuning by default; configure() applies a mission's own times.
var lands_at: float = 15.0
var lifts_at: float = 48.0
var gone_at: float = 58.0
var elapsed: float = 0.0
var stage: Stage = Stage.INBOUND
var running: bool = false


func _ready() -> void:
	if tuning:
		configure({})


## Uses the mission's timeline where it gives one ({lands_at, lifts_at, gone_at}), Tuning otherwise.
func configure(mission: Dictionary) -> void:
	lands_at = float(mission.get("lands_at", tuning.chopper_lands_at))
	lifts_at = float(mission.get("lifts_at", tuning.chopper_lifts_at))
	gone_at = float(mission.get("gone_at", tuning.chopper_gone_at))


## Which stage the chopper is at, t seconds into the run. Pure rule, so it's unit-tested.
static func stage_at(t: float, lands: float, lifts: float, gone: float) -> Stage:
	if t >= gone:
		return Stage.GONE
	if t >= lifts:
		return Stage.LIFTING_OFF
	if t >= lands:
		return Stage.LANDED
	return Stage.INBOUND


func start() -> void:
	elapsed = 0.0
	stage = Stage.INBOUND
	running = true
	stage_changed.emit(stage)


func stop() -> void:
	running = false


## 0 at the start of the run, 1 when the chopper is gone.
func fraction() -> float:
	return clampf(elapsed / gone_at, 0.0, 1.0)


## Where LIFTING OFF starts on the dial (0-1).
func lift_fraction() -> float:
	return lifts_at / gone_at


func _physics_process(delta: float) -> void:
	if not running:
		return
	elapsed += delta
	var s := stage_at(elapsed, lands_at, lifts_at, gone_at)
	if s != stage:
		stage = s
		stage_changed.emit(stage)
		if stage == Stage.GONE:
			running = false
