class_name BoatDeckVisualBuilder
extends RefCounted

const BoatVisuals := preload("res://scripts/boat_visual_factory.gd")
const SEA_LADDER_X := 0.72
const SEA_LADDER_Z := 5.86
const SEA_LADDER_TOP := 0.66
const SEA_LADDER_RUNGS := 5

func build(owner: Node3D, trim: Material, metal: Material) -> Node3D:
	var host := Node3D.new()
	host.name = "DeckVisuals"
	owner.add_child(host)
	## Nothing on the walk. Cleats and chocks sit on the cap, fenders hang
	## outboard of the rubbing strake, the ring and the boathook live on the
	## house. You do not trip over a place this boat could make fast.
	var rubber := BoatVisuals.material(Color(0.07, 0.07, 0.07), 0.96)
	var hemp := BoatVisuals.material(Color(0.42, 0.34, 0.20), 0.9)
	var ring_or := BoatVisuals.material(Color(0.72, 0.18, 0.10), 0.7)
	var ring_wh := BoatVisuals.material(Color(0.82, 0.80, 0.74), 0.75)
	var wood := trim

	# Horn cleats: bow, just forward of the house, and the quarters.
	# A coil at the foot of each, and a spare warp on the foredeck — empty
	# iron is a showroom.
	for sx in [-1.0, 1.0]:
		_cleat(host, Vector3(sx * 1.88, 1.16, -3.62), metal)
		_warp_coil(host, Vector3(sx * 1.52, 0.63, -3.62), hemp, 0.11)
		# Warp from the horn to the fairlead — slack, because it is a rope on
		# a cleat, not a stay on the mast.
		_rope(host, Vector3(sx * 1.88, 1.18, -3.62), Vector3(sx * 0.62, 1.20, -3.98),
				0.012, 0.09, hemp)
		_cleat(host, Vector3(sx * 1.92, 1.16, -0.72), metal)
		_warp_coil(host, Vector3(sx * 1.55, 0.63, -0.72), hemp, 0.10)
		_cleat(host, Vector3(sx * 1.72, 1.18, 5.58), metal)
		# Quarter coil sits ON the cap next to the cleat, not hovering in the well.
		_warp_coil(host, Vector3(sx * 1.48, 1.18, 5.50), hemp, 0.09)
		# Closed fairleads on the stem and the transom corners.
		_fairlead(host, Vector3(sx * 0.62, 1.16, -3.98), metal)
		_fairlead(host, Vector3(sx * 1.55, 1.18, 5.58), metal)
	# Spare on the foredeck, against the starboard bulwark, clear of the pipe.
	_warp_coil(host, Vector3(1.22, 0.63, -3.48), hemp, 0.16)

	# --- boarding ladder, over the transom ----------------------------------
	# The one way back aboard. Rungs carry on well below the waterline because
	# the bottom one has to be there when she rolls away from you, and a ladder
	# you can only reach at the top of a swell is a ladder that drowns people.
	# Two timber cheeks frame the ladder head.  The upper hand targets live on
	# the outside faces of the iron stiles; without solid structure behind those
	# stiles the fingers were anatomically correct but read as grasping empty air
	# when viewed from below.  These boards are outside the climbing lane and are
	# through-bolted into the transom, so they add context without narrowing it.
	for cheek_x in [SEA_LADDER_X - 0.25, SEA_LADDER_X + 0.25]:
		_box(host, Vector3(0.12, 0.72, 0.085), Vector3(cheek_x, 0.80, 5.705),
				Vector3(-6.0, 0.0, 0.0), wood)
		for bolt_y in [0.52, 0.80, 1.08]:
			_cyl(host, 0.015, 0.015, 0.012, Vector3(cheek_x, bolt_y, 5.755),
					Vector3(90.0, 0.0, 0.0), metal)
	# One parent, six degrees of rake: stiles, rungs and the grab sit in the
	# same plane. Rotate the parts independently and the rungs hang in a
	# zigzag that is not a ladder.
	var lad := Node3D.new()
	lad.name = "SeaLadder"
	lad.position = Vector3(SEA_LADDER_X, 0.0, SEA_LADDER_Z)
	lad.rotation_degrees = Vector3(6.0, 0.0, 0.0)
	host.add_child(lad)
	var lad_iron := BoatVisuals.material(Color(0.150, 0.115, 0.088), 0.90, 0.30)
	for lsx in [-0.16, 0.16]:
		# Stop at the hull's lower edge. The old 72 cm tail hung beneath the keel
		# after the useful ladder had already ended and looked like a broken copy.
		_box(host, Vector3(0.045, 1.78, 0.045), Vector3(lsx, 0.26, 0.0),
				Vector3.ZERO, lad_iron, lad)
		# Continue each stile over the transom to the deck grab. Previously the
		# long ladder ended outboard while a second U was drawn on the cap, so an
		# underside view read as two loose handles. These shoulders make one
		# uninterrupted welded frame.
		_box(host, Vector3(0.045, 0.050, 0.405), Vector3(lsx, 1.145, -0.202),
				Vector3.ZERO, lad_iron, lad)
		_cyl(host, 0.031, 0.031, 0.055, Vector3(lsx, 1.145, -0.018),
				Vector3.ZERO, lad_iron, lad)
	var lad_n := SEA_LADDER_RUNGS
	for li in lad_n:
		var ly: float = SEA_LADDER_TOP - 0.10 - float(li) * 0.27
		_cyl(host, 0.020, 0.020, 0.36, Vector3(0.0, ly, 0.0),
				Vector3(0.0, 0.0, 90.0), lad_iron, lad)
	# Continue the same rung rhythm through the formerly empty upper reach. The
	# stiles already ran to the transom shoulder, but without these two steps they
	# read as long unrelated bars when viewed from the water below.
	for upper_y in [SEA_LADDER_TOP + 0.17, SEA_LADDER_TOP + 0.44]:
		_cyl(host, 0.020, 0.020, 0.36, Vector3(0.0, upper_y, 0.0),
				Vector3(0.0, 0.0, 90.0), lad_iron, lad)
	# The upper U is the deck end of those same continuous stiles. Matching tube
	# thickness and collars make the assembly read as one welded ladder.
	for lsx in [-0.16, 0.16]:
		_cyl(host, 0.032, 0.032, 0.18, Vector3(SEA_LADDER_X + lsx, 1.36, 5.58),
				Vector3.ZERO, lad_iron)
		_cyl(host, 0.038, 0.038, 0.035, Vector3(SEA_LADDER_X + lsx, 1.205, 5.58),
				Vector3.ZERO, lad_iron)
	_cyl(host, 0.032, 0.032, 0.36, Vector3(SEA_LADDER_X, 1.44, 5.58),
			Vector3(0.0, 0.0, 90.0), lad_iron)

	# Fenders: three a side, hanging outboard from the rail. Bow, waist,
	# quarter — the set you keep in the water when you might come alongside.
	for sx in [-1.0, 1.0]:
		for z in [-3.42, -0.88, 5.18]:
			_fender(host, Vector3(sx * 2.14, 0.58, z), rubber, hemp)

	# Lifebuoy on the starboard house, between the after window and the
	# corner — not in the walk, not over a pane.
	_lifebuoy(host, Vector3(1.88, 1.62, 3.28), ring_or, ring_wh, hemp)

	# Boathook lashed along the port house, under the windows.
	_cyl(host, 0.016, 0.016, 2.15, Vector3(-1.88, 1.38, 1.55), Vector3(90.0, 0.0, 0.0), wood)
	_cyl(host, 0.014, 0.010, 0.16, Vector3(-1.88, 1.38, 0.40), Vector3(90.0, 0.0, 0.0), metal)
	_cyl(host, 0.010, 0.010, 0.12, Vector3(-1.88, 1.30, 0.34), Vector3(0.0, 0.0, 0.0), metal)
	_cyl(host, 0.008, 0.008, 0.10, Vector3(-1.88, 1.38, 2.05), Vector3(0.0, 0.0, 90.0), hemp)
	_cyl(host, 0.008, 0.008, 0.10, Vector3(-1.88, 1.38, 1.05), Vector3(0.0, 0.0, 90.0), hemp)
	return host


func _cleat(host: Node3D, pos: Vector3, metal: Material) -> void:
	_box(host, Vector3(0.08, 0.035, 0.20), pos, Vector3.ZERO, metal)
	_cyl(host, 0.022, 0.018, 0.22, pos + Vector3(0.0, 0.04, 0.0), Vector3(90.0, 0.0, 0.0), metal)
	_cyl(host, 0.016, 0.016, 0.05, pos + Vector3(0.0, 0.04, 0.10), Vector3.ZERO, metal)
	_cyl(host, 0.016, 0.016, 0.05, pos + Vector3(0.0, 0.04, -0.10), Vector3.ZERO, metal)


func _fairlead(host: Node3D, pos: Vector3, metal: Material) -> void:
	_box(host, Vector3(0.10, 0.03, 0.12), pos, Vector3.ZERO, metal)
	_cyl(host, 0.016, 0.016, 0.10, pos + Vector3(-0.04, 0.06, 0.0), Vector3.ZERO, metal)
	_cyl(host, 0.016, 0.016, 0.10, pos + Vector3(0.04, 0.06, 0.0), Vector3.ZERO, metal)
	_cyl(host, 0.012, 0.012, 0.09, pos + Vector3(0.0, 0.10, 0.0), Vector3(0.0, 0.0, 90.0), metal)


func _fender(host: Node3D, pos: Vector3, rubber: Material, hemp: Material) -> void:
	## Line runs FROM the cap, not a vertical hanging in the air 16 cm outboard
	## of the rail it pretends to be made fast to.
	var sx: float = 1.0 if pos.x > 0.0 else -1.0
	var hitch := Vector3(sx * 1.98, 1.13, pos.z)
	var top := pos + Vector3(0.0, 0.26, 0.0)
	_rope(host, hitch, top, 0.008, 0.05, hemp, 8)
	_cyl(host, 0.095, 0.10, 0.52, pos, Vector3.ZERO, rubber)
	_cyl(host, 0.07, 0.07, 0.04, pos + Vector3(0.0, 0.26, 0.0), Vector3.ZERO, rubber)
	_cyl(host, 0.07, 0.07, 0.04, pos + Vector3(0.0, -0.26, 0.0), Vector3.ZERO, rubber)


func _lifebuoy(host: Node3D, pos: Vector3, orange: Material, white: Material, hemp: Material) -> void:
	var mi := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.12
	t.outer_radius = 0.22
	t.rings = 14
	t.ring_segments = 20
	t.material = orange
	mi.mesh = t
	mi.position = pos
	mi.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	host.add_child(mi)
	var stripe := MeshInstance3D.new()
	var t2 := TorusMesh.new()
	t2.inner_radius = 0.155
	t2.outer_radius = 0.185
	t2.rings = 10
	t2.ring_segments = 16
	t2.material = white
	stripe.mesh = t2
	stripe.position = pos
	stripe.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	host.add_child(stripe)
	_cyl(host, 0.008, 0.008, 0.28, pos + Vector3(-0.04, 0.22, 0.0), Vector3.ZERO, hemp)
	_box(host, Vector3(0.04, 0.03, 0.04), pos + Vector3(-0.04, 0.36, 0.0), Vector3.ZERO, hemp)

func _box(host: Node3D, size: Vector3, position: Vector3,
		rotation_degrees: Vector3, material: Material,
		parent: Node3D = null) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	instance.mesh = mesh
	instance.position = position
	instance.rotation_degrees = rotation_degrees
	(parent if parent != null else host).add_child(instance)
	return instance


func _cyl(host: Node3D, bottom_radius: float, top_radius: float, height: float,
		position: Vector3, rotation_degrees: Vector3, material: Material,
		parent: Node3D = null) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = bottom_radius
	mesh.top_radius = top_radius
	mesh.height = height
	mesh.radial_segments = 10
	mesh.material = material
	instance.mesh = mesh
	instance.position = position
	instance.rotation_degrees = rotation_degrees
	(parent if parent != null else host).add_child(instance)
	return instance


func _stay(host: Node3D, start: Vector3, finish: Vector3,
		radius: float, material: Material) -> void:
	var direction := finish - start
	var length := direction.length()
	if length < 0.04:
		return
	var instance := _cyl(host, radius, radius, length,
			(start + finish) * 0.5, Vector3.ZERO, material)
	var y := direction / length
	var x := y.cross(Vector3.UP)
	if x.length_squared() < 1e-8:
		x = y.cross(Vector3.FORWARD)
	x = x.normalized()
	instance.basis = Basis(x, y, x.cross(y))
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _rope(host: Node3D, start: Vector3, finish: Vector3, radius: float,
		sag: float, material: Material, segments := 14) -> void:
	if segments < 2:
		return
	var previous := start
	for i in range(1, segments + 1):
		var amount := float(i) / float(segments)
		var point := start.lerp(finish, amount)
		point.y -= 4.0 * amount * (1.0 - amount) * sag
		_stay(host, previous, point, radius, material)
		previous = point


func _warp_coil(host: Node3D, position: Vector3,
		material: Material, radius: float) -> void:
	for turn in 3:
		var instance := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = radius * 0.42
		torus.outer_radius = radius * (1.0 - float(turn) * 0.08)
		torus.rings = 10
		torus.ring_segments = 16
		torus.material = material
		instance.mesh = torus
		instance.position = position + Vector3(0.0,
				(torus.outer_radius - torus.inner_radius) * 0.5
				+ float(turn) * 0.020, 0.0)
		instance.rotation_degrees = Vector3(0.0, float(turn) * 22.0, 0.0)
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		host.add_child(instance)
