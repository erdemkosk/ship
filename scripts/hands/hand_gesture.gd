extends RefCounted
class_name HandGesture
## Typed lifecycle state for one hand-authored interaction.

var id: String
var t := 0.0
var duration: float
var contact_at: float
var fired := false
var hold_after: bool
var release_after: bool
var approach: float
var follow_motion: Dictionary
var motion_start: Dictionary


func _init(p_id: String, spec: Dictionary, p_release_after: bool,
		p_motion_start: Dictionary) -> void:
	id = p_id
	duration = maxf(float(spec.get("gesture", 0.0)), 0.05)
	contact_at = clampf(float(spec.get("contact_at", 0.38)), 0.12, 0.78)
	hold_after = bool(spec.get("hold_after", false))
	release_after = p_release_after
	approach = maxf(float(spec.get("approach", 0.08)), 0.0)
	follow_motion = spec.get("follow_motion", {})
	motion_start = p_motion_start


func phase() -> float:
	return t / maxf(duration, 1e-4)


func after_contact() -> float:
	return t - duration * contact_at
