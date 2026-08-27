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

var target: Node3D
var ocean: Node3D
var weather: Node3D
var mode: int = Mode.FOLLOW
var free_mode := false  # read by boat.gd: true only in FREE mode

var yaw := 0.0
var pitch := -0.22
var dist := 16.0
var free_speed := 14.0



var _cam: Camera3D
var _orbiting := false
var _under_rect: ColorRect
var _under_mat: ShaderMaterial
var _warm_rect: ColorRect
var _warm_mat: ShaderMaterial
var _warmth := 0.22
var _motes: GPUParticles3D
var _prompt: Label
var _status: Label
var _hud_t := 0.0
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

	# Ship's state, top left: what every circuit is doing and which key works
	# it. A boat has no menus — this is the panel you glance at.
	_status = Label.new()
	_status.position = Vector2(14, 44)
	_status.add_theme_font_size_override("font_size", 14)
	_status.add_theme_color_override("font_color", Color(0.92, 0.72, 0.44))
	_status.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_status.add_theme_constant_override("outline_size", 4)
	_status.add_theme_constant_override("line_spacing", 3)
	pl.add_child(_status)



func set_mode(m: int) -> void:
	mode = m
	free_mode = mode == Mode.FREE
	match mode:
		Mode.FPS:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			_eye_ready = false
			_bob = 0.0
			_roll = 0.0
			# start looking where the boat points, standing at the wheel
			if target != null:
				var fwd := -target.global_basis.z
				yaw = atan2(-fwd.x, -fwd.z)
				_walker.spawn_at(target.CREW_START)
				target.set("helm_engaged", true)
				target.set("telegraph_engaged", false)
			pitch = 0.0
		Mode.FREE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			if target != null:
				target.set("helm_engaged", true)
				target.set("telegraph_engaged", false)
			if _prompt != null:
				_prompt.visible = false
			var fwd := -_cam.global_basis.z
			yaw = atan2(-fwd.x, -fwd.z)
			pitch = asin(clampf(fwd.y, -1.0, 1.0))
		_:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			if target != null:
				target.set("helm_engaged", true)
				target.set("telegraph_engaged", false)
			if _prompt != null:
				_prompt.visible = false
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
			# direct mouse look, no button needed
			yaw -= event.relative.x * 0.0035
			pitch = clampf(pitch - event.relative.y * 0.0035, -1.4, 1.4)
		elif _orbiting:
			yaw -= event.relative.x * 0.005
			if mode == Mode.FREE:
				pitch = clampf(pitch - event.relative.y * 0.005, -1.5, 1.5)
			else:
				pitch = clampf(pitch - event.relative.y * 0.005, -1.15, 0.45)
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
	_update_status(delta)
	if mode != Mode.FPS and _warm_rect != null:
		_warm_rect.visible = false


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
			var to: Vector3 = it["pos"] - eye
			var along := look_l.dot(to)
			if along <= 0.02 or along > 2.2:
				continue
			var rr: float = float(it["r"]) * (1.0 + sway)
			if iid == _last_aim:
				rr *= 1.75
			if (to - look_l * along).length() > rr:
				continue
			# The key sits next to the wheel. Nearest-along always picks the
			# helm first; a look toward the barrel should take the ignition.
			var take := along < nearest
			if iid == "ignition" and str(cand.get("id", "")) == "helm":
				take = true
			if take:
				nearest = along
				cand = it
		_last_aim = str(cand["id"]) if not cand.is_empty() else ""

	if Input.is_action_just_pressed("use"):
		if not cand.is_empty() and str(cand["id"]) == "ignition" \
				and target.has_method("toggle_switch"):
			target.toggle_switch("ignition")
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
			match cand["id"]:
				"helm":
					target.set("helm_engaged", true)
				"telegraph":
					target.set("telegraph_engaged", true)
				"chart":
					target.set("chart_engaged", true)
				"radio":
					target.set("radio_held", not bool(target.get("radio_held")))
				"windlass":
					var tk: Node = target.get("tackle")
					if tk != null:
						tk.toggle()
				"lights":
					if target.has_method("toggle_lights"):
						target.toggle_lights()
				_:
					# Every switch on the console routes to the same circuit its
					# keyboard shortcut throws — one system, two ways in.
					var cid := str(cand["id"])
					if (cid.begins_with("sw_") or cid.begins_with("door_")) \
							and target.has_method("toggle_switch"):
						target.toggle_switch(str(cand["id"]))
		engaged = "helm" if target.get("helm_engaged") \
				else ("telegraph" if target.get("telegraph_engaged") \
				else ("chart" if target.get("chart_engaged") else ""))

	if _prompt != null:
		if _walker.get("swimming"):
			_prompt.text = "SPACE — küpeşteden tırman" if _walker.get("can_board") \
					else "Denizdesin — tekneye yüz"
			_prompt.visible = true
		elif engaged == "helm":
			if not cand.is_empty() and str(cand["id"]) == "ignition":
				var st := int(target.get("engine"))
				_prompt.text = "E — Kontak  (%s)" % (
						"durdur" if st == 2 else ("bekleniyor" if st == 1 else "çalıştır"))
			else:
				_prompt.text = "E — dümeni bırak"
			_prompt.visible = true
		elif engaged == "telegraph":
			_prompt.text = "E — gaz kolunu bırak"
			_prompt.visible = true
		elif engaged == "chart":
			_prompt.text = "E — haritadan kalk"
			_prompt.visible = true
		elif bool(target.get("radio_held")) and cand.is_empty():
			_prompt.text = "Telsiz elinde — kordonu var, fazla uzaklaşma"
			_prompt.visible = true
		elif not cand.is_empty():
			if cand["id"] == "radio" and bool(target.get("radio_held")):
				_prompt.text = "E — telsizi yerine as"
			elif str(cand["id"]) == "ignition":
				var st := int(target.get("engine"))
				_prompt.text = "E — Kontak  (%s)" % (
						"durdur" if st == 2 else ("bekleniyor" if st == 1 else "çalıştır"))
			elif (str(cand["id"]).begins_with("sw_") or str(cand["id"]).begins_with("door_")) \
					and target.has_method("switch_state"):
				_prompt.text = "E — %s  (%s)" % [cand["name"],
						"kapat" if target.switch_state(str(cand["id"])) else "aç"]
			else:
				_prompt.text = "E — %s" % cand["name"]
			_prompt.visible = true
		else:
			_prompt.visible = false

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
		_walker.update(delta, target, wish,
				Input.is_action_just_pressed("jump") and not _panel_open())

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
	if ocean != null:
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

	var heel := asin(clampf(xf.basis.x.y, -1.0, 1.0))
	_roll = lerpf(_roll, clampf(heel * 0.34, -0.13, 0.13), 1.0 - exp(-6.0 * delta))
	_cam.global_basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) \
			* Basis(Vector3.BACK, _roll)
	_update_warmth(delta)


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


func _update_status(delta: float) -> void:
	if _status == null:
		return
	var show := mode != Mode.FREE and target != null
	_status.visible = show
	if not show:
		return
	_hud_t -= delta
	if _hud_t > 0.0:
		return
	_hud_t = 0.25

	var tackle: Node = target.get("tackle")
	var anchor := "içeride"
	if tackle != null and tackle.has_method("status"):
		var st: String = tackle.status()
		if st != "":
			anchor = st
	var rows := [
		"ÇAPA  [G]   %s" % anchor,
		"",
		"KAMARA      [1]  %s" % _on(target.get("light_cabin")),
		"DÜMEN EVİ   [2]  %s" % _on(target.get("light_helm")),
		"İKAZ FENERİ [3]  %s" % _on(target.get("light_beacon")),
		"PROJEKTÖR   [6]  %s" % _on(target.get("light_flood")),
		"SİLECEK     [5]  %s" % _on(target.get("wiper_on")),
	]
	_status.text = "\n".join(rows)


func _on(v: Variant) -> String:
	return "● açık" if bool(v) else "○ kapalı"


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


	_motes = GPUParticles3D.new()
	_motes.amount = 90
	_motes.lifetime = 4.5
	_motes.preprocess = 2.0
	_motes.emitting = false
	_motes.transform_align = GPUParticles3D.TRANSFORM_ALIGN_DISABLED
	_motes.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_motes.visibility_aabb = AABB(Vector3(-18, -12, -18), Vector3(36, 24, 36))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(8.0, 5.0, 8.0)
	pm.gravity = Vector3(0, 0.12, 0)
	pm.initial_velocity_min = 0.02
	pm.initial_velocity_max = 0.12
	pm.scale_min = 0.015
	pm.scale_max = 0.045
	pm.color = Color(0.7, 0.85, 0.82, 0.22)
	_motes.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.04, 0.04)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_color = Color(0.75, 0.9, 0.88, 0.28)
	q.material = mat
	_motes.draw_pass_1 = q
	add_child(_motes)
	_motes.top_level = true

	# Bubbles. Suspended motes tell you the water is dirty; bubbles tell you
	# which way is up, which is the thing you actually lose underwater.
	_bubbles = GPUParticles3D.new()
	_bubbles.amount = 70
	_bubbles.lifetime = 3.2
	_bubbles.preprocess = 1.5
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
	bmat.albedo_color = Color(0.72, 0.88, 0.92, 0.30)
	bmat.roughness = 0.05
	bmat.metallic = 0.0
	bmat.rim_enabled = true
	bmat.rim = 0.9
	bq.material = bmat
	_bubbles.draw_pass_1 = bq
	add_child(_bubbles)
	_bubbles.top_level = true


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
	if _motes != null:
		_motes.emitting = under
		if under:
			_motes.global_position = _cam.global_position
	if _bubbles != null:
		_bubbles.emitting = under
		if under:
			_bubbles.global_position = _cam.global_position + Vector3(0.0, -2.0, 0.0)
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
		_under_mat.set_shader_parameter("shaft_energy", 0.7 if sd.y > 0.05 else 0.15)


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











