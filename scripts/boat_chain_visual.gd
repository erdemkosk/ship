class_name BoatChainVisual
extends Node3D
## Owns the anchor-chain pile and animated feed run.

const CHAIN_PITCH := 0.032

var _pile: Array[MeshInstance3D] = []
var _cable: Array[MeshInstance3D] = []
var _link_mesh: Mesh


func build(material: Material) -> void:
	_link_mesh = _make_link_mesh(material)
	_build_pile(material)
	_build_cable(material)


func tick(stowed: float, tackle: Node) -> void:
	var shown := int(round(stowed * float(_pile.size())))
	for index in _pile.size():
		_pile[index].visible = index < shown
	_tick_cable(stowed, tackle)


func _make_link_mesh(material: Material) -> Mesh:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.008
	torus.outer_radius = 0.0155
	torus.rings = 12
	torus.ring_segments = 10
	torus.material = material
	return torus


func _link_instance(material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = _link_mesh if _link_mesh != null else _make_link_mesh(material)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


func _build_pile(material: Material) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	const PER_LAYER := 8
	const LAYERS := 6
	for index in PER_LAYER * LAYERS:
		var layer: int = index / PER_LAYER
		var offset: int = index % PER_LAYER
		var angle := float(offset) / float(PER_LAYER) * TAU + float(layer) * 0.38
		var radius := 0.20 - float(layer) * 0.008 + rng.randf_range(-0.025, 0.028)
		var link := _link_instance(material)
		link.position = Vector3(
				radius * cos(angle) + rng.randf_range(-0.018, 0.018),
				0.075 + float(layer) * 0.052 + rng.randf_range(-0.008, 0.012),
				-3.05 + radius * sin(angle) * 1.12)
		link.rotation = Vector3(rng.randf_range(-0.45, 0.45), angle + PI * 0.5,
				rng.randf_range(-0.35, 0.35))
		link.scale = Vector3(1.70, 1.0, 1.0)
		add_child(link)
		_pile.append(link)


func _build_cable(material: Material) -> void:
	for _index in 96:
		var link := _link_instance(material)
		add_child(link)
		_cable.append(link)


func _catmull_point(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3,
		t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t
			+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
			+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


func _catmull_path(keys: PackedVector3Array, samples_per_segment: int) -> PackedVector3Array:
	var result := PackedVector3Array()
	if keys.size() < 2:
		return keys
	for index in range(keys.size() - 1):
		var p0: Vector3 = keys[maxi(index - 1, 0)]
		var p1: Vector3 = keys[index]
		var p2: Vector3 = keys[index + 1]
		var p3: Vector3 = keys[mini(index + 2, keys.size() - 1)]
		for sample in samples_per_segment:
			result.append(_catmull_point(p0, p1, p2, p3,
					float(sample) / float(samples_per_segment)))
	result.append(keys[keys.size() - 1])
	return result


func _feed_path() -> PackedVector3Array:
	var inlet := PackedVector3Array([
		Vector3(0.0, 0.36, -3.05), Vector3(0.0, 0.28, -3.02),
		Vector3(0.0, 0.48, -3.02), Vector3(0.0, 0.68, -3.02),
		Vector3(0.0, 0.82, -3.10), Vector3(0.0, 0.90, -3.20),
	])
	var points := _catmull_path(inlet, 4)
	var center := Vector3(0.0, 1.02, -3.35)
	for index in 22:
		var angle := lerpf(2.18, -0.42, float(index) / 21.0)
		points.append(Vector3(0.0, center.y + cos(angle) * 0.163,
				center.z + sin(angle) * 0.163))
	var outlet := PackedVector3Array([
		points[points.size() - 1], Vector3(0.0, 1.14, -3.55),
		Vector3(0.0, 1.05, -3.74), Vector3(0.0, 1.08, -3.94),
		Vector3(0.0, 1.17, -4.07), Vector3(0.0, 1.20, -4.12),
	])
	var rest := _catmull_path(outlet, 5)
	for index in range(1, rest.size()):
		points.append(rest[index])
	return points


func _point_at_distance(points: PackedVector3Array, distances: PackedFloat32Array,
		distance: float) -> Vector3:
	var clamped := clampf(distance, 0.0, distances[distances.size() - 1])
	for index in range(1, points.size()):
		if distances[index] >= clamped - 1e-5:
			var span := maxf(distances[index] - distances[index - 1], 1e-5)
			return points[index - 1].lerp(points[index],
					(clamped - distances[index - 1]) / span)
	return points[points.size() - 1]


func _place_link(link: MeshInstance3D, index: int, from: Vector3, to: Vector3) -> void:
	var segment := to - from
	var length := segment.length()
	if length < 1e-5:
		link.visible = false
		return
	link.visible = true
	var tangent := segment / length
	var reference := Vector3.RIGHT if absf(tangent.dot(Vector3.RIGHT)) < 0.86 \
			else Vector3.FORWARD
	var normal := tangent.cross(reference)
	if normal.length_squared() < 1e-6:
		normal = Vector3.UP
	normal = normal.normalized()
	var hole := normal if index % 2 == 0 else tangent.cross(normal).normalized()
	var side := tangent.cross(hole)
	side = normal if side.length_squared() < 1e-6 else side.normalized()
	hole = tangent.cross(side).normalized()
	link.position = (from + to) * 0.5
	link.basis = Basis(tangent * 1.78, hole, side)


func _tick_cable(stowed: float, tackle: Node) -> void:
	if _cable.is_empty() or tackle == null:
		return
	var points := _feed_path()
	var distances := PackedFloat32Array()
	distances.resize(points.size())
	for index in range(1, points.size()):
		distances[index] = distances[index - 1] + points[index - 1].distance_to(points[index])
	var total := maxf(distances[distances.size() - 1], 0.05)
	var chain_out := float(tackle.get("chain_out"))
	var slide := fposmod(chain_out, CHAIN_PITCH)
	var hidden_length := (1.0 - stowed / 0.14) * 0.88 if stowed < 0.14 else 0.0
	for index in _cable.size():
		var start := float(index) * CHAIN_PITCH + slide
		if start > total - 0.012 or start < hidden_length:
			_cable[index].visible = false
			continue
		var finish := start + CHAIN_PITCH * 0.58
		_place_link(_cable[index], index,
				_point_at_distance(points, distances, start),
				_point_at_distance(points, distances, finish))
