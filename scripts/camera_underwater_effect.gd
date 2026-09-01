class_name CameraUnderwaterEffect
extends RefCounted
## Waterline transition, underwater grade and ambient suspended particles.

var _rect: ColorRect
var _material: ShaderMaterial
var _motes: GPUParticles3D
var _bubbles: GPUParticles3D


func setup(layer: CanvasLayer, host: Node3D) -> void:
	_rect = ColorRect.new()
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.color = Color.WHITE
	_material = ShaderMaterial.new()
	_material.shader = load("res://shaders/underwater.gdshader")
	_rect.material = _material
	_rect.visible = false
	layer.add_child(_rect)
	_motes = _make_motes()
	host.add_child(_motes)
	_motes.top_level = true
	_bubbles = _make_bubbles()
	host.add_child(_bubbles)
	_bubbles.top_level = true


func tick(camera: Camera3D, ocean: Node3D, weather: Node3D) -> bool:
	if ocean == null or camera == null:
		return false
	var water_height := float(ocean.call("get_height", camera.global_position))
	var depth := water_height - camera.global_position.y
	var underwater := depth > 0.025
	var fade := smoothstep(-0.035, 0.16, depth)
	ocean.set("camera_under", underwater)
	if weather != null and weather.has_method("set_underwater"):
		weather.call("set_underwater", underwater)
	_rect.visible = fade > 0.002
	if fade > 0.002:
		_material.set_shader_parameter("amount", fade)
		_material.set_shader_parameter("wave_time", ocean.get("wave_time"))
		_material.set_shader_parameter("depth_m", maxf(depth, 0.0))
		_material.set_shader_parameter("look_down",
				clampf(-camera.global_basis.z.y, 0.0, 1.0))
		_update_sun(camera, weather)
	_motes.emitting = underwater
	_bubbles.emitting = underwater
	if underwater:
		_motes.global_position = camera.global_position
		_bubbles.global_position = camera.global_position + Vector3(0.0, -2.0, 0.0)
	return underwater


func _update_sun(camera: Camera3D, weather: Node3D) -> void:
	if weather == null or not weather.has_method("sun_direction"):
		return
	var sun_direction: Vector3 = weather.call("sun_direction")
	var viewport_size := camera.get_viewport().get_visible_rect().size
	var screen_position := Vector2(0.5, -0.35)
	var local := camera.global_basis.inverse() * sun_direction
	if local.z < -0.05:
		var projected := camera.unproject_position(camera.global_position + sun_direction * 200.0)
		screen_position = Vector2(projected.x / maxf(viewport_size.x, 1.0),
				projected.y / maxf(viewport_size.y, 1.0))
		screen_position = screen_position.clamp(Vector2(-1.0, -1.0), Vector2(2.0, 2.0))
	_material.set_shader_parameter("sun_screen", screen_position)
	var night := bool(weather.call("is_night")) if weather.has_method("is_night") else false
	var shaft_energy := 0.62 if night else 1.05
	if bool(weather.get("storm")):
		shaft_energy *= 0.50
	if sun_direction.y < 0.05:
		shaft_energy *= 0.28
	_material.set_shader_parameter("shaft_energy", shaft_energy)
	_material.set_shader_parameter("lamp_tight", 0.48 if night else 1.15)
	var tint := Color(0.70, 0.80, 0.96) if night else Color(1.0, 0.90, 0.62)
	if weather.has_method("sun_tint"):
		tint = tint.lerp(weather.call("sun_tint") as Color, 0.45)
	_material.set_shader_parameter("shaft_color", tint)


func _make_motes() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = 280
	particles.lifetime = 6.5
	particles.preprocess = 2.5
	particles.emitting = false
	particles.transform_align = GPUParticles3D.TRANSFORM_ALIGN_DISABLED
	particles.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.visibility_aabb = AABB(Vector3(-22, -14, -22), Vector3(44, 28, 44))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(10.0, 6.0, 10.0)
	process.gravity = Vector3(0, 0.015, 0)
	process.initial_velocity_min = 0.01
	process.initial_velocity_max = 0.05
	process.scale_min = 0.010
	process.scale_max = 0.028
	process.color = Color(0.52, 0.58, 0.54, 0.18)
	particles.process_material = process
	var mesh := SphereMesh.new()
	mesh.radius = 0.005
	mesh.height = 0.010
	mesh.radial_segments = 6
	mesh.rings = 3
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.disable_fog = true
	material.albedo_color = Color(0.55, 0.62, 0.58, 0.16)
	mesh.material = material
	particles.draw_pass_1 = mesh
	return particles


func _make_bubbles() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = 140
	particles.lifetime = 3.6
	particles.preprocess = 1.8
	particles.emitting = false
	particles.transform_align = GPUParticles3D.TRANSFORM_ALIGN_DISABLED
	particles.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.visibility_aabb = AABB(Vector3(-14, -10, -14), Vector3(28, 24, 28))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(6.0, 4.0, 6.0)
	process.direction = Vector3.UP
	process.spread = 12.0
	process.initial_velocity_min = 0.25
	process.initial_velocity_max = 0.75
	process.gravity = Vector3(0, 1.1, 0)
	process.damping_min = 0.1
	process.damping_max = 0.4
	process.scale_min = 0.25
	process.scale_max = 1.0
	particles.process_material = process
	var mesh := SphereMesh.new()
	mesh.radius = 0.016
	mesh.height = 0.032
	mesh.radial_segments = 6
	mesh.rings = 3
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.78, 0.92, 0.95, 0.42)
	material.roughness = 0.05
	material.disable_fog = true
	material.rim_enabled = true
	material.rim = 0.9
	mesh.material = material
	particles.draw_pass_1 = mesh
	return particles
