class_name BoatLightingController
extends RefCounted
## Supply-sag flicker and cabin, helm, flood, beacon and nav-light output.


func update(delta: float, elapsed: float, previous_flicker: float,
		supply: float, blackout: float, cabin_live: bool, helm_live: bool,
		flood_live: bool, beacon_live: bool, weather: Node,
		cabin_lamp: OmniLight3D, helm_lamp: OmniLight3D,
		dial_ink: StandardMaterial3D, chart_lamp: SpotLight3D,
		lit_window: StandardMaterial3D, floods: Array[SpotLight3D],
		flood_lens: StandardMaterial3D, flood_beam: ShaderMaterial,
		helm_glow: StandardMaterial3D, beacon: OmniLight3D,
		beacon_material: StandardMaterial3D, nav_spots: Array[SpotLight3D],
		nav_materials: Array[StandardMaterial3D]) -> float:
	var target := 0.90 + 0.06 * sin(elapsed * 6.7) \
			+ 0.035 * sin(elapsed * 19.4 + 1.1)
	target *= (0.55 + 0.45 * supply) * (0.10 if blackout > 0.0 else 1.0)
	var flicker := lerpf(previous_flicker, target, 1.0 - exp(-12.0 * delta))
	if cabin_lamp != null:
		cabin_lamp.light_energy = lerpf(cabin_lamp.light_energy,
				1.7 * flicker if cabin_live else 0.0, 1.0 - exp(-9.0 * delta))
	if helm_lamp != null:
		helm_lamp.light_energy = lerpf(helm_lamp.light_energy,
				1.2 * flicker if helm_live else 0.0, 1.0 - exp(-9.0 * delta))
	if dial_ink != null:
		dial_ink.emission_energy_multiplier = 1.45 + 0.18 * sin(elapsed * 0.55)
	if chart_lamp != null:
		chart_lamp.light_energy = lerpf(chart_lamp.light_energy,
				7.5 * flicker if helm_live else 0.0, 1.0 - exp(-9.0 * delta))
	if lit_window != null:
		lit_window.emission_energy_multiplier = 2.2 * flicker if cabin_live else 0.0
	var flood_energy := 42.0 * flicker if flood_live else 0.0
	for flood in floods:
		flood.light_energy = lerpf(
				flood.light_energy, flood_energy, 1.0 - exp(-7.0 * delta))
	if flood_lens != null:
		flood_lens.emission_energy_multiplier = 8.0 * flicker if flood_live else 0.0
	if flood_beam != null:
		var haze := 1.0
		if weather != null:
			var rain: Variant = weather.get("rain_amount")
			if typeof(rain) == TYPE_FLOAT:
				haze += clampf(float(rain), 0.0, 1.0) * 0.6
		flood_beam.set_shader_parameter(
				"intensity", 1.35 * flicker if flood_live else 0.0)
		flood_beam.set_shader_parameter("haze", haze)
	if helm_glow != null:
		helm_glow.emission_energy_multiplier = 2.2 * flicker if helm_live else 0.0
	if beacon != null:
		var phase := fmod(elapsed, 2.40)
		var flash := 1.0 if (phase < 0.18 \
				or (phase >= 0.38 and phase < 0.56)) else 0.0
		var beacon_output := flash * flicker if beacon_live else 0.0
		beacon.light_energy = lerpf(beacon.light_energy,
				beacon_output * 4.8, 1.0 - exp(-10.0 * delta))
		if beacon_material != null:
			beacon_material.emission_energy_multiplier = beacon.light_energy * 1.8
	var nav_energy := 3.2 * flicker if beacon_live else 0.0
	for nav_spot in nav_spots:
		nav_spot.light_energy = lerpf(
				nav_spot.light_energy, nav_energy, 1.0 - exp(-10.0 * delta))
	for nav_material in nav_materials:
		nav_material.emission_energy_multiplier = \
				4.5 * flicker if beacon_live else 0.0
	return flicker
