extends Node3D
## Wires the scene together and registers input actions in code
## (no hard-coded keys elsewhere; rebindable via InputMap).

var _screenshot_path := ""
var _look_at_target := ""
var _look_rig: Node3D
var _look_boat: RigidBody3D
var _eye_local := Vector3.INF


func _enter_tree() -> void:
	_add_action("boat_forward", [KEY_W, KEY_UP])
	_add_action("boat_backward", [KEY_S, KEY_DOWN])
	_add_action("boat_left", [KEY_A, KEY_LEFT])
	_add_action("boat_right", [KEY_D, KEY_RIGHT])
	_add_action("toggle_panel", [KEY_TAB])
	_add_action("toggle_camera", [KEY_F])
	_add_action("use", [KEY_E])
	_add_action("jump", [KEY_SPACE])
	_add_action("toggle_fps", [KEY_QUOTEDBL, KEY_APOSTROPHE])
	# Only ever means one thing: in the water, swim DOWN. On deck it is dead.
	_add_action("dive", [KEY_CTRL, KEY_C])
	# Hold to look at the dive watch on your left wrist.
	_add_action("watch", [KEY_B])
	# The circuits. Every one of these is also a physical switch under the fuse
	# box lid — these are the shorthand the status panel prints beside each row,
	# and the panel is lying if they are not bound.
	_add_action("anchor", [KEY_G])
	_add_action("light_cabin", [KEY_1])
	_add_action("light_helm", [KEY_2])
	_add_action("light_beacon", [KEY_3])
	_add_action("light_flood", [KEY_6])
	_add_action("wiper", [KEY_5])


func _open_menu() -> void:
	if get_tree().get_first_node_in_group("main_menu") != null:
		return
	var menu: Node3D = (load("res://scripts/main_menu.gd") as GDScript).new()
	menu.call("setup", $CameraRig, $Boat, $Ocean, $Weather)
	add_child(menu)


func return_to_menu() -> void:
	## ESC from play. The world stays; the shot and the words come back.
	_open_menu()


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

	# The menu needs NOTHING to appear: double-click, editor play, exported
	# build — every ordinary launch opens on it. The only thing that skips it
	# is a command-line verification probe (--probe-*, --dive-test, ...),
	# because those need the bare world on frame one; a player never passes
	# arguments, so a player never sees anything but the menu.
	var uargs := OS.get_cmdline_user_args()
	var want_menu := true
	for a in uargs:
		if a.begins_with("--") and a != "--no-storm" and not a.begins_with("--time=") \
				and not a.begins_with("--menu"):
			want_menu = false
	if want_menu:
		_open_menu()
		for a in uargs:
			if a.begins_with("--menu-shot="):
				_menu_shot(get_tree().get_first_node_in_group("main_menu"), a.get_slice("=", 1))

	var look_lh := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--time="):
			weather.time_of_day = float(arg.get_slice("=", 1))
		elif arg == "--no-storm":
			weather.storm = false
			weather.rain_amount = 0.0
			weather.cloud_cover = 0.35
		# --- verification flags -------------------------------------------------
		# Everything below exists so a change to the sea, the hands or the helm
		# can be proven from the command line, without a person at the keyboard:
		#   --drive           power ahead from spawn
		#   --debug-buoy      log boat vs water height for seven seconds
		#   --probe-helm      print stance-to-control reach distances
		#   --probe-hands     print live hand claims, wrists and grips
		#   --pull-radar / --pull-sounder    E-grab an instrument after 1.5 s
		#   --hold-radio      lift the handset after 1.5 s
		#   --turn-test=DIR   hard-over turn, three frames into DIR
		#   --look-at=ID      aim the view at helm / telegraph / radar / sounder
		#   --pitch= --yaw=   nudge the view; --screenshot=PATH then quits
		elif arg == "--drive":
			Input.action_press("boat_forward")
			$Boat.linear_velocity = -$Boat.global_basis.z * 5.5
		elif arg == "--fps":
			$CameraRig.set_mode(1)
		elif arg.begins_with("--pitch="):
			rig.set("pitch", float(arg.get_slice("=", 1)))
		elif arg.begins_with("--yaw="):
			rig.set("yaw", rig.get("yaw") + float(arg.get_slice("=", 1)))
		elif arg.begins_with("--use="):
			_use_later(boat, arg.get_slice("=", 1))
		elif arg.begins_with("--eye="):
			# Park the FREE camera at a boat-local point — an inspection
			# tripod, for photographing interiors without fighting the walker.
			var e := arg.get_slice("=", 1).split(",")
			rig.set_mode(2)
			_eye_local = Vector3(float(e[0]), float(e[1]), float(e[2]))
			_look_rig = rig
			_look_boat = boat
		elif arg.begins_with("--spawn="):
			var v := arg.get_slice("=", 1).split(",")
			rig.get("_walker").call("spawn_at",
					Vector3(float(v[0]), float(v[1]), float(v[2])))
		elif arg.begins_with("--look-at="):
			# Aim the FPS view at a named point on the boat, for screenshots.
			_look_at_target = arg.get_slice("=", 1)
			_look_rig = rig
			_look_boat = boat
		elif arg == "--probe-hands":
			_probe_hands(rig, boat)
		elif arg == "--pull-radar":
			_pull_radar(rig)
		elif arg == "--pull-sounder":
			_pull_device(rig, "sounder")
		elif arg == "--hold-radio":
			_hold_radio(boat)
		elif arg == "--probe-engine":
			_probe_engine(boat)
		elif arg == "--drift-test":
			_drift_test(boat)
		elif arg == "--walk-aft":
			_walk_aft(rig)
		elif arg.begins_with("--roll-test="):
			_roll_test(boat, weather, arg.get_slice("=", 1))
		elif arg.begins_with("--switch-shot="):
			_switch_shot(rig, boat, arg.get_slice("=", 1))
		elif arg.begins_with("--radio-shot="):
			_radio_shot(rig, boat, arg.get_slice("=", 1))
		elif arg.begins_with("--watch-sweep="):
			_watch_sweep(rig, boat, arg.get_slice("=", 1))
		elif arg.begins_with("--watch-shot="):
			_watch_shot(rig, boat, arg.get_slice("=", 1))
		elif arg.begins_with("--maskdive="):
			_maskdive(rig, boat, arg.get_slice("=", 1))
		elif arg.begins_with("--gear-test="):
			_gear_test(rig, boat, arg.get_slice("=", 1))
		elif arg.begins_with("--stance-test="):
			_stance_test(rig, boat, arg.get_slice("=", 1))
		elif arg.begins_with("--ladder-shot="):
			_ladder_shot(rig, boat, arg.get_slice("=", 1))
		elif arg.begins_with("--dive-test="):
			_dive_test(rig, boat, arg.get_slice("=", 1))
		elif arg.begins_with("--turn-test="):
			_turn_test(arg.get_slice("=", 1))
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


func _pull_radar(rig: Node3D) -> void:
	_pull_device(rig, "radar")


func _use_later(boat: RigidBody3D, ids: String) -> void:
	# Mirrors the in-game E flow: the boat acts AND the hands hear about it.
	# Comma-separated ids fire in sequence, 0.6 s apart — enough to open a lid
	# and then jab what it was hiding.
	await get_tree().create_timer(2.0).timeout
	var arms: Node = $CameraRig.get("_arms")
	arms.set("boat", boat)
	for id in ids.split(","):
		boat.call("toggle_switch", id)
		arms.call("notify_use", id)
		await get_tree().create_timer(0.6).timeout


func _pull_device(rig: Node3D, id: String) -> void:
	await get_tree().create_timer(1.5).timeout
	var arms: Node = rig.get("_arms")
	arms.set("boat", $Boat)
	arms.call("notify_use", id)


func _hold_radio(boat: RigidBody3D) -> void:
	await get_tree().create_timer(1.5).timeout
	boat.set("radio_held", true)


func _probe_engine(boat: RigidBody3D) -> void:
	## Every engine-room mesh, measured in world space against the volume the
	## companionway treads occupy. Anything that reaches into a tread is named,
	## rather than found later by walking into it.
	await get_tree().create_timer(1.2).timeout
	var room: Node = boat.get("_engine_room")
	if room == null:
		print("motor odasi yok"); get_tree().quit(); return
	var to_local := boat.global_transform.affine_inverse()
	var treads: Array = []
	for i in 10:
		var ty := 0.903 + float(i) * 0.223
		var tz := 3.80 - float(i) * 0.30
		# board: 1.16 wide at x -1.08, 0.06 thick with its TOP at ty
		treads.append([i, ty - 0.06, ty, tz - 0.15, tz + 0.15])
	var hits := 0
	var checked := 0
	var stack: Array = [room]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if not (n is MeshInstance3D):
			continue
		var mi: MeshInstance3D = n
		var ab: AABB = mi.get_aabb()
		# eight corners into boat-local space
		var lo := Vector3(1e9, 1e9, 1e9)
		var hi := -lo
		for k in 8:
			var corner: Vector3 = to_local * (mi.global_transform * ab.get_endpoint(k))
			lo = lo.min(corner)
			hi = hi.max(corner)
		checked += 1
		if hi.x < -1.66 or lo.x > -0.50:
			continue
		for t in treads:
			if hi.y > float(t[1]) and lo.y < float(t[2]) \
					and hi.z > float(t[3]) and lo.z < float(t[4]):
				hits += 1
				print("  ÇAKIŞMA basamak %d  parca=%s  y=[%.2f..%.2f] z=[%.2f..%.2f] x=[%.2f..%.2f]"
						% [t[0], mi.name, lo.y, hi.y, lo.z, hi.z, lo.x, hi.x])
				break
	print("motor parcasi taranan=%d, basamaga giren=%d" % [checked, hits])
	get_tree().quit()


func _drift_test(boat: RigidBody3D) -> void:
	## Zero input, engine off: log heading and the yaw-torque ledger. If she
	## turns, the ledger says which term paid for it.
	boat.set("drift_dbg", true)
	await get_tree().create_timer(1.0).timeout
	var t := 0.0
	while t < 24.0:
		await get_tree().create_timer(4.0).timeout
		t += 4.0
		var yaw := rad_to_deg(boat.global_basis.get_euler().y)
		var s: Dictionary = boat.get("drift_sums")
		print("t=%4.0f  yon=%7.2f deg  helm=%+.3f  yawhiz=%+.4f  | align=%+.0f rudder=%+.0f damp=%+.0f ground=%+.0f" % [
			t, yaw, boat.get("_helm"), boat.angular_velocity.y,
			s["align"], s["rudder"], s["damp"], s["ground"]])
	get_tree().quit()


func _roll_test(boat: RigidBody3D, weather: Node3D, spec: String) -> void:
	## How lively is she? Peak and RMS heel and trim over half a minute, at a
	## named sea state. The only way to tell "she rolls too much" from "she
	## rolls" is to put a number on it and then change one thing.
	var parts := spec.split(",")
	var wind := float(parts[0]) if parts.size() > 0 else 14.0
	if parts.size() > 1:
		boat.set("roll_damp", float(parts[1]))
		boat.set("pitch_damp", float(parts[1]) * 0.67)
	if parts.size() > 2:
		boat.set("hull_plane_fit", parts[2] == "1")
	var oc: Node = boat.get("ocean")
	if oc != null and oc.has_method("set_wind"):
		oc.call("set_wind", wind, 40.0, 1.0, 0.9)
	if weather.has_method("set_wind"):
		weather.call("set_wind", wind, 40.0)
	# The sea state AGES — it does not appear. Give it long enough to be the
	# sea it was asked for before measuring anything on it.
	await get_tree().create_timer(45.0).timeout
	var n := 0.0
	var r2 := 0.0
	var p2 := 0.0
	var rmax := 0.0
	var pmax := 0.0
	var t := 0.0
	while t < 30.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		var b: Basis = boat.global_basis
		var roll: float = rad_to_deg(asin(clampf(b.x.y, -1.0, 1.0)))
		var pitch: float = rad_to_deg(asin(clampf(-b.z.y, -1.0, 1.0)))
		r2 += roll * roll
		p2 += pitch * pitch
		rmax = maxf(rmax, absf(roll))
		pmax = maxf(pmax, absf(pitch))
		n += 1.0
	print("[roll] wind=%.0f m/s  yalpa rms=%.2f deg tepe=%.2f  |  bas-kic rms=%.2f tepe=%.2f" % [
			wind, sqrt(r2 / n), rmax, sqrt(p2 / n), pmax])
	get_tree().quit()


func _switch_shot(rig: Node3D, boat: RigidBody3D, dir: String) -> void:
	## A finger on the toggles: can the arm reach them, and does the fingertip
	## land ON the knob or a centimetre over it.
	var w: RefCounted = rig.get("_walker")
	rig.set_mode(1)
	var pnl: Node = get_tree().get_first_node_in_group("ui_panel")
	if pnl != null:
		var pc: CanvasItem = pnl.get("_panel") as CanvasItem
		if pc != null:
			pc.visible = false
	await get_tree().create_timer(2.2).timeout
	boat.set("helm_engaged", false)
	boat.set("light_helm", true)
	boat.set("fusebox_open", true)
	w.call("spawn_at", Vector3(0.66, 2.91, 1.54))
	var cam: Camera3D = rig.get("_cam")
	var arms: Node = rig.get("_arms")
	arms.set("boat", boat)
	var hr: Node = arms.get("rig")
	for sid in ["sw_cabin", "sw_helm", "sw_beacon", "sw_flood", "sw_wiper", "sw_anchor"]:
		var lev: Node3D = boat.call("switch_lever", sid)
		for i in 5:
			var d: Vector3 = lev.global_position - cam.global_position
			rig.set("yaw", atan2(-d.x, -d.z))
			rig.set("pitch", asin(clampf(d.normalized().y, -1.0, 1.0)))
			await get_tree().create_timer(0.1).timeout
		arms.call("notify_use", sid)
		await get_tree().create_timer(0.80).timeout
		var g: Node3D = lev.get_node_or_null("Grip_R")
		var wr: Transform3D = hr.call("wrist_global", "R")
		var sh: Vector3 = hr.call("shoulder_global", "R")
		print("[sw] %-10s reach=%.3f  grip=%.2v  wrist=%.2v  err=%.3f" % [
				sid, sh.distance_to(g.global_position) if g != null else -1.0,
				boat.to_local(g.global_position) if g != null else Vector3.ZERO,
				boat.to_local(wr.origin),
				wr.origin.distance_to(g.global_position) if g != null else -1.0])
		await _shot(dir, "sw_%s" % sid)
		await get_tree().create_timer(0.5).timeout
	get_tree().quit()


func _radio_shot(rig: Node3D, boat: RigidBody3D, dir: String) -> void:
	## The handset in the hand, from the only angle that matters: yours.
	rig.set_mode(1)
	var pnl: Node = get_tree().get_first_node_in_group("ui_panel")
	if pnl != null:
		var pc: CanvasItem = pnl.get("_panel") as CanvasItem
		if pc != null:
			pc.visible = false
	await get_tree().create_timer(2.2).timeout
	boat.set("helm_engaged", true)
	boat.set("light_helm", true)
	await get_tree().create_timer(0.6).timeout
	boat.set("radio_held", true)
	var arms: Node = rig.get("_arms")
	arms.set("boat", boat)
	arms.call("notify_use", "radio")
	for i in 4:
		await get_tree().create_timer(0.7).timeout
		rig.set("pitch", [-0.10, 0.10, -0.30, 0.0][i])
		rig.set("yaw", _as_f(rig.get("yaw")) + [0.0, 0.22, -0.30, 0.10][i])
		await get_tree().create_timer(0.25).timeout
		await _shot(dir, "radio%d" % i)
	get_tree().quit()


func _menu_shot(menu: Node3D, dir: String) -> void:
	## The front door, photographed: the wide shot, the hand on the telegraph,
	## and the cut into the game.
	await get_tree().create_timer(5.0).timeout
	await _shot(dir, "menu0_wide")
	menu.call("debug_hover", "sail")
	await get_tree().create_timer(0.9).timeout
	await _shot(dir, "menu1_hand")
	menu.call("debug_hover", "abandon")
	await get_tree().create_timer(0.9).timeout
	await _shot(dir, "menu2_abandon")
	menu.call("debug_hover", "")
	menu.call("debug_press", "sail")
	await get_tree().create_timer(0.7).timeout
	await _shot(dir, "menu3_push")
	await get_tree().create_timer(2.6).timeout
	await _shot(dir, "menu4_ingame")
	get_tree().quit()


func _watch_sweep(rig: Node3D, boat: RigidBody3D, dir: String) -> void:
	## The strap, swept on the LIT DECK with the parts colour-coded.
	##
	## Underwater was tried and is useless for this: the diver keeps sinking,
	## so every frame of the sweep is darker than the last and the final one is
	## black. On deck the light is constant, and with the band flat red the
	## question answers itself — a link inside the arm is not drawn at all, a
	## link outside it breaks the silhouette.
	var w: RefCounted = rig.get("_walker")
	rig.set_mode(1)
	var pnl: Node = get_tree().get_first_node_in_group("ui_panel")
	if pnl != null:
		var pc: CanvasItem = pnl.get("_panel") as CanvasItem
		if pc != null:
			pc.visible = false
	await get_tree().create_timer(2.2).timeout
	boat.set("helm_engaged", false)
	w.call("spawn_at", Vector3(0.0, 0.63, 3.0))
	rig.set("pitch", -0.25)
	await get_tree().create_timer(0.4).timeout
	Input.action_press("watch")
	await get_tree().create_timer(1.0).timeout
	var hr: Node = (rig.get("_arms") as Node).get("rig")
	for k in [0, 3, 5, 7, 9, 11]:
		hr.call("set_strap_tight", float(k) * 0.001)
		await get_tree().create_timer(0.25).timeout
		await _shot(dir, "pen_%03d_skin" % k)
		hr.call("set_arm_visible", false)
		await get_tree().create_timer(0.20).timeout
		await _shot(dir, "pen_%03d_bare" % k)
		hr.call("set_arm_visible", true)
		await get_tree().create_timer(0.15).timeout
		print("[sweep] palm off %d mm" % k)
	Input.action_release("watch")
	get_tree().quit()


func _watch_shot(rig: Node3D, boat: RigidBody3D, dir: String) -> void:
	## The watch, everywhere it matters: on deck by day, on deck after dark
	## (backlight), and underwater with the depth row alive.
	var w: RefCounted = rig.get("_walker")
	var wx: Node3D = $Weather
	rig.set_mode(1)
	var pnl: Node = get_tree().get_first_node_in_group("ui_panel")
	if pnl != null:
		var pc: CanvasItem = pnl.get("_panel") as CanvasItem
		if pc != null:
			pc.visible = false
	await get_tree().create_timer(2.2).timeout
	boat.set("helm_engaged", false)
	w.call("spawn_at", Vector3(0.0, 0.63, 3.0))
	rig.set("pitch", -0.25)
	await get_tree().create_timer(0.4).timeout
	Input.action_press("watch")
	await get_tree().create_timer(1.0).timeout
	await _shot(dir, "watch0_day")
	wx.set("time_of_day", 21.6)
	await get_tree().create_timer(0.8).timeout
	await _shot(dir, "watch1_night")
	Input.action_release("watch")
	wx.set("time_of_day", 12.5)
	await get_tree().create_timer(0.8).timeout
	await _shot(dir, "watch2_released")
	# Over the stern and down: the depth row.
	w.call("spawn_at", Vector3(0.72, 0.63, 5.05))
	await get_tree().create_timer(0.3).timeout
	w.call("grab_sea_ladder", boat)
	await get_tree().create_timer(0.4).timeout
	Input.action_press("boat_backward")
	await get_tree().create_timer(3.4).timeout
	Input.action_release("boat_backward")
	rig.set("pitch", -1.0)
	Input.action_press("boat_forward")
	await get_tree().create_timer(3.2).timeout
	# Keep swimming down WHILE reading it — stop kicking in the shallow metres
	# and buoyancy hands you straight back to the surface, which is how the
	# first pass of this probe photographed a depth of zero.
	rig.set("pitch", -0.5)
	Input.action_press("watch")
	await get_tree().create_timer(1.0).timeout
	print("[watch] depth=%.2f" % w.get("swim_depth"))
	await _shot(dir, "watch3_under")
	Input.action_release("watch")
	Input.action_release("boat_forward")
	get_tree().quit()


func _maskdive(rig: Node3D, boat: RigidBody3D, dir: String) -> void:
	## The payoff: mask on, over the stern, under, and the glass going over.
	var w: RefCounted = rig.get("_walker")
	rig.set_mode(1)
	var pnl: Node = get_tree().get_first_node_in_group("ui_panel")
	if pnl != null:
		var pc: CanvasItem = pnl.get("_panel") as CanvasItem
		if pc != null:
			pc.visible = false
	await get_tree().create_timer(2.2).timeout
	boat.set("helm_engaged", false)
	boat.set("locker_open", true)
	boat.set("gear_worn", true)
	await get_tree().create_timer(1.6).timeout
	w.call("spawn_at", Vector3(0.72, 0.63, 5.05))
	await get_tree().create_timer(0.3).timeout
	w.call("grab_sea_ladder", boat)
	await get_tree().create_timer(0.4).timeout
	Input.action_press("boat_backward")
	await get_tree().create_timer(3.6).timeout
	Input.action_release("boat_backward")
	rig.set("pitch", -1.05)
	Input.action_press("boat_forward")
	await get_tree().create_timer(4.5).timeout
	print("[maskdive] sub=%s depth=%.2f" % [w.get("submerged"), w.get("swim_depth")])
	await _shot(dir, "md0_clear")
	for fv in [0.22, 0.45, 0.68, 0.90]:
		rig.set("_fog", fv)
		await get_tree().create_timer(0.35).timeout
		await _shot(dir, "md1_fog%02d" % int(fv * 100.0))
	rig.set("_fog", 0.90)
	rig.set("pitch", 0.55)
	await get_tree().create_timer(0.6).timeout
	await _shot(dir, "md3_up")
	rig.call("_wipe_mask")
	for i in 3:
		await get_tree().create_timer(0.24).timeout
		await _shot(dir, "md4_wipe%d" % i)
	Input.action_release("boat_forward")
	get_tree().quit()


func _gear_test(rig: Node3D, boat: RigidBody3D, dir: String) -> void:
	## The locker, the gear, and the glass: open it, put it on, fog it, wipe it.
	var w: RefCounted = rig.get("_walker")
	rig.set_mode(1)
	var pnl: Node = get_tree().get_first_node_in_group("ui_panel")
	if pnl != null:
		var pc: CanvasItem = pnl.get("_panel") as CanvasItem
		if pc != null:
			pc.visible = false
	await get_tree().create_timer(2.2).timeout
	boat.set("helm_engaged", false)
	boat.set("light_cabin", true)
	w.call("spawn_at", Vector3(-0.80, 0.68, 0.40))
	var cam: Camera3D = rig.get("_cam")
	for i in 6:
		var d: Vector3 = boat.to_global(Vector3(-1.30, 1.55, 0.40)) - cam.global_position
		rig.set("yaw", atan2(-d.x, -d.z))
		rig.set("pitch", asin(clampf(d.normalized().y, -1.0, 1.0)))
		await get_tree().create_timer(0.12).timeout
	await _shot(dir, "gear0_shut")
	boat.call("toggle_switch", "locker")
	await get_tree().create_timer(1.1).timeout
	await _shot(dir, "gear1_open")
	# Look at the gear on its hook.
	for i in 4:
		var d2: Vector3 = boat.to_global(Vector3(-1.36, 1.80, 0.36)) - cam.global_position
		rig.set("yaw", atan2(-d2.x, -d2.z))
		rig.set("pitch", asin(clampf(d2.normalized().y, -1.0, 1.0)))
		await get_tree().create_timer(0.12).timeout
	await _shot(dir, "gear2_hook")
	boat.call("toggle_switch", "divegear")
	var arms: Node = rig.get("_arms")
	if arms != null and arms.has_method("face_gesture"):
		arms.call("face_gesture", "wear")
	for i in 5:
		await get_tree().create_timer(0.30).timeout
		await _shot(dir, "gear3_wear%d" % i)
	await get_tree().create_timer(0.8).timeout
	print("[gear] worn=%s t=%.2f mode=%s pos=%.2v swim=%s" % [
			boat.get("gear_worn"), boat.call("gear_wear_t"), rig.get("mode"),
			w.get("pos"), w.get("swimming")])
	await _shot(dir, "gear4_on")
	# Fog it, at every stage of going over.
	for fv in [0.18, 0.42, 0.68, 0.92, 1.0]:
		rig.set("_fog", fv)
		await get_tree().create_timer(0.35).timeout
		await _shot(dir, "gear5_fog%02d" % int(fv * 100.0))
	rig.set("_fog", 0.85)
	rig.set("_wipe", 0.0)
	await get_tree().create_timer(0.3).timeout
	rig.call("_wipe_mask")
	for i in 6:
		await get_tree().create_timer(0.15).timeout
		await _shot(dir, "gear6_wipe%d" % i)
	await get_tree().create_timer(0.6).timeout
	print("[gear] fog after wipe = %.2f" % rig.get("_fog"))
	await _shot(dir, "gear7_clear")
	get_tree().quit()


func _stance_test(rig: Node3D, boat: RigidBody3D, dir: String) -> void:
	## Hands on the wheel, then try to look astern. A body that is holding on
	## does not turn; the head does, and only so far.
	rig.set_mode(1)
	await get_tree().create_timer(2.5).timeout
	boat.set("helm_engaged", true)
	for want in [2.6, -2.6, 0.4]:
		rig.set("yaw", rig.get("yaw") + want)
		await get_tree().create_timer(0.4).timeout
		var fwd: Vector3 = -boat.global_basis.z
		var base: float = atan2(-fwd.x, -fwd.z)
		var rel: float = rad_to_deg(wrapf(_as_f(rig.get("yaw")) - base, -PI, PI))
		print("[stance] istendi %+.0f deg -> basa gore %+.1f deg" % [
				rad_to_deg(want), rel])
	await _shot(dir, "stance_limit")
	get_tree().quit()


func _ladder_shot(rig: Node3D, boat: RigidBody3D, dir: String) -> void:
	## The hands on the rungs, in daylight, looking level.
	var w: RefCounted = rig.get("_walker")
	rig.set_mode(1)
	var pnl: Node = get_tree().get_first_node_in_group("ui_panel")
	if pnl != null:
		var pc: CanvasItem = pnl.get("_panel") as CanvasItem
		if pc != null:
			pc.visible = false
	await get_tree().create_timer(2.2).timeout
	boat.set("helm_engaged", false)
	w.call("spawn_at", Vector3(0.72, 0.63, 5.05))
	var aft: Vector3 = boat.global_basis.z
	rig.set("yaw", atan2(-aft.x, -aft.z))
	rig.set("pitch", -0.34)
	await get_tree().create_timer(0.5).timeout
	w.call("grab_sea_ladder", boat)
	await get_tree().create_timer(0.6).timeout
	print("[lad] yaw=%.2f pos=%.2v" % [rig.get("yaw"), w.get("pos")])
	await _shot(dir, "lad_a")
	Input.action_press("boat_backward")
	for i in 4:
		await get_tree().create_timer(0.6).timeout
		var arms: Node = rig.get("_arms")
		var hr: Node = arms.get("rig")
		var lw: Transform3D = hr.call("wrist_global", "L")
		var rw: Transform3D = hr.call("wrist_global", "R")
		print("[lad] y=%+.2f  wristL=%.2v  wristR=%.2v" % [
				w.get("pos").y, boat.to_local(lw.origin), boat.to_local(rw.origin)])
		await _shot(dir, "lad_b%d" % i)
	Input.action_release("boat_backward")
	get_tree().quit()


func _shot(dir: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, name])


func _dive_test(rig: Node3D, boat: RigidBody3D, dir: String) -> void:
	## The whole way overboard and back: deck -> ladder -> water -> under -> up
	## -> ladder -> deck. State printed AND photographed at every stage, because
	## "the ladder works" is a claim about a picture, not about a number.
	var w: RefCounted = rig.get("_walker")
	rig.set_mode(1)
	# The weather panel is up at boot and it gates every walking input, so a
	# climb test with it open measures nothing at all.
	var pnl: Node = get_tree().get_first_node_in_group("ui_panel")
	var pc: CanvasItem = null
	if pnl != null:
		pc = pnl.get("_panel") as CanvasItem
		if pc != null:
			pc.visible = false
	print("[dive] panel=%s open=%s" % [pc, pnl.call("is_open") if pnl != null else "?"])
	await get_tree().create_timer(2.2).timeout
	boat.set("helm_engaged", false)
	w.call("spawn_at", Vector3(0.72, 0.63, 5.05))
	# Face aft, down at the transom cap.
	var aft: Vector3 = boat.global_basis.z
	rig.set("yaw", atan2(-aft.x, -aft.z))
	rig.set("pitch", -0.55)
	await get_tree().create_timer(0.7).timeout
	print("[dive] deck   pos=%.2v" % w.get("pos"))
	await _shot(dir, "dive0_deck")

	w.call("grab_sea_ladder", boat)
	await get_tree().create_timer(0.8).timeout
	print("[dive] ladder on=%s pos=%.2v" % [w.get("on_sea_ladder"), w.get("pos")])
	await _shot(dir, "dive1_ladder")

	Input.action_press("boat_backward")
	await get_tree().create_timer(0.4).timeout
	print("[dive] axis=%.2f  ladder=%s y=%.3f" % [
			Input.get_axis("boat_backward", "boat_forward"),
			w.get("on_sea_ladder"), w.get("pos").y])
	await get_tree().create_timer(3.2).timeout
	Input.action_release("boat_backward")
	print("[dive] down   ladder=%s swim=%s sub=%s depth=%.2f pos=%.2v" % [
			w.get("on_sea_ladder"), w.get("swimming"), w.get("submerged"),
			w.get("swim_depth"), w.get("pos")])
	await _shot(dir, "dive2_water")

	# Look down and swim: that is the whole of diving.
	rig.set("pitch", -1.15)
	Input.action_press("boat_forward")
	await get_tree().create_timer(3.0).timeout
	print("[dive] under  sub=%s depth=%.2f" % [w.get("submerged"), w.get("swim_depth")])
	await _shot(dir, "dive3_under")
	await get_tree().create_timer(3.0).timeout
	print("[dive] deep   sub=%s depth=%.2f" % [w.get("submerged"), w.get("swim_depth")])
	await _shot(dir, "dive4_deep")
	Input.action_release("boat_forward")

	# Kick for the surface.
	rig.set("pitch", 0.2)
	Input.action_press("jump")
	await get_tree().create_timer(5.0).timeout
	Input.action_release("jump")
	print("[dive] up     sub=%s depth=%.2f can_board=%s" % [
			w.get("submerged"), w.get("swim_depth"), w.get("can_board")])
	await _shot(dir, "dive5_surface")

	# Swim back to her and take hold. Aim at the ladder itself and keep aiming:
	# she is under way and the sea is carrying you, so a heading taken once is
	# a heading that is wrong two seconds later.
	rig.set("pitch", -0.1)
	Input.action_press("boat_forward")
	var cam: Camera3D = rig.get("_cam")
	for i in 40:
		var lw: Vector3 = boat.to_global(Vector3(
				float(boat.SEA_LADDER_X), 0.1, float(boat.SEA_LADDER_Z) + 0.4))
		var d: Vector3 = lw - cam.global_position
		rig.set("yaw", atan2(-d.x, -d.z))
		if w.get("can_board") == true:
			break
		await get_tree().create_timer(0.3).timeout
	Input.action_release("boat_forward")
	print("[dive] at hull can_board=%s pos=%.2v" % [w.get("can_board"), w.get("pos")])
	if w.get("can_board"):
		w.call("grab_sea_ladder", boat)
	await get_tree().create_timer(0.6).timeout
	rig.set("yaw", atan2(-aft.x, -aft.z))
	rig.set("pitch", -0.25)
	await get_tree().create_timer(0.4).timeout
	print("[dive] regrab ladder=%s pos=%.2v" % [w.get("on_sea_ladder"), w.get("pos")])
	await _shot(dir, "dive6_regrab")

	Input.action_press("boat_forward")
	await get_tree().create_timer(4.5).timeout
	Input.action_release("boat_forward")
	print("[dive] aboard ladder=%s floor=%s pos=%.2v" % [
			w.get("on_sea_ladder"), w.get("on_floor"), w.get("pos")])
	await _shot(dir, "dive7_aboard")
	get_tree().quit()


func _walk_aft(rig: Node3D) -> void:
	await get_tree().create_timer(3.2).timeout
	rig.get("_walker").call("spawn_at", Vector3(0.0, 2.93, 2.6))


func _turn_test(dir: String) -> void:
	## Hold the helm hard over and photograph the left hand three times mid-turn
	## — before, during and after a re-grip.
	await get_tree().create_timer(2.0).timeout
	Input.action_press("boat_left")
	for i in 3:
		await get_tree().create_timer(0.55).timeout
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/turn_%d.png" % [dir, i])
		print("turn shot ", i)
	get_tree().quit()


func _process(_delta: float) -> void:
	if _look_rig == null:
		return
	if _eye_local != Vector3.INF and _look_boat != null:
		# The inspection tripod rides the boat: a world-fixed camera in a seaway
		# has the subject roll out from under it between two consecutive shots.
		(_look_rig.get("_cam") as Camera3D).global_position = \
				_look_boat.get_global_transform_interpolated() * _eye_local
	if _look_at_target == "":
		return
	var goal := Vector3.ZERO
	match _look_at_target:
		"telegraph":
			var t: Node3D = _look_boat.throttle_lever()
			goal = t.global_transform * Vector3(0.0, 0.31, 0.0)
		"helm":
			goal = (_look_boat.helm_wheel() as Node3D).global_position
		"radar":
			goal = (_look_boat.radar_housing() as Node3D).global_position
		"sounder":
			goal = (_look_boat.sounder_housing() as Node3D).global_position
		"engine":
			goal = _look_boat.to_global(Vector3(-1.05, 1.30, 2.16))
		"bow":
			goal = _look_boat.to_global(Vector3(0.0, 0.4, -4.6))
		"ladder":
			goal = _look_boat.to_global(Vector3(0.72, 0.30, 5.86))
		"stove":
			goal = _look_boat.to_global(Vector3(1.28, 0.95, 4.10))
		"locker":
			goal = _look_boat.to_global(Vector3(-1.44, 1.40, 0.36))
		"stairs":
			goal = _look_boat.to_global(Vector3(-1.10, 1.65, 2.30))
		"stairfoot":
			goal = _look_boat.to_global(Vector3(-1.10, 1.00, 3.60))
		"hawse":
			goal = _look_boat.to_global(Vector3(0.0, 0.30, -3.02))
		"rail":
			goal = _look_boat.to_global(Vector3(1.88, 1.72, -2.20))
		"fusebox":
			goal = _look_boat.to_global(Vector3(1.30, 3.72, 1.54))
		_:
			return
	var cam: Camera3D = _look_rig.get("_cam")
	var d: Vector3 = goal - cam.global_position
	_look_rig.set("yaw", atan2(-d.x, -d.z))
	_look_rig.set("pitch", asin(clampf(d.normalized().y, -1.0, 1.0)))


func _probe_hands(rig: Node3D, boat: RigidBody3D) -> void:
	await get_tree().create_timer(2.5).timeout
	var arms: Node = rig.get("_arms")
	arms.call("debug_frames", 3)
	await get_tree().create_timer(0.3).timeout
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
	for a in OS.get_cmdline_user_args():
		if a == "--late":
			await get_tree().create_timer(4.0).timeout
			break
	var img := get_viewport().get_texture().get_image()
	img.save_png(_screenshot_path)
	print("screenshot saved: ", _screenshot_path)
	get_tree().quit()


func _as_f(v: Variant) -> float:
	if typeof(v) == TYPE_FLOAT:
		return v
	if typeof(v) == TYPE_INT:
		return float(v)
	return 0.0
