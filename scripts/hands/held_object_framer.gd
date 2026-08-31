extends RefCounted
class_name HeldObjectFramer

## Camera-space carrier for things which stay in a hand (radio, torch, weapon,
## tool).  The grip still belongs to the object; this class only decides where
## the object/hand pair may live in the view.  Consequently a new carried item
## supplies data in GripMap and does not need a branch in hands.gd.


static func validation_error(frame: Dictionary) -> String:
	if frame.is_empty():
		return "held object has no camera frame"
	var anchor: Vector3 = frame.get("anchor", Vector3.ZERO)
	if not anchor.is_finite() or anchor.z >= -0.08:
		return "held camera anchor must be in front of the eye"
	var x_axis: Vector3 = frame.get("device_x", Vector3.ZERO)
	var z_axis: Vector3 = frame.get("device_z", Vector3.ZERO)
	if x_axis.length_squared() < 0.25 or z_axis.length_squared() < 0.25:
		return "held object has a degenerate camera basis"
	if absf(x_axis.normalized().dot(z_axis.normalized())) > 0.94:
		return "held object camera axes are nearly parallel"
	var margin: Vector2 = frame.get("safe_margin", Vector2(0.08, 0.08))
	if margin.x < 0.0 or margin.y < 0.0 or margin.x >= 0.45 or margin.y >= 0.45:
		return "held object safe margin is outside the view"
	var depths: Vector2 = frame.get("depth_range", Vector2(0.20, 0.70))
	if depths.x < 0.08 or depths.y <= depths.x:
		return "held object depth range is invalid"
	var hand_radius: Vector2 = frame.get("hand_radius", Vector2(0.045, 0.055))
	if hand_radius.x < 0.0 or hand_radius.y < 0.0:
		return "held hand clearance cannot be negative"
	return ""


static func camera_basis(frame: Dictionary, side: String) -> Basis:
	var x_axis: Vector3 = frame.get("device_x", Vector3.RIGHT)
	var z_axis: Vector3 = frame.get("device_z", Vector3.BACK)
	if side == "L" and bool(frame.get("mirror_left", true)):
		x_axis.x = -x_axis.x
		z_axis.x = -z_axis.x
	z_axis = z_axis.normalized()
	# Authoring only asks for two meaningful axes. Rebuilding the third and then
	# the first produces a proper orthonormal rotation even for a mirrored hold.
	var y_axis := z_axis.cross(x_axis).normalized()
	x_axis = y_axis.cross(z_axis).normalized()
	return Basis(x_axis, y_axis, z_axis).orthonormalized()


static func solve_local(frame: Dictionary, side: String, fov_degrees: float,
		aspect: float, local_points: Array[Vector3] = []) -> Transform3D:
	## Returns DEVICE -> CAMERA transform. Every supplied visual point plus a
	## palm-sized clearance around focus_point is kept inside the safe frustum.
	var basis := camera_basis(frame, side)
	var origin: Vector3 = frame.get("anchor", Vector3(0.20, -0.12, -0.30))
	if side == "L" and bool(frame.get("mirror_left", true)):
		origin.x = -origin.x
	var depth_range: Vector2 = frame.get("depth_range", Vector2(0.20, 0.70))
	origin.z = -clampf(-origin.z, depth_range.x, depth_range.y)
	var points := local_points
	if points.is_empty():
		points = [Vector3.ZERO]
	var margin: Vector2 = frame.get("safe_margin", Vector2(0.08, 0.08))
	var hand_radius: Vector2 = frame.get("hand_radius", Vector2(0.045, 0.055))
	var tan_half := tan(deg_to_rad(clampf(fov_degrees, 20.0, 130.0)) * 0.5)
	var safe_x := 1.0 - margin.x
	var safe_y := 1.0 - margin.y
	var lo_x := -INF
	var hi_x := INF
	var lo_y := -INF
	var hi_y := INF
	# Perspective matters for a long object aimed into the scene: its near end
	# can be twice the apparent size of its origin. Search backwards within the
	# authored range until the complete hull has a legal X/Y interval.
	var requested_depth := -origin.z
	for depth_step in 17:
		var sample_depth := lerpf(requested_depth, depth_range.y,
				float(depth_step) / 16.0)
		origin.z = -sample_depth
		lo_x = -INF
		hi_x = INF
		lo_y = -INF
		hi_y = INF
		for local_point: Vector3 in points:
			var q := basis * local_point
			var depth := maxf(-(origin.z + q.z), 0.081)
			var half_h := depth * tan_half
			var half_w := half_h * maxf(aspect, 0.25)
			lo_x = maxf(lo_x, -safe_x * half_w + hand_radius.x - q.x)
			hi_x = minf(hi_x, safe_x * half_w - hand_radius.x - q.x)
			lo_y = maxf(lo_y, -safe_y * half_h + hand_radius.y - q.y)
			hi_y = minf(hi_y, safe_y * half_h - hand_radius.y - q.y)
		if lo_x <= hi_x and lo_y <= hi_y:
			break
	# An exceptionally wide mesh may not fit at the requested depth. Preserve its
	# side and centre instead of producing NaNs; authored tests report the miss.
	origin.x = clampf(origin.x, lo_x, hi_x) if lo_x <= hi_x else (lo_x + hi_x) * 0.5
	origin.y = clampf(origin.y, lo_y, hi_y) if lo_y <= hi_y else (lo_y + hi_y) * 0.5

	# Keep the sight/interaction centre readable. This is evaluated at the palm
	# focus, not at the model origin, so a long tool cannot put the hand over the
	# reticle while its geometry happens to sit off-centre.
	var focus: Vector3 = frame.get("focus_point", Vector3.ZERO)
	var fq := basis * focus
	var focus_depth := maxf(-(origin.z + fq.z), 0.081)
	var focus_half_w := focus_depth * tan_half * maxf(aspect, 0.25)
	var keepout := clampf(float(frame.get("center_keepout", 0.16)), 0.0, safe_x)
	if keepout > 0.0:
		var desired_focus_x := keepout * focus_half_w * (1.0 if side == "R" else -1.0)
		var desired_origin_x := desired_focus_x - fq.x
		if side == "R" and origin.x + fq.x < desired_focus_x:
			origin.x = minf(maxf(desired_origin_x, lo_x), hi_x)
		elif side == "L" and origin.x + fq.x > desired_focus_x:
			origin.x = maxf(minf(desired_origin_x, hi_x), lo_x)
	return Transform3D(basis, origin)


static func report(local_xf: Transform3D, frame: Dictionary,
		fov_degrees: float, aspect: float,
		local_points: Array[Vector3] = []) -> Dictionary:
	var points := local_points
	if points.is_empty():
		points = [Vector3.ZERO]
	var margin: Vector2 = frame.get("safe_margin", Vector2(0.08, 0.08))
	var hand_radius: Vector2 = frame.get("hand_radius", Vector2(0.045, 0.055))
	var tan_half := tan(deg_to_rad(clampf(fov_degrees, 20.0, 130.0)) * 0.5)
	var aspect_safe := maxf(aspect, 0.25)
	var max_x := 0.0
	var max_y := 0.0
	var visible := true
	for local_point: Vector3 in points:
		var p := local_xf * local_point
		var depth := -p.z
		if depth <= 0.08:
			visible = false
			continue
		var half_h := depth * tan_half
		var half_w := half_h * aspect_safe
		max_x = maxf(max_x, (absf(p.x) + hand_radius.x) / half_w)
		max_y = maxf(max_y, (absf(p.y) + hand_radius.y) / half_h)
		if (absf(p.x) + hand_radius.x) / half_w > 1.0 - margin.x + 0.002 \
				or (absf(p.y) + hand_radius.y) / half_h > 1.0 - margin.y + 0.002:
			visible = false
	var focus: Vector3 = local_xf * (frame.get("focus_point", Vector3.ZERO) as Vector3)
	var focus_depth := maxf(-focus.z, 0.081)
	var focus_ndc_x := focus.x / (focus_depth * tan_half * aspect_safe)
	var keepout := float(frame.get("center_keepout", 0.16))
	return {
		"visible": visible,
		"max_ndc": Vector2(max_x, max_y),
		"focus_ndc_x": focus_ndc_x,
		"center_clear": absf(focus_ndc_x) + 0.002 >= keepout,
		"camera_local": local_xf,
	}
