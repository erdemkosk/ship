extends SceneTree
## Telegraph, shaft indicator and ignition reference contract.

var toggle_count := 0
var label_count := 0


func _material(color: Color, roughness: float, metallic := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material


func _box(_size: Vector3, _position: Vector3, _rotation: Vector3,
		_material_value: Material, parent: Node3D = null) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	(parent if parent != null else root).add_child(instance)
	return instance


func _cylinder(_bottom: float, _top: float, _height: float,
		_position: Vector3, _rotation: Vector3, _material_value: Material,
		parent: Node3D = null) -> MeshInstance3D:
	return _box(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO,
			_material_value, parent)


func _toggle(_id: String, _position: Vector3, _caption: String,
		_bronze: Material, _parent: Node3D = null, _compact := false) -> void:
	toggle_count += 1


func _label(_text: String, _position: Vector3, _size: int) -> void:
	label_count += 1


func _initialize() -> void:
	var owner := Node3D.new()
	var face := Node3D.new()
	root.add_child(owner)
	owner.add_child(face)
	var trim := _material(Color.WHITE, 0.5)
	var metal := _material(Color.GRAY, 0.5, 0.7)
	var bronze := _material(Color.BROWN, 0.4, 0.7)
	var state: Dictionary = preload(
			"res://scripts/boat_helm_controls_visual_builder.gd").new().build(
			owner, face, trim, metal, bronze, _box, _cylinder, _material,
			_toggle, _label)
	var segments: Array = state["power_segments"]
	var complete := state["throttle_lever"] is Node3D \
			and state["power_needle"] is Node3D \
			and state["ignition_key"] is Node3D \
			and state["ignition_led"] is StandardMaterial3D \
			and segments.size() == 13 and toggle_count == 2 and label_count == 1
	print("[helm-controls-visual] segments=%d toggles=%d labels=%d complete=%s" % [
			segments.size(), toggle_count, label_count, complete])
	if not complete:
		push_error("boat helm controls visual builder contract incomplete")
	quit(0 if complete else 1)
