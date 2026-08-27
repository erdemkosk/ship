extends MeshInstance3D
## Expanding foam ring. Mesh size stays fixed; the shader grows the ring
## so UVs don't swim backward. Position follows the Gerstner water particle
## at rest-xz so the ring rides the chop instead of clipping in and out.

var ocean: Node3D
var strength := 1.0
var origin_xz := Vector2.ZERO
var pooled := false
var life := 1.85

var _age := 0.0
var _mat: ShaderMaterial


func _ready() -> void:
	_mat = material_override as ShaderMaterial
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	extra_cull_margin = 4.0
	if pooled:
		visible = false
		set_process(false)
		return
	_bind_origin(Vector2(global_position.x, global_position.z))
	var span := 2.4 + 3.6 * strength
	scale = Vector3(span, 1.0, span)
	_place()


func retrigger(xz: Vector2, str: float, duration := 0.75, span := -1.0) -> void:
	pooled = true
	strength = str
	life = duration
	_age = 0.0
	_bind_origin(xz)
	if span < 0.0:
		span = 0.38 + 0.55 * str
	scale = Vector3(span, 1.0, span)
	if _mat == null:
		_mat = material_override as ShaderMaterial
	if _mat != null:
		_mat.set_shader_parameter("age", 0.0)
	visible = true
	set_process(true)
	_place()


func _bind_origin(world_xz: Vector2) -> void:
	if ocean != null and ocean.has_method("rest_xz"):
		origin_xz = ocean.rest_xz(world_xz)
	else:
		origin_xz = world_xz


func _place() -> void:
	if ocean == null:
		return
	if ocean.has_method("surface_point"):
		global_position = ocean.surface_point(origin_xz) + Vector3(0.0, 0.07, 0.0)
	else:
		global_position.y = ocean.get_height(global_position) + 0.07


func _process(delta: float) -> void:
	_age += delta
	var t := _age / maxf(life, 0.05)
	if t >= 1.0:
		if pooled:
			visible = false
			set_process(false)
			return
		queue_free()
		return
	if _mat != null:
		_mat.set_shader_parameter("age", t)
	_place()
