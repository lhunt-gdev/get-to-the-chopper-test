class_name ExtractionClock
extends Node
## The chopper's timeline: INBOUND -> LANDED -> LIFTING OFF -> GONE, on game time from the start
## of the run. The HUD shows it as an analog dial with a message under it; when the chopper is
## gone, the level ends the run (THE CHOPPER LEFT).

signal stage_changed(stage: Stage)

enum Stage { INBOUND, LANDED, LIFTING_OFF, GONE }

const MESSAGES := {
	Stage.INBOUND: "CHOPPER INBOUND",
	Stage.LANDED: "CHOPPER LANDED",
	Stage.LIFTING_OFF: "CHOPPER LIFTING OFF",
	Stage.GONE: "",
}

@export var tuning: Tuning

var elapsed: float = 0.0
var stage: Stage = Stage.INBOUND
var running: bool = false


## Which stage the chopper is at, t seconds into the run. Pure rule, so it's unit-tested.
static func stage_at(t: float, tu: Tuning) -> Stage:
	if t >= tu.chopper_gone_at:
		return Stage.GONE
	if t >= tu.chopper_lifts_at:
		return Stage.LIFTING_OFF
	if t >= tu.chopper_lands_at:
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
	return clampf(elapsed / tuning.chopper_gone_at, 0.0, 1.0)


func _physics_process(delta: float) -> void:
	if not running:
		return
	elapsed += delta
	var s := stage_at(elapsed, tuning)
	if s != stage:
		stage = s
		stage_changed.emit(stage)
		if stage == Stage.GONE:
			running = false
