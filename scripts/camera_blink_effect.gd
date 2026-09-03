class_name CameraBlinkEffect
extends Node

var _rect: ColorRect
var _material: ShaderMaterial
var _close := 0.0
var _wait := 4.0
var _tween: Tween
var _again := false
var _fps_active := false
var _shot_delay := -1.0
var _shot_close := 0.0


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
	if _shot_delay >= 0.0:
		_shot_delay -= delta
		if _shot_delay <= 0.0:
			_shot_delay = -1.0
			_start(_shot_close, 0.030, 0.055)
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
	_shot_delay = -1.0
	_shot_close = 0.0
	if _material != null:
		_material.set_shader_parameter("close", 0.0)
	if _rect != null:
		_rect.visible = false


func trigger_shot(space: StringName, openness: float, aim: float) -> void:
	## A delayed involuntary squint, driven by the same enclosure information as
	## the rifle report. Outdoors it is occasional; hard cabin reflections make it
	## likely. ADS never fully hides the sight picture.
	if not _fps_active or _tween != null and _tween.is_running():
		return
	var enclosed := clampf(1.0 - openness, 0.0, 1.0)
	var chance := 0.25
	if space == &"wheelhouse":
		chance = lerpf(0.70, 0.82, enclosed)
	elif space == &"cabin":
		chance = lerpf(0.78, 0.90, enclosed)
	if randf() > chance:
		return
	_shot_close = lerpf(0.48, 0.68, enclosed)
	if aim > 0.70:
		_shot_close = minf(_shot_close, 0.55)
	_shot_delay = randf_range(0.035, 0.065)


func _start(max_close := 1.0, close_time := 0.055, open_time := 0.12) -> void:
	if _tween != null:
		_tween.kill()
	_close = 0.0
	_rect.visible = true
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_property(self, "_close", max_close, close_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_interval(0.018 if max_close < 0.95 else 0.035)
	_tween.tween_property(self, "_close", 0.0, open_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
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
