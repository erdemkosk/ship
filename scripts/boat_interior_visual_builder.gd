class_name BoatInteriorVisualBuilder
extends RefCounted

func build(host: Node3D) -> Dictionary:
	## A steel clothes locker, bolted to the frames on the port side. Vents
	## punched in the door because wet gear that cannot breathe rots, a lip at
	## the bottom so what drips off it runs to the sole and not into the bunk,
	## and one plain lever handle.
	var steel := _material(Color(0.155, 0.170, 0.178), 0.62, 0.55)
	var steel_d := _material(Color(0.105, 0.115, 0.122), 0.70, 0.50)
	var iron := _material(Color(0.150, 0.115, 0.088), 0.90, 0.30)
	var rubber := _material(Color(0.045, 0.048, 0.052), 0.88)
	var glassy := _material(Color(0.30, 0.42, 0.46, 0.55), 0.10, 0.0)
	glassy.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var LX := -1.46          # centre of the carcass, against the port frames
	var LZ := 0.84           # under the first treads; aft face kisses z 1.10
	var Y0 := 0.68
	var Y1 := 2.38
	var HY := (Y0 + Y1) * 0.5
	# Carcass: back against the ship side, two sides, top, and a kick at the
	# bottom. Left open at the front — the door is the front.
	_box(host, Vector3(0.03, Y1 - Y0, 0.52), Vector3(LX - 0.225, HY, LZ), Vector3.ZERO, steel_d)
	_box(host, Vector3(0.48, Y1 - Y0, 0.03), Vector3(LX, HY, LZ - 0.245), Vector3.ZERO, steel_d)
	_box(host, Vector3(0.48, Y1 - Y0, 0.03), Vector3(LX, HY, LZ + 0.245), Vector3.ZERO, steel_d)
	_box(host, Vector3(0.48, 0.03, 0.52), Vector3(LX, Y1, LZ), Vector3.ZERO, steel)
	_box(host, Vector3(0.48, 0.02, 0.52), Vector3(LX, Y0 + 0.11, LZ), Vector3.ZERO, steel_d)
	_box(host, Vector3(0.48, 0.11, 0.52), Vector3(LX, Y0 + 0.055, LZ), Vector3.ZERO, steel_d)
	# A single strap across the back at chest height, to stop the bottle
	# walking about in a seaway. No rail, no hangers: nothing in here is
	# clothing, it is two pieces of equipment that stand up on their own.
	_box(host, Vector3(0.40, 0.035, 0.020), Vector3(LX, 1.52, LZ - 0.215), Vector3.ZERO, rubber)

	# The door. Hinged on its FORWARD edge so it opens across the locker and
	# not into the walk — the cabin sole between the bunk and this is 1.49 m
	# and a leaf swinging aft would take most of it.
	var locker_door := Node3D.new()
	locker_door.position = Vector3(LX + 0.225, HY, LZ - 0.245)
	host.add_child(locker_door)
	var leaf := MeshInstance3D.new()
	var lm := BoxMesh.new()
	# Overlap the carcass, do not sit inside it. −0.02 left a bright line
	# at the head and the kick.
	lm.size = Vector3(0.028, Y1 - Y0 + 0.02, 0.50)
	leaf.mesh = lm
	leaf.material_override = steel
	leaf.position = Vector3(0.0, 0.0, 0.245)
	locker_door.add_child(leaf)
	# Louvres, low and high — a locker breathes or it stinks.
	for i in 5:
		var vy: float = -0.62 + float(i) * 0.055
		for vy2 in [vy, vy + 0.95]:
			var v := MeshInstance3D.new()
			var vm := BoxMesh.new()
			vm.size = Vector3(0.006, 0.016, 0.30)
			v.mesh = vm
			v.material_override = steel_d
			v.position = Vector3(0.016, vy2, 0.245)
			v.rotation.z = deg_to_rad(-24.0)
			locker_door.add_child(v)
	# Handle: a plain lever, and the hasp it drops into.
	var h := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.030, 0.035, 0.145)
	h.mesh = hm
	h.material_override = iron
	h.position = Vector3(0.030, 0.10, 0.415)
	locker_door.add_child(h)

	# --- what is inside -----------------------------------------------------
	# A bottle standing on the locker floor with its mask hung over the valve.
	# That is how it is actually stowed: the cylinder stands, the mask lives on
	# top of it where it cannot be trodden on, and the whole lot comes out in
	# one movement.
	var tank_paint := _material(Color(0.16, 0.24, 0.22), 0.55, 0.35)
	var brass2 := _material(Color(0.52, 0.40, 0.16), 0.42, 0.85)
	var TZ := LZ + 0.02
	var gear_tank := Node3D.new()
	gear_tank.position = Vector3(LX, 0.0, TZ)
	host.add_child(gear_tank)
	var body := MeshInstance3D.new()
	var bm2 := CylinderMesh.new()
	bm2.top_radius = 0.084
	bm2.bottom_radius = 0.084
	bm2.height = 0.66
	bm2.radial_segments = 18
	body.mesh = bm2
	body.material_override = tank_paint
	body.position = Vector3(0.0, 1.12, 0.0)
	gear_tank.add_child(body)
	# Boot at the foot — the rubber cup a cylinder stands in.
	var boot := MeshInstance3D.new()
	var bo := CylinderMesh.new()
	bo.top_radius = 0.089
	bo.bottom_radius = 0.094
	bo.height = 0.10
	bo.radial_segments = 18
	boot.mesh = bo
	boot.material_override = rubber
	boot.position = Vector3(0.0, 0.84, 0.0)
	gear_tank.add_child(boot)
	# Neck, valve block and its handwheel.
	var neck := MeshInstance3D.new()
	var nk := CylinderMesh.new()
	nk.top_radius = 0.030
	nk.bottom_radius = 0.062
	nk.height = 0.075
	nk.radial_segments = 14
	neck.mesh = nk
	neck.material_override = tank_paint
	neck.position = Vector3(0.0, 1.49, 0.0)
	gear_tank.add_child(neck)
	var valve := MeshInstance3D.new()
	var vb := BoxMesh.new()
	vb.size = Vector3(0.052, 0.070, 0.052)
	valve.mesh = vb
	valve.material_override = brass2
	valve.position = Vector3(0.0, 1.56, 0.0)
	gear_tank.add_child(valve)
	var wheel := MeshInstance3D.new()
	var wt := TorusMesh.new()
	wt.inner_radius = 0.019
	wt.outer_radius = 0.032
	wt.rings = 12
	wt.ring_segments = 7
	wheel.mesh = wt
	wheel.material_override = brass2
	wheel.position = Vector3(0.0, 1.60, -0.045)
	wheel.rotation.x = deg_to_rad(90.0)
	gear_tank.add_child(wheel)
	# First stage on the valve, and the hose off it looping down the bottle.
	var reg := MeshInstance3D.new()
	var rg := CylinderMesh.new()
	rg.top_radius = 0.028
	rg.bottom_radius = 0.028
	rg.height = 0.048
	rg.radial_segments = 12
	reg.mesh = rg
	reg.material_override = brass2
	reg.position = Vector3(0.055, 1.56, 0.0)
	reg.rotation.z = deg_to_rad(90.0)
	gear_tank.add_child(reg)
	for hi in 5:
		var t: float = float(hi) / 4.0
		var hose := MeshInstance3D.new()
		var hs := CylinderMesh.new()
		hs.top_radius = 0.010
		hs.bottom_radius = 0.010
		hs.height = 0.115
		hs.radial_segments = 8
		hose.mesh = hs
		hose.material_override = rubber
		hose.position = Vector3(0.075 + sin(t * PI) * 0.030, 1.50 - t * 0.42,
				0.010 + t * 0.045)
		hose.rotation.x = deg_to_rad(-12.0 * t)
		hose.rotation.z = deg_to_rad(24.0 - 34.0 * t)
		gear_tank.add_child(hose)
	# Harness webbing round the bottle.
	for by in [1.02, 1.32]:
		var band := MeshInstance3D.new()
		var bd := CylinderMesh.new()
		bd.top_radius = 0.088
		bd.bottom_radius = 0.088
		bd.height = 0.035
		bd.radial_segments = 18
		band.mesh = bd
		band.material_override = rubber
		band.position = Vector3(0.0, by, 0.0)
		gear_tank.add_child(band)

	# The mask, hung by its strap over the valve. No hook, no hanger — the
	# strap simply lies over the block, which is where it always ends up.
	var gear_mask := Node3D.new()
	gear_mask.position = Vector3(LX, 1.46, TZ + 0.085)
	gear_mask.rotation.x = deg_to_rad(14.0)
	host.add_child(gear_mask)
	var skirt := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.180, 0.108, 0.070)
	skirt.mesh = sm
	skirt.material_override = rubber
	gear_mask.add_child(skirt)
	var lens := MeshInstance3D.new()
	var lnm := BoxMesh.new()
	lnm.size = Vector3(0.152, 0.080, 0.012)
	lens.mesh = lnm
	lens.material_override = glassy
	lens.position = Vector3(0.0, 0.006, 0.038)
	gear_mask.add_child(lens)
	# Frame round the glass, so it is a mask and not a slab.
	for fr in [[Vector3(0.176, 0.016, 0.016), Vector3(0.0, 0.049, 0.034)],
			[Vector3(0.176, 0.016, 0.016), Vector3(0.0, -0.043, 0.034)],
			[Vector3(0.016, 0.104, 0.016), Vector3(-0.083, 0.003, 0.034)],
			[Vector3(0.016, 0.104, 0.016), Vector3(0.083, 0.003, 0.034)]]:
		var fm := MeshInstance3D.new()
		var fb := BoxMesh.new()
		fb.size = fr[0]
		fm.mesh = fb
		fm.material_override = rubber
		fm.position = fr[1]
		gear_mask.add_child(fm)
	# The strap, over the valve block behind it.
	for sx2 in [-1.0, 1.0]:
		var strap := MeshInstance3D.new()
		var stm := BoxMesh.new()
		stm.size = Vector3(0.026, 0.012, 0.145)
		strap.mesh = stm
		strap.material_override = rubber
		strap.position = Vector3(sx2 * 0.072, 0.020, -0.100)
		strap.rotation.x = deg_to_rad(24.0)
		strap.rotation.y = deg_to_rad(-sx2 * 9.0)
		gear_mask.add_child(strap)
	return {
		"locker_door": locker_door,
		"gear_tank": gear_tank,
		"gear_mask": gear_mask,
	}


func build_stove_effects(host: Node3D) -> Dictionary:
	var heat := GPUParticles3D.new()
	heat.amount = 16
	heat.lifetime = 1.05
	heat.preprocess = 1.0
	heat.local_coords = true
	heat.position = Vector3(1.28, 1.18, 4.10)
	heat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	heat.visibility_aabb = AABB(Vector3(-1.2, -0.4, -1.2),
			Vector3(2.4, 2.4, 2.4))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(0.16, 0.02, 0.08)
	process.direction = Vector3.UP
	process.spread = 18.0
	process.initial_velocity_min = 0.09
	process.initial_velocity_max = 0.24
	process.gravity = Vector3(0.0, 0.34, 0.0)
	process.damping_min = 0.4
	process.damping_max = 0.9
	process.scale_min = 0.20
	process.scale_max = 0.55
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.30, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 0.72, 0.52, 0.085),
		Color(1.0, 0.66, 0.46, 0.045),
		Color(0.8, 0.55, 0.40, 0.0),
	])
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	process.color_ramp = ramp
	heat.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(0.055, 0.09)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_color = Color(1.0, 0.45, 0.12, 0.4)
	material.vertex_color_use_as_albedo = true
	quad.material = material
	heat.draw_pass_1 = quad
	heat.emitting = true
	host.add_child(heat)

	var sound: AudioStreamPlayer3D
	var stream: AudioStream = load("res://assets/audio/stove.mp3")
	if stream != null:
		if stream is AudioStreamMP3:
			(stream as AudioStreamMP3).loop = true
		sound = AudioStreamPlayer3D.new()
		sound.position = Vector3(1.28, 1.02, 4.08)
		sound.stream = stream
		sound.bus = "Master"
		sound.unit_size = 0.70
		sound.max_distance = 2.15
		sound.max_db = 6.0
		sound.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		sound.panning_strength = 0.90
		host.add_child(sound)
		sound.play()
	return {"heat": heat, "sound": sound}

func _material(albedo: Color, roughness: float, metallic := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = albedo
	material.roughness = roughness
	material.metallic = metallic
	return material


func _box(host: Node3D, size: Vector3, position: Vector3,
		rotation_degrees: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	instance.mesh = mesh
	instance.position = position
	instance.rotation_degrees = rotation_degrees
	host.add_child(instance)
	return instance
