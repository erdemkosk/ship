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
## catalog — `_pick_hand` takes the nearer one that can hold without folding
## its wrist. `preferred` is optional and binding when set (ignition is R).
## Helm rim, face, watch, ladder stay special — they are not objects.

const RIG := preload("res://scripts/hands/hand_rig.gd")

## Wheel arc a hand rides before re-gripping — a helmsman takes a fresh hold,
## they do not wind their wrist up.
const REGRIP_ARC := 0.9
const REGRIP_TIME := 0.34
## How far the palm lifts off the rim while it slides to the fresh hold.
const REGRIP_LIFT := 0.07
const RIM := 0.29          # helm rim radius (boat.gd torus: inner .26 outer .32)

var boat: Node3D
var rig: Node3D

var _cam: Camera3D
var _active := false
var _claim := {"L": "", "R": ""}
var _grips := {}
var _rim_angle := {}
var _rim_ref := {}
var _regrip := {"L": 0.0, "R": 0.0}
var _rim_from := {}
var _rim_to := {}
var _inspect := ""
## One-shot reach timer: the hand goes to a control (the ignition key), stays
## on it for the gesture, and gives the claim back on its own.
var _oneshot := 0.0
var _oneshot_side := "R"
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
var _face := ""
var _face_t := 0.0
## The dive watch. B held raises the left arm to read it — a HELD gesture, not
## a one-shot: the arm stays up exactly as long as the button does, which is
## how looking at a watch actually works. It outranks every left-hand claim
## (the wheel gets the hand back the moment B lifts) and it works in the water,
## where the depth row is the whole point of owning the thing.
var _watch_on := false
var _watch_t := 0.0
var _watch_clock := 0.0
var _watch_tod := 12.0
var _watch_depth := 0.0
## Where the wiping finger is, in the mask shader's own screen space, and which
## way it is travelling. The glass has to clear UNDER THE HAND — read off a
## timer instead and the fog cleared left-to-right while the hand went
## right-to-left, which is worse than not animating it at all.
var _wipe_x := 9.0
var _wipe_dir := -1.0
var _ladder := false
var _ladder_y := 0.0
var _lad_pos := {}
var _dbg := 0
var _swim_t := 0.0
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
		_watch_on = false
		if boat != null:
			# Leaving first person parks whatever the powered rails hold.
			boat.call("set_radar_pull", 0.0)
			boat.call("set_sounder_pull", 0.0)
		_claim = {"L": "", "R": ""}
		_inspect = ""


func inspecting_id() -> String:
	return _inspect


func notify_use(id: String) -> void:
	## Helm / telegraph / chart are modes owned by boat.gd — the engaged state
	## drives those claims in update(). Everything else is a GripMap spec.
	var spec: Dictionary = GripMap.spec_for(id)
	if spec.is_empty():
		return
	var gate: String = str(spec.get("gate", ""))
	if gate != "" and not bool(boat.call("switch_state", gate)):
		return
	if bool(spec.get("toggle", false)):
		var held := _owner_of(id)
		if held != "":
			_release(held)
			return
	var rail: String = str(spec.get("rail", ""))
	if rail != "":
		var setter := "set_%s_pull" % rail
		var other := "sounder" if rail == "radar" else "radar"
		if _num(boat, rail + "_pull") > 0.5:
			# Home as well as out: the hand pushes the case off, it does not
			# vanish while the rail retracts on its own.
			boat.call(setter, 0.0)
		else:
			boat.call("set_%s_pull" % other, 0.0)
			boat.call(setter, 1.0)
	if bool(spec.get("drops_instruments", false)):
		_drop_instruments()
	_begin(id, spec)


func set_watch(held: bool, tod: float, depth: float) -> void:
	if held and not _watch_on and _claim["L"] != "":
		# Rising edge: whatever the left hand held, it lets go of first.
		_release("L")
	_watch_on = held
	_watch_tod = tod
	_watch_depth = depth


func _watch_up() -> bool:
	return _watch_on or _watch_t > 0.01


func face_gesture(kind: String) -> void:
	_face = kind
	_face_t = 0.0
	_wipe_x = 9.0
	_wipe_dir = -1.0


func wipe_front() -> Vector2:
	## (x, direction) of the finger on the glass. x is in the same units the
	## mask shader uses: screen, centred, aspect-corrected.
	return Vector2(_wipe_x, _wipe_dir)


func set_sea_ladder(on: bool, feet_y: float) -> void:
	## Called from the camera with the walker's state. `feet_y` is boat-local.
	if on and not _ladder:
		_lad_pos.clear()
	_ladder = on
	_ladder_y = feet_y


func update(delta: float, p_boat: Node3D, engaged: String, walking: float,
		swimming: bool) -> void:
	boat = p_boat
	if rig == null or not rig.is_ready():
		return
	# The watch runs whether or not anyone is looking at it — a watch does.
	_watch_clock += delta
	_watch_t = move_toward(_watch_t, 1.0 if (_watch_on and _active) else 0.0,
			delta / 0.26)
	if rig.has_method("set_watch_display"):
		var hh := floorf(_watch_tod)
		var mins := floorf((_watch_tod - hh) * 60.0)
		var night := _watch_tod < 5.5 or _watch_tod > 18.5
		# The backlight is the sea's and the night's: underwater it is on,
		# after dark it is on, on a grey afternoon deck it is a dead film.
		var glw := 0.95 if _watch_depth > 0.02 else (0.65 if night else 0.06)
		rig.set_watch_display(hh, mins, _watch_clock, _watch_depth,
				1.013 + _watch_depth * 0.1003, glw)
	if _face != "" and _active:
		# Ahead of everything, including the swimming test: wiping the glass is
		# a thing you do precisely when you are in the water.
		rig.set_visible_hands(true)
		if _drive_face(delta):
			_face = ""
			_rest_t["L"] = 0.0
			_rest_t["R"] = 0.0
		_finish(delta)
		return
	if _ladder and _active and boat != null:
		rig.set_visible_hands(true)
		_claim = {"L": "", "R": ""}
		_inspect = ""
		_drive_ladder("L", delta)
		_drive_ladder("R", delta)
		_finish(delta)
		return
	if swimming and _active:
		rig.set_visible_hands(true)
		_claim = {"L": "", "R": ""}
		_inspect = ""
		_swim_t += delta
		if _watch_up():
			_drive_watch(delta)
		else:
			_drive_swim("L", delta)
		_drive_swim("R", delta)
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

	if _oneshot > 0.0:
		_oneshot -= delta
		if _oneshot <= 0.0:
			var oid: String = str(_claim.get(_oneshot_side, ""))
			if float(GripMap.spec_for(oid).get("oneshot", 0.0)) > 0.0:
				_release(_oneshot_side)

	# Radio state belongs to boat.gd; mirror it.
	if _on(boat, "radio_held"):
		if _owner_of("radio") == "":
			_begin("radio", GripMap.spec_for("radio"))
	else:
		var radio_side := _owner_of("radio")
		if radio_side != "":
			_release(radio_side)

	# At the wheel both hands work: left steers, right rests on the telegraph.
	if engaged == "helm":
		if _claim["L"] == "" and not _watch_up():
			_take("L", "helm")
		if _claim["R"] == "" and _inspect == "":
			_take("R", "telegraph")
	elif engaged == "telegraph":
		if _claim["R"] == "":
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
			_drive_watch(delta)
		else:
			_drive(side, delta)
	_finish(delta)


func _finish(delta: float) -> void:
	if rig.has_method("set_watch_read"):
		rig.set_watch_read(_watch_t)
	rig.update(delta)


# --- claims ------------------------------------------------------------------

func _take(side: String, id: String) -> void:
	_claim[side] = id
	_regrip[side] = 0.0
	if id == "helm":
		_seat_on_rim(side)


func _release(side: String) -> void:
	_claim[side] = ""
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


func _begin(id: String, spec: Dictionary = {}) -> void:
	if spec.is_empty():
		spec = GripMap.spec_for(id)
	if spec.is_empty() or rig == null or not rig.is_ready():
		return
	var side := _pick_hand(id, str(spec.get("preferred", "")))
	if side == "":
		return
	if bool(spec.get("must_reach", false)):
		var ev: Dictionary = rig.evaluate(side, _side_contact(id, side))
		if not bool(ev.get("reachable", false)):
			return
	_take(side, id)
	var t: float = float(spec.get("oneshot", 0.0))
	if t > 0.0:
		_oneshot = t
		_oneshot_side = side


func _pick_hand(id: String, preferred := "") -> String:
	## Organic unless the object named a hand. Ignition is right — that is
	## not a suggestion. Empty preferred: nearer arm that can hold it.
	if preferred == "L" or preferred == "R":
		if not _locked(preferred):
			return preferred
	var cl: Vector3 = _side_contact(id, "L")
	var cr: Vector3 = _side_contact(id, "R")
	var fl: Dictionary = _asked_axes(id, "L")
	var fr: Dictionary = _asked_axes(id, "R")
	var el: Dictionary = rig.consider("L", cl, fl["fingers"], fl["palm"])
	var er: Dictionary = rig.consider("R", cr, fr["fingers"], fr["palm"])
	var sl: float = _hand_score("L", el, preferred)
	var sr: float = _hand_score("R", er, preferred)
	if sl >= 80.0 and sr >= 80.0:
		return ""
	if not _locked("L") and not _locked("R"):
		var ok_l: bool = bool(el.get("comfortable", false))
		var ok_r: bool = bool(er.get("comfortable", false))
		if ok_l and not ok_r:
			return "L"
		if ok_r and not ok_l:
			return "R"
		if ok_l and ok_r:
			var dl: float = float(el.get("distance", 1e6))
			var dr: float = float(er.get("distance", 1e6))
			if absf(dl - dr) > 0.04:
				return "L" if dl < dr else "R"
	return "L" if sl < sr else "R"


func _hand_score(side: String, ev: Dictionary, preferred := "") -> float:
	if _locked(side) or rig == null or not rig.is_ready():
		return 100.0
	# Distance first. A wrist crime is worse than a few extra centimetres.
	# Crossing the chest is almost a refusal. Preferred is a whisper.
	var s: float = float(ev.get("distance", 0.0)) \
			+ float(ev.get("leftover", 0.0)) * 6.0 \
			+ float(ev.get("cross", 0.0)) * 5.0 \
			+ float(ev.get("wrist_break", 0.0)) * 0.55
	if not bool(ev.get("comfortable", false)):
		s += 1.4
	if _claim[side] in ["helm", "telegraph"]:
		s += 0.15
	if preferred == side:
		s -= 0.04
	return s


func _asked_axes(id: String, side: String) -> Dictionary:
	var spec: Dictionary = GripMap.sided(GripMap.spec_for(id), side)
	return {
		"fingers": spec.get("fingers", Vector3.ZERO),
		"palm": spec.get("palm", Vector3.ZERO),
	}


func _side_contact(id: String, side: String) -> Vector3:
	var device := _device_of(id)
	if device == null:
		if _cam == null:
			return Vector3.ZERO
		return _cam.global_position - _cam.global_basis.z * 0.40
	var spec: Dictionary = GripMap.sided(GripMap.spec_for(id), side)
	var local: Transform3D = GripMap.local_frame(spec, GripMap.contact_of(spec, boat, id))
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
		hold = _ride_rim(side, delta)
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
	var idle := sin(_watch_clock * 1.15 + (0.0 if side == "R" else 1.7)) * 0.010
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


func _drive_swim(side: String, _delta: float) -> void:
	## Front crawl as seen from inside the head: each arm pulls through the
	## lower third of the picture and recovers outboard. Idle treading is the
	## same path, slower.
	var c: Transform3D = _cam.global_transform
	var o: float = 1.0 if side == "R" else -1.0
	var move := Input.get_vector("boat_left", "boat_right", "boat_backward", "boat_forward")
	var rate := lerpf(1.35, 2.55, clampf(move.length(), 0.0, 1.0))
	var ph: float = _swim_t * rate + (0.0 if side == "R" else PI)
	var pull := sin(ph)
	var rec := cos(ph)
	var x: float = o * (0.20 + (1.0 - absf(pull)) * 0.06)
	var y: float = -0.26 + rec * 0.09
	var z: float = -0.30 - pull * 0.14
	var pt: Vector3 = c * Vector3(x, y, z)
	var fingers: Vector3 = c.basis * Vector3(o * 0.18, -0.22 - pull * 0.15, -0.96)
	var palm: Vector3 = c.basis * Vector3(o * 0.08, -0.92, 0.18)
	_last_grip[side] = pt
	_rest_t[side] = 0.0
	var hold: float = clampf(0.25 + pull * 0.35, 0.12, 0.7)
	rig.grip(side, pt, fingers, palm, 1.0, "open", hold)


# --- the watch ----------------------------------------------------------------

func _drive_watch(delta: float) -> void:
	## The left arm comes up across the chest and the back of the wrist turns
	## to the eye. Driven in camera space like the face gestures: the watch is
	## read fifteen centimetres from the lens, where a solved-to-target arm
	## wobbles and a keyframed path does not.
	##
	## The PALM is what grip() places and the palm is on the far side of the
	## wrist — so the contact aims palm-DOWN-and-away, and what faces you is
	## the strap side with the case on it.
	var c: Transform3D = _cam.global_transform
	var u: float = _watch_t * _watch_t * (3.0 - 2.0 * _watch_t)
	# Up from where an idle hand hangs, along a slight arc — lifted straight
	# in it reads as a puppet on a string. The end point stays far enough out
	# that the forearm passes UNDER the frame instead of through the lens.
	var lo := Vector3(-0.30, -0.62, -0.34)
	# Higher than it used to sit, because the wrist is straighter now. With a
	# real break in the wrist the watch could hang low and still face you; held
	# in line with the arm it only comes into view if the whole arm comes up —
	# which is exactly what a person does.
	var hi := Vector3(0.055, -0.062, -0.268)
	var pt: Vector3 = lo.lerp(hi, u)
	pt.x += sin(u * PI) * -0.05
	var contact: Vector3 = c * pt
	# The POSE is what presents the watch, because nothing else is allowed to:
	# the case is strapped flat to the wrist and does not turn toward anyone.
	#
	# The gesture is the one everybody actually makes — the forearm swung up
	# across the chest, and the hand very nearly IN LINE with it. That last
	# part is the whole of looking natural: a wrist held out to read a watch
	# barely breaks at all. So the hand is built FROM the live forearm line
	# with a small, fixed extension, rather than from a direction picked by
	# eye — pick it by eye and the break is whatever falls out, which is how
	# it kept coming back cranked.
	#
	# Supination is free and extension is rationed: the face is turned toward
	# the eye by rolling the forearm, which costs nothing anatomically, and
	# never by bending the wrist further.
	var fore: Vector3 = (contact - (rig.shoulder_global("L") as Vector3)).normalized()
	var to_eye: Vector3 = (c.origin - contact).normalized()
	var dorsal: Vector3 = (to_eye - to_eye.project(fore)).normalized()
	var ext := deg_to_rad(12.0)
	var fingers: Vector3 = (fore * cos(ext) + dorsal * sin(ext)).normalized()
	var face_n: Vector3 = (dorsal * cos(ext) - fore * sin(ext)).normalized()
	var palm: Vector3 = -face_n
	_last_grip["L"] = contact
	_rest_t["L"] = 0.0
	# A relaxed half-curl: an open starfish hand is nobody reading a watch.
	rig.grip("L", contact, fingers, palm, u, "wrap", 0.50 * u)


# --- your own face ------------------------------------------------------------

func _drive_face(delta: float) -> bool:
	## Returns true when the movement is finished.
	##
	## Both of these are read from INSIDE the head, which is the awkward part:
	## the hand is 15 cm from the lens and any error in it is enormous. So they
	## are keyframed as a path in camera space rather than solved to a target —
	## three points and an ease, the way an animator would do it.
	var c: Transform3D = _cam.global_transform
	_face_t += delta
	if _face == "wear":
		var dur := 1.35
		var u: float = clampf(_face_t / dur, 0.0, 1.0)
		var e: float = u * u * (3.0 - 2.0 * u)
		for side: String in ["L", "R"]:
			var o: float = 1.0 if side == "R" else -1.0
			# Up from your side with the mask, onto the face, then the strap
			# over your head and away.
			var a := Vector3(o * 0.34, -0.62, -0.34)
			var b := Vector3(o * 0.165, -0.05, -0.30)
			var d := Vector3(o * 0.185, 0.10, -0.02)
			var f := Vector3(o * 0.40, -0.30, 0.10)
			var pt: Vector3
			if e < 0.42:
				pt = a.lerp(b, e / 0.42)
			elif e < 0.74:
				pt = b.lerp(d, (e - 0.42) / 0.32)
			else:
				pt = d.lerp(f, (e - 0.74) / 0.26)
			# Palm turned in toward your own face, fingers along the strap.
			var fingers: Vector3 = c.basis * Vector3(-o * 0.35, 0.15, 0.92)
			var palm: Vector3 = c.basis * Vector3(-o, -0.15, 0.0)
			_last_grip[side] = c * pt
			rig.grip(side, c * pt, fingers, palm, 1.0, "wrap",
					clampf(1.0 - absf(e - 0.58) * 2.2, 0.15, 1.0), false)
		return _face_t >= dur
	# wipe: one finger, across the glass, and back down.
	var dur2 := 0.95
	var u2: float = clampf(_face_t / dur2, 0.0, 1.0)
	var a2 := Vector3(0.30, -0.58, -0.26)
	var b2 := Vector3(0.24, -0.02, -0.185)
	var c2 := Vector3(-0.24, 0.01, -0.185)
	var d2 := Vector3(-0.34, -0.46, -0.20)
	var pt2: Vector3
	if u2 < 0.24:
		pt2 = a2.lerp(b2, u2 / 0.24)
	elif u2 < 0.72:
		var w: float = (u2 - 0.24) / 0.48
		pt2 = b2.lerp(c2, w * w * (3.0 - 2.0 * w))
	else:
		pt2 = c2.lerp(d2, (u2 - 0.72) / 0.28)
	# The back of the finger on the glass: palm toward you, fingertip forward.
	var f2: Vector3 = c.basis * Vector3(-0.55, 0.05, -0.84)
	var p2: Vector3 = c.basis * Vector3(0.0, -0.25, 0.96)
	# Project the fingertip into the shader's space. For a camera with vertical
	# FOV f, a point at camera (x, y, z<0) lands at p.x = x / (-z * tan(f/2) * 2)
	# — the same centred, aspect-corrected coordinate the mask is drawn in. This
	# is the whole synchronisation: one number, taken from the hand itself.
	var half: float = tan(deg_to_rad(_cam.fov) * 0.5)
	_wipe_x = pt2.x / maxf(-pt2.z * half * 2.0, 1e-3)
	_wipe_dir = -1.0
	_last_grip["R"] = c * pt2
	rig.grip("R", c * pt2, f2, p2, 1.0, "point", 1.0, false)
	_rest_hand("L")
	return _face_t >= dur2


# --- the boarding ladder ------------------------------------------------------

const RUNG_PITCH := 0.27
## Where a hand reaches above the feet on a ladder. NOT eye height, which is
## where a real climber's hands are — at 1.6 the rung sits 36 cm from the lens
## and one palm fills a third of the frame. Chest height reads as a climb and
## keeps the hands in the bottom of the picture where hands belong.
const RUNG_REACH := 1.12
const RUNG_SPAN := 0.13    # hands either side of the stile centreline


func _rung_local(i: int) -> Vector3:
	var y: float = float(boat.SEA_LADDER_TOP) - 0.10 - float(i) * RUNG_PITCH
	# Same six-degree rake the walker climbs; see deck_walker._sea_stand.
	var z: float = float(boat.SEA_LADDER_Z) + y * 0.1045
	return Vector3(float(boat.SEA_LADDER_X), y, z)


func _drive_ladder(side: String, delta: float) -> void:
	## Two hands, alternating, on a ladder that is moving with the ship.
	##
	## The rung a hand wants is picked from the FEET, not from the hand: pick it
	## from the hand and the two chase each other up the ladder. The parity of
	## that index decides which hand is the high one, so every rung climbed
	## swaps the lead — which is the whole of an alternating climb, for free.
	var top: float = float(boat.SEA_LADDER_TOP)
	var i_f: float = (top - 0.10 - (_ladder_y + RUNG_REACH)) / RUNG_PITCH
	var i_hi: int = int(floor(i_f))
	var lead_is_r: bool = (i_hi % 2) == 0
	var high: bool = (side == "R") == lead_is_r
	var i: int = clampi(i_hi if high else i_hi + 1, 0, 6)
	var out: float = -1.0 if side == "L" else 1.0
	var lp: Vector3 = _rung_local(i) + Vector3(out * RUNG_SPAN, 0.024, 0.0)
	# Palm down on the iron, fingers curling over the far side of the rung.
	var f_l := Vector3(0.0, -0.30, -1.0)
	var p_l := Vector3(0.0, -1.0, -0.30)
	# At the top there are no rungs left to take: the top one is level with the
	# deck, and what your hands actually find up there are the two grab handles
	# standing above the cap. Reaching for a rung from up here puts both hands
	# down by your knees, which is what it looked like.
	if i_hi < 0:
		var hy: float = clampf(_ladder_y + RUNG_REACH, 0.70, 1.02)
		lp = Vector3(float(boat.SEA_LADDER_X) + out * 0.16 + out * 0.024, hy,
				float(boat.SEA_LADDER_Z) + hy * 0.1045)
		# A vertical post: the palm faces it, the fingers wrap round toward her.
		f_l = Vector3(0.0, -0.25, -1.0)
		p_l = Vector3(-out, -0.10, 0.0)

	var bxf: Transform3D = (boat as Node3D).get_global_transform_interpolated()
	var tgt: Vector3 = bxf * lp
	var cur: Vector3 = _lad_pos.get(side, tgt)
	# Travel to the new rung instead of appearing on it, and come off the iron
	# on the way — a hand that slides along a rung is a hand that never let go.
	var d: float = cur.distance_to(tgt)
	cur = cur.lerp(tgt, 1.0 - exp(-11.0 * delta))
	_lad_pos[side] = cur
	var lift: Vector3 = bxf.basis.z.normalized() * minf(d, 0.34) * 0.55
	var contact: Vector3 = cur + lift
	var fingers: Vector3 = bxf.basis * f_l
	var palm: Vector3 = bxf.basis * p_l
	_last_grip[side] = contact
	_rest_t[side] = 0.0
	# The hold opens while the hand is in transit and closes on the rung.
	rig.grip(side, contact, fingers, palm, 1.0, "wrap",
			clampf(1.0 - d * 3.0, 0.15, 1.0))


# --- the wheel ---------------------------------------------------------------

func _ride_rim(side: String, delta: float) -> float:
	## Ride the wheel round; when the wrist would be wrung out, take a fresh
	## hold. The swap is a real hand movement, not an IK fade: the fingers open,
	## the palm lifts off the rim and slides along an arc to the new point, and
	## the hold closes again — all with the arm still pinned to the moving grip,
	## so nothing snaps and nothing rubbers.
	var wheel: Node3D = boat.call("helm_wheel") as Node3D
	var g := _grip_node("helm", side)
	if wheel == null or g == null:
		return 1.0
	if _regrip[side] > 0.0:
		_regrip[side] = maxf(_regrip[side] - delta, 0.0)
		var u: float = 1.0 - _regrip[side] / REGRIP_TIME
		u = u * u * (3.0 - 2.0 * u)
		# The transit is planned in WORLD angle. Planning it in wheel-local
		# reads the same on paper and is wrong in practice: the wheel keeps
		# turning underneath the swap, the local lerp plus that rotation
		# composed into an arc that swung the hand under the hub — measured on
		# the rim's far bottom, out of frame, every single time. Fixing the
		# path in world space and back-solving the local angle each frame makes
		# the hand travel the short visible arc no matter what the wheel does.
		var world_a: float = lerp_angle(float(_rim_from[side]), float(_rim_to[side]), u)
		var a: float = world_a - wheel.rotation.z
		# Lift peaks mid-transit; zero at both ends so the hold seats cleanly.
		var lift: float = REGRIP_LIFT * sin(u * PI)
		_write_rim_grip(g, a, lift)
		if _regrip[side] <= 0.0:
			_rim_angle[side] = a
			_rim_ref[side] = wheel.rotation.z
		# Fingers open through the middle of the swap, closed at both ends.
		return clampf(1.0 - sin(u * PI) * 0.9, 0.1, 1.0)
	var turned: float = absf(wrapf(wheel.rotation.z - float(_rim_ref.get(side, 0.0)),
			-PI, PI))
	if turned > REGRIP_ARC:
		_rim_from[side] = float(_rim_angle[side]) + wheel.rotation.z
		_rim_to[side] = _pick_rim_angle(side) + wheel.rotation.z
		_regrip[side] = REGRIP_TIME
	return 1.0


func _pick_rim_angle(side: String) -> float:
	## The rim point nearest a spot in front of that shoulder — where a hand
	## naturally falls. Wheel-local, so it stays put as the wheel turns.
	var wheel: Node3D = boat.call("helm_wheel") as Node3D
	var sh: Vector3 = rig.shoulder_global(side)
	var aim: Vector3 = sh + (-_cam.global_basis.z) * 0.36 - _cam.global_basis.y * 0.10
	var best := 0.0
	var best_d := 1e9
	for i in 24:
		var a := float(i) / 24.0 * TAU
		var p: Vector3 = wheel.global_transform * (Vector3(cos(a), sin(a), 0.0) * RIM)
		var d: float = aim.distance_to(p)
		if d < best_d:
			best_d = d
			best = a
	return best


func _write_rim_grip(g: Node3D, angle: float, lift: float) -> void:
	## Grip semantics in WHEEL LOCAL, so they turn with the wheel:
	##   contact  on the rim circle (pushed outward by `lift` during a re-grip)
	##   fingers  through the wheel plane, away from the helmsman (local -Z)
	##   palm     onto the rim, toward the hub (-radial)
	var radial := Vector3(cos(angle), sin(angle), 0.0)
	var F := Vector3(0.0, 0.0, -1.0)
	var P := -radial
	# The lift leaves the wheel plane toward the helmsman as well as off the
	# rim, so the palm clears the spokes rather than scraping across them.
	var out := radial * (RIM + lift) + Vector3(0.0, 0.0, lift * 0.8)
	g.transform = Transform3D(Basis(P.cross(F), P, F), out)
	if g.has_meta("natural"):
		g.remove_meta("natural")


func _seat_on_rim(side: String) -> void:
	var wheel: Node3D = boat.call("helm_wheel") as Node3D
	var g := _grip_node("helm", side)
	if wheel == null or g == null:
		return
	_rim_angle[side] = _pick_rim_angle(side)
	_rim_ref[side] = wheel.rotation.z
	_write_rim_grip(g, _rim_angle[side], 0.0)


func _device_of(id: String) -> Node3D:
	return GripMap.device_of(boat, id)


func _grip_node(id: String, side: String) -> Node3D:
	var key := id + ":" + side
	if _grips.has(key) and is_instance_valid(_grips[key]):
		return _grips[key]
	var device: Node3D = _device_of(id)
	if device == null:
		return null
	var spec: Dictionary = GripMap.spec_for(id)
	var g := Node3D.new()
	g.name = "Grip_" + side
	device.add_child(g)
	# Prefer a grip the object already carries. Otherwise stamp the catalog
	# frame. Rim holds stay identity — _write_rim_grip owns those every frame.
	var stock := device.get_node_or_null("Grip") as Node3D
	if stock != null and stock != g:
		g.transform = stock.transform
	elif bool(spec.get("on_rim", false)) or spec.is_empty():
		g.transform = Transform3D.IDENTITY
	else:
		var sided: Dictionary = GripMap.sided(spec, side)
		g.transform = GripMap.local_frame(sided, GripMap.contact_of(sided, boat, id))
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
