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
const VEER_RATE := 4.5          # m/s the windlass pays after the anchor lands
const WEIGH_RATE := 1.8         # m/s hauling in
const CHAIN_STIFFNESS := 60000.0
const CHAIN_DAMPING := 9500.0
## Far above anything the engine or the weather can pull: once she is dug in,
## the boat stays where the chain says until you weigh.
const HOLDING_POWER := 560000.0
## Ninety-six, not fourteen. Fourteen segments across seventy metres of cable is
## one five-metre stick per link: it reads as a wire, not as chain. This is the
## one thing on the boat you watch run out, so it has to look like what it is.
const LINKS := 96

var boat: RigidBody3D
var ocean: Node3D

var state: int = State.STOWED
var chain_out := 0.0
var anchor_pos := Vector3.ZERO
var planted := false

var _anchor_vel := Vector3.ZERO
var _links: Array[MeshInstance3D] = []
var _anchor_mi: Node3D
var _link_mat: ShaderMaterial
var chain_rate := 0.0
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
	_link_mat.set_shader_parameter("albedo", Color(0.30, 0.30, 0.31))
	_link_mat.set_shader_parameter("rough", 0.42)
	_link_mat.set_shader_parameter("metal", 0.80)

	for i in LINKS:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.065
		cm.bottom_radius = 0.065
		cm.height = 1.0
		cm.radial_segments = 6
		cm.rings = 1
		cm.material = _link_mat
		mi.mesh = cm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.layers = 8          # out of the mirror; see ocean.TACKLE_LAYER
		mi.visible = false
		add_child(mi)
		_links.append(mi)

	_anchor_mi = Node3D.new()
	add_child(_anchor_mi)
	_anchor_mi.visible = false
	_stock(Vector3(0.11, 1.35, 0.11), Vector3(0.0, 0.0, 0.0))          # shank
	_stock(Vector3(1.15, 0.10, 0.10), Vector3(0.0, 0.62, 0.0))         # stock
	_stock(Vector3(0.14, 0.44, 0.44), Vector3(0.0, -0.62, 0.0))        # crown
	_stock(Vector3(0.62, 0.30, 0.12), Vector3(-0.30, -0.72, 0.0), 34.0)  # port fluke
	_stock(Vector3(0.62, 0.30, 0.12), Vector3(0.30, -0.72, 0.0), -34.0)  # stbd fluke


func _stock(size: Vector3, pos: Vector3, roll := 0.0) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = _link_mat
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


func roller() -> Vector3:
	## The bow roller: where the chain leaves the boat, and where its pull is
	## applied. Forward of the centre of mass, so she rounds up to her anchor.
	if boat == null:
		return global_position
	return boat.global_transform * ROLLER_LOCAL


func toggle() -> void:
	match state:
		State.STOWED:
			state = State.VEERING
			anchor_pos = roller()
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
				if chain_out < _scope_target:
					chain_out = minf(chain_out + VEER_RATE * delta, _scope_target)
				else:
					state = State.SET
		State.SET:
			_rumble = 0.0
			if not planted:
				_fall(delta, rl)
		State.WEIGHING:
			chain_out = maxf(chain_out - WEIGH_RATE * delta, 0.0)
			_rumble = 1.0
			var to_a := anchor_pos - rl
			var d := to_a.length()
			if d > chain_out:
				# Short-scoped: the anchor breaks out and comes up on the chain.
				planted = false
				anchor_pos = rl + to_a.normalized() * chain_out
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
	_anchor_vel.y += (-9.81 if not in_water else -6.5) * delta
	if in_water:
		_anchor_vel.y = maxf(_anchor_vel.y, -3.6)
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
	# Stowed, she still HANGS ON THE ROLLER — that is where an anchor lives on a
	# working boat, and hiding it was why you never saw the thing itself.
	if state == State.STOWED:
		# Catted on the roller: shank laid fore-and-aft along it, flukes out over
		# the stem. Hung straight down from the roller it ended up inside the
		# bow planking, which is worse than not drawing it at all.
		_anchor_mi.visible = true
		_anchor_mi.global_position = rl + boat.global_basis * Vector3(0.0, 0.02, -0.30)
		_anchor_mi.global_basis = boat.global_basis * Basis(Vector3.RIGHT, -PI * 0.5)
		# A short scope of cable showing on deck, from the roller back to the
		# windlass, the way it lies when she is stowed.
		var wl := boat.global_transform * Vector3(0.0, 0.90, -3.40)
		for i in _links.size():
			if i > 9:
				_links[i].visible = false
				continue
			var t0 := float(i) / 10.0
			var t1 := float(i + 1) / 10.0
			_place_link(_links[i], i, rl.lerp(wl, t0), rl.lerp(wl, t1))
		return
	_anchor_mi.visible = true

	_anchor_mi.global_position = anchor_pos
	var lie := (rl - anchor_pos)
	if planted:
		_anchor_mi.rotation = Vector3(0.0, atan2(lie.x, lie.z), 0.0)
	else:
		_anchor_mi.rotation = Vector3(0.25 * sin(anchor_pos.y * 1.3), atan2(lie.x, lie.z), 0.0)

	# Catenary: the slack we have out beyond the straight-line distance is what
	# hangs. Taut chain is a straight line; slack chain bellies down to the bed.
	var d := lie.length()
	var slack := maxf(chain_out - d, 0.0)
	# How much of the slack is lying on the bottom rather than hanging. Once she
	# is anchored most of it is: that is what a scope of chain is FOR, and it is
	# why the cable leaves the hook horizontally and only rises near the boat.
	var lay := 0.0
	if planted:
		lay = minf(slack * 0.85, Vector2(lie.x, lie.z).length() * 0.7)
	var sag := minf((slack - lay) * 0.40, d * 0.45 + 0.4)
	# The point where the cable leaves the ground.
	var flat := Vector2(lie.x, lie.z)
	var lift := anchor_pos
	if lay > 0.01 and flat.length() > 0.01:
		var fl := flat.normalized() * lay
		lift = anchor_pos + Vector3(fl.x, 0.0, fl.y)
		if ocean != null:
			lift.y = float(ocean.get_seafloor_height(lift)) + 0.06
	var ground_n := 0
	if lay > 0.01:
		ground_n = int(clampf(float(LINKS) * lay / maxf(chain_out, 0.1), 0.0, float(LINKS) - 4.0))
	for i in LINKS:
		var a: Vector3
		var b: Vector3
		if i < ground_n:
			# Along the bottom, following it.
			var g0 := float(i) / float(ground_n)
			var g1 := float(i + 1) / float(ground_n)
			a = anchor_pos.lerp(lift, g0)
			b = anchor_pos.lerp(lift, g1)
			if ocean != null:
				a.y = float(ocean.get_seafloor_height(a)) + 0.06
				b.y = float(ocean.get_seafloor_height(b)) + 0.06
		else:
			var n := float(LINKS - ground_n)
			var t0 := float(i - ground_n) / n
			var t1 := float(i - ground_n + 1) / n
			a = _catenary(lift, rl, t0, sag)
			b = _catenary(lift, rl, t1, sag)
		_place_link(_links[i], i, a, b)


func _place_link(mi: MeshInstance3D, i: int, a: Vector3, b: Vector3) -> void:
	## One link, laid between two points. Alternate ones are flattened the other
	## way, which is what makes a row of cylinders read as chain rather than as
	## a hose — real links interlock at right angles and catch the light in
	## alternating bands because of it.
	var seg := b - a
	var l := seg.length()
	mi.visible = true
	mi.global_position = (a + b) * 0.5
	if l <= 1e-5:
		return
	var up := seg / l
	var ref := Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var x := ref.cross(up).normalized()
	var z := x.cross(up)
	var fa := 1.85 if i % 2 == 0 else 0.55
	var fb := 0.55 if i % 2 == 0 else 1.85
	# Scale the COLUMNS, not the rows: Basis.scaled() works in the parent frame
	# and skews anything that is not standing straight up.
	mi.global_basis = Basis(x * fa, up * l, z * fb)


func _catenary(a: Vector3, b: Vector3, t: float, sag: float) -> Vector3:
	## Hangs the way a heavy chain hangs: steep where it leaves the boat, flat
	## where it meets the ground. A symmetric sine bulge — which is what this
	## was — puts the belly in the middle and makes the cable look like a
	## suspension cable rather than something with weight lying on a seabed.
	var p := a.lerp(b, t)
	var w := 1.0 - t
	p.y -= sag * (w * w * (3.0 - 2.0 * w)) * (0.35 + 0.65 * t)
	return p
