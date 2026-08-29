extends RefCounted
class_name GripMap
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

enum Kind { MODE, HOLD, GESTURE }

const KNOB_R := 0.032
const HELM_RIM := 0.29
const FINGER := 0.095

## Shared door-handle approach: palm onto the leaf, fingers wrapping down.
const _DOOR_F := Vector3(0.0, -0.35, -0.94)
const _DOOR_P := Vector3(-0.94, -0.20, 0.0)

const SWITCH := {
	"node": "switch_lever",
	"kind": Kind.GESTURE,
	"pose": "point",
	"oneshot": 1.05,
	"gate": "fusebox",
	"pos": Vector3(0.0, 0.064, 0.0),
	"fingers": Vector3(0.0, -0.92, -0.39),
	"palm": Vector3(0.0, -0.39, 0.92),
	"along_fingers": FINGER,
}

const ENTRIES := {
	"helm": {
		"node": "helm_wheel",
		"kind": Kind.MODE,
		"pose": "wrap",
		"preferred": "L",
		"on_rim": true,
	},
	"telegraph": {
		"node": "throttle_lever",
		"kind": Kind.MODE,
		"pose": "fist",
		"preferred": "R",
		"pos": Vector3(0.0, 0.33, 0.0),
		"fingers": Vector3(0.0, -0.35, -0.94),
		"palm": Vector3(0.0, -0.94, 0.35),
		"palm_offset": KNOB_R,
	},
	"ignition": {
		"node": "ignition_key",
		"kind": Kind.GESTURE,
		"pose": "pinch",
		"preferred": "R",
		"oneshot": 1.15,
		"drops_instruments": true,
		"pos": Vector3(0.0, 0.020, 0.052),
		"fingers": Vector3(0.05, -0.96, -0.27),
		"palm": Vector3(-0.52, -0.20, 0.83),
	},
	"radio": {
		"node": "radio_handset",
		"kind": Kind.HOLD,
		"pose": "wrap",
		"toggle": true,
		"pos": Vector3(0.026, -0.004, 0.012),
		"fingers": Vector3(0.15, -0.99, 0.0),
		"palm": Vector3(-1.0, 0.0, 0.0),
	},
	"radar": {
		"node": "radar_housing",
		"kind": Kind.GESTURE,
		"pose": "wrap",
		"oneshot": 0.7,
		"rail": "radar",
		"span": true,
		"pos": Vector3(0.205, -0.05, 0.06),
		"fingers": Vector3(0.0, 0.05, -1.0),
		"palm": Vector3(-1.0, 0.0, 0.0),
	},
	"sounder": {
		"node": "sounder_housing",
		"kind": Kind.GESTURE,
		"pose": "wrap",
		"oneshot": 0.7,
		"rail": "sounder",
		"span": true,
		"pos": Vector3(0.185, -0.03, 0.05),
		"fingers": Vector3(0.0, 0.05, -1.0),
		"palm": Vector3(-1.0, 0.0, 0.0),
	},
	"windlass": {
		"node": "windlass_node",
		"kind": Kind.GESTURE,
		"pose": "fist",
		"oneshot": 0.85,
		"drops_instruments": true,
		"pos": Vector3(0.30, 0.10, 0.0),
		"fingers": _DOOR_F,
		"palm": _DOOR_P,
	},
	"fusebox": {
		"node": "fuse_lid",
		"kind": Kind.GESTURE,
		"pose": "wrap",
		"oneshot": 0.85,
		"drops_instruments": true,
		"pos": Vector3(0.0, 0.13, 0.77),
		"fingers": _DOOR_F,
		"palm": _DOOR_P,
	},
	"locker": {
		"node": "locker_door",
		"kind": Kind.GESTURE,
		"pose": "wrap",
		"oneshot": 0.85,
		"drops_instruments": true,
		"pos": Vector3(0.03, 0.10, 0.41),
		"fingers": _DOOR_F,
		"palm": _DOOR_P,
	},
	"door_fwd": {
		"node": "door_node",
		"kind": Kind.GESTURE,
		"pose": "pinch",
		"oneshot": 0.85,
		"drops_instruments": true,
		"latch": true,
		"pos": Vector3(1.02, 1.58, -0.072),
		"fingers": _DOOR_F,
		"palm": _DOOR_P,
	},
	"door_aft": {
		"node": "door_node",
		"kind": Kind.GESTURE,
		"pose": "pinch",
		"oneshot": 0.85,
		"drops_instruments": true,
		"latch": true,
		"pos": Vector3(1.02, 1.58, 0.072),
		"fingers": _DOOR_F,
		"palm": _DOOR_P,
	},
	"door_wh": {
		"node": "door_node",
		"kind": Kind.GESTURE,
		"pose": "pinch",
		"oneshot": 0.85,
		"drops_instruments": true,
		"latch": true,
		"pos": Vector3(-0.98, 0.92, 0.072),
		"fingers": _DOOR_F,
		"palm": _DOOR_P,
	},
	"door_eng": {
		"node": "engine_door",
		"kind": Kind.GESTURE,
		"pose": "wrap",
		"oneshot": 0.85,
		"drops_instruments": true,
		"pos": Vector3(-0.07, -0.08, 1.10),
		"fingers": _DOOR_F,
		"palm": _DOOR_P,
	},
}


static func spec_for(id: String) -> Dictionary:
	if ENTRIES.has(id):
		return ENTRIES[id]
	if id.begins_with("sw_"):
		return SWITCH
	return {}


static func welded(spec: Dictionary) -> bool:
	var k: int = int(spec.get("kind", Kind.GESTURE))
	return k == Kind.MODE or k == Kind.HOLD or bool(spec.get("on_rim", false))


## A span has two holds, one on each flank. The catalog stores the RIGHT
## edge; the left is that frame mirrored through the device's X.
static func sided(spec: Dictionary, side: String) -> Dictionary:
	if side != "L" or not bool(spec.get("span", false)):
		return spec
	var out: Dictionary = spec.duplicate()
	var pos: Vector3 = spec.get("pos", Vector3.ZERO)
	var F: Vector3 = spec.get("fingers", Vector3(0.0, 0.0, -1.0))
	var P: Vector3 = spec.get("palm", Vector3(0.0, -1.0, 0.0))
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
	if bool(spec.get("latch", false)) and boat != null \
			and boat.has_method("door_latch_local"):
		pos = boat.call("door_latch_local", id)
	return pos


static func device_of(boat: Node3D, id: String) -> Node3D:
	if boat == null:
		return null
	var spec: Dictionary = spec_for(id)
	var acc: String = str(spec.get("node", ""))
	if acc == "":
		return null
	if acc == "switch_lever":
		return boat.call("switch_lever", id) as Node3D
	if acc == "door_node":
		return boat.call("door_node", id) as Node3D
	if not boat.has_method(acc):
		return null
	return boat.call(acc) as Node3D
