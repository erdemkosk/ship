extends RefCounted
class_name HelmHandDriver
## Ergonomic rim selection and re-grip lifecycle for both helm hands.

const REGRIP_ARC := 0.9
const REGRIP_TIME := 0.34
const REGRIP_LIFT := 0.07
const RIM := 0.29
const RIM_SAMPLES := 72
const RIM_BOTTOM_REGRIP := -0.16

var rig: Node
var _rim_angle := {}
var _rim_ref := {}
var _regrip := {"L": 0.0, "R": 0.0}
var _rim_from := {}
var _rim_to := {}


func setup(p_rig: Node) -> void:
	rig = p_rig


func reset(side: String) -> void:
	_regrip[side] = 0.0


func ride(side: String, delta: float, boat: Node3D, wheel: Node3D,
		grip: Node3D) -> float:
	if wheel == null or grip == null:
		return 1.0
	if float(_regrip[side]) > 0.0:
		_regrip[side] = maxf(float(_regrip[side]) - delta, 0.0)
		var u: float = 1.0 - float(_regrip[side]) / REGRIP_TIME
		u = u * u * (3.0 - 2.0 * u)
		# Plan in world angle while the wheel continues beneath the moving hand.
		var world_a: float = lerp_angle(float(_rim_from[side]),
				float(_rim_to[side]), u)
		var angle := world_a - wheel.rotation.z
		write_grip(grip, angle, REGRIP_LIFT * sin(u * PI))
		if float(_regrip[side]) <= 0.0:
			_rim_angle[side] = angle
			_rim_ref[side] = wheel.rotation.z
		return clampf(1.0 - sin(u * PI) * 0.9, 0.1, 1.0)
	var turned: float = absf(wrapf(wheel.rotation.z \
			- float(_rim_ref.get(side, 0.0)), -PI, PI))
	var current := candidate(side, float(_rim_angle.get(side, 0.0)), boat, wheel)
	var pose_bad: bool = float(current.get("up", -1.0)) < RIM_BOTTOM_REGRIP \
			or float(current.get("wrist_break", PI)) > float(rig.WRIST_CONE) * 1.10 \
			or float(current.get("palm_twist", PI)) > deg_to_rad(140.0)
	if turned > REGRIP_ARC or pose_bad:
		_rim_from[side] = float(_rim_angle[side]) + wheel.rotation.z
		_rim_to[side] = pick_angle(side, boat, wheel) + wheel.rotation.z
		_regrip[side] = REGRIP_TIME
	return 1.0


func pick_angle(side: String, boat: Node3D, wheel: Node3D) -> float:
	var best := 0.0
	var best_score := INF
	for i in RIM_SAMPLES:
		var angle := float(i) / float(RIM_SAMPLES) * TAU
		var option := candidate(side, angle, boat, wheel)
		var option_score: float = float(option.get("score", INF))
		if option_score < best_score:
			best_score = option_score
			best = angle
	return best


func candidate(side: String, angle: float, boat: Node3D,
		wheel: Node3D) -> Dictionary:
	if boat == null or wheel == null or rig == null or not rig.is_ready():
		return {"score": INF, "comfortable": false, "up": -1.0}
	var radial_local := Vector3(cos(angle), sin(angle), 0.0)
	var contact: Vector3 = wheel.global_transform * (radial_local * RIM)
	var fingers: Vector3 = (wheel.global_basis * Vector3(0.0, 0.0, -1.0)).normalized()
	var palm: Vector3 = (wheel.global_basis * -radial_local).normalized()
	var ev: Dictionary = rig.consider(side, contact, fingers, palm)
	var radial_world := (contact - wheel.global_position).normalized()
	var boat_up := boat.global_basis.y.normalized()
	var boat_right := boat.global_basis.x.normalized()
	var side_sign := 1.0 if side == "R" else -1.0
	var up: float = radial_world.dot(boat_up)
	var own_side: float = radial_world.dot(boat_right) * side_sign
	var sector_cost := Vector2(own_side, up).distance_to(Vector2(0.72, 0.69))
	var score: float = float(ev.get("distance", 1e6)) \
			+ float(ev.get("leftover", 0.0)) * 12.0 \
			+ float(ev.get("cross", 0.0)) * 7.0 \
			+ float(ev.get("elbow_cost", 0.0)) * 3.2 \
			+ float(ev.get("shoulder_raise", 0.0)) * 3.5 \
			+ float(ev.get("wrist_break", PI)) * 1.35 \
			+ float(ev.get("palm_twist", PI)) * 0.72 \
			+ sector_cost * 0.85
	if not bool(ev.get("reachable", false)):
		score += 20.0
	if up < -0.08:
		score += 4.0 + (-0.08 - up) * 12.0
	if own_side < -0.12:
		score += 2.5 + (-0.12 - own_side) * 5.0
	return {
		"score": score,
		"comfortable": bool(ev.get("comfortable", false)) \
				and up >= RIM_BOTTOM_REGRIP,
		"up": up,
		"own_side": own_side,
		"wrist_break": ev.get("wrist_break", PI),
		"palm_twist": ev.get("palm_twist", PI),
		"evaluation": ev,
	}


func write_grip(grip: Node3D, angle: float, lift: float) -> void:
	var radial := Vector3(cos(angle), sin(angle), 0.0)
	var fingers := Vector3(0.0, 0.0, -1.0)
	var palm := -radial
	var out := radial * (RIM + lift) + Vector3(0.0, 0.0, lift * 0.8)
	grip.transform = Transform3D(Basis(palm.cross(fingers), palm, fingers), out)
	if grip.has_meta("natural"):
		grip.remove_meta("natural")


func seat(side: String, boat: Node3D, wheel: Node3D, grip: Node3D) -> void:
	if boat == null or wheel == null or grip == null:
		return
	_rim_angle[side] = pick_angle(side, boat, wheel)
	_rim_ref[side] = wheel.rotation.z
	write_grip(grip, float(_rim_angle[side]), 0.0)
