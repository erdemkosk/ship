extends Node3D
class_name BackpackSystem
## A physical first-person inventory performance. The closed pack lives behind
## the eye; I brings it around the shoulder, two hands open it, and the same
## continuous progress curve reverses every action when it is stowed.

const OPEN_TIME := 2.05
const CLOSE_TIME := 1.75

var _camera: Camera3D
var _hands: Node
var _bag: Node3D
var _flap: Node3D
var _zipper: Node3D
var _cavity: MeshInstance3D
var _item: Node3D
var _body_straps: Node3D
var _focus_layer: CanvasLayer
var _focus_rect: ColorRect
var _focus_material: ShaderMaterial
var _fabric: ShaderMaterial
var _progress := 0.0
var _target := 0.0
var _phase := 0.0
var _last_progress := 0.0
var _enabled := true
var _zip_lower_teeth: Array[MeshInstance3D] = []
var _zip_upper_teeth: Array[MeshInstance3D] = []


func setup(camera: Camera3D, hands: Node) -> void:
	_camera = camera
	_hands = hands
	_build_pack()
	_build_body_straps()
	_build_focus()
	_publish_hands()


func toggle() -> void:
	if not _enabled:
		return
	_target = 0.0 if _target > 0.5 else 1.0


func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	if not enabled:
		_target = 0.0
		_progress = 0.0
	_apply_pose(_progress, 0.0)
	_publish_hands()


func force_stow(immediate := false) -> void:
	_target = 0.0
	if immediate:
		_progress = 0.0
		_apply_pose(0.0, 0.0)
		_publish_hands()


func is_active() -> bool:
	return _enabled and (_target > 0.0 or _progress > 0.002)


func is_open() -> bool:
	return _progress > 0.995 and _target > 0.5


func focus_amount() -> float:
	return smoothstep(0.24, 0.70, _progress) if _enabled else 0.0


func progress() -> float:
	return _progress


func update(delta: float) -> void:
	var duration := OPEN_TIME if _target > _progress else CLOSE_TIME
	_last_progress = _progress
	_progress = move_toward(_progress, _target, delta / duration)
	var velocity := absf(_progress - _last_progress) * duration / maxf(delta, 0.0001)
	_phase += delta * (1.15 + velocity * 3.2)
	_apply_pose(_progress, velocity)
	_publish_hands()


func state_report() -> Dictionary:
	return {
		"active": is_active(),
		"open": is_open(),
		"progress": _progress,
		"zipper": smoothstep(0.40, 0.66, _progress),
		"flap": smoothstep(0.62, 0.83, _progress),
		"item": smoothstep(0.84, 1.0, _progress),
		"focus": focus_amount(),
		"bag_visible": _bag.visible if _bag != null else false,
	}


func _publish_hands() -> void:
	if _hands == null or not _hands.has_method("set_backpack_state"):
		return
	_hands.set_backpack_state({
		"active": is_active(),
		"progress": _progress,
		"bag": _bag,
		"zipper": _zipper,
		"item": _item,
	})


func _apply_pose(p: float, velocity: float) -> void:
	if _bag == null:
		return
	var carry := smoothstep(0.0, 0.40, p)
	var carry_eased := carry * carry * (3.0 - 2.0 * carry)
	var stowed := Vector3(0.43, -0.31, 0.10)
	var front := Vector3(0.025, -0.325, -0.610)
	var pos := stowed.lerp(front, carry_eased)
	# Around the right shoulder, not straight through the player's chest.
	pos.x += sin(carry_eased * PI) * 0.17
	pos.y += sin(carry_eased * PI) * 0.065
	var from_basis := Basis.from_euler(Vector3(deg_to_rad(-18.0),
			deg_to_rad(-112.0), deg_to_rad(16.0)))
	var to_basis := Basis.from_euler(Vector3(deg_to_rad(-5.0),
			deg_to_rad(2.0), deg_to_rad(-2.0)))
	var basis := from_basis.slerp(to_basis, carry_eased)
	# Canvas inertia: the soft shell settles a fraction behind the main mass.
	var settle := sin(carry_eased * PI) * sin(_phase * 2.1) * 0.025 * velocity
	basis = basis * Basis(Vector3.BACK, settle)
	_bag.transform = Transform3D(basis, pos)
	_bag.visible = is_active()

	var zip := smoothstep(0.40, 0.66, p)
	_zipper.position = Vector3(lerpf(0.165, -0.165, zip), 0.145, 0.113)
	var opened := smoothstep(0.62, 0.83, p)
	# The padded top rolls back with a tiny fabric overshoot, rather than
	# rotating like the lid of a wooden box.
	_flap.rotation.x = deg_to_rad(-82.0) * opened \
			+ sin(opened * PI) * 0.055
	if _cavity != null:
		# The opening lies across the horizontal top of the pack. It grows toward
		# the back as the flap releases, exposing depth rather than a dark decal
		# pasted on the front face.
		_cavity.scale = Vector3(1.0, 0.11, lerpf(0.025, 0.70, opened))
		_cavity.visible = opened > 0.01
	# Each pair separates only after the real slider has passed it. This turns
	# the zipper into a mechanism instead of a row of decorative cubes.
	for i in _zip_lower_teeth.size():
		var threshold := float(i) / maxf(float(_zip_lower_teeth.size() - 1), 1.0)
		var separated := smoothstep(threshold, minf(threshold + 0.16, 1.0), zip)
		_zip_lower_teeth[i].position.y = 0.143
		_zip_lower_teeth[i].position.z = 0.106 + separated * 0.006
		_zip_upper_teeth[i].position.y = 0.146
		_zip_upper_teeth[i].position.z = 0.098 - separated * 0.006
	var take := smoothstep(0.84, 1.0, p)
	_item.position = Vector3(0.045, 0.151, 0.018).lerp(
			Vector3(0.135, 0.315, 0.175), take)
	_item.rotation = Vector3(deg_to_rad(90.0), take * 0.22, take * -0.18)
	_item.visible = p > 0.80
	if _fabric != null:
		_fabric.set_shader_parameter("motion", clampf(velocity, 0.0, 1.0))
		_fabric.set_shader_parameter("phase", _phase)
	if _body_straps != null:
		var strap_amount := 1.0 - smoothstep(0.03, 0.30, p)
		_body_straps.visible = _enabled and strap_amount > 0.02
		_body_straps.scale = Vector3.ONE * maxf(strap_amount, 0.001)
	if _focus_material != null:
		_focus_material.set_shader_parameter("amount", focus_amount() * 0.72)
		_focus_rect.visible = focus_amount() > 0.01


func _build_pack() -> void:
	_bag = Node3D.new()
	_bag.name = "BackpackViewmodel"
	_bag.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_camera.add_child(_bag)
	_fabric = ShaderMaterial.new()
	_fabric.shader = load("res://shaders/backpack_fabric.gdshader")
	_fabric.set_shader_parameter("albedo", Color(0.175, 0.195, 0.115, 1.0))
	var dark := _material(Color(0.018, 0.020, 0.016), 0.98)
	var leather := _material(Color(0.115, 0.060, 0.035), 0.86)
	var brass := _material(Color(0.48, 0.31, 0.10), 0.32, 0.65)

	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.168
	body_mesh.height = 0.405
	body_mesh.radial_segments = 24
	body_mesh.rings = 12
	var body_node := _mesh(body_mesh, _fabric, _bag,
			Vector3(0.0, -0.035, 0.0), Vector3.ZERO)
	body_node.scale = Vector3(1.10, 1.0, 0.56)
	# Padded front pocket and reinforced bottom give the silhouette weight.
	var pocket := SphereMesh.new()
	pocket.radius = 0.142
	pocket.height = 0.205
	pocket.radial_segments = 20
	pocket.rings = 9
	var pocket_node := _mesh(pocket, _fabric, _bag,
			Vector3(0.0, -0.085, 0.086), Vector3.ZERO)
	pocket_node.scale = Vector3(1.0, 1.0, 0.29)
	var bottom := BoxMesh.new()
	bottom.size = Vector3(0.37, 0.052, 0.158)
	_mesh(bottom, leather, _bag, Vector3(0.0, -0.225, 0.0), Vector3.ZERO)

	# The shell continues all the way beneath the zipper. The dark lining is a
	# shallow oval slit laid over that cloth and only gains height as the two
	# lips separate; there is never an unsupported black box under the teeth.
	var cavity_mesh := SphereMesh.new()
	cavity_mesh.radius = 0.142
	cavity_mesh.height = 0.245
	cavity_mesh.radial_segments = 24
	cavity_mesh.rings = 8
	_cavity = _mesh(cavity_mesh, dark, _bag,
			Vector3(0.0, 0.145, 0.015), Vector3.ZERO)
	_cavity.scale = Vector3(1.0, 0.11, 0.025)
	_cavity.visible = false
	# Two flat woven tapes sew the metal zipper directly into the shell. They
	# are intentionally not round tubes: zipper tape lies flat against fabric.
	for z in [0.117, 0.087]:
		var tape := BoxMesh.new()
		tape.size = Vector3(0.348, 0.007, 0.018)
		tape.subdivide_width = 10
		_mesh(tape, _fabric, _bag, Vector3(0.0, 0.143, z), Vector3.ZERO)
	# Bound side seams complete the U-shaped mouth and visually join the top
	# assembly to the body instead of leaving the zipper floating in space.
	for sx in [-1.0, 1.0]:
		var binding := BoxMesh.new()
		binding.size = Vector3(0.009, 0.007, 0.178)
		binding.subdivide_depth = 6
		_mesh(binding, _fabric, _bag, Vector3(sx * 0.174, 0.143, 0.031),
				Vector3.ZERO)
	_flap = Node3D.new()
	_flap.name = "BackpackFlap"
	_flap.position = Vector3(0.0, 0.108, -0.072)
	_bag.add_child(_flap)
	var flap_mesh := SphereMesh.new()
	flap_mesh.radius = 0.175
	flap_mesh.height = 0.145
	flap_mesh.radial_segments = 24
	flap_mesh.rings = 10
	var flap_node := _mesh(flap_mesh, _fabric, _flap,
			Vector3(0.0, 0.053, 0.071), Vector3.ZERO)
	flap_node.scale = Vector3(1.0, 1.0, 0.54)
	# Stitched edge around the top panel catches light like a real bound seam.
	_tube(Vector3(-0.150, 0.030, 0.139), Vector3(0.150, 0.030, 0.139),
			0.0045, leather, _flap)

	# Front compression strap, buckle and two small side pockets make the object
	# unmistakably a worn pack even before it starts moving.
	var compression := BoxMesh.new()
	compression.size = Vector3(0.286, 0.027, 0.014)
	_mesh(compression, leather, _bag, Vector3(0.0, -0.105, 0.137),
			Vector3.ZERO)
	var buckle := BoxMesh.new()
	buckle.size = Vector3(0.040, 0.039, 0.022)
	_mesh(buckle, brass, _bag, Vector3(0.0, -0.105, 0.148), Vector3.ZERO)
	for sx in [-1.0, 1.0]:
		var side_pocket := SphereMesh.new()
		side_pocket.radius = 0.070
		side_pocket.height = 0.125
		side_pocket.radial_segments = 12
		side_pocket.rings = 5
		var side_node := _mesh(side_pocket, _fabric, _bag,
				Vector3(sx * 0.174, -0.105, -0.003), Vector3.ZERO)
		side_node.scale = Vector3(0.52, 1.0, 0.72)

	# Interlocking teeth are two staggered rows. The hand follows the physical
	# slider while the rows peel apart behind it.
	for i in 18:
		var x := lerpf(0.162, -0.162, float(i) / 17.0)
		var lower_mesh := BoxMesh.new()
		lower_mesh.size = Vector3(0.008, 0.006, 0.008)
		var lower := _mesh(lower_mesh, brass, _bag,
				Vector3(x, 0.143, 0.106), Vector3.ZERO)
		_zip_lower_teeth.append(lower)
		var upper_mesh := BoxMesh.new()
		upper_mesh.size = Vector3(0.008, 0.006, 0.008)
		var upper := _mesh(upper_mesh, brass, _bag,
				Vector3(x - 0.004, 0.146, 0.098), Vector3.ZERO)
		_zip_upper_teeth.append(upper)
	_zipper = Node3D.new()
	_zipper.name = "ZipperSlider"
	_bag.add_child(_zipper)
	var slider := BoxMesh.new()
	slider.size = Vector3(0.025, 0.016, 0.018)
	_mesh(slider, brass, _zipper, Vector3.ZERO, Vector3.ZERO)
	_tube(Vector3(0.0, -0.004, 0.0), Vector3(0.0, -0.040, 0.012),
			0.004, brass, _zipper)

	# Shoulder straps belong to the object and become visible as it rolls around.
	for sx in [-1.0, 1.0]:
		_tube(Vector3(sx * 0.125, 0.155, -0.082),
				Vector3(sx * 0.175, -0.185, -0.092), 0.016, leather, _bag)
		_tube(Vector3(sx * 0.175, -0.185, -0.092),
				Vector3(sx * 0.105, -0.225, -0.080), 0.013, leather, _bag)

	# Temporary inventory item: a small brass field compass. It is deliberately
	# a normal Node3D slot so a future real item can replace it without touching
	# the bag choreography.
	_item = Node3D.new()
	_item.name = "InventoryItemSlot"
	_bag.add_child(_item)
	var compass := CylinderMesh.new()
	compass.top_radius = 0.046
	compass.bottom_radius = 0.046
	compass.height = 0.018
	compass.radial_segments = 20
	_mesh(compass, brass, _item, Vector3.ZERO, Vector3.ZERO)
	var face := CylinderMesh.new()
	face.top_radius = 0.038
	face.bottom_radius = 0.038
	face.height = 0.020
	face.radial_segments = 20
	_mesh(face, dark, _item, Vector3(0.0, 0.003, 0.0), Vector3.ZERO)
	var needle := BoxMesh.new()
	needle.size = Vector3(0.008, 0.023, 0.004)
	_mesh(needle, _material(Color(0.62, 0.08, 0.045), 0.55), _item,
			Vector3(0.0, 0.016, 0.0), Vector3(0.0, 0.0, deg_to_rad(22.0)))
	_apply_pose(0.0, 0.0)


func _build_body_straps() -> void:
	_body_straps = Node3D.new()
	_body_straps.name = "WornBackpackStraps"
	_camera.add_child(_body_straps)
	var strap_mat := _material(Color(0.075, 0.082, 0.058), 0.97)
	for sx in [-1.0, 1.0]:
		_tube(Vector3(sx * 0.205, -0.155, -0.235),
				Vector3(sx * 0.255, -0.365, -0.275), 0.017, strap_mat,
				_body_straps)
		_tube(Vector3(sx * 0.255, -0.365, -0.275),
				Vector3(sx * 0.310, -0.525, -0.245), 0.014, strap_mat,
				_body_straps)


func _build_focus() -> void:
	_focus_layer = CanvasLayer.new()
	_focus_layer.layer = 1
	add_child(_focus_layer)
	_focus_rect = ColorRect.new()
	_focus_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_focus_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_focus_material = ShaderMaterial.new()
	_focus_material.shader = load("res://shaders/backpack_focus.gdshader")
	_focus_rect.material = _focus_material
	_focus_rect.visible = false
	_focus_layer.add_child(_focus_rect)


func _mesh(mesh: Mesh, material: Material, parent: Node3D, pos: Vector3,
		rot: Vector3) -> MeshInstance3D:
	mesh.surface_set_material(0, material)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = pos
	node.rotation = rot
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node


func _tube(a: Vector3, b: Vector3, radius: float, material: Material,
		parent: Node3D) -> MeshInstance3D:
	var d := b - a
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = d.length()
	mesh.radial_segments = 8
	var node := _mesh(mesh, material, parent, (a + b) * 0.5, Vector3.ZERO)
	if d.length_squared() > 1e-8:
		node.basis = Basis(Quaternion(Vector3.UP, d.normalized()))
	return node


func _material(color: Color, roughness: float,
		metallic := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material
