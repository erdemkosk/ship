extends Node3D
class_name MainMenu
## The front door of the game: the first shot, with a plain menu over it.
##
## She is out there when you arrive — drifting beam-on in the storm, beacon
## going, one lamp burning in the wheelhouse — and the camera holds her the
## way a man in a liferaft would: low, slow, never quite steady. Over that,
## three words down the left edge. Nothing else.
##
## (Two dressier versions died here: a floating console of ship's fittings
## worked by a real IK hand, first hung over open water, then bolted to the
## chart table. Both photographed worse than they sounded — the hand crossed
## the whole frame, the fittings fought the navigation for table room, and
## none of it said anything three plain words do not. The shot is the menu;
## the words just name the exits.)

var rig: Node3D          # boat_camera
var boat: RigidBody3D
var ocean: Node3D
var weather: Node3D

var _cam: Camera3D
var _t := 0.0
var _orbit := 0.0
var _panel_on := false
var _leaving := ""           # "", "sail", "quit"
var _leave_t := 0.0
var _fade: ColorRect
var _title: TextureRect
var _sub: Label
var _buttons := {}
var _done := false


func setup(p_rig: Node3D, p_boat: RigidBody3D, p_ocean: Node3D, p_weather: Node3D) -> void:
	rig = p_rig
	boat = p_boat
	ocean = p_ocean
	weather = p_weather


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		# The ESC that opened this shot must not also close it.
		if _t < 0.20:
			get_viewport().set_input_as_handled()
			return
		# Same key that opened this shot: back into the man. Weather board
		# first, if it is up — then a second ESC sails. ABANDON SHIP still
		# quits; that is the button that means it.
		if _panel_on:
			_choose("weather")
		else:
			_choose("sail")
		get_viewport().set_input_as_handled()


func _ready() -> void:
	add_to_group("main_menu")
	_cam = rig.get("_cam")
	# The menu owns the camera. boat_camera's own process would put it right
	# back on the boat, so it sleeps until SET SAIL.
	rig.set_process(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var ret: CanvasItem = rig.get("_reticle") as CanvasItem
	if ret != null:
		ret.visible = false
	var pr: CanvasItem = rig.get("_prompt") as CanvasItem
	if pr != null:
		pr.visible = false
	# The weather panel and the fps counter belong to the game, not the shot.
	var pnl: Node = get_tree().get_first_node_in_group("ui_panel")
	if pnl != null:
		var pc: CanvasItem = pnl.get("_panel") as CanvasItem
		if pc != null:
			pc.visible = false
		var fl: CanvasItem = pnl.get("_fps_label") as CanvasItem
		if fl != null:
			fl.visible = false
	# Night coming on, the storm already made; the beacon and the lamp carry.
	weather.set("time_of_day", 20.6)
	_build_overlay()


func _exit_tree() -> void:
	if is_instance_valid(rig):
		rig.set_process(true)


# --- overlay -----------------------------------------------------------------

func _menu_button(text: String, id: String, parent: Control) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 30)
	b.add_theme_color_override("font_color", Color(0.66, 0.66, 0.62, 0.85))
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.80))
	b.add_theme_color_override("font_pressed_color", Color(1.0, 0.85, 0.55))
	b.add_theme_color_override("font_focus_color", Color(0.66, 0.66, 0.62, 0.85))
	b.add_theme_constant_override("outline_size", 8)
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	b.pressed.connect(func() -> void: _choose(id))
	parent.add_child(b)
	_buttons[id] = b
	return b


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 4
	add_child(layer)
	var vig := ColorRect.new()
	vig.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vm := ShaderMaterial.new()
	vm.shader = load("res://shaders/vignette.gdshader")
	vm.set_shader_parameter("strength", 0.62)
	vig.material = vm
	layer.add_child(vig)

	# The game's own mark. No boot card, no glitch burn-in — the menu is
	# already the first picture.
	_title = TextureRect.new()
	_title.texture = load("res://assets/ui/deep_trauma_logo.png")
	_title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_title.offset_top = 6.0
	_title.offset_left = -260.0
	_title.offset_right = 260.0
	_title.offset_bottom = 266.0
	_title.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_title.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.modulate.a = 0.95
	layer.add_child(_title)

	_sub = Label.new()
	_sub.text = "cold water keeps what it takes"
	_sub.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_sub.offset_top = 252.0
	_sub.offset_left = -640.0
	_sub.offset_right = 640.0
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.add_theme_font_size_override("font_size", 21)
	_sub.add_theme_color_override("font_color", Color(0.62, 0.63, 0.60, 0.62))
	layer.add_child(_sub)

	# The exits, down the left edge, out of her way.
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	col.offset_left = 84.0
	col.offset_top = -256.0
	col.offset_right = 420.0
	col.offset_bottom = -84.0
	col.add_theme_constant_override("separation", 18)
	layer.add_child(col)
	_menu_button("SET SAIL", "sail", col)
	_menu_button("WEATHER", "weather", col)
	_menu_button("ABANDON SHIP", "quit", col)

	var fl := CanvasLayer.new()
	fl.layer = 9
	add_child(fl)
	_fade = ColorRect.new()
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.color = Color(0, 0, 0, 0)
	fl.add_child(_fade)


func _choose(id: String) -> void:
	if _leaving != "" or _done:
		return
	match id:
		"sail":
			# Straight into the man. A fade-to-black and back read as the
			# menu opening and shutting again.
			_enter_game()
		"quit":
			_leaving = "quit"
			_leave_t = 0.0
			# The breaker means it: every light on her dies before the picture.
			boat.set("light_cabin", false)
			boat.set("light_helm", false)
			boat.set("light_beacon", false)
			boat.set("light_flood", false)
		"weather":
			_panel_on = not _panel_on
			var pnl: Node = get_tree().get_first_node_in_group("ui_panel")
			if pnl != null:
				var pc: CanvasItem = pnl.get("_panel") as CanvasItem
				if pc != null:
					pc.visible = _panel_on


# --- per frame ---------------------------------------------------------------

func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	_place_camera(delta)
	_run_fades(delta)


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


func _run_fades(delta: float) -> void:
	if _leaving == "":
		_fade.color.a = 0.0
		return
	_leave_t += delta
	_fade.color.a = minf(_fade.color.a + delta * 1.1, 1.0)
	if _leaving == "quit" and _leave_t > 1.6:
		get_tree().quit()


func _enter_game() -> void:
	_done = true
	set_process(false)
	var pnl: Node = get_tree().get_first_node_in_group("ui_panel")
	if pnl != null:
		var fl: CanvasItem = pnl.get("_fps_label") as CanvasItem
		if fl != null:
			fl.visible = true
		if _panel_on:
			var pc: CanvasItem = pnl.get("_panel") as CanvasItem
			if pc != null:
				pc.visible = false
	if is_instance_valid(rig):
		rig.set_process(true)
		rig.call("set_mode", 1)
	queue_free()


# --- probes ------------------------------------------------------------------

func debug_hover(id: String) -> void:
	# Text buttons speak for themselves; the probe just proves the states.
	for k in _buttons:
		var b: Button = _buttons[k]
		b.add_theme_color_override("font_color",
				Color(1.0, 0.95, 0.80) if (k == id or (id == "abandon" and k == "quit"))
				else Color(0.66, 0.66, 0.62, 0.85))


func debug_press(id: String) -> void:
	_choose("quit" if id == "abandon" else id)
