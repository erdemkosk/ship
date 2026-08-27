extends RefCounted
## First-person crew member, simulated in the BOAT'S LOCAL FRAME.
##
## This is the whole trick. A CharacterBody3D walking on a rigid body that is
## itself heaving five metres and rolling twenty degrees fights the physics
## engine and loses: it skates, it sinks through the deck, it gets left behind
## when the boat accelerates. Instead the walker keeps its position in the
## boat's coordinates and never moves in world space at all — the boat carries
## it, exactly the way a deck carries you.
##
## Gravity is the one thing that must stay in world space, so it is rotated into
## the local frame each tick. That single line is why you slide toward the lee
## rail when she heels, and why standing on the foredeck in a beam sea is work.
##
## Collision is deliberately not the physics engine either: the ship's walkable
## volume is a short list of axis-aligned rectangles published by boat.gd, and
## resolving a cylinder against those is a dozen lines and never tunnels.

const RADIUS := 0.30
const HEIGHT := 1.74
const EYE := 1.60
const STEP_UP := 0.42          # ledge you can walk over without jumping
const WALK_SPEED := 3.0
const ACCEL := 13.0
const GROUND_DRAG := 9.0
const AIR_DRAG := 0.4
const JUMP_SPEED := 3.5
const CLIMB_SPEED := 2.1
const SNAP_DOWN := 0.55        # how far below the feet a floor still catches you

var pos := Vector3.ZERO        # local, at the feet
var vel := Vector3.ZERO
var on_floor := false
var on_ladder := false
var swimming := false
var _grab := false   # Space-held grip on the rungs
var _swim_pos := Vector3.ZERO   # WORLD position while overboard
var can_board := false


func spawn_at(p: Vector3) -> void:
	pos = p
	vel = Vector3.ZERO
	on_floor = true
	swimming = false
	can_board = false
	_grab = false
	_swim_pos = Vector3.ZERO


func eye_local() -> Vector3:
	return pos + Vector3(0.0, EYE, 0.0)


func update(delta: float, boat: Node3D, wish: Vector2, want_jump: bool) -> void:
	## `wish` is the desired heading in the boat's local xz, already rotated by
	## where the player is looking. Length <= 1.
	if boat == null:
		return
	var floors: Array = boat.FLOORS
	var ceils: Array = boat.CEILINGS
	# The static list plus whatever is currently in the way and moves — right
	# now that is the two cabin doors, which only block while they are shut.
	var blockers: Array = boat.BLOCKERS + boat.door_blockers
	var ladder: AABB = boat.LADDER

	# World-down, expressed in the boat's frame. Everything else follows.
	var g: Vector3 = boat.global_basis.inverse() * (Vector3.DOWN * 9.81)

	# --- overboard -----------------------------------------------------------
	# Off the deck and down to the water there is no floor, and without this
	# the walker just kept falling in the boat's frame while the roll flipped
	# the slope-pull back and forth under it — the jittering the sea showed.
	# In the water you SWIM: held at the surface, carried by the current.
	var xf: Transform3D = boat.global_transform
	# Overboard means OVER THE SIDE — outside her rails, not merely lower than
	# you were. The old test also fired on `pos.y < 0.15`, so a stumble that
	# dropped you a metre inside the hull put you in the water with the deck
	# still over your head.
	var outside := absf(pos.x) > 1.34 or pos.z < -4.02 or pos.z > 4.24
	var ocean: Node = boat.get("ocean")
	if not swimming and outside and ocean != null:
		var wp: Vector3 = xf * pos
		if wp.y < float(ocean.get_height(wp)) + 0.15:
			swimming = true
			# Hand the swimmer a WORLD position of its own. Keeping it in the
			# boat's frame is why you kept pace with her after going over the
			# side: the hull sailed away and dragged your coordinates with it.
			_swim_pos = wp
	if swimming:
		_swim(delta, boat, xf, ocean, wish, want_jump)
		return
	can_board = false

	# --- ladder --------------------------------------------------------------
	# The rungs hold you only while you are actually hanging on them. Standing
	# at the foot of the ladder you are simply standing on the deck, free to
	# walk forward through the cabin door — the old code welded you to the
	# ladder the moment you entered its volume and clamped your position, which
	# is what made the lower deck unreachable.
	# The ladder takes over ONLY BETWEEN DECKS. Standing on either landing you
	# are simply standing — free to walk to the cabin door, or across the roof.
	# And stepping off the roof edge into it catches you and turns the fall into
	# a climb, instead of pitching you over the side.
	var band: Vector2 = boat.LADDER_BAND
	var in_ladder: bool = ladder.has_point(pos + Vector3(0.0, 0.9, 0.0))
	if in_ladder and want_jump and on_floor and pos.y < band.x:
		_grab = true                      # Space to start up from the deck
	if not in_ladder or pos.y > band.x:
		_grab = false
	on_ladder = in_ladder and (pos.y > band.x or _grab) and pos.y < band.y
	if on_ladder:
		# Hands on the rails: stay on the climbing line, not drifting off it.
		pos.x = clampf(pos.x, ladder.position.x + 0.10, ladder.end.x - 0.10)
		pos.z = clampf(pos.z, ladder.position.z + 0.08, ladder.position.z + 0.34)
	if on_ladder:
		vel = Vector3(wish.x * 0.8, wish.y * -CLIMB_SPEED, wish.y * 0.0)
		# On a ladder "forward" means up; sideways still shuffles you along it.
		vel.y = -wish.y * CLIMB_SPEED
		vel.x = wish.x * 0.9
		vel.z = 0.0
		if want_jump:
			vel.y = JUMP_SPEED
	else:
		vel += g * delta
		var hv := Vector3(vel.x, 0.0, vel.z)
		if on_floor:
			var target := Vector3(wish.x, 0.0, wish.y) * WALK_SPEED
			hv = hv.lerp(target, 1.0 - exp(-ACCEL * delta))
			# Down-slope pull, so a heeling deck is something you fight.
			hv += Vector3(g.x, 0.0, g.z) * delta * 0.65
			hv *= exp(-GROUND_DRAG * delta * (0.12 if wish.length_squared() > 0.01 else 1.0))
			if want_jump:
				vel.y = JUMP_SPEED
				on_floor = false
		else:
			hv += Vector3(wish.x, 0.0, wish.y) * ACCEL * 0.22 * delta
			hv *= exp(-AIR_DRAG * delta)
		if hv.length() > WALK_SPEED * 1.9:
			hv = hv.normalized() * WALK_SPEED * 1.9
		vel.x = hv.x
		vel.z = hv.z

	pos += vel * delta
	_resolve_walls(blockers)
	_resolve_ceilings(ceils)
	_resolve_floor(floors)


func _resolve_floor(floors: Array) -> void:
	var best := -1.0e9
	for f in floors:
		var r: Rect2 = f[0]
		var y: float = f[1]
		if not r.has_point(Vector2(pos.x, pos.z)):
			continue
		# A floor catches you if it is under your feet, or no more than a step up.
		if y <= pos.y + STEP_UP and y > best:
			best = y
	on_floor = false
	if best < -1.0e8:
		return
	if pos.y <= best + 0.02 or (vel.y <= 0.0 and pos.y <= best + SNAP_DOWN):
		pos.y = best
		if vel.y < 0.0:
			vel.y = 0.0
		on_floor = true


func _resolve_ceilings(ceils: Array) -> void:
	for c in ceils:
		var r: Rect2 = c[0]
		var y: float = c[1]
		if not r.has_point(Vector2(pos.x, pos.z)):
			continue
		# Only a ceiling to someone underneath it. Without this test the cabin
		# deckhead shoves you off the roof you are standing on.
		if pos.y >= y - 0.05:
			continue
		if pos.y + HEIGHT > y:
			pos.y = y - HEIGHT
			if vel.y > 0.0:
				vel.y = 0.0


func _resolve_walls(blockers: Array) -> void:
	## Cylinder vs. AABB, pushed out along whichever horizontal axis it is least
	## deep into. Two passes, because sliding out of one corner can push you
	## into the next.
	for _pass in 2:
		for b: AABB in blockers:
			var bmin := b.position
			var bmax := b.position + b.size
			# Vertical overlap first: a knee-high bulwark should not stop you
			# when you are standing on the roof above it.
			if pos.y + HEIGHT <= bmin.y + 0.02 or pos.y >= bmax.y - 0.02:
				continue
			var cx := clampf(pos.x, bmin.x, bmax.x)
			var cz := clampf(pos.z, bmin.z, bmax.z)
			var dx := pos.x - cx
			var dz := pos.z - cz
			var d2 := dx * dx + dz * dz
			if d2 > RADIUS * RADIUS:
				continue
			if d2 > 1e-6:
				var d := sqrt(d2)
				var push := RADIUS - d
				pos.x += dx / d * push
				pos.z += dz / d * push
			else:
				# Dead centre: pick the shallowest way out.
				var out_x: float = (bmin.x - RADIUS - pos.x) if (pos.x - bmin.x < bmax.x - pos.x) \
						else (bmax.x + RADIUS - pos.x)
				var out_z: float = (bmin.z - RADIUS - pos.z) if (pos.z - bmin.z < bmax.z - pos.z) \
						else (bmax.z + RADIUS - pos.z)
				if absf(out_x) < absf(out_z):
					pos.x += out_x
				else:
					pos.z += out_z


func _swim(delta: float, boat: Node3D, xf: Transform3D, ocean: Node,
		wish: Vector2, want_jump: bool) -> void:
	## In the water. Simulated at the wave surface in WORLD space (the sea does
	## not ride along with the boat), then written back into the boat's frame so
	## the camera pipeline stays one code path.
	var wpos: Vector3 = _swim_pos
	if ocean != null:
		var wh: float = ocean.get_height(wpos)
		# Chest-deep, bobbing with the swell.
		wpos.y = lerpf(wpos.y, wh - 0.35, 1.0 - exp(-6.0 * delta))
		if ocean.has_method("current_at"):
			var c: Vector2 = ocean.current_at(wpos)
			wpos += Vector3(c.x, 0.0, c.y) * delta
	# Paddle where you look — slowly. You are a person in oilskins, not a fish.
	var dir_w: Vector3 = xf.basis * Vector3(wish.x, 0.0, wish.y)
	dir_w.y = 0.0
	if dir_w.length_squared() > 1e-4:
		wpos += dir_w.normalized() * 1.3 * delta * minf(wish.length(), 1.0)
	# The sea does not ride along with the boat, so the swimmer is integrated in
	# world space and only converted into her frame for the camera.
	_swim_pos = wpos
	pos = xf.affine_inverse() * wpos
	vel = Vector3.ZERO
	on_floor = false
	on_ladder = false
	# Against the hull you can get a hand on the rail and haul yourself over.
	can_board = absf(pos.x) < 1.85 and absf(pos.z) < 4.45
	if can_board and want_jump:
		swimming = false
		pos = Vector3(clampf(pos.x, -1.1, 1.1), 0.63, clampf(pos.z, -3.7, 3.85))
		vel = Vector3.ZERO
		on_floor = true
