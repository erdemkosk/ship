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

# --- gizmo -----------------------------------------------------------------
var _gizmo: Node3D
var _gizmo_rods: Array = []
var _bounds_box: MeshInstance3D
var _drag_axis := -1
var _drag_rot := false
var _drag_start := Vector2.ZERO

var _undo: Array = []
var _last_pose := ""
var _look_hold := false


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
		_seq_stop_scrub()
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
	_target_opt.item_selected.connect(func(i: int) -> void: _select_target(i))
	vbox.add_child(_target_opt)
	# --- sequence ------------------------------------------------------------
	_section(vbox, "SEQUENCE  (reload stops)")
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
	_section(vbox, "GRIP FRAME  (object-local)")
	for i in 3:
		_pos_s.append(_slider(vbox, "pos %s" % ["X", "Y", "Z"][i], "%+.1f mm",
				-POS_SPAN, POS_SPAN, 0.0005, 0.0, 1000.0,
				func(_v: float) -> void: _apply_frame()))
	for i in 3:
		_rot_s.append(_slider(vbox, "rot %s" % ["X", "Y", "Z"][i], "%+.1f°",
				-180.0, 180.0, 0.5, 0.0, 1.0,
				func(_v: float) -> void: _apply_frame()))
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

	# --- solver / view -------------------------------------------------------
	_section(vbox, "SOLVER · VIEW")
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
		_amt_lbl.text = "hand %s · pose amount %.2f · solver %s" % [t["side"],
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
			for m: String in ["PrimaryGrip", "SupportGrip", "BoltHandle", "Chamber"]:
				var n := item.get_node_or_null(m) as Node3D
				if n != null:
					out.append({"key": "rifle/" + m, "label": "Rifle · " + m,
							"kind": "marker", "node": n, "item": item,
							"side": "L" if m == "SupportGrip" else "R"})
		elif item != null and kind == "utility_knife":
			var n := item.get_node_or_null("Grip") as Node3D
			if n != null:
				out.append({"key": "knife/Grip", "label": "Knife · Grip",
						"kind": "marker", "node": n, "item": item, "side": "R"})
	var claim: Dictionary = _arms.get("_claim")
	for side: String in ["L", "R"]:
		var id := str(claim.get(side, ""))
		if id == "":
			continue
		var spec: Dictionary = GRIP_MAP.spec_for(id)
		if spec.is_empty() or bool(spec.get("on_rim", false)):
			continue
		out.append({"key": id, "label": "%s · %s hand" % [id, side],
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
	_select_target(idx)


func _target() -> Dictionary:
	if _cur < 0 or _cur >= _targets.size():
		return {}
	var t: Dictionary = _targets[_cur]
	if t["kind"] == "marker" and not is_instance_valid(t["node"]):
		return {}
	return t


func _select_target(i: int) -> void:
	_cur = i
	var t := _target()
	if t.is_empty():
		return
	_subject.text = t["label"]
	_sync_from_target()
	_sync_pose(t)
	_gizmo.visible = _gizmo_chk.button_pressed
	_seq_box.visible = t["kind"] == "marker" and t.get("item") != null \
			and (t["item"] as Node).has_method("reload_elapsed")
	if _seq_box.visible:
		_seq_refresh()
	_pose_opt.disabled = t["kind"] != "grip"


# --- frame (position + rotation) ------------------------------------------

func _frame_of(t: Dictionary) -> Transform3D:
	## Object-local transform of the target: origin = palm contact, +Z fingers,
	## +Y palm — the GripMap contract, which the rifle's markers also follow.
	if t["kind"] == "marker":
		return (t["node"] as Node3D).transform
	var spec: Dictionary = GRIP_MAP.spec_for(t["id"])
	var sided: Dictionary = GRIP_MAP.sided(spec, t["side"])
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
	var e := xf.basis.orthonormalized().get_euler()
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
		_rot_s[i].set_value_no_signal(rad_to_deg(e[i]))
	_syncing = false
	for i in 3:
		_set_quiet(_pos_s[i], xf.origin[i])
		_set_quiet(_rot_s[i], rad_to_deg(e[i]))


func _slider_frame() -> Transform3D:
	var pos := Vector3(_pos_s[0].value, _pos_s[1].value, _pos_s[2].value)
	var e := Vector3(deg_to_rad(_rot_s[0].value), deg_to_rad(_rot_s[1].value),
			deg_to_rad(_rot_s[2].value))
	return Transform3D(Basis.from_euler(e), pos)


func _apply_frame() -> void:
	if _syncing:
		return
	var t := _target()
	if t.is_empty():
		return
	var xf := _slider_frame()
	if t["kind"] == "marker":
		(t["node"] as Node3D).transform = xf
		var item: Node = t.get("item")
		if item != null and item.has_method("refresh_marker_rest"):
			item.call("refresh_marker_rest")
		HAND_TUNING.set_marker(t["key"], {
			"pos": HAND_TUNING.to_json(xf.origin),
			"rot": HAND_TUNING.to_json(Vector3(_rot_s[0].value, _rot_s[1].value,
					_rot_s[2].value)),
		})
	else:
		var fields: Dictionary = HAND_TUNING.grip(t["id"]).duplicate()
		fields["pos"] = HAND_TUNING.to_json(xf.origin)
		fields["fingers"] = HAND_TUNING.to_json(xf.basis.z.normalized())
		fields["palm"] = HAND_TUNING.to_json(xf.basis.y.normalized())
		HAND_TUNING.set_grip(t["id"], fields)
		_arms.call("refresh_grip", t["id"])
	_say("%s frame edited" % t["label"])


func _reset_frame() -> void:
	var t := _target()
	if t.is_empty():
		return
	_push_undo()
	if t["kind"] == "marker":
		var n: Node3D = t["node"]
		if n.has_meta("authored_transform"):
			n.transform = n.get_meta("authored_transform")
		HAND_TUNING.set_marker(t["key"], {})
		var item: Node = t.get("item")
		if item != null and item.has_method("refresh_marker_rest"):
			item.call("refresh_marker_rest")
	else:
		var fields: Dictionary = HAND_TUNING.grip(t["id"]).duplicate()
		for k in ["pos", "fingers", "palm"]:
			fields.erase(k)
		HAND_TUNING.set_grip(t["id"], fields)
		_arms.call("refresh_grip", t["id"])
	_sync_from_target()
	_say("%s frame back to code default" % t["label"])


# --- fingers ---------------------------------------------------------------

func _live_pose_name(t: Dictionary) -> String:
	if t["kind"] == "grip":
		return str(GRIP_MAP.spec_for(t["id"]).get("pose", "wrap"))
	return str(_hrig.call("pose_name", t["side"]))


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
	_pose_lbl.text = "pose" if t["kind"] == "grip" else "pose (chosen by code)"
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
	if _syncing:
		return
	var t := _target()
	if t.is_empty() or _last_pose == "":
		return
	var fields := _pose_fields()
	_hrig.call("set_pose_override", _last_pose, fields)
	HAND_TUNING.set_pose(_last_pose, fields)
	_say("pose '%s' edited" % _last_pose)


func _choose_pose(i: int) -> void:
	var t := _target()
	if t.is_empty() or t["kind"] != "grip":
		return
	var name := _pose_opt.get_item_text(i)
	_push_undo()
	var fields: Dictionary = HAND_TUNING.grip(t["id"]).duplicate()
	fields["pose"] = name
	HAND_TUNING.set_grip(t["id"], fields)
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
	if t["kind"] == "grip":
		var g: Dictionary = HAND_TUNING.grip(t["id"]).duplicate()
		g["pose"] = name
		HAND_TUNING.set_grip(t["id"], g)
		_arms.call("refresh_grip", t["id"])
		_say("pose '%s' created and assigned to %s" % [name, t["id"]])
	else:
		_say("pose '%s' created (assign it in a sequence stop)" % name)
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
			HAND_TUNING.apply_marker(t["key"], n)
			var item: Node = t.get("item")
			if item != null and item.has_method("refresh_marker_rest"):
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
		return (t["node"] as Node3D).global_transform
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
			if _panel.get_global_rect().has_point(mb.position):
				return
			get_viewport().set_input_as_handled()
			var axis := _pick_axis(mb.position)
			if axis >= 0:
				_drag_axis = axis
				_drag_rot = mb.shift_pressed
				_drag_start = mb.position
				_push_undo()
		elif _drag_axis >= 0:
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
			var cur := _slider_frame()
			var local_axis := Vector3.ZERO
			local_axis[_drag_axis] = 1.0
			var nb := cur.basis * Basis(local_axis, deg_to_rad(px * 0.4))
			var e := nb.orthonormalized().get_euler()
			for i in 3:
				_set_quiet(_rot_s[i], rad_to_deg(e[i]))
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
	if t.is_empty() or t["kind"] != "marker":
		return null
	var item: Node = t.get("item")
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
