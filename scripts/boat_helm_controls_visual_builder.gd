class_name BoatHelmControlsVisualBuilder
extends RefCounted
## Physical flood/wiper switches, telegraph, shaft indicator and ignition.


func build(owner: Node3D, face: Node3D, trim: Material, metal: Material,
		bronze: Material, box_callback: Callable, cylinder_callback: Callable,
		material_callback: Callable, toggle_callback: Callable,
		label_callback: Callable) -> Dictionary:
	var switch_bronze: Material = material_callback.call(
			Color(0.36, 0.27, 0.13), 0.40, 0.75)
	var switch_face: Material = material_callback.call(
			Color(0.10, 0.07, 0.05), 0.64)
	box_callback.call(Vector3(0.32, 0.006, 0.12),
			Vector3(-0.66, 0.016, 0.02), Vector3.ZERO, switch_face, face)
	toggle_callback.call("sw_flood", Vector3(-0.56, 0.022, 0.00),
			"FLOOD", switch_bronze, face)
	toggle_callback.call("sw_wiper", Vector3(-0.76, 0.022, 0.00),
			"WIPER", switch_bronze, face)

	box_callback.call(Vector3(0.18, 0.17, 0.25),
			Vector3(0.58, 3.545, 0.175), Vector3.ZERO, metal)
	box_callback.call(Vector3(0.14, 0.055, 0.24),
			Vector3(0.58, 3.625, 0.185), Vector3.ZERO, bronze)
	var throttle_lever := Node3D.new()
	throttle_lever.position = Vector3(0.58, 3.62, 0.30)
	owner.add_child(throttle_lever)
	cylinder_callback.call(0.052, 0.052, 0.22, Vector3(0.58, 3.62, 0.22),
			Vector3(90.0, 0.0, 0.0), metal)
	cylinder_callback.call(0.043, 0.043, 0.018, Vector3(0.58, 3.62, 0.325),
			Vector3(90.0, 0.0, 0.0), bronze)
	var lever := MeshInstance3D.new()
	var lever_mesh := CylinderMesh.new()
	lever_mesh.top_radius = 0.020
	lever_mesh.bottom_radius = 0.026
	lever_mesh.height = 0.30
	lever_mesh.radial_segments = 8
	lever_mesh.rings = 1
	lever_mesh.material = bronze
	lever.mesh = lever_mesh
	lever.position = Vector3(0.0, 0.15, 0.0)
	throttle_lever.add_child(lever)
	var knob := MeshInstance3D.new()
	var knob_mesh := SphereMesh.new()
	knob_mesh.radius = 0.032
	knob_mesh.height = 0.064
	knob_mesh.material = trim
	knob.mesh = knob_mesh
	knob.position = Vector3(0.0, 0.31, 0.0)
	throttle_lever.add_child(knob)

	box_callback.call(Vector3(0.12, 0.42, 0.025),
			Vector3(0.87, 3.65, 0.02), Vector3.ZERO, trim)
	box_callback.call(Vector3(0.10, 0.014, 0.012),
			Vector3(0.87, 3.65, 0.038), Vector3.ZERO, bronze)
	var ahead_material: StandardMaterial3D = material_callback.call(
			Color(0.10, 0.55, 0.16), 0.6)
	ahead_material.emission_enabled = true
	ahead_material.emission = Color(0.12, 0.85, 0.20)
	ahead_material.emission_energy_multiplier = 0.6
	var astern_material: StandardMaterial3D = material_callback.call(
			Color(0.55, 0.10, 0.08), 0.6)
	astern_material.emission_enabled = true
	astern_material.emission = Color(0.9, 0.14, 0.08)
	astern_material.emission_energy_multiplier = 0.6
	var bezel: Material = material_callback.call(
			Color(0.30, 0.23, 0.11), 0.38, 0.78)
	box_callback.call(Vector3(0.085, 0.44, 0.030),
			Vector3(0.90, 3.70, 0.030), Vector3.ZERO, bezel)
	box_callback.call(Vector3(0.070, 0.42, 0.012),
			Vector3(0.90, 3.70, 0.046), Vector3.ZERO,
			material_callback.call(Color(0.045, 0.045, 0.042), 0.65))
	var power_segments: Array[StandardMaterial3D] = []
	for index in 13:
		var scale_index := index - 4
		var segment_y := 3.70 + float(scale_index) * 0.028
		var segment_material: StandardMaterial3D = material_callback.call(
				Color(0.05, 0.05, 0.05), 0.35)
		segment_material.emission_enabled = true
		segment_material.emission = Color(0.20, 1.0, 0.32) \
				if scale_index > 0 else (Color(1.0, 0.68, 0.16) \
				if scale_index == 0 else Color(1.0, 0.17, 0.09))
		segment_material.emission_energy_multiplier = 0.0
		box_callback.call(Vector3(0.048, 0.017, 0.008),
				Vector3(0.90, segment_y, 0.053), Vector3.ZERO, segment_material)
		power_segments.append(segment_material)
		var tick_width := 0.022 if scale_index % 4 == 0 else 0.012
		box_callback.call(Vector3(tick_width, 0.004, 0.006),
				Vector3(0.946 + tick_width * 0.5, segment_y, 0.046),
				Vector3.ZERO, bezel)
	var power_needle := Node3D.new()
	power_needle.position = Vector3(0.845, 3.70, 0.050)
	owner.add_child(power_needle)
	box_callback.call(Vector3(0.016, 0.020, 0.006), Vector3.ZERO,
			Vector3(0.0, 0.0, 45.0),
			material_callback.call(Color(0.52, 0.40, 0.16), 0.35, 0.7),
			power_needle)

	var ignition_position := Vector3(0.42, 3.64, 0.24)
	box_callback.call(Vector3(0.10, 0.17, 0.20),
			Vector3(ignition_position.x, 3.545, 0.145), Vector3.ZERO, metal)
	box_callback.call(Vector3(0.075, 0.045, 0.075),
			ignition_position + Vector3(0.0, -0.02, 0.0), Vector3.ZERO, bronze)
	cylinder_callback.call(0.022, 0.022, 0.04, ignition_position,
			Vector3.ZERO, bronze)
	cylinder_callback.call(0.010, 0.010, 0.03,
			ignition_position + Vector3(0.0, 0.018, 0.0), Vector3.ZERO, metal)
	var ignition_key := Node3D.new()
	ignition_key.position = ignition_position + Vector3(0.0, 0.028, 0.0)
	owner.add_child(ignition_key)
	box_callback.call(Vector3(0.010, 0.004, 0.055),
			Vector3(0.0, 0.0, 0.018), Vector3.ZERO, metal, ignition_key)
	cylinder_callback.call(0.016, 0.016, 0.005,
			Vector3(0.0, 0.0, 0.050), Vector3(90.0, 0.0, 0.0), bronze,
			ignition_key)
	box_callback.call(Vector3(0.022, 0.003, 0.008),
			Vector3(0.0, 0.0, 0.050), Vector3.ZERO, metal, ignition_key)
	var ignition_led: StandardMaterial3D = material_callback.call(
			Color(0.09, 0.09, 0.09), 0.30)
	ignition_led.emission_enabled = true
	ignition_led.emission = Color(1.0, 0.16, 0.10)
	ignition_led.emission_energy_multiplier = 1.1
	box_callback.call(Vector3(0.018, 0.010, 0.018),
			ignition_position + Vector3(0.055, -0.008, 0.02),
			Vector3.ZERO, bronze)
	var led_instance := MeshInstance3D.new()
	var led_mesh := SphereMesh.new()
	led_mesh.radius = 0.007
	led_mesh.height = 0.014
	led_mesh.material = ignition_led
	led_instance.mesh = led_mesh
	led_instance.position = ignition_position + Vector3(0.055, -0.002, 0.02)
	led_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	owner.add_child(led_instance)
	label_callback.call("KONTAK",
			ignition_position + Vector3(0.0, -0.018, 0.055), 28)
	return {
		"throttle_lever": throttle_lever,
		"power_segments": power_segments,
		"power_needle": power_needle,
		"ignition_key": ignition_key,
		"ignition_led": ignition_led,
	}
