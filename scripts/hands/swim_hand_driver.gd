extends RefCounted
class_name SwimHandDriver
## Camera-space front-crawl cycle used while the player is freely swimming.

var _time := 0.0


func advance(delta: float) -> void:
	_time += delta


func drive(side: String, camera: Camera3D, rig: Node) -> Vector3:
	# Each arm pulls through the lower third and recovers outboard. Treading
	# follows the same path more slowly, keeping the transition continuous.
	var c: Transform3D = camera.global_transform
	var out: float = 1.0 if side == "R" else -1.0
	var move := Input.get_vector("boat_left", "boat_right",
			"boat_backward", "boat_forward")
	var rate := lerpf(1.35, 2.55, clampf(move.length(), 0.0, 1.0))
	var phase: float = _time * rate + (0.0 if side == "R" else PI)
	var pull := sin(phase)
	var recovery := cos(phase)
	var x: float = out * (0.20 + (1.0 - absf(pull)) * 0.06)
	var y: float = -0.26 + recovery * 0.09
	var z: float = -0.30 - pull * 0.14
	var contact: Vector3 = c * Vector3(x, y, z)
	var fingers: Vector3 = c.basis * Vector3(
			out * 0.18, -0.22 - pull * 0.15, -0.96)
	var palm: Vector3 = c.basis * Vector3(out * 0.08, -0.92, 0.18)
	var hold: float = clampf(0.25 + pull * 0.35, 0.12, 0.7)
	rig.grip(side, contact, fingers, palm, 1.0, "open", hold)
	return contact
