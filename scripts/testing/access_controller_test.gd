extends SceneTree
## Door animation, blocker and dive-gear visibility contract without boat scene.


func _initialize() -> void:
	var forward := Node3D.new()
	var aft := Node3D.new()
	var engine := Node3D.new()
	var wheelhouse := Node3D.new()
	var fuse_lid := Node3D.new()
	var locker := Node3D.new()
	var mask := Node3D.new()
	var tank := Node3D.new()
	fuse_lid.position = Vector3(1.14, 3.738, 1.12)
	for node in [forward, aft, engine, wheelhouse, fuse_lid, locker, mask, tank]:
		root.add_child(node)
	var controller := preload("res://scripts/boat_access_controller.gd").new()
	controller.setup(forward, aft, engine, wheelhouse, fuse_lid, locker, mask, tank)
	var door_blockers: Array[AABB] = []
	var aim_blockers: Array[AABB] = []
	controller.update(1.0, false, false, false, false, false, false, false,
			door_blockers, aim_blockers)
	var closed_blockers := door_blockers.size()
	var gear_transition: float = controller.update(1.0, true, true, true, true,
			true, true, true, door_blockers, aim_blockers)
	var complete := closed_blockers == 3 and door_blockers.is_empty() \
			and aim_blockers.size() == 1 and forward.rotation.y < -1.7 \
			and aft.rotation.y > 1.7 and engine.rotation.y > 1.8 \
			and wheelhouse.rotation.y > 2.7 and fuse_lid.rotation.x < -1.1 \
			and locker.rotation.y < -1.9 and gear_transition > 0.70 \
			and not mask.visible and not tank.visible
	print("[access-controller] closed=%d open=%d aim=%d gear=%.3f hidden=%s/%s complete=%s" % [
			closed_blockers, door_blockers.size(), aim_blockers.size(),
			gear_transition, not mask.visible, not tank.visible, complete])
	if not complete:
		push_error("boat access controller contract incomplete")
	quit(0 if complete else 1)
