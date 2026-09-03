extends CanvasLayer
class_name HandEditor
## The in-game hand editor. P.
##
## Everything a hand does to a thing is a small set of numbers: where the palm
## sits on it, which way the fingers and the palm face, and how far each digit
## curls. Those numbers live in code today and are tuned by editing, running,
## looking, editing again. This panel puts sliders and a draggable gizmo on the
## live values, so the thing in your hand is what you are tuning, and Save
## writes them to data/hand_tuning.json — after which the code's own defaults
## never matter again for that grip.
##
## What can be edited is whatever is IN the hands right now:
##   • a tool from the bag: the rifle's grip markers (trigger, fore-end, bolt,
##     chamber) and the knife's grip
##   • any fitting the player has hold of: its GripMap frame and pose
##   • the finger pose the selected hand is using, digit by digit
## A reload can be scrubbed stop by stop while its markers are tuned
## (see the timeline at the bottom of the panel).
##
## Nothing here runs unless the panel is open (P toggles it). Closing it with unsaved changes
## saves them: a tuning that has been looked at and accepted is not something
## to lose to a forgotten keystroke.

const HAND_TUNING := preload("res://scripts/hands/hand_tuning.gd")
const GRIP_MAP := preload("res://scripts/hands/grip_map.gd")
const RELOAD_STOPS := preload("res://scripts/hands/rifle_reload_stops.gd")
const DECK_BAG := preload("res://scripts/deck_bag.gd")

const DIGITS := ["thumb", "index", "middle", "ring", "pinky"]
const JOINTS := ["knuckle", "mid", "tip"]
const POS_SPAN := 0.12       # slider half-range around the current value, m
const GIZMO_LEN := 0.055
const PICK_PX := 12.0
const SHOT_DIR := "user://hand_editor"

var rig: Node3D            # boat_camera
var boat: Node3D

var _arms: Node             # hands.gd
var _hrig: Node3D           # hand_rig.gd
var _cam: Camera3D
var _open := false
var _poll := 0.0

# --- targets ---------------------------------------------------------------
# {key, label, kind:"marker"|"grip", node, id, side, item}
var _targets: Array = []
var _cur := -1
var _syncing := false

# --- widgets ---------------------------------------------------------------
var _panel: PanelContainer
var _subject: Label
var _target_opt: OptionButton
var _pos_s: Array = []
var _rot_s: Array = []
var _pose_opt: OptionButton
var _pose_lbl: Label
var _finger_s := {}
var _splay_s: HSlider
var _amt_lbl: Label
var _solver_chk: CheckButton
var _bounds_chk: CheckButton
var _gizmo_chk: CheckButton
var _copy_name: LineEdit
var _status: Label
var _timeline: Control
var _seq_box: VBoxContainer
var _stop_opt: OptionButton
var _stop_t: HSlider
var _stop_pose: OptionButton
var _play_btn: Button
var _state_box: VBoxContainer
var _state_opt: OptionButton
var _attack_t: HSlider
var _state := ""            # "", "carry", "sights", "reload", "sling", "hold", "attack"
var _aim_latched := false
var _sling_bag_latched := false

# --- gizmo -----------------------------------------------------------------
var _gizmo: Node3D
var _gizmo_rods: Array = []
var _bounds_box: MeshInstance3D
var _drag_axis := -1
var _drag_rot := false
var _drag_start := Vector2.ZERO
var _press_in_panel := false
## The target's orientation, kept as a BASIS. The three rot sliders only show
## an euler reading of it and apply their own deltas about the target's own
## axes — because both rifle grips sit at an euler singularity (Y = ±90°),
## where the three angles are not independent and rebuilding a basis from
## edited euler numbers spun the grip by tens of degrees.
var _cur_basis := Basis.IDENTITY
var _rot_shown := Vector3.ZERO
## The code's own orientation for the target. The rot sliders read as the
## turn ADDED to it — three zeros mean "as authored", and small turns stay
## small numbers instead of an euler reading that flips at a singularity.
var _base_basis := Basis.IDENTITY

var _undo: Array = []
var _last_pose := ""
var _look_hold := false
var _finger_lock := false
## Which screen edge the panel sits on. It follows the hand being edited to
## the OPPOSITE edge (the idle left hand hangs exactly where a left-docked
## panel would hide it) unless the user has flipped it by hand.
var _dock := "left"
var _dock_manual := false


func setup(p_rig: Node3D, p_boat: Node3D) -> void:
	rig = p_rig
	boat = p_boat


func _ready() -> void:
	add_to_group("hand_editor")
	layer = 6
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_panel()
	_build_gizmo()
	_panel.visible = false
	_gizmo.visible = false
	set_process(false)


func is_open() -> bool:
	return _open


## True while the panel should own the pointer. Holding the middle mouse
## button hands it back to the camera so the hand can be looked at from
## another angle without closing the editor.
func wants_pointer() -> bool:
	return _open and not _look_hold


# --- open / close ----------------------------------------------------------

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("hand_editor"):
		if get_tree().get_first_node_in_group("main_menu") == null:
			set_open(not _open)
			get_viewport().set_input_as_handled()
		return
	if not _open:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			_look_hold = mb.pressed
			if mb.pressed:
				_drag_axis = -1
			get_viewport().set_input_as_handled()
			return
		# A click that is not on the gizmo must not fire the rifle or swing the
		# knife; the editor swallows the left button while it is up.
		if mb.button_index == MOUSE_BUTTON_LEFT and _look_hold:
			return
	if _look_hold:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if k.keycode == KEY_ESCAPE:
			set_open(false)
			get_viewport().set_input_as_handled()
			return
		if k.ctrl_pressed or k.meta_pressed:
			if k.keycode == KEY_S:
				_save()
				get_viewport().set_input_as_handled()
				return
			if k.keycode == KEY_Z:
				_undo_last()
				get_viewport().set_input_as_handled()
				return
	_gizmo_input(event)


func set_open(on: bool) -> void:
	if on == _open:
		return
	if on:
		_arms = rig.get("_arms")
		_cam = rig.get("_cam")
		_hrig = _arms.get("rig") if _arms != null else null
		if _arms == null or _hrig == null or _cam == null:
			push_warning("hand_editor: no hands to edit")
			return
		_open = true
		_panel.visible = true
		_gizmo.visible = _gizmo_chk.button_pressed
		set_process(true)
		_refresh_targets(true)
		_say("open — %s" % HAND_TUNING.save_path())
	else:
		_open = false
		if HAND_TUNING.is_dirty():
			_save()
		_panel.visible = false
		_gizmo.visible = false
		_set_bounds_visible(false)
		_set_state("")
		set_process(false)


# --- panel -----------------------------------------------------------------

func _build_panel() -> void:
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.06, 0.88)
	style.border_color = Color(0.30, 0.34, 0.30)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.anchor_left = 0.0
	_panel.anchor_right = 0.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = 10.0
	_panel.offset_right = 372.0
	_panel.offset_top = 10.0
	_panel.offset_bottom = -10.0
	add_child(_panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 5)
	scroll.add_child(vbox)

	var title := Label.new()
	title.text = "HAND EDITOR"
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", Color(0.85, 0.88, 0.80))
	vbox.add_child(title)
	var hint := Label.new()
	hint.text = "P close · ⌘S save · ⌘Z undo · drag gizmo (⇧ rotates) · hold MMB to look"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.55, 0.58, 0.55))
	vbox.add_child(hint)
	# --- file ----------------------------------------------------------------
	_section(vbox, "FILE")
	var brow := HBoxContainer.new()
	vbox.add_child(brow)
	_button(brow, "Save", func() -> void: _save())
	_button(brow, "Reload file", func() -> void: _reload_file())
	_button(brow, "Undo", func() -> void: _undo_last())
	_button(brow, "Shot", func() -> void: _screenshot())
	_button(brow, "⇄ side", func() -> void:
		_dock_manual = true
		_set_dock("right" if _dock == "left" else "left"))
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 11)
	_status.add_theme_color_override("font_color", Color(0.62, 0.70, 0.62))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_status)


	_subject = Label.new()
	_subject.add_theme_font_size_override("font_size", 13)
	_subject.add_theme_color_override("font_color", Color(0.95, 0.85, 0.60))
	_subject.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_subject)

	_target_opt = OptionButton.new()
	_target_opt.item_selected.connect(func(i: int) -> void: _select_target(i, true))
	vbox.add_child(_target_opt)
	# --- state ---------------------------------------------------------------
	# Which moment of the tool's life the hand is shown in. Chosen here and
	# HELD, so the sights or a mid-swing can be tuned without keeping a mouse
	# button down with the same hand that works the sliders.
	_section(vbox, "WHAT THE HANDS ARE DOING")
	_state_box = VBoxContainer.new()
	vbox.add_child(_state_box)
	var strow := HBoxContainer.new()
	_state_box.add_child(strow)
	var stl := Label.new()
	stl.text = "show"
	stl.add_theme_font_size_override("font_size", 13)
	strow.add_child(stl)
	_state_opt = OptionButton.new()
	_state_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_state_opt.item_selected.connect(func(i: int) -> void: _set_state(_state_opt.get_item_metadata(i)))
	strow.add_child(_state_opt)
	_attack_t = _slider(_state_box, "swing time", "%.2f s", 0.0, 0.62, 0.01, 0.0, 1.0,
			func(v: float) -> void: _seek_attack(v))
	_attack_t.get_meta("label").visible = false
	_attack_t.visible = false
	_state_box.visible = false

	# --- sequence ------------------------------------------------------------
	_section(vbox, "RELOAD — STOP BY STOP")
	_seq_box = VBoxContainer.new()
	vbox.add_child(_seq_box)
	_timeline = Control.new()
	_timeline.custom_minimum_size = Vector2(0, 34)
	_timeline.draw.connect(_draw_timeline)
	_timeline.gui_input.connect(_timeline_input)
	_seq_box.add_child(_timeline)
	var srow := HBoxContainer.new()
	_seq_box.add_child(srow)
	_play_btn = _button(srow, "▶ Play", func() -> void: _seq_toggle_play())
	_button(srow, "◀ stop", func() -> void: _seq_step(-1))
	_button(srow, "stop ▶", func() -> void: _seq_step(1))
	_button(srow, "Leave scrub", func() -> void: _seq_stop_scrub())
	_stop_opt = OptionButton.new()
	_stop_opt.item_selected.connect(func(i: int) -> void: _seq_select_stop(i))
	_seq_box.add_child(_stop_opt)
	_stop_t = _slider(_seq_box, "stop time", "%.2f s", 0.0, 6.0, 0.01, 0.0, 1.0,
			func(v: float) -> void: _seq_set_stop_time(v))
	var sprow := HBoxContainer.new()
	_seq_box.add_child(sprow)
	var spl := Label.new()
	spl.text = "stop pose"
	spl.add_theme_font_size_override("font_size", 13)
	sprow.add_child(spl)
	_stop_pose = OptionButton.new()
	_stop_pose.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stop_pose.item_selected.connect(func(i: int) -> void: _seq_set_stop_pose(i))
	sprow.add_child(_stop_pose)
	_seq_box.visible = false


	# --- frame ---------------------------------------------------------------
	_section(vbox, "WHERE THE HAND SITS")
	for i in 3:
		_pos_s.append(_slider(vbox, "move %s" % ["X", "Y", "Z"][i], "%+.1f mm",
				-POS_SPAN, POS_SPAN, 0.0005, 0.0, 1000.0,
				func(_v: float) -> void: _apply_frame()))
	for i in 3:
		_rot_s.append(_slider(vbox, "turn %s (from default)" % ["X", "Y", "Z"][i], "%+.1f°",
				-180.0, 180.0, 0.5, 0.0, 1.0,
				func(v: float) -> void: _turn(i, v)))
	var frow := HBoxContainer.new()
	vbox.add_child(frow)
	_button(frow, "Reset frame", func() -> void: _reset_frame())
	_button(frow, "Recentre sliders", func() -> void: _sync_from_target())

	# --- fingers -------------------------------------------------------------
	_section(vbox, "FINGERS")
	var prow := HBoxContainer.new()
	vbox.add_child(prow)
	_pose_lbl = Label.new()
	_pose_lbl.text = "pose"
	_pose_lbl.add_theme_font_size_override("font_size", 13)
	prow.add_child(_pose_lbl)
	_pose_opt = OptionButton.new()
	_pose_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pose_opt.item_selected.connect(func(i: int) -> void: _choose_pose(i))
	prow.add_child(_pose_opt)
	_amt_lbl = Label.new()
	_amt_lbl.add_theme_font_size_override("font_size", 11)
	_amt_lbl.add_theme_color_override("font_color", Color(0.55, 0.58, 0.55))
	vbox.add_child(_amt_lbl)
	for d: String in DIGITS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		vbox.add_child(row)
		var dl := Label.new()
		dl.text = d
		dl.custom_minimum_size = Vector2(52, 0)
		dl.add_theme_font_size_override("font_size", 12)
		row.add_child(dl)
		var trio: Array = []
		for j in 3:
			var s := HSlider.new()
			s.min_value = -0.30
			s.max_value = 1.90
			s.step = 0.01
			s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			s.custom_minimum_size = Vector2(0, 16)
			s.tooltip_text = "%s %s (rad)" % [d, JOINTS[j]]
			s.drag_started.connect(func() -> void: _push_undo())
			s.value_changed.connect(func(_v: float) -> void: _apply_pose())
			row.add_child(s)
			trio.append(s)
		_finger_s[d] = trio
	_splay_s = _slider(vbox, "thumb splay", "%+.2f rad", -0.8, 0.8, 0.01, 0.0, 1.0,
			func(_v: float) -> void: _apply_pose())
	var crow := HBoxContainer.new()
	vbox.add_child(crow)
	_copy_name = LineEdit.new()
	_copy_name.placeholder_text = "new pose name"
	_copy_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	crow.add_child(_copy_name)
	_button(crow, "Copy as", func() -> void: _copy_pose())
	_button(crow, "Reset pose", func() -> void: _reset_pose())
	var mrow := HBoxContainer.new()
	vbox.add_child(mrow)
	_button(mrow, "Give this grip its own pose",
			func() -> void: _private_pose())

	# --- solver / view -------------------------------------------------------
	_section(vbox, "SOLVER AND VIEW")
	_solver_chk = CheckButton.new()
	_solver_chk.text = "finger contact solver"
	_solver_chk.button_pressed = true
	_solver_chk.toggled.connect(func(on: bool) -> void:
		if _hrig != null:
			_hrig.set("contact_solver_enabled", on))
	vbox.add_child(_solver_chk)
	_bounds_chk = CheckButton.new()
	_bounds_chk.text = "draw contact bounds"
	vbox.add_child(_bounds_chk)
	_gizmo_chk = CheckButton.new()
	_gizmo_chk.text = "gizmo"
	_gizmo_chk.button_pressed = true
	_gizmo_chk.toggled.connect(func(on: bool) -> void: _gizmo.visible = on and _open)
	vbox.add_child(_gizmo_chk)




func _section(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(0.55, 0.72, 0.62))
	parent.add_child(l)
	var sep := HSeparator.new()
	parent.add_child(sep)


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 12)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _slider(parent: Control, label_text: String, fmt: String, minv: float,
		maxv: float, step: float, value: float, show_scale: float,
		cb: Callable) -> HSlider:
	var lab := Label.new()
	lab.add_theme_font_size_override("font_size", 12)
	lab.add_theme_color_override("font_color", Color(0.72, 0.76, 0.72))
	lab.text = "%s: %s" % [label_text, fmt % (value * show_scale)]
	parent.add_child(lab)
	var s := HSlider.new()
	s.min_value = minv
	s.max_value = maxv
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(0, 16)
	s.set_meta("label", lab)
	s.set_meta("label_text", label_text)
	s.set_meta("fmt", fmt)
	s.set_meta("show_scale", show_scale)
	s.drag_started.connect(func() -> void: _push_undo())
	s.value_changed.connect(func(v: float) -> void:
		lab.text = "%s: %s" % [label_text, fmt % (v * show_scale)]
		if not _syncing:
			cb.call(v))
	parent.add_child(s)
	return s


func _set_quiet(s: HSlider, v: float) -> void:
	_syncing = true
	s.set_value_no_signal(v)
	var lab: Label = s.get_meta("label") if s.has_meta("label") else null
	if lab != null:
		lab.text = "%s: %s" % [s.get_meta("label_text"),
				str(s.get_meta("fmt")) % (v * float(s.get_meta("show_scale")))]
	_syncing = false


func _say(msg: String) -> void:
	_status.text = ("● " if HAND_TUNING.is_dirty() else "") + msg


# --- targets ---------------------------------------------------------------

func _process(delta: float) -> void:
	if not _open:
		return
	_poll -= delta
	if _poll <= 0.0:
		_poll = 0.30
		_refresh_targets(false)
	_place_gizmo()
	_update_bounds()
	_seq_tick(delta)
	# The pose a hand is using can change under us (reload phases).
	var t := _target()
	if not t.is_empty():
		var live := _live_pose_name(t)
		if live != _last_pose:
			_sync_pose(t)
		var away := 0.0 if t["kind"] == "weapon" else _hand_distance(t)
		if away > 0.075:
			_amt_lbl.text = "%s hand is %.0f cm away from this — nothing here will look like it moves. Pick a STATE that puts it on." % [
					t["side"], away * 100.0]
		elif not _finger_lock and _pose_users(_last_pose).size() <= 1:
			_amt_lbl.text = "%s hand on it · pose amount %.2f · solver %s" % [t["side"],
					_hrig.call("pose_amount", t["side"]),
					"on" if bool(_hrig.get("contact_solver_enabled")) else "off"]
	_timeline.queue_redraw()


func _collect_targets() -> Array:
	var out: Array = []
	var bag: Node3D = rig.call("_deck_bag") as Node3D
	if bag != null:
		var kind := str(bag.call("active_item_kind"))
		var item: Node3D = bag.get("_active_item") as Node3D
		if item != null and kind == "hunting_rifle":
			# node, plain name, hand, and the state that actually puts that
			# hand on it — a fore-end grip means nothing in low carry, where
			# the rifle is held with the trigger hand alone.
			# The bolt marker is the CLOSED knob; during the reload the metal
			# has travelled rearward, and the hand is on the travelled frame.
			# `live` names the method that reports it, so the gizmo and the
			# "is a hand on this?" reading follow the hand, while the edit
			# still writes the marker the live frame is derived from.
			# node, plain name, hand, the states in which that hand is really
			# on it, the state to switch to when it is not, the reload stop
			# to scrub to, and the method reporting its live (animated) frame.
			# Aiming is not tunable here: that hold comes off the sight line.
			out.append({"key": "rifle/Hold",
					"label": "Rifle · the weapon itself",
					"kind": "weapon", "node": null, "item": item, "side": "R",
					"ok_states": ["carry", "reload", "sling"],
					"needs": "carry", "needs_stop": "", "live": ""})
			for spec: Array in [
					["PrimaryGrip", "trigger hand", "R",
							["carry", "sights", "sling"], "carry", "", ""],
					["SupportGrip", "fore-end hand", "L",
							["sights", "reload"], "sights", "", ""],
					["BoltHandle", "bolt knob", "R",
							["reload"], "reload", "bolt_open_end",
							"bolt_grip_transform"],
					["Chamber", "chamber / round", "R",
							["reload"], "reload", "cartridge_insert", ""]]:
				var n := item.get_node_or_null(str(spec[0])) as Node3D
				if n != null:
					out.append({"key": "rifle/" + str(spec[0]),
							"label": "Rifle · %s (%s)" % [spec[1], spec[2]],
							"kind": "marker", "node": n, "item": item,
							"side": str(spec[2]), "ok_states": spec[3],
							"needs": str(spec[4]),
							"needs_stop": str(spec[5]), "live": str(spec[6])})
		elif item != null and kind == "utility_knife":
			var n := item.get_node_or_null("Grip") as Node3D
			if n != null:
				out.append({"key": "knife/Grip", "label": "Knife · handle (R)",
						"kind": "marker", "node": n, "item": item, "side": "R",
						"ok_states": ["hold", "attack"], "needs": "hold",
						"needs_stop": "", "live": ""})
	var claim: Dictionary = _arms.get("_claim")
	for side: String in ["L", "R"]:
		var id := str(claim.get(side, ""))
		if id == "":
			# A hand on nothing is still a hand: its idle hang and its rest
			# pose are tuned here too.
			if bool(_arms.call("is_resting", side)):
				out.append({"key": "rest_" + side, "label": "%s hand · free (idle)" % side,
						"kind": "hand", "id": "rest_" + side, "side": side, "node": null})
			continue
		var spec: Dictionary = GRIP_MAP.spec_for(id)
		if spec.is_empty() or bool(spec.get("on_rim", false)):
			continue
		out.append({"key": id, "label": "%s (%s hand)" % [id, side],
				"kind": "grip", "id": id, "side": side, "node": null})
	return out


func _refresh_targets(force: bool) -> void:
	var found := _collect_targets()
	var same := not force and found.size() == _targets.size()
	if same:
		for i in found.size():
			if found[i]["key"] != _targets[i]["key"] \
					or found[i].get("node") != _targets[i].get("node"):
				same = false
				break
	if same:
		return
	var keep: String = str(_targets[_cur]["key"]) if _cur >= 0 and _cur < _targets.size() else ""
	_targets = found
	_target_opt.clear()
	for t: Dictionary in _targets:
		_target_opt.add_item(t["label"])
	if _targets.is_empty():
		_cur = -1
		_subject.text = "Nothing in the hands. Take hold of a fitting (E) or a tool from the bag (I)."
		_gizmo.visible = false
		_seq_box.visible = false
		return
	var idx := 0
	for i in _targets.size():
		if _targets[i]["key"] == keep:
			idx = i
	_target_opt.select(idx)
	# Not a user pick: the list only changed under us (a hand joined the
	# rifle, a tool was put away). Whatever state is up must survive it.
	_select_target(idx, false)


func _target() -> Dictionary:
	if _cur < 0 or _cur >= _targets.size():
		return {}
	var t: Dictionary = _targets[_cur]
	if t["kind"] == "marker" and not is_instance_valid(t["node"]):
		return {}
	return t


func _set_dock(side: String) -> void:
	_dock = side
	if side == "right":
		_panel.anchor_left = 1.0
		_panel.anchor_right = 1.0
		_panel.offset_left = -372.0
		_panel.offset_right = -10.0
	else:
		_panel.anchor_left = 0.0
		_panel.anchor_right = 0.0
		_panel.offset_left = 10.0
		_panel.offset_right = 372.0


func _select_target(i: int, user := true) -> void:
	_cur = i
	var t := _target()
	if t.is_empty():
		return
	if not _dock_manual:
		_set_dock("right" if t["side"] == "L" else "left")
	_subject.text = t["label"]
	_sync_from_target()
	_sync_pose(t)
	_gizmo.visible = _gizmo_chk.button_pressed
	_build_states(t)
	# Put the hand ON the thing that was picked. Otherwise the fore-end and
	# the bolt are edited with no hand near them, and every slider looks dead.
	#
	# Only on a real pick, and only when the state up is not one that puts
	# this hand on this thing. Distance is the wrong test — in the sights the
	# trigger hand sits a few centimetres from the bolt knob, close enough to
	# look satisfied while nothing is touching it — so each target names the
	# states in which its hand is genuinely working it.
	var needs := str(t.get("needs", ""))
	var ok_states: Array = t.get("ok_states", [])
	if user and needs != "" and not ok_states.has(_state):
		for si in _state_opt.item_count:
			if str(_state_opt.get_item_metadata(si)) == needs:
				_state_opt.select(si)
				_set_state(needs)
				_say("%s — showing '%s' so the hand is actually on it" % [
						t["label"], _state_opt.get_item_text(si)])
	if needs == "reload" and str(t.get("needs_stop", "")) != "":
		_seq_go_to(str(t["needs_stop"]))
	_pose_opt.disabled = t["kind"] == "marker"


# --- frame (position + rotation) ------------------------------------------

func _situation() -> String:
	## Which of the tool's holds is on screen. The editor's own STATE picker
	## is the authority while it is open; it is what the player is looking at.
	match _state:
		"sights":
			return "sights"
		"reload":
			return "reload"
		"hold", "attack", "":
			return "carry"
		_:
			return _state


func _marker_key(t: Dictionary) -> String:
	## Grips are tuned PER SITUATION. The fore-end is held one way while the
	## bolt is worked and another while the rifle is lowered into its sling;
	## one entry for both meant fixing the reload broke putting it away.
	if t["kind"] == "weapon" or str(t["key"]).begins_with("rifle/"):
		return HAND_TUNING.situation_key(str(t["key"]), _situation())
	return str(t["key"])


func _grip_key(t: Dictionary) -> String:
	## Where this target's frame is stored. A fitting that is mirrored for the
	## left hand keeps one entry PER HAND, so tuning one never reaches into
	## the other; everything else keeps a single entry.
	var id := str(t["id"])
	if t["kind"] == "hand":
		return id
	if _mirrored(id):
		return GRIP_MAP.side_key(id, str(t["side"]))
	return id


func _mirrored(id: String) -> bool:
	var spec: Dictionary = GRIP_MAP._catalog_spec(id)
	return bool(spec.get("handed", false)) or bool(spec.get("span", false))


func _frame_of(t: Dictionary) -> Transform3D:
	## Object-local transform of the target: origin = palm contact, +Z fingers,
	## +Y palm — the GripMap contract, which the rifle's markers also follow.
	if t["kind"] == "marker":
		return (t["node"] as Node3D).transform
	if t["kind"] == "weapon":
		return HAND_TUNING.hold_frame(str(t["key"]), _situation(),
				_authored_frame(t))
	if t["kind"] == "hand":
		# Camera-local: the offset added to the idle home, and the hang axes.
		var tune: Dictionary = HAND_TUNING.grip(t["id"])
		var base := _authored_frame(t)
		var xf := base
		if tune.has("pos"):
			xf.origin = HAND_TUNING.from_json(tune["pos"])
		if tune.has("fingers") and tune.has("palm"):
			var f: Vector3 = (HAND_TUNING.from_json(tune["fingers"]) as Vector3).normalized()
			var pv: Vector3 = HAND_TUNING.from_json(tune["palm"])
			pv = (pv - pv.project(f)).normalized()
			xf.basis = Basis(pv.cross(f).normalized(), pv, f)
		return xf
	var spec: Dictionary = GRIP_MAP.spec_for(t["id"])
	var sided: Dictionary = GRIP_MAP.sided(spec, t["side"], str(t["id"]))
	var f: Vector3 = (sided.get("fingers", Vector3.FORWARD) as Vector3).normalized()
	var p: Vector3 = sided.get("palm", Vector3.UP) as Vector3
	p = (p - p.project(f)).normalized()
	return Transform3D(Basis(p.cross(f).normalized(), p, f),
			sided.get("pos", Vector3.ZERO) as Vector3)


func _sync_from_target() -> void:
	var t := _target()
	if t.is_empty():
		return
	var xf := _frame_of(t)
	_cur_basis = xf.basis.orthonormalized()
	_base_basis = _authored_frame(t).basis.orthonormalized()
	_rot_shown = _rot_deg()
	# Re-ranging a slider can clamp its value and EMIT value_changed; nothing
	# in here may be taken as an edit.
	_syncing = true
	for i in 3:
		var s: HSlider = _pos_s[i]
		s.min_value = -1.0
		s.max_value = 1.0
		s.set_value_no_signal(xf.origin[i])
		s.min_value = xf.origin[i] - POS_SPAN
		s.max_value = xf.origin[i] + POS_SPAN
		_rot_s[i].set_value_no_signal(_rot_shown[i])
	_syncing = false
	for i in 3:
		_set_quiet(_pos_s[i], xf.origin[i])
		_set_quiet(_rot_s[i], _rot_shown[i])


func _slider_frame() -> Transform3D:
	var pos := Vector3(_pos_s[0].value, _pos_s[1].value, _pos_s[2].value)
	return Transform3D(_cur_basis, pos)


func _turn(axis: int, shown: float) -> void:
	## A rot slider moved: turn the target about ITS OWN axis by the change,
	## then show the fresh euler reading on all three sliders.
	if _syncing:
		return
	var delta := shown - _rot_shown[axis]
	if absf(delta) < 1e-4:
		return
	var local_axis := Vector3.ZERO
	local_axis[axis] = 1.0
	_cur_basis = (_cur_basis * Basis(local_axis, deg_to_rad(delta))).orthonormalized()
	_show_rotation()
	_apply_frame()


func _show_rotation() -> void:
	_rot_shown = _rot_deg()
	for i in 3:
		_set_quiet(_rot_s[i], _rot_shown[i])


func _rot_deg() -> Vector3:
	## The turn added to the authored orientation, as euler degrees.
	var e := (_base_basis.inverse() * _cur_basis).orthonormalized().get_euler()
	return Vector3(rad_to_deg(e.x), rad_to_deg(e.y), rad_to_deg(e.z))


func _authored_frame(t: Dictionary) -> Transform3D:
	if t["kind"] == "marker":
		var n: Node3D = t["node"]
		if n.has_meta("authored_transform"):
			return n.get_meta("authored_transform")
		return n.transform
	if t["kind"] == "weapon":
		return DECK_BAG.rifle_hold_default(_situation())
	if t["kind"] == "hand":
		var out := 1.0 if t["side"] == "R" else -1.0
		var f0 := Vector3(out * 0.08, -0.86, -0.46).normalized()
		var p0 := Vector3(-out * 0.95, -0.12, 0.16)
		p0 = (p0 - p0.project(f0)).normalized()
		return Transform3D(Basis(p0.cross(f0).normalized(), p0, f0), Vector3.ZERO)
	var spec: Dictionary = GRIP_MAP._catalog_spec(t["id"])
	var sided: Dictionary = GRIP_MAP.sided(spec, t["side"])
	var f: Vector3 = (sided.get("fingers", Vector3.FORWARD) as Vector3).normalized()
	var p: Vector3 = sided.get("palm", Vector3.UP) as Vector3
	p = (p - p.project(f)).normalized()
	return Transform3D(Basis(p.cross(f).normalized(), p, f),
			sided.get("pos", Vector3.ZERO) as Vector3)


func _apply_frame() -> void:
	if _syncing:
		return
	var t := _target()
	if t.is_empty():
		return
	var xf := _slider_frame()
	if t["kind"] == "weapon":
		var q := _cur_basis.get_rotation_quaternion().normalized()
		HAND_TUNING.set_marker(_marker_key(t), {
			"pos": HAND_TUNING.to_json(xf.origin),
			"quat": [snappedf(q.x, 0.00001), snappedf(q.y, 0.00001),
					snappedf(q.z, 0.00001), snappedf(q.w, 0.00001)],
			"turn_deg": HAND_TUNING.to_json(_rot_deg()),
		})
		_say("%s moved (%s)" % [t["label"], _situation()])
		return
	if t["kind"] == "marker":
		(t["node"] as Node3D).transform = xf
		var item: Node = t.get("item")
		if item != null and item.has_method("refresh_marker_rest"):
			item.call("refresh_marker_rest")
		var q := _cur_basis.get_rotation_quaternion().normalized()
		HAND_TUNING.set_marker(_marker_key(t), {
			"pos": HAND_TUNING.to_json(xf.origin),
			"quat": [snappedf(q.x, 0.00001), snappedf(q.y, 0.00001),
					snappedf(q.z, 0.00001), snappedf(q.w, 0.00001)],
			"turn_deg": HAND_TUNING.to_json(_rot_deg()),   # for the reader
		})
		var owner: Node = t.get("item")
		if owner != null and owner.has_method("refresh_marker_tuning"):
			owner.call("refresh_marker_tuning")
	else:
		var key := _grip_key(t)
		var fields: Dictionary = HAND_TUNING.grip(key).duplicate()
		fields["pos"] = HAND_TUNING.to_json(xf.origin)
		fields["fingers"] = HAND_TUNING.to_json(xf.basis.z.normalized())
		fields["palm"] = HAND_TUNING.to_json(xf.basis.y.normalized())
		HAND_TUNING.set_grip(key, fields)
		if t["kind"] == "grip":
			_arms.call("refresh_grip", t["id"])
	_say("%s frame edited" % t["label"])


func _reset_frame() -> void:
	var t := _target()
	if t.is_empty():
		return
	_push_undo()
	if t["kind"] == "weapon":
		HAND_TUNING.set_marker(_marker_key(t), {})
		_sync_from_target()
		_say("%s back to the code's own hold (%s)" % [t["label"], _situation()])
		return
	if t["kind"] == "marker":
		var n: Node3D = t["node"]
		if n.has_meta("authored_transform"):
			n.transform = n.get_meta("authored_transform")
		HAND_TUNING.set_marker(_marker_key(t), {})
		var item: Node = t.get("item")
		if item != null and item.has_method("refresh_marker_tuning"):
			item.call("refresh_marker_tuning")
		elif item != null and item.has_method("refresh_marker_rest"):
			item.call("refresh_marker_rest")
	else:
		var key := _grip_key(t)
		var fields: Dictionary = HAND_TUNING.grip(key).duplicate()
		for k in ["pos", "fingers", "palm"]:
			fields.erase(k)
		HAND_TUNING.set_grip(key, fields)
		if t["kind"] == "grip":
			_arms.call("refresh_grip", t["id"])
	_sync_from_target()
	_say("%s frame back to code default" % t["label"])


# --- fingers ---------------------------------------------------------------

func _live_pose_name(t: Dictionary) -> String:
	if t["kind"] == "grip":
		return str(GRIP_MAP.sided(GRIP_MAP.spec_for(t["id"]), str(t["side"]),
				str(t["id"])).get("pose", "wrap"))
	if t["kind"] == "hand":
		var tune: Dictionary = HAND_TUNING.grip(t["id"])
		return str(tune.get("pose", "open"))
	# A marker: the pose comes from the reload stop that is up, or from the
	# marker's own override, or from the code. Reading the LIVE name instead
	# lags by a frame after a re-assignment, and a finger edit made in that
	# frame went into the shared pose it had just been moved off.
	# The reload's stops pose the hand that works the action — the right one.
	# The fore-end hand is not part of that sequence, and reading a stop's
	# pose for it reported 'open' while it was really holding the fore-end.
	if _state == "reload" and str(t["side"]) == "R" \
			and _seq_item != null and _seq_cur >= 0:
		return str(_seq_item.call("reload_stop_pose",
				str((_seq_stops[_seq_cur] as Dictionary)["key"])))
	return HAND_TUNING.marker_pose(str(t["key"]),
			str(_hrig.call("pose_name", t["side"])), _situation())


func _pose_names() -> Array:
	var names: Array = (_hrig.call("poses") as Dictionary).keys()
	names.sort()
	return names


func _sync_pose(t: Dictionary) -> void:
	var name := _live_pose_name(t)
	_last_pose = name
	_pose_opt.clear()
	var names := _pose_names()
	for i in names.size():
		_pose_opt.add_item(str(names[i]))
		if names[i] == name:
			_pose_opt.select(i)
	_pose_lbl.text = "pose (chosen by code)" if t["kind"] == "marker" else "pose"
	# Which other grips would this edit reach? A pose is shared by name.
	var users := _pose_users(name)
	var idle: bool = t["kind"] == "weapon" \
			or (t["kind"] == "marker" and (name == "open" or name == "flat"))
	_finger_lock = idle
	for d: String in DIGITS:
		for j in 3:
			(_finger_s[d][j] as HSlider).editable = not idle
	_splay_s.editable = not idle
	if t["kind"] == "weapon":
		_amt_lbl.text = "the weapon's own hold, tuned for '%s' — the hands follow it" % _situation()
	elif idle:
		_amt_lbl.text = "%s hand is not on this grip right now (pose '%s'). " % [
				t["side"], name] + "Pick the state that puts it there (Sights), or the '%s hand · free' target." % t["side"]
	elif users.size() > 1:
		_amt_lbl.text = "pose '%s' is shared by: %s — edits reach all of them (Copy as… for a private one)" % [
				name, ", ".join(users)]
	var spec: Dictionary = (_hrig.call("poses") as Dictionary).get(name, {})
	for d: String in DIGITS:
		var values: Array = spec.get(d, spec.get("thumb", [0.0, 0.0, 0.0])
				if d == "thumb" else spec.get("fingers", [0.0, 0.0, 0.0]))
		for j in 3:
			_syncing = true
			(_finger_s[d][j] as HSlider).set_value_no_signal(
					float(values[mini(j, values.size() - 1)]))
			_syncing = false
	_set_quiet(_splay_s, float(spec.get("thumb_splay", 0.0)))


func _hand_distance(t: Dictionary) -> float:
	## How far the hand that owns this target is from it, in metres — the
	## NEAREST of palm and the two working fingertips, because a bolt knob is
	## held by the fingers with the palm a hand's width away by design.
	var xf := _target_global()
	if xf == Transform3D.IDENTITY:
		return 0.0
	var side: String = t["side"]
	var d: float = (_hrig.call("palm_global", side) as Vector3).distance_to(xf.origin)
	for digit: String in ["index", "thumb"]:
		d = minf(d, (_hrig.call("digit_tip_global", side, digit) as Vector3
				).distance_to(xf.origin))
	return d


## Everything a pose reaches. A pose is shared BY NAME, so tuning the
## cartridge pinch also moves the fuse-box finger and the backpack hand
## unless the target is given a pose of its own.
const CODE_POSE_USERS := {
	"rifle_primary": ["rifle trigger hand"],
	"rifle_support": ["rifle fore-end hand"],
	"bolt_grip": ["rifle bolt"],
	"pinch": ["rifle cartridge", "backpack hand"],
	"knife_grip": ["knife"],
	"power": ["backpack hand"],
	"handle": ["backpack hand"],
	"open": ["every idle hand", "swimming"],
	"wrap": ["ladder rungs", "wiping the mask"],
	"point": ["bag pointer"],
	"rim": ["the wheel"],
}


func _pose_users(name: String) -> Array:
	var out: Array = []
	for id in GRIP_MAP.ENTRIES:
		if str((GRIP_MAP.ENTRIES[id] as Dictionary).get("pose", "")) == name:
			out.append(str(id))
	if str(GRIP_MAP.SWITCH.get("pose", "")) == name:
		out.append("switches")
	# Anything the file has already pointed at this pose.
	for key in HAND_TUNING.data()["grips"]:
		if str((HAND_TUNING.data()["grips"][key] as Dictionary).get("pose", "")) == name:
			out.append(str(key))
	for key in HAND_TUNING.data()["markers"]:
		if str((HAND_TUNING.data()["markers"][key] as Dictionary).get("pose", "")) == name:
			out.append(str(key))
	for stop in RELOAD_STOPS.ORDER:
		if RELOAD_STOPS.pose_of(str(stop)) == name and not out.has("reload stops"):
			out.append("reload stops")
	for u in CODE_POSE_USERS.get(name, []):
		if not out.has(u):
			out.append(str(u))
	return out


func _private_pose(push_history := true) -> void:
	## Give the selected target a pose of its own, copied from the one it is
	## using now, so further finger edits reach nothing else.
	var t := _target()
	if t.is_empty() or _last_pose == "":
		return
	# Named after the grip, not after the pose it was copied from: the point
	# of it is that only this grip uses it. "_only" keeps it clear of the
	# shared names (knife/Grip would otherwise slug to the existing
	# "knife_grip" and quietly overwrite it).
	# Rifle marker poses are also situation-specific. Including @sling here is
	# what keeps a placement-hand edit out of carry and normal walking.
	var pose_owner_key := _marker_key(t) if t["kind"] == "marker" else str(t["key"])
	var slug := pose_owner_key.replace("/", "_").replace("@", "_").to_snake_case()
	var name := slug + "_only"
	var n := 2
	while (_hrig.call("poses") as Dictionary).has(name) and name != _last_pose:
		name = "%s_only%d" % [slug, n]
		n += 1
	if push_history:
		_push_undo()
	var fields := _pose_fields()
	_hrig.call("set_pose_override", name, fields)
	HAND_TUNING.set_pose(name, fields)
	_assign_pose(t, name)
	# The live pose catches up next frame; the editor must already be editing
	# the private copy, or the next slider move goes back into the shared one.
	_last_pose = name
	_sync_pose(t)
	_say("'%s' is now used by %s alone" % [name, t["label"]])


func _assign_pose(t: Dictionary, name: String) -> void:
	## Point whatever is actually choosing this hand's pose at `name`.
	if t["kind"] != "marker":
		var g: Dictionary = HAND_TUNING.grip(_grip_key(t)).duplicate()
		g["pose"] = name
		if t["kind"] == "hand":
			g["amount"] = 1.0
		HAND_TUNING.set_grip(_grip_key(t), g)
		if t["kind"] == "grip":
			_arms.call("refresh_grip", t["id"])
		return
	# A marker in the reload is posed by the stop that is up — but only for
	# the hand the sequence drives; otherwise the tool reads the pose off the
	# marker itself.
	if _state == "reload" and str(t["side"]) == "R" \
			and _seq_item != null and _seq_cur >= 0:
		_seq_item.call("set_reload_stop_pose",
				str((_seq_stops[_seq_cur] as Dictionary)["key"]), name)
		return
	var m: Dictionary = HAND_TUNING.marker(_marker_key(t)).duplicate()
	m["pose"] = name
	HAND_TUNING.set_marker(_marker_key(t), m)


func _pose_fields() -> Dictionary:
	var out := {}
	for d: String in DIGITS:
		var trio: Array = []
		for j in 3:
			trio.append(snappedf((_finger_s[d][j] as HSlider).value, 0.01))
		out[d] = trio
	if absf(_splay_s.value) > 0.001:
		out["thumb_splay"] = snappedf(_splay_s.value, 0.01)
	return out


func _apply_pose() -> void:
	if _syncing or _finger_lock:
		return
	var t := _target()
	if t.is_empty() or _last_pose == "":
		return
	# A sling finger edit must never rewrite the shared rifle_primary pose. Make
	# a private situation-owned copy on the first edit, without adding a second
	# undo step (the slider drag already captured one).
	if t["kind"] == "marker" and _situation() == "sling" \
			and not HAND_TUNING.marker(_marker_key(t)).has("pose"):
		_private_pose(false)
	var fields := _pose_fields()
	_hrig.call("set_pose_override", _last_pose, fields)
	HAND_TUNING.set_pose(_last_pose, fields)
	_say("pose '%s' edited" % _last_pose)


func _choose_pose(i: int) -> void:
	var t := _target()
	if t.is_empty() or t["kind"] == "marker":
		return
	var name := _pose_opt.get_item_text(i)
	_push_undo()
	var fields: Dictionary = HAND_TUNING.grip(_grip_key(t)).duplicate()
	fields["pose"] = name
	if t["kind"] == "hand":
		fields["amount"] = 1.0
	HAND_TUNING.set_grip(_grip_key(t), fields)
	if t["kind"] == "grip":
		_arms.call("refresh_grip", t["id"])
	_sync_pose(t)
	_say("%s now uses pose '%s'" % [t["id"], name])


func _copy_pose() -> void:
	var t := _target()
	var name := _copy_name.text.strip_edges().to_snake_case()
	if t.is_empty() or name == "":
		_say("give the new pose a name first")
		return
	_push_undo()
	var fields := _pose_fields()
	_hrig.call("set_pose_override", name, fields)
	HAND_TUNING.set_pose(name, fields)
	_assign_pose(t, name)
	_say("pose '%s' created and assigned to %s" % [name, t["label"]])
	_sync_pose(t)


func _reset_pose() -> void:
	var t := _target()
	if t.is_empty() or _last_pose == "":
		return
	_push_undo()
	HAND_TUNING.set_pose(_last_pose, {})
	_hrig.call("refresh_poses")
	_sync_pose(t)
	_say("pose '%s' back to code default" % _last_pose)


# --- undo / file -----------------------------------------------------------

func _push_undo() -> void:
	var t := _target()
	var snap := {"tuning": HAND_TUNING.snapshot(), "key": t.get("key", "")}
	if not t.is_empty() and t["kind"] == "marker":
		snap["xf"] = (t["node"] as Node3D).transform
	_undo.append(snap)
	if _undo.size() > 60:
		_undo.pop_front()


func _undo_last() -> void:
	if _undo.is_empty():
		_say("nothing to undo")
		return
	var snap: Dictionary = _undo.pop_back()
	HAND_TUNING.restore(snap["tuning"])
	_reapply_all(snap)
	_say("undone")


func _reapply_all(snap: Dictionary = {}) -> void:
	## Push the tuning tables back into the live objects.
	_hrig.call("refresh_poses")
	for t: Dictionary in _targets:
		if t["kind"] == "grip":
			_arms.call("refresh_grip", t["id"])
		elif is_instance_valid(t["node"]):
			var n: Node3D = t["node"]
			if n.has_meta("authored_transform"):
				n.transform = n.get_meta("authored_transform")
			if snap.has("xf") and snap.get("key", "") == t["key"]:
				n.transform = snap["xf"]
			HAND_TUNING.apply_marker(str(t["key"]), n, _situation())
			var item: Node = t.get("item")
			if item != null and item.has_method("refresh_marker_tuning"):
				item.call("refresh_marker_tuning")
			elif item != null and item.has_method("refresh_marker_rest"):
				item.call("refresh_marker_rest")
	var cur := _target()
	if not cur.is_empty():
		_sync_from_target()
		_sync_pose(cur)
		if _seq_box.visible:
			_seq_refresh()


func _save() -> void:
	if HAND_TUNING.save():
		_say("saved → %s" % HAND_TUNING.save_path())
	else:
		_say("SAVE FAILED — see console")


func _reload_file() -> void:
	HAND_TUNING.reload()
	_reapply_all()
	_say("re-read %s" % HAND_TUNING.save_path())


func _screenshot() -> void:
	var t := _target()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	var name := "%s_%s" % [str(t.get("key", "hands")).replace("/", "_"),
			Time.get_datetime_string_from_system().replace(":", "-")]
	var panel_was := _panel.visible
	var gizmo_was := _gizmo.visible
	_panel.visible = false
	_gizmo.visible = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [SHOT_DIR, name]
	get_viewport().get_texture().get_image().save_png(path)
	_panel.visible = panel_was
	_gizmo.visible = gizmo_was
	_say("shot → %s" % ProjectSettings.globalize_path(path))


# --- gizmo -----------------------------------------------------------------

func _build_gizmo() -> void:
	_gizmo = Node3D.new()
	_gizmo.name = "HandEditorGizmo"
	_gizmo.top_level = true
	add_child(_gizmo)
	for i in 3:
		var col: Color = [Color(1, 0.25, 0.25), Color(0.3, 1, 0.3), Color(0.35, 0.5, 1)][i]
		var rod := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var sz := Vector3(0.003, 0.003, 0.003)
		sz[i] = GIZMO_LEN
		bm.size = sz
		rod.mesh = bm
		var pos := Vector3.ZERO
		pos[i] = GIZMO_LEN * 0.5
		rod.position = pos
		rod.material_override = _glow(col)
		rod.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_gizmo.add_child(rod)
		_gizmo_rods.append(rod)
	# The palm plane: a thin square in XZ (normal = +Y = palm), so the eye
	# reads which way the palm faces and which way the fingers run.
	var plate := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.028, 0.0008, 0.040)
	plate.mesh = pm
	plate.position = Vector3(0, 0, 0.012)
	var pmat := _glow(Color(1, 0.9, 0.5))
	pmat.albedo_color.a = 0.35
	pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	plate.material_override = pmat
	plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_gizmo.add_child(plate)
	_bounds_box = MeshInstance3D.new()
	_bounds_box.top_level = true
	_bounds_box.visible = false
	_bounds_box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_bounds_box)


func _glow(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.no_depth_test = true
	m.render_priority = 100
	return m


func _target_global() -> Transform3D:
	var t := _target()
	if t.is_empty():
		return Transform3D.IDENTITY
	if t["kind"] == "marker":
		var item: Node = t.get("item")
		var live := str(t.get("live", ""))
		if live != "" and item != null and item.has_method(live):
			return (item as Node3D).global_transform \
					* (item.call(live) as Transform3D)
		return (t["node"] as Node3D).global_transform
	if t["kind"] == "weapon":
		var item: Node3D = t.get("item")
		if item != null and is_instance_valid(item):
			return item.global_transform
		return _cam.global_transform * _frame_of(t)
	if t["kind"] == "hand":
		return _cam.global_transform * (_arms.call("rest_frame", t["side"]) as Transform3D)
	var g: Node3D = _arms.call("grip_node_of", t["id"], t["side"]) as Node3D
	if g != null:
		return g.global_transform
	return Transform3D.IDENTITY


func _place_gizmo() -> void:
	if not _gizmo.visible:
		return
	var t := _target()
	if t.is_empty():
		_gizmo.visible = false
		return
	var xf := _target_global()
	_gizmo.global_transform = Transform3D(xf.basis.orthonormalized(), xf.origin)


func _gizmo_input(event: InputEvent) -> void:
	if not _gizmo.visible or _cam == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			# Over the panel the click belongs to the sliders — and so does
			# its release, or a slider grabbed there never lets go of the
			# mouse and keeps re-applying its value wherever the pointer goes.
			if _panel.get_global_rect().has_point(mb.position):
				_press_in_panel = true
				return
			_press_in_panel = false
			get_viewport().set_input_as_handled()
			var axis := _pick_axis(mb.position)
			if axis >= 0:
				_drag_axis = axis
				_drag_rot = mb.shift_pressed
				_drag_start = mb.position
				_push_undo()
		else:
			if _press_in_panel:
				_press_in_panel = false
				return
			_drag_axis = -1
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and _drag_axis >= 0:
		var mm := event as InputEventMouseMotion
		var xf := _target_global()
		var o := xf.origin
		var a := xf.basis[_drag_axis].normalized()
		if _cam.is_position_behind(o):
			return
		var p0 := _cam.unproject_position(o)
		var p1 := _cam.unproject_position(o + a * GIZMO_LEN)
		var d := (p1 - p0)
		if d.length() < 1.0:
			return
		d = d.normalized()
		var px := mm.relative.dot(d)
		var t := _target()
		if t.is_empty():
			return
		if _drag_rot or mm.shift_pressed:
			# Rotation about the target's own axis, in its own frame: compose
			# the delta and read the euler back so the three sliders stay true.
			var local_axis := Vector3.ZERO
			local_axis[_drag_axis] = 1.0
			_cur_basis = (_cur_basis * Basis(local_axis,
					deg_to_rad(px * 0.4))).orthonormalized()
			_show_rotation()
		else:
			# Metres per pixel at the target's depth.
			var depth := maxf((_cam.global_transform.affine_inverse() * o).length(), 0.05)
			var mpp := 2.0 * depth * tan(deg_to_rad(_cam.fov) * 0.5) \
					/ maxf(float(get_viewport().get_visible_rect().size.y), 1.0)
			var s: HSlider = _pos_s[_drag_axis]
			var nv: float = s.value + px * mpp
			if nv < s.min_value or nv > s.max_value:
				s.min_value = nv - POS_SPAN
				s.max_value = nv + POS_SPAN
			_set_quiet(s, nv)
		_apply_frame()
		get_viewport().set_input_as_handled()


func _pick_axis(m: Vector2) -> int:
	var xf := _target_global()
	var o := xf.origin
	if _cam.is_position_behind(o):
		return -1
	var p0 := _cam.unproject_position(o)
	var best := -1
	var best_d := PICK_PX
	for i in 3:
		var p1 := _cam.unproject_position(o + xf.basis[i].normalized() * GIZMO_LEN)
		var d := _dist_to_segment(m, p0, p1)
		if d < best_d:
			best_d = d
			best = i
	return best


func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 1e-6:
		return p.distance_to(a)
	var u := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * u)


# --- contact bounds --------------------------------------------------------

func _set_bounds_visible(on: bool) -> void:
	_bounds_box.visible = on


func _update_bounds() -> void:
	var t := _target()
	if t.is_empty() or not _bounds_chk.button_pressed:
		_bounds_box.visible = false
		return
	var cb: Dictionary = _hrig.call("contact_bounds_of", t["side"])
	if cb.is_empty():
		_bounds_box.visible = false
		return
	var device: Node3D = cb["device"]
	var box: AABB = cb["bounds"]
	if box.size.length_squared() < 1e-8:
		_bounds_box.visible = false
		return
	if _bounds_box.mesh == null:
		var bm := BoxMesh.new()
		_bounds_box.mesh = bm
		var m := _glow(Color(0.3, 1.0, 0.8))
		m.albedo_color.a = 0.22
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_bounds_box.material_override = m
	(_bounds_box.mesh as BoxMesh).size = box.size
	_bounds_box.global_transform = device.global_transform \
			* Transform3D(Basis.IDENTITY, box.get_center())
	_bounds_box.visible = true


# --- state ------------------------------------------------------------------

func _item_of(t: Dictionary) -> Node:
	## The tool this target belongs to — the weapon's own hold included, or
	## selecting it empties the state picker and every edit lands under
	## whatever situation happened to be left over.
	if t["kind"] == "marker" or t["kind"] == "weapon":
		return t.get("item")
	return null


func _build_states(t: Dictionary) -> void:
	var item := _item_of(t)
	_state_opt.clear()
	var states: Array = []
	if item != null and item.has_method("reload_elapsed"):
		states = [["Carry", "carry"], ["Sights (aim held)", "sights"],
				["Reload — stops", "reload"], ["Put in bag / sling", "sling"]]
	elif item != null and item.has_method("seek_attack"):
		states = [["Hold", "hold"], ["Swing — scrub", "attack"]]
	_state_box.visible = not states.is_empty()
	if states.is_empty():
		_set_state("")
		_seq_box.visible = false
		return
	for st in states:
		_state_opt.add_item(st[0])
		_state_opt.set_item_metadata(_state_opt.item_count - 1, st[1])
	# Keep the state across targets of the same tool; a rifle marker picked
	# while the reload is scrubbed should not drop the reload.
	var keep := _state
	# Opening the editor while the rifle is already hovering over its sling must
	# land on the matching isolated tuning key. Previously it silently selected
	# Carry, so the sliders wrote @carry while the runtime was reading @sling.
	if keep == "" and item != null and item.has_method("hand_situation"):
		keep = str(item.call("hand_situation"))
	var idx := 0
	for i in states.size():
		if states[i][1] == keep:
			idx = i
	_state_opt.select(idx)
	_set_state(states[idx][1])


func _set_state(state: String) -> void:
	var t := _target()
	var item := _item_of(t) if not t.is_empty() else null
	var bag: Node = rig.call("_deck_bag") if rig != null else null
	# Like the held sights/reload previews, Sling must be a complete editor
	# state: open the bag if needed, but restore it on exit only when the editor
	# was the thing that opened it. A bag the player already had open stays open.
	if state == "sling" and rig != null and rig.has_method("set_bag_open"):
		if not bool(rig.get("_bag_open")):
			_sling_bag_latched = bool(rig.call("set_bag_open", true))
	elif _sling_bag_latched and rig != null and rig.has_method("set_bag_open"):
		rig.call("set_bag_open", false)
		_sling_bag_latched = false
	if bag != null and bag.has_method("set_editor_rifle_sling_preview"):
		bag.call("set_editor_rifle_sling_preview", state == "sling")
	# Leave whatever the previous state was holding.
	if _aim_latched and state != "sights":
		Input.action_release("rifle_aim")
		_aim_latched = false
	if _state == "reload" and state != "reload":
		_seq_stop_scrub()
	if _state == "attack" and state != "attack" and item != null \
			and item.has_method("seek_attack"):
		item.call("seek_attack", -1.0, false)
	_state = state
	var tool_item: Node = _item_of(t)
	if tool_item == null and not t.is_empty():
		tool_item = t.get("item")
	if tool_item != null and tool_item.has_method("refresh_marker_tuning"):
		tool_item.call("refresh_marker_tuning")
	_seq_box.visible = state == "reload"
	_attack_t.visible = state == "attack"
	(_attack_t.get_meta("label") as Control).visible = state == "attack"
	match state:
		"sights":
			if not _aim_latched:
				Input.action_press("rifle_aim")
				_aim_latched = true
		"reload":
			_seq_refresh()
			if _seq_cur < 0 and not _seq_stops.is_empty():
				_stop_opt.select(1)
				_seq_select_stop(1)
			elif _seq_cur >= 0:
				_seq_select_stop(_seq_cur)
		"attack":
			if item != null:
				_attack_t.max_value = float(item.call("attack_duration"))
				_seek_attack(_attack_t.value)


func _seek_attack(v: float) -> void:
	var t := _target()
	var item := _item_of(t) if not t.is_empty() else null
	if item == null or not item.has_method("seek_attack"):
		return
	item.call("seek_attack", v, true)


# --- sequence (reload stops) ------------------------------------------------
# The reload is a chain of STOPS in time — bolt reached, bolt open, round
# shown, round at the chamber, seated, bolt home, back on the grip. The code
# interpolates between them; the editor moves the stops and scrubs to each so
# the markers can be tuned while the rifle is actually paused there.

var _seq_item: Node = null
var _seq_scrub := false
var _seq_playing := false
var _seq_stops: Array = []      # [{key, label, t}]
var _seq_cur := -1


func _seq_rifle() -> Node:
	var t := _target()
	if t.is_empty():
		return null
	var item: Node = _item_of(t)
	if item == null or not item.has_method("reload_stops"):
		return null
	return item


func _seq_refresh() -> void:
	var rifle := _seq_rifle()
	_seq_item = rifle
	_stop_opt.clear()
	_seq_stops = []
	if rifle == null:
		return
	var stops: Dictionary = rifle.call("reload_stops")
	var keys: Array = rifle.call("reload_stop_order")
	for k: String in keys:
		_seq_stops.append({"key": k, "t": float(stops.get(k, 0.0))})
		_stop_opt.add_item("%s  %.2fs" % [k, float(stops.get(k, 0.0))])
	_stop_pose.clear()
	for n in _pose_names():
		_stop_pose.add_item(str(n))
	if _seq_cur >= 0 and _seq_cur < _seq_stops.size():
		_stop_opt.select(_seq_cur)
		_seq_select_stop(_seq_cur)


func _seq_go_to(key: String) -> void:
	for i in _seq_stops.size():
		if str((_seq_stops[i] as Dictionary)["key"]) == key:
			_stop_opt.select(i)
			_seq_select_stop(i)
			return


func _seq_select_stop(i: int) -> void:
	if i < 0 or i >= _seq_stops.size():
		return
	_seq_cur = i
	var st: Dictionary = _seq_stops[i]
	_stop_t.max_value = float(_seq_item.call("reload_duration")) + 1.0
	_set_quiet(_stop_t, st["t"])
	var pose := str(_seq_item.call("reload_stop_pose", st["key"]))
	for j in _stop_pose.item_count:
		if _stop_pose.get_item_text(j) == pose:
			_stop_pose.select(j)
	_seq_scrub_to(st["t"])


func _seq_set_stop_time(v: float) -> void:
	if _seq_item == null or _seq_cur < 0:
		return
	var st: Dictionary = _seq_stops[_seq_cur]
	_seq_item.call("set_reload_stop", st["key"], v)
	st["t"] = float(_seq_item.call("reload_stops")[st["key"]])
	_stop_opt.set_item_text(_seq_cur, "%s  %.2fs" % [st["key"], st["t"]])
	_seq_scrub_to(st["t"])
	_say("stop '%s' at %.2f s" % [st["key"], st["t"]])


func _seq_set_stop_pose(i: int) -> void:
	if _seq_item == null or _seq_cur < 0:
		return
	var st: Dictionary = _seq_stops[_seq_cur]
	var pose := _stop_pose.get_item_text(i)
	_push_undo()
	_seq_item.call("set_reload_stop_pose", st["key"], pose)
	_say("stop '%s' pose → %s" % [st["key"], pose])


func _seq_scrub_to(t: float) -> void:
	if _seq_item == null:
		return
	_seq_scrub = true
	_seq_playing = false
	_play_btn.text = "▶ Play"
	var bag: Node3D = rig.call("_deck_bag") as Node3D
	if bag != null and not bool(_seq_item.call("is_reloading")):
		bag.call("begin_active_rifle_reload")
	_seq_item.call("seek_reload", t, true)


func _seq_stop_scrub() -> void:
	if _seq_item != null and _seq_scrub:
		_seq_item.call("seek_reload", -1.0, false)
	_seq_scrub = false
	_seq_playing = false
	if _play_btn != null:
		_play_btn.text = "▶ Play"


func _seq_toggle_play() -> void:
	if _seq_item == null:
		return
	if _seq_playing:
		_seq_playing = false
		_seq_item.call("set_reload_paused", true)
		_play_btn.text = "▶ Play"
		return
	if not bool(_seq_item.call("is_reloading")):
		var bag: Node3D = rig.call("_deck_bag") as Node3D
		if bag != null:
			bag.call("begin_active_rifle_reload")
	_seq_scrub = true
	_seq_playing = true
	_seq_item.call("set_reload_paused", false)
	_play_btn.text = "⏸ Pause"


func _seq_step(dir: int) -> void:
	if _seq_stops.is_empty():
		return
	var i := clampi((_seq_cur if _seq_cur >= 0 else 0) + dir, 0, _seq_stops.size() - 1)
	_stop_opt.select(i)
	_seq_select_stop(i)


func _seq_tick(_delta: float) -> void:
	if _seq_item == null or not _seq_scrub:
		return
	if _seq_playing and not bool(_seq_item.call("is_reloading")):
		# Ran off the end: hold the last frame rather than snapping back.
		_seq_playing = false
		_play_btn.text = "▶ Play"
		_seq_scrub = false


func _draw_timeline() -> void:
	var r := _timeline.get_rect()
	var w := r.size.x
	_timeline.draw_rect(Rect2(0, 12, w, 10), Color(0.12, 0.14, 0.13))
	if _seq_item == null:
		return
	var dur := maxf(float(_seq_item.call("reload_duration")), 0.01)
	for i in _seq_stops.size():
		var st: Dictionary = _seq_stops[i]
		var x: float = clampf(float(st["t"]) / dur, 0.0, 1.0) * w
		var c := Color(1.0, 0.85, 0.4) if i == _seq_cur else Color(0.55, 0.7, 0.6)
		_timeline.draw_line(Vector2(x, 6), Vector2(x, 28), c, 2.0)
	var now := float(_seq_item.call("reload_elapsed"))
	if now >= 0.0:
		var x := clampf(now / dur, 0.0, 1.0) * w
		_timeline.draw_line(Vector2(x, 2), Vector2(x, 32), Color(1, 0.3, 0.3), 1.5)


func _timeline_input(event: InputEvent) -> void:
	if _seq_item == null:
		return
	if event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var u := clampf((event as InputEventMouseButton).position.x
				/ maxf(_timeline.size.x, 1.0), 0.0, 1.0)
		_seq_scrub_to(u * float(_seq_item.call("reload_duration")))
	elif event is InputEventMouseMotion \
			and (event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT:
		var u := clampf((event as InputEventMouseMotion).position.x
				/ maxf(_timeline.size.x, 1.0), 0.0, 1.0)
		_seq_scrub_to(u * float(_seq_item.call("reload_duration")))
