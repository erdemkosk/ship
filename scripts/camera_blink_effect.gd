class_name CameraBlinkEffect
extends Node

var _rect: ColorRect
var _material: ShaderMaterial
var _close := 0.0
var _wait := 4.0
var _tween: Tween
var _again := false
var _fps_active := false


func setup(layer: CanvasLayer) -> void:
	_rect = ColorRect.new()
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.color = Color.WHITE
	_material = ShaderMaterial.new()
	_material.shader = load("res://shaders/blink.gdshader")
	_rect.material = _material
	_rect.visible = false
	layer.add_child(_rect)


func update(delta: float, fps_active: bool) -> void:
	_fps_active = fps_active
	if not fps_active or _rect == null or _material == null:
		return
	if _tween != null and _tween.is_running():
		_material.set_shader_parameter("close", _close)
		_rect.visible = _close > 0.004
		return
	_wait -= delta
	if _wait <= 0.0:
		_start()


func set_wait(value: float) -> void:
	_wait = value


func wait() -> float:
	return _wait


func stop() -> void:
	if _tween != null:
		_tween.kill()
		_tween = null
	_close = 0.0
	_again = false
	if _material != null:
		_material.set_shader_parameter("close", 0.0)
	if _rect != null:
		_rect.visible = false


func _start() -> void:
	if _tween != null:
		_tween.kill()
	_close = 0.0
	_rect.visible = true
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_property(self, "_close", 1.0, 0.055).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_interval(0.035)
	_tween.tween_property(self, "_close", 0.0, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.finished.connect(_on_finished, CONNECT_ONE_SHOT)


func _on_finished() -> void:
	_close = 0.0
	if _material != null:
		_material.set_shader_parameter("close", 0.0)
	if not _fps_active:
		stop()
		return
	if not _again and randf() < 0.18:
		_again = true
		_wait = 0.10
		return
	_again = false
	_wait = randf_range(3.2, 8.5)
	if _rect != null:
		_rect.visible = false
