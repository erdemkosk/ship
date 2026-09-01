extends SceneTree
## Current/orbital flow composition and reversible rudder-flow contract.

class MovingOcean extends Node:
	func current_at(_position: Vector3) -> Vector2:
		return Vector2(1.0, 2.0)

	func surface_velocity(_position: Vector3) -> Vector3:
		return Vector3(0.5, 0.8, -0.25)

	func wind_vector() -> Vector3:
		return Vector3(0.2, 0.0, 0.1)


func _initialize() -> void:
	var body := RigidBody3D.new()
	var ocean := MovingOcean.new()
	root.add_child(body)
	root.add_child(ocean)
	await process_frame
	var controller := preload("res://scripts/boat_hydrodynamics_controller.gd").new()
	var drift := {"align": 0.0, "rudder": 0.0, "damp": 0.0}
	var ahead: Dictionary = controller.update(body, ocean, 1.0, 1.0,
			Vector3.UP, 0.5, 0.4, 32800.0, 33000.0, 17500.0,
			9000.0, true, drift)
	var astern: Dictionary = controller.update(body, ocean, 1.0, 1.0,
			Vector3.UP, -1.0, 0.4, 32800.0, 33000.0, 17500.0,
			9000.0, true, drift)
	var water: Vector3 = ahead["water_velocity"]
	var complete := water.distance_to(Vector3(1.5, 0.0, 1.75)) < 0.001 \
			and float(ahead["stream"]) > 0.0 \
			and float(astern["stream"]) < 0.0 \
			and float(ahead["flow"]) > 0.0 and float(astern["flow"]) > 0.0 \
			and absf(float(drift["rudder"])) > 0.0
	print("[hydrodynamics-controller] water=%s stream=%.2f/%.2f flow=%.3f/%.3f complete=%s" % [
			water, float(ahead["stream"]), float(astern["stream"]),
			float(ahead["flow"]), float(astern["flow"]), complete])
	if not complete:
		push_error("boat hydrodynamics controller contract incomplete")
	quit(0 if complete else 1)
