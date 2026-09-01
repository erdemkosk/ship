class_name BoatHelmVisualBuilder
extends RefCounted
## Slim steering column, wheel rim, spokes and hub.


func build(owner: Node3D, trim: Material, metal: Material,
		cylinder_callback: Callable, material_callback: Callable) -> Node3D:
	var bronze: Material = material_callback.call(
			Color(0.34, 0.26, 0.13), 0.40, 0.72)
	var pivot := Node3D.new()
	pivot.position = Vector3(0.0, 3.45, 0.30)
	owner.add_child(pivot)
	cylinder_callback.call(0.044, 0.038, 0.36,
			Vector3(0.0, 0.18, 0.0), Vector3.ZERO, bronze, pivot)
	var wheel := Node3D.new()
	wheel.position = Vector3(0.0, 0.38, 0.0)
	wheel.rotation_degrees.x = -18.0
	pivot.add_child(wheel)
	var rim := MeshInstance3D.new()
	var rim_mesh := TorusMesh.new()
	rim_mesh.inner_radius = 0.26
	rim_mesh.outer_radius = 0.32
	rim_mesh.rings = 20
	rim_mesh.ring_segments = 6
	rim_mesh.material = trim
	rim.mesh = rim_mesh
	rim.rotation_degrees.x = 90.0
	wheel.add_child(rim)
	for index in 6:
		var angle := float(index) / 6.0 * TAU
		var spoke := MeshInstance3D.new()
		var spoke_mesh := CylinderMesh.new()
		spoke_mesh.top_radius = 0.022
		spoke_mesh.bottom_radius = 0.022
		spoke_mesh.height = 0.56
		spoke_mesh.radial_segments = 6
		spoke_mesh.rings = 1
		spoke_mesh.material = trim
		spoke.mesh = spoke_mesh
		spoke.rotation_degrees = Vector3(0.0, 0.0, rad_to_deg(angle))
		wheel.add_child(spoke)
	var hub := MeshInstance3D.new()
	var hub_mesh := CylinderMesh.new()
	hub_mesh.top_radius = 0.06
	hub_mesh.bottom_radius = 0.06
	hub_mesh.height = 0.10
	hub_mesh.radial_segments = 10
	hub_mesh.material = metal
	hub.mesh = hub_mesh
	hub.rotation_degrees.x = 90.0
	wheel.add_child(hub)
	return wheel
