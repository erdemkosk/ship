class_name BoatMeshBatcher
extends RefCounted
## Collects static primitive meshes by material and emits combined draw calls.

var _host: Node3D
var _items: Dictionary = {}
var _active := true


func _init(host: Node3D) -> void:
	_host = host


func emit(mesh: Mesh, pos: Vector3, rotation_degrees: Vector3, material: Material,
		parent: Node3D, shadows: bool, batchable_shader_materials: Array[ShaderMaterial]) -> void:
	if _can_batch(material, parent, batchable_shader_materials):
		if not _items.has(material):
			_items[material] = []
		(_items[material] as Array).append({
			"mesh": mesh,
			"xform": _local_transform(pos, rotation_degrees),
			"shadow": shadows,
		})
		return
	var instance := MeshInstance3D.new()
	_set_material(mesh, material)
	instance.mesh = mesh
	instance.position = pos
	instance.rotation_degrees = rotation_degrees
	if not shadows:
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent != null else _host).add_child(instance)


func flush() -> void:
	_active = false
	for material: Material in _items:
		var material_items: Array = _items[material]
		if material_items.is_empty():
			continue
		if material_items.size() == 1:
			_emit_single(material_items[0], material)
			continue
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var any_shadow := false
		for item: Dictionary in material_items:
			any_shadow = any_shadow or bool(item["shadow"])
			surface.append_from(item["mesh"], 0, item["xform"])
		var instance := MeshInstance3D.new()
		instance.mesh = surface.commit()
		instance.material_override = material
		if not any_shadow:
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_host.add_child(instance)
	_items.clear()


func _can_batch(material: Material, parent: Node3D,
		batchable_shader_materials: Array[ShaderMaterial]) -> bool:
	if not _active or parent != null:
		return false
	if material is StandardMaterial3D:
		return true
	return material is ShaderMaterial and batchable_shader_materials.has(material)


func _emit_single(item: Dictionary, material: Material) -> void:
	var instance := MeshInstance3D.new()
	var mesh: Mesh = item["mesh"]
	_set_material(mesh, material)
	instance.mesh = mesh
	instance.transform = item["xform"]
	if not item["shadow"]:
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_host.add_child(instance)


func _set_material(mesh: Mesh, material: Material) -> void:
	if mesh is PrimitiveMesh:
		(mesh as PrimitiveMesh).material = material
	else:
		mesh.surface_set_material(0, material)


func _local_transform(pos: Vector3, rotation_degrees: Vector3) -> Transform3D:
	var radians := Vector3(
		deg_to_rad(rotation_degrees.x),
		deg_to_rad(rotation_degrees.y),
		deg_to_rad(rotation_degrees.z)
	)
	return Transform3D(Basis.from_euler(radians), pos)
