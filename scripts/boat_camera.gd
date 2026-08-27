extends Node3D
## Camera with three modes, cycled with F:
##  - FOLLOW: orbits the boat; hold right mouse to orbit, wheel to zoom.
##  - FPS:    sitting in the boat; mouse is captured and look follows it
##            directly. Boat controls stay active.
##  - FREE:   fly camera; hold right mouse to look, W/A/S/D + Q/E to move,
##            Shift for speed boost. Boat input is suspended.
## The camera stays above the waves in FOLLOW / FPS. FREE mode can dive;
## Q lowers, E raises. Seafloor is the only lower clamp.

enum Mode { FOLLOW, FPS, FREE }

var target: Node3D
var ocean: Node3D
var weather: Node3D
var mode: int = Mode.FOLLOW
var free_mode := false  # read by boat.gd: true only in FREE mode

var yaw := 0.0
var pitch := -0.22
var dist := 16.0
var free_speed := 14.0

const FPS_EYE := Vector3(0.0, 3.30, 0.55)  # standing at the wheel, in the wheelhouse

var _cam: Camera3D
var _orbiting := false
var _under_rect: ColorRect
var _under_mat: ShaderMaterial
var _motes: GPUParticles3D
var _bubbles: GPUParticles3D


func _ready() -> void:
	_cam = Camera3D.new()
	_cam.fov = 70.0
	_cam.near = 0.1
	# The true horizon is ~5 km out; the sea plate has to reach past it.
	_cam.far = 18000.0
	add_child(_cam)
	_cam.current = true
	_cam.top_level = true  # free of rig transform; we place it explicitly
	_cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_build_underwater()


func set_mode(m: int) -> void:
	mode = m
	free_mode = mode == Mode.FREE
	match mode:
		Mode.FPS:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			# start looking where the boat points
			if target != null:
				var fwd := -target.global_basis.z
				yaw = atan2(-fwd.x, -fwd.z)
			pitch = 0.0
		Mode.FREE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			var fwd := -_cam.global_basis.z
			yaw = atan2(-fwd.x, -fwd.z)
			pitch = asin(clampf(fwd.y, -1.0, 1.0))
		_:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			pitch = clampf(pitch, -1.15, 0.45)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_camera"):
		set_mode((mode + 1) % 3)
		return
	if mode == Mode.FPS and event.is_action_pressed("ui_cancel"):
		set_mode(Mode.FOLLOW)
		return

	if event is InputEventMouseMotion:
		if mode == Mode.FPS:
			# direct mouse look, no button needed
			yaw -= event.relative.x * 0.0035
			pitch = clampf(pitch - event.relative.y * 0.0035, -1.4, 1.4)
		elif _orbiting:
			yaw -= event.relative.x * 0.005
			if mode == Mode.FREE:
				pitch = clampf(pitch - event.relative.y * 0.005, -1.5, 1.5)
			else:
				pitch = clampf(pitch - event.relative.y * 0.005, -1.15, 0.45)
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and mode != Mode.FPS:
			_orbiting = event.pressed
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _orbiting else Input.MOUSE_MODE_VISIBLE
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			if mode == Mode.FREE:
				free_speed = clampf(free_speed * 1.15, 2.0, 120.0)
			elif mode == Mode.FOLLOW:
				dist = clampf(dist * 0.9, 7.0, 60.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			if mode == Mode.FREE:
				free_speed = clampf(free_speed / 1.15, 2.0, 120.0)
			elif mode == Mode.FOLLOW:
				dist = clampf(dist * 1.1, 7.0, 60.0)


func _process(delta: float) -> void:
	match mode:
		Mode.FPS:
			_process_fps()
		Mode.FREE:
			_process_free(delta)
		_:
			_process_follow(delta)
	_update_underwater()


func _process_follow(delta: float) -> void:
	if target == null:
		return
	var t := 1.0 - exp(-8.0 * delta)
	var tgt: Vector3 = target.get_global_transform_interpolated().origin
	if not tgt.is_finite():
		return
	global_position = global_position.lerp(tgt, t)

	var rot := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	var cam_pos := global_position + rot * Vector3(0.0, 0.0, dist)
	_clamp_and_place(cam_pos)
	var look := global_position + Vector3(0.0, 2.4, 0.0)
	if _cam.global_position.is_finite() and look.is_finite() \
			and _cam.global_position.distance_squared_to(look) > 0.04:
		_cam.look_at(look, Vector3.UP)


func _process_fps() -> void:
	if target == null:
		return
	# Physics interpolation is on project-wide, so the boat's MESH is drawn at a
	# smoothly interpolated transform while `global_transform` still reports the
	# last physics tick. Reading the raw transform pins the eye to 60 Hz inside a
	# 120 Hz render and the whole boat shivers around you as you make way. Ask
	# for the interpolated one instead.
	var xf: Transform3D = target.get_global_transform_interpolated()
	global_position = xf.origin
	# eye rides the hull (position bobs with the boat), head stays level
	var cam_pos: Vector3 = xf * FPS_EYE
	if ocean != null:
		cam_pos.y = maxf(cam_pos.y, ocean.get_height(cam_pos) + 0.35)
	_cam.global_position = cam_pos
	_cam.global_basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)


func _process_free(delta: float) -> void:
	var look := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	var fwd := -look.z
	var right := look.x

	var move := Vector3.ZERO
	move += fwd * Input.get_axis("boat_backward", "boat_forward")
	move += right * Input.get_axis("boat_left", "boat_right")
	if Input.is_key_pressed(KEY_E):
		move += Vector3.UP
	if Input.is_key_pressed(KEY_Q):
		move -= Vector3.UP
	var speed := free_speed * (3.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0)

	var cam_pos := _cam.global_position + move * speed * delta
	_clamp_and_place(cam_pos)
	_cam.global_basis = look


func _clamp_and_place(cam_pos: Vector3) -> void:
	if ocean != null:
		if mode == Mode.FREE:
			var floor_h: float = ocean.get_seafloor_height(cam_pos)
			cam_pos.y = maxf(cam_pos.y, floor_h + 0.45)
		else:
			var wh: float = ocean.get_height(cam_pos)
			cam_pos.y = maxf(cam_pos.y, wh + 0.6)
	_cam.global_position = cam_pos


func _build_underwater() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 0
	add_child(layer)
	_under_rect = ColorRect.new()
	_under_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_under_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_under_rect.color = Color(1, 1, 1, 1)
	_under_mat = ShaderMaterial.new()
	_under_mat.shader = load("res://shaders/underwater.gdshader")
	_under_rect.material = _under_mat
	_under_rect.visible = false
	layer.add_child(_under_rect)


	_motes = GPUParticles3D.new()
	_motes.amount = 90
	_motes.lifetime = 4.5
	_motes.preprocess = 2.0
	_motes.emitting = false
	_motes.transform_align = GPUParticles3D.TRANSFORM_ALIGN_DISABLED
	_motes.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_motes.visibility_aabb = AABB(Vector3(-18, -12, -18), Vector3(36, 24, 36))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(8.0, 5.0, 8.0)
	pm.gravity = Vector3(0, 0.12, 0)
	pm.initial_velocity_min = 0.02
	pm.initial_velocity_max = 0.12
	pm.scale_min = 0.015
	pm.scale_max = 0.045
	pm.color = Color(0.7, 0.85, 0.82, 0.22)
	_motes.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.04, 0.04)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_color = Color(0.75, 0.9, 0.88, 0.28)
	q.material = mat
	_motes.draw_pass_1 = q
	add_child(_motes)
	_motes.top_level = true

	# Bubbles. Suspended motes tell you the water is dirty; bubbles tell you
	# which way is up, which is the thing you actually lose underwater.
	_bubbles = GPUParticles3D.new()
	_bubbles.amount = 70
	_bubbles.lifetime = 3.2
	_bubbles.preprocess = 1.5
	_bubbles.emitting = false
	_bubbles.transform_align = GPUParticles3D.TRANSFORM_ALIGN_DISABLED
	_bubbles.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_bubbles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bubbles.visibility_aabb = AABB(Vector3(-14, -10, -14), Vector3(28, 24, 28))
	var bpm := ParticleProcessMaterial.new()
	bpm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	bpm.emission_box_extents = Vector3(6.0, 4.0, 6.0)
	bpm.direction = Vector3(0, 1, 0)
	bpm.spread = 12.0
	bpm.initial_velocity_min = 0.25
	bpm.initial_velocity_max = 0.75
	bpm.gravity = Vector3(0, 1.1, 0)   # buoyancy, not gravity
	bpm.damping_min = 0.1
	bpm.damping_max = 0.4
	bpm.scale_min = 0.25
	bpm.scale_max = 1.0
	_bubbles.process_material = bpm
	var bq := SphereMesh.new()
	bq.radius = 0.016
	bq.height = 0.032
	bq.radial_segments = 6
	bq.rings = 3
	var bmat := StandardMaterial3D.new()
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.albedo_color = Color(0.72, 0.88, 0.92, 0.30)
	bmat.roughness = 0.05
	bmat.metallic = 0.0
	bmat.rim_enabled = true
	bmat.rim = 0.9
	bq.material = bmat
	_bubbles.draw_pass_1 = bq
	add_child(_bubbles)
	_bubbles.top_level = true


func _update_underwater() -> void:
	if ocean == null or _cam == null:
		return
	var wh: float = ocean.get_height(_cam.global_position)
	var under := _cam.global_position.y < wh - 0.05
	var depth := wh - _cam.global_position.y
	ocean.camera_under = under
	if weather != null and weather.has_method("set_underwater"):
		weather.set_underwater(under)
	if _under_rect != null:
		_under_rect.visible = under
	if under and _under_mat != null:
		_under_mat.set_shader_parameter("amount", 1.0)
		_under_mat.set_shader_parameter("wave_time", ocean.wave_time)
		_under_mat.set_shader_parameter("depth_m", depth)
	if _motes != null:
		_motes.emitting = under
		if under:
			_motes.global_position = _cam.global_position
	if _bubbles != null:
		_bubbles.emitting = under
		if under:
			_bubbles.global_position = _cam.global_position + Vector3(0.0, -2.0, 0.0)
	if under and _under_mat != null and weather != null and weather.has_method("sun_direction"):
		# Light shafts have to point at the real sun, so project it to screen.
		var sd: Vector3 = weather.sun_direction()
		var vp := get_viewport().get_visible_rect().size
		var ss := Vector2(0.5, -0.35)
		var local := _cam.global_basis.inverse() * sd
		if local.z < -0.05:  # in front of the camera
			var p2 := _cam.unproject_position(_cam.global_position + sd * 200.0)
			ss = Vector2(p2.x / maxf(vp.x, 1.0), p2.y / maxf(vp.y, 1.0))
			ss = ss.clamp(Vector2(-1.0, -1.0), Vector2(2.0, 2.0))
		_under_mat.set_shader_parameter("sun_screen", ss)
		_under_mat.set_shader_parameter("shaft_energy", 0.7 if sd.y > 0.05 else 0.15)
