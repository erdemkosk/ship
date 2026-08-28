extends RefCounted
class_name GripMap
## Where a hand goes, and what the thing it holds is allowed to do.
##
## One entry per interactable. `node` names an accessor already on boat.gd, so
## nothing here needs the boat rebuilt or its scene touched. The grip offsets are
## in that node's LOCAL space, which is the whole point: the grip node is created
## as a child of the device, so when the wheel turns or the lever swings its grip
## turns and swings with it. The hand is then welded to the device by parentage
## rather than by two curves agreeing frame to frame.
##
## `hands` decides which hand takes what. The helm is a left-hand job precisely
## so the right stays free for the throttle — one hand steering and one on the
## lever is how a boat is actually driven, and it only works if the two are
## separate claims on separate arms.

enum Motion {
	FIXED,   ## does not move; the hand just rests on it
	TURN,    ## rotates about its own axis (wheel, knob, key)
	SWING,   ## rotates over a limited arc (lever, door, hood on a bracket)
	PRESS,   ## travels a few millimetres along an axis (switch, button)
}

## Rim radius of the helm, from the torus built in boat.gd (_build_helm).
const HELM_RIM := 0.29

const ENTRIES := {
	"helm": {
		"node": "helm_wheel",
		"motion": Motion.TURN,
		# Left hand on the rim. The angle is chosen at grab time (see hands.gd)
		# and re-chosen when the wheel has turned far enough that the arm would
		# be wrung out — a helmsman re-grips, they do not rotate their wrist
		# through 240 degrees.
		"hands": {
			"L": {"pos": Vector3(-HELM_RIM, 0.0, 0.0), "rot": Vector3(0.0, 0.0, 90.0),
				"pose": "wrap", "on_rim": true},
		},
	},
	"telegraph": {
		"node": "throttle_lever",
		"motion": Motion.SWING,
		"hands": {
			"R": {"pos": Vector3(0.0, 0.31, 0.0), "rot": Vector3(-20.0, 0.0, 0.0),
				"pose": "fist"},
		},
	},
	"ignition": {
		"node": "ignition_key",
		"motion": Motion.TURN,
		"hands": {
			"R": {"pos": Vector3(0.0, 0.0, 0.03), "rot": Vector3(0.0, 0.0, 0.0),
				"pose": "pinch"},
		},
	},
	"windlass": {
		"node": "windlass_node",
		"motion": Motion.TURN,
		"hands": {
			"R": {"pos": Vector3(0.40, 0.10, 0.0), "rot": Vector3(0.0, 0.0, 90.0),
				"pose": "wrap"},
		},
	},
	"radio": {
		"node": "radio_handset",
		"motion": Motion.FIXED,
		"hands": {
			"R": {"pos": Vector3(0.0, 0.0, 0.0), "rot": Vector3(0.0, 0.0, 0.0),
				"pose": "wrap"},
		},
	},
}


static func has(id: String) -> bool:
	return ENTRIES.has(id)


static func entry(id: String) -> Dictionary:
	return ENTRIES.get(id, {})


static func local_transform(spec: Dictionary) -> Transform3D:
	var r: Vector3 = spec.get("rot", Vector3.ZERO)
	return Transform3D(
			Basis.from_euler(Vector3(deg_to_rad(r.x), deg_to_rad(r.y), deg_to_rad(r.z))),
			spec.get("pos", Vector3.ZERO))
