extends Node3D
## Anchor, chain and windlass.
##
## Four states, and the interesting one is SET. An anchored boat is not pinned
## to a point: she lies to her chain, swings head to wind and stream, and surges
## back whenever a sea shoulders her past the scope she has out. So the chain is
## modelled as what it is — a line with a length, that does nothing at all until
## it comes tight and then pulls very hard, from the bow roller rather than from
## the centre of the boat, which is why she rounds up to it.
##
## Once she is dug in the windlass pays only a snubbed margin beyond the lie of
## the chain, so the boat stays where you dropped the hook instead of orbiting
## the full length of her cable.

enum State { STOWED, VEERING, SET, WEIGHING }

const MAX_CHAIN := 70.0
## Let go, the anchor takes the chain with it: the windlass is out of gear and
## the cable runs free until the hook hits bottom. Hauling back is winch work.
const VEER_RATE := 7.0          # m/s the windlass pays after the anchor lands
const WEIGH_RATE := 3.2         # m/s hauling in
const CHAIN_STIFFNESS := 60000.0
const CHAIN_DAMPING := 9500.0
## Far above anything the engine or the weather can pull: once she is dug in,
## the boat stays where the chain says until you weigh.
const HOLDING_POWER := 560000.0
## Enough interlocking rings to cover MAX_CHAIN at LINK_PITCH. Stretching a
## few hundred across seventy metres is what turned the cable into dots.
const LINKS := 1800
const LINK_PITCH := 0.040

var boat: RigidBody3D
var ocean: Node3D

var state: int = State.STOWED
var chain_out := 0.0
var anchor_pos := Vector3.ZERO
var planted := false

var _anchor_vel := Vector3.ZERO
var _chain_mm: MultiMesh
var _chain_mi: MultiMeshInstance3D
var _anchor_mi: Node3D
var _link_mat: ShaderMaterial
var chain_rate := 0.0
## The gypsy is on the windlass fuse. Pulled, VEERING/WEIGHING freeze —
## the hook stays where it is, the drum does not turn.
var gypsy_powered := true
var _rumble := 0.0
var _scope_target := -1.0
var _drop_xz := Vector2.ZERO
var _splashed := false


func _ready() -> void:
	top_level = true
	# Galvanised, not black iron — the old colour vanished against the hull and
	# against the sea, and the whole point of ground tackle is watching it go.
	# On its own shader so that below the surface it takes the water's colour
	# instead of staying deck-bright all the way to the bottom.
	_link_mat = ShaderMaterial.new()
	_link_mat.shader = load("res://shaders/tackle.gdshader")
	_link_mat.set_shader_parameter("albedo", Color(0.38, 0.375, 0.365))
	_link_mat.set_shader_parameter("rough", 0.42)
	_link_mat.set_shader_parameter("metal", 0.80)
	_link_mat.set_shader_parameter("absorb", 0.085)
	var hook_mat := ShaderMaterial.new()
	hook_mat.shader = _link_mat.shader
	hook_mat.set_shader_parameter("albedo", Color(0.46, 0.42, 0.36))
	hook_mat.set_shader_parameter("rough", 0.48)
	hook_mat.set_shader_parameter("metal", 0.78)
	# The hook has to stay iron in the photic zone. Chain can fade; the
	# thing you swam down for cannot vanish into the murk.
	hook_mat.set_shader_parameter("absorb", 0.042)

	var ring := TorusMesh.new()
	# ~7 cm oval, bar thick enough to read through murk. Tiny rings vanish
	# between their own holes and look like a dotted line from the water.
	ring.inner_radius = 0.013
	ring.outer_radius = 0.028
	ring.rings = 8
	ring.ring_segments = 8
	ring.material = _link_mat
	_chain_mm = MultiMesh.new()
	_chain_mm.transform_format = MultiMesh.TRANSFORM_3D
	_chain_mm.mesh = ring
	_chain_mm.instance_count = LINKS
	_chain_mm.visible_instance_count = 0
	_chain_mi = MultiMeshInstance3D.new()
	_chain_mi.multimesh = _chain_mm
	_chain_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_chain_mi.layers = 8          # out of the mirror; see ocean.TACKLE_LAYER
	add_child(_chain_mi)

	_anchor_mi = Node3D.new()
	add_child(_anchor_mi)
	_anchor_mi.visible = false
	# Origin is the RING — where the cable shackles. Shank and flukes hang
	# below so the chain meets iron, not empty water.
	var eye := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.055
	tm.outer_radius = 0.095
	tm.rings = 14
	tm.ring_segments = 10
	tm.material = hook_mat
	eye.mesh = tm
	eye.layers = 8
	_anchor_mi.add_child(eye)
	_stock(Vector3(0.13, 1.28, 0.13), Vector3(0.0, -0.70, 0.0), 0.0, hook_mat)
	_stock(Vector3(1.05, 0.09, 0.09), Vector3(0.0, -0.22, 0.0), 0.0, hook_mat)
	_stock(Vector3(0.22, 0.22, 0.22), Vector3(0.0, -1.32, 0.0), 0.0, hook_mat)
	_stock(Vector3(0.78, 0.16, 0.22), Vector3(-0.38, -1.48, 0.0), 38.0, hook_mat)
	_stock(Vector3(0.78, 0.16, 0.22), Vector3(0.38, -1.48, 0.0), -38.0, hook_mat)


func _stock(size: Vector3, pos: Vector3, roll := 0.0, mat: Material = null) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat if mat != null else _link_mat
	mi.mesh = bm
	mi.position = pos
	mi.rotation_degrees.z = roll
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.layers = 8
	_anchor_mi.add_child(mi)


## Where the cable leaves her: over the roller at the stemhead, above the bow
## rail, clear of the planking. It used to be tucked inside the bow and the
## chain came out THROUGH her.
const ROLLER_LOCAL := Vector3(0.0, 1.20, -4.12)
## Just forward of the stem, below the roller — the lead a hawse actually
## gives. The hook hangs HERE, not inside the peak.
const FAIR_LOCAL := Vector3(0.0, 0.92, -4.58)
const HANG_LOCAL := Vector3(0.0, 0.48, -4.72)
const STEM_FOOT_LOCAL := Vector3(0.0, 0.10, -4.52)
const KEEL_LOCAL := Vector3(0.0, -0.82, -3.85)


func roller() -> Vector3:
	## The bow roller: where the chain leaves the boat, and where its pull is
	## applied. Forward of the centre of mass, so she rounds up to her anchor.
	if boat == null:
		return global_position
	return boat.global_transform * ROLLER_LOCAL


func _boat_pt(local: Vector3) -> Vector3:
	if boat == null:
		return global_position
	return boat.global_transform * local


func hang() -> Vector3:
	## Catted outboard of the stem. The shank hangs in the air ahead of the
	## planking; the flukes are in the water, not in the locker.
	return _boat_pt(HANG_LOCAL)


func toggle() -> void:
	match state:
		State.STOWED:
			state = State.VEERING
			anchor_pos = hang()
			# The spot she went in at. The anchor holds this xz the whole way
			# down: iron dropped over the bow lands where it was dropped, it is
			# not towed sideways through the water by a boat on the surface.
			_drop_xz = Vector2(anchor_pos.x, anchor_pos.z)
			_anchor_vel = Vector3.ZERO
			planted = false
			_splashed = false
			_scope_target = -1.0
			chain_out = 1.0
		State.VEERING, State.SET:
			state = State.WEIGHING
		State.WEIGHING:
			state = State.VEERING
			_scope_target = -1.0


func status() -> String:
	match state:
		State.VEERING:
			return "ANCHOR DOWN  %.0f m chain" % chain_out
		State.SET:
			return ("ANCHOR HOLDING  %.0f m chain" % chain_out) if planted \
					else ("ANCHOR DRAGGING  %.0f m" % chain_out)
		State.WEIGHING:
			return "ANCHOR HEAVING  %.0f m" % chain_out
		_:
			return ""


func _physics_process(delta: float) -> void:
	if boat == null:
		return
	var rl := roller()
	var chain_was := chain_out

	match state:
		State.VEERING:
			_rumble = 1.0
			if not planted:
				# The anchor is falling; _fall lets it strip chain as it goes.
				_fall(delta, rl)
			else:
				# On the bottom: pay just enough beyond the lie of the chain
				# for a snubbed few metres of swing, then hold. The target is
				# LOCKED the moment the hook lands — recomputing it while the
				# boat runs off would have the chain chasing her forever and
				# never coming taut.
				if _scope_target < 0.0:
					_scope_target = minf(anchor_pos.distance_to(rl) * 1.12 + 2.0, MAX_CHAIN)
				if gypsy_powered and chain_out < _scope_target:
					chain_out = minf(chain_out + VEER_RATE * delta, _scope_target)
				elif gypsy_powered:
					state = State.SET
		State.SET:
			_rumble = 0.0
			if not planted:
				_fall(delta, rl)
		State.WEIGHING:
			if gypsy_powered:
				chain_out = maxf(chain_out - WEIGH_RATE * delta, 0.0)
			_rumble = 1.0 if gypsy_powered else 0.0
			var to_a := anchor_pos - rl
			var d := to_a.length()
			if d > chain_out:
				# Short-scoped: the hook comes up the hawse, not through her.
				planted = false
				var haul: Vector3 = hang()
				var ahead: Vector3 = -boat.global_basis.z
				ahead.y = 0.0
				var flat: Vector3 = anchor_pos - haul
				flat.y = 0.0
				if ahead.length_squared() > 0.01 and ahead.normalized().dot(flat) < 0.15:
					var keel: Vector3 = _boat_pt(KEEL_LOCAL)
					if anchor_pos.distance_to(keel) > 2.0:
						haul = keel
				var to_h: Vector3 = anchor_pos - haul
				var hd := to_h.length()
				if hd > 0.01:
					anchor_pos = haul + to_h / hd * minf(chain_out, hd)
				else:
					anchor_pos = haul
				_anchor_vel = Vector3.ZERO
			if chain_out <= 0.35:
				state = State.STOWED
				planted = false

	if state != State.STOWED:
		_pull(delta, rl)

	# Metres a second off the drum, positive paying out. The windlass turns on
	# this, so what you see spinning on the foredeck is the cable that is
	# actually running.
	chain_rate = (chain_out - chain_was) / maxf(delta, 1e-4)
	if _link_mat != null and ocean != null:
		_link_mat.set_shader_parameter("water_y",
				float(ocean.get_height(boat.global_position)))

	_draw(rl)


func _fall(delta: float, rl: Vector3) -> void:
	## Straight down, and in where it went in.
	##
	## The old version swept the anchor sideways toward the boat while it fell,
	## which is why letting go never looked like letting go — the hook slid
	## through the water after you instead of dropping. It holds the xz it was
	## released at; the chain runs off the drum to keep up with both the fall and
	## whatever way the boat carries on making. That is what a free-running
	## windlass does, and it is why you back down slowly when you anchor.
	var surf := 0.0
	if ocean != null:
		surf = float(ocean.get_height(anchor_pos))
	var bed := -28.0
	if ocean != null:
		bed = float(ocean.get_seafloor_height(anchor_pos))

	var in_water: bool = anchor_pos.y <= surf
	if in_water and not _splashed:
		_splashed = true
		if ocean != null and ocean.has_method("splash"):
			ocean.splash(Vector3(anchor_pos.x, surf, anchor_pos.z), 0.85)
	# Solid iron: it goes like a stone in air, and still fast in water.
	_anchor_vel.y += (-9.81 if not in_water else -8.2) * delta
	if in_water:
		_anchor_vel.y = maxf(_anchor_vel.y, -5.8)
	anchor_pos.y += _anchor_vel.y * delta
	anchor_pos.x = _drop_xz.x
	anchor_pos.z = _drop_xz.y

	# Chain pays out to match. Never shortens: what has run off has run off.
	var need := rl.distance_to(anchor_pos) + 0.4
	chain_out = clampf(maxf(chain_out, need), 0.0, MAX_CHAIN)
	if need > MAX_CHAIN:
		# Run out of cable with the hook still in mid-water. Now it is a weight
		# on the end of a taut chain and she feels every bit of it.
		_taut(rl)
		var to_a := anchor_pos - rl
		anchor_pos = rl + to_a.normalized() * MAX_CHAIN
		_drop_xz = Vector2(anchor_pos.x, anchor_pos.z)

	if anchor_pos.y <= bed:
		anchor_pos.y = bed
		_anchor_vel = Vector3.ZERO
		planted = true
		# Scope: chain out to something like five times the depth is the rule of
		# thumb; here it is the lie of the cable plus a margin to snub on.
		_scope_target = minf(rl.distance_to(anchor_pos) * 1.25 + 5.0, MAX_CHAIN)


func _taut(rl: Vector3) -> void:
	## A chain is not a spring, and this is the whole difference.
	##
	## Past its length a rope or a cable does not push back harder the further
	## you stretch it — it simply stops you. So take the outward component of
	## her way away from her outright, then close whatever is left. Applied at
	## the BOW ROLLER, which is why she rounds up head to her anchor instead of
	## being dragged sideways. The old spring model let her bounce out and back
	## on the end of it, which ground tackle never does.
	var to_a := anchor_pos - rl
	var d := to_a.length()
	if d <= chain_out:
		return
	var dir := to_a / maxf(d, 1e-4)
	var excess := d - chain_out
	var arm := rl - boat.global_position
	var v_at: Vector3 = boat.linear_velocity + boat.angular_velocity.cross(arm)
	var vout := -v_at.dot(dir)
	if vout > 0.0:
		# Take her way off along the cable. Not all of it: a chain has a
		# catenary and a boat has a snubber, so a little surge is right.
		boat.apply_impulse(dir * vout * boat.mass * 0.82, arm)
	boat.apply_force(dir * minf(excess, 2.0) * CHAIN_STIFFNESS, arm)
	# Some of it into the whole hull, so she settles instead of slewing about
	# the roller.
	var bv: Vector3 = boat.linear_velocity
	boat.apply_central_force(-Vector3(bv.x, 0.0, bv.z) * 9000.0
			* clampf(excess * 3.0, 0.0, 1.0))


func _pull(delta: float, rl: Vector3) -> void:
	if not planted:
		return
	var to_a := anchor_pos - rl
	var d := to_a.length()
	if d <= chain_out:
		return  # slack; the chain is doing nothing at all
	var dir := to_a / maxf(d, 1e-4)
	var excess := d - chain_out
	_taut(rl)

	# Past her holding power she drags, and drags toward the load.
	var mag := excess * CHAIN_STIFFNESS + boat.linear_velocity.length() * CHAIN_DAMPING
	if mag > HOLDING_POWER:
		var drag := (mag - HOLDING_POWER) / HOLDING_POWER * 1.4 * delta
		anchor_pos -= dir * drag
		var bed := -28.0
		if ocean != null:
			bed = float(ocean.get_seafloor_height(anchor_pos))
		anchor_pos.y = bed


func _draw(rl: Vector3) -> void:
	# Stowed, she hangs OUTBOARD of the stem. Laid along the roller she sat
	# inside the peak; hung down from it she went through the planking. Catted
	# forward of the fairlead, shank up, flukes in the water ahead of her.
	if state == State.STOWED:
		_anchor_mi.visible = true
		_anchor_mi.global_position = hang()
		_anchor_mi.global_basis = boat.global_basis
		# Boat owns gypsy-to-roller. Here only the bight over the stem.
		_place_link_poly(_hang_path(rl))
		return
	_anchor_mi.visible = true
	_anchor_mi.global_position = anchor_pos
	var lie := (rl - anchor_pos)
	if planted:
		_anchor_mi.rotation = Vector3(0.0, atan2(lie.x, lie.z), 0.0)
	else:
		_anchor_mi.rotation = Vector3(0.25 * sin(anchor_pos.y * 1.3), atan2(lie.x, lie.z), 0.0)

	_place_link_poly(_overboard_path(rl))


func _hang_path(rl: Vector3) -> PackedVector3Array:
	## First metres over the roller: a J, not a kink. Deck chain stops at
	## the drum; this is only what leaves her.
	var keys := PackedVector3Array()
	var b: Basis = boat.global_basis
	keys.append(rl + b * Vector3(0.0, 0.01, 0.04))
	keys.append(rl)
	keys.append(rl + b * Vector3(0.0, -0.08, -0.14))
	keys.append(_boat_pt(FAIR_LOCAL))
	keys.append(hang())
	return _catmull_world(keys, 6)


func _catmull_world(keys: PackedVector3Array, per: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	if keys.size() < 2:
		return keys
	for i in range(keys.size() - 1):
		var p0: Vector3 = keys[maxi(i - 1, 0)]
		var p1: Vector3 = keys[i]
		var p2: Vector3 = keys[i + 1]
		var p3: Vector3 = keys[mini(i + 2, keys.size() - 1)]
		for s in per:
			var t := float(s) / float(per)
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t
					+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
					+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	out.append(keys[keys.size() - 1])
	return out


func _overboard_path(rl: Vector3) -> PackedVector3Array:
	## The cable NEVER chords the cabin. It leaves the roller, clears the
	## stem, and only then goes to the hook — down the hawse if she has
	## over-run it, which is what steaming over your own iron looks like.
	var pts := PackedVector3Array()
	var fair := _boat_pt(FAIR_LOCAL)
	var b: Basis = boat.global_basis
	pts.append(rl + b * Vector3(0.0, 0.01, 0.05))
	pts.append(rl)
	pts.append(rl + b * Vector3(0.0, -0.10, -0.16))
	pts.append(fair)
	var ahead: Vector3 = -boat.global_basis.z
	ahead.y = 0.0
	if ahead.length_squared() > 0.01:
		ahead = ahead.normalized()
	var to_h: Vector3 = anchor_pos - fair
	to_h.y = 0.0
	var astern := ahead.dot(to_h) < 0.20
	var surf := fair.y
	if ocean != null:
		surf = float(ocean.get_height(fair))
	if astern:
		var foot := _boat_pt(STEM_FOOT_LOCAL)
		foot.y = minf(foot.y, surf - 0.15)
		var keel := _boat_pt(KEEL_LOCAL)
		keel.y = minf(keel.y, surf - 0.85)
		pts.append(foot)
		pts.append(keel)
		_append_catenary(pts, keel, anchor_pos)
	else:
		_append_catenary(pts, fair, anchor_pos)
	return pts


func _append_catenary(pts: PackedVector3Array, a: Vector3, b: Vector3) -> void:
	var lie: Vector3 = a - b
	var d := lie.length()
	var slack := maxf(chain_out - d, 0.0)
	var lay := 0.0
	if planted:
		lay = minf(slack * 0.85, Vector2(lie.x, lie.z).length() * 0.7)
	var sag := minf((slack - lay) * 0.40, d * 0.45 + 0.4)
	var lift := b
	var flat := Vector2(lie.x, lie.z)
	if lay > 0.01 and flat.length() > 0.01:
		var fl := flat.normalized() * lay
		lift = b + Vector3(fl.x, 0.0, fl.y)
		if ocean != null:
			lift.y = float(ocean.get_seafloor_height(lift)) + 0.06
		pts.append(lift)
	var steps := 20
	for i in steps:
		var t := float(i + 1) / float(steps)
		var p := _catenary(lift, a, 1.0 - t, sag)
		if planted and i == 0:
			continue
		pts.append(p)
	if pts[pts.size() - 1].distance_squared_to(b) > 0.01:
		pts.append(b)


func _place_link_poly(pts: PackedVector3Array) -> void:
	if pts.size() < 2:
		_chain_mm.visible_instance_count = 0
		return
	var acc := PackedFloat32Array()
	acc.resize(pts.size())
	acc[0] = 0.0
	for i in range(1, pts.size()):
		acc[i] = acc[i - 1] + pts[i - 1].distance_to(pts[i])
	var total: float = maxf(acc[acc.size() - 1], 0.05)
	var slide := fposmod(chain_out, LINK_PITCH)
	# Fixed pitch, full run. Stretching a short stack of rings down the
	# hang is exactly the dotted column you get looking up from the water.
	var to_local: Transform3D = _chain_mi.global_transform.affine_inverse()
	var li := 0
	var d := slide
	while d < total - 0.008 and li < LINKS:
		_place_link(li, _along(pts, acc, d), _along(pts, acc, d + LINK_PITCH * 0.62), to_local)
		d += LINK_PITCH
		li += 1
	_chain_mm.visible_instance_count = li


func _along(pts: PackedVector3Array, acc: PackedFloat32Array, dist: float) -> Vector3:
	var d := clampf(dist, 0.0, acc[acc.size() - 1])
	for i in range(1, pts.size()):
		if acc[i] >= d - 1e-5:
			var span: float = maxf(acc[i] - acc[i - 1], 1e-5)
			var t: float = (d - acc[i - 1]) / span
			return pts[i - 1].lerp(pts[i], t)
	return pts[pts.size() - 1]


func _place_link(i: int, a: Vector3, b: Vector3, to_local: Transform3D) -> void:
	## Oval ring, hole alternating so they interlock. Visual length (~7 cm)
	## stays longer than LINK_PITCH so neighbours lock instead of floating.
	var seg := b - a
	var l := seg.length()
	if l <= 1e-5:
		_chain_mm.set_instance_transform(i, Transform3D())
		return
	var tang := seg / l
	var ref := Vector3.RIGHT if absf(tang.dot(Vector3.RIGHT)) < 0.86 else Vector3.FORWARD
	var n := tang.cross(ref)
	if n.length_squared() < 1e-6:
		n = Vector3.UP
	n = n.normalized()
	var hole := n if i % 2 == 0 else tang.cross(n).normalized()
	var side := tang.cross(hole)
	if side.length_squared() < 1e-6:
		side = n
	else:
		side = side.normalized()
	hole = tang.cross(side).normalized()
	var xf := Transform3D(Basis(tang * 1.72, hole, side), (a + b) * 0.5)
	_chain_mm.set_instance_transform(i, to_local * xf)


func _catenary(a: Vector3, b: Vector3, t: float, sag: float) -> Vector3:
	## Hangs the way a heavy chain hangs: steep where it leaves the boat, flat
	## where it meets the ground. A symmetric sine bulge — which is what this
	## was — puts the belly in the middle and makes the cable look like a
	## suspension cable rather than something with weight lying on a seabed.
	var p := a.lerp(b, t)
	var w := 1.0 - t
	p.y -= sag * (w * w * (3.0 - 2.0 * w)) * (0.35 + 0.65 * t)
	return p
