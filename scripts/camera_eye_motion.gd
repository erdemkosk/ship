class_name CameraEyeMotion
extends RefCounted
## Stateful boat-local eye smoothing, stride motion and heave absorption.

var chart_t := 0.0
var _eye_y := 0.0
var _eye_ready := false
var _bob := 0.0
var _reach_body_lean := Vector3.ZERO
var _boat_vy := 0.0
var _boat_vy_ready := false
var _heave_accel := 0.0
var _knee_offset := 0.0
var _knee_velocity := 0.0
var _station_eye_drop := 0.0
var _shore_eye_y := 0.0
var _shore_eye_ready := false


func reset() -> void:
	chart_t = 0.0
	_eye_ready = false
	_bob = 0.0
	_reach_body_lean = Vector3.ZERO
	_boat_vy_ready = false
	_heave_accel = 0.0
	_knee_offset = 0.0
	_knee_velocity = 0.0
	_station_eye_drop = 0.0
	_shore_eye_ready = false


func update(delta: float, target: Node3D, walker, engaged: String,
		boat_transform: Transform3D, camera_basis: Basis, arms,
		bag_focus: float, ocean) -> Dictionary:
	var ashore := bool(walker.get("ashore"))
	var swimming := bool(walker.get("swimming"))
	if swimming and walker.has_method("swim_eye_world"):
		# The swimmer and the water live in world space. Going through smoothed
		# boat-local Y here made the eye inherit the distant hull's rope-induced
		# heave even though the swimmer position itself was already independent.
		var camera_position: Vector3 = walker.call("swim_eye_world") as Vector3
		var bag_load_arc := sin(bag_focus * PI)
		camera_position.y -= bag_focus * 0.012 + bag_load_arc * 0.010
		_reach_body_lean = Vector3.ZERO
		_knee_offset = 0.0
		_knee_velocity = 0.0
		_boat_vy_ready = false
		_eye_ready = false
		_shore_eye_ready = false
		return {
			"position": camera_position,
			"walking": 0.0,
			"bag_load_arc": bag_load_arc,
		}
	if ashore and walker.has_method("shore_eye_world"):
		# Do not smooth a stationary world-space eye through boat-local Y. That
		# delayed inverse transform is exactly how wave heave leaked onto land.
		var horizontal_speed := Vector2(walker.vel.x, walker.vel.z).length()
		var walking := clampf(horizontal_speed / 3.0, 0.0, 1.0) \
				* (1.0 if walker.on_floor else 0.0)
		_bob = fmod(_bob + delta * horizontal_speed * 2.3, TAU)
		var amplitude := walking * 0.022
		var camera_position: Vector3 = walker.call("shore_eye_world") as Vector3
		if not _shore_eye_ready:
			_shore_eye_y = camera_position.y
			_shore_eye_ready = true
		else:
			_shore_eye_y = lerpf(_shore_eye_y, camera_position.y,
					1.0 - exp(-10.0 * delta))
		camera_position.y = _shore_eye_y
		camera_position.y += sin(_bob * 2.0) * amplitude
		camera_position += camera_basis.x * (sin(_bob) * amplitude * 0.9)
		var bag_load_arc := sin(bag_focus * PI)
		camera_position.y -= bag_focus * 0.012 + bag_load_arc * 0.010
		_reach_body_lean = Vector3.ZERO
		_knee_offset = 0.0
		_knee_velocity = 0.0
		_boat_vy_ready = false
		_eye_ready = false
		return {
			"position": camera_position,
			"walking": walking,
			"bag_load_arc": bag_load_arc,
		}
	_shore_eye_ready = false
	var eye_local: Vector3 = walker.call("eye_local")
	if engaged == "chart":
		chart_t = minf(chart_t + delta / 0.45, 1.0)
		var lean: float = chart_t * chart_t * (3.0 - 2.0 * chart_t)
		eye_local = eye_local.lerp(target.CHART_EYE, lean)
	else:
		chart_t = 0.0
	if not _eye_ready or absf(eye_local.y - _eye_y) > 1.10:
		_eye_y = eye_local.y
		_eye_ready = true
	else:
		_eye_y = lerpf(_eye_y, eye_local.y, 1.0 - exp(-13.0 * delta))
	eye_local.y = _eye_y
	var station_drop_goal := 0.08 if engaged == "helm" \
			else (0.04 if engaged == "telegraph" else 0.0)
	_station_eye_drop = lerpf(_station_eye_drop, station_drop_goal,
			1.0 - exp(-8.0 * delta))
	eye_local.y -= _station_eye_drop

	var horizontal_speed := 0.0 if engaged != "" \
			else Vector2(walker.vel.x, walker.vel.z).length()
	var walking: float = clampf(horizontal_speed / 3.0, 0.0, 1.0) \
			* (1.0 if walker.on_floor else 0.0)
	_bob = fmod(_bob + delta * horizontal_speed * 2.3, TAU)
	var amplitude := walking * 0.022
	eye_local.y += sin(_bob * 2.0) * amplitude
	eye_local.x += sin(_bob) * amplitude * 0.9
	var bag_load_arc := sin(bag_focus * PI)
	eye_local.x -= bag_load_arc * 0.026
	eye_local.y -= bag_focus * 0.012 + bag_load_arc * 0.010

	var body_goal := Vector3.ZERO
	if arms != null and arms.has_method("body_lean_local"):
		var lean_camera: Vector3 = arms.call("body_lean_local")
		body_goal = boat_transform.basis.inverse() * (camera_basis * lean_camera)
	var body_tau := 0.10 if body_goal.length_squared() > _reach_body_lean.length_squared() \
			else 0.24
	_reach_body_lean = _reach_body_lean.lerp(body_goal,
			1.0 - exp(-delta / body_tau))
	var on_ladder := bool(walker.get("on_sea_ladder"))
	if engaged == "chart" or swimming or on_ladder:
		_reach_body_lean = _reach_body_lean.lerp(Vector3.ZERO,
				1.0 - exp(-delta / 0.08))
	eye_local += _reach_body_lean
	_update_knee_suspension(delta, target, walker, swimming, on_ladder, ashore)
	eye_local += boat_transform.basis.inverse() * (Vector3.UP * _knee_offset)

	var camera_position: Vector3 = boat_transform * eye_local
	if ocean != null and not swimming and not on_ladder:
		camera_position.y = maxf(camera_position.y,
				float(ocean.call("get_height", camera_position)) + 0.35)
	return {
		"position": camera_position,
		"walking": walking,
		"bag_load_arc": bag_load_arc,
	}


func _update_knee_suspension(delta: float, boat: Node3D, walker,
		swimming: bool, on_ladder: bool, ashore: bool) -> void:
	var active := bool(walker.get("on_floor")) and not swimming \
			and not on_ladder and not ashore
	var current_vy := 0.0
	if boat is RigidBody3D:
		current_vy = (boat as RigidBody3D).linear_velocity.y
	if not _boat_vy_ready:
		_boat_vy = current_vy
		_boat_vy_ready = true
	var raw_accel := clampf((current_vy - _boat_vy) / maxf(delta, 0.001),
			-28.0, 28.0)
	_boat_vy = current_vy
	var accel_goal := raw_accel if active else 0.0
	_heave_accel = lerpf(_heave_accel, accel_goal, 1.0 - exp(-delta / 0.11))
	var target_offset := clampf(-_heave_accel * 0.0085, -0.065, 0.065) \
			if active else 0.0
	var dt := minf(delta, 0.033)
	var omega := TAU * 3.2
	var spring_accel := (target_offset - _knee_offset) * omega * omega \
			- 2.0 * omega * _knee_velocity
	_knee_velocity += spring_accel * dt
	_knee_offset += _knee_velocity * dt
	if absf(_knee_offset) > 0.065:
		_knee_offset = clampf(_knee_offset, -0.065, 0.065)
		_knee_velocity *= 0.25
