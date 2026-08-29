extends Node3D
## Black VHF whip on the mast truck. The ferrule is bolted; the stick is a
## stiff Verlet chain in the boat's frame, driven by the mount's inertial
## acceleration so it lags a roll and a slam instead of being glued upright.

const SEGS := 8
const LENGTH := 1.92
const DAMP := 0.958
const BEND := 10.0
const ALIGN := 5.2
const WIND_K := 0.14
const SAG := 0.22
const ITERS := 6

var _pts: PackedVector3Array
var _prev: PackedVector3Array
var _seg: Array[MeshInstance3D] = []
var _ds := 0.0
var _prev_v := Vector3.ZERO
var _prev_w := Vector3.ZERO
var _have_prev := false
var _whip: Node3D


func _ready() -> void:
	_ds = LENGTH / float(SEGS)
	_build_mount()
	_whip = Node3D.new()
	_whip.position = Vector3(0.0, 0.07, 0.0)
	add_child(_whip)
	_pts.resize(SEGS + 1)
	_prev.resize(SEGS + 1)
	for i in SEGS + 1:
		_pts[i] = Vector3(0.0, float(i) * _ds, 0.0)
		_prev[i] = _pts[i]
	var fib := _mat(Color(0.04, 0.04, 0.045), 0.62, 0.12)
	var cap := _mat(Color(0.18, 0.18, 0.19), 0.35, 0.65)
	for i in SEGS:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		var t := float(i) / float(SEGS)
		cm.bottom_radius = lerpf(0.018, 0.005, t)
		cm.top_radius = lerpf(0.016, 0.004, t + 1.0 / float(SEGS))
		cm.height = _ds
		cm.radial_segments = 8
		cm.rings = 1
		cm.material = fib
		mi.mesh = cm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_whip.add_child(mi)
		_seg.append(mi)
	var tip := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.012
	sm.height = 0.024
	sm.material = cap
	tip.mesh = sm
	tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_whip.add_child(tip)
	_seg.append(tip)
	_place_meshes()


func _build_mount() -> void:
	var ss := _mat(Color(0.55, 0.56, 0.54), 0.28, 0.78)
	var black := _mat(Color(0.08, 0.08, 0.08), 0.55, 0.2)
	_cyl(0.028, 0.028, 0.05, Vector3(0.0, 0.025, 0.0), ss)
	_box(Vector3(0.055, 0.018, 0.04), Vector3(0.0, 0.012, 0.0), ss)
	_cyl(0.016, 0.016, 0.04, Vector3(0.0, 0.048, 0.0), black)
	_cyl(0.022, 0.018, 0.035, Vector3(0.0, 0.068, 0.0), ss)


func _physics_process(delta: float) -> void:
	if delta < 0.0001 or _pts.is_empty():
		return
	delta = minf(delta, 0.04)
	var boat := get_parent() as RigidBody3D
	if boat == null:
		return
	var v: Vector3 = boat.linear_velocity
	var w: Vector3 = boat.angular_velocity
	var a := Vector3.ZERO
	var alpha := Vector3.ZERO
	if _have_prev:
		a = (v - _prev_v) / delta
		alpha = (w - _prev_w) / delta
	_prev_v = v
	_prev_w = w
	_have_prev = true

	var r_world: Vector3 = global_position - boat.global_position
	var a_mount: Vector3 = a + alpha.cross(r_world) + w.cross(w.cross(r_world))
	var inv: Basis = global_basis.inverse()
	var a_local: Vector3 = inv * a_mount
	var g_local: Vector3 = inv * Vector3(0.0, -9.81, 0.0)
	var wind_local := Vector3.ZERO
	var weather: Variant = boat.get("weather")
	if weather != null:
		var wa: float = deg_to_rad(float(weather.get("wind_direction_deg")))
		var ws: float = float(weather.get("wind_speed"))
		var wind_w := Vector3(cos(wa), 0.0, sin(wa)) * ws - v
		wind_local = inv * wind_w

	for i in range(1, SEGS + 1):
		var accel: Vector3 = -a_local + g_local * SAG
		accel += wind_local * (WIND_K * float(i) / float(SEGS))
		# Extra rotating-frame terms relative to the ferrule, not the COM —
		# mount inertia is already in -a_local.
		var r_l: Vector3 = _whip.position + _pts[i]
		var w_l: Vector3 = inv * w
		var al_l: Vector3 = inv * alpha
		accel += -al_l.cross(r_l) - w_l.cross(w_l.cross(r_l))
		var cur := _pts[i]
		var nxt: Vector3 = cur + (cur - _prev[i]) * DAMP + accel * delta * delta
		_prev[i] = cur
		_pts[i] = nxt

	_pts[0] = Vector3.ZERO
	_prev[0] = Vector3.ZERO
	for _k in ITERS:
		_pts[0] = Vector3.ZERO
		for i in SEGS:
			var d: Vector3 = _pts[i + 1] - _pts[i]
			var dist := d.length()
			if dist < 1e-6:
				continue
			var corr: Vector3 = d * ((_ds - dist) / dist) * 0.5
			if i == 0:
				_pts[i + 1] += corr * 2.0
			else:
				_pts[i] -= corr
				_pts[i + 1] += corr

	var kb := 1.0 - exp(-BEND * delta)
	var ka := 1.0 - exp(-ALIGN * delta)
	for i in range(1, SEGS + 1):
		var rest := Vector3(0.0, float(i) * _ds, 0.0)
		_pts[i] = _pts[i].lerp(rest, ka)
		if i >= 2:
			var dir: Vector3 = _pts[i - 1] - _pts[i - 2]
			var col: Vector3 = rest
			if dir.length_squared() > 1e-8:
				col = _pts[i - 1] + dir.normalized() * _ds
			_pts[i] = _pts[i].lerp(col, kb)
		if _pts[i].y < 0.04:
			_pts[i].y = 0.04
	for i in SEGS:
		var d2: Vector3 = _pts[i + 1] - _pts[i]
		var dist2 := d2.length()
		if dist2 < 1e-6:
			continue
		var corr2: Vector3 = d2 * ((_ds - dist2) / dist2)
		if i == 0:
			_pts[i + 1] += corr2
		else:
			_pts[i] -= corr2 * 0.5
			_pts[i + 1] += corr2 * 0.5
	_pts[0] = Vector3.ZERO
	_place_meshes()


func _place_meshes() -> void:
	for i in SEGS:
		var a := _pts[i]
		var b := _pts[i + 1]
		var d := b - a
		var h := d.length()
		_seg[i].position = (a + b) * 0.5
		if h < 1e-5:
			continue
		var y := d / h
		var x := y.cross(Vector3(0.0, 0.0, 1.0))
		if x.length_squared() < 1e-6:
			x = y.cross(Vector3(1.0, 0.0, 0.0))
		x = x.normalized()
		_seg[i].basis = Basis(x, y, x.cross(y))
	_seg[SEGS].position = _pts[SEGS]


func _mat(albedo: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = rough
	m.metallic = metal
	return m


func _cyl(r_bot: float, r_top: float, h: float, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.bottom_radius = r_bot
	m.top_radius = r_top
	m.height = h
	m.radial_segments = 8
	m.rings = 1
	m.material = mat
	mi.mesh = m
	mi.position = pos
	add_child(mi)


func _box(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	add_child(mi)
