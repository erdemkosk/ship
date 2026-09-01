class_name BoatInteractionLocator
extends RefCounted


func door_latch_local(id: String, player_local_position: Vector3,
		cabin_latch: Vector3, wheelhouse_latch: Vector3,
		forward_door_z: float, aft_door_z: float,
		wheelhouse_door_z: float) -> Vector3:
	match id:
		"door_fwd":
			return Vector3(cabin_latch.x, cabin_latch.y,
					cabin_latch.z if player_local_position.z > forward_door_z \
					else -cabin_latch.z)
		"door_aft":
			return Vector3(cabin_latch.x, cabin_latch.y,
					-cabin_latch.z if player_local_position.z < aft_door_z \
					else cabin_latch.z)
		"door_wh":
			var inside := player_local_position.y > 2.70 \
					and player_local_position.z < wheelhouse_door_z + 0.15
			return Vector3(wheelhouse_latch.x, wheelhouse_latch.y,
					-wheelhouse_latch.z if inside else wheelhouse_latch.z)
	return Vector3.ZERO


func interaction_position(id: String, fallback: Vector3,
		world_to_boat: Transform3D, player_local_position: Vector3,
		fuse_lid: Node3D, fuse_latch: Vector3, stove_switch: Node3D,
		switch_levers: Dictionary, fuse_bodies: Dictionary, doors: Dictionary,
		engine_door: Node3D, cabin_latch: Vector3, wheelhouse_latch: Vector3,
		forward_door_z: float, aft_door_z: float,
		wheelhouse_door_z: float) -> Vector3:
	if id == "fusebox" and fuse_lid != null:
		return world_to_boat * fuse_lid.to_global(fuse_latch)
	if id == "stove" and stove_switch != null:
		return world_to_boat * stove_switch.global_position
	if id.begins_with("sw_"):
		var lever := switch_levers.get(id) as Node3D
		if lever != null:
			return world_to_boat * lever.to_global(Vector3(0.0, 0.046, 0.0))
	if id.begins_with("fu_"):
		var cartridge := fuse_bodies.get(id) as Node3D
		if cartridge != null:
			return world_to_boat * cartridge.global_position
	if id in ["door_fwd", "door_aft", "door_wh"]:
		var leaf := doors.get(id) as Node3D
		if leaf != null:
			var latch := door_latch_local(id, player_local_position,
					cabin_latch, wheelhouse_latch, forward_door_z,
					aft_door_z, wheelhouse_door_z)
			return world_to_boat * leaf.to_global(latch)
	if id == "door_eng" and engine_door != null \
			and engine_door.get_child_count() > 1:
		return world_to_boat * (engine_door.get_child(1) as Node3D).global_position
	return fallback
