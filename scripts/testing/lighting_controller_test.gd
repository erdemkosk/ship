extends SceneTree
## Supply flicker and all physical light families contract.


func _material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.emission_enabled = true
	return material


func _initialize() -> void:
	var cabin := OmniLight3D.new()
	var helm := OmniLight3D.new()
	var chart := SpotLight3D.new()
	var flood := SpotLight3D.new()
	var beacon := OmniLight3D.new()
	var nav := SpotLight3D.new()
	for light in [cabin, helm, chart, flood, beacon, nav]:
		root.add_child(light)
	var dial := _material()
	var window := _material()
	var lens := _material()
	var helm_glow := _material()
	var beacon_material := _material()
	var nav_material := _material()
	var floods: Array[SpotLight3D] = [flood]
	var nav_spots: Array[SpotLight3D] = [nav]
	var nav_materials: Array[StandardMaterial3D] = [nav_material]
	var controller := preload("res://scripts/boat_lighting_controller.gd").new()
	var flicker := controller.update(0.5, 0.10, 1.0, 1.0, 0.0,
			true, true, true, true, null, cabin, helm, dial, chart, window,
			floods, lens, null, helm_glow, beacon, beacon_material,
			nav_spots, nav_materials)
	var complete := flicker > 0.8 and cabin.light_energy > 1.0 \
			and helm.light_energy > 0.8 and chart.light_energy > 5.0 \
			and flood.light_energy > 30.0 and beacon.light_energy > 3.0 \
			and nav.light_energy > 2.0 and window.emission_energy_multiplier > 1.0 \
			and lens.emission_energy_multiplier > 6.0 \
			and nav_material.emission_energy_multiplier > 3.0
	print("[lighting-controller] flicker=%.3f cabin=%.2f flood=%.2f beacon=%.2f nav=%.2f complete=%s" % [
			flicker, cabin.light_energy, flood.light_energy,
			beacon.light_energy, nav.light_energy, complete])
	if not complete:
		push_error("boat lighting controller contract incomplete")
	quit(0 if complete else 1)
