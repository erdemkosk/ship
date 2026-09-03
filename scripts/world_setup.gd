class_name WorldSetup
extends RefCounted
## Builds the runtime relationships between the scene's independent systems.

const GroundTackleScript := preload("res://scripts/ground_tackle.gd")
const FlotsamScript := preload("res://scripts/flotsam.gd")
const MooringHarborScript := preload("res://scripts/mooring_harbor.gd")


static func connect_world(root: Node3D, boat: RigidBody3D, ocean: Node3D,
		weather: Node3D, rig: Node3D, seabed: Node3D, ui: CanvasLayer) -> void:
	boat.ocean = ocean
	boat.weather = weather
	boat.camera_rig = rig
	ocean.follow_target = boat
	seabed.follow_target = boat
	ocean.bind_seabed(seabed)
	_place_boat(boat, ocean, seabed)
	rig.target = boat
	rig.ocean = ocean
	rig.weather = weather
	weather.ocean = ocean
	weather.boat = boat
	var harbor := MooringHarborScript.new()
	root.add_child(harbor)
	harbor.call("setup", boat, ocean, seabed)
	ocean.set("harbor", harbor)
	_configure_shore_start(rig, boat, seabed, harbor)
	var tackle := GroundTackleScript.new()
	tackle.boat = boat
	tackle.ocean = ocean
	root.add_child(tackle)
	boat.tackle = tackle
	ui.setup(ocean, weather)
	_spawn_flotsam(root, ocean)


static func _place_boat(boat: RigidBody3D, ocean: Node3D, seabed: Node3D) -> void:
	var island := Vector2(float(seabed.LIGHTHOUSE_X), float(seabed.LIGHTHOUSE_Z))
	var berth := Vector3(island.x + 380.0, 0.0, island.y)
	# Find the nearest navigable pocket around the island. Checking the whole
	# hull prevents a visually good centre point from putting bow or stern ashore.
	var found := false
	for radius in range(220, 326, 3):
		for step in 36:
			var angle := float(step) / 36.0 * TAU
			var candidate := Vector3(island.x + cos(angle) * radius, 0.0,
					island.y + sin(angle) * radius)
			if _is_berth_water(ocean, candidate):
				berth = candidate
				found = true
				break
		if found:
			break
	boat.global_position = Vector3(berth.x,
			float(ocean.get_height(berth)) + 1.2, berth.z)
	var toward_island := Vector3(island.x - berth.x, 0.0, island.y - berth.z).normalized()
	# Stern ladder faces the beach; the bow points out to sea ready to depart.
	var bow := -toward_island
	boat.rotation = Vector3(0.0, atan2(-bow.x, -bow.z), 0.0)
	boat.linear_velocity = Vector3.ZERO
	boat.angular_velocity = Vector3.ZERO


static func _is_berth_water(ocean: Node3D, centre: Vector3) -> bool:
	for offset in [Vector2.ZERO, Vector2(0.0, -6.0), Vector2(0.0, 6.0),
			Vector2(-2.8, 0.0), Vector2(2.8, 0.0)]:
		var point := centre + Vector3(offset.x, 0.0, offset.y)
		var depth := float(ocean.get_height(point)) \
				- float(ocean.get_seafloor_height(point))
		if depth < 4.0:
			return false
	return true


static func _configure_shore_start(rig: Node3D, boat: RigidBody3D,
		seabed: Node3D, harbor: Node3D) -> void:
	if not rig.has_method("set_initial_shore_spawn"):
		return
	if harbor != null and harbor.has_method("player_spawn"):
		var harbor_spawn: Vector3 = harbor.call("player_spawn") as Vector3
		rig.call("set_initial_shore_spawn", harbor_spawn, boat.global_position)
		return
	var island := Vector3(float(seabed.LIGHTHOUSE_X), 0.0,
			float(seabed.LIGHTHOUSE_Z))
	# Start on the dry beach facing the separately placed boat. Walk from the
	# berth toward the lighthouse until land rises above even a small wave, then
	# go a few metres farther inland so the first swell cannot spawn us swimming.
	var spawn := island
	var shore_found := false
	for metre in range(1, 150):
		var candidate := boat.global_position.move_toward(island, float(metre))
		var bed := float(seabed.call("get_walk_height", candidate))
		var water := float(boat.ocean.call("get_height", candidate))
		if bed > water + 0.55:
			spawn = candidate.move_toward(island, 4.0)
			shore_found = true
			break
	if not shore_found:
		spawn = island + Vector3(-9.5, 0.0, -8.0)
	spawn.y = float(seabed.call("get_walk_height", spawn)) + 0.05
	rig.call("set_initial_shore_spawn", spawn, boat.global_position)


static func _is_open_water(ocean: Node3D, x: float, z: float) -> bool:
	const MIN_BED := -8.0
	const HULL_RADIUS := 8.0
	const OFFSETS: Array[Vector2] = [
		Vector2.ZERO,
		Vector2(1.0, 0.0), Vector2(-1.0, 0.0),
		Vector2(0.0, 1.0), Vector2(0.0, -1.0),
		Vector2(0.71, 0.71), Vector2(-0.71, 0.71),
		Vector2(0.71, -0.71), Vector2(-0.71, -0.71),
	]
	for offset: Vector2 in OFFSETS:
		var point := Vector3(x + offset.x * HULL_RADIUS, 0.0,
				z + offset.y * HULL_RADIUS)
		if ocean.get_seafloor_height(point) > MIN_BED:
			return false
	return true


static func _spawn_flotsam(root: Node3D, ocean: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260827
	var specs: Array[Vector3] = [
		Vector3(-8.0, 0.0, 6.0), Vector3(-11.0, 1.0, 9.0),
		Vector3(-14.0, 2.0, 7.0), Vector3(12.0, 0.0, 11.0),
		Vector3(-22.0, 1.0, 28.0), Vector3(24.0, 0.0, -18.0),
		Vector3(-36.0, 2.0, 32.0), Vector3(44.0, 0.0, 20.0),
		Vector3(-26.0, 1.0, -40.0), Vector3(58.0, 0.0, -46.0),
		Vector3(-64.0, 2.0, 52.0),
	]
	for spec: Vector3 in specs:
		var position := Vector3(spec.x, 0.8, spec.z)
		if ocean.get_seafloor_height(position) > -1.6:
			continue
		var debris := FlotsamScript.new()
		debris.kind = int(spec.y)
		debris.ocean = ocean
		debris.spawn_yaw = rng.randf() * TAU
		root.add_child(debris)
		debris.global_position = position
