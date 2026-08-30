extends RefCounted
class_name GraspPlanner
## Biomechanical admission and ranking for an entire grasp path.
##
## IK answers "can these joints reach this transform?". This planner answers
## the human question before IK is allowed to run: which hand should approach,
## is every point of that approach legal, and which legal solution costs less?


static func admissible(ev: Dictionary, wrist_cone: float) -> bool:
	return float(ev.get("leftover", INF)) <= 0.025 \
			and float(ev.get("elbow_cost", PI)) <= deg_to_rad(10.0) \
			and float(ev.get("shoulder_raise", 1.0)) <= 0.18 \
			and float(ev.get("wrist_break", PI)) <= wrist_cone * 1.12 \
			and float(ev.get("palm_twist", PI)) <= deg_to_rad(138.0)


static func candidate_ok(candidate: Dictionary, wrist_cone: float) -> bool:
	if not admissible(candidate.get("end", {}), wrist_cone):
		return false
	for ev: Dictionary in candidate.get("path", []):
		if not admissible(ev, wrist_cone):
			return false
	return true


static func score(candidate: Dictionary, occupied: bool, preferred := "") -> float:
	if occupied:
		return INF
	var ev: Dictionary = candidate.get("end", {})
	var value := float(ev.get("distance", 0.0)) \
			+ float(ev.get("leftover", 0.0)) * 6.0 \
			+ float(ev.get("cross", 0.0)) * 5.0 \
			+ float(ev.get("elbow_cost", 0.0)) * 2.2 \
			+ float(ev.get("shoulder_raise", 0.0)) * 2.8 \
			+ float(ev.get("wrist_break", 0.0)) * 0.55 \
			+ float(ev.get("palm_twist", 0.0)) * 0.32
	# The worst point on the way matters: a legal-looking final pose does not
	# excuse an approach that crosses the torso or folds the wrist en route.
	for path_ev: Dictionary in candidate.get("path", []):
		value += float(path_ev.get("cross", 0.0)) * 1.4 \
				+ float(path_ev.get("wrist_break", 0.0)) * 0.16 \
				+ float(path_ev.get("palm_twist", 0.0)) * 0.10
	if not bool(ev.get("comfortable", false)):
		value += 1.4
	if preferred == str(candidate.get("side", "")):
		value -= 0.04
	value += float(candidate.get("soft_occupancy", 0.0))
	return value


static func choose(candidates: Dictionary, wrist_cone: float,
		occupied: Dictionary, preferred := "") -> Dictionary:
	var best: Dictionary = {}
	var best_score := INF
	for side: String in ["L", "R"]:
		var candidate: Dictionary = candidates.get(side, {})
		if candidate.is_empty() or not candidate_ok(candidate, wrist_cone):
			continue
		var value := score(candidate, bool(occupied.get(side, false)), preferred)
		if value < best_score:
			best_score = value
			best = candidate.duplicate()
			best["score"] = value
	return best
