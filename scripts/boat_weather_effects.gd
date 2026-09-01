class_name BoatWeatherEffects
extends Node

const ShaderSet := preload("res://scripts/shader_set.gd")
const WeatherScript := preload("res://scripts/weather.gd")
const WIPER_RATE := 2.6

var _host: Node3D
var _soak := 0.0
var _glass_wet := 0.0
var _rain_viewport: SubViewport
var _rain_material: ShaderMaterial
var _rain_age := 99.0
var _rain_field_wet := -1.0
var _wiper_phase := 0.0
var _wiper_pose := -1.08
var _shield_count := 0


func setup(host: Node3D) -> void:
	_host = host
	_build_rain_shields()


func build_rain_field(glass_material: ShaderMaterial,
		front_glass_material: ShaderMaterial) -> void:
	_rain_material = ShaderMaterial.new()
	_rain_material.shader = load("res://shaders/glass_rain_field.gdshader")
	_rain_viewport = SubViewport.new()
	_rain_viewport.name = "RainField"
	_rain_viewport.size = Vector2i(1024, 512)
	_rain_viewport.disable_3d = true
	_rain_viewport.transparent_bg = true
	_rain_viewport.gui_disable_input = true
	_rain_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_rain_viewport.msaa_2d = Viewport.MSAA_DISABLED
	var plate := ColorRect.new()
	plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.color = Color.WHITE
	plate.material = _rain_material
	_rain_viewport.add_child(plate)
	_host.add_child(_rain_viewport)
	var field: ViewportTexture = _rain_viewport.get_texture()
	if glass_material != null:
		ShaderSet.param(glass_material, &"rain_field", field)
	if front_glass_material != null:
		ShaderSet.param(front_glass_material, &"rain_field", field)


func update_hull_wetness(delta: float, ocean: Node3D, weather: Node3D,
		boat_position: Vector3, velocity: Vector3,
		hull_materials: Array[ShaderMaterial]) -> void:
	if ocean == null or hull_materials.is_empty():
		return
	var water_y: float = ocean.get_height(boat_position)
	var target := clampf(Vector2(velocity.x, velocity.z).length() / 7.0, 0.0, 1.0)
	target = maxf(target, clampf((ocean.get("sig_height") as float) / 5.0 - 0.35,
			0.0, 1.0))
	var active_weather := weather as WeatherScript
	if active_weather != null:
		target = maxf(target, clampf(active_weather.rain_amount * 1.25, 0.0, 1.0))
	var response := 2.5 if target > _soak else 0.35
	_soak = lerpf(_soak, target, 1.0 - exp(-response * delta))
	for material: ShaderMaterial in hull_materials:
		ShaderSet.param(material, &"water_y", water_y)
		ShaderSet.param(material, &"soak", _soak)


func update_glass(delta: float, weather: Node3D, wiper_live: bool,
		wiper_arm: Node3D, glass_material: ShaderMaterial,
		front_glass_material: ShaderMaterial) -> void:
	if wiper_live:
		_wiper_phase += delta * WIPER_RATE
	var angle := sin(_wiper_phase) * 1.02 if wiper_live else 0.0
	_wiper_pose = angle if wiper_live else lerpf(
			_wiper_pose, -1.08, 1.0 - exp(-6.0 * delta))
	if wiper_arm != null:
		wiper_arm.rotation.z = -_wiper_pose
	var rain_now := 0.0
	var active_weather := weather as WeatherScript
	if active_weather != null:
		rain_now = clampf(active_weather.rain_amount, 0.0, 1.0)
	if rain_now > _glass_wet:
		var wet_rate := 0.022 + rain_now * rain_now * 0.62
		_glass_wet = lerpf(_glass_wet, rain_now, 1.0 - exp(-wet_rate * delta))
	else:
		_glass_wet = maxf(rain_now, _glass_wet - delta * 0.038)
	if front_glass_material != null:
		ShaderSet.param(front_glass_material, &"wiper_on", 1 if wiper_live else 0)
		ShaderSet.param(front_glass_material, &"wiper_ang", angle)
		ShaderSet.param(front_glass_material, &"wiper_phase", _wiper_phase)
		ShaderSet.param(front_glass_material, &"wiper_rate", WIPER_RATE)
		ShaderSet.param(front_glass_material, &"rain", _glass_wet)
	if glass_material != null:
		ShaderSet.param(glass_material, &"rain", _glass_wet)
	_refresh_rain_field(delta)


func contract_report() -> Dictionary:
	return {
		"shield_count": _shield_count,
		"field_ready": _rain_viewport != null and _rain_material != null,
		"soak": _soak,
		"glass_wet": _glass_wet,
		"wiper_pose": _wiper_pose,
	}


func _build_rain_shields() -> void:
	for shield: Array in [
		[Vector3(4.28, 1.60, 10.10), Vector3(0.00, -0.25, 0.75)],
		[Vector3(3.78, 2.20, 5.30), Vector3(0.00, 1.80, 2.11)],
		[Vector3(3.68, 2.50, 4.60), Vector3(0.00, 4.15, 1.87)],
	]:
		var box := GPUParticlesCollisionBox3D.new()
		box.size = shield[0]
		box.position = shield[1]
		_host.add_child(box)
		_shield_count += 1


func _refresh_rain_field(delta: float) -> void:
	if _rain_viewport == null or _rain_material == null:
		return
	if _glass_wet <= 0.004:
		if _rain_field_wet > 0.004:
			ShaderSet.param(_rain_material, &"rain", 0.0)
			_rain_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
			_rain_field_wet = 0.0
		return
	_rain_age += delta
	if absf(_glass_wet - _rain_field_wet) < 0.012 and _rain_age < 0.14:
		return
	ShaderSet.param(_rain_material, &"rain", _glass_wet)
	_rain_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_rain_field_wet = _glass_wet
	_rain_age = 0.0
