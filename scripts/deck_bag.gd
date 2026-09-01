extends Node3D
class_name DeckBag3D
## A compact waxed-canvas deck bag for quick-access tools.  It is built from
## real 3D pieces so the inventory can later move from this wall stowage into
## the player's hands without swapping to a painted interface.

const UtilityKnifeScript := preload("res://scripts/utility_knife.gd")
const HuntingRifleScript := preload("res://scripts/hunting_rifle.gd")
const KIND_KNIFE := "utility_knife"
const KIND_RIFLE := "hunting_rifle"

var _clock := 0.0
const SLOT_POSITIONS := [
	Vector3(-0.178, -0.040, 0.125),
	Vector3(-0.060, -0.045, 0.125),
	Vector3(0.060, -0.050, 0.125),
	Vector3(0.174, -0.045, 0.125),
	# The rifle sits in the sling plane immediately behind the working hands.
	# Keeping it only a little proud of the canvas makes it read as part of the
	# bag instead of a second first-person weapon floating across the foreground.
	Vector3(0.0, -0.330, 0.145),
]
const SLOT_LABELS := ["Flashlight", "Signal flare", "Utility knife", "Multitool",
		"Hunting rifle"]
const KNIFE_SLOT := 2
const RIFLE_SLOT := 4
const SLOT_WEIGHTS := [0.32, 0.24, 0.18, 0.36, 1.45]
const RELOAD_BOLT_OPEN_START := 0.25
const RELOAD_BOLT_OPEN_END := 0.95
const RELOAD_CARTRIDGE_SHOW := 1.15
const RELOAD_CARTRIDGE_MOVE := 1.40
const RELOAD_CARTRIDGE_INSERT := 2.00
const RELOAD_INSERTED := 2.28
const RELOAD_BOLT_CLOSE_START := 2.45
const RELOAD_BOLT_CLOSE_END := 2.90
const RELOAD_DURATION := 3.30

var _slot_anchors: Array[Node3D] = []
var _pointer_anchors: Array[Node3D] = []
var _pointer_target: Node3D
var _pointer_current := 0
var _pointer_pending := 0
var _pointer_transition := 1.0
var _pointer_from := Vector3.ZERO
const POINTER_TRANSITION_DURATION := 0.19
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
var _rifle_primary_target: Node3D
var _rifle_support_target: Node3D
var _rifle_aim := 0.0
var _rifle_aim_goal := false
var _rifle_ads_settle := 0.0
var _rifle_reload_blend := 0.0
const TAKE_GRASP_DURATION := 0.12
const TAKE_EXTRACT_DURATION := 0.34
const KNIFE_CLEAR_DURATION := 0.16
# Account for the imported handle's thickness, not only its wrapper origin. A
# small negative offset keeps the complete knife behind the retaining leather
# while its rear face still remains clear of the canvas skin.
const KNIFE_SLOT_PROUD := -0.040
const KNIFE_CLEAR_PULL := 0.105
enum TakePhase { IDLE, GRASP, CLEAR_RESTRAINT, TURN_TO_CARRY, COMPLETE }
var _take_phase := TakePhase.IDLE
var _take_elapsed := -1.0
var _take_source_slot := -1
var _take_grip_start := Transform3D.IDENTITY
var _tool_loop_parts := {}
var _tool_loop_rest := {}
var _rifle_sling_parts: Array[MeshInstance3D] = []
var _rifle_sling_rest := {}
## Worn-bag dynamics. The camera supplies the shoulder frame; this state is the
## delayed mass hanging below two strap attachments, never a decorative bob.
var _sling_angle := Vector2.ZERO
var _sling_velocity := Vector2.ZERO
var _sling_last_anchor := Vector3.ZERO
var _sling_last_velocity := Vector3.ZERO
var _sling_ready := false
var _shoulder_strap_parts: Array[MeshInstance3D] = []
## Cosmetic soft-body layer. Inventory anchors remain rigid and exact for the
## hands; only the waxed canvas skin and loose hardware yield under its load.
var _soft_canvas_parts: Array[MeshInstance3D] = []
var _soft_canvas_rest: Dictionary = {}
var _load_ring_parts: Array[MeshInstance3D] = []
var _load_ring_rest: Dictionary = {}
var _body_yield := Vector2.ZERO # x = lateral lean, y = downward compression
var _body_yield_velocity := Vector2.ZERO
# The raise itself already consumes about 0.24 s. After the sights cross the
# shoulder threshold, one short 60 ms seating window is enough before the
# weapon-space lock may engage; surface/contact checks still prevent an early
# bad freeze.
const RIFLE_ADS_GRIP_SETTLE := 0.06
# The imported stock continues roughly 33 cm behind the rear sight. At 39 cm
# the camera sliced into the wood; 47.5 cm is the closest safe seating point
# for this stock and still brings the rifle subtly nearer than before.
const RIFLE_ADS_REAR_DISTANCE := -0.475


func _ready() -> void:
	name = "DeckBag"
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	visible = false
	_build()
	_pointer_target = Node3D.new()
	_pointer_target.name = "SlotPointerTransition"
	add_child(_pointer_target)
	if not _pointer_anchors.is_empty():
		_pointer_target.transform = _pointer_anchors[0].transform
		_pointer_from = _pointer_target.position
	_knife_hand_target = Node3D.new()
	_knife_hand_target.name = "KnifeHandTarget"
	_knife_hand_target.top_level = true
	add_child(_knife_hand_target)
	_rifle_primary_target = Node3D.new()
	_rifle_primary_target.name = "RiflePrimaryTarget"
	_rifle_primary_target.top_level = true
	add_child(_rifle_primary_target)
	_rifle_support_target = Node3D.new()
	_rifle_support_target.name = "RifleSupportTarget"
	_rifle_support_target.top_level = true
	add_child(_rifle_support_target)


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
		# Ten centimetres closer than the old presentation. The left hand still
		# lands on the physical handle, but the shorter reach leaves a visible,
		# weighted elbow bend instead of a straight mannequin arm.
		# Slightly higher in the lap: the long-gun cradle remains visible below
		# while the four quick-access pockets stay clear of the carrying forearm.
		# The long-gun sling now hangs well below the canvas. Lift the complete
		# inspection composition enough to keep the low rifle selectable on screen.
		var inspect := Vector3(0.050, 0.135, -0.535)
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
		var anchor_xf := camera.global_transform * Transform3D(Basis.from_euler(rot), pos)
		_update_sling_physics(delta, camera, anchor_xf, ease)
		reset_physics_interpolation()
		_update_physical_shoulder_strap(ease)
		_update_loaded_canvas(delta, ease)
	_update_pointer_transition(delta)
	_update_slot_restraints(delta)
	_update_knife_release(delta)
	_update_active_item(delta, camera, u)


func _update_sling_physics(delta: float, camera: Camera3D,
		anchor_xf: Transform3D, open_amount: float) -> void:
	## A constrained two-axis pendulum. Camera/boat acceleration supplies inertia;
	## gravity/stiffness returns the load and damping represents leather rubbing on
	## clothing. Opening the inventory progressively braces the bag in both hands.
	if delta <= 0.0 or delta > 0.10 or not _sling_ready:
		_sling_last_anchor = anchor_xf.origin
		_sling_last_velocity = Vector3.ZERO
		_sling_velocity = Vector2.ZERO
		_sling_angle = Vector2.ZERO
		_sling_ready = true
		global_transform = anchor_xf
		return
	var anchor_velocity := (anchor_xf.origin - _sling_last_anchor) / delta
	var acceleration := (anchor_velocity - _sling_last_velocity) / delta
	_sling_last_anchor = anchor_xf.origin
	_sling_last_velocity = anchor_velocity
	var local_accel := camera.global_basis.inverse() * acceleration
	var forcing := Vector2(-local_accel.z, local_accel.x) * 0.010
	forcing.x = clampf(forcing.x, -3.2, 3.2)
	forcing.y = clampf(forcing.y, -3.2, 3.2)
	var brace := smoothstep(0.58, 1.0, open_amount)
	var stiffness := lerpf(18.0, 48.0, brace)
	var damping := lerpf(5.8, 12.0, brace)
	_sling_velocity += (forcing - _sling_angle * stiffness
			- _sling_velocity * damping) * delta
	_sling_angle += _sling_velocity * delta
	_sling_angle.x = clampf(_sling_angle.x, -0.24, 0.24)
	_sling_angle.y = clampf(_sling_angle.y, -0.31, 0.31)
	# Once the bag is presented for selection both hands brace it: retain the
	# physical swing during the shoulder arc, but remove the final residual angle
	# so grip targets cannot slide away under planted fingers.
	var applied_angle := _sling_angle * (1.0 - brace)
	var swing_basis := Basis.from_euler(Vector3(applied_angle.x,
			0.0, applied_angle.y))
	var travel := Vector3(_sling_angle.y * 0.085,
			-(absf(_sling_angle.x) + absf(_sling_angle.y)) * 0.018,
			_sling_angle.x * 0.070) * (1.0 - brace)
	global_transform = anchor_xf * Transform3D(swing_basis, travel)


func _update_physical_shoulder_strap(open_amount: float) -> void:
	const STRAP_SEGMENTS := 48
	if _shoulder_strap_parts.size() != STRAP_SEGMENTS:
		return
	# Both ends remain riveted to the brass rings. The slack middle lags opposite
	# the bag's angular motion; when braced open it settles back into a broad U.
	var lag := Vector3(-_sling_angle.y * 0.16, -absf(_sling_angle.x) * 0.05,
			-_sling_angle.x * 0.11) * (1.0 - smoothstep(0.65, 1.0, open_amount))
	var points := PackedVector3Array()
	for i in STRAP_SEGMENTS + 1:
		var t := float(i) / float(STRAP_SEGMENTS)
		var x := lerpf(-0.218, 0.218, t)
		var sag := 4.0 * t * (1.0 - t)
		var asym := sin(t * PI) * (1.0 - absf(t * 2.0 - 1.0) * 0.25)
		# The fixed ends disappear behind the reinforced lower seam. The first
		# quarter therefore leaves the canvas almost vertically before the loose
		# hide rounds into its hanging U.
		points.append(Vector3(x, -0.155 - 0.34 * sag,
				0.038 + lag.z * asym) + Vector3(lag.x, lag.y, 0.0) * asym)
	for i in STRAP_SEGMENTS:
		_set_flat_strap_piece(_shoulder_strap_parts[i], points[i], points[i + 1])


func _set_flat_strap_piece(piece: MeshInstance3D, from: Vector3, to: Vector3) -> void:
	var delta := to - from
	var xy := Vector2(delta.x, delta.y)
	piece.position = from.lerp(to, 0.5)
	piece.rotation = Vector3(0.0, -atan2(delta.z, maxf(xy.length(), 0.0001)),
			atan2(delta.y, delta.x))
	var mesh := piece.mesh as BoxMesh
	if mesh != null:
		# A slight overlap hides the square gaps between articulated pieces while
		# retaining the live pendulum curve.
		mesh.size.x = delta.length() * 1.12


func _register_soft_canvas(part: MeshInstance3D) -> MeshInstance3D:
	_soft_canvas_parts.append(part)
	_soft_canvas_rest[part] = part.transform
	return part


func _register_load_ring(part: MeshInstance3D) -> MeshInstance3D:
	_load_ring_parts.append(part)
	_load_ring_rest[part] = part.transform
	return part


func _register_tool_loop(slot: int, part: MeshInstance3D) -> MeshInstance3D:
	if not _tool_loop_parts.has(slot):
		_tool_loop_parts[slot] = []
	(_tool_loop_parts[slot] as Array).append(part)
	_tool_loop_rest[part] = part.transform
	return part


func _register_rifle_sling(part: MeshInstance3D) -> MeshInstance3D:
	_rifle_sling_parts.append(part)
	_rifle_sling_rest[part] = part.transform
	return part


func _update_loaded_canvas(delta: float, open_amount: float) -> void:
	## Waxed canvas yields by millimetres, never breathes like rubber. Stored
	## objects determine both the downward load and its left/right distribution.
	if delta <= 0.0 or delta > 0.10:
		return
	var total_load := 0.0
	var moment := 0.0
	for index in RIFLE_SLOT:
		if slot_occupied(index):
			var weight: float = SLOT_WEIGHTS[index]
			total_load += weight
			moment += SLOT_POSITIONS[index].x * weight
	if slot_occupied(RIFLE_SLOT):
		total_load += SLOT_WEIGHTS[RIFLE_SLOT]
		# Its steel action sits a little to port even though the rifle is centred.
		moment -= 0.014
	var target := Vector2(clampf(moment * 0.055, -0.006, 0.006),
			clampf(total_load * 0.0048, 0.0, 0.012))
	var brace := smoothstep(0.65, 1.0, open_amount)
	var stiffness := lerpf(34.0, 55.0, brace)
	var damping := lerpf(7.5, 11.5, brace)
	_body_yield_velocity += (target - _body_yield) * stiffness * delta
	_body_yield_velocity *= exp(-damping * delta)
	_body_yield += _body_yield_velocity * delta

	for part in _soft_canvas_parts:
		if part == null or not is_instance_valid(part):
			continue
		var rest: Transform3D = _soft_canvas_rest[part]
		var low_factor := clampf((0.20 - rest.origin.y) / 0.40, 0.10, 1.0)
		part.transform = rest
		part.position = rest.origin + Vector3(_body_yield.x * low_factor,
				-_body_yield.y * low_factor, 0.0)
		var compression := _body_yield.y * 0.75 * low_factor
		part.scale = Vector3(1.0 + compression * 0.55,
				1.0 - compression, 1.0 + compression * 0.30)

	for ring in _load_ring_parts:
		if ring == null or not is_instance_valid(ring):
			continue
		var rest: Transform3D = _load_ring_rest[ring]
		ring.transform = rest
		var side := signf(rest.origin.x)
		ring.position = rest.origin + Vector3(_body_yield.x * 0.45,
				-_body_yield.y * 0.55, 0.0)
		# Metal follows the leather ear with restrained inertial lag.
		ring.rotation.z += side * (_sling_angle.y * 0.18
				+ _body_yield_velocity.y * 0.035)


func _update_pointer_transition(delta: float) -> void:
	if _pointer_target == null or _pointer_anchors.is_empty():
		return
	_pointer_transition = minf(_pointer_transition + delta / POINTER_TRANSITION_DURATION, 1.0)
	var t := _pointer_transition
	var goal := _pointer_anchors[_pointer_pending].position
	var retract := Vector3(0.0, 0.0, 0.055)
	if t < 0.32:
		_pointer_target.position = _pointer_from.lerp(_pointer_from + retract,
				smoothstep(0.0, 1.0, t / 0.32))
	elif t < 0.70:
		_pointer_target.position = (_pointer_from + retract).lerp(goal + retract,
				smoothstep(0.0, 1.0, inverse_lerp(0.32, 0.70, t)))
	else:
		_pointer_target.position = (goal + retract).lerp(goal,
				smoothstep(0.0, 1.0, inverse_lerp(0.70, 1.0, t)))
	_pointer_target.basis = _pointer_anchors[_pointer_pending].basis
	var roll_slot := _pointer_current if t < 0.50 else _pointer_pending
	_pointer_target.set_meta("centre_point_roll", roll_slot == RIFLE_SLOT)
	if t >= 1.0:
		_pointer_current = _pointer_pending


func _update_slot_restraints(_delta: float) -> void:
	var flex := sin(_take_extraction_progress() * PI) \
			if _take_source_slot >= 0 and not take_extraction_complete() else 0.0
	for slot in _tool_loop_parts:
		for part: MeshInstance3D in _tool_loop_parts[slot]:
			var rest: Transform3D = _tool_loop_rest[part]
			part.transform = rest
			if int(slot) == _take_source_slot:
				part.position.z += flex * 0.014
				part.scale.x = 1.0 + flex * 0.16
	for part: MeshInstance3D in _rifle_sling_parts:
		var rest: Transform3D = _rifle_sling_rest[part]
		part.transform = rest
		if _take_source_slot == RIFLE_SLOT:
			part.position.z += flex * 0.020
			part.scale.z = 1.0 + flex * 0.10


func slot_count() -> int:
	return SLOT_POSITIONS.size()


func slot_occupied(index: int) -> bool:
	return index >= 0 and index < _slot_items.size() and _slot_items[index] != null


func slot_target(index: int) -> Node3D:
	if index < 0 or index >= _slot_anchors.size():
		return null
	var item: Node3D = _slot_items[index] as Node3D if slot_occupied(index) else null
	return item if item != null else _slot_anchors[index]


func slot_pointer_target(index: int) -> Node3D:
	## Point at a stable spot just in front of the webbing. Using the item root
	## itself put the fingertip inside wide models and made the gesture read as an
	## open hand reaching through them instead of an index indicating a choice.
	if index < 0 or index >= _pointer_anchors.size():
		return null
	if index != _pointer_pending:
		_pointer_from = _pointer_target.position
		_pointer_pending = index
		_pointer_transition = 0.0
	return _pointer_target


func take_extraction_complete() -> bool:
	return _take_phase == TakePhase.COMPLETE


func _take_extraction_progress() -> float:
	if _take_phase == TakePhase.IDLE:
		return 0.0
	return clampf((_take_elapsed - TAKE_GRASP_DURATION) / TAKE_EXTRACT_DURATION,
			0.0, 1.0)


func slot_label(index: int) -> String:
	if index < 0 or index >= SLOT_LABELS.size():
		return ""
	if slot_occupied(index):
		return str((_slot_items[index] as Node3D).get_meta("item_label", SLOT_LABELS[index]))
	return "Empty rifle sling" if index == RIFLE_SLOT else "Empty slot"


func first_empty_slot() -> int:
	# The long sling is not generic inventory space. Only the rifle can return
	# there, so normal tools search the four webbing loops exclusively.
	for index in RIFLE_SLOT:
		if not slot_occupied(index):
			return index
	return -1


func can_place_active(index: int) -> bool:
	if _active_item == null or index < 0 or index >= _slot_items.size() \
			or slot_occupied(index):
		return false
	var rifle := active_item_kind() == KIND_RIFLE
	return rifle if index == RIFLE_SLOT else not rifle


func active_item_node() -> Node3D:
	return _active_item


func active_item_label() -> String:
	return _active_label


func active_item_kind() -> String:
	if _active_item == null:
		return ""
	return str(_active_item.get_meta("item_kind", "generic"))


func active_hand_target() -> Node3D:
	if active_item_kind() == KIND_KNIFE:
		return _knife_hand_target
	return _active_item


func active_hand_mode() -> String:
	if active_item_kind() == KIND_KNIFE:
		return "knife"
	if active_item_kind() == KIND_RIFLE:
		return "rifle"
	return "hold"


func rifle_primary_target() -> Node3D:
	return _rifle_primary_target if active_item_kind() == KIND_RIFLE else null


func rifle_support_target() -> Node3D:
	# Low carry deliberately reserves only the trigger hand. The support hand
	# joins while shouldering and stays through the short lower-from-ADS blend.
	return _rifle_support_target if active_item_kind() == KIND_RIFLE \
			and (_rifle_aim_goal or _rifle_aim > 0.18 \
			or bool(_active_item.call("is_reloading"))) else null


func set_rifle_aim(on: bool) -> void:
	_rifle_aim_goal = on and active_item_kind() == KIND_RIFLE \
			and _preview_slot < 0 and not bool(_active_item.call("is_reloading"))


func rifle_aim_amount() -> float:
	return _rifle_aim


func rifle_loaded() -> bool:
	return bool(_active_item.call("is_loaded")) \
			if active_item_kind() == KIND_RIFLE else false


func rifle_reloading() -> bool:
	return bool(_active_item.call("is_reloading")) \
			if active_item_kind() == KIND_RIFLE else false


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
	_begin_take_motion(index)
	_reparent_active_item_for_carry(item)
	if active_item_kind() == KIND_KNIFE and _knife_hand_target != null:
		_configure_taken_knife(item)
	elif active_item_kind() == KIND_RIFLE:
		_configure_taken_rifle(item)
	return item


func _begin_take_motion(index: int) -> void:
	_take_source_slot = index
	_take_elapsed = 0.0
	_take_phase = TakePhase.GRASP
	_preview_slot = -1
	_knife_draw = 0.0
	_knife_release_left = 0.0
	_knife_release_item = null
	_rifle_aim = 0.0
	_rifle_aim_goal = false
	_rifle_ads_settle = 0.0
	_rifle_reload_blend = 0.0


func _reparent_active_item_for_carry(item: Node3D) -> void:
	var outside := get_parent() as Node3D
	if outside != null:
		item.reparent(outside, true)
	item.top_level = true
	item.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	item.reset_physics_interpolation()


func _configure_taken_knife(item: Node3D) -> void:
	var knife := _active_item as UtilityKnife3D
	var grip := knife.grip_node()
	var grip_transform := grip.transform if grip != null else Transform3D.IDENTITY
	_knife_hand_target.global_transform = item.global_transform * grip_transform
	_take_grip_start = _knife_hand_target.global_transform
	_knife_hand_target.set_meta("held_device", item)
	_knife_hand_target.set_meta("held_grip_transform", grip_transform)
	_knife_hand_target.set_meta("authored_grip_frame", true)
	_knife_hand_target.set_meta("grip_closure", 1.0)


func _configure_taken_rifle(item: Node3D) -> void:
	var rifle: Node3D = _active_item
	var primary := rifle.call("primary_grip_node") as Node3D
	var support := rifle.call("support_grip_node") as Node3D
	_rifle_primary_target.global_transform = item.global_transform * primary.transform
	_rifle_support_target.global_transform = item.global_transform * support.transform
	_set_rifle_take_target(_rifle_primary_target, item, primary.transform,
			rifle.call("primary_contact_bounds") as AABB)
	_set_rifle_take_target(_rifle_support_target, item, support.transform,
			rifle.call("support_contact_bounds") as AABB)


func _set_rifle_take_target(target_node: Node3D, item: Node3D,
		grip_transform: Transform3D, bounds: AABB) -> void:
	target_node.set_meta("held_device", item)
	target_node.set_meta("held_grip_transform", grip_transform)
	target_node.set_meta("contact_bounds", bounds)
	target_node.set_meta("ads_locked", false)
	target_node.set_meta("weapon_space_pinned", false)


func set_preview_slot(index: int) -> void:
	if active_item_kind() == KIND_RIFLE \
			and bool(_active_item.call("is_reloading")):
		_preview_slot = -1
		return
	_preview_slot = index if index >= 0 and index < SLOT_POSITIONS.size() \
			and not slot_occupied(index) and can_place_active(index) else -1


func place_active_in_slot(index: int) -> bool:
	if not can_place_active(index):
		return false
	var item := _active_item
	if item is UtilityKnife3D:
		(item as UtilityKnife3D).cancel_attack()
	elif str(item.get_meta("item_kind", "")) == KIND_RIFLE:
		item.call("cancel_reload")
	_seat_item_in_slot(item, index)
	if item is UtilityKnife3D:
		_begin_knife_release(item as UtilityKnife3D)
	_clear_active_item_state()
	return true


func _seat_item_in_slot(item: Node3D, index: int) -> void:
	item.reparent(self, true)
	item.top_level = false
	item.transform = _slot_transform(index)
	item.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_INHERIT
	item.reset_physics_interpolation()
	_slot_items[index] = item


func _begin_knife_release(knife: UtilityKnife3D) -> void:
	_knife_release_item = knife
	_knife_release_left = KNIFE_RELEASE_DURATION
	var grip := knife.grip_node()
	_knife_hand_target.global_transform = knife.global_transform \
			* (grip.transform if grip != null else Transform3D.IDENTITY)
	_knife_hand_target.set_meta("authored_grip_frame", true)
	_knife_hand_target.set_meta("grip_closure", 1.0)


func _clear_active_item_state() -> void:
	_active_item = null
	_active_label = ""
	_preview_slot = -1
	_rifle_aim = 0.0
	_rifle_aim_goal = false
	_rifle_ads_settle = 0.0
	_take_phase = TakePhase.IDLE
	_take_elapsed = -1.0
	_take_source_slot = -1
	_rifle_reload_blend = 0.0
	_clear_active_hand_metadata()


func _clear_active_hand_metadata() -> void:
	_knife_hand_target.remove_meta("held_device")
	_knife_hand_target.remove_meta("held_grip_transform")
	for target_node: Node3D in [_rifle_primary_target, _rifle_support_target]:
		for key in ["held_device", "held_grip_transform", "contact_bounds",
				"ads_locked", "weapon_space_pinned", "hand_pose",
				"hand_attachment", "held_device_target"]:
			if target_node.has_meta(key):
				target_node.remove_meta(key)


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


func begin_active_rifle_fire() -> bool:
	if active_item_kind() == KIND_RIFLE and _preview_slot < 0:
		var openness := 1.0
		var acoustic_source: Node = get_parent()
		while acoustic_source != null:
			if acoustic_source.has_method("weather_openness"):
				openness = float(acoustic_source.call("weather_openness",
						_active_item.global_position))
				break
			acoustic_source = acoustic_source.get_parent()
		_active_item.call("set_acoustic_openness", openness)
		return bool(_active_item.call("begin_fire"))
	return false


func begin_active_rifle_reload() -> bool:
	if active_item_kind() == KIND_RIFLE and _preview_slot < 0:
		_rifle_aim_goal = false
		_rifle_ads_settle = 0.0
		var started := bool(_active_item.call("begin_reload"))
		if started:
			_rifle_reload_blend = 0.0
		return started
	return false


func active_rifle_camera_kick() -> Vector3:
	if active_item_kind() == KIND_RIFLE:
		return _active_item.call("recoil_camera") as Vector3
	return Vector3.ZERO


func active_rifle_pressure() -> float:
	if active_item_kind() == KIND_RIFLE:
		return float(_active_item.call("pressure_amount"))
	return 0.0


func active_rifle_muzzle() -> Node3D:
	return _active_item.call("muzzle_node") as Node3D \
			if active_item_kind() == KIND_RIFLE else null


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
	var kind := active_item_kind()
	_update_take_phase(delta)
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
	# Hold the prop in its webbing for a short finger-closing beat. The existing
	# draw interpolation then becomes the visible extraction rather than an
	# immediate inventory transfer.
	var grasping := _take_phase == TakePhase.GRASP
	if grasping:
		target = _active_item.global_transform
	if _active_item is UtilityKnife3D:
		_update_active_knife(delta, camera, bag_amount, target, grasping)
	elif kind == KIND_RIFLE:
		var rifle: Node3D = _active_item
		rifle.call("tick", delta)
		var reloading := bool(rifle.call("is_reloading"))
		if reloading:
			_rifle_aim_goal = false
		_rifle_aim = move_toward(_rifle_aim, 1.0 if _rifle_aim_goal else 0.0,
				delta / (0.24 if _rifle_aim_goal else 0.18))
		if _rifle_aim_goal and _rifle_aim > 0.82 and _preview_slot < 0:
			_rifle_ads_settle += delta
		else:
			_rifle_ads_settle = 0.0
		var ads_grip_locked := _rifle_ads_settle >= RIFLE_ADS_GRIP_SETTLE
		# Reconstruct the trigger palm from the live weapon in carry as well as ADS.
		# hands.gd still waits until the palm is within 5 mm before locking, so the
		# approach remains natural but independent hand lag cannot swim through wood.
		var weapon_space_pinned := not reloading
		_rifle_primary_target.set_meta("ads_locked", ads_grip_locked)
		_rifle_support_target.set_meta("ads_locked", ads_grip_locked)
		_rifle_primary_target.set_meta("weapon_space_pinned", weapon_space_pinned)
		_rifle_support_target.set_meta("weapon_space_pinned", weapon_space_pinned)
		if reloading:
			# Left-hand work position: receiver rolled slightly toward the eyes,
			# chamber visible, muzzle still safely above the horizon.
			_rifle_reload_blend = minf(_rifle_reload_blend + delta / 0.28, 1.0)
			var reload_basis := Basis.from_euler(Vector3(deg_to_rad(13.0),
					deg_to_rad(-7.0), deg_to_rad(-28.0)))
			var reload_pose := camera.global_transform * Transform3D(reload_basis,
					Vector3(0.020, -0.120, -0.520))
			target = _active_item.global_transform.interpolate_with(reload_pose,
					smoothstep(0.0, 1.0, _rifle_reload_blend))
		elif _preview_slot == RIFLE_SLOT and bag_amount > 0.62:
			_rifle_reload_blend = 0.0
			# Keep the SLOT orientation but let the camera/right shoulder own the
			# stock-wrist contact. Positioning the rifle root from the bag made the arm
			# chase a point across the body; solve the root backwards from a stable
			# camera-space palm instead. E still performs the final seating into the U.
			var raised_slot := _slot_transform(RIFLE_SLOT)
			var staged := global_transform * raised_slot
			var staged_primary := rifle.call("primary_grip_node") as Node3D
			var grip_frame := staged * staged_primary.transform
			grip_frame.origin = camera.global_transform * Vector3(0.165, -0.255, -0.500)
			target = grip_frame * staged_primary.transform.affine_inverse()
		else:
			_rifle_reload_blend = 0.0
			# One-hand patrol carry: butt low at the right hip, muzzle safely above
			# the horizon. It leaves the left arm completely free for doors/controls.
			# Keep the stock close to the chest and the muzzle diagonally up. The
			# previous near-vertical, distant pose made this same unscaled model look
			# miniature through perspective.
			var carry_basis := Basis.from_euler(Vector3(deg_to_rad(38.0),
					deg_to_rad(-8.0), deg_to_rad(-7.0)))
			var carry := camera.global_transform * Transform3D(carry_basis,
					Vector3(0.255, -0.195, -0.365))
			var sight := rifle.call("aim_anchor_node") as Node3D
			var eye_line := camera.global_transform * Transform3D(Basis.IDENTITY,
					# Pre-compensate the measured shoulder/IK settle so the rendered
					# rear notch—not merely the mathematical target—lands at eye level.
					Vector3(0.0, 0.035, RIFLE_ADS_REAR_DISTANCE))
			var aimed := eye_line * sight.transform.affine_inverse()
			target = carry.interpolate_with(aimed,
					smoothstep(0.0, 1.0, _rifle_aim))
			target *= rifle.call("recoil_local_transform") as Transform3D
		# Advance the weapon once, here, before deriving either hand target. Both
		# palms must solve to the exact frame that will be rendered this tick. The
		# former code advanced the rifle after the hands and let each hand chase a
		# different future transform; reload completion exposed that as a final
		# corkscrew/pop.
		var weapon_k := 1.0 - exp(-15.0 * delta)
		# Once the draw is complete, carry is camera-local just like ADS. Smoothing
		# this world transform made the rifle trail the camera by one frame whenever
		# the ship rolled, which looked like uncontrolled one-hand shaking.
		var stable_camera_carry := _take_phase == TakePhase.COMPLETE \
				and _preview_slot < 0
		var weapon_frame := target if reloading or stable_camera_carry \
				or (_rifle_aim > 0.82 and _preview_slot < 0) \
				else _active_item.global_transform.interpolate_with(target, weapon_k)
		if _preview_slot < 0 and not reloading:
			weapon_frame = _resolve_rifle_obstruction(weapon_frame, rifle, camera)
		_active_item.global_transform = weapon_frame
		var primary_grip := rifle.call("primary_grip_node") as Node3D
		var support_grip := rifle.call("support_grip_node") as Node3D
		var primary_target := weapon_frame * primary_grip.transform
		var support_local := support_grip.transform
		var support_target := weapon_frame * support_local
		_rifle_support_target.set_meta("held_grip_transform", support_local)
		var placing_in_sling := _preview_slot == RIFLE_SLOT and bag_amount > 0.62
		if placing_in_sling:
			primary_target = weapon_frame * (rifle.call(
					"sling_placement_grip_transform") as Transform3D)
			# While lowering the rifle into the U-shaped sling the right hand supports
			# it from underneath: palm contact stays on the stock, but knuckles and
			# fingers turn upward.  Flipping K/F around semantic palm Y produces that
			# real underhand placement without changing the rifle or its normal grip.
			primary_target.basis = Basis(-primary_target.basis.x,
					primary_target.basis.y, -primary_target.basis.z)
		if not reloading:
			_configure_normal_rifle_hand(rifle, primary_grip)
			if placing_in_sling:
				# This placement frame is intentionally different from the authored
				# trigger grip, so the hand must follow the staged target this tick.
				_rifle_primary_target.set_meta("weapon_space_pinned", false)
				_rifle_primary_target.set_meta("contact_bounds", rifle.call(
						"sling_placement_contact_bounds") as AABB)
		if reloading:
			_rifle_support_target.global_transform = support_target
			_update_rifle_reload_hand(rifle, camera, target, primary_target)
		else:
			# Carry, return and ADS all share the rendered weapon frame. Smooth the
			# rifle itself, never a second disconnected hand target.
			_rifle_primary_target.global_transform = primary_target
			_rifle_support_target.global_transform = support_target
	var k := 1.0 - exp(-15.0 * delta)
	# In ADS the weapon is the invariant reference and the arms solve TO it.
	# Interpolating a camera-relative target in world space adds a one-frame boat
	# lag, and welding the rifle to a wrist lets IK rotate the sights. Both break
	# the iron-sight line. Once shouldered, stamp the authored target exactly.
	if kind != KIND_RIFLE:
		_active_item.global_transform = _active_item.global_transform.interpolate_with(target, k)
	_active_item.reset_physics_interpolation()


func _update_active_knife(delta: float, camera: Camera3D, bag_amount: float,
		target: Transform3D, grasping: bool) -> void:
	var knife := _active_item as UtilityKnife3D
	knife.tick_attack(delta)
	if _preview_slot >= 0 and bag_amount > 0.62:
		var grip := knife.grip_node()
		var grip_target := target \
				* (grip.transform if grip != null else Transform3D.IDENTITY)
		var return_k := 1.0 - exp(-10.0 * delta)
		_knife_hand_target.global_transform = \
				_knife_hand_target.global_transform.interpolate_with(grip_target, return_k)
		_knife_hand_target.set_meta("authored_grip_frame", true)
		return
	if _take_phase == TakePhase.CLEAR_RESTRAINT:
		var clear_u := smoothstep(0.0, 1.0, _knife_clear_progress())
		_knife_hand_target.set_meta("authored_grip_frame", true)
		_knife_hand_target.global_transform = _take_grip_start
		_knife_hand_target.global_position += global_basis.z * (KNIFE_CLEAR_PULL * clear_u)
		return
	_knife_hand_target.set_meta("authored_grip_frame", false)
	if not grasping:
		var turn_duration := TAKE_EXTRACT_DURATION - KNIFE_CLEAR_DURATION \
				if _take_source_slot == KNIFE_SLOT else TAKE_EXTRACT_DURATION
		_knife_draw = minf(_knife_draw + delta / turn_duration, 1.0)
	var palm_target := camera.global_transform * Transform3D(Basis.IDENTITY,
			knife.hand_position_camera_local())
	_knife_hand_target.global_transform = _knife_hand_target.global_transform \
			.interpolate_with(palm_target, smoothstep(0.0, 1.0, _knife_draw))


func _update_take_phase(delta: float) -> void:
	if _take_phase == TakePhase.IDLE or _take_phase == TakePhase.COMPLETE:
		return
	_take_elapsed = minf(_take_elapsed + delta,
			TAKE_GRASP_DURATION + TAKE_EXTRACT_DURATION)
	if _take_elapsed < TAKE_GRASP_DURATION:
		_take_phase = TakePhase.GRASP
	elif _take_source_slot == KNIFE_SLOT \
			and _take_elapsed < TAKE_GRASP_DURATION + KNIFE_CLEAR_DURATION:
		_take_phase = TakePhase.CLEAR_RESTRAINT
	elif _take_elapsed < TAKE_GRASP_DURATION + TAKE_EXTRACT_DURATION:
		_take_phase = TakePhase.TURN_TO_CARRY
	else:
		_take_phase = TakePhase.COMPLETE


func _knife_clear_progress() -> float:
	return clampf((_take_elapsed - TAKE_GRASP_DURATION) / KNIFE_CLEAR_DURATION,
			0.0, 1.0)


func _resolve_rifle_obstruction(frame: Transform3D, rifle: Node3D,
		camera: Camera3D) -> Transform3D:
	## Keep the weapon rigid. A thick camera-to-muzzle sweep finds the first boat
	## solid, then translates the complete rifle (and therefore both authored hand
	## targets) back until the muzzle's safety shell sits in front of the surface.
	## Applying this after interpolation prevents a fast turn from tunnelling for
	## one rendered frame.
	var boat := get_parent()
	if boat == null or not boat.has_method("rifle_obstruction_fraction"):
		return frame
	if bool(boat.get_meta("rifle_test_ignore_obstruction", false)):
		return frame
	var muzzle := rifle.call("muzzle_node") as Node3D
	if muzzle == null:
		return frame
	var muzzle_world := frame * muzzle.position
	var eye := camera.global_position
	var fraction := float(boat.call("rifle_obstruction_fraction",
			eye, muzzle_world, 0.060))
	fraction = minf(fraction, _world_rifle_obstruction_fraction(
			eye, muzzle_world, boat, 0.060))
	if fraction >= 0.999:
		return frame
	# First yield like a person: draw the stock toward the chest and lower the
	# muzzle. This keeps the rifle visible and the shoulder believable instead of
	# solving every wall by pushing the butt through the camera.
	var obstruction := clampf((1.0 - fraction) * 3.0, 0.0, 1.0)
	var lowered_basis := Basis.from_euler(Vector3(deg_to_rad(-52.0),
			deg_to_rad(-9.0), deg_to_rad(-8.0)))
	var lowered := camera.global_transform * Transform3D(lowered_basis,
			Vector3(0.235, -0.255, -0.300))
	frame = frame.interpolate_with(lowered, obstruction)
	muzzle_world = frame * muzzle.position
	fraction = float(boat.call("rifle_obstruction_fraction",
			eye, muzzle_world, 0.060))
	fraction = minf(fraction, _world_rifle_obstruction_fraction(
			eye, muzzle_world, boat, 0.060))
	if fraction >= 0.999:
		return frame
	var eye_to_muzzle := muzzle_world - eye
	var distance := eye_to_muzzle.length()
	if distance < 0.001:
		return frame
	# Six extra centimetres stop the visible barrel skin at the wall rather than
	# stopping only its centreline. No maximum pull: collision integrity wins
	# even when the player presses their face directly against a bulkhead.
	var allowed := maxf(distance * fraction - 0.060, 0.04)
	var pull := distance - allowed
	frame.origin -= eye_to_muzzle.normalized() * pull
	return frame


func _world_rifle_obstruction_fraction(from: Vector3, to: Vector3,
		boat: Node, radius: float) -> float:
	## Boat joinery is procedural and uses the local AABB contract above. This
	## companion sphere cast covers every other physics object in the world, so
	## crates, loose rigid bodies and future props gain the same guarantee without
	## needing a weapon-specific list.
	if get_world_3d() == null:
		return 1.0
	var shape := SphereShape3D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, from)
	query.motion = to - from
	if boat is CollisionObject3D:
		query.exclude = [(boat as CollisionObject3D).get_rid()]
	var result := get_world_3d().direct_space_state.cast_motion(query)
	return clampf(result[0], 0.0, 1.0) if result.size() >= 1 else 1.0


func _configure_normal_rifle_hand(rifle: Node3D, primary_grip: Node3D) -> void:
	_rifle_primary_target.remove_meta("held_device_target")
	_rifle_primary_target.set_meta("held_device", rifle)
	_rifle_primary_target.set_meta("held_grip_transform", primary_grip.transform)
	_rifle_primary_target.set_meta("contact_bounds",
			rifle.call("primary_contact_bounds") as AABB)
	_rifle_primary_target.set_meta("hand_pose", "rifle_primary")
	_rifle_primary_target.set_meta("hand_attachment", false)
	# The imported marker supplies the exact stock contact, but forcing its full
	# wrist rotation in ADS bends the right hand over the receiver. Preserve the
	# palm position and blend only its axes toward the live shoulder/forearm line;
	# the blend increases while shouldering, where the old corkscrew was visible.
	_rifle_primary_target.set_meta("natural_grip_blend",
			lerpf(0.10, 0.28, smoothstep(0.15, 0.90, _rifle_aim)))
	_rifle_primary_target.set_meta("natural_grip_keep_fingers", true)
	_rifle_primary_target.set_meta("palm_clearance", 0.0)
	_rifle_primary_target.set_meta("control_forward_reach", 0.0)
	_rifle_primary_target.set_meta("control_index_bias", 0.0)


func _reload_segment(t: float, start: float, finish: float) -> float:
	return smoothstep(0.0, 1.0, clampf((t - start) /
			maxf(finish - start, 0.001), 0.0, 1.0))


func _update_rifle_reload_hand(rifle: Node3D, camera: Camera3D,
		weapon_frame: Transform3D, primary_frame: Transform3D) -> void:
	var t := float(rifle.call("reload_elapsed"))
	var chamber_node := rifle.call("chamber_node") as Node3D
	var bolt_node := rifle.call("bolt_handle_node") as Node3D
	var cartridge := rifle.call("cartridge_node") as Node3D
	var chamber := weapon_frame * chamber_node.transform
	var round_palm_local := rifle.call("cartridge_palm_local") as Vector3
	# The cartridge, not the wrist, owns the chamber alignment. Its +Z axis stays
	# on the bore/receiver line while the anatomically solved hand translates from
	# the pocket. This prevents the old 180-degree forearm roll at insertion.
	var chamber_entry := chamber
	chamber_entry.origin -= chamber.basis.z.normalized() * 0.105
	chamber_entry.origin += chamber.basis.y.normalized() * 0.018
	var pocket_palm_position := camera.global_transform \
			* Vector3(0.205, -0.165, -0.365)
	var pocket_round := Transform3D(chamber.basis,
			pocket_palm_position - chamber.basis * round_palm_local)
	var desired_round := pocket_round
	# Never approximate the imported action with a second hand-only curve. The
	# returned grip is Bolt_Bone's live transform, so palm and metal cannot drift.
	var bolt := weapon_frame * (rifle.call("bolt_grip_transform") as Transform3D)
	# Only the CONTACT position follows every degree of Bolt_Bone rotation. The
	# reference action uses a horizontal pincer grasp: forearm arrives from the
	# lower-right, fingers travel across the receiver from right to left, and the
	# back of the hand stays UP like the reference. The palm is neither presented
	# to the player nor rolled toward the sky: it faces strongly down onto the
	# action with only a small forward component, which keeps forearm and wrist in
	# the same anatomical plane.
	var bolt_fingers := (-camera.global_basis.x * 0.90 \
			- camera.global_basis.y * 0.26 \
			- camera.global_basis.z * 0.12).normalized()
	var bolt_palm := -camera.global_basis.y * 0.90 \
			- camera.global_basis.z * 0.35
	bolt_palm -= bolt_palm.project(bolt_fingers)
	bolt_palm = bolt_palm.normalized()
	var bolt_knuckles := bolt_palm.cross(bolt_fingers).normalized()
	bolt.basis = Basis(bolt_knuckles, bolt_palm, bolt_fingers)
	var hand_frame := primary_frame
	var pose := "bolt_grip"
	var natural_grip_blend := _reload_segment(t, 0.0, 0.16)
	var carrying_round := t >= RELOAD_CARTRIDGE_SHOW and t < RELOAD_INSERTED
	var bolt_contact_active := false
	if t < RELOAD_BOLT_OPEN_START:
		# R begins by moving the firing hand to the bolt. The bolt animation cannot
		# start until the palm has arrived at the live knob transform.
		hand_frame = Transform3D(primary_frame.basis,
				primary_frame.origin.lerp(bolt.origin,
				_reload_segment(t, 0.0, RELOAD_BOLT_OPEN_START)))
		bolt_contact_active = t >= 0.12
	elif t < RELOAD_BOLT_OPEN_END:
		hand_frame = bolt
		bolt_contact_active = true
	elif t < RELOAD_CARTRIDGE_SHOW:
		# The animation is paused at its measured full-rear key. The hand may leave
		# the knob, but the metal remains open while it travels to the cartridge.
		pose = "pinch"
		hand_frame = Transform3D(chamber.basis,
				bolt.origin.lerp(pocket_palm_position,
				_reload_segment(t, RELOAD_BOLT_OPEN_END,
				RELOAD_CARTRIDGE_SHOW)))
	elif t < RELOAD_CARTRIDGE_MOVE:
		pose = "pinch"
		desired_round = pocket_round
		hand_frame = Transform3D(chamber.basis,
				desired_round * round_palm_local)
	elif t < RELOAD_CARTRIDGE_INSERT:
		pose = "pinch"
		desired_round = Transform3D(chamber.basis,
				pocket_round.origin.lerp(chamber_entry.origin,
				_reload_segment(t, RELOAD_CARTRIDGE_MOVE,
				RELOAD_CARTRIDGE_INSERT)))
		hand_frame = Transform3D(chamber.basis,
				desired_round * round_palm_local)
	elif t < RELOAD_INSERTED:
		pose = "pinch"
		desired_round = Transform3D(chamber.basis,
				chamber_entry.origin.lerp(chamber.origin,
				_reload_segment(t, RELOAD_CARTRIDGE_INSERT,
				RELOAD_INSERTED)))
		hand_frame = Transform3D(chamber.basis,
				desired_round * round_palm_local)
	elif t < RELOAD_BOLT_CLOSE_START:
		var approach_blend := _reload_segment(t,
				RELOAD_INSERTED, RELOAD_BOLT_CLOSE_START)
		# Position travels to the knob while the authored endpoint stays the
		# chamber frame. hands.gd performs the one and only chamber->natural wrist
		# blend; interpolating this basis too caused a hidden second rotation.
		var inserted_palm := chamber * round_palm_local
		hand_frame = Transform3D(chamber.basis,
				inserted_palm.lerp(bolt.origin, approach_blend))
		pose = "bolt_grip"
	elif t < RELOAD_BOLT_CLOSE_END:
		pose = "bolt_grip"
		hand_frame = bolt
		bolt_contact_active = true
	else:
		pose = "rifle_primary"
		var return_blend := _reload_segment(t, RELOAD_BOLT_CLOSE_END,
				RELOAD_DURATION)
		# Preserve one stable trigger-grip endpoint while the palm comes home.
		# Blending bolt->primary here and then blending it again against the
		# anatomical frame made the wrist corkscrew near the end of the reload.
		hand_frame = Transform3D(primary_frame.basis,
				bolt.origin.lerp(primary_frame.origin, return_blend))
		natural_grip_blend = 1.0 - return_blend

	_rifle_primary_target.global_transform = hand_frame
	_rifle_primary_target.set_meta("ads_locked", false)
	_rifle_primary_target.set_meta("weapon_space_pinned", false)
	_rifle_primary_target.set_meta("hand_pose", pose)
	_rifle_primary_target.set_meta("natural_grip_blend", natural_grip_blend)
	# BoltHandle is the metal knob, not the centre of a human palm. Keep its live
	# transform exact and place the palm outside it; curled fingertips are what
	# actually meet the control.
	var bolt_grip_blend := natural_grip_blend if pose == "bolt_grip" else 0.0
	_rifle_primary_target.set_meta("palm_clearance", 0.028 * bolt_grip_blend)
	# Put the knob in the thumb/index web, ahead of the palm and toward the index
	# side. Without these semantic offsets the nearest digits are ring/pinky even
	# though the wrist itself is anatomically straight.
	_rifle_primary_target.set_meta("control_forward_reach",
			0.018 * bolt_grip_blend)
	_rifle_primary_target.set_meta("control_index_bias",
			0.020 * bolt_grip_blend)
	_rifle_primary_target.set_meta("hand_attachment", carrying_round)
	if carrying_round and cartridge != null:
		cartridge.global_transform = desired_round
		cartridge.reset_physics_interpolation()
		_rifle_primary_target.set_meta("held_device", cartridge)
		_rifle_primary_target.set_meta("held_grip_transform", Transform3D.IDENTITY)
		# hands.gd reconstructs the grip basis from its neutral wrist result. The
		# local palm point remains fixed, while the round itself lands exactly on
		# this authored chamber-space transform.
		_rifle_primary_target.set_meta("held_device_target", desired_round)
		_rifle_primary_target.set_meta("contact_bounds",
				rifle.call("cartridge_contact_bounds") as AABB)
	elif bolt_contact_active:
		_rifle_primary_target.remove_meta("held_device_target")
		_rifle_primary_target.set_meta("held_device", rifle)
		_rifle_primary_target.set_meta("held_grip_transform", Transform3D.IDENTITY)
		_rifle_primary_target.set_meta("contact_bounds",
				rifle.call("bolt_contact_bounds") as AABB)
	elif t >= RELOAD_BOLT_CLOSE_END:
		_rifle_primary_target.remove_meta("held_device_target")
		var primary_grip := rifle.call("primary_grip_node") as Node3D
		_configure_normal_rifle_hand(rifle, primary_grip)
	else:
		_rifle_primary_target.remove_meta("held_device_target")
		# Empty hand travelling to the pocket; do not let the finger solver chase
		# the rifle across the frame before the cartridge appears.
		_rifle_primary_target.set_meta("held_device", null)
		_rifle_primary_target.set_meta("held_grip_transform", Transform3D.IDENTITY)


func _slot_transform(index: int) -> Transform3D:
	var basis := Basis.IDENTITY
	var origin: Vector3 = SLOT_POSITIONS[index]
	if index == KNIFE_SLOT:
		# Keep the knife vertical in its original slot with the handle below. Rotate
		# it around that long axis so the cutting edge points to screen-left. Its
		# shallow Z offset leaves both leather retainers visibly in front.
		basis = Basis(Vector3.UP, Vector3.BACK, Vector3.LEFT)
		origin.y -= 0.055
		origin.z += KNIFE_SLOT_PROUD
	elif index == RIFLE_SLOT:
		# Wrapper -Z is muzzle-forward; rotate it across the bag with the muzzle
		# to starboard. The model is centred, so both sling loops share the load.
		basis = Basis(Vector3.UP, deg_to_rad(-90.0))
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


func _ring(inner_radius: float, outer_radius: float, pos: Vector3,
		rot_deg: Vector3, material: Material, part_name: String) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner_radius
	mesh.outer_radius = outer_radius
	mesh.rings = 14
	mesh.ring_segments = 8
	return _mesh_instance(mesh, pos, rot_deg, material, part_name)


func _flat_strap_piece(from: Vector3, to: Vector3, width: float,
		thickness: float, material: Material, part_name: String) -> MeshInstance3D:
	## A flat leather band between two authored points in the bag's front plane.
	## Individual short pieces form a gentle curve without turning leather into
	## the round hose/cylinder silhouette the old handle used.
	var delta := to - from
	var angle := rad_to_deg(atan2(delta.y, delta.x))
	return _box(Vector3(delta.length(), width, thickness), from.lerp(to, 0.5),
			Vector3(0.0, 0.0, angle), material, part_name)


func _cubic_strap_point(a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		t: float) -> Vector3:
	var u := 1.0 - t
	return a * (u * u * u) + b * (3.0 * u * u * t) \
			+ c * (3.0 * u * t * t) + d * (t * t * t)


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
	var aged_leather := _material(Color(0.245, 0.128, 0.060), 0.97)
	var brass := _material(Color(0.42, 0.30, 0.12), 0.38, 0.78)
	var steel := _material(Color(0.26, 0.27, 0.27), 0.42, 0.72)
	var steel_dark := _material(Color(0.090, 0.095, 0.098), 0.58, 0.56)
	var flare_red := _material(Color(0.43, 0.055, 0.035), 0.75, 0.05)
	var glass := _material(Color(0.34, 0.42, 0.38), 0.12)
	var thread := _material(Color(0.50, 0.39, 0.23), 0.98)

	# Canvas volume.  Edge rolls soften the primitive silhouette and make the
	# bag read as stuffed cloth rather than a metal case.
	_register_soft_canvas(_box(Vector3(0.48, 0.34, 0.135),
			Vector3(0.0, -0.025, 0.0), Vector3.ZERO, canvas, "CanvasBody"))
	_register_soft_canvas(_cylinder(0.040, 0.29,
			Vector3(-0.235, -0.025, 0.0), Vector3.ZERO,
			canvas_dark, "LeftCanvasRoll"))
	_register_soft_canvas(_cylinder(0.040, 0.29,
			Vector3(0.235, -0.025, 0.0), Vector3.ZERO,
			canvas_dark, "RightCanvasRoll"))
	_register_soft_canvas(_cylinder(0.038, 0.45,
			Vector3(0.0, -0.195, 0.0), Vector3(0.0, 0.0, 90.0),
			canvas_dark, "BottomCanvasRoll"))
	_register_soft_canvas(_cylinder(0.033, 0.48,
			Vector3(0.0, 0.185, 0.005), Vector3(0.0, 0.0, 90.0),
			canvas, "RolledMouth"))

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

	# Old carry strap: both ends are visibly riveted into reinforced leather tabs
	# on the bag's rolled mouth. A shallow, asymmetric arch reads as softened,
	# load-bearing hide; a perfect round cylinder read as a loose rubber hose.
	for x in [-0.180, 0.180]:
		_box(Vector3(0.042, 0.104, 0.014), Vector3(x, 0.178, 0.072),
				Vector3(0.0, 0.0, -8.0 * signf(x)), leather_edge,
				"CarryStrapTab")
		_cylinder(0.007, 0.008, Vector3(x, 0.157, 0.082),
				Vector3(90.0, 0.0, 0.0), brass, "CarryStrapRivet", 10)
		_stitch_line(Vector3(x - 0.012, 0.142, 0.081),
				Vector3(x - 0.012, 0.204, 0.081), 4, thread,
				"CarryTabStitch")
	var carry_curve := PackedVector3Array([
		Vector3(-0.180, 0.188, 0.076),
		Vector3(-0.181, 0.207, 0.078),
		Vector3(-0.145, 0.232, 0.080),
		Vector3(-0.090, 0.250, 0.081),
		Vector3(-0.030, 0.257, 0.082),
		Vector3(0.040, 0.256, 0.082),
		Vector3(0.105, 0.242, 0.081),
		Vector3(0.156, 0.215, 0.079),
		Vector3(0.180, 0.188, 0.076),
	])
	for index in carry_curve.size() - 1:
		_flat_strap_piece(carry_curve[index], carry_curve[index + 1], 0.030,
				0.010, aged_leather if index % 3 != 1 else leather_edge,
				"AgedCarryStrap%02d" % index)

	# Short side carry loop from the user's physical reference.  This is a real
	# load path stitched into the reinforced left roll: the palm lands on the
	# outer vertical run, leaving every front pocket readable and selectable.
	var side_carry_curve := PackedVector3Array([
		Vector3(-0.232, 0.116, 0.078),
		Vector3(-0.274, 0.120, 0.080),
		Vector3(-0.305, 0.094, 0.084),
		Vector3(-0.305, 0.052, 0.084),
		Vector3(-0.302, 0.012, 0.083),
		Vector3(-0.272, -0.010, 0.080),
		Vector3(-0.232, 0.000, 0.078),
	])
	for index in side_carry_curve.size() - 1:
		_flat_strap_piece(side_carry_curve[index], side_carry_curve[index + 1],
				0.026, 0.009,
				aged_leather if index % 2 == 0 else leather_edge,
				"SideCarryLoop%02d" % index)
	_box(Vector3(0.050, 0.150, 0.014), Vector3(-0.231, 0.054, 0.072),
			Vector3.ZERO, leather, "SideCarryReinforcement")
	for stitch_y in [0.010, 0.052, 0.094]:
		_stitch_line(Vector3(-0.238, stitch_y, 0.080),
				Vector3(-0.218, stitch_y, 0.080), 2, thread,
				"SideCarryStitch")

	# The shoulder strap is sewn around the lower canvas roll, not pinned to an
	# arbitrary point on the face. Reinforced ears visibly travel behind the bag,
	# curl under its bottom edge and finish in load-bearing brass rings.
	for x in [-0.218, 0.218]:
		_flat_strap_piece(Vector3(x, -0.105, 0.072),
				Vector3(x, -0.190, 0.050), 0.040, 0.012, leather_edge,
				"ShoulderUnderwrap")
		_box(Vector3(0.048, 0.080, 0.016), Vector3(x, -0.157, 0.050),
				Vector3(8.0, 0.0, -4.0 * signf(x)), leather,
				"ShoulderStrapEar")
		for rivet_y in [-0.130, -0.166]:
			_cylinder(0.006, 0.009, Vector3(x, rivet_y, 0.061),
					Vector3(90.0, 0.0, 0.0), brass, "ShoulderEarRivet", 10)
		_register_load_ring(_ring(0.014, 0.022,
				Vector3(x, -0.184, 0.047),
				Vector3(90.0, 0.0, 0.0), brass, "ShoulderStrapRing"))
	# The long shoulder strap is still attached while the bag is swung into the
	# lap. It falls in a broad U behind the rifle rather than hovering beside the
	# wrist. Alternating worn panels break the procedural-perfect silhouette.
	var shoulder_curve := PackedVector3Array()
	_shoulder_strap_parts.clear()
	var left_curve := [
		Vector3(-0.218, -0.155, 0.038),
		Vector3(-0.300, -0.255, 0.040),
		Vector3(-0.270, -0.485, 0.052),
		Vector3(0.000, -0.495, 0.058),
	]
	var right_curve := [
		Vector3(0.000, -0.495, 0.058),
		Vector3(0.270, -0.485, 0.052),
		Vector3(0.300, -0.255, 0.040),
		Vector3(0.218, -0.155, 0.038),
	]
	for sample in 25:
		shoulder_curve.append(_cubic_strap_point(left_curve[0], left_curve[1],
				left_curve[2], left_curve[3], float(sample) / 24.0))
	for sample in range(1, 25):
		shoulder_curve.append(_cubic_strap_point(right_curve[0], right_curve[1],
				right_curve[2], right_curve[3], float(sample) / 24.0))
	for index in shoulder_curve.size() - 1:
		var strap_piece := _flat_strap_piece(shoulder_curve[index], shoulder_curve[index + 1],
				0.034, 0.007,
				aged_leather if floori(float(index) / 10.0) % 3 != 1 else leather,
				"AgedShoulderStrap%02d" % index)
		_shoulder_strap_parts.append(strap_piece)

	# Exterior quick-access fittings: each tool has its own root and physical
	# slot. These are the exact meshes the right hand removes; no inventory icon
	# or duplicate viewmodel is swapped in when E is pressed.
	var tool_z := 0.125
	_slot_anchors.clear()
	_pointer_anchors.clear()
	_slot_items.clear()
	for index in SLOT_POSITIONS.size():
		var anchor := Node3D.new()
		anchor.name = "Slot%d" % (index + 1)
		anchor.transform = _slot_transform(index)
		add_child(anchor)
		_slot_anchors.append(anchor)
		var pointer_anchor := Node3D.new()
		pointer_anchor.name = "Slot%dPointer" % (index + 1)
		pointer_anchor.transform = _slot_transform(index)
		# Local +Z is the bag's camera-facing normal in inspection pose. Four
		# centimetres leaves the extended fingertip visibly clear of the prop.
		pointer_anchor.position += Vector3(0.0, 0.0, 0.040)
		if index == RIFLE_SLOT:
			pointer_anchor.set_meta("centre_point_roll", true)
		add_child(pointer_anchor)
		_pointer_anchors.append(pointer_anchor)
		var item: Node3D
		if index == KNIFE_SLOT:
			item = UtilityKnifeScript.new() as Node3D
		elif index == RIFLE_SLOT:
			item = HuntingRifleScript.new() as Node3D
		else:
			item = Node3D.new()
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
		var slot := [-0.178, -0.060, 0.060, 0.174].find(x)
		for y in [-0.105, 0.015]:
			var loop := _box(Vector3(0.060, 0.018, 0.016),
					Vector3(x, y, tool_z + 0.020), Vector3.ZERO, leather, "ToolLoop")
			_register_tool_loop(slot, loop)

	# Dedicated long-gun cradle below the ordinary inventory. Each restraint is a
	# real U around the rifle cross-section: rear leg attached to the bag, bridge
	# under the wood/receiver, and a front leather face touching the weapon. The
	# aft loop sits farther onto the stock instead of ending in empty air beside it.
	for x in [-0.355, 0.285]:
		var muzzle_loop: bool = float(x) > 0.0
		# The starboard restraint carries only the slim barrel. It must not reuse
		# the stock-sized U on the left: leave just enough leather clearance for
		# the bore tube and its wrapping.
		var band_w := 0.036 if muzzle_loop else 0.055
		var leg_h := 0.045 if muzzle_loop else 0.125
		# Barrel centre sits above the rifle wrapper origin. Raise the compact U as
		# a whole so its short legs actually flank the muzzle instead of hanging
		# below it in empty space.
		var leg_y := -0.274 if muzzle_loop else -0.320
		var rear_z := 0.123 if muzzle_loop else 0.112
		var front_z := 0.168 if muzzle_loop else 0.180
		var under_y := -0.303 if muzzle_loop else -0.382
		var under_d := 0.048 if muzzle_loop else 0.074
		var top_y := leg_y + leg_h * 0.5
		# The cradle is wider than the canvas body. A diagonal load strap joins
		# each loop to a reinforced lower corner instead of leaving it floating.
		var bag_x := 0.205 * signf(x)
		_box(Vector3(0.058, 0.072, 0.018), Vector3(bag_x, -0.165, 0.112),
				Vector3.ZERO, leather_edge, "RifleSlingAnchorTab")
		_cylinder(0.008, 0.012, Vector3(bag_x, -0.174, 0.124),
				Vector3(90.0, 0.0, 0.0), brass, "RifleSlingAnchorRivet", 10)
		_flat_strap_piece(Vector3(bag_x, -0.185, 0.120),
				Vector3(x, top_y, rear_z + 0.004),
				0.034 if muzzle_loop else 0.046, 0.018, leather,
				"RifleSlingConnection")
		# Hidden/rear leg against the bag.
		var sling_rear := _box(Vector3(band_w, leg_h, 0.018),
				Vector3(x, leg_y, rear_z), Vector3.ZERO, leather_edge, "RifleSlingRear")
		# Lower return closes the U beneath the rifle rather than leaving two tabs.
		var sling_under := _box(Vector3(band_w, 0.018, under_d), Vector3(x, under_y,
				(rear_z + front_z) * 0.5), Vector3.ZERO, leather_edge, "RifleSlingUnder")
		# Camera-facing band crosses the actual stock/receiver surface.
		var sling_front := _box(Vector3(band_w, leg_h, 0.020),
				Vector3(x, leg_y, front_z), Vector3.ZERO, leather, "RifleSlingFront")
		for sling_part in [sling_rear, sling_under, sling_front]:
			_register_rifle_sling(sling_part)
		_cylinder(0.009 if not muzzle_loop else 0.007,
				0.060 if not muzzle_loop else 0.040,
				Vector3(x, top_y, front_z - 0.002),
				Vector3(0.0, 0.0, 90.0), brass, "RifleSlingRivet", 10)

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
