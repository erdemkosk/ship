extends Node3D
## Environment controller: sun/time of day, procedural weather-driven sky
## (clouds, stars, lightning glow), fog, rain. Parameters driven from the UI.
##
## Every sky uniform is pushed twice — once to the sky material, once to the
## ocean (set_sky_param) — because the sea reflects this sky analytically
## instead of guessing at a tint. If you add a sky uniform, push it through
## _set_sky() or the reflection will drift out of sync with the dome.

var time_of_day := 20.2:
	set(v):
		time_of_day = v
		_apply_atmosphere()
var fog_amount := 0.45:
	set(v):
		fog_amount = v
		_apply_atmosphere()
var cloud_cover := 0.9:
	set(v):
		cloud_cover = v
		_apply_atmosphere()
var storm := true:
	set(v):
		storm = v
		_apply_atmosphere()
		if storm and _lightning_timer != null and _lightning_timer.is_stopped():
			_schedule_lightning()
		elif not storm:
			_end_strike()
			_thunder_token += 1
var rain_amount := 0.6:
	set(v):
		rain_amount = v
		_apply_rain()
		_apply_atmosphere()

var wind_speed := 14.0
var wind_direction_deg := 40.0

var ocean: Node3D:
	set(v):
		ocean = v
		# Wired up from main.gd after every _ready() has run, so the sky
		# parameters have to be replayed into the water here.
		_apply_atmosphere()

var _env: Environment
var _sky_mat: ShaderMaterial
var _sun: DirectionalLight3D
var _flash: DirectionalLight3D
var _strike_omni: OmniLight3D
var _bolt_mi: MeshInstance3D
var _hit_disc: MeshInstance3D
var _bolt_mat: ShaderMaterial
var _hit_mat: ShaderMaterial
var _bolt_pts: PackedVector3Array = PackedVector3Array()
var _forks: Array[PackedVector3Array] = []
var _strike_pos := Vector3.ZERO
var _cloud_pos := Vector3.ZERO
var _strike_t := -1.0
var _sheet := false
var _flash_k := 1.0
var _omni_k := 1.0
var _splash_k := 1.0
var _bolt_width := 1.05
var _fork_width := 0.42
var _restrike_a := -1.0
var _restrike_b := -1.0
var _splashed := false
var _thunder_token := 0
var _cloud_glow: MeshInstance3D
var _cloud_mat: ShaderMaterial
var _cloud_omni: OmniLight3D
var _thunder_pl: Array[AudioStreamPlayer3D] = []
var _thunder_wavs: Array[AudioStreamWAV] = []
var _rain: GPUParticles3D
var _lightning_timer: Timer
var _cloud_offset := Vector2.ZERO
var _cloud_time := 0.0
var _underwater := false
var _wind_pl: AudioStreamPlayer
var _storm_pl: AudioStreamPlayer
var _wind_lin := 0.0
var _storm_lin := 0.0
var _open_lin := 1.0
var _lp: AudioEffectLowPassFilter
var boat: Node3D


func _ready() -> void:
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = load("res://shaders/sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	# REALTIME re-renders the sky into a 256x256x6 radiance cubemap — and all its
	# mips — every single frame, running the full cloud shader for another
	# ~400k pixels. Nothing here consumes that at full rate: ambient comes from
	# a colour, there are no reflection probes, SSR is off, and the only thing
	# left reading it is the specular on some very rough wood and metal.
	# INCREMENTAL spreads the update over several frames instead.
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	sky.radiance_size = Sky.RADIANCE_SIZE_128

	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	# Filmic, not AgX. AgX has the better highlight roll-off, but this scene is
	# lit at 0.01-0.05 linear almost everywhere, and AgX's toe takes that to
	# black — the sea disappeared at night. Filmic lifts the low end, which is
	# what makes a deliberately dark sea readable. The glitter is kept in range
	# by the slope-derived roughness instead of by the tone curve.
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.tonemap_exposure = 1.05
	_env.tonemap_white = 4.0

	# Specular glints on water are physically tiny and physically very bright.
	# Without bloom they render as single grey pixels and read as noise.
	_env.glow_enabled = true
	_env.glow_normalized = true
	_env.glow_intensity = 0.55
	_env.glow_strength = 1.0
	_env.glow_bloom = 0.05
	_env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	_env.glow_hdr_threshold = 0.92
	_env.glow_hdr_scale = 2.0
	_env.glow_hdr_luminance_cap = 12.0
	_env.set("glow_levels/2", 0.4)
	_env.set("glow_levels/3", 0.9)
	_env.set("glow_levels/4", 0.6)
	_env.set("glow_levels/5", 0.25)

	_env.fog_enabled = true
	_env.fog_mode = Environment.FOG_MODE_DEPTH
	# The horizon has to dissolve on BOTH sides of the line, or the sea/sky seam
	# reappears as a hard edge no matter how good the water is.
	_env.fog_sky_affect = 0.7
	_env.fog_aerial_perspective = 0.6

	# Marine haze is a volume, not a post-process tint: this is what carries
	# light shafts out of the cloud breaks and around the lightning.
	# Keep the froxel volume short: the grid is fixed-resolution, so a long
	# volume makes distant cells huge and a small occluder (the boat, a burst of
	# spray) prints a hard-edged wedge of shadow across the sea.
	_env.volumetric_fog_enabled = true
	_env.volumetric_fog_length = 110.0
	_env.volumetric_fog_detail_spread = 2.0
	_env.volumetric_fog_anisotropy = 0.3
	_env.volumetric_fog_gi_inject = 0.5
	_env.volumetric_fog_ambient_inject = 1.0
	_env.volumetric_fog_sky_affect = 0.3

	# SSR is deliberately off: it only ever applies to opaque geometry, and the
	# only glossy surface in the scene is the (transparent) sea, which now gets
	# its reflection analytically from the sky shader.
	_env.ssr_enabled = false

	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)

	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 90.0
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	_sun.shadow_blur = 1.5
	# The sun is half a degree wide. That finite size is what stretches a point
	# glint into the shimmering column across the water.
	_sun.light_angular_distance = 0.53
	_sun.light_volumetric_fog_energy = 0.6
	add_child(_sun)

	_flash = DirectionalLight3D.new()
	_flash.light_color = Color(0.82, 0.88, 1.0)
	_flash.light_energy = 0.0
	_flash.shadow_enabled = false
	_flash.light_angular_distance = 2.0
	_flash.light_volumetric_fog_energy = 5.0
	add_child(_flash)
	_strike_omni = OmniLight3D.new()
	_strike_omni.light_color = Color(0.78, 0.86, 1.0)
	_strike_omni.light_energy = 0.0
	_strike_omni.omni_range = 95.0
	_strike_omni.omni_attenuation = 1.35
	_strike_omni.light_volumetric_fog_energy = 8.0
	_strike_omni.shadow_enabled = false
	add_child(_strike_omni)
	_bolt_mat = ShaderMaterial.new()
	_bolt_mat.shader = load("res://shaders/lightning.gdshader")
	_bolt_mi = MeshInstance3D.new()
	_bolt_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bolt_mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_bolt_mi.extra_cull_margin = 400.0
	_bolt_mi.material_override = _bolt_mat
	_bolt_mi.visible = false
	add_child(_bolt_mi)
	_hit_mat = ShaderMaterial.new()
	_hit_mat.shader = load("res://shaders/lightning_hit.gdshader")
	var disc := QuadMesh.new()
	disc.size = Vector2(9.0, 9.0)
	_hit_disc = MeshInstance3D.new()
	_hit_disc.mesh = disc
	_hit_disc.material_override = _hit_mat
	_hit_disc.extra_cull_margin = 40.0
	_hit_disc.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_hit_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hit_disc.visible = false
	add_child(_hit_disc)
	_cloud_mat = ShaderMaterial.new()
	_cloud_mat.shader = load("res://shaders/lightning_cloud.gdshader")
	var cg := QuadMesh.new()
	cg.size = Vector2(58.0, 40.0)
	_cloud_glow = MeshInstance3D.new()
	_cloud_glow.mesh = cg
	_cloud_glow.material_override = _cloud_mat
	_cloud_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cloud_glow.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_cloud_glow.extra_cull_margin = 200.0
	_cloud_glow.visible = false
	add_child(_cloud_glow)
	_cloud_omni = OmniLight3D.new()
	_cloud_omni.light_color = Color(0.76, 0.84, 1.0)
	_cloud_omni.light_energy = 0.0
	_cloud_omni.omni_range = 160.0
	_cloud_omni.omni_attenuation = 1.1
	_cloud_omni.light_volumetric_fog_energy = 14.0
	_cloud_omni.shadow_enabled = false
	add_child(_cloud_omni)

	_lightning_timer = Timer.new()
	_lightning_timer.one_shot = true
	_lightning_timer.timeout.connect(_do_flash)
	add_child(_lightning_timer)

	_build_rain()
	_build_weather_audio()
	_build_thunder()
	_apply_atmosphere()
	_apply_rain()
	if storm:
		_lightning_timer.start(randf_range(1.1, 2.2))


func set_wind(speed: float, direction_deg: float) -> void:
	wind_speed = speed
	wind_direction_deg = direction_deg
	_apply_rain()


func sun_direction() -> Vector3:
	## Unit vector from the world toward the sun (or moon).
	return _sun.basis.z.normalized() if _sun != null else Vector3.UP


func _push_sun_to_seabed() -> void:
	if ocean != null and ocean.has_method("set_seabed_sun"):
		ocean.set_seabed_sun(sun_direction())


func set_underwater(on: bool) -> void:
	if _underwater == on:
		return
	_underwater = on
	_apply_atmosphere()


func _set_sky(pname: String, value: Variant) -> void:
	if _sky_mat != null:
		_sky_mat.set_shader_parameter(pname, value)
	if ocean != null and ocean.has_method("set_sky_param"):
		ocean.set_sky_param(pname, value)


func _set_water(pname: String, value: Variant) -> void:
	if ocean != null and ocean.has_method("set_sky_param"):
		ocean.set_sky_param(pname, value)


func _apply_atmosphere() -> void:
	if _env == null:
		return

	# Sun elevation: 6h = sunrise, 18h = sunset.
	var ang := (time_of_day - 6.0) / 12.0 * PI
	var elev := sin(ang) * 65.0  # degrees above horizon
	var is_night := elev < -4.0
	var storm_mul := 0.35 if storm else 1.0

	# High sun + empty sky. Clouds already draw on the dome; this is the light
	# they were not blocking — noon with the slider at 0 should actually glare.
	var noon_k := clampf(elev / 58.0, 0.0, 1.0)
	noon_k = noon_k * noon_k * (3.0 - 2.0 * noon_k)
	var open := clampf(1.0 - cloud_cover, 0.0, 1.0) * (0.12 if storm else 1.0)
	open *= 1.0 - rain_amount * 0.40
	var bright := noon_k * open

	if is_night:
		# dim bluish moon
		_sun.rotation_degrees = Vector3(-38.0, 160.0, 0.0)
		_sun.light_energy = 0.62 * (0.65 if storm else 1.0)
		_sun.light_color = Color(0.55, 0.65, 0.9)
	else:
		var azimuth := lerpf(-110.0, 110.0, clampf((time_of_day - 6.0) / 12.0, 0.0, 1.0))
		_sun.rotation_degrees = Vector3(-maxf(elev, 2.0), azimuth, 0.0)
		var warm := clampf(elev / 35.0, 0.0, 1.0)
		_sun.light_color = Color(1.0, 0.42, 0.22).lerp(Color(1.0, 0.95, 0.88), warm)
		var sun_e := clampf(elev / 30.0, 0.05, 1.0) * 1.25 * storm_mul
		sun_e *= lerpf(0.78, 1.0, open)
		sun_e *= 1.0 + 0.85 * bright
		_sun.light_energy = sun_e

	var dl := clampf((elev + 10.0) / 40.0, 0.0, 1.0) * storm_mul
	var sunset_f := 0.0
	if not is_night:
		sunset_f = clampf(1.0 - elev / 20.0, 0.0, 1.0) * clampf(dl * 3.0, 0.0, 1.0)

	# --- sky shader parameters ---
	var top_day := Color(0.16, 0.24, 0.36).lerp(Color(0.30, 0.50, 0.80), bright)
	var hor_day := Color(0.48, 0.44, 0.40).lerp(Color(0.62, 0.74, 0.84), bright)
	var top := Color(0.022, 0.030, 0.052).lerp(top_day, dl)
	var hor := Color(0.052, 0.062, 0.086).lerp(hor_day, dl)
	hor = hor.lerp(Color(0.55, 0.26, 0.12), sunset_f * (0.35 if storm else 0.8))

	var cloud_lit := Color(0.05, 0.06, 0.085).lerp(Color(0.68, 0.65, 0.62), dl)
	cloud_lit = cloud_lit.lerp(Color(0.65, 0.32, 0.16), sunset_f * (0.25 if storm else 0.6))
	var cloud_dark := cloud_lit * (0.20 if storm else 0.38)
	if storm:
		cloud_dark = Color(cloud_dark.r * 0.88, cloud_dark.g, cloud_dark.b * 0.94)

	var stars := clampf((-elev - 2.0) / 8.0, 0.0, 1.0) * (0.12 if storm else 1.0)

	_set_sky("top_color", top)
	_set_sky("horizon_color", hor)
	_set_sky("ground_color", Color(0.008, 0.010, 0.014))
	_set_sky("sun_dir", _sun.basis.z.normalized())
	_push_sun_to_seabed()
	_set_sky("sun_color", _sun.light_color)
	_set_sky("sun_energy", 0.5 if is_night else clampf(dl * 1.8, 0.2, 1.5) * (1.0 + 0.9 * bright))
	_set_sky("sun_size", 0.0008 if is_night else 0.0015)
	_set_sky("cloud_coverage", cloud_cover)
	_set_sky("cloud_density", 1.35 if storm else 1.0)
	_set_sky("cloud_lit_color", cloud_lit)
	_set_sky("cloud_dark_color", cloud_dark)
	_set_sky("star_intensity", stars)

	# --- water body optics ---
	# What comes back out of the water is sunlight that got scattered inside it,
	# so it has to track the daylight or the sea glows at midnight.
	# Albedo of the water body itself — the engine lights it, so it must NOT be
	# pre-multiplied by the daylight or the sea goes black at night.
	# Open-ocean water reflectance is only a few percent, but at a few percent a
	# night sea is literally black on screen. This is the one place the model is
	# deliberately pushed past physical: the body albedo is lifted so the shape
	# of the water stays readable in the dark, which is the whole point of the
	# scene. Everything else (Fresnel, extinction, glitter) stays honest.
	# Physical open-ocean body reflectance is a few percent, which under full sun
	# is right — and at night puts the sea at literally zero on screen. So the
	# body albedo is scaled inversely with the light: honest by day, deliberately
	# lifted at night so the shape of the water stays readable. It is the one
	# knob here that is art rather than optics; Fresnel, extinction, the glitter
	# and the reflection all stay physical.
	var scatter := Color(0.045, 0.20, 0.225).lerp(Color(0.012, 0.062, 0.070), dl)
	if storm:
		scatter = scatter.lerp(Color(0.115, 0.165, 0.175).lerp(Color(0.035, 0.052, 0.055), dl), 0.5)
	_set_water("scatter_color", scatter)
	_set_water("scatter_strength", 1.0)
	# Turbidity: coastal water in a blow carries sediment and bubbles, so even
	# blue stops making it more than a few metres.
	var murk := clampf(0.55 + rain_amount * 0.5 + (0.35 if storm else 0.0), 0.4, 1.6)
	_set_water("extinction", Color(0.95, 0.38, 0.24) * murk)
	_set_water("sss_strength", lerpf(0.15, 1.25, dl) * (0.5 if storm else 1.0) * (1.0 + 0.4 * bright))
	# Rain and storm churn the top metre into bubbles: more scatter, less clarity.
	_set_water("refraction_strength", lerpf(0.65, 0.28, rain_amount))
	_set_water("rain_amount", rain_amount)
	_set_water("foam_color", Color(0.62, 0.70, 0.71).lerp(Color(0.10, 0.13, 0.15), 1.0 - dl) \
			.lerp(Color(0.62, 0.70, 0.71), 0.55))

	# --- ambient & fog ---
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# Ambient stands in for the whole sky hemisphere. Its BRIGHTNESS is authored
	# (at night a physically-derived value is so low the sea reads as black),
	# but its COLOUR is taken from the sky that is actually up there. Without
	# that, a burning sunset sky sat over a neutral grey sea: the water's rough
	# reflection averages toward this ambient, and a neutral ambient scrubs the
	# sunset straight back out of it.
	var base_amb := Color(0.13, 0.17, 0.22).lerp(
			Color(0.5, 0.55, 0.58).lerp(Color(0.78, 0.84, 0.90), bright), dl)
	var sky_avg := top.lerp(hor, 0.55)
	sky_avg = sky_avg.lerp(cloud_lit.lerp(cloud_dark, 0.4), clampf(cloud_cover * 0.85, 0.0, 1.0))
	var lum_b := base_amb.r * 0.3 + base_amb.g * 0.6 + base_amb.b * 0.1
	var lum_s := maxf(sky_avg.r * 0.3 + sky_avg.g * 0.6 + sky_avg.b * 0.1, 1e-4)
	var tinted := Color(sky_avg.r, sky_avg.g, sky_avg.b) * (lum_b / lum_s)
	_env.ambient_light_color = base_amb.lerp(tinted, 0.8)
	_env.ambient_light_energy = lerpf(0.95, 1.0, dl) * (1.0 + 0.55 * bright)
	_env.tonemap_exposure = lerpf(1.05, 1.20, bright)
	_set_water("sky_ambient", _env.ambient_light_color * _env.ambient_light_energy)
	if ocean != null and ocean.has_method("set_reflection_ambient"):
		ocean.set_reflection_ambient(_env.ambient_light_color, _env.ambient_light_energy)
	_env.fog_mode = Environment.FOG_MODE_DEPTH
	_env.fog_density = fog_amount * 0.014 * lerpf(1.0, 0.55, bright)
	var fog_day := Color(0.35, 0.36, 0.35).lerp(Color(0.58, 0.62, 0.66), bright)
	var fog_night := Color(0.055, 0.08, 0.09)
	_env.fog_light_color = fog_night.lerp(fog_day, dl)
	_env.fog_height = 0.0
	_env.fog_height_density = 0.0
	_env.fog_sky_affect = 0.7
	_env.fog_aerial_perspective = 0.6
	_env.volumetric_fog_enabled = true
	_env.volumetric_fog_length = 110.0
	_env.volumetric_fog_density = clampf(
			(0.004 + fog_amount * 0.016 + rain_amount * 0.006) * lerpf(1.0, 0.62, bright),
			0.0, 0.05)
	_env.volumetric_fog_albedo = _env.fog_light_color
	_env.volumetric_fog_emission = Color(0.0, 0.0, 0.0)
	_env.volumetric_fog_anisotropy = 0.3
	_env.volumetric_fog_ambient_inject = 1.0
	_env.volumetric_fog_sky_affect = 0.3
	_sun.light_volumetric_fog_energy = 0.6
	if _underwater:
		# Water stays water. The basin going black is the SEABED shader, not
		# this fog — a black fog colour paints the whole sea, from the boat too.
		_env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
		_env.fog_density = 0.009
		_env.fog_light_color = Color(0.02, 0.09, 0.11)
		_env.fog_height = -10.0
		_env.fog_height_density = 0.020
		_env.fog_sky_affect = 0.0
		_env.fog_aerial_perspective = 0.0
		_env.volumetric_fog_length = 36.0
		_env.volumetric_fog_density = 0.010
		_env.volumetric_fog_albedo = Color(0.12, 0.32, 0.34)
		_env.volumetric_fog_emission = Color(0.04, 0.11, 0.12)
		_env.volumetric_fog_anisotropy = 0.55
		_env.volumetric_fog_ambient_inject = 0.45
		_env.volumetric_fog_sky_affect = 0.0
		_env.ambient_light_color = Color(0.05, 0.18, 0.20)
		_env.ambient_light_energy = 1.05
		_sun.light_energy *= 0.70
		_sun.light_volumetric_fog_energy = 2.8


func _build_rain() -> void:
	_rain = GPUParticles3D.new()
	# 420 drops spread over 56 x 56 m is drizzle you have to look for. Rain you
	# can hear needs an order more, packed into a much smaller box around the
	# camera — density where you are standing is the whole effect, and drops
	# 30 m away were never doing any work.
	_rain.amount = 3600
	# Long enough to FALL PAST YOU. At 0.36 s a drop covered seven metres, so
	# emitting eleven metres overhead it died four metres above the camera and
	# the rain was a band in the sky you never stood in.
	_rain.lifetime = 0.85
	_rain.fixed_fps = 60
	_rain.transform_align = GPUParticles3D.TRANSFORM_ALIGN_DISABLED
	_rain.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# A drop with no size cannot hit anything; the default is a hundredth of a
	# metre. Give it a real radius or the shields never fire.
	_rain.collision_base_size = 0.35
	_rain.visibility_aabb = AABB(Vector3(-40, -20, -40), Vector3(80, 40, 80))

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(12.0, 1.0, 12.0)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 2.0
	pm.initial_velocity_min = 16.0
	pm.initial_velocity_max = 22.0
	pm.gravity = Vector3(0, -18.0, 0)
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.72, 1.0])
	fade.colors = PackedColorArray([
		Color(1, 1, 1, 1),
		Color(1, 1, 1, 0.7),
		Color(1, 1, 1, 0.0)])
	var fade_tex := GradientTexture1D.new()
	fade_tex.gradient = fade
	pm.color_ramp = fade_tex
	# Drops die where they land instead of falling on through the boat: the
	# roofs and decks carry GPUParticlesCollisionBox3D volumes (see
	# boat.gd/_build_rain_shields), so no rain falls inside the cabin or the
	# wheelhouse — and none falls THROUGH the deck either.
	pm.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	_rain.process_material = pm

	var quad := QuadMesh.new()
	quad.size = Vector2(0.011, 0.36)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.60, 0.67, 0.74, 0.20)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	mat.distance_fade_min_distance = 22.0
	mat.distance_fade_max_distance = 2.2
	quad.material = mat
	_rain.draw_pass_1 = quad
	add_child(_rain)


func _apply_rain() -> void:
	if _rain == null:
		return
	_rain.emitting = rain_amount > 0.01
	# Bend the slider: rain does not feel twice as heavy at 100% as at 50%, it
	# feels a little heavier. Front-load it so a middling setting already looks
	# like weather you would not go out in.
	_rain.amount_ratio = clampf(pow(rain_amount, 0.55), 0.0, 1.0)
	var pm: ParticleProcessMaterial = _rain.process_material
	var a := deg_to_rad(wind_direction_deg)
	pm.gravity = Vector3(cos(a), 0.0, sin(a)) * wind_speed * 0.55 + Vector3(0, -18.0, 0)


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam != null and _rain != null:
		_rain.global_position = cam.global_position + Vector3(0.0, 7.0, 0.0)

	# clouds drift with the wind; lightning lights the deck from within
	var wa := deg_to_rad(wind_direction_deg)
	_cloud_offset += Vector2(cos(wa), sin(wa)) * (2.0 + wind_speed) * delta * 0.0016
	_cloud_time += delta
	_set_sky("cloud_offset", _cloud_offset)
	_set_sky("cloud_time", _cloud_time)
	_set_sky("flash_energy", _flash.light_energy)
	if _env != null:
		var fe := clampf(_flash.light_energy / 10.0, 0.0, 1.6)
		_env.volumetric_fog_emission = Color(0.42, 0.50, 0.72) * fe
	_update_strike(delta)
	_update_weather_audio(delta)


func _schedule_lightning() -> void:
	if _lightning_timer != null:
		_lightning_timer.start(randf_range(2.4, 6.4))


func _do_flash() -> void:
	if not storm:
		return
	_start_strike()


func _start_strike() -> void:
	var cam := get_viewport().get_camera_3d()
	var origin := Vector3.ZERO
	if boat != null:
		origin = boat.global_position
	elif cam != null:
		origin = cam.global_position
	var fwd := Vector3(0.0, 0.0, -1.0)
	if cam != null:
		fwd = -cam.global_basis.z
		fwd.y = 0.0
		if fwd.length_squared() < 0.02:
			fwd = -cam.global_basis.x
			fwd.y = 0.0
		if fwd.length_squared() > 0.02:
			fwd = fwd.normalized()

	var roll := randf()
	_sheet = roll < 0.24
	var near := not _sheet and roll < 0.68
	var dist: float
	var yaw: float
	if _sheet:
		dist = randf_range(140.0, 320.0)
		yaw = randf() * TAU
		_flash_k = randf_range(0.85, 1.25)
		_omni_k = 0.0
		_splash_k = 0.0
		_bolt_width = 0.0
	elif near:
		dist = randf_range(36.0, 72.0)
		yaw = randf_range(-0.70, 0.70)
		_flash_k = 1.0
		_omni_k = 1.0
		_splash_k = 1.35
		_bolt_width = 1.05
		_fork_width = 0.42
	else:
		dist = randf_range(95.0, 165.0)
		yaw = randf_range(-1.15, 1.15)
		_flash_k = 0.55
		_omni_k = 0.38
		_splash_k = 0.7
		_bolt_width = 0.58
		_fork_width = 0.24

	var hit: Vector3 = origin + fwd.rotated(Vector3.UP, yaw) * dist
	if ocean != null and ocean.has_method("get_height"):
		hit.y = ocean.get_height(hit)
	else:
		hit.y = 0.0
	_strike_pos = hit
	var cloud_h := randf_range(90.0, 150.0) if not _sheet else randf_range(110.0, 170.0)
	_cloud_pos = hit + Vector3(randf_range(-22.0, 22.0), cloud_h, randf_range(-22.0, 22.0))
	_forks.clear()
	_bolt_pts = PackedVector3Array()
	if not _sheet:
		_bolt_pts = _jagged_path(_cloud_pos, hit, 6, 5.5 if near else 4.2)
		var nfork := randi_range(2, 4) if near else randi_range(1, 3)
		for _f in nfork:
			if _bolt_pts.size() < 10:
				break
			var k := randi_range(6, _bolt_pts.size() - 6)
			var root: Vector3 = _bolt_pts[k]
			var down := (hit - _cloud_pos).normalized()
			var side := down.cross(Vector3.UP)
			if side.length_squared() < 0.01:
				side = down.cross(Vector3.RIGHT)
			side = side.normalized()
			var reach := randf_range(12.0, 36.0)
			var tip: Vector3 = root + down * reach * randf_range(0.4, 1.0) \
					+ side * randf_range(-1.0, 1.0) * reach * 0.55 \
					+ Vector3.UP * randf_range(-6.0, 4.0)
			if tip.y < hit.y + 2.0:
				tip.y = hit.y + randf_range(6.0, 22.0)
			_forks.append(_jagged_path(root, tip, 5, 3.0))
		_rebuild_bolt_mesh()
		var tint := Color(0.82, 0.90, 1.0) if near else Color(0.68, 0.72, 1.0)
		_bolt_mat.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))

	_flash.basis = Basis.looking_at((hit - _cloud_pos).normalized(), Vector3.UP)
	var fdir: Vector3 = _cloud_pos - origin
	fdir.y = maxf(fdir.y, absf(fdir.x) + absf(fdir.z)) * 0.35
	if fdir.length_squared() > 0.01:
		_set_sky("flash_dir", fdir.normalized())
	if _strike_omni != null:
		_strike_omni.omni_range = 150.0 if near else 110.0
		_strike_omni.global_position = hit + Vector3(0.0, 6.0, 0.0)
	if _cloud_omni != null:
		_cloud_omni.global_position = _cloud_pos
	if _cloud_glow != null:
		_cloud_glow.global_position = _cloud_pos
	if _hit_disc != null:
		_hit_disc.global_position = hit + Vector3(0.0, 0.35, 0.0)
	_restrike_a = 0.30 if randf() < (0.85 if near or _sheet else 0.45) else -1.0
	_restrike_b = 0.50 if _restrike_a > 0.0 and randf() < 0.55 else -1.0
	_splashed = false
	_strike_t = 0.0
	_queue_thunder(dist, _sheet, hit)


func _jagged_path(a: Vector3, b: Vector3, depth: int, jag: float) -> PackedVector3Array:
	## Midpoint displacement across the channel, not along it. Big sideways
	## jumps turn each segment into a card; keep the wander small against
	## the length so it reads as a filament with kinks.
	var axis: Vector3 = b - a
	var len := maxf(axis.length(), 0.01)
	var down := axis / len
	var right := down.cross(Vector3.UP)
	if right.length_squared() < 0.01:
		right = down.cross(Vector3.RIGHT)
	right = right.normalized()
	var out := down.cross(right).normalized()
	var pts: PackedVector3Array = PackedVector3Array([a, b])
	var amp := minf(jag, len * 0.085)
	for _d in depth:
		var nxt := PackedVector3Array()
		for i in pts.size() - 1:
			var p0: Vector3 = pts[i]
			var p1: Vector3 = pts[i + 1]
			var mid: Vector3 = (p0 + p1) * 0.5
			mid += right * randf_range(-amp, amp) + out * randf_range(-amp * 0.45, amp * 0.45)
			nxt.append(p0)
			nxt.append(mid)
		nxt.append(pts[pts.size() - 1])
		pts = nxt
		amp *= 0.48
	pts[0] = a
	pts[pts.size() - 1] = b
	return pts


func _update_strike(delta: float) -> void:
	if _strike_t < 0.0:
		_set_sky("flash_lobe", 0.0)
		return
	_strike_t += delta
	if _strike_t > 1.22:
		_end_strike()
		if storm:
			_schedule_lightning()
		return
	var look := _eval_strike(_strike_t)
	var fade: float = look.x
	var reveal: float = look.y
	var flash_e: float = look.z
	var lobe: float = look.w
	_flash.light_energy = flash_e
	_set_sky("flash_lobe", lobe)
	if _bolt_mat != null:
		_bolt_mat.set_shader_parameter("fade", fade)
		_bolt_mat.set_shader_parameter("reveal", reveal)
		_bolt_mat.set_shader_parameter("core_gain", 2.4 + 4.2 * fade)
	if _hit_mat != null:
		var hit_p := maxf(_pulse_at(_strike_t, 0.12, 0.10),
				maxf(_pulse_at(_strike_t, _restrike_a, 0.08),
						_pulse_at(_strike_t, _restrike_b, 0.07)))
		_hit_mat.set_shader_parameter("fade", 0.0 if _sheet else maxf(hit_p, fade * 0.18))
	if _cloud_mat != null:
		_cloud_mat.set_shader_parameter("fade", lobe * 1.15)
	if _strike_omni != null:
		_strike_omni.light_energy = 0.0 if _sheet else (6.0 + 92.0 * fade) * _omni_k \
				* _pulse_at(_strike_t, 0.12, 0.10)
		if _restrike_a > 0.0:
			_strike_omni.light_energy = maxf(_strike_omni.light_energy,
					(4.0 + 60.0 * fade) * _omni_k * _pulse_at(_strike_t, _restrike_a, 0.08))
		if _restrike_b > 0.0:
			_strike_omni.light_energy = maxf(_strike_omni.light_energy,
					(3.0 + 48.0 * fade) * _omni_k * _pulse_at(_strike_t, _restrike_b, 0.07))
	if _cloud_omni != null:
		_cloud_omni.light_energy = 18.0 * lobe
	if ocean != null and ocean.has_method("get_height") and not _sheet:
		_strike_pos.y = ocean.get_height(_strike_pos)
		if _hit_disc != null:
			_hit_disc.global_position = _strike_pos + Vector3(0.0, 0.35, 0.0)
		if _strike_omni != null:
			_strike_omni.global_position = _strike_pos + Vector3(0.0, 6.0, 0.0)
	if _strike_t > 0.118 and not _splashed and not _sheet:
		_splashed = true
		if ocean != null and ocean.has_method("splash"):
			ocean.splash(_strike_pos, _splash_k)
	var show := fade > 0.015 and not _underwater
	if _bolt_mi != null:
		_bolt_mi.visible = show and not _sheet and _bolt_pts.size() > 1
	if _hit_disc != null:
		_hit_disc.visible = show and not _sheet
	if _cloud_glow != null:
		_cloud_glow.visible = lobe > 0.03 and not _underwater


func _eval_strike(t: float) -> Vector4:
	## x fade, y reveal, z directional flash, w cloud lobe.
	var reveal := 1.0
	var fade := 0.0
	var flash := 0.0
	var lobe := 0.0
	if t < 0.12:
		reveal = t / 0.12
		fade = 0.06 + 0.10 * reveal
		if _sheet:
			fade = 0.0
			reveal = 1.0
		flash = 0.38 * _flash_k
		lobe = 0.22 * _flash_k * reveal
	else:
		var stroke := _pulse_at(t, 0.12, 0.048)
		var r1 := _pulse_at(t, _restrike_a, 0.036)
		var r2 := _pulse_at(t, _restrike_b, 0.032)
		var peak := maxf(stroke, maxf(r1, r2))
		var after := 0.0
		if t > 0.16:
			after = 0.13 * exp(-(t - 0.16) * 2.6)
		fade = 0.0 if _sheet else maxf(peak, after)
		flash = (0.35 + 15.5 * peak + 1.1 * after) * _flash_k
		lobe = (0.28 + 1.35 * peak + 0.32 * after) * _flash_k
	return Vector4(fade, reveal, flash, lobe)


func _pulse_at(t: float, t0: float, width: float) -> float:
	if t0 < 0.0 or t < t0 or width < 0.001:
		return 0.0
	var u := (t - t0) / width
	if u > 1.0:
		return 0.0
	return exp(-u * 4.6) * (1.0 - u * 0.12)


func _end_strike() -> void:
	_strike_t = -1.0
	if _flash != null:
		_flash.light_energy = 0.0
	if _strike_omni != null:
		_strike_omni.light_energy = 0.0
	if _cloud_omni != null:
		_cloud_omni.light_energy = 0.0
	if _bolt_mi != null:
		_bolt_mi.visible = false
	if _hit_disc != null:
		_hit_disc.visible = false
	if _cloud_glow != null:
		_cloud_glow.visible = false
	_set_sky("flash_energy", 0.0)
	_set_sky("flash_lobe", 0.0)
	if _env != null:
		_env.volumetric_fog_emission = Color(0.0, 0.0, 0.0)


func _rebuild_bolt_mesh() -> void:
	## Crossed world-space ribbons. Built once per strike so the channel
	## does not crawl when the camera turns.
	if _bolt_mi == null:
		return
	var im := ImmediateMesh.new()
	_ribbon_world(im, _bolt_pts, _bolt_width)
	for fork: PackedVector3Array in _forks:
		_ribbon_world(im, fork, _fork_width)
	_bolt_mi.mesh = im


func _ribbon_world(im: ImmediateMesh, pts: PackedVector3Array, width: float) -> void:
	if pts.size() < 2 or width < 0.01:
		return
	var n := pts.size()
	var tan := PackedVector3Array()
	tan.resize(n)
	for i in n:
		if i == 0:
			tan[i] = pts[1] - pts[0]
		elif i == n - 1:
			tan[i] = pts[n - 1] - pts[n - 2]
		else:
			tan[i] = pts[i + 1] - pts[i - 1]
	var lens := PackedFloat32Array()
	lens.resize(n)
	lens[0] = 0.0
	var total := 0.0
	for i in n - 1:
		total += pts[i].distance_to(pts[i + 1])
		lens[i + 1] = total
	var inv := 1.0 / maxf(total, 0.001)
	for plane in range(2):
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in n - 1:
			var s0 := _cross_side(tan[i], plane)
			var s1 := _cross_side(tan[i + 1], plane)
			if s0.length_squared() < 0.5 or s1.length_squared() < 0.5:
				continue
			var t0 := lens[i] * inv
			var t1 := lens[i + 1] * inv
			var w0: float = width * lerpf(1.05, 0.40, t0)
			var w1: float = width * lerpf(1.05, 0.40, t1)
			var a0: Vector3 = pts[i] - s0 * w0
			var a1: Vector3 = pts[i] + s0 * w0
			var b0: Vector3 = pts[i + 1] - s1 * w1
			var b1: Vector3 = pts[i + 1] + s1 * w1
			_tri(im, a0, Vector2(0.0, t0), b0, Vector2(0.0, t1), a1, Vector2(1.0, t0))
			_tri(im, a1, Vector2(1.0, t0), b0, Vector2(0.0, t1), b1, Vector2(1.0, t1))
		im.surface_end()


func _cross_side(along: Vector3, which: int) -> Vector3:
	var s: Vector3 = along.cross(Vector3.UP)
	if s.length_squared() < 1e-6:
		s = along.cross(Vector3.RIGHT)
	if s.length_squared() < 1e-6:
		return Vector3.ZERO
	s = s.normalized()
	if which == 1:
		s = along.cross(s)
		if s.length_squared() < 1e-6:
			return Vector3.ZERO
		s = s.normalized()
	return s


func _tri(im: ImmediateMesh, p0: Vector3, u0: Vector2, p1: Vector3, u1: Vector2,
		p2: Vector3, u2: Vector2) -> void:
	im.surface_set_uv(u0)
	im.surface_add_vertex(p0)
	im.surface_set_uv(u1)
	im.surface_add_vertex(p1)
	im.surface_set_uv(u2)
	im.surface_add_vertex(p2)


func _build_weather_audio() -> void:
	## Real loops from assets/audio/. Volume follows the weather; they never
	## try to match individual waves (that is what sounded fake last time).
	## A Weather bus holds a low-pass so the cabin can muffle them without
	## touching the stove, which lives on Master and in the room.
	_ensure_weather_bus()
	_wind_pl = _loop_player("res://assets/audio/wind.mp3")
	_storm_pl = _loop_player("res://assets/audio/storm.mp3")
	add_child(_wind_pl)
	add_child(_storm_pl)
	_wind_pl.play()


func _build_thunder() -> void:
	for i in 3:
		_thunder_wavs.append(_synth_thunder(1000 + i * 97))
		var p := AudioStreamPlayer3D.new()
		p.bus = "Weather"
		p.unit_size = 16.0
		p.max_distance = 520.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		_thunder_pl.append(p)


func _synth_thunder(seed: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var rate := 22050
	var n := int(rate * 2.35)
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	for i in n:
		var t := float(i) / float(rate)
		var crack := exp(-t * 16.0) * (rng.randf() * 2.0 - 1.0)
		var rumble := sin(t * TAU * (28.0 + rng.randf() * 8.0)) * exp(-t * 1.55)
		rumble += sin(t * TAU * (17.0 + rng.randf() * 5.0)) * exp(-t * 1.15) * 0.7
		var nse := rng.randf() * 2.0 - 1.0
		lp = lerpf(lp, nse, 0.07)
		var s := crack * 0.52 + rumble * 0.48 + lp * 0.22 * exp(-t * 2.0)
		s = clampf(s * 0.72, -1.0, 1.0)
		data.encode_s16(i * 2, int(s * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav


func _queue_thunder(dist: float, sheet: bool, at: Vector3) -> void:
	var delay := clampf(dist / 340.0, 0.07, 1.15)
	var token := _thunder_token
	get_tree().create_timer(delay).timeout.connect(
			func() -> void: _play_thunder(token, dist, sheet, at))


func _play_thunder(token: int, dist: float, sheet: bool, at: Vector3) -> void:
	if token != _thunder_token or not storm or _thunder_pl.is_empty():
		return
	var p: AudioStreamPlayer3D = _thunder_pl[randi() % _thunder_pl.size()]
	if _thunder_wavs.is_empty():
		return
	p.stream = _thunder_wavs[randi() % _thunder_wavs.size()]
	p.global_position = at + Vector3(0.0, 8.0, 0.0)
	var lin := clampf(1.2 * (48.0 / maxf(dist, 22.0)), 0.07, 1.0)
	if sheet:
		lin *= 0.55
	if _underwater:
		lin *= 0.12
	p.volume_db = linear_to_db(maxf(lin, 0.0001))
	p.pitch_scale = randf_range(0.78, 1.06) * (0.72 if sheet else 1.0)
	p.play()


func _ensure_weather_bus() -> void:
	var idx := AudioServer.get_bus_index("Weather")
	if idx < 0:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, "Weather")
		AudioServer.set_bus_send(idx, "Master")
	if AudioServer.get_bus_effect_count(idx) == 0:
		_lp = AudioEffectLowPassFilter.new()
		_lp.cutoff_hz = 12000.0
		_lp.resonance = 0.35
		AudioServer.add_bus_effect(idx, _lp)
	else:
		_lp = AudioServer.get_bus_effect(idx, 0) as AudioEffectLowPassFilter


func _loop_player(path: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	var s: AudioStream = load(path)
	if s is AudioStreamMP3:
		(s as AudioStreamMP3).loop = true
	elif s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	p.stream = s
	p.bus = "Weather"
	p.volume_db = -80.0
	return p


func _weather_openness() -> float:
	if boat == null or not boat.has_method("weather_openness"):
		return 1.0
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return 1.0
	return float(boat.weather_openness(cam.global_position))


func _update_weather_audio(delta: float) -> void:
	if _wind_pl == null:
		return
	# Calm (a few knots) is barely there; a working breeze (~18 kn) is full.
	# Storms with 30+ kn stay at full rather than clipping louder.
	var w_tgt := clampf((wind_speed - 2.0) / 16.0, 0.0, 1.0)
	var s_tgt := 1.0 if storm else 0.0
	# Enclosure. Fast enough that shutting a door is an event, not a fade
	# you notice afterwards.
	var k_open := 1.0 - exp(-7.5 * delta)
	_open_lin = lerpf(_open_lin, _weather_openness(), k_open)
	var hear := lerpf(0.12, 1.0, _open_lin)
	w_tgt *= hear
	s_tgt *= hear
	if _underwater:
		w_tgt *= 0.22
		s_tgt *= 0.18
	if _lp != null:
		# Shut cabin: woolly, no highs. Deck: the recording as-is.
		_lp.cutoff_hz = lerpf(720.0, 11000.0, pow(_open_lin, 0.65))
	var k := 1.0 - exp(-2.4 * delta)
	_wind_lin = lerpf(_wind_lin, w_tgt, k)
	_storm_lin = lerpf(_storm_lin, s_tgt, 1.0 - exp(-1.6 * delta))
	_wind_pl.volume_db = linear_to_db(maxf(_wind_lin, 0.0001))
	_storm_pl.volume_db = linear_to_db(maxf(_storm_lin, 0.0001))
	if s_tgt > 0.02 and not _storm_pl.playing:
		_storm_pl.play()
	elif _storm_lin < 0.012 and _storm_pl.playing and not storm:
		_storm_pl.stop()
		_storm_lin = 0.0
		_storm_pl.volume_db = -80.0
	if not _wind_pl.playing:
		_wind_pl.play()

