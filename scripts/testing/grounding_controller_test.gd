extends SceneTree
## Seafloor contact and clear-water state contract without the boat scene.

class FlatSeafloor extends Node:
	func get_seafloor_height(_position: Vector3) -> float:
		return 0.0


func _initialize() -> void:
	var body := RigidBody3D.new()
	var ocean := FlatSeafloor.new()
	root.add_child(body)
	root.add_child(ocean)
	await process_frame
	var keel: Array[Vector3] = [Vector3.ZERO]
	var drift := {"ground": 0.0}
	var controller := preload("res://scripts/boat_grounding_controller.gd").new()
	body.global_position.y = -0.4
	var touching := controller.update(body, ocean, keel, true, drift)
	body.global_position.y = 2.0
	var clear := controller.update(body, ocean, keel, true, drift)
	var complete := touching and not clear
	print("[grounding-controller] touching=%s clear=%s complete=%s" % [
			touching, clear, complete])
	if not complete:
		push_error("boat grounding controller contract incomplete")
	quit(0 if complete else 1)
