class_name WorldSetup
extends RefCounted
## Builds the runtime relationships between the scene's independent systems.

const GroundTackleScript := preload("res://scripts/ground_tackle.gd")
const FlotsamScript := preload("res://scripts/flotsam.gd")


static func connect_world(root: Node3D, boat: RigidBody3D, ocean: Node3D,
		weather: Node3D, rig: Node3D, seabed: Node3D, ui: CanvasLayer) -> void:
	boat.ocean = ocean
	boat.weather = weather
	boat.camera_rig = rig
	ocean.follow_target = boat
	seabed.follow_target = boat
	ocean.bind_seabed(seabed)
	_place_boat(boat, ocean)
	rig.target = boat
	rig.ocean = ocean
	rig.weather = weather
	weather.ocean = ocean
	weather.boat = boat
	var tackle := GroundTackleScript.new()
	tackle.boat = boat
	tackle.ocean = ocean
	root.add_child(tackle)
	boat.tackle = tackle
	ui.setup(ocean, weather)
	_spawn_flotsam(root, ocean)


static func _place_boat(boat: RigidBody3D, ocean: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for _attempt in 80:
		var x := rng.randf_range(-920.0, 920.0)
		var z := rng.randf_range(-920.0, 920.0)
		if not _is_open_water(ocean, x, z):
			continue
		boat.global_position = Vector3(x, 1.2, z)
		boat.rotation = Vector3(0.0, rng.randf() * TAU, 0.0)
		boat.linear_velocity = Vector3.ZERO
		boat.angular_velocity = Vector3.ZERO
		return
	boat.global_position = Vector3(0.0, 1.2, 0.0)


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
