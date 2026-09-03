extends Node3D
## Small working pier and two physical mooring lines for the lighthouse berth.

const LINE_STIFFNESS := 18500.0
const LINE_DAMPING := 2600.0
const LINE_LIMIT := 82000.0
const QUAY_BOLLARD_BACK := 0.65
const LINE_SEGMENTS := 48
const PIER_WATER_REACH := 35.0

var boat: RigidBody3D
var ocean: Node3D
var seabed: Node3D
var pier_start := Vector3.ZERO
var pier_end := Vector3.ZERO
var pier_axis := Vector3.FORWARD
var pier_right := Vector3.RIGHT
var deck_y := 1.0
var pier_length := 12.0
var pier_half_width := 2.7

var _lines: Array[Dictionary] = []
var _rope_mat: StandardMaterial3D
var _harbor_lights: Array[OmniLight3D] = []
var _light_clock := 0.0


func setup(p_boat: RigidBody3D, p_ocean: Node3D, p_seabed: Node3D) -> void:
	boat = p_boat
	ocean = p_ocean
	seabed = p_seabed
	var island := Vector3(float(seabed.LIGHTHOUSE_X), 0.0,
			float(seabed.LIGHTHOUSE_Z))
	var outward := Vector3(boat.global_position.x - island.x, 0.0,
			boat.global_position.z - island.z).normalized()
	var dry := island
	for metre in range(1, 350):
		var p := boat.global_position.move_toward(island, float(metre))
		if float(seabed.call("get_height", p)) > float(ocean.call("get_height", p)) + 0.45:
			dry = p
			break
	pier_axis = outward
	pier_right = pier_axis.cross(Vector3.UP).normalized()
	var inner := Vector3(dry.x, 0.0, dry.z) - pier_axis * 8.0
	deck_y = maxf(float(seabed.call("get_height", dry)),
			float(seabed.call("get_height", inner))) + 0.22
	pier_start = Vector3(inner.x, deck_y, inner.z)
	# The harbour ends at a fixed quay head; it does not grow until it touches a
	# distant boat. All remaining open water is spanned by the actual hawser.
	pier_end = Vector3(dry.x, deck_y, dry.z) + pier_axis * PIER_WATER_REACH
	pier_length = maxf(pier_start.distance_to(pier_end), 8.0)
	_build_harbor()
	_build_lines()


func player_spawn() -> Vector3:
	## A few steps behind the first planks, looking straight down the lit pier.
	var spawn := pier_start - pier_axis * 1.8
	spawn.y = maxf(float(seabed.call("get_walk_height", spawn)), deck_y) + 0.10
	return spawn


func _process(delta: float) -> void:
	_light_clock += delta
	for i in _harbor_lights.size():
		var lamp := _harbor_lights[i]
		var slow := sin(_light_clock * (2.1 + float(i) * 0.17) + float(i) * 1.9)
		var nervous := sin(_light_clock * 17.0 + float(i) * 3.7)
		var dip := 0.30 if nervous < -0.94 else 1.0
		lamp.light_energy = (1.65 + slow * 0.24) * dip


func walk_height(world_pos: Vector3) -> float:
	var rel := world_pos - pier_start
	var along := rel.dot(pier_axis)
	var across := absf(rel.dot(pier_right))
	var width := 4.0 if along > pier_length - 6.0 else pier_half_width
	if along >= -0.5 and along <= pier_length + 0.8 and across <= width:
		return deck_y + 0.10
	return -INF


func _physics_process(_delta: float) -> void:
	if boat == null:
		return
	for i in _lines.size():
		var line := _lines[i]
		if bool(line["cut"]):
			continue
		var boat_point: Vector3 = boat.global_transform * (line["boat_local"] as Vector3)
		var shore_point: Vector3 = line["shore"] as Vector3
		var delta := shore_point - boat_point
		var distance := delta.length()
		if distance > 0.001:
			var direction := delta / distance
			var point_velocity := boat.linear_velocity \
					+ boat.angular_velocity.cross(boat_point - boat.global_position)
			var stretch := maxf(distance - float(line["rest"]), 0.0)
			var separating_speed := maxf(-point_velocity.dot(direction), 0.0)
			var tension := minf(stretch * LINE_STIFFNESS \
					+ separating_speed * LINE_DAMPING, LINE_LIMIT)
			if tension > 0.0:
				boat.apply_force(direction * tension, boat_point - boat.global_position)
		_update_line_visual(line, boat_point, shore_point)


func hit_by_knife(_damage: float, position: Vector3, _normal: Vector3) -> void:
	var nearest := -1
	var nearest_d := INF
	for i in _lines.size():
		if bool(_lines[i]["cut"]):
			continue
		var mid: Vector3 = _lines[i]["mid"] as Vector3
		var d := mid.distance_squared_to(position)
		if d < nearest_d:
			nearest_d = d
			nearest = i
	if nearest < 0:
		return
	_lines[nearest]["cut"] = true
	var visuals: Array = _lines[nearest]["visuals"] as Array
	for visual in visuals:
		(visual as Node3D).visible = false
	var collider := _lines[nearest]["collider"] as CollisionShape3D
	if collider != null:
		collider.set_deferred("disabled", true)
	var boat_collider := _lines[nearest]["boat_cut_shape"] as CollisionShape3D
	if boat_collider != null:
		boat_collider.set_deferred("disabled", true)


func _build_harbor() -> void:
	var timber := _mat(Color(0.24, 0.15, 0.085), 0.94)
	var wet := _mat(Color(0.13, 0.085, 0.052), 0.98)
	var iron := _mat(Color(0.075, 0.082, 0.083), 0.72, 0.62)
	var centre := (pier_start + pier_end) * 0.5
	_box(Vector3(pier_half_width * 2.0, 0.24, pier_length), centre,
			Vector3(0.0, atan2(pier_axis.x, pier_axis.z), 0.0), timber)
	var head_centre := pier_end - pier_axis * 2.7
	_box(Vector3(8.0, 0.26, 6.0), head_centre,
			Vector3(0.0, atan2(pier_axis.x, pier_axis.z), 0.0), timber)
	# Individual cap planks break the silhouette and catch the lamps; the darker
	# alternating boards keep the long pier from reading as one extruded box.
	for plank_i: int in range(int(pier_length)):
		var plank_pos: Vector3 = pier_start + pier_axis * (float(plank_i) + 0.5)
		var plank_mat := timber if plank_i % 3 != 1 else wet
		_box(Vector3(pier_half_width * 2.0 - 0.10, 0.035, 0.92),
				plank_pos + Vector3.UP * 0.135,
				Vector3(0.0, atan2(pier_axis.x, pier_axis.z), 0.0), plank_mat)
	for d: int in range(0, int(pier_length) + 1, 2):
		var p: Vector3 = pier_start + pier_axis * float(d)
		for side: float in [-1.0, 1.0]:
			_build_pile(p + pier_right * side * (pier_half_width - 0.25), wet)
		if d % 6 == 0:
			var lamp_side: float = -1.0 if (d / 6) % 2 == 0 else 1.0
			_build_lamp(p + pier_right * (pier_half_width - 0.42) * lamp_side, iron)
	var bp: Vector3 = pier_end - pier_axis * QUAY_BOLLARD_BACK + pier_right * 1.10
	_cyl(0.22, 0.29, 0.72, bp + Vector3.UP * 0.36, iron)
	_cyl(0.37, 0.37, 0.14, bp + Vector3.UP * 0.76, iron)


func _build_lines() -> void:
	_rope_mat = _mat(Color(0.30, 0.22, 0.12), 0.98)
	for side: float in [1.0]:
		var shore: Vector3 = pier_end - pier_axis * QUAY_BOLLARD_BACK \
				+ pier_right * side * 1.10 \
				+ Vector3.UP * 0.82
		# Small stern cleat on top of the transom cap, just outboard of the
		# boarding ladder. This point is both the visible knot and physical lead.
		var local: Vector3 = Vector3(side * 1.32, 1.40, 5.55)
		var bp: Vector3 = boat.global_transform * local
		var holder := StaticBody3D.new()
		add_child(holder)
		var shape := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.16
		capsule.height = maxf(bp.distance_to(shore), 0.25)
		shape.shape = capsule
		holder.add_child(shape)
		# A separate target surrounds the knot on the ship. The camera excludes
		# the boat's own collision RID during a knife swing, so this independent
		# body guarantees the hawser can be cut while standing aboard.
		var boat_cut_body := StaticBody3D.new()
		add_child(boat_cut_body)
		var boat_cut_shape := CollisionShape3D.new()
		var boat_cut_sphere := SphereShape3D.new()
		boat_cut_sphere.radius = 0.34
		boat_cut_shape.shape = boat_cut_sphere
		boat_cut_body.add_child(boat_cut_shape)
		var visuals: Array[MeshInstance3D] = []
		for _segment in LINE_SEGMENTS:
			var mi := MeshInstance3D.new()
			var mesh := CylinderMesh.new()
			mesh.top_radius = 0.027
			mesh.bottom_radius = 0.027
			mesh.height = 1.0
			mesh.radial_segments = 7
			mesh.material = _rope_mat
			mi.mesh = mesh
			add_child(mi)
			visuals.append(mi)
		for loop_i in 3:
			var loop := MeshInstance3D.new()
			var torus := TorusMesh.new()
			torus.inner_radius = 0.25 + float(loop_i) * 0.012
			torus.outer_radius = 0.285 + float(loop_i) * 0.012
			torus.rings = 18
			torus.ring_segments = 7
			torus.material = _rope_mat
			loop.mesh = torus
			add_child(loop)
			loop.global_position = shore - Vector3.UP * (0.22 + float(loop_i) * 0.065)
			visuals.append(loop)
		_build_boat_bollard(local, visuals)
		var line := {
			"boat_local": local, "shore": shore,
			"rest": bp.distance_to(shore) * 1.012,
			"cut": false, "visuals": visuals,
			"body": holder, "collider": shape, "mid": (bp + shore) * 0.5,
			"boat_cut_body": boat_cut_body, "boat_cut_shape": boat_cut_shape,
		}
		_lines.append(line)
		_update_line_visual(line, bp, shore)


func _update_line_visual(line: Dictionary, a: Vector3, b: Vector3) -> void:
	var visuals: Array = line["visuals"] as Array
	var segment_count: int = LINE_SEGMENTS
	var points: Array[Vector3] = []
	var distance := a.distance_to(b)
	var slack := clampf(float(line["rest"]) - distance, 0.0, 1.2)
	for i in segment_count + 1:
		var t := float(i) / float(segment_count)
		var p := a.lerp(b, t)
		p.y -= sin(t * PI) * (0.10 + slack * 0.55)
		points.append(p)
	for i in segment_count:
		_place_cylinder(visuals[i] as Node3D, points[i], points[i + 1])
	var body := line["body"] as StaticBody3D
	var mid := (a + b) * 0.5
	line["mid"] = mid
	_place_y_axis(body, mid, b - a)
	var boat_cut_body := line["boat_cut_body"] as StaticBody3D
	boat_cut_body.global_position = a
	var capsule := (line["collider"] as CollisionShape3D).shape as CapsuleShape3D
	capsule.height = maxf(distance, capsule.radius * 2.0)


func _place_cylinder(node: Node3D, a: Vector3, b: Vector3) -> void:
	var delta := b - a
	_place_y_axis(node, (a + b) * 0.5, delta)
	node.scale = Vector3(1.0, maxf(delta.length(), 0.001), 1.0)


func _place_y_axis(node: Node3D, centre: Vector3, delta: Vector3) -> void:
	node.global_position = centre
	if delta.length_squared() > 0.000001:
		node.global_basis = Basis(Quaternion(Vector3.UP, delta.normalized()))


func _mat(color: Color, roughness: float, metallic := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material


func _box(size: Vector3, position: Vector3, rotation: Vector3,
		material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	add_child(instance)
	instance.global_position = position
	instance.rotation = rotation


func _cyl(bottom: float, top: float, height: float, position: Vector3,
		material: Material, layer_mask: int = 1) -> void:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = bottom
	mesh.top_radius = top
	mesh.height = height
	mesh.radial_segments = 12
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.layers = layer_mask
	add_child(instance)
	instance.global_position = position


func _build_pile(deck_point: Vector3, material: Material) -> void:
	## Split at the actual waterline. The submerged timber remains visible by
	## refraction in the main camera, but layer 8 is excluded from the planar
	## mirror so an underwater post can never appear as a reflection above it.
	var top_y := deck_y + 0.35
	# Every pile reaches and enters the actual sand. A fixed 3.45 m length made
	# the outer harbour float as soon as the bottom became deeper than wading
	# depth, especially along the newly extended pier.
	var bed_y := float(seabed.call("get_height", deck_point))
	var bottom_y := minf(deck_y - 3.45, bed_y - 0.45)
	var water_y := float(ocean.call("get_height", deck_point))
	var split_y := clampf(water_y, bottom_y, top_y)
	var under_height := split_y - bottom_y
	if under_height > 0.02:
		_cyl(0.16, 0.18, under_height,
				Vector3(deck_point.x, bottom_y + under_height * 0.5, deck_point.z),
				material, 8)
	var above_height := top_y - split_y
	if above_height > 0.02:
		_cyl(0.18, 0.19, above_height,
				Vector3(deck_point.x, split_y + above_height * 0.5, deck_point.z),
				material, 1)


func _build_lamp(position: Vector3, metal: Material) -> void:
	_cyl(0.055, 0.07, 2.4, position + Vector3.UP * 1.2, metal)
	var glass := _mat(Color(0.68, 0.57, 0.34), 0.34)
	glass.emission_enabled = true
	glass.emission = Color(1.0, 0.58, 0.20)
	glass.emission_energy_multiplier = 2.4
	_cyl(0.13, 0.13, 0.28, position + Vector3.UP * 2.42, glass)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.48, 0.17)
	lamp.omni_range = 10.5
	lamp.shadow_enabled = true
	add_child(lamp)
	lamp.global_position = position + Vector3.UP * 2.42
	_harbor_lights.append(lamp)


func _build_boat_bollard(local: Vector3, rope_visuals: Array[MeshInstance3D]) -> void:
	## A real termination at the ship end, immediately beside the stern ladder.
	## It is parented to the hull, so both the iron and its turns follow roll and
	## heave while the live span continues to the fixed quay bollard.
	var iron := _mat(Color(0.065, 0.07, 0.072), 0.70, 0.68)
	var post := MeshInstance3D.new()
	var post_mesh := CylinderMesh.new()
	post_mesh.bottom_radius = 0.095
	post_mesh.top_radius = 0.125
	post_mesh.height = 0.28
	post_mesh.radial_segments = 12
	post_mesh.material = iron
	post.mesh = post_mesh
	boat.add_child(post)
	post.position = local + Vector3.DOWN * 0.14
	var cap := MeshInstance3D.new()
	var cap_mesh := CylinderMesh.new()
	cap_mesh.bottom_radius = 0.17
	cap_mesh.top_radius = 0.17
	cap_mesh.height = 0.065
	cap_mesh.radial_segments = 12
	cap_mesh.material = iron
	cap.mesh = cap_mesh
	boat.add_child(cap)
	cap.position = local + Vector3.UP * 0.015
	for loop_i in 3:
		var loop := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.105 + float(loop_i) * 0.008
		torus.outer_radius = 0.138 + float(loop_i) * 0.008
		torus.rings = 16
		torus.ring_segments = 7
		torus.material = _rope_mat
		loop.mesh = torus
		boat.add_child(loop)
		loop.position = local + Vector3.DOWN * (0.035 + float(loop_i) * 0.042)
		rope_visuals.append(loop)
