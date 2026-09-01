extends Node3D
## Camera with three modes, cycled with F:
##  - FOLLOW: orbits the boat; hold right mouse to orbit, wheel to zoom.
##  - FPS:    you are ABOARD her. Mouse looks, WASD walks the deck, Space
##            jumps, and the ladder aft of the deckhouse takes you up to the
##            wheelhouse. Stand at the wheel and press E to take the helm —
##            then WASD steers the boat instead of your feet. E again to let go.
##  - FREE:   fly camera; hold right mouse to look, W/A/S/D + Q/E to move,
##            Shift for speed boost. Boat input is suspended.
## The camera stays above the waves in FOLLOW / FPS. FREE mode can dive;
## Q lowers, E raises. Seafloor is the only lower clamp.

enum Mode { FOLLOW, FPS, FREE }

## Keyboard shorthand -> the switch it throws. Same ids the fuse box uses, so
## there is one circuit behind both and they cannot disagree.
const SHORTCUTS := {
	"anchor": "sw_anchor", "light_cabin": "sw_cabin", "light_helm": "sw_helm",
	"light_beacon": "sw_beacon", "light_flood": "sw_flood", "wiper": "sw_wiper",
}
const WeatherScript := preload("res://scripts/weather.gd")
const HandGripMap := preload("res://scripts/hands/grip_map.gd")
const InteractionActions := preload("res://scripts/interaction_action.gd")

var target: Node3D
var ocean: Node3D
var weather: Node3D
var mode: int = Mode.FOLLOW
var free_mode := false  # read by boat.gd: true only in FREE mode

var yaw := 0.0
var pitch := -0.22
var dist := 16.0
var free_speed := 14.0
## FPS look. Mouse writes the target; the head eases onto it so a flick is a
## turn, not a snap. Slower than orbit — you are a person, not a turret.
const FPS_LOOK := 0.0021
const FPS_LOOK_TAU := 0.075
var _look_yaw := 0.0
var _look_pitch := 0.0



var _cam: Camera3D
var _orbiting := false
var _under_rect: ColorRect
var _under_mat: ShaderMaterial
var _warm_rect: ColorRect
var _warm_mat: ShaderMaterial
var _warmth := 0.0
var _motes: GPUParticles3D
var _prompt: Label
var _walker: RefCounted = (load("res://scripts/deck_walker.gd") as GDScript).new()
# Eye smoothing. The walker's feet move in hard 0.28 m increments up a
# companionway, so an eye pinned straight to them climbs like a staircase of
# jump cuts. Smoothed in the BOAT'S frame, never in world space — smooth it in
# world space and you are also smoothing her heave, which puts the horizon on
# a spring and makes the whole deck feel like jelly.
var _eye_y := 0.0
var _eye_ready := false
var _bob := 0.0
## Boat-local eye offset produced by a deliberate hand reach. Feet remain on
## deck; this is head/torso travel from bending at the waist.
var _reach_body_lean := Vector3.ZERO
var _roll := 0.0
var _panel: Node = null
# 0 while you are not at the chart, running to 1 as you lean over it. The lean
# is what makes it a place you go rather than a screen that opens.
var _chart_t := 0.0
var _last_aim := ""
var _bubbles: GPUParticles3D
## Your own breath. Separate from the ambient field: those bubbles say the sea
## is aerated, these say YOU are down here and holding it — they come off your
## face, they burst as the water closes over you, and they trickle after.
var _breath: GPUParticles3D
var _breath_burst := 0.0
var _was_sub := false
var _was_ladder := false
## The mask. `_fog` is condensation on the inside of the glass, `_wipe` is the
## finger crossing it — 1 at the start of the sweep, 0 when it is clear.
var _mask_rect: ColorRect
var _mask_mat: ShaderMaterial
var _fog := 0.0
var _wipe := 0.0
var _inhale: AudioStreamPlayer
var _exhale: AudioStreamPlayer
var _stair_snd: Array[AudioStreamPlayer] = []
var _stair_voice := 0
var _stair_idx := -99
## The breath cycle, and the level of fog at which the next automatic clear
## happens. Both are deliberately irregular: a diver does not breathe to a
## metronome and does not clear their mask on a schedule either.
var _br_t := 0.0
var _br_in := true
var _wipe_at := 0.78
## Seconds of wearing it before the glass is milky. Same clock in air and
## water — a dive does not ice the pane; it is still breath on cold glass.
const FOG_DRY := 260.0
var _drops := 0.0
var _drop_wipe := 0.0
var _mask_was_under := false
var _breath_amt := 0.0
var _arms: Node
var _reticle: Control
var _blink_rect: ColorRect
var _blink_mat: ShaderMaterial
var _blink := 0.0
var _blink_wait := 4.0
var _blink_tween: Tween
var _blink_again := false
var _camera_attrs: CameraAttributesPractical
## The deck bag is body-worn. I swings it from the right shoulder into the
## lap; the continuous amount drives body weight, focus and the real 3D prop.
var _bag_open := false
var _bag_focus := 0.0
var _bag_saved_yaw := 0.0
var _bag_saved_pitch := 0.0
var _bag_selected := 0


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
	_camera_attrs = CameraAttributesPractical.new()
	_camera_attrs.dof_blur_far_enabled = false
	_camera_attrs.dof_blur_far_distance = 0.82
	_camera_attrs.dof_blur_far_transition = 0.48
	_camera_attrs.dof_blur_amount = 0.0
	_cam.attributes = _camera_attrs
	# Measured IK rig + per-hand grip claims (scripts/hands/).
	_arms = (load("res://scripts/hands/hands.gd") as GDScript).new()
	add_child(_arms)
	_arms.setup(_cam)
	_arms.connect("action_contact", _on_hand_action_contact)
	_build_underwater()
	# Interaction prompt: one line at the bottom of the view, only in FPS mode.
	var pl := CanvasLayer.new()
	pl.layer = 2
	add_child(pl)
	_prompt = Label.new()
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.offset_top = -78.0
	_prompt.offset_left = -260.0
	_prompt.offset_right = 260.0
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 17)
	_prompt.add_theme_color_override("font_color", Color(1.0, 0.72, 0.36))
	_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_prompt.add_theme_constant_override("outline_size", 4)
	_prompt.visible = false
	pl.add_child(_prompt)

	# Reticle. A boat has no HUD, so this is as close to nothing as it can be
	# and still answer the only question it exists to answer: WHICH of the four
	# fittings under your nose is the one E will take. A hairline dot when there
	# is nothing, four ticks closing on it when there is.
	_reticle = Control.new()
	_reticle.set_anchors_preset(Control.PRESET_FULL_RECT)
	_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reticle.set_script(load("res://scripts/reticle.gd"))
	pl.add_child(_reticle)

	# Occasional blink. On this layer so it covers the view, the reticle and
	# the prompt — eyelids sit in front of everything you were looking at.
	_blink_rect = ColorRect.new()
	_blink_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_blink_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blink_rect.color = Color(1, 1, 1, 1)
	_blink_mat = ShaderMaterial.new()
	_blink_mat.shader = load("res://shaders/blink.gdshader")
	_blink_rect.material = _blink_mat
	_blink_rect.visible = false
	pl.add_child(_blink_rect)


func _on_hand_action_contact(id: String) -> void:
	## Gameplay mutation happens when the authored fingers reach the fitting,
	## never when E is pressed.  From this frame onward the grip node is parented
	## to the moving part, so the hand follows the real hinge/lever/rail path.
	if target == null:
		return
	var spec: Dictionary = HandGripMap.spec_for(id)
	InteractionActions.execute(target, id, spec)


func _start_catalog_interaction(id: String, spec: Dictionary) -> bool:
	## One admission/dispatch route for every catalog entry. Modes and full-body
	## special drivers declare their result as data; authored actions only begin
	## a hand gesture here and commit later in _on_hand_action_contact().
	if spec.is_empty():
		return false
	var kind := int(spec.get("kind", HandGripMap.Kind.GESTURE))
	var accepted := false
	if kind != HandGripMap.Kind.SPECIAL and _arms != null:
		_arms.boat = target
		accepted = bool(_arms.notify_use(id, true))
	if str(spec.get("action", "")) != "":
		return accepted
	if kind == HandGripMap.Kind.MODE:
		if accepted:
			var property := str(spec.get("mode_property", ""))
			if property != "":
				target.set(property, true)
		return accepted
	if kind != HandGripMap.Kind.SPECIAL:
		return false
	match str(spec.get("special", "")):
		"mode":
			var property := str(spec.get("mode_property", ""))
			if property != "":
				target.set(property, true)
			return true
		"ladder":
			_walker.grab_sea_ladder(target)
			return true
		"wear":
			target.toggle_switch("divegear")
			if _arms != null and _arms.has_method("face_gesture"):
				_arms.face_gesture("wear")
			return true
	return false


func set_mode(m: int) -> void:
	if m != Mode.FPS:
		_reset_deck_bag()
	mode = m
	free_mode = mode == Mode.FREE
	match mode:
		Mode.FPS:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			_eye_ready = false
			_bob = 0.0
			_roll = 0.0
			if _arms != null:
				_arms.set_active(true)
			# start looking where the boat points, standing at the wheel
			if target != null:
				var fwd := -target.global_basis.z
				yaw = atan2(-fwd.x, -fwd.z)
				_walker.spawn_at(target.CREW_START)
				target.set("helm_engaged", true)
				target.set("telegraph_engaged", false)
			pitch = 0.0
			_look_yaw = yaw
			_look_pitch = pitch
			_blink_wait = randf_range(1.8, 4.5)
		Mode.FREE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			if _arms != null:
				_arms.set_active(false)
			if target != null:
				target.set("helm_engaged", true)
				target.set("telegraph_engaged", false)
			if _prompt != null:
				_prompt.visible = false
			_stop_blink()
			var fwd := -_cam.global_basis.z
			yaw = atan2(-fwd.x, -fwd.z)
			pitch = asin(clampf(fwd.y, -1.0, 1.0))
		_:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			if _arms != null:
				_arms.set_active(false)
			if target != null:
				target.set("helm_engaged", true)
				target.set("telegraph_engaged", false)
			if _prompt != null:
				_prompt.visible = false
			_stop_blink()
			pitch = clampf(pitch, -1.15, 0.45)


func _panel_open() -> bool:
	if _panel == null or not is_instance_valid(_panel):
		_panel = get_tree().get_first_node_in_group("ui_panel")
	return _panel != null and _panel.has_method("is_open") and _panel.is_open()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_camera"):
		set_mode((mode + 1) % 3)
		return
	if get_tree().get_first_node_in_group("main_menu") != null:
		return
	if event.is_action_pressed("backpack"):
		set_bag_open(not _bag_open)
		get_viewport().set_input_as_handled()
		return
	if mode == Mode.FPS and _bag_focus < 0.08 and not _panel_open() \
			and event.is_action_pressed("knife_attack"):
		var attack_bag := _deck_bag()
		if attack_bag != null and str(attack_bag.call("active_item_kind")) \
				== "utility_knife" and bool(attack_bag.call("begin_active_attack")):
			get_viewport().set_input_as_handled()
			return
	if mode == Mode.FPS and _bag_focus < 0.08 and not _panel_open() \
			and event.is_action_pressed("rifle_reload"):
		var reload_bag := _deck_bag()
		if reload_bag != null and str(reload_bag.call("active_item_kind")) \
				== "hunting_rifle":
			reload_bag.call("begin_active_rifle_reload")
			get_viewport().set_input_as_handled()
			return
	if mode == Mode.FPS and _bag_focus < 0.08 and not _panel_open() \
			and event.is_action_pressed("rifle_fire"):
		var fire_bag := _deck_bag()
		if fire_bag != null and str(fire_bag.call("active_item_kind")) \
				== "hunting_rifle" and bool(fire_bag.call("begin_active_rifle_fire")):
			_resolve_active_rifle_shot(fire_bag)
			get_viewport().set_input_as_handled()
			return
	if mode == Mode.FPS and _bag_open and _bag_focus > 0.58:
		if event.is_action_pressed("bag_previous"):
			_shift_bag_selection(-1)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("bag_next"):
			_shift_bag_selection(1)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("use"):
			_activate_bag_selection()
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("ui_cancel"):
		if _panel_open() and _panel != null and is_instance_valid(_panel):
			var pc: CanvasItem = _panel.get("_panel") as CanvasItem
			if pc != null:
				pc.visible = false
				get_viewport().set_input_as_handled()
				return
		var root := get_parent()
		if root != null and root.has_method("return_to_menu"):
			root.call("return_to_menu")
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion:
		# Panel up: the pointer is for the sliders, not for looking around.
		if _panel_open():
			return
		if mode == Mode.FPS and _bag_focus > 0.03:
			return # the neck and eyes are committed to the bag in the lap
		if mode == Mode.FPS and _chart_t > 0.0 and _chart_t < 1.0:
			return                      # leaning in; the camera is driving
		if mode == Mode.FPS:
			_look_yaw -= event.relative.x * FPS_LOOK
			_look_pitch = clampf(_look_pitch - event.relative.y * FPS_LOOK, -1.4, 1.4)
		elif _orbiting:
			yaw -= event.relative.x * 0.005
			if mode == Mode.FREE:
				pitch = clampf(pitch - event.relative.y * 0.005, -1.5, 1.5)
			else:
				pitch = clampf(pitch - event.relative.y * 0.005, -1.15, 0.45)
		return

	# Mask on: 3 is a finger across the WET glass, not the beacon. The fuse
	# still throws that circuit from the panel; the shortcut yields while you
	# are looking through a lens covered in sea.
	if mode == Mode.FPS and target != null and _flag(target, "gear_worn") \
			and event.is_action_pressed("light_beacon"):
		_wipe_drops()
		return

	# The circuits, by key. The toggles are on the face; the keys throw the
	# same fields. `by_hand = false` is the shortcut, not a finger.
	if mode == Mode.FPS and target != null and target.has_method("toggle_switch"):
		for act: String in SHORTCUTS:
			if event.is_action_pressed(act):
				target.toggle_switch(SHORTCUTS[act], false)
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


func set_bag_open(open: bool) -> bool:
	## Public for the repeatable screenshot route as well as the I binding.
	if mode != Mode.FPS or target == null:
		return false
	if open and (_panel_open() or _flag(_walker, "swimming") \
			or _flag(_walker, "on_sea_ladder")):
		return false
	if open:
		var active_bag := _deck_bag()
		if active_bag != null:
			active_bag.call("cancel_active_attack")
	if _bag_open == open:
		return true
	_bag_open = open
	if open:
		_bag_saved_yaw = yaw
		_bag_saved_pitch = pitch
		# A six-kilo bag cannot pass through hands already planted on the ship.
		target.set("helm_engaged", false)
		target.set("telegraph_engaged", false)
		target.set("chart_engaged", false)
		if _flag(target, "radio_held"):
			target.set("radio_held", false)
		if _arms != null and _arms.has_method("set_body_hold"):
			_arms.set_body_hold("deckbag", true, "L")
		var bag := _deck_bag()
		if bag != null and bag.call("active_item_node") != null:
			if str(bag.call("active_item_kind")) == "hunting_rifle":
				_bag_selected = 4
			else:
				var empty := int(bag.call("first_empty_slot"))
				if empty >= 0:
					_bag_selected = empty
	else:
		var bag := _deck_bag()
		if bag != null:
			bag.call("set_preview_slot", -1)
	return true


func _deck_bag() -> Node3D:
	if target == null or not target.has_method("deck_bag_node"):
		return null
	return target.call("deck_bag_node") as Node3D


func _shift_bag_selection(direction: int) -> void:
	var bag := _deck_bag()
	if bag == null:
		return
	var count := int(bag.call("slot_count"))
	if count <= 0:
		return
	_bag_selected = posmod(_bag_selected + direction, count)


func _activate_bag_selection() -> bool:
	## E has two symmetrical meanings: remove what the index finger indicates,
	## or insert the carried object into the indicated empty loop.
	var bag := _deck_bag()
	if bag == null or _bag_focus < 0.82:
		return false
	var active := bag.call("active_item_node") as Node3D
	if active == null:
		if not bool(bag.call("slot_occupied", _bag_selected)):
			return false
		active = bag.call("take_slot", _bag_selected) as Node3D
		if active == null:
			return false
		_set_active_bag_item_hands(bag)
		set_bag_open(false)
		return true
	if bool(bag.call("slot_occupied", _bag_selected)) \
			or not bool(bag.call("can_place_active", _bag_selected)):
		return false
	_clear_active_bag_item_hands()
	var placed := bool(bag.call("place_active_in_slot", _bag_selected))
	if placed and _arms != null and _arms.has_method("set_bag_hand") \
			and bool(bag.call("release_hand_active")):
		_arms.set_bag_hand(bag.call("release_hand_target") as Node3D,
				"knife_release")
	return placed


func _set_active_bag_item_hands(bag: Node3D) -> void:
	if _arms == null:
		return
	if str(bag.call("active_item_kind")) == "hunting_rifle" \
			and _arms.has_method("set_rifle_hands"):
		_arms.set_rifle_hands(bag.call("rifle_primary_target") as Node3D,
				bag.call("rifle_support_target") as Node3D)
	elif _arms.has_method("set_bag_hand"):
		_arms.set_bag_hand(bag.call("active_hand_target") as Node3D,
				str(bag.call("active_hand_mode")))


func _clear_active_bag_item_hands() -> void:
	if _arms == null:
		return
	if _arms.has_method("set_rifle_hands"):
		_arms.set_rifle_hands(null, null)
	if _arms.has_method("set_bag_hand"):
		_arms.set_bag_hand(null, "")


func _refresh_bag_hand() -> void:
	if _arms == null or not _arms.has_method("set_bag_hand"):
		return
	var bag := _deck_bag()
	if bag == null:
		_clear_active_bag_item_hands()
		return
	var active := bag.call("active_item_node") as Node3D
	if bool(bag.call("release_hand_active")):
		_arms.set_bag_hand(bag.call("release_hand_target") as Node3D,
				"knife_release")
	elif active != null:
		_set_active_bag_item_hands(bag)
	elif _bag_open and _bag_focus > 0.58:
		_arms.set_bag_hand(bag.call("slot_pointer_target", _bag_selected) as Node3D,
				"point")
	else:
		_clear_active_bag_item_hands()


func _reset_deck_bag() -> void:
	_bag_open = false
	_bag_focus = 0.0
	if _arms != null and _arms.has_method("set_body_hold"):
		_arms.set_body_hold("deckbag", false, "L")
	if _arms != null and _arms.has_method("set_bag_hand"):
		_arms.set_bag_hand(null, "")
	var bag := _deck_bag()
	if bag != null:
		bag.call("set_preview_slot", -1)
	if target != null and _cam != null and target.has_method("update_deck_bag_pose"):
		target.update_deck_bag_pose(0.0, _cam, 0.0)
	if _camera_attrs != null:
		_camera_attrs.dof_blur_far_enabled = false
		_camera_attrs.dof_blur_amount = 0.0


func _update_deck_bag(delta: float) -> void:
	if _bag_open and (_flag(_walker, "swimming") \
			or _flag(_walker, "on_sea_ladder")):
		_bag_open = false
	var goal := 1.0 if _bag_open else 0.0
	var duration := 0.78 if _bag_open else 0.62
	_bag_focus = move_toward(_bag_focus, goal, delta / duration)
	if _arms != null and _arms.has_method("set_body_hold"):
		if _bag_open:
			_arms.set_body_hold("deckbag", true, "L")
		elif _bag_focus <= 0.035:
			_arms.set_body_hold("deckbag", false, "L")
	if _camera_attrs != null:
		var aim_blur := 0.0
		var aim_bag := _deck_bag()
		if aim_bag != null and aim_bag.has_method("rifle_aim_amount"):
			aim_blur = float(aim_bag.call("rifle_aim_amount"))
		var blur := maxf(smoothstep(0.18, 0.86, _bag_focus), aim_blur * 0.62)
		_camera_attrs.dof_blur_far_enabled = blur > 0.01
		_camera_attrs.dof_blur_far_distance = lerpf(2.4, 0.82, blur)
		_camera_attrs.dof_blur_far_transition = lerpf(1.6, 0.42, blur)
		_camera_attrs.dof_blur_amount = 0.18 * blur
	var bag := _deck_bag()
	if bag != null:
		var active := bag.call("active_item_node") as Node3D
		var preview := -1
		if active != null and _bag_open and _bag_focus > 0.58 \
				and not bool(bag.call("slot_occupied", _bag_selected)) \
				and bool(bag.call("can_place_active", _bag_selected)):
			preview = _bag_selected
		bag.call("set_preview_slot", preview)
		bag.call("set_rifle_aim", mode == Mode.FPS and not _bag_open \
				and Input.is_action_pressed("rifle_aim"))

func _process(delta: float) -> void:
	match mode:
		Mode.FPS:
			_process_fps(delta)
		Mode.FREE:
			_process_free(delta)
		_:
			_process_follow(delta)
	_update_underwater()
	_update_blink(delta)
	if mode != Mode.FPS:
		# Everything that belongs to being ABOARD goes with the mode. These are
		# only ever written inside _process_fps, so on the frame you leave first
		# person they simply stopped being updated and stayed on screen — a
		# crosshair and a prompt floating over an orbit camera.
		if _warm_rect != null:
			_warm_rect.visible = false
		if _reticle != null:
			_reticle.visible = false
		if _prompt != null:
			_prompt.visible = false


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


func _process_fps(delta: float) -> void:
	if target == null:
		return
	_update_deck_bag(delta)
	# Physics interpolation is on project-wide, so the boat's MESH is drawn at a
	# smoothly interpolated transform while `global_transform` still reports the
	# last physics tick. Reading the raw transform pins the eye to 60 Hz inside a
	# 120 Hz render and the whole boat shivers around you as you make way. Ask
	# for the interpolated one instead.
	var xf: Transform3D = target.get_global_transform_interpolated()
	global_position = xf.origin

	# Tab opens the weather panel; while it is up you get your cursor back so
	# you can actually reach the sliders, and it is taken again on close.
	var want := Input.MOUSE_MODE_VISIBLE if _panel_open() else Input.MOUSE_MODE_CAPTURED
	if Input.mouse_mode != want:
		Input.mouse_mode = want

	# --- interaction: look at a thing, E takes hold of it, E lets go ---------
	# Everything aboard that accepts a hand is listed in boat.INTERACT; whichever
	# one is close and in front of you gets offered on the prompt line.
	var engaged := ""
	if target.get("helm_engaged"):
		engaged = "helm"
	elif target.get("telegraph_engaged"):
		engaged = "telegraph"
	elif target.get("chart_engaged"):
		engaged = "chart"

	var look_fwd := -_cam.global_basis.z
	var look_l: Vector3 = (xf.basis.inverse() * look_fwd).normalized()
	var eye: Vector3 = _walker.eye_local()

	var cand := {}
	if engaged != "chart" and _bag_focus < 0.08:
		# Ray against a sphere per fitting, nearest hit wins. It used to score by
		# alignment alone, which meant a big target behind a small one could take
		# the aim off it — you could be looking straight down a switch and get
		# offered the chart table. Now `r` is simply how big the thing is to
		# point at, and pointing at it is what selects it.
		# Aiming in a seaway. She rolls and pitches under your feet, so whatever
		# you are pointing at slides out from under the aim between one wave and
		# the next — and the switches are 10 cm targets. Two corrections, both
		# keyed to the thing actually causing the trouble:
		#
		#   * every target grows in proportion to how much she is MOVING, so it
		#     is precise when she is quiet and forgiving when she is not;
		#   * whatever is already being offered gets a further bonus, so it does
		#     not flicker off and back between rolls once you have found it.
		var sway := 0.0
		if target is RigidBody3D:
			var rb := target as RigidBody3D
			sway = clampf(rb.angular_velocity.length() * 1.6, 0.0, 1.4)
		var nearest := 1e9
		for it in target.INTERACT:
			var iid := str(it["id"])
			# Already on the wheel: the helm must not eat the key beside it.
			if engaged == "helm" and iid == "helm":
				continue
			if engaged == "telegraph" and iid == "telegraph":
				continue
			# The suit hangs INSIDE the locker. Through a shut steel door it is
			# not a thing you can reach, so it is not a thing you are offered.
			if iid == "divegear" and not (_flag(target, "locker_open")
					or _flag(target, "gear_worn")):
				continue
			# Cartridges and the house toggles sit in the well: with the
			# lid down they are not a thing you can take.
			if (iid.begins_with("fu_") or (target.has_method("switch_in_well")
					and target.switch_in_well(iid))) \
					and not _flag(target, "fusebox_open"):
				continue
			var ipos: Vector3 = it["pos"]
			if target.has_method("interact_pos"):
				ipos = target.interact_pos(iid, ipos)
			var to: Vector3 = ipos - eye
			var along := look_l.dot(to)
			if along <= 0.02 or along > 2.2:
				continue
			var base_r: float = float(it["r"])
			# Small fittings grow when she rolls; a table-sized volume must
			# not, or it swallows the door next to it.
			var rr: float = base_r * (1.0 + sway * clampf(0.14 / maxf(base_r, 0.05), 0.0, 1.0))
			if iid == _last_aim:
				rr *= 1.22
			var perp: float = (to - look_l * along).length()
			if perp > rr:
				continue
			# And it has to be in SIGHT. With the fuse lid standing open the
			# radio sits right behind it, and reaching through a steel plate to
			# take a handset off its hook is not a thing. The lid itself is
			# the fuse-box catch — do not let the plate hide its own latch.
			if iid != "fusebox" and not iid.begins_with("fu_") \
					and not (target.has_method("switch_in_well")
					and target.switch_in_well(iid)) \
					and _occluded(target, eye, ipos):
				continue
			# A prompt is a promise. Hand-authored fittings are offered only when
			# one arm can complete the reach, including the small deliberate torso
			# lean used after E. This prevents a visible prompt that does nothing.
			if _arms != null and not HandGripMap.spec_for(iid).is_empty():
				_arms.boat = target
				if not bool(_arms.can_offer(iid)):
					continue
			# Angle off the crosshair, then a size penalty so a fat volume
			# behind a knob cannot win just because you clipped its edge.
			var score: float = perp / maxf(along, 0.05)
			score *= 1.0 + base_r * 1.8
			if iid == _last_aim:
				score *= 0.88
			if score < nearest:
				nearest = score
				cand = it
		_last_aim = str(cand["id"]) if not cand.is_empty() else ""
	if _reticle != null:
		_reticle.set("aim_target", 0.0 if cand.is_empty() else 1.0)
		_reticle.visible = mode == Mode.FPS and _bag_focus < 0.08

	var candidate_spec: Dictionary = HandGripMap.spec_for(str(cand.get("id", ""))) \
			if not cand.is_empty() else {}
	if Input.is_action_just_pressed("use") and _bag_focus < 0.08:
		if cand.is_empty() and engaged == "" and _flag(target, "radio_held"):
			# Holding the handset with nothing else under the crosshair: E puts
			# it back on its hook. You should not have to hunt for the cradle
			# with your nose to hang up a radio.
			if _arms != null:
				_arms.boat = target
				_arms.notify_use("radio")
		elif cand.is_empty() and engaged == "" and _fog >= 0.10 and _wipe <= 0.0 \
				and _flag(target, "gear_worn"):
			# Nothing under the crosshair and the glass is milky: that is the
			# only thing E can sensibly mean.
			_wipe_mask()
		elif _arms != null and _arms.inspecting_id() != "":
			_arms.boat = target
			_arms.notify_use(_arms.inspecting_id())
		elif not cand.is_empty() and str(candidate_spec.get("action", "")) != "":
			# Physical controls outrank releasing the current station. This lets
			# the free hand turn the key or a switch while the other stays planted.
			_start_catalog_interaction(str(cand["id"]), candidate_spec)
		elif engaged == "helm":
			target.set("helm_engaged", false)
			_walker.spawn_at(target.HELM_STAND)
		elif engaged == "telegraph":
			target.set("telegraph_engaged", false)
			_walker.spawn_at(target.TELEGRAPH_STAND)
		elif engaged == "chart":
			target.set("chart_engaged", false)
			_walker.spawn_at(target.CHART_STAND)
		elif not cand.is_empty():
			_start_catalog_interaction(str(cand["id"]), candidate_spec)
		engaged = "helm" if target.get("helm_engaged") \
				else ("telegraph" if target.get("telegraph_engaged") \
				else ("chart" if target.get("chart_engaged") else ""))

	if _prompt != null:
		if _bag_focus > 0.65:
			var bag := _deck_bag()
			var active := bag.call("active_item_node") as Node3D if bag != null else null
			var slot_no := _bag_selected + 1
			if active == null:
				var label := str(bag.call("slot_label", _bag_selected)) if bag != null else ""
				_prompt.text = "←/→ — choose   ·   %d: %s   ·   E — take   ·   I — shoulder" % [slot_no, label]
			elif bag != null and not bool(bag.call("slot_occupied", _bag_selected)):
				_prompt.text = "←/→ — choose   ·   %d: empty   ·   E — place   ·   I — shoulder" % slot_no
			else:
				_prompt.text = "←/→ — choose   ·   %d: occupied   ·   find an empty slot" % slot_no
			_prompt.visible = true
		elif _active_bag_item_kind() == "utility_knife":
			_prompt.text = "LMB — slash   ·   I — open bag"
			_prompt.visible = true
		elif _active_bag_item_kind() == "hunting_rifle":
			var active_rifle_bag := _deck_bag()
			if active_rifle_bag != null and bool(active_rifle_bag.call("rifle_reloading")):
				_prompt.text = "Reloading — round / chamber / bolt   ·   I — open bag"
			elif active_rifle_bag != null and not bool(active_rifle_bag.call("rifle_loaded")):
				_prompt.text = "Empty   ·   R — load & cycle bolt   ·   I — open bag"
			else:
				_prompt.text = "RMB — sights   ·   LMB — fire   ·   R — reload   ·   I — open bag"
			_prompt.visible = true
		elif _walker.get("on_sea_ladder"):
			_prompt.text = "W/S — climb   ·   SPACE — let go"
			_prompt.visible = true
		elif _walker.get("swimming"):
			if _walker.get("can_board"):
				_prompt.text = "SPACE — take the ladder"
			elif _flag(_walker, "submerged"):
				_prompt.text = "SPACE — swim up"
			else:
				_prompt.text = "You are in the sea — swim to the stern ladder   ·   CTRL: dive"
			_prompt.visible = true
		elif engaged == "helm":
			if not cand.is_empty() and str(cand["id"]) == "ignition":
				var st := _inum(target, "engine")
				_prompt.text = "E — Ignition  (%s)" % (
						"stop" if st == 2 else ("cranking" if st == 1 else "start"))
			else:
				_prompt.text = "E — let go of the wheel"
			_prompt.visible = true
		elif engaged == "telegraph":
			_prompt.text = "E — let go of the throttle"
			_prompt.visible = true
		elif engaged == "chart":
			_prompt.text = "E — leave the chart"
			_prompt.visible = true
		elif _arms != null and _arms.inspecting_id() in ["radar", "sounder"]:
			_prompt.text = "E — stow the screen"
			_prompt.visible = true
		elif cand.is_empty() and _drops >= 0.22 and _drop_wipe <= 0.0 \
				and _flag(target, "gear_worn"):
			_prompt.text = "3 — wipe the water off the mask"
			_prompt.visible = true
		elif cand.is_empty() and _fog >= 0.10 and _wipe <= 0.0 \
				and _flag(target, "gear_worn"):
			_prompt.text = "E — wipe the mask"
			_prompt.visible = true
		elif _flag(target, "radio_held") and cand.is_empty():
			_prompt.text = "E — hang up the handset"
			_prompt.visible = true
		elif not cand.is_empty():
			if cand["id"] == "radio" and _flag(target, "radio_held"):
				_prompt.text = "E — hang up the handset"
			elif str(cand["id"]) in ["radar", "sounder"] and _arms != null \
					and _arms.inspecting_id() == str(cand["id"]):
				_prompt.text = "E — stow the screen"
			elif str(cand["id"]) == "locker":
				_prompt.text = "E — %s the locker" % (
						"close" if _flag(target, "locker_open") else "open")
			elif str(cand["id"]) == "divegear":
				_prompt.text = "E — %s the dive gear" % (
						"take off" if _flag(target, "gear_worn") else "put on")
			elif str(cand["id"]) == "ignition":
				var st := _inum(target, "engine")
				_prompt.text = "E — Ignition  (%s)" % (
						"stop" if st == 2 else ("cranking" if st == 1 else "start"))
			elif str(cand["id"]).begins_with("fu_") and target.has_method("fuse_seated"):
				_prompt.text = "E — %s  (%s)" % [cand["name"],
						"in" if target.fuse_seated(str(cand["id"])) else "out"]
			elif (str(cand["id"]).begins_with("sw_") or str(cand["id"]).begins_with("door_")) \
					and target.has_method("switch_state"):
				_prompt.text = "E — %s  (%s)" % [cand["name"],
						"off" if target.switch_state(str(cand["id"])) else "on"]
			else:
				_prompt.text = "E — %s" % cand["name"]
			_prompt.visible = true
		else:
			_prompt.visible = false

	if engaged == "helm":
		# Locked to the wheel: the boat's controls are yours, your feet are not.
		_walker.spawn_at(target.HELM_STAND)
	elif engaged == "telegraph":
		_walker.spawn_at(target.TELEGRAPH_STAND)
	elif engaged == "chart":
		_walker.spawn_at(target.CHART_STAND)
	else:
		# Walk. Input is taken in the boat's frame: "forward" is where you are
		# looking, projected onto her deck, so turning the boat under you does
		# not change which way you are walking.
		var look_right := _cam.global_basis.x
		var lf: Vector3 = xf.basis.inverse() * look_fwd
		var lr: Vector3 = xf.basis.inverse() * look_right
		var f2 := Vector2(lf.x, lf.z)
		var r2 := Vector2(lr.x, lr.z)
		if f2.length_squared() > 1e-5:
			f2 = f2.normalized()
		if r2.length_squared() > 1e-5:
			r2 = r2.normalized()
		var wish := Vector2.ZERO
		if not _panel_open():
			wish = f2 * Input.get_axis("boat_backward", "boat_forward") \
					+ r2 * Input.get_axis("boat_left", "boat_right")
			if wish.length() > 1.0:
				wish = wish.normalized()
			wish *= 0.0 if _bag_focus > 0.55 else lerpf(1.0, 0.28, _bag_focus)
		# Raw stick as well as the deck-projected heading: in the water and on
		# the rungs "forward" is not a direction on the deck plane.
		var axes := Vector2.ZERO
		if not _panel_open():
			axes = Vector2(Input.get_axis("boat_left", "boat_right"),
					Input.get_axis("boat_backward", "boat_forward"))
			axes *= 0.0 if _bag_focus > 0.55 else lerpf(1.0, 0.28, _bag_focus)
		_walker.update(delta, target, wish,
				Input.is_action_just_pressed("jump") and not _panel_open() \
						and _bag_focus < 0.08,
				look_fwd, axes,
				Input.is_action_pressed("jump") and not _panel_open() \
						and _bag_focus < 0.08,
				Input.is_action_pressed("dive") and not _panel_open())
		_tick_stair_step()

	# --- the eye -------------------------------------------------------------
	var eye_l: Vector3 = _walker.eye_local()
	if engaged == "chart":
		_chart_t = minf(_chart_t + delta / 0.45, 1.0)
		var lean: float = _chart_t * _chart_t * (3.0 - 2.0 * _chart_t)
		eye_l = eye_l.lerp(target.CHART_EYE, lean)
	else:
		_chart_t = 0.0
	if not _eye_ready:
		_eye_y = eye_l.y
		_eye_ready = true
	elif absf(eye_l.y - _eye_y) > 1.10:
		_eye_y = eye_l.y          # teleport: taking the helm, or coming aboard
	else:
		# Fast enough to feel like your own legs, slow enough that a 0.28 m
		# tread is a rise and not a cut.
		_eye_y = lerpf(_eye_y, eye_l.y, 1.0 - exp(-13.0 * delta))
	eye_l.y = _eye_y

	# A little sway with your stride. Two steps to the cycle, and only while
	# your feet are actually on something — no bobbing in mid-air.
	var hs := 0.0 if engaged != "" else Vector2(_walker.vel.x, _walker.vel.z).length()
	var walking: float = clampf(hs / 3.0, 0.0, 1.0) * (1.0 if _walker.on_floor else 0.0)
	_bob = fmod(_bob + delta * hs * 2.3, TAU)
	var amp := walking * 0.022
	eye_l.y += sin(_bob * 2.0) * amp
	eye_l.x += sin(_bob) * amp * 0.9
	# Counter-lean as six kilos travel round the right shoulder.  It is strongest
	# in the middle of the swing and settles once the weight is supported in lap.
	var bag_load_arc := sin(_bag_focus * PI)
	eye_l.x -= bag_load_arc * 0.026
	eye_l.y -= _bag_focus * 0.012 + bag_load_arc * 0.010

	# A long hand reach moves the person, not only the arm. hands.gd publishes
	# the camera-local share of the same lean used by IK; convert it into the
	# boat frame, ease it in faster than it returns, and add it to the eye.
	var body_goal := Vector3.ZERO
	if _arms != null and _arms.has_method("body_lean_local"):
		var lean_cam: Vector3 = _arms.body_lean_local()
		body_goal = xf.basis.inverse() * (_cam.global_basis * lean_cam)
	var body_tau := 0.10 if body_goal.length_squared() > _reach_body_lean.length_squared() \
			else 0.24
	_reach_body_lean = _reach_body_lean.lerp(body_goal,
			1.0 - exp(-delta / body_tau))
	if engaged == "chart" or _flag(_walker, "swimming") \
			or _flag(_walker, "on_sea_ladder"):
		_reach_body_lean = _reach_body_lean.lerp(Vector3.ZERO,
				1.0 - exp(-delta / 0.08))
	eye_l += _reach_body_lean

	var cam_pos: Vector3 = xf * eye_l
	# The eye is normally held clear of the water — you are aboard, and a wave
	# washing the lens every time she rolls is nobody's idea of a boat. In the
	# sea, or on the transom ladder with the sea coming over you, that clamp is
	# exactly wrong: it is the one moment the view SHOULD go under.
	if ocean != null and not _flag(_walker, "swimming") \
			and not _flag(_walker, "on_sea_ladder"):
		cam_pos.y = maxf(cam_pos.y, ocean.get_height(cam_pos) + 0.35)
	_cam.global_position = cam_pos

	# Lean a fraction of her heel into the view. Full deck roll is sickening and
	# a dead-level horizon feels like standing on a photograph; a third of it,
	# capped, reads as being aboard.
	if _bag_focus > 0.001:
		# Eyes follow the weight into the lap, then return to exactly the heading
		# they left when the bag goes back over the shoulder.
		var look_amount := smoothstep(0.0, 0.72, _bag_focus)
		var bag_pitch := lerpf(_bag_saved_pitch, -0.48, look_amount)
		var bk := 1.0 - exp(-9.5 * delta)
		yaw = lerp_angle(yaw, _bag_saved_yaw, bk)
		pitch = lerpf(pitch, bag_pitch, bk)
		_look_yaw = yaw
		_look_pitch = pitch
	elif engaged == "chart" and _chart_t < 1.0:
		# Turn the head onto the paper. Only while leaning in — once you are
		# there the mouse is yours again, so you can glance up at the window
		# without having to stand off the table first.
		var dirw: Vector3 = (xf.basis * (target.CHART_LOOK - target.CHART_EYE)).normalized()
		var k := 1.0 - exp(-11.0 * delta)
		yaw = lerp_angle(yaw, atan2(-dirw.x, -dirw.z), k)
		pitch = lerpf(pitch, asin(clampf(dirw.y, -1.0, 1.0)), k)
		_look_yaw = yaw
		_look_pitch = pitch
	else:
		var lk := 1.0 - exp(-delta / FPS_LOOK_TAU)
		yaw = lerp_angle(yaw, _look_yaw, lk)
		pitch = lerpf(pitch, _look_pitch, lk)

	# --- how far you can turn your head while you have hold of something -----
	# Planted at a control your BODY does not turn. A helmsman with both hands
	# on the wheel can look over either shoulder and no further; on the boarding
	# ladder you are facing the iron with your arms round it. Without this you
	# can stand at the wheel gripping it and look dead astern, which is the one
	# thing that most gives the hands away as decoration.
	var st_lim := 0.0
	var st_base := 0.0
	if engaged == "helm" or engaged == "telegraph":
		st_base = _yaw_of(-xf.basis.z)
		st_lim = deg_to_rad(48.0)
	elif engaged == "chart":
		st_base = _yaw_of(xf.basis * (target.CHART_LOOK - target.CHART_EYE))
		st_lim = deg_to_rad(58.0)
	elif _flag(_walker, "on_sea_ladder"):
		# Facing the iron. You are hanging OFF the transom, so the ladder is
		# toward the bow from you — her forward, not her stern.
		st_base = _yaw_of(-xf.basis.z)
		st_lim = deg_to_rad(62.0)
	if st_lim > 0.0:
		yaw = st_base + clampf(wrapf(yaw - st_base, -PI, PI), -st_lim, st_lim)
		_look_yaw = st_base + clampf(wrapf(_look_yaw - st_base, -PI, PI), -st_lim, st_lim)
	# Taking hold of the boarding ladder turns you round. You were leaning over
	# the cap looking down at it; now you are on it, facing it, with the ship in
	# front of your nose — and no amount of head-turning does that, the whole
	# body comes about.
	var on_lad: bool = _flag(_walker, "on_sea_ladder")
	if on_lad and not _was_ladder:
		yaw = _yaw_of(-xf.basis.z)
		pitch = clampf(pitch, -0.5, 0.5)
		_look_yaw = yaw
		_look_pitch = pitch
	_was_ladder = on_lad

	var heel := asin(clampf(xf.basis.x.y, -1.0, 1.0))
	var bag_roll := bag_load_arc * 0.025
	_roll = lerpf(_roll, clampf(heel * 0.24 + bag_roll, -0.11, 0.11),
			1.0 - exp(-6.0 * delta))
	var knife_kick := Vector3.ZERO
	var rifle_kick := Vector3.ZERO
	var held_bag := _deck_bag()
	if held_bag != null and held_bag.has_method("active_knife_camera_kick"):
		knife_kick = held_bag.call("active_knife_camera_kick") as Vector3
	if held_bag != null and held_bag.has_method("active_rifle_camera_kick"):
		rifle_kick = held_bag.call("active_rifle_camera_kick") as Vector3
	var total_kick := knife_kick + rifle_kick
	_cam.global_basis = Basis(Vector3.UP, yaw + total_kick.y) \
			* Basis(Vector3.RIGHT, pitch + total_kick.x) \
			* Basis(Vector3.BACK, _roll + total_kick.z)
	var rifle_aim := float(held_bag.call("rifle_aim_amount")) \
			if held_bag != null and held_bag.has_method("rifle_aim_amount") else 0.0
	var rifle_pressure := float(held_bag.call("active_rifle_pressure")) \
			if held_bag != null and held_bag.has_method("active_rifle_pressure") else 0.0
	# The shock front briefly opens peripheral vision, then the sight picture
	# settles back. This is optical concussion, not a zoom animation.
	_cam.fov = lerpf(70.0, 52.0, smoothstep(0.0, 1.0, rifle_aim)) \
			+ rifle_pressure * 4.2
	if target.has_method("update_deck_bag_pose"):
		target.update_deck_bag_pose(delta, _cam, _bag_focus)
	_refresh_bag_hand()
	if _arms != null:
		if _arms.has_method("set_watch"):
			# B is a HOLD: the arm is up while the button is, gone when it is
			# not. No toggle to forget about with your hand across the view.
			_arms.set_watch(
					Input.is_action_pressed("watch") and not _panel_open() \
							and _bag_focus < 0.08,
					float(weather.get("time_of_day")) if weather != null else 12.0,
					float(_walker.get("swim_depth")))
		if _arms.has_method("set_sea_ladder"):
			_arms.set_sea_ladder(_flag(_walker, "on_sea_ladder"), _walker.pos.y)
		_arms.update(delta, target, engaged, walking, _flag(_walker, "swimming"))
	_resolve_active_knife_sweep()
	_update_warmth(delta)


func _resolve_active_rifle_shot(bag: Node3D) -> void:
	if get_world_3d() == null or _cam == null:
		return
	var muzzle := bag.call("active_rifle_muzzle") as Node3D
	var origin := muzzle.global_position if muzzle != null else _cam.global_position
	# The sights own accuracy. Hip fire inherits a small deterministic shoulder
	# cone; ADS sends the ray exactly through the centre line.
	var aim := float(bag.call("rifle_aim_amount"))
	var direction := -_cam.global_basis.z
	if aim < 0.92:
		var spread := deg_to_rad(1.35) * (1.0 - aim)
		direction = direction.rotated(_cam.global_basis.y, sin(Time.get_ticks_msec() * 0.013) * spread)
		direction = direction.rotated(_cam.global_basis.x, cos(Time.get_ticks_msec() * 0.017) * spread)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 900.0)
	if target is CollisionObject3D:
		query.exclude = [(target as CollisionObject3D).get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var collider: Object = hit.get("collider") as Object
	var point: Vector3 = hit.get("position", origin + direction * 900.0)
	if collider != null and collider.has_method("hit_by_rifle"):
		collider.call("hit_by_rifle", 95.0, point, direction)
	if collider is RigidBody3D:
		(collider as RigidBody3D).apply_impulse(direction * 22.0,
				point - (collider as RigidBody3D).global_position)


func _active_bag_item_kind() -> String:
	var bag := _deck_bag()
	if bag == null:
		return ""
	return str(bag.call("active_item_kind"))


func _resolve_active_knife_sweep() -> void:
	var bag := _deck_bag()
	if bag == null or str(bag.call("active_item_kind")) != "utility_knife":
		return
	var sweep: Dictionary = bag.call("active_knife_sweep")
	if sweep.is_empty() or get_world_3d() == null:
		return
	var excluded: Array[RID] = []
	if target is CollisionObject3D:
		excluded.append((target as CollisionObject3D).get_rid())
	var blade_base: Vector3 = sweep.get("blade_base", Vector3.ZERO)
	var blade_tip: Vector3 = sweep.get("blade_tip", Vector3.ZERO)
	var edge := blade_tip - blade_base
	var reach_tip := blade_tip + edge.normalized() * 0.055 \
			if edge.length_squared() > 0.000001 else blade_tip
	var segments := [
		[sweep.get("from", Vector3.ZERO), sweep.get("to", Vector3.ZERO)],
		[blade_base, reach_tip],
	]
	var hit := {}
	for segment in segments:
		var from: Vector3 = segment[0]
		var to: Vector3 = segment[1]
		if from.distance_squared_to(to) < 0.000001:
			continue
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.exclude = excluded
		query.collide_with_areas = true
		hit = get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			break
	if hit.is_empty():
		return
	var collider := hit.get("collider") as Object
	var position: Vector3 = hit.get("position", Vector3.ZERO)
	var normal: Vector3 = hit.get("normal", Vector3.UP)
	bag.call("mark_active_knife_hit", collider, position, normal)
	var receiver := collider as Node
	while receiver != null and receiver != target:
		if receiver.has_method("hit_by_knife"):
			receiver.call("hit_by_knife", 35.0, position, normal)
			break
		if receiver.has_method("take_damage"):
			receiver.call("take_damage", 35.0)
			break
		receiver = receiver.get_parent()


func _tick_stair_step() -> void:
	## One clip per tread. The companionway is ordinary floors 0.223 m apart;
	## the boarding ladder is rungs. Crossing an index is a footfall. Landing
	## on the flight from the sole or the roof does not click.
	if _stair_snd.is_empty() or _walker == null:
		return
	if _flag(_walker, "swimming"):
		_stair_idx = -99
		return
	var p: Vector3 = _walker.pos
	var idx := -99
	if p.x > -1.70 and p.x < -0.46 and p.z > 0.90 and p.z < 4.00 \
			and p.y > 0.82 and p.y < 3.05 and _walker.on_floor:
		idx = int(round((p.y - 0.903) / 0.223))
	elif _flag(_walker, "on_sea_ladder"):
		idx = 100 + int(round((p.y + 1.30) / 0.27))
	if idx != -99 and _stair_idx != -99 and idx != _stair_idx:
		var pl: AudioStreamPlayer = _stair_snd[_stair_voice]
		_stair_voice = (_stair_voice + 1) % _stair_snd.size()
		pl.pitch_scale = randf_range(0.94, 1.08)
		pl.volume_db = randf_range(-11.0, -6.5)
		pl.play()
	_stair_idx = idx


func _occluded(bt: Node3D, from_l: Vector3, to_l: Vector3) -> bool:
	## Segment against the boat's aim blockers, slab method, boat-local. Cheap
	## enough to run per candidate per frame — there is never more than one.
	var blockers: Array = bt.get("aim_blockers")
	if blockers == null or blockers.is_empty():
		return false
	var d: Vector3 = to_l - from_l
	for b: AABB in blockers:
		var t0 := 0.0
		var t1 := 1.0
		var hit := true
		for ax in 3:
			var o: float = from_l[ax]
			var dd: float = d[ax]
			var lo: float = b.position[ax]
			var hi: float = b.position[ax] + b.size[ax]
			if absf(dd) < 1e-6:
				if o < lo or o > hi:
					hit = false
					break
				continue
			var ta: float = (lo - o) / dd
			var tb: float = (hi - o) / dd
			if ta > tb:
				var sw := ta
				ta = tb
				tb = sw
			t0 = maxf(t0, ta)
			t1 = minf(t1, tb)
			if t0 > t1:
				hit = false
				break
		if hit:
			return true
	return false


func _yaw_of(d: Vector3) -> float:
	## The camera's yaw that looks along `d`. Same convention as set_mode().
	return atan2(-d.x, -d.z)


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


func _update_blink(delta: float) -> void:
	if mode != Mode.FPS or _blink_rect == null or _blink_mat == null:
		return
	if _blink_tween != null and _blink_tween.is_running():
		_blink_mat.set_shader_parameter("close", _blink)
		_blink_rect.visible = _blink > 0.004
		return
	_blink_wait -= delta
	if _blink_wait <= 0.0:
		_start_blink()


func _start_blink() -> void:
	if _blink_tween != null:
		_blink_tween.kill()
	_blink = 0.0
	_blink_rect.visible = true
	_blink_tween = create_tween()
	_blink_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_blink_tween.tween_property(self, "_blink", 1.0, 0.055).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_blink_tween.tween_interval(0.035)
	_blink_tween.tween_property(self, "_blink", 0.0, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_blink_tween.finished.connect(_on_blink_finished, CONNECT_ONE_SHOT)


func _on_blink_finished() -> void:
	_blink = 0.0
	if _blink_mat != null:
		_blink_mat.set_shader_parameter("close", 0.0)
	if mode != Mode.FPS:
		_stop_blink()
		return
	if not _blink_again and randf() < 0.18:
		_blink_again = true
		_blink_wait = 0.10
		return
	_blink_again = false
	_blink_wait = randf_range(3.2, 8.5)
	if _blink_rect != null:
		_blink_rect.visible = false


func _stop_blink() -> void:
	if _blink_tween != null:
		_blink_tween.kill()
		_blink_tween = null
	_blink = 0.0
	_blink_again = false
	if _blink_mat != null:
		_blink_mat.set_shader_parameter("close", 0.0)
	if _blink_rect != null:
		_blink_rect.visible = false


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

	# Stove-heat grade. Only in FPS, and never over the underwater pass —
	# two screen-reads stacked is a smear, and you are not warm in the sea.
	_warm_rect = ColorRect.new()
	_warm_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_warm_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_warm_rect.color = Color(1, 1, 1, 1)
	_warm_mat = ShaderMaterial.new()
	_warm_mat.shader = load("res://shaders/warmth.gdshader")
	_warm_rect.material = _warm_mat
	_warm_rect.visible = false
	layer.add_child(_warm_rect)

	# The mask goes on TOP of both — it is between your eye and everything
	# else, including the water. Added last, so it draws last.
	_mask_rect = ColorRect.new()
	_mask_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mask_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mask_rect.color = Color(1, 1, 1, 1)
	_mask_mat = ShaderMaterial.new()
	_mask_mat.shader = load("res://shaders/dive_mask.gdshader")
	_mask_rect.material = _mask_mat
	_mask_rect.visible = false
	layer.add_child(_mask_rect)

	# Your own breath, so it is not positional — it happens inside your head.
	var inh: AudioStream = load("res://assets/audio/inhale.mp3")
	if inh != null:
		# Two voices off one clip: the draw through the regulator, and the same
		# breath let out — slower, deeper, quieter. That pair is the whole sound
		# of being under, and it is the reason a mask feels like a mask.
		_inhale = AudioStreamPlayer.new()
		_inhale.stream = inh
		_inhale.volume_db = -6.0
		add_child(_inhale)
		_exhale = AudioStreamPlayer.new()
		_exhale.stream = inh
		_exhale.volume_db = -13.0
		_exhale.pitch_scale = 0.74
		add_child(_exhale)

	var step: AudioStream = load("res://assets/audio/stair_step.mp3")
	if step != null:
		for _i in 2:
			var p := AudioStreamPlayer.new()
			p.stream = step
			p.volume_db = -8.0
			add_child(p)
			_stair_snd.append(p)


	_motes = GPUParticles3D.new()
	_motes.amount = 280
	_motes.lifetime = 6.5
	_motes.preprocess = 2.5
	_motes.emitting = false
	_motes.transform_align = GPUParticles3D.TRANSFORM_ALIGN_DISABLED
	_motes.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_motes.visibility_aabb = AABB(Vector3(-22, -14, -22), Vector3(44, 28, 44))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(10.0, 6.0, 10.0)
	pm.gravity = Vector3(0, 0.015, 0)
	pm.initial_velocity_min = 0.01
	pm.initial_velocity_max = 0.05
	pm.scale_min = 0.010
	pm.scale_max = 0.028
	pm.color = Color(0.52, 0.58, 0.54, 0.18)
	_motes.process_material = pm
	var q := SphereMesh.new()
	q.radius = 0.005
	q.height = 0.010
	q.radial_segments = 6
	q.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.disable_fog = true
	mat.albedo_color = Color(0.55, 0.62, 0.58, 0.16)
	q.material = mat
	_motes.draw_pass_1 = q
	add_child(_motes)
	_motes.top_level = true

	# Bubbles. Suspended motes tell you the water is dirty; bubbles tell you
	# which way is up, which is the thing you actually lose underwater.
	_bubbles = GPUParticles3D.new()
	_bubbles.amount = 140
	_bubbles.lifetime = 3.6
	_bubbles.preprocess = 1.8
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
	bmat.albedo_color = Color(0.78, 0.92, 0.95, 0.42)
	bmat.roughness = 0.05
	bmat.metallic = 0.0
	bmat.disable_fog = true
	bmat.rim_enabled = true
	bmat.rim = 0.9
	bq.material = bmat
	_bubbles.draw_pass_1 = bq
	add_child(_bubbles)
	_bubbles.top_level = true

	# The diver's own. Small, fast, and off the mouth.
	_breath = GPUParticles3D.new()
	_breath.amount = 40
	_breath.lifetime = 2.6
	_breath.emitting = false
	_breath.transform_align = GPUParticles3D.TRANSFORM_ALIGN_DISABLED
	_breath.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_breath.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_breath.visibility_aabb = AABB(Vector3(-3, -2, -3), Vector3(6, 14, 6))
	var rpm := ParticleProcessMaterial.new()
	rpm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	rpm.emission_sphere_radius = 0.05
	rpm.direction = Vector3(0, 1, 0)
	rpm.spread = 22.0
	rpm.initial_velocity_min = 0.35
	rpm.initial_velocity_max = 0.95
	rpm.gravity = Vector3(0, 1.6, 0)
	rpm.damping_min = 0.05
	rpm.damping_max = 0.25
	rpm.scale_min = 0.35
	rpm.scale_max = 1.25
	_breath.process_material = rpm
	_breath.draw_pass_1 = bq
	add_child(_breath)
	_breath.top_level = true


func _update_underwater() -> void:
	if ocean == null or _cam == null:
		return
	var wh: float = ocean.get_height(_cam.global_position)
	var depth := wh - _cam.global_position.y
	var under := depth > 0.025
	# A real eye crosses the meniscus over centimetres, not one boolean frame.
	# Fade the lens treatment through that band while the world/ocean switch at
	# its middle; this removes the cyan full-screen pop on every wave crossing.
	var submerge_fade := smoothstep(-0.035, 0.16, depth)
	ocean.camera_under = under
	if weather != null and weather.has_method("set_underwater"):
		weather.set_underwater(under)
	if _under_rect != null:
		_under_rect.visible = submerge_fade > 0.002
	if _warm_rect != null and under:
		_warm_rect.visible = false
	if submerge_fade > 0.002 and _under_mat != null:
		_under_mat.set_shader_parameter("amount", submerge_fade)
		_under_mat.set_shader_parameter("wave_time", ocean.wave_time)
		_under_mat.set_shader_parameter("depth_m", maxf(depth, 0.0))
		_under_mat.set_shader_parameter("look_down",
				clampf(-_cam.global_basis.z.y, 0.0, 1.0))
	if _motes != null:
		_motes.emitting = under
		if under:
			_motes.global_position = _cam.global_position
	if _bubbles != null:
		_bubbles.emitting = under
		if under:
			_bubbles.global_position = _cam.global_position + Vector3(0.0, -2.0, 0.0)
	_update_breath(under)
	_update_mask(get_process_delta_time(), under)
	if submerge_fade > 0.002 and _under_mat != null and weather != null \
			and weather.has_method("sun_direction"):
		# Bloom toward the real sun/moon. Night is a silver wash, not blades.
		var sd: Vector3 = weather.sun_direction()
		var vp := get_viewport().get_visible_rect().size
		var ss := Vector2(0.5, -0.35)
		var local := _cam.global_basis.inverse() * sd
		if local.z < -0.05:  # in front of the camera
			var p2 := _cam.unproject_position(_cam.global_position + sd * 200.0)
			ss = Vector2(p2.x / maxf(vp.x, 1.0), p2.y / maxf(vp.y, 1.0))
			ss = ss.clamp(Vector2(-1.0, -1.0), Vector2(2.0, 2.0))
		_under_mat.set_shader_parameter("sun_screen", ss)
		var night := false
		if weather.has_method("is_night"):
			night = weather.is_night()
		var stormy := false
		if "storm" in weather:
			stormy = weather.storm
		var shaft := 0.62 if night else 1.05
		if stormy:
			shaft *= 0.50
		if sd.y < 0.05:
			shaft *= 0.28
		_under_mat.set_shader_parameter("shaft_energy", shaft)
		_under_mat.set_shader_parameter("lamp_tight", 0.48 if night else 1.15)
		var tint := Color(0.70, 0.80, 0.96) if night else Color(1.0, 0.90, 0.62)
		if weather.has_method("sun_tint"):
			var st: Color = weather.sun_tint()
			tint = tint.lerp(st, 0.45)
		_under_mat.set_shader_parameter("shaft_color", tint)


func _update_mask(delta: float, under: bool) -> void:
	## The mask, from the moment it leaves the hook to the finger that clears
	## it. Nothing here decides whether you are WEARING it — boat.gd owns that,
	## because the thing is either on the hook or on your face and one of those
	## is a fitting on the ship.
	if _mask_rect == null or target == null:
		return
	var wear := 0.0
	if target.has_method("gear_wear_t"):
		var gt: Variant = target.call("gear_wear_t")
		if typeof(gt) == TYPE_FLOAT:
			wear = gt
		elif typeof(gt) == TYPE_INT:
			wear = float(gt)
	var worn: bool = wear > 0.001 and mode == Mode.FPS
	_mask_rect.visible = worn
	if not worn:
		_fog = 0.0
		_wipe = 0.0
		_drops = 0.0
		_drop_wipe = 0.0
		_br_t = 0.0
		_br_in = true
		_breath_amt = 0.0
		_mask_was_under = false
		return
	_breathe(delta, under)
	if under and not _mask_was_under:
		_drops = 1.0
	_mask_was_under = under
	if under:
		_drops = minf(_drops + delta * 1.6, 1.0)
	else:
		var rain_now := _rain()
		_drops = minf(_drops + rain_now * delta * 0.40, 0.92)
		_drops = maxf(_drops - delta * 0.018 * (1.0 - rain_now), 0.0)
	if _drop_wipe > 0.0:
		_drop_wipe = maxf(_drop_wipe - delta / 0.9, 0.0)
		if _drop_wipe <= 0.0:
			# A wipe takes the middle. Corners and the skirt keep their beads.
			_drops = maxf(_drops * 0.20, 0.14)
	# Condensation. It only really builds once the glass is cold, which is to
	# say in the water; in air it creeps.
	if _wipe > 0.0:
		_wipe = maxf(_wipe - delta / 0.9, 0.0)
		if _wipe <= 0.0:
			# Fog wipe does not touch the water on the glass. What is left of
			# the vapour is a film in the corners, which is where it starts again.
			_fog = 0.08
	elif wear > 0.98:
		# Same clock in air and water: the front crawls from the skirt over
		# minutes. A dive does not ice the glass; it is still your breath.
		_fog = minf(_fog + delta / FOG_DRY, 1.0)
		if not _br_in:
			_fog = minf(_fog + delta * 0.006, 1.0)
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_mask_mat.set_shader_parameter("wear", wear)
	_mask_mat.set_shader_parameter("fog", _fog)
	_mask_mat.set_shader_parameter("wipe", _wipe)
	_mask_mat.set_shader_parameter("drops", _drops)
	_mask_mat.set_shader_parameter("drop_wipe", _drop_wipe)
	# The clear front is the FINGER, not a timer. Ask the hand where it is.
	if (_wipe > 0.0 or _drop_wipe > 0.0) and _arms != null \
			and _arms.has_method("wipe_front"):
		var wf: Vector2 = _arms.wipe_front()
		_mask_mat.set_shader_parameter("wipe_x", wf.x)
		_mask_mat.set_shader_parameter("wipe_dir", wf.y)
	_mask_mat.set_shader_parameter("underwater", 1.0 if under else 0.0)
	_mask_mat.set_shader_parameter("aspect", maxf(vp.x, 1.0) / maxf(vp.y, 1.0))
	if ocean != null:
		_mask_mat.set_shader_parameter("wave_time", ocean.wave_time)
	var rain_amt := _rain()
	_mask_mat.set_shader_parameter("rain", rain_amt)
	_breath_amt = lerpf(_breath_amt, 1.0 if not _br_in else 0.0,
			1.0 - exp(-delta * (3.2 if under else 1.6)))
	_mask_mat.set_shader_parameter("breath", _breath_amt)


func _breathe(delta: float, under: bool) -> void:
	## In, pause, out, longer pause. Underwater you hear it through the
	## regulator. On deck you still breathe — the glass fogs from that, silently.
	_br_t -= delta
	if _br_t > 0.0:
		return
	if _br_in:
		if under and _inhale != null:
			_inhale.pitch_scale = randf_range(0.94, 1.07)
			_inhale.volume_db = randf_range(-8.0, -5.0)
			_inhale.play()
		_br_t = randf_range(1.30, 1.75) if under else randf_range(2.8, 4.2)
	else:
		if under and _exhale != null:
			_exhale.pitch_scale = randf_range(0.70, 0.80)
			_exhale.volume_db = randf_range(-15.0, -11.5)
			_exhale.play()
		_br_t = randf_range(2.10, 2.95) if under else randf_range(3.4, 5.0)
	_br_in = not _br_in


func _wipe_mask() -> void:
	## A finger across the inside of the glass. Only worth doing if there is
	## something on it.
	if _fog < 0.09 or _wipe > 0.0 or _drop_wipe > 0.0:
		return
	_wipe = 1.0
	# Where the NEXT one happens. Somewhere between a lens that is just going
	# hazy and one you cannot see out of at all.
	_wipe_at = randf_range(0.72, 0.96)
	if _arms != null and _arms.has_method("face_gesture"):
		_arms.face_gesture("wipe")


func _wipe_drops() -> void:
	## Water on the glass is not fog. A fog wipe leaves it; this is the pass
	## that takes the beads, and even then the skirt keeps a few.
	if not _flag(target, "gear_worn") or _drops < 0.12:
		return
	if _wipe > 0.0 or _drop_wipe > 0.0:
		return
	_drop_wipe = 1.0
	if _arms != null and _arms.has_method("face_gesture"):
		_arms.face_gesture("wipe")


func _update_breath(under: bool) -> void:
	## Bubbles off your own face, but only when it is YOU in the water — the
	## free camera goes under too and it does not breathe.
	if _breath == null or _cam == null:
		return
	var diver: bool = mode == Mode.FPS and _walker != null \
			and (_flag(_walker, "swimming") or _flag(_walker, "on_sea_ladder"))
	var sub: bool = diver and under
	if sub and not _was_sub:
		_breath_burst = 0.75
		_breath.restart()
		# The breath itself is on its own cycle in _breathe(); this is only the
		# lungful of bubbles that goes with the water closing over you.
		_br_t = 0.0
	_was_sub = sub
	_breath_burst = maxf(_breath_burst - get_process_delta_time(), 0.0)
	_breath.emitting = sub
	# One lungful as the water closes over you, then the slow leak of a held
	# breath. amount_ratio IS the emission rate, so this is literally that.
	_breath.amount_ratio = 1.0 if _breath_burst > 0.0 else 0.18
	if sub:
		_breath.global_position = _cam.global_position \
				+ (-_cam.global_basis.z) * 0.17 - _cam.global_basis.y * 0.09


func _update_warmth(delta: float) -> void:
	## The cabin when the heater is on. No slow acclimate — the colour
	## arrives with the bars.
	if target == null or not target.has_method("heat_at"):
		return
	var src := 0.0
	var tau := 1.1
	if _walker.swimming:
		src = 0.0
		tau = 1.4
	else:
		src = float(target.heat_at(_walker.pos))
		if src < 0.05 and weather != null:
			src = maxf(src - _rain() * 0.10, 0.0)
		tau = 0.9 if src > _warmth else 1.8
	_warmth = lerpf(_warmth, src, 1.0 - exp(-delta / tau))
	if _warm_rect == null or _warm_mat == null:
		return
	var show := _warmth > 0.16
	_warm_rect.visible = show
	if not show:
		return
	var close := clampf((_warmth - 0.72) / 0.28, 0.0, 1.0)
	_warm_mat.set_shader_parameter("warmth", clampf((_warmth - 0.16) / 0.84, 0.0, 1.0))
	_warm_mat.set_shader_parameter("close", close)
	if ocean != null:
		_warm_mat.set_shader_parameter("wave_time", ocean.wave_time)


func _rain() -> float:
	var w := weather as WeatherScript
	return clampf(w.rain_amount, 0.0, 1.0) if w != null else 0.0


func _flag(obj: Object, key: String) -> bool:
	return obj != null and obj.get(key) == true


func _inum(obj: Object, key: String) -> int:
	if obj == null:
		return 0
	var v: Variant = obj.get(key)
	if typeof(v) == TYPE_INT:
		return v
	if typeof(v) == TYPE_FLOAT:
		return int(v)
	return 0
