extends SceneTree
## Eye smoothing, stride output and chart-lean state contract.

class FakeBoat extends Node3D:
	const CHART_EYE := Vector3(0.4, 1.2, -0.6)

class FakeWalker extends RefCounted:
	var pos := Vector3.ZERO
	var vel := Vector3.ZERO
	var on_floor := true
	var swimming := false
	var on_sea_ladder := false

	func eye_local() -> Vector3:
		return pos + Vector3(0.0, 1.7, 0.0)


func _initialize() -> void:
	var boat := FakeBoat.new()
	root.add_child(boat)
	var walker := FakeWalker.new()
	var motion := preload("res://scripts/camera_eye_motion.gd").new()
	walker.vel = Vector3(3.0, 0.0, 0.0)
	var walk_result: Dictionary = motion.update(0.016, boat, walker, "",
			Transform3D.IDENTITY, Basis.IDENTITY, null, 0.0, null)
	var walk_ok := is_equal_approx(float(walk_result["walking"]), 1.0) \
			and (walk_result["position"] as Vector3).y > 1.65
	motion.reset()
	var chart_result: Dictionary = motion.update(0.225, boat, walker, "chart",
			Transform3D.IDENTITY, Basis.IDENTITY, null, 0.0, null)
	var chart_position := chart_result["position"] as Vector3
	var chart_ok := is_equal_approx(motion.chart_t, 0.5) \
			and chart_position.x > 0.15 and chart_position.z < -0.20 \
			and is_zero_approx(float(chart_result["walking"]))
	var complete := walk_ok and chart_ok
	print("[camera-eye-motion] walking=%s chart=%s complete=%s" % [
			walk_ok, chart_ok, complete])
	if not complete:
		push_error("camera eye motion contract incomplete")
	quit(0 if complete else 1)
