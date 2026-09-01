extends SceneTree
## Cartridge-carry phase and hand/device metadata contract.

class FakeRifle extends Node3D:
	var elapsed := 1.20
	var chamber := Node3D.new()
	var bolt := Node3D.new()
	var cartridge := Node3D.new()

	func _init() -> void:
		chamber.position = Vector3(0.0, 0.02, -0.3)
		bolt.position = Vector3(0.08, 0.04, -0.2)
		add_child(chamber)
		add_child(bolt)
		add_child(cartridge)

	func reload_elapsed() -> float: return elapsed
	func chamber_node() -> Node3D: return chamber
	func bolt_handle_node() -> Node3D: return bolt
	func cartridge_node() -> Node3D: return cartridge
	func cartridge_palm_local() -> Vector3: return Vector3(0.0, 0.01, 0.0)
	func bolt_grip_transform() -> Transform3D: return bolt.transform
	func cartridge_contact_bounds() -> AABB:
		return AABB(Vector3(-0.01, -0.01, -0.03), Vector3(0.02, 0.02, 0.06))
	func bolt_contact_bounds() -> AABB:
		return AABB(Vector3(-0.02, -0.02, -0.02), Vector3(0.04, 0.04, 0.04))


func _initialize() -> void:
	var rifle := FakeRifle.new()
	var camera := Camera3D.new()
	var hand_target := Node3D.new()
	root.add_child(rifle)
	root.add_child(camera)
	root.add_child(hand_target)
	await process_frame
	var controller := preload(
			"res://scripts/deck_bag_rifle_reload_controller.gd").new()
	controller.update(rifle, camera, Transform3D.IDENTITY,
			Transform3D.IDENTITY, hand_target, Callable())
	var pose_ok: bool = str(hand_target.get_meta("hand_pose", "")) == "pinch"
	var attachment_ok: bool = bool(hand_target.get_meta("hand_attachment", false)) \
			and hand_target.get_meta("held_device") == rifle.cartridge
	var target_ok: bool = hand_target.has_meta("held_device_target") \
			and rifle.cartridge.global_transform.is_equal_approx(
					hand_target.get_meta("held_device_target") as Transform3D)
	var complete: bool = pose_ok and attachment_ok and target_ok
	print("[deck-bag-rifle-reload] pose=%s attachment=%s target=%s complete=%s" % [
			pose_ok, attachment_ok, target_ok, complete])
	if not complete:
		push_error("deck bag rifle reload controller contract incomplete")
	quit(0 if complete else 1)
