extends SceneTree

const LocatorScript := preload("res://scripts/boat_interaction_locator.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var locator: BoatInteractionLocator = LocatorScript.new()
	var cabin_latch := Vector3(1.02, 1.58, 0.072)
	var wheelhouse_latch := Vector3(-0.98, 0.92, 0.072)
	var forward_inside := locator.door_latch_local("door_fwd",
			Vector3(0.0, 1.0, 0.0), cabin_latch, wheelhouse_latch,
			-0.45, 4.65, 4.05)
	var forward_outside := locator.door_latch_local("door_fwd",
			Vector3(0.0, 1.0, -1.0), cabin_latch, wheelhouse_latch,
			-0.45, 4.65, 4.05)
	var wheelhouse_inside := locator.door_latch_local("door_wh",
			Vector3(0.0, 3.2, 3.8), cabin_latch, wheelhouse_latch,
			-0.45, 4.65, 4.05)
	var root_node := Node3D.new()
	root.add_child(root_node)
	var stove := Node3D.new()
	stove.position = Vector3(1.0, 2.0, 3.0)
	root_node.add_child(stove)
	var lever := Node3D.new()
	lever.position = Vector3(-1.0, 1.0, 0.5)
	root_node.add_child(lever)
	var switch_levers := {"sw_test": lever}
	var position := locator.interaction_position("sw_test", Vector3.ZERO,
			Transform3D.IDENTITY, Vector3.ZERO, null, Vector3.ZERO, stove,
			switch_levers, {}, {}, null, cabin_latch, wheelhouse_latch,
			-0.45, 4.65, 4.05)
	var stove_position := locator.interaction_position("stove", Vector3.ZERO,
			Transform3D.IDENTITY, Vector3.ZERO, null, Vector3.ZERO, stove,
			switch_levers, {}, {}, null, cabin_latch, wheelhouse_latch,
			-0.45, 4.65, 4.05)
	var complete := forward_inside.z > 0.0 and forward_outside.z < 0.0 \
			and wheelhouse_inside.z < 0.0 \
			and position.is_equal_approx(Vector3(-1.0, 1.046, 0.5)) \
			and stove_position.is_equal_approx(Vector3(1.0, 2.0, 3.0))
	print("[interaction-locator] fwd=%.3f/%.3f wheel=%.3f switch=%s stove=%s complete=%s" % [
			forward_inside.z, forward_outside.z, wheelhouse_inside.z,
			position, stove_position, complete])
	if not complete:
		push_error("boat interaction locator contract incomplete")
	root_node.free()
	quit(0 if complete else 1)
