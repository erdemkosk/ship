extends SceneTree

const StoveScript := preload("res://scripts/boat_stove_controller.gd")


func _init() -> void:
	var controller: BoatStoveController = StoveScript.new()
	var lamp := OmniLight3D.new()
	var fill := OmniLight3D.new()
	var ember := StandardMaterial3D.new()
	ember.emission_enabled = true
	var reflector := StandardMaterial3D.new()
	reflector.emission_enabled = true
	controller.update(2.0, true, 0.0, 1.0, 0.5,
			lamp, fill, ember, reflector, null, null)
	var hot := controller.heat()
	var lit := lamp.visible and fill.visible and lamp.light_energy > fill.light_energy \
			and ember.emission_energy_multiplier > reflector.emission_energy_multiplier
	controller.update(3.0, false, 0.0, 1.0, 3.5,
			lamp, fill, ember, reflector, null, null)
	var cooling := controller.heat()
	controller.set_heat(2.0)
	var clamped := controller.heat()
	var complete := hot > 0.85 and lit and cooling < hot and clamped == 1.0
	print("[stove-controller] hot=%.3f cooling=%.3f clamped=%.1f lit=%s complete=%s" % [
			hot, cooling, clamped, lit, complete])
	if not complete:
		push_error("boat stove controller contract incomplete")
	lamp.free()
	fill.free()
	quit(0 if complete else 1)
