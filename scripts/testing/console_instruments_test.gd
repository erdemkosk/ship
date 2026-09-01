extends SceneTree

const InstrumentsScript := preload("res://scripts/boat_console_instruments.gd")


func _init() -> void:
	var instruments: BoatConsoleInstruments = InstrumentsScript.new()
	var needles: Array[Node3D] = [Node3D.new(), Node3D.new(), Node3D.new()]
	var compass := Node3D.new()
	instruments.update_gauges(0.25, Basis.from_euler(Vector3(0.0, PI * 0.5, 0.0)),
			Vector3(5.0, 0.0, 0.0), Vector3.ZERO, null, null, needles, compass)
	var segments: Array[StandardMaterial3D] = []
	for _i in 13:
		var material := StandardMaterial3D.new()
		material.emission_enabled = true
		segments.append(material)
	var telegraph := Node3D.new()
	instruments.update_power(0.50, 0.50, true, 0.0, 1.0, segments, telegraph)
	var lit := 0
	for material in segments:
		if material.emission_energy_multiplier > 0.01:
			lit += 1
	var complete := absf(compass.rotation.y) > 0.10 \
			and absf(needles[0].rotation.y) > 0.02 \
			and lit >= 5 and telegraph.position.y > 3.80
	print("[console-instruments] compass=%.3f speed=%.3f lit=%d telegraph=%.3f complete=%s" % [
			compass.rotation.y, needles[0].rotation.y, lit,
			telegraph.position.y, complete])
	if not complete:
		push_error("boat console instruments contract incomplete")
	for node in needles:
		node.free()
	compass.free()
	telegraph.free()
	quit(0 if complete else 1)
