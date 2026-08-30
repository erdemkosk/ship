extends RefCounted
class_name GraspPlanner
## Biomechanical admission and ranking for an entire grasp path.
##
## IK answers "can these joints reach this transform?". This planner answers
## the human question before IK is allowed to run: which hand should approach,
## is every point of that approach legal, and which legal solution costs less?


static func evaluate_frame(rig: Node, side: String, contact: Vector3,
		fingers: Vector3, palm: Vector3, natural_frame: bool,
		allow_fallback: bool) -> Dictionary:
	var ev: Dictionary = rig.consider(side, contact,
			Vector3.ZERO if natural_frame else fingers,
			Vector3.ZERO if natural_frame else palm)
	# Contact semantics guide the grasp, but may never authorize a snapped wrist.
	if allow_fallback and not natural_frame and (float(ev.get("wrist_break", 0.0)) \
			> float(rig.WRIST_CONE) * 0.85 \
			or float(ev.get("palm_twist", 0.0)) > deg_to_rad(125.0)):
		ev = rig.consider(side, contact)
		ev["natural_fallback"] = true
	return ev


static func sample_candidate(rig: Node, side: String, contact: Vector3,
		fingers: Vector3, palm: Vector3, approach: float, assist_cap: float,
		natural_frame: bool, allow_fallback: bool,
		soft_occupancy := 0.0) -> Dictionary:
	## Build and evaluate the whole approach path for either catalog or runtime
	## interactables. The rig's temporary assist is restored before returning.
	var old_assist: float = rig.reach_assist(side)
	var goal_axes: Dictionary = rig.natural_axes(side, contact) \
			if natural_frame else {"fingers": fingers.normalized(),
					"palm": palm.normalized()}
	var points: Array[Vector3] = []
	for alpha: float in [0.0, 0.34, 0.67, 1.0]:
		points.append(contact - (goal_axes["palm"] as Vector3) \
				* maxf(approach, 0.0) * (1.0 - alpha))
	var worst_leftover := 0.0
	for point: Vector3 in points:
		var raw_ev := evaluate_frame(rig, side, point, fingers, palm,
				natural_frame, allow_fallback)
		worst_leftover = maxf(worst_leftover, float(raw_ev.get("leftover", 0.0)))
	var needed := 0.0
	if assist_cap > 0.0:
		needed = minf(maxf(worst_leftover + 0.025, 0.025), assist_cap)
	rig.set_reach_assist(side, needed)
	var path: Array[Dictionary] = []
	for point: Vector3 in points:
		path.append(evaluate_frame(rig, side, point, fingers, palm,
				natural_frame, allow_fallback))
	var end: Dictionary = path.back()
	var candidate := {
		"side": side,
		"end": end,
		"path": path,
		"required_assist": needed,
		"soft_occupancy": soft_occupancy,
		"fingers": end.get("fingers", goal_axes["fingers"]),
		"palm": end.get("palm", goal_axes["palm"]),
	}
	rig.set_reach_assist(side, old_assist)
	return candidate


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
