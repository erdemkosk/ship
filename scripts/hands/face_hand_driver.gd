extends RefCounted
class_name FaceHandDriver
## Camera-space gestures that touch the player's own face and mask.

var _kind := ""
var _time := 0.0
var _wipe_x := 9.0
var _wipe_direction := -1.0


func start(kind: String) -> void:
	_kind = kind
	_time = 0.0
	_wipe_x = 9.0
	_wipe_direction = -1.0


func is_active() -> bool:
	return _kind != ""


func wipe_front() -> Vector2:
	return Vector2(_wipe_x, _wipe_direction)


func drive(delta: float, camera: Camera3D, rig: Node) -> Dictionary:
	## Returns the contacts driven this frame and whether the gesture finished.
	var c: Transform3D = camera.global_transform
	_time += delta
	if _kind == "wear":
		return _drive_wear(c, rig)
	return _drive_wipe(c, camera, rig)


func _drive_wear(camera_xform: Transform3D, rig: Node) -> Dictionary:
	var duration := 1.35
	var u: float = clampf(_time / duration, 0.0, 1.0)
	var eased: float = u * u * (3.0 - 2.0 * u)
	var contacts := {}
	for side: String in ["L", "R"]:
		var out: float = 1.0 if side == "R" else -1.0
		# Lift the mask from below, seat it on the face, then pull the strap
		# over the head and let the hands fall away.
		var low := Vector3(out * 0.34, -0.62, -0.34)
		var face := Vector3(out * 0.165, -0.05, -0.30)
		var crown := Vector3(out * 0.185, 0.10, -0.02)
		var away := Vector3(out * 0.40, -0.30, 0.10)
		var point: Vector3
		if eased < 0.42:
			point = low.lerp(face, eased / 0.42)
		elif eased < 0.74:
			point = face.lerp(crown, (eased - 0.42) / 0.32)
		else:
			point = crown.lerp(away, (eased - 0.74) / 0.26)
		var fingers: Vector3 = camera_xform.basis \
				* Vector3(-out * 0.35, 0.15, 0.92)
		var palm: Vector3 = camera_xform.basis * Vector3(-out, -0.15, 0.0)
		var contact: Vector3 = camera_xform * point
		contacts[side] = contact
		rig.grip(side, contact, fingers, palm, 1.0, "wrap",
				clampf(1.0 - absf(eased - 0.58) * 2.2, 0.15, 1.0), false)
	var done := _time >= duration
	if done:
		_kind = ""
	return {"done": done, "contacts": contacts, "rest_left": false}


func _drive_wipe(camera_xform: Transform3D, camera: Camera3D,
		rig: Node) -> Dictionary:
	var duration := 0.95
	var u: float = clampf(_time / duration, 0.0, 1.0)
	var low_right := Vector3(0.30, -0.58, -0.26)
	var glass_right := Vector3(0.24, -0.02, -0.185)
	var glass_left := Vector3(-0.24, 0.01, -0.185)
	var low_left := Vector3(-0.34, -0.46, -0.20)
	var point: Vector3
	if u < 0.24:
		point = low_right.lerp(glass_right, u / 0.24)
	elif u < 0.72:
		var wipe: float = (u - 0.24) / 0.48
		point = glass_right.lerp(glass_left,
				wipe * wipe * (3.0 - 2.0 * wipe))
	else:
		point = glass_left.lerp(low_left, (u - 0.72) / 0.28)
	var fingers: Vector3 = camera_xform.basis * Vector3(-0.55, 0.05, -0.84)
	var palm: Vector3 = camera_xform.basis * Vector3(0.0, -0.25, 0.96)
	# Keep the mask shader's clear line directly under the fingertip.
	var half_fov: float = tan(deg_to_rad(camera.fov) * 0.5)
	_wipe_x = point.x / maxf(-point.z * half_fov * 2.0, 1e-3)
	_wipe_direction = -1.0
	var contact: Vector3 = camera_xform * point
	rig.grip("R", contact, fingers, palm, 1.0, "point", 1.0, false)
	var done := _time >= duration
	if done:
		_kind = ""
	return {"done": done, "contacts": {"R": contact}, "rest_left": true}
