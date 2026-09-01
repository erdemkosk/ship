class_name CameraInteractionSelector
extends RefCounted
## Boat-local crosshair selection with reach, visibility and sway tolerance.

const HandGripMap := preload("res://scripts/hands/grip_map.gd")


func select(target, eye: Vector3, look_direction: Vector3, engaged: String,
		bag_focus: float, previous_id: String, arms: Node,
		occluded: Callable) -> Dictionary:
	var candidate := {}
	if engaged == "chart" or bag_focus >= 0.08:
		return {"candidate": candidate, "last_aim": ""}
	var sway := 0.0
	if target is RigidBody3D:
		sway = clampf((target as RigidBody3D).angular_velocity.length() * 1.6,
				0.0, 1.4)
	var nearest := INF
	for item in target.INTERACT:
		var id := str(item["id"])
		if (engaged == "helm" and id == "helm") \
				or (engaged == "telegraph" and id == "telegraph"):
			continue
		if id == "divegear" and not (_property_flag(target, "locker_open") \
				or _property_flag(target, "gear_worn")):
			continue
		var in_switch_well: bool = target.has_method("switch_in_well") \
				and bool(target.call("switch_in_well", id))
		if (id.begins_with("fu_") or in_switch_well) \
				and not _property_flag(target, "fusebox_open"):
			continue
		var interaction_position: Vector3 = item["pos"]
		if target.has_method("interact_pos"):
			interaction_position = target.call(
					"interact_pos", id, interaction_position)
		var offset := interaction_position - eye
		var along := look_direction.dot(offset)
		if along <= 0.02 or along > 2.2:
			continue
		var base_radius := float(item["r"])
		var radius := base_radius * (1.0 \
				+ sway * clampf(0.14 / maxf(base_radius, 0.05), 0.0, 1.0))
		if id == previous_id:
			radius *= 1.22
		var perpendicular := (offset - look_direction * along).length()
		if perpendicular > radius:
			continue
		if id != "fusebox" and not id.begins_with("fu_") \
				and not in_switch_well \
				and bool(occluded.call(target, eye, interaction_position)):
			continue
		if arms != null and not HandGripMap.spec_for(id).is_empty():
			arms.set("boat", target)
			if not bool(arms.call("can_offer", id)):
				continue
		var score: float = perpendicular / maxf(along, 0.05)
		score *= 1.0 + base_radius * 1.8
		if id == previous_id:
			score *= 0.88
		if score < nearest:
			nearest = score
			candidate = item
	return {
		"candidate": candidate,
		"last_aim": str(candidate["id"]) if not candidate.is_empty() else "",
	}


func _property_flag(object: Object, property: StringName) -> bool:
	var value: Variant = object.get(property)
	return typeof(value) == TYPE_BOOL and value
