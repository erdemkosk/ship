extends CanvasLayer
## Opening card: black field, DEEP TRAUMA centred, a light glitch, then gone.
## The sea is already running underneath — this only covers the eye.

const LOGO := preload("res://assets/ui/deep_trauma_logo.png")

var _logo: TextureRect
var _mat: ShaderMaterial
var _glitch := 0.0
var _t := 0.0


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_play()


func _build() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 1)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	_logo = TextureRect.new()
	_logo.texture = LOGO
	_logo.set_anchors_preset(Control.PRESET_FULL_RECT)
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logo.modulate.a = 0.0
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/logo_glitch.gdshader")
	_logo.material = _mat
	add_child(_logo)


func _play() -> void:
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(_logo, "modulate:a", 1.0, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.35)
	tw.tween_method(_set_glitch, 0.0, 0.28, 0.12)
	tw.tween_method(_set_glitch, 0.28, 0.06, 0.22)
	tw.tween_interval(0.55)
	tw.tween_method(_set_glitch, 0.06, 0.32, 0.10)
	tw.tween_method(_set_glitch, 0.32, 0.05, 0.28)
	tw.tween_interval(0.70)
	tw.tween_method(_set_glitch, 0.05, 0.42, 0.08)
	tw.parallel().tween_property(_logo, "modulate:a", 0.0, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_interval(0.12)
	tw.tween_callback(queue_free)


func _set_glitch(v: float) -> void:
	_glitch = v


func _process(delta: float) -> void:
	_t += delta
	if _mat != null:
		_mat.set_shader_parameter("amount", _glitch)
		_mat.set_shader_parameter("time", _t)


func _input(event: InputEvent) -> void:
	# Eat input so Tab / look / walk do not leak through the card.
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion:
		get_viewport().set_input_as_handled()
