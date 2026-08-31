extends RefCounted
class_name FingerContactSolver
## Closed-loop per-phalanx closure against the live held device.

const FINGER_PAD := 0.018


static func device_bounds(device: Node3D) -> AABB:
	var bounds := AABB()
	var found := false
	var inverse := device.global_transform.affine_inverse()
	var stack: Array[Node] = [device]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child: Node in node.get_children():
			stack.append(child)
		if not node is MeshInstance3D or not (node as MeshInstance3D).visible:
			continue
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		var local_box := mesh_node.get_aabb()
		var to_device := inverse * mesh_node.global_transform
		for endpoint in 8:
			var point := to_device * local_box.get_endpoint(endpoint)
			if not found:
				bounds = AABB(point, Vector3.ZERO)
				found = true
			else:
				bounds = bounds.expand(point)
	return bounds if found else AABB(Vector3(-0.035, -0.035, -0.035),
			Vector3(0.07, 0.07, 0.07))


static func solve(skeleton: Skeleton3D, finger_chains: Dictionary,
		device: Node3D, bounds: AABB, previous: Dictionary,
		pose_to_world: Transform3D, delta: float) -> Dictionary:
	var scales := previous.duplicate(true)
	var touched := 0
	var penetrations := 0
	var samples := 0
	var nearest := INF
	var grown := bounds.grow(FINGER_PAD)
	for finger: int in finger_chains:
		var chain: PackedInt32Array = finger_chains[finger]
		var values: Array = scales.get(finger, [0.18, 0.18, 0.18])
		values = values.duplicate()
		for joint in chain.size():
			var bone := chain[joint]
			var endpoint: Vector3
			if joint + 1 < chain.size():
				endpoint = (pose_to_world \
						* skeleton.get_bone_global_pose(chain[joint + 1])).origin
			else:
				var last := (pose_to_world \
						* skeleton.get_bone_global_pose(bone)).origin
				var before := (pose_to_world \
						* skeleton.get_bone_global_pose(chain[maxi(joint - 1, 0)])).origin
				endpoint = last + (last - before) * 0.72
			var local := device.to_local(endpoint)
			nearest = minf(nearest, _distance_to_aabb(local, bounds))
			var inside := bounds.has_point(local)
			var on_pad := grown.has_point(local)
			var value := float(values[mini(joint, values.size() - 1)])
			if inside:
				# Back this joint off quickly; downstream joints inherit the
				# correction on the next skeleton pass.
				value = maxf(value - delta * 8.5, 0.04)
				penetrations += 1
			elif on_pad:
				touched += 1
			else:
				value = minf(value + delta * 3.8, 1.0)
			values[joint] = value
			samples += 1
		scales[finger] = values
	return {"scales": scales, "touches": touched,
			"penetrations": penetrations, "samples": samples,
			"nearest": nearest,
			"quality": clampf(float(touched) / maxf(float(samples) * 0.34, 1.0)
					- float(penetrations) * 0.12, 0.0, 1.0)}


static func _distance_to_aabb(point: Vector3, box: AABB) -> float:
	var closest := point.clamp(box.position, box.end)
	return point.distance_to(closest)
