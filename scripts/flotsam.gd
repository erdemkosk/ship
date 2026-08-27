extends Node3D
## Driftwood, a bucket, or a blinking marker buoy. Kinematic — rides the
## Gerstner surface. RigidBody buoyancy was blowing up into NaN rotations.

enum Kind { PLANK, BUCKET, BUOY }

var ocean: Node3D
var kind: int = Kind.PLANK
var spawn_yaw := 0.0

var _draft := 0.06
var _rest_xz := Vector2.ZERO
var _blink: OmniLight3D
var _lamp_mat: StandardMaterial3D
var _t := 0.0


func _ready() -> void:
	match kind:
		Kind.BUCKET:
			_build_bucket()
		Kind.BUOY:
			_build_buoy()
		_:
			_build_plank()
	_rest_xz = Vector2(global_position.x, global_position.z)
	if ocean != null and ocean.has_method("rest_xz"):
		_rest_xz = ocean.rest_xz(_rest_xz)
	_place(0.0)
	if ocean != null and ocean.has_method("register_floater"):
		var r := 0.45
		match kind:
			Kind.BUCKET:
				r = 0.30
			Kind.BUOY:
				r = 0.55
		ocean.register_floater(self, r, _draft * 0.20)


func _build_plank() -> void:
	_draft = 0.04
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.32, 0.22, 0.13)
	wood.roughness = 0.95
	_mesh_box(Vector3(1.15, 0.07, 0.22), Vector3.ZERO, wood)


func _build_bucket() -> void:
	_draft = 0.08
	var rust := StandardMaterial3D.new()
	rust.albedo_color = Color(0.28, 0.22, 0.16)
	rust.metallic = 0.35
	rust.roughness = 0.72
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.16
	cyl.bottom_radius = 0.14
	cyl.height = 0.28
	cyl.radial_segments = 10
	cyl.rings = 1
	cyl.material = rust
	mi.mesh = cyl
	add_child(mi)
	var inner := MeshInstance3D.new()
	var hole := CylinderMesh.new()
	hole.top_radius = 0.13
	hole.bottom_radius = 0.11
	hole.height = 0.04
	hole.radial_segments = 8
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.08, 0.07, 0.06)
	hole.material = dark
	inner.mesh = hole
	inner.position.y = 0.12
	add_child(inner)


func _build_buoy() -> void:
	_draft = 0.22
	var hull := StandardMaterial3D.new()
	hull.albedo_color = Color(0.72, 0.18, 0.12)
	hull.roughness = 0.55
	var body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.16
	cyl.bottom_radius = 0.22
	cyl.height = 0.85
	cyl.radial_segments = 10
	cyl.material = hull
	body.mesh = cyl
	add_child(body)
	_lamp_mat = StandardMaterial3D.new()
	_lamp_mat.albedo_color = Color(0.9, 0.85, 0.7)
	_lamp_mat.emission_enabled = true
	_lamp_mat.emission = Color(1.0, 0.55, 0.2)
	_lamp_mat.emission_energy_multiplier = 0.0
	var cap := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.11
	sph.height = 0.22
	sph.material = _lamp_mat
	cap.mesh = sph
	cap.position.y = 0.48
	add_child(cap)
	_blink = OmniLight3D.new()
	_blink.position = Vector3(0.0, 0.52, 0.0)
	_blink.light_color = Color(1.0, 0.45, 0.18)
	_blink.light_energy = 0.0
	_blink.omni_range = 7.0
	_blink.omni_attenuation = 1.8
	_blink.shadow_enabled = false
	add_child(_blink)


func _mesh_box(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = mat
	mi.mesh = box
	mi.position = pos
	add_child(mi)


func _process(delta: float) -> void:
	_t += delta
	if ocean != null:
		var wind: Vector3 = ocean.wind_vector()
		_rest_xz += Vector2(wind.x, wind.z) * 0.012 * delta
		# Driftwood goes where the water goes; the wind only nudges it.
		if ocean.has_method("current_at"):
			_rest_xz += ocean.current_at(global_position) * delta
		_place(delta)
	if _blink == null:
		return
	var phase := fmod(_t, 2.6)
	var on := phase < 0.16 or (phase > 0.28 and phase < 0.42)
	_blink.light_energy = 3.2 if on else 0.0
	if _lamp_mat != null:
		_lamp_mat.emission_energy_multiplier = 4.2 if on else 0.05


func _place(_delta: float) -> void:
	if ocean == null:
		return
	var sp: Vector3 = ocean.surface_point(_rest_xz)
	if not sp.is_finite():
		return
	global_position = sp + Vector3(0.0, _draft, 0.0)
	# We already know this piece's rest position, so ask for the normal there
	# instead of making the ocean invert the displacement all over again.
	var n: Vector3 = ocean.normal_at_rest(_rest_xz).lerp(Vector3.UP, 0.4)
	if not n.is_finite() or n.length_squared() < 0.01:
		n = Vector3.UP
	else:
		n = n.normalized()
	var tangent := Vector3(cos(spawn_yaw), 0.0, sin(spawn_yaw))
	var x := tangent.cross(n)
	if x.length_squared() < 0.0004:
		x = Vector3.RIGHT.cross(n)
	if x.length_squared() < 0.0004:
		return
	x = x.normalized()
	var z := x.cross(n)
	if not z.is_finite() or z.length_squared() < 0.0004:
		return
	z = z.normalized()
	global_basis = Basis(x, n, z)
