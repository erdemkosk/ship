class_name BoatAccessController
extends RefCounted
## Door, hatch and dive-gear presentation plus their dynamic blocker volumes.

const DOOR_Z0 := -0.45
const DOOR_Z1 := 4.65
const WH_DOOR_Z := 4.05

var _door_forward: Node3D
var _door_aft: Node3D
var _door_engine: Node3D
var _door_wheelhouse: Node3D
var _fuse_lid: Node3D
var _locker_door: Node3D
var _gear_mask: Node3D
var _gear_tank: Node3D
var _gear_transition := 0.0


func setup(door_forward: Node3D, door_aft: Node3D, door_engine: Node3D,
		door_wheelhouse: Node3D, fuse_lid: Node3D, locker_door: Node3D,
		gear_mask: Node3D, gear_tank: Node3D) -> void:
	_door_forward = door_forward
	_door_aft = door_aft
	_door_engine = door_engine
	_door_wheelhouse = door_wheelhouse
	_fuse_lid = fuse_lid
	_locker_door = locker_door
	_gear_mask = gear_mask
	_gear_tank = gear_tank


func update(delta: float, forward_open: bool, aft_open: bool,
		engine_open: bool, wheelhouse_open: bool, fusebox_open: bool,
		locker_open: bool, gear_worn: bool, door_blockers: Array[AABB],
		aim_blockers: Array[AABB]) -> float:
	_update_doors(delta, forward_open, aft_open, engine_open,
			wheelhouse_open, door_blockers)
	_update_fuse_lid(delta, fusebox_open, aim_blockers)
	_update_dive_gear(delta, locker_open, gear_worn)
	return _gear_transition


func _update_doors(delta: float, forward_open: bool, aft_open: bool,
		engine_open: bool, wheelhouse_open: bool,
		door_blockers: Array[AABB]) -> void:
	door_blockers.clear()
	if _door_forward != null:
		_door_forward.rotation.y = lerpf(_door_forward.rotation.y,
				-1.85 if forward_open else 0.0, 1.0 - exp(-6.0 * delta))
		_door_aft.rotation.y = lerpf(_door_aft.rotation.y,
				1.85 if aft_open else 0.0, 1.0 - exp(-6.0 * delta))
		if _door_engine != null:
			_door_engine.rotation.y = lerpf(_door_engine.rotation.y,
					1.92 if engine_open else 0.0, 1.0 - exp(-6.0 * delta))
		if absf(_door_forward.rotation.y) < 0.9:
			door_blockers.append(AABB(Vector3(-0.58, 0.63, DOOR_Z0 - 0.02),
					Vector3(1.16, 1.98, 0.16)))
		if absf(_door_aft.rotation.y) < 0.9:
			door_blockers.append(AABB(Vector3(-0.58, 0.63, DOOR_Z1 - 0.14),
					Vector3(1.16, 1.98, 0.16)))
	if _door_wheelhouse != null:
		_door_wheelhouse.rotation.y = lerpf(_door_wheelhouse.rotation.y,
				2.90 if wheelhouse_open else 0.0, 1.0 - exp(-6.0 * delta))
		if absf(_door_wheelhouse.rotation.y) < 0.9:
			door_blockers.append(AABB(Vector3(-0.62, 2.91, WH_DOOR_Z - 0.10),
					Vector3(1.20, 1.98, 0.20)))


func _update_fuse_lid(delta: float, fusebox_open: bool,
		aim_blockers: Array[AABB]) -> void:
	aim_blockers.clear()
	if _fuse_lid == null:
		return
	_fuse_lid.rotation.x = lerpf(_fuse_lid.rotation.x,
			-1.22 if fusebox_open else 0.0, 1.0 - exp(-8.0 * delta))
	if _fuse_lid.rotation.x < -0.6:
		var hinge_position := _fuse_lid.position
		aim_blockers.append(AABB(
				Vector3(hinge_position.x - 0.13, hinge_position.y + 0.01,
					hinge_position.z - 0.04), Vector3(0.26, 0.50, 0.28)))


func _update_dive_gear(delta: float, locker_open: bool, gear_worn: bool) -> void:
	if _locker_door != null:
		_locker_door.rotation.y = lerpf(_locker_door.rotation.y,
				-2.05 if locker_open else 0.0, 1.0 - exp(-7.0 * delta))
	_gear_transition = move_toward(
			_gear_transition, 1.0 if gear_worn else 0.0, delta / 1.35)
	if _gear_mask != null:
		_gear_mask.visible = _gear_transition < 0.45
	if _gear_tank != null:
		_gear_tank.visible = _gear_transition < 0.30
