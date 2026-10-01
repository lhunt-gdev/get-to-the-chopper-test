class_name Sightlines
extends RefCounted
## Route-space help for line of sight (distance along the route, x across it). The sight itself
## is real rays against the walls (the level's _sees()); this only finds the wall you're taking
## cover behind, so your shots can lean out round its edge.
##
## A wall is {at: route distance, x0, x1: its span across}.


## The wall you're taking cover behind (the nearest one just ahead, across your x), or null.
static func cover_wall(player_d: float, player_x: float, walls: Array, reach: float = 2.0) -> Variant:
	var best: Variant = null
	var best_at := INF
	for b in walls:
		var at: float = b["at"]
		if at > player_d and at - player_d <= reach and player_x >= float(b["x0"]) and player_x <= float(b["x1"]) and at < best_at:
			best = b
			best_at = at
	return best
