extends SceneTree
## Toggle, LED, fuse motion and windlass supply runtime contract.

class FakeTackle extends Node:
	var gypsy_powered := false


func _on(_id: String) -> bool:
	return true


func _initialize() -> void:
	var lever := Node3D.new()
	var stove := Node3D.new()
	var cartridge := Node3D.new()
	var tackle := FakeTackle.new()
	for node in [lever, stove, cartridge, tackle]:
		root.add_child(node)
	cartridge.position.y = 1.0
	cartridge.set_meta("rest_y", 1.0)
	var led := StandardMaterial3D.new()
	led.emission_enabled = true
	var electrical := preload("res://scripts/boat_electrical_model.gd").new()
	electrical.register_fuse(&"fu_test")
	electrical.register_fuse(&"fu_anchor")
	electrical.toggle_fuse(&"fu_test")
	var controller := preload("res://scripts/boat_switchboard_controller.gd").new()
	controller.update(0.5, {"sw_test": lever}, {"sw_test": led},
			_on, _on, 0.0, 1.0, stove, true, {"fu_test": cartridge},
			electrical, tackle)
	var complete := lever.rotation.x > 0.3 and stove.rotation.x > 0.19 \
			and led.emission_energy_multiplier > 1.9 \
			and cartridge.position.y > 1.03 and tackle.gypsy_powered
	print("[switchboard-controller] lever=%.3f stove=%.3f led=%.2f fuse=%.3f powered=%s complete=%s" % [
			lever.rotation.x, stove.rotation.x, led.emission_energy_multiplier,
			cartridge.position.y, tackle.gypsy_powered, complete])
	if not complete:
		push_error("boat switchboard controller contract incomplete")
	quit(0 if complete else 1)
