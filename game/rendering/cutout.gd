class_name Cutout
extends RefCounted
## The cutout (user: "anything in front of the camera between the lens and Cross is faded/dissolved
## out"): walls, furniture, cover, pillars, guards and glass between the camera and CROSS dissolve,
## PS1 screen-door style (psx_lit.gdshader and psx_glass.gdshader drop their pixels on a 4x4 ordered
## dither, the same hole: psx_cutout.gdshaderinc), so the camera can go anywhere and he always shows.
## CROSS himself never does (his materials opt out, his pistol and his hit flash too:
## SoldierRig.keep_solid), nor a guard's or a dog's body once he's down (SoldierRig.keep_solid,
## DogRig.keep_solid: it doesn't melt away as you run past it), nor the floor under him (the level's
## surfaces keep FLOOR; a guard or a dog standing between dissolves boots and all, with no floor rule
## for him: PsxMaterials.figure), nor anything beyond him, nor anything drawn in neither (the
## sky, glows, the stairs doors' arrows and padlock, Label3D, the UI). On under the
## menu, through the opening pan and on the play camera; off on the stairwells' security cameras and
## just out of a stairwell (the play camera is still back in it then, and leaving the stairwell out
## of the picture shows him better), in the boss's KO replay, and on the rear CCTV monitor (the
## shaders only cut for the camera it was set for). Looks only: line of sight, shots, the guards and
## the bots never see it.
##
## The user's pick: a round hole RADIUS m round his chest, 5 m across at his distance (it was 1.8 m
## across, the MEDIUM of the first options; seen in the game, the user found that too tight round
## him, and picked 5 m from bigger sizes in the same moments), the same size on screen whatever it
## cuts through (a cone from the lens), fully open in the middle and dithered over the outer EDGE of
## its radius. It goes with him: up with his jump, and down into a slide.

## The hole's middle: his chest, this high above his feet as he runs (m).
const CHEST := 1.25
## Its radius at his depth (m), and how much of that, at the outside, is dithered (a part of it).
const RADIUS := 2.5
const EDGE := 0.3
## How far in front of his chest the dissolve stops (his back, his pack: m), and the dithered fade
## nearer the lens than that (m), so what reaches past him (a wall alongside) has no hard line.
const MARGIN := 0.35
const DEPTH_FADE := 0.35
## Nothing of the level lower than this above his feet dissolves (the floor under him), jumping or
## not (m). The guards and the dogs have no such floor (PsxMaterials.figure).
const FLOOR := 0.06
## In a slide his body is down near the floor: the hole drops this far (m), eased over SLIDE_EASE s
## as he drops into it (and as he comes back up).
const SLIDE_DROP := 0.65
const SLIDE_EASE := 0.12
## Nearer the lens than this (m), it's off (there's nothing between to cut).
const MIN_DEPTH := 0.5

## The camera's shots (the level's _place_camera says which it set up).
enum Shot { PLAY, MENU, PAN, CCTV, JUST_OUT, KO }

## What it works out for the shader's globals (cutout_cam, cutout_fwd, cutout_misc: see
## psx_lit.gdshader), kept between frames (and read by the tests).
static var cam := Vector4.ZERO
static var fwd := Vector4.ZERO
static var misc := Vector4.ZERO
## Whether the shader was last told it's on (so, off, it's told just once).
static var _shown := false


## Whether `shot` takes it: the menu's camera, the opening pan and the play camera do; the
## stairwells' security cameras, the stretch just out of a stairwell and the KO replay don't.
static func on_for(shot: Shot) -> bool:
	return shot == Shot.PLAY or shot == Shot.MENU or shot == Shot.PAN


## How far into a slide the hole is, a frame on from `now` (0 standing .. 1 all the way down),
## eased over SLIDE_EASE s either way.
static func slide_toward(now: float, sliding: bool, delta: float) -> float:
	return move_toward(now, 1.0 if sliding else 0.0, delta / SLIDE_EASE)


## How far his chest is from where it is as he runs: up `jump_y` (his jump), down `slide` of the
## way into a slide.
static func lift(jump_y: float, slide: float) -> float:
	return jump_y - SLIDE_DROP * slide


## The middle of the hole: his chest, `lift` m up (or down) from where it is as he runs, over
## `feet` (his ground point; up is world up).
static func centre(feet: Vector3, lift_by: float) -> Vector3:
	return feet + Vector3.UP * (CHEST + lift_by)


## Works it out for this frame (cam, fwd, misc): the camera at `at`, CROSS standing at `feet`, his
## chest `lift_by` m from where it is as he runs (lift()). `on` false (or him right at the lens)
## turns it off. The floor rule goes by his feet, wherever his chest is.
static func aim(at: Vector3, feet: Vector3, on: bool, lift_by: float = 0.0) -> void:
	var mid := centre(feet, lift_by)
	var depth := at.distance_to(mid)
	if not on or depth < MIN_DEPTH:
		cam.w = 0.0
		return
	var way := (mid - at) / depth
	cam = Vector4(at.x, at.y, at.z, 1.0)
	fwd = Vector4(way.x, way.y, way.z, depth / RADIUS)
	misc = Vector4(feet.y + FLOOR, depth - MARGIN, 1.0 / DEPTH_FADE, 1.0 / EDGE)


## Sets it for this frame (aim()), and tells the shader.
static func apply(at: Vector3, feet: Vector3, on: bool, lift_by: float = 0.0) -> void:
	aim(at, feet, on, lift_by)
	if cam.w > 0.0:
		RenderingServer.global_shader_parameter_set(&"cutout_cam", cam)
		RenderingServer.global_shader_parameter_set(&"cutout_fwd", fwd)
		RenderingServer.global_shader_parameter_set(&"cutout_misc", misc)
		_shown = true
	elif _shown:
		RenderingServer.global_shader_parameter_set(&"cutout_cam", cam)
		_shown = false


## Turns it off (until the next apply()).
static func off() -> void:
	cam.w = 0.0
	RenderingServer.global_shader_parameter_set(&"cutout_cam", cam)
	_shown = false
