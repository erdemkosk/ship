extends Node3D
## First-person hands. WRAD ARMS by wriks (CC0, assets/wrad_arms/), driven by
## the engine's own TwoBoneIK3D plus a wrist-orientation modifier.
##
## Everything directional about the hand is MEASURED from the skeleton's rest
## pose at load — nothing about its axes is assumed:
##
##   F  finger direction   = knuckles -> fingertips, averaged
##   K  knuckle line       = index knuckle -> pinky knuckle
##   P  palm normal        = K x F (right) / F x K (left), the way the palm faces
##   palm centre           = 0.7 of the way from wrist to the knuckle centroid
##   curl axis, per joint  = chain_dir x P at that joint
##
## A grip is then stated in the world's terms — "palm faces this way, fingers
## point that way, contact lands here" — and solved into a bone basis through
## the measured frame. The IK target is the WRIST that puts the PALM on the
## contact, not the wrist on the contact; aiming the wrist at the grip point is
## what previously drove every held object seven centimetres into the hand.

const ARM_PATH := "res://assets/wrad_arms/arms.glb"

const CHAINS := {
	"R": {"root": "bicep.r", "mid": "forearm.r", "end": "wrist.r"},
	"L": {"root": "bicep.l", "mid": "forearm.l", "end": "wrist.l"},
}
const FINGERS := ["thumb", "index", "middle", "ring", "pinky"]
const THUMB := 0
const INDEX := 1

const FOREARM_METRES := 0.27
const SHOULDER_OFFSET := Vector3(0.0, -0.29, 0.16)
## Torso lean toward an out-of-reach grip. Reaching across a console is a torso
## movement; a rig that will not lean either fails to touch half the boat or
## has to stretch bones.
# How far the body will lean after a hand. Reaching across a console 0.6 m deep
# is a lean, not a stretch — a real torso gives you a good 40 cm of it, and
# without that the far column of the switchboard is simply out of range and the
# solver can only point the arm at it.
const MAX_LEAN := 0.40
const LEAN_TAU := 0.12
## Shoulders belong to a torso, not a head: they take only a fraction of the
## camera's pitch, or looking down swings the arms out of their sockets.
##
## The fraction is ASYMMETRIC. Looking down, the arms must come along or the
## camera dips below the mesh's shoulder stumps and you see the hollow ends of
## your own arms — the "gap" that flashes whenever the head bobs. Looking up,
## the arms should stay put or they hover into the sky with you.
const FOLLOW_UP := 0.15
const FOLLOW_DOWN := 0.62

## Curl per joint, radians, applied about each joint's MEASURED curl axis.
const POSES := {
	"open":  {"thumb": 0.06, "fingers": 0.10},
	"flat":  {"thumb": 0.10, "fingers": 0.04},
	"wrap":  {"thumb": 0.40, "fingers": 0.62},
	"fist":  {"thumb": 0.48, "fingers": 0.85},
	"pinch": {"thumb": 0.50, "fingers": 0.24, "index": 0.58},
	# One finger out, the rest rolled away and the thumb over them. Every
	# switch on the boat asked for this pose by name and it was not in the
	# table — set_pose falls back to "open" for anything it does not know, so
	# what actually went at the toggles was a splayed, open hand.
	"point": {"thumb": 0.62, "fingers": 0.98, "index": 0.07},
}

var camera: Camera3D
var skeleton: Skeleton3D

var _lag: Node3D
var _model: Node3D
var _ik: TwoBoneIK3D
var _wrist: WristAlign
var _targets := {}
var _poles := {}
var _end_bone := {}
var _fingers := {"R": {}, "L": {}}      # side -> finger -> PackedInt32Array
var _curl_axis := {}                    # bone idx -> local axis Vector3
var _sem_inv := {}                      # side -> Basis, semantic->bone-local inverse
var _palm_local := {}                   # side -> palm centre in bone local (scaled)
var _shoulder_local := {}
var _weight := {"R": 0.0, "L": 0.0}
var _want := {"R": 0.0, "L": 0.0}
var _pose := {"R": "open", "L": "open"}
var _pose_amt := {"R": 0.0, "L": 0.0}
var _lean := Vector3.ZERO
var _lean_want := Vector3.ZERO
var _ready_ok := false
var _measured := {}
## Palm-normal sign per side. The cross-product handedness of this rig's rest
## pose was settled empirically (see _handcal bar test), not assumed: +1 keeps
## the measured direction, -1 flips it.
var palm_sign := {"R": 1.0, "L": 1.0}


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
	_measure_hand_frames()
	_build_ik()
	_ready_ok = true
	_lag.visible = false


func is_ready() -> bool:
	return _ready_ok


## The one entry point: put this hand's PALM on `contact`, palm facing `palm_n`,
## fingers along `fingers_d`, closed into `pose`.
func grip(side: String, contact: Vector3, fingers_d: Vector3, palm_n: Vector3,
		weight := 1.0, pose := "wrap", pose_amt := -1.0) -> void:
	if not _ready_ok or not _sem_inv.has(side):
		return
	var F: Vector3 = fingers_d.normalized()
	var P: Vector3 = (palm_n - palm_n.project(F)).normalized()
	if not F.is_finite() or not P.is_finite() or P.length_squared() < 0.5:
		return
	var K: Vector3 = P.cross(F)
	var sem_world := Basis(K, P, F)
	var bone_basis: Basis = sem_world * _sem_inv[side]
	var wrist_pos: Vector3 = contact - bone_basis * _palm_local[side]
	_reach(side, Transform3D(bone_basis, wrist_pos), weight)
	# pose_amt lets a hand stay PINNED (weight 1) while its fingers open — a
	# re-grip is exactly that: the palm rides the arc, the hold releases.
	set_pose(side, pose, weight if pose_amt < 0.0 else pose_amt)


func release(side: String) -> void:
	_want[side] = 0.0
	_pose[side] = "open"


func set_pose(side: String, pose: String, amount := 1.0) -> void:
	_pose[side] = pose if POSES.has(pose) else "open"
	_pose_amt[side] = clampf(amount, 0.0, 1.0)


func set_visible_hands(on: bool) -> void:
	if _lag != null:
		_lag.visible = on and _ready_ok


func update(delta: float) -> void:
	if not _ready_ok:
		return
	for side in _want:
		_weight[side] = move_toward(_weight[side], _want[side], delta * 5.0)
	if _ik != null:
		_ik.influence = maxf(_weight["R"], _weight["L"])
	if _wrist != null:
		for side in _end_bone:
			_wrist.weights[_end_bone[side]] = _weight[side]
	var k := 1.0 - exp(-delta / LEAN_TAU)
	_lean = _lean.lerp(_lean_want.limit_length(MAX_LEAN), k)
	_lean_want = Vector3.ZERO
	_lag.position = _lean
	var fwd: Vector3 = -camera.global_basis.z
	var cam_pitch: float = asin(clampf(fwd.y, -1.0, 1.0))
	var follow: float = FOLLOW_DOWN if cam_pitch < 0.0 else FOLLOW_UP
	_lag.rotation.x = -cam_pitch * (1.0 - follow)
	# Fingers pose before the modifier pass; IK and wrist align only touch the
	# arm chain and wrist, so this survives.
	skeleton.reset_bone_poses()
	for side in _pose:
		_apply_fingers(side)
	skeleton.advance(delta)


# --- internals ---------------------------------------------------------------

func _reach(side: String, xf: Transform3D, weight: float) -> void:
	var t: Node3D = _targets[side]
	t.global_transform = xf
	_want[side] = clampf(weight, 0.0, 1.0)
	var b: int = _end_bone[side]
	_wrist.wanted[b] = (skeleton.global_transform.affine_inverse() * xf).basis

	var pole: Node3D = _poles[side]
	var out: float = 1.0 if side == "R" else -1.0
	# Elbow hint. Hung off the MIDDLE of the shoulder-to-wrist line and pulled
	# DOWN IN WORLD SPACE, plus a little outboard — which is simply where an
	# elbow goes, because it is heavy and it is on the outside of the arm.
	#
	# It used to be placed relative to the wrist along the CAMERA's down axis.
	# Looking straight ahead those agree; looking down at a console they do not
	# at all — camera-down is half world-forward, so the hint landed beyond the
	# switchboard and the solver laid the whole forearm flat across it to get
	# there. That is the arm lying over the panel like a plank.
	var sh_g: Vector3 = _lag.global_transform * _shoulder_local.get(side, SHOULDER_OFFSET)
	var mid: Vector3 = (sh_g + xf.origin) * 0.5
	pole.global_position = mid + Vector3.DOWN * 0.32 \
			+ camera.global_basis.x * (out * 0.24)

	# If the grip is past the arm, lean the torso for the difference.
	var sh_local: Vector3 = _shoulder_local.get(side, SHOULDER_OFFSET)
	var sh_world: Vector3 = _lag.global_transform * (sh_local - _lean)
	var to_grip: Vector3 = xf.origin - sh_world
	var over: float = to_grip.length() - (float(_measured.get("reach_m", 0.6)) - 0.015)
	if over > 0.0:
		var want: Vector3 = _lag.global_transform.basis.inverse() \
				* (to_grip.normalized() * minf(over, MAX_LEAN))
		if want.length() > _lean_want.length():
			_lean_want = want


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
			var axis: Vector3 = _curl_axis.get(b, Vector3.RIGHT)
			var rest: Quaternion = skeleton.get_bone_rest(b).basis.get_rotation_quaternion()
			var ang: float = base * amt * (1.0 + float(i) * 0.10)
			skeleton.set_bone_pose_rotation(b, rest * Quaternion(axis, ang))


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
		g.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	if n is MeshInstance3D:
		# The GLB's own material renders close to fullbright, which makes the
		# hands glow against a dusk wheelhouse. Plain PBR with the shipped
		# albedo lets the scene's light own them like everything else aboard.
		var mi := n as MeshInstance3D
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = load("res://assets/wrad_arms/arm_albedo_pale.png")
		# The pale albedo under this boat's warm lamps reads salmon; pull it
		# toward neutral skin — red damped hardest, since the lamps add plenty —
		# and keep the surface matte so it never goes waxy under the helm light.
		mat.albedo_color = Color(0.71, 0.67, 0.63)
		mat.roughness = 0.87
		mat.metallic = 0.0
		for i in mi.get_surface_override_material_count():
			mi.set_surface_override_material(i, mat)
	for c in n.get_children():
		_shadowless(c)


func _bone(prefix: String) -> int:
	for i in skeleton.get_bone_count():
		if String(skeleton.get_bone_name(i)).begins_with(prefix):
			return i
	return -1


func _calibrate() -> void:
	## The GLB arrives through a Sketchfab export chain (a -90 X node and a 0.01
	## scale node), so units are measured, not assumed: scale until the forearm
	## is a real forearm, then park the shoulders behind and below the eye.
	var root := _bone(CHAINS["R"]["root"])
	var mid := _bone(CHAINS["R"]["mid"])
	var end := _bone(CHAINS["R"]["end"])
	_model.scale = Vector3.ONE
	_model.position = Vector3.ZERO
	var to_lag := _lag.global_transform.affine_inverse()
	var p_root: Vector3 = to_lag * (skeleton.global_transform * skeleton.get_bone_global_rest(root).origin)
	var p_mid: Vector3 = to_lag * (skeleton.global_transform * skeleton.get_bone_global_rest(mid).origin)
	var p_end: Vector3 = to_lag * (skeleton.global_transform * skeleton.get_bone_global_rest(end).origin)
	var forearm: float = p_mid.distance_to(p_end)
	var s: float = FOREARM_METRES / maxf(forearm, 1e-6)
	_model.scale = Vector3.ONE * s
	var l_root := _bone(CHAINS["L"]["root"])
	var p_lroot: Vector3 = to_lag * (skeleton.global_transform * skeleton.get_bone_global_rest(l_root).origin)
	var centre: Vector3 = (p_root + p_lroot) * 0.5 * s
	_model.position = SHOULDER_OFFSET - centre
	# NOTE: an earlier pass narrowed the shoulders with a non-uniform scale on
	# _model. Never do that to a skinned rig driven by IK — scaling one axis
	# skews every bone frame, the solver solves in the skewed space, and the
	# wrist-align math (pure rotations) stops being true. It cost an evening:
	# the left hand quietly stopped landing on the wheel and nothing errored.
	_shoulder_local = {
		"R": p_root * s + _model.position,
		"L": p_lroot * s + _model.position,
	}
	_measured = {
		"scale": s,
		"upper_arm_m": p_root.distance_to(p_mid) * s,
		"forearm_m": FOREARM_METRES,
		"reach_m": (p_root.distance_to(p_mid) + forearm) * s,
	}


func _measure_hand_frames() -> void:
	## Derive F / K / P, the palm centre and every curl axis from the rest pose.
	## WRAD ARMS marks the palm itself with a `socket` bone, so the contact
	## point is the author's, not an estimate.
	var scale_s: float = _measured["scale"]
	for side in ["R", "L"]:
		var sfx: String = ".r" if side == "R" else ".l"
		var hb := _bone(CHAINS[side]["end"])
		_end_bone[side] = hb
		var H: Transform3D = skeleton.get_bone_global_rest(hb)
		var H_inv := H.affine_inverse()

		var knuckle := {}
		var tip := {}
		for fi in FINGERS.size():
			var chain := PackedInt32Array()
			for j in range(1, 4):
				var idx := _bone("finger_%s%d%s" % [FINGERS[fi], j, sfx])
				if idx >= 0:
					chain.append(idx)
			_fingers[side][fi] = chain
			if chain.size() >= 3:
				knuckle[fi] = H_inv * skeleton.get_bone_global_rest(chain[0]).origin
				# Last joint plus most of a phalanx again ~ the fingertip.
				var p2: Vector3 = skeleton.get_bone_global_rest(chain[1]).origin
				var p3: Vector3 = skeleton.get_bone_global_rest(chain[2]).origin
				tip[fi] = H_inv * (p3 + (p3 - p2) * 0.8)

		var kn_c := Vector3.ZERO
		var tip_c := Vector3.ZERO
		var n := 0
		for fi in range(1, 5):  # index..pinky
			if knuckle.has(fi) and tip.has(fi):
				kn_c += knuckle[fi]
				tip_c += tip[fi]
				n += 1
		kn_c /= float(n)
		tip_c /= float(n)
		var F_l: Vector3 = (tip_c - kn_c).normalized()
		var K_raw: Vector3 = (knuckle[INDEX] - knuckle[4]).normalized()  # index -> pinky
		var P_l: Vector3
		if side == "R":
			P_l = K_raw.cross(F_l).normalized()
		else:
			P_l = F_l.cross(K_raw).normalized()
		P_l *= palm_sign[side]
		var K_l: Vector3 = P_l.cross(F_l).normalized()
		_sem_inv[side] = Basis(K_l, P_l, F_l).inverse()

		var sock := _bone("socket" + sfx)
		if sock >= 0:
			_palm_local[side] = (H_inv * skeleton.get_bone_global_rest(sock).origin) * scale_s
		else:
			_palm_local[side] = kn_c * 0.70 * scale_s

		var P_rig: Vector3 = H.basis * P_l
		for fi: int in _fingers[side]:
			var chain: PackedInt32Array = _fingers[side][fi]
			for i in chain.size():
				var b: int = chain[i]
				var here: Vector3 = skeleton.get_bone_global_rest(b).origin
				var next: Vector3
				if i + 1 < chain.size():
					next = skeleton.get_bone_global_rest(chain[i + 1]).origin
				elif tip.has(fi):
					next = H * tip[fi]
				else:
					continue
				var d: Vector3 = (next - here).normalized()
				var axis_w: Vector3 = d.cross(P_rig).normalized()
				_curl_axis[b] = (skeleton.get_bone_global_rest(b).basis.inverse()
						* axis_w).normalized()


func _build_ik() -> void:
	_ik = TwoBoneIK3D.new()
	_ik.name = "ArmIK"
	skeleton.add_child(_ik)
	_ik.set_setting_count(2)
	var i := 0
	for side in ["R", "L"]:
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
		_ik.set_root_bone(i, _bone(CHAINS[side]["root"]))
		_ik.set_middle_bone(i, _bone(CHAINS[side]["mid"]))
		_ik.set_end_bone(i, _end_bone[side])
		_ik.set_target_node(i, NodePath(t.name))
		_ik.set_pole_node(i, NodePath(pole.name))
		_ik.set_extend_end_bone(i, false)
		_ik.set_use_virtual_end(i, false)
		i += 1
	_wrist = WristAlign.new()
	_wrist.name = "WristAlign"
	skeleton.add_child(_wrist)
	_wrist.active = true
	for side in CHAINS:
		var sfx: String = ".r" if side == "R" else ".l"
		var t0 := _bone("forearm.Twist0" + sfx)
		var t1 := _bone("forearm.Twist1" + sfx)
		if t0 >= 0 and t1 >= 0:
			_wrist.twists[_end_bone[side]] = {
				"parent": _bone(CHAINS[side]["mid"]),
				"driven": [[t0, 0.30], [t1, 0.65]],
			}
	_ik.influence = 0.0
	_ik.active = true
	# Drive the modifier stack ourselves: place targets, then solve, once, in
	# that order. On IDLE a rig with no AnimationPlayer never dirties its pose
	# and the solver silently never runs.
	skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL


func set_palm_sign(side: String, sign_v: float) -> void:
	palm_sign[side] = sign_v
	_measure_hand_frames()


func probe_hand(side: String) -> Dictionary:
	## Mesh-free grip audit, in world space, from the SOLVED wrist:
	##   back_dot   (knuckle centroid - palm) . palm_normal  -> must be < 0
	##   thumb_dot  (thumb knuckle - palm)    . K            -> R < 0, L > 0
	##   curl_deg   actual bend across the index chain       -> wrap ~> 60 deg
	var b: int = _end_bone[side]
	if not _wrist.solved.has(b):
		return {}
	var W: Transform3D = skeleton.global_transform * (_wrist.solved[b] as Transform3D)
	var H_inv: Transform3D = skeleton.get_bone_global_rest(b).affine_inverse()
	var sfx: String = ".r" if side == "R" else ".l"
	var s_m: float = _measured["scale"]

	var sem: Basis = W.basis * _sem_inv[side].inverse()  # columns K,P,F in world
	var palm_w: Vector3 = W * _palm_local[side]
	var kn := Vector3.ZERO
	for fi in range(1, 5):
		kn += W * ((H_inv * skeleton.get_bone_global_rest(
				_fingers[side][fi][0]).origin) * s_m)
	kn /= 4.0
	var th: Vector3 = W * ((H_inv * skeleton.get_bone_global_rest(
			_fingers[side][THUMB][0]).origin) * s_m)

	var chain: PackedInt32Array = _fingers[side][INDEX]
	var q1: Quaternion = skeleton.get_bone_pose_rotation(chain[1])
	var r1: Quaternion = skeleton.get_bone_rest(chain[1]).basis.get_rotation_quaternion()
	return {
		"back_dot": (kn - palm_w).normalized().dot(sem.y),
		"thumb_dot": (th - palm_w).normalized().dot(sem.x),
		"curl_deg": rad_to_deg(r1.angle_to(q1)),
	}


func measurements() -> Dictionary:
	return _measured


func lean() -> Vector3:
	return _lean


func shoulder_global(side: String) -> Vector3:
	var b := _bone(CHAINS[side]["root"])
	return (skeleton.global_transform * skeleton.get_bone_global_rest(b)).origin


func wrist_global(side: String) -> Transform3D:
	## Read from the wrist modifier: outside a modification pass the skeleton
	## reports the PRE-modifier pose, which makes a working solver look broken.
	var b: int = _end_bone.get(side, -1)
	if b < 0 or not _wrist.solved.has(b):
		return Transform3D.IDENTITY
	return skeleton.global_transform * (_wrist.solved[b] as Transform3D)
