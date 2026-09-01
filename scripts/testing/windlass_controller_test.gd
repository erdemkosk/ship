extends SceneTree
## Windlass rate and stowed-chain fraction contract.

class FakeTackle extends Node:
	var chain_rate := 0.32
	var chain_out := 10.5

class FakeChainVisual extends RefCounted:
	var stowed := -1.0
	var received_tackle: Node

	func tick(value: float, tackle: Node) -> void:
		stowed = value
		received_tackle = tackle


func _initialize() -> void:
	var windlass := Node3D.new()
	var tackle := FakeTackle.new()
	root.add_child(windlass)
	root.add_child(tackle)
	var visual := FakeChainVisual.new()
	preload("res://scripts/boat_windlass_controller.gd").new().update(
			0.5, windlass, tackle, visual)
	var complete := is_equal_approx(windlass.rotation.x, 1.0) \
			and is_equal_approx(visual.stowed, 0.75) \
			and visual.received_tackle == tackle
	print("[windlass-controller] rotation=%.2f stowed=%.2f complete=%s" % [
			windlass.rotation.x, visual.stowed, complete])
	if not complete:
		push_error("boat windlass controller contract incomplete")
	quit(0 if complete else 1)
