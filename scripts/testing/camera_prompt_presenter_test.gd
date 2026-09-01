extends SceneTree
## Bag, swimming, ignition and fuse prompt precedence contract.

class FakeBag extends Node:
	var loaded := false

	func active_item_node() -> Node3D:
		return null

	func slot_label(_index: int) -> String:
		return "Utility knife"

	func slot_occupied(_index: int) -> bool:
		return true

	func rifle_reloading() -> bool:
		return false

	func rifle_loaded() -> bool:
		return loaded

class FakeWalker extends RefCounted:
	var on_sea_ladder := false
	var swimming := false
	var can_board := false
	var submerged := false

class FakeTarget extends Node:
	var engine := 0
	var gear_worn := false
	var radio_held := false
	var locker_open := false

	func fuse_seated(_id: String) -> bool:
		return false


func _initialize() -> void:
	var prompt := Label.new()
	var bag := FakeBag.new()
	var target := FakeTarget.new()
	root.add_child(prompt)
	root.add_child(bag)
	root.add_child(target)
	var walker := FakeWalker.new()
	var presenter := preload("res://scripts/camera_prompt_presenter.gd").new()
	presenter.update(prompt, 1.0, 0, bag, "", walker, target, "", null,
			{}, 0.0, 0.0, 0.0, 0.0)
	var bag_ok := "Utility knife" in prompt.text and prompt.visible
	presenter.update(prompt, 0.0, 0, bag, "hunting_rifle", walker, target,
			"", null, {}, 0.0, 0.0, 0.0, 0.0)
	var rifle_ok := prompt.text.begins_with("Empty")
	walker.swimming = true
	presenter.update(prompt, 0.0, 0, bag, "", walker, target, "", null,
			{}, 0.0, 0.0, 0.0, 0.0)
	var swim_ok := "in the sea" in prompt.text
	walker.swimming = false
	var fuse := {"id": "fu_cabin", "name": "Cabin fuse"}
	presenter.update(prompt, 0.0, 0, bag, "", walker, target, "", null,
			fuse, 0.0, 0.0, 0.0, 0.0)
	var fuse_ok := "Cabin fuse" in prompt.text and "out" in prompt.text
	var complete := bag_ok and rifle_ok and swim_ok and fuse_ok
	print("[camera-prompt-presenter] bag=%s rifle=%s swim=%s fuse=%s complete=%s" % [
			bag_ok, rifle_ok, swim_ok, fuse_ok, complete])
	if not complete:
		push_error("camera prompt presenter contract incomplete")
	quit(0 if complete else 1)
