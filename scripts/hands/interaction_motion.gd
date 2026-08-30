extends RefCounted
class_name InteractionMotion
## Stateless interpreter for an interactable's post-contact motion contract.
##
## Hands decide how to reach and grasp. This module only answers how far the
## contacted fitting has travelled and whether that travel is enough to let go.
## Keeping those responsibilities separate lets future drawers, lids and levers
## share one contract without adding object names or animation timers to hands.gd.


static func validation_error(follow: Dictionary) -> String:
	if follow.is_empty():
		return ""
	var motion_type := str(follow.get("type", ""))
	if motion_type not in ["hinge", "linear"]:
		return "unsupported follow motion"
	if motion_type == "hinge" and float(follow.get("angle", 0.0)) <= 0.0:
		return "follow motion has no travel"
	if motion_type == "linear" and float(follow.get("distance", 0.0)) <= 0.0:
		return "follow motion has no travel"
	var direction: Vector3 = follow.get("direction", Vector3.ZERO)
	if motion_type == "linear" and follow.has("direction") \
			and direction.length_squared() < 0.25:
		return "follow motion has invalid direction"
	if float(follow.get("timeout", 0.0)) <= 0.0:
		return "follow motion has no timeout"
	return ""


static func snapshot(device: Node3D) -> Dictionary:
	if device == null:
		return {}
	# Local transform intentionally excludes the boat's own pitch and roll.
	return {
		"rotation": device.transform.basis.get_rotation_quaternion(),
		"origin": device.transform.origin,
	}


static func progress(follow: Dictionary, start: Dictionary,
		device: Node3D) -> float:
	if follow.is_empty() or start.is_empty() or device == null:
		return 0.0
	match str(follow.get("type", "")):
		"hinge":
			var q0: Quaternion = start.get("rotation", Quaternion.IDENTITY)
			var q1 := device.transform.basis.get_rotation_quaternion()
			var travel := absf(q0.angle_to(q1))
			return clampf(travel / maxf(float(follow.get("angle", 0.01)), 0.01),
					0.0, 1.0)
		"linear":
			var origin: Vector3 = start.get("origin", device.transform.origin)
			var displacement := device.transform.origin - origin
			var direction: Vector3 = follow.get("direction", Vector3.ZERO)
			var travel := absf(displacement.dot(direction.normalized())) \
					if direction.length_squared() > 0.25 else displacement.length()
			return clampf(travel / maxf(float(follow.get("distance", 0.01)), 0.01),
					0.0, 1.0)
	return 0.0


static func should_release(follow: Dictionary, after_contact: float,
		motion_progress: float) -> bool:
	if follow.is_empty():
		return false
	var minimum := maxf(float(follow.get("min_time", 0.0)), 0.0)
	var timeout := maxf(float(follow.get("timeout", 0.18)), minimum)
	return after_contact >= minimum and (motion_progress >= 1.0 \
			or after_contact >= timeout)
