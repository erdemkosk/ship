extends SceneTree
## Crosshair selection, closed-well filtering and focus gate contract.

class FakeBoat extends RigidBody3D:
	const INTERACT := [
		{"id": "fu_cabin", "pos": Vector3(0.0, 0.0, -0.8), "r": 0.20},
		{"id": "chart", "pos": Vector3(0.03, 0.0, -1.0), "r": 0.20},
		{"id": "radio", "pos": Vector3(0.16, 0.0, -1.0), "r": 0.20},
	]
	var fusebox_open := false
	var locker_open := false
	var gear_worn := false

	func switch_in_well(id: String) -> bool:
		return id == "sw_cabin"

	func interact_pos(_id: String, fallback: Vector3) -> Vector3:
		return fallback


func _visible(_target, _from: Vector3, _to: Vector3) -> bool:
	return false


func _initialize() -> void:
	var boat := FakeBoat.new()
	root.add_child(boat)
	var selector := preload("res://scripts/camera_interaction_selector.gd").new()
	var selected: Dictionary = selector.select(boat, Vector3.ZERO,
			Vector3(0.0, 0.0, -1.0), "", 0.0, "", null, _visible)
	var focused: Dictionary = selected["candidate"]
	var gated: Dictionary = selector.select(boat, Vector3.ZERO,
			Vector3(0.0, 0.0, -1.0), "", 0.5, "", null, _visible)
	var chart_mode: Dictionary = selector.select(boat, Vector3.ZERO,
			Vector3(0.0, 0.0, -1.0), "chart", 0.0, "", null, _visible)
	var complete := str(focused.get("id", "")) == "chart" \
			and str(selected["last_aim"]) == "chart" \
			and (gated["candidate"] as Dictionary).is_empty() \
			and (chart_mode["candidate"] as Dictionary).is_empty()
	print("[camera-interaction-selector] selected=%s focus_gate=%s chart_gate=%s complete=%s" % [
			focused.get("id", ""), (gated["candidate"] as Dictionary).is_empty(),
			(chart_mode["candidate"] as Dictionary).is_empty(), complete])
	if not complete:
		push_error("camera interaction selector contract incomplete")
	quit(0 if complete else 1)
