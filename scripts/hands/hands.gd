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
		_watch_driver.force_lower()
		if boat != null:
			# Leaving first person parks whatever the powered rails hold.
			boat.call("set_radar_pull", 0.0)
			boat.call("set_sounder_pull", 0.0)
		_claim = {"L": "", "R": ""}
		_gesture = {"L": null, "R": null}
		_inspect = ""


func inspecting_id() -> String:
	return _inspect


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
	return (rig.lean() * (0.56 * phase)).limit_length(0.27)


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
	if spec.is_empty() or rig == null or not rig.is_ready() or _device_of(id) == null:
		return false
	var gate: String = str(spec.get("gate", ""))
	if gate != "" and not bool(boat.call("switch_state", gate)):
		return false
	return _pick_hand(id, str(spec.get("preferred", "")), MAX_REACH_ASSIST) != ""


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


func set_sea_ladder(on: bool, feet_y: float) -> void:
	_ladder_driver.set_state(on, feet_y)


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
	if _ladder_driver.is_active() and _active and boat != null:
		rig.set_visible_hands(true)
		_claim = {"L": "", "R": ""}
		_inspect = ""
		for side: String in ["L", "R"]:
			_last_grip[side] = _ladder_driver.drive(side, delta, boat, rig)
			_rest_t[side] = 0.0
		_finish(delta)
		return
	if swimming and _active:
		rig.set_visible_hands(true)
		_claim = {"L": "", "R": ""}
		_inspect = ""
		_swim_driver.advance(delta)
		if _watch_up():
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
		if _claim["R"] == "" and _inspect == "":
			if _can_take("R", "telegraph"):
				_take("R", "telegraph")
	elif engaged == "telegraph":
		if _claim["R"] == "":
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
			_last_grip["L"] = _watch_driver.drive(_cam, rig)
			_rest_t["L"] = 0.0
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
	_claim[side] = ""
	_gesture[side] = null
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
	var id: String = _claim[side]
	return id == "radio"


func _begin(id: String, spec: Dictionary = {}, allow_reach_assist := false) -> bool:
	if spec.is_empty():
		spec = GripMap.spec_for(id)
	if spec.is_empty() or rig == null or not rig.is_ready():
		return false
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


func _planned_candidate(side: String, id: String, assist_cap: float) -> Dictionary:
	## Sample the actual palm path, not only its endpoint. New interactables get
	## this automatically from their contact frame and approach distance.
	var goal: Vector3 = _side_contact(id, side)
	var asked: Dictionary = _asked_axes(id, side)
	var approach := maxf(float(GripMap.spec_for(id).get("approach", 0.0)), 0.0)
	var spec: Dictionary = GripMap.spec_for(id)
	return GRASP_PLANNER.sample_candidate(rig, side, goal, asked["fingers"],
			asked["palm"], approach, assist_cap, false, not GripMap.welded(spec),
			0.15 if _claim.get(side, "") in ["helm", "telegraph"] else 0.0)


func _pick_hand(id: String, preferred := "", reach_slack := 0.0) -> String:
	## Preferred is only a tie-breaker. Actual side, approach path, torso cross,
	## elbow, wrist and palm decide which hand a person would really use.
	var candidates := {
		"L": _planned_candidate("L", id, reach_slack),
		"R": _planned_candidate("R", id, reach_slack),
	}
	var choice: Dictionary = GRASP_PLANNER.choose(candidates, rig.WRIST_CONE,
			{"L": _locked("L"), "R": _locked("R")}, preferred)
	return str(choice.get("side", ""))


func _asked_axes(id: String, side: String) -> Dictionary:
	var spec: Dictionary = GripMap.sided(GripMap.spec_for(id), side)
	var local_contact: Vector3 = GripMap.contact_of(spec, boat, id)
	spec = GripMap.oriented_at_contact(spec, local_contact)
	var device := _device_of(id)
	var db: Basis = device.global_basis if device != null else Basis.IDENTITY
	if boat != null:
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
	if boat != null:
		p = (boat as Node3D).get_global_transform_interpolated() \
				* (boat.global_transform.affine_inverse() * p)
	return p


func _peek_contact(id: String) -> Vector3:
	return _side_contact(id, "R")


func _drive(side: String, delta: float) -> void:
	var id: String = _claim[side]
	if id == "":
		_rest_hand(side)
		return
	var g := _grip_node(id, side)
	if g == null:
		_release(side)
		return
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
	if boat != null:
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
	rig.grip(side, xf.origin, fingers, palm, 1.0, pose, hold, not welded)


func _rest_hand(side: String) -> void:
	## Idle hang in the lower corners. Standing, they just sit there. Walking,
	## they swing opposite each other — right forward with the left foot —
	## the way a body does, not a HUD bob.
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
	var fingers: Vector3 = c.basis * Vector3(out * 0.08, -0.86, -0.46)
	var palm: Vector3 = c.basis * Vector3(-out * 0.95, -0.12, 0.16)
	_last_grip[side] = contact
	rig.grip(side, contact, fingers, palm, 1.0, "open", 0.18)


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
