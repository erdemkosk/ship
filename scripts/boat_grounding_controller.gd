class_name BoatGroundingController
extends RefCounted
## Seafloor contact, Coulomb friction and downslope recovery forces.


func update(owner, ocean: Node, keel_probes: Array[Vector3],
		drift_debug: bool, drift_sums: Dictionary) -> bool:
	if ocean == null or not ocean.has_method("get_seafloor_height"):
		return false
	var deepest := 0.0
	var worst := Vector3.ZERO
	var hits := 0
	for keel_probe in keel_probes:
		var world_probe: Vector3 = owner.global_transform * keel_probe
		var bed := float(ocean.call("get_seafloor_height", world_probe))
		var penetration := bed - world_probe.y
		if penetration <= 0.0:
			continue
		hits += 1
		owner.apply_force(Vector3.UP * clampf(penetration, 0.0, 1.5)
				* 62000.0, world_probe - owner.global_position)
		if penetration > deepest:
			deepest = penetration
			worst = world_probe
	if hits == 0:
		return false
	var grip := clampf(deepest * 2.2, 0.30, 0.90)
	var horizontal_velocity := Vector3(
			owner.linear_velocity.x, 0.0, owner.linear_velocity.z)
	var speed := horizontal_velocity.length()
	if speed > 0.05:
		owner.apply_central_force(-horizontal_velocity / speed * 120000.0 * grip)
	owner.apply_central_force(-horizontal_velocity * 22000.0 * grip)
	owner.apply_torque(-owner.angular_velocity * 62000.0 * grip)
	if drift_debug:
		drift_sums["ground"] += -owner.angular_velocity.y * 62000.0 * grip
	var sample_distance := 3.0
	var gradient_x := float(ocean.call("get_seafloor_height",
			worst + Vector3(sample_distance, 0.0, 0.0))) \
			- float(ocean.call("get_seafloor_height",
			worst - Vector3(sample_distance, 0.0, 0.0)))
	var gradient_z := float(ocean.call("get_seafloor_height",
			worst + Vector3(0.0, 0.0, sample_distance))) \
			- float(ocean.call("get_seafloor_height",
			worst - Vector3(0.0, 0.0, sample_distance)))
	var downslope := Vector3(-gradient_x, 0.0, -gradient_z)
	if downslope.length_squared() > 1.0e-6:
		owner.apply_central_force(downslope.normalized()
				* clampf(deepest * 3.0, 0.6, 2.2) * 96000.0)
	return true
