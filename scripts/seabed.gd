extends Node3D
## Heightmapped seafloor + mini islands. One baked RF texture is the source of
## truth for the mesh, the ocean shore foam, and CPU queries (rocks, camera).

const TERRAIN_SIZE := 2048.0
const TEX_RES := 768
## Deep water. She was a 28 m basin — shallow enough that the bottom read as a
## floor just out of sight, which flattens the whole sea. At 74 m the light is
## gone long before the sand is, and a dive has somewhere to go.
const BASE_DEPTH := -74.0
# Shrinking this is tempting — most of it is invisible under opaque water — but
# it also carries the islands, and a short mesh cuts them off mid-shore. So keep
# the reach and buy the saving back in density instead.
const NEAR_SIZE := 640.0
const NEAR_QUAD := 3.2
const GRID := 18
const SPAWN_CLEAR := 80.0
const LIGHTHOUSE_X := 52.0
const LIGHTHOUSE_Z := -186.0

var follow_target: Node3D
var height_texture: ImageTexture
var terrain_size := TERRAIN_SIZE

var _img: Image
var _mat: ShaderMaterial
var _weed_mat: ShaderMaterial
var _rock_mat: ShaderMaterial
var _near: MeshInstance3D
var _noise: FastNoiseLite
var _detail: FastNoiseLite
var _islands: Array[Vector4] = [] # x, z, radius, peak


func _ready() -> void:
	_noise = FastNoiseLite.new()
	_noise.seed = 20260827
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.0032
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = 4

	_detail = FastNoiseLite.new()
	_detail.seed = 91
	_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_detail.frequency = 0.018
	_detail.fractal_octaves = 3

	_place_islands()
	_bake_height()
	_build_mesh()
	_build_colliders()
	_build_seaweed()
	_build_rocks()


func get_height(world_pos: Vector3) -> float:
	return _sample_img(world_pos.x, world_pos.z)


func get_walk_height(world_pos: Vector3) -> float:
	## The lighthouse's authored rock is built above the heightmap in three
	## visible tiers. Feet must follow those visible tops, not the terrain hidden
	## inside them, or the camera walks through the rock's hollow back faces.
	var terrain := get_height(world_pos)
	var d := Vector2(world_pos.x - LIGHTHOUSE_X,
			world_pos.z - LIGHTHOUSE_Z).length()
	var root_y := get_height(Vector3(LIGHTHOUSE_X, 0.0, LIGHTHOUSE_Z)) - 0.4
	if d <= 26.2:
		return maxf(terrain, root_y + 5.8)
	if d <= 28.7:
		return maxf(terrain, root_y + 4.9)
	if d <= 33.7:
		return maxf(terrain, root_y + 2.2)
	return terrain


func _wrap_uv(t: float) -> float:
	return fposmod(t, 1.0)


func _sample_img(x: float, z: float) -> float:
	if _img == null:
		return BASE_DEPTH
	var u := _wrap_uv(x / TERRAIN_SIZE + 0.5) * float(TEX_RES)
	var v := _wrap_uv(z / TERRAIN_SIZE + 0.5) * float(TEX_RES)
	var x0 := int(floor(u))
	var y0 := int(floor(v))
	var tx := u - float(x0)
	var ty := v - float(y0)
	x0 = posmod(x0, TEX_RES)
	y0 = posmod(y0, TEX_RES)
	var x1 := (x0 + 1) % TEX_RES
	var y1 := (y0 + 1) % TEX_RES
	var a := _img.get_pixel(x0, y0).r
	var b := _img.get_pixel(x1, y0).r
	var c := _img.get_pixel(x0, y1).r
	var d := _img.get_pixel(x1, y1).r
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), ty)


func _basin(x: float, z: float) -> float:
	var m := _noise.get_noise_2d(x, z)
	var d := _detail.get_noise_2d(x, z)
	# Open ocean stays deep: trenches ~-74 m, typical ~-45 m, rare shelves ~-22 m.
	# Shallows exist only as island skirts stamped later — not a swimming-pool spawn.
	return BASE_DEPTH + m * 48.0 + d * 4.2


func _place_islands() -> void:
	# Landmark rock for the lighthouse — dry, wide enough for the tower + cottage.
	_islands.append(Vector4(LIGHTHOUSE_X, LIGHTHOUSE_Z, 58.0, 6.8))
	var rng := RandomNumberGenerator.new()
	rng.seed = 2708
	var cell := TERRAIN_SIZE / float(GRID)
	var half := TERRAIN_SIZE * 0.5
	for gy in GRID:
		for gx in GRID:
			# Sparse on purpose. This is a deep-water place; the point of the
			# horizon is that there is nothing on it.
			if rng.randf() > 0.15:
				continue
			var cx := -half + (float(gx) + rng.randf_range(0.22, 0.78)) * cell
			var cz := -half + (float(gy) + rng.randf_range(0.22, 0.78)) * cell
			if Vector2(cx, cz).length() < SPAWN_CLEAR:
				continue
			var kind := rng.randf()
			var radius: float
			var peak: float
			if kind < 0.55:
				radius = rng.randf_range(2.2, 4.2)
				peak = rng.randf_range(0.18, 0.55)
			elif kind < 0.88:
				radius = rng.randf_range(3.2, 5.8)
				peak = rng.randf_range(0.4, 1.05)
			else:
				radius = rng.randf_range(4.5, 7.2)
				peak = rng.randf_range(0.8, 1.55)
			_islands.append(Vector4(cx, cz, _min_radius(radius), peak))
	# A couple of close cays — small, not extra landmasses.
	for i in 2:
		var ang := rng.randf_range(0.0, TAU)
		var dist := rng.randf_range(95.0, 190.0)
		_islands.append(Vector4(
			cos(ang) * dist, sin(ang) * dist,
			_min_radius(rng.randf_range(2.4, 4.4)), rng.randf_range(0.28, 0.75)))

	# --- real landmasses -----------------------------------------------------
	# Everything above is rocks: nothing wider than seven metres. Land you can
	# see from a long way off, steer for, and pile up on has to be a different
	# order of thing entirely, so it is placed by hand rather than scattered —
	# a handful of headlands at the distances a boat actually crosses.
	# Two, and both a long way off. Five of them turned the horizon into an
	# archipelago; the sea here is supposed to be empty, and land is supposed to
	# be an event.
	for big in [
		Vector4(-352.0, -138.0, 96.0, 19.0),    # high western headland
		Vector4(-188.0, 512.0, 124.0, 26.0),    # the big one, far southward
	]:
		_islands.append(big)

	# --- stacks and reefs ----------------------------------------------------
	# Rock that stands out of the water in its own right: sea stacks off the
	# headlands, and reefs in open water that you will not see until you are on
	# them. These are what make the chart worth reading.
	for st in [
		Vector4(-248.0, -196.0, 15.0, 8.5), Vector4(-268.0, -60.0, 12.0, 6.0),
		Vector4(-96.0, 396.0, 16.0, 9.0), Vector4(-300.0, 610.0, 14.0, 7.0),
		Vector4(150.0, -300.0, 11.0, 3.0),
	]:
		_islands.append(Vector4(st.x, st.y, _min_radius(st.z), st.w))

	# Submerged mounts. Radius stays under 14 so the stamp does not grow a
	# dry plateau. You will not see these from the boat; you meet them.
	for sm in [
		Vector4(28.0, 62.0, 11.0, -9.0),
		Vector4(-44.0, 38.0, 10.0, -14.0),
		Vector4(72.0, -22.0, 12.0, -7.5),
		Vector4(-18.0, -70.0, 11.5, -18.0),
		Vector4(110.0, 40.0, 10.5, -11.0),
		Vector4(-80.0, 95.0, 12.0, -8.0),
	]:
		_islands.append(sm)


func _min_radius(r: float) -> float:
	## An island narrower than a few heightmap texels cannot be represented: the
	## bilinear mesh runs from the -28 m basin up to the peak across a single
	## quad and draws a 30 m needle instead of a cay. Invisible while the water
	## was opaque; obvious the moment you can see through it.
	return maxf(r, TERRAIN_SIZE / float(TEX_RES) * 4.0)


func _bake_height() -> void:
	_img = Image.create(TEX_RES, TEX_RES, false, Image.FORMAT_RF)
	for y in TEX_RES:
		for x in TEX_RES:
			var wx := (float(x) / float(TEX_RES) - 0.5) * TERRAIN_SIZE
			var wz := (float(y) / float(TEX_RES) - 0.5) * TERRAIN_SIZE
			_img.set_pixel(x, y, Color(_basin(wx, wz), 0.0, 0.0))
	for isl in _islands:
		_stamp_island(isl)
	height_texture = ImageTexture.create_from_image(_img)


func _stamp_island(isl: Vector4) -> void:
	# Two stages: a broad shoal that climbs out of the basin, then the cay on
	# top of it. A single cone straight from -28 m to the peak is a glass
	# pyramid once the water is actually transparent — nothing in the sea rises
	# 30 m in 10 m of horizontal distance.
	var radius: float = isl.z
	var peak: float = isl.w
	var shelf := lerpf(-11.0, -5.0, clampf(peak, 0.0, 1.6) / 1.6)
	if radius >= 14.0:
		shelf = -3.5
	var lighthouse_land := absf(isl.x - LIGHTHOUSE_X) < 0.1 \
			and absf(isl.y - LIGHTHOUSE_Z) < 0.1
	var reach := radius * (4.6 if lighthouse_land \
			else (2.15 if radius >= 14.0 else 3.6))
	var r_px := int(ceil(reach / TERRAIN_SIZE * float(TEX_RES))) + 1
	var cx := int(floor((isl.x / TERRAIN_SIZE + 0.5) * float(TEX_RES)))
	var cy := int(floor((isl.y / TERRAIN_SIZE + 0.5) * float(TEX_RES)))
	for j in range(-r_px, r_px + 1):
		for i in range(-r_px, r_px + 1):
			var px := posmod(cx + i, TEX_RES)
			var py := posmod(cy + j, TEX_RES)
			var wx := (float(px) / float(TEX_RES) - 0.5) * TERRAIN_SIZE
			var wz := (float(py) / float(TEX_RES) - 0.5) * TERRAIN_SIZE
			# shortest wrapped delta to island center
			var dx := wx - isl.x
			var dz := wz - isl.y
			if dx > TERRAIN_SIZE * 0.5:
				dx -= TERRAIN_SIZE
			elif dx < -TERRAIN_SIZE * 0.5:
				dx += TERRAIN_SIZE
			if dz > TERRAIN_SIZE * 0.5:
				dz -= TERRAIN_SIZE
			elif dz < -TERRAIN_SIZE * 0.5:
				dz += TERRAIN_SIZE
			var d := Vector2(dx, dz).length()
			if d >= reach:
				continue
			var h := _img.get_pixel(px, py).r
			# shoal
			var wo := 1.0 - d / reach
			wo = wo * wo * (3.0 - 2.0 * wo)
			var lifted := maxf(h, lerpf(h, shelf, wo))
			# Landmark rocks keep a flat top so buildings don't hang off a dome.
			# Scaled off the radius now that there is more than one of them —
			# the old 40/95 was the lighthouse rock's shape, hard-coded.
			if radius >= 14.0:
				# Lobed, not circular. A perfect disc of land reads as a stamp
				# the moment you get close to it; two sine terms keyed off the
				# island's own coordinates give each one headlands and bays of
				# its own without any extra cost.
				var ang := atan2(dz, dx)
				var wob := 1.0 + 0.23 * sin(ang * 3.0 + isl.x * 0.05) \
						+ 0.13 * sin(ang * 5.0 - isl.y * 0.04)
				var plateau: float = radius * 0.69 * wob
				var outer: float = radius * (2.05 if lighthouse_land else 1.64) * wob
				# The harbour island has a real sandy apron rather than a cliff from
				# the beach straight into the deep basin. Follow the irregular coast
				# and ease continuously back to the original seabed at the outer edge:
				# ankle water, then a swimmable shelf, then genuinely deep water.
				if lighthouse_land and d >= outer:
					var shelf_t: float = clampf((d - outer) \
							/ maxf(reach - outer, 0.01), 0.0, 1.0)
					shelf_t = shelf_t * shelf_t * (3.0 - 2.0 * shelf_t)
					lifted = maxf(lifted, lerpf(-0.55, h, shelf_t))
				if d <= plateau:
					lifted = maxf(lifted, peak)
				elif d < outer:
					var t := (d - plateau) / (outer - plateau)
					t = t * t * (3.0 - 2.0 * t)
					lifted = maxf(lifted, lerpf(peak, -0.5, t))
			else:
				var ti := d / (radius * 1.28)
				if ti < 1.0:
					var wi := 1.0 - ti
					wi = wi * wi * (3.0 - 2.0 * wi)
					lifted = maxf(lifted, lerpf(lifted, peak, wi))
			if lifted > h:
				_img.set_pixel(px, py, Color(lifted, 0.0, 0.0))


func _noise_tex() -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = 44
	n.frequency = 0.04
	n.fractal_octaves = 4
	var tex := NoiseTexture2D.new()
	tex.noise = n
	tex.seamless = true
	tex.width = 256
	tex.height = 256
	return tex


func _build_mesh() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/seabed.gdshader")
	_mat.set_shader_parameter("height_map", height_texture)
	_mat.set_shader_parameter("detail_noise", _noise_tex())
	_mat.set_shader_parameter("terrain_size", TERRAIN_SIZE)

	_near = MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(NEAR_SIZE, NEAR_SIZE)
	var subdiv := int(NEAR_SIZE / NEAR_QUAD) - 1
	mesh.subdivide_width = subdiv
	mesh.subdivide_depth = subdiv
	_near.mesh = mesh
	_near.material_override = _mat
	_near.layers = 4
	_near.extra_cull_margin = 8.0
	_near.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_near.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(_near)


func _build_colliders() -> void:
	## Nothing here any more, and deliberately. There used to be a cylinder per
	## island, which meant a boat bounced off an invisible drum around a rock
	## and sailed straight over any island wider than fourteen metres — which is
	## every island worth the name. The bottom IS a heightmap, so the boat feels
	## for it directly (boat.gd/_run_aground) and grounds on whatever is
	## actually there: a shoal, a beach, a reef, the face of a headland.
	pass


func _build_seaweed() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 414
	var xform := PackedFloat32Array()
	var n := 0
	for isl in _islands:
		var blades := rng.randi_range(8, 22)
		for i in blades:
			var ang := rng.randf() * TAU
			var dist := isl.z * rng.randf_range(0.85, 2.1)
			var p := Vector3(isl.x + cos(ang) * dist, 0.0, isl.y + sin(ang) * dist)
			p.y = _sample_img(p.x, p.z)
			if p.y > -1.2 or p.y < -16.0:
				continue
			var basis := Basis.from_euler(Vector3(0.0, rng.randf() * TAU, rng.randf_range(-0.12, 0.12)))
			var tall := clampf((-p.y - 1.2) / 8.0, 0.35, 1.0)
			basis = basis.scaled(Vector3(
				rng.randf_range(0.7, 1.25),
				rng.randf_range(0.9, 2.1) * tall,
				rng.randf_range(0.7, 1.25)))
			var t := Transform3D(basis, p)
			_append_xform(xform, t)
			n += 1
	if n == 0:
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = n
	mm.mesh = _weed_mesh()
	mm.visible_instance_count = n
	for i in n:
		mm.set_instance_transform(i, _xform_from_packed(xform, i))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.layers = 4
	_weed_mat = ShaderMaterial.new()
	_weed_mat.shader = load("res://shaders/seaweed.gdshader")
	mi.material_override = _weed_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.visibility_range_end = 160.0
	mi.visibility_range_end_margin = 30.0
	add_child(mi)


func _weed_mesh() -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(0.11, 1.15)
	q.center_offset = Vector3(0.0, 0.52, 0.0)
	return q


func _build_rocks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	_rock_mat = ShaderMaterial.new()
	_rock_mat.shader = load("res://shaders/seabed_rock.gdshader")
	var box := BoxMesh.new()
	box.size = Vector3(1, 1, 1)
	box.material = _rock_mat
	var xforms: Array[Transform3D] = []
	for isl in _islands:
		var count := rng.randi_range(2, 6) if isl.w < 0.0 else rng.randi_range(1, 3)
		for i in count:
			var ang := rng.randf() * TAU
			var dist := rng.randf_range(0.0, isl.z * (1.1 if isl.w < 0.0 else 0.45))
			var p := Vector3(isl.x + cos(ang) * dist, 0.0, isl.y + sin(ang) * dist)
			p.y = _sample_img(p.x, p.z) + rng.randf_range(0.02, 0.12)
			var s := rng.randf_range(0.35, 1.4) if isl.w < 0.0 else rng.randf_range(0.12, 0.35)
			var b := Basis.from_euler(Vector3(
				rng.randf_range(-0.5, 0.5), rng.randf() * TAU, rng.randf_range(-0.5, 0.5)))
			b = b.scaled(Vector3(s * rng.randf_range(0.6, 1.4), s * rng.randf_range(0.45, 0.9),
					s * rng.randf_range(0.6, 1.4)))
			xforms.append(Transform3D(b, p))
	# Loose floor stones in the basin around the boat — things that resolve
	# out of the black when you get close.
	for i in 55:
		var p := Vector3(rng.randf_range(-90.0, 90.0), 0.0, rng.randf_range(-90.0, 90.0))
		p.y = _sample_img(p.x, p.z)
		if p.y > -6.0 or p.y < -68.0:
			continue
		var s := rng.randf_range(0.4, 1.8)
		var b := Basis.from_euler(Vector3(
			rng.randf_range(-0.6, 0.6), rng.randf() * TAU, rng.randf_range(-0.6, 0.6)))
		b = b.scaled(Vector3(s * rng.randf_range(0.5, 1.5), s * rng.randf_range(0.35, 0.8),
				s * rng.randf_range(0.5, 1.5)))
		xforms.append(Transform3D(b, p + Vector3(0.0, s * 0.15, 0.0)))
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = xforms.size()
	mm.mesh = box
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.visibility_range_end = 140.0
	mi.visibility_range_end_margin = 25.0
	add_child(mi)


func _append_xform(out: PackedFloat32Array, t: Transform3D) -> void:
	out.append(t.basis.x.x)
	out.append(t.basis.y.x)
	out.append(t.basis.z.x)
	out.append(t.origin.x)
	out.append(t.basis.x.y)
	out.append(t.basis.y.y)
	out.append(t.basis.z.y)
	out.append(t.origin.y)
	out.append(t.basis.x.z)
	out.append(t.basis.y.z)
	out.append(t.basis.z.z)
	out.append(t.origin.z)


func _xform_from_packed(data: PackedFloat32Array, i: int) -> Transform3D:
	var o := i * 12
	var b := Basis(
		Vector3(data[o], data[o + 4], data[o + 8]),
		Vector3(data[o + 1], data[o + 5], data[o + 9]),
		Vector3(data[o + 2], data[o + 6], data[o + 10]))
	var origin := Vector3(data[o + 3], data[o + 7], data[o + 11])
	return Transform3D(b, origin)


func set_sun(dir: Vector3) -> void:
	if _mat != null:
		_mat.set_shader_parameter("sun_dir", dir)


func set_caustics(scale: float, energy: float) -> void:
	## Ties the caustic net on the sand to the sea state above it.
	if _mat == null:
		return
	_mat.set_shader_parameter("caustic_scale", scale)
	_mat.set_shader_parameter("caustic_energy", energy)


func set_underwater(on: bool, wave_time: float, wind_dir: Vector2) -> void:
	if _mat != null:
		_mat.set_shader_parameter("camera_under", 1 if on else 0)
		_mat.set_shader_parameter("wave_time", wave_time)
	if _weed_mat != null:
		_weed_mat.set_shader_parameter("camera_under", 1 if on else 0)
		_weed_mat.set_shader_parameter("wave_time", wave_time)
		_weed_mat.set_shader_parameter("wind_dir", wind_dir)
	if _rock_mat != null:
		_rock_mat.set_shader_parameter("camera_under", 1 if on else 0)


func _process(_delta: float) -> void:
	if follow_target == null or _near == null:
		return
	var p: Vector3 = follow_target.global_position
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera != null and camera.global_position.distance_squared_to(p) > 3600.0:
		# The heightmap is global, but its dense render mesh must surround whoever
		# is looking at it. At the island the moored vessel is now far enough away
		# that following it clipped away the beach and the back half of the shelf.
		p = camera.global_position
	_near.global_position = Vector3(snappedf(p.x, NEAR_QUAD), 0.0, snappedf(p.z, NEAR_QUAD))
