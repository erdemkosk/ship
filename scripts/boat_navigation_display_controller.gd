class_name BoatNavigationDisplayController
extends RefCounted
## Shared power sag and navigation-display state for sounder, chart and radar.

var supply := 1.0
var blackout := 0.0
var _depth_elapsed := 0.0
var _depth_head := 0
var _depth_history: PackedFloat32Array
var _chart_texture_set := false
var _sounder_material: ShaderMaterial
var _chart_material: ShaderMaterial
var _radar_material: ShaderMaterial
var _chart_pin: Node3D


func setup(sounder_material: ShaderMaterial, chart_material: ShaderMaterial,
		radar_material: ShaderMaterial, chart_pin: Node3D,
		depth_history: PackedFloat32Array) -> void:
	_sounder_material = sounder_material
	_chart_material = chart_material
	_radar_material = radar_material
	_chart_pin = chart_pin
	_depth_history = depth_history


func update(delta: float, weather: Node, vertical_speed: float, ocean: Node,
		position: Vector3, basis: Basis, helm_circuit_live: bool) -> Vector2:
	_update_supply(delta, weather, vertical_speed)
	var visible_power := 0.05 if blackout > 0.0 else 1.0
	_update_sounder(delta, ocean, position, helm_circuit_live, visible_power)
	_update_chart_texture(ocean)
	_update_navigation_fix(position, basis, helm_circuit_live, visible_power)
	return Vector2(supply, blackout)


func _update_supply(delta: float, weather: Node, vertical_speed: float) -> void:
	var roughness := 0.0
	if weather != null:
		roughness = clampf(float(weather.get("wind_speed")) / 34.0 * 0.55
				+ float(weather.get("rain_amount")) * 0.28
				+ (0.30 if bool(weather.get("storm")) else 0.0), 0.0, 1.0)
	roughness = clampf(roughness
			+ clampf(absf(vertical_speed) / 7.0, 0.0, 0.30), 0.0, 1.0)
	supply = lerpf(supply, 1.0 - roughness * 0.88,
			1.0 - exp(-1.4 * delta))
	if blackout > 0.0:
		blackout -= delta
	elif randf() < roughness * roughness * delta * 1.6:
		blackout = randf_range(0.10, 0.85)


func _update_sounder(delta: float, ocean: Node, position: Vector3,
		helm_circuit_live: bool, visible_power: float) -> void:
	if _sounder_material == null:
		return
	var depth := 0.0
	if ocean != null:
		depth = maxf(float(ocean.call("get_height", position))
				- float(ocean.call("get_seafloor_height", position)), 0.0)
	_depth_elapsed += delta
	if _depth_elapsed > 0.5:
		_depth_elapsed = 0.0
		_depth_history[_depth_head] = depth
		_depth_head = (_depth_head + 1) % 64
		_sounder_material.set_shader_parameter("depth_hist", _depth_history)
		_sounder_material.set_shader_parameter("head", _depth_head)
	_sounder_material.set_shader_parameter("depth_now", depth)
	_sounder_material.set_shader_parameter("lit",
			(1.0 if helm_circuit_live else 0.35) * visible_power)
	_sounder_material.set_shader_parameter("power", supply)


func _update_chart_texture(ocean: Node) -> void:
	if _chart_material == null or _chart_texture_set or ocean == null:
		return
	var seabed := ocean.get("seabed") as Node
	if seabed == null:
		return
	var height_texture := seabed.get("height_texture") as Texture2D
	if height_texture == null:
		return
	_chart_material.set_shader_parameter("height_tex", height_texture)
	_chart_texture_set = true
	if _radar_material != null:
		_radar_material.set_shader_parameter("height_tex", height_texture)
		_radar_material.set_shader_parameter("terrain_size", 2048.0)


func _update_navigation_fix(position: Vector3, basis: Basis,
		helm_circuit_live: bool, visible_power: float) -> void:
	if _chart_material == null:
		return
	var chart_u := fposmod(position.x / 2048.0 + 0.5, 1.0)
	var chart_v := fposmod(position.z / 2048.0 + 0.5, 1.0)
	var forward := -basis.z
	var heading := atan2(forward.x, -forward.z)
	_chart_material.set_shader_parameter("boat_uv", Vector2(chart_u, chart_v))
	_chart_material.set_shader_parameter("boat_head", heading)
	if _radar_material != null:
		_radar_material.set_shader_parameter("boat_uv", Vector2(chart_u, chart_v))
		_radar_material.set_shader_parameter("boat_head", heading)
		_radar_material.set_shader_parameter("lit",
				(1.0 if helm_circuit_live else 0.30) * visible_power)
		_radar_material.set_shader_parameter("power", supply)
	if _chart_pin != null:
		_chart_pin.position = Vector3(
				1.05 + chart_u * 0.50, 3.712, 2.63 + chart_v * 0.50)


func contract_report() -> Dictionary:
	return {
		"supply": supply,
		"blackout": blackout,
		"depth_head": _depth_head,
		"depth_samples": _depth_history.size(),
		"chart_texture_set": _chart_texture_set,
		"chart_pin": _chart_pin.position if _chart_pin != null else Vector3.INF,
	}
