class_name BoatVisualFactory
extends RefCounted
## Stateless material and small effect-resource builders for the boat.


static func material(albedo: Color, roughness: float, metallic := 0.0) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = albedo
	result.roughness = roughness
	result.metallic = metallic
	return result


static func wet_hull_material(color: Color, roughness: float) -> ShaderMaterial:
	var result := ShaderMaterial.new()
	result.shader = load("res://shaders/wet_hull.gdshader")
	result.set_shader_parameter("albedo", color)
	result.set_shader_parameter("dry_roughness", roughness)
	return result


static func water_drop_mesh(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.1
	mesh.radial_segments = 8
	mesh.rings = 4
	var drop_material := StandardMaterial3D.new()
	drop_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	drop_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drop_material.albedo_color = Color(0.72, 0.82, 0.86, 0.45)
	drop_material.vertex_color_use_as_albedo = true
	drop_material.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	drop_material.distance_fade_min_distance = 16.0
	drop_material.distance_fade_max_distance = 2.2
	mesh.material = drop_material
	return mesh


static func spray_fade() -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	gradient.colors = PackedColorArray([
		Color(0.82, 0.9, 0.92, 0.7),
		Color(0.7, 0.8, 0.82, 0.28),
		Color(0.55, 0.62, 0.64, 0.0),
	])
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture
