class_name BoatChartTableVisualBuilder
extends RefCounted
## Physical chart, navigation tools, position pin and hooded chart lamp.


func build(owner: Node3D, trim: Material, metal: Material,
		helm_glow: Material, box_callback: Callable, cylinder_callback: Callable,
		material_callback: Callable) -> Dictionary:
	var center_x := 1.30
	var center_z := 2.88
	var top := 3.68
	var bronze: Material = material_callback.call(
			Color(0.34, 0.25, 0.12), 0.42, 0.75)
	box_callback.call(Vector3(0.60, 0.04, 0.03),
			Vector3(center_x, top + 0.045, center_z - 0.335),
			Vector3.ZERO, trim)
	box_callback.call(Vector3(0.60, 0.04, 0.03),
			Vector3(center_x, top + 0.045, center_z + 0.335),
			Vector3.ZERO, trim)
	box_callback.call(Vector3(0.03, 0.04, 0.70),
			Vector3(center_x - 0.285, top + 0.045, center_z),
			Vector3.ZERO, trim)
	box_callback.call(Vector3(0.03, 0.04, 0.70),
			Vector3(center_x + 0.285, top + 0.045, center_z),
			Vector3.ZERO, trim)

	var chart_material := ShaderMaterial.new()
	chart_material.shader = load("res://shaders/chart.gdshader")
	chart_material.set_shader_parameter("base_depth", -28.0)
	var sheet := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(0.50, 0.50)
	plane.material = chart_material
	sheet.mesh = plane
	sheet.position = Vector3(center_x, top + 0.012, center_z)
	sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	owner.add_child(sheet)

	var chart_pin := Node3D.new()
	owner.add_child(chart_pin)
	cylinder_callback.call(0.003, 0.008, 0.058,
			Vector3(0.0, 0.029, 0.0), Vector3.ZERO, bronze, chart_pin)
	var pin_head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.011
	head_mesh.height = 0.022
	head_mesh.material = material_callback.call(Color(0.55, 0.12, 0.08), 0.55)
	pin_head.mesh = head_mesh
	pin_head.position = Vector3(0.0, 0.066, 0.0)
	pin_head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chart_pin.add_child(pin_head)

	var rule_material: Material = material_callback.call(
			Color(0.18, 0.14, 0.10), 0.6)
	box_callback.call(Vector3(0.18, 0.010, 0.035),
			Vector3(center_x - 0.14, top + 0.035, center_z + 0.31),
			Vector3(0.0, 14.0, 0.0), rule_material)
	box_callback.call(Vector3(0.18, 0.010, 0.035),
			Vector3(center_x - 0.12, top + 0.035, center_z + 0.35),
			Vector3(0.0, 14.0, 0.0), rule_material)
	cylinder_callback.call(0.004, 0.004, 0.13,
			Vector3(center_x + 0.19, top + 0.075, center_z + 0.31),
			Vector3(28.0, 30.0, 0.0), bronze)
	cylinder_callback.call(0.004, 0.004, 0.13,
			Vector3(center_x + 0.21, top + 0.075, center_z + 0.31),
			Vector3(-28.0, 30.0, 0.0), bronze)
	cylinder_callback.call(0.007, 0.007, 0.12,
			Vector3(center_x + 0.06, top + 0.040, center_z + 0.34),
			Vector3(0.0, 62.0, 90.0),
			material_callback.call(Color(0.55, 0.42, 0.18), 0.8))
	cylinder_callback.call(0.022, 0.022, 0.28,
			Vector3(center_x - 0.02, top + 0.060, center_z - 0.32),
			Vector3(0.0, 0.0, 90.0),
			material_callback.call(Color(0.72, 0.66, 0.52), 0.9))

	var stem := Vector3(center_x - 0.24, top + 0.17, center_z - 0.34)
	var hood := Vector3(center_x - 0.18, top + 0.27, center_z - 0.24)
	var paper := Vector3(center_x, top + 0.02, center_z)
	box_callback.call(Vector3(0.025, 0.24, 0.025), stem, Vector3.ZERO, metal)
	cylinder_callback.call(0.065, 0.038, 0.085, hood,
			Vector3(42.0, 32.0, 0.0), metal)
	box_callback.call(Vector3(0.038, 0.018, 0.038),
			hood + Vector3(0.03, -0.04, 0.04), Vector3.ZERO, helm_glow)
	var chart_lamp := SpotLight3D.new()
	chart_lamp.position = hood + Vector3(0.04, -0.06, 0.06)
	chart_lamp.light_color = Color(1.0, 0.82, 0.55)
	chart_lamp.light_energy = 0.0
	chart_lamp.spot_range = 1.15
	chart_lamp.spot_angle = 34.0
	chart_lamp.spot_angle_attenuation = 0.85
	chart_lamp.spot_attenuation = 0.55
	chart_lamp.shadow_enabled = false
	owner.add_child(chart_lamp)
	chart_lamp.look_at(owner.global_transform * paper, Vector3.UP)
	return {
		"chart_material": chart_material,
		"chart_pin": chart_pin,
		"chart_lamp": chart_lamp,
	}
