extends RefCounted
class_name LadderHandDriver
## Alternating two-hand rung selection for the moving boarding ladder.

const RUNG_PITCH := 0.27
const RUNG_REACH := 1.12
const RUNG_SPAN := 0.13

var _active := false
var _feet_y := 0.0
var _positions := {}


func set_state(on: bool, feet_y: float) -> void:
	if on and not _active:
		_positions.clear()
	_active = on
	_feet_y = feet_y


func is_active() -> bool:
	return _active


func _rung_local(boat, index: int) -> Vector3:
	var y: float = float(boat.SEA_LADDER_TOP) - 0.10 - float(index) * RUNG_PITCH
	var z: float = float(boat.SEA_LADDER_Z) + y * 0.1045
	return Vector3(float(boat.SEA_LADDER_X), y, z)


func drive(side: String, delta: float, boat, rig: Node) -> Vector3:
	var top: float = float(boat.SEA_LADDER_TOP)
	var high_index: int = int(floor(
			(top - 0.10 - (_feet_y + RUNG_REACH)) / RUNG_PITCH))
	var lead_is_right := (high_index % 2) == 0
	var high := (side == "R") == lead_is_right
	var index := clampi(high_index if high else high_index + 1, 0, 6)
	var out := -1.0 if side == "L" else 1.0
	var local_point := _rung_local(boat, index) \
			+ Vector3(out * RUNG_SPAN, 0.024, 0.0)
	var fingers_local := Vector3(0.0, -0.30, -1.0)
	var palm_local := Vector3(0.0, -1.0, -0.30)
	if high_index < 0:
		var handle_y: float = clampf(_feet_y + RUNG_REACH, 0.70, 1.02)
		local_point = Vector3(float(boat.SEA_LADDER_X) + out * 0.184,
				handle_y, float(boat.SEA_LADDER_Z) + handle_y * 0.1045)
		fingers_local = Vector3(0.0, -0.25, -1.0)
		palm_local = Vector3(-out, -0.10, 0.0)
	var boat_transform: Transform3D = boat.get_global_transform_interpolated()
	var target: Vector3 = boat_transform * local_point
	var current: Vector3 = _positions.get(side, target)
	var distance := current.distance_to(target)
	current = current.lerp(target, 1.0 - exp(-11.0 * delta))
	_positions[side] = current
	var lift := boat_transform.basis.z.normalized() * minf(distance, 0.34) * 0.55
	var contact := current + lift
	var fingers: Vector3 = boat_transform.basis * fingers_local
	var palm: Vector3 = boat_transform.basis * palm_local
	rig.grip(side, contact, fingers, palm, 1.0, "wrap",
			clampf(1.0 - distance * 3.0, 0.15, 1.0))
	return contact
