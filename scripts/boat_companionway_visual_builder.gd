class_name BoatCompanionwayVisualBuilder
extends RefCounted
## Builds the companionway, sloped engine hatch and forward floodlights.


func build(owner: Node3D, trim: Material, metal: Material,
		box_callback: Callable, cyl_callback: Callable, mat_callback: Callable,
		box_node_callback: Callable, trap_callback: Callable,
		dog_callback: Callable) -> Dictionary:
	var engine_door: Node3D
	var flood_lens_material: StandardMaterial3D
	var flood_beam_material: ShaderMaterial
	var floodlights: Array[SpotLight3D] = []
	# --- companionway ------------------------------------------------------
	# Eight treads up the port side of the cabin, through an opening in the
	# deckhead. Walked, not climbed.
	for i in 10:
		# Numbered from the bottom, so tread 0 is the one you step onto off the
		# sole and tread 9 is level with the wheelhouse deck.
		var ty := 0.903 + float(i) * 0.223
		var tz := 3.80 - float(i) * 0.30
		# The board is hung so its TOP is exactly the height you walk at. Centred
		# on it instead, every step stands three centimetres proud of the surface
		# your feet are actually on, and you spend the whole flight shin-deep in
		# the treads.
		box_callback.call(Vector3(1.16, 0.06, 0.30), Vector3(-1.08, ty - 0.03, tz), Vector3.ZERO, trim)
		box_callback.call(Vector3(1.16, 0.163, 0.05), Vector3(-1.08, ty - 0.1415, tz + 0.125),
				Vector3.ZERO, trim)
	# Underside of the flight. Without this the well is a hole: stand at the
	# foot, look forward, and the machine sits in a triangle under bare treads.
	# The slab is the same rake as the going (0.223 on 0.30 = 36.6°) and sits
	# a couple of centimetres under the tread bottoms so the two do not fight.
	box_callback.call(Vector3(1.16, 0.04, 3.36), Vector3(-1.08, 1.817, 2.45),
			Vector3(36.6, 0.0, 0.0), trim)
	# Closing boards on the cabin face, except the hatch bay (k 2..5).
	var frame := mat_callback.call(
			Color(0.18, 0.19, 0.20), 0.35, 0.55) as Material
	for k in 9:
		var by := 2.910 - float(k) * 0.223 - 0.03
		if k >= 2 and k <= 5:
			continue
		box_callback.call(Vector3(0.05, by - 0.68, 0.30), Vector3(-0.525, (0.68 + by) * 0.5,
				1.10 + float(k) * 0.30), Vector3.ZERO, trim)

	# Engine hatch. The opening is bays k 2..5: z 1.55 .. 2.75, sole to the
	# soffit. Top edge is the same slope as the stairs, so shut it is a wall
	# and there is no wedge of daylight over the leaf.
	var slope := 0.223 / 0.30
	var z0 := 1.55
	var z1 := 2.77
	var hinge_y := 1.24
	engine_door = Node3D.new()
	engine_door.position = Vector3(-0.500, hinge_y, z0)
	owner.add_child(engine_door)
	# Sole is 0.63; 0.70 left a kick of daylight. The soffit is the stair
	# underside — 12 mm of air under it was a bright line from the cabin.
	var y_bot := 0.635 - hinge_y
	var y_hf := 2.850 - (z0 - 1.10) * slope - hinge_y - 0.002
	var y_ha := 2.850 - (z1 - 1.10) * slope - hinge_y - 0.002
	var z_e := z1 - z0
	var hatch_m: StandardMaterial3D = trim.duplicate()
	hatch_m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var leaf := trap_callback.call(
			0.045, y_bot, y_hf, y_ha, z_e, hatch_m) as MeshInstance3D
	engine_door.add_child(leaf)
	var bronze_h := mat_callback.call(
			Color(0.36, 0.27, 0.13), 0.4, 0.7) as Material
	var hnd := box_node_callback.call(Vector3(0.028, 0.13, 0.030),
			Vector3(-0.035, (y_bot + y_ha) * 0.5, z_e - 0.10),
			bronze_h) as MeshInstance3D
	engine_door.add_child(hnd)
	for hy in [y_bot + 0.16, (y_bot + y_hf) * 0.5, y_hf - 0.16]:
		var kn := box_node_callback.call(Vector3(0.055, 0.075, 0.030),
				Vector3(0.0, hy, 0.03), frame) as MeshInstance3D
		engine_door.add_child(kn)
	var iron_h := mat_callback.call(
			Color(0.105, 0.105, 0.115), 0.50, 0.65) as Material
	dog_callback.call(engine_door, Vector3(-0.01, y_bot + 0.22, 0.04), iron_h)
	dog_callback.call(engine_door, Vector3(-0.01, y_hf - 0.22, 0.04), iron_h)
	# Coaming round the opening on the upper deck, so it reads as a stairwell.
	# Trim only — it used to be a collider too, and between it and the wheelhouse
	# side that left a three-centimetre gap to squeeze the top step through.
	box_callback.call(Vector3(0.05, 0.26, 2.40), Vector3(-0.52, 3.04, 2.75), Vector3.ZERO, trim)
	box_callback.call(Vector3(1.22, 0.26, 0.05), Vector3(-1.08, 3.04, 3.95), Vector3.ZERO, trim)

	# --- forward floodlights ------------------------------------------------
	# Two of them, on the roof edge between the decks, throwing light out ahead
	# of the bow. Their own circuit: 6, or the panel's master switch.
	# The lens material has to exist BEFORE the loop — it used to be created
	# after, so the glasses were assigned null and never lit, which is why
	# throwing the switch did nothing you could see.
	flood_lens_material = StandardMaterial3D.new()
	flood_lens_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flood_lens_material.albedo_color = Color(0.16, 0.14, 0.11)
	flood_lens_material.emission_enabled = true
	flood_lens_material.emission = Color(1.0, 0.95, 0.82)
	flood_lens_material.emission_energy_multiplier = 0.0
	flood_beam_material = ShaderMaterial.new()
	flood_beam_material.shader = load("res://shaders/lighthouse_beam.gdshader")
	flood_beam_material.set_shader_parameter("intensity", 0.0)
	flood_beam_material.set_shader_parameter("gain", 0.9)
	flood_beam_material.set_shader_parameter("reach", 0.72)
	flood_beam_material.set_shader_parameter("edge_soft", 1.35)
	flood_beam_material.set_shader_parameter("soft_metres", 8.0)
	flood_beam_material.set_shader_parameter("haze", 1.0)
	flood_beam_material.set_shader_parameter("beam_color", Color(1.0, 0.94, 0.80))
	const BLEN := 28.0
	var bdip := deg_to_rad(12.0)
	for sx in [-1.0, 1.0]:
		var fp := Vector3(sx * 1.22, 3.06, -0.56)
		box_callback.call(Vector3(0.10, 0.16, 0.10), fp + Vector3(0.0, -0.09, 0.0), Vector3.ZERO, metal)
		cyl_callback.call(0.10, 0.12, 0.20, fp, Vector3(-72.0, 0.0, 0.0), metal)
		var lens := MeshInstance3D.new()
		var lmz := CylinderMesh.new()
		lmz.top_radius = 0.105
		lmz.bottom_radius = 0.105
		lmz.height = 0.03
		lmz.radial_segments = 12
		lmz.material = flood_lens_material
		lens.mesh = lmz
		lens.position = fp + Vector3(0.0, -0.03, -0.10)
		lens.rotation_degrees = Vector3(-72.0, 0.0, 0.0)
		owner.add_child(lens)
		var fl := SpotLight3D.new()
		fl.position = fp + Vector3(0.0, -0.02, -0.12)
		fl.rotation_degrees = Vector3(-12.0, 0.0, 0.0)
		fl.light_color = Color(1.0, 0.94, 0.80)
		fl.light_energy = 0.0
		fl.spot_range = 48.0
		fl.spot_angle = 28.0
		fl.spot_attenuation = 0.55
		fl.spot_angle_attenuation = 0.55
		fl.light_specular = 0.85
		fl.light_volumetric_fog_energy = 14.0
		fl.shadow_enabled = false
		owner.add_child(fl)
		floodlights.append(fl)
		# A short shaft you can actually see. The spot's volumetric fog dies
		# in the froxels; this cone is the same trick the lighthouse uses.
		var shaft := MeshInstance3D.new()
		var sc := CylinderMesh.new()
		sc.top_radius = 7.2
		sc.bottom_radius = 0.07
		sc.height = BLEN
		sc.radial_segments = 16
		sc.rings = 1
		sc.cap_top = false
		sc.cap_bottom = false
		sc.material = flood_beam_material
		shaft.mesh = sc
		shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		shaft.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		shaft.rotation_degrees = Vector3(-102.0, 0.0, 0.0)
		shaft.position = fp + Vector3(0.0, -sin(bdip) * BLEN * 0.5,
				-cos(bdip) * BLEN * 0.5)
		owner.add_child(shaft)


	return {
		"engine_door": engine_door,
		"flood_lens_material": flood_lens_material,
		"flood_beam_material": flood_beam_material,
		"floodlights": floodlights,
	}
