extends Node3D
## Slack warp in the boat's frame. Two pins, extra length, hangs under gravity
## and the hull's own acceleration so a roll lets it sag instead of staying
## glued in a torus.

const N := 16
const DAMP := 0.972
const ITERS := 8
const G := 16.0
const WeatherScript := preload("res://scripts/weather.gd")

var pin_a := Vector3.ZERO
var pin_b := Vector3.ZERO
var rest := 0.08
var deck_y := 0.64
var _pts := PackedVector3Array()
var _prev := PackedVector3Array()
var _seg: Array[MeshInstance3D] = []
var _prev_v := Vector3.ZERO
var _prev_w := Vector3.ZERO
var _have := false


func setup(a: Vector3, b: Vector3, slack: float, mat: Material, on_deck := 0.64) -> void:
	pin_a = a
	pin_b = b
	deck_y = on_deck
	var chord := a.distance_to(b)
	var drop: float = maxf(minf(a.y, b.y) - deck_y, 0.12)
	var length: float = maxf(chord * slack, chord + 2.0 * drop * 0.92)
	rest = length / float(N - 1)
	_pts.resize(N)
	_prev.resize(N)
	for i in N:
		var t := float(i) / float(N - 1)
		var p: Vector3 = a.lerp(b, t)
		p.y -= sin(PI * t) * drop * 0.92
		p.y = maxf(p.y, deck_y)
		# Hang inboard, over the deck, not out through the bulwark.
		var inb: float = 1.52 * signf(p.x) if absf(p.x) > 0.2 else p.x
		p.x = lerpf(p.x, inb, sin(PI * t) * 0.45)
		_pts[i] = p
		_prev[i] = p
	for i in N - 1:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.011
		cm.bottom_radius = 0.011
		cm.height = rest
		cm.radial_segments = 5
		cm.rings = 1
		cm.material = mat
		mi.mesh = cm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_seg.append(mi)
	_place()


func _physics_process(delta: float) -> void:
	if _pts.is_empty() or delta < 0.0001:
		return
	delta = minf(delta, 0.04)
	var boat := get_parent() as RigidBody3D
	if boat == null:
		return
	var v: Vector3 = boat.linear_velocity
	var w: Vector3 = boat.angular_velocity
	var acc := Vector3.ZERO
	var alpha := Vector3.ZERO
	if _have:
		acc = (v - _prev_v) / delta
		alpha = (w - _prev_w) / delta
	_prev_v = v
	_prev_w = w
	_have = true
	var inv: Basis = boat.global_basis.inverse()
	var g_l: Vector3 = inv * Vector3(0.0, -G, 0.0)
	var a_l: Vector3 = inv * acc
	var w_l: Vector3 = inv * w
	var al_l: Vector3 = inv * alpha
	var wind_l := Vector3.ZERO
	var wx: Variant = boat.get("weather")
	var wthr := wx as WeatherScript
	if wthr != null:
		var wa: float = deg_to_rad(wthr.wind_direction_deg)
		var ws: float = wthr.wind_speed
		wind_l = inv * (Vector3(cos(wa), 0.0, sin(wa)) * ws * 0.08)

	for i in range(1, N - 1):
		var r: Vector3 = _pts[i]
		var accel: Vector3 = g_l - a_l - al_l.cross(r) - w_l.cross(w_l.cross(r)) + wind_l
		var cur := _pts[i]
		_pts[i] = cur + (cur - _prev[i]) * DAMP + accel * delta * delta
		_prev[i] = cur

	for _k in ITERS:
		_pts[0] = pin_a
		_pts[N - 1] = pin_b
		for i in N - 1:
			var d: Vector3 = _pts[i + 1] - _pts[i]
			var dist := d.length()
			if dist < 1e-6:
				continue
			var corr: Vector3 = d * ((rest - dist) / dist) * 0.5
			if i == 0:
				_pts[i + 1] += corr * 2.0
			elif i == N - 2:
				_pts[i] -= corr * 2.0
			else:
				_pts[i] -= corr
				_pts[i + 1] += corr
		for i in range(1, N - 1):
			_pts[i].y = maxf(_pts[i].y, deck_y)
			if _pts[i].y < 1.08:
				_pts[i].x = clampf(_pts[i].x, -1.86, 1.86)
	_pts[0] = pin_a
	_pts[N - 1] = pin_b
	_place()


func _place() -> void:
	for i in N - 1:
		var a := _pts[i]
		var b := _pts[i + 1]
		var d := b - a
		var h := d.length()
		_seg[i].position = (a + b) * 0.5
		if h < 1e-5:
			continue
		var y := d / h
		var x := y.cross(Vector3.FORWARD)
		if x.length_squared() < 1e-6:
			x = y.cross(Vector3.RIGHT)
		x = x.normalized()
		# Stretch the Y column to the live segment; rest-length mesh, live gap.
		_seg[i].basis = Basis(x, y * (h / rest), x.cross(y))
