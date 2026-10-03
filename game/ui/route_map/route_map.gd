class_name RouteMap
extends Control
## The post-run route map (LOCKED: show the route travelled and where the run ended, and let the
## map grow through discovery; the design is the user's, see "Post-run route map and tally" in the
## decision log). A side-on profile of the mission: left to right is distance along the route, up
## and down are its three levels (roof, main, below), and the stairs and ladders are the slopes
## between them.
##  - This run: a bright line, drawn in from the start, with a dot where each area ends, finishing
##    on a skull (killed or captured), a chopper (got out) or a faded chopper (it left without him).
##  - Areas found on earlier runs (saved between sessions): a faint line.
##  - Areas never reached aren't drawn, and an area is only drawn as far as he's ever got into it.
##    Where a way off an area he's seen the end of leads somewhere never reached, a short stub
##    toward its level ends in a lock (user): it shows a way exists, not where it goes.

## How long the run's line takes to draw in (s).
const DRAW_TIME := 1.0
## Pixels between one level and the next, and the left margin for their names.
const TIER_GAP := 22.0
const LABEL_W := 34.0
## A stair or ladder's width on the map (px), and a way-not-taken stub's length (px).
const SLOPE_PX := 10.0
const STUB_PX := 9.0
const TIER_NAMES := {1: "ROOF", 0: "MAIN", -1: "BELOW"}

const SKULL := [".#####.", "#######", "#..#..#", "#..#..#", "#######", ".##.##.", ".#.#.#."]
const CHOPPER := ["###########", ".....#.....", "..#####...#", ".##########", ".#####.....", "..#...#....", ".#######..."]
const LOCK := [".###.", "#...#", "#...#", "#####", "##.##", "##.##", "#####"]

var graph: RouteGraph
## This run's areas, in order (RunLog.visited), and every area ever reached with how far into it
## he's ever got (RunLog.discovered: {id: metres}, RunLog.FULL once he's seen its end).
var visited: Array[StringName] = []
var discovered: Dictionary = {}
var end_reason: StringName = &""
## How far into the last area the run ended (m), and the real length of the stairs or ladder at
## its start (m; 0 if he came in on the level).
var end_into := 0.0
var end_ramp := 0.0
var _t := 0.0
var _layout := {}
var _far := 1.0
var _scale := 1.0
## Each area's ways in: {id: [the areas they come from]}.
var _ways_in := {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layout = layout(graph) if graph != null else {}
	for span: Vector2 in _layout.values():
		_far = maxf(_far, span.y)
	for id: StringName in _layout:
		for e in graph.all_next(id):
			var to := StringName(e.get("to", ""))
			if not _ways_in.has(to):
				_ways_in[to] = []
			_ways_in[to].append(id)


func _process(delta: float) -> void:
	if _t < DRAW_TIME:
		_t += delta
		queue_redraw()


## Show it all at once (a tap on the end screen).
func finish() -> void:
	_t = DRAW_TIME
	queue_redraw()


## Where each area sits along the map, in metres: {id: Vector2(start, end)}. Each starts where the
## longest way to it ends, so an area two routes reach has one place, and the stairs between
## levels fill any gap.
static func layout(g: RouteGraph) -> Dictionary:
	var order: Array[StringName] = []
	_topo(g, g.start_id, {}, order)
	var start := {g.start_id: 0.0}
	for id in order:
		var s: float = start.get(id, 0.0)
		for e in g.all_next(id):
			var to := StringName(e.get("to", ""))
			start[to] = maxf(float(start.get(to, 0.0)), s + g.length_of(id))
	var out := {}
	for id in order:
		out[id] = Vector2(start[id], start[id] + g.length_of(id))
	return out


static func _topo(g: RouteGraph, id: StringName, seen: Dictionary, order: Array[StringName]) -> void:
	if seen.has(id) or not g.has_node_id(id):
		return
	seen[id] = true
	for e in g.all_next(id):
		_topo(g, StringName(e.get("to", "")), seen, order)
	order.push_front(id)


## The way from the end of `a` to `b`, in map units (x metres, y level): along to where b starts,
## then, if b is on another level, up or down the stairs over b's first `slope` metres (a
## diagonal, as stairs and ladders climb at the start of an area).
static func link(a: Vector2, a_tier: int, b: Vector2, b_tier: int, slope: float) -> PackedVector2Array:
	var pts := PackedVector2Array([Vector2(a.y, a_tier)])
	if a_tier == b_tier:
		pts.append(Vector2(b.x, b_tier))
		return pts
	if b.x > a.y:
		pts.append(Vector2(b.x, a_tier))
	pts.append(Vector2(b.x + climb_of(b, slope), b_tier))
	return pts


## How far into an area its stairs' diagonal reaches (m): `slope`, or less in a short area.
static func climb_of(span: Vector2, slope: float) -> float:
	return minf(slope, (span.y - span.x) * 0.8)


## This run's line in map units, from the start to where it ended (`into` metres into the last
## area; `ramp`: the real length of the stairs it was entered by).
static func run_line(g: RouteGraph, lay: Dictionary, run: Array[StringName], into: float, slope: float, ramp: float = 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in run.size():
		var id := run[i]
		if not lay.has(id):
			continue
		var span: Vector2 = lay[id]
		var tier := g.tier_of(id)
		var last := i == run.size() - 1
		var d := clampf(into, 0.0, span.y - span.x)
		if last and ramp > 0.0 and i > 0 and lay.has(run[i - 1]) and g.tier_of(run[i - 1]) != tier:
			d = on_drawn_stairs(d, ramp, climb_of(span, slope), span.y - span.x)
		var stop := span.y if not last else span.x + d
		if i > 0 and lay.has(run[i - 1]):
			var link_pts := link(lay[run[i - 1]], g.tier_of(run[i - 1]), span, tier, slope)
			for k in range(1, link_pts.size()):
				var p := link_pts[k]
				if last and p.x > stop:  # it ended on the stairs: partway along the diagonal
					var q := pts[-1]
					pts.append(q.lerp(p, clampf((stop - q.x) / maxf(p.x - q.x, 0.001), 0.0, 1.0)))
					return pts
				pts.append(p)
		else:
			pts.append(Vector2(span.x, tier))
		pts.append(Vector2(maxf(stop, pts[-1].x), tier))
	return pts


## Where `d` metres into an area entered by stairs falls on the map, whose stairs are drawn wider
## (`drawn` m) than the real ones (`real` m): on the real flight, the same share of the way along
## the drawn one; past it, the same share of the rest of the area.
static func on_drawn_stairs(d: float, real: float, drawn: float, length: float) -> float:
	var r := minf(real, length)
	if r <= 0.0:
		return d
	if d <= r:
		return d / r * drawn
	return drawn + (d - r) / maxf(length - r, 0.001) * (length - drawn)


## How far into an area he's ever got (m), from the discovery record.
static func seen_of(found: Dictionary, id: StringName) -> float:
	return float(found.get(id, 0.0))


## The areas he's seen to the end (so the ways off them are drawn, and their locks).
static func seen_full(g: RouteGraph, lay: Dictionary, found: Dictionary) -> Dictionary:
	var out := {}
	for id: StringName in found:
		if lay.has(id) and seen_of(found, id) >= g.length_of(id) - 0.001:
			out[id] = true
	return out


## Which levels the run went through, in order: "MAIN > ROOF > MAIN".
static func levels_text(g: RouteGraph, run: Array[StringName]) -> String:
	var parts := PackedStringArray()
	for id in run:
		var name: String = TIER_NAMES.get(g.tier_of(id), "MAIN")
		if parts.is_empty() or parts[-1] != name:
			parts.append(name)
	return " > ".join(parts)


## The ways not taken: [from, to] for each way off an area seen in full (`seen`) into one never
## reached (not in `reached`: every area ever reached, this run's included).
static func locked_ways(g: RouteGraph, seen_full: Dictionary, reached: Dictionary) -> Array:
	var out := []
	var seen := {}
	for id: StringName in seen_full:
		for e in g.all_next(id):
			var to := StringName(e.get("to", ""))
			if reached.has(to) or not g.has_node_id(to) or seen.has([id, to]):
				continue
			seen[[id, to]] = true
			out.append([id, to])
	return out


# --- Drawing ------------------------------------------------------------------------------

func _px(p: Vector2) -> Vector2:
	return Vector2(LABEL_W + p.x * _scale, (1.0 - p.y) * TIER_GAP + 4.0).round()


func _draw() -> void:
	if graph == null:
		return
	_scale = (size.x - LABEL_W - 4.0) / _far
	var f := UiKit.font()
	# The levels: a dotted guide each, named on the left.
	for tier in [1, 0, -1]:
		var y := _px(Vector2(0, tier)).y
		draw_string(f, Vector2(0, y + 3), TIER_NAMES[tier], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, UiKit.DIM)
		var x := LABEL_W
		while x < size.x:
			draw_rect(Rect2(x, y, 1, 1), Color(UiKit.TEAL_DIM, 0.6))
			x += 4.0
	var slope := SLOPE_PX / _scale
	var reached := {}
	for id in discovered:
		if _layout.has(id):
			reached[StringName(id)] = true
	for id in visited:
		reached[id] = true
	var full := seen_full(graph, _layout, discovered)
	# Found on earlier runs: each area as far as he's ever got into it, and the ways on from the ones
	# he's seen the end of, faint.
	var faint := Color(UiKit.TEAL_DIM, 0.9)
	for id: StringName in reached:
		var span: Vector2 = _layout[id]
		var tier := graph.tier_of(id)
		var from := span.x + _climb_in(id, span, full, slope)
		var to_x := span.x + minf(seen_of(discovered, id), span.y - span.x)
		if to_x > from:
			draw_line(_px(Vector2(from, tier)), _px(Vector2(to_x, tier)), faint, 1.0)
		if full.has(id):
			for e in graph.all_next(id):
				var to := StringName(e.get("to", ""))
				if reached.has(to):
					_polyline(link(span, tier, _layout[to], graph.tier_of(to), slope), faint, 1.0)
	# The ways not taken: a stub toward the level they go to, ending in a lock.
	var lock_boxes: Array[Rect2] = []
	for way in locked_ways(graph, full, reached):
		var span: Vector2 = _layout[way[0]]
		var a := _px(Vector2(span.y, graph.tier_of(way[0])))
		var dir: int = signi(graph.tier_of(way[1]) - graph.tier_of(way[0]))
		var b := a + Vector2(STUB_PX, -dir * TIER_GAP * 0.4).round()
		_dashed(a, b, faint)
		_pixels(LOCK, b + Vector2(1, -3), UiKit.DIM)
		lock_boxes.append(Rect2(b + Vector2(0, -4), Vector2(7, 9)))
	# This run: the bright line, drawn in, a dot where each area ends, then where it ended.
	var line := run_line(graph, _layout, visited, end_into, slope, end_ramp)
	var pts := PackedVector2Array()
	for p in line:
		pts.append(_px(p))
	var shown := _partial(pts, clampf(_t / DRAW_TIME, 0.0, 1.0))
	if shown.size() >= 2:
		draw_polyline(shown, UiKit.TEAL, 2.0)
	for i in visited.size() - 1:
		var id := visited[i]
		if _layout.has(id):
			var d := _px(Vector2(_layout[id].y, graph.tier_of(id)))
			if _reached(shown, d):
				draw_rect(Rect2(d - Vector2(1, 1), Vector2(3, 3)), UiKit.PAPER)
	if _t >= DRAW_TIME and not pts.is_empty():
		_end_mark(pts[-1], lock_boxes)


## Where an area's own line starts (m past its start): where the stairs land, if every way into it
## that's drawn comes from another level; at its start otherwise.
func _climb_in(id: StringName, span: Vector2, drawn: Dictionary, slope: float) -> float:
	var any := false
	for from: StringName in _ways_in.get(id, []):
		if drawn.has(from):
			if graph.tier_of(from) == graph.tier_of(id):
				return 0.0
			any = true
	return climb_of(span, slope) if any else 0.0


## The run's end: a skull (killed, captured), a chopper (got out), a faded chopper (it left
## without him, or there was no way through). Above the line's end, or below it if that would
## cover a lock.
func _end_mark(at: Vector2, locks: Array[Rect2]) -> void:
	var art: Array = SKULL if end_reason in [&"killed", &"captured"] else CHOPPER  # GameState.END_KILLED, END_CAPTURED
	var color: Color = UiKit.RED if art == SKULL else (UiKit.GREEN if end_reason == &"extracted" else Color(UiKit.DIM, 0.85))
	_pixels(art, end_mark_at(at, art, locks), color)


## Where an end mark's top-left goes: centred above `at`, or below it if above would cover a lock.
static func end_mark_at(at: Vector2, art: Array, locks: Array[Rect2]) -> Vector2:
	var w: int = String(art[0]).length()
	var above := at + Vector2(-(w / 2), -10)
	var below := at + Vector2(-(w / 2), 4)
	for p: Vector2 in [above, below]:
		var box := Rect2(p - Vector2(1, 1), Vector2(w + 2, art.size() + 2))
		if not locks.any(func(r: Rect2) -> bool: return r.intersects(box)):
			return p
	return above


## Pixel art (rows, "#" = ink), its top-left at `at`, with a dark outline so it reads on the lines.
func _pixels(art: Array, at: Vector2, color: Color) -> void:
	for pass_i in 2:
		for y in art.size():
			var row: String = art[y]
			for x in row.length():
				if row[x] != "#":
					continue
				if pass_i == 0:
					draw_rect(Rect2(at + Vector2(x - 1, y - 1), Vector2(3, 3)), UiKit.INK)
				else:
					draw_rect(Rect2(at + Vector2(x, y), Vector2(1, 1)), color)


func _polyline(map_pts: PackedVector2Array, color: Color, width: float) -> void:
	var pts := PackedVector2Array()
	for p in map_pts:
		pts.append(_px(p))
	draw_polyline(pts, color, width)


func _dashed(a: Vector2, b: Vector2, color: Color) -> void:
	var n := maxi(1, int(a.distance_to(b) / 2.0))
	for i in n:
		if i % 2 == 0:
			draw_line(a.lerp(b, float(i) / n), a.lerp(b, float(i + 1) / n), color, 1.0)


## The first `frac` of the polyline's length.
static func _partial(pts: PackedVector2Array, frac: float) -> PackedVector2Array:
	if frac >= 1.0 or pts.size() < 2:
		return pts
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i - 1].distance_to(pts[i])
	var left := total * frac
	var out := PackedVector2Array([pts[0]])
	for i in range(1, pts.size()):
		var seg := pts[i - 1].distance_to(pts[i])
		if seg >= left:
			out.append(pts[i - 1].lerp(pts[i], left / maxf(seg, 0.001)))
			return out
		left -= seg
		out.append(pts[i])
	return out


## Whether the drawn-in part of the line has reached `p` (one of its corners).
static func _reached(shown: PackedVector2Array, p: Vector2) -> bool:
	for q in shown:
		if q.distance_to(p) < 0.5:
			return true
	return false
