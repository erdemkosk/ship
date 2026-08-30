extends RefCounted
class_name WatchHandDriver
## Owns the held-watch lifecycle, display state, and left-arm reading pose.

const RAISE_TIME := 0.26

var _held := false
var _amount := 0.0
var _clock := 0.0
var _tod := 12.0
var _depth := 0.0


func set_state(held: bool, tod: float, depth: float) -> bool:
	var rising := held and not _held
	_held = held
	_tod = tod
	_depth = depth
	return rising


func force_lower() -> void:
	_held = false


func is_up() -> bool:
	return _held or _amount > 0.01


func amount() -> float:
	return _amount


func clock() -> float:
	return _clock


func update(delta: float, active: bool, rig: Node) -> void:
	# The watch runs whether or not anyone is looking at it — a watch does.
	_clock += delta
	_amount = move_toward(_amount, 1.0 if (_held and active) else 0.0,
			delta / RAISE_TIME)
	if not rig.has_method("set_watch_display"):
		return
	var hh := floorf(_tod)
	var mins := floorf((_tod - hh) * 60.0)
	var night := _tod < 5.5 or _tod > 18.5
	# The backlight belongs to the sea and the night. On a grey afternoon
	# deck the face remains a dead film.
	var glow := 0.95 if _depth > 0.02 else (0.65 if night else 0.06)
	rig.set_watch_display(hh, mins, _clock, _depth,
			1.013 + _depth * 0.1003, glow)


func drive(camera: Camera3D, rig: Node) -> Vector3:
	## Raise the left forearm across the chest and present the strapped side of
	## the wrist by supinating the forearm, with only a small wrist extension.
	var c: Transform3D = camera.global_transform
	var u: float = _amount * _amount * (3.0 - 2.0 * _amount)
	var low := Vector3(-0.30, -0.62, -0.34)
	var high := Vector3(0.055, -0.062, -0.268)
	var point: Vector3 = low.lerp(high, u)
	point.x += sin(u * PI) * -0.05
	var contact: Vector3 = c * point
	var forearm: Vector3 = (contact - (rig.shoulder_global("L") as Vector3)).normalized()
	var to_eye: Vector3 = (c.origin - contact).normalized()
	var dorsal: Vector3 = (to_eye - to_eye.project(forearm)).normalized()
	var extension := deg_to_rad(12.0)
	var fingers: Vector3 = (forearm * cos(extension) \
			+ dorsal * sin(extension)).normalized()
	var face_normal: Vector3 = (dorsal * cos(extension) \
			- forearm * sin(extension)).normalized()
	var palm := -face_normal
	rig.grip("L", contact, fingers, palm, u, "wrap", 0.50 * u)
	return contact
