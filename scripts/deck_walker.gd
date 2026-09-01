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

## --- the boarding ladder over the transom ----------------------------------
## Slower than the companionway inside, deliberately. You are hauling a soaked
## body up wet iron with the stern coming at you; the whole point of the thing
## is that it is work, and that you can feel each rung.
const SEA_CLIMB := 0.62
const SEA_STEP_OFF := 5.22     # where you end up standing once you are over
const SEA_LEAN := 0.1045       # tan(6 deg): the stiles are raked, so is the climb
const SEA_STANDOFF := 0.36     # chest to rung — how far your body hangs off it

## --- in the water ----------------------------------------------------------
## A person in oilskins, not a fish. Everything here is slow.
const SWIM_SPEED := 1.30       # paddling, m/s
const SWIM_RISE := 1.05        # kicking for the surface
const SWIM_DIVE := 1.15        # driving yourself under against your own float
const SWIM_DRAG := 2.6         # the water takes your momentum back in ~0.4 s
const FLOAT_RISE := 0.60       # buoyancy at the surface, once you stop working
const NEUTRAL_DEPTH := 6.5     # where your chest stops floating you (see _swim)
const HEAD_OUT := 0.16         # where the eye settles above the wave, at rest
const SWIM_VMAX := 6.0

var pos := Vector3.ZERO        # local, at the feet
var vel := Vector3.ZERO
var on_floor := false
var on_ladder := false
var on_sea_ladder := false
var sea_ladder_mantle := 0.0
var swimming := false
## The eye is under the surface, and how deep. Read by the camera (it stops
## clamping the view above the waves) and by the hands.
var submerged := false
var swim_depth := 0.0
var _grab := false   # Space-held grip on the rungs
var _swim_pos := Vector3.ZERO   # WORLD position while overboard
var _swim_vel := Vector3.ZERO   # WORLD velocity while overboard
var can_board := false


func spawn_at(p: Vector3) -> void:
	pos = p
	vel = Vector3.ZERO
	on_floor = true
	swimming = false
	on_sea_ladder = false
	sea_ladder_mantle = 0.0
	submerged = false
	swim_depth = 0.0
	can_board = false
	_grab = false
	_swim_pos = Vector3.ZERO
	_swim_vel = Vector3.ZERO


func eye_local() -> Vector3:
	return pos + Vector3(0.0, EYE, 0.0)


func update(delta: float, boat: Node3D, wish: Vector2, want_jump: bool,
		look_w: Vector3 = Vector3.ZERO, axes: Vector2 = Vector2.ZERO,
		want_up: bool = false, want_down: bool = false) -> void:
	## `wish` is the desired heading in the boat's local xz, already rotated by
	## where the player is looking. Length <= 1.
	##
	## `look_w` and `axes` are for the water and the rungs, where the deck's flat
	## xz is not enough: in the sea forward means WHERE YOU ARE LOOKING in three
	## dimensions — look down, swim, and you go down — and on a ladder forward
	## means up. `axes` is the raw stick (x = strafe, y = ahead), unprojected.
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
	# Outside her BULWARKS — the line the blockers stop you at, not a box drawn
	# somewhere inside the deck. The old figures (1.34 and 4.24) were both well
	# inboard of the rail, so standing at the stern in any sea at all put you
	# over the side the first time a wave came aboard: the aft deck runs to
	# 5.52 and the side decks to 1.62, and you are allowed to stand on both.
	var outside := absf(pos.x) > 1.75 or pos.z < -4.15 or pos.z > 5.62
	var ocean: Node = boat.get("ocean")
	if on_sea_ladder:
		# Hanging off the transom you are outside every rail there is, so this
		# has to come before the overboard test or the ladder drops you in the
		# water on the frame you take hold of it.
		_climb_sea_ladder(delta, boat, xf, ocean, axes, want_jump)
		return
	# And ON NOTHING. Being pooped by a wave is not going overboard; you are
	# standing on her deck with the sea round your knees, which is a thing that
	# happens to fishermen every day of their lives. The only way into the water
	# is to be outside her AND have nothing under your feet.
	if not swimming and outside and not on_floor and ocean != null:
		var wp: Vector3 = xf * pos
		if wp.y < float(ocean.get_height(wp)) + 0.15:
			swimming = true
			# Hand the swimmer a WORLD position of its own. Keeping it in the
			# boat's frame is why you kept pace with her after going over the
			# side: the hull sailed away and dragged your coordinates with it.
			_swim_pos = wp
			# And keep the fall. Entering the water is a DIVE — the body carries
			# what it had on the way down, goes under, and comes back up. Zeroing
			# it here is what used to make going over the side read as stepping
			# into a bath.
			_swim_vel = xf.basis * vel
			if ocean.has_method("splash"):
				var entry_strength := clampf(absf(_swim_vel.y) * 0.24 + 0.45, 0.45, 2.2)
				ocean.splash(wp, entry_strength)
	if swimming:
		_swim(delta, boat, xf, ocean, axes, look_w, want_jump, want_up, want_down)
		return
	can_board = false
	submerged = false
	swim_depth = 0.0

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
		axes: Vector2, look_w: Vector3, want_jump: bool,
		want_up: bool, want_down: bool) -> void:
	## In the water. Simulated in WORLD space at the waves — the sea does not
	## ride along with the boat — and only written back into her frame at the
	## end so the camera stays one code path.
	##
	## Three things decide everything and there is nothing else in here:
	##
	##   * how much of you is UNDER. Half a body in the air still falls, cannot
	##     be paddled, and feels no buoyancy; that fraction is what turns a jump
	##     off the rail into a plunge instead of a landing.
	##   * where you are LOOKING, in three dimensions. Look down and swim and
	##     you go down. That is the whole of diving; there is no dive button.
	##   * buoyancy, which is not a force here but a place — the eye wants to sit
	##     a hand's breadth above the wave, and everything else is you working
	##     against that.
	var wpos: Vector3 = _swim_pos
	var wh: float = float(ocean.get_height(wpos)) if ocean != null else 0.0
	# How much of the body the sea has hold of: feet at wpos, head a body up.
	var frac: float = clampf((wh - wpos.y) / HEIGHT, 0.0, 1.0)
	# Depth of the EYE below the wave. Negative means your head is out.
	var sub: float = wh - (wpos.y + EYE)

	# --- what you are trying to do ------------------------------------------
	var fwd: Vector3 = look_w
	if fwd.length_squared() < 1e-6:
		fwd = -xf.basis.z
	fwd = fwd.normalized()
	var right: Vector3 = fwd.cross(Vector3.UP)
	right = right.normalized() if right.length_squared() > 1e-6 else xf.basis.x
	var drive: Vector3 = fwd * axes.y + right * axes.x
	if drive.length() > 1.0:
		drive = drive.normalized()
	if sub < 0.0:
		# Head out of the water: your arms are half in the air and you cannot
		# crawl UP out of the sea, however hard you look at the sky.
		drive.y = maxf(drive.y, 0.0)
	var wish_v: Vector3 = drive * SWIM_SPEED
	if want_up:
		wish_v.y += SWIM_RISE
	if want_down:
		wish_v.y -= SWIM_DIVE
	# Buoyancy as a target, not a push: above the settle line it pulls you down,
	# below it lifts you, and it dies at the line so you neither sink nor pop.
	#
	# And it is not the same at every depth. Your chest is the float and the
	# water squeezes it: a body is buoyant at the surface, neutral somewhere
	# around six metres and negative below that. That is a real thing — it is
	# why free divers can get down at all — and it is exactly the right feel:
	# the first two metres are the work, and after that the sea takes you.
	var squeeze: float = clampf(1.0 - maxf(sub, 0.0) / NEUTRAL_DEPTH, -0.35, 1.0)
	wish_v.y += FLOAT_RISE * squeeze * clampf((sub - HEAD_OUT) / 0.9, -1.0, 1.0)

	# --- what the water does about it ---------------------------------------
	# Authority scales with how much of you it holds. Out of it you are a
	# falling body and nothing you do matters.
	var k: float = 1.0 - exp(-SWIM_DRAG * maxf(frac, 0.05) * delta)
	_swim_vel = _swim_vel.lerp(wish_v * frac, k)
	_swim_vel.y -= 9.81 * delta * (1.0 - frac)
	if _swim_vel.length() > SWIM_VMAX:
		_swim_vel = _swim_vel.normalized() * SWIM_VMAX
	wpos += _swim_vel * delta

	if ocean != null:
		# Carried: the drift the whole sea has, plus a share of the orbital
		# motion of the wave you are actually in. That surge is why floating is
		# not the same as standing still.
		if ocean.has_method("current_at"):
			var c: Vector2 = ocean.current_at(wpos)
			wpos += Vector3(c.x, 0.0, c.y) * delta
		if ocean.has_method("surface_velocity"):
			var orb: Vector3 = ocean.surface_velocity(wpos)
			wpos += Vector3(orb.x, 0.0, orb.z) * delta * 0.45 * frac
		if ocean.has_method("inject_local_water") and drive.length_squared() > 0.04 \
				and frac > 0.18:
			var kick_phase := sin(float(Time.get_ticks_msec()) * 0.001 * TAU * 1.35)
			ocean.inject_local_water(wpos + fwd * 0.28, 0.30,
					kick_phase * drive.length() * minf(delta, 1.0 / 30.0) * 0.32)
		if ocean.has_method("get_seafloor_height"):
			wpos.y = maxf(wpos.y, float(ocean.get_seafloor_height(wpos)) + 0.05)

	wpos = _keep_out_of_hull(xf, wpos)
	_swim_pos = wpos
	pos = xf.affine_inverse() * wpos
	vel = Vector3.ZERO
	on_floor = false
	on_ladder = false
	swim_depth = maxf(wh - (wpos.y + EYE), 0.0)
	submerged = swim_depth > 0.0

	# The way back aboard is the ladder and only the ladder — swim to the stern
	# and take hold of it. Hauling yourself straight over a 1.5 m bulwark from
	# the sea was a teleport wearing a prompt.
	var lad: Vector3 = _sea_stand(boat, clampf(pos.y, float(boat.SEA_LADDER_BOT), 0.0))
	# Feet remain well below the hand that reaches the new lowest rung.
	can_board = Vector2(pos.x - lad.x, pos.z - lad.z).length() < 1.5 \
			and pos.y > float(boat.SEA_LADDER_BOT) - 1.25
	if can_board and want_jump:
		grab_sea_ladder(boat)


func _keep_out_of_hull(xf: Transform3D, wpos: Vector3) -> Vector3:
	## The sea is outside her. Swimming up under the keel used to put the
	## eye in the cabin; the hull is a closed volume now.
	var inv := xf.affine_inverse()
	var feet: Vector3 = inv * wpos
	var push := Vector3.ZERO
	var worst := 0.0
	for h in [0.10, 0.55, 1.05, EYE]:
		var p: Vector3 = feet + Vector3(0.0, h, 0.0)
		var q := _hull_escape(p)
		var d: Vector3 = q - p
		var pen := d.length()
		if pen > worst:
			worst = pen
			push = d
	if worst < 1e-4:
		return wpos
	var out: Vector3 = feet + push
	var wn: Vector3 = xf.basis * push
	if wn.length_squared() > 1e-6:
		wn = wn.normalized()
		var into := _swim_vel.dot(wn)
		if into < 0.0:
			_swim_vel -= wn * into
	return xf * out


func _hull_half_beam(z: float) -> float:
	if z < -3.40:
		var t := clampf((-3.40 - z) / 1.55, 0.0, 1.0)
		return lerpf(1.82, 0.16, t * t)
	if z > 4.80:
		var t2 := clampf((z - 4.80) / 0.95, 0.0, 1.0)
		return lerpf(1.92, 1.52, t2)
	return 1.86


func _hull_keel(z: float) -> float:
	if z < -3.60:
		return lerpf(-0.70, -0.22, clampf((-3.60 - z) / 1.40, 0.0, 1.0))
	return -0.70


func _hull_escape(p: Vector3) -> Vector3:
	## The ladder pocket begins behind the physical transom. Do not punch a
	## swimmer-sized tunnel through the hull merely to make the rungs reachable.
	if absf(p.x - 0.72) < 0.58 and p.z > 5.62 and p.y < 0.85:
		return p
	if p.z < -4.92 or p.z > 5.62:
		return p
	var hb := _hull_half_beam(p.z)
	if absf(p.x) > hb + 0.04:
		return p
	var y1 := 3.40 if (p.z > -0.60 and p.z < 4.75) else 1.18
	if p.y >= y1:
		return p
	# Below the keel is still blocked for the swimming controller. Otherwise a
	# downward-looking camera can cross beneath the centreline and then surface
	# inside the boat. Treat the underwater hull footprint as one solid obstacle
	# and resolve toward a side, bow or transom instead of resolving downward.
	var sx := 1.0 if p.x >= 0.0 else -1.0
	var d_side := hb + 0.10 - absf(p.x)
	var d_fore := p.z + 4.92
	var d_aft := 5.62 - p.z
	var out := p
	out.x = sx * (hb + 0.12)
	var best := d_side
	if d_fore < best:
		best = d_fore
		out = p
		out.z = -5.02
	if d_aft < best:
		out = p
		out.z = 5.74
	return out


# --- the boarding ladder ------------------------------------------------------

func sea_ladder_reach(boat: Node3D) -> bool:
	## Close enough to take hold of it, from the deck or from the water. From
	## aboard she is a step over the cap; from the sea you have to be at her.
	if boat == null or on_sea_ladder:
		return false
	var lad: Vector3 = _sea_stand(boat, clampf(pos.y, float(boat.SEA_LADDER_BOT),
			float(boat.SEA_LADDER_TOP)))
	var d: float = Vector2(pos.x - lad.x, pos.z - lad.z).length()
	return d < (1.5 if swimming else 1.9)


func grab_sea_ladder(boat: Node3D) -> bool:
	## Take hold. Everything about the state is decided in this one place so the
	## per-tick climb stays four lines.
	if boat == null:
		return false
	var top: float = float(boat.SEA_LADDER_TOP)
	var bot: float = float(boat.SEA_LADDER_BOT)
	# Out of the water you meet it at the rung under your feet; coming up out of
	# the sea you meet it at the lowest one you can reach, because a swimmer is
	# low in it and the top of the ladder is a metre over their head.
	var y: float = clampf(pos.y, bot, -0.05 if swimming else top)
	on_sea_ladder = true
	sea_ladder_mantle = 0.0
	swimming = false
	can_board = false
	_grab = false
	vel = Vector3.ZERO
	_swim_vel = Vector3.ZERO
	pos = _sea_stand(boat, y)
	return true


func _sea_stand(boat: Node3D, y: float) -> Vector3:
	## Where the BODY is for a given rung. The stiles are raked six degrees, so
	## the climbing line leans aft with them — hold it vertical and your chest
	## goes through the transom at the top while your feet swing off the bottom.
	var z: float = float(boat.SEA_LADDER_Z) + y * SEA_LEAN
	return Vector3(float(boat.SEA_LADDER_X), y, z + SEA_STANDOFF)


func _climb_sea_ladder(delta: float, boat: Node3D, xf: Transform3D, ocean: Node,
		axes: Vector2, want_jump: bool) -> void:
	var top: float = float(boat.SEA_LADDER_TOP)
	var bot: float = float(boat.SEA_LADDER_BOT)
	if sea_ladder_mantle > 0.0:
		_advance_sea_ladder_mantle(delta, boat, top)
		return
	var y: float = pos.y + axes.y * SEA_CLIMB * delta
	if y > top:
		# Do not teleport across the transom. Plant the hands, lift the body over
		# the cap, then set the feet down on deck over a short authored arc.
		sea_ladder_mantle = 0.001
		_advance_sea_ladder_mantle(delta, boat, top)
		return
	if want_jump:
		# Let go deliberately. Reaching the short ladder's bottom is not itself a
		# release: a held down key used to cross the boundary by one frame and turn
		# a planted grip into an unexplained fall whenever the boat was moving.
		on_sea_ladder = false
		swimming = true
		_swim_pos = xf * pos
		_swim_vel = Vector3(0.0, -1.2, 0.0)
		return
	if y < bot:
		y = bot
	pos = _sea_stand(boat, y)
	vel = Vector3(0.0, axes.y * SEA_CLIMB if y > bot + 0.001 else 0.0, 0.0)
	on_floor = false
	on_ladder = false
	# The bottom rungs are under water and she is moving under you, so the eye
	# can go below the surface while you are still holding on. It has to know.
	if ocean != null:
		var eye_w: Vector3 = xf * (pos + Vector3(0.0, EYE, 0.0))
		swim_depth = maxf(float(ocean.get_height(eye_w)) - eye_w.y, 0.0)
		submerged = swim_depth > 0.0


func _advance_sea_ladder_mantle(delta: float, boat: Node3D, top: float) -> void:
	const MANTLE_TIME := 0.82
	sea_ladder_mantle = minf(sea_ladder_mantle + delta / MANTLE_TIME, 1.0)
	var u := smoothstep(0.0, 1.0, sea_ladder_mantle)
	var start := _sea_stand(boat, top)
	var finish := Vector3(float(boat.SEA_LADDER_X), 0.63, SEA_STEP_OFF)
	pos = start.lerp(finish, u)
	# Rise before travelling inboard so the chest and camera clear the cap.
	pos.y += sin(u * PI) * 0.48
	vel = Vector3.ZERO
	on_floor = false
	on_ladder = false
	submerged = false
	swim_depth = 0.0
	if sea_ladder_mantle >= 1.0:
		sea_ladder_mantle = 0.0
		on_sea_ladder = false
		pos = finish
		on_floor = true
