extends RefCounted
class_name GraspPlanner
## Biomechanical admission and ranking for an entire grasp path.
##
## IK answers "can these joints reach this transform?". This planner answers
## the human question before IK is allowed to run: which hand should approach,
## is every point of that approach legal, and which legal solution costs less?

const INTERACTION_BEHAVIOR := preload("res://scripts/hands/interaction_behavior.gd")


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
		soft_occupancy := 0.0, context: Dictionary = {}) -> Dictionary:
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
	var travel: Array[Vector3] = [rig.approach_origin(side)]
	travel.append_array(points)
	var boat: Node3D = context.get("boat") as Node3D
	candidate["path_blocked"] = _path_blocked(travel, boat)
	var spec: Dictionary = context.get("spec", {})
	var behavior := INTERACTION_BEHAVIOR.profile(spec)
	end["gaze_weight"] = float(behavior.get("gaze_weight", 0.5))
	candidate["load_cost"] = INTERACTION_BEHAVIOR.load_cost(spec,
			int(context.get("side_count", 1))) \
			if not spec.is_empty() else 0.0
	rig.set_reach_assist(side, old_assist)
	return candidate


static func _path_blocked(points: Array[Vector3], boat: Node3D) -> bool:
	## Sweep the palm route against the same authored solid blockers used by
	## aiming. The blocker containing the endpoint is the intended contact
	## surface; an earlier hit on any other blocker is structural penetration.
	if boat == null or points.size() < 2:
		return false
	var blockers: Variant = boat.get("aim_blockers")
	if not blockers is Array or (blockers as Array).is_empty():
		return false
	for i in range(points.size() - 1):
		var from_local := boat.to_local(points[i])
		var to_local := boat.to_local(points[i + 1])
		for blocker: AABB in blockers:
			# Controls are mounted in panels represented by these same coarse
			# blockers. The block containing the goal is the contact surface, not
			# an obstacle; other boxes remain forbidden along the route.
			if blocker.grow(0.08).has_point(boat.to_local(points.back())):
				continue
			var entry := _segment_aabb_entry(from_local, to_local, blocker.grow(0.025))
			# A fitting mounted on a wall necessarily ends at that wall. Only a
			# blocker reached through the first 62% of a segment is structural
			# penetration; a late hit is the intended contact surface.
			if entry >= 0.0 and entry < 0.62:
				return true
	return false


static func _segment_aabb_entry(from: Vector3, to: Vector3, box: AABB) -> float:
	var direction := to - from
	var first := 0.0
	var last := 1.0
	for axis in 3:
		var origin: float = from[axis]
		var delta: float = direction[axis]
		var low: float = box.position[axis]
		var high: float = box.end[axis]
		if absf(delta) < 1e-7:
			if origin < low or origin > high:
				return -1.0
			continue
		var a := (low - origin) / delta
		var b := (high - origin) / delta
		if a > b:
			var swap := a
			a = b
			b = swap
		first = maxf(first, a)
		last = minf(last, b)
		if first > last:
			return -1.0
	return first


static func admissible(ev: Dictionary, wrist_cone: float) -> bool:
	return float(ev.get("leftover", INF)) <= 0.025 \
			and float(ev.get("elbow_cost", PI)) <= deg_to_rad(10.0) \
			and float(ev.get("shoulder_raise", 1.0)) <= 0.18 \
			and float(ev.get("wrist_break", PI)) <= wrist_cone * 1.12 \
			and float(ev.get("palm_twist", PI)) <= deg_to_rad(138.0)


static func candidate_ok(candidate: Dictionary, wrist_cone: float) -> bool:
	if bool(candidate.get("path_blocked", false)) \
			or not is_finite(float(candidate.get("load_cost", 0.0))):
		return false
	if not admissible(candidate.get("end", {}), wrist_cone):
		return false
	for ev: Dictionary in candidate.get("path", []):
		if not admissible(ev, wrist_cone):
			return false
	return true


static func score_breakdown(candidate: Dictionary, occupied: bool,
		preferred := "") -> Dictionary:
	if occupied:
		return {"total": INF, "quality": 0.0}
	var ev: Dictionary = candidate.get("end", {})
	var parts := {
		"reach": float(ev.get("distance", 0.0))
				+ float(ev.get("leftover", 0.0)) * 6.0,
		"cross_body": float(ev.get("cross", 0.0)) * 5.0,
		"elbow": float(ev.get("elbow_cost", 0.0)) * 2.2,
		"shoulder": float(ev.get("shoulder_raise", 0.0)) * 2.8,
		"wrist": float(ev.get("wrist_break", 0.0)) * 0.55
				+ float(ev.get("palm_twist", 0.0)) * 0.32,
		"torso": float(ev.get("torso_twist", 0.0)) * 0.38
				+ float(ev.get("balance_offset", 0.0)) * 2.0,
		"gaze": float(ev.get("gaze_occlusion", 0.0))
				* float(ev.get("gaze_weight", 0.5)),
		"load": float(candidate.get("load_cost", 0.0)),
		"path": 20.0 if bool(candidate.get("path_blocked", false)) else 0.0,
	}
	# The worst point on the way matters: a legal-looking final pose does not
	# excuse an approach that crosses the torso or folds the wrist en route.
	for path_ev: Dictionary in candidate.get("path", []):
		parts["cross_body"] += float(path_ev.get("cross", 0.0)) * 1.4 \
				+ float(path_ev.get("wrist_break", 0.0)) * 0.16 \
				+ float(path_ev.get("palm_twist", 0.0)) * 0.10
	if not bool(ev.get("comfortable", false)):
		parts["torso"] += 1.4
	if preferred == str(candidate.get("side", "")):
		parts["preference"] = -0.04
	else:
		parts["preference"] = 0.0
	parts["occupancy"] = float(candidate.get("soft_occupancy", 0.0))
	var total := 0.0
	for key: String in parts:
		total += float(parts[key])
	parts["total"] = total
	parts["quality"] = clampf(exp(-maxf(total, 0.0) * 0.42), 0.0, 1.0)
	return parts


static func score(candidate: Dictionary, occupied: bool, preferred := "") -> float:
	return float(score_breakdown(candidate, occupied, preferred).get("total", INF))


static func choose(candidates: Dictionary, wrist_cone: float,
		occupied: Dictionary, preferred := "", previous_side := "",
		switch_margin := 0.18) -> Dictionary:
	var best: Dictionary = {}
	var best_score := INF
	var scored := {}
	for side: String in ["L", "R"]:
		var candidate: Dictionary = candidates.get(side, {})
		if candidate.is_empty() or not candidate_ok(candidate, wrist_cone):
			continue
		var breakdown := score_breakdown(candidate,
				bool(occupied.get(side, false)), preferred)
		var value := float(breakdown.get("total", INF))
		scored[side] = {"candidate": candidate, "breakdown": breakdown,
				"score": value}
		if value < best_score:
			best_score = value
			best = candidate.duplicate()
			best["score"] = value
			best["quality"] = breakdown.get("quality", 0.0)
			best["quality_breakdown"] = breakdown
	# Hysteresis: retain the human's current hand unless the alternative is
	# materially better. Tiny camera/boat motion must not make ownership flicker.
	if previous_side != "" and scored.has(previous_side):
		var previous: Dictionary = scored[previous_side]
		if float(previous["score"]) <= best_score + switch_margin:
			best = (previous["candidate"] as Dictionary).duplicate()
			best["score"] = previous["score"]
			best["quality_breakdown"] = previous["breakdown"]
			best["quality"] = (previous["breakdown"] as Dictionary).get("quality", 0.0)
	return best
