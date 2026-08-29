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
## The dive watch on the left wrist: its face material (the scripts feed it
## time / depth / pressure every frame) and its mount.
var _watch_mat: ShaderMaterial
## Kept so the standoff can be swept at runtime and CHOSEN off screenshots,
## which is the only thing that has actually worked on this arm.
var _watch_holder: Node3D
var _watch_head: Node3D
## Strap links, kept with their angles so the band's radius can be swept and
## CHOSEN off screenshots — the same way the standoff and the tilt were.
var _strap: Array = []
var _strap_geom := {}
## 13 degrees, chosen off a six-frame sweep from 0 to 25: at 0 the arm still
## cuts the bottom-left of the display, past 20 the case starts lifting off
## the wrist. Re-choose it with --watch-sweep if the arm or the pose changes.
var _watch_tilt := 0.227
## Across-arm radius as a fraction of the dorsal one.
const STRAP_RATIO := 1.18
## What the band has closed to by the time it is under the wrist, and what it
## leaves the case at. The front is over 1.0 — the caseback plane is where the
## case sits, and the case is stood off far enough to clear a wrist that
## bulges when the pose bends it; the links either side of it have to clear the
## same bulge or they bury themselves in the skin beside the watch.
var strap_tight := 0.66
const STRAP_FRONT := 1.12
@export var watch_axes_debug := false
var _watch_n := Vector3.UP
var _watch_ax := Vector3.FORWARD
var _watch_invs := 1.0
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
	_build_watch()
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


func _strap_close(a: float) -> float:
	## How much the band has tightened by the time it has wrapped `a` radians
	## from the case. 1.0 where it leaves the lugs, STRAP_TIGHT under the arm.
	var t: float = clampf((a - 0.70) / 2.35, 0.0, 1.0)
	return lerpf(STRAP_FRONT, strap_tight, t * t * (3.0 - 2.0 * t))


func set_arm_visible(on: bool) -> void:
	## Hide the SKIN but keep the watch. Shooting the same frame twice, once
	## each way, is a penetration test: anything that shows only when the arm
	## is gone is inside the arm. Nothing else has settled this reliably —
	## every judgement made from a single view was wrong about something.
	if _watch_holder == null:
		return
	for node in _walk_children(_model):
		if not (node is MeshInstance3D):
			continue
		# Walk UP to see whether this belongs to the watch. Checking only the
		# immediate parent's name hid the watch along with the arm, because
		# every one of its parts hangs off an unnamed Node3D.
		var anc: Node = node
		var mine := false
		while anc != null:
			if anc == _watch_holder:
				mine = true
				break
			anc = anc.get_parent()
		if not mine:
			(node as MeshInstance3D).visible = on


func set_strap_tight(v: float) -> void:
	## Now sweeps the PALM OFFSET, which is the parameter that actually
	## decides whether the band clears the arm.
	if _watch_holder == null:
		return
	var rn: float = float(_strap_geom.get("rn0", 0.024)) + v
	_strap_geom["rn"] = rn
	_strap_geom["axis"] = float(_strap_geom.get("axis0", -0.030)) - v
	set_strap_scale(1.0)


func set_strap_scale(k: float) -> void:
	var rn: float = float(_strap_geom.get("rn", 0.024)) * k
	var ra: float = rn * float(_strap_geom.get("ratio", 0.86))
	var az: float = float(_strap_geom.get("axis", -0.030))
	for e in _strap:
		var a: float = e[1]
		var r: float = rn * ra / sqrt(pow(ra * cos(a), 2.0) + pow(rn * sin(a), 2.0))
		(e[0] as Node3D).position = Vector3(0.0, sin(a) * r, az + cos(a) * r)


func _flat(c: Color) -> ShaderMaterial:
	## Flat, unmistakable colour on the same shader, so the debug material can
	## stand in for a real one without changing any types.
	var m := _watch_mtl(c, c, Vector3(1, 1, 1), 1.0, 0.0, 0.0, 0.0)
	return m


func _watch_mtl(base: Color, worn_c: Color, half: Vector3, rough: float,
		metal: float, wear: float, rib: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/watch_body.gdshader")
	m.set_shader_parameter("base_color", base)
	m.set_shader_parameter("worn_color", worn_c)
	m.set_shader_parameter("half_size", half)
	m.set_shader_parameter("rough_base", rough)
	m.set_shader_parameter("metal_base", metal)
	m.set_shader_parameter("wear", wear)
	m.set_shader_parameter("rib", rib)
	return m


func set_watch_tilt(v: float) -> void:
	_watch_tilt = v
	if _watch_head != null:
		_watch_head.rotation.y = v


func set_watch_standoff(v: float) -> void:
	if _watch_holder != null:
		_watch_holder.position = (_watch_n * v - _watch_ax * 0.032) * _watch_invs


func set_watch_display(h: float, m: float, t: float, depth: float,
		press: float, glow: float) -> void:
	if _watch_mat == null:
		return
	_watch_mat.set_shader_parameter("hours", h)
	_watch_mat.set_shader_parameter("minutes", m)
	_watch_mat.set_shader_parameter("tsec", t)
	_watch_mat.set_shader_parameter("depth_m", depth)
	_watch_mat.set_shader_parameter("press_bar", press)
	_watch_mat.set_shader_parameter("glow", glow)


func _build_watch() -> void:
	## A digital dive watch, strapped to the LEFT wrist for good: it is part of
	## the arm, not a viewmodel, so it rides every gesture — on the wheel, on
	## the ladder rungs, raised to the face when B asks for it.
	##
	## Mounted from the MEASURED hand frame, nothing assumed: the back of the
	## wrist is minus the palm normal, "12 o'clock" runs up the forearm, and
	## the display's reading direction is the finger axis — hold your own arm
	## across your chest and that is exactly how a watch face sits.
	if skeleton == null or not _sem_inv.has("L"):
		return
	var ba := BoneAttachment3D.new()
	ba.bone_name = str(CHAINS["L"]["end"])
	skeleton.add_child(ba)
	# Columns of the measured semantic basis, in wrist-bone local space.
	var sem: Basis = (_sem_inv["L"] as Basis).inverse()
	var F: Vector3 = sem.z.normalized()          # wrist -> fingers
	var n: Vector3 = (-sem.y).normalized()       # back of the wrist
	# The display reads ALONG the arm, elbow toward hand. The proof is the
	# gesture everyone makes: forearm horizontal across the chest — and the
	# text on a real watch sits level, reading with the arm. (This axis went
	# across-arm for one revision, "fixed" against a pose that held the arm
	# vertically; the pose was the thing that was wrong.)
	#
	# And that is ALL the orientation there is. An earlier pass added a roll
	# trim and a wedge so the face met the raised eye squarely — and it read
	# instantly as wrong, because a watch does not look at you. It is strapped
	# flat to the wrist and goes where the wrist goes; whatever angle your
	# forearm presents is the angle you read it at.
	# Along the arm, in the plane of the wrist's own back.
	#
	# An attempt to use the true elbow-to-wrist axis instead was reverted, and
	# the sweep is why: deriving `arm_ax` from the forearm bone and then
	# squaring the dorsal normal against it rotated the mount round the wrist,
	# so the case sat on the FLANK. Photographed at six standoffs from 22 to
	# 32 mm, the arm cut the same diagonal across the display in every one —
	# distance cannot fix a direction. The finger axis, projected into the
	# dorsal plane, is what puts it on the back of the wrist where it belongs.
	var X: Vector3 = (F - F.project(n)).normalized()
	var arm_ax: Vector3 = X
	var Y: Vector3 = n.cross(X).normalized()
	# Bone space is not metres; _measured.scale is the factor the palm-contact
	# maths already trusts, so the watch is authored in metres and converted
	# through the same number.
	var inv_s: float = 1.0 / maxf(float(_measured.get("scale", 1.0)), 1e-6)
	# How far out to stand it off the bone — MEASURED off the arm mesh, not
	# guessed. A fixed 2.05 cm was right for exactly one wrist rotation; the
	# moment the reading pose changed, the case was sitting inside the
	# forearm. Nothing else in this rig assumes a dimension it could measure,
	# and the thickness of an arm is no different: find the skin, and put the
	# caseback on it.
	# Measured on this rig: skin about 21 mm out from the wrist bone, so the
	# caseback sits a millimetre and a half proud of the arm. The old fixed
	# 20.5 put the caseback SEVEN MILLIMETRES inside it — invisible in the
	# pose it was tuned against, and buried the moment the wrist turned.
	var across: Vector3 = arm_ax.cross(n).normalized()
	# Part identification: every piece of the watch in its own flat colour, so
	# a bad-looking fragment can be NAMED off a screenshot instead of guessed
	# at. case=blue  bezel=yellow  screen=grey  strap=red  keeper=green
	if watch_axes_debug:
		pass
	# How far off the bone the case stands. A CONSTANT, verified against
	# screenshots, and that is a deliberate retreat from measuring it.
	#
	# Measuring was tried properly: gather the arm vertices in the wrist bone's
	# rest frame, take the support function of the cross-section, stand the
	# caseback on it. It cannot work on this asset. There are 55 vertices in
	# the whole strip of forearm the watch covers, so the rest-pose hull is a
	# crude polygon; and the pose the watch is read in extends the wrist far
	# enough that the skinned silhouette leaves that hull anyway. Three
	# successive "measured" answers — 21.4, then 14.6 mm — each buried the case
	# somewhere different. A number that has been looked at beats a number that
	# has been derived from the wrong data.
	# 30 mm, chosen off a six-frame sweep from 22 to 32: below 28 the wrist
	# cuts into the bottom of the display, above 30 the case starts to lift
	# off the arm. The sweep lives on as --watch-sweep if it ever needs
	# re-choosing (a different arm asset, a different reading pose).
	const WRIST_STANDOFF := 0.0300
	var back_off: float = WRIST_STANDOFF
	_watch_n = n
	_watch_ax = arm_ax
	_watch_invs = inv_s
	var holder := Node3D.new()
	holder.name = "WatchHolder"
	_watch_holder = holder
	holder.transform = Transform3D(
			Basis(X, Y, n).orthonormalized() * Basis.from_scale(Vector3.ONE * inv_s),
			(n * back_off - arm_ax * 0.032) * inv_s)
	ba.add_child(holder)
	# Flat on the wrist, full stop. (A wedge lived here once, leaning the case
	# toward the eye — it made the watch follow the viewer like a screen, and
	# a thing strapped to a wrist must do exactly the opposite.)
	var head := Node3D.new()
	head.position = Vector3(-0.002, 0.0, -0.0015)
	# Tilted to follow the TAPER of the forearm. The arm is fatter toward the
	# elbow, so a flat case lying parallel to the bone buries its elbow-side
	# edge and floats its wrist-side one — which is why every intrusion so far
	# has been at the same corner of the display. Lifting that edge is what
	# lets a rigid plate sit on a cone.
	head.rotation.y = _watch_tilt
	_watch_head = head
	holder.add_child(head)

	# Axis markers, for when the frame has to be SEEN rather than reasoned
	# about: red = local X, green = local Y, blue = local Z. Two revisions of
	# the strap wrapped the wrong plane because the answer was inferred.
	if watch_axes_debug:
		for ax in [[Vector3(0.05, 0, 0), Color(1, 0, 0)],
				[Vector3(0, 0.05, 0), Color(0, 1, 0)],
				[Vector3(0, 0, 0.05), Color(0.2, 0.4, 1)]]:
			var rod := MeshInstance3D.new()
			var rm := BoxMesh.new()
			rm.size = Vector3(0.004, 0.004, 0.004) + (ax[0] as Vector3).abs() * 2.0
			rod.mesh = rm
			var em := StandardMaterial3D.new()
			em.albedo_color = ax[1]
			em.emission_enabled = true
			em.emission = ax[1]
			em.emission_energy_multiplier = 3.0
			rod.material_override = em
			rod.position = (ax[0] as Vector3)
			rod.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			holder.add_child(rod)

	# All four parts share one shader; the numbers are the story. See
	# shaders/watch_body.gdshader — the wear is derived from where the geometry
	# is, so every corner this thing has ever been knocked on is already worn.
	var resin := _watch_mtl(Color(0.075, 0.080, 0.086), Color(0.30, 0.31, 0.33),
			Vector3(0.0180, 0.0155, 0.0058), 0.70, 0.0, 0.85, 0.0)
	var worn := _watch_mtl(Color(0.140, 0.145, 0.152), Color(0.62, 0.63, 0.64),
			Vector3(0.0155, 0.0131, 0.0063), 0.44, 0.55, 1.45, 0.0)
	var rubber := _watch_mtl(Color(0.036, 0.038, 0.041), Color(0.20, 0.20, 0.21),
			Vector3(0.0100, 0.0083, 0.0021), 0.93, 0.0, 0.75, 1.0)
	# Fine moulded ribs — six or seven across each link. At the first frequency
	# a link spanned barely one cycle, so every bakla came out as one light
	# band and one dark one and the strap read as a tank track.
	rubber.set_shader_parameter("rib_freq", 2350.0)
	rubber.set_shader_parameter("metal_gain", 0.0)
	if watch_axes_debug:
		resin = _flat(Color(0.10, 0.30, 1.00))    # case
		worn = _flat(Color(1.00, 0.85, 0.10))     # bezel / metal
		rubber = _flat(Color(1.00, 0.10, 0.10))   # strap

	# Case, worn bezel standing a little proud, and the crystal's frame.
	#
	# 36 x 31, and the width is the part that matters. A FLAT plate cannot sit
	# on a round arm if it is as wide as the arm: this forearm measures about
	# 21 mm from bone to skin, so a 42 mm case spans the full diameter and its
	# two edges are forced down to the level of the bone axis — buried, however
	# far you stand the centre off. It has to sit on the CROWN of the wrist,
	# which means clearly narrower than the wrist. (45 x 50 first, then 40 x 42,
	# both photographed with the arm cutting across the display.)
	var case := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(0.0360, 0.0310, 0.0115)
	case.mesh = cm
	case.material_override = resin
	head.add_child(case)
	var bez := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.0310, 0.0262, 0.0126)
	bez.mesh = bm
	bez.material_override = worn
	head.add_child(bez)
	# No lugs. The band runs straight out of the case sides — see the angle
	# list below, which starts where the case's own edge ends, so the first
	# link emerges from under it with nothing bridging and nothing to notice.
	var screen := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.0248, 0.0155)
	screen.mesh = qm
	_watch_mat = ShaderMaterial.new()
	_watch_mat.shader = load("res://shaders/dive_watch.gdshader")
	screen.material_override = _watch_mat
	screen.position = Vector3(0.0, 0.0, 0.0067)
	head.add_child(screen)
	# Two side buttons — light on the left, mode on the right, neither of
	# which does anything, which is also period-correct by year three.
	for by: float in [-1.0, 1.0]:
		var btn := MeshInstance3D.new()
		var bc := CylinderMesh.new()
		bc.top_radius = 0.0030
		bc.bottom_radius = 0.0030
		bc.height = 0.0062
		bc.radial_segments = 8
		btn.mesh = bc
		btn.material_override = worn
		btn.position = Vector3(0.0, by * 0.0178, -0.0014)
		head.add_child(btn)

	# The strap: stiff old rubber, in segments around the wrist, with a keeper.
	# The strap wraps the arm, so its radius comes off the same measurement:
	# the band rides just outside the skin instead of a hardcoded circle that
	# happened to fit one rotation.
	# Enough links, close enough together, to read as one continuous band all
	# the way round — and each one measures the arm IN ITS OWN DIRECTION. A
	# single radius drew a circle round an elliptical forearm: it bit into the
	# skin at the sides and stood clear of the silhouette at the top, which is
	# the tab that was sticking out past the arm.
	# The band is centred ON THE BONE. It was centred 5.8 mm off it, because
	# the holder's origin is the case FACE and that offset was never taken
	# back out: at twelve o'clock the ring then came out above the caseback,
	# inside the case, and round the sides it stood clear of the skin. That is
	# the band floating off the wrist.
	# The band circles in the HOLDER's frame, square to the forearm — a strap
	# is a ring round a limb. (It was moved into the case's tilted frame once,
	# to make the joint symmetrical; tilting the ring walks one side of it
	# toward the elbow, where the arm is thicker, and drove it into the flesh.)
	#
	# And the ring is NOT centred on the wrist bone. The bone runs close under
	# the back of the wrist — there is almost no flesh there and a good deal on
	# the palm side — so a ring centred on it is off-centre in the arm: correct
	# at the top, buried at the bottom. Every attempt to fix that with radius
	# alone failed, in both directions, because it is not a radius problem.
	#
	# Measured, not guessed: the watch was rendered twice per setting, once
	# with the arm and once with it hidden, and the strap's pixels counted in
	# each. Anything visible only in the bare frame is inside the arm. Centred
	# on the bone the band never got above 83 per cent visible however it was
	# sized; offset toward the palm it clears completely.
	# 6 mm. The pixel test is noisier than it looks — part of the band is
	# legitimately hidden BEHIND THE HAND from the reading angle, so anything
	# short of 100 per cent does not necessarily mean penetration, and only a
	# band big enough to be wrong reaches 100. 6 mm is where the ring stops
	# reading as buried without starting to read as a hoop.
	var palm_off := 0.0060
	var axis_z: float = -back_off - palm_off
	var rad_n: float = back_off - 0.0058 + palm_off
	var rad_a: float = rad_n * STRAP_RATIO
	_strap_geom = {"rn": rad_n, "ratio": STRAP_RATIO, "axis": axis_z,
			"rn0": back_off - 0.0058, "axis0": -back_off}
	for sgn: float in [-1.0, 1.0]:
		# Starting at the LUGS: below about fifty degrees the ring runs under
		# the case, so links there are buried inside it and the strap appeared
		# to begin in mid-air beside the watch rather than at its ends. Close
		# enough together, and wide enough, that the band has no gaps in it.
		# From 36 degrees — where the ellipse clears the side of the case, so
		# the strap appears to come out of it — round to 176, which meets its
		# opposite number under the wrist. The wrap is complete: there is no
		# arc of bare arm left anywhere except under the case itself.
		for a_deg: float in [40.0, 55.0, 70.0, 85.0, 100.0, 115.0, 130.0,
				145.0, 160.0, 175.0]:
			var a: float = deg_to_rad(a_deg) * sgn
			var r: float = rad_n * rad_a / sqrt(
					pow(rad_a * cos(a), 2.0) + pow(rad_n * sin(a), 2.0))

			var sm2 := MeshInstance3D.new()
			var sb := BoxMesh.new()
			# Long along the arm, narrow across it: that is a strap link.
			sb.size = Vector3(0.0200, 0.0165, 0.0042)
			sm2.mesh = sb
			sm2.material_override = rubber
			# Placed on the measured surface, then referred back to the holder,
			# whose origin is the case face rather than the bone.
			# AROUND the arm, in the across x dorsal plane.
			#
			# Which plane that is was finally settled by DRAWING the frame —
			# three coloured rods along the holder's own axes (watch_axes_debug)
			# — after two revisions had guessed it from the case's proportions
			# and from a sweep, and guessed wrong in both directions. Local X
			# runs along the arm, Y across it, Z out of the wrist.
			sm2.position = Vector3(0.0, sin(a) * r, axis_z + cos(a) * r)
			sm2.rotation.x = -a
			holder.add_child(sm2)
			_strap.append([sm2, a])
	# The buckle keeper, on the underside where the tail doubles back.
	var keeper := MeshInstance3D.new()
	var km := BoxMesh.new()
	km.size = Vector3(0.0105, 0.0135, 0.0068)
	keeper.mesh = km
	keeper.material_override = (_flat(Color(0.1, 1.0, 0.2)) if watch_axes_debug
			else rubber)
	var ka := deg_to_rad(152.0)
	var kr: float = rad_n * rad_a / sqrt(
			pow(rad_a * cos(ka), 2.0) + pow(rad_n * sin(ka), 2.0))
	kr += 0.0026
	keeper.position = Vector3(0.0, sin(ka) * kr, axis_z + cos(ka) * kr)
	keeper.rotation.x = -ka
	holder.add_child(keeper)
	# NOT _shadowless(ba): that helper also repaints every MeshInstance3D with
	# the arm's skin texture — run it here and the watch becomes a flesh watch.
	# Only the shadow flag is wanted, so only the shadow flag is set.
	for c in _walk_children(ba):
		if c is GeometryInstance3D:
			(c as GeometryInstance3D).cast_shadow = \
					GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _probe_arm(ax: Vector3, n: Vector3, across: Vector3) -> void:
	## The arm's actual radius under the watch, in metres, direction by
	## direction. Banded along the axis the debug rods proved is the arm's —
	## the earlier attempt at this banded along the FINGER axis and sliced the
	## limb diagonally, which is why it returned nonsense and was abandoned.
	var wb: int = _end_bone.get("L", -1)
	var s_m: float = float(_measured.get("scale", 1.0))
	if wb < 0 or s_m <= 1e-6:
		return
	var rest_inv: Transform3D = skeleton.get_bone_global_rest(wb).affine_inverse()
	var sk_inv: Transform3D = skeleton.global_transform.affine_inverse()
	var pts := PackedVector3Array()
	for node in _walk_children(_model):
		if not (node is MeshInstance3D):
			continue
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var to_bone: Transform3D = rest_inv * sk_inv * mi.global_transform
		for si in mi.mesh.get_surface_count():
			var arr: Array = mi.mesh.surface_get_arrays(si)
			if arr.is_empty():
				continue
			for v: Vector3 in (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				var p: Vector3 = (to_bone * v) * s_m
				var al: float = p.dot(ax)
				if al > 0.005 or al < -0.070:
					continue
				if (p - ax * al).length() > 0.060:
					continue
				pts.append(p)
	for lbl in [["dorsal", n], ["lateral+", across], ["lateral-", -across],
			["palmar", -n]]:
		var d: Vector3 = lbl[1]
		var best := -1e9
		for p: Vector3 in pts:
			var al: float = p.dot(ax)
			if absf(al + 0.032) > 0.014:
				continue
			var r: float = (p - ax * al).dot(d)
			if r > best:
				best = r
		print("[arm] %-9s %.4f m" % [lbl[0], best])
	print("[arm] verts in strip = %d" % pts.size())


func _walk_children(n: Node) -> Array:
	var out: Array = []
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		out.append(c)
		for ch in c.get_children():
			stack.append(ch)
	return out


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
