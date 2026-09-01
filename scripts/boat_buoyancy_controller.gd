class_name BoatBuoyancyController
extends RefCounted
## Stateful probe buoyancy, hull-plane fitting, swell heave and slam detection.

var _previous_water_heights := PackedFloat32Array()
var _water_heights_valid := false
var _previous_com_wave_velocity := 0.0
var _com_wave_velocity_valid := false
var _slam_cooldown := 0.0


func setup(probe_count: int) -> void:
	_previous_water_heights.resize(probe_count)


func reset_history() -> void:
	_water_heights_valid = false
	_com_wave_velocity_valid = false


func update(owner: RigidBody3D, ocean: Node, probes: Array[Vector3],
		delta: float, probe_stiffness: float, probe_damping: float,
		fit_hull_plane: bool) -> Dictionary:
	var submerged := 0.0
	var hull_count := 0.0
	var wet_count := 0.0
	var slammed := false
	var com_wave_velocity := 0.0
	var plane_sums := PackedFloat64Array()
	plane_sums.resize(8)
	for index in probes.size():
		var world_probe: Vector3 = owner.global_transform * probes[index]
		var water_height := float(ocean.call("get_height", world_probe))
		var wave_velocity := 0.0
		if _water_heights_valid:
			wave_velocity = clampf(
					(water_height - _previous_water_heights[index]) / delta,
					-10.0, 10.0)
		_previous_water_heights[index] = water_height
		if probes[index].y < 0.0:
			hull_count += 1.0
			com_wave_velocity += wave_velocity
			_accumulate_plane(plane_sums, world_probe, water_height,
					owner.global_position)
		var depth := water_height - world_probe.y
		if depth <= 0.0:
			continue
		wet_count += 1.0
		if probes[index].y < 0.0:
			submerged += 1.0
		var offset := world_probe - owner.global_position
		var point_velocity := owner.linear_velocity \
				+ owner.angular_velocity.cross(offset)
		var relative_vertical := clampf(
				point_velocity.y - wave_velocity, -12.0, 12.0)
		var force := probe_stiffness * clampf(depth, 0.0, 1.4) \
				- probe_damping * relative_vertical
		force = clampf(force, 0.0, probe_stiffness * 2.4)
		owner.apply_force(Vector3.UP * force, offset)
		if probes[index].y < 0.0 and relative_vertical < -4.2 \
				and depth < 0.28 and _slam_cooldown <= 0.0:
			_slam_cooldown = 1.15
			slammed = true
			ocean.call("hull_slam", world_probe, probes[index],
					clampf(absf(relative_vertical) * 0.18, 0.4, 1.1))
	if hull_count > 0.0:
		submerged /= hull_count
		com_wave_velocity /= hull_count
	_water_heights_valid = true
	_slam_cooldown -= delta
	var wave_normal := _fit_wave_normal(
			ocean, owner.global_position, plane_sums, hull_count, fit_hull_plane)
	var hydro := maxf(submerged, wet_count / float(probes.size()))
	if hydro > 0.0:
		_apply_swell_heave(owner, delta, com_wave_velocity, hydro)
	else:
		_com_wave_velocity_valid = false
	return {
		"submerged": submerged,
		"hydro": hydro,
		"wave_normal": wave_normal,
		"slammed": slammed,
	}


func _accumulate_plane(sums: PackedFloat64Array, world_probe: Vector3,
		water_height: float, origin: Vector3) -> void:
	var x := world_probe.x - origin.x
	var z := world_probe.z - origin.z
	var height := water_height - origin.y
	sums[0] += x
	sums[1] += z
	sums[2] += height
	sums[3] += x * x
	sums[4] += z * z
	sums[5] += x * z
	sums[6] += x * height
	sums[7] += z * height


func _fit_wave_normal(ocean: Node, position: Vector3,
		sums: PackedFloat64Array, hull_count: float,
		fit_hull_plane: bool) -> Vector3:
	if fit_hull_plane and hull_count >= 3.0:
		var mean_x := sums[0] / hull_count
		var mean_z := sums[1] / hull_count
		var mean_height := sums[2] / hull_count
		var covariance_xx := sums[3] - hull_count * mean_x * mean_x
		var covariance_zz := sums[4] - hull_count * mean_z * mean_z
		var covariance_xz := sums[5] - hull_count * mean_x * mean_z
		var covariance_xh := sums[6] - hull_count * mean_x * mean_height
		var covariance_zh := sums[7] - hull_count * mean_z * mean_height
		var determinant := covariance_xx * covariance_zz \
				- covariance_xz * covariance_xz
		if absf(determinant) > 1.0e-5:
			var gradient_x := (covariance_xh * covariance_zz
					- covariance_zh * covariance_xz) / determinant
			var gradient_z := (covariance_zh * covariance_xx
					- covariance_xh * covariance_xz) / determinant
			gradient_x = clampf(gradient_x, -0.85, 0.85)
			gradient_z = clampf(gradient_z, -0.85, 0.85)
			return Vector3(-gradient_x, 1.0, -gradient_z).normalized()
	if ocean.has_method("get_normal"):
		return ocean.call("get_normal", position) as Vector3
	return Vector3.UP


func _apply_swell_heave(owner: RigidBody3D, delta: float,
		com_wave_velocity: float, hydro: float) -> void:
	var wave_acceleration := 0.0
	if _com_wave_velocity_valid:
		wave_acceleration = clampf(
				(com_wave_velocity - _previous_com_wave_velocity) / delta,
				-14.0, 14.0)
	_previous_com_wave_velocity = com_wave_velocity
	_com_wave_velocity_valid = true
	owner.apply_central_force(
			Vector3.UP * wave_acceleration * owner.mass * 0.7 * hydro)
