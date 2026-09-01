extends Node3D
class_name DeckBag3D
## A compact waxed-canvas deck bag for quick-access tools.  It is built from
## real 3D pieces so the inventory can later move from this wall stowage into
## the player's hands without swapping to a painted interface.

const UtilityKnifeScript := preload("res://scripts/utility_knife.gd")
const HuntingRifleScript := preload("res://scripts/hunting_rifle.gd")

var _clock := 0.0
const SLOT_POSITIONS := [
	Vector3(-0.178, -0.040, 0.125),
	Vector3(-0.060, -0.045, 0.125),
	Vector3(0.060, -0.050, 0.125),
	Vector3(0.174, -0.045, 0.125),
	# The long-gun cradle overlaps the bag's lower lip by a few centimetres.
	# This keeps it unmistakably BELOW the tool row without letting the camera
	# crop the rifle and its straps out of the inspection view.
	# The imported armature's visible stock sits about 18 cm below its semantic
	# root. This compensated root position places the actual rifle across the
	# lowest face of the bag (not off the bottom of the viewport).
	Vector3(0.0, -0.235, 0.245),
]
const SLOT_LABELS := ["Flashlight", "Signal flare", "Utility knife", "Multitool",
		"Hunting rifle"]
const RIFLE_SLOT := 4
const RELOAD_CARTRIDGE_SHOW := 0.28
const RELOAD_INSERTED := 1.32
const RELOAD_BOLT_START := 1.42
const RELOAD_BOLT_END := 2.42
const RELOAD_DURATION := 2.75

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
var _rifle_primary_target: Node3D
var _rifle_support_target: Node3D
var _rifle_draw := 1.0
var _rifle_aim := 0.0
var _rifle_aim_goal := false
var _rifle_ads_settle := 0.0
var _rifle_reload_blend := 0.0
# The raise itself already consumes about 0.24 s. After the sights cross the
# shoulder threshold, one short 60 ms seating window is enough before the
# weapon-space lock may engage; surface/contact checks still prevent an early
# bad freeze.
const RIFLE_ADS_GRIP_SETTLE := 0.06


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
		# Raise the bag body so the dedicated long-gun sling can live physically
		# beneath it without the rifle being cropped out of the inspection view.
		var inspect := Vector3(0.050, 0.070, -0.570)
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
	var rifle := active_item_kind() == "hunting_rifle"
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
	if active_item_kind() == "utility_knife":
		return _knife_hand_target
	return _active_item


func active_hand_mode() -> String:
	if active_item_kind() == "utility_knife":
		return "knife"
	if active_item_kind() == "hunting_rifle":
		return "rifle"
	return "hold"


func rifle_primary_target() -> Node3D:
	return _rifle_primary_target if active_item_kind() == "hunting_rifle" else null


func rifle_support_target() -> Node3D:
	# Low carry deliberately reserves only the trigger hand. The support hand
	# joins while shouldering and stays through the short lower-from-ADS blend.
	return _rifle_support_target if active_item_kind() == "hunting_rifle" \
			and (_rifle_aim_goal or _rifle_aim > 0.18 \
			or bool(_active_item.call("is_reloading"))) else null


func set_rifle_aim(on: bool) -> void:
	_rifle_aim_goal = on and active_item_kind() == "hunting_rifle" \
			and _preview_slot < 0 and not bool(_active_item.call("is_reloading"))


func rifle_aim_amount() -> float:
	return _rifle_aim


func rifle_loaded() -> bool:
	return bool(_active_item.call("is_loaded")) \
			if active_item_kind() == "hunting_rifle" else false


func rifle_reloading() -> bool:
	return bool(_active_item.call("is_reloading")) \
			if active_item_kind() == "hunting_rifle" else false


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
	_rifle_draw = 0.0
	_rifle_aim = 0.0
	_rifle_aim_goal = false
	_rifle_ads_settle = 0.0
	_rifle_reload_blend = 0.0
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
	elif active_item_kind() == "hunting_rifle":
		var rifle: Node3D = _active_item
		var primary := rifle.call("primary_grip_node") as Node3D
		var support := rifle.call("support_grip_node") as Node3D
		_rifle_primary_target.global_transform = item.global_transform \
				* primary.transform
		_rifle_support_target.global_transform = item.global_transform \
				* support.transform
		_rifle_primary_target.set_meta("held_device", item)
		_rifle_primary_target.set_meta("held_grip_transform", primary.transform)
		_rifle_primary_target.set_meta("contact_bounds",
				rifle.call("primary_contact_bounds") as AABB)
		_rifle_primary_target.set_meta("ads_locked", false)
		_rifle_primary_target.set_meta("weapon_space_pinned", false)
		_rifle_support_target.set_meta("held_device", item)
		_rifle_support_target.set_meta("held_grip_transform", support.transform)
		_rifle_support_target.set_meta("contact_bounds",
				rifle.call("support_contact_bounds") as AABB)
		_rifle_support_target.set_meta("ads_locked", false)
		_rifle_support_target.set_meta("weapon_space_pinned", false)
	return item


func set_preview_slot(index: int) -> void:
	if active_item_kind() == "hunting_rifle" \
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
	elif str(item.get_meta("item_kind", "")) == "hunting_rifle":
		item.call("cancel_reload")
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
	_rifle_aim = 0.0
	_rifle_aim_goal = false
	_rifle_ads_settle = 0.0
	_rifle_reload_blend = 0.0
	_knife_hand_target.remove_meta("held_device")
	_knife_hand_target.remove_meta("held_grip_transform")
	for target_node: Node3D in [_rifle_primary_target, _rifle_support_target]:
		for key in ["held_device", "held_grip_transform", "contact_bounds",
				"ads_locked", "weapon_space_pinned", "hand_pose",
				"hand_attachment", "held_device_target"]:
			if target_node.has_meta(key):
				target_node.remove_meta(key)
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


func begin_active_rifle_fire() -> bool:
	if active_item_kind() == "hunting_rifle" and _preview_slot < 0:
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
	if active_item_kind() == "hunting_rifle" and _preview_slot < 0:
		_rifle_aim_goal = false
		_rifle_ads_settle = 0.0
		var started := bool(_active_item.call("begin_reload"))
		if started:
			_rifle_reload_blend = 0.0
		return started
	return false


func active_rifle_camera_kick() -> Vector3:
	if active_item_kind() == "hunting_rifle":
		return _active_item.call("recoil_camera") as Vector3
	return Vector3.ZERO


func active_rifle_pressure() -> float:
	if active_item_kind() == "hunting_rifle":
		return float(_active_item.call("pressure_amount"))
	return 0.0


func active_rifle_muzzle() -> Node3D:
	return _active_item.call("muzzle_node") as Node3D \
			if active_item_kind() == "hunting_rifle" else null


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
	elif active_item_kind() == "hunting_rifle":
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
		# Let the shoulder/forearms finish the raise before capturing their rigid
		# weapon-space hold. Pinning at the first ADS frame freezes an arm that is
		# still short of the stock; the brief settle is part of the raise, not sway.
		var weapon_space_pinned := ads_grip_locked and not reloading
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
			# Keep the rifle physically in the right hand, lifted just clear of its
			# sling. E completes the final short seating movement into the cradle.
			var raised_slot := _slot_transform(RIFLE_SLOT)
			raised_slot.origin += Vector3(0.0, 0.055, 0.075)
			target = global_transform * raised_slot
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
					Vector3(0.0, 0.035, -0.300))
			var aimed := eye_line * sight.transform.affine_inverse()
			target = carry.interpolate_with(aimed,
					smoothstep(0.0, 1.0, _rifle_aim))
			target *= rifle.call("recoil_local_transform") as Transform3D
		_rifle_draw = minf(_rifle_draw + delta / 0.46, 1.0)
		# Advance the weapon once, here, before deriving either hand target. Both
		# palms must solve to the exact frame that will be rendered this tick. The
		# former code advanced the rifle after the hands and let each hand chase a
		# different future transform; reload completion exposed that as a final
		# corkscrew/pop.
		var weapon_k := 1.0 - exp(-15.0 * delta)
		var weapon_frame := target if reloading \
				or (_rifle_aim > 0.82 and _preview_slot < 0) \
				else _active_item.global_transform.interpolate_with(target, weapon_k)
		_active_item.global_transform = weapon_frame
		var primary_grip := rifle.call("primary_grip_node") as Node3D
		var support_grip := rifle.call("support_grip_node") as Node3D
		var primary_target := weapon_frame * primary_grip.transform
		var support_target := weapon_frame * support_grip.transform
		if not reloading:
			_configure_normal_rifle_hand(rifle, primary_grip)
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
	if active_item_kind() != "hunting_rifle":
		_active_item.global_transform = _active_item.global_transform.interpolate_with(target, k)
	_active_item.reset_physics_interpolation()


func _configure_normal_rifle_hand(rifle: Node3D, primary_grip: Node3D) -> void:
	_rifle_primary_target.remove_meta("held_device_target")
	_rifle_primary_target.set_meta("held_device", rifle)
	_rifle_primary_target.set_meta("held_grip_transform", primary_grip.transform)
	_rifle_primary_target.set_meta("contact_bounds",
			rifle.call("primary_contact_bounds") as AABB)
	_rifle_primary_target.set_meta("hand_pose", "rifle_primary")
	_rifle_primary_target.set_meta("hand_attachment", false)
	_rifle_primary_target.set_meta("natural_grip_blend", 0.0)
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
	var pose := "pinch"
	var natural_grip_blend := _reload_segment(t, 0.0, 0.16)
	var carrying_round := t >= RELOAD_CARTRIDGE_SHOW and t < RELOAD_INSERTED
	if t < RELOAD_CARTRIDGE_SHOW:
		# Position leaves the trigger grip; hands.gd supplies the neutral wrist
		# frame. No hand-authored Euler rotation participates in this reach.
		hand_frame = Transform3D(primary_frame.basis,
				primary_frame.origin.lerp(pocket_palm_position,
				_reload_segment(t, 0.0, RELOAD_CARTRIDGE_SHOW)))
	elif t < 0.48:
		desired_round = pocket_round
		hand_frame = Transform3D(chamber.basis,
				desired_round * round_palm_local)
	elif t < 1.08:
		desired_round = Transform3D(chamber.basis,
				pocket_round.origin.lerp(chamber_entry.origin,
				_reload_segment(t, 0.48, 1.08)))
		hand_frame = Transform3D(chamber.basis,
				desired_round * round_palm_local)
	elif t < RELOAD_INSERTED:
		desired_round = Transform3D(chamber.basis,
				chamber_entry.origin.lerp(chamber.origin,
				_reload_segment(t, 1.08, RELOAD_INSERTED)))
		hand_frame = Transform3D(chamber.basis,
				desired_round * round_palm_local)
	elif t < RELOAD_BOLT_START:
		var approach_blend := _reload_segment(t,
				RELOAD_INSERTED, RELOAD_BOLT_START)
		# Position travels to the knob while the authored endpoint stays the
		# chamber frame. hands.gd performs the one and only chamber->natural wrist
		# blend; interpolating this basis too caused a hidden second rotation.
		var inserted_palm := chamber * round_palm_local
		hand_frame = Transform3D(chamber.basis,
				inserted_palm.lerp(bolt.origin, approach_blend))
		pose = "bolt_grip"
	elif t < RELOAD_BOLT_END:
		pose = "bolt_grip"
		hand_frame = bolt
	else:
		pose = "rifle_primary"
		var return_blend := _reload_segment(t, RELOAD_BOLT_END, RELOAD_DURATION)
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
	elif t >= RELOAD_INSERTED and t < RELOAD_BOLT_END:
		_rifle_primary_target.remove_meta("held_device_target")
		_rifle_primary_target.set_meta("held_device", rifle)
		_rifle_primary_target.set_meta("held_grip_transform", Transform3D.IDENTITY)
		_rifle_primary_target.set_meta("contact_bounds",
				rifle.call("bolt_contact_bounds") as AABB)
	elif t >= RELOAD_BOLT_END:
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
	if index == 2:
		# Blade down, grip up, flush with the same two leather retaining loops.
		basis = Basis(Vector3.BACK, deg_to_rad(-90.0))
		origin.y += 0.055
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
		anchor.transform = _slot_transform(index)
		add_child(anchor)
		_slot_anchors.append(anchor)
		var item: Node3D
		if index == 2:
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
		for y in [-0.105, 0.015]:
			_box(Vector3(0.060, 0.018, 0.016), Vector3(x, y, tool_z + 0.020),
					Vector3.ZERO, leather, "ToolLoop")

	# Dedicated long-gun cradle below the ordinary inventory. These two broad
	# leather loops visibly carry the rifle and are not addressable by tools.
	for x in [-0.285, 0.285]:
		_box(Vector3(0.055, 0.090, 0.022), Vector3(x, -0.103, 0.262),
				Vector3.ZERO, leather, "RifleSling")
		_cylinder(0.009, 0.060, Vector3(x, -0.060, 0.261),
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
