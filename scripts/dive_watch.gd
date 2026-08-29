extends Node3D
## Wrist dive computer: a simple brass case with a green LED module. Time of
## day, depth and hydrostatic pressure. Built in place so it takes the boat's
## light like any other fitting, and the digits stay emissive in the murk.

var _line_t: Label3D
var _line_d: Label3D
var _line_p: Label3D
var _line_m: Label3D


func _ready() -> void:
	_build_case()
	_build_strap()
	_build_screen()


func set_readout(tod: float, depth_m: float, wet: bool) -> void:
	if _line_t == null:
		return
	var h := wrapi(int(tod), 0, 24)
	var mins := wrapi(int(tod * 60.0), 0, 60)
	var sec := wrapi(int(Time.get_ticks_msec() / 1000.0), 0, 60)
	_line_t.text = "%02d:%02d:%02d" % [h, mins, sec]
	_line_d.text = "D  %5.1f m" % depth_m
	_line_p.text = "P  %5.2f bar" % (1.013 + depth_m * 0.0981)
	_line_m.text = "DIVE" if wet else "SURF"
	_line_m.modulate = Color(0.35, 1.0, 0.45) if wet else Color(0.25, 0.85, 0.40)


func _mat_brass(rough := 0.32, dark := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.64, 0.48, 0.22).lerp(Color(0.28, 0.20, 0.10), dark)
	m.metallic = 0.88
	m.roughness = rough
	m.disable_fog = true
	return m


func _mat_leather() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.07, 0.045, 0.035)
	m.roughness = 0.92
	m.metallic = 0.0
	m.disable_fog = true
	return m


func _mat_glass() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.02, 0.06, 0.04, 0.42)
	m.metallic = 0.15
	m.roughness = 0.06
	m.emission_enabled = true
	m.emission = Color(0.05, 0.22, 0.08)
	m.emission_energy_multiplier = 0.35
	m.disable_fog = true
	return m


func _mesh(mesh: Mesh, mat: Material, xf: Transform3D) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.transform = xf
	add_child(mi)


func _build_case() -> void:
	var brass := _mat_brass()
	var brass_dark := _mat_brass(0.45, 0.45)
	var case := CylinderMesh.new()
	case.top_radius = 0.023
	case.bottom_radius = 0.0235
	case.height = 0.011
	case.radial_segments = 24
	_mesh(case, brass, Transform3D(Basis.IDENTITY, Vector3.ZERO))

	var bezel := TorusMesh.new()
	bezel.inner_radius = 0.0175
	bezel.outer_radius = 0.0235
	bezel.rings = 10
	bezel.ring_segments = 24
	_mesh(bezel, brass_dark, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0062, 0.0)))

	var lugs := BoxMesh.new()
	lugs.size = Vector3(0.016, 0.006, 0.010)
	_mesh(lugs, brass, Transform3D(Basis.IDENTITY, Vector3(0.0, -0.001, 0.022)))
	_mesh(lugs, brass, Transform3D(Basis.IDENTITY, Vector3(0.0, -0.001, -0.022)))

	var crown := CylinderMesh.new()
	crown.top_radius = 0.0032
	crown.bottom_radius = 0.0036
	crown.height = 0.007
	crown.radial_segments = 10
	var cr := Basis(Vector3.FORWARD, PI * 0.5)
	_mesh(crown, brass, Transform3D(cr, Vector3(0.026, 0.0, 0.0)))

	var screw := SphereMesh.new()
	screw.radius = 0.0016
	screw.height = 0.0032
	screw.radial_segments = 8
	screw.rings = 4
	for i in 4:
		var a := float(i) * TAU * 0.25 + 0.4
		_mesh(screw, brass_dark, Transform3D(Basis.IDENTITY,
				Vector3(cos(a) * 0.0195, 0.0064, sin(a) * 0.0195)))

	var glass := CylinderMesh.new()
	glass.top_radius = 0.017
	glass.bottom_radius = 0.017
	glass.height = 0.0022
	glass.radial_segments = 20
	_mesh(glass, _mat_glass(), Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0056, 0.0)))


func _build_strap() -> void:
	var leather := _mat_leather()
	var brass := _mat_brass(0.40, 0.2)
	var strap := BoxMesh.new()
	strap.size = Vector3(0.018, 0.0036, 0.034)
	_mesh(strap, leather, Transform3D(Basis.IDENTITY, Vector3(0.0, -0.005, 0.038)))
	_mesh(strap, leather, Transform3D(Basis.IDENTITY, Vector3(0.0, -0.005, -0.038)))
	var buckle := BoxMesh.new()
	buckle.size = Vector3(0.014, 0.003, 0.008)
	_mesh(buckle, brass, Transform3D(Basis.IDENTITY, Vector3(0.0, -0.004, 0.054)))
	var stitch := BoxMesh.new()
	stitch.size = Vector3(0.012, 0.0006, 0.028)
	var stitch_mat := leather.duplicate() as StandardMaterial3D
	stitch_mat.albedo_color = Color(0.14, 0.09, 0.06)
	_mesh(stitch, stitch_mat, Transform3D(Basis.IDENTITY, Vector3(0.0, -0.003, 0.038)))
	_mesh(stitch, stitch_mat, Transform3D(Basis.IDENTITY, Vector3(0.0, -0.003, -0.038)))


func _build_screen() -> void:
	var plate := QuadMesh.new()
	plate.size = Vector2(0.030, 0.022)
	var plate_mat := StandardMaterial3D.new()
	plate_mat.albedo_color = Color(0.01, 0.03, 0.015)
	plate_mat.roughness = 0.55
	plate_mat.emission_enabled = true
	plate_mat.emission = Color(0.02, 0.10, 0.04)
	plate_mat.emission_energy_multiplier = 0.4
	plate_mat.disable_fog = true
	_mesh(plate, plate_mat, Transform3D(Basis(Vector3.RIGHT, -PI * 0.5),
			Vector3(0.0, 0.0050, 0.0)))

	_line_t = _led(24, Vector3(0.0, 0.0054, -0.0055))
	_line_d = _led(14, Vector3(0.0, 0.0054, 0.0008))
	_line_p = _led(14, Vector3(0.0, 0.0054, 0.0054))
	_line_m = _led(11, Vector3(0.0, 0.0054, 0.0096))
	_line_t.text = "00:00:00"
	_line_d.text = "D   0.0 m"
	_line_p.text = "P  1.01 bar"
	_line_m.text = "SURF"


func _led(size: int, pos: Vector3) -> Label3D:
	var lab := Label3D.new()
	lab.font_size = size
	lab.pixel_size = 0.00042
	lab.modulate = Color(0.30, 1.0, 0.42)
	lab.outline_modulate = Color(0.02, 0.12, 0.04, 0.85)
	lab.outline_size = 4
	lab.shaded = false
	lab.double_sided = false
	lab.no_depth_test = false
	lab.position = pos
	lab.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(lab)
	return lab
