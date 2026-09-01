class_name DeckBagVisualBuilder
extends RefCounted
## Procedural construction for DeckBag3D. Returns the anchors and deformable
## pieces required by runtime inventory/motion code; owns no gameplay state.

const UtilityKnifeScript := preload("res://scripts/utility_knife.gd")
const HuntingRifleScript := preload("res://scripts/hunting_rifle.gd")
const DeckBagLayoutScript := preload("res://scripts/deck_bag_layout.gd")
const SLOT_POSITIONS := DeckBagLayoutScript.SLOT_POSITIONS
const SLOT_LABELS := DeckBagLayoutScript.SLOT_LABELS
const KNIFE_SLOT := DeckBagLayoutScript.KNIFE_SLOT
const RIFLE_SLOT := DeckBagLayoutScript.RIFLE_SLOT

var _host: Node3D
var _slot_anchors: Array[Node3D] = []
var _pointer_anchors: Array[Node3D] = []
var _slot_items: Array = []
var _tool_loop_parts: Dictionary = {}
var _tool_loop_rest: Dictionary = {}
var _rifle_sling_parts: Array[MeshInstance3D] = []
var _rifle_sling_rest: Dictionary = {}
var _shoulder_strap_parts: Array[MeshInstance3D] = []
var _side_handle_parts: Array[MeshInstance3D] = []
var _side_handle_points := PackedVector3Array()
var _soft_canvas_parts: Array[MeshInstance3D] = []
var _soft_canvas_rest: Dictionary = {}
var _load_ring_parts: Array[MeshInstance3D] = []
var _load_ring_rest: Dictionary = {}


func _register_soft_canvas(part: MeshInstance3D) -> MeshInstance3D:
	_soft_canvas_parts.append(part)
	_soft_canvas_rest[part] = part.transform
	return part


func _register_load_ring(part: MeshInstance3D) -> MeshInstance3D:
	_load_ring_parts.append(part)
	_load_ring_rest[part] = part.transform
	return part


func _register_tool_loop(slot: int, part: MeshInstance3D) -> MeshInstance3D:
	if not _tool_loop_parts.has(slot):
		_tool_loop_parts[slot] = []
	(_tool_loop_parts[slot] as Array).append(part)
	_tool_loop_rest[part] = part.transform
	return part


func _register_rifle_sling(part: MeshInstance3D) -> MeshInstance3D:
	_rifle_sling_parts.append(part)
	_rifle_sling_rest[part] = part.transform
	return part

func _slot_transform(index: int) -> Transform3D:
	return DeckBagLayoutScript.slot_transform(index)


func _material(color: Color, roughness: float, metallic := 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	return mat


func _fabric_material(color: Color, worn: Color, wear: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/waxed_canvas.gdshader") as Shader
	mat.set_shader_parameter("base_color", color)
	mat.set_shader_parameter("worn_color", worn)
	mat.set_shader_parameter("wear_amount", wear)
	return mat


func _mesh_instance(mesh: Mesh, pos: Vector3, rot_deg: Vector3,
		material: Material, part_name: String, parent: Node3D = null) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = part_name
	part.mesh = mesh
	part.position = pos
	part.rotation_degrees = rot_deg
	part.material_override = material
	var owner: Node3D = parent if parent != null else _host
	owner.add_child(part)
	return part


func _box(size: Vector3, pos: Vector3, rot_deg: Vector3,
		material: Material, part_name := "BagPart", parent: Node3D = null) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _mesh_instance(mesh, pos, rot_deg, material, part_name, parent)


func _cylinder(radius: float, height: float, pos: Vector3, rot_deg: Vector3,
		material: Material, part_name := "BagPart", segments := 12,
		parent: Node3D = null) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	return _mesh_instance(mesh, pos, rot_deg, material, part_name, parent)


func _ellipsoid(size: Vector3, pos: Vector3, rot_deg: Vector3,
		material: Material, part_name: String) -> MeshInstance3D:
	## A low-poly padded lobe is a better cloth silhouette than another bevel-less
	## box.  SphereMesh supplies smooth normals; non-uniform scale makes the
	## stuffed canvas volume while keeping the procedural asset lightweight.
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 24
	mesh.rings = 12
	var part := _mesh_instance(mesh, pos, rot_deg, material, part_name)
	part.scale = size
	return part


func _ring(inner_radius: float, outer_radius: float, pos: Vector3,
		rot_deg: Vector3, material: Material, part_name: String) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner_radius
	mesh.outer_radius = outer_radius
	mesh.rings = 14
	mesh.ring_segments = 8
	return _mesh_instance(mesh, pos, rot_deg, material, part_name)


func _flat_strap_piece(from: Vector3, to: Vector3, width: float,
		thickness: float, material: Material, part_name: String) -> MeshInstance3D:
	## A flat leather band between two authored points in the bag's front plane.
	## Individual short pieces form a gentle curve without turning leather into
	## the round hose/cylinder silhouette the old handle used.
	var delta := to - from
	var angle := rad_to_deg(atan2(delta.y, delta.x))
	return _box(Vector3(delta.length(), width, thickness), from.lerp(to, 0.5),
			Vector3(0.0, 0.0, angle), material, part_name)


func _elastic_strap_piece(from: Vector3, to: Vector3, width: float,
		thickness: float, material: Material, part_name: String) -> MeshInstance3D:
	## Rounded woven elastic between two points. A flattened ellipsoid removes the
	## rigid timber-like corners while preserving the exact authored load path.
	var delta := to - from
	var angle := rad_to_deg(atan2(delta.y, delta.x))
	return _ellipsoid(Vector3(delta.length(), width, thickness),
			from.lerp(to, 0.5), Vector3(0.0, 0.0, angle), material, part_name)


func _strap_piece_3d(from: Vector3, to: Vector3, width: float,
		thickness: float, material: Material, part_name: String) -> MeshInstance3D:
	## A thin flat band whose long axis may curve toward the camera. This is used
	## for retainers wrapping a prop; the older XY-only helper could only produce
	## one broad plank across the front of the knife.
	var delta := to - from
	var x_axis := delta.normalized()
	var y_axis := Vector3.UP - Vector3.UP.project(x_axis)
	if y_axis.length_squared() < 0.001:
		y_axis = Vector3.FORWARD - Vector3.FORWARD.project(x_axis)
	y_axis = y_axis.normalized()
	var z_axis := x_axis.cross(y_axis).normalized()
	y_axis = z_axis.cross(x_axis).normalized()
	var piece := _box(Vector3(delta.length() * 1.06, width, thickness),
			from.lerp(to, 0.5), Vector3.ZERO, material, part_name)
	piece.basis = Basis(x_axis, y_axis, z_axis)
	return piece


func _cubic_strap_point(a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		t: float) -> Vector3:
	var u := 1.0 - t
	return a * (u * u * u) + b * (3.0 * u * u * t) \
			+ c * (3.0 * u * t * t) + d * (t * t * t)


func _buckle(center: Vector3, width: float, height: float,
		brass: Material, prefix: String) -> void:
	var bar := 0.008
	var z := center.z
	_box(Vector3(width, bar, bar), center + Vector3(0.0, height * 0.5, 0.0),
			Vector3.ZERO, brass, prefix + "Top")
	_box(Vector3(width, bar, bar), center - Vector3(0.0, height * 0.5, 0.0),
			Vector3.ZERO, brass, prefix + "Bottom")
	_box(Vector3(bar, height, bar), Vector3(center.x - width * 0.5, center.y, z),
			Vector3.ZERO, brass, prefix + "Left")
	_box(Vector3(bar, height, bar), Vector3(center.x + width * 0.5, center.y, z),
			Vector3.ZERO, brass, prefix + "Right")
	_box(Vector3(width * 0.78, 0.006, 0.006), center,
			Vector3.ZERO, brass, prefix + "Tongue")


func _stitch_line(from: Vector3, to: Vector3, count: int,
		stitch: Material, prefix: String) -> void:
	for i in count:
		var t := (float(i) + 0.5) / float(count)
		var p := from.lerp(to, t)
		var along := to - from
		var horizontal := absf(along.x) > absf(along.y)
		var size := Vector3(0.020, 0.004, 0.004) if horizontal \
				else Vector3(0.004, 0.020, 0.004)
		_box(size, p, Vector3.ZERO, stitch, "%s%02d" % [prefix, i])


func build(host: Node3D) -> Dictionary:
	_host = host
	var canvas := _fabric_material(Color(0.105, 0.115, 0.096),
			Color(0.205, 0.190, 0.130), 0.31)
	var canvas_dark := _fabric_material(Color(0.060, 0.064, 0.054),
			Color(0.145, 0.135, 0.095), 0.24)
	var canvas_wear := _material(Color(0.155, 0.158, 0.125), 0.99)
	var slot_imprint := _material(Color(0.043, 0.047, 0.038), 0.99)
	var leather := _material(Color(0.145, 0.080, 0.045), 0.91)
	var leather_edge := _material(Color(0.075, 0.043, 0.028), 0.96)
	var aged_leather := _material(Color(0.245, 0.128, 0.060), 0.97)
	var brass := _material(Color(0.42, 0.30, 0.12), 0.38, 0.78)
	var steel := _material(Color(0.26, 0.27, 0.27), 0.42, 0.72)
	var steel_dark := _material(Color(0.090, 0.095, 0.098), 0.58, 0.56)
	var zipper_metal := _material(Color(0.20, 0.18, 0.13), 0.48, 0.62)
	var rifle_elastic := _fabric_material(Color(0.030, 0.034, 0.029),
			Color(0.095, 0.090, 0.065), 0.12)
	var flare_red := _material(Color(0.43, 0.055, 0.035), 0.75, 0.05)
	var glass := _material(Color(0.34, 0.42, 0.38), 0.12)
	var thread := _material(Color(0.50, 0.39, 0.23), 0.98)

	# Canvas volume. The box is only the opaque core; three shallow padded lobes
	# and mismatched edge rolls own the visible silhouette. Their few-millimetre
	# overlap reads as packed waxed cloth instead of a flat equipment board.
	_register_soft_canvas(_box(Vector3(0.48, 0.34, 0.135),
			Vector3(0.0, -0.025, 0.0), Vector3.ZERO, canvas, "CanvasBody"))
	_register_soft_canvas(_ellipsoid(Vector3(0.445, 0.285, 0.122),
			Vector3(-0.010, -0.030, 0.028), Vector3(0.0, 0.0, -1.5),
			canvas, "StuffedMainPanel"))
	_register_soft_canvas(_ellipsoid(Vector3(0.215, 0.255, 0.105),
			Vector3(-0.115, -0.040, 0.044), Vector3(0.0, 0.0, -4.0),
			canvas, "StuffedPortLobe"))
	_register_soft_canvas(_ellipsoid(Vector3(0.205, 0.238, 0.098),
			Vector3(0.125, -0.050, 0.040), Vector3(0.0, 0.0, 3.0),
			canvas_dark, "StuffedStarboardLobe"))
	_register_soft_canvas(_cylinder(0.040, 0.29,
			Vector3(-0.235, -0.018, 0.0), Vector3(0.0, 0.0, -1.5),
			canvas_dark, "LeftCanvasRoll"))
	_register_soft_canvas(_cylinder(0.040, 0.29,
			Vector3(0.235, -0.032, 0.0), Vector3(0.0, 0.0, 1.0),
			canvas_dark, "RightCanvasRoll"))
	_register_soft_canvas(_cylinder(0.038, 0.45,
			Vector3(0.0, -0.195, 0.0), Vector3(0.0, 0.0, 90.0),
			canvas_dark, "BottomCanvasRoll"))
	_register_soft_canvas(_cylinder(0.033, 0.48,
			Vector3(0.0, 0.185, 0.005), Vector3(0.0, 0.0, 90.0),
			canvas, "RolledMouth"))

	# Open clamshell architecture. A recessed organiser panel and a thick,
	# continuous padded lip make this read as a real opened backpack rather than
	# equipment attached to a flat board. The zipper teeth sit on the inner edge,
	# safely outside every selectable prop and finger target.
	_register_soft_canvas(_box(Vector3(0.430, 0.300, 0.030),
			Vector3(0.0, -0.025, 0.078), Vector3.ZERO,
			canvas_dark, "RecessedOrganizerPanel"))
	for x in [-0.224, 0.224]:
		_register_soft_canvas(_cylinder(0.020, 0.315,
				Vector3(x, -0.025, 0.103), Vector3.ZERO,
				canvas, "ClamshellSideLip"))
	for y in [-0.178, 0.128]:
		_register_soft_canvas(_cylinder(0.020, 0.448,
				Vector3(0.0, y, 0.103), Vector3(0.0, 0.0, 90.0),
				canvas, "ClamshellHorizontalLip"))
	# Short alternating teeth imply a heavy two-way marine zipper without a
	# noisy high-poly chain. Corners deliberately remain cloth so they can flex.
	for i in 13:
		var zipper_x := lerpf(-0.192, 0.192, float(i) / 12.0)
		for zipper_y in [-0.157, 0.107]:
			_box(Vector3(0.016, 0.007, 0.008),
					Vector3(zipper_x, zipper_y, 0.124), Vector3.ZERO,
					zipper_metal, "ZipperToothHorizontal")
	for i in 8:
		var zipper_y := lerpf(-0.130, 0.080, float(i) / 7.0)
		for zipper_x in [-0.203, 0.203]:
			_box(Vector3(0.007, 0.016, 0.008),
					Vector3(zipper_x, zipper_y, 0.124), Vector3.ZERO,
					zipper_metal, "ZipperToothVertical")

	# MOLLE/PALS organiser sewn into the inner wall. Horizontal webbing remains
	# behind the dedicated retainers; vertical stitch breaks provide the modular
	# grid visible in the reference without turning the inventory into UI tiles.
	for row in 5:
		var molle_y := -0.132 + float(row) * 0.058
		_box(Vector3(0.390, 0.018, 0.008), Vector3(0.0, molle_y, 0.108),
				Vector3.ZERO, leather_edge, "MolleWebbingRow%02d" % row)
		for column in 7:
			var stitch_x := -0.168 + float(column) * 0.056
			_box(Vector3(0.004, 0.020, 0.004),
					Vector3(stitch_x, molle_y, 0.114), Vector3.ZERO,
					thread, "MolleBarTack%02d_%02d" % [row, column])

	# Shallow side utility pouches give the open bag the same layered silhouette
	# as its closed exterior. They stay behind the side carry loop and never cover
	# slot one or its pointing volume.
	for side: float in [-1.0, 1.0]:
		var side_x: float = side * 0.274
		_register_soft_canvas(_ellipsoid(Vector3(0.090, 0.205, 0.078),
				Vector3(side_x, -0.045, 0.020), Vector3(0.0, 0.0, side * 2.5),
				canvas_dark, "SideUtilityPouch"))
		_box(Vector3(0.078, 0.045, 0.016), Vector3(side_x, 0.038, 0.068),
				Vector3(-8.0, 0.0, side * 2.0), leather, "SidePouchFlap")
		_buckle(Vector3(side_x, 0.025, 0.081), 0.030, 0.028,
				brass, "SidePouchBuckle")

	# A broad flap and two old closure straps.  The flap stands a little proud
	# of the body so its shadow survives the dim cabin lighting.
	_box(Vector3(0.455, 0.145, 0.024), Vector3(0.0, 0.105, 0.082),
			Vector3(-5.0, 0.0, 0.0), canvas_dark, "TopFlap")
	_register_soft_canvas(_ellipsoid(Vector3(0.430, 0.128, 0.050),
			Vector3(-0.008, 0.112, 0.087), Vector3(0.0, 0.0, -5.0),
			canvas_dark, "PaddedTopFlap"))
	_box(Vector3(0.435, 0.026, 0.012), Vector3(0.0, 0.168, 0.099),
			Vector3.ZERO, leather_edge, "FlapEdge")
	for x in [-0.155, 0.155]:
		_box(Vector3(0.032, 0.315, 0.014), Vector3(x, -0.006, 0.092),
				Vector3.ZERO, leather, "ClosureStrap")
		_buckle(Vector3(x, 0.070, 0.105), 0.052, 0.048, brass, "ClosureBuckle")

	# Old carry strap: both ends are visibly riveted into reinforced leather tabs
	# on the bag's rolled mouth. A shallow, asymmetric arch reads as softened,
	# load-bearing hide; a perfect round cylinder read as a loose rubber hose.
	for x in [-0.180, 0.180]:
		_box(Vector3(0.042, 0.104, 0.014), Vector3(x, 0.178, 0.072),
				Vector3(0.0, 0.0, -8.0 * signf(x)), leather_edge,
				"CarryStrapTab")
		_cylinder(0.007, 0.008, Vector3(x, 0.157, 0.082),
				Vector3(90.0, 0.0, 0.0), brass, "CarryStrapRivet", 10)
		_stitch_line(Vector3(x - 0.012, 0.142, 0.081),
				Vector3(x - 0.012, 0.204, 0.081), 4, thread,
				"CarryTabStitch")
	var carry_curve := PackedVector3Array([
		Vector3(-0.180, 0.188, 0.076),
		Vector3(-0.181, 0.207, 0.078),
		Vector3(-0.145, 0.232, 0.080),
		Vector3(-0.090, 0.250, 0.081),
		Vector3(-0.030, 0.257, 0.082),
		Vector3(0.040, 0.256, 0.082),
		Vector3(0.105, 0.242, 0.081),
		Vector3(0.156, 0.215, 0.079),
		Vector3(0.180, 0.188, 0.076),
	])
	for index in carry_curve.size() - 1:
		_flat_strap_piece(carry_curve[index], carry_curve[index + 1], 0.030,
				0.010, aged_leather if index % 3 != 1 else leather_edge,
				"AgedCarryStrap%02d" % index)

	# Short side carry loop from the user's physical reference.  This is a real
	# load path stitched into the reinforced left roll: the palm lands on the
	# outer vertical run, leaving every front pocket readable and selectable.
	var side_carry_curve := PackedVector3Array([
		Vector3(-0.232, 0.116, 0.078),
		Vector3(-0.274, 0.120, 0.080),
		Vector3(-0.305, 0.094, 0.084),
		Vector3(-0.305, 0.052, 0.084),
		Vector3(-0.302, 0.012, 0.083),
		Vector3(-0.272, -0.010, 0.080),
		Vector3(-0.232, 0.000, 0.078),
	])
	_side_handle_points = side_carry_curve.duplicate()
	_side_handle_parts.clear()
	for index in side_carry_curve.size() - 1:
		var side_piece := _flat_strap_piece(side_carry_curve[index], side_carry_curve[index + 1],
				0.026, 0.009,
				aged_leather if index % 2 == 0 else leather_edge,
				"SideCarryLoop%02d" % index)
		_side_handle_parts.append(side_piece)
	_box(Vector3(0.050, 0.150, 0.014), Vector3(-0.231, 0.054, 0.072),
			Vector3.ZERO, leather, "SideCarryReinforcement")
	for stitch_y in [0.010, 0.052, 0.094]:
		_stitch_line(Vector3(-0.238, stitch_y, 0.080),
				Vector3(-0.218, stitch_y, 0.080), 2, thread,
				"SideCarryStitch")

	# The shoulder strap is sewn around the lower canvas roll, not pinned to an
	# arbitrary point on the face. Reinforced ears visibly travel behind the bag,
	# curl under its bottom edge and finish in load-bearing brass rings.
	for x in [-0.218, 0.218]:
		_flat_strap_piece(Vector3(x, -0.105, 0.072),
				Vector3(x, -0.190, 0.050), 0.040, 0.012, leather_edge,
				"ShoulderUnderwrap")
		_box(Vector3(0.048, 0.080, 0.016), Vector3(x, -0.157, 0.050),
				Vector3(8.0, 0.0, -4.0 * signf(x)), leather,
				"ShoulderStrapEar")
		for rivet_y in [-0.130, -0.166]:
			_cylinder(0.006, 0.009, Vector3(x, rivet_y, 0.061),
					Vector3(90.0, 0.0, 0.0), brass, "ShoulderEarRivet", 10)
		_register_load_ring(_ring(0.014, 0.022,
				Vector3(x, -0.184, 0.047),
				Vector3(90.0, 0.0, 0.0), brass, "ShoulderStrapRing"))
	# The long shoulder strap is still attached while the bag is swung into the
	# lap. It falls in a broad U behind the rifle rather than hovering beside the
	# wrist. Alternating worn panels break the procedural-perfect silhouette.
	var shoulder_curve := PackedVector3Array()
	_shoulder_strap_parts.clear()
	var left_curve := [
		Vector3(-0.218, -0.155, 0.038),
		Vector3(-0.300, -0.255, 0.040),
		Vector3(-0.270, -0.485, 0.052),
		Vector3(0.000, -0.495, 0.058),
	]
	var right_curve := [
		Vector3(0.000, -0.495, 0.058),
		Vector3(0.270, -0.485, 0.052),
		Vector3(0.300, -0.255, 0.040),
		Vector3(0.218, -0.155, 0.038),
	]
	for sample in 25:
		shoulder_curve.append(_cubic_strap_point(left_curve[0], left_curve[1],
				left_curve[2], left_curve[3], float(sample) / 24.0))
	for sample in range(1, 25):
		shoulder_curve.append(_cubic_strap_point(right_curve[0], right_curve[1],
				right_curve[2], right_curve[3], float(sample) / 24.0))
	for index in shoulder_curve.size() - 1:
		var strap_piece := _flat_strap_piece(shoulder_curve[index], shoulder_curve[index + 1],
				0.034, 0.007,
				aged_leather if floori(float(index) / 10.0) % 3 != 1 else leather,
				"AgedShoulderStrap%02d" % index)
		_shoulder_strap_parts.append(strap_piece)

	# Exterior quick-access fittings: each tool has its own root and physical
	# slot. These are the exact meshes the right hand removes; no inventory icon
	# or duplicate viewmodel is swapped in when E is pressed.
	var tool_z := 0.125
	_slot_anchors.clear()
	_pointer_anchors.clear()
	_slot_items.clear()
	for index in SLOT_POSITIONS.size():
		var anchor := Node3D.new()
		anchor.name = "Slot%d" % (index + 1)
		anchor.transform = _slot_transform(index)
		_host.add_child(anchor)
		_slot_anchors.append(anchor)
		var pointer_anchor := Node3D.new()
		pointer_anchor.name = "Slot%dPointer" % (index + 1)
		pointer_anchor.transform = _slot_transform(index)
		# Local +Z is the bag's camera-facing normal in inspection pose. Four
		# centimetres leaves the extended fingertip visibly clear of the prop.
		pointer_anchor.position += Vector3(0.0, 0.0, 0.040)
		if index == RIFLE_SLOT:
			pointer_anchor.set_meta("centre_point_roll", true)
		_host.add_child(pointer_anchor)
		_pointer_anchors.append(pointer_anchor)
		var item: Node3D
		if index == KNIFE_SLOT:
			item = UtilityKnifeScript.new() as Node3D
		elif index == RIFLE_SLOT:
			item = HuntingRifleScript.new() as Node3D
		else:
			item = Node3D.new()
		item.name = "BagItem%d" % (index + 1)
		item.transform = _slot_transform(index)
		item.set_meta("item_label", SLOT_LABELS[index])
		_host.add_child(item)
		_slot_items.append(item)
	# Brass flashlight.
	var flashlight := _slot_items[0] as Node3D
	_cylinder(0.024, 0.185, Vector3.ZERO, Vector3.ZERO,
			brass, "FlashlightBody", 16, flashlight)
	_cylinder(0.033, 0.035, Vector3(0.0, 0.110, 0.0), Vector3.ZERO,
			brass, "FlashlightHead", 16, flashlight)
	_cylinder(0.025, 0.006, Vector3(0.0, 0.130, 0.0), Vector3.ZERO,
			glass, "FlashlightLens", 16, flashlight)
	# Maritime flare.
	var flare := _slot_items[1] as Node3D
	_cylinder(0.019, 0.205, Vector3.ZERO, Vector3.ZERO,
			flare_red, "SignalFlare", 14, flare)
	_cylinder(0.022, 0.020, Vector3(0.0, 0.113, 0.0), Vector3.ZERO,
			steel_dark, "FlareCap", 14, flare)
	# Slot three is the imported utility knife itself; the same node leaves the
	# webbing, seats in the palm and performs the cut.
	# Folded steel multitool.
	var multitool := _slot_items[3] as Node3D
	_box(Vector3(0.045, 0.185, 0.025), Vector3.ZERO,
			Vector3.ZERO, steel, "Multitool", multitool)
	for y in [-0.115, 0.025]:
		_cylinder(0.009, 0.031, Vector3(0.0, y + 0.045, 0.002),
				Vector3(90.0, 0.0, 0.0), brass, "MultitoolRivet", 10, multitool)

	# Every object has the restraint a sailor would actually choose.  The dark,
	# compressed backing remains when an item leaves, so an empty slot reads as a
	# physical absence rather than a disabled UI cell.
	for index in 4:
		var x: float = SLOT_POSITIONS[index].x
		_box(Vector3(0.054, 0.205, 0.003), Vector3(x, -0.050, 0.102),
				Vector3.ZERO, slot_imprint, "Slot%dPressureGhost" % (index + 1))

	# 1 — brass torch: two narrow cylindrical wraps plus a stitched bottom cup.
	for y in [-0.096, 0.024]:
		_register_tool_loop(0, _box(Vector3(0.064, 0.017, 0.017),
				Vector3(SLOT_POSITIONS[0].x, y, tool_z + 0.020),
				Vector3.ZERO, aged_leather, "FlashlightRetainer"))
	_box(Vector3(0.072, 0.044, 0.020),
			Vector3(SLOT_POSITIONS[0].x, -0.148, 0.132),
			Vector3(-8.0, 0.0, 0.0), leather_edge, "FlashlightBottomCup")
	_stitch_line(Vector3(SLOT_POSITIONS[0].x - 0.026, -0.156, 0.145),
			Vector3(SLOT_POSITIONS[0].x + 0.026, -0.156, 0.145), 3,
			thread, "FlashlightCupStitch")

	# 2 — flare: a deep canvas sleeve carries its base; only one elasticised
	# throat band needs to open when the cylinder is pulled free.
	_box(Vector3(0.070, 0.108, 0.020),
			Vector3(SLOT_POSITIONS[1].x, -0.105, 0.124),
			Vector3.ZERO, canvas_dark, "FlareSleeve")
	_register_tool_loop(1, _box(Vector3(0.062, 0.016, 0.017),
			Vector3(SLOT_POSITIONS[1].x, 0.024, tool_z + 0.020),
			Vector3.ZERO, leather_edge, "FlareElasticThroat"))
	_stitch_line(Vector3(SLOT_POSITIONS[1].x - 0.027, -0.154, 0.139),
			Vector3(SLOT_POSITIONS[1].x + 0.027, -0.154, 0.139), 3,
			thread, "FlareSleeveStitch")

	# 3 — utility knife: a narrow leather sheath supports the imported knife;
	# the handle remains visible above one snap retainer.
	_box(Vector3(0.078, 0.225, 0.016), Vector3(SLOT_POSITIONS[2].x,
			-0.075, 0.078), Vector3.ZERO, leather_edge, "KnifeSheathBack")
	_box(Vector3(0.078, 0.038, 0.020), Vector3(SLOT_POSITIONS[2].x,
			-0.170, 0.102), Vector3.ZERO, leather, "KnifeSheathToe")
	var knife_x: float = SLOT_POSITIONS[2].x
	var knife_band_points := PackedVector3Array([
		Vector3(knife_x - 0.039, 0.012, 0.126),
		Vector3(knife_x - 0.019, 0.012, 0.142),
		Vector3(knife_x + 0.018, 0.012, 0.145),
		Vector3(knife_x + 0.039, 0.012, 0.127),
	])
	for band_index in knife_band_points.size() - 1:
		_register_tool_loop(2, _strap_piece_3d(knife_band_points[band_index],
				knife_band_points[band_index + 1], 0.012, 0.006,
				rifle_elastic, "KnifeElasticRetainer%02d" % band_index))
	# Offset snap at the actual opening end; it no longer reads as a decorative
	# button glued to the centre of a solid beam.
	_cylinder(0.0045, 0.006, Vector3(knife_x + 0.027, 0.012, 0.149),
			Vector3(90.0, 0.0, 0.0), brass, "KnifeRetainerSnap", 10)

	# 4 — multitool: a shallow gusseted pouch and weather flap.  The metal body
	# still protrudes enough to identify and grasp it.
	_box(Vector3(0.082, 0.190, 0.016), Vector3(SLOT_POSITIONS[3].x,
			-0.060, 0.104), Vector3.ZERO, canvas_dark, "MultitoolPouchBack")
	for side in [-1.0, 1.0]:
		_box(Vector3(0.014, 0.180, 0.036), Vector3(SLOT_POSITIONS[3].x
				+ side * 0.040, -0.065, 0.125),
				Vector3(0.0, side * 7.0, 0.0), leather_edge,
				"MultitoolPouchGusset")
	_register_tool_loop(3, _box(Vector3(0.088, 0.050, 0.018),
			Vector3(SLOT_POSITIONS[3].x, 0.052, 0.145),
			Vector3(-10.0, 0.0, 0.0), leather, "MultitoolPouchFlap"))
	_cylinder(0.007, 0.008, Vector3(SLOT_POSITIONS[3].x, 0.035, 0.158),
			Vector3(90.0, 0.0, 0.0), brass, "MultitoolSnap", 10)

	# Integrated long-gun compartment. Its padded back and perimeter are wider
	# than the upper organiser because the rifle dictates the shape of the bag.
	# The weapon remains completely exposed to the hand while the dark recess and
	# zipper line make it read as stored inside the pack, never floating below it.
	_register_soft_canvas(_box(Vector3(0.850, 0.185, 0.070),
			Vector3(0.0, -0.337, 0.045), Vector3.ZERO,
			canvas_dark, "RifleCompartmentBack"))
	_register_soft_canvas(_ellipsoid(Vector3(0.815, 0.155, 0.065),
			Vector3(-0.010, -0.340, 0.075), Vector3.ZERO,
			canvas, "RifleCompartmentPadding"))
	for y in [-0.432, -0.242]:
		_register_soft_canvas(_cylinder(0.024, 0.845,
				Vector3(0.0, y, 0.086), Vector3(0.0, 0.0, 90.0),
				canvas_dark, "RifleCompartmentLip"))
	for x in [-0.423, 0.423]:
		_register_soft_canvas(_cylinder(0.024, 0.170,
				Vector3(x, -0.337, 0.086), Vector3.ZERO,
				canvas_dark, "RifleCompartmentSide"))
	for i in 22:
		var rifle_zip_x := lerpf(-0.385, 0.385, float(i) / 21.0)
		_box(Vector3(0.018, 0.007, 0.007),
				Vector3(rifle_zip_x, -0.253, 0.111), Vector3.ZERO,
				zipper_metal, "RifleCompartmentZipper")
	# Hinge bridges make the upper organiser and lower gun compartment one
	# clamshell object, with actual load paths instead of two hovering panels.
	for x in [-0.165, 0.165]:
		_box(Vector3(0.058, 0.118, 0.018), Vector3(x, -0.226, 0.092),
				Vector3.ZERO, leather_edge, "ClamshellHinge")
		for hinge_y in [-0.258, -0.206]:
			_cylinder(0.006, 0.009, Vector3(x, hinge_y, 0.104),
					Vector3(90.0, 0.0, 0.0), brass, "ClamshellHingeRivet", 10)

	# Dedicated long-gun cradle below the ordinary inventory. Each restraint is a
	# real U around the rifle cross-section: rear leg attached to the bag, bridge
	# under the wood/receiver, and a front leather face touching the weapon. The
	# aft loop sits farther onto the stock instead of ending in empty air beside it.
	for x in [-0.355, 0.285]:
		var muzzle_loop: bool = float(x) > 0.0
		# The starboard restraint carries only the slim barrel. It must not reuse
		# the stock-sized U on the left: leave just enough leather clearance for
		# the bore tube and its wrapping.
		var band_w := 0.036 if muzzle_loop else 0.055
		var leg_h := 0.045 if muzzle_loop else 0.125
		# Barrel centre sits above the rifle wrapper origin. Raise the compact U as
		# a whole so its short legs actually flank the muzzle instead of hanging
		# below it in empty space.
		var leg_y := -0.274 if muzzle_loop else -0.320
		var rear_z := 0.123 if muzzle_loop else 0.112
		var front_z := 0.168 if muzzle_loop else 0.180
		var under_y := -0.303 if muzzle_loop else -0.382
		var under_d := 0.048 if muzzle_loop else 0.074
		var top_y := leg_y + leg_h * 0.5
		# The cradle is wider than the canvas body. A diagonal load strap joins
		# each loop to a reinforced lower corner instead of leaving it floating.
		var bag_x := 0.205 * signf(x)
		_box(Vector3(0.058, 0.072, 0.018), Vector3(bag_x, -0.165, 0.112),
				Vector3.ZERO, leather_edge, "RifleSlingAnchorTab")
		_cylinder(0.008, 0.012, Vector3(bag_x, -0.174, 0.124),
				Vector3(90.0, 0.0, 0.0), brass, "RifleSlingAnchorRivet", 10)
		var strap_start := Vector3(bag_x, -0.185, 0.120)
		var strap_end := Vector3(x, top_y, rear_z + 0.004)
		var connection_width := 0.030 if muzzle_loop else 0.040
		var elastic_curve := PackedVector3Array()
		for segment in 6:
			var curve_t := float(segment) / 5.0
			var curve_point := strap_start.lerp(strap_end, curve_t)
			curve_point.y -= sin(curve_t * PI) * 0.018
			curve_point.z += sin(curve_t * PI) * 0.005
			elastic_curve.append(curve_point)
		for segment in elastic_curve.size() - 1:
			_register_rifle_sling(_flat_strap_piece(elastic_curve[segment],
					elastic_curve[segment + 1], connection_width, 0.007,
					rifle_elastic, "RifleElasticConnection%02d" % segment))
		# Hidden/rear leg against the bag.
		var sling_rear := _box(Vector3(band_w, leg_h, 0.007),
				Vector3(x, leg_y, rear_z), Vector3.ZERO,
				rifle_elastic, "RifleElasticRear")
		# Lower return closes the U beneath the rifle rather than leaving two tabs.
		var sling_under := _box(Vector3(band_w, 0.007, under_d),
				Vector3(x, under_y, (rear_z + front_z) * 0.5), Vector3.ZERO,
				rifle_elastic, "RifleElasticUnder")
		# Camera-facing band crosses the actual stock/receiver surface.
		var sling_front := _box(Vector3(band_w, leg_h, 0.008),
				Vector3(x, leg_y, front_z), Vector3.ZERO,
				rifle_elastic, "RifleElasticFront")
		for sling_part in [sling_rear, sling_under, sling_front]:
			_register_rifle_sling(sling_part)
		_cylinder(0.009 if not muzzle_loop else 0.007,
				0.060 if not muzzle_loop else 0.040,
				Vector3(x, top_y, front_z - 0.002),
				Vector3(0.0, 0.0, 90.0), brass, "RifleSlingRivet", 10)

	# Worn salt bloom and hand repair.  Subtle raised patches catch the cabin
	# lamp without requiring a one-off texture asset.
	_box(Vector3(0.075, 0.050, 0.004), Vector3(-0.105, -0.145, 0.071),
			Vector3(0.0, 0.0, -8.0), canvas_wear, "SaltWear")
	_box(Vector3(0.060, 0.040, 0.006), Vector3(0.115, -0.135, 0.073),
			Vector3(0.0, 0.0, 5.0), canvas_dark, "CanvasRepair")
	# Faded vessel-store stencil. It is deliberately small and low contrast: an
	# old ownership mark on cloth, not a floating inventory title.
	_box(Vector3(0.075, 0.028, 0.005), Vector3(0.155, -0.158, 0.119),
			Vector3(0.0, 0.0, -4.0), canvas_wear, "FadedStorePatch")
	var store_mark := Label3D.new()
	store_mark.name = "FadedStoreMark"
	store_mark.text = "D-17"
	store_mark.font_size = 18
	store_mark.pixel_size = 0.00062
	store_mark.modulate = Color(0.34, 0.31, 0.22, 0.72)
	store_mark.outline_size = 0
	store_mark.position = Vector3(0.155, -0.158, 0.123)
	store_mark.rotation_degrees.z = -4.0
	_host.add_child(store_mark)
	_stitch_line(Vector3(-0.205, 0.150, 0.101), Vector3(0.205, 0.150, 0.101),
			12, thread, "FlapStitch")
	_stitch_line(Vector3(-0.215, -0.165, 0.072), Vector3(0.215, -0.165, 0.072),
			12, thread, "BottomStitch")
	_stitch_line(Vector3(-0.212, -0.145, 0.083), Vector3(-0.212, 0.135, 0.083),
			9, thread, "PortEdgeStitch")
	_stitch_line(Vector3(0.212, -0.150, 0.081), Vector3(0.212, 0.128, 0.081),
			9, thread, "StarboardEdgeStitch")
	_stitch_line(Vector3(0.086, -0.154, 0.080), Vector3(0.145, -0.149, 0.080),
			4, thread, "RepairBottomStitch")
	_stitch_line(Vector3(0.086, -0.116, 0.080), Vector3(0.145, -0.111, 0.080),
			4, thread, "RepairTopStitch")
	return {
		"_slot_anchors": _slot_anchors,
		"_pointer_anchors": _pointer_anchors,
		"_slot_items": _slot_items,
		"_tool_loop_parts": _tool_loop_parts,
		"_tool_loop_rest": _tool_loop_rest,
		"_rifle_sling_parts": _rifle_sling_parts,
		"_rifle_sling_rest": _rifle_sling_rest,
		"_shoulder_strap_parts": _shoulder_strap_parts,
		"_side_handle_parts": _side_handle_parts,
		"_side_handle_points": _side_handle_points,
		"_soft_canvas_parts": _soft_canvas_parts,
		"_soft_canvas_rest": _soft_canvas_rest,
		"_load_ring_parts": _load_ring_parts,
		"_load_ring_rest": _load_ring_rest,
	}
