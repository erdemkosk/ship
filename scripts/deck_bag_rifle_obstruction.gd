class_name DeckBagRifleObstruction
extends RefCounted
## Keeps the carried rifle rigid while yielding the whole weapon around solids.


func resolve(owner: Node3D, frame: Transform3D, rifle: Node3D,
		camera: Camera3D) -> Transform3D:
	var boat := owner.get_parent()
	if boat == null or not boat.has_method("rifle_obstruction_fraction"):
		return frame
	if bool(boat.get_meta("rifle_test_ignore_obstruction", false)):
		return frame
	var muzzle := rifle.call("muzzle_node") as Node3D
	if muzzle == null:
		return frame
	var muzzle_world := frame * muzzle.position
	var eye := camera.global_position
	var fraction := float(boat.call("rifle_obstruction_fraction",
			eye, muzzle_world, 0.060))
	fraction = minf(fraction, _world_fraction(owner, eye, muzzle_world,
			boat, 0.060))
	if fraction >= 0.999:
		return frame
	# First yield like a person: draw the stock toward the chest and lower the
	# muzzle before translating the complete weapon away from the surface.
	var obstruction := clampf((1.0 - fraction) * 3.0, 0.0, 1.0)
	var lowered_basis := Basis.from_euler(Vector3(deg_to_rad(-52.0),
			deg_to_rad(-9.0), deg_to_rad(-8.0)))
	var lowered := camera.global_transform * Transform3D(lowered_basis,
			Vector3(0.235, -0.255, -0.300))
	frame = frame.interpolate_with(lowered, obstruction)
	muzzle_world = frame * muzzle.position
	fraction = float(boat.call("rifle_obstruction_fraction",
			eye, muzzle_world, 0.060))
	fraction = minf(fraction, _world_fraction(owner, eye, muzzle_world,
			boat, 0.060))
	if fraction >= 0.999:
		return frame
	var eye_to_muzzle := muzzle_world - eye
	var distance := eye_to_muzzle.length()
	if distance < 0.001:
		return frame
	var allowed := maxf(distance * fraction - 0.060, 0.04)
	frame.origin -= eye_to_muzzle.normalized() * (distance - allowed)
	return frame


func _world_fraction(owner: Node3D, from: Vector3, to: Vector3,
		boat: Node, radius: float) -> float:
	if owner.get_world_3d() == null:
		return 1.0
	var shape := SphereShape3D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, from)
	query.motion = to - from
	if boat is CollisionObject3D:
		query.exclude = [(boat as CollisionObject3D).get_rid()]
	var result := owner.get_world_3d().direct_space_state.cast_motion(query)
	return clampf(result[0], 0.0, 1.0) if result.size() >= 1 else 1.0
