class_name Sightlines
extends RefCounted
## Line of sight in route space (distance along the route, x across it). Walls are solid: a shot
## (yours or a trooper's) can't pass through a blocker, but it can go over small cover (boxes and
## barriers aren't blockers) and round a wall's edge.
##
## A blocker is {at: route distance, x0, x1: its span across, open: Callable or null}. `open`
## (e.g. a door that's been burst open) returns true once the blocker no longer blocks.

## A shot that grazes a wall's edge by less than this still gets past.
const EDGE_MARGIN := 0.05


## True if something solid stands between (from_d, from_x) and (to_d, to_x). `ignore` is a
## blocker to leave out (the wall you're leaning out from behind).
static func blocked(from_d: float, from_x: float, to_d: float, to_x: float, blockers: Array,
		ignore: Variant = null) -> bool:
	var near := minf(from_d, to_d)
	var far := maxf(from_d, to_d)
	if far - near < 0.01:
		return false
	for b in blockers:
		if ignore != null and is_same(b, ignore):
			continue
		var at: float = b["at"]
		if at <= near or at >= far:
			continue
		var open = b.get("open")
		if open is Callable and open.call():
			continue
		var t := (at - from_d) / (to_d - from_d)
		var x := lerpf(from_x, to_x, t)
		if x > float(b["x0"]) + EDGE_MARGIN and x < float(b["x1"]) - EDGE_MARGIN:
			return true
	return false


## The wall you're taking cover behind (the nearest blocker just ahead, across your x), or null.
static func cover_wall(player_d: float, player_x: float, blockers: Array, reach: float = 2.0) -> Variant:
	var best: Variant = null
	var best_at := INF
	for b in blockers:
		var at: float = b["at"]
		if at > player_d and at - player_d <= reach and player_x >= float(b["x0"]) and player_x <= float(b["x1"]) and at < best_at:
			best = b
			best_at = at
	return best
