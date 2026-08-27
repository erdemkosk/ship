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
var _rain: GPUParticles3D
var _lightning_timer: Timer
var _cloud_offset := Vector2.ZERO
var _cloud_time := 0.0
var _underwater := false


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
	_flash.light_color = Color(0.8, 0.85, 1.0)
	_flash.light_energy = 0.0
	_flash.shadow_enabled = false
	_flash.light_angular_distance = 2.0
	_flash.light_volumetric_fog_energy = 5.0
	add_child(_flash)

	_lightning_timer = Timer.new()
	_lightning_timer.one_shot = true
	_lightning_timer.timeout.connect(_do_flash)
	add_child(_lightning_timer)

	_build_rain()
	_apply_atmosphere()
	_apply_rain()
	if storm:
		_schedule_lightning()


func set_wind(speed: float, direction_deg: float) -> void:
	wind_speed = speed
	wind_direction_deg = direction_deg
	_apply_rain()


func sun_direction() -> Vector3:
	## Unit vector from the world toward the sun (or moon).
	return _sun.basis.z.normalized() if _sun != null else Vector3.UP


func set_underwater(on: bool) -> void:
	if _underwater == on:
		return
	_underwater = on
	_apply_atmosphere()


func _set_sky(pname: String, value: Variant) -> void:
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
		_sun.light_energy = clampf(elev / 30.0, 0.05, 1.0) * 1.25 * storm_mul

	var dl := clampf((elev + 10.0) / 40.0, 0.0, 1.0) * storm_mul
	var sunset_f := 0.0
	if not is_night:
		sunset_f = clampf(1.0 - elev / 20.0, 0.0, 1.0) * clampf(dl * 3.0, 0.0, 1.0)

	# --- sky shader parameters ---
	var top := Color(0.022, 0.030, 0.052).lerp(Color(0.16, 0.24, 0.36), dl)
	var hor := Color(0.052, 0.062, 0.086).lerp(Color(0.48, 0.44, 0.40), dl)
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
	_set_sky("sun_color", _sun.light_color)
	_set_sky("sun_energy", 0.5 if is_night else clampf(dl * 1.8, 0.2, 1.5))
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
	_set_water("sss_strength", lerpf(0.15, 1.25, dl) * (0.5 if storm else 1.0))
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
	var base_amb := Color(0.13, 0.17, 0.22).lerp(Color(0.5, 0.55, 0.58), dl)
	var sky_avg := top.lerp(hor, 0.55)
	sky_avg = sky_avg.lerp(cloud_lit.lerp(cloud_dark, 0.4), clampf(cloud_cover * 0.85, 0.0, 1.0))
	var lum_b := base_amb.r * 0.3 + base_amb.g * 0.6 + base_amb.b * 0.1
	var lum_s := maxf(sky_avg.r * 0.3 + sky_avg.g * 0.6 + sky_avg.b * 0.1, 1e-4)
	var tinted := Color(sky_avg.r, sky_avg.g, sky_avg.b) * (lum_b / lum_s)
	_env.ambient_light_color = base_amb.lerp(tinted, 0.8)
	_env.ambient_light_energy = lerpf(0.95, 1.0, dl)
	_set_water("sky_ambient", _env.ambient_light_color * _env.ambient_light_energy)
	if ocean != null and ocean.has_method("set_reflection_ambient"):
		ocean.set_reflection_ambient(_env.ambient_light_color, _env.ambient_light_energy)
	_env.fog_density = fog_amount * 0.014
	var fog_day := Color(0.35, 0.36, 0.35)
	var fog_night := Color(0.055, 0.08, 0.09)
	_env.fog_light_color = fog_night.lerp(fog_day, dl)
	_env.fog_height = 0.0
	_env.fog_height_density = 0.0
	_env.volumetric_fog_enabled = not _underwater
	_env.volumetric_fog_density = clampf(0.004 + fog_amount * 0.016 + rain_amount * 0.006, 0.0, 0.05)
	_env.volumetric_fog_albedo = _env.fog_light_color
	_env.volumetric_fog_emission = Color(0.0, 0.0, 0.0)
	if _underwater:
		_env.fog_density = 0.062
		_env.fog_light_color = Color(0.02, 0.09, 0.11)
		_env.fog_height = 2.0
		_env.fog_height_density = 0.42
		_env.ambient_light_color = Color(0.03, 0.11, 0.13)
		_env.ambient_light_energy = 0.7
		_sun.light_energy *= 0.32


func _build_rain() -> void:
	_rain = GPUParticles3D.new()
	_rain.amount = 420
	_rain.lifetime = 0.36
	_rain.fixed_fps = 30
	_rain.transform_align = GPUParticles3D.TRANSFORM_ALIGN_DISABLED
	_rain.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rain.visibility_aabb = AABB(Vector3(-40, -20, -40), Vector3(80, 40, 80))

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(28.0, 0.8, 28.0)
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
	_rain.process_material = pm

	var quad := QuadMesh.new()
	quad.size = Vector2(0.006, 0.22)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.55, 0.62, 0.70, 0.07)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	mat.distance_fade_min_distance = 18.0
	mat.distance_fade_max_distance = 5.5
	quad.material = mat
	_rain.draw_pass_1 = quad
	add_child(_rain)


func _apply_rain() -> void:
	if _rain == null:
		return
	_rain.emitting = rain_amount > 0.01
	_rain.amount_ratio = clampf(rain_amount, 0.0, 1.0)
	var pm: ParticleProcessMaterial = _rain.process_material
	var a := deg_to_rad(wind_direction_deg)
	pm.gravity = Vector3(cos(a), 0.0, sin(a)) * wind_speed * 0.55 + Vector3(0, -18.0, 0)


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam != null and _rain != null:
		_rain.global_position = cam.global_position + Vector3(0.0, 11.0, 0.0)

	# clouds drift with the wind; lightning lights the deck from within
	var wa := deg_to_rad(wind_direction_deg)
	_cloud_offset += Vector2(cos(wa), sin(wa)) * (2.0 + wind_speed) * delta * 0.0016
	_cloud_time += delta
	_set_sky("cloud_offset", _cloud_offset)
	_set_sky("cloud_time", _cloud_time)
	_set_sky("flash_energy", _flash.light_energy)


func _schedule_lightning() -> void:
	_lightning_timer.start(randf_range(4.0, 14.0))


func _do_flash() -> void:
	if not storm:
		return
	_flash.rotation_degrees = Vector3(-randf_range(35.0, 60.0), randf_range(0.0, 360.0), 0.0)
	var tw := create_tween()
	tw.tween_property(_flash, "light_energy", 7.0, 0.04)
	tw.tween_property(_flash, "light_energy", 0.4, 0.08)
	tw.tween_property(_flash, "light_energy", 5.0, 0.06)
	tw.tween_property(_flash, "light_energy", 0.0, 0.4)
	tw.finished.connect(_schedule_lightning)
