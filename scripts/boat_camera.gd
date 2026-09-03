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
const CameraWarmthEffectScript := preload("res://scripts/camera_warmth_effect.gd")
const CameraUnderwaterEffectScript := preload("res://scripts/camera_underwater_effect.gd")
const CameraMaskEffectScript := preload("res://scripts/camera_mask_effect.gd")
const CameraBlinkEffectScript := preload("res://scripts/camera_blink_effect.gd")
const DeckBagInteractionStateScript := preload("res://scripts/deck_bag_interaction_state.gd")
const CameraInteractionSelectorScript := preload("res://scripts/camera_interaction_selector.gd")
const CameraPromptPresenterScript := preload("res://scripts/camera_prompt_presenter.gd")
const CameraFpsLocomotionScript := preload("res://scripts/camera_fps_locomotion.gd")
const CameraEyeMotionScript := preload("res://scripts/camera_eye_motion.gd")

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

## WRAD arms terminate inside the torso. Free look may inspect the floor, but
## a planted/loaded hand cannot follow that view without exposing the open
## shoulder ends.  -0.56 rad is the last angle where both shoulder caps remain
## behind the camera on the 70-degree gameplay lens.
const FREE_LOOK_DOWN_LIMIT := -1.40
const HELD_LOOK_DOWN_LIMIT := -0.56
const HELM_LOOK_DOWN_LIMIT := -1.02
const LOOK_UP_LIMIT := 1.40



var _cam: Camera3D
var _orbiting := false
var _underwater_effect: CameraUnderwaterEffect = CameraUnderwaterEffectScript.new()
var _warmth_effect: CameraWarmthEffect = CameraWarmthEffectScript.new()
var _prompt: Label
var _walker: RefCounted = (load("res://scripts/deck_walker.gd") as GDScript).new()
var _initial_shore_spawn := Vector3.INF
var _initial_shore_look := Vector3.ZERO
var _has_initial_shore_spawn := false
var _roll := 0.0
var _ship_pitch := 0.0
var _panel: Node = null
var _hand_editor: Node
var _last_aim := ""
var _interaction_selector: CameraInteractionSelector = CameraInteractionSelectorScript.new()
var _prompt_presenter: CameraPromptPresenter = CameraPromptPresenterScript.new()
var _fps_locomotion: CameraFpsLocomotion = CameraFpsLocomotionScript.new()
var _eye_motion: CameraEyeMotion = CameraEyeMotionScript.new()
## Your own breath. Separate from the ambient field: those bubbles say the sea
## is aerated, these say YOU are down here and holding it — they come off your
## face, they burst as the water closes over you, and they trickle after.
var _was_ladder := false
## The mask. `_fog` is condensation on the inside of the glass, `_wipe` is the
## finger crossing it — 1 at the start of the sweep, 0 when it is clear.
var _mask_effect: CameraMaskEffect = CameraMaskEffectScript.new()
var _fog: float:
	get: return _mask_effect.fog
	set(value): _mask_effect.fog = value
var _wipe: float:
	get: return _mask_effect.wipe
	set(value): _mask_effect.wipe = value
var _stair_snd: Array[AudioStreamPlayer] = []
var _stair_voice := 0
var _stair_idx := -99
## The breath cycle, and the level of fog at which the next automatic clear
## happens. Both are deliberately irregular: a diver does not breathe to a
## metronome and does not clear their mask on a schedule either.
var _drops: float:
	get: return _mask_effect.drops
	set(value): _mask_effect.drops = value
var _drop_wipe: float:
	get: return _mask_effect.drop_wipe
	set(value): _mask_effect.drop_wipe = value
var _arms: Node
var _reticle: Control
var _blink_effect: CameraBlinkEffect = CameraBlinkEffectScript.new()
var _blink_wait: float:
	get: return _blink_effect.wait()
	set(value): _blink_effect.set_wait(value)
var _camera_attrs: CameraAttributesPractical
## The deck bag is body-worn. I swings it from the right shoulder into the
## lap; the continuous amount drives body weight, focus and the real 3D prop.
var _bag_state: DeckBagInteractionState = DeckBagInteractionStateScript.new()
var _bag_open: bool:
	get: return _bag_state.open
	set(value): _bag_state.open = value
var _bag_focus: float:
	get: return _bag_state.focus
	set(value): _bag_state.focus = value
var _bag_saved_yaw: float:
	get: return _bag_state.saved_yaw
	set(value): _bag_state.saved_yaw = value
var _bag_saved_pitch: float:
	get: return _bag_state.saved_pitch
	set(value): _bag_state.saved_pitch = value
var _bag_selected: int:
	get: return _bag_state.selected
	set(value): _bag_state.selected = value
var _bag_take_pending: bool:
	get: return _bag_state.take_pending
	set(value): _bag_state.take_pending = value


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
	# ADS rear notch is 0.475 m from the eye. Blur only in front of that
	# plane so the notch and front post stay readable along the sight line.
	_camera_attrs.dof_blur_near_enabled = false
	_camera_attrs.dof_blur_near_distance = 0.45
	_camera_attrs.dof_blur_near_transition = 0.24
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

	# Eyelids sit in front of the view, reticle and interaction prompt.
	add_child(_blink_effect)
	_blink_effect.setup(pl)


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
			return bool(_walker.grab_sea_ladder(target))
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
			_eye_motion.reset()
			_roll = 0.0
			_ship_pitch = 0.0
			if _arms != null:
				_arms.set_active(true)
			# start looking where the boat points, standing at the wheel
			if target != null:
				var fwd := -target.global_basis.z
				if _has_initial_shore_spawn:
					_walker.spawn_ashore(_initial_shore_spawn, target)
					if _initial_shore_look.is_finite() \
							and _initial_shore_look.length_squared() > 0.01:
						fwd = (_initial_shore_look - _initial_shore_spawn).normalized()
					_has_initial_shore_spawn = false
					target.set("helm_engaged", false)
				else:
					_walker.spawn_at(target.CREW_START)
					target.set("helm_engaged", true)
				yaw = atan2(-fwd.x, -fwd.z)
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


func set_initial_shore_spawn(world_pos: Vector3, look_at: Vector3) -> void:
	_initial_shore_spawn = world_pos
	_initial_shore_look = look_at
	_has_initial_shore_spawn = true


func _panel_open() -> bool:
	if _panel == null or not is_instance_valid(_panel):
		_panel = get_tree().get_first_node_in_group("ui_panel")
	return _panel != null and _panel.has_method("is_open") and _panel.is_open()


func _editor_open() -> bool:
	## The hand editor (P) takes the POINTER for its sliders and gizmo and
	## nothing else: keys, aim and reload keep working so the grip being tuned
	## can be put through its motions while the panel is up.
	if _hand_editor == null or not is_instance_valid(_hand_editor):
		_hand_editor = get_tree().get_first_node_in_group("hand_editor")
	return _hand_editor != null and _hand_editor.has_method("wants_pointer") \
			and _hand_editor.wants_pointer()


func _view_pitch_guard_active() -> bool:
	# Check control state directly as well as the hand rig so the limit is active
	# on the exact frame E takes hold, before the per-hand claim has settled.
	if target != null and (_flag(target, "helm_engaged") \
			or _flag(target, "telegraph_engaged")):
		return true
	if _flag(_walker, "on_sea_ladder"):
		return true
	return _arms != null and _arms.has_method("view_pitch_guard_active") \
			and bool(_arms.call("view_pitch_guard_active"))


func _look_down_limit() -> float:
	## A helmsman must be able to inspect and work the key below the wheel.
	## Carried tools move with the body/camera and must not lock the player's
	## neck: a knife is especially needed at feet, ropes and low objects. Fixed
	## controls and the ladder retain their authored shoulder-safe limits.
	if target != null and _flag(target, "helm_engaged"):
		return HELM_LOOK_DOWN_LIMIT
	var carried_bag := _deck_bag()
	if carried_bag != null and carried_bag.has_method("active_item_kind") \
			and str(carried_bag.call("active_item_kind")) != "":
		return FREE_LOOK_DOWN_LIMIT
	return HELD_LOOK_DOWN_LIMIT if _view_pitch_guard_active() \
			else FREE_LOOK_DOWN_LIMIT


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
			_trigger_rifle_blink(fire_bag)
			_resolve_active_rifle_shot(fire_bag)
			get_viewport().set_input_as_handled()
			return
	if mode == Mode.FPS and _bag_open and _bag_focus > 0.58:
		if event.is_action_pressed("bag_left"):
			_move_bag_selection(Vector2i.LEFT)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("bag_right"):
			_move_bag_selection(Vector2i.RIGHT)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("bag_up"):
			_move_bag_selection(Vector2i.UP)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("bag_down"):
			_move_bag_selection(Vector2i.DOWN)
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
		if _panel_open() or _editor_open():
			return
		if mode == Mode.FPS and _bag_focus > 0.03:
			return # the neck and eyes are committed to the bag in the lap
		if mode == Mode.FPS and _eye_motion.chart_t > 0.0 and _eye_motion.chart_t < 1.0:
			return                      # leaning in; the camera is driving
		if mode == Mode.FPS:
			_look_yaw -= event.relative.x * FPS_LOOK
			var down_limit := _look_down_limit()
			_look_pitch = clampf(_look_pitch - event.relative.y * FPS_LOOK,
					down_limit, LOOK_UP_LIMIT)
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
	_bag_state.set_open(open, yaw, pitch)
	if open:
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
	_bag_state.shift(direction, count)


func _move_bag_selection(direction: Vector2i) -> void:
	## Four tools form the upper row; the rifle is the full-width lower row.
	## Down/S always reaches it in one press. Up/W returns to the exact tool the
	## player came from, while A/D stays within the upper row.
	var bag := _deck_bag()
	if bag != null:
		_bag_state.move(direction, int(bag.call("slot_count")))


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
		# Keep the bag presented while the fingers close and the prop clears its
		# restraint. The ordinary close begins only after that physical extraction.
		_bag_take_pending = true
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
		var support := bag.call("rifle_support_target") as Node3D \
				if bool(bag.call("rifle_support_required")) else null
		_arms.set_rifle_hands(bag.call("rifle_primary_target") as Node3D,
				support)
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
	_bag_state.reset()
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
		_camera_attrs.dof_blur_near_enabled = false
		_camera_attrs.dof_blur_far_enabled = false
		_camera_attrs.dof_blur_amount = 0.0


func _update_deck_bag(delta: float) -> void:
	if _bag_open and (_flag(_walker, "swimming") \
			or _flag(_walker, "on_sea_ladder")):
		_bag_open = false
	_bag_state.update_focus(delta)
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
		var bag_blur := smoothstep(0.18, 0.86, _bag_focus)
		var sight_blur := smoothstep(0.15, 1.0, aim_blur) * (1.0 - bag_blur)
		_camera_attrs.dof_blur_near_enabled = sight_blur > 0.01
		# Looking into the bag still focuses nearby; aiming no longer blurs
		# the distant target. The receiver and hands soften toward the eye.
		_camera_attrs.dof_blur_far_enabled = bag_blur > 0.01
		_camera_attrs.dof_blur_far_distance = lerpf(2.4, 0.82, bag_blur)
		_camera_attrs.dof_blur_far_transition = lerpf(1.6, 0.42, bag_blur)
		_camera_attrs.dof_blur_amount = maxf(0.18 * bag_blur, 0.22 * sight_blur)
	var bag := _deck_bag()
	if bag != null:
		if _bag_take_pending and bool(bag.call("take_extraction_complete")):
			_bag_take_pending = false
			set_bag_open(false)
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
		_warmth_effect.hide()
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
	var want := Input.MOUSE_MODE_VISIBLE if _panel_open() or _editor_open() \
			else Input.MOUSE_MODE_CAPTURED
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

	var selection: Dictionary = _interaction_selector.select(target, eye,
			look_l, engaged, _bag_focus, _last_aim, _arms, _occluded)
	var cand: Dictionary = selection["candidate"]
	_last_aim = str(selection["last_aim"])

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

	var prompt_bag := _deck_bag()
	_prompt_presenter.update(_prompt, _bag_focus, _bag_selected, prompt_bag,
			_active_bag_item_kind(), _walker, target, engaged, _arms, cand,
			_drops, _drop_wipe, _fog, _wipe)

	_fps_locomotion.update(delta, target, _walker, engaged, xf, look_fwd,
			_cam.global_basis.x, _panel_open(), _bag_focus, _tick_stair_step)

	var eye_result: Dictionary = _eye_motion.update(delta, target, _walker,
			engaged, xf, _cam.global_basis, _arms, _bag_focus, ocean)
	var walking: float = float(eye_result["walking"])
	var bag_load_arc: float = float(eye_result["bag_load_arc"])
	var cam_pos: Vector3 = eye_result["position"] as Vector3
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
	elif engaged == "chart" and _eye_motion.chart_t < 1.0:
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

	# Entering a hold while already looking at the floor must close the shoulder
	# seam on that same frame. Subsequent mouse input is clamped above, so this is
	# normally a one-shot correction rather than a continuously driven camera.
	if _view_pitch_guard_active():
		var down_limit := _look_down_limit()
		pitch = maxf(pitch, down_limit)
		_look_pitch = maxf(_look_pitch, down_limit)

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

	var held_bag := _deck_bag()
	var rifle_aim := float(held_bag.call("rifle_aim_amount")) \
			if held_bag != null and held_bag.has_method("rifle_aim_amount") else 0.0
	var manipulating := engaged != "" or _bag_focus > 0.15 or rifle_aim > 0.15
	if _arms != null and _arms.has_method("inspecting_id"):
		manipulating = manipulating or str(_arms.call("inspecting_id")) != ""
	var space := &"deck"
	if target.has_method("acoustic_space"):
		space = target.call("acoustic_space", cam_pos) as StringName
	var roll_follow := 0.24
	var pitch_follow := 0.15
	var roll_limit := deg_to_rad(6.3)
	var pitch_limit := deg_to_rad(5.0)
	if space == &"wheelhouse":
		roll_follow = 0.45
		pitch_follow = 0.35
		roll_limit = deg_to_rad(9.0)
		pitch_limit = deg_to_rad(8.0)
	elif space == &"cabin":
		roll_follow = 0.65
		pitch_follow = 0.50
		roll_limit = deg_to_rad(13.0)
		pitch_limit = deg_to_rad(10.0)
	if manipulating:
		roll_follow = 0.75
		pitch_follow = 0.60
		roll_limit = deg_to_rad(15.0)
		pitch_limit = deg_to_rad(12.0)
	var heel := asin(clampf(xf.basis.x.y, -1.0, 1.0))
	var vessel_pitch := asin(clampf(-xf.basis.z.y, -1.0, 1.0))
	var bag_roll := bag_load_arc * 0.025
	var roll_goal := _soft_limit_angle(heel * roll_follow,
			roll_limit * 0.68, roll_limit) + bag_roll
	var pitch_goal := _soft_limit_angle(vessel_pitch * pitch_follow,
			pitch_limit * 0.68, pitch_limit)
	# Both land and open water are world-space player states. The vessel may be
	# hundreds of metres away, so none of its heel or pitch belongs in the view.
	if _flag(_walker, "ashore") or _flag(_walker, "swimming"):
		roll_goal = bag_roll
		pitch_goal = 0.0
	_roll = lerpf(_roll, roll_goal, 1.0 - exp(-6.0 * delta))
	_ship_pitch = lerpf(_ship_pitch, pitch_goal, 1.0 - exp(-7.0 * delta))
	var knife_kick := Vector3.ZERO
	var rifle_kick := Vector3.ZERO
	if held_bag != null and held_bag.has_method("active_knife_camera_kick"):
		knife_kick = held_bag.call("active_knife_camera_kick") as Vector3
	if held_bag != null and held_bag.has_method("active_rifle_camera_kick"):
		rifle_kick = held_bag.call("active_rifle_camera_kick") as Vector3
	var total_kick := knife_kick + rifle_kick
	_cam.global_basis = Basis(Vector3.UP, yaw + total_kick.y) \
			* Basis(Vector3.RIGHT, pitch + _ship_pitch + total_kick.x) \
			* Basis(Vector3.BACK, _roll + total_kick.z)
	var rifle_pressure := float(held_bag.call("active_rifle_pressure")) \
			if held_bag != null and held_bag.has_method("active_rifle_pressure") else 0.0
	# The shock front briefly opens peripheral vision, then the sight picture
	# settles back. This is optical concussion, not a zoom animation.
	_cam.fov = lerpf(70.0, 52.0, smoothstep(0.0, 1.0, rifle_aim)) \
			+ rifle_pressure * 1.35
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
			_arms.set_sea_ladder(_flag(_walker, "on_sea_ladder"), _walker.pos.y,
					float(_walker.get("sea_ladder_mantle")))
		_arms.update(delta, target, engaged, walking, _flag(_walker, "swimming"))
	_resolve_active_knife_sweep()
	_warmth_effect.tick(delta, target, _walker, weather, ocean)


func _soft_limit_angle(angle: float, knee: float, maximum: float) -> float:
	## Exactly linear through ordinary motion, then progressively compresses
	## exceptional rolls/slams instead of hitting a visible hard camera clamp.
	var magnitude := absf(angle)
	if magnitude <= knee or maximum <= knee:
		return angle
	var tail := maximum - knee
	var compressed := knee + tail * (1.0 - exp(-(magnitude - knee) / tail))
	return signf(angle) * minf(compressed, maximum)


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
	var solid_distance := origin.distance_to(hit.get("position") as Vector3) \
			if not hit.is_empty() else 900.0
	var water_hit := _rifle_water_intersection(origin, direction, solid_distance)
	if water_hit != Vector3.INF:
		if ocean != null and ocean.has_method("bullet_impact"):
			ocean.call("bullet_impact", water_hit, direction)
		return
	if hit.is_empty():
		return
	var collider: Object = hit.get("collider") as Object
	var point: Vector3 = hit.get("position", origin + direction * 900.0)
	if collider != null and collider.has_method("hit_by_rifle"):
		collider.call("hit_by_rifle", 95.0, point, direction)
	if collider is RigidBody3D:
		(collider as RigidBody3D).apply_impulse(direction * 22.0,
				point - (collider as RigidBody3D).global_position)


func _rifle_water_intersection(origin: Vector3, direction: Vector3,
		maximum_distance: float) -> Vector3:
	## Find the first crossing of the live displaced surface. This is evaluated
	## only once per shot, so a coarse bracket plus bisection is both cheap and
	## robust across steep FFT waves; a flat y=0 plane would visibly miss crests.
	if ocean == null or not ocean.has_method("get_height") \
			or direction.y >= -0.0001 or maximum_distance <= 0.05:
		return Vector3.INF
	var previous_t := 0.05
	var previous_point := origin + direction * previous_t
	var previous_gap := previous_point.y - float(ocean.get_height(previous_point))
	if previous_gap <= 0.0:
		return Vector3.INF
	const STEPS := 96
	for i in range(1, STEPS + 1):
		var t := maximum_distance * float(i) / float(STEPS)
		var point := origin + direction * t
		var gap := point.y - float(ocean.get_height(point))
		if gap <= 0.0 and previous_gap > 0.0:
			var low := previous_t
			var high := t
			for _iteration in 12:
				var middle := (low + high) * 0.5
				var middle_point := origin + direction * middle
				var middle_gap := middle_point.y \
						- float(ocean.get_height(middle_point))
				if middle_gap > 0.0:
					low = middle
				else:
					high = middle
			var hit_t := (low + high) * 0.5
			var result := origin + direction * hit_t
			result.y = float(ocean.get_height(result))
			return result
		previous_t = t
		previous_gap = gap
	return Vector3.INF


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
	_blink_effect.update(delta, mode == Mode.FPS)


func _trigger_rifle_blink(bag: Node3D) -> void:
	var space := &"deck"
	var openness := 1.0
	if target != null and _cam != null:
		if target.has_method("acoustic_space"):
			space = target.call("acoustic_space", _cam.global_position) as StringName
		if target.has_method("weather_openness"):
			openness = float(target.call("weather_openness", _cam.global_position))
	var aim := float(bag.call("rifle_aim_amount")) \
			if bag.has_method("rifle_aim_amount") else 0.0
	_blink_effect.trigger_shot(space, openness, aim)


func _stop_blink() -> void:
	_blink_effect.stop()


func _build_underwater() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 0
	add_child(layer)
	_underwater_effect.setup(layer, self)

	# Stove heat sits between the underwater pass and the physical mask.
	_warmth_effect.setup(layer)

	# The mask goes on TOP of both — it is between your eye and everything
	# else, including the water. Added last, so it draws last.
	_mask_effect.setup(layer, self, _arms)

	var step: AudioStream = load("res://assets/audio/stair_step.mp3")
	if step != null:
		for _i in 2:
			var p := AudioStreamPlayer.new()
			p.stream = step
			p.volume_db = -8.0
			add_child(p)
			_stair_snd.append(p)




func _update_underwater() -> void:
	var under := _underwater_effect.tick(_cam, ocean, weather)
	if under:
		_warmth_effect.hide()
		_mask_effect.tick(get_process_delta_time(), under, target, ocean, weather,
			_cam, _walker, mode == Mode.FPS)


func _wipe_mask() -> void:
	_mask_effect.wipe_fog()


func _wipe_drops() -> void:
	_mask_effect.wipe_water(_flag(target, "gear_worn"))


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
