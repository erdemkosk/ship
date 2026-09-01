extends SceneTree
## VHF finite-reach release and coiled-cord geometry contract.

class FakeCameraRig extends Node3D:
	var mode := 1
	var _cam: Camera3D


func _initialize() -> void:
	var boat := Node3D.new()
	var handset := Node3D.new()
	var rig := FakeCameraRig.new()
	var camera := Camera3D.new()
	rig._cam = camera
	root.add_child(boat)
	boat.add_child(handset)
	root.add_child(rig)
	rig.add_child(camera)
	var cord: Array[MeshInstance3D] = []
	for _index in 6:
		var segment := MeshInstance3D.new()
		boat.add_child(segment)
		cord.append(segment)
	await process_frame
	camera.global_position = Vector3(12.0, 4.0, 0.0)
	var controller := preload("res://scripts/boat_radio_handset_controller.gd").new()
	var held := controller.update(boat, handset, cord, rig, true, false, 0.50)
	var finite_segments := true
	var length_sum := 0.0
	for segment in cord:
		finite_segments = finite_segments and segment.transform.is_finite()
		length_sum += segment.basis.y.length()
	var complete := not held and finite_segments and length_sum > 0.1 \
			and handset.position.distance_to(controller.CRADLE) < 1.0
	print("[radio-handset-controller] held=%s segments=%d length=%.3f complete=%s" % [
			held, cord.size(), length_sum, complete])
	if not complete:
		push_error("boat radio handset controller contract incomplete")
	quit(0 if complete else 1)
