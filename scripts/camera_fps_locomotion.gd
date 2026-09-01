class_name CameraFpsLocomotion
extends RefCounted
## Station foot locking and boat-local walking/swimming input routing.


func update(delta: float, target, walker, engaged: String,
		boat_transform: Transform3D, look_forward: Vector3,
		look_right: Vector3, panel_open: bool, bag_focus: float,
		stair_step_callback: Callable) -> void:
	if engaged == "helm":
		walker.call("spawn_at", target.HELM_STAND)
		return
	if engaged == "telegraph":
		walker.call("spawn_at", target.TELEGRAPH_STAND)
		return
	if engaged == "chart":
		walker.call("spawn_at", target.CHART_STAND)
		return
	var local_forward: Vector3 = boat_transform.basis.inverse() * look_forward
	var local_right: Vector3 = boat_transform.basis.inverse() * look_right
	var forward_2d := Vector2(local_forward.x, local_forward.z)
	var right_2d := Vector2(local_right.x, local_right.z)
	if forward_2d.length_squared() > 1.0e-5:
		forward_2d = forward_2d.normalized()
	if right_2d.length_squared() > 1.0e-5:
		right_2d = right_2d.normalized()
	var wish := Vector2.ZERO
	var axes := Vector2.ZERO
	if not panel_open:
		wish = forward_2d * Input.get_axis("boat_backward", "boat_forward") \
				+ right_2d * Input.get_axis("boat_left", "boat_right")
		if wish.length() > 1.0:
			wish = wish.normalized()
		axes = Vector2(Input.get_axis("boat_left", "boat_right"),
				Input.get_axis("boat_backward", "boat_forward"))
		var input_scale := 0.0 if bag_focus > 0.55 \
				else lerpf(1.0, 0.28, bag_focus)
		wish *= input_scale
		axes *= input_scale
	walker.call("update", delta, target, wish,
			Input.is_action_just_pressed("jump") and not panel_open \
					and bag_focus < 0.08,
			look_forward, axes,
			Input.is_action_pressed("jump") and not panel_open \
					and bag_focus < 0.08,
			Input.is_action_pressed("dive") and not panel_open)
	stair_step_callback.call()
