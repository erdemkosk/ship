class_name BoatCabinVisualBuilder
extends RefCounted
## Builds the lower deckhouse, cabin fit-out, stove and weathertight doors.


func build(owner: Node3D, deck: Material, paint: Material,
		paint_dark: Material, trim: Material, metal: Material, dark: Material,
		cabin_latch: Vector3,
		box_callback: Callable, cyl_callback: Callable, mat_callback: Callable,
		glass_callback: Callable, hatch_callback: Callable,
		leaf_callback: Callable, dive_locker_callback: Callable,
		stove_effects_callback: Callable, lived_in_callback: Callable) -> Dictionary:
	var glass_material: ShaderMaterial
	var lit_window: StandardMaterial3D
	var cabin_lamp: OmniLight3D
	var stove_reflector: StandardMaterial3D
	var stove_ember: StandardMaterial3D
	var stove_switch: Node3D
	var stove_lamp: OmniLight3D
	var stove_fill: OmniLight3D
	var door_forward: Node3D
	var door_aft: Node3D
	# --- deckhouse (lower level) --------------------------------------------
	# Built as walls, not as a solid block. You can go inside her, so every
	# surface has to exist from both faces.
	glass_material = ShaderMaterial.new()
	glass_material.shader = load("res://shaders/glass.gdshader")
	# Among transparent surfaces Godot sorts by instance origin, and the panes
	# share an origin neighbourhood with the ocean rings. Force the glass to
	# draw last so the sea is always on screen before the pane blends over it.
	glass_material.render_priority = 12

	const cabin_z0 := -0.45   # forward bulkhead
	const cabin_z1 := 4.65    # aft bulkhead
	const cabin_x := 1.80     # half beam of the house
	const cabin_y0 := 0.63    # cabin sole
	const cabin_y1 := 2.75    # cabin deckhead / roof underside (2.05 m headroom)
	var cy := (cabin_y0 + cabin_y1) * 0.5
	var ch := cabin_y1 - cabin_y0
	var cz := (cabin_z0 + cabin_z1) * 0.5
	var cl := cabin_z1 - cabin_z0

	box_callback.call(Vector3(cabin_x * 2.0, 0.09, cl), Vector3(0.0, cabin_y0, cz), Vector3.ZERO, deck)  # sole
	box_callback.call(Vector3(0.08, ch, cl), Vector3(-cabin_x, cy, cz), Vector3.ZERO, paint)
	box_callback.call(Vector3(0.08, ch, cl), Vector3(cabin_x, cy, cz), Vector3.ZERO, paint)
	# Aft bulkhead, also with a doorway: foredeck -> cabin -> aft deck -> ladder
	# -> roof -> wheelhouse is a loop you can actually walk.
	box_callback.call(Vector3(1.25, ch, 0.08), Vector3(-1.175, cy, cabin_z1), Vector3.ZERO, paint)
	box_callback.call(Vector3(1.25, ch, 0.08), Vector3(1.175, cy, cabin_z1), Vector3.ZERO, paint)
	# Header lands on both jambs, not on the hole: 1.10 left a hairline at
	# each stile. 0.20 deep so a 1.74 m man still walks under it.
	box_callback.call(Vector3(1.20, 0.20, 0.08), Vector3(0.0, cabin_y1 - 0.10, cabin_z1), Vector3.ZERO, paint)
	box_callback.call(Vector3(1.20, 0.06, 0.10), Vector3(0.0, cabin_y0 + 0.03, cabin_z1), Vector3.ZERO, trim)
	# Forward bulkhead with a doorway cut out of it (two jambs + a header).
	box_callback.call(Vector3(1.25, ch, 0.08), Vector3(-1.175, cy, cabin_z0), Vector3.ZERO, paint)
	box_callback.call(Vector3(1.25, ch, 0.08), Vector3(1.175, cy, cabin_z0), Vector3.ZERO, paint)
	box_callback.call(Vector3(1.20, 0.20, 0.08), Vector3(0.0, cabin_y1 - 0.10, cabin_z0), Vector3.ZERO, paint)
	box_callback.call(Vector3(1.20, 0.06, 0.10), Vector3(0.0, cabin_y0 + 0.03, cabin_z0), Vector3.ZERO, trim)
	# Roof of the deckhouse — the walkable upper deck.
	# Roof / upper deck, laid in four pieces so the companionway has an opening
	# to come up through on the port side aft. Hatch mouth 1.18 m, not 1.30.
	box_callback.call(Vector3(0.16, 0.16, 5.62), Vector3(-1.75, cabin_y1 + 0.08, 2.29), Vector3.ZERO, paint_dark)
	box_callback.call(Vector3(2.32, 0.16, 5.62), Vector3(0.67, cabin_y1 + 0.08, 2.29), Vector3.ZERO, paint_dark)
	box_callback.call(Vector3(1.18, 0.16, 1.47), Vector3(-1.08, cabin_y1 + 0.08, 0.215), Vector3.ZERO, paint_dark)
	box_callback.call(Vector3(1.18, 0.16, 1.15), Vector3(-1.08, cabin_y1 + 0.08, 4.525), Vector3.ZERO, paint_dark)

	# Side windows: three a side, glazed.
	for i in 3:
		var z := cabin_z0 + 0.85 + float(i) * 1.05
		for sx in [-1.0, 1.0]:
			box_callback.call(Vector3(0.11, 0.58, 0.74), Vector3(sx * cabin_x, 1.72, z), Vector3.ZERO, trim)
			glass_callback.call(Vector3(0.05, 0.46, 0.62), Vector3(sx * (cabin_x + 0.01), 1.72, z), glass_material)
	# Cabin lamp: on the deckhead, centred on the middle pair of side windows
	# (z = 1.45). A box floating 20 cm below the sole-head looked like it had
	# been put down crooked rather than hung.
	var cabin_lamp_z := cabin_z0 + 0.85 + 1.05
	lit_window = mat_callback.call(Color(0.30, 0.20, 0.10), 0.55)
	lit_window.emission_enabled = true
	lit_window.emission = Color(1.0, 0.66, 0.30)
	lit_window.emission_energy_multiplier = 2.2
	cyl_callback.call(0.025, 0.025, 0.08, Vector3(0.0, cabin_y1 - 0.04, cabin_lamp_z), Vector3.ZERO, metal)
	box_callback.call(Vector3(0.18, 0.12, 0.18), Vector3(0.0, cabin_y1 - 0.14, cabin_lamp_z), Vector3.ZERO, lit_window)
	cabin_lamp = OmniLight3D.new()
	cabin_lamp.position = Vector3(0.0, cabin_y1 - 0.24, cabin_lamp_z)
	cabin_lamp.light_color = Color(1.0, 0.62, 0.30)
	cabin_lamp.light_energy = 1.6
	cabin_lamp.omni_range = 4.2
	cabin_lamp.omni_attenuation = 1.6
	cabin_lamp.shadow_enabled = false
	owner.add_child(cabin_lamp)

	# --- cabin fit-out ------------------------------------------------------
	# A home, not a hold. Bunk made up along the port side, table and stool to
	# starboard, a shelf of books over them, a cupboard by the forward door, the
	# stove in the aft corner with its pipe running up through the deckhead into
	# the funnel on the roof, and a worn rug on the sole between them.
	var blanket := mat_callback.call(Color(0.34, 0.10, 0.09), 0.96) as Material
	var linen := mat_callback.call(Color(0.60, 0.56, 0.48), 0.94) as Material
	var rug_red := mat_callback.call(Color(0.27, 0.11, 0.09), 0.97) as Material
	var rug_edge := mat_callback.call(Color(0.40, 0.31, 0.18), 0.97) as Material
	var books: Array[StandardMaterial3D] = [
		mat_callback.call(Color(0.25, 0.16, 0.10), 0.9),
		mat_callback.call(Color(0.13, 0.19, 0.15), 0.9),
		mat_callback.call(Color(0.30, 0.24, 0.12), 0.9),
	]

	# --- cabin furniture ------------------------------------------------------
	# Laid out from a check of the volumes rather than by eye. The old
	# arrangement had the stove standing inside the foot of the bunk and the
	# cupboard let into the forward bulkhead; both are gone. Three zones now,
	# and nothing crosses between them:
	#   forward bay  z -0.38 .. 0.95   table and stool to port, cupboard and
	#                                  sea chest to starboard
	#   corridor     z  0.95 .. 3.95   companionway to port, bunk to starboard,
	#                                  1.49 m of clear deck between them
	#   aft bay      z  3.95 .. 4.58   the stove, and the foot of the stairs

	# Bunk: frame, mattress, blanket over the foot, pillow at the head, and a
	# lee-board so the sleeper stays in it in a seaway.
	box_callback.call(Vector3(0.76, 0.30, 2.00), Vector3(1.30, 0.85, 2.30), Vector3.ZERO, trim)
	box_callback.call(Vector3(0.72, 0.10, 1.94), Vector3(1.30, 1.05, 2.30), Vector3.ZERO, linen)
	box_callback.call(Vector3(0.74, 0.07, 1.15), Vector3(1.30, 1.12, 2.76), Vector3.ZERO, blanket)
	box_callback.call(Vector3(0.46, 0.09, 0.36), Vector3(1.30, 1.13, 1.52), Vector3.ZERO, linen)
	box_callback.call(Vector3(0.05, 0.26, 2.00), Vector3(0.94, 1.05, 2.30), Vector3.ZERO, trim)

	# Dive locker, tucked under the forward end of the companionway — the
	# dead corner between the port frames and the first treads. Gear still
	# drips on the sole, not the bunk.
	dive_locker_callback.call()

	# Shelf of books on the starboard wall, over the head of the bunk, with a
	# fiddle so they stay put.
	box_callback.call(Vector3(0.24, 0.05, 1.10), Vector3(1.58, 1.98, 2.20), Vector3.ZERO, trim)
	box_callback.call(Vector3(0.24, 0.05, 0.04), Vector3(1.58, 2.30, 1.68), Vector3.ZERO, trim)
	for i in 6:
		var bz := 1.76 + float(i) * 0.165
		box_callback.call(Vector3(0.17, 0.22 + 0.05 * float(i % 3), 0.10),
				Vector3(1.58, 2.12, bz), Vector3(0.0, 0.0, 2.0 * float(i % 2)), books[i % 3])
	box_callback.call(Vector3(0.24, 0.04, 1.10), Vector3(1.58, 2.02, 2.20), Vector3.ZERO, trim)

	# Cupboard, forward starboard corner — clear of the bulkhead it used to be
	# buried in.
	box_callback.call(Vector3(0.46, 1.05, 0.40), Vector3(1.43, 1.21, -0.05), Vector3.ZERO, trim)
	box_callback.call(Vector3(0.38, 0.92, 0.03), Vector3(1.43, 1.20, 0.16), Vector3.ZERO, dark)
	box_callback.call(Vector3(0.05, 0.05, 0.05), Vector3(1.43, 1.20, 0.18), Vector3.ZERO, metal)

	# Sea chest, abaft the cupboard.
	box_callback.call(Vector3(0.45, 0.42, 0.45), Vector3(1.385, 0.90, 0.575), Vector3(0.0, 8.0, 0.0), dark)
	box_callback.call(Vector3(0.47, 0.06, 0.47), Vector3(1.385, 1.13, 0.575), Vector3(0.0, 8.0, 0.0), trim)

	# Cabin heater, in the aft bay. An ELECTRIC bar fire in a cast case: no
	# flue, no fuel, no chimney — and therefore something you switch rather
	# than something you light. Elements take their time both ways, which is
	# the whole character of the thing: E and it climbs to a slow red, E again
	# and it fades out over the better part of a minute, still ticking.
	var heater_case := mat_callback.call(
			Color(0.135, 0.132, 0.128), 0.62, 0.45) as Material
	box_callback.call(Vector3(0.46, 0.55, 0.42), Vector3(1.28, 0.92, 4.28), Vector3.ZERO, heater_case)
	# Reflector bowl behind the elements: brushed, so it throws the glow back
	# into the room instead of swallowing it.
	stove_reflector = mat_callback.call(Color(0.52, 0.50, 0.46), 0.28, 0.85)
	stove_reflector.emission_enabled = true
	stove_reflector.emission = Color(1.0, 0.48, 0.16)
	stove_reflector.emission_energy_multiplier = 0.0
	box_callback.call(Vector3(0.36, 0.34, 0.02), Vector3(1.28, 0.94, 4.09),
			Vector3.ZERO, stove_reflector)
	# Three bar elements. THESE are the light: coiled wire that goes from dead
	# grey to orange as it takes the current.
	stove_ember = mat_callback.call(Color(0.16, 0.13, 0.115), 0.55)
	stove_ember.emission_enabled = true
	stove_ember.emission = Color(1.0, 0.42, 0.12)
	stove_ember.emission_energy_multiplier = 0.0
	for eb in 3:
		cyl_callback.call(0.017, 0.017, 0.34, Vector3(1.28, 0.80 + float(eb) * 0.13, 4.075),
				Vector3(0.0, 0.0, 90.0), stove_ember)
	# Guard bars across the front, because a red-hot element at shin height in
	# a rolling boat is exactly what a guard is for.
	for gb in 5:
		cyl_callback.call(0.006, 0.006, 0.40, Vector3(1.28, 0.74 + float(gb) * 0.10, 4.048),
				Vector3(0.0, 0.0, 90.0), metal)
	box_callback.call(Vector3(0.03, 0.42, 0.03), Vector3(1.09, 0.94, 4.048), Vector3.ZERO, metal)
	box_callback.call(Vector3(0.03, 0.42, 0.03), Vector3(1.47, 0.94, 4.048), Vector3.ZERO, metal)
	# Rocker switch on the case top, and the flex running down to the skirting.
	# It owns a pivot because the hand grip must be parented to the part that
	# actually rocks; a painted box cannot carry contact motion.
	stove_switch = Node3D.new()
	stove_switch.position = Vector3(1.28, 1.205, 4.20)
	owner.add_child(stove_switch)
	box_callback.call(Vector3(0.05, 0.02, 0.07), Vector3.ZERO, Vector3.ZERO,
			mat_callback.call(Color(0.36, 0.27, 0.13), 0.40, 0.75), stove_switch)
	cyl_callback.call(0.008, 0.008, 0.52, Vector3(1.47, 0.70, 4.44), Vector3(22.0, 0.0, 0.0),
			mat_callback.call(Color(0.055, 0.055, 0.058), 0.85))
	# The near lamp used to sit inside the case with a 1.8 m, steep falloff —
	# a blob on the bars, not a fire in the room. It lives in front of the
	# elements now, and a second softer fill washes the sole and the bunk.
	stove_lamp = OmniLight3D.new()
	stove_lamp.position = Vector3(1.18, 1.08, 3.94)
	stove_lamp.light_color = Color(1.0, 0.52, 0.20)
	stove_lamp.light_energy = 0.0
	stove_lamp.omni_range = 3.6
	stove_lamp.omni_attenuation = 1.35
	stove_lamp.light_volumetric_fog_energy = 1.8
	stove_lamp.shadow_enabled = false
	owner.add_child(stove_lamp)
	stove_fill = OmniLight3D.new()
	stove_fill.position = Vector3(0.28, 1.52, 2.70)
	stove_fill.light_color = Color(1.0, 0.46, 0.18)
	stove_fill.light_energy = 0.0
	stove_fill.omni_range = 5.4
	stove_fill.omni_attenuation = 1.08
	stove_fill.light_volumetric_fog_energy = 0.7
	stove_fill.shadow_enabled = false
	owner.add_child(stove_fill)
	stove_effects_callback.call()
	lived_in_callback.call(trim, metal)

	# Weathertight hatches, not house doors. Each leaf hangs on a pivot and
	# swings; E on the drop-bar opens or shuts it. Shut, it puts a blocker
	# across the doorway so it is a hatch and not a picture of one.
	var gasket := mat_callback.call(Color(0.045, 0.040, 0.038), 0.95) as Material
	var batten := mat_callback.call(
			Color(0.118, 0.108, 0.092), 0.72, 0.35) as Material
	var plate := mat_callback.call(
			Color(0.210, 0.215, 0.200), 0.78, 0.22) as Material
	for k in 2:
		# Far enough off the bulkhead that the leaf shuts AGAINST the jamb
		# instead of into it. At 0.06 the leaf and the jamb were 2.5 mm apart in
		# z, which is a z-fight waiting for the first person to widen the leaf.
		var dz: float = (cabin_z0 + 0.085) if k == 0 else (cabin_z1 - 0.085)
		var piv := Node3D.new()
		piv.position = Vector3(-0.55, 0.0, dz)
		owner.add_child(piv)
		# Outboard face: forward hatch looks toward the bow (−Z), aft toward
		# the stern (+Z). Hardware sits on the weather side.
		var face: float = -1.0 if k == 0 else 1.0
		# Hole is 1.10 × 1.92. The old 1.12 leaf met the hinge stile on a
		# knife-edge — one millimetre of daylight. Overlap both jambs and
		# the header the way a hatch actually shuts.
		leaf_callback.call(piv, 1.18, 1.96, 0.56, 1.66, cabin_latch.x, true,
				face, plate, batten, gasket, metal)
		if k == 0:
			door_forward = piv
		else:
			door_aft = piv
	# Coaming on the WEATHER face, so from the deck the opening is a hatch
	# you walk up to, not a hole in a painted wall.
	hatch_callback.call(0.0, cabin_z0 - 0.08, 0.66, 1.96, -1.0, metal, paint, 1.10)
	hatch_callback.call(0.0, cabin_z1 + 0.08, 0.66, 1.96, 1.0, metal, paint, 1.10)

	# Rug on the sole, down the corridor between the stairs and the bunk.
	box_callback.call(Vector3(0.90, 0.025, 1.60), Vector3(0.20, 0.70, 2.30), Vector3.ZERO, rug_red)
	box_callback.call(Vector3(0.90, 0.028, 0.12), Vector3(0.20, 0.70, 1.56), Vector3.ZERO, rug_edge)
	box_callback.call(Vector3(0.90, 0.028, 0.12), Vector3(0.20, 0.70, 3.04), Vector3.ZERO, rug_edge)

	return {
		"glass_material": glass_material,
		"lit_window": lit_window,
		"cabin_lamp": cabin_lamp,
		"stove_reflector": stove_reflector,
		"stove_ember": stove_ember,
		"stove_switch": stove_switch,
		"stove_lamp": stove_lamp,
		"stove_fill": stove_fill,
		"door_forward": door_forward,
		"door_aft": door_aft,
		"gasket": gasket,
		"batten": batten,
		"plate": plate,
	}
