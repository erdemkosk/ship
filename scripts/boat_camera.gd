extends Node3D
## Camera with three modes, cycled with F:
##  - FOLLOW: orbits the boat; hold right mouse to orbit, wheel to zoom.
##  - FPS:    you are ABOARD her. Mouse looks, WASD walks the deck, Space
##            jumps, and the ladder aft of the deckhouse takes you up to the
##            wheelhouse. Stand at the wheel and press E to take the helm —
##            then WASD steers the boat instead of your feet. E again to let go.
##  - FREE:   fly camera; hold right mouse to look, W/A/S/D + Q/E to move,
##            Shift for speed boost. Boat input is suspended.
## The camera stays above the waves in FOLLOW / FPS. FREE mode can dive;
## Q lowers, E raises. Seafloor is the only lower clamp.

enum Mode { FOLLOW, FPS, FREE }

## Keyboard shorthand -> the switch it throws. Same ids the fuse box uses, so
## there is one circuit behind both and they cannot disagree.
const SHORTCUTS := {
	"anchor": "sw_anchor", "light_cabin": "sw_cabin", "light_helm": "sw_helm",
	"light_beacon": "sw_beacon", "light_flood": "sw_flood", "wiper": "sw_wiper",
}

var target: Node3D
var ocean: Node3D
var weather: Node3D
var mode: int = Mode.FOLLOW
var free_mode := false  # read by boat.gd: true only in FREE mode

var yaw := 0.0
var pitch := -0.22
var dist := 16.0
var free_speed := 14.0
## FPS look. Mouse writes the target; the head eases onto it so a flick is a
## turn, not a snap. Slower than orbit — you are a person, not a turret.
const FPS_LOOK := 0.0021
const FPS_LOOK_TAU := 0.075
var _look_yaw := 0.0
var _look_pitch := 0.0



var _cam: Camera3D
var _orbiting := false
var _under_rect: ColorRect
var _under_mat: ShaderMaterial
var _warm_rect: ColorRect
var _warm_mat: ShaderMaterial
var _warmth := 0.22
var _motes: GPUParticles3D
var _prompt: Label
var _walker: RefCounted = (load("res://scripts/deck_walker.gd") as GDScript).new()
# Eye smoothing. The walker's feet move in hard 0.28 m increments up a
# companionway, so an eye pinned straight to them climbs like a staircase of
# jump cuts. Smoothed in the BOAT'S frame, never in world space — smooth it in
# world space and you are also smoothing her heave, which puts the horizon on
# a spring and makes the whole deck feel like jelly.
var _eye_y := 0.0
var _eye_ready := false
var _bob := 0.0
var _roll := 0.0
var _panel: Node = null
# 0 while you are not at the chart, running to 1 as you lean over it. The lean
# is what makes it a place you go rather than a screen that opens.
var _chart_t := 0.0
var _last_aim := ""
var _bubbles: GPUParticles3D
## Your own breath. Separate from the ambient field: those bubbles say the sea
## is aerated, these say YOU are down here and holding it — they come off your
## face, they burst as the water closes over you, and they trickle after.
var _breath: GPUParticles3D
var _breath_burst := 0.0
var _was_sub := false
var _was_ladder := false
## The mask. `_fog` is condensation on the inside of the glass, `_wipe` is the
## finger crossing it — 1 at the start of the sweep, 0 when it is clear.
var _mask_rect: ColorRect
var _mask_mat: ShaderMaterial
var _fog := 0.0
var _wipe := 0.0
var _inhale: AudioStreamPlayer
var _exhale: AudioStreamPlayer
## The breath cycle, and the level of fog at which the next automatic clear
## happens. Both are deliberately irregular: a diver does not breathe to a
## metronome and does not clear their mask on a schedule either.
var _br_t := 0.0
var _br_in := true
var _wipe_at := 0.78
## Seconds of wearing it before the glass is milky. Same clock in air and
## water — a dive does not ice the pane; it is still breath on cold glass.
const FOG_DRY := 260.0
var _drops := 0.0
var _drop_wipe := 0.0
var _mask_was_under := false
var _breath_amt := 0.0
var _arms: Node
var _reticle: Control
var _blink_rect: ColorRect
var _blink_mat: ShaderMaterial
var _blink := 0.0
var _blink_wait := 4.0
var _blink_tween: Tween
var _blink_again := false


func _ready() -> void:
	_cam = Camera3D.new()
	_cam.fov = 70.0
	_cam.near = 0.1
	# The true horizon is ~5 km out; the sea plate has to reach past it.
	_cam.far = 18000.0
	add_child(_cam)
	_cam.current = true
	_cam.top_level = true  # free of rig transform; we place it explicitly
	_cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# New hand system: measured IK rig + per-hand grip claims (scripts/hands/).
	# The old fps_arms.gd is left on disk untouched — swap this one line back to
	# fall straight over to it.
	_arms = (load("res://scripts/hands/hands.gd") as GDScript).new()
	add_child(_arms)
	_arms.setup(_cam)
	_build_underwater()
	# Interaction prompt: one line at the bottom of the view, only in FPS mode.
	var pl := CanvasLayer.new()
	pl.layer = 2
	add_child(pl)
	_prompt = Label.new()
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.offset_top = -78.0
	_prompt.offset_left = -260.0
	_prompt.offset_right = 260.0
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 17)
	_prompt.add_theme_color_override("font_color", Color(1.0, 0.72, 0.36))
	_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_prompt.add_theme_constant_override("outline_size", 4)
	_prompt.visible = false
	pl.add_child(_prompt)

	# Reticle. A boat has no HUD, so this is as close to nothing as it can be
	# and still answer the only question it exists to answer: WHICH of the four
	# fittings under your nose is the one E will take. A hairline dot when there
	# is nothing, four ticks closing on it when there is.
	_reticle = Control.new()
	_reticle.set_anchors_preset(Control.PRESET_FULL_RECT)
	_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reticle.set_script(load("res://scripts/reticle.gd"))
	pl.add_child(_reticle)

	# Occasional blink. On this layer so it covers the view, the reticle and
	# the prompt — eyelids sit in front of everything you were looking at.
	_blink_rect = ColorRect.new()
	_blink_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_blink_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blink_rect.color = Color(1, 1, 1, 1)
	_blink_mat = ShaderMaterial.new()
	_blink_mat.shader = load("res://shaders/blink.gdshader")
	_blink_rect.material = _blink_mat
	_blink_rect.visible = false
	pl.add_child(_blink_rect)


func set_mode(m: int) -> void:
	mode = m
	free_mode = mode == Mode.FREE
	match mode:
		Mode.FPS:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			_eye_ready = false
			_bob = 0.0
			_roll = 0.0
			if _arms != null:
				_arms.set_active(true)
			# start looking where the boat points, standing at the wheel
			if target != null:
				var fwd := -target.global_basis.z
				yaw = atan2(-fwd.x, -fwd.z)
				_walker.spawn_at(target.CREW_START)
				target.set("helm_engaged", true)
				target.set("telegraph_engaged", false)
			pitch = 0.0
			_look_yaw = yaw
			_look_pitch = pitch
			_blink_wait = randf_range(1.8, 4.5)
		Mode.FREE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			if _arms != null:
				_arms.set_active(false)
			if target != null:
				target.set("helm_engaged", true)
				target.set("telegraph_engaged", false)
			if _prompt != null:
				_prompt.visible = false
			_stop_blink()
			var fwd := -_cam.global_basis.z
			yaw = atan2(-fwd.x, -fwd.z)
			pitch = asin(clampf(fwd.y, -1.0, 1.0))
		_:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			if _arms != null:
				_arms.set_active(false)
			if target != null:
				target.set("helm_engaged", true)
				target.set("telegraph_engaged", false)
			if _prompt != null:
				_prompt.visible = false
			_stop_blink()
			pitch = clampf(pitch, -1.15, 0.45)


func _panel_open() -> bool:
	if _panel == null or not is_instance_valid(_panel):
		_panel = get_tree().get_first_node_in_group("ui_panel")
	return _panel != null and _panel.has_method("is_open") and _panel.is_open()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_camera"):
		set_mode((mode + 1) % 3)
		return
	if mode == Mode.FPS and event.is_action_pressed("ui_cancel"):
		set_mode(Mode.FOLLOW)
		return

	if event is InputEventMouseMotion:
		# Panel up: the pointer is for the sliders, not for looking around.
		if _panel_open():
			return
		if mode == Mode.FPS and _chart_t > 0.0 and _chart_t < 1.0:
			return                      # leaning in; the camera is driving
		if mode == Mode.FPS:
			_look_yaw -= event.relative.x * FPS_LOOK
			_look_pitch = clampf(_look_pitch - event.relative.y * FPS_LOOK, -1.4, 1.4)
		elif _orbiting:
			yaw -= event.relative.x * 0.005
			if mode == Mode.FREE:
				pitch = clampf(pitch - event.relative.y * 0.005, -1.5, 1.5)
			else:
				pitch = clampf(pitch - event.relative.y * 0.005, -1.15, 0.45)
		return

	# Mask on: 3 is a finger across the WET glass, not the beacon. The fuse
	# still throws that circuit from the panel; the shortcut yields while you
	# are looking through a lens covered in sea.
	if mode == Mode.FPS and target != null and bool(target.get("gear_worn")) \
			and event.is_action_pressed("light_beacon"):
		_wipe_drops()
		return

	# The circuits, by key. A physical switch under the fuse box lid is the
	# honest way to work one, and it is still there — but the status panel
	# prints a key beside every row, and a panel that prints keys that do
	# nothing is worse than no panel. `by_hand = false` is what says "this is
	# the shortcut, not a finger", so the shut lid does not swallow it.
	if mode == Mode.FPS and target != null and target.has_method("toggle_switch"):
		for act: String in SHORTCUTS:
			if event.is_action_pressed(act):
				target.toggle_switch(SHORTCUTS[act], false)
				return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and mode != Mode.FPS:
			_orbiting = event.pressed
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _orbiting else Input.MOUSE_MODE_VISIBLE
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			if mode == Mode.FREE:
				free_speed = clampf(free_speed * 1.15, 2.0, 120.0)
			elif mode == Mode.FOLLOW:
				dist = clampf(dist * 0.9, 7.0, 60.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			if mode == Mode.FREE:
				free_speed = clampf(free_speed / 1.15, 2.0, 120.0)
			elif mode == Mode.FOLLOW:
				dist = clampf(dist * 1.1, 7.0, 60.0)


func _process(delta: float) -> void:
	match mode:
		Mode.FPS:
			_process_fps(delta)
		Mode.FREE:
			_process_free(delta)
		_:
			_process_follow(delta)
	_update_underwater()
	_update_blink(delta)
	if mode != Mode.FPS:
		# Everything that belongs to being ABOARD goes with the mode. These are
		# only ever written inside _process_fps, so on the frame you leave first
		# person they simply stopped being updated and stayed on screen — a
		# crosshair and a prompt floating over an orbit camera.
		if _warm_rect != null:
			_warm_rect.visible = false
		if _reticle != null:
			_reticle.visible = false
		if _prompt != null:
			_prompt.visible = false


func _process_follow(delta: float) -> void:
	if target == null:
		return
	var t := 1.0 - exp(-8.0 * delta)
	var tgt: Vector3 = target.get_global_transform_interpolated().origin
	if not tgt.is_finite():
		return
	global_position = global_position.lerp(tgt, t)

	var rot := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	var cam_pos := global_position + rot * Vector3(0.0, 0.0, dist)
	_clamp_and_place(cam_pos)
	var look := global_position + Vector3(0.0, 2.4, 0.0)
	if _cam.global_position.is_finite() and look.is_finite() \
			and _cam.global_position.distance_squared_to(look) > 0.04:
		_cam.look_at(look, Vector3.UP)


func _process_fps(delta: float) -> void:
	if target == null:
		return
	# Physics interpolation is on project-wide, so the boat's MESH is drawn at a
	# smoothly interpolated transform while `global_transform` still reports the
	# last physics tick. Reading the raw transform pins the eye to 60 Hz inside a
	# 120 Hz render and the whole boat shivers around you as you make way. Ask
	# for the interpolated one instead.
	var xf: Transform3D = target.get_global_transform_interpolated()
	global_position = xf.origin

	# Tab opens the weather panel; while it is up you get your cursor back so
	# you can actually reach the sliders, and it is taken again on close.
	var want := Input.MOUSE_MODE_VISIBLE if _panel_open() else Input.MOUSE_MODE_CAPTURED
	if Input.mouse_mode != want:
		Input.mouse_mode = want

	# --- interaction: look at a thing, E takes hold of it, E lets go ---------
	# Everything aboard that accepts a hand is listed in boat.INTERACT; whichever
	# one is close and in front of you gets offered on the prompt line.
	var engaged := ""
	if target.get("helm_engaged"):
		engaged = "helm"
	elif target.get("telegraph_engaged"):
		engaged = "telegraph"
	elif target.get("chart_engaged"):
		engaged = "chart"

	var look_fwd := -_cam.global_basis.z
	var look_l: Vector3 = (xf.basis.inverse() * look_fwd).normalized()
	var eye: Vector3 = _walker.eye_local()

	var cand := {}
	if engaged != "chart":
		# Ray against a sphere per fitting, nearest hit wins. It used to score by
		# alignment alone, which meant a big target behind a small one could take
		# the aim off it — you could be looking straight down a switch and get
		# offered the chart table. Now `r` is simply how big the thing is to
		# point at, and pointing at it is what selects it.
		# Aiming in a seaway. She rolls and pitches under your feet, so whatever
		# you are pointing at slides out from under the aim between one wave and
		# the next — and the switches are 10 cm targets. Two corrections, both
		# keyed to the thing actually causing the trouble:
		#
		#   * every target grows in proportion to how much she is MOVING, so it
		#     is precise when she is quiet and forgiving when she is not;
		#   * whatever is already being offered gets a further bonus, so it does
		#     not flicker off and back between rolls once you have found it.
		var sway := 0.0
		if target is RigidBody3D:
			var rb := target as RigidBody3D
			sway = clampf(rb.angular_velocity.length() * 1.6, 0.0, 1.4)
		var nearest := 1e9
		for it in target.INTERACT:
			var iid := str(it["id"])
			# Already on the wheel: the helm must not eat the key beside it.
			if engaged == "helm" and iid == "helm":
				continue
			if engaged == "telegraph" and iid == "telegraph":
				continue
			# The suit hangs INSIDE the locker. Through a shut steel door it is
			# not a thing you can reach, so it is not a thing you are offered.
			if iid == "divegear" and not (bool(target.get("locker_open"))
					or bool(target.get("gear_worn"))):
				continue
			# Same for the switchboard: the toggles are under a steel hood. With
			# the hood down they are not merely inoperable — they are not there
			# to point at, and offering them was the confusing part, because the
			# prompt appeared and then E did nothing.
			if iid.begins_with("sw_") and not bool(target.get("fusebox_open")):
				continue
			var ipos: Vector3 = it["pos"]
			if target.has_method("interact_pos"):
				ipos = target.interact_pos(iid, ipos)
			var to: Vector3 = ipos - eye
			var along := look_l.dot(to)
			if along <= 0.02 or along > 2.2:
				continue
			var rr: float = float(it["r"]) * (1.0 + sway)
			if iid == _last_aim:
				rr *= 1.75
			var perp: float = (to - look_l * along).length()
			if perp > rr:
				continue
			# And it has to be in SIGHT. With the fuse lid standing open the
			# radio sits right behind it, and reaching through a steel plate to
			# take a handset off its hook is not a thing.
			if _occluded(target, eye, ipos):
				continue
			# Score by ANGLE OFF THE CROSSHAIR, not by distance along the ray.
			# Nearest-along handed you whichever fitting happened to be closest
			# to your face — around the radar bracket that is four things at
			# once, and never the one you were looking at. Perp/along is the
			# tangent of the aim error, so the winner is simply whatever sits
			# closest to the centre of the screen. The sticky bonus survives as
			# a discount, so a target you have already found does not lose to a
			# neighbour on a roll.
			var score: float = perp / maxf(along, 0.05)
			if iid == _last_aim:
				score *= 0.62
			if score < nearest:
				nearest = score
				cand = it
		_last_aim = str(cand["id"]) if not cand.is_empty() else ""
	if _reticle != null:
		_reticle.set("aim_target", 0.0 if cand.is_empty() else 1.0)
		_reticle.visible = mode == Mode.FPS

	if Input.is_action_just_pressed("use"):
		if cand.is_empty() and engaged == "" and bool(target.get("radio_held")):
			# Holding the handset with nothing else under the crosshair: E puts
			# it back on its hook. You should not have to hunt for the cradle
			# with your nose to hang up a radio.
			target.set("radio_held", false)
			if _arms != null:
				_arms.boat = target
				_arms.notify_use("radio")
		elif cand.is_empty() and engaged == "" and _fog >= 0.10 and _wipe <= 0.0 \
				and bool(target.get("gear_worn")):
			# Nothing under the crosshair and the glass is milky: that is the
			# only thing E can sensibly mean.
			_wipe_mask()
		elif _arms != null and _arms.inspecting_id() != "":
			_arms.boat = target
			_arms.notify_use(_arms.inspecting_id())
		elif not cand.is_empty() and str(cand["id"]) == "ignition" \
				and target.has_method("toggle_switch"):
			target.toggle_switch("ignition")
			if _arms != null:
				_arms.boat = target
				_arms.notify_use("ignition")
		elif engaged == "helm":
			target.set("helm_engaged", false)
			_walker.spawn_at(target.HELM_STAND)
		elif engaged == "telegraph":
			target.set("telegraph_engaged", false)
			_walker.spawn_at(target.TELEGRAPH_STAND)
		elif engaged == "chart":
			target.set("chart_engaged", false)
			_walker.spawn_at(target.CHART_STAND)
		elif not cand.is_empty():
			var iid := str(cand["id"])
			if _arms != null:
				_arms.boat = target
				if iid == "radio":
					# One key, both ways: off the hook and back onto it.
					target.set("radio_held", not bool(target.get("radio_held")))
				_arms.notify_use(iid)
			match iid:
				"helm":
					target.set("helm_engaged", true)
				"telegraph":
					target.set("telegraph_engaged", true)
				"chart":
					target.set("chart_engaged", true)
				"radio", "radar", "sounder":
					pass
				"sea_ladder":
					_walker.grab_sea_ladder(target)
				"locker":
					target.toggle_switch("locker")
				"divegear":
					target.toggle_switch("divegear")
					if _arms != null and _arms.has_method("face_gesture"):
						_arms.face_gesture("wear")
				"windlass":
					var tk: Node = target.get("tackle")
					if tk != null:
						tk.toggle()
				"lights":
					if target.has_method("toggle_lights"):
						target.toggle_lights()
				_:
					# Brass toggles and doors: E throws the circuit.
					var cid := str(cand["id"])
					if (cid.begins_with("sw_") or cid.begins_with("door_")
							or cid == "fusebox" or cid == "stove") \
							and target.has_method("toggle_switch"):
						target.toggle_switch(str(cand["id"]))
		engaged = "helm" if target.get("helm_engaged") \
				else ("telegraph" if target.get("telegraph_engaged") \
				else ("chart" if target.get("chart_engaged") else ""))

	if _prompt != null:
		if _walker.get("on_sea_ladder"):
			_prompt.text = "W/S — climb   ·   SPACE — let go"
			_prompt.visible = true
		elif _walker.get("swimming"):
			if _walker.get("can_board"):
				_prompt.text = "SPACE — take the ladder"
			elif bool(_walker.get("submerged")):
				_prompt.text = "SPACE — swim up   ·   B — watch"
			else:
				_prompt.text = "You are in the sea — swim to the stern ladder   ·   CTRL: dive   ·   B — watch"
			_prompt.visible = true
		elif engaged == "helm":
			if not cand.is_empty() and str(cand["id"]) == "ignition":
				var st := int(target.get("engine"))
				_prompt.text = "E — Ignition  (%s)" % (
						"stop" if st == 2 else ("cranking" if st == 1 else "start"))
			else:
				_prompt.text = "E — let go of the wheel   ·   B — watch"
			_prompt.visible = true
		elif engaged == "telegraph":
			_prompt.text = "E — let go of the throttle"
			_prompt.visible = true
		elif engaged == "chart":
			_prompt.text = "E — leave the chart"
			_prompt.visible = true
		elif _arms != null and _arms.inspecting_id() in ["radar", "sounder"]:
			_prompt.text = "E — stow the screen"
			_prompt.visible = true
		elif cand.is_empty() and _drops >= 0.22 and _drop_wipe <= 0.0 \
				and bool(target.get("gear_worn")):
			_prompt.text = "3 — wipe the water off the mask"
			_prompt.visible = true
		elif cand.is_empty() and _fog >= 0.10 and _wipe <= 0.0 \
				and bool(target.get("gear_worn")):
			_prompt.text = "E — wipe the mask"
			_prompt.visible = true
		elif bool(target.get("radio_held")) and cand.is_empty():
			_prompt.text = "E — hang up the handset"
			_prompt.visible = true
		elif not cand.is_empty():
			if cand["id"] == "radio" and bool(target.get("radio_held")):
				_prompt.text = "E — hang up the handset"
			elif str(cand["id"]) in ["radar", "sounder"] and _arms != null \
					and _arms.inspecting_id() == str(cand["id"]):
				_prompt.text = "E — stow the screen"
			elif str(cand["id"]) == "locker":
				_prompt.text = "E — %s the locker" % (
						"close" if bool(target.get("locker_open")) else "open")
			elif str(cand["id"]) == "divegear":
				_prompt.text = "E — %s the dive gear" % (
						"take off" if bool(target.get("gear_worn")) else "put on")
			elif str(cand["id"]) == "ignition":
				var st := int(target.get("engine"))
				_prompt.text = "E — Ignition  (%s)" % (
						"stop" if st == 2 else ("cranking" if st == 1 else "start"))
			elif (str(cand["id"]).begins_with("sw_") or str(cand["id"]).begins_with("door_")) \
					and target.has_method("switch_state"):
				_prompt.text = "E — %s  (%s)" % [cand["name"],
						"off" if target.switch_state(str(cand["id"])) else "on"]
			else:
				_prompt.text = "E — %s" % cand["name"]
			_prompt.visible = true
		else:
			_prompt.text = "B — watch"
			_prompt.visible = true

	if engaged == "helm":
		# Locked to the wheel: the boat's controls are yours, your feet are not.
		_walker.spawn_at(target.HELM_STAND)
	elif engaged == "telegraph":
		_walker.spawn_at(target.TELEGRAPH_STAND)
	elif engaged == "chart":
		_walker.spawn_at(target.CHART_STAND)
	else:
		# Walk. Input is taken in the boat's frame: "forward" is where you are
		# looking, projected onto her deck, so turning the boat under you does
		# not change which way you are walking.
		var look_right := _cam.global_basis.x
		var lf: Vector3 = xf.basis.inverse() * look_fwd
		var lr: Vector3 = xf.basis.inverse() * look_right
		var f2 := Vector2(lf.x, lf.z)
		var r2 := Vector2(lr.x, lr.z)
		if f2.length_squared() > 1e-5:
			f2 = f2.normalized()
		if r2.length_squared() > 1e-5:
			r2 = r2.normalized()
		var wish := Vector2.ZERO
		if not _panel_open():
			wish = f2 * Input.get_axis("boat_backward", "boat_forward") \
					+ r2 * Input.get_axis("boat_left", "boat_right")
			if wish.length() > 1.0:
				wish = wish.normalized()
		# Raw stick as well as the deck-projected heading: in the water and on
		# the rungs "forward" is not a direction on the deck plane.
		var axes := Vector2.ZERO
		if not _panel_open():
			axes = Vector2(Input.get_axis("boat_left", "boat_right"),
					Input.get_axis("boat_backward", "boat_forward"))
		_walker.update(delta, target, wish,
				Input.is_action_just_pressed("jump") and not _panel_open(),
				look_fwd, axes,
				Input.is_action_pressed("jump") and not _panel_open(),
				Input.is_action_pressed("dive") and not _panel_open())

	# --- the eye -------------------------------------------------------------
	var eye_l: Vector3 = _walker.eye_local()
	if engaged == "chart":
		_chart_t = minf(_chart_t + delta / 0.45, 1.0)
		var lean: float = _chart_t * _chart_t * (3.0 - 2.0 * _chart_t)
		eye_l = eye_l.lerp(target.CHART_EYE, lean)
	else:
		_chart_t = 0.0
	if not _eye_ready:
		_eye_y = eye_l.y
		_eye_ready = true
	elif absf(eye_l.y - _eye_y) > 1.10:
		_eye_y = eye_l.y          # teleport: taking the helm, or coming aboard
	else:
		# Fast enough to feel like your own legs, slow enough that a 0.28 m
		# tread is a rise and not a cut.
		_eye_y = lerpf(_eye_y, eye_l.y, 1.0 - exp(-13.0 * delta))
	eye_l.y = _eye_y

	# A little sway with your stride. Two steps to the cycle, and only while
	# your feet are actually on something — no bobbing in mid-air.
	var hs := 0.0 if engaged != "" else Vector2(_walker.vel.x, _walker.vel.z).length()
	var walking: float = clampf(hs / 3.0, 0.0, 1.0) * (1.0 if _walker.on_floor else 0.0)
	_bob = fmod(_bob + delta * hs * 2.3, TAU)
	var amp := walking * 0.022
	eye_l.y += sin(_bob * 2.0) * amp
	eye_l.x += sin(_bob) * amp * 0.9

	var cam_pos: Vector3 = xf * eye_l
	# The eye is normally held clear of the water — you are aboard, and a wave
	# washing the lens every time she rolls is nobody's idea of a boat. In the
	# sea, or on the transom ladder with the sea coming over you, that clamp is
	# exactly wrong: it is the one moment the view SHOULD go under.
	if ocean != null and not bool(_walker.get("swimming")) \
			and not bool(_walker.get("on_sea_ladder")):
		cam_pos.y = maxf(cam_pos.y, ocean.get_height(cam_pos) + 0.35)
	_cam.global_position = cam_pos

	# Lean a fraction of her heel into the view. Full deck roll is sickening and
	# a dead-level horizon feels like standing on a photograph; a third of it,
	# capped, reads as being aboard.
	if engaged == "chart" and _chart_t < 1.0:
		# Turn the head onto the paper. Only while leaning in — once you are
		# there the mouse is yours again, so you can glance up at the window
		# without having to stand off the table first.
		var dirw: Vector3 = (xf.basis * (target.CHART_LOOK - target.CHART_EYE)).normalized()
		var k := 1.0 - exp(-11.0 * delta)
		yaw = lerp_angle(yaw, atan2(-dirw.x, -dirw.z), k)
		pitch = lerpf(pitch, asin(clampf(dirw.y, -1.0, 1.0)), k)
		_look_yaw = yaw
		_look_pitch = pitch
	else:
		var lk := 1.0 - exp(-delta / FPS_LOOK_TAU)
		yaw = lerp_angle(yaw, _look_yaw, lk)
		pitch = lerpf(pitch, _look_pitch, lk)

	# --- how far you can turn your head while you have hold of something -----
	# Planted at a control your BODY does not turn. A helmsman with both hands
	# on the wheel can look over either shoulder and no further; on the boarding
	# ladder you are facing the iron with your arms round it. Without this you
	# can stand at the wheel gripping it and look dead astern, which is the one
	# thing that most gives the hands away as decoration.
	var st_lim := 0.0
	var st_base := 0.0
	if engaged == "helm" or engaged == "telegraph":
		st_base = _yaw_of(-xf.basis.z)
		st_lim = deg_to_rad(48.0)
	elif engaged == "chart":
		st_base = _yaw_of(xf.basis * (target.CHART_LOOK - target.CHART_EYE))
		st_lim = deg_to_rad(58.0)
	elif bool(_walker.get("on_sea_ladder")):
		# Facing the iron. You are hanging OFF the transom, so the ladder is
		# toward the bow from you — her forward, not her stern.
		st_base = _yaw_of(-xf.basis.z)
		st_lim = deg_to_rad(62.0)
	if st_lim > 0.0:
		yaw = st_base + clampf(wrapf(yaw - st_base, -PI, PI), -st_lim, st_lim)
		_look_yaw = st_base + clampf(wrapf(_look_yaw - st_base, -PI, PI), -st_lim, st_lim)
	# Taking hold of the boarding ladder turns you round. You were leaning over
	# the cap looking down at it; now you are on it, facing it, with the ship in
	# front of your nose — and no amount of head-turning does that, the whole
	# body comes about.
	var on_lad: bool = bool(_walker.get("on_sea_ladder"))
	if on_lad and not _was_ladder:
		yaw = _yaw_of(-xf.basis.z)
		pitch = clampf(pitch, -0.5, 0.5)
		_look_yaw = yaw
		_look_pitch = pitch
	_was_ladder = on_lad

	var heel := asin(clampf(xf.basis.x.y, -1.0, 1.0))
	_roll = lerpf(_roll, clampf(heel * 0.24, -0.09, 0.09), 1.0 - exp(-6.0 * delta))
	_cam.global_basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) \
			* Basis(Vector3.BACK, _roll)
	if _arms != null:
		if _arms.has_method("set_sea_ladder"):
			_arms.set_sea_ladder(bool(_walker.get("on_sea_ladder")), _walker.pos.y)
		if _arms.has_method("set_watch_glance"):
			var glance := Input.is_key_pressed(KEY_B)
			if InputMap.has_action("watch"):
				glance = glance or Input.is_action_pressed("watch")
			_arms.set_watch_glance(mode == Mode.FPS and glance)
		var wet := false
		var depth := 0.0
		if ocean != null and _cam != null:
			var wh: float = ocean.get_height(_cam.global_position)
			depth = maxf(wh - _cam.global_position.y, 0.0)
			wet = _cam.global_position.y < wh - 0.05
		if not wet:
			depth = 0.0
		var tod := 12.0
		if weather != null:
			tod = float(weather.get("time_of_day"))
		if _arms.has_method("tick_watch"):
			_arms.tick_watch(tod, depth, wet)
		_arms.update(delta, target, engaged, walking, bool(_walker.get("swimming")))
	_update_warmth(delta)


func _occluded(bt: Node3D, from_l: Vector3, to_l: Vector3) -> bool:
	## Segment against the boat's aim blockers, slab method, boat-local. Cheap
	## enough to run per candidate per frame — there is never more than one.
	var blockers: Array = bt.get("aim_blockers")
	if blockers == null or blockers.is_empty():
		return false
	var d: Vector3 = to_l - from_l
	for b: AABB in blockers:
		var t0 := 0.0
		var t1 := 1.0
		var hit := true
		for ax in 3:
			var o: float = from_l[ax]
			var dd: float = d[ax]
			var lo: float = b.position[ax]
			var hi: float = b.position[ax] + b.size[ax]
			if absf(dd) < 1e-6:
				if o < lo or o > hi:
					hit = false
					break
				continue
			var ta: float = (lo - o) / dd
			var tb: float = (hi - o) / dd
			if ta > tb:
				var sw := ta
				ta = tb
				tb = sw
			t0 = maxf(t0, ta)
			t1 = minf(t1, tb)
			if t0 > t1:
				hit = false
				break
		if hit:
			return true
	return false


func _yaw_of(d: Vector3) -> float:
	## The camera's yaw that looks along `d`. Same convention as set_mode().
	return atan2(-d.x, -d.z)


func _process_free(delta: float) -> void:
	var look := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	var fwd := -look.z
	var right := look.x

	var move := Vector3.ZERO
	move += fwd * Input.get_axis("boat_backward", "boat_forward")
	move += right * Input.get_axis("boat_left", "boat_right")
	if Input.is_key_pressed(KEY_E):
		move += Vector3.UP
	if Input.is_key_pressed(KEY_Q):
		move -= Vector3.UP
	var speed := free_speed * (3.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0)

	var cam_pos := _cam.global_position + move * speed * delta
	_clamp_and_place(cam_pos)
	_cam.global_basis = look


func _clamp_and_place(cam_pos: Vector3) -> void:
	if ocean != null:
		if mode == Mode.FREE:
			var floor_h: float = ocean.get_seafloor_height(cam_pos)
			cam_pos.y = maxf(cam_pos.y, floor_h + 0.45)
		else:
			var wh: float = ocean.get_height(cam_pos)
			cam_pos.y = maxf(cam_pos.y, wh + 0.6)
	_cam.global_position = cam_pos


func _update_blink(delta: float) -> void:
	if mode != Mode.FPS or _blink_rect == null or _blink_mat == null:
		return
	if _blink_tween != null and _blink_tween.is_running():
		_blink_mat.set_shader_parameter("close", _blink)
		_blink_rect.visible = _blink > 0.004
		return
	_blink_wait -= delta
	if _blink_wait <= 0.0:
		_start_blink()


func _start_blink() -> void:
	if _blink_tween != null:
		_blink_tween.kill()
	_blink = 0.0
	_blink_rect.visible = true
	_blink_tween = create_tween()
	_blink_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_blink_tween.tween_property(self, "_blink", 1.0, 0.055).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_blink_tween.tween_interval(0.035)
	_blink_tween.tween_property(self, "_blink", 0.0, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_blink_tween.finished.connect(_on_blink_finished, CONNECT_ONE_SHOT)


func _on_blink_finished() -> void:
	_blink = 0.0
	if _blink_mat != null:
		_blink_mat.set_shader_parameter("close", 0.0)
	if mode != Mode.FPS:
		_stop_blink()
		return
	if not _blink_again and randf() < 0.18:
		_blink_again = true
		_blink_wait = 0.10
		return
	_blink_again = false
	_blink_wait = randf_range(3.2, 8.5)
	if _blink_rect != null:
		_blink_rect.visible = false


func _stop_blink() -> void:
	if _blink_tween != null:
		_blink_tween.kill()
		_blink_tween = null
	_blink = 0.0
	_blink_again = false
	if _blink_mat != null:
		_blink_mat.set_shader_parameter("close", 0.0)
	if _blink_rect != null:
		_blink_rect.visible = false


func _build_underwater() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 0
	add_child(layer)
	_under_rect = ColorRect.new()
	_under_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_under_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_under_rect.color = Color(1, 1, 1, 1)
	_under_mat = ShaderMaterial.new()
	_under_mat.shader = load("res://shaders/underwater.gdshader")
	_under_rect.material = _under_mat
	_under_rect.visible = false
	layer.add_child(_under_rect)

	# Stove-heat grade. Only in FPS, and never over the underwater pass —
	# two screen-reads stacked is a smear, and you are not warm in the sea.
	_warm_rect = ColorRect.new()
	_warm_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_warm_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_warm_rect.color = Color(1, 1, 1, 1)
	_warm_mat = ShaderMaterial.new()
	_warm_mat.shader = load("res://shaders/warmth.gdshader")
	_warm_rect.material = _warm_mat
	_warm_rect.visible = false
	layer.add_child(_warm_rect)

	# The mask goes on TOP of both — it is between your eye and everything
	# else, including the water. Added last, so it draws last.
	_mask_rect = ColorRect.new()
	_mask_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mask_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mask_rect.color = Color(1, 1, 1, 1)
	_mask_mat = ShaderMaterial.new()
	_mask_mat.shader = load("res://shaders/dive_mask.gdshader")
	_mask_rect.material = _mask_mat
	_mask_rect.visible = false
	layer.add_child(_mask_rect)

	# Your own breath, so it is not positional — it happens inside your head.
	var inh: AudioStream = load("res://assets/audio/inhale.mp3")
	if inh != null:
		# Two voices off one clip: the draw through the regulator, and the same
		# breath let out — slower, deeper, quieter. That pair is the whole sound
		# of being under, and it is the reason a mask feels like a mask.
		_inhale = AudioStreamPlayer.new()
		_inhale.stream = inh
		_inhale.volume_db = -6.0
		add_child(_inhale)
		_exhale = AudioStreamPlayer.new()
		_exhale.stream = inh
		_exhale.volume_db = -13.0
		_exhale.pitch_scale = 0.74
		add_child(_exhale)


	_motes = GPUParticles3D.new()
	_motes.amount = 520
	_motes.lifetime = 5.5
	_motes.preprocess = 2.5
	_motes.emitting = false
	_motes.transform_align = GPUParticles3D.TRANSFORM_ALIGN_DISABLED
	_motes.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_motes.visibility_aabb = AABB(Vector3(-22, -14, -22), Vector3(44, 28, 44))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(10.0, 6.0, 10.0)
	pm.gravity = Vector3(0, -0.07, 0)
	pm.initial_velocity_min = 0.01
	pm.initial_velocity_max = 0.08
	pm.scale_min = 0.012
	pm.scale_max = 0.038
	pm.color = Color(0.52, 0.58, 0.54, 0.22)
	_motes.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.05, 0.05)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.disable_fog = true
	mat.albedo_color = Color(0.55, 0.62, 0.58, 0.28)
	q.material = mat
	_motes.draw_pass_1 = q
	add_child(_motes)
	_motes.top_level = true

	# Bubbles. Suspended motes tell you the water is dirty; bubbles tell you
	# which way is up, which is the thing you actually lose underwater.
	_bubbles = GPUParticles3D.new()
	_bubbles.amount = 140
	_bubbles.lifetime = 3.6
	_bubbles.preprocess = 1.8
	_bubbles.emitting = false
	_bubbles.transform_align = GPUParticles3D.TRANSFORM_ALIGN_DISABLED
	_bubbles.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_bubbles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bubbles.visibility_aabb = AABB(Vector3(-14, -10, -14), Vector3(28, 24, 28))
	var bpm := ParticleProcessMaterial.new()
	bpm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	bpm.emission_box_extents = Vector3(6.0, 4.0, 6.0)
	bpm.direction = Vector3(0, 1, 0)
	bpm.spread = 12.0
	bpm.initial_velocity_min = 0.25
	bpm.initial_velocity_max = 0.75
	bpm.gravity = Vector3(0, 1.1, 0)   # buoyancy, not gravity
	bpm.damping_min = 0.1
	bpm.damping_max = 0.4
	bpm.scale_min = 0.25
	bpm.scale_max = 1.0
	_bubbles.process_material = bpm
	var bq := SphereMesh.new()
	bq.radius = 0.016
	bq.height = 0.032
	bq.radial_segments = 6
	bq.rings = 3
	var bmat := StandardMaterial3D.new()
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.albedo_color = Color(0.78, 0.92, 0.95, 0.42)
	bmat.roughness = 0.05
	bmat.metallic = 0.0
	bmat.disable_fog = true
	bmat.rim_enabled = true
	bmat.rim = 0.9
	bq.material = bmat
	_bubbles.draw_pass_1 = bq
	add_child(_bubbles)
	_bubbles.top_level = true

	# The diver's own. Small, fast, and off the mouth.
	_breath = GPUParticles3D.new()
	_breath.amount = 40
	_breath.lifetime = 2.6
	_breath.emitting = false
	_breath.transform_align = GPUParticles3D.TRANSFORM_ALIGN_DISABLED
	_breath.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_breath.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_breath.visibility_aabb = AABB(Vector3(-3, -2, -3), Vector3(6, 14, 6))
	var rpm := ParticleProcessMaterial.new()
	rpm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	rpm.emission_sphere_radius = 0.05
	rpm.direction = Vector3(0, 1, 0)
	rpm.spread = 22.0
	rpm.initial_velocity_min = 0.35
	rpm.initial_velocity_max = 0.95
	rpm.gravity = Vector3(0, 1.6, 0)
	rpm.damping_min = 0.05
	rpm.damping_max = 0.25
	rpm.scale_min = 0.35
	rpm.scale_max = 1.25
	_breath.process_material = rpm
	_breath.draw_pass_1 = bq
	add_child(_breath)
	_breath.top_level = true


func _update_underwater() -> void:
	if ocean == null or _cam == null:
		return
	var wh: float = ocean.get_height(_cam.global_position)
	var under := _cam.global_position.y < wh - 0.05
	var depth := wh - _cam.global_position.y
	ocean.camera_under = under
	if weather != null and weather.has_method("set_underwater"):
		weather.set_underwater(under)
	if _under_rect != null:
		_under_rect.visible = under
	if _warm_rect != null and under:
		_warm_rect.visible = false
	if under and _under_mat != null:
		_under_mat.set_shader_parameter("amount", 1.0)
		_under_mat.set_shader_parameter("wave_time", ocean.wave_time)
		_under_mat.set_shader_parameter("depth_m", depth)
		_under_mat.set_shader_parameter("look_down",
				clampf(-_cam.global_basis.z.y, 0.0, 1.0))
	if _motes != null:
		_motes.emitting = under
		if under:
			_motes.global_position = _cam.global_position
	if _bubbles != null:
		_bubbles.emitting = under
		if under:
			_bubbles.global_position = _cam.global_position + Vector3(0.0, -2.0, 0.0)
	_update_breath(under)
	_update_mask(get_process_delta_time(), under)
	if under and _under_mat != null and weather != null and weather.has_method("sun_direction"):
		# Light shafts have to point at the real sun, so project it to screen.
		var sd: Vector3 = weather.sun_direction()
		var vp := get_viewport().get_visible_rect().size
		var ss := Vector2(0.5, -0.35)
		var local := _cam.global_basis.inverse() * sd
		if local.z < -0.05:  # in front of the camera
			var p2 := _cam.unproject_position(_cam.global_position + sd * 200.0)
			ss = Vector2(p2.x / maxf(vp.x, 1.0), p2.y / maxf(vp.y, 1.0))
			ss = ss.clamp(Vector2(-1.0, -1.0), Vector2(2.0, 2.0))
		_under_mat.set_shader_parameter("sun_screen", ss)
		_under_mat.set_shader_parameter("shaft_energy", 1.05 if sd.y > 0.05 else 0.22)


func _update_mask(delta: float, under: bool) -> void:
	## The mask, from the moment it leaves the hook to the finger that clears
	## it. Nothing here decides whether you are WEARING it — boat.gd owns that,
	## because the thing is either on the hook or on your face and one of those
	## is a fitting on the ship.
	if _mask_rect == null or target == null:
		return
	var wear: float = float(target.call("gear_wear_t")) if target.has_method("gear_wear_t") \
			else 0.0
	var worn: bool = wear > 0.001 and mode == Mode.FPS
	_mask_rect.visible = worn
	if not worn:
		_fog = 0.0
		_wipe = 0.0
		_drops = 0.0
		_drop_wipe = 0.0
		_br_t = 0.0
		_br_in = true
		_breath_amt = 0.0
		_mask_was_under = false
		return
	_breathe(delta, under)
	if under and not _mask_was_under:
		_drops = 1.0
	_mask_was_under = under
	if under:
		_drops = minf(_drops + delta * 1.6, 1.0)
	else:
		var rain_now := 0.0
		if weather != null:
			rain_now = clampf(float(weather.get("rain_amount")), 0.0, 1.0)
		_drops = minf(_drops + rain_now * delta * 0.40, 0.92)
		_drops = maxf(_drops - delta * 0.018 * (1.0 - rain_now), 0.0)
	if _drop_wipe > 0.0:
		_drop_wipe = maxf(_drop_wipe - delta / 0.9, 0.0)
		if _drop_wipe <= 0.0:
			# A wipe takes the middle. Corners and the skirt keep their beads.
			_drops = maxf(_drops * 0.20, 0.14)
	# Condensation. It only really builds once the glass is cold, which is to
	# say in the water; in air it creeps.
	if _wipe > 0.0:
		_wipe = maxf(_wipe - delta / 0.9, 0.0)
		if _wipe <= 0.0:
			# Fog wipe does not touch the water on the glass. What is left of
			# the vapour is a film in the corners, which is where it starts again.
			_fog = 0.08
	elif wear > 0.98:
		# Same clock in air and water: the front crawls from the skirt over
		# minutes. A dive does not ice the glass; it is still your breath.
		_fog = minf(_fog + delta / FOG_DRY, 1.0)
		if not _br_in:
			_fog = minf(_fog + delta * 0.006, 1.0)
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_mask_mat.set_shader_parameter("wear", wear)
	_mask_mat.set_shader_parameter("fog", _fog)
	_mask_mat.set_shader_parameter("wipe", _wipe)
	_mask_mat.set_shader_parameter("drops", _drops)
	_mask_mat.set_shader_parameter("drop_wipe", _drop_wipe)
	# The clear front is the FINGER, not a timer. Ask the hand where it is.
	if (_wipe > 0.0 or _drop_wipe > 0.0) and _arms != null \
			and _arms.has_method("wipe_front"):
		var wf: Vector2 = _arms.wipe_front()
		_mask_mat.set_shader_parameter("wipe_x", wf.x)
		_mask_mat.set_shader_parameter("wipe_dir", wf.y)
	_mask_mat.set_shader_parameter("underwater", 1.0 if under else 0.0)
	_mask_mat.set_shader_parameter("aspect", maxf(vp.x, 1.0) / maxf(vp.y, 1.0))
	if ocean != null:
		_mask_mat.set_shader_parameter("wave_time", ocean.wave_time)
	var rain_amt := 0.0
	if weather != null:
		rain_amt = clampf(float(weather.get("rain_amount")), 0.0, 1.0)
	_mask_mat.set_shader_parameter("rain", rain_amt)
	_breath_amt = lerpf(_breath_amt, 1.0 if not _br_in else 0.0,
			1.0 - exp(-delta * (3.2 if under else 1.6)))
	_mask_mat.set_shader_parameter("breath", _breath_amt)


func _breathe(delta: float, under: bool) -> void:
	## In, pause, out, longer pause. Underwater you hear it through the
	## regulator. On deck you still breathe — the glass fogs from that, silently.
	_br_t -= delta
	if _br_t > 0.0:
		return
	if _br_in:
		if under and _inhale != null:
			_inhale.pitch_scale = randf_range(0.94, 1.07)
			_inhale.volume_db = randf_range(-8.0, -5.0)
			_inhale.play()
		_br_t = randf_range(1.30, 1.75) if under else randf_range(2.8, 4.2)
	else:
		if under and _exhale != null:
			_exhale.pitch_scale = randf_range(0.70, 0.80)
			_exhale.volume_db = randf_range(-15.0, -11.5)
			_exhale.play()
		_br_t = randf_range(2.10, 2.95) if under else randf_range(3.4, 5.0)
	_br_in = not _br_in


func _wipe_mask() -> void:
	## A finger across the inside of the glass. Only worth doing if there is
	## something on it.
	if _fog < 0.09 or _wipe > 0.0 or _drop_wipe > 0.0:
		return
	_wipe = 1.0
	# Where the NEXT one happens. Somewhere between a lens that is just going
	# hazy and one you cannot see out of at all.
	_wipe_at = randf_range(0.72, 0.96)
	if _arms != null and _arms.has_method("face_gesture"):
		_arms.face_gesture("wipe")


func _wipe_drops() -> void:
	## Water on the glass is not fog. A fog wipe leaves it; this is the pass
	## that takes the beads, and even then the skirt keeps a few.
	if not bool(target.get("gear_worn")) or _drops < 0.12:
		return
	if _wipe > 0.0 or _drop_wipe > 0.0:
		return
	_drop_wipe = 1.0
	if _arms != null and _arms.has_method("face_gesture"):
		_arms.face_gesture("wipe")


func _update_breath(under: bool) -> void:
	## Bubbles off your own face, but only when it is YOU in the water — the
	## free camera goes under too and it does not breathe.
	if _breath == null or _cam == null:
		return
	var diver: bool = mode == Mode.FPS and _walker != null \
			and (bool(_walker.get("swimming")) or bool(_walker.get("on_sea_ladder")))
	var sub: bool = diver and under
	if sub and not _was_sub:
		_breath_burst = 0.75
		_breath.restart()
		# The breath itself is on its own cycle in _breathe(); this is only the
		# lungful of bubbles that goes with the water closing over you.
		_br_t = 0.0
	_was_sub = sub
	_breath_burst = maxf(_breath_burst - get_process_delta_time(), 0.0)
	_breath.emitting = sub
	# One lungful as the water closes over you, then the slow leak of a held
	# breath. amount_ratio IS the emission rate, so this is literally that.
	_breath.amount_ratio = 1.0 if _breath_burst > 0.0 else 0.18
	if sub:
		_breath.global_position = _cam.global_position \
				+ (-_cam.global_basis.z) * 0.17 - _cam.global_basis.y * 0.09


func _update_warmth(delta: float) -> void:
	## Body heat. The stove fills the cabin over tens of seconds; the deck and
	## the sea take it back faster. No number on a panel — you feel it the way
	## you feel a fire, as colour on the face.
	if target == null or not target.has_method("heat_at"):
		return
	var src := 0.0
	var tau := 8.0
	if _walker.swimming:
		src = 0.0
		tau = 2.2
	else:
		src = float(target.heat_at(_walker.pos))
		if src < 0.05 and weather != null:
			src = maxf(src - clampf(float(weather.get("rain_amount")), 0.0, 1.0) * 0.10, 0.0)
		tau = 9.5 if src > _warmth else 6.5
	_warmth = lerpf(_warmth, src, 1.0 - exp(-delta / tau))
	if _warm_rect == null or _warm_mat == null:
		return
	var show := _warmth > 0.16
	_warm_rect.visible = show
	if not show:
		return
	var close := clampf((_warmth - 0.72) / 0.28, 0.0, 1.0)
	_warm_mat.set_shader_parameter("warmth", clampf((_warmth - 0.16) / 0.84, 0.0, 1.0))
	_warm_mat.set_shader_parameter("close", close)
	if ocean != null:
		_warm_mat.set_shader_parameter("wave_time", ocean.wave_time)











