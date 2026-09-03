class_name DeckBagRifleReloadController
extends RefCounted
## Reload hand choreography and its authored cartridge/bolt timing contract.

const STOPS := preload("res://scripts/hands/rifle_reload_stops.gd")

func _reload_segment(t: float, start: float, finish: float) -> float:
	return smoothstep(0.0, 1.0, clampf((t - start) /
			maxf(finish - start, 0.001), 0.0, 1.0))


func update(rifle: Node3D, camera: Camera3D, weapon_frame: Transform3D,
		primary_frame: Transform3D, primary_target: Node3D,
		configure_normal_hand: Callable) -> void:
	var t := float(rifle.call("reload_elapsed"))
	# Every boundary below is a STOP in the shared table (rifle_reload_stops),
	# the same numbers the rifle's animation runs on and the editor moves.
	var S: Dictionary = STOPS.times()
	var RELOAD_BOLT_OPEN_START: float = S["bolt_open_start"]
	var RELOAD_BOLT_OPEN_END: float = S["bolt_open_end"]
	var RELOAD_CARTRIDGE_SHOW: float = S["cartridge_show"]
	var RELOAD_CARTRIDGE_MOVE: float = S["cartridge_move"]
	var RELOAD_CARTRIDGE_INSERT: float = S["cartridge_insert"]
	var RELOAD_INSERTED: float = S["inserted"]
	var RELOAD_BOLT_CLOSE_START: float = S["bolt_close_start"]
	var RELOAD_BOLT_CLOSE_END: float = S["bolt_close_end"]
	var RELOAD_DURATION: float = S["duration"]
	var chamber_node := rifle.call("chamber_node") as Node3D
	var bolt_node := rifle.call("bolt_handle_node") as Node3D
	var cartridge := rifle.call("cartridge_node") as Node3D
	var chamber := weapon_frame * chamber_node.transform
	var round_palm_local := rifle.call("cartridge_palm_local") as Vector3
	# The cartridge, not the wrist, owns the chamber alignment. Its +Z axis stays
	# on the bore/receiver line while the anatomically solved hand translates from
	# the pocket. This prevents the old 180-degree forearm roll at insertion.
	var chamber_entry := chamber
	chamber_entry.origin -= chamber.basis.z.normalized() * 0.105
	chamber_entry.origin += chamber.basis.y.normalized() * 0.018
	# The pouch on the belt, BELOW the frame. A round that becomes visible
	# inside the picture is a round out of nothing, however good the hand
	# looks; the hand has to leave the shot, close on the cartridge down
	# there, and bring it up. At 70 degrees vertical-ish and 0.30 m out the
	# bottom edge of the frame is about 0.21 m below the eye line, so this
	# sits a further 13 cm under it — the whole hand goes out of sight.
	var pocket_palm_position := camera.global_transform \
			* Vector3(0.165, -0.345, -0.300)
	var pocket_round := Transform3D(chamber.basis,
			pocket_palm_position - chamber.basis * round_palm_local)
	var desired_round := pocket_round
	# Never approximate the imported action with a second hand-only curve. The
	# returned grip is Bolt_Bone's live transform, so palm and metal cannot drift.
	var bolt := weapon_frame * (rifle.call("bolt_grip_transform") as Transform3D)
	# Only the CONTACT position follows every degree of Bolt_Bone rotation. The
	# reference action uses a horizontal pincer grasp: forearm arrives from the
	# lower-right, fingers travel across the receiver from right to left, and the
	# back of the hand stays UP like the reference. The palm is neither presented
	# to the player nor rolled toward the sky: it faces strongly down onto the
	# action with only a small forward component, which keeps forearm and wrist in
	# the same anatomical plane.
	var bolt_fingers := (-camera.global_basis.x * 0.90 \
			- camera.global_basis.y * 0.26 \
			- camera.global_basis.z * 0.12).normalized()
	var bolt_palm := -camera.global_basis.y * 0.90 \
			- camera.global_basis.z * 0.35
	bolt_palm -= bolt_palm.project(bolt_fingers)
	bolt_palm = bolt_palm.normalized()
	var bolt_knuckles := bolt_palm.cross(bolt_fingers).normalized()
	bolt.basis = Basis(bolt_knuckles, bolt_palm, bolt_fingers)
	var hand_frame := primary_frame
	var pose := STOPS.pose_at(t)
	var natural_grip_blend := _reload_segment(t, 0.0, 0.16)
	var carrying_round := t >= RELOAD_CARTRIDGE_SHOW and t < RELOAD_INSERTED
	var bolt_contact_active := false
	if t < RELOAD_BOLT_OPEN_START:
		# R begins by moving the firing hand to the bolt. The bolt animation cannot
		# start until the palm has arrived at the live knob transform.
		hand_frame = Transform3D(primary_frame.basis,
				primary_frame.origin.lerp(bolt.origin,
				_reload_segment(t, 0.0, RELOAD_BOLT_OPEN_START)))
		bolt_contact_active = t >= 0.12
	elif t < RELOAD_BOLT_OPEN_END:
		hand_frame = bolt
		bolt_contact_active = true
	elif t < RELOAD_CARTRIDGE_SHOW:
		# The animation is paused at its measured full-rear key. The hand may leave
		# the knob, but the metal remains open while it travels to the cartridge.
		hand_frame = Transform3D(chamber.basis,
				bolt.origin.lerp(pocket_palm_position,
				_reload_segment(t, RELOAD_BOLT_OPEN_END,
				RELOAD_CARTRIDGE_SHOW)))
	elif t < RELOAD_CARTRIDGE_MOVE:
		desired_round = pocket_round
		hand_frame = Transform3D(chamber.basis,
				desired_round * round_palm_local)
	elif t < RELOAD_CARTRIDGE_INSERT:
		desired_round = Transform3D(chamber.basis,
				pocket_round.origin.lerp(chamber_entry.origin,
				_reload_segment(t, RELOAD_CARTRIDGE_MOVE,
				RELOAD_CARTRIDGE_INSERT)))
		hand_frame = Transform3D(chamber.basis,
				desired_round * round_palm_local)
	elif t < RELOAD_INSERTED:
		desired_round = Transform3D(chamber.basis,
				chamber_entry.origin.lerp(chamber.origin,
				_reload_segment(t, RELOAD_CARTRIDGE_INSERT,
				RELOAD_INSERTED)))
		hand_frame = Transform3D(chamber.basis,
				desired_round * round_palm_local)
	elif t < RELOAD_BOLT_CLOSE_START:
		var approach_blend := _reload_segment(t,
				RELOAD_INSERTED, RELOAD_BOLT_CLOSE_START)
		# Position travels to the knob while the authored endpoint stays the
		# chamber frame. hands.gd performs the one and only chamber->natural wrist
		# blend; interpolating this basis too caused a hidden second rotation.
		var inserted_palm := chamber * round_palm_local
		hand_frame = Transform3D(chamber.basis,
				inserted_palm.lerp(bolt.origin, approach_blend))
	elif t < RELOAD_BOLT_CLOSE_END:
		hand_frame = bolt
		bolt_contact_active = true
	else:
		var return_blend := _reload_segment(t, RELOAD_BOLT_CLOSE_END,
				RELOAD_DURATION)
		# Preserve one stable trigger-grip endpoint while the palm comes home.
		# Blending bolt->primary here and then blending it again against the
		# anatomical frame made the wrist corkscrew near the end of the reload.
		hand_frame = Transform3D(primary_frame.basis,
				bolt.origin.lerp(primary_frame.origin, return_blend))
		natural_grip_blend = 1.0 - return_blend

	primary_target.global_transform = hand_frame
	primary_target.set_meta("ads_locked", false)
	primary_target.set_meta("weapon_space_pinned", false)
	primary_target.set_meta("hand_pose", pose)
	primary_target.set_meta("natural_grip_blend", natural_grip_blend)
	# BoltHandle is the metal knob, not the centre of a human palm. Keep its live
	# transform exact and place the palm outside it; curled fingertips are what
	# actually meet the control.
	var bolt_grip_blend := natural_grip_blend if pose == "bolt_grip" else 0.0
	primary_target.set_meta("palm_clearance", 0.028 * bolt_grip_blend)
	# Put the knob in the thumb/index web, ahead of the palm and toward the index
	# side. Without these semantic offsets the nearest digits are ring/pinky even
	# though the wrist itself is anatomically straight.
	primary_target.set_meta("control_forward_reach",
			0.018 * bolt_grip_blend)
	primary_target.set_meta("control_index_bias",
			0.020 * bolt_grip_blend)
	primary_target.set_meta("hand_attachment", carrying_round)
	if carrying_round and cartridge != null:
		cartridge.global_transform = desired_round
		cartridge.reset_physics_interpolation()
		primary_target.set_meta("held_device", cartridge)
		primary_target.set_meta("held_grip_transform", Transform3D.IDENTITY)
		# hands.gd reconstructs the grip basis from its neutral wrist result. The
		# local palm point remains fixed, while the round itself lands exactly on
		# this authored chamber-space transform.
		primary_target.set_meta("held_device_target", desired_round)
		primary_target.set_meta("contact_bounds",
				rifle.call("cartridge_contact_bounds") as AABB)
	elif bolt_contact_active:
		primary_target.remove_meta("held_device_target")
		primary_target.set_meta("held_device", rifle)
		primary_target.set_meta("held_grip_transform", Transform3D.IDENTITY)
		primary_target.set_meta("contact_bounds",
				rifle.call("bolt_contact_bounds") as AABB)
	elif t >= RELOAD_BOLT_CLOSE_END:
		primary_target.remove_meta("held_device_target")
		var primary_grip := rifle.call("primary_grip_node") as Node3D
		configure_normal_hand.call(rifle, primary_grip)
	else:
		primary_target.remove_meta("held_device_target")
		# Empty hand travelling to the pocket; do not let the finger solver chase
		# the rifle across the frame before the cartridge appears.
		primary_target.set_meta("held_device", null)
		primary_target.set_meta("held_grip_transform", Transform3D.IDENTITY)
