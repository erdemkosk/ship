class_name BoatInteriorEnvironment
extends RefCounted

const CABIN_XZ := Rect2(-1.70, -0.38, 3.40, 5.03)
const STOVE := Vector3(1.28, 1.05, 4.28)
const DOOR_Z0 := -0.45
const DOOR_Z1 := 4.65
const WHEELHOUSE_DOOR_Z := 4.05


func rifle_obstruction_fraction(world_to_boat: Transform3D,
		from_world: Vector3, to_world: Vector3, radius: float,
		blockers: Array[AABB], door_blockers: Array[AABB],
		aim_blockers: Array[AABB], floors: Array, ceilings: Array) -> float:
	var from_local := world_to_boat * from_world
	var to_local := world_to_boat * to_world
	var solids: Array[AABB] = []
	solids.append_array(blockers)
	solids.append_array(door_blockers)
	solids.append_array(aim_blockers)
	for floor_data in floors:
		var rect: Rect2 = floor_data[0]
		var y: float = floor_data[1]
		solids.append(AABB(Vector3(rect.position.x, y - 0.055,
				rect.position.y), Vector3(rect.size.x, 0.055, rect.size.y)))
	for ceiling_data in ceilings:
		var rect: Rect2 = ceiling_data[0]
		var y: float = ceiling_data[1]
		solids.append(AABB(Vector3(rect.position.x, y,
				rect.position.y), Vector3(rect.size.x, 0.065, rect.size.y)))
	var fraction := 1.0
	for solid in solids:
		fraction = minf(fraction, segment_aabb_entry_fraction(
				from_local, to_local, solid.grow(radius)))
	return fraction


func weather_openness(world_to_boat: Transform3D, world_position: Vector3,
		forward_door_angle: float, aft_door_angle: float,
		wheelhouse_door_angle: float) -> float:
	if not world_position.is_finite():
		return 1.0
	var position := world_to_boat * world_position
	var in_cabin := position.y >= 0.55 and position.y < 2.82 \
			and CABIN_XZ.has_point(Vector2(position.x, position.z))
	var in_wheelhouse := _in_wheelhouse(position)
	if not in_cabin and not in_wheelhouse:
		return 1.0
	var forward_open := clampf(absf(forward_door_angle) / 1.85, 0.0, 1.0)
	var aft_open := clampf(absf(aft_door_angle) / 1.85, 0.0, 1.0)
	var wheelhouse_open := clampf(absf(wheelhouse_door_angle) / 2.90, 0.0, 1.0)
	if in_wheelhouse:
		var distance := Vector2(position.x,
				position.z - WHEELHOUSE_DOOR_Z).length()
		return lerpf(0.12, lerpf(0.90, 0.30,
				clampf(distance / 3.2, 0.0, 1.0)), wheelhouse_open)
	var openness := 0.10
	if forward_open > 0.02:
		var distance := Vector2(position.x, position.z - DOOR_Z0).length()
		openness = maxf(openness, lerpf(0.88, 0.26,
				clampf(distance / 3.6, 0.0, 1.0)) * forward_open)
	if aft_open > 0.02:
		var distance := Vector2(position.x, position.z - DOOR_Z1).length()
		openness = maxf(openness, lerpf(0.88, 0.26,
				clampf(distance / 3.6, 0.0, 1.0)) * aft_open)
	return openness


func acoustic_space(world_to_boat: Transform3D,
		world_position: Vector3) -> StringName:
	if not world_position.is_finite():
		return &"deck"
	var position := world_to_boat * world_position
	if position.y >= 0.55 and position.y < 2.82 \
			and CABIN_XZ.has_point(Vector2(position.x, position.z)):
		return &"cabin"
	if _in_wheelhouse(position):
		return &"wheelhouse"
	return &"deck"


func heat_at(local_position: Vector3, stove_heat: float) -> float:
	if stove_heat < 0.04 or local_position.y < 0.58 or local_position.y >= 2.78:
		return 0.0
	if not CABIN_XZ.has_point(Vector2(local_position.x, local_position.z)):
		return 0.0
	var distance := Vector2(local_position.x - STOVE.x,
			local_position.z - STOVE.z).length()
	var proximity := 1.0 - smoothstep(0.35, 3.4, distance)
	return stove_heat * (0.58 + 0.42 * proximity)


func segment_aabb_entry_fraction(from: Vector3, to: Vector3, box: AABB) -> float:
	var direction := to - from
	var enter := 0.0
	var leave := 1.0
	for axis in 3:
		var origin: float = from[axis]
		var delta: float = direction[axis]
		var minimum: float = box.position[axis]
		var maximum: float = box.end[axis]
		if absf(delta) < 0.000001:
			if origin < minimum or origin > maximum:
				return 1.0
			continue
		var first := (minimum - origin) / delta
		var last := (maximum - origin) / delta
		if first > last:
			var swap := first
			first = last
			last = swap
		enter = maxf(enter, first)
		leave = minf(leave, last)
		if enter > leave:
			return 1.0
	return clampf(enter, 0.0, 1.0)


func _in_wheelhouse(position: Vector3) -> bool:
	return position.y >= 2.82 and position.y < 5.40 \
			and absf(position.x) < 1.74 \
			and position.z > -0.32 and position.z < 4.12
