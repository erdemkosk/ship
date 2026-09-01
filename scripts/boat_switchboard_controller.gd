class_name BoatSwitchboardController
extends RefCounted
## Toggle/LED presentation, fuse cartridge motion and windlass power routing.


func update(delta: float, switch_levers: Dictionary, switch_leds: Dictionary,
		switch_state: Callable, circuit_live: Callable, blackout: float,
		supply: float, stove_switch: Node3D, stove_on: bool,
		fuse_bodies: Dictionary, electrical: BoatElectricalModel,
		tackle: Node) -> void:
	for id: String in switch_levers:
		var pivot := switch_levers[id] as Node3D
		pivot.rotation.x = lerpf(pivot.rotation.x,
				0.34 if bool(switch_state.call(id)) else -0.34,
				1.0 - exp(-16.0 * delta))
		var led := switch_leds.get(id) as StandardMaterial3D
		if led == null:
			continue
		var live := bool(circuit_live.call(id))
		led.emission = Color(1.0, 0.70, 0.28)
		led.emission_energy_multiplier = (2.0 if live else 0.0) \
				* (0.12 if blackout > 0.0 else (0.55 + 0.45 * supply))
	if stove_switch != null:
		stove_switch.rotation.x = lerpf(stove_switch.rotation.x,
				0.20 if stove_on else -0.20, 1.0 - exp(-18.0 * delta))
	for fuse_id: String in fuse_bodies:
		var cartridge := fuse_bodies[fuse_id] as Node3D
		if cartridge == null:
			continue
		var rest := float(cartridge.get_meta("rest_y", 3.676))
		var target_y := rest if electrical.is_seated(fuse_id) else rest + 0.032
		cartridge.position.y = lerpf(
				cartridge.position.y, target_y, 1.0 - exp(-14.0 * delta))
	if tackle != null:
		tackle.set("gypsy_powered", electrical.is_seated(&"sw_anchor"))
