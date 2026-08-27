extends Node3D
## Gerstner wave ocean driven by a Pierson-Moskowitz spectrum. The exact same
## wave set runs in the vertex shader (GPU) and in _displace() (CPU) so the
## boat's buoyancy matches what you see.
##
## The spectrum is what makes it read as a sea rather than as a few sine waves:
## energy is spread over ~40 components from swell-length down to half a metre,
## with directional spread widening at short wavelengths (short-crested chop on
## top of long-crested swell). Whatever chop is too small to draw at distance is
## handed to the shader as `mss` (mean square slope) and comes back as
## roughness — that's the sun glitter path.

const MAX_WAVES := 48
const NUM_SWELL := 4
const NUM_WIND := 36
const NUM_WAVES := NUM_SWELL + NUM_WIND
const G := 9.81
## Fully developed seas are brutal (Hs ~7 m at 18 m/s). Limited fetch keeps the
## presets sailable; the wave-height slider multiplies on top of this.
const SEA_DEVELOPMENT := 0.55
const EARTH_RADIUS := 6371000.0
## Visual layers. The reflection camera has to be able to exclude the water it
## is reflecting into (and the seabed, which would otherwise show up mirrored
## in the sky reflection), so both live on their own layers.
const MAX_FLOATERS := 8  # must match the shader's MAX_FLOATERS
const MAX_TRAIL := 20    # must match the shader's MAX_TRAIL
## How far the boat travels between track samples. Small enough that a hard turn
## still reads as a curve, large enough that MAX_TRAIL covers the whole visible
## length of the wake.
const TRAIL_SPACING := 2.5

## Tidal stream. Coastal water is not still: it runs, it reverses, and it speeds
## up wherever the bottom comes close. TIDE_PERIOD is one full ebb-flood cycle —
## six hours compressed to a few minutes so you can actually feel it turn.
const TIDE_PERIOD := 420.0
const CURRENT_SAMPLE := 30.0   # finite-difference step for the stream function
const OCEAN_LAYER := 2
const SEABED_LAYER := 4
## Ground tackle. Kept out of the mirror: the anchor spends its life BELOW the
## water, and a planar reflection of something below the plane comes back as a
## ghost of it hanging in the air above — which is exactly what a sinking anchor
## looked like.
const TACKLE_LAYER := 8

# Clipmap: dense 0.5 m quads around the boat, coarser rings outward.
const CLOSE_SIZE := 48.0
const CLOSE_QUAD := 0.5
const MID_SIZE := 168.0
const MID_QUAD := 2.0
const WIDE_SIZE := 900.0
const WIDE_QUAD := 9.0
const FAR_SIZE := 14000.0
const FAR_QUAD := FAR_SIZE / 96.0

var wind_speed := 14.0
var wind_direction_deg := 40.0
## Peak tidal stream in m/s (springs). 0 turns the current off entirely.
var current_strength := 0.85
var wave_height := 1.0
var steepness := 0.9

var follow_target: Node3D
var seabed: Node3D
var wave_time := 0.0
var max_amplitude := 0.5
var sig_height := 1.0  ## significant wave height (Hs), metres
var camera_under := false

var _mat_close: ShaderMaterial
var _mat_mid: ShaderMaterial
var _mat_wide: ShaderMaterial
var _mat_far: ShaderMaterial
var _close: MeshInstance3D
var _mid: MeshInstance3D
var _wide: MeshInstance3D
var _far: MeshInstance3D

var _far_y := -1.0
var _dirs: Array[Vector2] = []
var _amps := PackedFloat32Array()
var _ks := PackedFloat32Array()
var _omegas := PackedFloat32Array()
# Flattened tables for the CPU evaluator. Buoyancy runs this loop thousands of
# times per frame in GDScript, so every array lookup and multiply that can be
# hoisted out of it, is.
var _kx := PackedFloat32Array()    # k * dir.x
var _kz := PackedFloat32Array()    # k * dir.y
var _om := PackedFloat32Array()    # omega
var _sax := PackedFloat32Array()   # steepness * dir.x * amp
var _saz := PackedFloat32Array()   # steepness * dir.y * amp
var _ka := PackedFloat32Array()    # k * amp
var _kadx := PackedFloat32Array()  # k * amp * dir.x
var _kadz := PackedFloat32Array()  # k * amp * dir.y
var _cpu_n := 0                    # components the CPU bothers with
var _shoal_key := Vector2i(2147483647, 0)
var _shoal_val := 1.0
var _cur_noise: FastNoiseLite
var _tide := 0.0
var _sky_params := {}
var _tex_drop: ImageTexture
var _splash_fx: GPUParticles3D
var _splash_pm: ParticleProcessMaterial
var _spindrift: GPUParticles3D
var _spindrift_pm: ParticleProcessMaterial
var _rings: Array[MeshInstance3D] = []
var _ring_next := 0
var _breakers: Array[GPUParticles3D] = []
var _breaker_next := 0
var _breaker_cd := 0.0
var _scan_rng := RandomNumberGenerator.new()
var _refl_vp: SubViewport
var _refl_cam: Camera3D
var _refl_env: Environment
var _refl_plane_y := 0.0
var _floaters: Array = []  # [{node, radius, draft}]
var _trail: Array = []     # [[Vector2 world_xz, float speed]], newest first


func _ready() -> void:
	var shader: Shader = load("res://shaders/ocean.gdshader")
	_mat_close = ShaderMaterial.new()
	_mat_close.shader = shader

	var normal_tex := _bake_detail_normal(512, 4.2)
	var foam_tex := _bake_foam_noise(512)
	_mat_close.set_shader_parameter("detail_normal", normal_tex)
	_mat_close.set_shader_parameter("normal_strength", 0.72)
	_mat_close.set_shader_parameter("foam_noise", foam_tex)

	_mat_mid = _mat_close.duplicate()
	_mat_wide = _mat_close.duplicate()
	_mat_far = _mat_close.duplicate()

	_close = _make_ring(CLOSE_SIZE, CLOSE_QUAD, _mat_close)
	_mid = _make_ring(MID_SIZE, MID_QUAD, _mat_mid)
	_wide = _make_ring(WIDE_SIZE, WIDE_QUAD, _mat_wide)
	_far = _make_ring(FAR_SIZE, FAR_QUAD, _mat_far)
	_far.position.y = _far_y

	_cur_noise = FastNoiseLite.new()
	_cur_noise.seed = 5150
	_cur_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_cur_noise.frequency = 0.0016
	_cur_noise.fractal_octaves = 2

	_bind_fallback_height()
	rebuild_waves()
	_build_splash()
	_build_spray()
	_build_reflection()


func bind_seabed(s: Node3D) -> void:
	seabed = s
	_push_seabed_uniforms()
	_push_uniforms()


func set_sky_param(pname: String, value: Variant) -> void:
	## Called by weather.gd for every sky uniform, so the sea reflects exactly
	## the sky that is being drawn overhead.
	_sky_params[pname] = value
	for mat: ShaderMaterial in _mats():
		mat.set_shader_parameter(pname, value)


func set_lighthouse_beams(pos: Vector3, dir_a: Vector3, dir_b: Vector3, on: float) -> void:
	for mat: ShaderMaterial in _mats():
		mat.set_shader_parameter("lh_pos", pos)
		mat.set_shader_parameter("lh_dir_a", dir_a)
		mat.set_shader_parameter("lh_dir_b", dir_b)
		mat.set_shader_parameter("lh_on", on)


func _bind_fallback_height() -> void:
	var img := Image.create(1, 1, false, Image.FORMAT_RF)
	img.set_pixel(0, 0, Color(-28.0, 0.0, 0.0))
	var tex := ImageTexture.create_from_image(img)
	for mat: ShaderMaterial in _mats():
		mat.set_shader_parameter("height_map", tex)


func set_wind(speed: float, direction_deg: float, height: float, steep: float) -> void:
	wind_speed = speed
	wind_direction_deg = direction_deg
	wave_height = height
	steepness = steep
	rebuild_waves()


func wind_vector() -> Vector3:
	var a := deg_to_rad(wind_direction_deg)
	return Vector3(cos(a), 0.0, sin(a)) * wind_speed


func rebuild_waves() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260813

	_dirs.clear()
	_amps = PackedFloat32Array()
	_ks = PackedFloat32Array()
	_omegas = PackedFloat32Array()

	var u := maxf(wind_speed, 0.8)
	var wind_rad := deg_to_rad(wind_direction_deg)
	# Pierson-Moskowitz peak frequency for a fully developed sea at this wind.
	var omega_p := 0.855 * G / u
	var omega_min := omega_p * 0.62
	var omega_max := sqrt(G * TAU / 0.55)  # ~0.55 m shortest wavelength we draw
	var span := log(omega_max / omega_min)

	# --- wind sea: PM spectrum, log-spaced, spread widening with frequency ---
	for i in NUM_WIND:
		var t := (float(i) + 0.5) / float(NUM_WIND)
		var w := omega_min * exp(span * t)
		var dw := w * span / float(NUM_WIND)
		var s := 8.1e-3 * G * G / pow(w, 5.0) * exp(-1.25 * pow(omega_p / w, 4.0))
		var a := sqrt(maxf(2.0 * s * dw, 0.0))
		# Long components stay long-crested; capillary chop scatters wide.
		var spread := lerpf(0.22, 1.25, t)
		var ang := wind_rad + rng.randf_range(-spread, spread)
		_dirs.append(Vector2(cos(ang), sin(ang)))
		_amps.append(a)
		_ks.append(w * w / G)
		_omegas.append(w)

	# --- swell: older, longer, from a different quarter than today's wind ----
	# A real sea almost never has swell and wind sea aligned; that mismatch is
	# what makes the surface look like it has history.
	var swell_rad := wind_rad + deg_to_rad(58.0)
	var swell_hs := 0.45
	for i in NUM_SWELL:
		var t := float(i) / float(maxi(NUM_SWELL - 1, 1))
		var w: float = omega_p * lerpf(0.36, 0.58, t)
		var ang := swell_rad + rng.randf_range(-0.13, 0.13)
		_dirs.append(Vector2(cos(ang), sin(ang)))
		_amps.append(swell_hs * lerpf(1.0, 0.45, t))
		_ks.append(w * w / G)
		_omegas.append(w)

	# Normalise to a real significant wave height, so the slider is a physical
	# multiplier rather than an arbitrary gain.
	var m0 := 0.0
	for i in NUM_WAVES:
		m0 += _amps[i] * _amps[i] * 0.5
	var hs_now := 4.0 * sqrt(maxf(m0, 1e-9))
	var hs_target := clampf(SEA_DEVELOPMENT * 0.21 * u * u / G, 0.02, 20.0) * wave_height
	var amp_scale := hs_target / maxf(hs_now, 1e-6)
	for i in NUM_WAVES:
		_amps[i] *= amp_scale
	sig_height = hs_target

	# Keep total steepness below the self-intersection threshold at extreme
	# slider combos, otherwise crests fold into loops.
	var total := 0.0
	for i in NUM_WAVES:
		total += _ks[i] * _amps[i]
	total *= maxf(steepness, 0.001)
	if total > 1.45:
		var s := 1.45 / total
		for i in NUM_WAVES:
			_amps[i] *= s
		sig_height *= s

	# Crest reference for the shader. With 40 components the sum of amplitudes
	# wildly overestimates a real crest; Rayleigh statistics put the tallest
	# crest in a short record at roughly Hs * 0.9.
	max_amplitude = maxf(sig_height * 0.62, 0.05)

	# The flat horizon plate must stay below the deepest trough, or it pokes
	# through the animated surface and draws ugly intersection lines.
	_far_y = -(max_amplitude * 0.45 + 0.35)
	if _far != null:
		_far.position.y = _far_y

	_build_cpu_tables()
	_push_uniforms()


func _build_cpu_tables() -> void:
	## Sort by amplitude, then let the CPU skip the tail. A component with a
	## one-centimetre amplitude cannot move a boat, but it costs exactly as much
	## to evaluate as the swell — and buoyancy evaluates the whole set for every
	## probe, every physics tick. The GPU still draws all of them.
	var order: Array[int] = []
	for i in NUM_WAVES:
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return _amps[a] > _amps[b])

	var d2: Array[Vector2] = []
	var a2 := PackedFloat32Array()
	var k2 := PackedFloat32Array()
	var o2 := PackedFloat32Array()
	for i in order:
		d2.append(_dirs[i])
		a2.append(_amps[i])
		k2.append(_ks[i])
		o2.append(_omegas[i])
	_dirs = d2
	_amps = a2
	_ks = k2
	_omegas = o2

	_kx = PackedFloat32Array(); _kx.resize(NUM_WAVES)
	_kz = PackedFloat32Array(); _kz.resize(NUM_WAVES)
	_om = PackedFloat32Array(); _om.resize(NUM_WAVES)
	_sax = PackedFloat32Array(); _sax.resize(NUM_WAVES)
	_saz = PackedFloat32Array(); _saz.resize(NUM_WAVES)
	_ka = PackedFloat32Array(); _ka.resize(NUM_WAVES)
	_kadx = PackedFloat32Array(); _kadx.resize(NUM_WAVES)
	_kadz = PackedFloat32Array(); _kadz.resize(NUM_WAVES)
	var cutoff := maxf(sig_height * 0.004, 0.008)
	_cpu_n = 0
	for i in NUM_WAVES:
		var d: Vector2 = _dirs[i]
		var a: float = _amps[i]
		var k: float = _ks[i]
		_kx[i] = k * d.x
		_kz[i] = k * d.y
		_om[i] = _omegas[i]
		_sax[i] = steepness * d.x * a
		_saz[i] = steepness * d.y * a
		_ka[i] = k * a
		_kadx[i] = k * a * d.x
		_kadz[i] = k * a * d.y
		if a >= cutoff:
			_cpu_n = i + 1
	_cpu_n = clampi(_cpu_n, 8, NUM_WAVES)


func _push_uniforms() -> void:
	var wparams := PackedVector4Array()
	wparams.resize(MAX_WAVES)
	var womegas := PackedFloat32Array()
	womegas.resize(MAX_WAVES)
	for i in NUM_WAVES:
		wparams[i] = Vector4(_dirs[i].x, _dirs[i].y, _amps[i], _ks[i])
		womegas[i] = _omegas[i]

	var wind_dir := Vector2(cos(deg_to_rad(wind_direction_deg)), sin(deg_to_rad(wind_direction_deg)))
	# Cox-Munk: the slope variance of a wind-roughened sea. Drives the width of
	# the sun glitter path and the roughness of the far water.
	var slope_var := clampf(0.003 + 0.0052 * wind_speed, 0.004, 0.14)
	for mat: ShaderMaterial in _mats():
		mat.set_shader_parameter("waves", wparams)
		mat.set_shader_parameter("omegas", womegas)
		mat.set_shader_parameter("choppiness", steepness)
		mat.set_shader_parameter("max_amp", max_amplitude)
		mat.set_shader_parameter("wind_dir", wind_dir)
		# Stokes drift is roughly 3% of the wind. _process adds the tidal stream
		# on top of this every frame.
		mat.set_shader_parameter("surface_drift", wind_dir * wind_speed * 0.03)
		mat.set_shader_parameter("mss", slope_var)
		mat.set_shader_parameter("curvature_k", 1.0 / (2.0 * EARTH_RADIUS))
		mat.set_shader_parameter("foam_amount", clampf(0.18 + wind_speed * 0.022, 0.0, 1.0))
		# Steeper seas fold sooner; let whitecaps arrive with the wind.
		mat.set_shader_parameter("foam_threshold", clampf(0.04 + wind_speed * 0.012, 0.04, 0.42))
	_mat_close.set_shader_parameter("num_waves", NUM_WAVES)
	_mat_close.set_shader_parameter("hull_mask", 1)
	_mat_close.set_shader_parameter("far_clip", 0)
	_mat_mid.set_shader_parameter("num_waves", NUM_WAVES)
	_mat_mid.set_shader_parameter("hull_mask", 0)
	_mat_mid.set_shader_parameter("far_clip", 1)
	_mat_mid.set_shader_parameter("near_radius", _clip_radius(CLOSE_SIZE))
	_mat_wide.set_shader_parameter("num_waves", NUM_WAVES)
	_mat_wide.set_shader_parameter("hull_mask", 0)
	_mat_wide.set_shader_parameter("far_clip", 1)
	_mat_wide.set_shader_parameter("near_radius", _clip_radius(MID_SIZE))
	_mat_far.set_shader_parameter("num_waves", 0)
	_mat_far.set_shader_parameter("hull_mask", 0)
	_mat_far.set_shader_parameter("far_clip", 1)
	_mat_far.set_shader_parameter("near_radius", _clip_radius(WIDE_SIZE))
	# The horizon plate has no geometry left to carry chop, so all of its slope
	# variance has to arrive as roughness.
	_mat_far.set_shader_parameter("normal_strength", 0.0)
	if seabed != null and seabed.has_method("set_caustics"):
		# A short, steep sea makes a fine, fast caustic net; a long swell makes a
		# broad slow one.
		seabed.set_caustics(clampf(0.45 + wind_speed * 0.055, 0.3, 2.2),
				clampf(1.5 - wind_speed * 0.032, 0.3, 1.5))
	_push_cull_margins()
	_push_seabed_uniforms()
	_apply_sky_params()
	_update_spray_rate()


func _apply_sky_params() -> void:
	for k: String in _sky_params:
		for mat: ShaderMaterial in _mats():
			mat.set_shader_parameter(k, _sky_params[k])


func _push_seabed_uniforms() -> void:
	if seabed == null:
		return
	var htex: Texture2D = seabed.get("height_texture")
	var tsize: float = float(seabed.get("terrain_size"))
	for mat: ShaderMaterial in _mats():
		if htex != null:
			mat.set_shader_parameter("height_map", htex)
		mat.set_shader_parameter("terrain_size", tsize)
		mat.set_shader_parameter("camera_under", 1 if camera_under else 0)


func _process(delta: float) -> void:
	wave_time += delta
	_tide = sin(TAU * wave_time / TIDE_PERIOD)
	for mat: ShaderMaterial in _mats():
		mat.set_shader_parameter("wave_time", wave_time)

	if follow_target != null:
		var p := follow_target.global_position
		# Snap each ring to its own quad so vertices don't swim as the boat moves.
		_snap_ring(_close, p, CLOSE_QUAD, 0.0)
		_snap_ring(_mid, p, MID_QUAD, 0.0)
		_snap_ring(_wide, p, WIDE_QUAD, 0.0)
		_snap_ring(_far, p, FAR_QUAD, _far_y)

		# wake track + hull water mask follow the boat every frame
		var vel := Vector3.ZERO
		if follow_target is RigidBody3D:
			vel = follow_target.linear_velocity
		var bp := Vector2(p.x, p.z)
		var spd := Vector2(vel.x, vel.z).length()
		_update_trail(bp, spd, delta)
		# Foam floats on the water, so it has to ride the current as well as the
		# wind. One sample at the boat is enough for what you can see.
		var cur := current_at(p)
		var wdir := Vector2(cos(deg_to_rad(wind_direction_deg)), sin(deg_to_rad(wind_direction_deg)))
		var drift := wdir * wind_speed * 0.03 + cur
		for mat: ShaderMaterial in _mats():
			mat.set_shader_parameter("surface_drift", drift)
			mat.set_shader_parameter("current_vec", cur)
		_mat_close.set_shader_parameter("boat_inv", follow_target.global_transform.affine_inverse())
		for mat: ShaderMaterial in _mats():
			mat.set_shader_parameter("boat_pos", bp)
			mat.set_shader_parameter("boat_speed", spd)
	for mat: ShaderMaterial in _mats():
		mat.set_shader_parameter("camera_under", 1 if camera_under else 0)
	if seabed != null:
		var wd := Vector2(cos(deg_to_rad(wind_direction_deg)), sin(deg_to_rad(wind_direction_deg)))
		seabed.set_underwater(camera_under, wave_time, wd)
	_update_spray(delta)
	_update_floaters()
	_update_reflection(delta)


func _build_reflection() -> void:
	## Planar reflection. The analytic sky reflection gets the sea to look like
	## water; this is what puts the boat, the buoy and the flotsam back ON it.
	## The mirror plane is mean sea level, so a fragment riding a crest is
	## slightly off — the standard planar approximation, and invisible at the
	## roughness a sea surface has.
	_refl_vp = SubViewport.new()
	_refl_vp.size = Vector2i(480, 270)
	_refl_vp.transparent_bg = true
	_refl_vp.handle_input_locally = false
	_refl_vp.msaa_3d = Viewport.MSAA_DISABLED
	_refl_vp.positional_shadow_atlas_size = 0
	_refl_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_refl_vp)
	_refl_vp.world_3d = get_viewport().world_3d

	# The reflection pass must NOT draw the sky: the shader already has an
	# analytic sky reflection, and a drawn sky would come back with alpha 1
	# everywhere and paint the whole sea flat. A transparent background makes
	# alpha the coverage mask for "something real is reflected here".
	# Linear tonemapping, because the result is composited into the water and
	# then tonemapped once by the main pass.
	_refl_env = Environment.new()
	_refl_env.background_mode = Environment.BG_COLOR
	_refl_env.background_color = Color(0, 0, 0, 0)
	_refl_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_refl_env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_refl_env.tonemap_exposure = 1.0

	_refl_cam = Camera3D.new()
	# Moved from _process to track the main camera. Global physics interpolation
	# would warn every frame (Camera3D::_notification) if this stayed ON.
	_refl_cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# Everything except the water itself and the seabed.
	_refl_cam.cull_mask = 0xFFFFF & ~(OCEAN_LAYER | SEABED_LAYER | TACKLE_LAYER)
	_refl_cam.near = 0.1
	# Far enough to hold the lighthouse and the full length of its beams; they
	# are the one thing on this sea worth seeing reflected from a distance.
	_refl_cam.far = 1400.0
	_refl_cam.environment = _refl_env
	_refl_vp.add_child(_refl_cam)
	_refl_cam.current = true

	var tex := _refl_vp.get_texture()
	for mat: ShaderMaterial in _mats():
		mat.set_shader_parameter("reflect_tex", tex)


func _update_reflection(delta: float) -> void:
	if _refl_cam == null:
		return
	var cam := get_viewport().get_camera_3d()
	# Nothing to mirror from below the surface, and the mirror plane would be
	# behind the camera anyway.
	var on := cam != null and not camera_under
	for mat: ShaderMaterial in _mats():
		mat.set_shader_parameter("reflect_on", 1 if on else 0)
	if not on:
		_refl_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	# Every frame. Skipping every other one halved a cost that was already only
	# half a millisecond, and the stale frame showed up as the reflection
	# sliding whenever the camera moved.
	_refl_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	var vs := get_viewport().get_visible_rect().size
	var want := Vector2i(maxi(int(vs.x) / 3, 64), maxi(int(vs.y) / 3, 64))
	if _refl_vp.size != want:
		_refl_vp.size = want

	# The mirror plane is the water directly under the camera, NOT y = 0. In a
	# 4.5 m sea the boat spends half its time several metres below mean level,
	# and mirroring about y = 0 puts every reflection metres out of place.
	# Smoothed, because the instantaneous surface height jitters with the chop
	# and a jittering mirror plane makes the whole reflection swim.
	# The plane has to sit on the water around whatever you are most likely to
	# see reflected — which is the boat and what is floating next to it, not the
	# horizon. Averaging in a point 18 m ahead dragged the plane off the boat and
	# made its reflection drift; track the surface under the boat instead, and
	# track it quickly, or the plane lags behind the heave and the whole
	# reflection slides up and down.
	var anchor: Vector3 = cam.global_position
	if follow_target != null and is_instance_valid(follow_target):
		if anchor.distance_squared_to(follow_target.global_position) < 3600.0:
			anchor = follow_target.global_position
	var h: float = get_height(anchor)
	if not is_finite(_refl_plane_y):
		_refl_plane_y = h
	_refl_plane_y = lerpf(_refl_plane_y, h, 1.0 - exp(-22.0 * delta))
	for mat: ShaderMaterial in _mats():
		mat.set_shader_parameter("reflect_plane_y", _refl_plane_y)

	# Same position and orientation reflected in that plane. This is an ordinary
	# camera looking at the real world from under the surface — no world
	# mirroring, so backface culling stays correct; the price is that its image
	# comes out horizontally flipped, which the shader undoes.
	var t := cam.global_transform
	var fwd := -t.basis.z
	var up := t.basis.y
	var pm := Vector3(t.origin.x, 2.0 * _refl_plane_y - t.origin.y, t.origin.z)
	var fm := Vector3(fwd.x, -fwd.y, fwd.z)
	var um := Vector3(up.x, -up.y, up.z)
	if absf(fm.normalized().dot(um.normalized())) > 0.999:
		um = Vector3.UP
	_refl_cam.look_at_from_position(pm, pm + fm, um)
	_refl_cam.fov = cam.fov
	_refl_cam.keep_aspect = cam.keep_aspect


func register_floater(node: Node3D, radius: float, draft: float) -> void:
	## Anything that sits in the water and should push it around. Cheap enough
	## that every plank can register; only the nearest few reach the shader.
	_floaters.append({"node": node, "radius": radius, "draft": draft})


func _update_floaters() -> void:
	var cam := get_viewport().get_camera_3d()
	var centre: Vector3 = cam.global_position if cam != null else Vector3.ZERO
	var found: Array = []
	if follow_target != null and is_instance_valid(follow_target):
		# A boat sitting still barely marks the water; one under way pushes a
		# real bow wave. Scale the disturbance with speed through the water.
		var bv := Vector3.ZERO
		if follow_target is RigidBody3D:
			bv = follow_target.linear_velocity
		var bspd := clampf(Vector2(bv.x, bv.z).length() / 12.0, 0.0, 1.0)
		found.append([0.0, Vector2(follow_target.global_position.x, follow_target.global_position.z),
				3.4, lerpf(0.05, 0.22, bspd)])
	var stale := false
	for f in _floaters:
		var n: Node3D = f["node"]
		if not is_instance_valid(n):
			stale = true
			continue
		var p := n.global_position
		var d := Vector2(p.x - centre.x, p.z - centre.z).length_squared()
		if d > 3600.0:  # past 60 m the ring is under a pixel
			continue
		found.append([d, Vector2(p.x, p.z), f["radius"], f["draft"]])
	if stale:
		_floaters = _floaters.filter(func(f): return is_instance_valid(f["node"]))
	found.sort_custom(func(a, b): return a[0] < b[0])

	var arr := PackedVector4Array()
	arr.resize(MAX_FLOATERS)
	var n_used := mini(found.size(), MAX_FLOATERS)
	for i in n_used:
		arr[i] = Vector4(found[i][1].x, found[i][1].y, found[i][2], found[i][3])
	for mat: ShaderMaterial in _mats():
		mat.set_shader_parameter("floaters", arr)
		mat.set_shader_parameter("num_floaters", n_used)


func shoal_factor(world_pos: Vector3) -> float:
	## Mirrors the Green's-law term in the vertex shader so CPU buoyancy and the
	## drawn surface stay the same surface over a shoal.
	if seabed == null:
		return 1.0
	# Every buoyancy probe would otherwise bilinearly sample the seabed image,
	# and Image.get_pixel is not cheap. A hull's worth of probes all land in the
	# same 8 m cell, so one lookup covers them.
	var key := Vector2i(int(floor(world_pos.x * 0.125)), int(floor(world_pos.z * 0.125)))
	if key == _shoal_key:
		return _shoal_val
	_shoal_key = key
	var depth: float = maxf(-float(seabed.get_height(world_pos)), 0.4)
	_shoal_val = clampf(pow(clampf(18.0 / depth, 1.0, 30.0), 0.25), 1.0, 2.2)
	return _shoal_val


func set_reflection_ambient(color: Color, energy: float) -> void:
	## Keeps objects in the reflection lit like objects in the main pass.
	if _refl_env != null:
		_refl_env.ambient_light_color = color
		_refl_env.ambient_light_energy = energy


func _update_trail(bp: Vector2, spd: float, delta: float) -> void:
	## The boat's recent track, newest first. A new sample is laid down every
	## TRAIL_SPACING metres of travel, so the trail resolves a turn rather than
	## the passage of time — a boat drifting at half a knot does not fill it.
	if not _trail.is_empty() and bp.distance_squared_to(_trail[0][0]) > 1600.0:
		_trail.clear()  # teleported (respawn); the old track is not ours
	if _trail.is_empty() or bp.distance_to(_trail[0][0]) >= TRAIL_SPACING:
		_trail.push_front([bp, spd])
		if _trail.size() > MAX_TRAIL:
			_trail.resize(MAX_TRAIL)

	# A wake dissipates. Without this the arc a boat carved an hour ago would
	# still be sitting in the water behind it.
	var decay := exp(-delta / 7.0)
	for e in _trail:
		e[1] *= decay
	while not _trail.is_empty() and _trail[_trail.size() - 1][1] < 0.2:
		_trail.resize(_trail.size() - 1)

	var arr := PackedVector4Array()
	arr.resize(MAX_TRAIL)
	# Element 0 is the transom right now, so the wake's root never lags behind
	# the boat even between samples.
	arr[0] = Vector4(bp.x, bp.y, 0.0, spd)
	var n := 1
	var prev := bp
	var arc := 0.0
	for e in _trail:
		var q: Vector2 = e[0]
		var d := prev.distance_to(q)
		if d < 0.05:
			continue
		arc += d
		arr[n] = Vector4(q.x, q.y, arc, e[1])
		prev = q
		n += 1
		if n >= MAX_TRAIL:
			break
	for mat: ShaderMaterial in _mats():
		mat.set_shader_parameter("trail", arr)
		mat.set_shader_parameter("trail_count", n)


func tide() -> float:
	## -1 at full ebb, +1 at full flood, 0 at slack water.
	return _tide


func _stream(p: Vector2) -> float:
	## Stream function. Taking the current as its perpendicular gradient makes
	## the flow divergence-free by construction — water that turns instead of
	## water that appears and vanishes, so you get gyres and eddies rather than
	## everything sliding the same way.
	return _cur_noise.get_noise_2d(p.x, p.y)


func current_at(world_pos: Vector3) -> Vector2:
	## Horizontal water velocity in m/s.
	if current_strength <= 0.001 or _cur_noise == null:
		return Vector2.ZERO
	var p := Vector2(world_pos.x, world_pos.z)
	var e := CURRENT_SAMPLE
	var dpsi_dz := (_stream(p + Vector2(0.0, e)) - _stream(p - Vector2(0.0, e))) / (2.0 * e)
	var dpsi_dx := (_stream(p + Vector2(e, 0.0)) - _stream(p - Vector2(e, 0.0))) / (2.0 * e)
	# perpendicular gradient => incompressible flow
	var v := Vector2(dpsi_dz, -dpsi_dx) * 4200.0
	if v.length() > 1.0:
		v = v.normalized()
	# Continuity: the same volume through a shallower gap has to move faster.
	# This is why tide rips sit over shoals and off headlands.
	var depth := 28.0
	if seabed != null:
		depth = maxf(-float(seabed.get_height(world_pos)), 1.2)
	var speed_up := clampf(26.0 / depth, 1.0, 3.2)
	return v * current_strength * _tide * speed_up


func get_seafloor_height(world_pos: Vector3) -> float:
	if seabed != null:
		return float(seabed.get_height(world_pos))
	return -28.0


func _mats() -> Array[ShaderMaterial]:
	return [_mat_close, _mat_mid, _mat_wide, _mat_far]


func _clip_radius(inner_size: float) -> float:
	# Hole just inside the denser ring, with extra overlap so Gerstner chop
	# cannot open a gap between clipmap levels.
	var half := inner_size * 0.5
	return maxf(half - max_amplitude * 1.15 - 2.0, half * 0.35)


func _push_cull_margins() -> void:
	var m := max_amplitude + 8.0
	for mi: MeshInstance3D in [_close, _mid, _wide, _far]:
		if mi != null:
			mi.extra_cull_margin = m


func _make_ring(size: float, quad: float, mat: ShaderMaterial) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(size, size)
	var nquads := maxi(int(round(size / quad)), 1)
	mesh.subdivide_width = nquads - 1
	mesh.subdivide_depth = nquads - 1
	mi.mesh = mesh
	mi.material_override = mat
	mi.layers = OCEAN_LAYER
	mi.extra_cull_margin = 12.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(mi)
	return mi


func _snap_ring(mi: MeshInstance3D, p: Vector3, quad: float, y: float) -> void:
	mi.global_position = Vector3(snappedf(p.x, quad), y, snappedf(p.z, quad))


func _tile_noise(n: FastNoiseLite, x: int, y: int, sz: int) -> float:
	var fx := float(x) / float(sz)
	var fy := float(y) / float(sz)
	var s00 := n.get_noise_2d(float(x), float(y))
	var s10 := n.get_noise_2d(float(x - sz), float(y))
	var s01 := n.get_noise_2d(float(x), float(y - sz))
	var s11 := n.get_noise_2d(float(x - sz), float(y - sz))
	return lerpf(lerpf(s00, s10, fx), lerpf(s01, s11, fx), fy)


func _bake_height(seed: int, freq: float, octaves: int, sz: int) -> PackedFloat32Array:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.frequency = freq
	n.fractal_octaves = octaves
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	var h := PackedFloat32Array()
	h.resize(sz * sz)
	for y in sz:
		for x in sz:
			h[y * sz + x] = _tile_noise(n, x, y, sz) * 0.5 + 0.5
	return h


func _bake_detail_normal(sz: int, bump: float) -> ImageTexture:
	var h := _bake_height(1, 0.011, 5, sz)
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	for y in sz:
		for x in sz:
			var l := h[y * sz + ((x - 1 + sz) % sz)]
			var r := h[y * sz + ((x + 1) % sz)]
			var u := h[((y - 1 + sz) % sz) * sz + x]
			var d := h[((y + 1) % sz) * sz + x]
			var nrm := Vector3((l - r) * bump, 2.0, (u - d) * bump).normalized()
			img.set_pixel(x, y, Color(nrm.x * 0.5 + 0.5, nrm.y * 0.5 + 0.5, nrm.z * 0.5 + 0.5, 1.0))
	# Mipmaps matter here: the shader reads this at grazing angles out to a few
	# hundred metres, and an unfiltered normal map aliases into crawling noise.
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _bake_foam_noise(sz: int) -> ImageTexture:
	var h := _bake_height(7, 0.026, 4, sz)
	var img := Image.create(sz, sz, false, Image.FORMAT_L8)
	for y in sz:
		for x in sz:
			var v := h[y * sz + x]
			img.set_pixel(x, y, Color(v, v, v))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func splash(world_pos: Vector3, strength := 1.0) -> void:
	## Water flies up and out, then falls back. Never paint the sea mesh —
	## even 0.5 m quads turn a painted crater into a dark square.
	if _splash_fx == null:
		_build_splash()
	var s := clampf(strength, 0.4, 2.2)
	_splash_pm.initial_velocity_min = 2.4 * s
	_splash_pm.initial_velocity_max = 5.2 * s
	_splash_pm.radial_accel_min = 1.2 * s
	_splash_pm.radial_accel_max = 2.8 * s
	_splash_fx.amount_ratio = clampf(0.4 + s * 0.28, 0.4, 1.0)
	_splash_fx.global_position = Vector3(world_pos.x, get_height(world_pos) + 0.06, world_pos.z)
	_splash_fx.restart()
	_splash_fx.emitting = true
	if not _rings.is_empty():
		var ring := _rings[_ring_next]
		_ring_next = (_ring_next + 1) % _rings.size()
		ring.retrigger(Vector2(world_pos.x, world_pos.z), s,
				0.8 + 0.4 * s, 0.9 + 1.5 * s)


func _ensure_splash_tex() -> void:
	if _tex_drop != null:
		return
	_tex_drop = _make_blob_tex(16, 16, 3.2, false)


func _make_blob_tex(w: int, h: int, softness: float, teardrop: bool) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var u := (float(x) + 0.5) / float(w)
			var v := (float(y) + 0.5) / float(h)
			var dx := (u - 0.5) * 2.0
			var dy := (v - (0.38 if teardrop else 0.5)) * 2.0
			if teardrop:
				var slim := lerpf(0.42, 1.15, v)
				dx /= slim
			var r2 := dx * dx + dy * dy
			var a := exp(-r2 * softness)
			if a < 0.04:
				a = 0.0
			img.set_pixel(x, y, Color(0.82, 0.90, 0.93, a))
	return ImageTexture.create_from_image(img)


func _ramp(colors: PackedColorArray, offsets: PackedFloat32Array) -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = offsets
	g.colors = colors
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


func _droplet_quad(size: Vector2) -> QuadMesh:
	_ensure_splash_tex()
	var quad := QuadMesh.new()
	quad.size = size
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _tex_drop
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	quad.material = mat
	return quad


func _build_splash() -> void:
	_ensure_splash_tex()
	_splash_fx = GPUParticles3D.new()
	_splash_fx.amount = 48
	_splash_fx.lifetime = 0.75
	_splash_fx.one_shot = true
	_splash_fx.explosiveness = 1.0
	_splash_fx.fixed_fps = 30
	_splash_fx.local_coords = false
	_splash_fx.emitting = false
	_splash_fx.transform_align = GPUParticles3D.TRANSFORM_ALIGN_DISABLED
	_splash_fx.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_splash_fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_splash_fx.visibility_aabb = AABB(Vector3(-6, -3, -6), Vector3(12, 10, 12))

	_splash_pm = ParticleProcessMaterial.new()
	_splash_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_splash_pm.emission_sphere_radius = 0.04
	_splash_pm.direction = Vector3(0, 1, 0)
	_splash_pm.spread = 68.0
	_splash_pm.initial_velocity_min = 2.6
	_splash_pm.initial_velocity_max = 5.4
	_splash_pm.gravity = Vector3(0, -17.0, 0)
	_splash_pm.scale_min = 0.5
	_splash_pm.scale_max = 1.05
	_splash_pm.color = Color(0.72, 0.82, 0.86, 0.45)
	_splash_pm.color_ramp = _ramp(
		PackedColorArray([
			Color(0.78, 0.86, 0.88, 0.5),
			Color(0.62, 0.72, 0.74, 0.18),
			Color(0.45, 0.52, 0.54, 0.0)]),
		PackedFloat32Array([0.0, 0.4, 1.0]))
	_splash_fx.process_material = _splash_pm
	_splash_fx.draw_pass_1 = _droplet_quad(Vector2(0.04, 0.055))
	add_child(_splash_fx)
	_build_rings()


func _build_rings() -> void:
	## Expanding foam rings for anything that hits the water. Pooled, because a
	## squall drops a lot of rocks and spawning a node per impact stutters.
	var ring_shader: Shader = load("res://shaders/splash_foam.gdshader")
	var disk_script: GDScript = load("res://scripts/splash_disk.gd")
	for i in 6:
		var mi: MeshInstance3D = disk_script.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(1.0, 1.0)
		mi.mesh = pm
		var mat := ShaderMaterial.new()
		mat.shader = ring_shader
		# Thin and faint. At full strength the ring reads as a drawn white torus
		# lying on the sea rather than as disturbed water.
		mat.set_shader_parameter("foam_color", Color(0.70, 0.78, 0.80, 0.30))
		mi.material_override = mat
		mi.set("ocean", self)
		mi.set("pooled", true)
		add_child(mi)
		_rings.append(mi)


# --- spray -------------------------------------------------------------------
# Two systems, because a gale has two kinds of airborne water: spindrift torn
# continuously off the whole surface, and the burst thrown up by one crest
# actually breaking.

func _build_spray() -> void:
	_spindrift = GPUParticles3D.new()
	_spindrift.amount = 130
	_spindrift.lifetime = 1.5
	_spindrift.fixed_fps = 30
	_spindrift.local_coords = false
	_spindrift.emitting = false
	_spindrift.transform_align = GPUParticles3D.TRANSFORM_ALIGN_DISABLED
	_spindrift.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_spindrift.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spindrift.visibility_aabb = AABB(Vector3(-45, -6, -45), Vector3(90, 24, 90))
	_spindrift_pm = ParticleProcessMaterial.new()
	_spindrift_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_spindrift_pm.emission_box_extents = Vector3(34.0, 0.6, 34.0)
	_spindrift_pm.direction = Vector3(0, 1, 0)
	_spindrift_pm.spread = 40.0
	_spindrift_pm.initial_velocity_min = 0.6
	_spindrift_pm.initial_velocity_max = 2.4
	_spindrift_pm.gravity = Vector3(0, -4.5, 0)
	_spindrift_pm.damping_min = 0.4
	_spindrift_pm.damping_max = 1.2
	_spindrift_pm.scale_min = 0.6
	_spindrift_pm.scale_max = 2.4
	_spindrift_pm.color_ramp = _ramp(
		PackedColorArray([
			Color(0.78, 0.85, 0.88, 0.0),
			Color(0.74, 0.82, 0.85, 0.26),
			Color(0.60, 0.68, 0.70, 0.0)]),
		PackedFloat32Array([0.0, 0.22, 1.0]))
	_spindrift.process_material = _spindrift_pm
	_spindrift.draw_pass_1 = _droplet_quad(Vector2(0.09, 0.075))
	add_child(_spindrift)

	for i in 4:
		var b := GPUParticles3D.new()
		b.amount = 40
		b.lifetime = 1.25
		b.one_shot = true
		b.explosiveness = 0.85
		b.fixed_fps = 30
		b.local_coords = false
		b.emitting = false
		b.transform_align = GPUParticles3D.TRANSFORM_ALIGN_DISABLED
		b.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		b.visibility_aabb = AABB(Vector3(-10, -4, -10), Vector3(20, 14, 20))
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(1.6, 0.1, 0.5)
		pm.direction = Vector3(0, 1, 0)
		pm.spread = 45.0
		pm.initial_velocity_min = 2.0
		pm.initial_velocity_max = 5.0
		pm.gravity = Vector3(0, -11.0, 0)
		pm.damping_min = 0.5
		pm.damping_max = 1.6
		pm.scale_min = 0.7
		pm.scale_max = 2.0
		pm.color_ramp = _ramp(
			PackedColorArray([
				Color(0.86, 0.92, 0.94, 0.5),
				Color(0.72, 0.80, 0.82, 0.22),
				Color(0.55, 0.62, 0.64, 0.0)]),
			PackedFloat32Array([0.0, 0.35, 1.0]))
		b.process_material = pm
		b.draw_pass_1 = _droplet_quad(Vector2(0.07, 0.06))
		add_child(b)
		_breakers.append(b)
	_update_spray_rate()


func _update_spray_rate() -> void:
	if _spindrift_pm == null:
		return
	# Spindrift starts around force 6 and takes over the picture by force 9.
	var f := clampf((wind_speed - 11.0) / 22.0, 0.0, 1.0)
	_spindrift.amount_ratio = maxf(f, 0.02)
	_spindrift.emitting = f > 0.02 and not camera_under
	var a := deg_to_rad(wind_direction_deg)
	_spindrift_pm.gravity = Vector3(cos(a), 0.0, sin(a)) * wind_speed * 0.55 + Vector3(0, -4.5, 0)
	_spindrift_pm.initial_velocity_max = 1.4 + wind_speed * 0.10


func _update_spray(delta: float) -> void:
	if _spindrift == null or follow_target == null:
		return
	var cam := get_viewport().get_camera_3d()
	var centre: Vector3 = cam.global_position if cam != null else follow_target.global_position
	_spindrift.global_position = Vector3(centre.x, 0.35, centre.z)
	_spindrift.emitting = wind_speed > 11.5 and not camera_under

	# Breaking crests: sample the same Jacobian the shader uses and fire a
	# burst where the surface is actually folding over.
	_breaker_cd -= delta
	if _breaker_cd > 0.0 or camera_under or wind_speed < 9.0:
		return
	_breaker_cd = lerpf(0.55, 0.13, clampf((wind_speed - 9.0) / 22.0, 0.0, 1.0))
	var best := 1.0
	var best_p := Vector2.ZERO
	var origin := Vector2(centre.x, centre.z)
	for i in 14:
		var ang := _scan_rng.randf() * TAU
		var r := 5.0 + _scan_rng.randf() * 38.0
		var q := origin + Vector2(cos(ang), sin(ang)) * r
		var j := jacobian(q)
		if j < best:
			best = j
			best_p = q
	if best > 0.16:
		return
	var b := _breakers[_breaker_next]
	_breaker_next = (_breaker_next + 1) % _breakers.size()
	if b.emitting:
		return
	var wpos := surface_point(best_p)
	var pm: ParticleProcessMaterial = b.process_material
	var a := deg_to_rad(wind_direction_deg)
	pm.gravity = Vector3(cos(a), 0.0, sin(a)) * wind_speed * 0.35 + Vector3(0, -11.0, 0)
	b.amount_ratio = clampf(0.35 + (0.16 - best) * 1.6, 0.3, 1.0)
	b.global_position = wpos + Vector3(0.0, 0.1, 0.0)
	b.restart()
	b.emitting = true


func get_height(world_pos: Vector3) -> float:
	# Invert the horizontal Gerstner displacement iteratively, then sample height.
	var xz := Vector2(world_pos.x, world_pos.z)
	var pt := xz
	for i in 2:
		var d := _displace(pt)
		pt = xz - Vector2(d.x, d.z)
	return _displace(pt).y * shoal_factor(world_pos)


func get_normal(world_pos: Vector3, _eps := 0.85) -> Vector3:
	return normal_at_rest(rest_xz(Vector2(world_pos.x, world_pos.z)))


func rest_xz(world_xz: Vector2) -> Vector2:
	## Invert Gerstner horizontal displacement so foam can follow a water particle.
	var pt := world_xz
	for i in 2:
		var d := _displace(pt)
		pt = world_xz - Vector2(d.x, d.z)
	return pt


func surface_point(xz: Vector2) -> Vector3:
	## Follows the Gerstner water particle at rest-xz, so foam rides the chop
	## instead of sliding backward over it.
	var disp := _displace(xz)
	return Vector3(xz.x + disp.x, disp.y, xz.y + disp.z)


func surface_velocity(world_pos: Vector3) -> Vector3:
	## Orbital velocity of the Gerstner surface at this xz (m/s).
	var vx := 0.0
	var vy := 0.0
	var vz := 0.0
	var t := wave_time
	var px := world_pos.x
	var pz := world_pos.z
	for i in _cpu_n:
		var w: float = _om[i]
		var f: float = _kx[i] * px + _kz[i] * pz - w * t
		var s := sin(f)
		vx += _sax[i] * w * s
		vy -= _amps[i] * w * cos(f)
		vz += _saz[i] * w * s
	return Vector3(vx, vy, vz)


func jacobian(rest_p: Vector2) -> float:
	## Determinant of the horizontal displacement map. Mirrors wave_jacobian()
	## in wave_common.gdshaderinc: below ~0 the surface folds and breaks.
	var jxx := 0.0
	var jzz := 0.0
	var jxz := 0.0
	var t := wave_time
	var px := rest_p.x
	var pz := rest_p.y
	var st := steepness
	for i in _cpu_n:
		var d: Vector2 = _dirs[i]
		var q: float = st * _ka[i] * sin(_kx[i] * px + _kz[i] * pz - _om[i] * t)
		jxx -= q * d.x * d.x
		jzz -= q * d.y * d.y
		jxz -= q * d.x * d.y
	return (1.0 + jxx) * (1.0 + jzz) - jxz * jxz


func _displace(p: Vector2) -> Vector3:
	var rx := 0.0
	var ry := 0.0
	var rz := 0.0
	var t := wave_time
	var px := p.x
	var pz := p.y
	for i in _cpu_n:
		var f: float = _kx[i] * px + _kz[i] * pz - _om[i] * t
		var c := cos(f)
		rx += _sax[i] * c
		ry += _amps[i] * sin(f)
		rz += _saz[i] * c
	return Vector3(rx, ry, rz)


func normal_at_rest(p: Vector2) -> Vector3:
	## Surface normal straight from the wave sum — the same expression the vertex
	## shader uses. The old path finite-differenced three get_height() calls,
	## which is twelve wave loops for one normal; this is one.
	var sx := 0.0
	var sz := 0.0
	var ny := 0.0
	var t := wave_time
	var px := p.x
	var pz := p.y
	var st := steepness
	for i in _cpu_n:
		var f: float = _kx[i] * px + _kz[i] * pz - _om[i] * t
		var c := cos(f)
		sx += _kadx[i] * c
		sz += _kadz[i] * c
		ny += st * _ka[i] * sin(f)
	var n := Vector3(-sx, maxf(1.0 - ny, 0.08), -sz)
	if not n.is_finite() or n.length_squared() < 0.0001:
		return Vector3.UP
	return n.normalized()
