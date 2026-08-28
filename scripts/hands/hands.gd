extends Node3D
## Drives the hands from what the player is actually holding.
##
## Drop-in for the interface boat_camera.gd already calls: setup / set_active /
## notify_use / inspecting_id / update, plus a `boat` property.
##
## The old rig answered "what should the hands do?" with a set of canned poses
## and, for anything it could not pose, by cloning the device and flying it at
## the lens. This answers it with claims instead: each hand claims at most one
## interactable, the claim resolves to a grip node parented to that device, and
## the hand is sent there. Nothing is cloned, nothing is reparented to the
## camera, and a device that moves takes its grip — and therefore the hand —
## with it.
##
## Two claims can be live at once, which is the whole reason the hands are
## tracked separately: left on the wheel, right on the throttle is how the boat
## is driven, and it is only expressible if the arms are not one animation.

const RIG := preload("res://scripts/hands/hand_rig.gd")

## Wheel rotation, in radians, that a hand will ride round before letting go and
## taking a fresh hold. A helmsman re-grips; they do not wind their wrist up.
const REGRIP_ARC := 1.15
const REGRIP_TIME := 0.26

var boat: Node3D
var rig: Node3D

var _cam: Camera3D
var _active := false
var _claim := {"L": "", "R": ""}
var _grips := {}          # "id:side" -> Node3D, child of the device
var _rim_ref := {}        # side -> wheel rotation when this hold was taken
var _regrip := {"L": 0.0, "R": 0.0}
var _inspect := ""


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
	if not _active:
		_claim = {"L": "", "R": ""}
		_inspect = ""


func inspecting_id() -> String:
	return _inspect


func notify_use(id: String) -> void:
	## E was pressed on something. Devices that are held rather than poked keep
	## the claim until E is pressed again.
	if not GripMap.has(id):
		return
	var entry := GripMap.entry(id)
	var hands: Dictionary = entry.get("hands", {})
	for side: String in hands:
		if _claim[side] == id:
			_release(side)
		else:
			_take(side, id)
	_inspect = id if _claim["R"] == id or _claim["L"] == id else ""


func update(delta: float, p_boat: Node3D, engaged: String, walking: float,
		swimming: bool) -> void:
	boat = p_boat
	if rig == null or not rig.is_ready():
		return
	if not _active or swimming or boat == null:
		rig.release("L")
		rig.release("R")
		rig.set_visible_hands(false)
		rig.update(delta)
		return
	rig.set_visible_hands(true)

	# Standing at the wheel is a two-handed job by default: the left steers, the
	# right stays on the telegraph. Neither is a mode — they are two claims.
	if engaged == "helm":
		if _claim["L"] == "":
			_take("L", "helm")
		if _claim["R"] == "":
			_take("R", "telegraph")
	elif engaged == "" and _inspect == "":
		if _claim["L"] == "helm":
			_release("L")
		if _claim["R"] == "telegraph":
			_release("R")

	for side: String in _claim:
		_drive(side, delta)
	rig.update(delta)


# --- claims ------------------------------------------------------------------

func _take(side: String, id: String) -> void:
	if not GripMap.has(id):
		return
	var entry := GripMap.entry(id)
	if not (entry.get("hands", {}) as Dictionary).has(side):
		return
	_claim[side] = id
	_regrip[side] = 0.0
	var g := _grip_node(id, side)
	if g != null and bool((entry["hands"][side] as Dictionary).get("on_rim", false)):
		_seat_on_rim(side, g)


func _release(side: String) -> void:
	_claim[side] = ""
	if rig != null:
		rig.release(side)


func _drive(side: String, delta: float) -> void:
	var id: String = _claim[side]
	if id == "":
		return
	var entry := GripMap.entry(id)
	var spec: Dictionary = entry["hands"][side]
	var g := _grip_node(id, side)
	if g == null:
		_release(side)
		return

	var w := 1.0
	if bool(spec.get("on_rim", false)):
		w = _ride_rim(side, g, delta)
	rig.reach(side, g.global_transform, w)
	rig.set_pose(side, str(spec.get("pose", "wrap")), w)


func _ride_rim(side: String, g: Node3D, delta: float) -> float:
	## Follow the wheel round, then let go and take a fresh hold.
	##
	## The grip is a child of the wheel, so while it is held the hand tracks the
	## rim exactly — no slip, no matching of two rotations. What has to be
	## handled is the limit of a wrist: past about a radian the arm is wrung out,
	## so the hold is dropped, the hand slides to a fresh angle, and it closes
	## again. The release is what makes it read as re-gripping instead of the
	## hand rubbering round the wheel.
	var wheel: Node3D = boat.call("helm_wheel") as Node3D
	if wheel == null:
		return 1.0
	if _regrip[side] > 0.0:
		_regrip[side] = maxf(_regrip[side] - delta, 0.0)
		if _regrip[side] <= REGRIP_TIME * 0.5 and not _rim_ref.has(side + "_done"):
			_seat_on_rim(side, g)
			_rim_ref[side + "_done"] = true
		if _regrip[side] <= 0.0:
			_rim_ref.erase(side + "_done")
		# Open the hand through the middle of the swap and close it again.
		var u: float = 1.0 - absf(_regrip[side] / REGRIP_TIME - 0.5) * 2.0
		return clampf(1.0 - u, 0.15, 1.0)
	var turned: float = absf(wrapf(wheel.rotation.z - float(_rim_ref.get(side, 0.0)),
			-PI, PI))
	if turned > REGRIP_ARC:
		_regrip[side] = REGRIP_TIME
	return 1.0


func _seat_on_rim(side: String, g: Node3D) -> void:
	## Pick the point on the rim the hand can most comfortably take: the one
	## nearest a spot just in front of that shoulder. Re-picked on every fresh
	## hold, so a wheel that has been spun still gets grabbed somewhere sane.
	var wheel: Node3D = boat.call("helm_wheel") as Node3D
	if wheel == null:
		return
	var sh: Vector3 = rig.shoulder_global(side)
	var aim: Vector3 = sh + (-_cam.global_basis.z) * 0.34 - _cam.global_basis.y * 0.12
	var best := 0.0
	var best_d := 1e9
	for i in 24:
		var a := float(i) / 24.0 * TAU
		var local := Vector3(cos(a), sin(a), 0.0) * GripMap.HELM_RIM
		var d: float = aim.distance_to(wheel.global_transform * local)
		if d < best_d:
			best_d = d
			best = a
	# Palm wraps the rim: the hand's own up axis points along the tangent.
	g.transform = Transform3D(
			Basis(Vector3(0.0, 0.0, 1.0), a_tangent(best)),
			Vector3(cos(best), sin(best), 0.0) * GripMap.HELM_RIM)
	_rim_ref[side] = wheel.rotation.z


func a_tangent(angle: float) -> float:
	return angle + PI * 0.5


func _grip_node(id: String, side: String) -> Node3D:
	var key := id + ":" + side
	if _grips.has(key) and is_instance_valid(_grips[key]):
		return _grips[key]
	var entry := GripMap.entry(id)
	var accessor := str(entry.get("node", ""))
	if accessor == "" or not boat.has_method(accessor):
		return null
	var device: Node3D = boat.call(accessor) as Node3D
	if device == null:
		return null
	var g := Node3D.new()
	g.name = "Grip_" + side
	# Parented to the device on purpose: this is what welds the hand to a thing
	# that moves. Nothing here has to track the device — it IS the device.
	device.add_child(g)
	g.transform = GripMap.local_transform(entry["hands"][side])
	_grips[key] = g
	return g
