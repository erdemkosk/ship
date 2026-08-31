extends RefCounted
class_name InteractionBehavior
## Data-only physical semantics shared by planning, animation and validation.

const PROFILES := {
	"mode": {"motion": "hold", "mass_kg": 0.0, "force_n": 8.0,
			"min_hands": 1, "body_commit": 0.15, "gaze_weight": 0.35},
	"rotary_key": {"motion": "rotary", "mass_kg": 0.05, "force_n": 4.0,
			"min_hands": 1, "body_commit": 0.08, "gaze_weight": 0.75},
	"toggle": {"motion": "toggle", "mass_kg": 0.03, "force_n": 3.0,
			"min_hands": 1, "body_commit": 0.05, "gaze_weight": 0.80},
	"pinch_pull": {"motion": "linear", "mass_kg": 0.08, "force_n": 9.0,
			"min_hands": 1, "body_commit": 0.12, "gaze_weight": 0.65},
	"linear_pull": {"motion": "linear", "mass_kg": 1.5, "force_n": 18.0,
			"min_hands": 1, "body_commit": 0.32, "gaze_weight": 0.45},
	"hinge_light": {"motion": "hinge", "mass_kg": 1.2, "force_n": 16.0,
			"min_hands": 1, "body_commit": 0.30, "gaze_weight": 0.50},
	"hinge_medium": {"motion": "hinge", "mass_kg": 5.0, "force_n": 38.0,
			"min_hands": 1, "body_commit": 0.62, "gaze_weight": 0.40},
	"handset": {"motion": "carry", "mass_kg": 0.45, "force_n": 7.0,
			"min_hands": 1, "body_commit": 0.12, "gaze_weight": 0.30},
	"crank": {"motion": "rotary", "mass_kg": 7.0, "force_n": 52.0,
			"min_hands": 1, "body_commit": 0.82, "gaze_weight": 0.30},
	"heavy_lift": {"motion": "lift", "mass_kg": 14.0, "force_n": 120.0,
			"min_hands": 2, "body_commit": 1.0, "gaze_weight": 0.25},
	"chart": {"motion": "inspect", "mass_kg": 0.0, "force_n": 0.0,
			"min_hands": 0, "body_commit": 0.35, "gaze_weight": 0.0},
	"climb": {"motion": "climb", "mass_kg": 75.0, "force_n": 260.0,
			"min_hands": 2, "body_commit": 1.0, "gaze_weight": 0.15},
	"wear": {"motion": "wear", "mass_kg": 4.0, "force_n": 18.0,
			"min_hands": 2, "body_commit": 0.55, "gaze_weight": 0.20},
}


static func profile(spec: Dictionary) -> Dictionary:
	var name := str(spec.get("behavior", ""))
	return (PROFILES.get(name, {}) as Dictionary).duplicate()


static func validation_error(spec: Dictionary) -> String:
	var name := str(spec.get("behavior", ""))
	if name == "":
		return "missing physical behavior"
	if not PROFILES.has(name):
		return "unknown physical behavior '%s'" % name
	var data: Dictionary = PROFILES[name]
	var hands := int(data.get("min_hands", -1))
	if hands < 0 or hands > 2:
		return "invalid hand count"
	if float(data.get("mass_kg", -1.0)) < 0.0 \
			or float(data.get("force_n", -1.0)) < 0.0:
		return "invalid load"
	if hands == 2 and str(spec.get("special", "")) == "" \
			and not bool(spec.get("span", false)):
		return "two-hand load requires a span grip"
	if hands == 2 and str(spec.get("special", "")) == "" \
			and float(spec.get("gesture", 0.0)) <= 0.0:
		return "two-hand load requires a contact gesture"
	if float(data.get("force_n", 0.0)) > 30.0 \
			and str(spec.get("pose", "")) in ["point", "pinch"]:
		return "high load cannot use a fingertip grip"
	return ""


static func load_cost(spec: Dictionary, side_count := 1) -> float:
	var data := profile(spec)
	if data.is_empty():
		return INF
	if side_count < int(data.get("min_hands", 1)):
		return INF
	var force := float(data.get("force_n", 0.0)) / maxf(float(side_count), 1.0)
	return force / 90.0 + float(data.get("body_commit", 0.0)) * 0.35
