extends Node3D
## Wires the scene together and registers input actions in code
## (no hard-coded keys elsewhere; rebindable via InputMap).

const HandGripMap := preload("res://scripts/hands/grip_map.gd")
const HeldObjectFramer := preload("res://scripts/hands/held_object_framer.gd")

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
	# Body-worn deck bag: one press brings it round, the next shoulders it.
	_add_action("backpack", [KEY_I])
	# Once the bag is in the lap, the arrow keys move the physical pointing
	# finger between its four loops. They intentionally share keys with walking;
	# boat_camera consumes them while the bag has focus.
	_add_action("bag_previous", [KEY_LEFT, KEY_UP])
	_add_action("bag_next", [KEY_RIGHT, KEY_DOWN])
	_add_mouse_action("knife_attack", MOUSE_BUTTON_LEFT)
	_add_mouse_action("rifle_fire", MOUSE_BUTTON_LEFT)
	_add_mouse_action("rifle_aim", MOUSE_BUTTON_RIGHT)
	_add_action("rifle_reload", [KEY_R])
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


func _add_mouse_action(action: String, button: MouseButton) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
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
		elif arg.begins_with("--grip-test="):
			_grip_test(rig, boat, arg.get_slice("=", 1))
		elif arg.begins_with("--fusebox-test="):
			_fusebox_grip_test(rig, boat, arg.get_slice("=", 1))
		elif arg == "--grasp-planner-test":
			_grasp_planner_test(rig, boat)
		elif arg == "--interaction-contract-test":
			_interaction_contract_test()
		elif arg == "--interaction-action-test":
			_interaction_action_test(boat)
		elif arg == "--input-interaction-test":
			_input_interaction_test(rig, boat)
		elif arg == "--catalog-integrity-test":
			_catalog_integrity_test(rig, boat)
		elif arg == "--held-framing-test":
			_held_framing_test(rig, boat)
		elif arg == "--helm-driver-test":
			_helm_driver_test(rig, boat)
		elif arg == "--pull-radar":
			_pull_radar(rig)
		elif arg == "--pull-sounder":
			_pull_device(rig, "sounder")
		elif arg == "--hold-radio":
			_hold_radio(boat)
		elif arg == "--open-bag":
			_open_bag_later(rig)
		elif arg == "--bag-take-shot":
			_bag_take_shot(rig)
		elif arg == "--bag-return-shot":
			_bag_return_shot(rig)
		elif arg == "--bag-cycle-test":
			_bag_cycle_test(rig, boat)
		elif arg == "--bag-item-test":
			_bag_item_test(rig, boat)
		elif arg == "--knife-test":
			_knife_test(rig, boat)
		elif arg.begins_with("--knife-shot="):
			_knife_shot(rig, boat, arg.get_slice("=", 1))
		elif arg == "--rifle-test":
			_rifle_test(rig, boat)
		elif arg.begins_with("--rifle-shot="):
			_rifle_shot(rig, boat, arg.get_slice("=", 1))
		elif arg == "--probe-engine":
			_probe_engine(boat)
		elif arg == "--drift-test":
			_drift_test(boat)
		elif arg == "--walk-aft":
			_walk_aft(rig)
		elif arg.begins_with("--walk-hand-shot="):
			_walk_hand_shot(rig, arg.get_slice("=", 1))
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
		elif arg.begins_with("--ocean-test="):
			_ocean_test(rig, boat, arg.get_slice("=", 1))
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


func _grip_test(rig: Node3D, boat: RigidBody3D, dir: String) -> void:
	## Stand at the helm and E every instrument a hand should meet. Prints
	## which arm took it and how far the wrist missed the grip, then a frame.
	if not dir.is_absolute_path():
		dir = ProjectSettings.globalize_path("res://" + dir.trim_prefix("res://"))
	DirAccess.make_dir_recursive_absolute(dir)
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
	w.call("spawn_at", boat.HELM_STAND)
	var cam: Camera3D = rig.get("_cam")
	var arms: Node = rig.get("_arms")
	arms.set("boat", boat)
	var hr: Node = arms.get("rig")
	var contact_ids: Array[String] = []
	var record_contact := func(contact_id: String) -> void:
		contact_ids.append(contact_id)
	arms.connect("action_contact", record_contact)
	var cases: Array = [
		["radar", Vector3(0.76, 2.91, 0.64)],
		["sounder", Vector3(0.76, 2.91, 0.64)],
		["ignition", Vector3(0.12, 2.91, 0.52)],
		["radio", Vector3(1.10, 2.91, 0.72)],
		# User-facing assisted reach: still works from the wheelhouse centre rather
		# than requiring the exact numerical test stance beside the panel.
		["fusebox", Vector3(0.0, 2.91, 1.10)],
		["sw_cabin", Vector3(0.66, 2.91, 1.54)],
		["fu_cabin", Vector3(0.72, 2.91, 1.56)],
		["door_wh", Vector3(-0.36, 2.91, 3.52)],
		["door_fwd", Vector3(0.05, 0.63, -0.02)],
		["door_aft", Vector3(0.05, 0.63, 4.28)],
		["stove", Vector3(0.82, 0.63, 3.80)],
		["locker", Vector3(-0.78, 0.63, 0.82)],
		["door_eng", Vector3(-0.10, 0.63, 2.54)],
		# Stand beside the crank, not at the outer edge of its interaction sphere;
		# its hand contact is offset to starboard from the drum centre.
		["windlass", Vector3(0.0, 0.58, -2.82)],
	]
	for c: Array in cases:
		var id: String = c[0]
		var device: Node3D = arms.call("_device_of", id) as Node3D
		if device == null:
			print("[grip] %s  CIHAZ YOK" % id)
			continue
		w.call("spawn_at", c[1])
		await get_tree().create_timer(0.35).timeout
		for _i in 5:
			var d: Vector3 = device.global_position - cam.global_position
			if d.length_squared() > 1e-6:
				d = d.normalized()
				rig.set("yaw", atan2(-d.x, -d.z))
				rig.set("pitch", asin(clampf(d.y, -1.0, 1.0)))
			await get_tree().create_timer(0.08).timeout
		var offered: bool = bool(arms.call("can_offer", id))
		var contacts_before := contact_ids.count(id)
		var accepted: bool = bool(arms.call("notify_use", id, true))
		if offered != accepted:
			push_error("reach promise mismatch for %s: offered=%s accepted=%s" % [
					id, offered, accepted])
		var started_side := ""
		var started_claim: Dictionary = arms.get("_claim")
		if str(started_claim.get("L", "")) == id:
			started_side = "L"
		elif str(started_claim.get("R", "")) == id:
			started_side = "R"
		if not accepted:
			for eval_side in ["L", "R"]:
				var fail_ev: Dictionary = arms.call("_grip_evaluation", eval_side, id)
				var fail_plan: Dictionary = arms.call("_planned_candidate",
						eval_side, id, float(arms.MAX_REACH_ASSIST))
				print("[grip-eval] %s/%s reach=%s left=%.3f elbow=%.1f wrist=%.1f twist=%.1f" % [
					id, eval_side, fail_ev.get("reachable", false),
					float(fail_ev.get("leftover", -1.0)),
					rad_to_deg(float(fail_ev.get("elbow_angle", 0.0))),
					rad_to_deg(float(fail_ev.get("wrist_break", 0.0))),
					rad_to_deg(float(fail_ev.get("palm_twist", 0.0)))])
				print("  plan blocked=%s load=%.2f quality=%.2f" % [
						fail_plan.get("path_blocked", false),
						float(fail_plan.get("load_cost", INF)),
						float(fail_plan.get("quality", 0.0))])
		await get_tree().create_timer(0.50).timeout
		var action_name := str(HandGripMap.spec_for(id).get("action", ""))
		if accepted and action_name != "" and contact_ids.count(id) <= contacts_before:
			push_error("%s was accepted but never emitted hand contact" % id)
		if id == "ignition" and accepted and int(boat.get("engine")) == 0:
			push_error("ignition hand reached the key but did not start the engine action")
		var tested_body_lean: Vector3 = rig.get("_reach_body_lean")
		if id in ["fusebox", "windlass"] and tested_body_lean.length() < 0.06:
			push_error("%s was assisted without visible upper-body travel" % id)
		if id == "fusebox" and not bool(boat.get("fusebox_open")):
			push_error("fusebox gesture reached contact but did not open the lid")
		if id == "windlass":
			var tested_tackle: Node = boat.get("tackle")
			if tested_tackle == null or int(tested_tackle.get("state")) == 0:
				push_error("windlass gesture reached contact but did not start the anchor")
		var claim: Dictionary = arms.get("_claim")
		var side := ""
		if str(claim.get("L", "")) == id:
			side = "L"
		elif str(claim.get("R", "")) == id:
			side = "R"
		var measured_side: String = side if side != "" else started_side
		var g: Node3D = device.get_node_or_null("Grip_" + (measured_side \
				if measured_side != "" else "R"))
		var look: Vector3 = g.global_position if g != null else device.global_position
		if DisplayServer.get_name() != "headless":
			for _j in 4:
				var aim: Vector3 = look - cam.global_position
				if aim.length_squared() > 1e-6:
					aim = aim.normalized()
					rig.set("yaw", atan2(-aim.x, -aim.z))
					# Hands live in the lower third; look a little under the grip
					# or the shot is the horizon and a mast.
					rig.set("pitch", asin(clampf(aim.y, -1.0, 1.0)) - 0.22)
				await get_tree().create_timer(0.08).timeout
		var ev: Dictionary = arms.call("_grip_evaluation", measured_side \
				if measured_side != "" else "R", id)
		var err := -1.0
		if side != "" and g != null:
			err = (hr.call("wrist_global", side) as Transform3D).origin.distance_to(
					g.global_position)
		print("[grip] %-8s side=%-2s live=%s leftover=%.3f reachable=%s wrist_err=%.3f claim=%s" % [
				id, measured_side if measured_side != "" else "-", side != "",
				float(ev.get("leftover", -1.0)), ev.get("reachable", false),
				err, claim])
		await _shot(dir, "grip_%s" % id)
		if side != "":
			arms.call("_release", side)
		if id == "radio":
			boat.set("radio_held", false)
		if id == "radar" or id == "sounder":
			boat.call("set_%s_pull" % id, 0.0)
		await get_tree().create_timer(0.35).timeout
	get_tree().quit()


func _fusebox_grip_test(rig: Node3D, boat: RigidBody3D, dir: String) -> void:
	## Serial fuse-lid contract test. Three ordinary wheelhouse stances exercise
	## closed contact, the moving hinge, and release. The assertion is against
	## the procedural brass latch itself, not the old duplicated coordinates.
	if not dir.is_absolute_path():
		dir = ProjectSettings.globalize_path("res://" + dir.trim_prefix("res://"))
	DirAccess.make_dir_recursive_absolute(dir)
	rig.set_mode(1)
	var walker: RefCounted = rig.get("_walker")
	var arms: Node = rig.get("_arms")
	arms.set("boat", boat)
	var hand_rig: Node = arms.get("rig")
	var cam: Camera3D = rig.get("_cam")
	boat.set("helm_engaged", false)
	boat.set("telegraph_engaged", false)
	await get_tree().create_timer(2.0).timeout
	var stances := [
		["centre", Vector3(0.0, 2.91, 1.10)],
		["inboard", Vector3(0.42, 2.91, 1.36)],
		["forward", Vector3(0.20, 2.91, 0.92)],
	]
	for tc: Array in stances:
		boat.set("fusebox_open", false)
		arms.call("_release", "L")
		arms.call("_release", "R")
		walker.call("spawn_at", tc[1])
		await get_tree().create_timer(0.65).timeout
		var lid: Node3D = boat.call("fuse_lid") as Node3D
		var latch_local: Vector3 = boat.call("fuse_latch_local")
		var latch_world: Vector3 = lid.to_global(latch_local)
		for _aim in 6:
			var aim := (latch_world - cam.global_position).normalized()
			rig.set("yaw", atan2(-aim.x, -aim.z))
			rig.set("pitch", asin(clampf(aim.y, -1.0, 1.0)))
			await get_tree().create_timer(0.06).timeout
		var offered: bool = bool(arms.call("can_offer", "fusebox"))
		var accepted: bool = bool(arms.call("notify_use", "fusebox", true))
		if not offered or not accepted:
			push_error("fusebox/%s offer=%s accepted=%s" % [tc[0], offered, accepted])
			continue
		# notify_use records the claim; hands.update stamps the device-local Grip
		# on the following frame, exactly as it does during normal play.
		await get_tree().create_timer(0.03).timeout
		var claim: Dictionary = arms.get("_claim")
		var side := "L" if str(claim.get("L", "")) == "fusebox" else "R"
		var grip: Node3D = lid.get_node_or_null("Grip_" + side)
		if grip == null:
			push_error("fusebox/%s created no grip" % tc[0])
			continue
		var along := float(preload("res://scripts/hands/grip_map.gd").spec_for(
				"fusebox").get("along_fingers", 0.0))
		var palm_local: Vector3 = lid.to_local(grip.global_position)
		var palm_on_lid := absf(palm_local.x) <= 0.14 \
				and palm_local.z >= -0.02 and palm_local.z <= 0.41
		if not palm_on_lid:
			push_error("fusebox/%s palm target outside lid: %s" % [tc[0], palm_local])
		var max_tip_error := 0.0
		var min_palm_error := INF
		var max_wrist_break := 0.0
		var max_palm_twist := 0.0
		var max_elbow := 0.0
		var opened_at := -1.0
		var detached_after := -1.0
		var detach_angle := -1.0
		var elapsed := 0.0
		while elapsed < 0.62:
			await get_tree().create_timer(0.02).timeout
			elapsed += 0.02
			latch_world = lid.to_global(boat.call("fuse_latch_local"))
			var fingertip: Vector3 = grip.global_transform * Vector3(0.0, 0.0, along)
			max_tip_error = maxf(max_tip_error, fingertip.distance_to(latch_world))
			claim = arms.get("_claim")
			var opened := bool(boat.get("fusebox_open"))
			if opened and opened_at < 0.0:
				opened_at = elapsed
			if opened and str(claim.get(side, "")) == "fusebox":
				min_palm_error = minf(min_palm_error,
						(hand_rig.call("palm_global", side) as Vector3).distance_to(
								grip.global_position))
				var live_eval: Dictionary = arms.call("_grip_evaluation", side, "fusebox")
				max_wrist_break = maxf(max_wrist_break,
						float(live_eval.get("wrist_break", 0.0)))
				max_palm_twist = maxf(max_palm_twist,
						float(live_eval.get("palm_twist", 0.0)))
				max_elbow = maxf(max_elbow, float(live_eval.get("elbow_angle", 0.0)))
			elif opened and detached_after < 0.0:
				detached_after = elapsed - opened_at
				detach_angle = absf(lid.rotation.x)
		if max_tip_error > 0.004:
			push_error("fusebox/%s fingertip missed latch by %.3f m" % [
					tc[0], max_tip_error])
		if not bool(boat.get("fusebox_open")):
			push_error("fusebox/%s did not open" % tc[0])
		if not is_finite(min_palm_error) or min_palm_error > 0.035:
			push_error("fusebox/%s solved palm missed grip by %.3f m" % [
					tc[0], min_palm_error])
		if detached_after < 0.04 or detached_after > 0.15:
			push_error("fusebox/%s unnatural detach time %.3f s" % [
					tc[0], detached_after])
		if detach_angle < deg_to_rad(18.0) or detach_angle > deg_to_rad(55.0):
			push_error("fusebox/%s detached at unnatural lid angle %.1f deg" % [
					tc[0], rad_to_deg(detach_angle)])
		if max_wrist_break > deg_to_rad(58.0) or max_palm_twist > deg_to_rad(138.0) \
				or max_elbow > deg_to_rad(165.0):
			push_error("fusebox/%s anatomy wrist=%.1f twist=%.1f elbow=%.1f" % [
					tc[0], rad_to_deg(max_wrist_break), rad_to_deg(max_palm_twist),
					rad_to_deg(max_elbow)])
		print("[fusebox] %-7s hand=%s offered=%s palm_local=%s tip_err=%.4f palm_err=%.4f detach=%.3fs@%.1fdeg wrist=%.1f twist=%.1f elbow=%.1f open=%s" % [
				tc[0], side, offered, palm_local, max_tip_error, min_palm_error,
				detached_after, rad_to_deg(detach_angle), rad_to_deg(max_wrist_break),
				rad_to_deg(max_palm_twist), rad_to_deg(max_elbow), boat.get("fusebox_open")])
		await _shot(dir, "fusebox_%s" % tc[0])
	get_tree().quit()


func _grasp_planner_test(rig: Node3D, boat: RigidBody3D) -> void:
	## Bilateral contract: the object on the player's left must select the left
	## hand even when an old preference asks for right, and vice versa. Each
	## accepted result must contain a fully admissible sampled approach path.
	rig.set_mode(1)
	var arms: Node = rig.get("_arms")
	arms.set("boat", boat)
	boat.set("helm_engaged", false)
	boat.set("telegraph_engaged", false)
	await get_tree().create_timer(2.0).timeout
	var cam: Camera3D = rig.get("_cam")
	var planner := preload("res://scripts/hands/grasp_planner.gd")
	var cases := [
		["player_right_of_object", Vector3(-0.30, -0.20, -0.46), "L", "R"],
		["player_left_of_object", Vector3(0.30, -0.20, -0.46), "R", "L"],
	]
	for tc: Array in cases:
		var contact: Vector3 = cam.global_transform * (tc[1] as Vector3)
		var choice: Dictionary = arms.call("plan_world_grasp", contact,
				Vector3.ZERO, Vector3.ZERO, 0.07, tc[3], 0.10)
		var side := str(choice.get("side", ""))
		if side != str(tc[2]):
			push_error("grasp planner/%s chose %s, expected %s" % [tc[0], side, tc[2]])
		if (choice.get("path", []) as Array).size() != 4:
			push_error("grasp planner/%s did not validate the whole approach" % tc[0])
		var ev: Dictionary = choice.get("end", {})
		var quality: Dictionary = choice.get("quality_breakdown", {})
		for quality_key in ["reach", "cross_body", "elbow", "shoulder",
				"wrist", "torso", "gaze", "load", "path", "quality"]:
			if not quality.has(quality_key):
				push_error("grasp quality omitted '%s'" % quality_key)
		# An equal alternative must not steal the selected hand inside the
		# hysteresis margin.
		var left := choice.duplicate(true)
		left["side"] = "L"
		var right := choice.duplicate(true)
		right["side"] = "R"
		var sticky: Dictionary = planner.choose({"L": left, "R": right},
				float((arms.get("rig") as Node).WRIST_CONE),
				{"L": false, "R": false}, "R", "L", 0.18)
		if str(sticky.get("side", "")) != "L":
			push_error("grasp hysteresis changed hands inside its margin")
		print("[grasp-planner] %-23s hand=%s preferred=%s score=%.3f cross=%.3f elbow=%.1f wrist=%.1f twist=%.1f samples=%d" % [
				tc[0], side, tc[3], float(choice.get("score", INF)),
				float(ev.get("cross", INF)), rad_to_deg(float(ev.get("elbow_angle", 0.0))),
				rad_to_deg(float(ev.get("wrist_break", 0.0))),
				rad_to_deg(float(ev.get("palm_twist", 0.0))),
				(choice.get("path", []) as Array).size()])
	get_tree().quit()


func _interaction_contract_test() -> void:
	## Pure contract test; no hand skeleton or ship fitting is involved.
	var motion := preload("res://scripts/hands/interaction_motion.gd")
	var behavior := preload("res://scripts/hands/interaction_behavior.gd")
	var planner := preload("res://scripts/hands/grasp_planner.gd")
	var device := Node3D.new()
	var hinge := {"type": "hinge", "angle": 0.74,
			"min_time": 0.05, "timeout": 0.15}
	var start: Dictionary = motion.snapshot(device)
	device.rotation.y = 0.37
	var hinge_progress: float = motion.progress(hinge, start, device)
	if not is_equal_approx(hinge_progress, 0.5):
		push_error("hinge motion contract progress %.3f, expected 0.5" % hinge_progress)
	device.rotation = Vector3.ZERO
	var linear := {"type": "linear", "distance": 0.20,
			"direction": Vector3.RIGHT, "min_time": 0.04, "timeout": 0.18}
	start = motion.snapshot(device)
	device.position = Vector3(0.10, 0.0, 0.30)
	var linear_progress: float = motion.progress(linear, start, device)
	if not is_equal_approx(linear_progress, 0.5):
		push_error("linear motion contract progress %.3f, expected 0.5" % linear_progress)
	if motion.should_release(linear, 0.02, 1.0):
		push_error("motion contract ignored minimum contact time")
	if not motion.should_release(linear, 0.05, 1.0):
		push_error("motion contract did not release at completed travel")
	if motion.validation_error(linear) != "":
		push_error("valid linear motion contract was rejected")
	var heavy := {"behavior": "heavy_lift", "span": true, "pose": "power"}
	if is_finite(float(behavior.load_cost(heavy, 1))) \
			or not is_finite(float(behavior.load_cost(heavy, 2))):
		push_error("heavy load contract did not require two hands")
	var unsafe := {"behavior": "crank", "pose": "pinch"}
	if str(behavior.validation_error(unsafe)) == "":
		push_error("high-force fingertip contract was accepted")
	var blocker := AABB(Vector3(-0.1, -0.1, -0.1), Vector3(0.2, 0.2, 0.2))
	var path_entry: float = planner._segment_aabb_entry(
			Vector3(-1.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0), blocker)
	var path_miss: float = planner._segment_aabb_entry(
			Vector3(-1.0, 1.0, 0.0), Vector3(1.0, 1.0, 0.0), blocker)
	if path_entry < 0.40 or path_entry > 0.50 or path_miss >= 0.0:
		push_error("approach collision sweep failed entry/miss contract")
	print("[interaction-motion] hinge=%.3f linear=%.3f minimum=true release=true" % [
			hinge_progress, linear_progress])
	device.free()
	get_tree().quit()


func _interaction_action_test(boat: RigidBody3D) -> void:
	## Gameplay dispatch is tested without a camera, hand skeleton or animation.
	var actions := preload("res://scripts/interaction_action.gd")
	var grips := preload("res://scripts/hands/grip_map.gd")
	boat.set("radio_held", false)
	if not actions.execute(boat, "radio", grips.spec_for("radio")) \
			or not bool(boat.get("radio_held")):
		push_error("radio interaction action failed")
	boat.call("set_radar_pull", 0.0)
	boat.call("set_sounder_pull", 1.0)
	if not actions.execute(boat, "radar", grips.spec_for("radar")) \
			or float(boat.get("radar_pull")) < 0.99 \
			or float(boat.get("sounder_pull")) > 0.01:
		push_error("exclusive rail interaction action failed")
	var stove_before := bool(boat.get("stove_on"))
	if not actions.execute(boat, "stove", grips.spec_for("stove")) \
			or bool(boat.get("stove_on")) == stove_before:
		push_error("toggle interaction action failed")
	boat.set("fusebox_open", false)
	if actions.execute(boat, "sw_cabin", grips.spec_for("sw_cabin")):
		push_error("interaction action bypassed a closed gate")
	var tackle: Node = boat.get("tackle")
	var tackle_before := int(tackle.get("state")) if tackle != null else -1
	if not actions.execute(boat, "windlass", grips.spec_for("windlass")) \
			or tackle == null or int(tackle.get("state")) == tackle_before:
		push_error("child interaction action failed")
	print("[interaction-action] radio=true rail=true toggle=true gate=true child=true")
	get_tree().quit()


func _input_interaction_test(rig: Node3D, boat: RigidBody3D) -> void:
	## Exercise the camera's common player route while the helm mode owns a hand,
	## then require authored contact and the engine mutation. This catches the
	## legacy precedence bug where "leave helm" swallowed ignition use.
	rig.set_mode(1)
	await get_tree().create_timer(2.2).timeout
	boat.set("helm_engaged", true)
	var walker: RefCounted = rig.get("_walker")
	walker.call("spawn_at", Vector3(0.12, 2.91, 0.52))
	var arms: Node = rig.get("_arms")
	var contacts: Array[String] = []
	arms.connect("action_contact", func(id: String) -> void: contacts.append(id))
	if not bool(arms.call("can_offer", "ignition")):
		push_error("input interaction setup could not offer ignition")
	var accepted: bool = bool(rig.call("_start_catalog_interaction", "ignition",
			HandGripMap.spec_for("ignition")))
	if not accepted:
		push_error("camera route rejected offered ignition while helm was engaged")
	await get_tree().create_timer(0.75).timeout
	var finger_report: Dictionary = (arms.get("rig") as Node).call(
			"finger_contact_report", "R")
	if int(finger_report.get("samples", 0)) < 15:
		push_error("finger solver did not evaluate every ignition phalanx")
	if int(finger_report.get("touches", 0)) < 1:
		push_error("ignition grip closed without any phalanx contact")
	if not contacts.has("ignition"):
		push_error("E accepted ignition without reaching hand contact")
	if int(boat.get("engine")) == 0:
		push_error("ignition contact did not execute its gameplay action")
	print("[input-interaction] offered=true routed=%s contact=%s engine=%s fingers=%d touch=%d penetration=%d nearest=%.3f quality=%.2f" % [
			accepted,
			contacts.has("ignition"), boat.get("engine"),
			int(finger_report.get("samples", 0)),
			int(finger_report.get("touches", 0)),
			int(finger_report.get("penetrations", 0)),
			float(finger_report.get("nearest", INF)),
			float(finger_report.get("quality", 0.0))])
	get_tree().quit()


func _catalog_integrity_test(rig: Node3D, boat: RigidBody3D) -> void:
	## Every advertised INTERACT entry must declare its physical behavior and
	## either a live grip device or an explicit full-body special driver.
	var arms: Node = rig.get("_arms")
	arms.set("boat", boat)
	var seen := {}
	var authored := 0
	var special := 0
	for item: Dictionary in boat.INTERACT:
		var id := str(item.get("id", ""))
		if id == "" or seen.has(id):
			push_error("interaction catalog has empty/duplicate id '%s'" % id)
			continue
		seen[id] = true
		var spec := HandGripMap.spec_for(id)
		if spec.is_empty():
			push_error("INTERACT '%s' bypasses GripMap" % id)
			continue
		var error := HandGripMap.validation_error(spec)
		if error != "":
			push_error("INTERACT '%s' has invalid contract: %s" % [id, error])
		var kind := int(spec.get("kind", HandGripMap.Kind.GESTURE))
		if kind == HandGripMap.Kind.SPECIAL:
			special += 1
			continue
		authored += 1
		if arms.call("_device_of", id) == null:
			push_error("INTERACT '%s' has no live grip device" % id)
		if not (arms.get("rig") as Node).call("has_pose", str(spec.get("pose", ""))):
			push_error("INTERACT '%s' has no finger pose" % id)
		if kind == HandGripMap.Kind.GESTURE and str(spec.get("action", "")) == "":
			push_error("gesture '%s' can reach contact without an action" % id)
	print("[catalog-integrity] total=%d authored=%d special=%d complete=true" % [
			seen.size(), authored, special])
	get_tree().quit()


func _helm_driver_test(rig: Node3D, boat: RigidBody3D) -> void:
	## Numeric helm contract: both hands choose their own upper sector and a
	## hard-over wheel produces a lifted, open-finger re-grip that seats again.
	rig.set_mode(1)
	var walker: RefCounted = rig.get("_walker")
	walker.call("spawn_at", boat.HELM_STAND)
	var arms: Node = rig.get("_arms")
	arms.set("boat", boat)
	await get_tree().create_timer(2.0).timeout
	var driver: RefCounted = arms.get("_helm_driver")
	var wheel: Node3D = boat.call("helm_wheel") as Node3D
	for side: String in ["L", "R"]:
		var angle: float = driver.call("pick_angle", side, boat, wheel)
		var option: Dictionary = driver.call("candidate", side, angle, boat, wheel)
		if float(option.get("up", -1.0)) < -0.16 \
				or float(option.get("own_side", -1.0)) < -0.12:
			push_error("helm/%s selected an underside or cross-body grip" % side)
	var grip: Node3D = arms.call("_grip_node", "helm", "L") as Node3D
	driver.call("reset", "L")
	driver.call("seat", "L", boat, wheel, grip)
	var original_rotation := wheel.rotation.z
	wheel.rotation.z += 1.10
	driver.call("ride", "L", 0.001, boat, wheel, grip)
	var minimum_hold := 1.0
	var maximum_lift := 0.0
	for _i in 20:
		var hold: float = driver.call("ride", "L", 0.02, boat, wheel, grip)
		minimum_hold = minf(minimum_hold, hold)
		maximum_lift = maxf(maximum_lift, absf(grip.position.z))
	wheel.rotation.z = original_rotation
	var seated_radius := Vector2(grip.position.x, grip.position.y).length()
	if minimum_hold > 0.25 or maximum_lift < 0.03:
		push_error("helm regrip did not open and lift: hold=%.2f lift=%.3f" % [
				minimum_hold, maximum_lift])
	if absf(seated_radius - 0.29) > 0.004 or absf(grip.position.z) > 0.004:
		push_error("helm regrip did not reseat on rim: radius=%.3f z=%.3f" % [
				seated_radius, grip.position.z])
	print("[helm-driver] sectors=true min_hold=%.2f lift=%.3f seated=%.3f" % [
			minimum_hold, maximum_lift, seated_radius])
	get_tree().quit()


func _pull_radar(rig: Node3D) -> void:
	_pull_device(rig, "radar")


func _use_later(boat: RigidBody3D, ids: String) -> void:
	# Mirrors the in-game E flow: input starts the reach; the hand commits the
	# boat action at contact. Comma-separated ids wait for the full gesture so a
	# lid is open before the next finger enters its well.
	await get_tree().create_timer(2.0).timeout
	var arms: Node = $CameraRig.get("_arms")
	arms.set("boat", boat)
	for id in ids.split(","):
		var accepted: bool = bool(arms.call("notify_use", id))
		print("[use] %s accepted=%s" % [id, accepted])
		if not accepted:
			for side in ["L", "R"]:
				var ev: Dictionary = arms.call("_grip_evaluation", side, id)
				print("  %s reach=%s left=%.3f elbow=%.1f raise=%.2f wrist=%.1f twist=%.1f" % [
					side, ev.get("reachable", false), float(ev.get("leftover", -1.0)),
					rad_to_deg(float(ev.get("elbow_angle", 0.0))),
					float(ev.get("shoulder_raise", 0.0)),
					rad_to_deg(float(ev.get("wrist_break", 0.0))),
					rad_to_deg(float(ev.get("palm_twist", 0.0)))])
		await get_tree().create_timer(1.0).timeout


func _pull_device(rig: Node3D, id: String) -> void:
	await get_tree().create_timer(1.5).timeout
	var arms: Node = rig.get("_arms")
	arms.set("boat", $Boat)
	arms.call("notify_use", id)


func _hold_radio(boat: RigidBody3D) -> void:
	await get_tree().create_timer(1.5).timeout
	boat.set("radio_held", true)


func _open_bag_later(rig: Node3D) -> void:
	## Repeatable visual review: enter first person, remove the developer panel,
	## then let the exact I-path settle before the generic screenshot timer fires.
	await get_tree().create_timer(0.45).timeout
	rig.call("set_mode", 1)
	var panel: Node = get_tree().get_first_node_in_group("ui_panel")
	if panel != null:
		var panel_view: CanvasItem = panel.get("_panel") as CanvasItem
		if panel_view != null:
			panel_view.visible = false
	await get_tree().create_timer(0.20).timeout
	rig.call("set_bag_open", true)


func _bag_take_shot(rig: Node3D) -> void:
	## Visual route for the second half of the loop: select slot one, take its
	## real model, and let the bag finish travelling back to the shoulder.
	await get_tree().create_timer(0.45).timeout
	rig.call("set_mode", 1)
	var panel: Node = get_tree().get_first_node_in_group("ui_panel")
	if panel != null:
		var panel_view: CanvasItem = panel.get("_panel") as CanvasItem
		if panel_view != null:
			panel_view.visible = false
	rig.set("_bag_selected", 0)
	await get_tree().create_timer(0.20).timeout
	rig.call("set_bag_open", true)
	await get_tree().create_timer(0.90).timeout
	rig.call("_activate_bag_selection")


func _bag_return_shot(rig: Node3D) -> void:
	## Leaves the item hovering at the empty loop immediately before E places it.
	await get_tree().create_timer(0.45).timeout
	rig.call("set_mode", 1)
	var panel: Node = get_tree().get_first_node_in_group("ui_panel")
	if panel != null:
		var panel_view: CanvasItem = panel.get("_panel") as CanvasItem
		if panel_view != null:
			panel_view.visible = false
	rig.set("_bag_selected", 0)
	await get_tree().create_timer(0.20).timeout
	rig.call("set_bag_open", true)
	await get_tree().create_timer(0.90).timeout
	rig.call("_activate_bag_selection")
	await get_tree().create_timer(0.65).timeout
	rig.call("set_bag_open", true)


func _bag_cycle_test(rig: Node3D, boat: RigidBody3D) -> void:
	rig.call("set_mode", 1)
	var panel: Node = get_tree().get_first_node_in_group("ui_panel")
	if panel != null:
		var panel_view: CanvasItem = panel.get("_panel") as CanvasItem
		if panel_view != null:
			panel_view.visible = false
	await get_tree().create_timer(0.65).timeout
	var opened: bool = bool(rig.call("set_bag_open", true))
	await get_tree().create_timer(0.95).timeout
	var bag: Node3D = boat.call("deck_bag_node") as Node3D
	var arms: Node = rig.get("_arms")
	var claims: Dictionary = arms.get("_claim")
	var focus_open := float(rig.get("_bag_focus"))
	var hand_open := str(claims.get("L", "")) == "deckbag"
	var visible_open := bag != null and bag.visible
	var grip_eval: Dictionary = arms.call("_grip_evaluation", "L", "deckbag")
	var wrist_break := rad_to_deg(float(grip_eval.get("wrist_break", PI)))
	var closed: bool = bool(rig.call("set_bag_open", false))
	await get_tree().create_timer(0.78).timeout
	claims = arms.get("_claim")
	var focus_closed := float(rig.get("_bag_focus"))
	var hand_closed := str(claims.get("L", "")) != "deckbag"
	var hidden_closed := bag != null and not bag.visible
	var complete := opened and closed and focus_open > 0.99 and hand_open \
			and visible_open and focus_closed < 0.01 and hand_closed and hidden_closed
	complete = complete and wrist_break < 3.0
	print("[bag-cycle] open=%.2f hand=%s visible=%s wrist=%.1fdeg natural_f=%s natural_p=%s close=%.2f released=%s hidden=%s complete=%s" % [
			focus_open, hand_open, visible_open, wrist_break,
			str(grip_eval.get("fingers", Vector3.ZERO)),
			str(grip_eval.get("palm", Vector3.ZERO)), focus_closed, hand_closed,
			hidden_closed, complete])
	if not complete:
		push_error("deck bag shoulder cycle incomplete")
	get_tree().quit()


func _bag_item_test(rig: Node3D, boat: RigidBody3D) -> void:
	rig.call("set_mode", 1)
	var panel: Node = get_tree().get_first_node_in_group("ui_panel")
	if panel != null:
		var panel_view: CanvasItem = panel.get("_panel") as CanvasItem
		if panel_view != null:
			panel_view.visible = false
	rig.set("_bag_selected", 0)
	await get_tree().create_timer(0.35).timeout
	rig.call("set_bag_open", true)
	await get_tree().create_timer(0.95).timeout
	var bag: Node3D = boat.call("deck_bag_node") as Node3D
	var arms: Node = rig.get("_arms")
	var hand_rig: Node = arms.get("rig")
	var pointer_report: Dictionary = arms.get("_bag_hand_report")
	var pointer_wrist := rad_to_deg(float(pointer_report.get("wrist_break", PI)))
	var pointer_target := bag.call("slot_pointer_target", 0) as Node3D
	var index_tip := hand_rig.call("digit_tip_global", "R", "index") as Vector3
	var pointer_tip_error := index_tip.distance_to(pointer_target.global_position)
	var hand_poses: Dictionary = hand_rig.get("_pose")
	var pointer_ok := str(arms.get("_bag_hand_mode")) == "point" \
			and str(hand_poses.get("R", "")) == "point" \
			and pointer_wrist < 12.0 and pointer_tip_error < 0.030
	var taken := bool(rig.call("_activate_bag_selection"))
	await get_tree().create_timer(0.78).timeout
	var active_after_take := bag.call("active_item_node") as Node3D
	var closed_after_take := not bool(rig.get("_bag_open"))
	var empty_after_take := not bool(bag.call("slot_occupied", 0))
	var hold_after_take := str(arms.get("_bag_hand_mode")) == "hold"
	var take_ok := taken and active_after_take != null \
			and empty_after_take and closed_after_take and hold_after_take
	rig.call("set_bag_open", true)
	await get_tree().create_timer(0.95).timeout
	var preview_ok := int(rig.get("_bag_selected")) == 0 \
			and int(bag.get("_preview_slot")) == 0
	var placed := bool(rig.call("_activate_bag_selection"))
	await get_tree().create_timer(0.16).timeout
	var place_ok := placed and bag.call("active_item_node") == null \
			and bool(bag.call("slot_occupied", 0)) \
			and str(arms.get("_bag_hand_mode")) == "point"
	var complete := pointer_ok and take_ok and preview_ok and place_ok
	print("[bag-item] point=%s wrist=%.1fdeg tip=%.4f take=%s closes=%s empty=%s hold=%s preview=%s place=%s restored=%s complete=%s" % [
			pointer_ok, pointer_wrist, pointer_tip_error,
			taken, closed_after_take, empty_after_take,
			hold_after_take, preview_ok, placed, place_ok, complete])
	if not complete:
		push_error("deck bag take/return cycle incomplete")
	get_tree().quit()


func _knife_test(rig: Node3D, boat: RigidBody3D) -> void:
	## Full player path: point at slot three, take the imported model, verify its
	## palm weld, cut once, then return that same node to the empty webbing.
	rig.call("set_mode", 1)
	var panel: Node = get_tree().get_first_node_in_group("ui_panel")
	if panel != null:
		var panel_view: CanvasItem = panel.get("_panel") as CanvasItem
		if panel_view != null:
			panel_view.visible = false
	rig.set("_bag_selected", 2)
	await get_tree().create_timer(0.35).timeout
	rig.call("set_bag_open", true)
	await get_tree().create_timer(0.95).timeout
	var bag: Node3D = boat.call("deck_bag_node") as Node3D
	var slot_label := str(bag.call("slot_label", 2))
	var taken := bool(rig.call("_activate_bag_selection"))
	await get_tree().create_timer(0.82).timeout
	var active := bag.call("active_item_node") as Node3D
	var same_model := active != null \
			and str(active.get_meta("item_kind", "")) == "utility_knife" \
			and int(active.call("model_mesh_count")) == 4
	var arms: Node = rig.get("_arms")
	var report: Dictionary = arms.get("_bag_hand_report")
	var wrist := rad_to_deg(float(report.get("wrist_break", PI)))
	var hand_rig: Node = arms.get("rig")
	var hand_poses: Dictionary = hand_rig.get("_pose")
	var palm_grip := str(hand_poses.get("R", "")) == "knife_grip"
	var finger_contact: Dictionary = hand_rig.call("finger_contact_report", "R")
	var handle_bounds: AABB = active.call("grip_contact_bounds") as AABB
	var contact_ok := int(finger_contact.get("touches", 0)) >= 8 \
			and int(finger_contact.get("penetrations", 1)) == 0 \
			and float(finger_contact.get("nearest", -1.0)) >= 0.0
	var weld: Dictionary = hand_rig.call("held_attachment_report", "R")
	var welded := bool(weld.get("welded", false)) \
			and float(weld.get("position_error", 1.0)) < 0.001 \
			and float(weld.get("angle_error", 1.0)) < deg_to_rad(0.2)
	var tip := active.call("blade_tip_node") as Node3D if active != null else null
	var enlarged := tip != null and tip.position.length() > 0.25
	var sound_removed := active != null \
			and active.find_child("KnifeWhoosh", true, false) == null
	var tip_start := tip.global_position if tip != null else Vector3.ZERO
	var hit_target := StaticBody3D.new()
	hit_target.name = "KnifeSweepTestTarget"
	var hit_shape := CollisionShape3D.new()
	var hit_wall := BoxShape3D.new()
	hit_wall.size = Vector3(1.5, 1.5, 0.025)
	hit_shape.shape = hit_wall
	hit_target.add_child(hit_shape)
	add_child(hit_target)
	var test_camera := rig.get("_cam") as Camera3D
	hit_target.global_transform = test_camera.global_transform \
			* Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -0.55))
	await get_tree().physics_frame
	var max_travel := 0.0
	var max_render_weld := 0.0
	var sweep_frames := 0
	var lmb_bound := false
	for input_event in InputMap.action_get_events("knife_attack"):
		if input_event is InputEventMouseButton \
				and (input_event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			lmb_bound = true
	var attack_event := InputEventAction.new()
	attack_event.action = "knife_attack"
	attack_event.pressed = true
	rig.call("_unhandled_input", attack_event)
	var attacked := bool(active.call("is_attacking"))
	for _i in 34:
		await get_tree().create_timer(0.018).timeout
		if tip != null:
			max_travel = maxf(max_travel, tip.global_position.distance_to(tip_start))
		var moving_weld: Dictionary = hand_rig.call("held_attachment_report", "R")
		max_render_weld = maxf(max_render_weld,
				float(moving_weld.get("render_position_error", 0.0)))
		if not (bag.call("active_knife_sweep") as Dictionary).is_empty():
			sweep_frames += 1
	await get_tree().create_timer(0.22).timeout
	var hit_registered := bool(active.call("hit_latched"))
	rig.set("_bag_selected", 2)
	var reopened := bool(rig.call("set_bag_open", true))
	await get_tree().create_timer(0.95).timeout
	var return_frame := bool(bag.get("_knife_hand_target").get_meta(
			"authored_grip_frame", false)) \
			and str(arms.get("_bag_hand_mode")) == "knife"
	var placed := bool(rig.call("_activate_bag_selection"))
	await get_tree().create_timer(0.10).timeout
	var release_mode := str(arms.get("_bag_hand_mode")) == "knife_release"
	var release_opening := float(bag.get("_knife_hand_target").get_meta(
			"grip_closure", 1.0)) < 0.98
	await get_tree().create_timer(0.30).timeout
	var restored := placed and bag.call("active_item_node") == null \
			and bool(bag.call("slot_occupied", 2)) \
			and str(arms.get("_bag_hand_mode")) == "point"
	var complete := slot_label == "Utility knife" and taken and same_model \
			and wrist < 1.0 \
			and palm_grip and contact_ok and welded and enlarged and sound_removed \
			and lmb_bound and attacked and max_travel > 0.12 \
			and hit_registered and return_frame and release_mode and release_opening \
			and reopened and restored
	print("[knife] label=%s take=%s imported=%s enlarged=%s palm=%s bounds=%s..%s contacts=%d penetrations=%d nearest=%.4f silent=%s wrist=%.2fdeg weld=%s pos_err=%.5f render_err=%.5f lmb=%s attack=%s travel=%.3fm sweeps=%d hit=%s return_frame=%s release=%s opening=%s place=%s restored=%s complete=%s" % [
			slot_label, taken, same_model, enlarged, palm_grip,
			handle_bounds.position, handle_bounds.end,
			int(finger_contact.get("touches", 0)),
			int(finger_contact.get("penetrations", 0)),
			float(finger_contact.get("nearest", -1.0)),
			sound_removed, wrist, welded,
			float(weld.get("position_error", -1.0)), max_render_weld,
			lmb_bound, attacked, max_travel,
			sweep_frames, hit_registered, return_frame, release_mode, release_opening,
			placed, restored, complete])
	if not complete:
		push_error("utility knife take/attack/return contract incomplete")
	get_tree().quit()


func _knife_shot(rig: Node3D, boat: RigidBody3D, dir: String) -> void:
	## Three deterministic frames for visual review: webbing, settled grip and
	## the fast middle of the diagonal cut.
	await get_tree().create_timer(0.35).timeout
	rig.call("set_mode", 1)
	var panel: Node = get_tree().get_first_node_in_group("ui_panel")
	if panel != null:
		var panel_view: CanvasItem = panel.get("_panel") as CanvasItem
		if panel_view != null:
			panel_view.visible = false
	rig.set("_bag_selected", 2)
	rig.call("set_bag_open", true)
	await get_tree().create_timer(0.95).timeout
	await _shot(dir, "knife0_bag")
	rig.call("_activate_bag_selection")
	await get_tree().create_timer(0.82).timeout
	await _shot(dir, "knife1_held")
	var bag: Node3D = boat.call("deck_bag_node") as Node3D
	bag.call("begin_active_attack")
	await get_tree().create_timer(0.20).timeout
	await _shot(dir, "knife2_slash")
	await get_tree().create_timer(0.52).timeout
	rig.set("_bag_selected", 2)
	rig.call("set_bag_open", true)
	await get_tree().create_timer(0.95).timeout
	await _shot(dir, "knife3_return")
	rig.call("_activate_bag_selection")
	await get_tree().create_timer(0.10).timeout
	await _shot(dir, "knife4_release")
	await get_tree().create_timer(0.30).timeout
	await _shot(dir, "knife5_stowed")
	get_tree().quit()


func _rifle_test(rig: Node3D, boat: RigidBody3D) -> void:
	## Dedicated sling -> two-hand shoulder -> sights -> animated shot -> sling.
	## The contract includes geometric sight alignment and exclusive-slot rules,
	## not merely the presence of a model node.
	rig.call("set_mode", 1)
	var panel: Node = get_tree().get_first_node_in_group("ui_panel")
	if panel != null:
		var panel_view: CanvasItem = panel.get("_panel") as CanvasItem
		if panel_view != null:
			panel_view.visible = false
	rig.set("_bag_selected", 4)
	await get_tree().create_timer(0.35).timeout
	rig.call("set_bag_open", true)
	await get_tree().create_timer(0.95).timeout
	var bag: Node3D = boat.call("deck_bag_node") as Node3D
	var slot_label := str(bag.call("slot_label", 4))
	var rifle_slot_node := bag.call("slot_target", 4) as Node3D
	var quick_slot_node := bag.call("slot_target", 2) as Node3D
	var rifle_slot_local := bag.to_local(rifle_slot_node.global_position)
	var rifle_below_tools := rifle_slot_local.y \
			< bag.to_local(quick_slot_node.global_position).y - 0.15
	# The stowed rifle belongs to the bag, not the foreground hand layer: centred
	# under the canvas and no farther forward than the retaining-loop plane.
	var rifle_stowed_in_sling := absf(rifle_slot_local.x) < 0.010 \
			and rifle_slot_local.y < -0.280 and rifle_slot_local.z < 0.180
	var taken := bool(rig.call("_activate_bag_selection"))
	await get_tree().create_timer(1.05).timeout
	var rifle := bag.call("active_item_node") as Node3D
	var imported := rifle != null and int(rifle.call("model_mesh_count")) == 6
	var clips: PackedStringArray = rifle.call("animation_names") \
			if rifle != null else PackedStringArray()
	var animated := false
	for clip in clips:
		animated = animated or "shoot" in str(clip).to_lower()
	var exclusive := bool(bag.call("can_place_active", 4)) \
			and not bool(bag.call("can_place_active", 0))
	var arms: Node = rig.get("_arms")
	var one_hand_carry := str(arms.get("_bag_hand_mode")) == "rifle" \
			and arms.get("_rifle_support_target") == null \
			and not bool(arms.call("_locked", "L"))
	var hand_rig: Node = arms.get("rig")
	var right_weld: Dictionary = hand_rig.call("held_attachment_report", "R")
	var primary_target := bag.call("rifle_primary_target") as Node3D
	var primary_grip := rifle.call("primary_grip_node") as Node3D
	var primary_error := primary_target.global_position.distance_to(
			rifle.global_transform * primary_grip.position)

	Input.action_press("rifle_aim")
	await get_tree().create_timer(0.34).timeout
	var two_hands := str(arms.get("_bag_hand_mode")) == "rifle" \
			and arms.get("_rifle_support_target") != null
	var support_target := bag.call("rifle_support_target") as Node3D
	var support_grip := rifle.call("support_grip_node") as Node3D
	var support_error := support_target.global_position.distance_to(
			rifle.global_transform * support_grip.position)
	var primary_contact: Dictionary = hand_rig.call("finger_contact_report", "R")
	var support_contact: Dictionary = hand_rig.call("finger_contact_report", "L")
	var primary_bounds: AABB = rifle.call("primary_contact_bounds") as AABB
	var support_bounds: AABB = rifle.call("support_contact_bounds") as AABB
	var grip_contact_ok := int(primary_contact.get("touches", 0)) >= 6 \
			and int(support_contact.get("touches", 0)) >= 2 \
			and int(primary_contact.get("penetrations", 1)) == 0 \
			and int(support_contact.get("penetrations", 1)) == 0
	# Weapon drives both hands. An attachment report here means the old broken
	# topology has returned: the trigger wrist is rotating the entire rifle.
	var weapon_owned := right_weld.is_empty() and primary_error < 0.020 \
			and support_error < 0.020
	var aim_amount := float(bag.call("rifle_aim_amount"))
	var cam := rig.get("_cam") as Camera3D
	var rear := rifle.call("aim_anchor_node") as Node3D
	var front := rifle.call("front_sight_node") as Node3D
	var rear_local := cam.to_local(rear.global_position)
	var front_local := cam.to_local(front.global_position)
	var muzzle_local := cam.to_local(
			(rifle.call("muzzle_node") as Node3D).global_position)
	var closest_rifle_z := float(rifle.call("closest_camera_surface_z", cam))
	var camera_clear_of_rifle := closest_rifle_z < -(cam.near + 0.040)
	var sight_aligned := aim_amount > 0.94 \
			and absf(rear_local.x) < 0.025 and absf(rear_local.y) < 0.060 \
			and rear_local.z < -0.46 and rear_local.z > -0.54 \
			and absf(front_local.x) < 0.030 \
			and (front.global_position - rear.global_position).normalized().dot(
					-cam.global_basis.z) > 0.985
	# Let both arm IK chains settle for several rendered poses. They may move,
	# but the rifle's camera-space sight anchor must remain invariant.
	var rear_lock_sample := rear_local
	await get_tree().create_timer(0.65).timeout
	rear_local = cam.to_local(rear.global_position)
	front_local = cam.to_local(front.global_position)
	# Contact solver needs a few skeleton passes after the support hand joins.
	primary_contact = hand_rig.call("finger_contact_report", "R")
	support_contact = hand_rig.call("finger_contact_report", "L")
	var hand_lock := bool(hand_rig.call("contact_frozen", "R")) \
			and bool(hand_rig.call("contact_frozen", "L")) \
			and bool(hand_rig.call("grip_locked", "R")) \
			and bool(hand_rig.call("grip_locked", "L"))
	var primary_palm := hand_rig.call("solved_palm_global", "R") as Transform3D
	var support_palm := hand_rig.call("solved_palm_global", "L") as Transform3D
	var primary_palm_error := primary_palm.origin.distance_to(
			rifle.global_transform * primary_grip.position)
	var support_palm_error := support_palm.origin.distance_to(
			rifle.global_transform * support_grip.position)
	var palm_lock_error := maxf(primary_palm_error, support_palm_error)
	var palms_pinned := palm_lock_error < 0.006
	grip_contact_ok = int(primary_contact.get("touches", 0)) >= 6 \
			and int(support_contact.get("touches", 0)) >= 2 \
			and int(primary_contact.get("penetrations", 1)) == 0 \
			and int(support_contact.get("penetrations", 1)) == 0
	var ads_locked := rear_local.distance_to(rear_lock_sample) < 0.004 \
			and absf(front_local.x) < 0.030 and hand_lock

	var fire_event := InputEventAction.new()
	fire_event.action = "rifle_fire"
	fire_event.pressed = true
	rig.call("_unhandled_input", fire_event)
	await get_tree().create_timer(0.012).timeout
	var fired := bool(rifle.call("is_firing"))
	var no_muzzle_flash := float(rifle.call("flash_energy")) <= 0.001 \
			and not bool(rifle.call("blast_visible"))
	var shot_sound := bool(rifle.call("shot_audio_playing"))
	var pressure := float(rifle.call("pressure_amount")) > 0.20
	var indoor_profile := rifle.call("acoustic_profile_for", 0.0) as Dictionary
	var outdoor_profile := rifle.call("acoustic_profile_for", 1.0) as Dictionary
	var acoustic_variants := float(indoor_profile["report_db"]) \
			> float(outdoor_profile["report_db"]) + 5.0 \
			and float(indoor_profile["report_pitch"]) \
			< float(outdoor_profile["report_pitch"]) \
			and float(indoor_profile["body_db"]) \
			> float(outdoor_profile["body_db"]) + 40.0
	var clip_playing := bool(rifle.call("shoot_animation_playing"))
	var automatic_bolt_suppressed := not bool(rifle.call(
			"current_animation_moves_bolt"))
	var recoil := (bag.call("active_rifle_camera_kick") as Vector3).length() \
			> deg_to_rad(1.0)
	primary_palm = hand_rig.call("solved_palm_global", "R") as Transform3D
	support_palm = hand_rig.call("solved_palm_global", "L") as Transform3D
	var shot_palm_error := maxf(primary_palm.origin.distance_to(
			rifle.global_transform * primary_grip.position),
			support_palm.origin.distance_to(
			rifle.global_transform * support_grip.position))
	var shot_palms_pinned := shot_palm_error < 0.012
	Input.action_release("rifle_aim")
	var empty_after_shot := not bool(bag.call("rifle_loaded"))
	var dry_fire_blocked := not bool(bag.call("begin_active_rifle_fire"))
	var reload_started := bool(bag.call("begin_active_rifle_reload"))
	# Mechanical order: open the bolt first, hold it fully rearward, insert the
	# cartridge while the action is open, then drive the bolt forward.
	await get_tree().create_timer(0.85).timeout
	var cartridge := rifle.call("cartridge_node") as Node3D
	var bolt_opens_first := cartridge != null and not cartridge.visible \
			and str(primary_target.get_meta("hand_pose", "")) == "bolt_grip" \
			and float(rifle.call("bolt_open_amount")) > 0.020
	await get_tree().create_timer(0.18).timeout
	var held_open_amount := float(rifle.call("bolt_open_amount"))
	var bolt_held_for_round := bool(rifle.call("reload_bolt_held_open")) \
			and held_open_amount > 0.060 and not cartridge.visible
	await get_tree().create_timer(0.20).timeout
	var round_in_hand := cartridge != null and cartridge.visible \
			and bool(primary_target.get_meta("hand_attachment", false)) \
			and str(primary_target.get_meta("hand_pose", "")) == "pinch"
	var round_visual := rifle.call("cartridge_visual_report") as Dictionary
	var round_dimensioned := int(round_visual.get("mesh_count", 0)) >= 10 \
			and absf(float(round_visual.get("case_length", 0.0)) - 0.057) < 0.0001 \
			and absf(float(round_visual.get("overall_length", 0.0)) - 0.082) < 0.0001
	var round_contact := hand_rig.call("finger_contact_report", "R") as Dictionary
	var round_touch_map := round_contact.get("touches_by_finger", {}) as Dictionary
	var round_fingers_seated := int(round_touch_map.get(0, 0)) >= 1 \
			and int(round_touch_map.get(1, 0)) >= 1 \
			and int(round_touch_map.get(2, 0)) == 0 \
			and int(round_touch_map.get(3, 0)) == 0 \
			and int(round_touch_map.get(4, 0)) == 0 \
			and int(round_contact.get("penetrations", 1)) == 0
	var round_palm := hand_rig.call("solved_palm_global", "R") as Transform3D
	var round_anatomy := hand_rig.call("consider", "R", round_palm.origin,
			round_palm.basis.z, round_palm.basis.y) as Dictionary
	var round_wrist_neutral := float(round_anatomy.get("wrist_break", PI)) \
			< deg_to_rad(4.0) and float(round_anatomy.get("palm_twist", PI)) \
			< deg_to_rad(4.0)
	var round_weld := hand_rig.call("held_attachment_report", "R") as Dictionary
	var round_attached := float(round_weld.get("position_error", 1.0)) < 0.001 \
			and float(round_weld.get("angle_error", PI)) < deg_to_rad(0.5)
	var left_carries_reload := arms.get("_rifle_support_target") != null
	# Sample the last visible insertion frame, while both the round and the hand
	# still exist. Its case head must land at the authored breech centre and its
	# +Z projectile axis must agree with the barrel/chamber axis.
	await get_tree().create_timer(1.02).timeout
	var chamber_node := rifle.call("chamber_node") as Node3D
	var chamber_world := rifle.global_transform * chamber_node.transform
	var insertion_root_error := cartridge.global_position.distance_to(
			chamber_world.origin)
	var insertion_axis_dot := cartridge.global_basis.z.normalized().dot(
			chamber_world.basis.z.normalized())
	var insertion_aligned := insertion_root_error < 0.012 \
			and insertion_axis_dot > 0.995
	await get_tree().create_timer(0.45).timeout
	var bolt_work := not cartridge.visible \
			and str(primary_target.get_meta("hand_pose", "")) == "bolt_grip" \
			and bool(bag.call("rifle_reloading"))
	var reload_sound_synced := bool(rifle.call("reload_audio_playing")) \
			and absf(float(rifle.call("reload_sound_started_at")) - 0.25) < 0.04 \
			and absf(float(rifle.call("reload_sound_pitch")) - 0.85) < 0.01
	var bolt_contact := hand_rig.call("finger_contact_report", "R") as Dictionary
	var bolt_touch_map := bolt_contact.get("touches_by_finger", {}) as Dictionary
	var bolt_fingers_seated := int(bolt_touch_map.get(1, 0)) >= 1 \
			and int(bolt_touch_map.get(3, 0)) == 0 \
			and int(bolt_touch_map.get(4, 0)) == 0 \
			and int(bolt_contact.get("penetrations", 1)) == 0
	var bolt_palm := hand_rig.call("solved_palm_global", "R") as Transform3D
	var live_bolt := rifle.global_transform \
			* (rifle.call("bolt_grip_transform") as Transform3D)
	var bolt_natural := hand_rig.call("natural_axes", "R", live_bolt.origin) as Dictionary
	var bolt_expected_palm := live_bolt.origin \
			- (bolt_natural["palm"] as Vector3) \
			* float(primary_target.get_meta("palm_clearance", 0.0)) \
			- (bolt_natural["fingers"] as Vector3) \
			* float(primary_target.get_meta("control_forward_reach", 0.0)) \
			+ (bolt_natural["palm"] as Vector3).cross(
					bolt_natural["fingers"] as Vector3).normalized() \
			* float(primary_target.get_meta("control_index_bias", 0.0))
	var bolt_sync_error := bolt_palm.origin.distance_to(bolt_expected_palm)
	var bolt_synced := bolt_sync_error < 0.008
	var bolt_anatomy := hand_rig.call("consider", "R", bolt_expected_palm,
			bolt_palm.basis.z, bolt_palm.basis.y) as Dictionary
	var bolt_wrist_break := float(bolt_anatomy.get("wrist_break", PI))
	var bolt_palm_twist := float(bolt_anatomy.get("palm_twist", PI))
	var bolt_wrist_neutral := bolt_wrist_break < deg_to_rad(3.0) \
			and bolt_palm_twist < deg_to_rad(3.0)
	await get_tree().create_timer(0.75).timeout
	var reload_ready := bool(bag.call("rifle_loaded")) \
			and not bool(bag.call("rifle_reloading")) \
			and str(primary_target.get_meta("hand_pose", "")) == "rifle_primary"
	var carry_restored := arms.get("_rifle_support_target") == null \
			and not bool(arms.call("_locked", "L"))
	rig.set("_bag_selected", 4)
	var reopened := bool(rig.call("set_bag_open", true))
	await get_tree().create_timer(0.95).timeout
	var placed := bool(rig.call("_activate_bag_selection"))
	await get_tree().create_timer(0.20).timeout
	var restored := placed and bool(bag.call("slot_occupied", 4)) \
			and bag.call("active_item_node") == null
	var complete := slot_label == "Hunting rifle" and rifle_below_tools \
			and rifle_stowed_in_sling \
			and taken and imported \
			and animated and exclusive and one_hand_carry and two_hands and weapon_owned \
			and grip_contact_ok and sight_aligned and camera_clear_of_rifle \
			and ads_locked and palms_pinned \
			and pressure and no_muzzle_flash and shot_sound and acoustic_variants \
			and shot_palms_pinned and carry_restored \
			and fired and clip_playing and automatic_bolt_suppressed and recoil \
			and empty_after_shot and dry_fire_blocked and reload_started \
			and bolt_opens_first and bolt_held_for_round \
			and bolt_synced and bolt_wrist_neutral and bolt_fingers_seated \
			and reload_sound_synced \
			and round_in_hand and round_dimensioned and round_fingers_seated \
			and round_wrist_neutral \
			and round_attached and insertion_aligned \
			and left_carries_reload and bolt_work and reload_ready \
			and reopened and restored
	print("[rifle] label=%s below=%s stow=%s/%s take=%s imported=%s clips=%s exclusive=%s carry_1h=%s aim_2h=%s carry_restored=%s weapon_owned=%s grip_err=%.4f/%.4f contacts=%d/%d penetration=%d/%d nearest=%.4f/%.4f local=%s/%s bounds=%s/%s aim=%.2f rear=%s front=%s muzzle=%s camera_clear=%s/%.3f aligned=%s locked=%s hand_lock=%s palms=%.4f/%.4f shot_palms=%.4f fire=%s sound=%s no_flash=%s acoustic=%s anim=%s auto_bolt_off=%s recoil=%s empty=%s dry_block=%s reload=%s order=%s/%s open=%.3f reload_sound=%s round=%s round_mesh=%s round_contact=%d/%d round_digits=%s round_wrist=%.2f/%.2f round_weld=%.4f/%.2f insert=%.4f/%.3f/%s left_hold=%s bolt=%s bolt_contact=%d/%d digits=%s sync=%.4f/%s wrist=%.2f/%.2f neutral=%s ready=%s place=%s restored=%s complete=%s" % [
			slot_label, rifle_below_tools, rifle_stowed_in_sling, rifle_slot_local,
			taken, imported, clips, exclusive,
			one_hand_carry, two_hands,
			carry_restored, weapon_owned,
			primary_error, support_error,
			int(primary_contact.get("touches", 0)), int(support_contact.get("touches", 0)),
			int(primary_contact.get("penetrations", 0)),
			int(support_contact.get("penetrations", 0)),
			float(primary_contact.get("nearest", -1.0)),
			float(support_contact.get("nearest", -1.0)),
			primary_contact.get("nearest_local", Vector3.ZERO),
			support_contact.get("nearest_local", Vector3.ZERO),
			primary_bounds, support_bounds,
			aim_amount, rear_local, front_local,
			muzzle_local, camera_clear_of_rifle, closest_rifle_z,
			sight_aligned, ads_locked, hand_lock, primary_palm_error,
			support_palm_error,
			shot_palm_error, fired, shot_sound, no_muzzle_flash, acoustic_variants,
			clip_playing, automatic_bolt_suppressed, recoil, empty_after_shot,
			dry_fire_blocked, reload_started,
			bolt_opens_first, bolt_held_for_round, held_open_amount,
			reload_sound_synced,
			round_in_hand, round_dimensioned,
			int(round_contact.get("touches", 0)),
			int(round_contact.get("penetrations", 0)), round_touch_map,
			rad_to_deg(float(round_anatomy.get("wrist_break", PI))),
			rad_to_deg(float(round_anatomy.get("palm_twist", PI))),
			float(round_weld.get("position_error", 1.0)),
			rad_to_deg(float(round_weld.get("angle_error", PI))),
			insertion_root_error, insertion_axis_dot, insertion_aligned,
			left_carries_reload, bolt_work,
			int(bolt_contact.get("touches", 0)),
			int(bolt_contact.get("penetrations", 0)), bolt_touch_map,
			bolt_sync_error, bolt_synced,
			rad_to_deg(bolt_wrist_break), rad_to_deg(bolt_palm_twist),
			bolt_wrist_neutral,
			reload_ready,
			placed, restored, complete])
	if not complete:
		push_error("hunting rifle sling/aim/fire/return contract incomplete")
	get_tree().quit()


func _rifle_shot(rig: Node3D, boat: RigidBody3D, dir: String) -> void:
	## Deterministic visual audit of every state the player complained about.
	rig.call("set_mode", 1)
	var panel: Node = get_tree().get_first_node_in_group("ui_panel")
	if panel != null:
		var panel_view: CanvasItem = panel.get("_panel") as CanvasItem
		if panel_view != null:
			panel_view.visible = false
	rig.set("_bag_selected", 4)
	rig.call("set_bag_open", true)
	await get_tree().create_timer(0.95).timeout
	await _shot(dir, "rifle0_sling")
	rig.call("_activate_bag_selection")
	await get_tree().create_timer(1.05).timeout
	await _shot(dir, "rifle1_one_hand_carry")
	Input.action_press("rifle_aim")
	# Capture only after the measured weapon-space palm/contact locks are active.
	await get_tree().create_timer(0.65).timeout
	await _shot(dir, "rifle2_sights")
	var bag: Node3D = boat.call("deck_bag_node") as Node3D
	bag.call("begin_active_rifle_fire")
	await get_tree().create_timer(0.025).timeout
	await _shot(dir, "rifle3_shot")
	await get_tree().create_timer(0.12).timeout
	await _shot(dir, "rifle4_recoil")
	Input.action_release("rifle_aim")
	bag.call("begin_active_rifle_reload")
	await get_tree().create_timer(0.72).timeout
	await _shot(dir, "rifle5_bolt_opening")
	await get_tree().create_timer(0.25).timeout
	await _shot(dir, "rifle6_bolt_held_open")
	await get_tree().create_timer(0.28).timeout
	await _shot(dir, "rifle7_round_in_hand")
	await get_tree().create_timer(0.98).timeout
	await _shot(dir, "rifle8_insert_round")
	await get_tree().create_timer(0.34).timeout
	await _shot(dir, "rifle9_bolt_forward")
	await get_tree().create_timer(0.30).timeout
	await _shot(dir, "rifle10_bolt_lock")
	await get_tree().create_timer(0.18).timeout
	await _shot(dir, "rifle11_return_early")
	await get_tree().create_timer(0.18).timeout
	await _shot(dir, "rifle12_regrip")
	await get_tree().create_timer(0.20).timeout
	await _shot(dir, "rifle13_ready")
	rig.set("_bag_selected", 4)
	rig.call("set_bag_open", true)
	await get_tree().create_timer(0.95).timeout
	await _shot(dir, "rifle14_return")
	get_tree().quit()


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
		# The dash pair is on the opposite side of the wheelhouse from the fuse
		# well. Test each from the stance a player would actually take, rather
		# than asking a metre-long ghost arm to cover both consoles without feet.
		if sid in ["sw_flood", "sw_wiper"]:
			w.call("spawn_at", Vector3(-0.50, 2.91, 0.48))
		else:
			w.call("spawn_at", Vector3(0.66, 2.91, 1.54))
		await get_tree().create_timer(0.30).timeout
		var lev: Node3D = boat.call("switch_lever", sid)
		for i in 5:
			var d: Vector3 = lev.global_position - cam.global_position
			rig.set("yaw", atan2(-d.x, -d.z))
			rig.set("pitch", asin(clampf(d.normalized().y, -1.0, 1.0)))
			await get_tree().create_timer(0.1).timeout
		var accepted: bool = bool(arms.call("notify_use", sid))
		if not accepted:
			for side in ["L", "R"]:
				var ev: Dictionary = arms.call("_grip_evaluation", side, sid)
				print("[sw-eval] %s/%s reach=%s left=%.3f elbow=%.1f wrist=%.1f twist=%.1f" % [
					sid, side, ev.get("reachable", false),
					float(ev.get("leftover", -1.0)),
					rad_to_deg(float(ev.get("elbow_angle", 0.0))),
					rad_to_deg(float(ev.get("wrist_break", 0.0))),
					rad_to_deg(float(ev.get("palm_twist", 0.0)))])
		# Past contact, before release: measure the wrist while it is still on
		# the moving lever rather than after it has already returned to rest.
		await get_tree().create_timer(0.48).timeout
		var claim: Dictionary = arms.get("_claim")
		var side := "L" if str(claim.get("L", "")) == sid else (
				"R" if str(claim.get("R", "")) == sid else "")
		var g: Node3D = lev.get_node_or_null("Grip_" + (side if side != "" else "R"))
		var wr: Transform3D = hr.call("wrist_global", side if side != "" else "R")
		var sh: Vector3 = hr.call("shoulder_global", side if side != "" else "R")
		print("[sw] %-10s side=%-2s reach=%.3f  grip=%.2v  wrist=%.2v  err=%.3f" % [
				sid, side if side != "" else "-",
				sh.distance_to(g.global_position) if g != null else -1.0,
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
	var arms: Node = rig.get("_arms")
	arms.set("boat", boat)
	# This helper photographs the carried pose, not reach admission at whichever
	# helm spawn the test happened to inherit. Mirror a loaded/equipped radio;
	# Hands then claims it through the same passive state synchronisation used by
	# save restore and scripted pickup.
	boat.set("radio_held", true)
	await get_tree().create_timer(0.8).timeout
	if not bool(boat.get("radio_pose_locked")):
		push_error("radio screenshot route did not acquire the held pose")
	for i in 4:
		await get_tree().create_timer(0.7).timeout
		rig.set("pitch", [-0.10, 0.10, -0.30, 0.0][i])
		rig.set("yaw", _as_f(rig.get("yaw")) + [0.0, 0.22, -0.30, 0.10][i])
		await get_tree().create_timer(0.25).timeout
		await _shot(dir, "radio%d" % i)
	get_tree().quit()


func _held_framing_test(rig: Node3D, boat: RigidBody3D) -> void:
	## First exercise a future long tool at hostile anchors/aspect ratios, then
	## verify the real radio and palm remain framed while the player looks around.
	var tool_frame := {
		"anchor": Vector3(0.72, -0.34, -0.48),
		"device_x": Vector3(1.0, 0.0, 0.0),
		"device_z": Vector3(0.0, -0.12, -0.99),
		"focus_point": Vector3(0.0, 0.0, 0.08),
		"safe_margin": Vector2(0.06, 0.07),
		"hand_radius": Vector2(0.045, 0.055),
		# A generic tool may intentionally sit nearer the sight line than the
		# cheek-held radio; the contract, not a code branch, chooses that lane.
		"center_keepout": 0.12,
		"depth_range": Vector2(0.34, 0.75),
		"mirror_left": true,
	}
	var tool_points: Array[Vector3] = []
	for x in [-0.045, 0.045]:
		for y in [-0.065, 0.065]:
			for z in [-0.34, 0.16]:
				tool_points.append(Vector3(x, y, z))
	for aspect in [4.0 / 3.0, 16.0 / 9.0, 21.0 / 9.0]:
		for side in ["L", "R"]:
			var solved := HeldObjectFramer.solve_local(tool_frame, side, 70.0,
					aspect, tool_points)
			var report := HeldObjectFramer.report(solved, tool_frame, 70.0,
					aspect, tool_points)
			if not bool(report.get("visible", false)) \
					or not bool(report.get("center_clear", false)):
				push_error("held framing failed synthetic %s at %.3f: %s" % [
						side, aspect, report])

	rig.set_mode(1)
	await get_tree().create_timer(2.2).timeout
	var arms: Node = rig.get("_arms")
	arms.set("boat", boat)
	boat.set("radio_held", true)
	await get_tree().create_timer(1.2).timeout
	for look in [Vector2(-0.18, -0.22), Vector2(0.14, 0.28), Vector2.ZERO]:
		rig.set("pitch", look.x)
		rig.set("yaw", _as_f(rig.get("yaw")) + look.y)
		await get_tree().create_timer(0.35).timeout
		var live: Dictionary = arms.call("held_frame_report", "radio")
		if not bool(live.get("visible", false)) \
				or not bool(live.get("center_clear", false)):
			push_error("held framing lost live radio: %s" % live)
		var claims: Dictionary = arms.get("_claim")
		var radio_side := "L" if str(claims.get("L", "")) == "radio" else "R"
		var weld: Dictionary = arms.get("rig").call("held_attachment_report",
				radio_side)
		if not bool(weld.get("welded", false)) \
				or float(weld.get("position_error", INF)) > 0.0005 \
				or float(weld.get("render_position_error", INF)) > 0.0005 \
				or float(weld.get("angle_error", INF)) > deg_to_rad(0.05):
			push_error("held object slipped in the solved palm: %s" % weld)
	# Sample the transition itself, not merely the settled endpoints. This is the
	# regression for a handset visibly swimming through closed fingers while the
	# camera is moving.
	var max_weld_position_error := 0.0
	var max_render_position_error := 0.0
	var max_weld_angle_error := 0.0
	for sample in 36:
		rig.set("yaw", _as_f(rig.get("yaw")) + sin(float(sample) * 0.71) * 0.032)
		rig.set("pitch", sin(float(sample) * 0.43) * 0.20)
		await get_tree().process_frame
		var moving_claims: Dictionary = arms.get("_claim")
		var moving_side := "L" if str(moving_claims.get("L", "")) == "radio" else "R"
		var moving_weld: Dictionary = arms.get("rig").call(
				"held_attachment_report", moving_side)
		max_weld_position_error = maxf(max_weld_position_error,
				float(moving_weld.get("position_error", INF)))
		max_render_position_error = maxf(max_render_position_error,
				float(moving_weld.get("render_position_error", INF)))
		max_weld_angle_error = maxf(max_weld_angle_error,
				float(moving_weld.get("angle_error", INF)))
	if max_weld_position_error > 0.0005 or max_render_position_error > 0.0005 \
			or max_weld_angle_error > deg_to_rad(0.05):
		push_error("held weld drifted during camera motion: logical=%.6f render=%.6f angle=%.4f" % [
				max_weld_position_error, max_render_position_error,
				rad_to_deg(max_weld_angle_error)])
	if not bool(boat.get("radio_pose_locked")):
		push_error("held framing did not transfer radio pose ownership to hands")
	var final_report: Dictionary = arms.call("held_frame_report", "radio")
	print("[held-framing] synthetic=6 radio_visible=%s center_clear=%s max_ndc=%s weld_pos=%.6f render_pos=%.6f weld_deg=%.4f" % [
		final_report.get("visible", false), final_report.get("center_clear", false),
		final_report.get("max_ndc", Vector2.ZERO), max_weld_position_error,
		max_render_position_error, rad_to_deg(max_weld_angle_error)])
	var handset: Node3D = boat.call("radio_handset") as Node3D
	boat.set("radio_held", false)
	await get_tree().create_timer(0.8).timeout
	if handset == null or handset.get_parent() != boat \
			or bool(boat.get("radio_pose_locked")):
		push_error("held radio did not restore its boat hierarchy on release")
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
	# The headless display driver never emits frame_post_draw; numeric probes
	# must keep running instead of hanging forever at their optional screenshot.
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, name])


func _ocean_test(rig: Node3D, boat: RigidBody3D, dir: String) -> void:
	## Repeatable water review: lay down a full-speed track, then inspect its
	## centreline/cusps and the bow contact at the camera heights that expose them.
	# Wake comparisons must not randomly happen at midnight in a thunderstorm.
	# Hold a modest breeze and high daylight so consecutive speed/motion passes
	# measure the wake rather than a different sea and exposure.
	var wx: Node = get_node_or_null("Weather")
	if wx != null:
		wx.set("time_of_day", 12.5)
		wx.set("storm", false)
		wx.set("rain_amount", 0.0)
		wx.set("cloud_cover", 0.28)
		if wx.has_method("set_wind"):
			wx.call("set_wind", 4.0, 40.0)
	var pnl: Node = get_tree().get_first_node_in_group("ui_panel")
	if pnl != null:
		var pc: CanvasItem = pnl.get("_panel") as CanvasItem
		if pc != null:
			pc.visible = false
	await get_tree().create_timer(2.2).timeout
	rig.set_mode(2)
	_look_rig = rig
	_look_boat = boat
	var cam: Camera3D = rig.get("_cam")
	# Match the user's high, calm-water review angle before laying down the wake;
	# this isolates planar-reflection alignment from prop wash and white water.
	_eye_local = Vector3(8.5, 7.0, 10.5)
	await get_tree().process_frame
	await get_tree().process_frame
	var reflection_goal := boat.to_global(Vector3(0.0, 0.15, 0.0))
	var reflection_dir := reflection_goal - cam.global_position
	rig.set("yaw", atan2(-reflection_dir.x, -reflection_dir.z))
	rig.set("pitch", asin(clampf(reflection_dir.normalized().y, -1.0, 1.0)))
	await get_tree().create_timer(0.55).timeout
	await _shot(dir, "ocean2_reflection")
	# Full-power time sequence from directly astern. These early frames expose a
	# detached source immediately; a single mature-wake beauty shot cannot.
	_eye_local = Vector3(0.0, 1.72, 13.5)
	await get_tree().process_frame
	await get_tree().process_frame
	var build_goal := boat.to_global(Vector3(0.0, -0.08, 4.15))
	var build_dir := build_goal - cam.global_position
	rig.set("yaw", atan2(-build_dir.x, -build_dir.z))
	rig.set("pitch", asin(clampf(build_dir.normalized().y, -1.0, 1.0)))
	# The wake review says full power, so the screw and its aerated local field
	# must be live as well as the imposed through-water speed.
	boat.set("engine", 2) # Boat.EngineState.RUNNING
	var review_speed := 10.5
	var review_turn := false
	var review_slams := false
	var review_motion := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--wake-speed="):
			review_speed = clampf(float(arg.get_slice("=", 1)), 1.0, 16.0)
		elif arg == "--wake-turn":
			review_turn = true
		elif arg == "--wake-slam":
			review_slams = true
		elif arg == "--wake-motion":
			review_motion = true
	var review_load := clampf(review_speed / 10.5, 0.12, 1.0)
	boat.set("throttle", review_load)
	boat.set("_rpm", review_load)
	for i in 70:
		boat.linear_velocity = -boat.global_basis.z * review_speed
		if review_turn:
			boat.angular_velocity.y = 0.16
		if review_slams and i in [12, 32, 52]:
			# Deterministic starboard-forefoot entries: regression coverage for the
			# old round analytic craters without depending on random sea phase.
			var local_hit := Vector3(1.45, -0.62, -3.20)
			var hit: Vector3 = boat.to_global(local_hit)
			boat.ocean.hull_slam(hit, local_hit, 1.1)
		await get_tree().create_timer(0.10).timeout
		if review_motion and i >= 7 and i <= 39 and i % 2 == 1:
			await _shot(dir, "ocean_motion_%02d" % i)
		if i in [7, 19, 39, 69]:
			await _shot(dir, "ocean_build_%02d" % i)
	for setup in [
		[Vector3(0.0, 2.05, 13.5), Vector3(0.0, -0.10, 2.6), "ocean0_wake"],
		[Vector3(5.8, 0.82, -0.8), Vector3(0.0, -0.12, -3.8), "ocean1_bow"],
		[Vector3(8.8, 8.5, 16.0), Vector3(0.0, 0.0, 3.2), "ocean3_wake_overview"],
	]:
		_eye_local = setup[0]
		await get_tree().process_frame
		await get_tree().process_frame
		var goal: Vector3 = boat.to_global(setup[1])
		var d: Vector3 = goal - cam.global_position
		rig.set("yaw", atan2(-d.x, -d.z))
		rig.set("pitch", asin(clampf(d.normalized().y, -1.0, 1.0)))
		await get_tree().create_timer(0.55).timeout
		await _shot(dir, setup[2])
	get_tree().quit()


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


func _walk_hand_shot(rig: Node3D, dir: String) -> void:
	## Two opposite gait phases for visual/anatomical review of free hands.
	rig.call("set_mode", 1)
	var walk_boat: Node3D = rig.get("target") as Node3D
	if walk_boat != null:
		walk_boat.set("helm_engaged", false)
		walk_boat.set("telegraph_engaged", false)
		walk_boat.set("chart_engaged", false)
	rig.get("_walker").call("spawn_at", Vector3(0.0, 2.93, 2.60))
	var panel: Node = get_tree().get_first_node_in_group("ui_panel")
	if panel != null:
		var panel_view: CanvasItem = panel.get("_panel") as CanvasItem
		if panel_view != null:
			panel_view.visible = false
	await get_tree().create_timer(0.55).timeout
	Input.action_press("boat_forward")
	await get_tree().create_timer(0.35).timeout
	# Freeze the authored extremes rather than hoping a screenshot lands on the
	# useful half of a continuously advancing step.  This makes before/after
	# hand reviews deterministic on both 60 Hz and 120 Hz machines.
	var arms: Node = rig.get("_arms") as Node
	if arms != null:
		arms.set("_stride", 1.0)
		arms.set("_gait", PI * 0.5)
	await get_tree().process_frame
	await get_tree().process_frame
	_walk_hand_report(rig, "right_forward")
	await _shot(dir, "walk0_right_forward")
	if arms != null:
		arms.set("_gait", PI * 1.5)
	await get_tree().process_frame
	await get_tree().process_frame
	_walk_hand_report(rig, "left_forward")
	await _shot(dir, "walk1_left_forward")
	Input.action_release("boat_forward")
	get_tree().quit()


func _walk_hand_report(rig: Node3D, phase: String) -> void:
	var arms: Node = rig.get("_arms") as Node
	var cam: Camera3D = rig.get("_cam") as Camera3D
	if arms == null or cam == null:
		return
	var hand_rig: Node = arms.get("rig") as Node
	if hand_rig == null:
		return
	var r_frame: Transform3D = hand_rig.call("solved_palm_global", "R")
	var l_frame: Transform3D = hand_rig.call("solved_palm_global", "L")
	var r_palm := r_frame.basis.y.normalized()
	var l_palm := l_frame.basis.y.normalized()
	var r_fingers := r_frame.basis.z.normalized()
	var l_fingers := l_frame.basis.z.normalized()
	print(("[walk_hands] phase=%s R_palm(view/right/up)=%.2f/%.2f/%.2f " \
			+ "L_palm(view/right/up)=%.2f/%.2f/%.2f " \
			+ "finger_down=%.2f/%.2f") % [phase,
			r_palm.dot(-cam.global_basis.z), r_palm.dot(cam.global_basis.x),
			r_palm.dot(cam.global_basis.y),
			l_palm.dot(-cam.global_basis.z), l_palm.dot(cam.global_basis.x),
			l_palm.dot(cam.global_basis.y),
			r_fingers.dot(-cam.global_basis.y),
			l_fingers.dot(-cam.global_basis.y)])


func _turn_test(dir: String) -> void:
	## Hold the helm hard over and photograph the left hand three times mid-turn
	## — before, during and after a re-grip.
	await get_tree().create_timer(2.0).timeout
	Input.action_press("boat_left")
	for i in 3:
		await get_tree().create_timer(0.55).timeout
		await _shot(dir, "turn_%d" % i)
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
		"deckbag":
			goal = _look_boat.to_global(Vector3(1.61, 1.62, 0.84))
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
