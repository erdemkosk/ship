extends SceneTree

const EnvironmentScript := preload("res://scripts/boat_interior_environment.gd")


func _init() -> void:
	var environment: BoatInteriorEnvironment = EnvironmentScript.new()
	var identity := Transform3D.IDENTITY
	var cabin := environment.acoustic_space(identity, Vector3(0.0, 1.4, 1.0))
	var wheelhouse := environment.acoustic_space(identity, Vector3(0.0, 3.5, 1.0))
	var deck := environment.acoustic_space(identity, Vector3(2.5, 1.4, 1.0))
	var cabin_closed := environment.weather_openness(identity,
			Vector3(0.0, 1.4, -0.35), 0.0, 0.0, 0.0)
	var cabin_open := environment.weather_openness(identity,
			Vector3(0.0, 1.4, -0.35), 1.85, 0.0, 0.0)
	var near_heat := environment.heat_at(Vector3(1.28, 1.05, 4.28), 1.0)
	var outside_heat := environment.heat_at(Vector3(2.2, 1.05, 4.28), 1.0)
	var blockers: Array[AABB] = [AABB(Vector3(-0.10, -0.10, -0.10),
			Vector3(0.20, 0.20, 0.20))]
	var empty_boxes: Array[AABB] = []
	var obstruction := environment.rifle_obstruction_fraction(identity,
			Vector3(-1.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0), 0.0,
			blockers, empty_boxes, empty_boxes, [], [])
	var complete := cabin == &"cabin" and wheelhouse == &"wheelhouse" \
			and deck == &"deck" and absf(cabin_closed - 0.10) < 0.001 \
			and cabin_open > 0.80 and near_heat > 0.95 \
			and outside_heat == 0.0 and absf(obstruction - 0.45) < 0.001
	print("[interior-environment] spaces=%s/%s/%s weather=%.2f/%.2f heat=%.2f/%.2f obstruction=%.2f complete=%s" % [
			cabin, wheelhouse, deck, cabin_closed, cabin_open,
			near_heat, outside_heat, obstruction, complete])
	if not complete:
		push_error("boat interior environment contract incomplete")
	quit(0 if complete else 1)
