class_name BoatStoveController
extends RefCounted

var _heat := 0.0


func heat() -> float:
	return _heat


func set_heat(value: float) -> void:
	_heat = clampf(value, 0.0, 1.0)


func update(delta: float, switched_on: bool, blackout: float, supply: float,
		clock: float, lamp: OmniLight3D, fill: OmniLight3D,
		ember: StandardMaterial3D, reflector: StandardMaterial3D,
		heat_particles: GPUParticles3D, sound: AudioStreamPlayer3D) -> void:
	var powered := 1.0 if switched_on and blackout <= 0.0 else 0.0
	powered *= clampf(supply, 0.0, 1.0)
	var response_time := 0.85 if powered > _heat else 2.4
	_heat = lerpf(_heat, powered, 1.0 - exp(-delta / response_time))
	var shimmer := 1.0 + 0.030 * sin(clock * 21.4) \
			+ 0.018 * sin(clock * 3.7 + 1.1)
	var glow := _heat * shimmer
	if lamp != null:
		lamp.light_energy = 5.2 * glow
		lamp.visible = glow > 0.004
	if fill != null:
		fill.light_energy = 2.8 * glow
		fill.visible = glow > 0.008
	if ember != null:
		ember.emission_energy_multiplier = 8.4 * glow
		ember.emission = Color(1.0, 0.22 + 0.34 * _heat,
				0.04 + 0.14 * _heat)
	if reflector != null:
		reflector.emission_energy_multiplier = 2.4 * glow
	if heat_particles != null:
		heat_particles.emitting = _heat > 0.12
	if sound != null:
		if _heat > 0.05:
			if not sound.playing:
				sound.play()
			sound.volume_db = linear_to_db(clampf(_heat * 0.55, 0.02, 1.0))
		elif sound.playing:
			sound.stop()
