extends Node3D
## Drives the hands from what the player is holding. Drop-in for the interface
## boat_camera.gd already calls (setup / set_active / notify_use / inspecting_id
## / update / boat).
##
## Each hand is a separate claim — left on the wheel while the right works the
## telegraph is the whole point. A claim resolves to a grip node PARENTED to the
## device, whose basis IS the grip semantics: origin = palm contact, +Z = finger
## direction, +Y = palm normal. When the device moves, its grip moves, and the
## hand is welded to it by parentage rather than by two animations agreeing.
##
## Hands do not invent a hold. `GripMap` is the object's contract: where the
## palm lands, how long the gesture lasts. Which ARM goes is not in the
## catalog — `_pick_hand` takes the lower-cost legal path without folding its
## wrist. `preferred` is only a small tie-breaker; anatomy remains authoritative.
## Helm rim, face, watch, ladder stay special — they are not objects.

const RIG := preload("res://scripts/hands/hand_rig.gd")
const GRASP_PLANNER := preload("res://scripts/hands/grasp_planner.gd")
const INTERACTION_MOTION := preload("res://scripts/hands/interaction_motion.gd")
const GESTURE_STATE := preload("res://scripts/hands/hand_gesture.gd")
const HELM_DRIVER := preload("res://scripts/hands/helm_hand_driver.gd")
const LADDER_DRIVER := preload("res://scripts/hands/ladder_hand_driver.gd")
const WATCH_DRIVER := preload("res://scripts/hands/watch_hand_driver.gd")
const FACE_DRIVER := preload("res://scripts/hands/face_hand_driver.gd")
const SWIM_DRIVER := preload("res://scripts/hands/swim_hand_driver.gd")
const INTERACTION_BEHAVIOR := preload("res://scripts/hands/interaction_behavior.gd")
const HELD_OBJECT_FRAMER := preload("res://scripts/hands/held_object_framer.gd")

## Fired at the exact contact phase of a hand-authored interaction.  The camera
## owns gameplay intent; the hand owns when flesh actually reaches the control.
## Keeping that boundary explicit prevents doors, keys and switches moving a
## quarter-second before the fingers arrive.
signal action_contact(id: String)

## Extra upper-body travel allowed only after the player has a fitting under
## the crosshair and presses use. This bridges the old prompt distance and the
## anatomical solver without granting two-metre ghost arms.
const MAX_REACH_ASSIST := 0.38

var boat: Node3D
var rig: Node3D
var _helm_driver := HELM_DRIVER.new()
var _ladder_driver := LADDER_DRIVER.new()
var _full_body_override_active := false
var _watch_driver := WATCH_DRIVER.new()
var _face_driver := FACE_DRIVER.new()
var _swim_driver := SWIM_DRIVER.new()

var _cam: Camera3D
var _active := false
var _claim := {"L": "", "R": ""}
var _grips := {}
var _inspect := ""
## Per-hand interaction phase.  A gesture moves through approach -> contact ->
## actuation -> release, and emits action_contact exactly once at contact.
## Dictionary fields: id, t, duration, contact_at, fired, hold_after,
## release_after, approach.
var _gesture: Dictionary = {"L": null, "R": null}
## Withdrawal. When a claim ends the hand does not vanish and does not stay
## planted — it travels back out of frame from wherever it was, over about a
## third of a second. Without this the hand simply held its last pose in the
## middle of the view, which reads as an arm stuck to the door it just opened.
var _rest_t := {"L": 1.0, "R": 1.0}
var _last_grip := {"L": Vector3.ZERO, "R": Vector3.ZERO}
## Semantic K/P/F continuity at release. Position-only withdrawal made a hand
## leave the rifle smoothly while its wrist snapped straight to the idle basis.
var _last_axes := {"L": {}, "R": {}}
var _last_pose := {"L": "open", "R": "open"}
## The chosen side is sticky per fitting. A competing arm must beat it by a
## meaningful quality margin, not by one noisy millimetre on a rolling boat.
var _selection_side := {}
var _grasp_quality := {}
var _multi_required := {}
var _multi_contact := {}
var _held_blend_time := {}
## A carried prop cannot remain in a physics-interpolated RigidBody hierarchy:
## its logical transform is correct, but the renderer applies the parent's
## previous/current physics blend once more and it swims through the palm.
## Preserve its scene ownership and temporarily reparent it under the exact
## camera/body node which also owns the rendered arms.
var _held_space_state := {}
## Local-space visual hulls for persistent held objects. They are measured from
## the live meshes once, so a future weapon/tool cannot escape the camera just
## because its origin happens to be on screen.
var _held_point_cache := {}
## Both hands on the boarding ladder. Not a claim like the others: there is no
## device node to parent a grip to, the rungs are boat.gd constants, and BOTH
## hands are on it at once and alternate — which is the only thing that makes a
## climb read as a climb rather than a lift.
## Gestures at your own face rather than at the ship: pulling a mask on, and
## wiping the inside of its glass. They have no device to hang a grip on — the
## thing they touch is you — so they are driven straight in camera space.
## The dive watch. B held raises the left arm to read it — a HELD gesture, not
## a one-shot: the arm stays up exactly as long as the button does, which is
## how looking at a watch actually works. It outranks every left-hand claim
## (the wheel gets the hand back the moment B lifts) and it works in the water,
## where the depth row is the whole point of owning the thing.
## Where the wiping finger is, in the mask shader's own screen space, and which
## way it is travelling. The glass has to clear UNDER THE HAND — read off a
## timer instead and the fog cleared left-to-right while the hand went
## right-to-left, which is worse than not animating it at all.
var _dbg := 0
## Walk cycle for the idle hang. `walking` arrives from the camera; we keep
## our own phase so the two arms stay opposite and start/stop without a snap.
var _stride := 0.0
var _gait := 0.0
## The bag's right hand is a continuous body gesture, not a ship fitting: it
## either points at a physical slot or grips the item that has left that slot.
var _bag_hand_target: Node3D
var _bag_hand_mode := ""
var _bag_hand_report := {}
var _rifle_support_target: Node3D


func debug_frames(n: int) -> void:
	_dbg = n


func setup(cam: Camera3D) -> void:
	_cam = cam
	rig = RIG.new()
	add_child(rig)
	rig.setup(cam)
	_helm_driver.setup(rig)
	rig.set_visible_hands(false)


func set_active(on: bool) -> void:
	_active = on and rig != null and rig.is_ready()
	if rig != null:
		rig.set_visible_hands(_active)
	if _cam != null:
		# The palms work centimetres from the lens; the default near plane cuts
		# them open.
		_cam.near = 0.05 if _active else 0.10
	if not _active:
		_bag_hand_target = null
		_bag_hand_mode = ""
		_rifle_support_target = null
		_restore_held_render_space("bag_rifle")
		_watch_driver.force_lower()
		for side: String in ["L", "R"]:
			_unlock_held(str(_claim.get(side, "")))
		if boat != null:
			# Leaving first person parks whatever the powered rails hold.
			boat.call("set_radar_pull", 0.0)
			boat.call("set_sounder_pull", 0.0)
		_claim = {"L": "", "R": ""}
		_gesture = {"L": null, "R": null}
		_inspect = ""


func inspecting_id() -> String:
	return _inspect


func view_pitch_guard_active() -> bool:
	## The arm meshes end inside the torso.  While a hand is planted on a real
	## object the player may turn their head, but looking below the shoulder line
	## exposes those deliberately hidden mesh ends.  Camera code uses this single
	## semantic answer for controls, carried tools and the boarding ladder.
	if _ladder_driver.is_active():
		return true
	if _bag_hand_target != null or _rifle_support_target != null:
		return true
	for side: String in ["L", "R"]:
		if str(_claim.get(side, "")) != "":
			return true
	return false


func body_lean_local() -> Vector3:
	## Camera-local upper-body contribution for boat_camera.gd. The arm rig still
	## solves the exact palm contact; this moves the eye/shoulders with it so a
	## long reach reads as bending at the waist instead of telescoping arms.
	if rig == null or not rig.is_ready():
		return Vector3.ZERO
	var phase := 0.0
	for side: String in ["L", "R"]:
		var gs: HandGesture = _gesture.get(side)
		if gs == null:
			continue
		var u := clampf(gs.phase(), 0.0, 1.0)
		var contact := gs.contact_at
		var side_phase := 1.0
		if u > contact:
			side_phase = 1.0 - smoothstep(contact, 0.88, u)
		phase = maxf(phase, side_phase)
	if phase <= 0.0:
		return Vector3.ZERO
	# The rest remains in the shoulders/waist model. Capping the eye travel
	# prevents a far fitting from pulling the camera through its own bulkhead.
	var body_commit := 0.0
	for side: String in ["L", "R"]:
		var held_id := str(_claim.get(side, ""))
		if held_id != "":
			var profile := INTERACTION_BEHAVIOR.profile(GripMap.spec_for(held_id))
			body_commit = maxf(body_commit, float(profile.get("body_commit", 0.0)))
	return (rig.lean() * ((0.56 + body_commit * 0.18) * phase)).limit_length(0.30)


func grasp_quality(id: String) -> Dictionary:
	## Runtime audit surface for tests/debug UI: planner score plus the live
	## per-phalanx contact result for whichever hand currently owns the object.
	var report: Dictionary = (_grasp_quality.get(id, {}) as Dictionary).duplicate(true)
	var side := _owner_of(id)
	if side != "":
		report["finger_contact"] = rig.finger_contact_report(side)
	return report


func held_frame_report(id: String) -> Dictionary:
	## Debug/test surface expressed in normalized camera space. `visible` means
	## the complete object hull and palm allowance fit inside its authored frame.
	var spec := GripMap.spec_for(id)
	var frame: Dictionary = spec.get("held_frame", {})
	var device := _device_of(id)
	if frame.is_empty() or device == null or _cam == null:
		return {}
	var view_size := _cam.get_viewport().get_visible_rect().size
	var aspect := view_size.x / maxf(view_size.y, 1.0)
	var local_xf := _cam.global_transform.affine_inverse() * device.global_transform
	return HELD_OBJECT_FRAMER.report(local_xf, frame, _cam.fov, aspect,
			_held_visual_points(id, device, frame))


func notify_use(id: String, allow_reach_assist := false) -> bool:
	## Helm / telegraph / chart are modes owned by boat.gd — the engaged state
	## drives those claims in update(). Everything else is a GripMap spec.
	var spec: Dictionary = GripMap.spec_for(id)
	if spec.is_empty():
		return false
	var contract_error := GripMap.validation_error(spec)
	if contract_error != "" or not rig.has_pose(str(spec.get("pose", ""))):
		push_warning("hands: invalid grip '%s': %s" % [id,
				contract_error if contract_error != "" else "unknown finger profile"])
		return false
	if _device_of(id) == null:
		push_warning("hands: grip '%s' has no live device" % id)
		return false
	var gate: String = str(spec.get("gate", ""))
	if gate != "" and not bool(boat.call("switch_state", gate)):
		return false
	var active_owner := _owner_of(id)
	if active_owner != "" and _gesture_is(active_owner, id):
		return false # debounce E while approach/contact is already in flight
	if bool(spec.get("drops_instruments", false)):
		_drop_instruments()
	return _begin(id, spec, allow_reach_assist)


func can_offer(id: String) -> bool:
	## The reticle and the hand share one admission rule. If this returns true,
	## pressing use will not be silently rejected for distance a moment later.
	var spec: Dictionary = GripMap.spec_for(id)
	if spec.is_empty() or rig == null or not rig.is_ready():
		return false
	# Full-body specials (boarding ladder, worn gear) deliberately have no held
	# device node. Their own driver owns reach and motion after the world-space
	# catalog has already selected them.
	if int(spec.get("kind", GripMap.Kind.GESTURE)) == GripMap.Kind.SPECIAL:
		return true
	if _device_of(id) == null:
		return false
	var gate: String = str(spec.get("gate", ""))
	if gate != "" and not bool(boat.call("switch_state", gate)):
		return false
	return _pick_hand(id, str(spec.get("preferred", "")), MAX_REACH_ASSIST) != ""


func set_body_hold(id: String, on: bool, side := "L") -> bool:
	## Body-worn gear does not begin at a world fitting under the crosshair. The
	## shoulder motion places the object; this claims the hand that bears its
	## weight and lets the ordinary grip solver follow the real handle.
	if not on:
		var owner := _owner_of(id)
		if owner != "":
			_release(owner)
		return true
	if _device_of(id) == null or GripMap.spec_for(id).is_empty():
		return false
	if _owner_of(id) == side:
		return true
	if _claim.get(side, "") != "":
		_release(side)
	_take(side, id)
	return true


func set_bag_hand(target: Node3D, mode := "") -> void:
	## Camera supplies the real slot/item node after the bag has been posed. A
	## stale world-space point would visibly swim when the vessel rolls.
	if target == null or mode != "knife":
		_restore_held_render_space("bag_knife")
	if mode != "rifle":
		_clear_rifle_hands()
	_bag_hand_target = target
	_bag_hand_mode = mode if target != null else ""
	if target != null and mode == "knife":
		var knife_device := target.get_meta("held_device", null) as Node3D
		if knife_device != null:
			_enter_held_render_space("bag_knife", "R", knife_device)
	if target == null:
		_bag_hand_report = {}
		if rig != null:
			rig.clear_held_attachment("R")
			rig.set_contact_target("R", null)
	if target != null and _claim.get("R", "") != "":
		_release("R")


func set_rifle_hands(primary: Node3D, support: Node3D) -> void:
	if primary == null:
		_clear_rifle_hands()
		return
	_restore_held_render_space("bag_knife")
	_bag_hand_target = primary
	_bag_hand_mode = "rifle"
	var released_support := _rifle_support_target != null and support == null
	_rifle_support_target = support
	# A long gun is not a knife/viewmodel welded to one wrist. The weapon owns
	# its shoulder/ADS transform; both arms independently solve to its stock.
	# Reparenting it to the trigger wrist lets every IK correction rotate the
	# sights, exactly the instability the player reported.
	_restore_held_render_space("bag_rifle")
	if rig != null:
		rig.clear_held_attachment("R")
		if released_support and _claim.get("L", "") == "":
			rig.set_contact_frozen("L", false)
			rig.set_grip_locked("L", false)
			rig.set_reach_bias("L", 0.0)
			rig.set_contact_target("L", null)
	if _claim.get("R", "") != "":
		_release("R")


func _clear_rifle_hands() -> void:
	if _bag_hand_mode != "rifle" and _rifle_support_target == null:
		return
	_restore_held_render_space("bag_rifle")
	_rifle_support_target = null
	if _bag_hand_mode == "rifle":
		_bag_hand_target = null
		_bag_hand_mode = ""
	if rig != null:
		rig.clear_held_attachment("R")
		rig.set_contact_frozen("R", false)
		rig.set_contact_frozen("L", false)
		rig.set_grip_locked("R", false)
		rig.set_grip_locked("L", false)
		rig.set_reach_bias("R", 0.0)
		rig.set_reach_bias("L", 0.0)
		if _claim.get("R", "") == "":
			rig.set_contact_target("R", null)
		if _claim.get("L", "") == "":
			rig.set_contact_target("L", null)


func plan_world_grasp(contact: Vector3, fingers := Vector3.ZERO,
		palm := Vector3.ZERO, approach := 0.08, preferred := "",
		assist_cap := 0.0) -> Dictionary:
	## Public geometry-only entry for future interactables. A caller supplies a
	## world contact frame (or zero axes for an inferred natural hold); the same
	## bilateral path/anatomy planner used by ship fittings chooses the arm.
	if rig == null or not rig.is_ready():
		return {}
	var candidates := {}
	for side: String in ["L", "R"]:
		var natural_frame := fingers.length_squared() < 0.25 \
				or palm.length_squared() < 0.25
		candidates[side] = GRASP_PLANNER.sample_candidate(rig, side, contact,
				fingers, palm, approach, assist_cap, natural_frame, true,
				0.15 if _claim.get(side, "") in ["helm", "telegraph"] else 0.0)
	return GRASP_PLANNER.choose(candidates, rig.WRIST_CONE,
			{"L": _locked("L"), "R": _locked("R")}, preferred)


func set_watch(held: bool, tod: float, depth: float) -> void:
	if _watch_driver.set_state(held, tod, depth) and _claim["L"] != "":
		# Rising edge: whatever the left hand held, it lets go of first.
		_release("L")


func _watch_up() -> bool:
	return _watch_driver.is_up()


func face_gesture(kind: String) -> void:
	_face_driver.start(kind)


func wipe_front() -> Vector2:
	## (x, direction) of the finger on the glass. x is in the same units the
	## mask shader uses: screen, centred, aspect-corrected.
	return _face_driver.wipe_front()


func set_sea_ladder(on: bool, feet_y: float, mantle := 0.0) -> void:
	_ladder_driver.set_state(on, feet_y, mantle)


func _enter_full_body_override() -> void:
	## Ladder/swim drivers own both arms. Leave no stale gesture, rail ownership,
	## contact freeze or rifle grip lock behind for the next cabin interaction.
	for side: String in ["L", "R"]:
		var old_id := str(_claim.get(side, ""))
		if old_id != "":
			_unlock_held(old_id)
		_claim[side] = ""
		_gesture[side] = null
		rig.clear_held_attachment(side)
		rig.set_contact_frozen(side, false)
		rig.set_grip_locked(side, false)
		rig.set_reach_bias(side, 0.0)
		rig.set_reach_assist(side, 0.0)
		rig.set_contact_target(side, null)
		rig.release(side)
	_multi_required.clear()
	_multi_contact.clear()
	_inspect = ""


func update(delta: float, p_boat: Node3D, engaged: String, walking: float,
		swimming: bool) -> void:
	boat = p_boat
	if rig == null or not rig.is_ready():
		return
	_watch_driver.update(delta, _active, rig)
	if _face_driver.is_active() and _active:
		# Ahead of everything, including the swimming test: wiping the glass is
		# a thing you do precisely when you are in the water.
		rig.set_visible_hands(true)
		rig.set_contact_target("L", null)
		rig.set_contact_target("R", null)
		var face_result: Dictionary = _face_driver.drive(delta, _cam, rig)
		for side: String in face_result.get("contacts", {}):
			_last_grip[side] = face_result["contacts"][side]
			_rest_t[side] = 0.0
		if bool(face_result.get("rest_left", false)):
			_rest_hand("L")
		if bool(face_result.get("done", false)):
			_rest_t["L"] = 0.0
			_rest_t["R"] = 0.0
		_finish(delta)
		return
	var full_body_override := (_ladder_driver.is_active() or swimming) and _active
	if full_body_override and not _full_body_override_active:
		_enter_full_body_override()
	_full_body_override_active = full_body_override
	if _ladder_driver.is_active() and _active and boat != null:
		rig.set_visible_hands(true)
		rig.set_contact_target("L", null)
		rig.set_contact_target("R", null)
		_inspect = ""
		for side: String in ["L", "R"]:
			_last_grip[side] = _ladder_driver.drive(side, delta, boat, rig)
			_rest_t[side] = 0.0
		_finish(delta)
		return
	if swimming and _active:
		rig.set_visible_hands(true)
		rig.set_contact_target("L", null)
		rig.set_contact_target("R", null)
		_inspect = ""
		_swim_driver.advance(delta)
		if _watch_up():
			rig.set_contact_target("L", null)
			_last_grip["L"] = _watch_driver.drive(_cam, rig)
			_rest_t["L"] = 0.0
		else:
			_last_grip["L"] = _swim_driver.drive("L", _cam, rig)
			_rest_t["L"] = 0.0
		_last_grip["R"] = _swim_driver.drive("R", _cam, rig)
		_rest_t["R"] = 0.0
		_finish(delta)
		return
	if not _active or boat == null:
		rig.release("L")
		rig.release("R")
		rig.set_visible_hands(false)
		_finish(delta)
		return
	rig.set_visible_hands(true)
	# Want the stride even when the walker is sliding on a wet deck and
	# `walking` (speed/3) stays small — WASD is the truth of the step.
	var stick := Input.get_vector("boat_left", "boat_right",
			"boat_backward", "boat_forward").length()
	var want: float = maxf(clampf(walking, 0.0, 1.0), clampf(stick, 0.0, 1.0))
	_stride = lerpf(_stride, want, 1.0 - exp(-10.0 * delta))
	if _stride > 0.02:
		_gait += delta * lerpf(2.8, 6.4, _stride)
	if _dbg > 0:
		_dbg -= 1
		print("[hands] engaged=%s claim=%s" % [engaged, _claim])
		for dbg_pair in [["L", "helm"], ["R", "telegraph"]]:
			var dbg_ev: Dictionary = _grip_evaluation(dbg_pair[0], dbg_pair[1])
			print("  %s/%s reach=%s left=%.3f elbow=%.1f cost=%.1f raise=%.2f wrist=%.1f twist=%.1f" % [
				dbg_pair[0], dbg_pair[1], dbg_ev.get("reachable", false),
				float(dbg_ev.get("leftover", -1.0)),
				rad_to_deg(float(dbg_ev.get("elbow_angle", 0.0))),
				rad_to_deg(float(dbg_ev.get("elbow_cost", 0.0))),
				float(dbg_ev.get("shoulder_raise", 0.0)),
				rad_to_deg(float(dbg_ev.get("wrist_break", 0.0))),
				rad_to_deg(float(dbg_ev.get("palm_twist", 0.0)))])

	_tick_gestures(delta)

	# Radio state belongs to boat.gd; mirror it.
	if _on(boat, "radio_held"):
		if _owner_of("radio") == "":
			# Passive state synchronisation (load/probe/script), not a new button
			# press: take the authored hold without firing the toggle action again.
			var rs := _pick_hand("radio", "")
			if rs != "" and _can_take(rs, "radio"):
				_take(rs, "radio")
	else:
		var radio_side := _owner_of("radio")
		if radio_side != "" and not _gesture_is(radio_side, "radio"):
			_release(radio_side)

	# At the wheel both hands work: left steers, right rests on the telegraph.
	if engaged == "helm":
		if _claim["L"] == "" and not _watch_up():
			if _can_take("L", "helm"):
				_take("L", "helm")
		if _claim["R"] == "" and _inspect == "" and _bag_hand_target == null:
			# This is the authored helm station: its standing point and lever were
			# measured as one combined two-control posture.  Do not make the returning
			# right hand pass the generic free-standing interaction gate every frame;
			# small boat motion/IK settling could reject it and leave the hand floating.
			# Hard-held items still block this branch through `_bag_hand_target` above.
			_take("R", "telegraph")
	elif engaged == "telegraph":
		if _claim["R"] == "" and _bag_hand_target == null:
			if _can_take("R", "telegraph"):
				_take("R", "telegraph")
	else:
		if _claim["L"] == "helm":
			_release("L")
		if _claim["R"] == "telegraph":
			_release("R")

	for side: String in _claim:
		if _claim[side] == "":
			_rest_t[side] = minf(_rest_t[side] + delta, 1.0)
		if side == "L" and _watch_up():
			rig.set_contact_target("L", null)
			_last_grip["L"] = _watch_driver.drive(_cam, rig)
			_rest_t["L"] = 0.0
		elif side == "L" and _rifle_support_target != null:
			_drive_rifle_support()
		elif side == "R" and _bag_hand_target != null:
			_drive_bag_hand(delta)
		else:
			_drive(side, delta)
	_finish(delta)


func _finish(delta: float) -> void:
	if rig.has_method("set_watch_read"):
		rig.set_watch_read(_watch_driver.amount())
	rig.update(delta)


# --- claims ------------------------------------------------------------------

func _take(side: String, id: String) -> void:
	_claim[side] = id
	_gesture[side] = null
	_helm_driver.reset(side)
	if id == "helm":
		_helm_driver.seat(side, boat, _device_of("helm"), _grip_node("helm", side))


func _release(side: String) -> void:
	var old_id := str(_claim.get(side, ""))
	_claim[side] = ""
	_gesture[side] = null
	if _owner_of(old_id) == "":
		_unlock_held(old_id)
	rig.set_reach_assist(side, 0.0)
	rig.release(side)


func _owner_of(id: String) -> String:
	for s: String in ["L", "R"]:
		if _claim[s] == id:
			return s
	return ""


func _drop_instruments() -> void:
	for s: String in ["L", "R"]:
		if _claim[s] in ["radar", "sounder"]:
			_release(s)


## Soft claims (helm, telegraph) can be stolen for a gesture and come back
## on their own. Hard ones (radio, a held watch) cannot — the other hand goes.
func _locked(side: String) -> bool:
	if side == "L" and _watch_up():
		return true
	if side == "L" and _rifle_support_target != null:
		return true
	if side == "R" and _bag_hand_target != null:
		return true
	var id: String = _claim[side]
	return id in ["radio", "deckbag"]


func _begin(id: String, spec: Dictionary = {}, allow_reach_assist := false) -> bool:
	if spec.is_empty():
		spec = GripMap.spec_for(id)
	if spec.is_empty() or rig == null or not rig.is_ready():
		return false
	var behavior := INTERACTION_BEHAVIOR.profile(spec)
	if int(behavior.get("min_hands", 1)) >= 2:
		return _begin_two_hand(id, spec, allow_reach_assist)
	# A toggle hold (currently the handset) is returned by touching the object
	# that is already in the hand.  Keep the claim until the return gesture has
	# reached contact; otherwise it teleports to its cradle before the fingers
	# have let it go.
	var owner := _owner_of(id)
	if bool(spec.get("toggle", false)) and owner != "":
		_start_gesture(owner, id, spec, true)
		return true
	var assist_cap := MAX_REACH_ASSIST if allow_reach_assist else 0.0
	var side := _pick_hand(id, str(spec.get("preferred", "")), assist_cap)
	if side == "":
		return false
	var before: Dictionary = _grip_evaluation(side, id)
	var assist := minf(maxf(float(before.get("leftover", 0.0)) + 0.025, 0.0),
			assist_cap)
	rig.set_reach_assist(side, assist)
	# No interaction is allowed to fire merely because an IK target exists.  It
	# must be reachable with this authored palm/finger frame and remain inside a
	# generous anatomical wrist/forearm envelope.  If neither hand can do that,
	# doing nothing is more truthful than showing a broken arm.
	if not _can_take(side, id):
		rig.set_reach_assist(side, 0.0)
		return false
	_take(side, id)
	if float(spec.get("gesture", 0.0)) > 0.0:
		_start_gesture(side, id, spec, false)
	return true


func _begin_two_hand(id: String, spec: Dictionary,
		allow_reach_assist: bool) -> bool:
	## Heavy runtime interactables reserve both arms and commit only after both
	## palms have independently passed the same anatomical/path checks.
	if _locked("L") or _locked("R"):
		return false
	var assist_cap := MAX_REACH_ASSIST if allow_reach_assist else 0.0
	var candidates := {
		"L": _planned_candidate("L", id, assist_cap, 2),
		"R": _planned_candidate("R", id, assist_cap, 2),
	}
	for side: String in ["L", "R"]:
		if not GRASP_PLANNER.candidate_ok(candidates[side], rig.WRIST_CONE):
			return false
	for side: String in ["L", "R"]:
		var needed := float((candidates[side] as Dictionary).get("required_assist", 0.0))
		rig.set_reach_assist(side, needed)
		_take(side, id)
		if float(spec.get("gesture", 0.0)) > 0.0:
			_start_gesture(side, id, spec, false)
	_multi_required[id] = 2
	_multi_contact[id] = {}
	return true


func _can_take(side: String, id: String, allow_owned := false) -> bool:
	if _locked(side) and not (allow_owned and _claim.get(side, "") == id):
		return false
	var ev: Dictionary = _grip_evaluation(side, id)
	return _admissible(ev)


func _admissible(ev: Dictionary, reach_slack := 0.0) -> bool:
	if reach_slack > 0.0:
		var relaxed := ev.duplicate()
		relaxed["leftover"] = maxf(float(ev.get("leftover", INF)) - reach_slack, 0.0)
		return GRASP_PLANNER.admissible(relaxed, rig.WRIST_CONE)
	return GRASP_PLANNER.admissible(ev, rig.WRIST_CONE)


func _start_gesture(side: String, id: String, spec: Dictionary,
		release_after: bool) -> void:
	var device := _device_of(id)
	_gesture[side] = GESTURE_STATE.new(id, spec, release_after,
			INTERACTION_MOTION.snapshot(device))


func _motion_progress(gs: HandGesture) -> float:
	var device := _device_of(gs.id)
	return INTERACTION_MOTION.progress(gs.follow_motion, gs.motion_start, device)


func _tick_gestures(delta: float) -> void:
	for side: String in ["L", "R"]:
		var gs: HandGesture = _gesture[side]
		if gs == null:
			continue
		gs.t += delta
		var u := gs.phase()
		if not gs.fired and u >= gs.contact_at:
			# The player or the fitting may have moved during approach.  Re-solve
			# at the instant of contact; an out-of-reach ghost hand never gets to
			# operate gameplay merely because it started close enough.
			if not _can_take(side, gs.id, true):
				var keep_existing := gs.hold_after \
						and _on(boat, "radio_held")
				_gesture[side] = null
				if not keep_existing:
					_release(side)
				continue
			gs.fired = true
			var required := int(_multi_required.get(gs.id, 1))
			if required > 1:
				var contacts: Dictionary = _multi_contact.get(gs.id, {})
				contacts[side] = true
				_multi_contact[gs.id] = contacts
				if contacts.size() >= required:
					action_contact.emit(gs.id)
			else:
				action_contact.emit(gs.id)
			# The callback is synchronous and may deliberately release this hand.
			if _gesture[side] == null:
				continue
		# Hinged parts can run away from the body after contact (a powered hatch
		# is the obvious case). Follow their real arc only while the new contact
		# remains anatomically legal; then let the fingers peel off instead of
		# letting parentage drag the wrist past arm length.
		if gs.fired and not gs.hold_after:
			var after_contact := gs.after_contact()
			var follow := gs.follow_motion
			if not follow.is_empty():
				if INTERACTION_MOTION.should_release(follow, after_contact,
						_motion_progress(gs)):
					_gesture[side] = null
					_release(side)
					continue
			var contact_ok := _can_take(side, gs.id, true)
			var tracks_ok := true
			if u > gs.contact_at + 0.05:
				var live_grip := _grip_node(gs.id, side)
				if live_grip != null:
					var wrist: Transform3D = rig.wrist_global(side)
					# About 8 cm is the measured palm-to-wrist offset. Eighteen
					# allows follow-through, but not a visibly detached hand.
					tracks_ok = wrist.origin.distance_to(live_grip.global_position) < 0.18
			if not contact_ok or not tracks_ok:
				_gesture[side] = null
				_release(side)
				continue
		if u >= 1.0:
			var keep := gs.hold_after and not gs.release_after
			_gesture[side] = null
			if keep:
				# The handset is now at the ear; the pickup lean belongs to the
				# approach, not to the whole time it remains in the hand.
				rig.set_reach_assist(side, 0.0)
			else:
				_release(side)
			if _owner_of(gs.id) == "":
				_multi_required.erase(gs.id)
				_multi_contact.erase(gs.id)


func _gesture_is(side: String, id: String) -> bool:
	var gs: HandGesture = _gesture.get(side)
	return gs != null and gs.id == id


func _grip_evaluation(side: String, id: String) -> Dictionary:
	# The helm's actual contact is on the selected rim sector, not at the hub.
	# Evaluating the hub could approve a stance whose nearest valid rim point is
	# another 29 cm away — precisely the sort of technically-reachable lie this
	# system is meant to reject.
	if id == "helm":
		var wheel := _device_of("helm")
		var cand: Dictionary = _helm_driver.candidate(side,
				_helm_driver.pick_angle(side, boat, wheel), boat, wheel)
		return cand.get("evaluation", {})
	var spec: Dictionary = GripMap.spec_for(id)
	var contact: Vector3 = _side_contact(id, side)
	var asked := _asked_axes(id, side)
	return _evaluate_grip_frame(side, id, contact, asked)


func _evaluate_grip_frame(side: String, id: String, contact: Vector3,
		asked: Dictionary) -> Dictionary:
	var spec: Dictionary = GripMap.spec_for(id)
	return GRASP_PLANNER.evaluate_frame(rig, side, contact,
			asked["fingers"], asked["palm"], false, not GripMap.welded(spec))


func _planned_candidate(side: String, id: String, assist_cap: float,
		side_count := 1) -> Dictionary:
	## Sample the actual palm path, not only its endpoint. New interactables get
	## this automatically from their contact frame and approach distance.
	var goal: Vector3 = _side_contact(id, side)
	var asked: Dictionary = _asked_axes(id, side)
	var approach := maxf(float(GripMap.spec_for(id).get("approach", 0.0)), 0.0)
	var spec: Dictionary = GripMap.spec_for(id)
	return GRASP_PLANNER.sample_candidate(rig, side, goal, asked["fingers"],
			asked["palm"], approach, assist_cap, false, not GripMap.welded(spec),
			0.15 if _claim.get(side, "") in ["helm", "telegraph"] else 0.0,
			{"boat": boat, "spec": spec, "side_count": side_count})


func _pick_hand(id: String, preferred := "", reach_slack := 0.0) -> String:
	## Preferred is only a tie-breaker. Actual side, approach path, torso cross,
	## elbow, wrist and palm decide which hand a person would really use.
	var candidates := {
		"L": _planned_candidate("L", id, reach_slack),
		"R": _planned_candidate("R", id, reach_slack),
	}
	var choice: Dictionary = GRASP_PLANNER.choose(candidates, rig.WRIST_CONE,
			{"L": _locked("L"), "R": _locked("R")}, preferred,
			str(_selection_side.get(id, "")), 0.18)
	var side := str(choice.get("side", ""))
	if side != "":
		_selection_side[id] = side
		_grasp_quality[id] = {
			"side": side,
			"score": choice.get("score", INF),
			"quality": choice.get("quality", 0.0),
			"breakdown": choice.get("quality_breakdown", {}),
			"path_blocked": choice.get("path_blocked", false),
		}
	return side


func _asked_axes(id: String, side: String) -> Dictionary:
	var spec: Dictionary = GripMap.sided(GripMap.spec_for(id), side)
	var local_contact: Vector3 = GripMap.contact_of(spec, boat, id)
	spec = GripMap.oriented_at_contact(spec, local_contact)
	var device := _device_of(id)
	var db: Basis = device.global_basis if device != null else Basis.IDENTITY
	if boat != null and not _is_camera_held(id) and not _camera_space(id):
		db = (boat as Node3D).get_global_transform_interpolated().basis \
				* boat.global_basis.inverse() * db
	return {
		"fingers": db * (spec.get("fingers", Vector3.ZERO) as Vector3),
		"palm": db * (spec.get("palm", Vector3.ZERO) as Vector3),
	}


func _side_contact(id: String, side: String) -> Vector3:
	var device := _device_of(id)
	if device == null:
		if _cam == null:
			return Vector3.ZERO
		return _cam.global_position - _cam.global_basis.z * 0.40
	var spec: Dictionary = GripMap.sided(GripMap.spec_for(id), side)
	var local_contact: Vector3 = GripMap.contact_of(spec, boat, id)
	spec = GripMap.oriented_at_contact(spec, local_contact)
	var local: Transform3D = GripMap.local_frame(spec, local_contact)
	var p: Vector3 = device.global_transform * local.origin
	if boat != null and not _is_camera_held(id) and not _camera_space(id):
		p = (boat as Node3D).get_global_transform_interpolated() \
				* (boat.global_transform.affine_inverse() * p)
	return p


func _peek_contact(id: String) -> Vector3:
	return _side_contact(id, "R")


func _drive_bag_hand(_delta: float) -> void:
	if _bag_hand_target == null or not is_instance_valid(_bag_hand_target):
		_bag_hand_target = null
		_bag_hand_mode = ""
		rig.set_contact_frozen("R", false)
		rig.set_grip_locked("R", false)
		rig.set_reach_bias("R", 0.0)
		_rest_hand("R")
		return
	var object_point := _bag_hand_target.global_position
	var contact := object_point
	var axes: Dictionary
	var pose := "power"
	var pose_amount := 1.0
	if _bag_hand_mode == "point":
		rig.set_contact_target("R", null)
		rig.clear_held_attachment("R")
		# Solve from the rig's measured index-tip offset. This accounts for both
		# finger length and the index knuckle's thumb-side position in the palm.
		# Keep the back/side of the hand readable to the player across every slot;
		# deriving roll from each target made slot 1 hide the pointing finger.
		var readable_palm: Vector3
		if bool(_bag_hand_target.get_meta("centre_point_roll", false)):
			# Point at the low, centred rifle with the palm facing down. A slight
			# camera-facing component keeps the index silhouette readable without
			# rolling the wrist sideways as the bag settles.
			readable_palm = (-_cam.global_basis.y \
					- _cam.global_basis.z * 0.12).normalized()
		else:
			readable_palm = (-_cam.global_basis.z \
					+ _cam.global_basis.x * 0.16).normalized()
		var point_frame: Dictionary = rig.point_frame(
				"R", object_point, readable_palm)
		contact = point_frame["contact"] as Vector3
		axes = {
			"fingers": point_frame["fingers"] as Vector3,
			"palm": point_frame["palm"] as Vector3,
		}
		pose = "point"
	elif _bag_hand_mode == "knife" or _bag_hand_mode == "knife_release":
		# The target is the desired PALM contact, not the prop itself. The solver
		# keeps the natural forearm direction, then pronates around it so the BACK
		# of the fist faces the player: knuckles visible, palm hidden, thumb locked
		# over the handle like a normal knife power grip.
		if bool(_bag_hand_target.get_meta("authored_grip_frame", false)):
			# During insertion the target IS the knife's semantic K/P/F frame. The
			# hand follows that exact frame, so the knife cannot rotate sideways and
			# then snap through the fist when it reaches the webbing.
			axes = {
				"fingers": _bag_hand_target.global_basis.z.normalized(),
				"palm": _bag_hand_target.global_basis.y.normalized(),
			}
		else:
			axes = rig.natural_axes("R", contact)
			var knife_fingers: Vector3 = axes["fingers"]
			# A small roll exposes the thumb-side ridge instead of presenting a flat,
			# featureless back of hand. The knife is welded to this same semantic
			# frame, so hand and blade always roll together.
			var knife_palm := (-_cam.global_basis.z \
					+ _cam.global_basis.x * 0.20).normalized()
			knife_palm -= knife_palm.project(knife_fingers)
			if knife_palm.length_squared() > 0.0001:
				axes["palm"] = knife_palm.normalized()
		pose = "knife_grip"
		pose_amount = float(_bag_hand_target.get_meta("grip_closure", 1.0))
		var held_device := _bag_hand_target.get_meta("held_device") as Node3D \
				if _bag_hand_target.has_meta("held_device") else null
		var held_grip: Transform3D = _bag_hand_target.get_meta(
				"held_grip_transform") as Transform3D \
				if _bag_hand_target.has_meta("held_grip_transform") \
				else Transform3D.IDENTITY
		if held_device != null and held_device.has_method("grip_contact_bounds"):
			rig.set_contact_target_bounds("R", held_device,
					# Use the rig's real fingertip thickness around the broad knife
					# scales. The old 6 mm shell protected only the joint endpoints,
					# allowing the rendered phalanx meshes to enter the yellow handle.
					held_device.call("grip_contact_bounds") as AABB, 0.018)
		else:
			rig.set_contact_target("R", null)
		if _bag_hand_mode == "knife" and held_device != null:
			rig.set_held_attachment("R", held_device, held_grip)
		else:
			rig.clear_held_attachment("R")
	elif _bag_hand_mode == "rifle":
		pose = str(_bag_hand_target.get_meta("hand_pose", "rifle_primary"))
		var rifle_device := _bag_hand_target.get_meta("held_device") as Node3D \
				if _bag_hand_target.has_meta("held_device") else null
		var weapon_pin_requested := bool(_bag_hand_target.get_meta(
				"weapon_space_pinned", false)) and rifle_device != null
		# Once shouldered, bypass the intermediary target node completely. The
		# semantic palm frame is reconstructed from the rifle's current transform
		# and authored grip in this very update, eliminating any one-frame camera,
		# recoil or process-order drift.
		var primary_world := _bag_hand_target.global_transform
		if weapon_pin_requested:
			var primary_local: Transform3D = _bag_hand_target.get_meta(
					"held_grip_transform", Transform3D.IDENTITY) as Transform3D
			primary_world = rifle_device.global_transform * primary_local
			contact = primary_world.origin
			axes = {
				"fingers": primary_world.basis.z.normalized(),
				"palm": primary_world.basis.y.normalized(),
			}
		else:
			axes = {
				"fingers": _bag_hand_target.global_basis.z.normalized(),
				"palm": _bag_hand_target.global_basis.y.normalized(),
			}
		# A moving bolt supplies position, never an arbitrary wrist rotation. Blend
		# toward the arm solver's shoulder/contact frame on approach, stay fully
		# anatomical while cycling, then blend back into the trigger grip. This
		# makes a 180-degree wrist roll impossible by construction.
		var natural_blend := float(_bag_hand_target.get_meta(
				"natural_grip_blend", 0.0))
		if natural_blend > 0.001:
			# First derive the outward direction at the metal, move the palm centre
			# clear of it, then solve the wrist axes at that final palm position.
			# Solving the axes before the offset introduced a small but visible bend.
			var metal_natural: Dictionary = rig.natural_axes("R", contact)
			var metal_f := metal_natural["fingers"] as Vector3
			var metal_p := metal_natural["palm"] as Vector3
			var metal_k := metal_p.cross(metal_f).normalized()
			contact -= metal_p * float(_bag_hand_target.get_meta(
					"palm_clearance", 0.0))
			contact -= metal_f * float(_bag_hand_target.get_meta(
					"control_forward_reach", 0.0))
			contact += metal_k * float(_bag_hand_target.get_meta(
					"control_index_bias", 0.0))
			var natural: Dictionary = rig.natural_axes("R", contact)
			var authored_f := axes["fingers"] as Vector3
			var authored_p := axes["palm"] as Vector3
			var natural_f := natural["fingers"] as Vector3
			var natural_p := natural["palm"] as Vector3
			# Firearm grips must keep the authored finger direction so the digits
			# continue to wrap the stock/trigger.  They may still roll the palm toward
			# the forearm, which removes the broken-looking wrist without losing contact.
			var keep_fingers := bool(_bag_hand_target.get_meta(
					"natural_grip_keep_fingers", false)) and pose == "rifle_primary"
			var blended_f := authored_f if keep_fingers else authored_f.slerp(
					natural_f, smoothstep(0.0, 1.0, natural_blend)).normalized()
			var blended_p := authored_p.slerp(natural_p,
					smoothstep(0.0, 1.0, natural_blend))
			blended_p -= blended_p.project(blended_f)
			if blended_p.length_squared() > 0.001:
				axes = {"fingers": blended_f, "palm": blended_p.normalized()}
		var primary_palm: Transform3D = rig.solved_palm_global("R")
		var primary_lock_ready: bool = bool(rig.grip_locked("R")) \
				or primary_palm.origin.distance_to(primary_world.origin) < 0.005
		rig.set_grip_locked("R", weapon_pin_requested and primary_lock_ready)
		# A properly spaced sight picture puts the stock farther from the camera.
		# Bring the shoulder girdle into that hold instead of stretching either arm.
		# The trigger palm now sits lower/rearward on the actual stock wrist. Let
		# the right shoulder follow that shouldered contact instead of leaving the
		# palm a centimetre short and visually hovering above the grip.
		rig.set_reach_bias("R", 0.115 if weapon_pin_requested else 0.0)
		if rifle_device != null and _bag_hand_target.has_meta("contact_bounds"):
			rig.set_contact_target_bounds("R", rifle_device,
					# Eight millimetres represents the compressible finger-pad shell,
					# not a gap. It lets the palm-side phalanges bear on wood without
					# requiring their bone endpoints to enter the solid stock volume.
					_bag_hand_target.get_meta("contact_bounds") as AABB, 0.008)
			if pose == "bolt_grip":
				rig.seed_contact_closure("R", 0.94)
			var primary_report: Dictionary = rig.finger_contact_report("R")
			var primary_seated := int(primary_report.get("touches", 0)) >= 6 \
					and int(primary_report.get("penetrations", 1)) == 0
			rig.set_contact_frozen("R", bool(_bag_hand_target.get_meta(
					"ads_locked", false)) and primary_seated)
			if bool(_bag_hand_target.get_meta("hand_attachment", false)):
				var reload_grip: Transform3D = _bag_hand_target.get_meta(
						"held_grip_transform", Transform3D.IDENTITY) as Transform3D
				if _bag_hand_target.has_meta("held_device_target"):
					# Small reload objects own their task-space orientation (the
					# cartridge must follow the chamber axis), while the arm solver owns
					# the wrist. Derive the device-local grip that makes both constraints
					# true instead of rotating the forearm to imitate the cartridge.
					var desired_device: Transform3D = _bag_hand_target.get_meta(
							"held_device_target") as Transform3D
					# Opposite brass surfaces at the lower case body. The thumb and
					# index solve to these two pads; no middle/ring digit participates.
					rig.set_precision_pinch("R",
							desired_device * Vector3(0.0082, 0.0, 0.031),
							desired_device * Vector3(-0.0100, 0.0, 0.031))
					var grip_f := (axes["fingers"] as Vector3).normalized()
					var grip_p := axes["palm"] as Vector3
					grip_p = (grip_p - grip_p.project(grip_f)).normalized()
					var desired_palm := Transform3D(Basis(
							grip_p.cross(grip_f).normalized(), grip_p, grip_f),
							contact)
					reload_grip = desired_device.affine_inverse() * desired_palm
					_bag_hand_target.set_meta("held_grip_transform", reload_grip)
				# During the cartridge stage only, the tiny round is seated from the
				# final solved pinch exactly like the knife. The rifle itself is never
				# wrist-owned; the left hand and camera keep control of the long gun.
				rig.set_held_attachment("R", rifle_device, reload_grip)
			else:
				rig.clear_precision_pinch("R")
				rig.clear_held_attachment("R")
		else:
			rig.clear_precision_pinch("R")
			rig.set_contact_frozen("R", false)
			rig.set_contact_target("R", null)
			rig.clear_held_attachment("R")
	else:
		# The item origin is authored at its grip zone.  A natural frame keeps the
		# wrist straight across all four different silhouettes; the power pose
		# supplies the actual cylindrical wrap.
		rig.set_contact_target("R", null)
		rig.clear_precision_pinch("R")
		rig.set_grip_locked("R", false)
		rig.clear_held_attachment("R")
		axes = rig.natural_axes("R", contact)
	_last_grip["R"] = contact
	_last_axes["R"] = axes.duplicate()
	_last_pose["R"] = pose
	_rest_t["R"] = 0.0
	if _bag_hand_mode == "rifle":
		# Keep the trigger elbow near the ribs.  The former outboard hint made the
		# forearm arrive from beyond the right edge even though the shoulder had
		# already advanced to the stock.  A slightly lower, tucked elbow leaves a
		# visible bend instead of drawing one fully stretched outside arm.
		rig.set_elbow_hint("R", 0.28, 0.12)
	_bag_hand_report = rig.consider("R", contact, axes["fingers"], axes["palm"])
	rig.grip("R", contact, axes["fingers"], axes["palm"], 1.0, pose,
			pose_amount, false)


func _drive_rifle_support() -> void:
	if _rifle_support_target == null or not is_instance_valid(_rifle_support_target):
		_rifle_support_target = null
		rig.set_contact_frozen("L", false)
		rig.set_grip_locked("L", false)
		rig.set_reach_bias("L", 0.0)
		return
	var device := _rifle_support_target.get_meta("held_device") as Node3D \
			if _rifle_support_target.has_meta("held_device") else null
	var weapon_pin_requested := bool(_rifle_support_target.get_meta(
			"weapon_space_pinned", false)) and device != null
	var support_world := _rifle_support_target.global_transform
	if weapon_pin_requested:
		var support_local: Transform3D = _rifle_support_target.get_meta(
				"held_grip_transform", Transform3D.IDENTITY) as Transform3D
		support_world = device.global_transform * support_local
	var contact := support_world.origin
	var axes := {
		"fingers": support_world.basis.z.normalized(),
		"palm": support_world.basis.y.normalized(),
	}
	var support_palm: Transform3D = rig.solved_palm_global("L")
	var support_lock_ready: bool = bool(rig.grip_locked("L")) \
			or support_palm.origin.distance_to(support_world.origin) < 0.005
	rig.set_grip_locked("L", weapon_pin_requested and support_lock_ready)
	# The centred ADS support point is slightly farther across the rifle than the
	# imported port-edge marker. Let the left shoulder follow it so the palm seats
	# under the wood instead of stopping short and appearing to slide off.
	rig.set_reach_bias("L", 0.155 if weapon_pin_requested else 0.0)
	if device != null and _rifle_support_target.has_meta("contact_bounds"):
		rig.set_contact_target_bounds("L", device,
				# A wrapped fore-end bears through finger pads, not mathematical
				# points; 12 mm matches the WRAD mesh's fleshy fingertip radius.
				_rifle_support_target.get_meta("contact_bounds") as AABB, 0.012)
		var support_report: Dictionary = rig.finger_contact_report("L")
		var support_seated := int(support_report.get("touches", 0)) >= 2 \
				and int(support_report.get("penetrations", 1)) == 0
		rig.set_contact_frozen("L", bool(_rifle_support_target.get_meta(
				"ads_locked", false)) and support_seated)
	else:
		rig.set_contact_frozen("L", false)
		rig.set_contact_target("L", null)
	rig.clear_held_attachment("L")
	_last_grip["L"] = contact
	_last_axes["L"] = axes.duplicate()
	_last_pose["L"] = "rifle_support"
	_rest_t["L"] = 0.0
	# Let the support elbow settle a little lower and farther outboard. The palm
	# remains welded beneath the fore-end, but the forearm now meets it at a small
	# anatomical wrist angle instead of forming one unnaturally straight beam.
	rig.set_elbow_hint("L", 0.32, 0.22)
	rig.grip("L", contact, axes["fingers"], axes["palm"], 1.0,
			"rifle_support", 1.0, false)


func _drive(side: String, delta: float) -> void:
	var id: String = _claim[side]
	if id == "":
		_rest_hand(side)
		return
	var held_in_view := _drive_held_object(id, side, delta)
	var g := _grip_node(id, side)
	if g == null:
		_release(side)
		return
	if held_in_view and _owner_of(id) == side:
		rig.set_held_attachment(side, _device_of(id), g.transform)
	else:
		rig.clear_held_attachment(side)
	# The bag's device bounds include the entire half-metre canvas body. Feeding
	# that to the generic finger collision solver makes it open the hand to avoid
	# the bag instead of closing round the narrow top handle. Its dedicated pose
	# is authored to that handle, so it deliberately bypasses whole-object bounds.
	rig.set_contact_target(side, null if _camera_space(id) else _device_of(id))
	var hold := 1.0
	if id == "helm":
		hold = _helm_driver.ride(side, delta, boat, _device_of("helm"), g)
		g = _grip_node(id, side)
	_rest_t[side] = 0.0
	var xf: Transform3D = g.global_transform
	# The camera rides the boat's INTERPOLATED transform (boat_camera.gd); a
	# grip read through plain global_transform rides the physics-stepped one.
	# At 120 fps over 60 Hz physics the two disagree every other frame by
	# however far the boat moved that tick — centimetres in a seaway — and the
	# hand shimmers between two positions. Remapping the grip through the same
	# interpolated frame the camera uses puts hand and eye on one timeline.
	if boat != null and not held_in_view and not _camera_space(id):
		xf = (boat as Node3D).get_global_transform_interpolated() \
				* (boat.global_transform.affine_inverse() * xf)
	# A hand starts clear of the fitting, closes as the palm arrives, makes the
	# gameplay change exactly at contact, then stays parented to the moving part.
	# Because the grip node belongs to the lever/door/handset, its real hinge or
	# rail supplies the action direction; no duplicated hand animation can drift
	# away from the object it is meant to be moving.
	if _gesture_is(side, id):
		var gs: HandGesture = _gesture[side]
		var u := clampf(gs.phase(), 0.0, 1.0)
		var contact_at := gs.contact_at
		if u < contact_at:
			var a: float = clampf(u / maxf(contact_at, 1e-4), 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)
			xf.origin -= xf.basis.y * gs.approach * (1.0 - a)
			hold *= lerpf(0.16, 1.0, a)
		elif (not gs.hold_after) or gs.release_after:
			# Keep the grasp through the object's first movement, then open before
			# withdrawal.  Releasing at the same instant as contact reads as a tap.
			var follow := gs.follow_motion
			var let_go := smoothstep(0.72, 1.0, u)
			if not follow.is_empty():
				# Peel the fingers as the fitting moves, irrespective of its speed.
				let_go = smoothstep(0.55, 1.0, _motion_progress(gs))
			hold *= lerpf(1.0, 0.14, let_go)
	# Fingers only. This block chooses a POSE and nothing else — an earlier
	# revision had the body of notify_use() pasted in here, so every frame the
	# hand held a door handle it re-took its own claim and pushed the one-shot
	# timer back to full. The timer never expired, the claim never came back,
	# and the arm stayed welded to whatever it had last touched.
	var spec: Dictionary = GripMap.spec_for(id)
	var pose := str(spec.get("pose", "wrap"))
	# The arm stays pinned (weight 1); `hold` only opens and closes the
	# fingers, which is what a re-grip looks like from inside the hand.
	_last_grip[side] = xf.origin
	var fingers: Vector3 = xf.basis.z
	var palm: Vector3 = xf.basis.y
	var welded := GripMap.welded(spec)
	# A catalog pose written for one approach will snap the other wrist.
	# If the asked fingers sit outside the forearm cone, hold it the way
	# the arm actually arrives — palm on the thing, wrist not broken.
	if not welded:
		var asked: Dictionary = _asked_axes(id, side)
		var ev: Dictionary = rig.consider(side, xf.origin,
				asked["fingers"], asked["palm"])
		if float(ev.get("wrist_break", 0.0)) > rig.WRIST_CONE * 0.85 \
				or float(ev.get("palm_twist", 0.0)) > deg_to_rad(125.0) \
				or bool(g.get_meta("natural", false)):
			fingers = ev["fingers"]
			palm = ev["palm"]
	_last_axes[side] = {"fingers": fingers, "palm": palm}
	_last_pose[side] = pose
	# The bag hangs from the hand, so its elbow stays tucked toward the ribs and
	# visibly flexed. Restore the general-purpose hint for every other fitting.
	if id == "deckbag":
		# User reference: fist high on the handle, elbow visibly broken to the
		# player's left. For side L, positive outboard moves the pole left.
		rig.set_elbow_hint(side, 0.17, 0.34)
	else:
		rig.set_elbow_hint(side, 0.32, 0.24)
	rig.grip(side, xf.origin, fingers, palm, 1.0, pose, hold, not welded)


func _drive_held_object(id: String, side: String, delta: float) -> bool:
	var spec := GripMap.spec_for(id)
	if int(spec.get("kind", GripMap.Kind.GESTURE)) != GripMap.Kind.HOLD:
		return false
	var frame: Dictionary = spec.get("held_frame", {})
	if frame.is_empty() or _cam == null:
		return false
	var active := _held_active(spec, frame)
	var lock_property := str(frame.get("lock_property", ""))
	if lock_property != "" and boat != null:
		boat.set(lock_property, active)
	if not active:
		_held_blend_time.erase(id)
		_restore_held_render_space(id)
		return false
	# A two-hand carried object has one carrier transform. The second palm reads
	# its own grip from that same transform; it must not move the prop a second
	# time using a mirrored camera anchor.
	if _owner_of(id) != side:
		return true
	var device := _device_of(id)
	if device == null:
		return false
	_enter_held_render_space(id, side, device)
	var view_size := _cam.get_viewport().get_visible_rect().size
	var aspect := view_size.x / maxf(view_size.y, 1.0)
	var points := _held_visual_points(id, device, frame)
	var target_local := HELD_OBJECT_FRAMER.solve_local(frame, side, _cam.fov,
			aspect, points)
	# Smooth relative to the eye. World-space smoothing lags behind a rolling
	# vessel and is exactly what makes a held prop wander toward a screen edge.
	var camera_inverse := _cam.global_transform.affine_inverse()
	var current_local := camera_inverse * device.global_transform
	var blend_time := float(_held_blend_time.get(id, 0.0)) + delta
	_held_blend_time[id] = blend_time
	# Ease the pickup from its world fitting, then become a true viewmodel. Once
	# settled, a fast head turn must not leave hand or muzzle behind for a frame.
	var amount := 1.0 if blend_time >= float(frame.get("settle_time", 0.48)) \
			else 1.0 - exp(-maxf(float(frame.get("smoothing", 18.0)), 1.0) * delta)
	var placed_local := current_local.interpolate_with(target_local, amount)
	device.global_transform = _cam.global_transform * placed_local
	return true


func _held_active(spec: Dictionary, frame: Dictionary) -> bool:
	var property := str(frame.get("active_property",
			spec.get("toggle_property", "")))
	return true if property == "" else _on(boat, property)


func _is_camera_held(id: String) -> bool:
	var spec := GripMap.spec_for(id)
	if int(spec.get("kind", GripMap.Kind.GESTURE)) != GripMap.Kind.HOLD:
		return false
	var frame: Dictionary = spec.get("held_frame", {})
	return not frame.is_empty() and _held_active(spec, frame)


func _camera_space(id: String) -> bool:
	return bool(GripMap.spec_for(id).get("camera_space", false))


func _unlock_held(id: String) -> void:
	if id == "":
		return
	_held_blend_time.erase(id)
	_restore_held_render_space(id)
	if boat == null:
		return
	var frame: Dictionary = GripMap.spec_for(id).get("held_frame", {})
	var lock_property := str(frame.get("lock_property", ""))
	if lock_property != "":
		boat.set(lock_property, false)


func _enter_held_render_space(id: String, side: String, device: Node3D) -> void:
	if _held_space_state.has(id):
		return
	var world := device.global_transform
	_held_space_state[id] = {
		"device": device,
		"parent": device.get_parent(),
		"index": device.get_index(),
		"top_level": device.top_level,
		"interpolation": device.physics_interpolation_mode,
	}
	var mount: Node3D = rig.held_mount(side)
	device.reparent(mount, true)
	device.top_level = false
	device.global_transform = world
	device.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	device.reset_physics_interpolation()


func _restore_held_render_space(id: String) -> void:
	if not _held_space_state.has(id):
		return
	var state: Dictionary = _held_space_state[id]
	_held_space_state.erase(id)
	var device: Node3D = state.get("device") as Node3D
	if device == null or not is_instance_valid(device):
		return
	var world := device.global_transform
	var original_parent: Node = state.get("parent") as Node
	if original_parent != null and is_instance_valid(original_parent):
		device.reparent(original_parent, true)
		var original_index := int(state.get("index", -1))
		if original_index >= 0:
			original_parent.move_child(device,
					mini(original_index, original_parent.get_child_count() - 1))
	device.top_level = bool(state.get("top_level", false))
	device.global_transform = world
	device.physics_interpolation_mode = int(state.get("interpolation",
			Node.PHYSICS_INTERPOLATION_MODE_INHERIT))
	device.reset_physics_interpolation()


func _held_visual_points(id: String, device: Node3D,
		frame: Dictionary) -> Array[Vector3]:
	var cache_key := "%s:%s" % [id, device.get_instance_id()]
	if _held_point_cache.has(cache_key):
		return _held_point_cache[cache_key] as Array[Vector3]
	var points: Array[Vector3] = []
	var to_device := device.global_transform.affine_inverse()
	var stack: Array[Node] = [device]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child: Node in node.get_children():
			stack.append(child)
		if not (node is MeshInstance3D):
			continue
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		var bounds := mesh_node.get_aabb()
		for corner in 8:
			points.append(to_device * (mesh_node.global_transform
					* bounds.get_endpoint(corner)))
	points.append(frame.get("focus_point", Vector3.ZERO) as Vector3)
	if points.size() == 1:
		points.append(Vector3.ZERO)
	_held_point_cache[cache_key] = points
	return points


func _rest_hand(side: String) -> void:
	## Idle hang in the lower corners. Standing, they just sit there. Walking,
	## they swing opposite each other — right forward with the left foot —
	## the way a body does, not a HUD bob.
	rig.set_contact_target(side, null)
	var out: float = 1.0 if side == "R" else -1.0
	var c: Transform3D = _cam.global_transform
	var ph: float = _gait + (0.0 if side == "R" else PI)
	var s := sin(ph)
	var w: float = smoothstep(0.02, 0.38, _stride)
	var idle := sin(_watch_driver.clock() * 1.15 \
			+ (0.0 if side == "R" else 1.7)) * 0.010
	# Visible in the lower third, a real step, but the wrist does not roll —
	# that is what walked the watch off the left arm.
	var home: Vector3 = c * Vector3(
			out * (0.168 + (1.0 - absf(s)) * 0.030 * w),
			-0.30 + s * 0.085 * w + idle,
			-0.28 - s * 0.12 * w)
	var u: float = clampf(_rest_t[side] / 0.34, 0.0, 1.0)
	u = u * u * (3.0 - 2.0 * u)
	var from: Vector3 = _last_grip[side] if u < 1.0 else home
	var contact: Vector3 = from.lerp(home, u)
	# Restore the original walking silhouette: loose fingers hang diagonally
	# down/forward and each palm stays side-on to the camera. Inferring this frame
	# again from shoulder -> hand made both wrists roll through the step and
	# periodically presented the broad open palm to the player.
	var fingers: Vector3 = c.basis * Vector3(out * 0.08, -0.86, -0.46)
	var palm: Vector3 = c.basis * Vector3(-out * 0.95, -0.12, 0.16)
	var previous: Dictionary = _last_axes.get(side, {}) as Dictionary
	if u < 1.0 and previous.has("fingers") and previous.has("palm"):
		# Rotation-minimising transport: follow the changing forearm direction but
		# never add pronation/supination around it. This is the missing invariant
		# that stops a released support hand showing its palm in the final frame.
		var previous_f := (previous["fingers"] as Vector3).normalized()
		var previous_p := (previous["palm"] as Vector3).normalized()
		fingers = previous_f.slerp(fingers, u).normalized()
		palm = Basis(Quaternion(previous_f, fingers)) * previous_p
		palm -= palm.project(fingers)
		if palm.length_squared() > 0.001:
			palm = palm.normalized()
	_last_grip[side] = contact
	_last_axes[side] = {"fingers": fingers, "palm": palm}
	var release_pose := str(_last_pose.get(side, "open"))
	var release_amount := 0.18
	if release_pose == "rifle_support":
		# Keep the support grasp while clearing the stock. Fingers relax only in
		# the lower half of withdrawal, where opening cannot masquerade as a palm
		# flip in front of the receiver.
		release_amount = 1.0 - smoothstep(0.48, 0.92, u) * 0.82
	else:
		release_pose = "open"
	if u >= 1.0:
		_last_pose[side] = "open"
	rig.grip(side, contact, fingers, palm, 1.0, release_pose, release_amount)


func _device_of(id: String) -> Node3D:
	return GripMap.device_of(boat, id)


func _grip_node(id: String, side: String) -> Node3D:
	var key := id + ":" + side
	var spec: Dictionary = GripMap.spec_for(id)
	if _grips.has(key) and is_instance_valid(_grips[key]):
		var cached: Node3D = _grips[key]
		# Door grips change face with the player.  A cached node must therefore
		# be re-stamped on every use; otherwise the first side ever touched wins
		# for the rest of the session.
		if bool(spec.get("latch", false)):
			var live: Dictionary = GripMap.sided(spec, side)
			var live_contact: Vector3 = GripMap.contact_of(live, boat, id)
			live = GripMap.oriented_at_contact(live, live_contact)
			cached.transform = GripMap.local_frame(live, live_contact)
		return cached
	var device: Node3D = _device_of(id)
	if device == null:
		return null
	var g := Node3D.new()
	g.name = "Grip_" + side
	device.add_child(g)
	# Prefer a grip the object already carries. Otherwise stamp the catalog
	# frame. Rim holds stay identity — HelmHandDriver owns those every frame.
	var stock := device.get_node_or_null("Grip") as Node3D
	if stock != null and stock != g:
		g.transform = stock.transform
	elif bool(spec.get("on_rim", false)) or spec.is_empty():
		g.transform = Transform3D.IDENTITY
	else:
		var sided: Dictionary = GripMap.sided(spec, side)
		var local_contact: Vector3 = GripMap.contact_of(sided, boat, id)
		sided = GripMap.oriented_at_contact(sided, local_contact)
		g.transform = GripMap.local_frame(sided, local_contact)
	_grips[key] = g
	return g


func _on(obj: Object, key: String) -> bool:
	return obj != null and obj.get(key) == true


func _num(obj: Object, key: String) -> float:
	if obj == null:
		return 0.0
	var v: Variant = obj.get(key)
	if typeof(v) == TYPE_FLOAT:
		return v
	if typeof(v) == TYPE_INT:
		return float(v)
	return 0.0
