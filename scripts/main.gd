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
	_add_action("use", [KEY_E])
	_add_action("jump", [KEY_SPACE])
	_add_action("anchor", [KEY_G])
	_add_action("light_cabin", [KEY_1])
	_add_action("light_helm", [KEY_2])
	_add_action("light_beacon", [KEY_3])
	_add_action("light_flood", [KEY_6])
	_add_action("wiper", [KEY_5])


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
	boat.weather = weather
	boat.camera_rig = rig
	ocean.follow_target = boat
	var seabed: Node3D = $Seabed
	seabed.follow_target = boat
	ocean.bind_seabed(seabed)
	_place_boat(boat, ocean)
	rig.target = boat
	rig.ocean = ocean
	rig.weather = weather
	weather.ocean = ocean
	weather.boat = boat
	var tackle: Node3D = (load("res://scripts/ground_tackle.gd") as GDScript).new()
	tackle.boat = boat
	tackle.ocean = ocean
	add_child(tackle)
	boat.tackle = tackle
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
		elif arg == "--fps":
			$CameraRig.set_mode(1)
		elif arg.begins_with("--pitch="):
			rig.set("pitch", float(arg.get_slice("=", 1)))
		elif arg == "--probe-hands":
			_probe_hands(rig, boat)
		elif arg == "--probe-helm":
			_probe_helm(boat)
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


func _place_boat(boat: RigidBody3D, ocean: Node3D) -> void:
	## Open water only. Origin used to be a reserved basin; now we pick a
	## heading and a patch of sea that will actually float a 9 m hull — not a
	## beach, not a reef, not the face of a headland.
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var half := 920.0
	for _i in 80:
		var x := rng.randf_range(-half, half)
		var z := rng.randf_range(-half, half)
		if not _is_open_water(ocean, x, z):
			continue
		boat.global_position = Vector3(x, 1.2, z)
		boat.rotation = Vector3(0.0, rng.randf() * TAU, 0.0)
		boat.linear_velocity = Vector3.ZERO
		boat.angular_velocity = Vector3.ZERO
		return
	boat.global_position = Vector3(0.0, 1.2, 0.0)


func _is_open_water(ocean: Node3D, x: float, z: float) -> bool:
	## Keel sits ~0.7 m below the marks. -8 m under the whole hull is enough
	## that the first swell will not put a bilge on a shelf we did not see.
	const MIN_BED := -8.0
	const HULL_R := 8.0
	const OFFSETS: Array[Vector2] = [
		Vector2.ZERO,
		Vector2(1.0, 0.0), Vector2(-1.0, 0.0), Vector2(0.0, 1.0), Vector2(0.0, -1.0),
		Vector2(0.71, 0.71), Vector2(-0.71, 0.71),
		Vector2(0.71, -0.71), Vector2(-0.71, -0.71),
	]
	for o: Vector2 in OFFSETS:
		var p := Vector3(x + o.x * HULL_R, 0.0, z + o.y * HULL_R)
		if ocean.get_seafloor_height(p) > MIN_BED:
			return false
	return true


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


func _probe_hands(rig: Node3D, boat: RigidBody3D) -> void:
	await get_tree().create_timer(2.5).timeout
	var arms: Node = rig.get("_arms")
	var hands: Node = arms.get("rig")
	var to_local := boat.global_transform.affine_inverse()
	print("ELLER (bot uzayi)")
	print("  talep: L=%s  R=%s" % [arms.get("_claim")["L"], arms.get("_claim")["R"]])
	for side in ["L", "R"]:
		var wrist: Vector3 = to_local * hands.call("wrist_global", side).origin
		var sh: Vector3 = to_local * hands.call("shoulder_global", side)
		print("  %s omuz=(%.2f,%.2f,%.2f) bilek=(%.2f,%.2f,%.2f) uzanma=%.2f m" % [
			side, sh.x, sh.y, sh.z, wrist.x, wrist.y, wrist.z, sh.distance_to(wrist)])
	var g: Variant = arms.get("_grips")
	for k: String in g:
		var n: Node3D = g[k]
		var p: Vector3 = to_local * n.global_position
		print("  tutus %-16s (%.2f,%.2f,%.2f)" % [k, p.x, p.y, p.z])
	print("  egilme=%.3f m" % Vector3(hands.call("lean")).length())
	get_tree().quit()


func _probe_helm(boat: RigidBody3D) -> void:
	var stand: Vector3 = boat.HELM_STAND
	var eye: Vector3 = stand + Vector3(0.0, 1.60, 0.0)
	var ls: Vector3 = eye + Vector3(-0.11, -0.22, 0.10)
	var rs: Vector3 = eye + Vector3(0.11, -0.22, 0.10)
	var wheel: Node3D = boat.helm_wheel()
	var thr: Node3D = boat.throttle_lever()
	var to_local := boat.global_transform.affine_inverse()
	var wc: Vector3 = to_local * wheel.global_position
	var knob: Vector3 = to_local * (thr.global_transform * Vector3(0.0, 0.31, 0.0))
	var rim_near: float = 1e9
	for i in 12:
		var a := float(i) / 12.0 * TAU
		var p: Vector3 = to_local * (wheel.global_transform
				* (Vector3(cos(a), sin(a), 0.0) * 0.29))
		rim_near = minf(rim_near, ls.distance_to(p))
	print("ERGONOMI (bot uzayi, kol erisimi 0.63 m, egilme +0.26 m => 0.89 m)")
	print("  durus=%.2f,%.2f,%.2f  goz=%.2f,%.2f,%.2f" % [
		stand.x, stand.y, stand.z, eye.x, eye.y, eye.z])
	print("  dumen merkezi %.2f,%.2f,%.2f -> sol omuz %.2f m (jant en yakin %.2f m)" % [
		wc.x, wc.y, wc.z, ls.distance_to(wc), rim_near])
	print("  gaz topuzu    %.2f,%.2f,%.2f -> sag omuz %.2f m" % [
		knob.x, knob.y, knob.z, rs.distance_to(knob)])
	get_tree().quit()


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
