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

const RIG := preload("res://scripts/hands/hand_rig.gd")

## Wheel arc a hand rides before re-gripping — a helmsman takes a fresh hold,
## they do not wind their wrist up.
const REGRIP_ARC := 0.9
const REGRIP_TIME := 0.34
## How far the palm lifts off the rim while it slides to the fresh hold.
const REGRIP_LIFT := 0.07
const RIM := 0.29          # helm rim radius (boat.gd torus: inner .26 outer .32)
## Everything that is a GESTURE rather than a mode: the hand goes, does the
## thing, and hands the claim back on its own. Doors and lids are here because
## a door that opens with no hand in shot is a door opened by a ghost.
const GESTURES := ["ignition", "fusebox", "windlass",
		"door_fwd", "door_aft", "door_wh", "door_eng", "locker"]
## How the hand meets each: local offset on the device, plus finger pose.
const GESTURE_GRIP := {
	"fusebox": {"pos": Vector3(0.0, 0.13, 0.77), "pose": "wrap"},
	"door_fwd": {"pos": Vector3(0.86, 1.62, 0.05), "pose": "wrap"},
	"door_aft": {"pos": Vector3(0.86, 1.62, 0.05), "pose": "wrap"},
	"door_wh": {"pos": Vector3(-0.86, 0.94, -0.05), "pose": "wrap"},
	"door_eng": {"pos": Vector3(-0.07, 0.02, 0.82), "pose": "wrap"},
	"locker": {"pos": Vector3(0.03, 0.10, 0.41), "pose": "wrap"},
	"windlass": {"pos": Vector3(0.30, 0.10, 0.0), "pose": "fist"},
}
const KNOB_R := 0.032

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
var _watch: Node3D
var _watch_on := false
var _watch_blend := 0.0
var _swim_t := 0.0


func debug_frames(n: int) -> void:
	_dbg = n


func setup(cam: Camera3D) -> void:
	_cam = cam
	rig = RIG.new()
	add_child(rig)
	rig.setup(cam)
	rig.set_visible_hands(false)
	_watch = (load("res://scripts/dive_watch.gd") as GDScript).new()
	add_child(_watch)
	_watch.visible = false


func set_active(on: bool) -> void:
	_active = on and rig != null and rig.is_ready()
	if rig != null:
		rig.set_visible_hands(_active)
	if _cam != null:
		# The palms work centimetres from the lens; the default near plane cuts
		# them open.
		_cam.near = 0.05 if _active else 0.10
	if not _active:
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
	## drives those claims in update(). Only genuinely held things toggle here.
	if id == "radio":
		if _claim["R"] == "radio":
			_release("R")
		else:
			_take("R", "radio")
	elif id.begins_with("sw_"):
		# A finger jab at the toggle — only when the fuse box is open, which is
		# also the only time the boat will accept the throw.
		if bool(boat.call("switch_state", "fusebox")):
			if _claim["R"] in ["", "telegraph"]:
				_take("R", id)
				# Long enough to actually see the finger arrive, press, and
				# come back. At 0.55 the hand was gone before it got there.
				_oneshot = 1.05
	elif id in GESTURES and id != "ignition":
		# Reach, work it, let go. The lid or leaf is already swinging — boat.gd
		# owns that — so the hand is timed to arrive with it, not to cause it.
		if _claim["R"] in ["radar", "sounder"]:
			_release("R")
		_take("R", id)
		_oneshot = 0.85
	elif id == "ignition":
		# Turning the key is a gesture, not a mode: reach, pinch, and the claim
		# hands itself back. If an instrument is out, it goes home first — you
		# do not start an engine with a radar in your fist.
		if _claim["R"] in ["radar", "sounder"]:
			_release("R")
		_take("R", "ignition")
		_oneshot = 1.15
	elif id == "radar" or id == "sounder":
		# The rail is powered: E sends the carrier gliding out toward the eye,
		# E again (or walking away) sends it home. The hand does not drag it —
		# from the helm the case is beyond a real arm anyway. If it IS within
		# reach, the hand gives it a brief touch as it starts to move, and
		# that is all.
		var setter := "set_radar_pull" if id == "radar" else "set_sounder_pull"
		var other_setter := "set_sounder_pull" if id == "radar" else "set_radar_pull"
		var was_out: bool = float(boat.get(id + "_pull")) > 0.5
		if was_out:
			boat.call(setter, 0.0)
		else:
			boat.call(other_setter, 0.0)
			boat.call(setter, 1.0)
			var g := _grip_node(id, "R")
			if g != null and _claim["R"] in ["", "telegraph"]:
				var limit: float = float(rig.measurements().get("reach_m", 0.55)) \
						+ rig.MAX_LEAN
				if rig.shoulder_global("R").distance_to(g.global_position) < limit:
					_take("R", id)
					_oneshot = 0.7


func face_gesture(kind: String) -> void:
	_face = kind
	_face_t = 0.0
	_wipe_x = 9.0
	_wipe_dir = -1.0


func wipe_front() -> Vector2:
	## (x, direction) of the finger on the glass. x is in the same units the
	## mask shader uses: screen, centred, aspect-corrected.
	return Vector2(_wipe_x, _wipe_dir)


func set_watch_glance(on: bool) -> void:
	_watch_on = on


func tick_watch(tod: float, depth_m: float, wet: bool) -> void:
	if _watch != null and _watch.has_method("set_readout"):
		_watch.set_readout(tod, depth_m, wet)


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
	_watch_blend = move_toward(_watch_blend, 1.0 if _watch_on else 0.0, delta / 0.22)
	if _watch_blend > 0.02 and _active:
		rig.set_visible_hands(true)
		_drive_watch(delta, swimming)
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
	if _dbg > 0:
		_dbg -= 1
		print("[hands] engaged=%s claim=%s" % [engaged, _claim])

	if _oneshot > 0.0:
		_oneshot -= delta
		if _oneshot <= 0.0 and (_claim["R"] in GESTURES or _claim["R"] in ["radar", "sounder"]
				or _claim["R"].begins_with("sw_")):
			_release("R")


	# Radio state belongs to boat.gd; mirror it.
	if bool(boat.get("radio_held")):
		if _claim["R"] != "radio":
			_take("R", "radio")
	elif _claim["R"] == "radio":
		_release("R")

	# At the wheel both hands work: left steers, right rests on the telegraph.
	if engaged == "helm":
		if _claim["L"] == "":
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
		_drive(side, delta)
	_finish(delta)


func _finish(delta: float) -> void:
	rig.update(delta)
	_place_watch()


func _place_watch() -> void:
	if _watch == null or _cam == null:
		return
	if not _active:
		_watch.visible = false
		return
	if rig != null and rig.has_wrist("L"):
		_watch.visible = true
		_watch.global_transform = rig.watch_xf("L")
		return
	# B held but the IK has not written a wrist yet: still put the dial in
	# front of the eye so deck and sea do the same thing.
	if _watch_blend > 0.04:
		_watch.visible = true
		var c: Transform3D = _cam.global_transform
		var face: Vector3 = c.basis.z
		var along: Vector3 = c.basis.x
		var across: Vector3 = face.cross(along).normalized()
		along = across.cross(face).normalized()
		_watch.global_transform = Transform3D(Basis(across, face, along),
				c * Vector3(-0.08, -0.04, -0.16))
		return
	_watch.visible = false


# --- claims ------------------------------------------------------------------

func _take(side: String, id: String) -> void:
	_claim[side] = id
	_regrip[side] = 0.0
	if id == "helm":
		_seat_on_rim(side)


func _release(side: String) -> void:
	_claim[side] = ""
	rig.release(side)


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
	var pose := "wrap"
	if id == "telegraph":
		pose = "fist"
	elif id == "ignition":
		pose = "pinch"
	elif id.begins_with("sw_"):
		pose = "point"
	elif GESTURE_GRIP.has(id):
		pose = str(GESTURE_GRIP[id].get("pose", "wrap"))
	# The arm stays pinned (weight 1); `hold` only opens and closes the
	# fingers, which is what a re-grip looks like from inside the hand.
	_last_grip[side] = xf.origin
	rig.grip(side, xf.origin, xf.basis.z, xf.basis.y, 1.0, pose, hold)


func _rest_hand(side: String) -> void:
	## Idle: hands DOWN and OUT of shot, at the sides where they hang. The old
	## rest sat them at camera-space y -0.52, which at this field of view is
	## still on screen — so every finished gesture left a hand parked in the
	## middle of the picture. It also snapped there, because the IK target
	## jumped. Now the hand travels from wherever it let go, on an ease, to a
	## spot well below the frustum.
	var out: float = 1.0 if side == "R" else -1.0
	var c: Transform3D = _cam.global_transform
	# BEHIND the lens plane (+z in camera space), not merely low. The old home
	# at y -0.86 was 0.66 m from the shoulder and the arm is 0.55 — so the
	# solver could not reach it, stopped short, and left the hand parked in the
	# bottom of the picture, which is the "hand stuck on screen" all over again.
	# This one is 0.26 m away and behind the near plane: reachable, and gone.
	var home: Vector3 = c * Vector3(out * 0.36, -0.52, 0.12)
	var u: float = clampf(_rest_t[side] / 0.34, 0.0, 1.0)
	u = u * u * (3.0 - 2.0 * u)
	var from: Vector3 = _last_grip[side] if u < 1.0 else home
	var contact: Vector3 = from.lerp(home, u)
	var fingers: Vector3 = c.basis * Vector3(out * 0.12, -0.90, -0.42)
	var palm: Vector3 = c.basis * Vector3(-out, -0.10, 0.0)
	# Weight falls away with the travel: by the time it is home the solver has
	# let go entirely and the arm hangs on its own.
	rig.grip(side, contact, fingers, palm, 1.0 - u * 0.55, "open", 0.0)


func _drive_watch(_delta: float, swimming: bool) -> void:
	## Raise the left wrist into the mask opening and look at the dial. Close
	## and high — the old pose sat under the rubber skirt, so you never saw it.
	var c: Transform3D = _cam.global_transform
	var u: float = _watch_blend
	u = u * u * (3.0 - 2.0 * u)
	var home := Vector3(-0.36, -0.52, 0.12)
	var show := Vector3(-0.10, -0.03, -0.18)
	var pt: Vector3 = c * home.lerp(show, u)
	var f_home := Vector3(-0.12, -0.90, -0.42)
	var f_show := Vector3(0.55, 0.18, -0.81)
	var p_home := Vector3(1.0, -0.10, 0.0)
	var p_show := Vector3(0.22, -0.48, -0.85)
	var fingers: Vector3 = c.basis * f_home.lerp(f_show, u)
	var palm: Vector3 = c.basis * p_home.lerp(p_show, u)
	_last_grip["L"] = pt
	_rest_t["L"] = 0.0
	rig.grip("L", pt, fingers, palm, 1.0, "open", 0.2)
	if swimming:
		_swim_t += _delta
		_drive_swim("R", _delta)
	else:
		_rest_t["R"] = minf(_rest_t["R"] + _delta, 1.0)
		_rest_hand("R")


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
					clampf(1.0 - absf(e - 0.58) * 2.2, 0.15, 1.0))
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
	rig.grip("R", c * pt2, f2, p2, 1.0, "point", 1.0)
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
	var z: float = float(boat.SEA_LADDER_Z) + 0.02 + (y + 0.32) * 0.1045
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
				float(boat.SEA_LADDER_Z) - 0.04 + (hy + 0.32) * 0.1045)
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


func _seat_on_rim(side: String) -> void:
	var wheel: Node3D = boat.call("helm_wheel") as Node3D
	var g := _grip_node("helm", side)
	if wheel == null or g == null:
		return
	_rim_angle[side] = _pick_rim_angle(side)
	_rim_ref[side] = wheel.rotation.z
	_write_rim_grip(g, _rim_angle[side], 0.0)


func _grip_node(id: String, side: String) -> Node3D:
	var key := id + ":" + side
	if _grips.has(key) and is_instance_valid(_grips[key]):
		return _grips[key]
	var device: Node3D = null
	if id.begins_with("sw_"):
		device = boat.call("switch_lever", id) as Node3D
	elif id.begins_with("door_") and id != "door_eng":
		device = boat.call("door_node", id) as Node3D
	elif id == "door_eng":
		device = boat.call("engine_door") as Node3D
	elif id == "locker":
		device = boat.call("locker_door") as Node3D
	elif id == "fusebox":
		device = boat.call("fuse_lid") as Node3D
	elif id == "windlass":
		device = boat.call("windlass_node") as Node3D
	else:
		var accessor: String = {"helm": "helm_wheel", "telegraph": "throttle_lever",
				"radio": "radio_handset", "radar": "radar_housing",
				"sounder": "sounder_housing", "ignition": "ignition_key"}.get(id, "")
		if accessor == "" or not boat.has_method(accessor):
			return null
		device = boat.call(accessor) as Node3D
	if device == null:
		return null
	var g := Node3D.new()
	g.name = "Grip_" + side
	device.add_child(g)
	match id:
		"telegraph":
			# Fist over the knob at the top of the lever, approached from aft
			# and above; contact on the knob's surface where the palm lands.
			# The reference point is 2 cm ABOVE the knob centre: the palm's
			# contact patch is the heel of the hand, and anchoring at the centre
			# seated the fist visibly low on the shaft with the knob peeking out
			# under the fingers instead of nesting against the palm.
			var F := Vector3(0.0, -0.35, -0.94).normalized()
			var P := Vector3(0.0, -0.94, 0.35).normalized()
			g.transform = Transform3D(Basis(P.cross(F), P, F),
					Vector3(0.0, 0.33, 0.0) - P * KNOB_R)
		"radio":
			# The handset's long axis is Z: earpiece cap at -Z, mouthpiece +Z,
			# the PTT bar on -X "where your thumb lands" (boat.gd). So the palm
			# takes the +X flank — palm normal -X — fingers wrapping down across
			# the grip, knuckle line along +Z, which puts the thumb exactly on
			# the bar. Contact ON the +X surface, not at the centre; a palm at
			# the centre means fingers through the mesh.
			var F := Vector3(0.15, -0.99, 0.0).normalized()
			var P := Vector3(-1.0, 0.0, 0.0)
			g.transform = Transform3D(Basis(P.cross(F), P, F),
					Vector3(0.026, -0.004, 0.012))
		"radar":
			# Right-hand hold on the case's starboard edge: palm faces the box,
			# fingers hooking over toward its back. The node is a child of the
			# case, so as the hinge swings the hand swings welded to it.
			var F := Vector3(0.0, 0.05, -1.0).normalized()
			var P := Vector3(-1.0, 0.0, 0.0)
			g.transform = Transform3D(Basis(P.cross(F), P, F),
					Vector3(0.205, -0.05, 0.06))
		"ignition":
			# Pinch on the key's bow from above and aft. The grip is a child of
			# the KEY node, which rotates as the engine cranks — so the fingers
			# turn with the key instead of hovering while it moves.
			#
			# The wrist is deliberately COCKED: fingers drop nearly straight
			# down while the arm arrives from high aft, so the hand breaks at
			# the wrist the way a hand actually does over a key — straight-on it
			# read as a rod with fingers.
			var F := Vector3(0.05, -0.96, -0.27).normalized()
			var P := Vector3(-0.52, -0.20, 0.83).normalized()
			g.transform = Transform3D(Basis(P.cross(F), P, F),
					Vector3(0.0, 0.020, 0.052))
		_ when GESTURE_GRIP.has(id):
			# Palm onto the handle from inboard, fingers curling round it.
			var spec: Dictionary = GESTURE_GRIP[id]
			var F := Vector3(0.0, -0.35, -0.94).normalized()
			var P := Vector3(-0.94, -0.20, 0.0).normalized()
			g.transform = Transform3D(Basis(P.cross(F), P, F), spec["pos"])
		_ when id.begins_with("sw_"):
			# Fingertip on the lever knob: index leads, everything else curls
			# away — the "point" pose does the talking.
			# A toggle is pressed with a FINGERTIP, and grip() places the
			# PALM. So the anchor has to sit back along the finger axis by the
			# length of the finger — otherwise the palm lands on the knob and
			# the fingers go through the panel, which is what it was doing.
			#
			# Fingers nearly straight down and the palm turned toward the
			# player: that presents the narrow back of the hand to the eye and
			# puts the index on top of the ball, instead of laying the flat of
			# the hand across the board.
			var F := Vector3(0.0, -0.92, -0.39).normalized()
			var P := Vector3(0.0, -0.39, 0.92).normalized()
			# ball top 0.064 above the pivot, palm centre to fingertip 0.095.
			g.transform = Transform3D(Basis(P.cross(F), P, F),
					Vector3(0.0, 0.064, 0.0) - F * 0.095)
		"sounder":
			# Same hold, smaller case: edge at half of 0.34 plus a finger.
			var F := Vector3(0.0, 0.05, -1.0).normalized()
			var P := Vector3(-1.0, 0.0, 0.0)
			g.transform = Transform3D(Basis(P.cross(F), P, F),
					Vector3(0.185, -0.03, 0.05))
		_:
			g.transform = Transform3D.IDENTITY
	_grips[key] = g
	return g
