extends Node3D
## Wires the scene together and registers input actions in code
## (no hard-coded keys elsewhere; rebindable via InputMap).

var _screenshot_path := ""


func _enter_tree() -> void:
	_add_action("boat_forward", [KEY_W, KEY_UP])
	_add_action("boat_backward", [KEY_S, KEY_DOWN])
	_add_action("boat_left", [KEY_A, KEY_LEFT])
	_add_action("boat_right", [KEY_D, KEY_RIGHT])
	_add_action("toggle_panel", [KEY_TAB])
	_add_action("toggle_camera", [KEY_F])
	_add_action("throw_rock", [KEY_T])


func _add_action(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k: Key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


func _ready() -> void:
	var ocean: Node3D = $Ocean
	var boat: RigidBody3D = $Boat
	var weather: Node3D = $Weather
	var rig: Node3D = $CameraRig
	var ui: CanvasLayer = $UI

	boat.ocean = ocean
	boat.camera_rig = rig
	boat.global_position = Vector3(0.0, 1.2, 0.0)
	ocean.follow_target = boat
	var seabed: Node3D = $Seabed
	seabed.follow_target = boat
	ocean.bind_seabed(seabed)
	rig.target = boat
	rig.ocean = ocean
	rig.weather = weather
	weather.ocean = ocean
	ui.setup(ocean, weather)
	_spawn_flotsam(ocean)

	var look_lh := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--time="):
			weather.time_of_day = float(arg.get_slice("=", 1))
		elif arg == "--no-storm":
			weather.storm = false
			weather.rain_amount = 0.0
			weather.cloud_cover = 0.35
		elif arg == "--drive":
			Input.action_press("boat_forward")
			$Boat.linear_velocity = -$Boat.global_basis.z * 5.5
		elif arg == "--throw":
			_test_throw()
		elif arg == "--fps":
			$CameraRig.set_mode(1)
		elif arg == "--debug-buoy":
			_debug_buoyancy($Boat, $Ocean)
		elif arg == "--lighthouse":
			look_lh = true
			# Close enough to read the tower, still looking at the boat.
			boat.global_position = Vector3(18.0, 6.0, -95.0)
			boat.linear_velocity = Vector3.ZERO
		elif arg.begins_with("--screenshot="):
			_screenshot_path = arg.get_slice("=", 1)
			if look_lh:
				rig.set("pitch", -0.10)
				rig.set("dist", 28.0)
				rig.set("yaw", atan2(-34.0, 91.0))
			else:
				rig.set("pitch", -0.30)
				rig.set("dist", 8.2)
				rig.set("yaw", 0.48)
			_take_test_screenshot()


func _unhandled_input(event: InputEvent) -> void:
	# left click: drop a rock where you clicked on the water
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			return
		var click_pos: Vector2 = event.position
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			click_pos = get_viewport().get_visible_rect().size * 0.5  # FPS: look center
		var origin := cam.project_ray_origin(click_pos)
		var dir := cam.project_ray_normal(click_pos)
		if dir.y >= -0.02:
			return  # clicked at/above the horizon
		var ocean: Node3D = $Ocean
		# iterate ray vs. wave surface (start from the y=0 plane)
		var p := origin + dir * (-origin.y / dir.y)
		for i in 3:
			var h: float = ocean.get_height(p)
			p = origin + dir * ((h - origin.y) / dir.y)
		if origin.distance_to(p) > 250.0:
			return
		var rock := preload("res://scripts/rock.gd").new()
		rock.ocean = ocean
		add_child(rock)
		rock.global_position = p + Vector3(0.0, 4.0, 0.0)
		rock.linear_velocity = Vector3(0.0, -1.5, 0.0)


func _spawn_flotsam(ocean: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260827
	var specs: Array[Vector3] = [
		Vector3(-8.0, 0.0, 6.0),  # plank
		Vector3(-11.0, 1.0, 9.0), # bucket
		Vector3(-14.0, 2.0, 7.0), # blinking buoy
		Vector3(12.0, 0.0, 11.0),
		Vector3(-22.0, 1.0, 28.0),
		Vector3(24.0, 0.0, -18.0),
		Vector3(-36.0, 2.0, 32.0),
		Vector3(44.0, 0.0, 20.0),
		Vector3(-26.0, 1.0, -40.0),
		Vector3(58.0, 0.0, -46.0),
		Vector3(-64.0, 2.0, 52.0),
	]
	for spec: Vector3 in specs:
		var pos := Vector3(spec.x, 0.8, spec.z)
		if ocean.get_seafloor_height(pos) > -1.6:
			continue
		var debris := preload("res://scripts/flotsam.gd").new()
		debris.kind = int(spec.y)
		debris.ocean = ocean
		debris.spawn_yaw = rng.randf() * TAU
		add_child(debris)
		debris.global_position = pos


func _test_throw() -> void:
	# drop a rock at a camera-visible spot beside the boat
	await get_tree().create_timer(2.22).timeout
	var rock := preload("res://scripts/rock.gd").new()
	rock.ocean = $Ocean
	add_child(rock)
	rock.global_position = $Boat.global_position + Vector3(-2.5, 3.5, 2.0)
	rock.linear_velocity = Vector3(0, -3.0, 0)


func _debug_buoyancy(boat: RigidBody3D, ocean: Node3D) -> void:
	for i in 14:
		await get_tree().create_timer(0.5).timeout
		var bp: Vector3 = boat.global_position
		var wh: float = ocean.get_height(bp)
		print("t=%.1f boat.y=%.2f water=%.2f draft=%.2f vel=%.2f up=%.2f" % [
			i * 0.5, bp.y, wh, wh - bp.y, boat.linear_velocity.length(),
			boat.global_basis.y.dot(Vector3.UP)])
	get_tree().quit()


func _take_test_screenshot() -> void:
	await get_tree().create_timer(3.0).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png(_screenshot_path)
	print("screenshot saved: ", _screenshot_path)
	get_tree().quit()
