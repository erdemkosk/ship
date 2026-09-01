extends SceneTree
## Procedure contract for hull/deck composition without loading the boat scene.


func _initialize() -> void:
	var counts := {"boxes": 0, "cylinders": 0, "prisms": 0,
			"nameboards": 0, "bulwarks": 0}
	var ladder_posts: Array[float] = []
	var box_callback := func(_size: Vector3, _position: Vector3,
			_rotation: Vector3, _material: Material, _parent = null) -> void:
		counts["boxes"] += 1
	var cylinder_callback := func(_bottom: float, _top: float, _height: float,
			position: Vector3, _rotation: Vector3, _material: Material,
			_parent = null) -> void:
		counts["cylinders"] += 1
		ladder_posts.append(position.x)
	var prism_callback := func(_aft_width: float, _length: float, _height: float,
			_position: Vector3, _material: Material) -> void:
		counts["prisms"] += 1
	var nameboard_callback := func() -> void:
		counts["nameboards"] += 1
	var bulwark_callback := func(_x: float, _face: float,
			_material: Material) -> void:
		counts["bulwarks"] += 1
	var material := StandardMaterial3D.new()
	preload("res://scripts/boat_hull_visual_builder.gd").new().build(
			material, material, material, material, material, material, material,
			1.32, box_callback, cylinder_callback, prism_callback,
			nameboard_callback, bulwark_callback)
	var complete: bool = counts["boxes"] == 21 and counts["cylinders"] == 2 \
			and counts["prisms"] == 5 and counts["nameboards"] == 1 \
			and counts["bulwarks"] == 2 \
			and is_equal_approx(ladder_posts[0], 1.16) \
			and is_equal_approx(ladder_posts[1], 1.48)
	print("[hull-visual] boxes=%d cylinders=%d prisms=%d name=%d bulwarks=%d complete=%s" % [
			counts["boxes"], counts["cylinders"], counts["prisms"],
			counts["nameboards"], counts["bulwarks"], complete])
	if not complete:
		push_error("boat hull visual builder contract incomplete")
	quit(0 if complete else 1)
