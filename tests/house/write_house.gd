extends SceneTree
## Writes the cast's scoreboard entries into mission 1's route.json ("house"), from the bot runs
## make_house.sh collected (one JSON line each: scenario, setting, ending, raw). Run by make_house.sh:
##   godot --headless --path . -s res://tests/house/write_house.gd -- --runs=FILE [--dry]
## For each setting it picks ten (the decision log's "Scoring and the scoreboard": the board's ladder,
## so beating ARDBALLS comes first, getting out at all puts you in the top six, and beating VESPER
## means mastering the level):
##   VESPER   the bots' best escape, a touch under it (0.3 s less chopper time to spare)
##   ARDBALLS the best escape in the other style (user: "Replace ??? with ARDBALLS"; a different one each time) (quiet: never above SNEAKING, no alarm set off; loud:
##            the rest). Whoever flies the chopper: nobody knows who that is.
##   BISHOP   an escape with a hit (the boss's sweep)
##   VESPER   an escape with a stumble (a barrier run into)
##   CONDOR   an escape with an alarm set off and stopped (the lowest-scoring one, so the ladder spreads)
##   BISHOP   another escape (from cover)
##   VORHALT  a capture (the company puts its name on everything)
##   CONDOR   the chopper leaving with ARDBALLS still standing
##   BISHOP   killed half way
##   ARDBALLS derived, not a run: the board's floor, just over any run that dies in the first area
##            (its length and the pad's run, every guard in it down; killed, at ALERT), so a quick
##            death never makes the top 10. No failed run under it is used.
## A slot whose kind of run didn't happen on a setting takes the best run not used yet. No entry may
## score as much as VESPER: one that would has its spare time cut by tenths until it's under her
## (said in its "from"). Each entry keeps its bot's name and the raw tally ("raw"), so the game scores
## it again whenever the points change (Progress.house).

const ROUTE := "res://game/levels/prototype_slice/route.json"
const VESPER_TOUCH := 0.3


func _initialize() -> void:
	var runs_path := ""
	var dry := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--runs="):
			runs_path = a.get_slice("=", 1)
		elif a == "--dry":
			dry = true
	var runs: Array = []
	for line in FileAccess.get_file_as_string(runs_path).split("\n"):
		var r = JSON.parse_string(line) if line.strip_edges() != "" else null
		if r is Dictionary and String(r.get("route", "")) == "mission_1":
			runs.append(r)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROUTE))
	var pad := 30.0
	var first := {}
	for n in data["nodes"]:
		if String(n.get("end", "")) != "":
			pad = float(n.get("length", pad))
		if String(n.get("id", "")) == String(data.get("start", "")):
			first = n
	# The floor (ARDBALLS'): the first area run to its end and the pad's length on, every guard in it
	# down (the first area is the same on every setting: a route rule).
	var floor_raw := {"distance": float(first.get("length", 0.0)) + pad, "downed": (first.get("enemies", []) as Array).size()}
	var house := {}
	for setting: String in RouteGraph.SETTINGS:
		var mine := runs.filter(func(r: Dictionary) -> bool: return String(r["setting"]) == setting)
		house[setting] = pick(mine, setting, floor_raw)
		print("%s (%d runs):" % [setting.to_upper(), mine.size()])
		for e in house[setting]:
			print("  %-8s %9s  %-12s alert %d  from %s" % [e["name"], Score.format(e["score"]), e["ending"], e["alert"], e["from"]])
	if dry:
		quit(0)
		return
	var text := FileAccess.get_file_as_string(ROUTE)
	var lines := text.split("\n")
	var block := PackedStringArray(["  \"house\": {"])
	for i in RouteGraph.SETTINGS.size():
		var setting: String = RouteGraph.SETTINGS[i]
		block.append("    \"%s\": [" % setting)
		var list: Array = house[setting]
		for j in list.size():
			block.append("      " + JSON.stringify(list[j], "", false) + ("," if j < list.size() - 1 else ""))
		block.append("    ]" + ("," if i < RouteGraph.SETTINGS.size() - 1 else ""))
	block.append("  },")
	var at := lines.find("  \"house\": {")
	var out := PackedStringArray()
	if at >= 0:
		var close := at + 1
		while close < lines.size() and lines[close] != "  },":
			close += 1
		out = lines.slice(0, at)
		out.append_array(block)
		out.append_array(lines.slice(close + 1))
	else:
		var s := lines.find("  \"settings\": {")
		var close := s + 1
		while close < lines.size() and lines[close] != "  },":
			close += 1
		out = lines.slice(0, close + 1)
		out.append_array(block)
		out.append_array(lines.slice(close + 1))
	var f := FileAccess.open(ROUTE, FileAccess.WRITE)
	f.store_string("\n".join(out))
	f.close()
	var check = JSON.parse_string(FileAccess.get_file_as_string(ROUTE))
	print("wrote %s (%s)" % [ROUTE, "valid JSON" if check is Dictionary and check.get("house") is Dictionary else "BROKEN JSON"])
	quit(0 if check is Dictionary else 1)


## The ten for one setting (see the top), best first.
static func pick(runs: Array, setting: String, floor_raw: Dictionary) -> Array:
	# ARDBALLS (derived, not a run): the floor. No failed run under it is used.
	var ard := {"distance": float(floor_raw["distance"]), "downed": int(floor_raw["downed"]), "hits": 0, "alarms_set_off": 0, "alarms_stopped": 0,
			"spare": -1.0, "time": 0.0, "run_into": 0, "top_alert": 3}
	var ard_score := Score.total(ard, setting)
	var all: Array = []
	for r in runs:
		var raw := Score.raw_of(r["raw"])
		var score := Score.total(raw, setting)
		if String(r["ending"]) != "extracted" and score <= ard_score:
			continue
		all.append({"scenario": String(r["scenario"]), "ending": String(r["ending"]), "raw": raw, "score": score})
	all.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["score"] > b["score"])
	var used := {}
	var take := func(want: Callable, lowest := false) -> Variant:
		var order := all.duplicate()
		if lowest:
			order.reverse()
		for r in order:
			if not used.has(r["scenario"]) and want.call(r):
				used[r["scenario"]] = true
				return r
		return null
	var out: Array = []
	var out_of := func(r: Dictionary) -> bool: return r["ending"] == "extracted"
	var quiet := func(r: Dictionary) -> bool: return int(r["raw"]["top_alert"]) == 1 and int(r["raw"]["alarms_set_off"]) == 0
	var best = take.call(out_of)
	if best == null:
		push_error("no escape on %s: nothing to build the board on" % setting)
		return []
	var vesper := _entry("VESPER", best, setting, "")
	_cut_spare(vesper, setting, VESPER_TOUCH, "%.1f s less to spare" % VESPER_TOUCH)
	out.append(vesper)
	var best_quiet: bool = quiet.call(best)
	var slots := [
		["ARDBALLS", func(r: Dictionary) -> bool: return out_of.call(r) and quiet.call(r) != best_quiet],
		["BISHOP", func(r: Dictionary) -> bool: return out_of.call(r) and int(r["raw"]["hits"]) > 0 and int(r["raw"]["run_into"]) == 0],
		["VESPER", func(r: Dictionary) -> bool: return out_of.call(r) and int(r["raw"]["run_into"]) > 0],
		["CONDOR", func(r: Dictionary) -> bool: return out_of.call(r) and int(r["raw"]["alarms_set_off"]) > 0 and int(r["raw"]["alarms_stopped"]) > 0, "lowest"],
		["BISHOP", func(r: Dictionary) -> bool: return out_of.call(r) and r["scenario"] == "cover"],
		["VORHALT", func(r: Dictionary) -> bool: return r["ending"] == "captured"],
		["CONDOR", func(r: Dictionary) -> bool: return r["ending"] == "chopper_left"],
		["BISHOP", func(r: Dictionary) -> bool: return r["ending"] == "killed"],
	]
	for s in slots:
		var r = take.call(s[1], s.size() > 2)
		var note := ""
		if r == null:
			r = take.call(func(x: Dictionary) -> bool: return out_of.call(x) == ((s[0] as String) in ["ARDBALLS", "BISHOP", "VESPER", "CONDOR"] and out.size() < 6))
			note = "stand-in"
		if r == null:
			r = take.call(func(_x: Dictionary) -> bool: return true)
			note = "stand-in"
		if r == null:
			continue
		var e := _entry(s[0], r, setting, note)
		if int(e["score"]) >= int(vesper["score"]):
			var tenths := int(e["score"]) - int(vesper["score"])
			_cut_spare(e, setting, (floorf(tenths / float(Score.PER_TENTH * Score.multiplier(setting))) + 1.0) / 10.0, "under VESPER")
		out.append(e)
	out.append({"name": "ARDBALLS", "score": ard_score, "ending": "killed", "alert": 3, "from": "derived: the floor, over any death in the first area",
			"v": Score.VERSION, "raw": Score.raw_of(ard)})
	var last: Dictionary = out.pop_back()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["score"] > b["score"])
	out.append(last)
	return out


static func _entry(name: String, r: Dictionary, setting: String, note: String) -> Dictionary:
	var raw: Dictionary = r["raw"].duplicate()
	return {"name": name, "score": Score.total(raw, setting), "ending": r["ending"], "alert": int(raw["top_alert"]),
			"from": r["scenario"] + (" (%s)" % note if note != "" else ""), "v": Score.VERSION, "raw": raw}


## Takes `seconds` off an escape's spare chopper time (and onto its run time), rescoring it.
static func _cut_spare(e: Dictionary, setting: String, seconds: float, why: String) -> void:
	var raw: Dictionary = e["raw"]
	if float(raw["spare"]) < 0.0:
		return
	raw["spare"] = snappedf(maxf(0.0, float(raw["spare"]) - seconds), 0.1)
	raw["time"] = snappedf(float(raw["time"]) + seconds, 0.1)
	e["raw"] = Score.raw_of(raw)
	e["score"] = Score.total(e["raw"], setting)
	e["from"] = String(e["from"]) + " (%s)" % why if not String(e["from"]).contains("(") else String(e["from"]).trim_suffix(")") + ", %s)" % why
