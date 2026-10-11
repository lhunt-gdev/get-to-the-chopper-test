class_name Score
extends RefCounted
## A run's score, from its tally (the decision log's "Scoring and the scoreboard"; user, 2026-10-10:
## "The scoring for easy, medium and hard should be taken from the scores the player gets at the end
## or death of a run"). Pure: the same numbers always give the same score, so a saved entry's score
## can be worked out again from its raw numbers when the points change (VERSION).
##
## Every run scores, whatever the ending: 10 a metre run, 250 an enemy down (ARDBALLS counts as one),
## 500 an alarm stopped, less 500 an alarm set off. Only an escape adds 50,000 EXFIL, less 5,000 a hit
## taken, and 1,000 a second of chopper time to spare (100 a tenth). Then x the setting (user: EASY
## x1, MEDIUM x2, HARD x3); never below 0. Not scored: the run's time, things run into (each is
## already a hit), the alert level, the route, new areas found. Captured scores the same way as
## killed (user). The points are sized so any escape beats any failed run on the same board (band():
## a test proves it from every mission's route.json, on every setting).
##
## The numbers it reads (the tally's: Tally.rows_for): distance (m), downed, hits, alarms_set_off,
## alarms_stopped, spare (s of chopper time left; < 0 when he didn't get out).

## Bumped whenever a point value changes: saved entries with another version are scored again from
## their raw numbers (Progress).
const VERSION := 1
const PER_METRE := 10
const PER_DOWN := 250
const PER_STOPPED := 500
const PER_SET_OFF := 500
const EXFIL := 50000
const PER_HIT := 5000
## 1,000 a second of chopper time to spare, counted by the tenth (so ties are rare).
const PER_TENTH := 100
## The setting's multiplier (user: "EASY x1 MEDIUM x2 HARD x3"); a route without settings (the TEST
## RANGE) is x1.
const MULTIPLIER := {"easy": 1, "medium": 2, "hard": 3}
## The numbers an entry keeps (its raw tally), so its score can be worked out again.
const RAW_KEYS := ["distance", "downed", "hits", "alarms_set_off", "alarms_stopped", "spare", "time", "run_into", "top_alert"]


## Whole metres run (the office before the door is behind the start: never below 0).
static func metres(stats: Dictionary) -> int:
	return floori(maxf(0.0, float(stats.get("distance", 0.0))))


## Whether he got out (the tally has his spare chopper time only then).
static func escaped(stats: Dictionary) -> bool:
	return float(stats.get("spare", -1.0)) >= 0.0


## The chopper time to spare in tenths of a second (-1 if he didn't get out).
static func spare_tenths(stats: Dictionary) -> int:
	return roundi(float(stats["spare"]) * 10.0) if escaped(stats) else -1


## What one tally row adds to the score before the setting's multiplier (Tally rolls each in as it
## lands): DISTANCE, CHOPPER TO SPARE (the EXFIL and the seconds together: only an escape has the
## row), ENEMIES DOWN, HITS TAKEN (only off an escape), ALARMS SET OFF, ALARMS STOPPED; the other
## rows score nothing.
static func row_points(label: String, stats: Dictionary) -> int:
	match label:
		"DISTANCE":
			return PER_METRE * metres(stats)
		"CHOPPER TO SPARE":
			return EXFIL + PER_TENTH * spare_tenths(stats) if escaped(stats) else 0
		"ENEMIES DOWN":
			return PER_DOWN * int(stats.get("downed", 0))
		"HITS TAKEN":
			return -PER_HIT * int(stats.get("hits", 0)) if escaped(stats) else 0
		"ALARMS SET OFF":
			return -PER_SET_OFF * int(stats.get("alarms_set_off", 0))
		"ALARMS STOPPED":
			return PER_STOPPED * int(stats.get("alarms_stopped", 0))
	return 0


## The score before the setting's multiplier (can be below 0: total() floors it).
static func base(stats: Dictionary) -> int:
	var sum := 0
	for label in ["DISTANCE", "CHOPPER TO SPARE", "ENEMIES DOWN", "HITS TAKEN", "ALARMS SET OFF", "ALARMS STOPPED"]:
		sum += row_points(label, stats)
	return sum


static func multiplier(setting: String) -> int:
	return int(MULTIPLIER.get(setting, 1))


## The score: the setting's multiplier x the base, never below 0.
static func total(stats: Dictionary, setting: String) -> int:
	return multiplier(setting) * maxi(0, base(stats))


## The raw numbers a board entry keeps (whole metres, the spare time to the tenth).
static func raw_of(stats: Dictionary) -> Dictionary:
	var out := {}
	for k in RAW_KEYS:
		match k:
			"distance":
				out[k] = metres(stats)
			"spare":
				out[k] = spare_tenths(stats) / 10.0 if escaped(stats) else -1.0
			"time":
				out[k] = snappedf(float(stats.get("time", 0.0)), 0.1)
			"top_alert":
				out[k] = clampi(int(stats.get("top_alert", 1)), 1, 3)
			_:
				out[k] = maxi(0, int(stats.get(k, 0)))
	return out


## A score as the screens show it: "161,000".
static func format(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


## The band (the guarantee that any escape beats any failed run), worked out from a mission's route
## data on one setting: "fail_max", the most a run that didn't get out can score (the longest way to
## the pad, every enemy on it at any alert and the boss, every alarm box and alarm runner on it
## stopped, nothing set off), and "escape_min", the least an escape can score (the shortest way, no
## enemy down, every tripwire, searchlight and runner on it set off, a hit short of dying, no time to
## spare); both x the setting. `hits` is how many hits kill him (Tuning.player_hits). Also
## "longest" and "shortest" (m).
static func band(data: Dictionary, setting: String, hits: int) -> Dictionary:
	var d := RouteGraph.for_setting(data, setting) if data.get("settings") is Dictionary else data
	var nodes := {}
	for n: Dictionary in d.get("nodes", []):
		nodes[String(n["id"])] = n
	var paths: Array = []
	_paths(nodes, String(d.get("start", "")), [], paths)
	var fail_max := 0
	var escape_min := 1 << 40
	var longest := 0.0
	var shortest := INF
	for p: Array in paths:
		var length := 0.0
		var enemies := 1  # (the boss on the pad)
		var stoppable := 0
		var set_offs := 0
		for id: String in p:
			var n: Dictionary = nodes[id]
			length += float(n.get("length", 50.0))
			for e in n.get("enemies", []):
				enemies += 1
				if String(e.get("kind", "")) == "security_trooper":
					stoppable += 1  # (dropped before his panel)
					set_offs += 1   # (or he gets there)
			stoppable += n.get("alarms", []).size()
			set_offs += n.get("searchlights", []).size()
			for o in n.get("obstacles", []):
				if String(o.get("kind", "")) == "tripwire":
					set_offs += 1
		longest = maxf(longest, length)
		shortest = minf(shortest, length)
		fail_max = maxi(fail_max, PER_METRE * ceili(length) + PER_DOWN * enemies + PER_STOPPED * stoppable)
		escape_min = mini(escape_min, PER_METRE * floori(length) - PER_SET_OFF * set_offs + EXFIL - PER_HIT * (hits - 1))
	var m := multiplier(setting)
	return {"fail_max": m * fail_max, "escape_min": m * maxi(0, escape_min), "longest": longest, "shortest": shortest, "paths": paths.size()}


## Every way from `id` to an end (lists of area ids), whatever the alert.
static func _paths(nodes: Dictionary, id: String, so_far: Array, out: Array) -> void:
	if not nodes.has(id) or id in so_far:
		return
	var here := so_far + [id]
	var n: Dictionary = nodes[id]
	if String(n.get("end", "")) != "":
		out.append(here)
		return
	for e in n.get("next", []):
		_paths(nodes, String(e.get("to", "")), here, out)
