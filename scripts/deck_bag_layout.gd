class_name DeckBagLayout
extends RefCounted
## Shared authored slot geometry. Runtime seating and procedural construction
## must read the same transforms or hand targets drift from visible restraints.

const SLOT_POSITIONS := [
	Vector3(-0.178, -0.040, 0.125),
	Vector3(-0.060, -0.045, 0.125),
	Vector3(0.060, -0.050, 0.125),
	Vector3(0.174, -0.045, 0.125),
	Vector3(0.0, -0.330, 0.145),
]
const SLOT_LABELS := ["Flashlight", "Signal flare", "Utility knife", "Multitool",
		"Hunting rifle"]
const KNIFE_SLOT := 2
const RIFLE_SLOT := 4
const KNIFE_SLOT_PROUD := -0.040


static func slot_transform(index: int) -> Transform3D:
	var basis := Basis.IDENTITY
	var origin: Vector3 = SLOT_POSITIONS[index]
	if index == KNIFE_SLOT:
		basis = Basis(Vector3.UP, Vector3.BACK, Vector3.LEFT)
		origin.y -= 0.055
		origin.z += KNIFE_SLOT_PROUD
	elif index == RIFLE_SLOT:
		basis = Basis(Vector3.UP, deg_to_rad(-90.0))
	return Transform3D(basis, origin)
