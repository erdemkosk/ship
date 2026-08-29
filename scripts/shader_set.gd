extends RefCounted
## Skip ShaderMaterial.set_shader_parameter when the CPU already holds
## that value. The upload is the cost; the compare is not.
##
## Preload this script — do not wait for a class_name. A hot-reload can
## parse boat/weather/ocean before the global name is registered.

static var _cache: Dictionary = {} # instance_id -> Dictionary[StringName, Variant]


static func param(mat: ShaderMaterial, pname: StringName, value: Variant) -> void:
	if mat == null:
		return
	var id: int = mat.get_instance_id()
	var bucket: Dictionary
	if _cache.has(id):
		bucket = _cache[id]
		if bucket.has(pname) and _same(bucket[pname], value):
			return
	else:
		bucket = {}
		_cache[id] = bucket
	bucket[pname] = value
	mat.set_shader_parameter(pname, value)


static func many(mats: Array[ShaderMaterial], pname: StringName, value: Variant) -> void:
	for mat: ShaderMaterial in mats:
		param(mat, pname, value)


static func _same(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		return false
	match typeof(a):
		TYPE_FLOAT:
			return is_equal_approx(a, b)
		TYPE_VECTOR2:
			return (a as Vector2).is_equal_approx(b)
		TYPE_VECTOR3:
			return (a as Vector3).is_equal_approx(b)
		TYPE_VECTOR4:
			return (a as Vector4).is_equal_approx(b)
		TYPE_COLOR:
			return (a as Color).is_equal_approx(b)
		TYPE_TRANSFORM3D:
			return (a as Transform3D).is_equal_approx(b)
		TYPE_BASIS:
			return (a as Basis).is_equal_approx(b)
		TYPE_QUATERNION:
			return (a as Quaternion).is_equal_approx(b)
		_:
			return a == b
