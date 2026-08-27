extends RigidBody3D
## Throwable rock. Hits the water once, then sinks with drag/buoyancy.
## Velocity is never assigned in _physics_process (that fights interpolation
## and looks like the stone reversing).

var ocean: Node3D
var _splashed := false
var _bubbles: GPUParticles3D


func _ready() -> void:
	mass = 3.2
	continuous_cd = true
	can_sleep = false
	linear_damp = 0.0
	angular_damp = 0.4
	gravity_scale = 1.0
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.0
	pm.friction = 0.35
	physics_material_override = pm

	var mesh := SphereMesh.new()
	mesh.radius = 0.12
	mesh.height = 0.24
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.16, 0.14)
	mat.roughness = 1.0
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)

	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.12
	col.shape = shape
	add_child(col)

	if ocean != null and ocean.follow_target is PhysicsBody3D:
		add_collision_exception_with(ocean.follow_target)

	_build_bubbles()


func _build_bubbles() -> void:
	_bubbles = GPUParticles3D.new()
	_bubbles.amount = 18
	_bubbles.lifetime = 0.7
	_bubbles.emitting = false
	_bubbles.local_coords = false
	_bubbles.transform_align = GPUParticles3D.TRANSFORM_ALIGN_DISABLED
	_bubbles.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_bubbles.visibility_aabb = AABB(Vector3(-2, -2, -2), Vector3(4, 6, 4))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.06
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 18.0
	pm.initial_velocity_min = 0.15
	pm.initial_velocity_max = 0.45
	pm.gravity = Vector3(0, 0.8, 0)
	pm.scale_min = 0.04
	pm.scale_max = 0.09
	pm.color = Color(0.75, 0.85, 0.9, 0.35)
	_bubbles.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.07, 0.07)
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	smat.albedo_color = Color(0.8, 0.9, 0.95, 0.4)
	q.material = smat
	_bubbles.draw_pass_1 = q
	add_child(_bubbles)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if ocean == null:
		return
	var pos := state.transform.origin
	var wh: float = ocean.get_height(pos)
	var depth: float = wh - pos.y
	var v := state.linear_velocity

	if depth > 0.0:
		if not _splashed:
			_splashed = true
			var impact := clampf(maxf(-v.y, 0.4), 0.5, 2.4)
			ocean.splash(Vector3(pos.x, wh, pos.z), impact)
			# Always continue downward — never bounce back out of the surface.
			v.y = minf(v.y * 0.35, -0.55)
			v.x *= 0.55
			v.z *= 0.55
			state.linear_velocity = v
			v = state.linear_velocity
		if _bubbles != null:
			_bubbles.emitting = true

		var submerged := clampf(depth / 0.24, 0.0, 1.0)
		# Denser than water: buoyancy < weight, so it sinks.
		state.apply_central_force(Vector3.UP * mass * 9.81 * 0.32 * submerged)
		# Quadratic drag — kills the "slides backward" snap.
		var speed := v.length()
		if speed > 0.02:
			state.apply_central_force(-v.normalized() * speed * speed * 3.4 * submerged)
		state.apply_central_force(-v * 1.6 * submerged)
		# Ride the orbital motion of the swell so the stone doesn't look like
		# the Gerstner chop is dragging the sea out from under it.
		if depth < 2.2 and ocean.has_method("surface_velocity"):
			var orb: Vector3 = ocean.surface_velocity(pos)
			var fade := clampf(1.0 - depth / 2.2, 0.0, 1.0)
			var rel := orb * fade - Vector3(v.x, 0.0, v.z)
			state.apply_central_force(rel * mass * 2.4)

		var floor_h: float = ocean.get_seafloor_height(pos)
		if pos.y <= floor_h + 0.12:
			queue_free()
			return
	else:
		if _bubbles != null:
			_bubbles.emitting = false

	if pos.y < -55.0:
		queue_free()
