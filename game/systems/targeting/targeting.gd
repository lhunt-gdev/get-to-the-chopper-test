class_name Targeting
extends RefCounted
## Decides what FIRE shoots. Enemies are not built yet; this is the rule, ready to test.
##
## AUTO_PRIORITY (Controls v1 + agreed rule): pick the most urgent threat in the
##   forward cone. An enemy can report urgency with get_threat_priority() -> int
##   (e.g. a Security Trooper reaching for an alarm = 100, a charging dog = 50).
##   Ties go to the nearest enemy.
## TAP_TO_TARGET (proposal under test): only a tapped enemy is shot.
## HYBRID: a tapped enemy wins while it is valid; otherwise AUTO_PRIORITY.


static func pick(
		candidates: Array[Node3D],
		origin: Vector3,
		forward: Vector3,
		tuning: Tuning,
		tapped: Node3D = null) -> Node3D:
	var tapped_ok := tapped != null and is_instance_valid(tapped) and in_cone(tapped.global_position, origin, forward, tuning)
	match tuning.targeting_mode:
		Tuning.TargetingMode.TAP_TO_TARGET:
			return tapped if tapped_ok else null
		Tuning.TargetingMode.HYBRID:
			if tapped_ok:
				return tapped
	return _most_urgent(candidates, origin, forward, tuning)


static func _most_urgent(candidates: Array[Node3D], origin: Vector3, forward: Vector3, tuning: Tuning) -> Node3D:
	var best: Node3D = null
	var best_priority := -1
	var best_dist := INF
	for c in candidates:
		if not is_instance_valid(c) or not in_cone(c.global_position, origin, forward, tuning):
			continue
		var p: int = c.get_threat_priority() if c.has_method("get_threat_priority") else 0
		var d := origin.distance_to(c.global_position)
		if p > best_priority or (p == best_priority and d < best_dist):
			best = c
			best_priority = p
			best_dist = d
	return best


static func in_cone(target: Vector3, origin: Vector3, forward: Vector3, tuning: Tuning) -> bool:
	var to := target - origin
	var dist := to.length()
	if dist > tuning.target_range or dist < 0.001:
		return false
	return rad_to_deg(forward.normalized().angle_to(to / dist)) <= tuning.target_cone_degrees
