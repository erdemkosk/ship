extends Node3D
## First-person hands. BAMEN FPS rig (CC-BY-4.0), driven by the engine's own IK.
##
## Three rules, each one a thing the previous rig got wrong:
##
## 1. Never rebuild a bone basis. Godot 4.6+ ships TwoBoneIK3D and an arm is
##    exactly the two-bone case it solves. We move a target node; the solver
##    does the rest, in the rig's own axes, so the bind pose survives.
##
## 2. The hand goes to the object. The object never comes to the hand, and it is
##    certainly never cloned, made top_level and flown at the lens — which is
##    what "the radar screen slides into your face" was.
##
## 3. The grip point is a CHILD of the thing being gripped. When a device swings
##    on its bracket or slides on its rail, its grip node moves with it, the IK
##    target follows, and the hand is welded to it by construction rather than by
##    two animations agreeing. That is what stops it looking off.

const ARM_PATH := "res://assets/fps_arms/fps_arms.glb"

## Bones that make up each arm. root -> middle -> end is what TwoBoneIK3D wants.
const CHAINS := {
	"R": {"root": "Arm_1.R_021", "mid": "Arm_2.R_022", "end": "Hand_1.R_023"},
	"L": {"root": "Arm_1.L_02", "mid": "Arm_2.L_03", "end": "Hand_1.L_04"},
}

## Where the shoulders should sit relative to the lens, in metres. Not a guess:
## the rig is measured on load and scaled so its own forearm length matches a
## real one, then offset so the shoulders land behind and below the eye.
const FOREARM_METRES := 0.26

## Finger poses, as a curl per joint in radians. Small angles on the bone's own
## local X only — the previous rig drove 0.85 rad per joint on a guessed axis
## and folded the hands inside out. Index 0 is the knuckle, and each joint
## further out curls slightly more, which is what a real finger does.
const POSES := {
	"open":  {"thumb": 0.05, "fingers": 0.08},
	"flat":  {"thumb": 0.10, "fingers": 0.05},
	"wrap":  {"thumb": 0.32, "fingers": 0.52},
	"fist":  {"thumb": 0.42, "fingers": 0.78},
	"pinch": {"thumb": 0.46, "fingers": 0.20, "index": 0.55},
	"point": {"thumb": 0.30, "fingers": 0.72, "index": 0.04},
}
## Finger_1 is the thumb and Finger_2 the index in this rig's naming.
const THUMB := 1
const INDEX := 2
const SHOULDER_OFFSET := Vector3(0.0, -0.22, 0.10)
## How far the shoulders may travel toward something out of arm's reach.
##
## An arm is 0.63 m and a wheelhouse is not laid out to that number — reaching a
## throttle across a console is a torso movement, not an arm movement, and a rig
## that refuses to lean either cannot touch half the boat or has to cheat by
## stretching bones. Leaning the shoulder anchor is the honest version and, in
## first person, is exactly what a lean looks like: the view stays put and the
## arms come from further over.
const MAX_LEAN := 0.26
const LEAN_TAU := 0.12
## How much of the camera's pitch the shoulders take. Shoulders belong to a
## torso, not to a head: look down thirty-five degrees and a rig parented
## straight to the lens swings its shoulder anchor down and forward with it, so
## the arms start coming out of the chest and nothing they hold looks held. A
## real neck passes on a little of it and no more.
const SHOULDER_PITCH_FOLLOW := 0.25

var camera: Camera3D
var skeleton: Skeleton3D

var _lag: Node3D
var _model: Node3D
var _ik: TwoBoneIK3D
var _wrist: WristAlign
var _end_bone := {}
var _targets := {}   # side -> Node3D, world-space wrist goal
var _poles := {}     # side -> Node3D, elbow hint
var _idx := {}       # side -> IK setting index
var _weight := {"R": 0.0, "L": 0.0}
var _want := {"R": 0.0, "L": 0.0}
var _ready_ok := false
var _measured := {}
var _lean := Vector3.ZERO
var _lean_want := Vector3.ZERO
var _shoulder_local := {}
var _fingers := {"R": {}, "L": {}}
var _pose := {"R": "open", "L": "open"}
var _pose_amt := {"R": 0.0, "L": 0.0}


func setup(cam: Camera3D) -> void:
	camera = cam
	_lag = Node3D.new()
	_lag.name = "HandsLag"
	cam.add_child(_lag)

	_model = _load_glb()
	if _model == null:
		return
	_lag.add_child(_model)
	skeleton = _find_skeleton(_model)
	if skeleton == null:
		push_error("hand_rig: no Skeleton3D in %s" % ARM_PATH)
		return

	_shadowless(_model)
	_calibrate()
	_build_ik()
	_ready_ok = true
	_lag.visible = false


func is_ready() -> bool:
	return _ready_ok


## Put a wrist on a world transform. `weight` 0..1 blends the IK in, so a hand
## can leave a control without snapping.
func reach(side: String, xf: Transform3D, weight := 1.0) -> void:
	if not _ready_ok or not _targets.has(side):
		return
	var t: Node3D = _targets[side]
	t.global_transform = xf
	_want[side] = clampf(weight, 0.0, 1.0)
	# Hand the same frame to the wrist aligner, in skeleton space, so the palm
	# arrives facing the way the grip asked for rather than however the solver
	# happened to leave it.
	var b: int = _end_bone.get(side, -1)
	if b >= 0:
		var in_skel: Transform3D = skeleton.global_transform.affine_inverse() * xf
		_wrist.wanted[b] = in_skel.basis
		_wrist.weights[b] = _weight[side]
	# Elbow hint: down and outboard of the line from shoulder to wrist. Without
	# a pole the solver is free to pick any point on the circle of valid elbow
	# positions, and it will happily choose one that puts the elbow through the
	# chest.
	var pole: Node3D = _poles[side]
	var out: float = 1.0 if side == "R" else -1.0
	pole.global_position = xf.origin + camera.global_basis * Vector3(out * 0.42, -0.55, 0.20)

	# If the grip is past the end of the arm, ask the torso for the difference.
	# The largest single deficit wins rather than the sum, so two grips on
	# opposite sides do not cancel each other out into standing still.
	var sh_local: Vector3 = _shoulder_local.get(side, SHOULDER_OFFSET)
	var sh_world: Vector3 = _lag.global_transform * (sh_local - _lean)
	var to_grip: Vector3 = xf.origin - sh_world
	var over: float = to_grip.length() - (float(_measured.get("reach_m", 0.6)) - 0.06)
	if over > 0.0:
		var want: Vector3 = _lag.global_transform.basis.inverse() \
				* (to_grip.normalized() * minf(over, MAX_LEAN))
		if want.length() > _lean_want.length():
			_lean_want = want


func release(side: String) -> void:
	_want[side] = 0.0
	_pose[side] = "open"


## Close a hand into a named pose. `amount` lets a grip tighten as the hand
## arrives instead of snapping shut in mid-air.
func set_pose(side: String, pose: String, amount := 1.0) -> void:
	_pose[side] = pose if POSES.has(pose) else "open"
	_pose_amt[side] = clampf(amount, 0.0, 1.0)


func _apply_fingers(side: String) -> void:
	var spec: Dictionary = POSES[_pose[side]]
	var amt: float = _pose_amt[side]
	for f: int in _fingers[side]:
		var chain: PackedInt32Array = _fingers[side][f]
		var base: float = spec.get("thumb", 0.0) if f == THUMB else spec.get("fingers", 0.0)
		if f == INDEX and spec.has("index"):
			base = spec["index"]
		for i in chain.size():
			var b: int = chain[i]
			var rest: Quaternion = skeleton.get_bone_rest(b).basis.get_rotation_quaternion()
			var ang: float = base * amt * (1.0 + float(i) * 0.10)
			skeleton.set_bone_pose_rotation(b, rest * Quaternion(Vector3.RIGHT, ang))


func set_visible_hands(on: bool) -> void:
	if _lag != null:
		_lag.visible = on and _ready_ok


func update(delta: float) -> void:
	if not _ready_ok:
		return
	# Blend each arm's IK in and out rather than switching it, so releasing a
	# control lets the hand drift back to rest instead of teleporting.
	for side in _want:
		_weight[side] = move_toward(_weight[side], _want[side], delta * 5.0)
	# Lean eases both ways; snapping the shoulders is worse than not leaning.
	var k := 1.0 - exp(-delta / LEAN_TAU)
	_lean = _lean.lerp(_lean_want.limit_length(MAX_LEAN), k)
	_lean_want = Vector3.ZERO
	_lag.position = _lean
	# Undo most of the camera's pitch so the shoulders stay level with the deck.
	var fwd: Vector3 = -camera.global_basis.z
	var cam_pitch: float = asin(clampf(fwd.y, -1.0, 1.0))
	_lag.rotation.x = -cam_pitch * (1.0 - SHOULDER_PITCH_FOLLOW)
	if _ik != null:
		_ik.influence = maxf(_weight["R"], _weight["L"])
	if _wrist != null:
		for side in _end_bone:
			var b: int = _end_bone[side]
			if b >= 0:
				_wrist.weights[b] = _weight[side]
	# Fingers are posed before the modifier pass. The IK and the wrist aligner
	# only touch the arm chain and the wrist, so what is set here survives.
	for side in _pose:
		_pose_amt[side] = move_toward(_pose_amt[side],
				1.0 if _want[side] > 0.5 else 0.0, delta * 6.0)
		_apply_fingers(side)
	skeleton.advance(delta)


# --- setup -------------------------------------------------------------------

func _load_glb() -> Node3D:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(ARM_PATH, st) != OK:
		push_error("hand_rig: cannot read %s" % ARM_PATH)
		return null
	return doc.generate_scene(st)


func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n as Skeleton3D
	for c in n.get_children():
		var s := _find_skeleton(c)
		if s != null:
			return s
	return null


func _shadowless(n: Node) -> void:
	if n is GeometryInstance3D:
		var g := n as GeometryInstance3D
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# The hands live a few centimetres from the lens; letting the world's
		# reflection probes and GI touch them just makes them swim.
		g.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	for c in n.get_children():
		_shadowless(c)


func _calibrate() -> void:
	## The GLB arrives through a Sketchfab export chain — a -90 degree X node and
	## a 0.01 scale node — so nothing about its units can be assumed. Measure the
	## forearm in the model's own space, scale until it is a real forearm, then
	## park the shoulders relative to the lens.
	var root := skeleton.find_bone(CHAINS["R"]["root"])
	var mid := skeleton.find_bone(CHAINS["R"]["mid"])
	var end := skeleton.find_bone(CHAINS["R"]["end"])
	if root < 0 or mid < 0 or end < 0:
		push_error("hand_rig: right arm bones not found")
		return

	_model.scale = Vector3.ONE
	_model.position = Vector3.ZERO
	var to_lag := _lag.global_transform.affine_inverse()
	var p_mid: Vector3 = to_lag * (skeleton.global_transform * skeleton.get_bone_global_rest(mid).origin)
	var p_end: Vector3 = to_lag * (skeleton.global_transform * skeleton.get_bone_global_rest(end).origin)
	var p_root: Vector3 = to_lag * (skeleton.global_transform * skeleton.get_bone_global_rest(root).origin)
	var forearm: float = p_mid.distance_to(p_end)
	var s: float = FOREARM_METRES / maxf(forearm, 1e-6)
	_model.scale = Vector3.ONE * s

	# Shoulders behind and below the eye. Mid-point of the two shoulders so the
	# rig is centred on the lens rather than on whichever arm was measured.
	var l_root := skeleton.find_bone(CHAINS["L"]["root"])
	var p_lroot: Vector3 = p_root
	if l_root >= 0:
		p_lroot = to_lag * (skeleton.global_transform * skeleton.get_bone_global_rest(l_root).origin)
	var centre: Vector3 = (p_root + p_lroot) * 0.5 * s
	_model.position = SHOULDER_OFFSET - centre

	# Shoulder positions in lag space, needed every frame to decide whether a
	# grip is out of reach and which way to lean for it.
	_shoulder_local = {
		"R": p_root * s + _model.position,
		"L": p_lroot * s + _model.position,
	}
	_measured = {
		"forearm_raw": forearm,
		"scale": s,
		"upper_arm_m": p_root.distance_to(p_mid) * s,
		"forearm_m": FOREARM_METRES,
		"reach_m": (p_root.distance_to(p_mid) + forearm) * s,
		"shoulder_local": SHOULDER_OFFSET,
	}


func measurements() -> Dictionary:
	return _measured


func _build_ik() -> void:
	_ik = TwoBoneIK3D.new()
	_ik.name = "ArmIK"
	skeleton.add_child(_ik)
	_ik.set_setting_count(2)
	var i := 0
	for side in ["R", "L"]:
		# Targets live under the modifier itself so the NodePath is a single
		# name. Parenting them elsewhere makes the path climb the tree and it
		# silently breaks the moment anything is reparented.
		var t := Node3D.new()
		t.name = "IKTarget" + side
		t.top_level = true
		_ik.add_child(t)
		var pole := Node3D.new()
		pole.name = "IKPole" + side
		pole.top_level = true
		_ik.add_child(pole)
		_targets[side] = t
		_poles[side] = pole
		_idx[side] = i
		_ik.set_root_bone_name(i, CHAINS[side]["root"])
		_ik.set_middle_bone_name(i, CHAINS[side]["mid"])
		_ik.set_end_bone_name(i, CHAINS[side]["end"])
		_ik.set_target_node(i, NodePath(t.name))
		_ik.set_pole_node(i, NodePath(pole.name))
		# The effector is the WRIST, which is the end bone's own origin. Left
		# extended, the solver aims the end bone's tip instead and every reach
		# lands a hand-length short of what it was told.
		_ik.set_extend_end_bone(i, false)
		_ik.set_use_virtual_end(i, false)
		i += 1
	for side in CHAINS:
		_end_bone[side] = skeleton.find_bone(CHAINS[side]["end"])
		for f in range(1, 6):
			var chain := PackedInt32Array()
			var last: int = 4 if f == THUMB else 3
			for j in range(1, last + 1):
				var idx := -1
				for b in skeleton.get_bone_count():
					if String(skeleton.get_bone_name(b)).begins_with(
							"Finger_%d_%d.%s" % [f, j, side]):
						idx = b
						break
				if idx >= 0:
					chain.append(idx)
			_fingers[side][f] = chain
	# Second modifier, added AFTER the IK so it runs after it. Child order is
	# execution order; putting it first would align a wrist the solver then moves.
	_wrist = WristAlign.new()
	_wrist.name = "WristAlign"
	skeleton.add_child(_wrist)
	_wrist.active = true
	_wrist.influence = 1.0

	_ik.influence = 0.0
	_ik.active = true
	# Drive the modifier stack ourselves. On IDLE the skeleton only runs its
	# modifiers when something has already marked its pose dirty, and a rig with
	# no AnimationPlayer never does — the solver was configured perfectly and
	# silently never ran. MANUAL plus an explicit advance() also gives the right
	# ordering for first-person hands: place the targets, then solve, once, in
	# that order, every frame.
	skeleton.modifier_callback_mode_process = \
			Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	skeleton.show_rest_only = false


func shoulder_global(side: String) -> Vector3:
	var b := skeleton.find_bone(CHAINS[side]["root"])
	if b < 0:
		return Vector3.ZERO
	# The shoulder is upstream of the solved chain, so its rest pose is its pose.
	return (skeleton.global_transform * skeleton.get_bone_global_rest(b)).origin


func lean() -> Vector3:
	return _lean


func wrist_global(side: String) -> Transform3D:
	## Where the wrist actually ended up, in world space.
	##
	## Read from the wrist modifier, NOT from the skeleton. Outside a
	## modification pass Skeleton3D returns the pose as it was BEFORE the
	## modifiers ran, so asking it directly reports the bind pose and makes a
	## working solver look broken — which cost an afternoon to find out.
	var b: int = _end_bone.get(side, -1)
	if b < 0 or not _wrist.solved.has(b):
		return Transform3D.IDENTITY
	return skeleton.global_transform * (_wrist.solved[b] as Transform3D)
