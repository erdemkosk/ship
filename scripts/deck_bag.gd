extends Node3D
class_name DeckBag3D
## A compact waxed-canvas deck bag for quick-access tools.  It is built from
## real 3D pieces so the inventory can later move from this wall stowage into
## the player's hands without swapping to a painted interface.

const UtilityKnifeScript := preload("res://scripts/utility_knife.gd")
const HuntingRifleScript := preload("res://scripts/hunting_rifle.gd")
const DeckBagVisualBuilderScript := preload("res://scripts/deck_bag_visual_builder.gd")
const DeckBagLayoutScript := preload("res://scripts/deck_bag_layout.gd")
const DeckBagRifleObstructionScript := preload("res://scripts/deck_bag_rifle_obstruction.gd")
const DeckBagRifleReloadControllerScript := preload("res://scripts/deck_bag_rifle_reload_controller.gd")
const KIND_KNIFE := "utility_knife"
const KIND_RIFLE := "hunting_rifle"

var _clock := 0.0
const SLOT_POSITIONS := DeckBagLayoutScript.SLOT_POSITIONS
const SLOT_LABELS := DeckBagLayoutScript.SLOT_LABELS
const KNIFE_SLOT := DeckBagLayoutScript.KNIFE_SLOT
const RIFLE_SLOT := DeckBagLayoutScript.RIFLE_SLOT
const SLOT_WEIGHTS := [0.32, 0.24, 0.18, 0.36, 1.45]

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
var _knife_release_start := Transform3D.IDENTITY
var _rifle_primary_target: Node3D
var _rifle_support_target: Node3D
var _rifle_aim := 0.0
var _rifle_aim_goal := false
var _rifle_ads_settle := 0.0
var _rifle_reload_blend := 0.0
var _rifle_obstruction: DeckBagRifleObstruction = DeckBagRifleObstructionScript.new()
var _rifle_reload_controller: DeckBagRifleReloadController = \
		DeckBagRifleReloadControllerScript.new()
const TAKE_GRASP_DURATION := 0.12
const TAKE_EXTRACT_DURATION := 0.34
const KNIFE_CLEAR_DURATION := 0.16
# Account for the imported handle's thickness, not only its wrapper origin. A
# small negative offset keeps the complete knife behind the retaining leather
# while its rear face still remains clear of the canvas skin.
const KNIFE_CLEAR_PULL := 0.145
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
var _side_handle_parts: Array[MeshInstance3D] = []
var _side_handle_points := PackedVector3Array()
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
	var visual_state: Dictionary = DeckBagVisualBuilderScript.new().build(self)
	for property: String in visual_state:
		set(property, visual_state[property])
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


func _slot_transform(index: int) -> Transform3D:
	## Runtime seating uses the same authored slot contract as the visual builder.
	return DeckBagLayoutScript.slot_transform(index)


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
		# Breathing belongs to the weighted swing, not the inventory screen. Once
		# both hands brace the open bag, even a few millimetres of decorative motion
		# makes the independently solved arms drift through one another on a rolling
		# ship. Fade it out completely before selection becomes active.
		var settled := smoothstep(0.72, 1.0, ease)
		var inspection_lock := smoothstep(0.82, 0.96, ease)
		var breathing := settled * (1.0 - inspection_lock)
		pos.x += sin(_clock * 1.15) * 0.0035 * breathing
		pos.y += sin(_clock * 1.72 + 0.8) * 0.0025 * breathing
		var rot := Vector3(
			deg_to_rad(lerpf(18.0, -5.0, ease) + weight_arc * 8.0),
			deg_to_rad(lerpf(-108.0, 0.0, ease)),
			deg_to_rad(weight_arc * -13.0 + sin(_clock * 1.15) * 0.8 * settled))
		var anchor_xf := camera.global_transform * Transform3D(Basis.from_euler(rot), pos)
		_update_sling_physics(delta, camera, anchor_xf, ease)
		reset_physics_interpolation()
		_update_physical_shoulder_strap(ease)
		_update_side_carry_handle(ease)
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
	if open_amount >= 0.96:
		# The left hand owns the side handle and the right hand owns the selected
		# slot. At this point the load is physically closed between two contacts;
		# retaining pendulum history only lets a wave inject motion between palms.
		_sling_velocity = Vector2.ZERO
		_sling_angle = Vector2.ZERO
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
	# As the left fist takes the side loop, the load settles a few millimetres
	# toward that hand and loses the last loose roll. This is weight transfer, not
	# a decorative bob, and vanishes again while the bag returns to the shoulder.
	var hand_load := smoothstep(0.28, 0.92, open_amount)
	var hand_seat := Transform3D(Basis.from_euler(Vector3(0.0, 0.0,
			deg_to_rad(1.4) * hand_load)),
			Vector3(-0.007, -0.004, 0.0) * hand_load)
	global_transform = anchor_xf * Transform3D(swing_basis, travel) * hand_seat


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


func _update_side_carry_handle(open_amount: float) -> void:
	if _side_handle_parts.size() != _side_handle_points.size() - 1:
		return
	var points := _side_handle_points.duplicate()
	var tension := smoothstep(0.18, 0.86, open_amount)
	# Index 3 is the authored palm contact and never moves. Adjacent leather
	# straightens toward it under load; the stitched ends retain a little lag.
	points[2].x = lerpf(points[2].x, -0.305, tension)
	points[4].x = lerpf(points[4].x, -0.305, tension)
	var lag_z := -_sling_angle.x * 0.020 * (1.0 - tension)
	for index in points.size():
		if index != 3:
			var influence := sin(float(index) / float(points.size() - 1) * PI)
			points[index].z += lag_z * influence
	for index in _side_handle_parts.size():
		_set_flat_strap_piece(_side_handle_parts[index], points[index], points[index + 1])

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
		var authored_scale := rest.basis.get_scale()
		part.scale = authored_scale * Vector3(1.0 + compression * 0.55,
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
		# Loaded leather hangs lower; empty leather remembers the curve but springs
		# back enough that the vacant rifle slot is immediately readable.
		part.position.y += -0.006 if slot_occupied(RIFLE_SLOT) else 0.004
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


func rifle_support_required() -> bool:
	## Patrol carry deliberately leaves the left hand free. The support hand joins
	## only while shouldering the rifle or operating its action during reload.
	if active_item_kind() != KIND_RIFLE:
		return false
	return _rifle_aim_goal or _rifle_aim > 0.02 \
			or bool(_active_item.call("is_reloading"))


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
	# Preserve the hand's raised preview frame. The item is now seated, but the
	# palm must release from in front of the canvas and withdraw outward; snapping
	# it to the slot's deep grip frame made the complete hand enter the backpack.
	_knife_release_start = _knife_hand_target.global_transform
	_knife_hand_target.set_meta("authored_grip_frame", true)
	_knife_hand_target.set_meta("inventory_braced", true)
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
				"hand_attachment", "held_device_target", "inventory_braced"]:
			if target_node.has_meta(key):
				target_node.remove_meta(key)


func _update_knife_release(delta: float) -> void:
	if _knife_release_left <= 0.0 or _knife_release_item == null \
			or not is_instance_valid(_knife_release_item):
		_knife_release_left = 0.0
		_knife_release_item = null
		_knife_hand_target.remove_meta("inventory_braced")
		return
	_knife_release_left = maxf(_knife_release_left - delta, 0.0)
	var grip := _knife_release_item.grip_node()
	var seated_grip := _knife_release_item.global_transform \
			* (grip.transform if grip != null else Transform3D.IDENTITY)
	# A hard clearance plane in front of the organiser. The first beat follows
	# the knife only as far as this plane; after the fingers open, the palm peels
	# outward and slightly to the thumb side instead of retreating through cloth.
	var safe_seat := seated_grip
	safe_seat.origin += global_basis.z * 0.064
	_knife_hand_target.set_meta("authored_grip_frame", true)
	var progress := 1.0 - _knife_release_left / KNIFE_RELEASE_DURATION
	if progress < 0.38:
		_knife_hand_target.global_transform = _knife_release_start.interpolate_with(
				safe_seat, smoothstep(0.0, 1.0, progress / 0.38))
	else:
		var retract := safe_seat
		retract.origin += global_basis.z * 0.105 + global_basis.x * 0.030
		_knife_hand_target.global_transform = safe_seat.interpolate_with(retract,
				smoothstep(0.0, 1.0, inverse_lerp(0.38, 1.0, progress)))
	_knife_hand_target.set_meta("grip_closure",
			1.0 - smoothstep(0.12, 0.58, progress))


func begin_active_attack() -> bool:
	if _active_item is UtilityKnife3D and _preview_slot < 0:
		return (_active_item as UtilityKnife3D).begin_attack()
	return false


func begin_active_rifle_fire() -> bool:
	if active_item_kind() == KIND_RIFLE and _preview_slot < 0:
		var openness := 1.0
		var acoustic_space := &"deck"
		var acoustic_source: Node = get_parent()
		while acoustic_source != null:
			if acoustic_source.has_method("weather_openness"):
				openness = float(acoustic_source.call("weather_openness",
						_active_item.global_position))
				if acoustic_source.has_method("acoustic_space"):
					acoustic_space = acoustic_source.call("acoustic_space",
							_active_item.global_position) as StringName
				break
			acoustic_source = acoustic_source.get_parent()
		if _active_item.has_method("set_acoustic_environment"):
			_active_item.call("set_acoustic_environment", acoustic_space, openness)
		else:
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
		var previewing_rifle := _preview_slot == RIFLE_SLOT and bag_amount > 0.62
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
		elif previewing_rifle:
			_rifle_reload_blend = 0.0
			# Raise the actual sling transform as one rigid assembly. Solving the rifle
			# backwards from a camera-right palm pushed nearly the entire long gun out
			# of frame after the padded compartment made the composition wider.
			var raised_slot := _slot_transform(RIFLE_SLOT)
			target = global_transform * raised_slot
			target.origin += global_basis.z * 0.075 + global_basis.y * 0.018
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
				or (previewing_rifle and bag_amount >= 0.90) \
				or (_rifle_aim > 0.82 and _preview_slot < 0) \
				else _active_item.global_transform.interpolate_with(target, weapon_k)
		if _preview_slot < 0 and not reloading:
			weapon_frame = _rifle_obstruction.resolve(self, weapon_frame, rifle, camera)
		_active_item.global_transform = weapon_frame
		var primary_grip := rifle.call("primary_grip_node") as Node3D
		var support_grip := rifle.call("support_grip_node") as Node3D
		var primary_target := weapon_frame * primary_grip.transform
		var support_local := support_grip.transform
		var support_target := weapon_frame * support_local
		_rifle_support_target.set_meta("held_grip_transform", support_local)
		var placing_in_sling := previewing_rifle
		_rifle_primary_target.set_meta("inventory_braced",
				placing_in_sling and bag_amount >= 0.90)
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
			_rifle_reload_controller.update(rifle, camera, target, primary_target,
					_rifle_primary_target, _configure_normal_rifle_hand)
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
		if _preview_slot >= 0 and bag_amount >= 0.90:
			_active_item.global_transform = target
		else:
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
		if bag_amount >= 0.90:
			_knife_hand_target.global_transform = grip_target
		else:
			var return_k := 1.0 - exp(-10.0 * delta)
			var current_local := global_transform.affine_inverse() \
					* _knife_hand_target.global_transform
			var target_local := global_transform.affine_inverse() * grip_target
			_knife_hand_target.global_transform = global_transform \
					* current_local.interpolate_with(target_local, return_k)
		_knife_hand_target.set_meta("authored_grip_frame", true)
		_knife_hand_target.set_meta("inventory_braced", true)
		return
	_knife_hand_target.remove_meta("inventory_braced")
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
	if _take_source_slot == KNIFE_SLOT and _take_phase == TakePhase.TURN_TO_CARRY:
		# Deterministic clearance arc: the palm begins fourteen centimetres in
		# front of the MOLLE panel, moves a little farther out, then turns toward
		# camera carry. A straight world-space interpolation cut the forearm through
		# the bag whenever ship roll moved the final target across the slot.
		var draw_u := smoothstep(0.0, 1.0, _knife_draw)
		var clear_frame := _take_grip_start
		clear_frame.origin += global_basis.z * KNIFE_CLEAR_PULL
		var control := clear_frame.origin + global_basis.z * 0.070 \
				+ global_basis.x * 0.035
		var u_inv := 1.0 - draw_u
		_knife_hand_target.global_position = clear_frame.origin * (u_inv * u_inv) \
				+ control * (2.0 * u_inv * draw_u) \
				+ palm_target.origin * (draw_u * draw_u)
		_knife_hand_target.global_basis = clear_frame.basis.slerp(
				palm_target.basis, draw_u)
	else:
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
