extends RefCounted
class_name GripMap

const INTERACTION_MOTION := preload("res://scripts/hands/interaction_motion.gd")
const INTERACTION_BEHAVIOR := preload("res://scripts/hands/interaction_behavior.gd")
const HELD_OBJECT_FRAMER := preload("res://scripts/hands/held_object_framer.gd")
## The object's side of a hold. Hands do not invent a grip — they read this.
##
## A grip is a frame in the DEVICE's local space:
##   origin  palm contact
##   +Z      fingers
##   +Y      palm normal
## The grip node is parented to the device, so when the wheel turns or the
## radar swings the hand is welded by parentage, not by two animations agreeing.
##
## To add an interactable: one entry here (or a Grip child already on the
## node). Do not add a branch in hands.gd.

enum Kind { MODE, HOLD, GESTURE, SPECIAL }

const KNOB_R := 0.032
const HELM_RIM := 0.29
const FINGER := 0.095

## Shared door-handle approach: palm onto the leaf, fingers wrapping down.
const _DOOR_F := Vector3(0.0, -0.35, -0.94)
const _DOOR_P := Vector3(-0.94, -0.20, 0.0)

const SWITCH := {
	"node": "switch_lever",
	"node_uses_id": true,
	"kind": Kind.GESTURE,
	"pose": "point",
	"behavior": "toggle",
	"action": "toggle",
	"handed": true,
	"gesture": 0.64,
	"contact_at": 0.40,
	"approach": 0.085,
	"pos": Vector3(0.0, 0.064, 0.0),
	"fingers": Vector3(0.0, -0.92, -0.39),
	"palm": Vector3(-1.0, 0.0, 0.0),
	"along_fingers": FINGER,
}

const ENTRIES := {
	"helm": {
		"node": "helm_wheel",
		"kind": Kind.MODE,
		"pose": "rim",
		"behavior": "mode",
		"mode_property": "helm_engaged",
		"preferred": "L",
		"on_rim": true,
	},
	"telegraph": {
		"node": "throttle_lever",
		"kind": Kind.MODE,
		"pose": "power",
		"behavior": "mode",
		"mode_property": "telegraph_engaged",
		"preferred": "R",
		"pos": Vector3(0.0, 0.33, 0.0),
		"fingers": Vector3(0.0, -0.35, -0.94),
		# Right palm comes from the outboard side and faces inboard around the
		# knob; palm-down made the forearm perform an almost 180° roll.
		"palm": Vector3(-1.0, 0.0, 0.0),
		"palm_offset": KNOB_R,
	},
	"ignition": {
		"node": "ignition_key",
		"kind": Kind.GESTURE,
		"pose": "key",
		"behavior": "rotary_key",
		"action": "toggle",
		"preferred": "R",
		"gesture": 0.92,
		"contact_at": 0.36,
		"follow_motion": {"type": "hinge", "angle": 0.62,
				"min_time": 0.05, "timeout": 0.16},
		"approach": 0.075,
		"drops_instruments": true,
		"pos": Vector3(0.0, 0.020, 0.052),
		"fingers": Vector3(0.05, -0.96, -0.27),
		"palm": Vector3(-0.52, -0.20, 0.83),
	},
	"radio": {
		"node": "radio_handset",
		"kind": Kind.HOLD,
		"pose": "handset",
		"behavior": "handset",
		"action": "radio",
		"toggle_property": "radio_held",
		"toggle": true,
		"gesture": 0.58,
		"contact_at": 0.34,
		"approach": 0.090,
		"hold_after": true,
		"handed": true,
		"pos": Vector3(0.026, -0.004, 0.012),
		# The cradle is below and ahead of the shoulder; include that forward
		# component so pickup does not begin with a 66° wrist break.
		"fingers": Vector3(0.12, -0.85, -0.51),
		"palm": Vector3(-1.0, 0.0, 0.0),
		# Persistent holds live in camera space after contact. The same contract is
		# used by future torches, weapons and tools: all visible geometry plus the
		# gripping hand stays inside the safe frame and outside the reticle lane.
		"held_frame": {
			# Deliberately inside the theoretical frustum clamp. The solved shoulder
			# and wrist may contribute a few millimetres after IK; this reserve keeps
			# the hand/object weld inside the frame even during a sharp head turn.
			"anchor": Vector3(0.070, -0.125, -0.275),
			"device_x": Vector3(0.94, 0.19, -0.28),
			"device_z": Vector3(0.11, -0.90, -0.42),
			"focus_point": Vector3(0.026, -0.004, 0.012),
			"safe_margin": Vector2(0.05, 0.06),
			"hand_radius": Vector2(0.035, 0.045),
			"center_keepout": 0.18,
			"depth_range": Vector2(0.24, 0.52),
			"mirror_left": true,
			"smoothing": 18.0,
			"lock_property": "radio_pose_locked",
		},
	},
	"deckbag": {
		"node": "deck_bag_node",
		"kind": Kind.MODE,
		"pose": "bag_handle",
		"behavior": "shoulder_bag",
		"preferred": "L",
		# A loaded fabric handle is not a rigid machine control.  Keep the palm on
		# the real handle but allow the grasp solver to align the wrist with the
		# approaching forearm; the curled finger pose supplies the wrap around it.
		"welded": false,
		# The bag owns its shoulder-to-lap camera arc.  The hand follows this
		# authored handle and must not be remapped through the boat interpolation.
		"camera_space": true,
		"pos": Vector3(0.0, 0.292, 0.0),
		"fingers": Vector3(0.0, -1.0, 0.0),
		"palm": Vector3(0.0, 0.0, -1.0),
	},
	"radar": {
		"node": "radar_housing",
		"kind": Kind.GESTURE,
		"pose": "hook",
		"behavior": "linear_pull",
		"action": "rail",
		"gesture": 0.76,
		"contact_at": 0.34,
		"approach": 0.090,
		"rail": "radar",
		"exclusive_rails": ["radar", "sounder"],
		"span": true,
		"pos": Vector3(0.205, -0.05, 0.06),
		"fingers": Vector3(0.0, 0.05, -1.0),
		"palm": Vector3(-1.0, 0.0, 0.0),
	},
	"sounder": {
		"node": "sounder_housing",
		"kind": Kind.GESTURE,
		"pose": "hook",
		"behavior": "linear_pull",
		"action": "rail",
		"gesture": 0.76,
		"contact_at": 0.34,
		"approach": 0.090,
		"rail": "sounder",
		"exclusive_rails": ["radar", "sounder"],
		"span": true,
		"pos": Vector3(0.185, -0.03, 0.05),
		"fingers": Vector3(0.0, 0.05, -1.0),
		"palm": Vector3(-1.0, 0.0, 0.0),
	},
	"stove": {
		"node": "stove_switch",
		"kind": Kind.GESTURE,
		"pose": "point",
		"behavior": "toggle",
		"action": "toggle",
		"gesture": 0.62,
		"contact_at": 0.40,
		"approach": 0.075,
		"handed": true,
		"pos": Vector3(0.0, 0.018, 0.0),
		"fingers": Vector3(0.0, -0.94, -0.34),
		"palm": Vector3(-1.0, 0.0, 0.0),
		"along_fingers": FINGER,
	},
	"windlass": {
		"node": "windlass_node",
		"kind": Kind.GESTURE,
		"pose": "power",
		"behavior": "crank",
		"action": "tackle",
		"action_property": "tackle",
		"gesture": 0.84,
		"contact_at": 0.38,
		"approach": 0.10,
		"handed": true,
		"drops_instruments": true,
		"pos": Vector3(0.30, 0.10, 0.0),
		"fingers": _DOOR_F,
		"palm": _DOOR_P,
	},
	"fusebox": {
		"node": "fuse_lid",
		"kind": Kind.GESTURE,
		"pose": "pinch",
		"behavior": "hinge_light",
		"action": "toggle",
		"gesture": 0.86,
		"contact_at": 0.38,
		# Follow the real hinge until the fingers have lifted it through a useful
		# arc.  This is a motion contract, not a fuse-box animation timer.
		"follow_motion": {"type": "hinge", "angle": 0.74,
				"min_time": 0.05, "timeout": 0.15},
		"approach": 0.085,
		"drops_instruments": true,
		"contact_accessor": "fuse_latch_local",
		# Reach from the inboard aisle and pinch the 40 mm brass catch. The grip
		# origin is the palm; along_fingers leaves the actual touch at the tips.
		"pos": Vector3.ZERO,
		"fingers": Vector3(0.99, -0.12, 0.0),
		# Palm faces down; approach therefore comes from above the closed lid.
		"palm": Vector3(-0.12, -0.99, 0.0),
		"along_fingers": 0.075,
	},
	"locker": {
		"node": "locker_door",
		"kind": Kind.GESTURE,
		"pose": "handle",
		"behavior": "hinge_medium",
		"action": "toggle",
		"gesture": 0.90,
		"contact_at": 0.36,
		"approach": 0.10,
		"follow_motion": {"type": "hinge", "angle": 0.44,
				"min_time": 0.05, "timeout": 0.17},
		"handed": true,
		"drops_instruments": true,
		"pos": Vector3(0.03, 0.10, 0.41),
		"fingers": _DOOR_F,
		"palm": _DOOR_P,
	},
	"fu_cabin": {
		"node": "fuse_body",
		"node_uses_id": true,
		"kind": Kind.GESTURE,
		"pose": "pinch",
		"behavior": "pinch_pull",
		"action": "toggle",
		"gesture": 0.72,
		"contact_at": 0.40,
		"approach": 0.070,
		"handed": true,
		"gate": "fusebox",
		"pos": Vector3.ZERO,
		"fingers": Vector3(0.0, -0.92, -0.39),
		"palm": Vector3(-1.0, 0.0, 0.0),
		"along_fingers": FINGER,
	},
	"door_fwd": {
		"node": "door_node",
		"node_uses_id": true,
		"kind": Kind.GESTURE,
		"pose": "handle",
		"behavior": "hinge_medium",
		"action": "toggle",
		"gesture": 0.92,
		"contact_at": 0.34,
		"approach": 0.095,
		"follow_motion": {"type": "hinge", "angle": 0.40,
				"min_time": 0.05, "timeout": 0.16},
		"handed": true,
		"drops_instruments": true,
		"latch": true,
		"contact_accessor": "door_latch_local",
		"contact_uses_id": true,
		"pos": Vector3(1.02, 1.58, -0.072),
		"fingers": _DOOR_F,
		"palm": _DOOR_P,
	},
	"door_aft": {
		"node": "door_node",
		"node_uses_id": true,
		"kind": Kind.GESTURE,
		"pose": "handle",
		"behavior": "hinge_medium",
		"action": "toggle",
		"gesture": 0.92,
		"contact_at": 0.34,
		"approach": 0.095,
		"follow_motion": {"type": "hinge", "angle": 0.40,
				"min_time": 0.05, "timeout": 0.16},
		"handed": true,
		"drops_instruments": true,
		"latch": true,
		"contact_accessor": "door_latch_local",
		"contact_uses_id": true,
		"pos": Vector3(1.02, 1.58, 0.072),
		"fingers": _DOOR_F,
		"palm": _DOOR_P,
	},
	"door_wh": {
		"node": "door_node",
		"node_uses_id": true,
		"kind": Kind.GESTURE,
		"pose": "handle",
		"behavior": "hinge_medium",
		"action": "toggle",
		"gesture": 0.92,
		"contact_at": 0.34,
		"approach": 0.095,
		"follow_motion": {"type": "hinge", "angle": 0.40,
				"min_time": 0.05, "timeout": 0.16},
		"handed": true,
		"drops_instruments": true,
		"latch": true,
		"contact_accessor": "door_latch_local",
		"contact_uses_id": true,
		"pos": Vector3(-0.98, 0.92, 0.072),
		"fingers": _DOOR_F,
		"palm": _DOOR_P,
	},
	"door_eng": {
		"node": "engine_door",
		"kind": Kind.GESTURE,
		"pose": "hook",
		"behavior": "hinge_medium",
		"action": "toggle",
		"gesture": 0.90,
		"contact_at": 0.36,
		"approach": 0.090,
		"follow_motion": {"type": "hinge", "angle": 0.40,
				"min_time": 0.05, "timeout": 0.16},
		"handed": true,
		"drops_instruments": true,
		"pos": Vector3(-0.07, -0.08, 1.10),
		"fingers": _DOOR_F,
		"palm": _DOOR_P,
	},
	"chart": {
		"kind": Kind.SPECIAL,
		"behavior": "chart",
		"special": "mode",
		"mode_property": "chart_engaged",
	},
	"sea_ladder": {
		"kind": Kind.SPECIAL,
		"behavior": "climb",
		"special": "ladder",
	},
	"divegear": {
		"kind": Kind.SPECIAL,
		"behavior": "wear",
		"special": "wear",
	},
}


static func spec_for(id: String) -> Dictionary:
	if ENTRIES.has(id):
		return ENTRIES[id]
	if id.begins_with("sw_"):
		if id == "sw_cabin" or id == "sw_helm" or id == "sw_beacon" \
				or id == "sw_anchor":
			var well: Dictionary = SWITCH.duplicate()
			well["gate"] = "fusebox"
			return well
		return SWITCH
	if id.begins_with("fu_"):
		var fuse: Dictionary = ENTRIES.get("fu_cabin", {}).duplicate()
		if fuse.is_empty():
			return {}
		return fuse
	return {}


static func validation_error(spec: Dictionary) -> String:
	## Fail closed.  A malformed frame must never become an identity transform
	## that sends a hand to the device origin and still fires gameplay.
	var behavior_error := INTERACTION_BEHAVIOR.validation_error(spec)
	if behavior_error != "":
		return behavior_error
	if int(spec.get("kind", Kind.GESTURE)) == Kind.SPECIAL:
		return "" if str(spec.get("special", "")) != "" else "missing special driver"
	if str(spec.get("node", "")) == "":
		return "missing device accessor"
	if str(spec.get("pose", "")) == "":
		return "missing finger profile"
	if int(spec.get("kind", Kind.GESTURE)) == Kind.HOLD:
		var frame_error := HELD_OBJECT_FRAMER.validation_error(
				spec.get("held_frame", {}) as Dictionary)
		if frame_error != "":
			return frame_error
	if not bool(spec.get("on_rim", false)):
		var f: Vector3 = spec.get("fingers", Vector3.ZERO)
		var p: Vector3 = spec.get("palm", Vector3.ZERO)
		if f.length_squared() < 0.25 or p.length_squared() < 0.25:
			return "degenerate finger/palm axis"
		if absf(f.normalized().dot(p.normalized())) > 0.96:
			return "finger and palm axes are nearly parallel"
	var duration := float(spec.get("gesture", 0.0))
	if duration > 0.0:
		var action := str(spec.get("action", ""))
		if action == "":
			return "gesture has no gameplay action"
		if action not in ["toggle", "radio", "rail", "tackle"]:
			return "unsupported gameplay action"
		var contact := float(spec.get("contact_at", -1.0))
		if contact < 0.10 or contact > 0.80:
			return "contact phase outside gesture"
	var follow: Dictionary = spec.get("follow_motion", {})
	var motion_error := INTERACTION_MOTION.validation_error(follow)
	if motion_error != "":
		return motion_error
	if not follow.is_empty():
		var physical_motion := str(INTERACTION_BEHAVIOR.profile(spec).get("motion", ""))
		var follow_type := str(follow.get("type", ""))
		if physical_motion != follow_type \
				and not (physical_motion == "rotary" and follow_type == "hinge"):
			return "follow motion disagrees with physical behavior"
	return ""


static func welded(spec: Dictionary) -> bool:
	if spec.has("welded"):
		return bool(spec.get("welded", false))
	var k: int = int(spec.get("kind", Kind.GESTURE))
	return k == Kind.MODE or k == Kind.HOLD or bool(spec.get("on_rim", false))


## A span has two holds, one on each flank. The catalog stores the RIGHT
## edge; the left is that frame mirrored through the device's X.
static func sided(spec: Dictionary, side: String) -> Dictionary:
	if side != "L" or not (bool(spec.get("span", false)) \
			or bool(spec.get("handed", false))):
		return spec
	var out: Dictionary = spec.duplicate()
	var pos: Vector3 = spec.get("pos", Vector3.ZERO)
	var F: Vector3 = spec.get("fingers", Vector3(0.0, 0.0, -1.0))
	var P: Vector3 = spec.get("palm", Vector3(0.0, -1.0, 0.0))
	if bool(spec.get("span", false)):
		out["pos"] = Vector3(-pos.x, pos.y, pos.z)
	out["fingers"] = Vector3(-F.x, F.y, F.z)
	out["palm"] = Vector3(-P.x, P.y, P.z)
	return out


static func local_frame(spec: Dictionary, contact: Vector3) -> Transform3D:
	var F: Vector3 = (spec.get("fingers", Vector3(0.0, 0.0, -1.0)) as Vector3).normalized()
	var P: Vector3 = spec.get("palm", Vector3(0.0, -1.0, 0.0)) as Vector3
	P = (P - P.project(F)).normalized()
	if P.length_squared() < 0.25:
		return Transform3D(Basis.IDENTITY, contact)
	var pos: Vector3 = contact
	pos -= P * float(spec.get("palm_offset", 0.0))
	pos -= F * float(spec.get("along_fingers", 0.0))
	return Transform3D(Basis(P.cross(F), P, F), pos)


static func contact_of(spec: Dictionary, boat: Node3D, id: String) -> Vector3:
	var pos: Vector3 = spec.get("pos", Vector3.ZERO)
	var contact_accessor := str(spec.get("contact_accessor", ""))
	if contact_accessor != "" and boat != null and boat.has_method(contact_accessor):
		var dynamic_contact: Variant = boat.call(contact_accessor, id) \
				if bool(spec.get("contact_uses_id", false)) \
				else boat.call(contact_accessor)
		if dynamic_contact is Vector3:
			return dynamic_contact
	return pos


static func oriented_at_contact(spec: Dictionary, contact: Vector3) -> Dictionary:
	## A door handle is used from both faces of the leaf.  The latch point already
	## changes face; its semantic frame must mirror with it or the fingers arrive
	## through the steel from the opposite room.
	if not bool(spec.get("latch", false)):
		return spec
	var authored: Vector3 = spec.get("pos", contact)
	if absf(authored.z) < 1e-5 or absf(contact.z) < 1e-5 \
			or signf(authored.z) == signf(contact.z):
		return spec
	var out := spec.duplicate()
	var f: Vector3 = spec.get("fingers", Vector3.FORWARD)
	var p: Vector3 = spec.get("palm", Vector3.DOWN)
	out["fingers"] = Vector3(f.x, f.y, -f.z)
	out["palm"] = Vector3(p.x, p.y, -p.z)
	return out


static func device_of(boat: Node3D, id: String) -> Node3D:
	if boat == null:
		return null
	var spec: Dictionary = spec_for(id)
	var acc: String = str(spec.get("node", ""))
	if acc == "":
		return null
	if not boat.has_method(acc):
		return null
	if bool(spec.get("node_uses_id", false)):
		return boat.call(acc, id) as Node3D
	return boat.call(acc) as Node3D
