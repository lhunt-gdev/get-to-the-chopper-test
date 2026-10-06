class_name IntroCamera
extends RefCounted
## The camera before the run, in the route frame at the player (m; +X his right, -Z ahead, so it's
## in front of him at -Z): behind the main menu, in front of him swaying slowly from side to side;
## then the opening pan (GoldenEye N64 inspiration; user: "keep the current values") from in front
## of him round his right side to the play camera behind him. Static, so the tests use the game's
## own numbers.

## The menu's sway: how far round (rad, + his right) and how fast, how far out and how high the
## camera is (m), and the height it looks at (on a 480-high screen). Close in and looking a little
## high (user: "zoomed in on Cross a bit more ... moved down a little more so he is clear of the
## text"): a quarter bigger than at 3.3 m and 1.25 m, his head under the title's red rule.
const SWAY := 0.7
const SWAY_RATE := 0.22
const MENU_R := 2.75
const MENU_EYE := 1.55
const MENU_LOOK := 1.58
## The play camera's field of view (deg, vertical: the level's Camera3D), and the screen height
## the menu is laid out for (px: the game's base height; a phone only ever adds to it).
const FOV := 70.0
const MENU_H := 480.0
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


## Behind the menu, swayed `s`, the player `x` across, on a screen `h` px high: [eye, look, fov].
static func menu(s: float, x: float, h := MENU_H) -> Array:
	return [Vector3(x + sin(s) * MENU_R, MENU_EYE, -cos(s) * MENU_R), Vector3(x, menu_look(h), 0.0), menu_fov(h)]


## The menu camera's field of view on a screen `h` px high (deg, vertical). The menu's text is
## pinned to the top in px, but the view scales with the screen's height: so on a phone taller
## than MENU_H it opens up just enough to keep him the same size in px as on a 480-high screen.
static func menu_fov(h: float) -> float:
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(FOV / 2.0)) * maxf(h, MENU_H) / MENU_H))


## The height the menu camera looks at on a screen `h` px high: on a taller phone, tipped down so
## he's as far under the title as on a 480-high screen (the extra height shows floor under him).
static func menu_look(h: float) -> float:
	var tip := atan((maxf(h, MENU_H) - MENU_H) / 2.0 * tan(deg_to_rad(FOV / 2.0)) / (MENU_H / 2.0))
	return MENU_EYE - MENU_R * tan(atan((MENU_EYE - MENU_LOOK) / MENU_R) + tip)


## The opening pan `e` of the way round (its eased progress 0..1) on a screen `h` px high: [eye,
## look, fov]. It ends exactly on the play camera (`play_look`: where that looks; FOV). With
## `from_menu` > 0 it starts exactly where the menu's camera was (swayed `from_sway`, its view too)
## and eases onto the approved path over that much of the pan, never turning back (blended round
## him and out from him, so it only ever goes on round: from_menu 0.45 or more for the menu's
## widest sway); from there on it's exactly the approved path. 0: it starts in front of him (a cut
## from the menu).
static func pan(e: float, x: float, from_sway: float, from_menu: float, play_look: Vector3, h := MENU_H) -> Array:
	var m := 1.0 - smoothstep(0.0, from_menu, e) if from_menu > 0.0 else 0.0
	var a := PI * e
	var r := lerpf(PAN_R, PAN_R_END, e * e)
	var across := sin(a) * r * PAN_WIDE
	var along := cos(a) * r
	var round := atan2(across, along) + from_sway * m  # (how far round from straight in front: + his right)
	var out := Vector2(across, along).length() + (MENU_R - PAN_R) * m
	var eye := Vector3(x + sin(round) * out, lerpf(PAN_EYE, PAN_EYE_END, e) + (MENU_EYE - PAN_EYE) * m, -cos(round) * out)
	var look := Vector3(x, lerpf(PAN_LOOK, menu_look(h), m), 0.0).lerp(play_look, smoothstep(0.75, 1.0, e))
	return [eye, look, lerpf(FOV, menu_fov(h), m)]
