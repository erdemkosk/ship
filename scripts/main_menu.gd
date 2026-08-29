extends Node3D
class_name MainMenu
## The front door of the game, and it is not a screen — it is the first shot.
##
## She is out there when you arrive: drifting beam-on in the storm, beacon
## going, cabin lamp burning in one window, and the camera holds her the way a
## man in a liferaft would — low, slow, never quite steady. The menu itself is
## a rack of ship's fittings in the foreground: a telegraph lever, a brass
## toggle, a breaker under a red guard. There is no cursor-on-a-word anywhere.
##
## The hand does the choosing. The same measured IK arm the game plays with
## reaches out when the mouse finds a control, settles on it, and works it when
## pressed — and the telegraph is not clicked but TAKEN: hold the button and
## drag, and the hand hauls the lever through its arc with you. Release it past
## the gate and you have ordered the engine ahead; that is what starting the
## game is. WEATHER throws a toggle and opens the sea-state panel. ABANDON
## pulls the breaker: every light on her dies first, then the picture.

const RIG := preload("res://scripts/hands/hand_rig.gd")

var rig: Node3D          # boat_camera
var boat: RigidBody3D
var ocean: Node3D
var weather: Node3D

var _cam: Camera3D
var _hands: Node3D
var _console: Node3D
var _lever_piv: Node3D       # the telegraph
var _toggle_piv: Node3D      # weather
var _breaker_piv: Node3D     # abandon
var _knob: Node3D
var _t := 0.0
var _orbit := 0.0
var _hover := ""
var _forced_hover := ""
var _holding := false
## Telegraph arc. Rest leans TOWARD you — you push her ahead, away from
## yourself, the way every engine order ever given has gone.
var _lever_a := 0.52
var _drag_y := 0.0
var _hold_t := 0.0
var _autopush := false
var _panel_on := false
var _leaving := ""           # "", "sail", "quit"
var _leave_t := 0.0
var _fade: ColorRect
var _title: Label
var _sub: Label
var _hint: Label
var _done := false

const LEVER_REST := 0.52
const LEVER_FULL := -0.62
const LEVER_GATE := -0.34


func setup(p_rig: Node3D, p_boat: RigidBody3D, p_ocean: Node3D, p_weather: Node3D) -> void:
	rig = p_rig
	boat = p_boat
	ocean = p_ocean
	weather = p_weather


func _ready() -> void:
	_cam = rig.get("_cam")
	# The menu owns the camera. boat_camera's own process would put it right
	# back on the boat, so it sleeps until the lever is pulled.
	rig.set_process(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# The weather panel and the fps counter belong to the game, not the shot.
	var pnl: Node = get_tree().get_first_node_in_group("ui_panel")
	if pnl != null:
		var pc: CanvasItem = pnl.get("_panel") as CanvasItem
		if pc != null:
			pc.visible = false
		var fl: CanvasItem = pnl.get("_fps_label") as CanvasItem
		if fl != null:
			fl.visible = false
	# Night coming on, the storm already made. The boot preset is the storm;
	# the hour is pushed a little later so the beacon and the lamp carry.
	weather.set("time_of_day", 20.6)
	_build_console()
	_build_overlay()
	# The arm. Its own rig instance, so the game's claim system is not even in
	# the room — the menu drives the grip directly.
	_hands = RIG.new()
	add_child(_hands)
	_hands.setup(_cam)
	_hands.set_visible_hands(true)


func _exit_tree() -> void:
	if is_instance_valid(rig):
		rig.set_process(true)
	_free_hands()


func _free_hands() -> void:
	## The rig hangs its arm model under the CAMERA (that is how it rides the
	## view), so freeing the rig node alone leaves the whole arm orphaned on
	## the lens — a severed limb floating over the game. The lag node is the
	## part that has to go.
	if _hands == null:
		return
	var lag: Node = _hands.get("_lag")
	if lag != null and is_instance_valid(lag):
		lag.queue_free()
	if is_instance_valid(_hands):
		_hands.queue_free()
	_hands = null


# --- the furniture -----------------------------------------------------------

func _mat(c: Color, r: float, m := 0.0) -> StandardMaterial3D:
	var mt := StandardMaterial3D.new()
	mt.albedo_color = c
	mt.roughness = r
	mt.metallic = m
	return mt


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _cyl(parent: Node3D, r: float, h: float, pos: Vector3, rot: Vector3,
		mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 14
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _build_console() -> void:
	## A rail of controls low in the frame, riding the camera — rain-wet wood
	## and brass, the only warm things between you and her.
	_console = Node3D.new()
	# Close enough that the arm SETTLES on the fittings. At 0.80 m the far
	# controls were past reach-plus-lean and the arm could only stretch at
	# them across the whole frame, which is the opposite of a hand at rest.
	_console.position = Vector3(0.0, -0.40, -0.64)
	_console.rotation.x = 0.30    # tipped up toward the eye
	_cam.add_child(_console)
	var wood := _mat(Color(0.075, 0.060, 0.045), 0.38)   # oiled, wet
	var wood_edge := _mat(Color(0.105, 0.085, 0.062), 0.45)
	var brass := _mat(Color(0.42, 0.32, 0.15), 0.35, 0.8)
	var iron := _mat(Color(0.13, 0.13, 0.14), 0.6, 0.4)
	var red := _mat(Color(0.42, 0.09, 0.06), 0.55)

	_box(_console, Vector3(0.92, 0.040, 0.26), Vector3.ZERO, wood)
	_box(_console, Vector3(0.94, 0.018, 0.28), Vector3(0.0, -0.028, 0.0), wood_edge)

	# --- the telegraph, centre: SET SAIL ------------------------------------
	var ped := Node3D.new()
	ped.position = Vector3(0.0, 0.022, -0.02)
	_console.add_child(ped)
	_box(ped, Vector3(0.13, 0.055, 0.13), Vector3(0.0, 0.028, 0.0), iron)
	# Quadrant plate the lever sweeps across. Its disc lies IN the swing
	# plane — normal athwart — so it reads as the arc the handle travels,
	# instead of standing up as a wall in front of it, which is what the
	# first pass built and what hid the whole instrument.
	_cyl(ped, 0.100, 0.016, Vector3(0.0, 0.115, 0.0),
			Vector3(0.0, 0.0, 90.0), brass)
	_lever_piv = Node3D.new()
	_lever_piv.position = Vector3(0.0, 0.115, 0.028)
	ped.add_child(_lever_piv)
	_cyl(_lever_piv, 0.011, 0.17, Vector3(0.0, 0.085, 0.0), Vector3.ZERO, iron)
	# The grip is a BAR, athwart — a hand wraps a horizontal handle. The
	# first pass left the cylinder upright and the hand had nothing to hold.
	_knob = _cyl(_lever_piv, 0.017, 0.085, Vector3(0.0, 0.185, 0.0),
			Vector3(0.0, 0.0, 90.0), brass)
	_lever_piv.rotation.x = _lever_a
	_lever_piv.rotation.x = 0.52

	# --- the toggle, port: WEATHER ------------------------------------------
	var tbase := Node3D.new()
	tbase.position = Vector3(-0.30, 0.022, 0.02)
	_console.add_child(tbase)
	_box(tbase, Vector3(0.115, 0.020, 0.115), Vector3(0.0, 0.010, 0.0), brass)
	_toggle_piv = Node3D.new()
	_toggle_piv.position = Vector3(0.0, 0.022, 0.0)
	tbase.add_child(_toggle_piv)
	_cyl(_toggle_piv, 0.010, 0.075, Vector3(0.0, 0.037, 0.0), Vector3.ZERO, brass)
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.017
	sm.height = 0.034
	ball.mesh = sm
	ball.material_override = brass
	ball.position = Vector3(0.0, 0.078, 0.0)
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_toggle_piv.add_child(ball)
	_toggle_piv.rotation.x = -0.30

	# --- the breaker, starboard: ABANDON ------------------------------------
	var bbase := Node3D.new()
	bbase.position = Vector3(0.30, 0.022, 0.02)
	_console.add_child(bbase)
	_box(bbase, Vector3(0.115, 0.062, 0.125), Vector3(0.0, 0.031, 0.0), iron)
	_box(bbase, Vector3(0.10, 0.014, 0.028), Vector3(0.0, 0.070, -0.048), red)
	_breaker_piv = Node3D.new()
	_breaker_piv.position = Vector3(0.0, 0.062, 0.0)
	bbase.add_child(_breaker_piv)
	_box(_breaker_piv, Vector3(0.030, 0.105, 0.020), Vector3(0.0, 0.052, 0.0), red)
	_box(_breaker_piv, Vector3(0.040, 0.026, 0.026), Vector3(0.0, 0.105, 0.0), iron)
	_breaker_piv.rotation.x = -0.42

	# Painted labels on the board's forward face.
	for it in [["SET SAIL", 0.0], ["WEATHER", -0.30], ["ABANDON SHIP", 0.30]]:
		var lb := Label3D.new()
		lb.text = str(it[0])
		lb.font_size = 26
		lb.pixel_size = 0.00070
		lb.modulate = Color(0.78, 0.74, 0.66, 0.92)
		lb.outline_size = 7
		lb.outline_modulate = Color(0, 0, 0, 0.8)
		lb.position = Vector3(float(it[1]), 0.026, 0.118)
		lb.rotation.x = -1.05
		_console.add_child(lb)


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 4
	add_child(layer)
	# Storm-dark corners; the same vignette the sea already knows.
	var vig := ColorRect.new()
	vig.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vm := ShaderMaterial.new()
	vm.shader = load("res://shaders/vignette.gdshader")
	vm.set_shader_parameter("strength", 0.62)
	vig.material = vm
	layer.add_child(vig)

	_title = Label.new()
	_title.text = "D A R K   S E A"
	_title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_title.offset_top = 64.0
	_title.offset_left = -640.0
	_title.offset_right = 640.0
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 92)
	_title.add_theme_color_override("font_color", Color(0.80, 0.79, 0.74))
	_title.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.04, 0.9))
	_title.add_theme_constant_override("outline_size", 10)
	layer.add_child(_title)

	_sub = Label.new()
	_sub.text = "cold water keeps what it takes"
	_sub.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_sub.offset_top = 178.0
	_sub.offset_left = -640.0
	_sub.offset_right = 640.0
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.add_theme_font_size_override("font_size", 21)
	_sub.add_theme_color_override("font_color", Color(0.62, 0.63, 0.60, 0.75))
	layer.add_child(_sub)

	_hint = Label.new()
	_hint.text = "take the telegraph and put her ahead"
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.offset_top = -46.0
	_hint.offset_left = -640.0
	_hint.offset_right = 640.0
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 17)
	_hint.add_theme_color_override("font_color", Color(0.70, 0.62, 0.46, 0.0))
	layer.add_child(_hint)

	var fl := CanvasLayer.new()
	fl.layer = 9
	add_child(fl)
	_fade = ColorRect.new()
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.color = Color(0, 0, 0, 1)
	fl.add_child(_fade)


# --- per frame ---------------------------------------------------------------

func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	_place_camera(delta)
	_run_menu(delta)
	_run_hand(delta)
	_run_fades(delta)
	if _hands != null:
		_hands.update(delta)


func _place_camera(delta: float) -> void:
	## A slow half-orbit off her weather quarter, held low over the water the
	## way a swimmer would see her, with a handheld drift that never repeats.
	_orbit += delta * 0.030
	var bp: Vector3 = boat.get_global_transform_interpolated().origin
	var a := _orbit + 2.4
	var pos := bp + Vector3(cos(a), 0.0, sin(a)) * 16.5
	pos.y = bp.y + 3.4 + sin(_t * 0.11) * 0.5
	if ocean != null:
		pos.y = maxf(pos.y, float(ocean.get_height(pos)) + 1.9)
	_cam.global_position = _cam.global_position.lerp(pos, 1.0 - exp(-2.5 * delta)) \
			if _t > 0.1 else pos
	var look := bp + Vector3(0.0, 2.0, 0.0)
	# The unsteadiness is the liferaft, not an earthquake: two slow sines a
	# few tenths of a degree each, plus the lerped chase above.
	var d := (look - _cam.global_position).normalized()
	var yaw := atan2(-d.x, -d.z) + sin(_t * 0.23) * 0.012
	var pitch := asin(clampf(d.y, -1.0, 1.0)) + sin(_t * 0.17 + 1.0) * 0.009
	_cam.global_basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) \
			* Basis(Vector3.BACK, sin(_t * 0.13) * 0.008)


func _item_world(id: String) -> Vector3:
	match id:
		"sail":
			return _knob.global_position
		"weather":
			return _toggle_piv.to_global(Vector3(0.0, 0.078, 0.0))
		"abandon":
			return _breaker_piv.to_global(Vector3(0.0, 0.105, 0.0))
	return Vector3.ZERO


func _run_menu(delta: float) -> void:
	if _leaving != "":
		return
	# Hover: whichever control the pointer is over, judged on screen — the
	# only place a pointer exists.
	var mouse := get_viewport().get_mouse_position()
	var best := ""
	var best_d := 95.0
	for id in ["sail", "weather", "abandon"]:
		var wp := _item_world(id)
		if _cam.is_position_behind(wp):
			continue
		var sp := _cam.unproject_position(wp)
		var dd := sp.distance_to(mouse)
		if dd < best_d:
			best_d = dd
			best = id
	if _forced_hover != "":
		best = _forced_hover
	if not _holding:
		_hover = best

	var pressed := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if pressed and not _holding and _hover != "":
		_holding = true
		_hold_t = 0.0
		_drag_y = mouse.y
	if _holding:
		_hold_t += delta
		if _hover == "sail":
			# TAKEN, not clicked: the lever follows the drag, the hand rides
			# it. Drag up = push away = ahead. A short tap asks the hand to
			# shove it home itself.
			_lever_a = clampf(_lever_a + (mouse.y - _drag_y) * 0.010,
					LEVER_FULL, LEVER_REST)
			_drag_y = mouse.y
		if not pressed:
			_holding = false
			match _hover:
				"sail":
					if _lever_a <= LEVER_GATE:
						_begin_leave("sail")
					elif _hold_t < 0.30:
						_autopush = true
				"weather":
					_panel_on = not _panel_on
					_toggle_piv.rotation.x = 0.30 if _panel_on else -0.30
					var pnl: Node = get_tree().get_first_node_in_group("ui_panel")
					if pnl != null:
						var pc: CanvasItem = pnl.get("_panel") as CanvasItem
						if pc != null:
							pc.visible = _panel_on
				"abandon":
					_begin_leave("quit")
	if _autopush:
		_lever_a = move_toward(_lever_a, LEVER_FULL, delta * 2.6)
		if _lever_a <= LEVER_GATE:
			_autopush = false
			_begin_leave("sail")
	if not _holding and not _autopush and _leaving == "" and _lever_a < LEVER_REST:
		# Sprung, like a real telegraph detent: let go short of the gate and
		# it walks back to rest.
		_lever_a = move_toward(_lever_a, LEVER_REST, delta * 1.4)
	_lever_piv.rotation.x = _lever_a


func _run_hand(delta: float) -> void:
	if _hands == null or not _hands.is_ready():
		return
	var c: Transform3D = _cam.global_transform
	var target := _hover
	if _leaving == "quit":
		target = "abandon"
	elif _leaving == "sail" or _autopush:
		target = "sail"
	if target == "":
		# Down and out of the shot, the way the game's own idle hands hang.
		var home: Vector3 = c * Vector3(0.36, -0.66, 0.04)
		_hands.grip("R", home, c.basis * Vector3(0.1, -0.9, -0.4),
				c.basis * Vector3(-1.0, -0.1, 0.0), 0.35, "open", 0.0)
		return
	var wp := _item_world(target)
	var engaged := _holding or _autopush or _leaving != ""
	# Settled on it when working it; hovering a hand's breadth off it when not.
	var contact := wp if engaged else wp + c.basis * Vector3(0.015, 0.055, 0.055)
	# Every pair here is orthogonal BY CONSTRUCTION. Hand grip() two nearly
	# parallel axes and its re-projection invents a wrist roll of its own —
	# the flat, broken hand of the first pass of this menu.
	var pose := "wrap"
	var fingers: Vector3 = c.basis * Vector3(0.0, -0.55, -0.835)
	var palm: Vector3 = c.basis * Vector3(0.0, -0.835, 0.55)
	if target == "weather":
		pose = "point"
		fingers = c.basis * Vector3(0.0, -0.80, -0.60)
		palm = c.basis * Vector3(0.0, -0.60, 0.80)
	elif target == "abandon":
		fingers = c.basis * Vector3(0.0, -0.30, -0.95)
		palm = c.basis * Vector3(-0.20, -0.91, 0.36)
	_hands.grip("R", contact, fingers, palm, 1.0, pose,
			1.0 if engaged else 0.55)


func _begin_leave(kind: String) -> void:
	_leaving = kind
	_leave_t = 0.0
	if kind == "quit":
		_breaker_piv.rotation.x = 0.55
		# The breaker means it: every circuit on her dies before the picture.
		boat.set("light_cabin", false)
		boat.set("light_helm", false)
		boat.set("light_beacon", false)
		boat.set("light_flood", false)


func _run_fades(delta: float) -> void:
	# Boot: fade up from black; title breathes in a beat later.
	if _leaving == "":
		_fade.color.a = maxf(_fade.color.a - delta * 0.55, 0.0)
		var ta := clampf((_t - 1.2) / 2.6, 0.0, 1.0)
		_title.add_theme_color_override("font_color",
				Color(0.80, 0.79, 0.74, ta * 0.92))
		_sub.add_theme_color_override("font_color",
				Color(0.62, 0.63, 0.60, ta * 0.62))
		_hint.add_theme_color_override("font_color", Color(0.70, 0.62, 0.46,
				clampf((_t - 4.0) / 2.0, 0.0, 0.55)))
		return
	_leave_t += delta
	_fade.color.a = minf(_fade.color.a + delta * 1.1, 1.0)
	if _leaving == "sail" and _leave_t > 1.15:
		_enter_game()
	elif _leaving == "quit" and _leave_t > 1.6:
		get_tree().quit()


func _enter_game() -> void:
	_done = true
	var pnl: Node = get_tree().get_first_node_in_group("ui_panel")
	if pnl != null:
		var fl: CanvasItem = pnl.get("_fps_label") as CanvasItem
		if fl != null:
			fl.visible = true
	rig.set_process(true)
	rig.call("set_mode", 1)
	# The fade rect outlives the menu by a second so the cut is covered.
	var fr := _fade
	var tw := create_tween()
	tw.tween_interval(0.25)
	tw.tween_property(fr, "color:a", 0.0, 0.9)
	tw.tween_callback(queue_free)
	# Everything 3D goes now; the overlay stays for the tween.
	_console.queue_free()
	_free_hands()


# --- probes ------------------------------------------------------------------

func debug_hover(id: String) -> void:
	_forced_hover = id


func debug_press(id: String) -> void:
	_forced_hover = ""
	_hover = id
	match id:
		"sail":
			_autopush = true
		"abandon":
			_begin_leave("quit")
		"weather":
			_panel_on = not _panel_on
