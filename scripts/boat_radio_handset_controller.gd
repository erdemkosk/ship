class_name BoatRadioHandsetController
extends RefCounted
## VHF handset pose, finite cord reach and coiled-cord presentation.

const ANCHOR := Vector3(1.548, 3.915, 0.50)
const CRADLE := Vector3(1.49, 3.94, 0.55)
const CORD_LENGTH := 2.40

var _pull_time := 0.0


func update(owner: Node3D, handset: Node3D, cord: Array[MeshInstance3D],
		camera_rig: Node3D, held: bool, pose_locked: bool,
		delta: float) -> bool:
	if handset == null:
		return held
	var in_first_person := false
	var camera: Camera3D = null
	if camera_rig != null:
		var mode: Variant = camera_rig.get("mode")
		in_first_person = typeof(mode) == TYPE_INT and mode == 1
		var camera_value: Variant = camera_rig.get("_cam")
		if camera_value is Camera3D:
			camera = camera_value
	if held and in_first_person and not pose_locked:
		held = _update_free_pose(owner, handset, camera, held, delta)
	elif held and in_first_person and pose_locked:
		held = _update_locked_reach(owner, handset, camera, held, delta)
	if not held:
		_pull_time = 0.0
		if not pose_locked:
			handset.position = handset.position.lerp(
					CRADLE, 1.0 - exp(-9.0 * delta))
			handset.rotation.x = lerpf(
					handset.rotation.x, 0.0, 1.0 - exp(-9.0 * delta))
			handset.rotation.y = lerpf(
					handset.rotation.y, 0.0, 1.0 - exp(-9.0 * delta))
			handset.rotation.z = lerpf(
					handset.rotation.z, 0.209, 1.0 - exp(-9.0 * delta))
	_update_cord(owner, handset, cord)
	return held


func _update_free_pose(owner: Node3D, handset: Node3D, camera: Camera3D,
		held: bool, delta: float) -> bool:
	if camera == null or not camera.global_position.is_finite():
		return held
	var wanted: Vector3 = owner.global_transform.affine_inverse() \
			* (camera.global_position
			+ camera.global_basis * Vector3(0.205, -0.125, -0.275))
	var reach := wanted - ANCHOR
	if reach.length() > CORD_LENGTH:
		_pull_time += delta
		wanted = ANCHOR + reach.normalized() * CORD_LENGTH
		if _pull_time > 0.45:
			held = false
	else:
		_pull_time = 0.0
	handset.position = handset.position.lerp(wanted, 1.0 - exp(-22.0 * delta))
	var camera_basis := camera.global_basis
	var handset_z: Vector3 = (
			camera_basis * Vector3(0.11, -0.90, -0.42)).normalized()
	var handset_x: Vector3 = (
			camera_basis * Vector3(0.94, 0.19, -0.28)).normalized()
	var handset_y: Vector3 = handset_z.cross(handset_x).normalized()
	handset_x = handset_y.cross(handset_z).normalized()
	var wanted_basis: Basis = owner.global_basis.inverse() \
			* Basis(handset_x, handset_y, handset_z)
	handset.basis = handset.basis.slerp(wanted_basis.orthonormalized(),
			1.0 - exp(-16.0 * delta))
	return held


func _update_locked_reach(owner: Node3D, handset: Node3D, camera: Camera3D,
		held: bool, delta: float) -> bool:
	if camera == null:
		return held
	var local_handset: Vector3 = owner.global_transform.affine_inverse() \
			* handset.global_position
	if (local_handset - ANCHOR).length() > CORD_LENGTH + 0.04:
		_pull_time += delta
		if _pull_time > 0.45:
			held = false
	else:
		_pull_time = 0.0
	return held


func _update_cord(owner: Node3D, handset: Node3D,
		cord: Array[MeshInstance3D]) -> void:
	var local_handset := owner.global_transform.affine_inverse() \
			* handset.global_transform
	var endpoint: Vector3 = local_handset.origin \
			+ local_handset.basis * Vector3(0.0, -0.012, 0.108)
	var count := cord.size()
	for index in count:
		var start := _cord_point(float(index) / float(count), ANCHOR, endpoint)
		var finish := _cord_point(
				float(index + 1) / float(count), ANCHOR, endpoint)
		var segment := finish - start
		var length := segment.length()
		var mesh := cord[index]
		mesh.position = (start + finish) * 0.5
		if length > 1.0e-5:
			var up := segment / length
			var reference := Vector3.RIGHT \
					if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
			var basis_x := reference.cross(up).normalized()
			mesh.basis = Basis(basis_x, up * length, basis_x.cross(up))


func _cord_point(t: float, start: Vector3, finish: Vector3) -> Vector3:
	var direction := finish - start
	var distance := direction.length()
	var slack := clampf(1.0 - distance / CORD_LENGTH, 0.0, 1.0)
	var axis := direction / maxf(distance, 1.0e-4)
	var radial_x := Vector3.UP.cross(axis)
	if radial_x.length_squared() < 1.0e-5:
		radial_x = Vector3.RIGHT.cross(axis)
	radial_x = radial_x.normalized()
	var radial_y := axis.cross(radial_x)
	var radius := 0.007 + 0.026 * slack
	var turns := 1.8 + 4.0 * slack
	var angle := t * TAU * turns
	var taper := smoothstep(0.0, 0.12, t) * smoothstep(1.0, 0.88, t)
	var point := start + direction * t \
			+ (radial_x * cos(angle) + radial_y * sin(angle)) * radius * taper
	point.y -= slack * 0.16 * sin(PI * t)
	return point
