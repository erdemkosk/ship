class_name BoatSwitchboardVisualBuilder
extends RefCounted
## Builds the shared toggle design, switchboard well and fuse cartridges.

var fuse_bodies := {}
var switch_levers := {}
var switch_leds := {}
var _owner: Node3D
var _electrical: RefCounted
var _box_callback: Callable
var _cyl_callback: Callable
var _mat_callback: Callable
var _fuse_lid: Node3D
var _fuse_latch_local := Vector3(0.0, 0.012, 0.44)


func setup(owner: Node3D, electrical: RefCounted, box_callback: Callable,
		cyl_callback: Callable, mat_callback: Callable) -> void:
	_owner = owner
	_electrical = electrical
	_box_callback = box_callback
	_cyl_callback = cyl_callback
	_mat_callback = mat_callback


func build_switchboard(trim: Material, metal: Material) -> Dictionary:
	## A switch console, standing between the radar and the chart table where
	## your right hand falls. Six brass toggles: walk up and throw them. A boat
	## this old would not have a menu, and it does not have one here either.
	var bronze := _mat(Color(0.36, 0.27, 0.13), 0.40, 0.75)
	var cx := 1.30
	var cz := 1.54

	# The carcass: one run from the dashboard corner aft to the chart table, with
	# a single top. What used to be three separate lumps of furniture standing
	# near each other is now one piece — a wheelhouse is fitted out, not furnished.
	_box(Vector3(0.64, 0.72, 3.21), Vector3(cx, 3.27, 1.745), Vector3.ZERO, trim)
	_box(Vector3(0.68, 0.05, 3.25), Vector3(cx, 3.655, 1.745), Vector3.ZERO, trim)
	# Drawer fronts down its inboard face.
	for d in 5:
		_box(Vector3(0.02, 0.15, 0.56), Vector3(cx - 0.325, 3.44 - float(d % 2) * 0.20,
				0.45 + float(d) * 0.62), Vector3.ZERO, _mat(Color(0.09, 0.07, 0.05), 0.9))
		_box(Vector3(0.03, 0.025, 0.10), Vector3(cx - 0.34, 3.44 - float(d % 2) * 0.20,
				0.45 + float(d) * 0.62), Vector3.ZERO, bronze)
	# The well holds the cartridges and the four house switches. Flood and
	# the wiper sit on the dash.
	_build_fuse_box(bronze)
	return {
		"fuse_lid": _fuse_lid,
		"fuse_latch_local": _fuse_latch_local,
		"fuse_bodies": fuse_bodies,
		"switch_levers": switch_levers,
		"switch_leds": switch_leds,
	}


func _build_fuse_box(bronze: Material) -> void:
	## One steel well, one grid. Inboard column is the house toggles,
	## outboard is the cartridges. Every row uses the same pitch.
	const BOX_X := 1.140
	const BOX_Z := 1.340
	const INNER_W := 0.230
	const PITCH := 0.070
	const INNER_L := PITCH * 4.0 + 0.072
	const WALL := 0.012
	const FLOOR := 3.656
	const RIM := 3.738
	const LID_T := 0.008
	const COL_SW := 1.090
	const COL_FU := 1.195
	const Z0 := BOX_Z - PITCH * 1.5
	var outer_w: float = INNER_W + WALL * 2.0
	var outer_l: float = INNER_L + WALL * 2.0
	var hinge_z: float = BOX_Z - outer_l * 0.5
	var wall_h: float = RIM - FLOOR
	var wall_cy: float = FLOOR + wall_h * 0.5
	var enamel := _mat(Color(0.38, 0.36, 0.30), 0.70)
	var phenolic := _mat(Color(0.10, 0.07, 0.05), 0.64)
	var copper := _mat(Color(0.58, 0.32, 0.13), 0.34, 0.90)
	var ceramic := _mat(Color(0.84, 0.80, 0.72), 0.50)
	var cloth := _mat(Color(0.13, 0.10, 0.08), 0.88)
	var red_lead := _mat(Color(0.42, 0.08, 0.06), 0.72)
	var steel := _mat(Color(0.22, 0.22, 0.23), 0.48, 0.62)
	var gasket := _mat(Color(0.06, 0.055, 0.05), 0.94)
	var lid_mat := _mat(Color(0.20, 0.205, 0.21), 0.46, 0.58)

	_box(Vector3(INNER_W, 0.006, INNER_L), Vector3(BOX_X, FLOOR, BOX_Z), Vector3.ZERO, phenolic)
	_box(Vector3(outer_w, wall_h, WALL), Vector3(BOX_X, wall_cy, BOX_Z - INNER_L * 0.5 - WALL * 0.5),
			Vector3.ZERO, steel)
	_box(Vector3(outer_w, wall_h, WALL), Vector3(BOX_X, wall_cy, BOX_Z + INNER_L * 0.5 + WALL * 0.5),
			Vector3.ZERO, steel)
	_box(Vector3(WALL, wall_h, INNER_L), Vector3(BOX_X - INNER_W * 0.5 - WALL * 0.5, wall_cy, BOX_Z),
			Vector3.ZERO, steel)
	_box(Vector3(WALL, wall_h, INNER_L), Vector3(BOX_X + INNER_W * 0.5 + WALL * 0.5, wall_cy, BOX_Z),
			Vector3.ZERO, steel)
	var rim_y: float = RIM - 0.002
	var gask_y: float = RIM + 0.001
	var rim_w: float = outer_w + 0.008
	var frame: float = (rim_w - INNER_W) * 0.5
	_box(Vector3(rim_w, 0.004, frame), Vector3(BOX_X, rim_y, BOX_Z - (INNER_L + frame) * 0.5),
			Vector3.ZERO, steel)
	_box(Vector3(rim_w, 0.004, frame), Vector3(BOX_X, rim_y, BOX_Z + (INNER_L + frame) * 0.5),
			Vector3.ZERO, steel)
	_box(Vector3(frame, 0.004, INNER_L), Vector3(BOX_X - (INNER_W + frame) * 0.5, rim_y, BOX_Z),
			Vector3.ZERO, steel)
	_box(Vector3(frame, 0.004, INNER_L), Vector3(BOX_X + (INNER_W + frame) * 0.5, rim_y, BOX_Z),
			Vector3.ZERO, steel)
	_box(Vector3(INNER_W + 0.010, 0.003, 0.008), Vector3(BOX_X, gask_y, BOX_Z - INNER_L * 0.5),
			Vector3.ZERO, gasket)
	_box(Vector3(INNER_W + 0.010, 0.003, 0.008), Vector3(BOX_X, gask_y, BOX_Z + INNER_L * 0.5),
			Vector3.ZERO, gasket)
	_box(Vector3(0.008, 0.003, INNER_L), Vector3(BOX_X - INNER_W * 0.5, gask_y, BOX_Z),
			Vector3.ZERO, gasket)
	_box(Vector3(0.008, 0.003, INNER_L), Vector3(BOX_X + INNER_W * 0.5, gask_y, BOX_Z),
			Vector3.ZERO, gasket)

	_box(Vector3(0.012, 0.006, INNER_L - 0.05), Vector3(COL_FU + 0.028, FLOOR + 0.010, BOX_Z),
			Vector3.ZERO, copper)
	_cyl(0.006, 0.006, 0.08, Vector3(COL_FU + 0.028, FLOOR - 0.036, Z0 - 0.02),
			Vector3.ZERO, red_lead)
	_cyl(0.011, 0.011, 0.014, Vector3(COL_FU + 0.028, FLOOR + 0.012, Z0 - 0.02),
			Vector3.ZERO, steel)
	_stamp("12V", Vector3(BOX_X, FLOOR + 0.006, Z0 - 0.048), 16)

	_fuse_lid = Node3D.new()
	_fuse_lid.position = Vector3(BOX_X, RIM, hinge_z)
	_owner.add_child(_fuse_lid)
	var lid_w: float = outer_w + 0.008
	var lid_l: float = outer_l + 0.006
	_fuse_latch_local = Vector3(0.0, LID_T + 0.004, lid_l - 0.018)
	_box(Vector3(lid_w, LID_T, lid_l), Vector3(0.0, LID_T * 0.5, lid_l * 0.5),
			Vector3.ZERO, lid_mat, _fuse_lid)
	_box(Vector3(lid_w - 0.010, 0.003, lid_l - 0.010), Vector3(0.0, LID_T + 0.001, lid_l * 0.5),
			Vector3.ZERO, enamel, _fuse_lid)
	var lip_d := 0.006
	var lip_y := -lip_d * 0.5
	_box(Vector3(INNER_W - 0.010, lip_d, 0.005), Vector3(0.0, lip_y, WALL + 0.008),
			Vector3.ZERO, lid_mat, _fuse_lid)
	_box(Vector3(INNER_W - 0.010, lip_d, 0.005), Vector3(0.0, lip_y, lid_l - WALL - 0.008),
			Vector3.ZERO, lid_mat, _fuse_lid)
	_box(Vector3(0.005, lip_d, INNER_L - 0.014), Vector3(-(INNER_W * 0.5 - 0.010), lip_y, lid_l * 0.5),
			Vector3.ZERO, lid_mat, _fuse_lid)
	_box(Vector3(0.005, lip_d, INNER_L - 0.014), Vector3(INNER_W * 0.5 - 0.010, lip_y, lid_l * 0.5),
			Vector3.ZERO, lid_mat, _fuse_lid)
	_box(Vector3(0.040, 0.010, 0.024), _fuse_latch_local, Vector3.ZERO, bronze, _fuse_lid)
	_box(Vector3(0.012, 0.014, 0.008), Vector3(0.0, 0.000, lid_l - 0.004),
			Vector3.ZERO, bronze, _fuse_lid)
	for hx in [-0.05, 0.05]:
		_cyl(0.006, 0.006, 0.018, Vector3(BOX_X + hx, RIM, hinge_z),
				Vector3(0.0, 0.0, 90.0), bronze)

	var sw_ids: Array[String] = ["sw_cabin", "sw_helm", "sw_beacon", "sw_anchor"]
	var fu_ids: Array[String] = ["fu_cabin", "fu_helm", "fu_beacon", "fu_anchor"]
	var names: Array[String] = ["CABIN", "WH LTS", "NAV", "WINDLASS"]
	var amps: Array[String] = ["10A", "5A", "10A", "40A"]
	for i in 4:
		var rz: float = Z0 + float(i) * PITCH
		_place_cartridge(fu_ids[i], Vector3(COL_FU, 3.676, rz), bronze, ceramic)
		_stamp(amps[i], Vector3(COL_FU + 0.022, 3.682, rz), 12)
		_stamp(names[i], Vector3(COL_SW - 0.038, 3.668, rz), 12)
		_cyl(0.0028, 0.0028, 0.048, Vector3((COL_SW + COL_FU) * 0.5, 3.664, rz),
				Vector3(0.0, 0.0, 90.0), cloth)
		build_toggle(sw_ids[i], Vector3(COL_SW, 3.688, rz), "", bronze, null, true)
	# Dash circuits still have a cartridge. They sit on the lid, not in the
	# grid — the well is four rows, and those two switches are at the helm.
	_place_cartridge("fu_flood", Vector3(-0.035, -0.014, 0.20), bronze, ceramic, _fuse_lid)
	_place_cartridge("fu_wiper", Vector3(0.035, -0.014, 0.20), bronze, ceramic, _fuse_lid)
	_stamp("FLOOD 15A", Vector3(-0.035, -0.006, 0.20), 10, _fuse_lid)
	_stamp("WIPER 5A", Vector3(0.035, -0.006, 0.20), 10, _fuse_lid)


func _place_cartridge(id: String, pos: Vector3, bronze: Material, ceramic: Material,
		parent: Node3D = null) -> void:
	_electrical.call("register_fuse", id)
	_box(Vector3(0.011, 0.009, 0.014), pos + Vector3(0.0, -0.006, -0.015),
			Vector3.ZERO, bronze, parent)
	_box(Vector3(0.011, 0.009, 0.014), pos + Vector3(0.0, -0.006, 0.015),
			Vector3.ZERO, bronze, parent)
	var cart := Node3D.new()
	cart.position = pos
	cart.set_meta("rest_y", pos.y)
	if parent == null:
		_owner.add_child(cart)
	else:
		parent.add_child(cart)
	_cyl(0.0055, 0.0055, 0.030, Vector3.ZERO, Vector3(90.0, 0.0, 0.0), ceramic, cart)
	_cyl(0.007, 0.007, 0.006, Vector3(0.0, 0.0, -0.014),
			Vector3(90.0, 0.0, 0.0), bronze, cart)
	_cyl(0.007, 0.007, 0.006, Vector3(0.0, 0.0, 0.014),
			Vector3(90.0, 0.0, 0.0), bronze, cart)
	fuse_bodies[id] = cart


func build_toggle(id: String, pos: Vector3, caption: String, bronze: Material,
		parent: Node3D = null, compact := false) -> void:
	## One brass toggle, its jewel and the ink under it. `pos` is the pivot
	## in the parent's frame (or the boat's). The lever grows along local +Y
	## so the same part sits on a flat face or on the raked dash.
	## `compact` is the well: jewel toward the fuse, name already on the row.
	var base := Vector3(0.036, 0.007, 0.032) if compact else Vector3(0.050, 0.008, 0.044)
	_box(base, pos + Vector3(0.0, -0.012, 0.0), Vector3.ZERO, bronze, parent)
	var piv := Node3D.new()
	piv.position = pos
	if parent == null:
		_owner.add_child(piv)
	else:
		parent.add_child(piv)
	_cyl(0.010, 0.007, 0.044, Vector3(0.0, 0.022, 0.0), Vector3.ZERO, bronze, piv)
	var tip := MeshInstance3D.new()
	var tm := SphereMesh.new()
	tm.radius = 0.011
	tm.height = 0.022
	tm.material = bronze
	tip.mesh = tm
	tip.position = Vector3(0.0, 0.046, 0.0)
	tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	piv.add_child(tip)
	switch_levers[id] = piv
	var led_mat := _mat(Color(0.18, 0.14, 0.10), 0.16)
	led_mat.emission_enabled = true
	led_mat.emission = Color(1.0, 0.70, 0.28)
	led_mat.emission_energy_multiplier = 0.0
	var jx: Vector3 = pos + (Vector3(0.024, 0.002, 0.0) if compact \
			else Vector3(-0.038, 0.002, 0.0))
	_box(Vector3(0.014, 0.005, 0.014), jx + Vector3(0.0, -0.008, 0.0),
			Vector3.ZERO, bronze, parent)
	var led := MeshInstance3D.new()
	var lm := SphereMesh.new()
	lm.radius = 0.0055
	lm.height = 0.011
	lm.material = led_mat
	led.mesh = lm
	led.position = jx
	led.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if parent == null:
		_owner.add_child(led)
	else:
		parent.add_child(led)
	switch_leds[id] = led_mat
	if caption != "":
		_box(Vector3(0.062, 0.003, 0.012), pos + Vector3(0.0, -0.014, 0.036),
				Vector3.ZERO, bronze, parent)
		_stamp(caption, pos + Vector3(0.0, -0.010, 0.036), 16, parent)


func _stamp(text: String, pos: Vector3, size: int, parent: Node3D = null) -> void:
	## Ink in the brass, not a caption floating over it.
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.00034
	l.modulate = Color(0.18, 0.12, 0.06)
	l.shaded = true
	l.double_sided = false
	l.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	l.position = pos
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if parent == null:
		_owner.add_child(l)
	else:
		parent.add_child(l)


func _mat(albedo: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	return _mat_callback.call(albedo, rough, metal) as StandardMaterial3D


func _box(size: Vector3, pos: Vector3, rot_deg: Vector3, mat: Material,
		parent: Node3D = null) -> void:
	_box_callback.call(size, pos, rot_deg, mat, parent)


func _cyl(r_bot: float, r_top: float, h: float, pos: Vector3,
		rot_deg: Vector3, mat: Material, parent: Node3D = null) -> void:
	_cyl_callback.call(r_bot, r_top, h, pos, rot_deg, mat, parent)
