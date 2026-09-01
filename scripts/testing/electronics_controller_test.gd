extends SceneTree
## Pure runtime contract for articulated electronics; no boat scene required.


func _initialize() -> void:
	var controller := preload("res://scripts/boat_electronics_controller.gd").new()
	var scanner := Node3D.new()
	var radar_arm := Node3D.new()
	var radar_pivot := Node3D.new()
	var sounder_arm := Node3D.new()
	var sounder_pivot := Node3D.new()
	root.add_child(scanner)
	root.add_child(radar_arm)
	radar_arm.add_child(radar_pivot)
	root.add_child(sounder_arm)
	sounder_arm.add_child(sounder_pivot)
	var radar_home := Vector3(0.0, 4.2, 0.0)
	radar_arm.position = radar_home
	controller.setup(null, null, scanner, radar_arm, radar_pivot,
			sounder_arm, sounder_pivot, radar_home)
	var pulls: Vector2 = controller.update(1.0, false, 0.0, 1.0,
			1.0, 1.0, -1.2, 0.45, -0.8, 0.35, null)
	var complete := pulls.is_equal_approx(Vector2.ONE) \
			and radar_arm.rotation.y < -0.8 \
			and radar_arm.position.y < radar_home.y - 0.03 \
			and radar_pivot.rotation.y > 0.30 \
			and sounder_arm.rotation.y < -0.55 \
			and sounder_pivot.rotation.y > 0.24 \
			and absf(scanner.rotation.y) > 0.1
	print("[electronics-controller] radar=%.3f/%.3f sounder=%.3f scanner=%.3f complete=%s" % [
			radar_arm.rotation.y, radar_pivot.rotation.y,
			sounder_arm.rotation.y, scanner.rotation.y, complete])
	if not complete:
		push_error("boat electronics controller contract incomplete")
	quit(0 if complete else 1)
