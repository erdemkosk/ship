class_name BoatWheelhouseVisualBuilder
extends RefCounted
## Builds the glazed wheelhouse shell, balcony hatch and helm light.


func build(owner: Node3D, paint: Material, paint_dark: Material,
		trim: Material, metal: Material, glass_material: ShaderMaterial,
		gasket: Material, batten: Material, plate: Material,
		wheelhouse_latch: Vector3, box_callback: Callable,
		cyl_callback: Callable, mat_callback: Callable, glass_callback: Callable,
		leaf_callback: Callable, hatch_callback: Callable,
		wiper_callback: Callable, chart_callback: Callable,
		electronics_callback: Callable, switchboard_callback: Callable,
		helm_callback: Callable, console_callback: Callable) -> Dictionary:
	var front_glass: ShaderMaterial
	var wheelhouse_door: Node3D
	var helm_glow: StandardMaterial3D
	var helm_lamp: OmniLight3D
	# --- wheelhouse (upper level) -------------------------------------------
	const WH_Z0 := -0.25
	const WH_Z1 := 4.05
	const WH_X := 1.74
	const WH_Y0 := 2.91   # sole: the top of the deckhouse roof
	const WH_Y1 := 5.34   # deckhead — the glass band has to run well past the
	# standing eye at 4.36, or the horizon lands exactly on the header.
	var wy := (WH_Y0 + WH_Y1) * 0.5
	var wh := WH_Y1 - WH_Y0
	var wz := (WH_Z0 + WH_Z1) * 0.5
	var wl := WH_Z1 - WH_Z0

	box_callback.call(Vector3(WH_X * 2.0 + 0.22, 0.16, wl + 0.30), Vector3(0.0, WH_Y1 + 0.08, wz),
			Vector3.ZERO, paint_dark)
	# Sill to 3.32, glass to 4.74, header above: the standing eye (4.36) sits in
	# the MIDDLE of the pane, so the horizon is glass, not woodwork.
	for sx in [-1.0, 1.0]:
		box_callback.call(Vector3(0.09, 0.50, wl), Vector3(sx * WH_X, 3.16, wz), Vector3.ZERO, paint)
		box_callback.call(Vector3(0.09, 0.25, wl), Vector3(sx * WH_X, 5.215, wz), Vector3.ZERO, paint)
		box_callback.call(Vector3(0.10, wh, 0.10), Vector3(sx * WH_X, wy, WH_Z0), Vector3.ZERO, trim)
		box_callback.call(Vector3(0.10, wh, 0.10), Vector3(sx * WH_X, wy, WH_Z1), Vector3.ZERO, trim)
		glass_callback.call(Vector3(0.05, 1.68, wl - 0.14), Vector3(sx * WH_X, 4.25, wz))
	box_callback.call(Vector3(WH_X * 2.0, 0.50, 0.09), Vector3(0.0, 3.16, WH_Z0), Vector3.ZERO, paint)
	box_callback.call(Vector3(WH_X * 2.0, 0.25, 0.09), Vector3(0.0, 5.215, WH_Z0), Vector3.ZERO, paint)
	# The front pane gets its own material: it is the one with the wiper.
	front_glass = glass_material.duplicate()
	front_glass.set_shader_parameter("has_wiper", 1)
	glass_callback.call(Vector3(WH_X * 2.0 - 0.16, 1.68, 0.05), Vector3(0.0, 4.25, WH_Z0), front_glass)
	# The dry fan lives in the glass shader. The arm itself is out on the
	# weather face — a thin steel whip, not the black plank that used to sit
	# dead-centre of the view and hide the horizon. It parks to port so the
	# helm is not a bar.
	wiper_callback.call(WH_Z0)
	# Aft face. The doorway is on the centreline, out onto the roof balcony.
	# Port of it is a solid panel (it also closes the stairwell). Starboard is
	# glass over a sill, with a jamb so the door has something to hang on.
	box_callback.call(Vector3(1.23, wh, 0.09), Vector3(-1.185, wy, WH_Z1), Vector3.ZERO, paint)
	box_callback.call(Vector3(1.07, 0.50, 0.09), Vector3(1.205, 3.16, WH_Z1), Vector3.ZERO, paint)
	box_callback.call(Vector3(0.12, wh, 0.09), Vector3(0.61, wy, WH_Z1), Vector3.ZERO, paint)
	box_callback.call(Vector3(3.48, 0.25, 0.09), Vector3(0.0, 5.215, WH_Z1), Vector3.ZERO, paint)
	box_callback.call(Vector3(1.22, 0.26, 0.09), Vector3(0.0, 4.96, WH_Z1), Vector3.ZERO, paint)
	box_callback.call(Vector3(1.22, 0.06, 0.10), Vector3(0.0, WH_Y0 + 0.03, WH_Z1), Vector3.ZERO, trim)
	glass_callback.call(Vector3(1.07, 1.68, 0.05), Vector3(1.205, 4.25, WH_Z1))

	# Balcony hatch. Hinged starboard so it parks against the glass, not over
	# the companionway. Inward — the balcony is a metre deep and a leaf that
	# size would hit the aft rail.
	# The hole in the aft bulkhead is x −0.57..0.55, y 2.91..4.83. A 1.06 × 1.88
	# leaf centred on the hinge left a strip of daylight on the port stile and
	# under the lintel — shut, and you could still see the balcony through it.
	# Sit the plate AGAINST the inner face (same 85 mm as the cabin hatches)
	# and let it land on both jambs and the header.
	var wh_piv := Node3D.new()
	wh_piv.position = Vector3(0.55, WH_Y0, WH_Z1 - 0.085)
	owner.add_child(wh_piv)
	leaf_callback.call(wh_piv, 1.18, 1.98, -0.58, 0.99, wheelhouse_latch.x, false,
			1.0, plate, batten, gasket, metal, false)
	hatch_callback.call(0.0, WH_Z1 + 0.06, WH_Y0 + 0.02, 1.98, 1.0, metal, paint, 1.12)
	# Deadlight, not a house panel: a small square port with a heavy frame.
	box_callback.call(Vector3(0.40, 0.32, 0.018), Vector3(-0.53, 1.28, 0.044), Vector3.ZERO, metal, wh_piv)
	box_callback.call(Vector3(0.30, 0.22, 0.012), Vector3(-0.53, 1.28, 0.052), Vector3.ZERO,
			mat_callback.call(Color(0.07, 0.09, 0.11), 0.22), wh_piv)
	wheelhouse_door = wh_piv

	# The centre of the room stays EMPTY: aft door -> wheel is a straight walk.
	chart_callback.call(trim, metal)
	electronics_callback.call(trim, metal)
	switchboard_callback.call(trim, metal)
	# Helm lamp: dead centre of the wheelhouse deckhead, not 15 cm aft of it
	# and not sitting inside the window header.
	helm_glow = mat_callback.call(Color(0.30, 0.20, 0.10), 0.55)
	helm_glow.emission_enabled = true
	helm_glow.emission = Color(1.0, 0.66, 0.30)
	helm_glow.emission_energy_multiplier = 2.2
	cyl_callback.call(0.02, 0.02, 0.10, Vector3(0.0, WH_Y1 - 0.05, wz), Vector3.ZERO, metal)
	box_callback.call(Vector3(0.16, 0.12, 0.16), Vector3(0.0, WH_Y1 - 0.16, wz), Vector3.ZERO, helm_glow)
	helm_lamp = OmniLight3D.new()
	helm_lamp.position = Vector3(0.0, WH_Y1 - 0.26, wz)
	helm_lamp.light_color = Color(1.0, 0.50, 0.24)
	helm_lamp.light_energy = 1.1
	helm_lamp.omni_range = 3.8
	helm_lamp.omni_attenuation = 1.8
	helm_lamp.shadow_enabled = false
	owner.add_child(helm_lamp)

	helm_callback.call(trim, metal)
	console_callback.call(trim, metal)

	return {
		"front_glass": front_glass,
		"wheelhouse_door": wheelhouse_door,
		"helm_glow": helm_glow,
		"helm_lamp": helm_lamp,
	}
