class_name BoatAnchorVisualBuilder
extends RefCounted
## Builds the breaker plate, bow roller, chain locker and moving windlass.

const BoatChainVisualScript := preload("res://scripts/boat_chain_visual.gd")

var _box_callback: Callable
var _cyl_callback: Callable
var _mat_callback: Callable


func build(owner: Node3D, metal: Material, bronze: Material,
		box_callback: Callable, cyl_callback: Callable,
		mat_callback: Callable) -> Dictionary:
	_box_callback = box_callback
	_cyl_callback = cyl_callback
	_mat_callback = mat_callback
	# --- main breaker on the bulkhead ----------------------------------------
	# The flush plate that used to be here is gone: its job belongs to the switch
	# console, where the switches are things you walk up to and throw. What is
	# left is the main breaker, which is what a bulkhead plate is for.
	_box(Vector3(0.03, 0.14, 0.11), Vector3(1.67, 4.02, 2.30), Vector3.ZERO, metal)
	_box(Vector3(0.03, 0.05, 0.03), Vector3(1.685, 4.02, 2.30), Vector3.ZERO, bronze)

	# --- bow roller at the stemhead ------------------------------------------
	# The cable has to leave her over something. Without it the chain simply
	# appeared out of the planking, which is the sort of thing you only notice
	# once and then cannot stop noticing.
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.035, 0.20, 0.34), Vector3(sx * 0.085, 1.16, -4.12),
				Vector3.ZERO, metal)
	_cyl(0.055, 0.055, 0.15, Vector3(0.0, 1.20, -4.12), Vector3(0.0, 0.0, 90.0), metal)
	_box(Vector3(0.22, 0.05, 0.30), Vector3(0.0, 1.05, -4.12), Vector3.ZERO, metal)
	# Stopper on the deck between the windlass and the roller, where the cable
	# is made fast once she is brought up.
	_box(Vector3(0.10, 0.10, 0.14), Vector3(0.0, 0.72, -3.80), Vector3.ZERO, metal)

	# --- spurling pipe and chain locker --------------------------------------
	# The cable has to GO somewhere. It comes in over the roller, round the
	# gypsy, and drops straight down this pipe into the locker in the forepeak —
	# and because the deck is genuinely cut, you can stand on the foredeck and
	# look down it at your own chain lying in the dark.
	var rust_iron := _mat(Color(0.150, 0.115, 0.088), 0.90, 0.30)
	# Raised coaming round the opening, so it is a fitting and not a slot.
	for r_sx in [-0.145, 0.145]:
		_box(Vector3(0.05, 0.09, 0.34), Vector3(r_sx, 0.68, -3.02), Vector3.ZERO, rust_iron)
	for r_sz in [-3.165, -2.875]:
		_box(Vector3(0.34, 0.09, 0.05), Vector3(0.0, 0.68, r_sz), Vector3.ZERO, rust_iron)
	# The pipe itself, dropping into the peak. Open both ends, seen from above.
	for p_sx in [-0.13, 0.13]:
		_box(Vector3(0.02, 0.52, 0.26), Vector3(p_sx, 0.30, -3.02), Vector3.ZERO, rust_iron)
	for p_sz in [-3.15, -2.89]:
		_box(Vector3(0.26, 0.52, 0.02), Vector3(0.0, 0.30, p_sz), Vector3.ZERO, rust_iron)
	# Locker: painted sides and a sole, so what is down there reads as a room
	# rather than as a void the chain disappears into.
	var locker_paint := _mat(Color(0.115, 0.120, 0.115), 0.92, 0.10)
	_box(Vector3(1.10, 0.03, 1.30), Vector3(0.0, 0.045, -3.05), Vector3.ZERO, locker_paint)
	_box(Vector3(0.03, 0.62, 1.30), Vector3(-0.55, 0.34, -3.05), Vector3.ZERO, locker_paint)
	_box(Vector3(0.03, 0.62, 1.30), Vector3(0.55, 0.34, -3.05), Vector3.ZERO, locker_paint)
	_box(Vector3(1.10, 0.62, 0.03), Vector3(0.0, 0.34, -3.70), Vector3.ZERO, locker_paint)
	_box(Vector3(1.10, 0.62, 0.03), Vector3(0.0, 0.34, -2.40), Vector3.ZERO, locker_paint)
	# The bitter end, shackled to a ringbolt in the forward bulkhead — the one
	# fitting on a boat whose whole job is to be the last thing that holds.
	_cyl(0.012, 0.012, 0.10, Vector3(0.0, 0.52, -3.66), Vector3(90.0, 0.0, 0.0), bronze)
	# Stowed cable is a COIL, not a ball. What has not gone over the bow
	# lives in here, piled the way a chain locker actually fills — loose
	# turns on the sole, growing as you weigh, gone as you veer.
	var link_iron := _mat(Color(0.28, 0.275, 0.268), 0.48, 0.86)
	var chain_visual := BoatChainVisualScript.new()
	owner.add_child(chain_visual)
	chain_visual.build(link_iron)

	# --- windlass on the foredeck, over the chain locker ---------------------
	# The bed and the standards are fixed; the GYPSY turns. You could not see
	# the cable being paid out or hove in before because the one part of the
	# boat whose whole job is to do that was a static box.
	_box(Vector3(0.56, 0.26, 0.34), Vector3(0.0, 0.80, -3.35), Vector3.ZERO, metal)
	_box(Vector3(0.07, 0.30, 0.30), Vector3(-0.30, 0.95, -3.35), Vector3.ZERO, metal)
	_box(Vector3(0.07, 0.30, 0.30), Vector3(0.30, 0.95, -3.35), Vector3.ZERO, metal)
	var windlass := Node3D.new()
	windlass.position = Vector3(0.0, 1.02, -3.35)
	owner.add_child(windlass)
	_cyl(0.13, 0.13, 0.46, Vector3.ZERO, Vector3(0.0, 0.0, 90.0), bronze, windlass)
	_cyl(0.17, 0.17, 0.05, Vector3(0.24, 0.0, 0.0), Vector3(0.0, 0.0, 90.0), metal, windlass)
	_cyl(0.17, 0.17, 0.05, Vector3(-0.24, 0.0, 0.0), Vector3(0.0, 0.0, 90.0), metal, windlass)
	# Whelps — the ribs round a gypsy that the links sit between. They are also
	# what lets you SEE it turning; a smooth drum spinning looks like a drum
	# standing still.
	for w in 8:
		var wa := float(w) / 8.0 * TAU
		_box(Vector3(0.44, 0.035, 0.055),
				Vector3(0.0, cos(wa) * 0.145, sin(wa) * 0.145),
				Vector3(rad_to_deg(wa), 0.0, 0.0), metal, windlass)
	# Handle on the end of the shaft, and the deck stopper abaft it.
	_cyl(0.018, 0.018, 0.20, Vector3(0.30, 0.0, 0.0), Vector3(0.0, 0.0, 90.0), bronze, windlass)
	_cyl(0.016, 0.016, 0.16, Vector3(0.40, 0.10, 0.0), Vector3(90.0, 0.0, 0.0), bronze, windlass)

	return {"chain_visual": chain_visual, "windlass": windlass}


func _mat(albedo: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	return _mat_callback.call(albedo, rough, metal) as StandardMaterial3D


func _box(size: Vector3, pos: Vector3, rot_deg: Vector3, mat: Material,
		parent: Node3D = null) -> void:
	_box_callback.call(size, pos, rot_deg, mat, parent)


func _cyl(r_bot: float, r_top: float, h: float, pos: Vector3,
		rot_deg: Vector3, mat: Material, parent: Node3D = null) -> void:
	_cyl_callback.call(r_bot, r_top, h, pos, rot_deg, mat, parent)
