extends SceneTree
## Probe buoyancy and fitted water-plane contract without the full boat scene.

class FakeOcean extends Node:
	var slam_count := 0

	func get_height(position: Vector3) -> float:
		return 0.1 * position.x - 0.05 * position.z

	func get_normal(_position: Vector3) -> Vector3:
		return Vector3.UP

	func hull_slam(_position: Vector3, _probe: Vector3, _strength: float) -> void:
		slam_count += 1


func _initialize() -> void:
	var body := RigidBody3D.new()
	var ocean := FakeOcean.new()
	root.add_child(body)
	root.add_child(ocean)
	await process_frame
	var probes: Array[Vector3] = [
		Vector3(-1.0, -0.4, -2.0), Vector3(1.0, -0.4, -2.0),
		Vector3(-1.0, -0.4, 2.0), Vector3(1.0, -0.4, 2.0),
	]
	var controller := preload("res://scripts/boat_buoyancy_controller.gd").new()
	controller.setup(probes.size())
	var state: Dictionary = controller.update(
			body, ocean, probes, 0.016, 13500.0, 3100.0, true)
	var normal: Vector3 = state["wave_normal"]
	var expected := Vector3(-0.1, 1.0, 0.05).normalized()
	var complete := is_equal_approx(float(state["submerged"]), 1.0) \
			and is_equal_approx(float(state["hydro"]), 1.0) \
			and normal.distance_to(expected) < 0.001 \
			and not bool(state["slammed"]) and ocean.slam_count == 0
	print("[buoyancy-controller] submerged=%.2f hydro=%.2f normal=%s complete=%s" % [
			float(state["submerged"]), float(state["hydro"]), normal, complete])
	if not complete:
		push_error("boat buoyancy controller contract incomplete")
	quit(0 if complete else 1)
