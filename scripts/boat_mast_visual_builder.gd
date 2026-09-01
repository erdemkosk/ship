class_name BoatMastVisualBuilder
extends RefCounted
## Builds mast, rigging, navigation lanterns and deckhouse safety rails.


func build(owner: Node3D, trim: Material, metal: Material,
		box_callback: Callable, cyl_callback: Callable, mat_callback: Callable,
		stay_callback: Callable, rope_callback: Callable,
		lantern_callback: Callable, deck_gear_callback: Callable) -> Dictionary:
	var beacon_material: StandardMaterial3D
	var beacon: OmniLight3D
	# --- mast, funnel, rails ------------------------------------------------
	# Mast and its yard. There was a boom too — a 2.4 m spar lying fore-and-aft
	# at chest height under the mast, running from z -2.45 aft to -0.05, which
	# put its inboard end THROUGH the cabin's forward bulkhead and into the
	# room. Nothing was rigged to it and it was in the way of the one clear walk
	# up the foredeck, so it is gone.
	var mast := Node3D.new()
	mast.name = "MastVisuals"
	mast.position = Vector3(0.0, 3.10, -2.35)
	mast.rotation_degrees = Vector3(0.0, 0.0, 3.0)
	owner.add_child(mast)
	cyl_callback.call(0.11, 0.075, 5.20, Vector3.ZERO, Vector3.ZERO, trim, mast)
	box_callback.call(Vector3(1.70, 0.07, 0.07), Vector3(0.0, 1.45, 0.0), Vector3.ZERO, trim, mast)
	# Red masthead warning beacon, on the stick's own axis.
	beacon_material = StandardMaterial3D.new()
	beacon_material.albedo_color = Color(0.42, 0.025, 0.018)
	beacon_material.emission_enabled = true
	beacon_material.emission = Color(1.0, 0.025, 0.012)
	beacon_material.emission_energy_multiplier = 0.0
	var truck := 2.60
	cyl_callback.call(0.10, 0.10, 0.12, Vector3(0.0, truck + 0.06, 0.0), Vector3.ZERO, metal, mast)
	cyl_callback.call(0.085, 0.085, 0.20, Vector3(0.0, truck + 0.22, 0.0), Vector3.ZERO, beacon_material, mast)
	cyl_callback.call(0.11, 0.02, 0.10, Vector3(0.0, truck + 0.37, 0.0), Vector3.ZERO, metal, mast)
	beacon = OmniLight3D.new()
	beacon.position = Vector3(0.0, truck + 0.22, 0.0)
	beacon.light_color = Color(1.0, 0.035, 0.018)
	beacon.light_energy = 0.0
	beacon.omni_range = 32.0
	beacon.omni_attenuation = 1.3
	beacon.shadow_enabled = false
	mast.add_child(beacon)
	# Standing rigging. Four wires: a forestay to the stem, a shroud each side
	# to the cap, and a halliard off the yard. Without them the mast is a pole
	# planted in the deck.
	var wire := mat_callback.call(
			Color(0.22, 0.22, 0.24), 0.42, 0.72) as Material
	var halliard := mat_callback.call(
			Color(0.38, 0.30, 0.18), 0.88) as Material
	var mast_head := _mast_point(Vector3(0.0, 2.48, 0.0))
	var shroud_head := _mast_point(Vector3(0.0, 2.18, 0.0))
	stay_callback.call(shroud_head, Vector3(-1.94, 1.14, -2.18), 0.009, wire)
	stay_callback.call(shroud_head, Vector3(1.94, 1.14, -2.18), 0.009, wire)
	# Chainplates where the shrouds land, and a tang on the stem-head.
	box_callback.call(Vector3(0.04, 0.16, 0.10), Vector3(-1.96, 1.10, -2.18), Vector3(0.0, 0.0, 5.0), metal)
	box_callback.call(Vector3(0.04, 0.16, 0.10), Vector3(1.96, 1.10, -2.18), Vector3(0.0, 0.0, -5.0), metal)
	box_callback.call(Vector3(0.05, 0.08, 0.08), Vector3(0.0, 1.16, -4.96), Vector3.ZERO, metal)
	# Forestay is rope, not a rod. The shrouds stay bar-taut; this run is long
	# enough to take a catenary or it reads as a steel tube planted in the stem.
	rope_callback.call(mast_head, Vector3(0.0, 1.18, -4.96), 0.011, 0.14, halliard)
	# Halliard belays on a pin on the mast, not in mid-air.
	box_callback.call(Vector3(0.04, 0.03, 0.09), Vector3(0.12, -1.52, 0.0), Vector3.ZERO, metal, mast)
	stay_callback.call(_mast_point(Vector3(0.82, 1.45, 0.0)), _mast_point(Vector3(0.12, -1.48, 0.0)),
			0.007, halliard)
	# Sidelights on the house, sternlight ON the transom cap — y 1.52 / z 5.84
	# was a lantern hanging in the air behind the name.
	lantern_callback.call(Vector3(-1.88, 2.12, 0.22), 90.0, Color(0.95, 0.08, 0.06))
	lantern_callback.call(Vector3(1.88, 2.12, 0.22), -90.0, Color(0.06, 0.85, 0.18))
	lantern_callback.call(Vector3(0.0, 1.24, 5.66), 180.0, Color(0.95, 0.94, 0.88))
	# No funnel. The cabin heater is electric now — it burns nothing, so there
	# is nothing to take up a flue, and a stack that vents an appliance with no
	# fire in it is a lie standing on the roof. The balcony is clear.
	# Foredeck rail: stanchions plus a top rail, both parallel to the wooden
	# bulwark they stand inside. The posts used to splay from 1.69 to 1.94 and
	# the cap followed them at 4.3 degrees — a top plank that ran away from
	# the one below it.
	const FORE_RAIL_X := 1.88
	for i in 7:
		var t := float(i) / 6.0
		var rz := lerpf(-3.85, -0.55, t)
		cyl_callback.call(0.035, 0.035, 0.62, Vector3(-FORE_RAIL_X, 1.42, rz), Vector3.ZERO, metal)
		cyl_callback.call(0.035, 0.035, 0.62, Vector3(FORE_RAIL_X, 1.42, rz), Vector3.ZERO, metal)
	box_callback.call(Vector3(0.05, 0.05, 3.32), Vector3(-FORE_RAIL_X, 1.72, -2.20), Vector3.ZERO, metal)
	box_callback.call(Vector3(0.05, 0.05, 3.32), Vector3(FORE_RAIL_X, 1.72, -2.20), Vector3.ZERO, metal)
	# Rail round the deckhouse roof, so standing up there is not a sheer drop.
	# The roof plating runs to z 5.10; the old side pipes died at 4.55 and the
	# aft pipe sat at 5.06 with a half-metre of nothing between them — that is
	# the broken ring as seen from astern. One closed rectangle now.
	box_callback.call(Vector3(0.05, 0.05, 5.36), Vector3(-1.80, 3.29, 2.38), Vector3.ZERO, metal)
	box_callback.call(Vector3(0.05, 0.05, 5.36), Vector3(1.80, 3.29, 2.38), Vector3.ZERO, metal)
	for i in 8:
		var sz := lerpf(-0.30, 5.06, float(i) / 7.0)
		cyl_callback.call(0.03, 0.03, 0.56, Vector3(-1.80, 3.11, sz), Vector3.ZERO, metal)
		cyl_callback.call(0.03, 0.03, 0.56, Vector3(1.80, 3.11, sz), Vector3.ZERO, metal)
	box_callback.call(Vector3(3.65, 0.05, 0.05), Vector3(0.0, 3.29, 5.06), Vector3.ZERO, metal)
	for i in 5:
		cyl_callback.call(0.03, 0.03, 0.56, Vector3(-1.80 + float(i) * 0.90, 3.11, 5.06),
				Vector3.ZERO, metal)
	box_callback.call(Vector3(3.65, 0.05, 0.05), Vector3(0.0, 3.29, -0.30), Vector3.ZERO, metal)

	deck_gear_callback.call(trim, metal)

	return {"beacon_material": beacon_material, "beacon": beacon}


func _mast_point(local: Vector3) -> Vector3:
	var angle := deg_to_rad(3.0)
	var cosine := cos(angle)
	var sine := sin(angle)
	return Vector3(0.0, 3.10, -2.35) + Vector3(
			local.x * cosine - local.y * sine,
			local.x * sine + local.y * cosine, local.z)
