class_name BoatElectronicsVisualBuilder
extends RefCounted
## Builds the movable sounder, radar and VHF installations.
##
## Mesh emission is supplied by the boat so root-level static geometry keeps
## using its batching policy. The returned dictionary is the runtime contract.

const RADIO_ANCHOR := Vector3(1.548, 3.915, 0.50)
const RADIO_CRADLE := Vector3(1.49, 3.94, 0.55)

var _box_callback: Callable
var _cyl_callback: Callable
var _mat_callback: Callable
var _sounder_arm: Node3D
var _sounder_home := Vector3.ZERO
var _sounder_pivot: Node3D
var _sounder_case: MeshInstance3D
var _sounder_mat: ShaderMaterial
var _sounder_screen: MeshInstance3D
var _depth_hist: PackedFloat32Array
var _radar_arm: Node3D
var _radar_home := Vector3.ZERO
var _radar_pivot: Node3D
var _radar_case: MeshInstance3D
var _radar_mat: ShaderMaterial
var _radar_screen: MeshInstance3D
var _radar_ping: AudioStreamPlayer3D
var _radio_set: Node3D
var _radio_hand: Node3D
var _radio_snd: AudioStreamPlayer3D
var _cord: Array[MeshInstance3D] = []


func build(owner: Node3D, trim: Material, metal: Material,
		box_callback: Callable, cyl_callback: Callable,
		mat_callback: Callable) -> Dictionary:
	_box_callback = box_callback
	_cyl_callback = cyl_callback
	_mat_callback = mat_callback
	## The two boxes aboard with wires going into them. Everything else on this
	## boat is brass and glass and does not care whether the batteries are up;
	## these two do, and they look it.
	var bronze := _mat(Color(0.34, 0.25, 0.12), 0.42, 0.75)
	var casing := _mat(Color(0.13, 0.135, 0.125), 0.72, 0.15)

	# --- echo sounder -------------------------------------------------------
	# High on the starboard side of the front bulkhead. It sat lower and further
	# inboard first, which put it squarely in the arc of the throttle lever —
	# the lever pivots at x 0.70 and swings 0.30 m of bronze right through where
	# the case used to be. Up here it is clear of the lever, clear of the wheel,
	# and still below the horizon at a standing eye.
	var sp := Vector3(1.15, 4.02, -0.06)
	_box(Vector3(0.05, 0.16, 0.04), sp + Vector3(-0.17, -0.10, 0.02), Vector3.ZERO, metal)
	_box(Vector3(0.05, 0.16, 0.04), sp + Vector3(0.17, -0.10, 0.02), Vector3.ZERO, metal)
	# Same hinge treatment as the radar above it: the bracket posts stay on the
	# bulkhead, the housing — case, face knobs and screen — hangs under a pivot
	# on the bolt line, so a hand on the case tips the whole instrument.
	var s_hinge := sp + Vector3(0.0, -0.10, 0.065)
	# Its own swing arm, one shelf down — same wrought iron, same bolted pads.
	var s_iron := _mat(Color(0.150, 0.115, 0.088), 0.90, 0.30)
	var s_pad := _mat(Color(0.205, 0.120, 0.070), 0.95, 0.15)
	_sounder_arm = Node3D.new()
	_sounder_arm.position = Vector3(0.62, 3.95, -0.03)
	owner.add_child(_sounder_arm)
	_sounder_home = _sounder_arm.position
	var s_off := s_hinge - _sounder_arm.position
	_box(Vector3(0.034, 0.43, 0.034), Vector3(0.0, -0.075, 0.0), Vector3.ZERO, s_iron, _sounder_arm)
	_cyl(0.030, 0.030, 0.045, Vector3(0.0, 0.07, 0.0), Vector3.ZERO, bronze, _sounder_arm)
	var s_mnt := _sounder_arm.position
	for spy in [0.10, -0.16]:
		_box(Vector3(0.10, 0.075, 0.028), s_mnt + Vector3(0.0, spy, -0.040), Vector3.ZERO, s_pad)
		for sbx in [-0.034, 0.034]:
			for sby in [-0.022, 0.022]:
				_cyl(0.007, 0.007, 0.013, s_mnt + Vector3(sbx, spy + sby, -0.024),
						Vector3(90.0, 0.0, 0.0), s_iron)
	_box(Vector3(0.022, 0.022, 0.26), s_mnt + Vector3(0.0, -0.24, -0.095),
			Vector3(-50.0, 0.0, 0.0), s_iron)
	# Same rule one shelf down: into the case body, aimed at its centre.
	var s_goal := Vector3(0.53, 0.0, -0.03)
	var s_dir := s_goal.normalized()
	var s_bar := MeshInstance3D.new()
	var sbm := BoxMesh.new()
	sbm.size = Vector3(0.026, 0.036, 0.50)
	sbm.material = s_iron
	s_bar.mesh = sbm
	s_bar.position = s_dir * 0.25 + Vector3(0.0, 0.07, 0.0)
	s_bar.rotation.y = atan2(s_goal.x, s_goal.z)
	_sounder_arm.add_child(s_bar)
	_sounder_pivot = Node3D.new()
	_sounder_pivot.position = s_off
	_sounder_arm.add_child(_sounder_pivot)
	var s_case := MeshInstance3D.new()
	var s_bm := BoxMesh.new()
	s_bm.size = Vector3(0.34, 0.27, 0.17)
	s_bm.material = casing
	s_case.mesh = s_bm
	s_case.position = sp - s_hinge
	s_case.rotation_degrees = Vector3(-22.0, 0.0, 0.0)
	_sounder_pivot.add_child(s_case)
	_sounder_case = s_case
	# Two knobs, as every one of these ever had. There WAS a bezel plate here
	# and it was sitting a centimetre in front of the glass, which is why the
	# screen read as a dead black rectangle.
	_cyl(0.018, 0.018, 0.022, sp + Vector3(-0.115, -0.085, 0.095) - s_hinge,
			Vector3(68.0, 0.0, 0.0), bronze, _sounder_pivot)
	_cyl(0.018, 0.018, 0.022, sp + Vector3(0.115, -0.085, 0.095) - s_hinge,
			Vector3(68.0, 0.0, 0.0), bronze, _sounder_pivot)

	_sounder_mat = ShaderMaterial.new()
	_sounder_mat.shader = load("res://shaders/sounder.gdshader")
	_depth_hist.resize(64)
	for i in 64:
		_depth_hist[i] = 0.0
	var scr := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.255, 0.185)
	qm.material = _sounder_mat
	scr.mesh = qm
	scr.position = sp + Vector3(0.0, 0.034, 0.088) - s_hinge
	scr.rotation_degrees = Vector3(-22.0, 0.0, 0.0)
	scr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sounder_pivot.add_child(scr)
	_sounder_screen = scr
	# --- radar, in the bracket above it -------------------------------------
	# The HOUSING rides a RAIL. The bracket posts and the two bronze bolt heads
	# stay on the bulkhead; casing and screen live under a carrier node, and
	# pulling the case slides the whole unit down its rail toward the helmsman —
	# a straight glide, no tilt — then home again the same way. Nothing
	# detaches, nothing flies to the lens.
	var rp := Vector3(1.18, 4.38, -0.05)
	_box(Vector3(0.05, 0.14, 0.04), rp + Vector3(-0.18, -0.16, 0.02), Vector3.ZERO, metal)
	_box(Vector3(0.05, 0.14, 0.04), rp + Vector3(0.18, -0.16, 0.02), Vector3.ZERO, metal)
	_cyl(0.016, 0.016, 0.020, rp + Vector3(-0.145, -0.135, 0.100), Vector3(70.0, 0.0, 0.0), bronze)
	_cyl(0.016, 0.016, 0.020, rp + Vector3(0.145, -0.135, 0.100), Vector3(70.0, 0.0, 0.0), bronze)
	var hinge := rp + Vector3(0.0, -0.135, 0.100)
	# The swing arm: WROUGHT IRON, not shop-fitting chrome. A thin old post
	# BOLTED to the bulkhead frame with two visible pad-plates and a diagonal
	# stay — every moving thing aboard shows what carries it, and this one
	# carries a radar, so it shows twice. The iron is rust-brown, pitted-rough,
	# and no thicker than it must be.
	var iron_old := _mat(Color(0.150, 0.115, 0.088), 0.90, 0.30)
	var iron_pad := _mat(Color(0.205, 0.120, 0.070), 0.95, 0.15)
	_radar_arm = Node3D.new()
	_radar_arm.position = Vector3(0.66, 4.245, -0.04)
	owner.add_child(_radar_arm)
	_radar_home = _radar_arm.position
	var arm_off := hinge - _radar_arm.position
	# Post: thin, and it STOPS at the arm. It used to run on up past the
	# carrier with the bar riding over the top, which put a length of iron in
	# the air above the set — the joint was on show instead of inside the thing
	# it holds. Console top to a hand above the bar, and no further.
	_box(Vector3(0.038, 0.73, 0.038), Vector3(0.0, -0.16, 0.0), Vector3.ZERO, iron_old, _radar_arm)
	_cyl(0.034, 0.034, 0.05, Vector3(0.0, 0.135, 0.0), Vector3.ZERO, bronze, _radar_arm)
	# Pad-plates clamping the post to the bulkhead frame, four bolt heads each.
	var mnt := _radar_arm.position
	for py in [0.16, -0.30]:
		_box(Vector3(0.11, 0.085, 0.030), mnt + Vector3(0.0, py, -0.045), Vector3.ZERO, iron_pad)
		for bx in [-0.038, 0.038]:
			for by2 in [-0.026, 0.026]:
				_cyl(0.0075, 0.0075, 0.014, mnt + Vector3(bx, py + by2, -0.028),
						Vector3(90.0, 0.0, 0.0), iron_old)
	# Diagonal stay down to the frame: an old bracket trusts a triangle.
	_box(Vector3(0.024, 0.024, 0.34), mnt + Vector3(0.0, -0.30, -0.115),
			Vector3(-52.0, 0.0, 0.0), iron_old)
	# NOTE: the pads and stay are added to the BOAT, not the arm — the mount
	# stays on the wall while the arm swings out of it.
	# The arm runs at the CASE'S OWN MID-HEIGHT and drives into its body, so the
	# last hand of iron is buried in the thing it carries. It is aimed at the
	# case CENTRE rather than at the pivot: the pivot sits 15 cm proud of the
	# casing's back face, so a bar ending there pokes out behind the set — and
	# the carrier yaws about that pivot as it comes round, which walks the case
	# further off it still. Aiming at the centre and running 0.50 m keeps the
	# tip inside the shell through the whole swing.
	var arm_goal := Vector3(0.52, 0.0, -0.06)
	var arm_dir := arm_goal.normalized()
	var arm_bar := MeshInstance3D.new()
	var abm := BoxMesh.new()
	abm.size = Vector3(0.028, 0.040, 0.50)
	abm.material = iron_old
	arm_bar.mesh = abm
	arm_bar.position = arm_dir * 0.25 + Vector3(0.0, 0.135, 0.0)
	arm_bar.rotation.y = atan2(arm_goal.x, arm_goal.z)
	_radar_arm.add_child(arm_bar)
	_radar_pivot = Node3D.new()
	_radar_pivot.position = arm_off
	_radar_arm.add_child(_radar_pivot)
	var rcase := MeshInstance3D.new()
	var rbm := BoxMesh.new()
	rbm.size = Vector3(0.38, 0.36, 0.20)
	rbm.material = casing
	rcase.mesh = rbm
	rcase.position = rp - hinge
	rcase.rotation_degrees = Vector3(-20.0, 0.0, 0.0)
	_radar_pivot.add_child(rcase)
	_radar_case = rcase
	_radar_mat = ShaderMaterial.new()
	_radar_mat.shader = load("res://shaders/radar.gdshader")
	var rscr := MeshInstance3D.new()
	var rq := QuadMesh.new()
	rq.size = Vector2(0.275, 0.275)
	rq.material = _radar_mat
	rscr.mesh = rq
	rscr.position = rp + Vector3(0.0, 0.038, 0.104) - hinge
	rscr.rotation_degrees = Vector3(-20.0, 0.0, 0.0)
	rscr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_radar_pivot.add_child(rscr)
	_radar_screen = rscr
	var ping_stream: AudioStream = load("res://assets/audio/radar_ping.mp3")
	if ping_stream != null:
		_radar_ping = AudioStreamPlayer3D.new()
		_radar_ping.stream = ping_stream
		_radar_ping.volume_db = -16.0
		_radar_ping.unit_size = 2.6
		_radar_ping.max_distance = 34.0
		_radar_ping.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		_radar_ping.position = rp - hinge
		_radar_pivot.add_child(_radar_ping)
	# Waveguide up through the deckhead toward the scanner on the roof.
	_cyl(0.010, 0.010, 0.42, rp + Vector3(0.10, 0.34, -0.02), Vector3(0.0, 0.0, -8.0), casing)

	# Transducer cable, disappearing through the deck the way they all do.
	_cyl(0.006, 0.006, 0.62, sp + Vector3(-0.10, -0.42, 0.02), Vector3(6.0, 0.0, 4.0), casing)

	# --- VHF set, on the starboard side forward of the chart table -----------
	_radio_set = Node3D.new()
	owner.add_child(_radio_set)
	var vhf_black := _mat(Color(0.035, 0.035, 0.038), 0.78, 0.08)
	var dark_face := _mat(Color(0.025, 0.025, 0.028), 0.62)
	var lcd := _mat(Color(0.05, 0.11, 0.07), 0.45)
	lcd.emission_enabled = true
	lcd.emission = Color(0.35, 1.0, 0.55)
	lcd.emission_energy_multiplier = 0.9

	# Case, with a face raked back so you can read it from the wheel.
	_box(Vector3(0.11, 0.22, 0.32), Vector3(1.605, 4.00, 0.44), Vector3.ZERO, vhf_black)
	_box(Vector3(0.012, 0.19, 0.29), Vector3(1.544, 4.00, 0.44), Vector3(0.0, 0.0, 0.0), dark_face)
	# Speaker grille: six slots, because that is what the front of one is.
	for i in 6:
		_box(Vector3(0.004, 0.012, 0.12), Vector3(1.537, 4.06 - float(i) * 0.019, 0.375),
				Vector3.ZERO, _mat(Color(0.02, 0.02, 0.02), 0.9))
	# Channel window. It sits on 16 — the distress and calling channel, which is
	# where a set left alone always ends up.
	_box(Vector3(0.006, 0.055, 0.085), Vector3(1.539, 3.965, 0.525), Vector3.ZERO,
			_mat(Color(0.03, 0.05, 0.035), 0.4))
	# "1": the two right-hand segments. "6": all but the top right.
	var sx := 1.5365
	_box(Vector3(0.004, 0.020, 0.005), Vector3(sx, 3.978, 0.556), Vector3.ZERO, lcd)
	_box(Vector3(0.004, 0.020, 0.005), Vector3(sx, 3.954, 0.556), Vector3.ZERO, lcd)
	for seg in [
		Vector3(0.0, 0.023, -0.014), Vector3(0.0, 0.000, -0.014), Vector3(0.0, -0.023, -0.014),
	]:
		_box(Vector3(0.004, 0.005, 0.024), Vector3(sx, 3.966 + seg.y, 0.525 + seg.z), Vector3.ZERO, lcd)
	_box(Vector3(0.004, 0.020, 0.005), Vector3(sx, 3.978, 0.5125), Vector3.ZERO, lcd)
	_box(Vector3(0.004, 0.020, 0.005), Vector3(sx, 3.954, 0.5125), Vector3.ZERO, lcd)
	_box(Vector3(0.004, 0.020, 0.005), Vector3(sx, 3.954, 0.5375), Vector3.ZERO, lcd)
	# Volume and squelch, and the channel rocker between them.
	_cyl(0.016, 0.014, 0.020, Vector3(1.537, 3.905, 0.545), Vector3(0.0, 0.0, 90.0), bronze)
	_cyl(0.016, 0.014, 0.020, Vector3(1.537, 3.905, 0.500), Vector3(0.0, 0.0, 90.0), bronze)
	_box(Vector3(0.008, 0.014, 0.040), Vector3(1.540, 3.905, 0.400), Vector3.ZERO, dark_face)
	# Aerial lead out of the top, and the power tail out of the bottom.
	_cyl(0.007, 0.007, 0.13, Vector3(1.605, 4.16, 0.40), Vector3(18.0, 0.0, 6.0), vhf_black)
	_cyl(0.006, 0.006, 0.22, Vector3(1.600, 3.80, 0.36), Vector3(-10.0, 0.0, 8.0), vhf_black)
	# Strain relief where the handset cord enters the case — the cord used to
	# start in mid-air a few centimetres off the box.
	_cyl(0.013, 0.008, 0.030, RADIO_ANCHOR + Vector3(0.012, 0.0, 0.0),
			Vector3(0.0, 0.0, 90.0), vhf_black)
	# Cradle hook the handset hangs on.
	_box(Vector3(0.05, 0.018, 0.10), RADIO_CRADLE + Vector3(0.028, -0.055, 0.0), Vector3.ZERO, metal)
	_box(Vector3(0.02, 0.055, 0.02), RADIO_CRADLE + Vector3(0.045, -0.012, -0.045), Vector3.ZERO, metal)

	# The handset. Its own node, because it leaves the cradle. Shaped the way one
	# is: a slim grip with a fat cap at each end, the earpiece a little deeper
	# than the mouthpiece, and the transmit bar under your thumb.
	_radio_hand = Node3D.new()
	owner.add_child(_radio_hand)
	_box(Vector3(0.038, 0.046, 0.150), Vector3(0.0, 0.0, 0.0), Vector3.ZERO, vhf_black, _radio_hand)
	_box(Vector3(0.054, 0.054, 0.052), Vector3(0.0, 0.004, -0.088), Vector3.ZERO, vhf_black, _radio_hand)
	_box(Vector3(0.050, 0.046, 0.044), Vector3(0.0, 0.002, 0.086), Vector3.ZERO, vhf_black, _radio_hand)
	# Earpiece and mouthpiece grilles.
	_cyl(0.019, 0.019, 0.004, Vector3(0.0, 0.029, -0.088), Vector3.ZERO,
			_mat(Color(0.02, 0.02, 0.02), 0.9), _radio_hand)
	_cyl(0.013, 0.013, 0.004, Vector3(0.0, 0.025, 0.086), Vector3.ZERO,
			_mat(Color(0.02, 0.02, 0.02), 0.9), _radio_hand)
	# Press-to-talk, on the side where your thumb lands, and a transmit lamp.
	_box(Vector3(0.008, 0.024, 0.062), Vector3(-0.023, 0.002, 0.006), Vector3.ZERO,
			_mat(Color(0.26, 0.09, 0.06), 0.7), _radio_hand)
	_box(Vector3(0.010, 0.008, 0.010), Vector3(0.0, 0.024, -0.052), Vector3.ZERO,
			_mat(Color(0.22, 0.05, 0.04), 0.6), _radio_hand)
	_radio_hand.position = RADIO_CRADLE
	_radio_hand.rotation_degrees = Vector3(0.0, 0.0, 12.0)
	var talk: AudioStream = load("res://assets/audio/telsiz_konusma.mp3")
	if talk != null:
		_radio_snd = AudioStreamPlayer3D.new()
		_radio_snd.stream = talk
		_radio_snd.volume_db = -5.0
		_radio_snd.unit_size = 1.1
		_radio_snd.max_distance = 26.0
		_radio_snd.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		_radio_hand.add_child(_radio_snd)

	# Coiled cord. Thirty-odd little cylinders that get laid along a helix every
	# frame — the helix tightens as you come back to the set and pulls out as
	# you walk away, which is the whole reason to have it.
	var cord_mat := _mat(Color(0.055, 0.055, 0.055), 0.85)
	# Eighty segments, and the turn count kept low, because a coil is sampled
	# geometry: wind it faster than the segments can follow and consecutive
	# points land on opposite sides of the helix, which draws a starburst of
	# chords rather than a cord.
	for i in 48:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.006
		cm.bottom_radius = 0.006
		cm.height = 1.0
		cm.radial_segments = 5
		cm.rings = 1
		cm.material = cord_mat
		mi.mesh = cm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		owner.add_child(mi)
		_cord.append(mi)


	return {
		"sounder_arm": _sounder_arm,
		"sounder_home": _sounder_home,
		"sounder_pivot": _sounder_pivot,
		"sounder_case": _sounder_case,
		"sounder_mat": _sounder_mat,
		"sounder_screen": _sounder_screen,
		"depth_hist": _depth_hist,
		"radar_arm": _radar_arm,
		"radar_home": _radar_home,
		"radar_pivot": _radar_pivot,
		"radar_case": _radar_case,
		"radar_mat": _radar_mat,
		"radar_screen": _radar_screen,
		"radar_ping": _radar_ping,
		"radio_set": _radio_set,
		"radio_hand": _radio_hand,
		"radio_snd": _radio_snd,
		"cord": _cord,
	}


func _mat(albedo: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	return _mat_callback.call(albedo, rough, metal) as StandardMaterial3D


func _box(size: Vector3, pos: Vector3, rot_deg: Vector3, mat: Material,
		parent: Node3D = null) -> void:
	_box_callback.call(size, pos, rot_deg, mat, parent)


func _cyl(r_bot: float, r_top: float, h: float, pos: Vector3,
		rot_deg: Vector3, mat: Material, parent: Node3D = null) -> void:
	_cyl_callback.call(r_bot, r_top, h, pos, rot_deg, mat, parent)
