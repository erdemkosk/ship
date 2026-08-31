extends Node3D
class_name DeckBag3D
## A compact waxed-canvas deck bag for quick-access tools.  It is built from
## real 3D pieces so the inventory can later move from this wall stowage into
## the player's hands without swapping to a painted interface.

const UtilityKnifeScript := preload("res://scripts/utility_knife.gd")

var _clock := 0.0
const SLOT_POSITIONS := [
	Vector3(-0.178, -0.040, 0.125),
	Vector3(-0.060, -0.045, 0.125),
	Vector3(0.060, -0.050, 0.125),
	Vector3(0.174, -0.045, 0.125),
]
const SLOT_LABELS := ["Flashlight", "Signal flare", "Utility knife", "Multitool"]

var _slot_anchors: Array[Node3D] = []
## Deliberately untyped: an empty physical slot is represented by null.
var _slot_items: Array = []
var _active_item: Node3D
var _active_label := ""
var _preview_slot := -1
var _knife_hand_target: Node3D
var _knife_draw := 1.0
const KNIFE_RELEASE_DURATION := 0.34
var _knife_release_left := 0.0
var _knife_release_item: UtilityKnife3D


func _ready() -> void:
	name = "DeckBag"
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	visible = false
	_build()
	_knife_hand_target = Node3D.new()
	_knife_hand_target.name = "KnifeHandTarget"
	_knife_hand_target.top_level = true
	add_child(_knife_hand_target)


func update_camera_pose(delta: float, camera: Camera3D, amount: float) -> void:
	## The bag is worn behind the right shoulder at amount=0 and swung round the
	## ribs into the lap at amount=1.  A quadratic arc, delayed rotation and a
	## little overshoot sell weight; a straight lerp reads like a UI panel.
	_clock += delta
	var u := clampf(amount, 0.0, 1.0)
	visible = u > 0.004
	if camera == null:
		return
	if visible:
		var ease := smoothstep(0.0, 1.0, u)
		var shoulder := Vector3(0.34, -0.02, 0.10)
		var round_ribs := Vector3(0.43, -0.12, -0.34)
		var inspect := Vector3(0.035, -0.195, -0.62)
		var a := shoulder.lerp(round_ribs, ease)
		var b := round_ribs.lerp(inspect, ease)
		var pos := a.lerp(b, ease)
		var weight_arc := sin(ease * PI)
		pos.y -= weight_arc * 0.035
		# Once settled it still rides the character's breathing, but never floats.
		var settled := smoothstep(0.72, 1.0, ease)
		pos.x += sin(_clock * 1.15) * 0.0035 * settled
		pos.y += sin(_clock * 1.72 + 0.8) * 0.0025 * settled
		var rot := Vector3(
			deg_to_rad(lerpf(18.0, -5.0, ease) + weight_arc * 8.0),
			deg_to_rad(lerpf(-108.0, 0.0, ease)),
			deg_to_rad(weight_arc * -13.0 + sin(_clock * 1.15) * 0.8 * settled))
		global_transform = camera.global_transform * Transform3D(Basis.from_euler(rot), pos)
		reset_physics_interpolation()
	_update_knife_release(delta)
	_update_active_item(delta, camera, u)


func slot_count() -> int:
	return SLOT_POSITIONS.size()


func slot_occupied(index: int) -> bool:
	return index >= 0 and index < _slot_items.size() and _slot_items[index] != null


func slot_target(index: int) -> Node3D:
	if index < 0 or index >= _slot_anchors.size():
		return null
	var item: Node3D = _slot_items[index] as Node3D if slot_occupied(index) else null
	return item if item != null else _slot_anchors[index]


func slot_label(index: int) -> String:
	if index < 0 or index >= SLOT_LABELS.size():
		return ""
	if slot_occupied(index):
		return str((_slot_items[index] as Node3D).get_meta("item_label", SLOT_LABELS[index]))
	return "Empty slot"


func first_empty_slot() -> int:
	for index in _slot_items.size():
		if not slot_occupied(index):
			return index
	return -1


func active_item_node() -> Node3D:
	return _active_item


func active_item_label() -> String:
	return _active_label


func active_item_kind() -> String:
	if _active_item == null:
		return ""
	return str(_active_item.get_meta("item_kind", "generic"))


func active_hand_target() -> Node3D:
	if active_item_kind() == "utility_knife":
		return _knife_hand_target
	return _active_item


func active_hand_mode() -> String:
	return "knife" if active_item_kind() == "utility_knife" \
			else "hold"


func release_hand_active() -> bool:
	return _knife_release_left > 0.0 and _knife_release_item != null


func release_hand_target() -> Node3D:
	return _knife_hand_target if release_hand_active() else null


func take_slot(index: int) -> Node3D:
	if _active_item != null or not slot_occupied(index):
		return null
	var item := _slot_items[index] as Node3D
	_slot_items[index] = null
	_active_item = item
	_active_label = str(item.get_meta("item_label", SLOT_LABELS[index]))
	_preview_slot = -1
	_knife_draw = 0.0
	_knife_release_left = 0.0
	_knife_release_item = null
	var outside := get_parent() as Node3D
	if outside != null:
		item.reparent(outside, true)
	item.top_level = true
	item.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	item.reset_physics_interpolation()
	if active_item_kind() == "utility_knife" and _knife_hand_target != null:
		var knife := _active_item as UtilityKnife3D
		var grip := knife.grip_node()
		_knife_hand_target.global_transform = item.global_transform \
				* (grip.transform if grip != null else Transform3D.IDENTITY)
		_knife_hand_target.set_meta("held_device", item)
		_knife_hand_target.set_meta("held_grip_transform",
				grip.transform if grip != null else Transform3D.IDENTITY)
		_knife_hand_target.set_meta("authored_grip_frame", false)
		_knife_hand_target.set_meta("grip_closure", 1.0)
	return item


func set_preview_slot(index: int) -> void:
	_preview_slot = index if index >= 0 and index < SLOT_POSITIONS.size() \
			and not slot_occupied(index) else -1


func place_active_in_slot(index: int) -> bool:
	if _active_item == null or index < 0 or index >= _slot_items.size() \
			or slot_occupied(index):
		return false
	var item := _active_item
	if item is UtilityKnife3D:
		(item as UtilityKnife3D).cancel_attack()
	item.reparent(self, true)
	item.top_level = false
	item.transform = _slot_transform(index)
	item.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_INHERIT
	item.reset_physics_interpolation()
	_slot_items[index] = item
	if item is UtilityKnife3D:
		_knife_release_item = item as UtilityKnife3D
		_knife_release_left = KNIFE_RELEASE_DURATION
		var grip := _knife_release_item.grip_node()
		_knife_hand_target.global_transform = item.global_transform \
				* (grip.transform if grip != null else Transform3D.IDENTITY)
		_knife_hand_target.set_meta("authored_grip_frame", true)
		_knife_hand_target.set_meta("grip_closure", 1.0)
	_active_item = null
	_active_label = ""
	_preview_slot = -1
	_knife_hand_target.remove_meta("held_device")
	_knife_hand_target.remove_meta("held_grip_transform")
	return true


func _update_knife_release(delta: float) -> void:
	if _knife_release_left <= 0.0 or _knife_release_item == null \
			or not is_instance_valid(_knife_release_item):
		_knife_release_left = 0.0
		_knife_release_item = null
		return
	_knife_release_left = maxf(_knife_release_left - delta, 0.0)
	var grip := _knife_release_item.grip_node()
	_knife_hand_target.global_transform = _knife_release_item.global_transform \
			* (grip.transform if grip != null else Transform3D.IDENTITY)
	_knife_hand_target.set_meta("authored_grip_frame", true)
	var progress := 1.0 - _knife_release_left / KNIFE_RELEASE_DURATION
	_knife_hand_target.set_meta("grip_closure",
			1.0 - smoothstep(0.06, 0.62, progress))


func begin_active_attack() -> bool:
	if _active_item is UtilityKnife3D and _preview_slot < 0:
		return (_active_item as UtilityKnife3D).begin_attack()
	return false


func cancel_active_attack() -> void:
	if _active_item is UtilityKnife3D:
		(_active_item as UtilityKnife3D).cancel_attack()


func active_knife_sweep() -> Dictionary:
	if _active_item is UtilityKnife3D:
		return (_active_item as UtilityKnife3D).sample_sweep()
	return {}


func active_knife_camera_kick() -> Vector3:
	if _active_item is UtilityKnife3D:
		return (_active_item as UtilityKnife3D).camera_kick()
	return Vector3.ZERO


func mark_active_knife_hit(collider: Object, position: Vector3,
		normal: Vector3) -> void:
	if _active_item is UtilityKnife3D:
		(_active_item as UtilityKnife3D).mark_hit(collider, position, normal)


func _update_active_item(delta: float, camera: Camera3D, bag_amount: float) -> void:
	if _active_item == null or not is_instance_valid(_active_item):
		return
	var target: Transform3D
	if _preview_slot >= 0 and bag_amount > 0.62:
		# Hover a few centimetres in front of the empty loop.  The hand and item
		# travel together, so E completes an insertion instead of teleporting it.
		var preview_transform := _slot_transform(_preview_slot)
		preview_transform.origin += Vector3(0.0, 0.0, 0.060)
		target = global_transform * preview_transform
	else:
		var carry_rot := Basis.from_euler(Vector3(deg_to_rad(-10.0),
				deg_to_rad(-4.0), deg_to_rad(-8.0)))
		target = camera.global_transform * Transform3D(carry_rot,
				Vector3(0.205, -0.205, -0.40))
	if _active_item is UtilityKnife3D:
		var knife := _active_item as UtilityKnife3D
		knife.tick_attack(delta)
		if _preview_slot >= 0 and bag_amount > 0.62:
			var grip := knife.grip_node()
			var grip_target := target \
					* (grip.transform if grip != null else Transform3D.IDENTITY)
			var return_k := 1.0 - exp(-10.0 * delta)
			_knife_hand_target.global_transform = \
					_knife_hand_target.global_transform.interpolate_with(
							grip_target, return_k)
			_knife_hand_target.set_meta("authored_grip_frame", true)
		else:
			_knife_hand_target.set_meta("authored_grip_frame", false)
			_knife_draw = minf(_knife_draw + delta / 0.38, 1.0)
			var palm_target := camera.global_transform * Transform3D(Basis.IDENTITY,
					knife.hand_position_camera_local())
			_knife_hand_target.global_transform = _knife_hand_target.global_transform \
					.interpolate_with(palm_target, smoothstep(0.0, 1.0, _knife_draw))
	var k := 1.0 - exp(-15.0 * delta)
	_active_item.global_transform = _active_item.global_transform.interpolate_with(target, k)
	_active_item.reset_physics_interpolation()


func _slot_transform(index: int) -> Transform3D:
	var basis := Basis.IDENTITY
	var origin: Vector3 = SLOT_POSITIONS[index]
	if index == 2:
		# Blade down, grip up, flush with the same two leather retaining loops.
		basis = Basis(Vector3.BACK, deg_to_rad(-90.0))
		origin.y += 0.055
	return Transform3D(basis, origin)


func _material(color: Color, roughness: float, metallic := 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	return mat


func _mesh_instance(mesh: Mesh, pos: Vector3, rot_deg: Vector3,
		material: Material, part_name: String, parent: Node3D = null) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = part_name
	part.mesh = mesh
	part.position = pos
	part.rotation_degrees = rot_deg
	part.material_override = material
	var owner := parent if parent != null else self
	owner.add_child(part)
	return part


func _box(size: Vector3, pos: Vector3, rot_deg: Vector3,
		material: Material, part_name := "BagPart", parent: Node3D = null) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _mesh_instance(mesh, pos, rot_deg, material, part_name, parent)


func _cylinder(radius: float, height: float, pos: Vector3, rot_deg: Vector3,
		material: Material, part_name := "BagPart", segments := 12,
		parent: Node3D = null) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	return _mesh_instance(mesh, pos, rot_deg, material, part_name, parent)


func _buckle(center: Vector3, width: float, height: float,
		brass: Material, prefix: String) -> void:
	var bar := 0.008
	var z := center.z
	_box(Vector3(width, bar, bar), center + Vector3(0.0, height * 0.5, 0.0),
			Vector3.ZERO, brass, prefix + "Top")
	_box(Vector3(width, bar, bar), center - Vector3(0.0, height * 0.5, 0.0),
			Vector3.ZERO, brass, prefix + "Bottom")
	_box(Vector3(bar, height, bar), Vector3(center.x - width * 0.5, center.y, z),
			Vector3.ZERO, brass, prefix + "Left")
	_box(Vector3(bar, height, bar), Vector3(center.x + width * 0.5, center.y, z),
			Vector3.ZERO, brass, prefix + "Right")
	_box(Vector3(width * 0.78, 0.006, 0.006), center,
			Vector3.ZERO, brass, prefix + "Tongue")


func _stitch_line(from: Vector3, to: Vector3, count: int,
		stitch: Material, prefix: String) -> void:
	for i in count:
		var t := (float(i) + 0.5) / float(count)
		var p := from.lerp(to, t)
		var along := to - from
		var horizontal := absf(along.x) > absf(along.y)
		var size := Vector3(0.020, 0.004, 0.004) if horizontal \
				else Vector3(0.004, 0.020, 0.004)
		_box(size, p, Vector3.ZERO, stitch, "%s%02d" % [prefix, i])


func _build() -> void:
	var canvas := _material(Color(0.105, 0.115, 0.096), 0.96)
	var canvas_dark := _material(Color(0.060, 0.064, 0.054), 0.98)
	var canvas_wear := _material(Color(0.155, 0.158, 0.125), 0.99)
	var leather := _material(Color(0.145, 0.080, 0.045), 0.91)
	var leather_edge := _material(Color(0.075, 0.043, 0.028), 0.96)
	var brass := _material(Color(0.42, 0.30, 0.12), 0.38, 0.78)
	var steel := _material(Color(0.26, 0.27, 0.27), 0.42, 0.72)
	var steel_dark := _material(Color(0.090, 0.095, 0.098), 0.58, 0.56)
	var flare_red := _material(Color(0.43, 0.055, 0.035), 0.75, 0.05)
	var glass := _material(Color(0.34, 0.42, 0.38), 0.12)
	var thread := _material(Color(0.50, 0.39, 0.23), 0.98)

	# Canvas volume.  Edge rolls soften the primitive silhouette and make the
	# bag read as stuffed cloth rather than a metal case.
	_box(Vector3(0.48, 0.34, 0.135), Vector3(0.0, -0.025, 0.0),
			Vector3.ZERO, canvas, "CanvasBody")
	_cylinder(0.040, 0.29, Vector3(-0.235, -0.025, 0.0), Vector3.ZERO,
			canvas_dark, "LeftCanvasRoll")
	_cylinder(0.040, 0.29, Vector3(0.235, -0.025, 0.0), Vector3.ZERO,
			canvas_dark, "RightCanvasRoll")
	_cylinder(0.038, 0.45, Vector3(0.0, -0.195, 0.0), Vector3(0.0, 0.0, 90.0),
			canvas_dark, "BottomCanvasRoll")
	_cylinder(0.033, 0.48, Vector3(0.0, 0.185, 0.005), Vector3(0.0, 0.0, 90.0),
			canvas, "RolledMouth")

	# A broad flap and two old closure straps.  The flap stands a little proud
	# of the body so its shadow survives the dim cabin lighting.
	_box(Vector3(0.455, 0.145, 0.024), Vector3(0.0, 0.105, 0.082),
			Vector3(-5.0, 0.0, 0.0), canvas_dark, "TopFlap")
	_box(Vector3(0.435, 0.026, 0.012), Vector3(0.0, 0.168, 0.099),
			Vector3.ZERO, leather_edge, "FlapEdge")
	for x in [-0.155, 0.155]:
		_box(Vector3(0.032, 0.315, 0.014), Vector3(x, -0.006, 0.092),
				Vector3.ZERO, leather, "ClosureStrap")
		_buckle(Vector3(x, 0.070, 0.105), 0.052, 0.048, brass, "ClosureBuckle")

	# Carry handle and shoulder-strap anchors.  Nothing resembles MOLLE: this
	# is a repaired sailor's bag, held together with leather and brass.
	_box(Vector3(0.025, 0.11, 0.025), Vector3(-0.105, 0.245, 0.0),
			Vector3(0.0, 0.0, -12.0), leather, "HandleLeft")
	_box(Vector3(0.025, 0.11, 0.025), Vector3(0.105, 0.245, 0.0),
			Vector3(0.0, 0.0, 12.0), leather, "HandleRight")
	_cylinder(0.013, 0.19, Vector3(0.0, 0.292, 0.0), Vector3(0.0, 0.0, 90.0),
			leather, "CarryHandle")
	for x in [-0.225, 0.225]:
		_cylinder(0.022, 0.010, Vector3(x, 0.185, 0.030), Vector3(90.0, 0.0, 0.0),
			brass, "StrapRing")

	# Exterior quick-access fittings: each tool has its own root and physical
	# slot. These are the exact meshes the right hand removes; no inventory icon
	# or duplicate viewmodel is swapped in when E is pressed.
	var tool_z := 0.125
	_slot_anchors.clear()
	_slot_items.clear()
	for index in SLOT_POSITIONS.size():
		var anchor := Node3D.new()
		anchor.name = "Slot%d" % (index + 1)
		anchor.position = _slot_transform(index).origin
		add_child(anchor)
		_slot_anchors.append(anchor)
		var item: Node3D = UtilityKnifeScript.new() as Node3D if index == 2 \
				else Node3D.new()
		item.name = "BagItem%d" % (index + 1)
		item.transform = _slot_transform(index)
		item.set_meta("item_label", SLOT_LABELS[index])
		add_child(item)
		_slot_items.append(item)
	# Brass flashlight.
	var flashlight := _slot_items[0] as Node3D
	_cylinder(0.024, 0.185, Vector3.ZERO, Vector3.ZERO,
			brass, "FlashlightBody", 16, flashlight)
	_cylinder(0.033, 0.035, Vector3(0.0, 0.110, 0.0), Vector3.ZERO,
			brass, "FlashlightHead", 16, flashlight)
	_cylinder(0.025, 0.006, Vector3(0.0, 0.130, 0.0), Vector3.ZERO,
			glass, "FlashlightLens", 16, flashlight)
	# Maritime flare.
	var flare := _slot_items[1] as Node3D
	_cylinder(0.019, 0.205, Vector3.ZERO, Vector3.ZERO,
			flare_red, "SignalFlare", 14, flare)
	_cylinder(0.022, 0.020, Vector3(0.0, 0.113, 0.0), Vector3.ZERO,
			steel_dark, "FlareCap", 14, flare)
	# Slot three is the imported utility knife itself; the same node leaves the
	# webbing, seats in the palm and performs the cut.
	# Folded steel multitool.
	var multitool := _slot_items[3] as Node3D
	_box(Vector3(0.045, 0.185, 0.025), Vector3.ZERO,
			Vector3.ZERO, steel, "Multitool", multitool)
	for y in [-0.115, 0.025]:
		_cylinder(0.009, 0.031, Vector3(0.0, y + 0.045, 0.002),
				Vector3(90.0, 0.0, 0.0), brass, "MultitoolRivet", 10, multitool)

	# Retaining loops around each tool. They are deliberately few and broad;
	# repeated webbing would turn the silhouette into a modern tactical pack.
	for x in [-0.178, -0.060, 0.060, 0.174]:
		for y in [-0.105, 0.015]:
			_box(Vector3(0.060, 0.018, 0.016), Vector3(x, y, tool_z + 0.020),
					Vector3.ZERO, leather, "ToolLoop")

	# Worn salt bloom and hand repair.  Subtle raised patches catch the cabin
	# lamp without requiring a one-off texture asset.
	_box(Vector3(0.075, 0.050, 0.004), Vector3(-0.105, -0.145, 0.071),
			Vector3(0.0, 0.0, -8.0), canvas_wear, "SaltWear")
	_box(Vector3(0.060, 0.040, 0.006), Vector3(0.115, -0.135, 0.073),
			Vector3(0.0, 0.0, 5.0), canvas_dark, "CanvasRepair")
	_stitch_line(Vector3(-0.205, 0.150, 0.101), Vector3(0.205, 0.150, 0.101),
			12, thread, "FlapStitch")
	_stitch_line(Vector3(-0.215, -0.165, 0.072), Vector3(0.215, -0.165, 0.072),
			12, thread, "BottomStitch")
