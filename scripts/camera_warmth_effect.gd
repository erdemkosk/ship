class_name CameraWarmthEffect
extends RefCounted
## Cabin heat colour grade. The host supplies its existing CanvasLayer so the
## effect remains between the underwater pass and the physical dive mask.

var _rect: ColorRect
var _material: ShaderMaterial
var _amount := 0.0


func setup(layer: CanvasLayer) -> void:
	_rect = ColorRect.new()
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.color = Color.WHITE
	_material = ShaderMaterial.new()
	_material.shader = load("res://shaders/warmth.gdshader")
	_rect.material = _material
	_rect.visible = false
	layer.add_child(_rect)


func tick(delta: float, boat: Node3D, walker: RefCounted, weather: Node3D,
		ocean: Node3D) -> void:
	if boat == null or walker == null or not boat.has_method("heat_at"):
		hide()
		return
	var source := 0.0
	var response_time := 1.1
	if bool(walker.get("swimming")):
		response_time = 1.4
	else:
		source = float(boat.call("heat_at", walker.get("pos")))
		if source < 0.05 and weather != null:
			source = maxf(source - _rain_amount(weather) * 0.10, 0.0)
		response_time = 0.9 if source > _amount else 1.8
	_amount = lerpf(_amount, source, 1.0 - exp(-delta / response_time))
	if _rect == null or _material == null:
		return
	var show := _amount > 0.16
	_rect.visible = show
	if not show:
		return
	var close := clampf((_amount - 0.72) / 0.28, 0.0, 1.0)
	_material.set_shader_parameter("warmth", clampf((_amount - 0.16) / 0.84, 0.0, 1.0))
	_material.set_shader_parameter("close", close)
	if ocean != null:
		_material.set_shader_parameter("wave_time", ocean.get("wave_time"))


func hide() -> void:
	if _rect != null:
		_rect.visible = false


static func _rain_amount(weather: Node3D) -> float:
	return clampf(float(weather.get("rain_amount")), 0.0, 1.0) if weather != null else 0.0
