class_name KoReplay
extends RefCounted
## The boss's KO replay (user: "Some similar to how old school 3d fight games like teken would show
## death animations from 3 different camera angles"): his death (GuardRig.pose_death) shown three
## times in slow motion: live, close up as the last hits land, then replayed low and side-on (the
## flight and the twists in profile), then from high up in front as the gun lands, he lands and his
## blood spreads.
##
## Each shot: the part of his death it shows (`from`, `to`: s on his death's own clock), how slow
## it plays (`scale`: the game's time scale), whether it's a replay, and its camera, in his space
## (m; he faces -Z, toward you, and +X is his right): where it is at the start and the end of the
## shot, what it looks at, how much it follows his body instead, and its field of view (vertical,
## degrees). The level plays them in turn.

const SHOTS := 3


static func shots(tuning: Tuning) -> Array[Dictionary]:
	return [
		{"name": "live", "from": 0.0, "to": 1.25, "scale": tuning.boss_ko_slow.x, "replay": false,
			"cam": [Vector3(-1.9, 1.55, -3.4), Vector3(-1.45, 1.35, -2.8)], "look": Vector3(0.0, 1.5, 0.0), "follow": 0.6, "fov": 55.0},
		{"name": "profile", "from": 0.05, "to": 1.25, "scale": tuning.boss_ko_slow.y, "replay": true,
			"cam": [Vector3(4.8, 0.75, -0.3), Vector3(4.8, 0.6, 1.6)], "look": Vector3(0.0, 0.9, 0.0), "follow": 1.0, "fov": 58.0},
		{"name": "above", "from": 0.4, "to": 2.2, "scale": tuning.boss_ko_slow.z, "replay": true,
			"cam": [Vector3(0.5, 3.65, -4.2), Vector3(0.45, 3.5, -3.7)], "look": Vector3(0.2, 0.2, 0.5), "follow": 0.0, "fov": 60.0},
	]


## How long a shot lasts (real s).
static func length(shot: Dictionary) -> float:
	return (float(shot["to"]) - float(shot["from"])) / float(shot["scale"])


## How far through `shot` his death is at `death_t` (0..1).
static func progress(shot: Dictionary, death_t: float) -> float:
	return clampf((death_t - float(shot["from"])) / (float(shot["to"]) - float(shot["from"])), 0.0, 1.0)


## The camera for `shot` at `u` (0..1 through it), with his body (his hips, his space) at `body`:
## in his space.
static func camera(shot: Dictionary, u: float, body: Vector3) -> Transform3D:
	var e := u * u * (3.0 - 2.0 * u)
	var at: Vector3 = (shot["cam"][0] as Vector3).lerp(shot["cam"][1], e)
	var look: Vector3 = (shot["look"] as Vector3).lerp(body + Vector3(0.0, 0.25, 0.0), float(shot["follow"]))
	return Transform3D(Basis.IDENTITY, at).looking_at(look, Vector3.UP)
