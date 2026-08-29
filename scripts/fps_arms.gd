extends Node3D
## First-person arms. BAMEN FPS rig (CC-BY-4.0).
##
## The previous pass rebuilt every bone basis from world axes and shredded
## the bind pose — that is why the helm looked broken and a grab looked like
## twisted sticks. This pass never replaces a bone's rest orientation.
## Additive local eulers only. Interactables come TO the hands.
##
## Radar / sounder: the screen is a photo. It slides in from the right,
## faces the lens the whole way, and sits in the palms. E sends it home.

const ARM_PATH := "res://assets/fps_arms/fps_arms.glb"

const POKE_TIME := 0.32
const SLIDE_IN := 0.38
const SLIDE_OUT := 0.32

enum Kind { IDLE, POKE, INSPECT }

var _lag: Node3D
var _model: Node3D
var _skel: Skeleton3D
var _ready_ok := false

var _sh_r := -1
var _sh_l := -1
var _fingers_r: Dictionary = {}
var _fingers_l: Dictionary = {}

var _bob_t := 0.0
var _kind: int = Kind.IDLE
var _hold_id := ""
var _poke_t := 0.0
var _phase := 0.0
var _returning := false
var _grip := 0.0

var _moved: Node3D
var _moved_home := Transform3D.IDENTITY
var _hide_src: MeshInstance3D
var _clone: MeshInstance3D

var boat: Node3D
var cam: Camera3D
var _active := false


func setup(p_cam: Camera3D) -> void:
	cam = p_cam
	_lag = Node3D.new()
	_lag.name = "ArmsLag"
	p_cam.add_child(_lag)
	_model = _instantiate_glb()
	if _model == null:
		return
	_lag.add_child(_model)
	_skel = _find_skel(_model)
	if _skel == null:
		push_error("fps_arms: no Skeleton3D in glb")
		return
	_bind_bones()
	_strip_shadows(_model)
	_place_in_view()
	_ready_ok = true
	_lag.visible = false


func _instantiate_glb() -> Node3D:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(ARM_PATH, state) != OK:
		push_error("fps_arms: cannot read %s" % ARM_PATH)
		return null
	return doc.generate_scene(state)


func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n as Skeleton3D
	for c in n.get_children():
		var s := _find_skel(c)
		if s != null:
			return s
	return null


func _bone(key: String) -> int:
	for i in _skel.get_bone_count():
		if key in String(_skel.get_bone_name(i)):
			return i
	return -1


func _chain(side: String, finger: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var last := 4 if finger == 1 else 3
	for j in range(1, last + 1):
		var id := _bone("Finger_%d_%d.%s" % [finger, j, side])
		if id >= 0:
			out.append(id)
	return out


func _bind_bones() -> void:
	_sh_r = _bone("Arm_1.R")
	_sh_l = _bone("Arm_1.L")
	for f in range(1, 6):
		_fingers_r[f] = _chain("R", f)
		_fingers_l[f] = _chain("L", f)


func _strip_shadows(n: Node) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		_strip_shadows(c)


func _place_in_view() -> void:
	## Rest wrists sit at y≈1.24 in armature space. The eye is the camera, so
	## the rig drops until only the forearms enter the frustum. Do NOT center
	## the mesh AABB on the lens — that puts the camera inside the mesh and
	## the near plane clips the whole thing to nothing.
	_model.scale = Vector3.ONE * 0.92
	_model.position = Vector3(0.0, -1.42, 0.08)


func inspecting_id() -> String:
	if _kind == Kind.INSPECT and _hold_id != "":
		return _hold_id
	return ""


func set_active(on: bool) -> void:
	_active = on and _ready_ok
	if _lag != null:
		_lag.visible = _active
		_lag.transform = Transform3D.IDENTITY
	if cam != null:
		cam.near = 0.05 if _active else 0.10


func notify_use(id: String) -> void:
	if not _ready_ok:
		return
	if id == "helm" or id == "telegraph" or id == "chart":
		return
	if _kind_of(id) == Kind.INSPECT:
		if _hold_id == id and not _returning:
			_start_return()
		else:
			_start_inspect(id)
	else:
		_start_poke(id)


func update(delta: float, p_boat: Node3D, engaged: String, walking: float,
		swimming: bool) -> void:
	boat = p_boat
	if not _ready_ok or cam == null:
		return
	if swimming or not _active:
		_reset_pose()
		if _lag != null:
			_lag.visible = false
		return
	_lag.visible = true
	_bob_t = fmod(_bob_t + delta * (1.2 + walking * 6.5), TAU)
	_update_lag(delta, engaged)
	_skel.reset_bone_poses()
	_idle_sway(walking)

	var want_grip := 0.0
	if _kind == Kind.INSPECT:
		_tick_inspect(delta)
		want_grip = 0.55 if _hold_id == "radio" else 0.40
	elif _kind == Kind.POKE:
		_tick_poke(delta)
		want_grip = 0.0
	elif engaged == "helm" or engaged == "telegraph":
		want_grip = 0.45
	elif engaged == "chart":
		want_grip = 0.20
	elif boat != null and boat.get("radio_held") == true and _hold_id != "radio":
		_start_inspect("radio")
	_grip = move_toward(_grip, want_grip, delta * 8.0)
	if _kind != Kind.POKE and _grip > 0.01:
		_curl_fingers(_fingers_r, _grip, false)
		_curl_fingers(_fingers_l, _grip * 0.85, false)

	if (boat == null or boat.get("radio_held") != true) and _hold_id == "radio" and not _returning:
		_start_return()


func _update_lag(delta: float, engaged: String) -> void:
	## Child of the camera, so identity = glued to the lens. A small local
	## slerp is the look lag without parking the mesh at the world origin.
	if engaged != "" and _kind != Kind.INSPECT:
		_lag.transform = Transform3D.IDENTITY
	else:
		_lag.transform = _lag.transform.interpolate_with(
				Transform3D.IDENTITY, 1.0 - exp(-14.0 * delta))


func _kind_of(id: String) -> int:
	if id == "radio" or id == "radar" or id == "sounder":
		return Kind.INSPECT
	return Kind.POKE


func _start_poke(id: String) -> void:
	_kind = Kind.POKE
	_hold_id = id
	_poke_t = 0.0
	_returning = false


func _start_inspect(id: String) -> void:
	_clear_inspect(true)
	_kind = Kind.INSPECT
	_hold_id = id
	_phase = 0.0
	_returning = false
	match id:
		"radio":
			_moved = boat.call("radio_handset") as Node3D
			if _moved == null:
				_kind = Kind.IDLE
				_hold_id = ""
				return
			boat.set("radio_pose_locked", true)
			_moved_home = Transform3D(
					Basis.from_euler(Vector3(0.0, 0.0, deg_to_rad(12.0))),
					Vector3(1.49, 3.94, 0.55))
		"radar", "sounder":
			var src: MeshInstance3D = boat.call("screen_mesh", id) as MeshInstance3D
			if src == null:
				_kind = Kind.IDLE
				_hold_id = ""
				return
			_hide_src = src
			_clone = src.duplicate() as MeshInstance3D
			_clone.top_level = true
			_clone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			cam.get_parent().add_child(_clone)
			_clone.global_transform = src.global_transform
			src.visible = false
			_moved = _clone
			_moved_home = src.global_transform


func _start_return() -> void:
	if _kind != Kind.INSPECT:
		return
	_returning = true
	_phase = 0.0
	if _hold_id == "radio":
		boat.set("radio_held", false)


func _tick_inspect(delta: float) -> void:
	_phase += delta
	var dur := SLIDE_OUT if _returning else SLIDE_IN
	var u := clampf(_phase / maxf(dur, 0.001), 0.0, 1.0)
	u = u * u * (3.0 - 2.0 * u)
	if _returning and u >= 1.0:
		_finish_return()
		return
	var t := (1.0 - u) if _returning else u
	if _moved != null:
		_moved.global_transform = _home_global().interpolate_with(_held_xf(), t)


func _held_xf() -> Transform3D:
	## A photo in the hands: faces the lens, slightly right, in the palms.
	## Radar slides in from off-screen right (x=0.55 → 0.12) so it reads as
	## a shard coming to you, not a 3D brick being wrestled.
	var t := clampf(_phase / SLIDE_IN, 0.0, 1.0)
	if _returning:
		t = 1.0
	t = t * t * (3.0 - 2.0 * t)
	if _hold_id == "radio":
		var pos := Vector3(0.16, -0.12, -0.30)
		var bas := Basis.from_euler(Vector3(0.18, 0.40, 0.06))
		return cam.global_transform * Transform3D(bas, pos)
	# Screen: always camera-facing (QuadMesh +Z toward the lens).
	var x := lerpf(0.62, 0.11, t)
	return cam.global_transform * Transform3D(Basis.IDENTITY, Vector3(x, -0.07, -0.40))


func _finish_return() -> void:
	if _moved != null and _hold_id == "radio":
		_moved.transform = _moved_home
	_clear_inspect(true)
	if boat != null:
		boat.set("radio_pose_locked", false)
	_kind = Kind.IDLE
	_hold_id = ""
	_returning = false


func _clear_inspect(restore: bool) -> void:
	if _clone != null:
		if restore and _hide_src != null:
			_hide_src.visible = true
		_clone.queue_free()
		_clone = null
	_hide_src = null
	_moved = null


func _home_global() -> Transform3D:
	if _hold_id == "radio" and boat != null:
		return boat.global_transform * _moved_home
	return _moved_home


func _tick_poke(delta: float) -> void:
	_poke_t += delta
	var u := clampf(_poke_t / POKE_TIME, 0.0, 1.0)
	var press: float = sin(clampf(u / 0.55, 0.0, 1.0) * PI) if u < 0.55 \
			else 1.0 - clampf((u - 0.55) / 0.45, 0.0, 1.0)
	press = clampf(press, 0.0, 1.0)
	# Lean the right shoulder toward the thing — rest * small euler, never a
	# rebuilt basis. That is the whole difference from the broken grab.
	var local: Vector3 = cam.global_transform.affine_inverse() * _world_point(_hold_id)
	var yaw := clampf(local.x * 0.7, -0.35, 0.45)
	var pit := clampf(-0.12 - local.y * 0.4, -0.45, 0.15)
	_nudge_bone(_sh_r, Vector3(pit, yaw, 0.08) * press)
	_curl_fingers(_fingers_r, 0.0, true, press)
	if u >= 1.0:
		_kind = Kind.IDLE
		_hold_id = ""


func _world_point(id: String) -> Vector3:
	if boat == null:
		return cam.global_position + cam.global_basis * Vector3(0.2, -0.15, -0.4)
	match id:
		"ignition":
			var key: Node3D = boat.call("ignition_key") as Node3D
			if key != null:
				return key.global_position
		"windlass":
			var w: Node3D = boat.call("windlass_node") as Node3D
			if w != null:
				return w.global_position + w.global_basis * Vector3(0.40, 0.10, 0.0)
		"door_fwd", "door_aft":
			var d: Node3D = boat.call("door_node", id) as Node3D
			if d != null:
				return d.to_global(Vector3(0.94, 1.62, 0.032))
		"door_wh":
			var dw: Node3D = boat.call("door_node", id) as Node3D
			if dw != null:
				return dw.to_global(Vector3(-0.94, 0.94, -0.032))
	if id.begins_with("sw_"):
		var sw: Node3D = boat.call("switch_lever", id) as Node3D
		if sw != null:
			return sw.to_global(Vector3(0.0, 0.052, 0.0))
	var items: Variant = boat.get("INTERACT")
	if items is Array:
		for it in items:
			if str(it["id"]) == id:
				return boat.global_transform * it["pos"]
	return cam.global_position + -cam.global_basis.z * 0.4


func _idle_sway(walking: float) -> void:
	if _sh_r < 0:
		return
	var breath := sin(_bob_t * 0.55) * 0.016
	var step := sin(_bob_t) * walking * 0.04
	_nudge_bone(_sh_r, Vector3(0.025 + step, breath, 0.015))
	_nudge_bone(_sh_l, Vector3(-0.025 - step * 0.85, breath, 0.015))


func _nudge_bone(idx: int, euler: Vector3) -> void:
	if idx < 0:
		return
	var rest: Quaternion = _skel.get_bone_rest(idx).basis.get_rotation_quaternion()
	_skel.set_bone_pose_rotation(idx, rest * Quaternion.from_euler(euler))


func _curl_fingers(fingers: Dictionary, wrap: float, poke: bool, w := 1.0) -> void:
	## Rest * local X only, and the angle is small. The old 0.85 rad per joint
	## on a guessed axis is what folded the hands inside out.
	for f in fingers:
		var chain: PackedInt32Array = fingers[f]
		var amount := wrap * 0.22
		if poke:
			amount = 0.04 if int(f) == 2 else 0.28
			if int(f) == 1:
				amount = 0.12
		for i in chain.size():
			var idx: int = chain[i]
			var rest := _skel.get_bone_rest(idx)
			var q := rest.basis.get_rotation_quaternion() \
					* Quaternion(Vector3.RIGHT, amount * w * (1.0 + float(i) * 0.08))
			_skel.set_bone_pose_rotation(idx, q)


func _reset_pose() -> void:
	if _skel != null:
		_skel.reset_bone_poses()
