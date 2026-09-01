class_name BoatHydrodynamicsController
extends RefCounted
## Wave alignment, hull drag, leeway, wind, screw thrust and rudder forces.

const HULL_DRAG := 1430.0


func update(owner, ocean: Node, hydro: float, submerged: float,
		wave_normal: Vector3, rpm: float, helm: float, thrust_power: float,
		turn_torque: float, roll_damp: float, pitch_damp: float,
		drift_debug: bool, drift_sums: Dictionary) -> Dictionary:
	if hydro <= 0.0:
		return {"water_velocity": Vector3.ZERO, "stream": 0.0, "flow": 0.0}
	var up_dot: float = owner.global_basis.y.dot(Vector3.UP)
	_apply_wave_alignment(owner, wave_normal, hydro, up_dot,
			drift_debug, drift_sums)
	_apply_roll_pitch_damping(owner, hydro, roll_damp, pitch_damp,
			drift_debug, drift_sums)
	var water_velocity := _water_velocity(ocean, owner.global_position)
	_apply_hull_forces(owner, ocean, hydro, water_velocity,
			drift_debug, drift_sums)
	var stream := 0.0
	var flow := 0.0
	if up_dot > 0.22:
		owner.apply_central_force(-owner.global_basis.z * rpm
				* thrust_power * submerged)
		stream = -owner.global_basis.z.dot(owner.linear_velocity - water_velocity) \
				+ rpm * 2.6
		var through_water := absf(stream)
		flow = clampf(maxf(through_water / 9.0, absf(rpm) * 0.35), 0.05, 1.0)
		flow *= flow * 0.5 + flow * 0.5
		var sense := clampf(stream / 0.22, -1.0, 1.0)
		var rudder_torque := helm * sense * turn_torque * flow * submerged
		owner.apply_torque(Vector3.UP * rudder_torque)
		if drift_debug:
			drift_sums["rudder"] += rudder_torque
	return {"water_velocity": water_velocity, "stream": stream, "flow": flow}


func _apply_wave_alignment(owner, wave_normal: Vector3, hydro: float,
		up_dot: float, drift_debug: bool, drift_sums: Dictionary) -> void:
	if up_dot <= 0.32:
		return
	var target_up := wave_normal.normalized()
	if target_up.length_squared() <= 0.01:
		return
	var tilt_axis: Vector3 = owner.global_basis.y.cross(target_up)
	tilt_axis.y = 0.0
	var torque: Vector3 = tilt_axis * 34000.0 * up_dot * up_dot * hydro
	owner.apply_torque(torque)
	if drift_debug:
		drift_sums["align"] += torque.y


func _apply_roll_pitch_damping(owner, hydro: float, roll_damp: float,
		pitch_damp: float, drift_debug: bool, drift_sums: Dictionary) -> void:
	var roll_torque: Vector3 = -owner.angular_velocity.project(owner.global_basis.z) \
			* roll_damp * hydro
	var pitch_torque: Vector3 = -owner.angular_velocity.project(owner.global_basis.x) \
			* pitch_damp * hydro
	roll_torque.y = 0.0
	pitch_torque.y = 0.0
	owner.apply_torque(roll_torque + pitch_torque)
	if drift_debug:
		drift_sums["damp"] += (roll_torque + pitch_torque).y


func _water_velocity(ocean: Node, position: Vector3) -> Vector3:
	var velocity := Vector3.ZERO
	if ocean.has_method("current_at"):
		var current: Vector2 = ocean.call("current_at", position)
		velocity = Vector3(current.x, 0.0, current.y)
	if ocean.has_method("surface_velocity"):
		var orbital: Vector3 = ocean.call("surface_velocity", position)
		if orbital.is_finite():
			velocity += Vector3(orbital.x, 0.0, orbital.z)
	return velocity


func _apply_hull_forces(owner, ocean: Node, hydro: float,
		water_velocity: Vector3, drift_debug: bool,
		drift_sums: Dictionary) -> void:
	var velocity: Vector3 = owner.linear_velocity
	var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
	owner.apply_central_force(
			-(horizontal_velocity - water_velocity) * HULL_DRAG * hydro)
	owner.apply_central_force(Vector3.DOWN * velocity.y * 240.0 * hydro)
	var local_angular: Vector3 = owner.global_basis.inverse() * owner.angular_velocity
	var local_damping := Vector3(
			local_angular.x * 19000.0, 0.0, local_angular.z * 8200.0)
	var roll_pitch_torque: Vector3 = -(owner.global_basis * local_damping)
	roll_pitch_torque.y = 0.0
	owner.apply_torque(roll_pitch_torque * hydro)
	var yaw_torque: float = -owner.angular_velocity.y * 124000.0 * hydro
	owner.apply_torque(Vector3.UP * yaw_torque)
	if drift_debug:
		drift_sums["damp"] += yaw_torque
	var side: Vector3 = owner.global_basis.x
	var lateral_speed := side.dot(owner.linear_velocity - water_velocity)
	owner.apply_central_force(-side * lateral_speed * 5300.0 * hydro)
	owner.apply_central_force(ocean.call("wind_vector") * 26.0 * hydro)
