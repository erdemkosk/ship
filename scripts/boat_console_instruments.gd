class_name BoatConsoleInstruments
extends RefCounted


func update_gauges(delta: float, boat_basis: Basis, velocity: Vector3,
		boat_position: Vector3, ocean: Node3D, tackle: Node3D,
		needles: Array[Node3D], compass_card: Node3D) -> void:
	if needles.size() < 3:
		return
	var response := 1.0 - exp(-5.0 * delta)
	var forward := -boat_basis.z
	var heading := fmod(rad_to_deg(atan2(forward.x, -forward.z)) + 360.0, 360.0)
	if compass_card != null:
		compass_card.rotation.y = lerp_angle(compass_card.rotation.y,
				deg_to_rad(heading), response * 0.6)
	needles[0].rotation.y = lerp_angle(needles[0].rotation.y,
			_dial_angle(Vector2(velocity.x, velocity.z).length() * 1.94384, 20.0),
			response)
	var depth := 0.0
	if ocean != null:
		var bed: float = ocean.get_seafloor_height(boat_position)
		var surface: float = ocean.get_height(boat_position)
		depth = maxf(surface - bed - 0.75, 0.0)
	needles[1].rotation.y = lerp_angle(needles[1].rotation.y,
			_dial_angle(depth, 40.0), response)
	var chain := float(tackle.get("chain_out")) if tackle != null else 0.0
	needles[2].rotation.y = lerp_angle(needles[2].rotation.y,
			_dial_angle(chain, 70.0), response)


func update_power(rpm: float, throttle: float, engine_running: bool,
		blackout: float, supply: float, segments: Array[StandardMaterial3D],
		needle: Node3D) -> void:
	for i in segments.size():
		var index := i - 4
		var level := 0.0
		if index > 0:
			level = clampf((rpm - float(index - 1) * 0.125) / 0.125, 0.0, 1.0)
		elif index < 0:
			level = clampf((-rpm - float(-index - 1) * 0.10) / 0.10, 0.0, 1.0)
		elif engine_running:
			level = 0.30
		var energy := level * (2.6 if level > 0.55 else 1.5)
		segments[i].emission_energy_multiplier = energy \
				* (0.12 if blackout > 0.0 else (0.55 + 0.45 * supply))
	if needle != null:
		var telegraph_step := throttle / (0.125 if throttle >= 0.0 else 0.10)
		needle.position.y = 3.70 + clampf(telegraph_step, -4.0, 8.0) * 0.028


func _dial_angle(value: float, full_scale: float) -> float:
	return -deg_to_rad(-120.0 + clampf(value / full_scale, 0.0, 1.0) * 240.0)
