extends SceneTree
## Diesel state, ignition and drivetrain presentation contract without boat scene.

class FakeEngineRoom extends Node:
	var last_state := -1
	var last_rpm := 0.0

	func drive(state: int, rpm: float, _delta: float) -> void:
		last_state = state
		last_rpm = rpm


func _initialize() -> void:
	var owner := Node3D.new()
	var lever := Node3D.new()
	var key := Node3D.new()
	var screw := Node3D.new()
	var motor := Node3D.new()
	var wheel := Node3D.new()
	var room := FakeEngineRoom.new()
	var led := StandardMaterial3D.new()
	for node in [owner, lever, key, screw, motor, wheel, room]:
		root.add_child(node)
	var controller := preload("res://scripts/boat_engine_controller.gd").new()
	controller.setup(owner, lever, key, led, room, screw, motor, wheel,
			null, null, null)
	var ignition := controller.turn_ignition(controller.OFF) as Dictionary
	var step := controller.step(2.2, int(ignition["engine"]), 0.0, 0.8,
			float(ignition["crank_left"])) as Dictionary
	controller.update_drivetrain(1.0, int(step["engine"]),
			float(step["rpm"]), 0.8, 0.6)
	var stopped := controller.turn_ignition(int(step["engine"])) as Dictionary
	var complete := bool(ignition["cranking"]) \
			and int(step["engine"]) == controller.RUNNING \
			and bool(step["caught"]) and float(step["rpm"]) > 0.50 \
			and int(stopped["engine"]) == controller.OFF \
			and lever.rotation_degrees.x < -20.0 \
			and key.rotation.y < -1.5 and led.emission_energy_multiplier > 2.0 \
			and room.last_state == controller.RUNNING \
			and is_equal_approx(room.last_rpm, float(step["rpm"])) \
			and absf(screw.rotation.y) > 0.1 \
			and motor.rotation.y > 0.25 and wheel.rotation.z > 2.0
	print("[engine-controller] state=%d rpm=%.3f lever=%.1f key=%.2f motor=%.2f wheel=%.2f complete=%s" % [
			int(step["engine"]), float(step["rpm"]), lever.rotation_degrees.x,
			key.rotation.y, motor.rotation.y, wheel.rotation.z, complete])
	if not complete:
		push_error("boat engine controller contract incomplete")
	quit(0 if complete else 1)
