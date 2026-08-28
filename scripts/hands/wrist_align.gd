extends SkeletonModifier3D
class_name WristAlign
## Orients the wrists after the arm IK has placed them.
##
## TwoBoneIK3D positions the end bone; it does not rotate it. That is correct for
## a solver — the elbow circle has no opinion about wrist roll — but it means a
## hand sent to a wheel arrives at the right point facing the wrong way, which is
## most of what "the hands look off" is.
##
## This runs as a second modifier after the IK, in the same pose buffer, so it
## reads the solved wrist and rewrites only its rotation. Position is left
## exactly where the solver put it.
##
## It is also the only place the final pose can be read from. Outside a
## modification pass Skeleton3D hands back the pre-modifier pose, so anything
## that needs to know where a hand actually ended up — attaching a held object,
## checking a grip landed — reads `solved` here rather than asking the skeleton.

## bone index -> desired GLOBAL basis for that bone, in skeleton space.
var wanted := {}
## bone index -> 0..1 blend against whatever the IK left.
var weights := {}
## bone index -> the pose the bone actually ended up with, skeleton space.
var solved := {}


func clear_all() -> void:
	wanted.clear()
	weights.clear()


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	for b: int in wanted:
		if b < 0 or b >= sk.get_bone_count():
			continue
		var cur: Transform3D = sk.get_bone_global_pose(b)
		var w: float = clampf(weights.get(b, 1.0), 0.0, 1.0)
		if w > 0.001:
			var goal: Basis = wanted[b]
			var q := cur.basis.get_rotation_quaternion().slerp(
					goal.get_rotation_quaternion(), w)
			var parent := sk.get_bone_parent(b)
			var parent_global: Transform3D = Transform3D.IDENTITY
			if parent >= 0:
				parent_global = sk.get_bone_global_pose(parent)
			# Rotation only: rebuild the local pose from the parent's solved
			# frame, keeping the origin the IK chose.
			var local_rot: Quaternion = (parent_global.basis.get_rotation_quaternion().inverse()
					* q).normalized()
			sk.set_bone_pose_rotation(b, local_rot)
			cur = sk.get_bone_global_pose(b)
		solved[b] = cur
