extends RigidBody3D
## Small wooden boat. Buoyancy at hull + deck probes; W/S thrust, A/D rudder.
## Rolls with the swell. Past vanishing stability it capsizes.

# Hull bottom + deck probes. Deck samples (y > 0) only matter when inverted —
# they keep a capsized boat floating instead of falling through.
#
# Everything here is in metres on a 9 m hull whose origin sits at the design
# waterline, so a probe at y = -0.62 is the keel and y = +0.6 is the deck.
const PROBES: Array[Vector3] = [
	Vector3(1.05, -0.62, 3.2),
	Vector3(-1.05, -0.62, 3.2),
	Vector3(1.20, -0.62, 0.0),
	Vector3(-1.20, -0.62, 0.0),
	Vector3(0.85, -0.62, -3.2),
	Vector3(-0.85, -0.62, -3.2),
	Vector3(1.20, 0.60, 2.2),
	Vector3(-1.20, 0.60, 2.2),
	Vector3(1.20, 0.60, -2.2),
	Vector3(-1.20, 0.60, -2.2),
]

#
# The whole set is scaled off MASS. A 4.5 t boat needs ~20x the spring, damping,
# drag and thrust of the 220 kg dinghy this started as, or it sinks, wallows and
# takes a minute to reach speed.
const MASS := 4500.0
const HULL_DRAG := 1430.0     # linear; top speed is simply thrust / HULL_DRAG
# Tuned so she floats on her marks: 6 hull probes at y = -0.62 each carry
# m*g/6, and k is chosen to put that equilibrium right at the boot top.
@export var probe_stiffness := 16000.0
@export var probe_damping := 760.0
@export var thrust_power := 38600.0
@export var turn_torque := 155000.0

var ocean: Node3D
var camera_rig: Node3D
var _lantern: OmniLight3D
var _lantern_spot: SpotLight3D
var _lamp_mat: StandardMaterial3D
var _lit_window: StandardMaterial3D
var _glass_mat: ShaderMaterial
var _cabin_lamp: OmniLight3D
var _helm_lamp: OmniLight3D
var _wheel: Node3D
var _motor_pivot: Node3D
var _prop: GPUParticles3D
var _prop_pm: ParticleProcessMaterial
var _hull_mats: Array[ShaderMaterial] = []
var _soak := 0.0
var _slam_cd := 0.0
var _t := 0.0
var _flicker := 1.0
var _prev_wh := PackedFloat32Array()
var _prev_wh_valid := false
var _prev_com_vy := 0.0
var _com_vy_valid := false


func _ready() -> void:
	mass = MASS
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	# Low, and a little aft where the engine sits. A boat with a wheelhouse on
	# top of a deckhouse is top-heavy by shape; the ballast has to answer for it
	# or she lies over at the first beam sea.
	center_of_mass = Vector3(0.0, -0.32, 0.20)
	linear_damp = 0.03
	angular_damp = 0.05
	can_sleep = false
	_prev_wh.resize(PROBES.size())
	_build_collision()
	_build_visuals()
	_build_motor()
	_build_water_fx()
	# Roughly m(L^2+H^2)/12 about each axis: pitch, yaw, roll. Roll is left
	# heavier than the box formula so she rolls slow and deep like timber.
	inertia = Vector3(32000.0, 34000.0, 9000.0)


func _build_collision() -> void:
	var hull := CollisionShape3D.new()
	var hs := BoxShape3D.new()
	hs.size = Vector3(2.9, 1.9, 8.6)
	hull.shape = hs
	hull.position = Vector3(0.0, 0.05, 0.0)
	add_child(hull)

	var house := CollisionShape3D.new()
	var ds := BoxShape3D.new()
	ds.size = Vector3(2.4, 3.6, 3.6)
	house.shape = ds
	house.position = Vector3(0.0, 2.35, 1.3)
	add_child(house)


func _glass(size: Vector3, pos: Vector3) -> void:
	## A pane, not a black rectangle. Both faces drawn, so it still reads as
	## glass from inside the wheelhouse.
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = _glass_mat
	mi.mesh = bm
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _mat(albedo: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = rough
	m.metallic = metal
	return m


func _wet_wood(color: Color, rough: float) -> ShaderMaterial:
	## Hull planking that darkens and goes glossy below the waterline. The
	## waterline is pushed every frame in _update_wetness().
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/wet_hull.gdshader")
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("dry_roughness", rough)
	_hull_mats.append(m)
	return m


func _build_visuals() -> void:
	## An old wooden coaster: 9 m hull, deckhouse on the deck, wheelhouse on top
	## of that. Everything is boxes and cylinders, so the character has to come
	## from proportion and from what is worn: dark oiled topsides, paint gone
	## chalky above the rubbing strake, one lit window.
	var hull_wood := _wet_wood(Color(0.115, 0.085, 0.062), 0.88)
	var keel_wood := _wet_wood(Color(0.070, 0.052, 0.040), 0.93)
	var boot := _wet_wood(Color(0.28, 0.075, 0.055), 0.80)   # boot-top stripe
	var deck := _mat(Color(0.20, 0.155, 0.110), 0.94)
	var paint := _mat(Color(0.46, 0.44, 0.395), 0.86)        # chalky white
	var paint_dark := _mat(Color(0.20, 0.20, 0.19), 0.88)
	var trim := _mat(Color(0.155, 0.105, 0.070), 0.82)
	var metal := _mat(Color(0.105, 0.105, 0.115), 0.50, 0.65)
	var dark := _mat(Color(0.045, 0.040, 0.036), 0.92)

	# --- hull ---------------------------------------------------------------
	_box(Vector3(1.5, 0.30, 8.0), Vector3(0.0, -0.68, 0.0), Vector3.ZERO, keel_wood)
	_box(Vector3(2.45, 0.55, 8.3), Vector3(0.0, -0.42, 0.0), Vector3.ZERO, hull_wood)
	_box(Vector3(2.80, 0.80, 8.3), Vector3(0.0, 0.05, 0.0), Vector3.ZERO, hull_wood)
	# Flared topsides, tilted out a few degrees so she is not a shoebox.
	_box(Vector3(0.20, 1.05, 8.2), Vector3(-1.44, 0.22, 0.0), Vector3(0.0, 0.0, 7.0), hull_wood)
	_box(Vector3(0.20, 1.05, 8.2), Vector3(1.44, 0.22, 0.0), Vector3(0.0, 0.0, -7.0), hull_wood)
	# Boot top: the paint line at the waterline, the thing that says "this floats
	# here" more than any other detail on a working boat.
	_box(Vector3(2.86, 0.16, 8.32), Vector3(0.0, -0.06, 0.0), Vector3.ZERO, boot)
	# Bow: two panels converging on the stem.
	_box(Vector3(0.20, 1.35, 2.6), Vector3(-0.72, 0.18, -3.5), Vector3(0.0, 19.0, 0.0), hull_wood)
	_box(Vector3(0.20, 1.35, 2.6), Vector3(0.72, 0.18, -3.5), Vector3(0.0, -19.0, 0.0), hull_wood)
	_box(Vector3(0.26, 1.55, 0.9), Vector3(0.0, 0.30, -4.45), Vector3(14.0, 0.0, 0.0), keel_wood)
	# Transom, raked.
	_box(Vector3(2.75, 1.25, 0.22), Vector3(0.0, 0.18, 4.20), Vector3(-9.0, 0.0, 0.0), hull_wood)
	# Rubbing strake all round.
	_box(Vector3(2.98, 0.14, 8.35), Vector3(0.0, 0.52, 0.0), Vector3.ZERO, trim)

	# --- deck and bulwarks --------------------------------------------------
	_box(Vector3(2.60, 0.14, 8.0), Vector3(0.0, 0.56, 0.05), Vector3.ZERO, deck)
	_box(Vector3(0.14, 0.52, 7.9), Vector3(-1.34, 0.86, 0.05), Vector3(0.0, 0.0, 5.0), paint_dark)
	_box(Vector3(0.14, 0.52, 7.9), Vector3(1.34, 0.86, 0.05), Vector3(0.0, 0.0, -5.0), paint_dark)
	_box(Vector3(2.70, 0.10, 0.14), Vector3(0.0, 1.13, -3.95), Vector3.ZERO, trim)
	# Hatch and a coil of gear on the foredeck.
	_box(Vector3(1.10, 0.22, 1.30), Vector3(0.0, 0.72, -2.05), Vector3.ZERO, trim)
	_box(Vector3(0.55, 0.30, 0.55), Vector3(-0.80, 0.78, -3.05), Vector3(0.0, 22.0, 0.0), dark)

	# --- deckhouse (lower level) --------------------------------------------
	# Built as walls, not as a solid block. You can go inside her, so every
	# surface has to exist from both faces.
	_glass_mat = ShaderMaterial.new()
	_glass_mat.shader = load("res://shaders/glass.gdshader")

	const CH_Z0 := -0.45   # forward bulkhead
	const CH_Z1 := 3.15    # aft bulkhead
	const CH_X := 1.16     # half beam of the house
	const CH_Y0 := 0.63    # cabin sole
	const CH_Y1 := 2.45    # cabin deckhead / roof underside
	var cy := (CH_Y0 + CH_Y1) * 0.5
	var ch := CH_Y1 - CH_Y0
	var cz := (CH_Z0 + CH_Z1) * 0.5
	var cl := CH_Z1 - CH_Z0

	_box(Vector3(CH_X * 2.0, 0.09, cl), Vector3(0.0, CH_Y0, cz), Vector3.ZERO, deck)  # sole
	_box(Vector3(0.08, ch, cl), Vector3(-CH_X, cy, cz), Vector3.ZERO, paint)
	_box(Vector3(0.08, ch, cl), Vector3(CH_X, cy, cz), Vector3.ZERO, paint)
	_box(Vector3(CH_X * 2.0, ch, 0.08), Vector3(0.0, cy, CH_Z1), Vector3.ZERO, paint)
	# Forward bulkhead with a doorway cut out of it (two jambs + a header).
	_box(Vector3(0.62, ch, 0.08), Vector3(-0.85, cy, CH_Z0), Vector3.ZERO, paint)
	_box(Vector3(0.62, ch, 0.08), Vector3(0.85, cy, CH_Z0), Vector3.ZERO, paint)
	_box(Vector3(1.10, 0.42, 0.08), Vector3(0.0, CH_Y1 - 0.21, CH_Z0), Vector3.ZERO, paint)
	_box(Vector3(1.14, 0.06, 0.10), Vector3(0.0, CH_Y0 + 0.03, CH_Z0), Vector3.ZERO, trim)
	# Roof of the deckhouse — the walkable upper deck.
	_box(Vector3(2.42, 0.14, cl + 0.14), Vector3(0.0, CH_Y1 + 0.07, cz), Vector3.ZERO, paint_dark)

	# Side windows: three a side, glazed.
	for i in 3:
		var z := CH_Z0 + 0.85 + float(i) * 1.05
		for sx in [-1.0, 1.0]:
			_box(Vector3(0.11, 0.58, 0.74), Vector3(sx * CH_X, 1.72, z), Vector3.ZERO, trim)
			_glass(Vector3(0.05, 0.46, 0.62), Vector3(sx * (CH_X + 0.01), 1.72, z))
	# Cabin lamp: the one warm thing aboard.
	_cabin_lamp = OmniLight3D.new()
	_cabin_lamp.position = Vector3(0.0, 2.15, 1.35)
	_cabin_lamp.light_color = Color(1.0, 0.62, 0.30)
	_cabin_lamp.light_energy = 1.6
	_cabin_lamp.omni_range = 4.2
	_cabin_lamp.omni_attenuation = 1.6
	_cabin_lamp.shadow_enabled = false
	add_child(_cabin_lamp)
	_lit_window = _mat(Color(0.30, 0.20, 0.10), 0.55)
	_lit_window.emission_enabled = true
	_lit_window.emission = Color(1.0, 0.66, 0.30)
	_lit_window.emission_energy_multiplier = 2.2
	_box(Vector3(0.22, 0.16, 0.22), Vector3(0.0, 2.24, 1.35), Vector3.ZERO, _lit_window)

	# Bunk, table, stove — enough that it reads as somewhere someone lives.
	_box(Vector3(0.78, 0.12, 1.90), Vector3(-0.72, 1.05, 1.90), Vector3.ZERO, trim)
	_box(Vector3(0.74, 0.14, 1.80), Vector3(-0.72, 1.14, 1.90), Vector3.ZERO, dark)
	_box(Vector3(0.70, 0.08, 0.90), Vector3(0.74, 1.28, 0.55), Vector3.ZERO, trim)
	_cyl(0.05, 0.05, 0.62, Vector3(0.74, 0.95, 0.55), Vector3.ZERO, metal)
	_box(Vector3(0.44, 0.52, 0.44), Vector3(0.80, 0.90, 2.55), Vector3.ZERO, metal)
	_cyl(0.07, 0.07, 1.30, Vector3(0.80, 1.81, 2.55), Vector3.ZERO, metal)

	# --- wheelhouse (upper level) -------------------------------------------
	const WH_Z0 := -0.25
	const WH_Z1 := 2.15
	const WH_X := 0.96
	const WH_Y0 := 2.55
	const WH_Y1 := 4.10
	var wy := (WH_Y0 + WH_Y1) * 0.5
	var wh := WH_Y1 - WH_Y0
	var wz := (WH_Z0 + WH_Z1) * 0.5
	var wl := WH_Z1 - WH_Z0

	_box(Vector3(WH_X * 2.0, 0.10, wl), Vector3(0.0, WH_Y0, wz), Vector3.ZERO, deck)
	_box(Vector3(WH_X * 2.0 + 0.22, 0.14, wl + 0.30), Vector3(0.0, WH_Y1, wz), Vector3.ZERO, paint_dark)
	# Sills and headers; the gap between them is glass all the way round.
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.09, 0.34, wl), Vector3(sx * WH_X, WH_Y0 + 0.30, wz), Vector3.ZERO, paint)
		_box(Vector3(0.09, 0.30, wl), Vector3(sx * WH_X, WH_Y1 - 0.15, wz), Vector3.ZERO, paint)
		_box(Vector3(0.10, wh, 0.10), Vector3(sx * WH_X, wy, WH_Z0), Vector3.ZERO, trim)
		_box(Vector3(0.10, wh, 0.10), Vector3(sx * WH_X, wy, WH_Z1), Vector3.ZERO, trim)
		_glass(Vector3(0.05, 0.86, wl - 0.14), Vector3(sx * WH_X, 3.32, wz))
	_box(Vector3(WH_X * 2.0, 0.34, 0.09), Vector3(0.0, WH_Y0 + 0.30, WH_Z0), Vector3.ZERO, paint)
	_box(Vector3(WH_X * 2.0, 0.30, 0.09), Vector3(0.0, WH_Y1 - 0.15, WH_Z0), Vector3.ZERO, paint)
	_glass(Vector3(WH_X * 2.0 - 0.16, 0.86, 0.05), Vector3(0.0, 3.32, WH_Z0))
	# Aft face: a doorway out onto the deckhouse roof, glass either side of it.
	_box(Vector3(0.46, wh, 0.09), Vector3(-0.72, wy, WH_Z1), Vector3.ZERO, paint)
	_box(Vector3(0.46, wh, 0.09), Vector3(0.72, wy, WH_Z1), Vector3.ZERO, paint)
	_box(Vector3(1.02, 0.30, 0.09), Vector3(0.0, WH_Y1 - 0.15, WH_Z1), Vector3.ZERO, paint)
	_glass(Vector3(0.40, 0.80, 0.05), Vector3(-0.72, 3.35, WH_Z1))
	_glass(Vector3(0.40, 0.80, 0.05), Vector3(0.72, 3.35, WH_Z1))

	# Chart table and a binnacle light, so the wheelhouse is a room and not a box.
	_box(Vector3(1.20, 0.07, 0.60), Vector3(0.0, 3.30, 1.72), Vector3.ZERO, trim)
	_cyl(0.04, 0.04, 0.72, Vector3(-0.48, 2.93, 1.72), Vector3.ZERO, metal)
	_cyl(0.04, 0.04, 0.72, Vector3(0.48, 2.93, 1.72), Vector3.ZERO, metal)
	_helm_lamp = OmniLight3D.new()
	_helm_lamp.position = Vector3(0.0, 3.86, 1.10)
	_helm_lamp.light_color = Color(1.0, 0.50, 0.24)
	_helm_lamp.light_energy = 1.1
	_helm_lamp.omni_range = 3.4
	_helm_lamp.omni_attenuation = 1.8
	_helm_lamp.shadow_enabled = false
	add_child(_helm_lamp)
	_box(Vector3(0.16, 0.12, 0.16), Vector3(0.0, 3.94, 1.10), Vector3.ZERO, _lit_window)

	_build_helm(trim, metal)

func _build_helm(trim: Material, metal: Material) -> void:
	## The wheel, on a pedestal, raked back the way a real one is. You stand at
	## this in FPS mode, so it is the one piece of the boat seen from 40 cm.
	var pivot := Node3D.new()
	pivot.position = Vector3(0.0, 2.62, 0.30)
	add_child(pivot)
	_box(Vector3(0.34, 0.62, 0.30), Vector3(0.0, 0.31, 0.0), Vector3.ZERO, trim, pivot)
	_box(Vector3(0.60, 0.10, 0.34), Vector3(0.0, 0.66, 0.10), Vector3(-14.0, 0.0, 0.0), trim, pivot)

	_wheel = Node3D.new()
	_wheel.position = Vector3(0.0, 0.72, -0.14)
	_wheel.rotation_degrees.x = -22.0
	pivot.add_child(_wheel)
	var rim := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.26
	t.outer_radius = 0.32
	t.rings = 20
	t.ring_segments = 6
	t.material = trim
	rim.mesh = t
	rim.rotation_degrees.x = 90.0
	_wheel.add_child(rim)
	for i in 6:
		var a := float(i) / 6.0 * TAU
		var sp := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.022
		cm.bottom_radius = 0.022
		cm.height = 0.56
		cm.radial_segments = 6
		cm.rings = 1
		cm.material = trim
		sp.mesh = cm
		sp.rotation_degrees = Vector3(0.0, 0.0, rad_to_deg(a))
		_wheel.add_child(sp)
	var hub := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.06
	hm.bottom_radius = 0.06
	hm.height = 0.10
	hm.radial_segments = 10
	hm.material = metal
	hub.mesh = hm
	hub.rotation_degrees.x = 90.0
	_wheel.add_child(hub)


func _cyl(r_bot: float, r_top: float, h: float, pos: Vector3, rot_deg: Vector3,
		mat: Material, parent: Node3D = null) -> void:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.bottom_radius = r_bot
	m.top_radius = r_top
	m.height = h
	m.radial_segments = 10
	m.rings = 1
	m.material = mat
	mi.mesh = m
	mi.position = pos
	mi.rotation_degrees = rot_deg
	if parent == null:
		add_child(mi)
	else:
		parent.add_child(mi)


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


func _build_motor() -> void:
	## A 9 m boat has a shaft and a rudder, not an outboard. The rudder swings
	## with the helm and the wheel in the wheelhouse turns with it.
	_motor_pivot = Node3D.new()
	_motor_pivot.position = Vector3(0.0, -0.55, 4.05)
	add_child(_motor_pivot)

	var metal := _mat(Color(0.09, 0.09, 0.10), 0.55, 0.6)
	var bronze := _mat(Color(0.30, 0.22, 0.11), 0.45, 0.75)

	_box(Vector3(0.10, 0.95, 0.85), Vector3(0.0, -0.18, 0.10), Vector3.ZERO, metal, _motor_pivot)
	_box(Vector3(0.09, 0.22, 0.30), Vector3(0.0, 0.36, 0.02), Vector3.ZERO, metal, _motor_pivot)

	# Shaft and screw, just ahead of the rudder.
	var shaft := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.055
	sm.bottom_radius = 0.055
	sm.height = 1.30
	sm.radial_segments = 8
	sm.material = metal
	shaft.mesh = sm
	shaft.position = Vector3(0.0, -0.62, 3.35)
	shaft.rotation_degrees = Vector3(84.0, 0.0, 0.0)
	add_child(shaft)
	for i in 3:
		var blade := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.30, 0.04, 0.14)
		bm.material = bronze
		blade.mesh = bm
		blade.position = Vector3(0.0, -0.68, 3.86)
		blade.rotation_degrees = Vector3(18.0, 0.0, float(i) * 120.0)
		add_child(blade)


func _drop_mesh(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.1
	m.radial_segments = 8
	m.rings = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.72, 0.82, 0.86, 0.45)
	mat.vertex_color_use_as_albedo = true
	mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	mat.distance_fade_min_distance = 16.0
	mat.distance_fade_max_distance = 2.2
	m.material = mat
	return m


func _spray_fade() -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	g.colors = PackedColorArray([
		Color(0.82, 0.9, 0.92, 0.7),
		Color(0.7, 0.8, 0.82, 0.28),
		Color(0.55, 0.62, 0.64, 0.0)])
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


func _build_water_fx() -> void:
	# Propeller churn: droplets thrown aft that fall back onto the sea.
	_prop = GPUParticles3D.new()
	_prop.amount = 90
	_prop.lifetime = 0.7
	_prop.fixed_fps = 30
	_prop.local_coords = false
	_prop.transform_align = GPUParticles3D.TRANSFORM_ALIGN_DISABLED
	_prop.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_prop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_prop.position = Vector3(0.0, -0.62, 4.15)
	_prop.visibility_aabb = AABB(Vector3(-8, -3, -8), Vector3(16, 8, 16))
	_prop_pm = ParticleProcessMaterial.new()
	_prop_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_prop_pm.emission_sphere_radius = 0.30
	_prop_pm.direction = Vector3(0.0, 0.35, 1.0)
	_prop_pm.spread = 28.0
	_prop_pm.initial_velocity_min = 2.4
	_prop_pm.initial_velocity_max = 5.4
	_prop_pm.gravity = Vector3(0.0, -14.0, 0.0)
	_prop_pm.scale_min = 0.45
	_prop_pm.scale_max = 1.1
	_prop_pm.color = Color(0.8, 0.88, 0.9, 0.55)
	_prop_pm.color_ramp = _spray_fade()
	_prop.process_material = _prop_pm
	_prop.draw_pass_1 = _drop_mesh(0.022)
	_prop.emitting = false
	add_child(_prop)


func _process(delta: float) -> void:
	_t += delta
	_update_lantern(delta)
	_update_wetness(delta)

	var free_cam: bool = camera_rig != null and camera_rig.get("free_mode")
	var thr := 0.0
	var turn := 0.0
	if not free_cam:
		thr = Input.get_axis("boat_backward", "boat_forward")
		turn = Input.get_axis("boat_right", "boat_left")

	if _motor_pivot != null:
		var k := 1.0 - exp(-5.0 * delta)
		_motor_pivot.rotation.y = lerp_angle(_motor_pivot.rotation.y, turn * 0.55, k)
	if _wheel != null:
		# Four turns lock to lock, the way a cable-and-quadrant helm feels.
		_wheel.rotation.z = lerp_angle(_wheel.rotation.z, turn * 4.2,
				1.0 - exp(-5.0 * delta))

	var fwd_speed := -global_basis.z.dot(linear_velocity)
	if _prop != null:
		_prop.amount_ratio = clampf(absf(thr) * 0.7 + maxf(fwd_speed, 0.0) * 0.12, 0.0, 1.0)
		_prop.emitting = absf(thr) > 0.08 or fwd_speed > 0.9

	if not free_cam and Input.is_action_just_pressed("throw_rock"):
		_throw_rock()


func _update_wetness(delta: float) -> void:
	if ocean == null or _hull_mats.is_empty():
		return
	var wy: float = ocean.get_height(global_position)
	# Driving into a head sea keeps the topsides soaked; it dries off slowly.
	var target := clampf(Vector2(linear_velocity.x, linear_velocity.z).length() / 7.0, 0.0, 1.0)
	target = maxf(target, clampf(float(ocean.get("sig_height")) / 5.0 - 0.35, 0.0, 1.0))
	var k := (1.0 - exp(-2.5 * delta)) if target > _soak else (1.0 - exp(-0.35 * delta))
	_soak = lerpf(_soak, target, k)
	for m: ShaderMaterial in _hull_mats:
		m.set_shader_parameter("water_y", wy)
		m.set_shader_parameter("soak", _soak)


func _update_lantern(delta: float) -> void:
	if _lantern == null:
		return
	# Irregular kerosene flicker, plus a bit of hull vibration.
	var n := 0.86 + 0.07 * sin(_t * 6.7) + 0.045 * sin(_t * 19.4 + 1.1) \
			+ 0.03 * sin(_t * 41.2 + 2.4)
	var beat := fmod(_t * 0.41 + sin(_t * 0.17) * 0.3, 1.0)
	if beat < 0.035:
		n *= 0.55 + 0.25 * sin(_t * 90.0)
	var shake := clampf(angular_velocity.length() * 0.08, 0.0, 0.5)
	n *= 1.0 - shake * 0.12
	_flicker = lerpf(_flicker, n, 1.0 - exp(-18.0 * delta))
	_lantern.light_energy = 0.16 * _flicker
	if _lantern_spot != null:
		_lantern_spot.light_energy = 0.26 * _flicker
	if _lamp_mat != null:
		_lamp_mat.emission_energy_multiplier = 0.32 * _flicker
	# Pole wobble so the bulb isn't a locked studio light.
	var wob := (1.0 + absf(Input.get_axis("boat_backward", "boat_forward")) * 1.4)
	_lantern.position = Vector3(
			sin(_t * 37.0) * 0.005 * wob,
			2.95 + sin(_t * 29.0) * 0.004 * wob,
			2.35 + cos(_t * 33.0) * 0.004 * wob)
	if _lantern_spot != null:
		_lantern_spot.position = _lantern.position + Vector3(0.0, -0.03, -0.03)


func _throw_rock() -> void:
	var rock := preload("res://scripts/rock.gd").new()
	rock.ocean = ocean
	get_parent().add_child(rock)
	var fwd := -global_basis.z
	rock.global_position = global_position + fwd * 4.8 + Vector3.UP * 1.6
	rock.linear_velocity = fwd * 6.5 + Vector3.UP * 2.2 + linear_velocity


func _physics_process(delta: float) -> void:
	if ocean == null:
		return
	if not global_position.is_finite() or not linear_velocity.is_finite():
		global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 2.0, 0.0))
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		return

	var submerged := 0.0
	var hull_n := 0.0
	var wet_n := 0.0
	var com_wave_vy := 0.0
	for i in PROBES.size():
		var wp: Vector3 = global_transform * PROBES[i]
		var wh: float = ocean.get_height(wp)
		var wave_vy := 0.0
		if _prev_wh_valid:
			wave_vy = clampf((wh - _prev_wh[i]) / delta, -10.0, 10.0)
		_prev_wh[i] = wh
		if PROBES[i].y < 0.0:
			hull_n += 1.0
			com_wave_vy += wave_vy

		var depth: float = wh - wp.y
		if depth > 0.0:
			wet_n += 1.0
			if PROBES[i].y < 0.0:
				submerged += 1.0
			var r := wp - global_position
			var v_at := linear_velocity + angular_velocity.cross(r)
			var rel_vy := clampf(v_at.y - wave_vy, -12.0, 12.0)
			var f := probe_stiffness * clampf(depth, 0.0, 1.4) - probe_damping * rel_vy
			f = clampf(f, 0.0, probe_stiffness * 2.4)
			apply_force(Vector3.UP * f, r)
			if PROBES[i].y < 0.0 and rel_vy < -4.2 and depth < 0.28 and _slam_cd <= 0.0:
				_slam_cd = 1.15
				ocean.splash(wp, clampf(absf(rel_vy) * 0.18, 0.4, 1.1))
	if hull_n > 0.0:
		submerged /= hull_n
		com_wave_vy /= hull_n
	_prev_wh_valid = true
	_slam_cd -= delta

	var wave_n := Vector3.UP
	if ocean.has_method("get_normal"):
		wave_n = ocean.get_normal(global_position)

	var hydro := maxf(submerged, wet_n / float(PROBES.size()))
	if hydro > 0.0:
		# Ride the swell: extra heave from the wave's own vertical accel.
		var wave_ay := 0.0
		if _com_vy_valid:
			wave_ay = clampf((com_wave_vy - _prev_com_vy) / delta, -14.0, 14.0)
		_prev_com_vy = com_wave_vy
		_com_vy_valid = true
		apply_central_force(Vector3.UP * wave_ay * mass * 0.7 * hydro)

		# Align with the wave only while still upright. Past ~70° of heel the
		# righting moment vanishes and a steep face can finish the capsize.
		var up_dot := global_basis.y.dot(Vector3.UP)
		if up_dot > 0.32:
			var target_up := wave_n.normalized()
			if target_up.length_squared() > 0.01:
				var tilt_axis := global_basis.y.cross(target_up)
				apply_torque(tilt_axis * 46000.0 * up_dot * up_dot * hydro)

		# Horizontal drag (keel + hull). Leave Y mostly free so the boat can
		# jump a crest and fall into the trough.
		#
		# Drag is against the WATER, not against the ground. That one word is
		# the whole tidal stream: point at the harbour in a three-knot cross-set
		# and you will still arrive downstream of it.
		var water_v := Vector3.ZERO
		if ocean.has_method("current_at"):
			var c: Vector2 = ocean.current_at(global_position)
			water_v = Vector3(c.x, 0.0, c.y)
		var v := linear_velocity
		var v_h := Vector3(v.x, 0.0, v.z)
		apply_central_force(-(v_h - water_v) * HULL_DRAG * hydro)
		apply_central_force(Vector3.DOWN * v.y * 240.0 * hydro)
		# Roll damps less than yaw/pitch so a beam swell can actually heel it.
		var local_w: Vector3 = global_basis.inverse() * angular_velocity
		var damp_w := Vector3(local_w.x * 19000.0, local_w.y * 30000.0, local_w.z * 5600.0)
		apply_torque(-(global_basis * damp_w) * hydro)
		var side := global_basis.x
		var lat := side.dot(linear_velocity - water_v)
		apply_central_force(-side * lat * 5300.0 * hydro)
		apply_central_force(ocean.wind_vector() * 26.0 * hydro)

		var free_cam: bool = camera_rig != null and camera_rig.get("free_mode")
		if not free_cam and up_dot > 0.22:
			var fwd_in := Input.get_axis("boat_backward", "boat_forward")
			var turn_in := Input.get_axis("boat_right", "boat_left")
			apply_central_force(-global_basis.z * fwd_in * thrust_power * submerged)
			apply_torque(Vector3.UP * turn_in * turn_torque * submerged)
	else:
		_com_vy_valid = false

	if angular_velocity.length() > 2.2:
		angular_velocity = angular_velocity.limit_length(2.2)
	if linear_velocity.y > 11.0:
		linear_velocity.y = 11.0

	if global_position.y < -30.0 or global_position.y > 120.0:
		global_position = Vector3(0.0, 2.0, 0.0)
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		_prev_wh_valid = false
		_com_vy_valid = false
