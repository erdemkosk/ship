extends RefCounted
class_name BackpackHandDriver
## Two-hand body-space performance for the backpack. The bag owns animation;
## this driver reads its live anchors and puts flesh on them.


func drive(state: Dictionary, camera: Camera3D, rig: Node) -> Dictionary:
	var bag: Node3D = state.get("bag") as Node3D
	var zipper: Node3D = state.get("zipper") as Node3D
	var item: Node3D = state.get("item") as Node3D
	if bag == null or zipper == null or item == null:
		return {}
	var p := clampf(float(state.get("progress", 0.0)), 0.0, 1.0)
	var appear := smoothstep(0.02, 0.20, p)
	var b := bag.global_transform

	# Left hand takes the bag's weight at its lower outboard corner. It remains
	# there while the right hand works; that asymmetry is what makes the object
	# feel heavy instead of like a menu floating in front of the camera.
	var left_contact := b * Vector3(-0.155, -0.205, 0.045)
	var left_fingers := (b.basis * Vector3(0.55, 0.68, -0.48)).normalized()
	var left_palm := (b.basis * Vector3(0.52, 0.42, -0.74)).normalized()
	rig.set_contact_target("L", bag)
	rig.grip("L", left_contact, left_fingers, left_palm, appear,
			"power", 0.88 * appear, false)

	var support := b * Vector3(0.165, 0.025, 0.095)
	var zip_point := zipper.global_position
	var item_point := item.global_position
	var right_contact: Vector3
	var pose := "handle"
	var pose_amount := 0.82 * appear
	if p < 0.38:
		var u := smoothstep(0.10, 0.38, p)
		right_contact = support.lerp(zip_point, u)
		pose = "handle" if u < 0.55 else "pinch"
		pose_amount = lerpf(0.72, 0.94, u) * appear
	elif p < 0.82:
		# Follow the physical zipper slider; no duplicate hand curve can drift
		# away from it when the bag sways.
		right_contact = zip_point
		pose = "pinch"
		pose_amount = 0.96 * appear
	else:
		var take := smoothstep(0.82, 0.98, p)
		right_contact = zip_point.lerp(item_point, take)
		pose = "pinch" if take < 0.58 else "power"
		pose_amount = lerpf(0.94, 0.84, take) * appear
	var right_fingers := (b.basis * Vector3(-0.10, 0.86, -0.50)).normalized()
	var right_palm := (b.basis * Vector3(-0.42, -0.10, -0.90)).normalized()
	if p > 0.84:
		# Curl around the little round object rather than pressing it into the bag.
		right_fingers = (camera.global_basis * Vector3(-0.18, -0.84, -0.52)).normalized()
		right_palm = (camera.global_basis * Vector3(-0.72, -0.08, 0.68)).normalized()
	rig.set_contact_target("R", item if p > 0.84 else bag)
	rig.grip("R", right_contact, right_fingers, right_palm, appear,
			pose, pose_amount, false)
	return {
		"contacts": {"L": left_contact, "R": right_contact},
		"left_target": bag,
		"right_target": item if p > 0.84 else bag,
	}
