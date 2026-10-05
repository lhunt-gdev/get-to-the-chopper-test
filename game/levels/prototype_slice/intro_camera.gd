class_name IntroCamera
extends RefCounted
## The camera before the run, in the route frame at the player (m; +X his right, -Z ahead, so it's
## in front of him at -Z): behind the main menu, in front of him swaying slowly from side to side;
## then the opening pan (GoldenEye N64 inspiration; user: "keep the current values") from in front
## of him round his right side to the play camera behind him. Static, so the tests use the game's
## own numbers.

## The menu's sway: how far round (rad, + his right) and how fast, how far out and how high the
## camera is (m), and the height it looks at.
const SWAY := 0.7
const SWAY_RATE := 0.22
const MENU_R := 3.3
const MENU_EYE := 1.55
const MENU_LOOK := 1.25
## The pan: how far out it starts and ends, how wide its arc is (of that, across), its height from
## start to end, and the height it looks at until it turns to look ahead (over the last quarter).
const PAN_R := 3.0
const PAN_R_END := 5.5
const PAN_WIDE := 0.75
const PAN_EYE := 1.5
const PAN_EYE_END := 3.4
const PAN_LOOK := 1.3


## Where the menu's sway has got to (rad), `t` s in.
static func sway(t: float) -> float:
	return SWAY * sin(t * SWAY_RATE)


## Behind the menu, swayed `s`, the player `x` across: [eye, look].
static func menu(s: float, x: float) -> Array:
	return [Vector3(x + sin(s) * MENU_R, MENU_EYE, -cos(s) * MENU_R), Vector3(x, MENU_LOOK, 0.0)]


## The opening pan `e` of the way round (its eased progress 0..1): [eye, look]. It ends exactly on
## the play camera (`play_look`: where that looks). With `from_menu` > 0 it starts exactly where the
## menu's camera was (swayed `from_sway`) and eases onto the approved path over that much of the
## pan, never turning back (blended round him and out from him, so it only ever goes on round:
## from_menu 0.45 or more for the menu's widest sway); from there on it's exactly the approved path.
## 0: it starts in front of him (a cut from the menu).
static func pan(e: float, x: float, from_sway: float, from_menu: float, play_look: Vector3) -> Array:
	var m := 1.0 - smoothstep(0.0, from_menu, e) if from_menu > 0.0 else 0.0
	var a := PI * e
	var r := lerpf(PAN_R, PAN_R_END, e * e)
	var across := sin(a) * r * PAN_WIDE
	var along := cos(a) * r
	var round := atan2(across, along) + from_sway * m  # (how far round from straight in front: + his right)
	var out := Vector2(across, along).length() + (MENU_R - PAN_R) * m
	var eye := Vector3(x + sin(round) * out, lerpf(PAN_EYE, PAN_EYE_END, e) + (MENU_EYE - PAN_EYE) * m, -cos(round) * out)
	var look := Vector3(x, lerpf(PAN_LOOK, MENU_LOOK, m), 0.0).lerp(play_look, smoothstep(0.75, 1.0, e))
	return [eye, look]
