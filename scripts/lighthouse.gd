extends StaticBody3D
## Coastal lighthouse on a dedicated rock: tapered daymarked tower, gallery,
## glass lantern, and a rotating two-faced optic (real characteristic).

const PERIOD := 16.0  # seconds per revolution
const WeatherScript := preload("res://scripts/weather.gd")

var seabed: Node3D
var weather: Node3D
var _ocean: Node3D

var _optics: Node3D
var _spot_a: SpotLight3D
var _spot_b: SpotLight3D
var _lamp: OmniLight3D
var _lens_mat: StandardMaterial3D
var _beam_mat: ShaderMaterial
var _glass_mat: StandardMaterial3D


func _ready() -> void:
	if seabed == null:
		seabed = get_parent().get_node_or_null("Seabed")
	if weather == null:
		weather = get_parent().get_node_or_null("Weather")
	if _ocean == null:
		_ocean = get_parent().get_node_or_null("Ocean")
	_sit_on_rock()
	_build()
	# Yaw only — look_at would pitch the cottage off the rock.
	var to_origin := Vector2(-global_position.x, -global_position.z)
	if to_origin.length_squared() > 4.0:
		rotation.y = atan2(-to_origin.x, -to_origin.y)


func _sit_on_rock() -> void:
	var xz := Vector2(52.0, -186.0)
	if seabed != null:
		xz = Vector2(seabed.LIGHTHOUSE_X, seabed.LIGHTHOUSE_Z)
	var y := 6.5
	if seabed != null and seabed.has_method("get_height"):
		y = float(seabed.get_height(Vector3(xz.x, 0.0, xz.y)))
	global_position = Vector3(xz.x, y - 0.4, xz.y)


func _process(delta: float) -> void:
	if _optics != null:
		_optics.rotate_y(delta * TAU / PERIOD)
	var k := _night_k()
	if _spot_a != null:
		_spot_a.light_energy = 70.0 * k
		_spot_b.light_energy = 70.0 * k
		_spot_a.light_volumetric_fog_energy = 22.0 * k
		_spot_b.light_volumetric_fog_energy = 22.0 * k
		_lamp.light_energy = lerpf(0.8, 8.0, k)
		_lamp.light_volumetric_fog_energy = 4.0 * k
	if _lens_mat != null:
		_lens_mat.emission_energy_multiplier = lerpf(1.2, 12.0, k)
	if _glass_mat != null:
		_glass_mat.emission_energy_multiplier = lerpf(0.8, 7.0, k)
	if _beam_mat != null:
		_beam_mat.set_shader_parameter("intensity", k)
		# A beam is only visible because of what is in the air between you and
		# it, so fog and rain are what make it a shaft rather than a dot.
		var thickness := 0.35
		var w := weather as WeatherScript
		if w != null:
			thickness = clampf(w.fog_amount * 0.9 + w.rain_amount * 0.5, 0.0, 1.4)
		var hz := 0.55 + thickness * 1.05
		var rc := clampf(1.15 - thickness * 0.5, 0.35, 1.15)
		_beam_mat.set_shader_parameter("haze", hz)
		_beam_mat.set_shader_parameter("reach", rc)
	if _ocean != null and _spot_a != null and _ocean.has_method("set_lighthouse_beams"):
		_ocean.set_lighthouse_beams(
			_lamp.global_position if _lamp != null else global_position,
			-_spot_a.global_basis.z,
			-_spot_b.global_basis.z,
			k)


func _night_k() -> float:
	var w := weather as WeatherScript
	if w == null:
		return 1.0
	var t: float = w.time_of_day
	var elev := sin((t - 6.0) / 12.0 * PI)
	return clampf(1.0 - elev * 1.15, 0.06, 1.0)


func _mat(albedo: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = rough
	m.metallic = metal
	return m


func _build() -> void:
	var plaster := _mat(Color(0.88, 0.85, 0.78), 0.74)
	var red := _mat(Color(0.78, 0.16, 0.11), 0.55)
	var stone := _mat(Color(0.36, 0.34, 0.31), 0.92)
	var stone_dark := _mat(Color(0.24, 0.23, 0.21), 0.96)
	var metal := _mat(Color(0.14, 0.14, 0.15), 0.42, 0.72)
	var dark := _mat(Color(0.09, 0.08, 0.07), 0.85)
	var roof := _mat(Color(0.16, 0.14, 0.13), 0.62, 0.15)

	# Big rocky islet: volume from below the waterline up to the yard so
	# the tower and cottage never hang in empty air.
	_cyl(34.0, 29.0, 18.0, Vector3(0.0, -6.8, 0.0), stone)
	_cyl(31.0, 29.0, 5.0, Vector3(0.0, 2.4, 0.0), stone_dark)
	_cyl(28.0, 26.5, 2.4, Vector3(0.0, 4.6, 0.0), stone)
	_box(Vector3(10.0, 3.6, 7.0), Vector3(12.0, 0.2, 7.5), Vector3(0.0, 18.0, 0.0), stone)
	_box(Vector3(8.0, 4.2, 6.5), Vector3(-10.0, -0.2, 8.0), Vector3(0.0, -28.0, 0.0), stone_dark)
	_box(Vector3(7.5, 3.2, 9.0), Vector3(-12.0, -0.4, -8.5), Vector3(0.0, 14.0, 0.0), stone)
	_box(Vector3(9.0, 3.0, 6.0), Vector3(11.0, -0.2, -9.0), Vector3(0.0, -16.0, 0.0), stone_dark)
	_box(Vector3(8.5, 3.8, 6.2), Vector3(16.5, 0.1, 3.5), Vector3(0.0, 6.0, 0.0), stone)
	_box(Vector3(9.5, 3.4, 8.0), Vector3(15.5, -0.3, 8.8), Vector3(0.0, -10.0, 0.0), stone_dark)
	_box(Vector3(6.5, 5.0, 5.5), Vector3(-4.0, -1.0, 14.0), Vector3(0.0, 40.0, 0.0), stone)
	_box(Vector3(7.0, 4.4, 5.0), Vector3(5.5, -0.8, -14.5), Vector3(0.0, -38.0, 0.0), stone_dark)

	# Tapered shaft ~34 m, white with two red daymarks.
	_cyl(5.5, 2.9, 34.0, Vector3(0.0, 19.4, 0.0), plaster)
	_cyl(4.85, 4.35, 3.2, Vector3(0.0, 12.4, 0.0), red)
	_cyl(3.95, 3.45, 3.0, Vector3(0.0, 24.6, 0.0), red)

	# Door + stone stoop facing local -Z (toward spawn).
	_box(Vector3(1.35, 2.7, 0.2), Vector3(0.0, 6.55, -5.55), Vector3.ZERO, dark)
	_box(Vector3(1.8, 0.28, 1.4), Vector3(0.0, 5.15, -6.1), Vector3.ZERO, stone)
	_box(Vector3(0.7, 0.16, 1.05), Vector3(0.0, 5.38, -6.7), Vector3.ZERO, stone)
	_box(Vector3(0.7, 0.16, 0.85), Vector3(0.0, 5.56, -7.2), Vector3.ZERO, stone)

	# Windows around the shaft.
	for lvl in 4:
		var wy := 7.2 + float(lvl) * 6.6
		var wr := lerpf(5.15, 3.15, float(lvl) / 3.0)
		for k in 4:
			var a := float(k) * PI * 0.5 + 0.35
			var p := Vector3(sin(a) * wr, wy, -cos(a) * wr)
			_box(Vector3(0.78, 1.25, 0.14), p, Vector3(0.0, rad_to_deg(a), 0.0), dark)

	# Gallery deck + iron railing.
	_cyl(3.85, 3.85, 0.22, Vector3(0.0, 36.55, 0.0), stone)
	var rail_y := 37.15
	for i in 18:
		var a := float(i) / 18.0 * TAU
		_cyl(0.05, 0.05, 1.05, Vector3(sin(a) * 3.65, rail_y, cos(a) * 3.65), metal)
	_torus(3.65, 0.05, Vector3(0.0, 37.65, 0.0), metal)

	# Lantern room: metal cage + glowing glass so the lamp reads from a kilometre.
	_glass_mat = StandardMaterial3D.new()
	_glass_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glass_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_glass_mat.albedo_color = Color(1.0, 0.92, 0.7, 0.35)
	_glass_mat.emission_enabled = true
	_glass_mat.emission = Color(1.0, 0.9, 0.62)
	_glass_mat.emission_energy_multiplier = 7.0
	_glass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cyl(2.35, 2.35, 4.0, Vector3(0.0, 39.15, 0.0), _glass_mat)
	for i in 8:
		var a := float(i) / 8.0 * TAU
		_box(Vector3(0.09, 3.9, 0.09), Vector3(sin(a) * 2.32, 39.15, cos(a) * 2.32), Vector3.ZERO, metal)
	_cyl(2.45, 2.45, 0.18, Vector3(0.0, 37.25, 0.0), metal)
	_cyl(2.45, 2.45, 0.18, Vector3(0.0, 41.05, 0.0), metal)

	# Dome + vent ball + vane.
	var dome := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 2.4
	sm.height = 2.7
	sm.material = roof
	dome.mesh = sm
	dome.position = Vector3(0.0, 42.05, 0.0)
	add_child(dome)
	_cyl(0.14, 0.14, 1.25, Vector3(0.0, 43.55, 0.0), metal)
	_box(Vector3(0.95, 0.07, 0.2), Vector3(0.24, 44.1, 0.0), Vector3(0.0, 0.0, -18.0), metal)

	# Keeper's cottage on the stone terrace, not hanging off the shaft.
	_box(Vector3(8.4, 0.55, 6.8), Vector3(11.4, 3.75, 5.2), Vector3.ZERO, stone)
	_box(Vector3(6.2, 2.9, 4.4), Vector3(11.4, 5.45, 5.2), Vector3.ZERO, plaster)
	_box(Vector3(6.7, 0.16, 4.9), Vector3(11.4, 6.95, 5.2), Vector3.ZERO, roof)
	_box(Vector3(6.5, 1.25, 0.16), Vector3(11.4, 7.45, 5.2), Vector3(32.0, 0.0, 0.0), roof)
	_box(Vector3(6.5, 1.25, 0.16), Vector3(11.4, 7.45, 5.2), Vector3(-32.0, 0.0, 0.0), roof)
	_box(Vector3(0.85, 1.7, 0.12), Vector3(11.4, 4.95, 3.02), Vector3.ZERO, dark)
	_box(Vector3(0.7, 0.8, 0.1), Vector3(9.6, 5.6, 3.02), Vector3.ZERO, dark)
	_box(Vector3(0.7, 0.8, 0.1), Vector3(13.2, 5.6, 3.02), Vector3.ZERO, dark)

	_build_optic(metal)
	_build_collision()


func _build_optic(_metal: StandardMaterial3D) -> void:
	_optics = Node3D.new()
	_optics.position = Vector3(0.0, 39.15, 0.0)
	add_child(_optics)

	_lens_mat = StandardMaterial3D.new()
	_lens_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_lens_mat.albedo_color = Color(1.0, 0.94, 0.7)
	_lens_mat.emission_enabled = true
	_lens_mat.emission = Color(1.0, 0.93, 0.68)
	_lens_mat.emission_energy_multiplier = 12.0
	var lens := MeshInstance3D.new()
	var lm := SphereMesh.new()
	lm.radius = 1.05
	lm.height = 2.1
	lm.material = _lens_mat
	lens.mesh = lm
	_optics.add_child(lens)

	_beam_mat = ShaderMaterial.new()
	_beam_mat.shader = load("res://shaders/lighthouse_beam.gdshader")
	_beam_mat.set_shader_parameter("intensity", 1.0)
	_beam_mat.set_shader_parameter("gain", 1.0)

	_spot_a = _make_spot(0.0)
	_spot_b = _make_spot(180.0)
	_add_beam(0.0, 1.0, _beam_mat)
	_add_beam(180.0, 1.0, _beam_mat)

	_lamp = OmniLight3D.new()
	_lamp.light_color = Color(1.0, 0.9, 0.62)
	_lamp.light_energy = 8.0
	_lamp.omni_range = 55.0
	_lamp.omni_attenuation = 1.1
	_lamp.shadow_enabled = false
	_lamp.light_volumetric_fog_energy = 4.0
	_lamp.position = Vector3(0.0, 39.15, 0.0)
	add_child(_lamp)


func _make_spot(yaw_deg: float) -> SpotLight3D:
	var arm := Node3D.new()
	arm.rotation_degrees.y = yaw_deg
	_optics.add_child(arm)
	var s := SpotLight3D.new()
	# Start just outside the glass so the lantern cage doesn't eat the volume.
	s.position.z = -2.7
	s.rotation_degrees.x = 5.0
	s.light_color = Color(1.0, 0.93, 0.68)
	s.light_energy = 70.0
	s.spot_range = 900.0
	s.spot_angle = 14.0
	s.spot_attenuation = 0.35
	s.spot_angle_attenuation = 0.4
	s.light_specular = 1.0
	s.shadow_enabled = false
	s.light_volumetric_fog_energy = 18.0
	s.light_cull_mask = 0xFFFFF
	arm.add_child(s)
	return s


func _add_beam(yaw_deg: float, spread: float, mat: ShaderMaterial) -> void:
	const LEN := 520.0
	var arm := Node3D.new()
	arm.rotation_degrees.y = yaw_deg
	_optics.add_child(arm)
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 28.0 * spread
	cyl.bottom_radius = 0.4 * spread
	cyl.height = LEN
	cyl.radial_segments = 30
	cyl.rings = 1
	# No end caps. CylinderMesh closes both ends by default, and the far one is a
	# 28 m disc hanging 520 m out at sea — it reads as a round blob on the tip of
	# the beam. A shaft of light has no end face; it just runs out of light.
	cyl.cap_top = false
	cyl.cap_bottom = false
	cyl.material = mat
	mi.mesh = cyl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.rotation_degrees.x = -95.0
	var dip := deg_to_rad(5.0)
	mi.position = Vector3(0.0, -sin(dip) * LEN * 0.5, -cos(dip) * LEN * 0.5)
	arm.add_child(mi)


func _build_collision() -> void:
	var tower := CollisionShape3D.new()
	var tshape := CylinderShape3D.new()
	tshape.radius = 5.6
	tshape.height = 38.0
	tower.shape = tshape
	tower.position.y = 19.0
	add_child(tower)
	var house := CollisionShape3D.new()
	var hshape := BoxShape3D.new()
	hshape.size = Vector3(6.2, 3.2, 4.4)
	house.shape = hshape
	house.position = Vector3(11.4, 5.5, 5.2)
	add_child(house)
	var rock := CollisionShape3D.new()
	var rshape := CylinderShape3D.new()
	rshape.radius = 28.0
	rshape.height = 16.0
	rock.shape = rshape
	rock.position.y = -5.0
	add_child(rock)


func _cyl(r_bot: float, r_top: float, h: float, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.bottom_radius = r_bot
	m.top_radius = r_top
	m.height = h
	m.radial_segments = 22
	m.rings = 1
	m.material = mat
	mi.mesh = m
	mi.position = pos
	add_child(mi)


func _torus(r: float, thick: float, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = r - thick
	t.outer_radius = r + thick
	t.rings = 24
	t.ring_segments = 8
	t.material = mat
	mi.mesh = t
	mi.position = pos
	add_child(mi)


func _box(size: Vector3, pos: Vector3, rot_deg: Vector3, mat: Material, parent: Node3D = null) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	mi.rotation_degrees = rot_deg
	if parent == null:
		add_child(mi)
	else:
		parent.add_child(mi)
