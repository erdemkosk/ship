extends Node3D
## Makine dairesi under the companionway: a dry 3-cyl marine diesel on beds,
## open on the inboard face so the crank and pistons read from the cabin.
## Motion is driven from the boat's engine state — not a canned clip.

const CRANK_R := 0.052
const ROD := 0.148
const CYL_Z := [-0.195, 0.0, 0.195]

var _crank: Node3D
var _fly: Node3D
var _alt: Node3D
var _pistons: Array[Node3D] = []
var _rods: Array[Node3D] = []
var _angle := 0.0
var _lamp: OmniLight3D
var _lamp_mat: StandardMaterial3D
var _door_open := false


func _ready() -> void:
	_build()


func set_door(open: bool) -> void:
	## The lamp answers the door: cracked open for a look, the well lights up
	## the way you would flick the fixture on stepping down to check the oil.
	_door_open = open


func drive(state: int, shaft_rpm: float, delta: float) -> void:
	## state matches boat.EngineState: 0 off, 1 cranking, 2 running.
	var spd := 0.0
	if state == 1:
		spd = 9.5
	elif state == 2:
		spd = 14.0 + absf(shaft_rpm) * 26.0
	_angle = fmod(_angle + spd * delta, TAU)
	if _crank != null:
		_crank.rotation.z = _angle
	if _fly != null:
		_fly.rotation.z = _angle
	if _alt != null:
		_alt.rotation.z = _angle * 2.4
	_pose_rods()
	if _lamp != null:
		var on := state != 0
		var want := 0.45
		if _door_open:
			want = 1.6
		elif on:
			want = 1.1
		_lamp.light_energy = lerpf(_lamp.light_energy, want, 1.0 - exp(-8.0 * delta))
		if _lamp_mat != null:
			_lamp_mat.emission_energy_multiplier = 2.6 if _door_open else (1.4 if on else 0.7)


func _build() -> void:
	# Enamel, not rust. A boat that is lived in keeps the engine wiped down.
	var iron := _mat(Color(0.16, 0.18, 0.155), 0.42, 0.22)
	var green := _mat(Color(0.12, 0.16, 0.12), 0.38, 0.08)
	var cover := _mat(Color(0.08, 0.09, 0.08), 0.48, 0.12)
	var steel := _mat(Color(0.22, 0.23, 0.24), 0.32, 0.72)
	var bronze := _mat(Color(0.42, 0.32, 0.16), 0.34, 0.78)
	var brass := _mat(Color(0.55, 0.46, 0.22), 0.28, 0.82)
	var black := _mat(Color(0.07, 0.07, 0.07), 0.55, 0.25)
	var lag := _mat(Color(0.62, 0.58, 0.48), 0.88, 0.0)
	var plate := _mat(Color(0.18, 0.175, 0.16), 0.55, 0.15)
	var wood := _mat(Color(0.18, 0.12, 0.07), 0.78, 0.0)
	var alum := _mat(Color(0.50, 0.51, 0.50), 0.62, 0.35)

	# Painted sole under the well, and timber beds. Dry.
	_box(Vector3(1.14, 0.03, 1.55), Vector3(-1.08, 0.695, 2.18), Vector3.ZERO, plate)
	for s in [-1.0, 1.0]:
		_box(Vector3(0.10, 0.07, 1.28), Vector3(-1.08 + s * 0.22, 0.745, 2.18),
				Vector3.ZERO, wood)
		_box(Vector3(0.08, 0.04, 1.22), Vector3(-1.08 + s * 0.22, 0.795, 2.18),
				Vector3.ZERO, steel)

	# Fore and aft bulkheads, sole to the stair soffit. The aft one used to
	# stop at 1.31 — a half-wall under the flight, with the machine showing
	# in the triangle above it.
	_box(Vector3(1.14, 1.90, 0.04), Vector3(-1.08, 1.65, 1.42), Vector3.ZERO, wood)
	_box(Vector3(1.14, 0.78, 0.04), Vector3(-1.08, 1.09, 2.92), Vector3.ZERO, wood)

	var eng := Node3D.new()
	eng.position = Vector3(-1.05, 1.02, 2.16)
	add_child(eng)

	# Castings live OUTBOARD. The inboard half is a cutaway: from the hatch
	# you read the crank, the rods and the three pistons, not a closed block
	# with a window that only showed the shaft.
	_box(Vector3(0.22, 0.14, 0.72), Vector3(-0.16, -0.20, 0.0), Vector3.ZERO, iron, eng)
	_box(Vector3(0.22, 0.28, 0.70), Vector3(-0.16, 0.00, 0.0), Vector3.ZERO, green, eng)
	_box(Vector3(0.20, 0.10, 0.68), Vector3(-0.15, 0.18, 0.0), Vector3.ZERO, iron, eng)
	_box(Vector3(0.18, 0.07, 0.64), Vector3(-0.14, 0.26, 0.0), Vector3.ZERO, cover, eng)
	# Injector pump and rail along the outboard side.
	_box(Vector3(0.08, 0.12, 0.42), Vector3(-0.24, 0.08, 0.02), Vector3.ZERO, black, eng)
	for i in 3:
		_cyl(0.012, 0.012, 0.16, Vector3(-0.20, 0.22, CYL_Z[i]),
				Vector3(0.0, 0.0, 18.0), black, eng)
	# Heat exchanger sits ON the remaining block, not over the open bores.
	_cyl(0.055, 0.055, 0.38, Vector3(-0.14, 0.34, 0.12), Vector3(90.0, 0.0, 0.0), alum, eng)
	_cyl(0.058, 0.058, 0.04, Vector3(-0.14, 0.34, -0.08), Vector3(90.0, 0.0, 0.0), bronze, eng)
	_cyl(0.058, 0.058, 0.04, Vector3(-0.14, 0.34, 0.32), Vector3(90.0, 0.0, 0.0), bronze, eng)
	# Raw-water pump.
	_cyl(0.045, 0.045, 0.07, Vector3(0.18, -0.04, 0.38), Vector3(90.0, 0.0, 0.0), bronze, eng)
	# Fuel filters, dry and brass-bowled.
	_cyl(0.032, 0.028, 0.11, Vector3(0.20, 0.02, -0.18), Vector3.ZERO, black, eng)
	_cyl(0.030, 0.030, 0.05, Vector3(0.20, -0.06, -0.18), Vector3.ZERO, brass, eng)
	_cyl(0.032, 0.028, 0.11, Vector3(0.20, 0.02, -0.32), Vector3.ZERO, black, eng)
	_cyl(0.030, 0.030, 0.05, Vector3(0.20, -0.06, -0.32), Vector3.ZERO, brass, eng)
	# Starter, low on the flywheel side.
	_cyl(0.04, 0.04, 0.16, Vector3(-0.16, -0.06, 0.42), Vector3(90.0, 0.0, 0.0), black, eng)
	# Wet exhaust, lagged: a short riser off the manifold, then hard AFT and low
	# to the waterlock. The first route climbed instead — to y 1.91 in boat
	# space, which is inside the fourth companionway tread. The pipe came up
	# through the stairs you walk on; --probe-engine names it in one line.
	_cyl(0.042, 0.042, 0.06, Vector3(-0.10, 0.22, 0.42), Vector3(0.0, 0.0, 28.0), steel, eng)
	_cyl(0.038, 0.038, 0.16, Vector3(-0.12, 0.29, 0.44), Vector3(0.0, 0.0, 20.0), lag, eng)
	# The aft run DESCENDS as it goes, the way a wet exhaust must so the lock
	# stays the low point. It also has to: the treads come down to meet it, and
	# tread 2's underside is at y 1.289 in boat space over this very spot.
	_cyl(0.036, 0.036, 0.40, Vector3(-0.16, 0.30, 0.62), Vector3(80.0, 0.0, 0.0), lag, eng)
	# Waterlock against the aft bulkhead, and the tail hose leaving through it.
	_box(Vector3(0.16, 0.16, 0.14), Vector3(-0.16, 0.14, 0.83), Vector3.ZERO, black, eng)
	_cyl(0.030, 0.030, 0.10, Vector3(-0.16, 0.14, 0.93), Vector3(90.0, 0.0, 0.0), black, eng)

	# Cutaway frame around crank AND bores, so the whole motion reads.
	_box(Vector3(0.018, 0.52, 0.018), Vector3(0.02, 0.08, -0.36), Vector3.ZERO, steel, eng)
	_box(Vector3(0.018, 0.52, 0.018), Vector3(0.02, 0.08, 0.36), Vector3.ZERO, steel, eng)
	_box(Vector3(0.018, 0.018, 0.74), Vector3(0.02, -0.17, 0.0), Vector3.ZERO, steel, eng)
	_box(Vector3(0.018, 0.018, 0.74), Vector3(0.02, 0.33, 0.0), Vector3.ZERO, steel, eng)
	# Open bores: three walls each, inboard face left off so the piston is
	# the thing you see from the hatch.
	for z in CYL_Z:
		_box(Vector3(0.11, 0.24, 0.012), Vector3(-0.04, 0.16, z - 0.058), Vector3.ZERO, iron, eng)
		_box(Vector3(0.11, 0.24, 0.012), Vector3(-0.04, 0.16, z + 0.058), Vector3.ZERO, iron, eng)
		_box(Vector3(0.012, 0.24, 0.104), Vector3(-0.09, 0.16, z), Vector3.ZERO, iron, eng)

	_crank = Node3D.new()
	_crank.position = Vector3(0.0, 0.0, 0.0)
	eng.add_child(_crank)
	_cyl(0.028, 0.028, 0.68, Vector3.ZERO, Vector3(90.0, 0.0, 0.0), steel, _crank)
	for i in 3:
		var pin := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.018
		pm.bottom_radius = 0.018
		pm.height = 0.046
		pm.radial_segments = 10
		pm.material = steel
		pin.mesh = pm
		pin.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		pin.position = Vector3(CRANK_R, 0.0, CYL_Z[i])
		_crank.add_child(pin)
		var web := MeshInstance3D.new()
		var wm := BoxMesh.new()
		wm.size = Vector3(CRANK_R * 2.0 + 0.02, 0.034, 0.028)
		wm.material = iron
		web.mesh = wm
		web.position = Vector3(CRANK_R * 0.5, 0.0, CYL_Z[i])
		_crank.add_child(web)

	_fly = Node3D.new()
	_fly.position = Vector3(0.0, 0.0, 0.42)
	eng.add_child(_fly)
	_cyl(0.16, 0.16, 0.045, Vector3.ZERO, Vector3(90.0, 0.0, 0.0), iron, _fly)
	_cyl(0.168, 0.168, 0.018, Vector3(0.0, 0.0, 0.0), Vector3(90.0, 0.0, 0.0), steel, _fly)
	# Coupling aft of the flywheel, toward the shaft log.
	_cyl(0.055, 0.055, 0.06, Vector3(0.0, 0.0, 0.55), Vector3(90.0, 0.0, 0.0), steel, eng)
	_cyl(0.022, 0.022, 0.28, Vector3(0.0, -0.08, 0.78), Vector3(72.0, 0.0, 0.0), steel, eng)

	_alt = Node3D.new()
	_alt.position = Vector3(0.16, 0.10, -0.40)
	eng.add_child(_alt)
	_cyl(0.05, 0.05, 0.11, Vector3.ZERO, Vector3(90.0, 0.0, 0.0), black, _alt)
	_cyl(0.042, 0.042, 0.018, Vector3(0.0, 0.0, -0.06), Vector3(90.0, 0.0, 0.0), steel, _alt)

	var piston_crown := _mat(Color(0.62, 0.60, 0.52), 0.28, 0.55)
	var piston_skirt := _mat(Color(0.28, 0.27, 0.24), 0.40, 0.35)
	for i in 3:
		var p := Node3D.new()
		eng.add_child(p)
		_cyl(0.050, 0.050, 0.028, Vector3(0.0, 0.018, 0.0), Vector3.ZERO, piston_crown, p)
		_cyl(0.048, 0.048, 0.055, Vector3(0.0, -0.022, 0.0), Vector3.ZERO, piston_skirt, p)
		_cyl(0.051, 0.051, 0.008, Vector3(0.0, 0.002, 0.0), Vector3.ZERO, steel, p)
		_box(Vector3(0.036, 0.022, 0.036), Vector3(0.0, -0.055, 0.0), Vector3.ZERO, iron, p)
		_pistons.append(p)
		var r := Node3D.new()
		eng.add_child(r)
		_cyl(0.015, 0.015, ROD, Vector3.ZERO, Vector3.ZERO, steel, r)
		_rods.append(r)

	# Drip tray under the pan — every dry bilge has one, and it is what says
	# "kept", not "abandoned".
	_box(Vector3(0.46, 0.018, 0.86), Vector3(-0.05, -0.295, 0.0), Vector3.ZERO, steel, eng)
	_box(Vector3(0.42, 0.012, 0.82), Vector3(-0.05, -0.286, 0.0), Vector3.ZERO, black, eng)
	# Battery box forward, strapped, with its two cables running to the starter.
	_box(Vector3(0.26, 0.20, 0.34), Vector3(-0.03, -0.155, -0.62), Vector3.ZERO, wood, eng)
	_box(Vector3(0.24, 0.04, 0.30), Vector3(-0.03, -0.03, -0.62), Vector3.ZERO, black, eng)
	_box(Vector3(0.28, 0.03, 0.06), Vector3(-0.03, -0.02, -0.62), Vector3.ZERO, steel, eng)
	_cyl(0.009, 0.009, 0.52, Vector3(-0.10, -0.05, -0.36), Vector3(78.0, 0.0, 8.0),
			_mat(Color(0.45, 0.08, 0.06), 0.6), eng)
	_cyl(0.009, 0.009, 0.48, Vector3(-0.16, -0.09, -0.34), Vector3(80.0, 0.0, -6.0), black, eng)
	# Oil can and a folded rag on the aft bed — the story of the last check.
	_cyl(0.038, 0.030, 0.10, Vector3(0.24, -0.21, 0.58), Vector3.ZERO, alum, eng)
	_cyl(0.006, 0.006, 0.07, Vector3(0.26, -0.13, 0.56), Vector3(0.0, 0.0, 38.0), alum, eng)
	_box(Vector3(0.14, 0.02, 0.10), Vector3(0.06, -0.245, 0.60), Vector3(0.0, 24.0, 0.0),
			_mat(Color(0.55, 0.50, 0.42), 0.9), eng)

	# Builder plate.
	var tag := Label3D.new()
	tag.text = "3 CYL DIESEL"
	tag.font_size = 28
	tag.pixel_size = 0.00055
	tag.modulate = Color(0.78, 0.70, 0.42)
	tag.position = Vector3(-0.04, 0.02, 0.0)
	tag.rotation_degrees = Vector3(0.0, 90.0, 0.0)
	tag.shaded = false
	eng.add_child(tag)

	# Bulkhead lamp on the fore wall. The old one hung in the hatch mouth
	# with no rose and no wire — a glowing egg in empty air.
	_lamp_mat = _mat(Color(0.85, 0.82, 0.70), 0.35)
	_lamp_mat.emission_enabled = true
	_lamp_mat.emission = Color(1.0, 0.92, 0.72)
	_lamp_mat.emission_energy_multiplier = 0.7
	_box(Vector3(0.05, 0.04, 0.04), Vector3(-1.22, 1.86, 1.45), Vector3.ZERO, black)
	_cyl(0.016, 0.016, 0.06, Vector3(-1.22, 1.80, 1.48), Vector3(18.0, 0.0, 0.0), black)
	_cyl(0.048, 0.040, 0.08, Vector3(-1.22, 1.72, 1.52), Vector3(12.0, 0.0, 0.0), _lamp_mat)
	_lamp = OmniLight3D.new()
	_lamp.position = Vector3(-1.18, 1.68, 1.62)
	_lamp.light_color = Color(1.0, 0.93, 0.78)
	_lamp.light_energy = 0.55
	_lamp.omni_range = 2.4
	_lamp.omni_attenuation = 1.8
	_lamp.shadow_enabled = false
	add_child(_lamp)

	_pose_rods()


func _pose_rods() -> void:
	for i in _pistons.size():
		var a := _angle + float(i) * TAU / 3.0
		var pin := Vector3(CRANK_R * sin(a), CRANK_R * cos(a), CYL_Z[i])
		var py: float = pin.y + sqrt(maxf(ROD * ROD - pin.x * pin.x, 1e-6))
		var top := Vector3(0.0, py, CYL_Z[i])
		_pistons[i].position = top
		var mid := (pin + top) * 0.5
		_rods[i].position = mid
		var d := top - pin
		_rods[i].rotation = Vector3(0.0, 0.0, atan2(-d.x, d.y))


func _mat(albedo: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = rough
	m.metallic = metal
	return m


func _cyl(r_bot: float, r_top: float, h: float, pos: Vector3, rot_deg: Vector3,
		mat: Material, parent: Node3D = null) -> void:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.bottom_radius = r_bot
	m.top_radius = r_top
	m.height = h
	m.radial_segments = 12
	m.rings = 1
	m.material = mat
	mi.mesh = m
	mi.position = pos
	mi.rotation_degrees = rot_deg
	(parent if parent != null else self).add_child(mi)


func _box(size: Vector3, pos: Vector3, rot_deg: Vector3, mat: Material,
		parent: Node3D = null) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	mi.rotation_degrees = rot_deg
	(parent if parent != null else self).add_child(mi)
