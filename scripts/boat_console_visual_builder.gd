class_name BoatConsoleVisualBuilder
extends RefCounted

const BoatVisuals := preload("res://scripts/boat_visual_factory.gd")

var _dial_ink: StandardMaterial3D
var _compass_card: Node3D


func build(owner: Node3D, trim: Material, metal: Material) -> Dictionary:
	var bronze := BoatVisuals.material(Color(0.28, 0.21, 0.12), 0.52, 0.62)
	var dial_face := ShaderMaterial.new()
	dial_face.shader = load("res://shaders/dial.gdshader")
	dial_face.set_shader_parameter("albedo", Color(0.055, 0.050, 0.040))
	dial_face.set_shader_parameter("dirt", 0.64)
	dial_face.set_shader_parameter("radium", 0.03)
	dial_face.set_shader_parameter("flicker", 1.0)
	_dial_ink = BoatVisuals.material(Color(0.34, 0.42, 0.14), 0.78)
	_dial_ink.emission_enabled = true
	_dial_ink.emission = Color(0.42, 0.92, 0.16)
	_dial_ink.emission_energy_multiplier = 1.55
	_box(Vector3(1.86, 0.54, 0.32), Vector3(0.0, 3.20, -0.10),
			Vector3.ZERO, trim, owner)
	var face := Node3D.new()
	face.name = "AnalogConsoleFace"
	face.position = Vector3(0.0, 3.60, -0.04)
	face.rotation_degrees.x = 42.0
	owner.add_child(face)
	_box(Vector3(1.86, 0.03, 0.32), Vector3.ZERO, Vector3.ZERO, metal, face)
	var radius := 0.070
	var needles: Array[Node3D] = []
	needles.append(_make_dial(face, -0.36, radius, "PARAKETE",
			["0", "10", "20"], bronze, dial_face, "kn"))
	needles.append(_make_dial(face, -0.16, radius, "İSKANDİL",
			["0", "20", "40"], bronze, dial_face, "m"))
	needles.append(_make_dial(face, 0.24, radius, "ZİNCİR",
			["0", "35", "70"], bronze, dial_face, "m"))
	_make_compass(face, 0.04, radius, bronze, dial_face)
	return {
		"bronze": bronze,
		"dial_face": dial_face,
		"dial_ink": _dial_ink,
		"face": face,
		"needles": needles,
		"compass_card": _compass_card,
	}


func _dial_label(parent: Node3D, text: String, pos: Vector3, size: int,
		shade: Color) -> void:
	## Phosphor numerals: unshaded so they read in the dark without a lamp.
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.00040
	l.modulate = shade
	l.outline_size = 3
	l.outline_modulate = Color(0.04, 0.08, 0.02, 0.55)
	l.shaded = false
	l.double_sided = false
	l.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	l.position = pos
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)


func _dial_body(parent: Node3D, x: float, r: float, bezel: Material,
		dial_face: Material) -> Node3D:
	## Small tarnished well. Dial "up" is local -Z. All four sit on the same
	## plane so the row stays straight.
	var g := Node3D.new()
	g.position = Vector3(x, 0.022, 0.0)
	parent.add_child(g)
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = 0.006
	cm.radial_segments = 22
	cm.material = dial_face
	disc.mesh = cm
	g.add_child(disc)
	var bez := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = r - 0.002
	tm.outer_radius = r + 0.010
	tm.rings = 18
	tm.ring_segments = 6
	tm.material = bezel
	bez.mesh = tm
	bez.position = Vector3(0.0, 0.004, 0.0)
	g.add_child(bez)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.08, 0.10, 0.07, 0.05)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.48
	glass.metallic = 0.0
	var pane := MeshInstance3D.new()
	var gp := CylinderMesh.new()
	gp.top_radius = r - 0.006
	gp.bottom_radius = r - 0.006
	gp.height = 0.002
	gp.radial_segments = 16
	gp.material = glass
	pane.mesh = gp
	pane.position = Vector3(0.0, 0.010, 0.0)
	pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.add_child(pane)
	return g


func _dial_tick(parent: Node3D, deg: float, r: float, length: float,
		width: float, mat: Material = null) -> void:
	## Dial angle: 0 is straight up, positive clockwise as the helm sees it.
	var a := deg_to_rad(deg)
	var d := r - length * 0.5 - 0.008
	_box(Vector3(width, 0.004, length),
			Vector3(sin(a) * d, 0.008, -cos(a) * d),
			Vector3(0.0, -deg, 0.0), mat if mat != null else _dial_ink, parent)


func _make_dial(parent: Node3D, x: float, r: float, caption: String,
		nums: Array, bezel: Material, dial_face: Material,
		unit := "") -> Node3D:
	var g := _dial_body(parent, x, r, bezel, dial_face)
	var n: int = maxi(nums.size(), 2)
	var span := 240.0
	var step := span / float(n - 1)
	# Minor ticks between the numbered majors.
	for i in (n - 1) * 2 + 1:
		var deg := -120.0 + float(i) * (step * 0.5)
		var major := i % 2 == 0
		_dial_tick(g, deg, r, 0.016 if major else 0.008,
				0.004 if major else 0.002)
	for i in n:
		var deg := -120.0 + float(i) * step
		var a := deg_to_rad(deg)
		var d := r - 0.028
		_dial_label(g, str(nums[i]), Vector3(sin(a) * d, 0.008, -cos(a) * d),
				22, Color(0.62, 1.0, 0.28))
	_dial_label(g, caption, Vector3(0.0, 0.008, r * 0.20), 16,
			Color(0.38, 0.52, 0.18))
	if unit != "":
		_dial_label(g, unit, Vector3(0.0, 0.008, r * 0.40), 14,
				Color(0.34, 0.46, 0.16))

	var needle := Node3D.new()
	g.add_child(needle)
	_box(Vector3(0.004, 0.003, r * 0.68), Vector3(0.0, 0.008, -r * 0.28),
			Vector3.ZERO, _dial_ink, needle)
	_box(Vector3(0.006, 0.003, r * 0.18), Vector3(0.0, 0.008, r * 0.08),
			Vector3.ZERO, _dial_ink, needle)
	_cyl(0.009, 0.009, 0.006, Vector3(0.0, 0.009, 0.0), Vector3.ZERO, bezel, g)
	return needle


func _make_compass(parent: Node3D, x: float, r: float, bezel: Material,
		dial_face: Material) -> void:
	## A card compass, not a needle: the card stays with the earth and the ship
	## turns under it, so the heading is whatever sits under the lubber line.
	var g := _dial_body(parent, x, r, bezel, dial_face)
	_compass_card = Node3D.new()
	g.add_child(_compass_card)
	for i in 16:
		var deg := float(i) * 22.5
		var cardinal := i % 4 == 0
		_dial_tick(_compass_card, deg, r, 0.016 if cardinal else 0.008,
				0.004 if cardinal else 0.002)
	var pts := ["K", "D", "G", "B"]
	for i in 4:
		var a := deg_to_rad(float(i) * 90.0)
		var d := r - 0.028
		_dial_label(_compass_card, pts[i],
				Vector3(sin(a) * d, 0.008, -cos(a) * d), 20,
				Color(0.95, 0.38, 0.18) if i == 0 else Color(0.62, 1.0, 0.28))
	_box(Vector3(0.005, 0.003, r * 0.42), Vector3(0.0, 0.008, -r * 0.24),
			Vector3.ZERO, _dial_ink, _compass_card)
	_box(Vector3(0.008, 0.004, 0.016), Vector3(0.0, 0.010, -r + 0.012),
			Vector3.ZERO, _dial_ink, g)
	_dial_label(g, "PUSULA", Vector3(0.0, 0.008, r * 0.34), 14,
			Color(0.38, 0.52, 0.18))

func _box(size: Vector3, position: Vector3, rotation_degrees: Vector3,
		material: Material, parent: Node3D) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	instance.mesh = mesh
	instance.position = position
	instance.rotation_degrees = rotation_degrees
	parent.add_child(instance)
	return instance


func _cyl(bottom_radius: float, top_radius: float, height: float,
		position: Vector3, rotation_degrees: Vector3, material: Material,
		parent: Node3D) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = bottom_radius
	mesh.top_radius = top_radius
	mesh.height = height
	mesh.radial_segments = 10
	mesh.material = material
	instance.mesh = mesh
	instance.position = position
	instance.rotation_degrees = rotation_degrees
	parent.add_child(instance)
	return instance
