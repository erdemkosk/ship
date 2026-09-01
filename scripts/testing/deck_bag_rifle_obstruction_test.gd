extends SceneTree
## Rifle obstruction passthrough, test bypass and rigid-yield contract.

class FakeBoat extends Node3D:
	func rifle_obstruction_fraction(_from: Vector3, _to: Vector3,
			_radius: float) -> float:
		return 0.35

class FakeRifle extends Node3D:
	var muzzle := Node3D.new()

	func _init() -> void:
		muzzle.position = Vector3(0.0, 0.0, -1.0)
		add_child(muzzle)

	func muzzle_node() -> Node3D:
		return muzzle


func _initialize() -> void:
	var resolver := preload("res://scripts/deck_bag_rifle_obstruction.gd").new()
	var plain_parent := Node3D.new()
	var plain_owner := Node3D.new()
	root.add_child(plain_parent)
	plain_parent.add_child(plain_owner)
	var rifle := FakeRifle.new()
	var camera := Camera3D.new()
	root.add_child(rifle)
	root.add_child(camera)
	await process_frame
	var frame := Transform3D(Basis.IDENTITY, Vector3(0.2, -0.1, -0.3))
	var passthrough := resolver.resolve(plain_owner, frame, rifle, camera)
	var passthrough_ok := passthrough.is_equal_approx(frame)

	var boat := FakeBoat.new()
	var owner := Node3D.new()
	root.add_child(boat)
	boat.add_child(owner)
	await process_frame
	boat.set_meta("rifle_test_ignore_obstruction", true)
	var ignored := resolver.resolve(owner, frame, rifle, camera)
	var ignored_ok := ignored.is_equal_approx(frame)
	boat.set_meta("rifle_test_ignore_obstruction", false)
	var yielded := resolver.resolve(owner, frame, rifle, camera)
	var yield_ok := not yielded.is_equal_approx(frame)
	var complete := passthrough_ok and ignored_ok and yield_ok
	print("[deck-bag-rifle-obstruction] passthrough=%s ignored=%s yield=%s complete=%s" % [
			passthrough_ok, ignored_ok, yield_ok, complete])
	if not complete:
		push_error("deck bag rifle obstruction contract incomplete")
	quit(0 if complete else 1)
