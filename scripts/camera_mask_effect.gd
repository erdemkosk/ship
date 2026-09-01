class_name CameraMaskEffect
extends RefCounted
## Physical dive mask: condensation, exterior drops, breathing and personal
## bubbles. Gameplay ownership stays on the boat; this object owns presentation.

const FOG_DRY := 260.0

var fog := 0.0
var wipe := 0.0
var drops := 0.0
var drop_wipe := 0.0

var _rect: ColorRect
var _material: ShaderMaterial
var _inhale: AudioStreamPlayer
var _exhale: AudioStreamPlayer
var _breath_particles: GPUParticles3D
var _arms: Node
var _breath_burst := 0.0
var _was_submerged := false
var _was_underwater := false
var _breath_time := 0.0
var _breathing_in := true
var _breath_amount := 0.0


func setup(layer: CanvasLayer, host: Node3D, arms: Node) -> void:
	_arms = arms
	_rect = ColorRect.new()
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.color = Color.WHITE
	_material = ShaderMaterial.new()
	_material.shader = load("res://shaders/dive_mask.gdshader")
	_rect.material = _material
	_rect.visible = false
	layer.add_child(_rect)
	_build_breath_audio(host)
	_breath_particles = _make_breath_particles()
	host.add_child(_breath_particles)
	_breath_particles.top_level = true


func tick(delta: float, underwater: bool, boat: Node3D, ocean: Node3D,
		weather: Node3D, camera: Camera3D, walker: RefCounted,
		first_person: bool) -> void:
	if _rect == null or boat == null:
		return
	var wear := float(boat.call("gear_wear_t")) if boat.has_method("gear_wear_t") else 0.0
	var worn := wear > 0.001 and first_person
	_rect.visible = worn
	if not worn:
		_reset()
		return
	_tick_breath_cycle(delta, underwater)
	if underwater and not _was_underwater:
		drops = 1.0
	_was_underwater = underwater
	if underwater:
		drops = minf(drops + delta * 1.6, 1.0)
	else:
		var rain := _rain_amount(weather)
		drops = minf(drops + rain * delta * 0.40, 0.92)
		drops = maxf(drops - delta * 0.018 * (1.0 - rain), 0.0)
	if drop_wipe > 0.0:
		drop_wipe = maxf(drop_wipe - delta / 0.9, 0.0)
		if drop_wipe <= 0.0:
			drops = maxf(drops * 0.20, 0.14)
	if wipe > 0.0:
		wipe = maxf(wipe - delta / 0.9, 0.0)
		if wipe <= 0.0:
			fog = 0.08
	elif wear > 0.98:
		fog = minf(fog + delta / FOG_DRY, 1.0)
		if not _breathing_in:
			fog = minf(fog + delta * 0.006, 1.0)
	_update_material(delta, wear, underwater, ocean, weather)
	_update_personal_breath(delta, underwater, camera, walker, first_person)


func wipe_fog() -> void:
	if fog < 0.09 or wipe > 0.0 or drop_wipe > 0.0:
		return
	wipe = 1.0
	if _arms != null and _arms.has_method("face_gesture"):
		_arms.call("face_gesture", "wipe")


func wipe_water(gear_worn: bool) -> void:
	if not gear_worn or drops < 0.12 or wipe > 0.0 or drop_wipe > 0.0:
		return
	drop_wipe = 1.0
	if _arms != null and _arms.has_method("face_gesture"):
		_arms.call("face_gesture", "wipe")


func _reset() -> void:
	fog = 0.0
	wipe = 0.0
	drops = 0.0
	drop_wipe = 0.0
	_breath_time = 0.0
	_breathing_in = true
	_breath_amount = 0.0
	_was_underwater = false


func _update_material(delta: float, wear: float, underwater: bool, ocean: Node3D,
		weather: Node3D) -> void:
	var viewport_size := _rect.get_viewport().get_visible_rect().size
	_material.set_shader_parameter("wear", wear)
	_material.set_shader_parameter("fog", fog)
	_material.set_shader_parameter("wipe", wipe)
	_material.set_shader_parameter("drops", drops)
	_material.set_shader_parameter("drop_wipe", drop_wipe)
	if (wipe > 0.0 or drop_wipe > 0.0) and _arms != null \
			and _arms.has_method("wipe_front"):
		var front: Vector2 = _arms.call("wipe_front")
		_material.set_shader_parameter("wipe_x", front.x)
		_material.set_shader_parameter("wipe_dir", front.y)
	_material.set_shader_parameter("underwater", 1.0 if underwater else 0.0)
	_material.set_shader_parameter("aspect",
			maxf(viewport_size.x, 1.0) / maxf(viewport_size.y, 1.0))
	if ocean != null:
		_material.set_shader_parameter("wave_time", ocean.get("wave_time"))
	_material.set_shader_parameter("rain", _rain_amount(weather))
	_breath_amount = lerpf(_breath_amount, 1.0 if not _breathing_in else 0.0,
			1.0 - exp(-delta * (3.2 if underwater else 1.6)))
	_material.set_shader_parameter("breath", _breath_amount)


func _tick_breath_cycle(delta: float, underwater: bool) -> void:
	_breath_time -= delta
	if _breath_time > 0.0:
		return
	if _breathing_in:
		if underwater and _inhale != null:
			_inhale.pitch_scale = randf_range(0.94, 1.07)
			_inhale.volume_db = randf_range(-8.0, -5.0)
			_inhale.play()
		_breath_time = randf_range(1.30, 1.75) if underwater else randf_range(2.8, 4.2)
	else:
		if underwater and _exhale != null:
			_exhale.pitch_scale = randf_range(0.70, 0.80)
			_exhale.volume_db = randf_range(-15.0, -11.5)
			_exhale.play()
		_breath_time = randf_range(2.10, 2.95) if underwater else randf_range(3.4, 5.0)
	_breathing_in = not _breathing_in


func _update_personal_breath(delta: float, underwater: bool, camera: Camera3D,
		walker: RefCounted, first_person: bool) -> void:
	if _breath_particles == null or camera == null or walker == null:
		return
	var diver := first_person and (bool(walker.get("swimming")) \
			or bool(walker.get("on_sea_ladder")))
	var submerged := diver and underwater
	if submerged and not _was_submerged:
		_breath_burst = 0.75
		_breath_particles.restart()
		_breath_time = 0.0
	_was_submerged = submerged
	_breath_burst = maxf(_breath_burst - delta, 0.0)
	_breath_particles.emitting = submerged
	_breath_particles.amount_ratio = 1.0 if _breath_burst > 0.0 else 0.18
	if submerged:
		_breath_particles.global_position = camera.global_position \
				+ (-camera.global_basis.z) * 0.17 - camera.global_basis.y * 0.09


func _build_breath_audio(host: Node3D) -> void:
	var stream: AudioStream = load("res://assets/audio/inhale.mp3")
	if stream == null:
		return
	_inhale = AudioStreamPlayer.new()
	_inhale.stream = stream
	_inhale.volume_db = -6.0
	host.add_child(_inhale)
	_exhale = AudioStreamPlayer.new()
	_exhale.stream = stream
	_exhale.volume_db = -13.0
	_exhale.pitch_scale = 0.74
	host.add_child(_exhale)


func _make_breath_particles() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = 40
	particles.lifetime = 2.6
	particles.emitting = false
	particles.transform_align = GPUParticles3D.TRANSFORM_ALIGN_DISABLED
	particles.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.visibility_aabb = AABB(Vector3(-3, -2, -3), Vector3(6, 14, 6))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.05
	process.direction = Vector3.UP
	process.spread = 22.0
	process.initial_velocity_min = 0.35
	process.initial_velocity_max = 0.95
	process.gravity = Vector3(0, 1.6, 0)
	process.damping_min = 0.05
	process.damping_max = 0.25
	process.scale_min = 0.35
	process.scale_max = 1.25
	particles.process_material = process
	var mesh := SphereMesh.new()
	mesh.radius = 0.016
	mesh.height = 0.032
	mesh.radial_segments = 6
	mesh.rings = 3
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.78, 0.92, 0.95, 0.42)
	material.roughness = 0.05
	material.disable_fog = true
	material.rim_enabled = true
	material.rim = 0.9
	mesh.material = material
	particles.draw_pass_1 = mesh
	return particles


static func _rain_amount(weather: Node3D) -> float:
	return clampf(float(weather.get("rain_amount")), 0.0, 1.0) if weather != null else 0.0
