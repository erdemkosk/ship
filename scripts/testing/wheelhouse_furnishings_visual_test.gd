extends SceneTree
## Chart table and helm builder runtime-reference contract.

var owner: Node3D


func _material(color: Color, roughness: float, metallic := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material


func _mesh(_a, _b, _c, _d, _e = null, _f = null, parent: Node3D = null) -> void:
	var node := MeshInstance3D.new()
	(parent if parent != null else owner).add_child(node)


func _initialize() -> void:
	owner = Node3D.new()
	root.add_child(owner)
	await process_frame
	var trim := _material(Color.WHITE, 0.5)
	var metal := _material(Color.GRAY, 0.5, 0.7)
	var glow := _material(Color.ORANGE, 0.4)
	var chart: Dictionary = preload(
			"res://scripts/boat_chart_table_visual_builder.gd").new().build(
			owner, trim, metal, glow, _mesh, _mesh, _material)
	var wheel: Node3D = preload(
			"res://scripts/boat_helm_visual_builder.gd").new().build(
			owner, trim, metal, _mesh, _material)
	var chart_material := chart["chart_material"] as ShaderMaterial
	var pin := chart["chart_pin"] as Node3D
	var lamp := chart["chart_lamp"] as SpotLight3D
	var complete := chart_material != null and chart_material.shader != null \
			and pin != null and pin.get_child_count() == 2 \
			and lamp != null and is_zero_approx(lamp.light_energy) \
			and wheel != null and wheel.get_child_count() == 8
	print("[wheelhouse-furnishings] pin=%d wheel=%d lamp=%s complete=%s" % [
			pin.get_child_count(), wheel.get_child_count(), lamp != null, complete])
	if not complete:
		push_error("wheelhouse furnishings visual contract incomplete")
	quit(0 if complete else 1)
