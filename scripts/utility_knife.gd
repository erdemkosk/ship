extends Node3D
class_name UtilityKnife3D
## The exact imported knife is shared by the bag, the hand and the attack.
## Its wrapper origin is the palm contact on the grip, so the hand solver can
## weld the prop without a second view-model or a frame-late corrective offset.

signal struck(collider: Object, position: Vector3, normal: Vector3)

const MODEL_SCENE := preload("res://art/models/utility_knife.glb")
const MODEL_SCALE := 0.0084
const SOURCE_GRIP_CENTER := Vector3(13.35, -3.10, -0.34)
const SOURCE_BLADE_BASE := Vector3(2.20, -2.55, -0.34)
const SOURCE_BLADE_TIP := Vector3(-17.85, -2.55, -0.34)
const HANDLE_KNUCKLE_OFFSET := 0.0
# Surface-to-surface clearance, not a guessed handle-centre offset. The actual
# imported grip AABB is measured below and translated until its near scale is
# this far beyond the authored palm contact plane.
const PALM_SKIN_CLEARANCE := 0.002
const ATTACK_DURATION := 0.62
const HAND_TUNING := preload("res://scripts/hands/hand_tuning.gd")
const HIT_WINDOW_START := 0.28
const HIT_WINDOW_END := 0.56
const WINDUP_END := 0.27
const STRIKE_END := 0.47
const FOLLOW_END := 0.60

var _model: Node3D
var _grip: Node3D
var _blade_base: Node3D
var _blade_tip: Node3D
var _grip_bounds := AABB()
var _attack_elapsed := -1.0
var _previous_tip := Vector3.ZERO
var _previous_tip_valid := false
var _hit_latched := false
var _attack_serial := 0
var _attack_variant := 0
var _hit_reaction := 0.0


func _init() -> void:
	name = "UtilityKnife"
	set_meta("item_label", "Utility knife")
	set_meta("item_kind", "utility_knife")


func _ready() -> void:
	if _model != null:
		return
	_build_model()


func _build_model() -> void:
	_model = MODEL_SCENE.instantiate() as Node3D
	_model.name = "ImportedUtilityKnife"
	# A knife handle crosses a closed palm from pinky to index: it belongs on the
	# semantic KNUCKLE axis, never on the open-finger axis. Source -X runs from
	# handle to blade, so it maps to +K (toward the index). Source -Y supplies
	# the blade height (-F), and raw Z is its face normal (-P, toward the back of
	# the hand). This is a proper right-handed basis and keeps blade, fist and
	# forearm anatomically consistent instead of rotating the knife through the
	# palm by ninety degrees.
	var raw_to_local := Basis(
			Vector3.LEFT,
			Vector3.FORWARD,
			Vector3.DOWN).scaled(Vector3.ONE * MODEL_SCALE)
	_model.transform = Transform3D(raw_to_local, Vector3.ZERO)
	add_child(_model)
	# Sketchfab's importer inserts an FBX correction transform below the scene
	# root. Raw glTF accessor coordinates therefore are not model-root points.
	# Measure through the imported node hierarchy first, then translate the scene
	# so the REAL handle centre—not a guessed pre-import coordinate—lands here.
	var grip_mesh := _model.find_child("grip_Lowpoly__0", true, false) as MeshInstance3D
	var blade_mesh := _model.find_child("blade_Lowpoly__0", true, false) as MeshInstance3D
	if grip_mesh != null:
		var imported_grip := to_local(grip_mesh.to_global(SOURCE_GRIP_CENTER))
		var unseated_bounds := _mesh_bounds_in_self(grip_mesh)
		_model.position += Vector3(
				HANDLE_KNUCKLE_OFFSET - imported_grip.x,
				PALM_SKIN_CLEARANCE - unseated_bounds.position.y,
				-imported_grip.z)
		_grip_bounds = _mesh_bounds_in_self(grip_mesh)

	_grip = Node3D.new()
	_grip.name = "Grip"
	add_child(_grip)
	_grip.set_meta("authored_transform", _grip.transform)
	HAND_TUNING.apply_marker("knife/Grip", _grip)
	_blade_base = Node3D.new()
	_blade_base.name = "BladeBase"
	_blade_base.position = _imported_point(blade_mesh, SOURCE_BLADE_BASE)
	add_child(_blade_base)
	_blade_tip = Node3D.new()
	_blade_tip.name = "BladeTip"
	_blade_tip.position = _imported_point(blade_mesh, SOURCE_BLADE_TIP)
	add_child(_blade_tip)


func _imported_point(mesh_node: MeshInstance3D, source_point: Vector3) -> Vector3:
	if mesh_node == null:
		return Vector3.ZERO
	return to_local(mesh_node.to_global(source_point))


func _mesh_bounds_in_self(mesh_node: MeshInstance3D) -> AABB:
	if mesh_node == null or mesh_node.mesh == null:
		return AABB(Vector3(-0.10, 0.018, -0.025), Vector3(0.20, 0.026, 0.050))
	var source := mesh_node.get_aabb()
	var bounds := AABB()
	for endpoint in 8:
		var point := to_local(mesh_node.to_global(source.get_endpoint(endpoint)))
		bounds = AABB(point, Vector3.ZERO) if endpoint == 0 else bounds.expand(point)
	return bounds


func grip_node() -> Node3D:
	return _grip


func grip_contact_bounds() -> AABB:
	## Handle only. Feeding the blade into the finger solver makes it back the
	## fist away from empty air; these bounds let every phalanx close until its
	## pad actually meets the scales and stop before it penetrates them.
	return _grip_bounds


func blade_tip_node() -> Node3D:
	return _blade_tip


func blade_base_node() -> Node3D:
	return _blade_base


func model_mesh_count() -> int:
	return _count_meshes(_model)


func begin_attack() -> bool:
	if _attack_elapsed >= 0.0:
		return false
	# Rotate through small, authored variations. Choosing once here keeps the
	# gesture human without introducing frame-to-frame random jitter.
	_attack_variant = _attack_serial % 3
	_attack_serial += 1
	_attack_elapsed = 0.0
	_hit_latched = false
	_hit_reaction = 0.0
	_previous_tip_valid = false
	return true


func cancel_attack() -> void:
	_attack_elapsed = -1.0
	_hit_reaction = 0.0
	_previous_tip_valid = false
	_hit_latched = false


func tick_attack(delta: float) -> void:
	_hit_reaction = move_toward(_hit_reaction, 0.0, delta / 0.10)
	if _attack_elapsed < 0.0:
		return
	_attack_elapsed += delta
	if _attack_elapsed >= ATTACK_DURATION:
		_attack_elapsed = -1.0


func is_attacking() -> bool:
	return _attack_elapsed >= 0.0


func attack_phase() -> float:
	if _attack_elapsed < 0.0:
		return -1.0
	return clampf(_attack_elapsed / ATTACK_DURATION, 0.0, 1.0)


func hand_position_camera_local() -> Vector3:
	## High-right preparation, a fast curved cut, a brief follow-through, then a
	## weighted return. The arm solver follows this palm contact and the knife
	## stays welded to the solved palm.
	var idle := Vector3(0.235, -0.235, -0.455)
	var phase := attack_phase()
	if phase < 0.0:
		return idle
	var side := 0.0
	var lift := 0.0
	var depth := 0.0
	match _attack_variant:
		0:
			side = -0.012
			lift = 0.008
		1:
			lift = -0.006
			depth = 0.012
		2:
			side = 0.014
			depth = -0.010
	var windup := Vector3(0.375 + side, -0.055 + lift, -0.355 + depth)
	var strike := Vector3(-0.115 - side * 0.5, -0.345, -0.585)
	var follow := Vector3(-0.170 - side, -0.405 - lift * 0.5, -0.625)
	var pos: Vector3
	if phase < WINDUP_END:
		var u := _ease_in_out(phase / WINDUP_END)
		pos = _quadratic_bezier(idle,
				Vector3(0.285, -0.205 + lift, -0.405), windup, u)
	elif phase < STRIKE_END:
		var u := 1.0 - pow(1.0 - inverse_lerp(WINDUP_END, STRIKE_END, phase), 3.4)
		pos = _quadratic_bezier(windup,
				Vector3(0.105 + side, -0.105, -0.455), strike, u)
	elif phase < FOLLOW_END:
		var u := _ease_out(inverse_lerp(STRIKE_END, FOLLOW_END, phase))
		pos = _quadratic_bezier(strike,
				Vector3(-0.155, -0.385, -0.615), follow, u)
	else:
		var u := _ease_in_out(inverse_lerp(FOLLOW_END, 1.0, phase))
		pos = _quadratic_bezier(follow,
				Vector3(0.075, -0.345, -0.565), idle, u)
	# Contact compresses the arm very slightly instead of letting the blade pass
	# through a surface with no physical acknowledgement.
	pos += Vector3(0.012, 0.006, 0.025) * _hit_reaction
	return pos


func camera_kick() -> Vector3:
	## A restrained head/shoulder answer to the arm's mass. This replaces the
	## discarded synthetic whoosh: anticipation leans into the strike, the cut
	## snaps across it, and recovery gives the view back without screen shake.
	var phase := attack_phase()
	if phase < 0.0:
		return Vector3.ZERO
	var prepared := Vector3(deg_to_rad(-1.0), deg_to_rad(0.7), deg_to_rad(2.6))
	var cut := Vector3(deg_to_rad(1.6), deg_to_rad(-1.2), deg_to_rad(-4.8))
	var motion: Vector3
	if phase < WINDUP_END:
		motion = prepared * _ease_in_out(phase / WINDUP_END)
	elif phase < STRIKE_END:
		var u := 1.0 - pow(1.0 - inverse_lerp(
				WINDUP_END, STRIKE_END, phase), 3.0)
		motion = prepared.lerp(cut, u)
	elif phase < FOLLOW_END:
		motion = cut.lerp(cut * 0.72,
				_ease_out(inverse_lerp(STRIKE_END, FOLLOW_END, phase)))
	else:
		motion = (cut * 0.72).lerp(Vector3.ZERO,
				_ease_in_out(inverse_lerp(FOLLOW_END, 1.0, phase)))
	# A short rotational impulse at contact. It is layered over the existing
	# shoulder motion, so misses retain the clean follow-through.
	var hit_kick := Vector3(deg_to_rad(-0.65), deg_to_rad(0.35),
			deg_to_rad(0.9)) * _hit_reaction
	return motion + hit_kick


func sample_sweep() -> Dictionary:
	if _blade_tip == null or _blade_base == null:
		return {}
	var current_tip := _blade_tip.global_position
	var phase := attack_phase()
	var result := {}
	if _previous_tip_valid and not _hit_latched \
			and phase >= HIT_WINDOW_START and phase <= HIT_WINDOW_END:
		result = {
			"from": _previous_tip,
			"to": current_tip,
			"blade_base": _blade_base.global_position,
			"blade_tip": current_tip,
			"phase": phase,
		}
	_previous_tip = current_tip
	_previous_tip_valid = is_attacking()
	return result


func mark_hit(collider: Object, position: Vector3, normal: Vector3) -> void:
	if _hit_latched:
		return
	_hit_latched = true
	_hit_reaction = 1.0
	struck.emit(collider, position, normal)


func hit_latched() -> bool:
	return _hit_latched


func _quadratic_bezier(a: Vector3, control: Vector3, b: Vector3, t: float) -> Vector3:
	var ab := a.lerp(control, t)
	var bc := control.lerp(b, t)
	return ab.lerp(bc, t)


func _ease_in_out(t: float) -> float:
	return smoothstep(0.0, 1.0, clampf(t, 0.0, 1.0))


func _ease_out(t: float) -> float:
	var u := clampf(t, 0.0, 1.0)
	return 1.0 - pow(1.0 - u, 2.4)


func _count_meshes(node: Node) -> int:
	if node == null:
		return 0
	var total := 1 if node is MeshInstance3D else 0
	for child in node.get_children():
		total += _count_meshes(child)
	return total
