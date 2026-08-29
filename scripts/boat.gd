extends RigidBody3D
## Small wooden boat. Buoyancy at hull + deck probes; W/S thrust, A/D rudder.
## Rolls with the swell. Past vanishing stability it capsizes.

# Hull bottom + deck probes. Deck samples (y > 0) only matter when inverted —
# they keep a capsized boat floating instead of falling through.
#
# Everything here is in metres on a 9 m hull whose origin sits at the design
# waterline, so a probe at y = -0.62 is the keel and y = +0.6 is the deck.
const PROBES: Array[Vector3] = [
	Vector3(1.66, -0.62, 4.0),
	Vector3(-1.66, -0.62, 4.0),
	Vector3(1.84, -0.62, 0.5),
	Vector3(-1.84, -0.62, 0.5),
	Vector3(1.45, -0.62, -3.2),
	Vector3(-1.45, -0.62, -3.2),
	Vector3(1.84, 0.60, 3.0),
	Vector3(-1.84, 0.60, 3.0),
	Vector3(1.84, 0.60, -2.2),
	Vector3(-1.84, 0.60, -2.2),
]

# Where she feels for the bottom. The same keel line as the buoyancy probes but
# spread further fore and aft, because a boat grounds by the forefoot first and
# swings on it — plus the turn of the bilge either side, so she takes a list when
# she settles on a slope instead of sitting up straight on a rock.
const KEEL: Array[Vector3] = [
	Vector3(0.0, -0.68, -3.90),
	Vector3(0.0, -0.68, -2.00),
	Vector3(0.0, -0.68, 0.0),
	Vector3(0.0, -0.68, 2.00),
	Vector3(0.0, -0.68, 3.90),
	Vector3(-1.40, -0.42, 0.0),
	Vector3(1.40, -0.42, 0.0),
]

#
# The whole set is scaled off MASS. A 4.5 t boat needs ~20x the spring, damping,
# drag and thrust of the 220 kg dinghy this started as, or it sinks, wallows and
# takes a minute to reach speed.
const MASS := 4500.0
const HULL_DRAG := 1430.0     # linear; top speed is simply thrust / HULL_DRAG
# Tuned so she floats on her marks: 6 hull probes at y = -0.62 each carry
# m*g/6, and k is chosen to put that equilibrium right at the boot top.
@export var probe_stiffness := 16000.0
@export var probe_damping := 760.0
## Roll and pitch damping from the water, N.m.s, and whether the wave slope is
## averaged over the hull's own footprint. Exported so a change to either can be
## MEASURED against the old behaviour rather than argued about — see --roll-test.
@export var roll_damp := 17500.0
@export var pitch_damp := 9000.0
@export var hull_plane_fit := true
@export var thrust_power := 38600.0
# Deliberately small, and scaled by the water flowing over the rudder below.
# Nine metres and four and a half tonnes do not dart: you put the helm over and
# then you wait, and she comes round in her own time.
@export var turn_torque := 33000.0

var ocean: Node3D
var camera_rig: Node3D
var tackle: Node3D
var _lit_window: StandardMaterial3D
var _helm_glow: StandardMaterial3D
var _glass_mat: ShaderMaterial
var _front_glass_mat: ShaderMaterial
var _wiper_pivot: Node3D
var weather: Node3D
## Wiper switch — 5 at the helm. Sweeps only while on; parks upright when off.
var wiper_on := false
var _cabin_lamp: OmniLight3D
var _stove_lamp: OmniLight3D
var _stove_ember: StandardMaterial3D
var _stove_heat: GPUParticles3D
var _stove_snd: AudioStreamPlayer3D
## Electric heater: switched, and slow at both ends. `stove_on` is what the
## switch says; `_stove_heat_t` is what the elements have got round to.
var stove_on := false
var _stove_heat_t := 0.0
var _helm_lamp: OmniLight3D
var _beacon: OmniLight3D
var _beacon_mat: StandardMaterial3D
var _floods: Array[SpotLight3D] = []
var _flood_lens_mat: StandardMaterial3D
var _flood_beam_mat: ShaderMaterial
## Switch panel at the helm. Thrown with E on the brass toggles.
var light_cabin := true
var light_helm := true
var light_beacon := true
var light_flood := false
var _wheel: Node3D
var _needles: Array[Node3D] = []
var _compass_card: Node3D
var _dial_ink: StandardMaterial3D
var _thr_lever: Node3D
var _pwr_segs: Array[StandardMaterial3D] = []
var _pwr_needle: Node3D
var _motor_pivot: Node3D
var _screw: Node3D
var _engine_room: Node3D
var _prop: GPUParticles3D
var _prop_pm: ParticleProcessMaterial
## False while you are walking the deck rather than standing at the wheel.
var helm_engaged := true
## Engine telegraph setting, -0.4 (slow astern) to 1.0 (full ahead). A SETTING:
## you put the lever somewhere and the screw keeps turning at that power while
## you walk the deck, drop the hook, make tea. W/S at the helm move the lever.
var throttle := 0.0        # what the telegraph lever is asking for
var _rpm := 0.0            # what the shaft is actually doing
var _helm := 0.0           # where the rudder actually is, not where you asked
## The diesel. Off until you turn the key; the shaft does not answer a dead
## engine, and the bar on the right goes dark with it.
enum EngineState { OFF, CRANKING, RUNNING }
var engine: EngineState = EngineState.OFF
var _crank_left := 0.0
var _ign_key: Node3D
var _ign_led: StandardMaterial3D
var _starter_snd: AudioStreamPlayer3D
var _engine_snd: AudioStreamPlayer3D
var _ign_click: AudioStreamPlayer3D
var _eng_lp: AudioEffectLowPassFilter
var _eng_open := 1.0
var aground := false
## True while you stand at the telegraph alone: W/S work the lever, no steering.
var telegraph_engaged := false
var _hull_mats: Array[ShaderMaterial] = []
var _soak := 0.0
var _glass_wet := 0.0
var _sounder_mat: ShaderMaterial
var _radar_mat: ShaderMaterial
var _radar_tex_set := false
var _radio_pull := 0.0
var _windlass: Node3D
## Chain locker: the heap on the locker sole and the run of cable dropping to
## it through the spurling pipe. Both shrink as the cable is veered.
var _chain_heap: MeshInstance3D
var _chain_run: Array[MeshInstance3D] = []
var _switch_levers := {}
var _switch_leds := {}
var _door_fwd: Node3D
var _door_aft: Node3D
var _door_wh: Node3D
## Shut at the start of the game: you open her up yourself.
var door_fwd_open := false
var door_aft_open := false
var door_wh_open := false
## The engine access door in the companionway side. Shut, the machine is a
## green shadow behind joinery; open, the whole well reads.
var _door_eng: Node3D
var door_eng_open := false
## The switchboard lives under a steel fuse-box cover now. Closed, the toggles
## are sealed away (and refuse to throw); open, the whole board is offered to
## the fingers. E on the box works the lid.
var _fuse_lid: Node3D
var fusebox_open := false
## Dive locker, port side of the cabin. `gear_worn` is the mask and suit ON
## YOU; `_gear_t` is the putting-on itself, which is a second and a half of
## your own hands in front of your face and is the only reason the screen is
## allowed to go dark in a game with no cuts in it.
## Things that are in the WAY of your eye, boat-local. Not collision — this is
## about what you can point at. A fuse-box lid standing open is a steel plate
## between you and whatever is behind it, and being offered the radio through
## it (and taking it by accident) is the whole reason this exists.
var aim_blockers: Array[AABB] = []
var locker_open := false
var gear_worn := false
var _gear_t := 0.0
var _locker_door: Node3D
var _gear_mask: Node3D
var _gear_tank: Node3D
## One sound for everything hinged aboard, played AT the thing that moved —
## a door heard from the far end of the cabin is a different sound from the one
## under your hand, and the only way to get that is to put the speaker on the
## hinge. Four voices, so two doors and a locker lid can overlap.
var _door_snd: Array[AudioStreamPlayer3D] = []
var _door_voice := 0
## Doorways get a blocker only while their door is SHUT. BLOCKERS is a const —
## it has to be, the walker reads it every tick — so the two that move live
## here, and deck_walker.gd resolves against both lists.
var door_blockers: Array[AABB] = []
const DOOR_Z0 := -0.45
const DOOR_Z1 := 4.65
const WH_DOOR_Z := 4.05
var _supply := 1.0
var _blackout := 0.0
var _depth_hist := PackedFloat32Array()
var _depth_head := 0
var _depth_t := 0.0
var _radio_set: Node3D
var _radio_hand: Node3D
var _cord: Array[MeshInstance3D] = []
var radio_held := false
## True while the viewmodel is driving the handset. The cord still follows;
## the lerp-to-face / lerp-to-cradle does not fight the hand.
var radio_pose_locked := false
var _radar_screen: MeshInstance3D
var _radar_pivot: Node3D
var _radar_arm: Node3D
var _radar_case: MeshInstance3D
## Where the radar carrier sits when stowed, and the rail it runs out along:
## inboard and aft toward the helm stand, dropping a touch so the screen meets
## the eye line instead of hanging over it.
var _radar_home := Vector3.ZERO
var _radar_swing_t := 0.0
var _radar_face_t := 0.0
var _sounder_arm: Node3D
var _sounder_swing_t := 0.0
var _sounder_face_t := 0.0
## The radar hangs off a SWING ARM — a proper piece of ironwork with a pivot
## post planted by the front bulkhead. Pulling the set does not slide it down
## an invisible track: the arm turns on its pivot and the carrier comes round
## to you on an ARC, the way anything mounted on an articulated bracket
## actually arrives. The three numbers are the joint itself:
##   RADAR_SWING       how far the arm turns (about -95 degrees)
##   RADAR_FACE_LOCAL  extra turn of the carrier ON the arm, so the screen
##                     finishes square to the helmsman's eye
##   RADAR_DROP        the arm settles a touch as it comes out
const RADAR_DROP := 0.05
## The arm does not swing to a canned pose. On each deploy the target angle is
## solved from where the HELMSMAN IS STANDING: the carrier comes round its arc
## until it sits just ahead of the eye, and never closer than MIN_GAP — open it
## from up close and it stops correspondingly earlier. The law-of-cosines term
## finds the exact point on the arc where the gap bottoms out.
const ARM_MIN_GAP := 0.60
## One quiet ping per sweep revolution. The shader turns the beam at
## rpm * 0.10471976 rad/s (radar.gdshader); the same clock is tracked here so
## the tick lands once per visual rotation.
var _radar_ping: AudioStreamPlayer3D
var _radar_sweep_prev := 0.0
var _radar_scan: Node3D
var _radar_spin := 0.0
## The handset plays its traffic when lifted, from the top, once — hang it up
## and lift again for another pass. The speaker IS the handset, so the voice
## rides it to your ear.
var _radio_snd: AudioStreamPlayer3D
var _radio_prev_held := false
var _sounder_pivot: Node3D
var _sounder_case: MeshInstance3D
var _sounder_home := Vector3.ZERO
var sounder_pull := 0.0
## 0 = stowed against the bulkhead, 1 = tipped out toward the helmsman. The
## hand sets the target; the pivot eases there like a thing with mass.
var radar_pull := 0.0
var _sounder_screen: MeshInstance3D
const RADIO_ANCHOR := Vector3(1.548, 3.915, 0.50)
const RADIO_CRADLE := Vector3(1.49, 3.94, 0.55)
const RADIO_CORD := 2.40
var _chart_mat: ShaderMaterial
var _chart_tex_set := false
var _chart_pin: Node3D
var chart_engaged := false
var _wiper_phase := 0.0
const WIPER_RATE := 2.6
var _slam_cd := 0.0
var _t := 0.0
var _flicker := 1.0
var _prev_wh := PackedFloat32Array()
var _prev_wh_valid := false
var _prev_com_vy := 0.0
## --drift-test instrumentation: per-source yaw-torque integrals, so a
## boat that turns by itself can be charged to the term actually doing it.
var drift_dbg := false
var drift_sums := {"align": 0.0, "rudder": 0.0, "damp": 0.0, "ground": 0.0}
var _com_vy_valid := false


func _ready() -> void:
	mass = MASS
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	# Low, and a little aft where the engine sits. A boat with a wheelhouse on
	# top of a deckhouse is top-heavy by shape; the ballast has to answer for it
	# or she lies over at the first beam sea.
	center_of_mass = Vector3(0.0, -0.32, 0.20)
	linear_damp = 0.03
	angular_damp = 0.05
	can_sleep = false
	_prev_wh.resize(PROBES.size())
	_build_collision()
	_build_rain_shields()
	_build_visuals()
	_dress_steel()
	_build_motor()
	_engine_room = (load("res://scripts/engine_room.gd") as GDScript).new()
	add_child(_engine_room)
	var vhf: Node3D = (load("res://scripts/vhf_antenna.gd") as GDScript).new()
	# Starboard-aft corner of the wheelhouse roof — where a VHF actually lives.
	vhf.position = Vector3(1.58, 5.52, 3.78)
	add_child(vhf)
	_build_radar_scanner()
	_build_engine_sound()
	_build_door_sound()
	_build_water_fx()
	# Roughly m(L^2+H^2)/12 about each axis: pitch, yaw, roll. Roll is left
	# heavier than the box formula so she rolls slow and deep like timber.
	inertia = Vector3(46000.0, 52000.0, 23500.0)


func _build_rain_shields() -> void:
	## Anything with a roof keeps the rain out. These volumes ride the boat and
	## swallow rain particles (weather.gd sets HIDE_ON_CONTACT), so the decks,
	## the cabin and the wheelhouse stay dry while the sea around still hisses.
	## They have to be THICK. A drop falls at better than 20 m/s and the system
	## steps at a fixed rate, so it covers most of a metre between one test and
	## the next — a 24 cm slab of collision is simply not there most frames, and
	## the rain came through the roof. Each volume now fills the whole room
	## under its roof: anything that gets in dies immediately, whatever the step.
	for shield: Array in [
		[Vector3(4.28, 1.60, 10.10), Vector3(0.00, -0.25, 0.75)],  # under the deck
		[Vector3(3.78, 2.20, 5.30), Vector3(0.00, 1.80, 2.11)],    # the cabin
		[Vector3(3.68, 2.50, 4.60), Vector3(0.00, 4.15, 1.87)],    # the wheelhouse
	]:
		var box := GPUParticlesCollisionBox3D.new()
		box.size = shield[0]
		box.position = shield[1]
		add_child(box)


func _dress_steel() -> void:
	## Rivets and rust: the two things that say IRON from twenty metres.
	##
	## Rivets are one MultiMesh — hundreds of heads, one draw call. They follow
	## the real seam lines: three strakes a side, the bow wedge edges, the house
	## corners. Rust is a handful of thin overlay plates: waterline bleed, chain
	## wear at the hawse, streaks under the scuppers, a tired patch on the
	## transom. Placement is seeded, not random — she rusts the same way every
	## launch, like a real boat photographed twice.
	var head := SphereMesh.new()
	head.radius = 0.014
	head.height = 0.018
	head.radial_segments = 6
	head.rings = 3
	head.material = _mat(Color(0.090, 0.092, 0.100), 0.45, 0.8)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = head
	var spots := PackedVector3Array()
	# Hull strakes, both sides.
	for side in [-1.0, 1.0]:
		for y in [-0.26, 0.04, 0.36]:
			var z := -3.85
			while z < 5.5:
				spots.append(Vector3(2.052 * side, y, z))
				z += 0.26
	# Bow wedge seams, converging.
	for side in [-1.0, 1.0]:
		for i in 7:
			var t := float(i) / 6.0
			spots.append(Vector3(lerpf(2.02, 0.14, t) * side,
					0.36, lerpf(-3.95, -4.98, t)))
			spots.append(Vector3(lerpf(2.02, 0.14, t) * side,
					-0.26, lerpf(-3.95, -4.85, t)))
	# Transom edge and quarters.
	for i in 14:
		spots.append(Vector3(-1.85 + float(i) * 0.285, 0.36, 5.815))
	# Deckhouse and wheelhouse corner posts: vertical rivet columns.
	for cx in [-1.815, 1.815]:
		for cz in [-0.43, 4.63]:
			for i in 6:
				spots.append(Vector3(cx, 0.85 + float(i) * 0.32, cz))
	mm.instance_count = spots.size()
	for i in spots.size():
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, spots[i]))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)

	# Rust. Thin proud plates; the colour does the talking.
	var rust := _mat(Color(0.330, 0.148, 0.072), 0.96)
	var rust_dark := _mat(Color(0.210, 0.096, 0.052), 0.94)
	var patches: Array = [
		# hawse / anchor wear, both bows
		[Vector3(0.012, 0.42, 0.85), Vector3(-2.055, 0.22, -3.35), rust],
		[Vector3(0.012, 0.36, 0.70), Vector3(2.055, 0.16, -3.55), rust_dark],
		# waterline bleed amidships
		[Vector3(0.012, 0.20, 1.60), Vector3(-2.055, -0.02, 1.20), rust_dark],
		[Vector3(0.012, 0.16, 1.10), Vector3(2.055, -0.06, 2.30), rust],
		# scupper streaks running DOWN from the deck edge
		[Vector3(0.012, 0.55, 0.16), Vector3(-2.052, 0.18, 0.10), rust],
		[Vector3(0.012, 0.48, 0.14), Vector3(-2.052, 0.14, 3.10), rust_dark],
		[Vector3(0.012, 0.60, 0.18), Vector3(2.052, 0.12, 4.20), rust],
		[Vector3(0.012, 0.40, 0.13), Vector3(2.052, 0.20, -1.40), rust_dark],
		# transom, under the name
		[Vector3(1.30, 0.35, 0.012), Vector3(0.35, 0.05, 5.822), rust_dark],
		# stem head, where the chain rides
		[Vector3(0.18, 0.55, 0.05), Vector3(0.0, 0.75, -5.06), rust],
		# deck patches by the windlass and the ladder
		[Vector3(0.55, 0.006, 0.80), Vector3(0.55, 0.634, -3.10), rust_dark],
		[Vector3(0.40, 0.006, 0.55), Vector3(-0.90, 0.634, 4.95), rust],
	]
	for pa in patches:
		_box(pa[0], pa[1], Vector3.ZERO, pa[2])


func _build_collision() -> void:
	var hull := CollisionShape3D.new()
	var hs := BoxShape3D.new()
	hs.size = Vector3(4.18, 1.9, 10.1)
	hull.shape = hs
	hull.position = Vector3(0.0, 0.05, 0.0)
	add_child(hull)

	var house := CollisionShape3D.new()
	var ds := BoxShape3D.new()
	ds.size = Vector3(2.4, 3.6, 3.6)
	house.shape = ds
	house.position = Vector3(0.0, 2.35, 1.3)
	add_child(house)


func _glass(size: Vector3, pos: Vector3, mat: ShaderMaterial = null) -> void:
	## A pane, not a black rectangle. Both faces drawn, so it still reads as
	## glass from inside the wheelhouse.
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat if mat != null else _glass_mat
	mi.mesh = bm
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## Walkable geometry, in the boat's own local frame.
##
## The player is simulated in local space (see scripts/deck_walker.gd), so all
## of this stays valid however she is rolling. Floors are [Rect2 over xz, y];
## blockers and ceilings are plain AABBs. Kept as data next to the meshes that
## draw them so the two cannot drift apart unnoticed.

const FLOORS: Array = [
	# Bilge catch. Anything inside the hull that loses its footing — a slip on a
	# heeling deck, a miss on the stairs — lands on this instead of falling
	# through her and finding itself in the sea. Lowest floor there is, so every
	# real deck wins over it; it only ever catches what nothing else did.
	[Rect2(-1.92, -3.92, 3.84, 9.60), 0.63],
	[Rect2(-1.92, -3.92, 3.84, 3.56), 0.63],   # foredeck, up to the door sill
	[Rect2(-1.92, 4.55, 3.84, 0.97), 0.63],    # aft deck, up to the door sill
	[Rect2(-1.70, -0.38, 3.40, 4.96), 0.68],   # cabin sole
	# Upper deck, in four pieces around the STAIRWELL — the opening the
	# companionway comes up through, port side. The well is 1.18 m: still
	# enough to turn on (0.58 m of body-room) but the hatch mouth is not a
	# flue the stove can breathe up through.
	[Rect2(-1.83, -0.52, 0.16, 5.62), 2.91],
	[Rect2(-0.49, -0.52, 2.32, 5.62), 2.91],
	[Rect2(-1.67, -0.52, 1.18, 1.47), 2.91],
	[Rect2(-1.67, 3.95, 1.18, 1.15), 2.91],
	# The companionway. TEN treads now, 0.223 m of rise on 0.30 m of going:
	# 36.6 degrees, which is a staircase. It was eight treads at 0.279 on 0.238
	# — 49.6 degrees — and that is not a staircase, it is a ladder with the
	# rungs filled in, which is why it never felt right to come down. The extra
	# metre and a bit of going is most of what the boat was lengthened for.
	# They are still plain floors: no mode, no grabbing, ordinary walking.
	[Rect2(-1.67, 0.95, 1.18, 0.30), 2.910],
	[Rect2(-1.67, 1.25, 1.18, 0.30), 2.687],
	[Rect2(-1.67, 1.55, 1.18, 0.30), 2.464],
	[Rect2(-1.67, 1.85, 1.18, 0.30), 2.241],
	[Rect2(-1.67, 2.15, 1.18, 0.30), 2.018],
	[Rect2(-1.67, 2.45, 1.18, 0.30), 1.795],
	[Rect2(-1.67, 2.75, 1.18, 0.30), 1.572],
	[Rect2(-1.67, 3.05, 1.18, 0.30), 1.349],
	[Rect2(-1.67, 3.35, 1.18, 0.30), 1.126],
	[Rect2(-1.67, 3.65, 1.18, 0.30), 0.903],
]

const CEILINGS: Array = [
	# Cabin deckhead, cut around the stairwell so you do not crack your head on
	# the way up.
	[Rect2(-0.49, -0.38, 2.19, 4.96), 2.73],
	[Rect2(-1.70, -0.38, 1.21, 1.33), 2.73],
	[Rect2(-1.70, 3.95, 1.21, 0.63), 2.73],
	[Rect2(-1.73, -0.30, 3.46, 4.35), 5.32],   # wheelhouse deckhead
]

const BLOCKERS: Array[AABB] = [
	# deckhouse: sides, and jambs either side of the fore and aft doorways
	AABB(Vector3(-1.86, 0.63, -0.50), Vector3(0.13, 2.12, 5.20)),
	AABB(Vector3(1.73, 0.63, -0.50), Vector3(0.13, 2.12, 5.20)),
	AABB(Vector3(-1.86, 0.63, -0.51), Vector3(1.31, 2.12, 0.13)),
	AABB(Vector3(0.55, 0.63, -0.51), Vector3(1.31, 2.12, 0.13)),
	AABB(Vector3(-1.86, 0.63, 4.59), Vector3(1.31, 2.12, 0.13)),
	AABB(Vector3(0.55, 0.63, 4.59), Vector3(1.31, 2.12, 0.13)),
	# wheelhouse: sides, front, and the aft bulkhead either side of its door.
	# The port panel runs on past the doorway to close the aft end of the
	# stairwell, so the only way into the hole is down the steps.
	AABB(Vector3(-1.80, 2.91, -0.31), Vector3(0.13, 2.43, 4.48)),
	AABB(Vector3(1.67, 2.91, -0.31), Vector3(0.13, 2.43, 4.48)),
	AABB(Vector3(-1.80, 2.91, -0.32), Vector3(3.60, 2.43, 0.13)),
	AABB(Vector3(-1.80, 2.91, 3.99), Vector3(1.25, 2.43, 0.13)),
	AABB(Vector3(0.55, 2.91, 3.99), Vector3(1.25, 2.43, 0.13)),
	# bulwarks and the ends of the boat
	AABB(Vector3(-2.08, 0.63, -4.05), Vector3(0.16, 0.60, 9.65)),
	AABB(Vector3(1.92, 0.63, -4.05), Vector3(0.16, 0.60, 9.65)),
	AABB(Vector3(-2.08, 0.63, -4.08), Vector3(4.16, 0.90, 0.18)),
	AABB(Vector3(-2.08, 0.63, 5.52), Vector3(4.16, 0.90, 0.18)),
	# rail round the deckhouse roof
	AABB(Vector3(-1.88, 2.91, -0.56), Vector3(0.12, 0.75, 5.70)),
	AABB(Vector3(1.76, 2.91, -0.56), Vector3(0.12, 0.75, 5.70)),
	AABB(Vector3(-1.88, 2.91, 5.00), Vector3(3.76, 0.75, 0.12)),
	# Stairwell coaming, inboard side. Two things about it.
	#
	# Its base sits at 3.05 rather than at deck level, and that 14 cm is the
	# whole design: it stops someone standing on the deck (feet 2.91, head 4.65)
	# and passes clean over the head of someone on the stairs. At deck level it
	# caught them and would not let them down.
	#
	# And the well it guards is 1.18 m wide. 1.10 left a 0.60 m body with 0.50 m
	# of room — enough on paper and cramped in the hand. 1.30 walked, but the
	# hatch mouth on the upper deck was a flue: stove heat and crackle came
	# straight up. 1.18 keeps 0.58 m of body-room and closes the mouth a little.
	# It starts at 1.55, not at 0.95: the first two treads are level with the
	# deck and are the WAY IN. Running the rail the full length of the well
	# walled the entrance off — coming aft from the wheel you met it head on and
	# had to go right forward again to get round its end. A companionway rail
	# has a gap in it where you step through, and now this one does.
	AABB(Vector3(-0.49, 3.05, 1.55), Vector3(0.10, 0.81, 2.40)),
	# Under the companionway. The treads are floors, which made them walkable —
	# and made the space UNDER them empty, so from the cabin sole you strolled
	# straight in through the side of the staircase and stood inside it. One
	# volume per tread, from the sole up to 50 cm below its own tread.
	#
	# Fifty, and the number matters. The going is 0.30 m and the body is 0.30 m
	# in radius, so while you are still standing on step n+2 your shoulder
	# already reaches the underside of step n — two steps ahead, before you have
	# climbed the height that would let the engine ignore it. Clear it by one
	# rise (0.22) or even one and a half (0.30) and that volume shoves you back
	# exactly at the edge of the next tread's rectangle: you arrive at the
	# boundary, the floor test excludes it, and you stall halfway up. Clearing
	# TWO rises means the volume is already ignored by the time you need to be
	# inside it, and the climb runs.
	#
	# The bottom two steps get none at all: they are a single step off the sole
	# and one more above it, they are the way in, and the same arithmetic would
	# wall the entrance off.
	AABB(Vector3(-1.67, 0.68, 0.95), Vector3(1.18, 1.730, 0.30)),
	AABB(Vector3(-1.67, 0.68, 1.25), Vector3(1.18, 1.507, 0.30)),
	AABB(Vector3(-1.67, 0.68, 1.55), Vector3(1.18, 1.284, 0.30)),
	AABB(Vector3(-1.67, 0.68, 1.85), Vector3(1.18, 1.061, 0.30)),
	AABB(Vector3(-1.67, 0.68, 2.15), Vector3(1.18, 0.838, 0.30)),
	AABB(Vector3(-1.67, 0.68, 2.45), Vector3(1.18, 0.615, 0.30)),
	AABB(Vector3(-1.67, 0.68, 2.75), Vector3(1.18, 0.392, 0.30)),
	AABB(Vector3(-1.67, 0.68, 3.05), Vector3(1.18, 0.169, 0.30)),
	# windlass on the foredeck
	AABB(Vector3(-0.30, 0.63, -3.55), Vector3(0.60, 0.55, 0.40)),
	# the wheel and its column
	AABB(Vector3(-0.20, 2.91, 0.14), Vector3(0.40, 1.30, 0.32)),
	# dashboard under the front glass, and the chart table aft of it
	AABB(Vector3(-1.29, 2.91, -0.22), Vector3(2.58, 0.60, 0.36)),
	# One continuous run of joinery down the starboard side, from the corner of
	# the dashboard aft to the end of the chart table. It was three separate
	# lumps of furniture standing near each other; a wheelhouse is fitted out,
	# not furnished.
	AABB(Vector3(0.98, 2.91, 0.14), Vector3(0.64, 0.81, 3.21)),
	# Cabin furniture. Laid out so nothing shares a volume with anything else —
	# the bunk used to have the stove standing in the foot of it, and the
	# cupboard was let into the forward bulkhead.
	AABB(Vector3(0.92, 0.68, 1.30), Vector3(0.76, 0.75, 2.00)),    # bunk
	AABB(Vector3(-1.70, 0.68, 0.10), Vector3(0.48, 1.74, 0.52)),    # dive locker
	AABB(Vector3(1.05, 0.68, 4.05), Vector3(0.46, 0.90, 0.46)),    # stove
	AABB(Vector3(1.20, 0.68, -0.25), Vector3(0.46, 1.05, 0.40)),   # cupboard
	AABB(Vector3(1.16, 0.68, 0.35), Vector3(0.45, 0.62, 0.45)),    # sea chest
]

## Tall enough that stepping backwards off the roof edge lands you ON the
## ladder instead of past it: the catch test probes 0.9 m above the feet, so
## the volume has to reach well above the roof line or a roof-level dismount
## misses it, and you fall — over the stern, into the sea.
## No ladder any more: she has a proper companionway inside, so the whole
## grab-the-rungs mode is gone. Kept as an empty volume the walker can still
## ask about without needing a special case.
## Boarding ladder over the transom: the way back aboard, and the way in. Rungs
## run from the deck down past the waterline, so it is reachable from the sea
## whatever the boat is doing on the swell.
const SEA_LADDER_X := 0.72
const SEA_LADDER_Z := 5.86
const SEA_LADDER_TOP := 0.66
const SEA_LADDER_BOT := -1.30
const LADDER := AABB(Vector3(0.0, -999.0, 0.0), Vector3(0.0, 0.0, 0.0))
const LADDER_BAND := Vector2(0.0, 0.0)
## Where you stand to take the wheel, and where the wheel itself is.
## Right at the wheel, half a step to starboard. Measured, not chosen: from the
## old spot the throttle knob sat 1.14 m from the right shoulder against a
## 0.63 m arm, so it simply could not be held while the left hand steered.
const HELM_STAND := Vector3(0.0, 2.91, 0.70)
# The chart table: where you stand, where your eye goes when you lean over it,
# and the point on the paper the camera settles on. Three points rather than a
# UI screen, because the chart is a thing in the room and reading it should be
# something you do with your body.
const CHART_STAND := Vector3(0.44, 2.91, 2.98)
const CHART_EYE := Vector3(0.92, 4.20, 2.92)
const CHART_LOOK := Vector3(1.30, 3.72, 2.88)
const HELM_REACH := 1.05
## Spawn point when you step into first person: at the wheel.
const CREW_START := Vector3(0.0, 2.93, 1.10)
## Cabin stove: body centre, where the fire sits. Heat is the air around
## the plate, not the whole cabin — door sills and the hatch stay cold.
const STOVE := Vector3(1.28, 1.05, 4.28)
const CABIN_XZ := Rect2(-1.70, -0.38, 3.40, 5.03)
## Where you stand to work the telegraph alone.
const TELEGRAPH_STAND := Vector3(0.58, 2.91, 0.70)
## Everything aboard you can put a hand on. The camera looks for the nearest of
## these in front of you and offers it on E.
const INTERACT: Array = [
	{"id": "helm", "pos": Vector3(0.0, 3.75, 0.30), "r": 0.36, "name": "Helm"},
	{"id": "telegraph", "pos": Vector3(0.70, 3.78, 0.02), "r": 0.18, "name": "Throttle"},
	{"id": "ignition", "pos": Vector3(0.50, 3.54, 0.06), "r": 0.28, "name": "Ignition"},
	{"id": "windlass", "pos": Vector3(0.0, 1.00, -3.35), "r": 0.55, "name": "Windlass (anchor)"},
	# Switch console between the radar and the chart table. Walk up, throw.
	{"id": "door_fwd", "pos": Vector3(0.0, 1.55, -0.45), "r": 0.50, "name": "Forward door"},
	{"id": "door_aft", "pos": Vector3(0.0, 1.55, 4.65), "r": 0.50, "name": "Aft door"},
	{"id": "door_wh", "pos": Vector3(0.0, 3.85, 4.05), "r": 0.50, "name": "Wheelhouse door"},
	# Small, and on the LATCH rather than over the board. A big target sitting
	# on top of the toggles wins the crosshair from every one of them, and with
	# the lid open you could never point at a switch at all. When it is open
	# this moves up onto the standing lid — see interact_pos().
	{"id": "fusebox", "pos": Vector3(1.17, 3.78, 1.235), "r": 0.10, "name": "Fuse box"},
	{"id": "sw_cabin", "pos": Vector3(1.05, 3.78, 1.42), "r": 0.055, "name": "Cabin light"},
	{"id": "sw_helm", "pos": Vector3(1.17, 3.78, 1.42), "r": 0.055, "name": "Wheelhouse light"},
	{"id": "sw_beacon", "pos": Vector3(1.29, 3.78, 1.42), "r": 0.055, "name": "Beacon"},
	{"id": "sw_flood", "pos": Vector3(1.05, 3.78, 1.66), "r": 0.055, "name": "Floodlights"},
	{"id": "sw_wiper", "pos": Vector3(1.17, 3.78, 1.66), "r": 0.055, "name": "Wiper"},
	{"id": "sw_anchor", "pos": Vector3(1.29, 3.78, 1.66), "r": 0.055, "name": "Windlass (anchor)"},
	{"id": "chart", "pos": Vector3(1.30, 3.72, 2.88), "r": 0.36, "name": "Chart table"},
	{"id": "radio", "pos": Vector3(1.49, 3.94, 0.55), "r": 0.20, "name": "Radio"},
	{"id": "stove", "pos": Vector3(1.28, 1.05, 4.10), "r": 0.30, "name": "Heater"},
	{"id": "sea_ladder", "pos": Vector3(0.72, 0.80, 5.80), "r": 0.42, "name": "Boarding ladder"},
	{"id": "locker", "pos": Vector3(-1.22, 1.52, 0.52), "r": 0.34, "name": "Dive locker"},
	{"id": "divegear", "pos": Vector3(-1.34, 1.76, 0.34), "r": 0.30, "name": "Dive gear"},
	{"id": "door_eng", "pos": Vector3(-0.50, 1.24, 2.15), "r": 0.42, "name": "Engine hatch"},
	{"id": "radar", "pos": Vector3(1.18, 4.28, 0.10), "r": 0.28, "name": "Radar"},
	{"id": "sounder", "pos": Vector3(1.15, 4.02, 0.08), "r": 0.22, "name": "Sounder"},
]


func radio_handset() -> Node3D:
	return _radio_hand


func helm_wheel() -> Node3D:
	return _wheel


func throttle_lever() -> Node3D:
	return _thr_lever


func ignition_key() -> Node3D:
	return _ign_key


func windlass_node() -> Node3D:
	return _windlass


func switch_lever(id: String) -> Node3D:
	return _switch_levers.get(id) as Node3D


func door_node(id: String) -> Node3D:
	match id:
		"door_fwd":
			return _door_fwd
		"door_aft":
			return _door_aft
		"door_wh":
			return _door_wh
	return null


func engine_door() -> Node3D:
	return _door_eng


func interact_pos(id: String, fallback: Vector3) -> Vector3:
	## Where a fitting is RIGHT NOW, for aiming. Most of them never move and
	## just hand the constant back; the ones on hinges and rails do not, and a
	## crosshair aimed at where a thing used to be is the whole problem.
	if id == "fusebox" and _fuse_lid != null and _fuse_lid.rotation.x < -0.9:
		# Standing open: you close it by taking hold of the lid, which is up in
		# the air in front of the board, not down on the latch.
		return _fuse_lid.position + Vector3(0.0, 0.42, -0.20)
	return fallback


func locker_door() -> Node3D:
	return _locker_door


func gear_wear_t() -> float:
	## 0 while it hangs in the locker, 1 while it is on your face. Everything
	## between is the animation, and the overlay reads it directly.
	return _gear_t


func fuse_lid() -> Node3D:
	return _fuse_lid


func radar_housing() -> Node3D:
	return _radar_case


func sounder_housing() -> Node3D:
	return _sounder_case


func set_sounder_pull(v: float) -> void:
	sounder_pull = clampf(v, 0.0, 1.0)
	if sounder_pull > 0.5 and _sounder_arm != null and _sounder_pivot != null:
		var t := _swing_targets(_sounder_arm, _sounder_pivot.position)
		_sounder_swing_t = t.x
		_sounder_face_t = t.y


func _swing_targets(arm: Node3D, arm_off: Vector3) -> Vector2:
	## Solve (swing, carrier face yaw) that parks the carrier on its arc just
	## ahead of wherever the player is right now. Boat-local, XZ plane.
	var cam: Camera3D = camera_rig.get("_cam") if camera_rig != null else null
	if cam == null:
		return Vector2(-1.5, 0.4)
	var P: Vector3 = to_local(cam.global_position)
	# Bias the park spot a hand-width toward the centreline. Dead on the eye
	# line it sat exactly between you and the OTHER instrument's bracket, so
	# reading one meant wearing the other as a blindfold.
	P.x -= 0.22
	var C: Vector3 = arm.position
	var rest_bearing := atan2(arm_off.x, arm_off.z)
	var r := Vector2(arm_off.x, arm_off.z).length()
	var dv := Vector2(P.x - C.x, P.z - C.z)
	var d := maxf(dv.length(), 0.05)
	var bearing_p := atan2(dv.x, dv.y)
	# On the player's bearing the carrier sits d - r from them; if that is
	# already under the gap, back off along the arc by the cosine-law angle.
	var phi := 0.0
	if d < r + ARM_MIN_GAP:
		phi = acos(clampf((r * r + d * d - ARM_MIN_GAP * ARM_MIN_GAP)
				/ (2.0 * r * d), -1.0, 1.0))
	var candidate_a := wrapf(bearing_p + phi - rest_bearing, -PI, PI)
	var candidate_b := wrapf(bearing_p - phi - rest_bearing, -PI, PI)
	# Take the solution nearer home, so the arm never swings the long way round.
	var swing: float = candidate_a if absf(candidate_a) < absf(candidate_b) else candidate_b
	swing = clampf(swing, -2.3, 0.0)
	var end_bearing := rest_bearing + swing
	var carrier := Vector2(C.x, C.z) + Vector2(sin(end_bearing), cos(end_bearing)) * r
	# carrier.y is boat-local Z (Vector2 packs XZ).
	var face_world := atan2(P.x - carrier.x, P.z - carrier.y)
	# The carrier's screen faces boat +Z with the arm at rest, so its world yaw
	# is swing + local. Subtracting end_bearing here (as the first pass did)
	# double-counts the arm's REST bearing and turns the screen ~80 degrees off
	# the eye — which is exactly how it photographed.
	return Vector2(swing, wrapf(face_world - swing, -PI, PI))


func set_radar_pull(v: float) -> void:
	radar_pull = clampf(v, 0.0, 1.0)
	if radar_pull > 0.5 and _radar_arm != null and _radar_pivot != null:
		var t := _swing_targets(_radar_arm, _radar_pivot.position)
		_radar_swing_t = t.x
		_radar_face_t = t.y


func screen_mesh(id: String) -> MeshInstance3D:
	match id:
		"radar":
			return _radar_screen
		"sounder":
			return _sounder_screen
	return null


func _mat(albedo: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = rough
	m.metallic = metal
	return m


func _wet_wood(color: Color, rough: float) -> ShaderMaterial:
	## Hull planking that darkens and goes glossy below the waterline. The
	## waterline is pushed every frame in _update_wetness().
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/wet_hull.gdshader")
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("dry_roughness", rough)
	_hull_mats.append(m)
	return m


func _build_visuals() -> void:
	## An old wooden coaster: 9 m hull, deckhouse on the deck, wheelhouse on top
	## of that. Everything is boxes and cylinders, so the character has to come
	## from proportion and from what is worn: dark oiled topsides, paint gone
	## chalky above the rubbing strake, one lit window.
	# She is IRON. The palette keeps its old variable names so every _box below
	# keeps its meaning, but the truth changed: plate steel on a riveted coaster
	# that has worked thirty winters — grey paint gone chalky, oxide bleeding at
	# the seams, the boot top more red lead than red. The hull still runs
	# through the wet-darkening shader, because wet steel is half of what makes
	# a working boat look like one. The warm wood stays below decks, where
	# people live; outside it is the sea against metal, and the metal is losing.
	var hull_wood := _wet_wood(Color(0.130, 0.140, 0.148), 0.60)
	var keel_wood := _wet_wood(Color(0.082, 0.088, 0.094), 0.55)
	var boot := _wet_wood(Color(0.300, 0.092, 0.058), 0.82)   # red-lead boot top
	var deck := _mat(Color(0.140, 0.135, 0.125), 0.84, 0.30)
	var paint := _mat(Color(0.370, 0.395, 0.372), 0.74, 0.10) # weathered grey-green
	var paint_dark := _mat(Color(0.070, 0.075, 0.080), 0.66, 0.55)
	var trim := _mat(Color(0.158, 0.144, 0.124), 0.62, 0.50)
	var metal := _mat(Color(0.105, 0.105, 0.115), 0.50, 0.65)
	var dark := _mat(Color(0.045, 0.040, 0.036), 0.92)

	# --- hull ---------------------------------------------------------------
	_box(Vector3(1.7, 0.30, 9.5), Vector3(0.0, -0.68, 0.75), Vector3.ZERO, keel_wood)
	_box(Vector3(3.73, 0.55, 9.8), Vector3(0.0, -0.42, 0.75), Vector3.ZERO, hull_wood)
	_box(Vector3(4.08, 0.80, 9.8), Vector3(0.0, 0.05, 0.75), Vector3.ZERO, hull_wood)
	# Flared topsides, tilted out a few degrees so she is not a shoebox.
	_box(Vector3(0.20, 1.05, 9.7), Vector3(-2.08, 0.22, 0.75), Vector3(0.0, 0.0, 7.0), hull_wood)
	_box(Vector3(0.20, 1.05, 9.7), Vector3(2.08, 0.22, 0.75), Vector3(0.0, 0.0, -7.0), hull_wood)
	# Boot top: the paint line at the waterline, the thing that says "this floats
	# here" more than any other detail on a working boat.
	_box(Vector3(4.14, 0.16, 9.82), Vector3(0.0, -0.06, 0.75), Vector3.ZERO, boot)
	# Bow: a real one. The old bow was three planks — two flat panels and a
	# vertical post — which from ahead read as exactly that. Now the hull's own
	# layers each run forward into a plan-view wedge (same widths, same colours,
	# so every seam lines through), the whole entry tapers to a raked stem, and
	# the deck closes the top with a triangle. Boxes end square; bows do not.
	# Each wedge BUTTS its hull course instead of lapping it. Overlapping them
	# put two coplanar faces in the same millimetre over a 25 cm band, which is
	# exactly the flicker across the bow: the depth test cannot choose, so it
	# chooses differently every frame. Aft edge of each prism = forward edge of
	# the box it continues (hull courses end at z -4.15, the boot top at -4.16).
	_prism(3.73, 0.85, 0.55, Vector3(0.0, -0.42, -4.575), hull_wood)
	_prism(4.08, 1.00, 0.80, Vector3(0.0, 0.05, -4.650), hull_wood)
	_prism(4.145, 1.02, 0.16, Vector3(0.0, -0.06, -4.670), boot)
	# The band between sheer and deck edge, fairing the flared topsides in.
	# Sheer band. Its top is held 1 cm BELOW the deck plane on purpose: flush
	# with it, the band and the foredeck triangle shared a surface and fought.
	_prism(4.10, 0.85, 0.19, Vector3(0.0, 0.525, -4.525), hull_wood)
	# Foredeck triangle: same thickness as the main deck, so its top lands on
	# the same 0.63 plane and the bow is walked onto, not stepped down into.
	# Aft edge butts the main deck's forward edge at z -3.95 exactly.
	_prism(3.92, 1.00, 0.14, Vector3(0.0, 0.56, -4.45), deck)
	# Raked stem: foot at the keel, head leaning forward over the water.
	_box(Vector3(0.16, 1.85, 0.30), Vector3(0.0, 0.32, -4.93), Vector3(-19.0, 0.0, 0.0), keel_wood)
	# Bulwarks converge on the stem head. Geometry, not eyeballing: each runs
	# from the side bulwark's forward end (x 1.98, z -3.90) to the apex
	# (0, -5.05) — that is a 60-degree sweep over 2.32 m, and nothing shallower
	# MEETS the sides; the first pass used 33 degrees from x 0.97 and the rails
	# hung in the air a half-metre inboard of the bulwarks they pretended to
	# continue.
	_box(Vector3(0.12, 0.50, 2.32), Vector3(-0.99, 0.86, -4.475), Vector3(0.0, -60.0, 0.0), paint_dark)
	_box(Vector3(0.12, 0.50, 2.32), Vector3(0.99, 0.86, -4.475), Vector3(0.0, 60.0, 0.0), paint_dark)
	# Stem-head block closing the vee where the two rails meet.
	_box(Vector3(0.20, 0.50, 0.24), Vector3(0.0, 0.86, -5.00), Vector3.ZERO, paint_dark)
	# Rubbing strake, same construction one strake down: sides end at x 2.13,
	# z -4.17; meet at (0, -5.08).
	_box(Vector3(0.10, 0.14, 2.35), Vector3(-1.065, 0.52, -4.625), Vector3(0.0, -66.0, 0.0), trim)
	_box(Vector3(0.10, 0.14, 2.35), Vector3(1.065, 0.52, -4.625), Vector3(0.0, 66.0, 0.0), trim)
	# Transom, raked.
	_box(Vector3(4.03, 1.25, 0.22), Vector3(0.0, 0.18, 5.70), Vector3(-9.0, 0.0, 0.0), hull_wood)
	_build_nameboard()
	# Rubbing strake all round.
	_box(Vector3(4.26, 0.14, 9.85), Vector3(0.0, 0.52, 0.75), Vector3.ZERO, trim)

	# --- deck and bulwarks --------------------------------------------------
	# Deck, in four pieces because there is a HOLE in it. A spurling pipe needs
	# an actual opening — faking one with a dark disc leaves the deck's own top
	# face visible down the bore, which is worse than no pipe. So the plating is
	# laid round the hole: forward of it, a band either side of it, and the long
	# run aft. Hole is 0.24 square at (0, -3.02), just abaft the windlass.
	_box(Vector3(3.88, 0.14, 0.81), Vector3(0.0, 0.56, -3.545), Vector3.ZERO, deck)
	_box(Vector3(1.82, 0.14, 0.24), Vector3(-1.03, 0.56, -3.02), Vector3.ZERO, deck)
	_box(Vector3(1.82, 0.14, 0.24), Vector3(1.03, 0.56, -3.02), Vector3.ZERO, deck)
	_box(Vector3(3.88, 0.14, 8.45), Vector3(0.0, 0.56, 1.325), Vector3.ZERO, deck)
	_box(Vector3(0.14, 0.52, 9.4), Vector3(-1.98, 0.86, 0.80), Vector3(0.0, 0.0, 5.0), paint_dark)
	_box(Vector3(0.14, 0.52, 9.4), Vector3(1.98, 0.86, 0.80), Vector3(0.0, 0.0, -5.0), paint_dark)
	_box(Vector3(3.98, 0.10, 0.14), Vector3(0.0, 1.13, -3.95), Vector3.ZERO, trim)
	# Foredeck left clear. There was a cargo hatch and a crate of gear lying on
	# it — a metre-and-a-bit slab of planking in the middle of the working deck
	# and a dark box beside it, both of them just something to trip over. The
	# windlass and the mast are the only things out here that do a job.

	# --- deckhouse (lower level) --------------------------------------------
	# Built as walls, not as a solid block. You can go inside her, so every
	# surface has to exist from both faces.
	_glass_mat = ShaderMaterial.new()
	_glass_mat.shader = load("res://shaders/glass.gdshader")
	# Among transparent surfaces Godot sorts by instance origin, and the panes
	# share an origin neighbourhood with the ocean rings. Force the glass to
	# draw last so the sea is always on screen before the pane blends over it.
	_glass_mat.render_priority = 12

	const CH_Z0 := -0.45   # forward bulkhead
	const CH_Z1 := 4.65    # aft bulkhead
	const CH_X := 1.80     # half beam of the house
	const CH_Y0 := 0.63    # cabin sole
	const CH_Y1 := 2.75    # cabin deckhead / roof underside (2.05 m headroom)
	var cy := (CH_Y0 + CH_Y1) * 0.5
	var ch := CH_Y1 - CH_Y0
	var cz := (CH_Z0 + CH_Z1) * 0.5
	var cl := CH_Z1 - CH_Z0

	_box(Vector3(CH_X * 2.0, 0.09, cl), Vector3(0.0, CH_Y0, cz), Vector3.ZERO, deck)  # sole
	_box(Vector3(0.08, ch, cl), Vector3(-CH_X, cy, cz), Vector3.ZERO, paint)
	_box(Vector3(0.08, ch, cl), Vector3(CH_X, cy, cz), Vector3.ZERO, paint)
	# Aft bulkhead, also with a doorway: foredeck -> cabin -> aft deck -> ladder
	# -> roof -> wheelhouse is a loop you can actually walk.
	_box(Vector3(1.25, ch, 0.08), Vector3(-1.175, cy, CH_Z1), Vector3.ZERO, paint)
	_box(Vector3(1.25, ch, 0.08), Vector3(1.175, cy, CH_Z1), Vector3.ZERO, paint)
	# Header only 0.20 deep: the opening clears 1.92 m, so a 1.74 m man walks
	# through the door rather than through the lintel.
	_box(Vector3(1.10, 0.20, 0.08), Vector3(0.0, CH_Y1 - 0.10, CH_Z1), Vector3.ZERO, paint)
	_box(Vector3(1.14, 0.06, 0.10), Vector3(0.0, CH_Y0 + 0.03, CH_Z1), Vector3.ZERO, trim)
	# Forward bulkhead with a doorway cut out of it (two jambs + a header).
	_box(Vector3(1.25, ch, 0.08), Vector3(-1.175, cy, CH_Z0), Vector3.ZERO, paint)
	_box(Vector3(1.25, ch, 0.08), Vector3(1.175, cy, CH_Z0), Vector3.ZERO, paint)
	_box(Vector3(1.10, 0.20, 0.08), Vector3(0.0, CH_Y1 - 0.10, CH_Z0), Vector3.ZERO, paint)
	_box(Vector3(1.14, 0.06, 0.10), Vector3(0.0, CH_Y0 + 0.03, CH_Z0), Vector3.ZERO, trim)
	# Roof of the deckhouse — the walkable upper deck.
	# Roof / upper deck, laid in four pieces so the companionway has an opening
	# to come up through on the port side aft. Hatch mouth 1.18 m, not 1.30.
	_box(Vector3(0.16, 0.16, 5.62), Vector3(-1.75, CH_Y1 + 0.08, 2.29), Vector3.ZERO, paint_dark)
	_box(Vector3(2.32, 0.16, 5.62), Vector3(0.67, CH_Y1 + 0.08, 2.29), Vector3.ZERO, paint_dark)
	_box(Vector3(1.18, 0.16, 1.47), Vector3(-1.08, CH_Y1 + 0.08, 0.215), Vector3.ZERO, paint_dark)
	_box(Vector3(1.18, 0.16, 1.15), Vector3(-1.08, CH_Y1 + 0.08, 4.525), Vector3.ZERO, paint_dark)

	# Side windows: three a side, glazed.
	for i in 3:
		var z := CH_Z0 + 0.85 + float(i) * 1.05
		for sx in [-1.0, 1.0]:
			_box(Vector3(0.11, 0.58, 0.74), Vector3(sx * CH_X, 1.72, z), Vector3.ZERO, trim)
			_glass(Vector3(0.05, 0.46, 0.62), Vector3(sx * (CH_X + 0.01), 1.72, z))
	# Cabin lamp: on the deckhead, centred on the middle pair of side windows
	# (z = 1.45). A box floating 20 cm below the sole-head looked like it had
	# been put down crooked rather than hung.
	var cabin_lamp_z := CH_Z0 + 0.85 + 1.05
	_lit_window = _mat(Color(0.30, 0.20, 0.10), 0.55)
	_lit_window.emission_enabled = true
	_lit_window.emission = Color(1.0, 0.66, 0.30)
	_lit_window.emission_energy_multiplier = 2.2
	_cyl(0.025, 0.025, 0.08, Vector3(0.0, CH_Y1 - 0.04, cabin_lamp_z), Vector3.ZERO, metal)
	_box(Vector3(0.18, 0.12, 0.18), Vector3(0.0, CH_Y1 - 0.14, cabin_lamp_z), Vector3.ZERO, _lit_window)
	_cabin_lamp = OmniLight3D.new()
	_cabin_lamp.position = Vector3(0.0, CH_Y1 - 0.24, cabin_lamp_z)
	_cabin_lamp.light_color = Color(1.0, 0.62, 0.30)
	_cabin_lamp.light_energy = 1.6
	_cabin_lamp.omni_range = 4.2
	_cabin_lamp.omni_attenuation = 1.6
	_cabin_lamp.shadow_enabled = false
	add_child(_cabin_lamp)

	# --- cabin fit-out ------------------------------------------------------
	# A home, not a hold. Bunk made up along the port side, table and stool to
	# starboard, a shelf of books over them, a cupboard by the forward door, the
	# stove in the aft corner with its pipe running up through the deckhead into
	# the funnel on the roof, and a worn rug on the sole between them.
	var blanket := _mat(Color(0.34, 0.10, 0.09), 0.96)
	var linen := _mat(Color(0.60, 0.56, 0.48), 0.94)
	var rug_red := _mat(Color(0.27, 0.11, 0.09), 0.97)
	var rug_edge := _mat(Color(0.40, 0.31, 0.18), 0.97)
	var books: Array[StandardMaterial3D] = [
		_mat(Color(0.25, 0.16, 0.10), 0.9),
		_mat(Color(0.13, 0.19, 0.15), 0.9),
		_mat(Color(0.30, 0.24, 0.12), 0.9),
	]

	# --- cabin furniture ------------------------------------------------------
	# Laid out from a check of the volumes rather than by eye. The old
	# arrangement had the stove standing inside the foot of the bunk and the
	# cupboard let into the forward bulkhead; both are gone. Three zones now,
	# and nothing crosses between them:
	#   forward bay  z -0.38 .. 0.95   table and stool to port, cupboard and
	#                                  sea chest to starboard
	#   corridor     z  0.95 .. 3.95   companionway to port, bunk to starboard,
	#                                  1.49 m of clear deck between them
	#   aft bay      z  3.95 .. 4.58   the stove, and the foot of the stairs

	# Bunk: frame, mattress, blanket over the foot, pillow at the head, and a
	# lee-board so the sleeper stays in it in a seaway.
	_box(Vector3(0.76, 0.30, 2.00), Vector3(1.30, 0.85, 2.30), Vector3.ZERO, trim)
	_box(Vector3(0.72, 0.10, 1.94), Vector3(1.30, 1.05, 2.30), Vector3.ZERO, linen)
	_box(Vector3(0.74, 0.07, 1.15), Vector3(1.30, 1.12, 2.76), Vector3.ZERO, blanket)
	_box(Vector3(0.46, 0.09, 0.36), Vector3(1.30, 1.13, 1.52), Vector3.ZERO, linen)
	_box(Vector3(0.05, 0.26, 2.00), Vector3(0.94, 1.05, 2.30), Vector3.ZERO, trim)

	# Dive locker, port side across from the bunk — where the table used to be.
	# A steel wardrobe bolted to the frames: a working boat keeps her gear where
	# it drips onto the sole and not into the bedding.
	_build_dive_locker()

	# Shelf of books on the starboard wall, over the head of the bunk, with a
	# fiddle so they stay put.
	_box(Vector3(0.24, 0.05, 1.10), Vector3(1.58, 1.98, 2.20), Vector3.ZERO, trim)
	_box(Vector3(0.24, 0.05, 0.04), Vector3(1.58, 2.30, 1.68), Vector3.ZERO, trim)
	for i in 6:
		var bz := 1.76 + float(i) * 0.165
		_box(Vector3(0.17, 0.22 + 0.05 * float(i % 3), 0.10),
				Vector3(1.58, 2.12, bz), Vector3(0.0, 0.0, 2.0 * float(i % 2)), books[i % 3])
	_box(Vector3(0.24, 0.04, 1.10), Vector3(1.58, 2.02, 2.20), Vector3.ZERO, trim)

	# Cupboard, forward starboard corner — clear of the bulkhead it used to be
	# buried in.
	_box(Vector3(0.46, 1.05, 0.40), Vector3(1.43, 1.21, -0.05), Vector3.ZERO, trim)
	_box(Vector3(0.38, 0.92, 0.03), Vector3(1.43, 1.20, 0.16), Vector3.ZERO, dark)
	_box(Vector3(0.05, 0.05, 0.05), Vector3(1.43, 1.20, 0.18), Vector3.ZERO, metal)

	# Sea chest, abaft the cupboard.
	_box(Vector3(0.45, 0.42, 0.45), Vector3(1.385, 0.90, 0.575), Vector3(0.0, 8.0, 0.0), dark)
	_box(Vector3(0.47, 0.06, 0.47), Vector3(1.385, 1.13, 0.575), Vector3(0.0, 8.0, 0.0), trim)

	# Cabin heater, in the aft bay. An ELECTRIC bar fire in a cast case: no
	# flue, no fuel, no chimney — and therefore something you switch rather
	# than something you light. Elements take their time both ways, which is
	# the whole character of the thing: E and it climbs to a slow red, E again
	# and it fades out over the better part of a minute, still ticking.
	var heater_case := _mat(Color(0.135, 0.132, 0.128), 0.62, 0.45)
	_box(Vector3(0.46, 0.55, 0.42), Vector3(1.28, 0.92, 4.28), Vector3.ZERO, heater_case)
	# Reflector bowl behind the elements: brushed, so it throws the glow back
	# into the room instead of swallowing it.
	_box(Vector3(0.36, 0.34, 0.02), Vector3(1.28, 0.94, 4.09),
			Vector3.ZERO, _mat(Color(0.52, 0.50, 0.46), 0.28, 0.85))
	# Three bar elements. THESE are the light: coiled wire that goes from dead
	# grey to orange as it takes the current.
	_stove_ember = _mat(Color(0.16, 0.13, 0.115), 0.55)
	_stove_ember.emission_enabled = true
	_stove_ember.emission = Color(1.0, 0.34, 0.09)
	_stove_ember.emission_energy_multiplier = 0.0
	for eb in 3:
		_cyl(0.017, 0.017, 0.34, Vector3(1.28, 0.80 + float(eb) * 0.13, 4.075),
				Vector3(0.0, 0.0, 90.0), _stove_ember)
	# Guard bars across the front, because a red-hot element at shin height in
	# a rolling boat is exactly what a guard is for.
	for gb in 5:
		_cyl(0.006, 0.006, 0.40, Vector3(1.28, 0.74 + float(gb) * 0.10, 4.048),
				Vector3(0.0, 0.0, 90.0), metal)
	_box(Vector3(0.03, 0.42, 0.03), Vector3(1.09, 0.94, 4.048), Vector3.ZERO, metal)
	_box(Vector3(0.03, 0.42, 0.03), Vector3(1.47, 0.94, 4.048), Vector3.ZERO, metal)
	# Rocker switch on the case top, and the flex running down to the skirting.
	_box(Vector3(0.05, 0.02, 0.07), Vector3(1.28, 1.205, 4.20), Vector3.ZERO,
			_mat(Color(0.36, 0.27, 0.13), 0.40, 0.75))
	_cyl(0.008, 0.008, 0.52, Vector3(1.47, 0.70, 4.44), Vector3(22.0, 0.0, 0.0),
			_mat(Color(0.055, 0.055, 0.058), 0.85))
	_stove_lamp = OmniLight3D.new()
	_stove_lamp.position = Vector3(1.28, 1.02, 4.08)
	_stove_lamp.light_color = Color(1.0, 0.42, 0.14)
	_stove_lamp.light_energy = 1.55
	_stove_lamp.omni_range = 1.85
	_stove_lamp.omni_attenuation = 3.2
	_stove_lamp.light_volumetric_fog_energy = 2.4
	_stove_lamp.shadow_enabled = false
	add_child(_stove_lamp)
	_build_stove_heat()
	_build_cabin_lived(trim, metal)

	# Doors that actually work. Each leaf hangs on a pivot at its hinge and
	# swings; E on it opens or shuts it. Shut, it puts a blocker across the
	# doorway (see door_blockers) so it is a door and not a picture of one.
	for k in 2:
		# Far enough off the bulkhead that the leaf shuts AGAINST the jamb
		# instead of into it. At 0.06 the leaf and the jamb were 2.5 mm apart in
		# z, which is a z-fight waiting for the first person to widen the leaf.
		var dz: float = (CH_Z0 + 0.085) if k == 0 else (CH_Z1 - 0.085)
		var piv := Node3D.new()
		piv.position = Vector3(-0.55, 0.0, dz)
		add_child(piv)
		# Panelled leaf: frame, two panels, a knob and a plate.
		# The leaf is 1.12 for a 1.10 opening, so it LAPS the jamb by a
		# centimetre either side. At 1.06 it was 4 cm short of the frame and you
		# could see daylight down the closing edge of a shut door.
		_box(Vector3(1.12, 1.92, 0.045), Vector3(0.56, 1.64, 0.0), Vector3.ZERO, trim, piv)
		_box(Vector3(0.72, 0.62, 0.055), Vector3(0.56, 2.16, 0.0), Vector3.ZERO,
				_mat(Color(0.105, 0.072, 0.048), 0.85), piv)
		_box(Vector3(0.72, 0.72, 0.055), Vector3(0.56, 1.24, 0.0), Vector3.ZERO,
				_mat(Color(0.105, 0.072, 0.048), 0.85), piv)
		_cyl(0.022, 0.022, 0.07, Vector3(0.97, 1.62, 0.0), Vector3(90.0, 0.0, 0.0), metal, piv)
		_box(Vector3(0.05, 0.16, 0.012), Vector3(0.97, 1.62, 0.032), Vector3.ZERO, metal, piv)
		for hy in [1.02, 2.22]:
			_cyl(0.014, 0.014, 0.07, Vector3(0.02, hy, 0.0), Vector3(0.0, 0.0, 90.0), metal, piv)
		if k == 0:
			_door_fwd = piv
		else:
			_door_aft = piv

	# Rug on the sole, down the corridor between the stairs and the bunk.
	_box(Vector3(0.90, 0.025, 1.60), Vector3(0.20, 0.70, 2.30), Vector3.ZERO, rug_red)
	_box(Vector3(0.90, 0.028, 0.12), Vector3(0.20, 0.70, 1.56), Vector3.ZERO, rug_edge)
	_box(Vector3(0.90, 0.028, 0.12), Vector3(0.20, 0.70, 3.04), Vector3.ZERO, rug_edge)

	# --- wheelhouse (upper level) -------------------------------------------
	const WH_Z0 := -0.25
	const WH_Z1 := 4.05
	const WH_X := 1.74
	const WH_Y0 := 2.91   # sole: the top of the deckhouse roof
	const WH_Y1 := 5.34   # deckhead — the glass band has to run well past the
	# standing eye at 4.36, or the horizon lands exactly on the header.
	var wy := (WH_Y0 + WH_Y1) * 0.5
	var wh := WH_Y1 - WH_Y0
	var wz := (WH_Z0 + WH_Z1) * 0.5
	var wl := WH_Z1 - WH_Z0

	_box(Vector3(WH_X * 2.0 + 0.22, 0.16, wl + 0.30), Vector3(0.0, WH_Y1 + 0.08, wz),
			Vector3.ZERO, paint_dark)
	# Sill to 3.32, glass to 4.74, header above: the standing eye (4.36) sits in
	# the MIDDLE of the pane, so the horizon is glass, not woodwork.
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.09, 0.50, wl), Vector3(sx * WH_X, 3.16, wz), Vector3.ZERO, paint)
		_box(Vector3(0.09, 0.25, wl), Vector3(sx * WH_X, 5.215, wz), Vector3.ZERO, paint)
		_box(Vector3(0.10, wh, 0.10), Vector3(sx * WH_X, wy, WH_Z0), Vector3.ZERO, trim)
		_box(Vector3(0.10, wh, 0.10), Vector3(sx * WH_X, wy, WH_Z1), Vector3.ZERO, trim)
		_glass(Vector3(0.05, 1.68, wl - 0.14), Vector3(sx * WH_X, 4.25, wz))
	_box(Vector3(WH_X * 2.0, 0.50, 0.09), Vector3(0.0, 3.16, WH_Z0), Vector3.ZERO, paint)
	_box(Vector3(WH_X * 2.0, 0.25, 0.09), Vector3(0.0, 5.215, WH_Z0), Vector3.ZERO, paint)
	# The front pane gets its own material: it is the one with the wiper.
	_front_glass_mat = _glass_mat.duplicate()
	_front_glass_mat.set_shader_parameter("has_wiper", 1)
	_glass(Vector3(WH_X * 2.0 - 0.16, 1.68, 0.05), Vector3(0.0, 4.25, WH_Z0), _front_glass_mat)
	# Wiper arm on the outside of the glass, pivoted low on the pane.
	_wiper_pivot = Node3D.new()
	_wiper_pivot.position = Vector3(0.0, 3.45, WH_Z0 - 0.045)
	add_child(_wiper_pivot)
	var wiper_arm := _mat(Color(0.06, 0.06, 0.06), 0.6, 0.4)
	_box(Vector3(0.035, 1.05, 0.02), Vector3(0.0, 0.52, 0.0), Vector3.ZERO, wiper_arm, _wiper_pivot)
	_box(Vector3(0.05, 0.30, 0.025), Vector3(0.0, 1.00, 0.005), Vector3.ZERO, wiper_arm, _wiper_pivot)
	# Aft face. The doorway is on the centreline, out onto the roof balcony.
	# Port of it is a solid panel (it also closes the stairwell). Starboard is
	# glass over a sill, with a jamb so the door has something to hang on.
	_box(Vector3(1.23, wh, 0.09), Vector3(-1.185, wy, WH_Z1), Vector3.ZERO, paint)
	_box(Vector3(1.07, 0.50, 0.09), Vector3(1.205, 3.16, WH_Z1), Vector3.ZERO, paint)
	_box(Vector3(0.12, wh, 0.09), Vector3(0.61, wy, WH_Z1), Vector3.ZERO, paint)
	_box(Vector3(3.48, 0.25, 0.09), Vector3(0.0, 5.215, WH_Z1), Vector3.ZERO, paint)
	_box(Vector3(1.14, 0.26, 0.09), Vector3(0.0, 4.96, WH_Z1), Vector3.ZERO, paint)
	_box(Vector3(1.14, 0.06, 0.10), Vector3(0.0, WH_Y0 + 0.03, WH_Z1), Vector3.ZERO, trim)
	_glass(Vector3(1.07, 1.68, 0.05), Vector3(1.205, 4.25, WH_Z1))

	# The balcony door. Hinged starboard so it parks against the glass, not
	# over the companionway. Inward, the way the cabin doors do — the balcony
	# is only a metre deep and a leaf that size would hit the aft rail.
	var wh_piv := Node3D.new()
	wh_piv.position = Vector3(0.55, WH_Y0, WH_Z1 - 0.04)
	add_child(wh_piv)
	_box(Vector3(1.06, 1.88, 0.045), Vector3(-0.53, 0.96, 0.0), Vector3.ZERO, trim, wh_piv)
	_box(Vector3(0.72, 0.58, 0.055), Vector3(-0.53, 1.42, 0.0), Vector3.ZERO,
			_mat(Color(0.105, 0.072, 0.048), 0.85), wh_piv)
	_box(Vector3(0.72, 0.68, 0.055), Vector3(-0.53, 0.58, 0.0), Vector3.ZERO,
			_mat(Color(0.105, 0.072, 0.048), 0.85), wh_piv)
	_cyl(0.022, 0.022, 0.07, Vector3(-0.94, 0.94, 0.0), Vector3(90.0, 0.0, 0.0), metal, wh_piv)
	_box(Vector3(0.05, 0.16, 0.012), Vector3(-0.94, 0.94, -0.032), Vector3.ZERO, metal, wh_piv)
	for hy in [0.38, 1.50]:
		_cyl(0.014, 0.014, 0.07, Vector3(-0.02, hy, 0.0), Vector3(0.0, 0.0, 90.0), metal, wh_piv)
	_door_wh = wh_piv

	# The centre of the room stays EMPTY: aft door -> wheel is a straight walk.
	_build_chart_table(trim, metal)
	_build_electronics(trim, metal)
	_build_switchboard(trim, metal)
	# Helm lamp: dead centre of the wheelhouse deckhead, not 15 cm aft of it
	# and not sitting inside the window header.
	_helm_glow = _mat(Color(0.30, 0.20, 0.10), 0.55)
	_helm_glow.emission_enabled = true
	_helm_glow.emission = Color(1.0, 0.66, 0.30)
	_helm_glow.emission_energy_multiplier = 2.2
	_cyl(0.02, 0.02, 0.10, Vector3(0.0, WH_Y1 - 0.05, wz), Vector3.ZERO, metal)
	_box(Vector3(0.16, 0.12, 0.16), Vector3(0.0, WH_Y1 - 0.16, wz), Vector3.ZERO, _helm_glow)
	_helm_lamp = OmniLight3D.new()
	_helm_lamp.position = Vector3(0.0, WH_Y1 - 0.26, wz)
	_helm_lamp.light_color = Color(1.0, 0.50, 0.24)
	_helm_lamp.light_energy = 1.1
	_helm_lamp.omni_range = 3.8
	_helm_lamp.omni_attenuation = 1.8
	_helm_lamp.shadow_enabled = false
	add_child(_helm_lamp)

	_build_helm(trim, metal)
	_build_console(trim, metal)

	# --- mast, funnel, rails ------------------------------------------------
	# Mast and its yard. There was a boom too — a 2.4 m spar lying fore-and-aft
	# at chest height under the mast, running from z -2.45 aft to -0.05, which
	# put its inboard end THROUGH the cabin's forward bulkhead and into the
	# room. Nothing was rigged to it and it was in the way of the one clear walk
	# up the foredeck, so it is gone.
	var mast := Node3D.new()
	mast.position = Vector3(0.0, 3.10, -2.35)
	mast.rotation_degrees = Vector3(0.0, 0.0, 3.0)
	add_child(mast)
	_cyl(0.11, 0.075, 5.20, Vector3.ZERO, Vector3.ZERO, trim, mast)
	_box(Vector3(1.70, 0.07, 0.07), Vector3(0.0, 1.45, 0.0), Vector3.ZERO, trim, mast)
	# Masthead beacon. The stick leans three degrees, so a world-space lamp at
	# x = 0 sat beside the truck, not on it. These sit on the mast's own axis,
	# the base flush with the top of the pole.
	_beacon_mat = StandardMaterial3D.new()
	_beacon_mat.albedo_color = Color(0.32, 0.05, 0.04)
	_beacon_mat.emission_enabled = true
	_beacon_mat.emission = Color(1.0, 0.15, 0.10)
	_beacon_mat.emission_energy_multiplier = 0.0
	var truck := 2.60
	_cyl(0.10, 0.10, 0.12, Vector3(0.0, truck + 0.06, 0.0), Vector3.ZERO, metal, mast)
	_cyl(0.085, 0.085, 0.20, Vector3(0.0, truck + 0.22, 0.0), Vector3.ZERO, _beacon_mat, mast)
	_cyl(0.11, 0.02, 0.10, Vector3(0.0, truck + 0.37, 0.0), Vector3.ZERO, metal, mast)
	_beacon = OmniLight3D.new()
	_beacon.position = Vector3(0.0, truck + 0.22, 0.0)
	_beacon.light_color = Color(1.0, 0.16, 0.10)
	_beacon.light_energy = 0.0
	_beacon.omni_range = 26.0
	_beacon.omni_attenuation = 1.3
	_beacon.shadow_enabled = false
	mast.add_child(_beacon)
	# No funnel. The cabin heater is electric now — it burns nothing, so there
	# is nothing to take up a flue, and a stack that vents an appliance with no
	# fire in it is a lie standing on the roof. The balcony is clear.
	# Foredeck rail: stanchions plus a top rail.
	for i in 7:
		var t := float(i) / 6.0
		var rz := lerpf(-3.85, -0.55, t)
		var rx := lerpf(1.69, 1.94, t)
		_cyl(0.035, 0.035, 0.62, Vector3(-rx, 1.42, rz), Vector3.ZERO, metal)
		_cyl(0.035, 0.035, 0.62, Vector3(rx, 1.42, rz), Vector3.ZERO, metal)
	# The top rail caps the STANCHIONS. It used to sit at x 1.18 while the posts
	# it was supposed to cap ran 1.69 to 1.94 — half a metre inboard of its own
	# supports, so it floated across the deck and buried itself in the bulwark.
	# Centre and angle are now derived from the posts: mid-point (1.815, -2.20),
	# and atan2(0.25, 3.30) = 4.3 degrees of splay.
	_box(Vector3(0.05, 0.05, 3.32), Vector3(-1.815, 1.72, -2.20), Vector3(0.0, 4.33, 0.0), metal)
	_box(Vector3(0.05, 0.05, 3.32), Vector3(1.815, 1.72, -2.20), Vector3(0.0, -4.33, 0.0), metal)
	# Rail round the deckhouse roof, so standing up there is not a sheer drop.
	_box(Vector3(0.05, 0.05, 4.9), Vector3(-1.80, 3.29, 2.10), Vector3.ZERO, metal)
	_box(Vector3(0.05, 0.05, 4.9), Vector3(1.80, 3.29, 2.10), Vector3.ZERO, metal)
	for i in 7:
		var sz := lerpf(-0.30, 4.50, float(i) / 6.0)
		_cyl(0.03, 0.03, 0.56, Vector3(-1.80, 3.11, sz), Vector3.ZERO, metal)
		_cyl(0.03, 0.03, 0.56, Vector3(1.80, 3.11, sz), Vector3.ZERO, metal)
	# Ladder up the back of the deckhouse: deck -> roof -> wheelhouse door.
	# The side rails run well PAST the roof, the way every real ship's ladder
	# does — they are what you grab to swing yourself on at the top.
	# Rail right across the aft edge of the roof. No opening in it now: you go
	# below through the wheelhouse and down the companionway, so there is
	# nothing back here left to fall off.
	_box(Vector3(3.62, 0.05, 0.05), Vector3(0.0, 3.29, 5.06), Vector3.ZERO, metal)
	for i in 5:
		_cyl(0.03, 0.03, 0.56, Vector3(-1.78 + float(i) * 0.89, 3.11, 5.06),
				Vector3.ZERO, metal)

	_build_deck_gear(trim, metal)

	# --- companionway ------------------------------------------------------
	# Eight treads up the port side of the cabin, through an opening in the
	# deckhead. Walked, not climbed.
	for i in 10:
		# Numbered from the bottom, so tread 0 is the one you step onto off the
		# sole and tread 9 is level with the wheelhouse deck.
		var ty := 0.903 + float(i) * 0.223
		var tz := 3.80 - float(i) * 0.30
		# The board is hung so its TOP is exactly the height you walk at. Centred
		# on it instead, every step stands three centimetres proud of the surface
		# your feet are actually on, and you spend the whole flight shin-deep in
		# the treads.
		_box(Vector3(1.16, 0.06, 0.30), Vector3(-1.08, ty - 0.03, tz), Vector3.ZERO, trim)
		_box(Vector3(1.16, 0.163, 0.05), Vector3(-1.08, ty - 0.1415, tz + 0.125),
				Vector3.ZERO, trim)
	# The inboard side of the flight is three separate pieces of joinery in
	# three separate SLABS OF X, and that is the whole point of these numbers.
	# They used to share one: the stringer at -0.52, the closing boards at
	# -0.515 and the engine-door frame at -0.515, all 4 to 5 cm thick — three
	# solids inside the same two centimetres of space, coplanar faces and all.
	# That is the flicker and the clash down the side of the stair.
	#
	#   stringer        -0.600 .. -0.550   the raking beam that carries it
	#   closing boards  -0.550 .. -0.500   the panel between beam and cabin
	#   door frame      -0.500 .. -0.455   standing proud of the panel, as a
	#                                      frame does
	_box(Vector3(0.05, 0.30, 3.10), Vector3(-0.575, 1.86, 2.42), Vector3(-36.6, 0.0, 0.0), trim)
	# Handrail. A companionway has one, and without it this read as a flight of
	# boards with two bare posts standing near it. It rakes with the treads, one
	# hand's width off the joinery, on two short stanchions.
	var rail_m := _mat(Color(0.30, 0.21, 0.11), 0.55, 0.25)
	_cyl(0.024, 0.024, 3.05, Vector3(-0.62, 2.62, 2.42), Vector3(-36.6, 0.0, 0.0), rail_m)
	for rz in [1.55, 3.25]:
		# Stanchion from the stringer up to the rail, at the rake of the stair.
		var ry: float = 2.91 - (rz - 1.10) * 0.7431
		_cyl(0.017, 0.017, 0.60, Vector3(-0.62, ry + 0.42, rz), Vector3.ZERO, rail_m)
	# Closing boards down the inboard side, stepping with the treads, so the
	# stair reads as a solid piece of joinery from the cabin rather than a
	# flight of planks with daylight under it. The middle of the flight is
	# left open: that is the engine-room window, framed in steel.
	var frame := _mat(Color(0.18, 0.19, 0.20), 0.35, 0.55)
	for k in 9:
		# Trim only, so these can close right up under the tread even though the
		# collision volume behind them has to stop short.
		var by := 2.910 - float(k) * 0.223 - 0.03
		if k >= 2 and k <= 5:
			# The engine bay is left ENTIRELY open. There used to be a strip of
			# closing board over the door head; it was still standing across the
			# view with the door swung back, which is the one thing an access
			# door exists to prevent. The leaf below now runs the full height of
			# the bay, so there is nothing left for a strip to close.
			continue
		_box(Vector3(0.05, by - 0.68, 0.30), Vector3(-0.525, (0.68 + by) * 0.5,
				1.10 + float(k) * 0.30), Vector3.ZERO, trim)

	# The engine door. Hinged on its forward edge, steel-framed like the
	# machinery panel it is, swinging into the cabin so the whole well shows.
	_door_eng = Node3D.new()
	_door_eng.position = Vector3(-0.500, 1.24, 1.70)
	add_child(_door_eng)
	var leaf := _box_node(Vector3(0.045, 1.44, 0.90), Vector3(0.0, 0.23, 0.45), trim)
	_door_eng.add_child(leaf)
	var lf := _box_node(Vector3(0.052, 1.44, 0.05), Vector3(0.0, 0.23, 0.025), frame)
	_door_eng.add_child(lf)
	var lf2 := _box_node(Vector3(0.052, 1.44, 0.05), Vector3(0.0, 0.23, 0.875), frame)
	_door_eng.add_child(lf2)
	var lf3 := _box_node(Vector3(0.052, 0.06, 0.90), Vector3(0.0, 0.92, 0.45), frame)
	_door_eng.add_child(lf3)
	var lf4 := _box_node(Vector3(0.052, 0.06, 0.90), Vector3(0.0, -0.46, 0.45), frame)
	_door_eng.add_child(lf4)
	# Latch handle on the free edge, and a pair of hinge knuckles on the hung one.
	var bronze_h := _mat(Color(0.36, 0.27, 0.13), 0.4, 0.7)
	var hnd := _box_node(Vector3(0.028, 0.13, 0.030), Vector3(-0.035, 0.02, 0.82), bronze_h)
	_door_eng.add_child(hnd)
	for hy in [-0.34, 0.34, 0.82]:
		var kn := _box_node(Vector3(0.055, 0.075, 0.030), Vector3(0.0, hy, 0.03), frame)
		_door_eng.add_child(kn)
	# The frame stands PROUD of the closing boards, the way a door frame does,
	# and it is a closed rectangle. The stray post that used to stand at z 2.88
	# was buried inside a closing board — one of the two bare rods you could see
	# from the cabin with nothing joining them to anything.
	_box(Vector3(0.045, 1.52, 0.045), Vector3(-0.478, 1.47, 1.655), Vector3.ZERO, frame)
	_box(Vector3(0.045, 1.52, 0.045), Vector3(-0.478, 1.47, 2.645), Vector3.ZERO, frame)
	_box(Vector3(0.045, 0.045, 1.035), Vector3(-0.478, 2.208, 2.15), Vector3.ZERO, frame)
	_box(Vector3(0.045, 0.045, 1.035), Vector3(-0.478, 0.732, 2.15), Vector3.ZERO, frame)
	_cyl(0.028, 0.028, 3.35, Vector3(-0.52, 2.66, 2.42), Vector3(53.4, 0.0, 0.0), metal)
	for i in 4:
		_cyl(0.022, 0.022, 0.90, Vector3(-0.52, 1.42 + float(i) * 0.50,
				3.35 - float(i) * 0.67), Vector3.ZERO, metal)
	# Coaming round the opening on the upper deck, so it reads as a stairwell.
	# Trim only — it used to be a collider too, and between it and the wheelhouse
	# side that left a three-centimetre gap to squeeze the top step through.
	_box(Vector3(0.05, 0.26, 2.40), Vector3(-0.52, 3.04, 2.75), Vector3.ZERO, trim)
	_box(Vector3(1.22, 0.26, 0.05), Vector3(-1.08, 3.04, 3.95), Vector3.ZERO, trim)
	# Guard rail on top of the coaming, matching the collider. A 26 cm kerb is
	# something you trip over on the way past; this is something you hold.
	_box(Vector3(0.05, 0.05, 2.40), Vector3(-0.52, 3.80, 2.75), Vector3.ZERO, metal)
	for i in 4:
		_cyl(0.025, 0.025, 0.62, Vector3(-0.52, 3.48, 1.70 + float(i) * 0.72),
				Vector3.ZERO, metal)

	# --- forward floodlights ------------------------------------------------
	# Two of them, on the roof edge between the decks, throwing light out ahead
	# of the bow. Their own circuit: 6, or the panel's master switch.
	# The lens material has to exist BEFORE the loop — it used to be created
	# after, so the glasses were assigned null and never lit, which is why
	# throwing the switch did nothing you could see.
	_flood_lens_mat = StandardMaterial3D.new()
	_flood_lens_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flood_lens_mat.albedo_color = Color(0.16, 0.14, 0.11)
	_flood_lens_mat.emission_enabled = true
	_flood_lens_mat.emission = Color(1.0, 0.95, 0.82)
	_flood_lens_mat.emission_energy_multiplier = 0.0
	_flood_beam_mat = ShaderMaterial.new()
	_flood_beam_mat.shader = load("res://shaders/lighthouse_beam.gdshader")
	_flood_beam_mat.set_shader_parameter("intensity", 0.0)
	_flood_beam_mat.set_shader_parameter("gain", 0.9)
	_flood_beam_mat.set_shader_parameter("reach", 0.72)
	_flood_beam_mat.set_shader_parameter("edge_soft", 1.35)
	_flood_beam_mat.set_shader_parameter("soft_metres", 8.0)
	_flood_beam_mat.set_shader_parameter("haze", 1.0)
	_flood_beam_mat.set_shader_parameter("beam_color", Color(1.0, 0.94, 0.80))
	const BLEN := 28.0
	var bdip := deg_to_rad(12.0)
	for sx in [-1.0, 1.0]:
		var fp := Vector3(sx * 1.22, 3.06, -0.56)
		_box(Vector3(0.10, 0.16, 0.10), fp + Vector3(0.0, -0.09, 0.0), Vector3.ZERO, metal)
		_cyl(0.10, 0.12, 0.20, fp, Vector3(-72.0, 0.0, 0.0), metal)
		var lens := MeshInstance3D.new()
		var lmz := CylinderMesh.new()
		lmz.top_radius = 0.105
		lmz.bottom_radius = 0.105
		lmz.height = 0.03
		lmz.radial_segments = 12
		lmz.material = _flood_lens_mat
		lens.mesh = lmz
		lens.position = fp + Vector3(0.0, -0.03, -0.10)
		lens.rotation_degrees = Vector3(-72.0, 0.0, 0.0)
		add_child(lens)
		var fl := SpotLight3D.new()
		fl.position = fp + Vector3(0.0, -0.02, -0.12)
		fl.rotation_degrees = Vector3(-12.0, 0.0, 0.0)
		fl.light_color = Color(1.0, 0.94, 0.80)
		fl.light_energy = 0.0
		fl.spot_range = 48.0
		fl.spot_angle = 28.0
		fl.spot_attenuation = 0.55
		fl.spot_angle_attenuation = 0.55
		fl.light_specular = 0.85
		fl.light_volumetric_fog_energy = 14.0
		fl.shadow_enabled = false
		add_child(fl)
		_floods.append(fl)
		# A short shaft you can actually see. The spot's volumetric fog dies
		# in the froxels; this cone is the same trick the lighthouse uses.
		var shaft := MeshInstance3D.new()
		var sc := CylinderMesh.new()
		sc.top_radius = 7.2
		sc.bottom_radius = 0.07
		sc.height = BLEN
		sc.radial_segments = 16
		sc.rings = 1
		sc.cap_top = false
		sc.cap_bottom = false
		sc.material = _flood_beam_mat
		shaft.mesh = sc
		shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		shaft.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		shaft.rotation_degrees = Vector3(-102.0, 0.0, 0.0)
		shaft.position = fp + Vector3(0.0, -sin(bdip) * BLEN * 0.5,
				-cos(bdip) * BLEN * 0.5)
		add_child(shaft)


func _build_console(trim: Material, metal: Material) -> void:
	## The helm station. Everything you need while steering is FORWARD of you,
	## under the glass, and the walk from the aft door to the wheel stays clear.
	##
	## The instruments are ANALOGUE — brass bezels, black faces, cream needles
	## on a 240-degree sweep, and a proper card compass that swings under a fixed
	## lubber line. No numbers ticking over: on a boat this old you read a needle
	## at a glance in the dark, and the paint on the ticks is what you see.
	var bronze := _mat(Color(0.34, 0.26, 0.13), 0.40, 0.72)
	var dial_face := _mat(Color(0.030, 0.028, 0.026), 0.72)
	_dial_ink = _mat(Color(0.80, 0.76, 0.66), 0.55)
	_dial_ink.emission_enabled = true
	_dial_ink.emission = Color(0.72, 0.80, 0.62)
	_dial_ink.emission_energy_multiplier = 0.35   # old radium paint, barely alive

	# --- console body -------------------------------------------------------
	_box(Vector3(1.86, 0.54, 0.32), Vector3(0.0, 3.20, -0.10), Vector3.ZERO, trim)

	# The gauge plate is raked BACK so its face points up at the helmsman's eye.
	# It used to be raked the other way — the dials were aimed out the window.
	var face := Node3D.new()
	face.position = Vector3(0.0, 3.45, -0.05)
	face.rotation_degrees.x = 42.0
	add_child(face)
	_box(Vector3(1.86, 0.03, 0.32), Vector3.ZERO, Vector3.ZERO, metal, face)

	# --- dials --------------------------------------------------------------
	_needles.append(_make_dial(face, -0.84, 0.095, "PARAKETE", ["0", "10", "20"],
			bronze, dial_face))                                    # 0: speed
	_needles.append(_make_dial(face, -0.58, 0.095, "SOUNDER", ["0", "20", "40"],
			bronze, dial_face))                                    # 1: depth
	_needles.append(_make_dial(face, 0.14, 0.095, "CHAIN", ["0", "35", "70"],
			bronze, dial_face))                                    # 2: chain
	_make_compass(face, -0.24, 0.135, bronze, dial_face)

	# --- throttle: a lever ON the console, right-hand end --------------------
	# No freestanding pedestal — it read as a bar stool in the middle of the
	# room. The lever grows out of the console where your right hand falls.
	_box(Vector3(0.18, 0.10, 0.20), Vector3(0.70, 3.51, 0.02), Vector3.ZERO, metal)
	_thr_lever = Node3D.new()
	# Inboard and aft of where it was. A telegraph you cannot reach without
	# letting go of the wheel is a telegraph nobody uses; 8 cm in and 20 cm aft
	# brings the knob inside a leaning right arm while keeping it on the
	# starboard console where it belongs.
	_thr_lever.position = Vector3(0.58, 3.62, 0.30)
	add_child(_thr_lever)
	var lever := MeshInstance3D.new()
	var lm := CylinderMesh.new()
	lm.top_radius = 0.020
	lm.bottom_radius = 0.026
	lm.height = 0.30
	lm.radial_segments = 8
	lm.rings = 1
	lm.material = bronze
	lever.mesh = lm
	lever.position = Vector3(0.0, 0.15, 0.0)
	_thr_lever.add_child(lever)
	var knob := MeshInstance3D.new()
	var km := SphereMesh.new()
	km.radius = 0.032
	km.height = 0.064
	km.material = trim
	knob.mesh = km
	knob.position = Vector3(0.0, 0.31, 0.0)
	_thr_lever.add_child(knob)

	# quadrant plate the lever swings over: engraved ahead / stop / astern
	_box(Vector3(0.12, 0.42, 0.025), Vector3(0.87, 3.65, 0.02), Vector3.ZERO, trim)
	_box(Vector3(0.10, 0.014, 0.012), Vector3(0.87, 3.65, 0.038), Vector3.ZERO, _dial_ink)
	var g_up := _mat(Color(0.10, 0.55, 0.16), 0.6)
	g_up.emission_enabled = true
	g_up.emission = Color(0.12, 0.85, 0.20)
	g_up.emission_energy_multiplier = 0.6
	var g_dn := _mat(Color(0.55, 0.10, 0.08), 0.6)
	g_dn.emission_enabled = true
	g_dn.emission = Color(0.9, 0.14, 0.08)
	g_dn.emission_energy_multiplier = 0.6
	# --- shaft indicator, beside the lever -----------------------------------
	# Thirteen segments in a brass bezel: four red below the stop mark for
	# astern, eight green above it for ahead. It reads the SHAFT, not the lever,
	# so what you watch is the engine catching up with what you just asked for —
	# and the little bronze pointer alongside is the lever, so the gap between
	# the two IS the lag. It was two boxes that stretched; a stretching box
	# reads as a bar of paint, not as an instrument.
	var bezel := _mat(Color(0.30, 0.23, 0.11), 0.38, 0.78)
	_box(Vector3(0.085, 0.44, 0.030), Vector3(0.90, 3.70, 0.030), Vector3.ZERO, bezel)
	_box(Vector3(0.070, 0.42, 0.012), Vector3(0.90, 3.70, 0.046), Vector3.ZERO,
			_mat(Color(0.045, 0.045, 0.042), 0.65))
	for i in 13:
		var idx := i - 4                       # -4 astern .. +8 ahead
		var segy := 3.70 + float(idx) * 0.028
		var m := _mat(Color(0.05, 0.05, 0.05), 0.35)
		m.emission_enabled = true
		m.emission = Color(0.20, 1.0, 0.32) if idx > 0 else (
				Color(1.0, 0.68, 0.16) if idx == 0 else Color(1.0, 0.17, 0.09))
		m.emission_energy_multiplier = 0.0
		_box(Vector3(0.048, 0.017, 0.008), Vector3(0.90, segy, 0.053), Vector3.ZERO, m)
		_pwr_segs.append(m)
		# Long tick every fourth, short between: a scale you can read at a
		# glance without counting lit bars.
		var tw: float = 0.022 if idx % 4 == 0 else 0.012
		_box(Vector3(tw, 0.004, 0.006), Vector3(0.90 + 0.046 + tw * 0.5, segy, 0.046),
				Vector3.ZERO, bezel)
	# The lever's own demand, tracked alongside.
	_pwr_needle = Node3D.new()
	_pwr_needle.position = Vector3(0.845, 3.70, 0.050)
	add_child(_pwr_needle)
	_box(Vector3(0.016, 0.020, 0.006), Vector3.ZERO, Vector3(0.0, 0.0, 45.0),
			_mat(Color(0.52, 0.40, 0.16), 0.35, 0.7), _pwr_needle)

	# Ignition. A key in a barrel, not a switch on a panel — you turn it, you
	# wait, and the diesel catches. Same place your right hand already is.
	var ign := Vector3(0.50, 3.495, 0.06)
	_box(Vector3(0.07, 0.04, 0.07), ign + Vector3(0.0, -0.02, 0.0), Vector3.ZERO, metal)
	_cyl(0.022, 0.022, 0.04, ign, Vector3.ZERO, bronze)
	_cyl(0.010, 0.010, 0.03, ign + Vector3(0.0, 0.018, 0.0), Vector3.ZERO, metal)
	_ign_key = Node3D.new()
	_ign_key.position = ign + Vector3(0.0, 0.028, 0.0)
	add_child(_ign_key)
	_box(Vector3(0.010, 0.004, 0.055), Vector3(0.0, 0.0, 0.018), Vector3.ZERO, metal, _ign_key)
	_cyl(0.016, 0.016, 0.005, Vector3(0.0, 0.0, 0.050), Vector3(90.0, 0.0, 0.0), bronze, _ign_key)
	_box(Vector3(0.022, 0.003, 0.008), Vector3(0.0, 0.0, 0.050), Vector3.ZERO, metal, _ign_key)
	_ign_led = _mat(Color(0.09, 0.09, 0.09), 0.30)
	_ign_led.emission_enabled = true
	_ign_led.emission = Color(1.0, 0.16, 0.10)
	_ign_led.emission_energy_multiplier = 1.1
	_box(Vector3(0.018, 0.010, 0.018), ign + Vector3(0.055, -0.008, 0.02), Vector3.ZERO, bronze)
	var iled := MeshInstance3D.new()
	var ilm := SphereMesh.new()
	ilm.radius = 0.007
	ilm.height = 0.014
	ilm.material = _ign_led
	iled.mesh = ilm
	iled.position = ign + Vector3(0.055, -0.002, 0.02)
	iled.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(iled)
	_console_label("KONTAK", ign + Vector3(0.0, -0.018, 0.055), 28)

	# --- main breaker on the bulkhead ----------------------------------------
	# The flush plate that used to be here is gone: its job belongs to the switch
	# console, where the switches are things you walk up to and throw. What is
	# left is the main breaker, which is what a bulkhead plate is for.
	_box(Vector3(0.03, 0.14, 0.11), Vector3(1.67, 4.02, 2.30), Vector3.ZERO, metal)
	_box(Vector3(0.03, 0.05, 0.03), Vector3(1.685, 4.02, 2.30), Vector3.ZERO, bronze)

	# --- bow roller at the stemhead ------------------------------------------
	# The cable has to leave her over something. Without it the chain simply
	# appeared out of the planking, which is the sort of thing you only notice
	# once and then cannot stop noticing.
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.035, 0.20, 0.34), Vector3(sx * 0.085, 1.16, -4.12),
				Vector3.ZERO, metal)
	_cyl(0.055, 0.055, 0.15, Vector3(0.0, 1.20, -4.12), Vector3(0.0, 0.0, 90.0), metal)
	_box(Vector3(0.22, 0.05, 0.30), Vector3(0.0, 1.05, -4.12), Vector3.ZERO, metal)
	# Stopper on the deck between the windlass and the roller, where the cable
	# is made fast once she is brought up.
	_box(Vector3(0.10, 0.10, 0.14), Vector3(0.0, 0.72, -3.80), Vector3.ZERO, metal)

	# --- spurling pipe and chain locker --------------------------------------
	# The cable has to GO somewhere. It comes in over the roller, round the
	# gypsy, and drops straight down this pipe into the locker in the forepeak —
	# and because the deck is genuinely cut, you can stand on the foredeck and
	# look down it at your own chain lying in the dark.
	var rust_iron := _mat(Color(0.150, 0.115, 0.088), 0.90, 0.30)
	# Raised coaming round the opening, so it is a fitting and not a slot.
	for r_sx in [-0.145, 0.145]:
		_box(Vector3(0.05, 0.09, 0.34), Vector3(r_sx, 0.68, -3.02), Vector3.ZERO, rust_iron)
	for r_sz in [-3.165, -2.875]:
		_box(Vector3(0.34, 0.09, 0.05), Vector3(0.0, 0.68, r_sz), Vector3.ZERO, rust_iron)
	# The pipe itself, dropping into the peak. Open both ends, seen from above.
	for p_sx in [-0.13, 0.13]:
		_box(Vector3(0.02, 0.52, 0.26), Vector3(p_sx, 0.30, -3.02), Vector3.ZERO, rust_iron)
	for p_sz in [-3.15, -2.89]:
		_box(Vector3(0.26, 0.52, 0.02), Vector3(0.0, 0.30, p_sz), Vector3.ZERO, rust_iron)
	# Locker: painted sides and a sole, so what is down there reads as a room
	# rather than as a void the chain disappears into.
	var locker_paint := _mat(Color(0.115, 0.120, 0.115), 0.92, 0.10)
	_box(Vector3(1.10, 0.03, 1.30), Vector3(0.0, 0.045, -3.05), Vector3.ZERO, locker_paint)
	_box(Vector3(0.03, 0.62, 1.30), Vector3(-0.55, 0.34, -3.05), Vector3.ZERO, locker_paint)
	_box(Vector3(0.03, 0.62, 1.30), Vector3(0.55, 0.34, -3.05), Vector3.ZERO, locker_paint)
	_box(Vector3(1.10, 0.62, 0.03), Vector3(0.0, 0.34, -3.70), Vector3.ZERO, locker_paint)
	_box(Vector3(1.10, 0.62, 0.03), Vector3(0.0, 0.34, -2.40), Vector3.ZERO, locker_paint)
	# The bitter end, shackled to a ringbolt in the forward bulkhead — the one
	# fitting on a boat whose whole job is to be the last thing that holds.
	_cyl(0.012, 0.012, 0.10, Vector3(0.0, 0.52, -3.66), Vector3(90.0, 0.0, 0.0), bronze)
	# Heap of stowed cable on the locker sole. It SHRINKS as you veer: what is
	# over the bow is not in the locker, and being able to see that is the whole
	# point of cutting the deck.
	_chain_heap = MeshInstance3D.new()
	var heap_m := SphereMesh.new()
	heap_m.radius = 0.30
	heap_m.height = 0.34
	heap_m.radial_segments = 12
	heap_m.rings = 5
	heap_m.material = _mat(Color(0.155, 0.150, 0.150), 0.72, 0.55)
	_chain_heap.mesh = heap_m
	_chain_heap.position = Vector3(0.0, 0.09, -3.05)
	add_child(_chain_heap)
	# The inboard run: gypsy -> pipe -> heap, six stubby links standing in for
	# the cable. Static geometry; what moves is how much of it is showing.
	for li in 6:
		var t := float(li) / 5.0
		var lk := MeshInstance3D.new()
		# (`link_m`, not `lm` — this function already owns that name further up.)
		var link_m := BoxMesh.new()
		link_m.size = Vector3(0.055, 0.10, 0.055)
		link_m.material = _mat(Color(0.175, 0.175, 0.180), 0.55, 0.80)
		lk.mesh = link_m
		lk.position = Vector3(0.0, lerpf(0.92, 0.16, t), lerpf(-3.30, -3.02, t))
		lk.rotation.y = float(li) * 0.9
		lk.rotation.x = lerpf(-0.55, 0.0, t)
		add_child(lk)
		_chain_run.append(lk)

	# --- windlass on the foredeck, over the chain locker ---------------------
	# The bed and the standards are fixed; the GYPSY turns. You could not see
	# the cable being paid out or hove in before because the one part of the
	# boat whose whole job is to do that was a static box.
	_box(Vector3(0.56, 0.26, 0.34), Vector3(0.0, 0.80, -3.35), Vector3.ZERO, metal)
	_box(Vector3(0.07, 0.30, 0.30), Vector3(-0.30, 0.95, -3.35), Vector3.ZERO, metal)
	_box(Vector3(0.07, 0.30, 0.30), Vector3(0.30, 0.95, -3.35), Vector3.ZERO, metal)
	_windlass = Node3D.new()
	_windlass.position = Vector3(0.0, 1.02, -3.35)
	add_child(_windlass)
	_cyl(0.13, 0.13, 0.46, Vector3.ZERO, Vector3(0.0, 0.0, 90.0), bronze, _windlass)
	_cyl(0.17, 0.17, 0.05, Vector3(0.24, 0.0, 0.0), Vector3(0.0, 0.0, 90.0), metal, _windlass)
	_cyl(0.17, 0.17, 0.05, Vector3(-0.24, 0.0, 0.0), Vector3(0.0, 0.0, 90.0), metal, _windlass)
	# Whelps — the ribs round a gypsy that the links sit between. They are also
	# what lets you SEE it turning; a smooth drum spinning looks like a drum
	# standing still.
	for w in 8:
		var wa := float(w) / 8.0 * TAU
		_box(Vector3(0.44, 0.035, 0.055),
				Vector3(0.0, cos(wa) * 0.145, sin(wa) * 0.145),
				Vector3(rad_to_deg(wa), 0.0, 0.0), metal, _windlass)
	# Handle on the end of the shaft, and the deck stopper abaft it.
	_cyl(0.018, 0.018, 0.20, Vector3(0.30, 0.0, 0.0), Vector3(0.0, 0.0, 90.0), bronze, _windlass)
	_cyl(0.016, 0.016, 0.16, Vector3(0.40, 0.10, 0.0), Vector3(90.0, 0.0, 0.0), bronze, _windlass)
	_box(Vector3(0.08, 0.07, 0.55), Vector3(0.0, 0.92, -3.85), Vector3.ZERO, metal)


func _dial_label(parent: Node3D, text: String, pos: Vector3, size: int,
		shade: Color) -> void:
	## Painted on the dial: lies in the face plane, reads upright to the helm.
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.00060
	l.modulate = shade
	l.shaded = false
	l.double_sided = false
	l.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	l.position = pos
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)


func _dial_body(parent: Node3D, x: float, r: float, bezel: Material,
		dial_face: Material) -> Node3D:
	## Bezel, face and glass ring, in the plate's plane. Dial "up" is local -Z.
	var g := Node3D.new()
	g.position = Vector3(x, 0.016, 0.0)
	parent.add_child(g)
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = 0.010
	cm.radial_segments = 22
	cm.material = dial_face
	disc.mesh = cm
	g.add_child(disc)
	var bez := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = r
	tm.outer_radius = r + 0.016
	tm.rings = 20
	tm.ring_segments = 6
	tm.material = bezel
	bez.mesh = tm
	bez.position = Vector3(0.0, 0.004, 0.0)
	g.add_child(bez)
	return g


func _dial_tick(parent: Node3D, deg: float, r: float, length: float,
		width: float) -> void:
	## Dial angle: 0 is straight up, positive clockwise as the helm sees it.
	var a := deg_to_rad(deg)
	var d := r - length * 0.5 - 0.010
	_box(Vector3(width, 0.005, length),
			Vector3(sin(a) * d, 0.008, -cos(a) * d),
			Vector3(0.0, -deg, 0.0), _dial_ink, parent)


func _make_dial(parent: Node3D, x: float, r: float, caption: String,
		nums: Array, bezel: Material, dial_face: Material) -> Node3D:
	var g := _dial_body(parent, x, r, bezel, dial_face)
	# Nine ticks over 240 degrees; every second one long.
	for i in 9:
		var deg := -120.0 + float(i) * 30.0
		var major := i % 2 == 0
		_dial_tick(g, deg, r, 0.030 if major else 0.017, 0.008 if major else 0.005)
	# Scale numbers at the two ends and the middle.
	var at := [-120.0, 0.0, 120.0]
	for i in mini(nums.size(), 3):
		var a := deg_to_rad(at[i])
		var d := r - 0.052
		_dial_label(g, str(nums[i]), Vector3(sin(a) * d, 0.010, -cos(a) * d + 0.012),
				34, Color(0.78, 0.74, 0.64))
	_dial_label(g, caption, Vector3(0.0, 0.010, r * 0.46), 30, Color(0.62, 0.50, 0.32))

	var needle := Node3D.new()
	g.add_child(needle)
	_box(Vector3(0.009, 0.005, r * 0.78), Vector3(0.0, 0.014, -r * 0.39),
			Vector3.ZERO, _dial_ink, needle)
	_box(Vector3(0.013, 0.005, r * 0.22), Vector3(0.0, 0.014, r * 0.11),
			Vector3.ZERO, _dial_ink, needle)
	var hub := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.014
	hm.bottom_radius = 0.014
	hm.height = 0.014
	hm.radial_segments = 10
	hm.material = bezel
	hub.mesh = hm
	hub.position = Vector3(0.0, 0.017, 0.0)
	g.add_child(hub)
	return needle


func _make_compass(parent: Node3D, x: float, r: float, bezel: Material,
		dial_face: Material) -> void:
	## A card compass, not a needle: the card stays with the earth and the ship
	## turns under it, so the heading is whatever sits under the lubber line.
	var g := _dial_body(parent, x, r, bezel, dial_face)
	_compass_card = Node3D.new()
	g.add_child(_compass_card)
	for i in 16:
		var deg := float(i) * 22.5
		var major := i % 4 == 0
		_dial_tick(_compass_card, deg, r, 0.028 if major else 0.014,
				0.007 if major else 0.004)
	var pts := ["K", "D", "G", "B"]
	for i in 4:
		var a := deg_to_rad(float(i) * 90.0)
		var d := r - 0.050
		_dial_label(_compass_card, pts[i],
				Vector3(sin(a) * d, 0.010, -cos(a) * d + 0.013), 40,
				Color(0.90, 0.42, 0.28) if i == 0 else Color(0.80, 0.76, 0.66))
	# North arrow on the card.
	var red := _mat(Color(0.55, 0.10, 0.07), 0.6)
	red.emission_enabled = true
	red.emission = Color(0.95, 0.20, 0.10)
	red.emission_energy_multiplier = 0.30
	_box(Vector3(0.011, 0.005, r * 0.62), Vector3(0.0, 0.013, -r * 0.31),
			Vector3.ZERO, red, _compass_card)
	# Lubber line: fixed to the ship, at the top of the bowl.
	_box(Vector3(0.008, 0.006, 0.038), Vector3(0.0, 0.016, -r + 0.020),
			Vector3.ZERO, _dial_ink, g)
	_dial_label(g, "PUSULA", Vector3(0.0, 0.010, r * 0.52), 30,
			Color(0.62, 0.50, 0.32))


func _update_gauges(delta: float) -> void:
	if _needles.size() < 3:
		return
	# Needles have mass and oil in them: they swing to a reading, they do not
	# snap to it.
	var k := 1.0 - exp(-5.0 * delta)

	var fwd := -global_basis.z
	var head := fmod(rad_to_deg(atan2(fwd.x, -fwd.z)) + 360.0, 360.0)
	if _compass_card != null:
		_compass_card.rotation.y = lerp_angle(_compass_card.rotation.y,
				deg_to_rad(head), k * 0.6)

	var v := linear_velocity
	_needles[0].rotation.y = lerp_angle(_needles[0].rotation.y,
			_dial_angle(Vector2(v.x, v.z).length() * 1.94384, 20.0), k)

	var dep := 0.0
	if ocean != null:
		# Under the keel, not from the surface: the number you need when you
		# are looking for water to anchor in.
		var bed: float = ocean.get_seafloor_height(global_position)
		var surf: float = ocean.get_height(global_position)
		dep = maxf(surf - bed - 0.75, 0.0)
	_needles[1].rotation.y = lerp_angle(_needles[1].rotation.y,
			_dial_angle(dep, 40.0), k)

	var ch := 0.0
	if tackle != null:
		ch = float(tackle.get("chain_out"))
	_needles[2].rotation.y = lerp_angle(_needles[2].rotation.y,
			_dial_angle(ch, 70.0), k)


func _dial_angle(value: float, full: float) -> float:
	## -120 deg at zero, +120 at full scale. A pivot's rotation.y is the
	## negative of the dial angle (dial "up" is local -Z).
	return -deg_to_rad(-120.0 + clampf(value / full, 0.0, 1.0) * 240.0)


func _build_switchboard(trim: Material, metal: Material) -> void:
	## A switch console, standing between the radar and the chart table where
	## your right hand falls. Six brass toggles: walk up and throw them. A boat
	## this old would not have a menu, and it does not have one here either.
	var bronze := _mat(Color(0.36, 0.27, 0.13), 0.40, 0.75)
	var face_mat := _mat(Color(0.115, 0.105, 0.095), 0.62)
	var cx := 1.30
	var cz := 1.54

	# The carcass: one run from the dashboard corner aft to the chart table, with
	# a single top. What used to be three separate lumps of furniture standing
	# near each other is now one piece — a wheelhouse is fitted out, not furnished.
	_box(Vector3(0.64, 0.72, 3.21), Vector3(cx, 3.27, 1.745), Vector3.ZERO, trim)
	_box(Vector3(0.68, 0.05, 3.25), Vector3(cx, 3.655, 1.745), Vector3.ZERO, trim)
	# Drawer fronts down its inboard face.
	for d in 5:
		_box(Vector3(0.02, 0.15, 0.56), Vector3(cx - 0.325, 3.44 - float(d % 2) * 0.20,
				0.45 + float(d) * 0.62), Vector3.ZERO, _mat(Color(0.09, 0.07, 0.05), 0.9))
		_box(Vector3(0.03, 0.025, 0.10), Vector3(cx - 0.34, 3.44 - float(d % 2) * 0.20,
				0.45 + float(d) * 0.62), Vector3.ZERO, bronze)
	# The switchboard is a slate panel let INTO that top, not a stand of its own.
	#
	# It sits on the INBOARD half of the console, and that is not a decision
	# about looks. The joinery runs out to x 1.62 and you cannot stand closer to
	# it than x 0.68 — so a board spread across the full top put its outboard
	# column a full metre from the shoulder, against an arm that is 0.55 m long
	# with 0.34 m of lean. The solver could only stretch at it, which is exactly
	# what "the hand is broken" looked like. Every toggle is now inside 0.62 m.
	var bx := 1.17
	_box(Vector3(0.42, 0.03, 0.58), Vector3(bx, 3.695, cz), Vector3.ZERO, face_mat)
	_box(Vector3(0.46, 0.045, 0.035), Vector3(bx, 3.70, cz - 0.305), Vector3.ZERO, bronze)
	_box(Vector3(0.46, 0.045, 0.035), Vector3(bx, 3.70, cz + 0.305), Vector3.ZERO, bronze)

	# The fuse-box hood over the board: a shallow steel lid, hinged on its
	# forward edge, with a lip deep enough to clear the thrown levers. Opening
	# it stands the lid up against the dashboard, clear of the hand.
	var hood_mat := _mat(Color(0.170, 0.180, 0.185), 0.55, 0.55)
	_fuse_lid = Node3D.new()
	_fuse_lid.position = Vector3(bx, 3.715, cz - 0.315)
	add_child(_fuse_lid)
	var hood_top := _box_node(Vector3(0.48, 0.022, 0.65), Vector3(0.0, 0.105, 0.325), hood_mat)
	_fuse_lid.add_child(hood_top)
	var hood_f := _box_node(Vector3(0.48, 0.105, 0.022), Vector3(0.0, 0.052, 0.011), hood_mat)
	_fuse_lid.add_child(hood_f)
	var hood_a := _box_node(Vector3(0.48, 0.105, 0.022), Vector3(0.0, 0.052, 0.639), hood_mat)
	_fuse_lid.add_child(hood_a)
	var hood_l := _box_node(Vector3(0.022, 0.105, 0.65), Vector3(-0.229, 0.052, 0.325), hood_mat)
	_fuse_lid.add_child(hood_l)
	var hood_r := _box_node(Vector3(0.022, 0.105, 0.65), Vector3(0.229, 0.052, 0.325), hood_mat)
	_fuse_lid.add_child(hood_r)
	var latch := _box_node(Vector3(0.06, 0.03, 0.035), Vector3(0.0, 0.095, 0.63),
			_mat(Color(0.36, 0.27, 0.13), 0.4, 0.7))
	_fuse_lid.add_child(latch)

	# Six toggles, two rows of three. The lever of each carries its own state.
	var ids: Array[String] = ["sw_cabin", "sw_helm", "sw_beacon",
			"sw_flood", "sw_wiper", "sw_anchor"]
	var names: Array[String] = ["CABIN", "HELM", "BEACON", "FLOOD", "WIPER", "ANCHOR"]
	for i in 6:
		var col := i % 3
		var row: int = i / 3
		var sx := bx - 0.12 + float(col) * 0.12
		var sz := cz - 0.12 + float(row) * 0.24
		var sy := 3.712
		# Escutcheon, and the toggle standing up out of it.
		_box(Vector3(0.075, 0.012, 0.075), Vector3(sx, sy - 0.012, sz), Vector3.ZERO, bronze)
		var piv := Node3D.new()
		piv.position = Vector3(sx, sy, sz)
		add_child(piv)
		_cyl(0.011, 0.008, 0.050, Vector3(0.0, 0.025, 0.0), Vector3.ZERO, bronze, piv)
		var tip := MeshInstance3D.new()
		var tm := SphereMesh.new()
		tm.radius = 0.012
		tm.height = 0.024
		tm.material = bronze
		tip.mesh = tm
		tip.position = Vector3(0.0, 0.052, 0.0)
		tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		piv.add_child(tip)
		_switch_levers[ids[i]] = piv
		# Tell-tale beside each: green burning, red dark. You can read the whole
		# board at a glance from the wheel without walking over to it.
		var led_mat := _mat(Color(0.09, 0.09, 0.09), 0.30)
		led_mat.emission_enabled = true
		led_mat.emission = Color(1.0, 0.16, 0.10)
		led_mat.emission_energy_multiplier = 1.1
		_box(Vector3(0.026, 0.008, 0.026), Vector3(sx, sy - 0.006, sz + 0.048),
				Vector3.ZERO, bronze)
		var led := MeshInstance3D.new()
		var lm := SphereMesh.new()
		lm.radius = 0.0085
		lm.height = 0.017
		lm.material = led_mat
		led.mesh = lm
		led.position = Vector3(sx, sy + 0.006, sz + 0.048)
		led.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(led)
		_switch_leds[ids[i]] = led_mat
		# Engraved plate for each circuit.
		_console_label(names[i], Vector3(sx, sy - 0.008, sz + 0.092), 34)


func _worn_letter(color: Color, wear: float, flake_seed: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/worn_letter.gdshader")
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("wear", wear)
	m.set_shader_parameter("seed", flake_seed)
	return m


func _build_nameboard() -> void:
	## Painted name on the transom, read from astern: M on the port side.
	## The old arc put the first letter on +X, so from behind it read YCREM.
	## What is left is chalky cream with the wood showing through — not gilt.
	var board := Node3D.new()
	board.position = Vector3(0.0, 0.18, 5.70)
	board.rotation_degrees = Vector3(-9.0, 0.0, 0.0)
	add_child(board)
	var serif := SystemFont.new()
	serif.font_names = PackedStringArray(["Georgia", "Times New Roman", "serif"])
	serif.font_italic = true
	serif.font_weight = 600
	var letters := "MERCY"
	var n: int = letters.length()
	# Ends and the R have shed more than the E — that is how a name weathers.
	var wear: Array[float] = [0.46, 0.28, 0.58, 0.34, 0.66]
	var r := 2.45
	var span := deg_to_rad(20.5)
	for i: int in n:
		var t := 0.0 if n == 1 else float(i) / float(n - 1)
		var ang: float = lerp(-span, span, t)
		var pos := Vector3(r * sin(ang), r * cos(ang) - r * cos(span) + 0.28, 0.118)
		var tilt := rad_to_deg(ang) * 0.9
		var flake := float(i) * 2.17 + 0.4
		var stain := _worn_letter(Color(0.16, 0.11, 0.07), wear[i] * 0.22, flake + 8.0)
		var paint := _worn_letter(Color(0.64, 0.56, 0.40), wear[i], flake)
		_transom_glyph(board, letters.substr(i, 1), pos + Vector3(0.006, -0.008, -0.003),
				tilt, stain, serif, 0.0046, 0.004)
		_transom_glyph(board, letters.substr(i, 1), pos, tilt, paint, serif, 0.0042, 0.005)


func _transom_glyph(parent: Node3D, ch: String, pos: Vector3, tilt_z: float,
		mat: Material, font: Font, pixel: float, depth: float) -> void:
	var mesh := TextMesh.new()
	mesh.text = ch
	mesh.font = font
	mesh.font_size = 64
	mesh.pixel_size = pixel
	mesh.depth = depth
	mesh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mesh.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = Vector3(0.0, 0.0, tilt_z)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


func _console_label(text: String, pos: Vector3, size: int) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.00042
	l.modulate = Color(0.72, 0.66, 0.50)
	l.shaded = false
	l.double_sided = false
	l.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	l.position = pos
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(l)


func toggle_switch(id: String, by_hand := true) -> void:
	## One switch, one circuit. Called from the E handler when you throw a
	## toggle by hand; the number keys reach the same fields.
	# Sealed board: a closed fuse box does not take a finger.
	if id.begins_with("sw_") and by_hand and not fusebox_open:
		return
	match id:
		"stove": stove_on = not stove_on
		"fusebox":
			fusebox_open = not fusebox_open
			_hinge_sound(Vector3(1.30, 3.72, 1.54))
		"sw_cabin": light_cabin = not light_cabin
		"sw_helm": light_helm = not light_helm
		"sw_beacon": light_beacon = not light_beacon
		"sw_flood": light_flood = not light_flood
		"sw_wiper": wiper_on = not wiper_on
		"sw_anchor":
			if tackle != null:
				tackle.toggle()
		"door_fwd":
			door_fwd_open = not door_fwd_open
			_hinge_sound(Vector3(0.0, 1.30, DOOR_Z0))
		"door_aft":
			door_aft_open = not door_aft_open
			_hinge_sound(Vector3(0.0, 1.30, DOOR_Z1))
		"door_wh":
			door_wh_open = not door_wh_open
			_hinge_sound(Vector3(0.0, 3.55, WH_DOOR_Z))
		"door_eng":
			door_eng_open = not door_eng_open
			_hinge_sound(Vector3(-0.515, 1.24, 2.15))
			if _engine_room != null:
				_engine_room.call("set_door", door_eng_open)
		"locker":
			locker_open = not locker_open
			_hinge_sound(Vector3(-1.30, 1.50, 0.36))
		"divegear":
			# Only ever from the locker, and only with the door open — you do
			# not pull a wetsuit through a steel panel.
			if locker_open or gear_worn:
				gear_worn = not gear_worn
		"ignition": _turn_ignition()


func switch_state(id: String) -> bool:
	match id:
		"sw_cabin": return light_cabin
		"sw_helm": return light_helm
		"sw_beacon": return light_beacon
		"sw_flood": return light_flood
		"sw_wiper": return wiper_on
		"sw_anchor": return tackle != null and int(tackle.state) != 0
		"door_fwd": return door_fwd_open
		"door_aft": return door_aft_open
		"door_wh": return door_wh_open
		"door_eng": return door_eng_open
		"fusebox": return fusebox_open
		"stove": return stove_on
		"ignition": return engine != EngineState.OFF
	return false


func _prism(w: float, depth: float, h: float, pos: Vector3, mat: Material) -> void:
	## A plan-view wedge: triangular cross-section in the deck plane, apex
	## pointing forward. This is the one primitive a pointed bow needs and the
	## one thing a BoxMesh cannot fake.
	var mi := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.left_to_right = 0.5
	pm.size = Vector3(w, depth, h)
	pm.material = mat
	mi.mesh = pm
	# PrismMesh points +Y; lying it on its back points the apex forward (-Z)
	# and turns the extrusion into height.
	mi.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	mi.position = pos
	add_child(mi)


func _box_node(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	## _box, but returned instead of parented — for pieces that hang on pivots.
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	return mi


func _build_chart_table(trim: Material, metal: Material) -> void:
	## A proper chart table against the starboard side, where the little folding
	## desk was. The paper on it is not a picture of the world, it is drawn FROM
	## the world: chart.gdshader reads the same seabed heightmap the seafloor
	## does, so every headland and every ten-metre line on the paper is the one
	## that is actually out there.
	# No carcass of its own any more: the chart lies on the aft end of the one
	# console run, inside a fiddle. It used to be a separate table standing
	# beside a separate switch stand beside the dashboard.
	var cx := 1.30
	var cz := 2.88
	var top := 3.68
	var bronze := _mat(Color(0.34, 0.25, 0.12), 0.42, 0.75)

	# Fiddle round the chart so it and the dividers stay aboard.
	_box(Vector3(0.60, 0.04, 0.03), Vector3(cx, top + 0.045, cz - 0.335), Vector3.ZERO, trim)
	_box(Vector3(0.60, 0.04, 0.03), Vector3(cx, top + 0.045, cz + 0.335), Vector3.ZERO, trim)
	_box(Vector3(0.03, 0.04, 0.70), Vector3(cx - 0.285, top + 0.045, cz), Vector3.ZERO, trim)
	_box(Vector3(0.03, 0.04, 0.70), Vector3(cx + 0.285, top + 0.045, cz), Vector3.ZERO, trim)

	# The chart. A plane, because its UV runs 0..1 across the sheet and that is
	# exactly the world's own wrap — the paper IS the terrain texture, read
	# through a shader that knows how to draw a chart.
	_chart_mat = ShaderMaterial.new()
	_chart_mat.shader = load("res://shaders/chart.gdshader")
	_chart_mat.set_shader_parameter("base_depth", -28.0)
	var sheet := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(0.50, 0.50)
	pm.material = _chart_mat
	sheet.mesh = pm
	sheet.position = Vector3(cx, top + 0.012, cz)
	sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sheet)

	# Brass pin standing on your fix. The pencil circle under it is drawn by the
	# shader; this is the thing your eye actually goes to.
	_chart_pin = Node3D.new()
	add_child(_chart_pin)
	_cyl(0.003, 0.008, 0.058, Vector3(0.0, 0.029, 0.0), Vector3.ZERO, bronze, _chart_pin)
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.011
	hm.height = 0.022
	hm.material = _mat(Color(0.55, 0.12, 0.08), 0.55)
	head.mesh = hm
	head.position = Vector3(0.0, 0.066, 0.0)
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_chart_pin.add_child(head)

	# Instruments, lying where they were put down: parallel rules, dividers, a
	# pencil, and the folio's next sheet still rolled.
	_box(Vector3(0.18, 0.010, 0.035), Vector3(cx - 0.14, top + 0.035, cz + 0.31),
			Vector3(0.0, 14.0, 0.0), _mat(Color(0.18, 0.14, 0.10), 0.6))
	_box(Vector3(0.18, 0.010, 0.035), Vector3(cx - 0.12, top + 0.035, cz + 0.35),
			Vector3(0.0, 14.0, 0.0), _mat(Color(0.18, 0.14, 0.10), 0.6))
	_cyl(0.004, 0.004, 0.13, Vector3(cx + 0.19, top + 0.075, cz + 0.31), Vector3(28.0, 30.0, 0.0), bronze)
	_cyl(0.004, 0.004, 0.13, Vector3(cx + 0.21, top + 0.075, cz + 0.31), Vector3(-28.0, 30.0, 0.0), bronze)
	_cyl(0.007, 0.007, 0.12, Vector3(cx + 0.06, top + 0.040, cz + 0.34), Vector3(0.0, 62.0, 90.0),
			_mat(Color(0.55, 0.42, 0.18), 0.8))
	_cyl(0.022, 0.022, 0.28, Vector3(cx - 0.02, top + 0.060, cz - 0.32), Vector3(0.0, 0.0, 90.0),
			_mat(Color(0.72, 0.66, 0.52), 0.9))

	# A hooded lamp on the helm circuit, angled down at the paper.
	_box(Vector3(0.025, 0.24, 0.025), Vector3(cx + 0.24, top + 0.17, cz - 0.34), Vector3.ZERO, metal)
	_cyl(0.065, 0.038, 0.085, Vector3(cx + 0.20, top + 0.28, cz - 0.28), Vector3(38.0, -28.0, 0.0), metal)
	_box(Vector3(0.038, 0.018, 0.038), Vector3(cx + 0.185, top + 0.25, cz - 0.26), Vector3.ZERO, _helm_glow)


func _build_electronics(trim: Material, metal: Material) -> void:
	## The two boxes aboard with wires going into them. Everything else on this
	## boat is brass and glass and does not care whether the batteries are up;
	## these two do, and they look it.
	var bronze := _mat(Color(0.34, 0.25, 0.12), 0.42, 0.75)
	var casing := _mat(Color(0.13, 0.135, 0.125), 0.72, 0.15)

	# --- echo sounder -------------------------------------------------------
	# High on the starboard side of the front bulkhead. It sat lower and further
	# inboard first, which put it squarely in the arc of the throttle lever —
	# the lever pivots at x 0.70 and swings 0.30 m of bronze right through where
	# the case used to be. Up here it is clear of the lever, clear of the wheel,
	# and still below the horizon at a standing eye.
	var sp := Vector3(1.15, 4.02, -0.06)
	_box(Vector3(0.05, 0.16, 0.04), sp + Vector3(-0.17, -0.10, 0.02), Vector3.ZERO, metal)
	_box(Vector3(0.05, 0.16, 0.04), sp + Vector3(0.17, -0.10, 0.02), Vector3.ZERO, metal)
	# Same hinge treatment as the radar above it: the bracket posts stay on the
	# bulkhead, the housing — case, face knobs and screen — hangs under a pivot
	# on the bolt line, so a hand on the case tips the whole instrument.
	var s_hinge := sp + Vector3(0.0, -0.10, 0.065)
	# Its own swing arm, one shelf down — same wrought iron, same bolted pads.
	var s_iron := _mat(Color(0.150, 0.115, 0.088), 0.90, 0.30)
	var s_pad := _mat(Color(0.205, 0.120, 0.070), 0.95, 0.15)
	_sounder_arm = Node3D.new()
	_sounder_arm.position = Vector3(0.62, 3.95, -0.03)
	add_child(_sounder_arm)
	_sounder_home = _sounder_arm.position
	var s_off := s_hinge - _sounder_arm.position
	_box(Vector3(0.034, 0.43, 0.034), Vector3(0.0, -0.075, 0.0), Vector3.ZERO, s_iron, _sounder_arm)
	_cyl(0.030, 0.030, 0.045, Vector3(0.0, 0.07, 0.0), Vector3.ZERO, bronze, _sounder_arm)
	var s_mnt := _sounder_arm.position
	for spy in [0.10, -0.16]:
		_box(Vector3(0.10, 0.075, 0.028), s_mnt + Vector3(0.0, spy, -0.040), Vector3.ZERO, s_pad)
		for sbx in [-0.034, 0.034]:
			for sby in [-0.022, 0.022]:
				_cyl(0.007, 0.007, 0.013, s_mnt + Vector3(sbx, spy + sby, -0.024),
						Vector3(90.0, 0.0, 0.0), s_iron)
	_box(Vector3(0.022, 0.022, 0.26), s_mnt + Vector3(0.0, -0.24, -0.095),
			Vector3(-50.0, 0.0, 0.0), s_iron)
	# Same rule one shelf down: into the case body, aimed at its centre.
	var s_goal := Vector3(0.53, 0.0, -0.03)
	var s_dir := s_goal.normalized()
	var s_bar := MeshInstance3D.new()
	var sbm := BoxMesh.new()
	sbm.size = Vector3(0.026, 0.036, 0.50)
	sbm.material = s_iron
	s_bar.mesh = sbm
	s_bar.position = s_dir * 0.25 + Vector3(0.0, 0.07, 0.0)
	s_bar.rotation.y = atan2(s_goal.x, s_goal.z)
	_sounder_arm.add_child(s_bar)
	_sounder_pivot = Node3D.new()
	_sounder_pivot.position = s_off
	_sounder_arm.add_child(_sounder_pivot)
	var s_case := MeshInstance3D.new()
	var s_bm := BoxMesh.new()
	s_bm.size = Vector3(0.34, 0.27, 0.17)
	s_bm.material = casing
	s_case.mesh = s_bm
	s_case.position = sp - s_hinge
	s_case.rotation_degrees = Vector3(-22.0, 0.0, 0.0)
	_sounder_pivot.add_child(s_case)
	_sounder_case = s_case
	# Two knobs, as every one of these ever had. There WAS a bezel plate here
	# and it was sitting a centimetre in front of the glass, which is why the
	# screen read as a dead black rectangle.
	_cyl(0.018, 0.018, 0.022, sp + Vector3(-0.115, -0.085, 0.095) - s_hinge,
			Vector3(68.0, 0.0, 0.0), bronze, _sounder_pivot)
	_cyl(0.018, 0.018, 0.022, sp + Vector3(0.115, -0.085, 0.095) - s_hinge,
			Vector3(68.0, 0.0, 0.0), bronze, _sounder_pivot)

	_sounder_mat = ShaderMaterial.new()
	_sounder_mat.shader = load("res://shaders/sounder.gdshader")
	_depth_hist.resize(64)
	for i in 64:
		_depth_hist[i] = 0.0
	var scr := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.255, 0.185)
	qm.material = _sounder_mat
	scr.mesh = qm
	scr.position = sp + Vector3(0.0, 0.034, 0.088) - s_hinge
	scr.rotation_degrees = Vector3(-22.0, 0.0, 0.0)
	scr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sounder_pivot.add_child(scr)
	_sounder_screen = scr
	# --- radar, in the bracket above it -------------------------------------
	# The HOUSING rides a RAIL. The bracket posts and the two bronze bolt heads
	# stay on the bulkhead; casing and screen live under a carrier node, and
	# pulling the case slides the whole unit down its rail toward the helmsman —
	# a straight glide, no tilt — then home again the same way. Nothing
	# detaches, nothing flies to the lens.
	var rp := Vector3(1.18, 4.38, -0.05)
	_box(Vector3(0.05, 0.14, 0.04), rp + Vector3(-0.18, -0.16, 0.02), Vector3.ZERO, metal)
	_box(Vector3(0.05, 0.14, 0.04), rp + Vector3(0.18, -0.16, 0.02), Vector3.ZERO, metal)
	_cyl(0.016, 0.016, 0.020, rp + Vector3(-0.145, -0.135, 0.100), Vector3(70.0, 0.0, 0.0), bronze)
	_cyl(0.016, 0.016, 0.020, rp + Vector3(0.145, -0.135, 0.100), Vector3(70.0, 0.0, 0.0), bronze)
	var hinge := rp + Vector3(0.0, -0.135, 0.100)
	# The swing arm: WROUGHT IRON, not shop-fitting chrome. A thin old post
	# BOLTED to the bulkhead frame with two visible pad-plates and a diagonal
	# stay — every moving thing aboard shows what carries it, and this one
	# carries a radar, so it shows twice. The iron is rust-brown, pitted-rough,
	# and no thicker than it must be.
	var iron_old := _mat(Color(0.150, 0.115, 0.088), 0.90, 0.30)
	var iron_pad := _mat(Color(0.205, 0.120, 0.070), 0.95, 0.15)
	_radar_arm = Node3D.new()
	_radar_arm.position = Vector3(0.66, 4.245, -0.04)
	add_child(_radar_arm)
	_radar_home = _radar_arm.position
	var arm_off := hinge - _radar_arm.position
	# Post: thin, and it STOPS at the arm. It used to run on up past the
	# carrier with the bar riding over the top, which put a length of iron in
	# the air above the set — the joint was on show instead of inside the thing
	# it holds. Console top to a hand above the bar, and no further.
	_box(Vector3(0.038, 0.73, 0.038), Vector3(0.0, -0.16, 0.0), Vector3.ZERO, iron_old, _radar_arm)
	_cyl(0.034, 0.034, 0.05, Vector3(0.0, 0.135, 0.0), Vector3.ZERO, bronze, _radar_arm)
	# Pad-plates clamping the post to the bulkhead frame, four bolt heads each.
	var mnt := _radar_arm.position
	for py in [0.16, -0.30]:
		_box(Vector3(0.11, 0.085, 0.030), mnt + Vector3(0.0, py, -0.045), Vector3.ZERO, iron_pad)
		for bx in [-0.038, 0.038]:
			for by2 in [-0.026, 0.026]:
				_cyl(0.0075, 0.0075, 0.014, mnt + Vector3(bx, py + by2, -0.028),
						Vector3(90.0, 0.0, 0.0), iron_old)
	# Diagonal stay down to the frame: an old bracket trusts a triangle.
	_box(Vector3(0.024, 0.024, 0.34), mnt + Vector3(0.0, -0.30, -0.115),
			Vector3(-52.0, 0.0, 0.0), iron_old)
	# NOTE: the pads and stay are added to the BOAT, not the arm — the mount
	# stays on the wall while the arm swings out of it.
	# The arm runs at the CASE'S OWN MID-HEIGHT and drives into its body, so the
	# last hand of iron is buried in the thing it carries. It is aimed at the
	# case CENTRE rather than at the pivot: the pivot sits 15 cm proud of the
	# casing's back face, so a bar ending there pokes out behind the set — and
	# the carrier yaws about that pivot as it comes round, which walks the case
	# further off it still. Aiming at the centre and running 0.50 m keeps the
	# tip inside the shell through the whole swing.
	var arm_goal := Vector3(0.52, 0.0, -0.06)
	var arm_dir := arm_goal.normalized()
	var arm_bar := MeshInstance3D.new()
	var abm := BoxMesh.new()
	abm.size = Vector3(0.028, 0.040, 0.50)
	abm.material = iron_old
	arm_bar.mesh = abm
	arm_bar.position = arm_dir * 0.25 + Vector3(0.0, 0.135, 0.0)
	arm_bar.rotation.y = atan2(arm_goal.x, arm_goal.z)
	_radar_arm.add_child(arm_bar)
	_radar_pivot = Node3D.new()
	_radar_pivot.position = arm_off
	_radar_arm.add_child(_radar_pivot)
	var rcase := MeshInstance3D.new()
	var rbm := BoxMesh.new()
	rbm.size = Vector3(0.38, 0.36, 0.20)
	rbm.material = casing
	rcase.mesh = rbm
	rcase.position = rp - hinge
	rcase.rotation_degrees = Vector3(-20.0, 0.0, 0.0)
	_radar_pivot.add_child(rcase)
	_radar_case = rcase
	_radar_mat = ShaderMaterial.new()
	_radar_mat.shader = load("res://shaders/radar.gdshader")
	var rscr := MeshInstance3D.new()
	var rq := QuadMesh.new()
	rq.size = Vector2(0.275, 0.275)
	rq.material = _radar_mat
	rscr.mesh = rq
	rscr.position = rp + Vector3(0.0, 0.038, 0.104) - hinge
	rscr.rotation_degrees = Vector3(-20.0, 0.0, 0.0)
	rscr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_radar_pivot.add_child(rscr)
	_radar_screen = rscr
	var ping_stream: AudioStream = load("res://assets/audio/radar_ping.mp3")
	if ping_stream != null:
		_radar_ping = AudioStreamPlayer3D.new()
		_radar_ping.stream = ping_stream
		_radar_ping.volume_db = -16.0
		_radar_ping.unit_size = 2.6
		_radar_ping.max_distance = 34.0
		_radar_ping.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		_radar_ping.position = rp - hinge
		_radar_pivot.add_child(_radar_ping)
	# Waveguide up through the deckhead toward the scanner on the roof.
	_cyl(0.010, 0.010, 0.42, rp + Vector3(0.10, 0.34, -0.02), Vector3(0.0, 0.0, -8.0), casing)

	# Transducer cable, disappearing through the deck the way they all do.
	_cyl(0.006, 0.006, 0.62, sp + Vector3(-0.10, -0.42, 0.02), Vector3(6.0, 0.0, 4.0), casing)

	# --- VHF set, on the starboard side forward of the chart table -----------
	_radio_set = Node3D.new()
	add_child(_radio_set)
	var vhf_black := _mat(Color(0.035, 0.035, 0.038), 0.78, 0.08)
	var dark_face := _mat(Color(0.025, 0.025, 0.028), 0.62)
	var lcd := _mat(Color(0.05, 0.11, 0.07), 0.45)
	lcd.emission_enabled = true
	lcd.emission = Color(0.35, 1.0, 0.55)
	lcd.emission_energy_multiplier = 0.9

	# Case, with a face raked back so you can read it from the wheel.
	_box(Vector3(0.11, 0.22, 0.32), Vector3(1.605, 4.00, 0.44), Vector3.ZERO, vhf_black)
	_box(Vector3(0.012, 0.19, 0.29), Vector3(1.544, 4.00, 0.44), Vector3(0.0, 0.0, 0.0), dark_face)
	# Speaker grille: six slots, because that is what the front of one is.
	for i in 6:
		_box(Vector3(0.004, 0.012, 0.12), Vector3(1.537, 4.06 - float(i) * 0.019, 0.375),
				Vector3.ZERO, _mat(Color(0.02, 0.02, 0.02), 0.9))
	# Channel window. It sits on 16 — the distress and calling channel, which is
	# where a set left alone always ends up.
	_box(Vector3(0.006, 0.055, 0.085), Vector3(1.539, 3.965, 0.525), Vector3.ZERO,
			_mat(Color(0.03, 0.05, 0.035), 0.4))
	# "1": the two right-hand segments. "6": all but the top right.
	var sx := 1.5365
	_box(Vector3(0.004, 0.020, 0.005), Vector3(sx, 3.978, 0.556), Vector3.ZERO, lcd)
	_box(Vector3(0.004, 0.020, 0.005), Vector3(sx, 3.954, 0.556), Vector3.ZERO, lcd)
	for seg in [
		Vector3(0.0, 0.023, -0.014), Vector3(0.0, 0.000, -0.014), Vector3(0.0, -0.023, -0.014),
	]:
		_box(Vector3(0.004, 0.005, 0.024), Vector3(sx, 3.966 + seg.y, 0.525 + seg.z), Vector3.ZERO, lcd)
	_box(Vector3(0.004, 0.020, 0.005), Vector3(sx, 3.978, 0.5125), Vector3.ZERO, lcd)
	_box(Vector3(0.004, 0.020, 0.005), Vector3(sx, 3.954, 0.5125), Vector3.ZERO, lcd)
	_box(Vector3(0.004, 0.020, 0.005), Vector3(sx, 3.954, 0.5375), Vector3.ZERO, lcd)
	# Volume and squelch, and the channel rocker between them.
	_cyl(0.016, 0.014, 0.020, Vector3(1.537, 3.905, 0.545), Vector3(0.0, 0.0, 90.0), bronze)
	_cyl(0.016, 0.014, 0.020, Vector3(1.537, 3.905, 0.500), Vector3(0.0, 0.0, 90.0), bronze)
	_box(Vector3(0.008, 0.014, 0.040), Vector3(1.540, 3.905, 0.400), Vector3.ZERO, dark_face)
	# Aerial lead out of the top, and the power tail out of the bottom.
	_cyl(0.007, 0.007, 0.13, Vector3(1.605, 4.16, 0.40), Vector3(18.0, 0.0, 6.0), vhf_black)
	_cyl(0.006, 0.006, 0.22, Vector3(1.600, 3.80, 0.36), Vector3(-10.0, 0.0, 8.0), vhf_black)
	# Strain relief where the handset cord enters the case — the cord used to
	# start in mid-air a few centimetres off the box.
	_cyl(0.013, 0.008, 0.030, RADIO_ANCHOR + Vector3(0.012, 0.0, 0.0),
			Vector3(0.0, 0.0, 90.0), vhf_black)
	# Cradle hook the handset hangs on.
	_box(Vector3(0.05, 0.018, 0.10), RADIO_CRADLE + Vector3(0.028, -0.055, 0.0), Vector3.ZERO, metal)
	_box(Vector3(0.02, 0.055, 0.02), RADIO_CRADLE + Vector3(0.045, -0.012, -0.045), Vector3.ZERO, metal)

	# The handset. Its own node, because it leaves the cradle. Shaped the way one
	# is: a slim grip with a fat cap at each end, the earpiece a little deeper
	# than the mouthpiece, and the transmit bar under your thumb.
	_radio_hand = Node3D.new()
	add_child(_radio_hand)
	_box(Vector3(0.038, 0.046, 0.150), Vector3(0.0, 0.0, 0.0), Vector3.ZERO, vhf_black, _radio_hand)
	_box(Vector3(0.054, 0.054, 0.052), Vector3(0.0, 0.004, -0.088), Vector3.ZERO, vhf_black, _radio_hand)
	_box(Vector3(0.050, 0.046, 0.044), Vector3(0.0, 0.002, 0.086), Vector3.ZERO, vhf_black, _radio_hand)
	# Earpiece and mouthpiece grilles.
	_cyl(0.019, 0.019, 0.004, Vector3(0.0, 0.029, -0.088), Vector3.ZERO,
			_mat(Color(0.02, 0.02, 0.02), 0.9), _radio_hand)
	_cyl(0.013, 0.013, 0.004, Vector3(0.0, 0.025, 0.086), Vector3.ZERO,
			_mat(Color(0.02, 0.02, 0.02), 0.9), _radio_hand)
	# Press-to-talk, on the side where your thumb lands, and a transmit lamp.
	_box(Vector3(0.008, 0.024, 0.062), Vector3(-0.023, 0.002, 0.006), Vector3.ZERO,
			_mat(Color(0.26, 0.09, 0.06), 0.7), _radio_hand)
	_box(Vector3(0.010, 0.008, 0.010), Vector3(0.0, 0.024, -0.052), Vector3.ZERO,
			_mat(Color(0.22, 0.05, 0.04), 0.6), _radio_hand)
	_radio_hand.position = RADIO_CRADLE
	_radio_hand.rotation_degrees = Vector3(0.0, 0.0, 12.0)
	var talk: AudioStream = load("res://assets/audio/telsiz_konusma.mp3")
	if talk != null:
		_radio_snd = AudioStreamPlayer3D.new()
		_radio_snd.stream = talk
		_radio_snd.volume_db = -5.0
		_radio_snd.unit_size = 1.1
		_radio_snd.max_distance = 26.0
		_radio_snd.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		_radio_hand.add_child(_radio_snd)

	# Coiled cord. Thirty-odd little cylinders that get laid along a helix every
	# frame — the helix tightens as you come back to the set and pulls out as
	# you walk away, which is the whole reason to have it.
	var cord_mat := _mat(Color(0.055, 0.055, 0.055), 0.85)
	# Eighty segments, and the turn count kept low, because a coil is sampled
	# geometry: wind it faster than the segments can follow and consecutive
	# points land on opposite sides of the helix, which draws a starburst of
	# chords rather than a cord.
	for i in 48:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.006
		cm.bottom_radius = 0.006
		cm.height = 1.0
		cm.radial_segments = 5
		cm.rings = 1
		cm.material = cord_mat
		mi.mesh = cm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_cord.append(mi)


func cord_point(t: float, a: Vector3, b: Vector3) -> Vector3:
	## A point along the coiled cord. Straight run from a to b, with a helix
	## wound round it whose radius collapses as the cord comes taut, plus a
	## little sag while there is slack left to sag with.
	var d := b - a
	var l := d.length()
	var slack: float = clampf(1.0 - l / RADIO_CORD, 0.0, 1.0)
	var ax := d / maxf(l, 1e-4)
	var r1 := Vector3.UP.cross(ax)
	if r1.length_squared() < 1e-5:
		r1 = Vector3.RIGHT.cross(ax)
	r1 = r1.normalized()
	var r2 := ax.cross(r1)
	var rad: float = 0.007 + 0.026 * slack
	var turns: float = 1.8 + 4.0 * slack
	var ang: float = t * TAU * turns
	# Ends taper into the fittings instead of the coil starting mid-air.
	var taper: float = smoothstep(0.0, 0.12, t) * smoothstep(1.0, 0.88, t)
	var p := a + d * t + (r1 * cos(ang) + r2 * sin(ang)) * rad * taper
	p.y -= slack * 0.16 * sin(PI * t)
	return p


func _update_radio(delta: float) -> void:
	if _radio_hand == null:
		return
	# Only while you are actually aboard in first person. It used to run in every
	# mode, and on the frame the handset was taken the camera had not been placed
	# yet — so the cord read as five hundred metres long and snatched it straight
	# back out of your hand.
	var in_fps: bool = camera_rig != null and int(camera_rig.get("mode")) == 1
	if radio_held and in_fps and not radio_pose_locked:
		# Held up by your face. Worked out in the boat's frame so it rides with
		# her: a handset in your hand does not swing about when she rolls.
		var cam: Camera3D = camera_rig.get("_cam")
		if cam != null and cam.global_position.is_finite():
			# Where a handset actually goes: up by your right cheek, close in.
			# It used to be sent to (0.21, -0.11, -0.31) — a third of a metre
			# out in front and half way to the edge of the frame — so the arm
			# had to reach almost straight to get there and what you saw was a
			# forearm lying across the picture with a box on the end of it.
			var want: Vector3 = global_transform.affine_inverse() \
					* (cam.global_position + cam.global_basis * Vector3(0.205, -0.125, -0.275))
			# Cord's length is the cord's length. Come up against the end of it
			# and it holds; keep going and it is pulled out of your hand, which
			# is exactly what happens with a fixed VHF handset.
			var reach := want - RADIO_ANCHOR
			if reach.length() > RADIO_CORD:
				_radio_pull += delta
				want = RADIO_ANCHOR + reach.normalized() * RADIO_CORD
				if _radio_pull > 0.45:
					radio_held = false
			else:
				_radio_pull = 0.0
			_radio_hand.position = _radio_hand.position.lerp(want, 1.0 - exp(-22.0 * delta))
			# And the ANGLE it is held at, which is the rest of the problem. The
			# handset's long axis is Z, earpiece at -Z and mouthpiece at +Z; a
			# handset at your face runs from your ear DOWN to your mouth, not
			# horizontally away from you like a torch. So +Z is aimed down and a
			# little forward, +X out to the right away from your head — which
			# puts the PTT bar under your thumb and the palm against your cheek
			# where the grip expects them.
			var cb: Basis = cam.global_basis
			var zw: Vector3 = (cb * Vector3(0.11, -0.90, -0.42)).normalized()
			# +X is the face your PALM is on, so it has to point AWAY from the eye as
			# well as outboard — aimed back toward the viewer it puts the hand
			# between you and the set, and you watch a radio being held by a mitten.
			var xw: Vector3 = (cb * Vector3(0.94, 0.19, -0.28)).normalized()
			var yw: Vector3 = zw.cross(xw).normalized()
			xw = yw.cross(zw).normalized()
			var want_b: Basis = global_basis.inverse() * Basis(xw, yw, zw)
			_radio_hand.basis = _radio_hand.basis.slerp(want_b.orthonormalized(),
					1.0 - exp(-16.0 * delta))
	if radio_held and in_fps and radio_pose_locked:
		# The viewmodel owns the pose; still yank the set out of the hand if
		# the cord comes taut.
		var cam2: Camera3D = camera_rig.get("_cam")
		if cam2 != null:
			var here: Vector3 = global_transform.affine_inverse() * _radio_hand.global_position
			if (here - RADIO_ANCHOR).length() > RADIO_CORD + 0.04:
				_radio_pull += delta
				if _radio_pull > 0.45:
					radio_held = false
			else:
				_radio_pull = 0.0
	if not radio_held:
		_radio_pull = 0.0
		if not radio_pose_locked:
			_radio_hand.position = _radio_hand.position.lerp(RADIO_CRADLE, 1.0 - exp(-9.0 * delta))
			_radio_hand.rotation.x = lerpf(_radio_hand.rotation.x, 0.0, 1.0 - exp(-9.0 * delta))
			_radio_hand.rotation.y = lerpf(_radio_hand.rotation.y, 0.0, 1.0 - exp(-9.0 * delta))
			_radio_hand.rotation.z = lerpf(_radio_hand.rotation.z, 0.209, 1.0 - exp(-9.0 * delta))

	var a := RADIO_ANCHOR
	# Onto the handset's own tail, in the handset's frame — a fixed world offset
	# left the cord entering the side of it once you turned to face the window.
	var b: Vector3 = _radio_hand.position + _radio_hand.basis * Vector3(0.0, -0.012, 0.108)
	var n := _cord.size()
	for i in n:
		var t0 := float(i) / float(n)
		var t1 := float(i + 1) / float(n)
		var p0 := cord_point(t0, a, b)
		var p1 := cord_point(t1, a, b)
		var seg := p1 - p0
		var ln := seg.length()
		var mi := _cord[i]
		mi.position = (p0 + p1) * 0.5
		if ln > 1e-5:
			var up := seg / ln
			var ref := Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
			var bx := ref.cross(up).normalized()
			# Lengthen the Y COLUMN directly. Basis.scaled() applies its scale in
			# the parent frame, so on a segment pointing anywhere but straight up
			# it skews the cylinder instead of stretching it — eighty of those is
			# the starburst this drew the first time.
			mi.basis = Basis(bx, up * ln, bx.cross(up))


func _build_radar_scanner() -> void:
	## Open-array scanner on the wheelhouse roof, inboard of the VHF. The PPI
	## already paints; this is the aerial that was missing. The drum turns at
	## the same 7.5 rpm as the sweep on the screen.
	var ss := _mat(Color(0.48, 0.49, 0.47), 0.32, 0.72)
	var white := _mat(Color(0.86, 0.86, 0.84), 0.48, 0.05)
	var window := _mat(Color(0.08, 0.09, 0.10), 0.38, 0.15)
	var pos := Vector3(1.22, 5.52, 3.72)
	_box(Vector3(0.22, 0.025, 0.22), pos + Vector3(0.0, 0.012, 0.0), Vector3.ZERO, ss)
	_cyl(0.045, 0.040, 0.16, pos + Vector3(0.0, 0.10, 0.0), Vector3.ZERO, ss)
	_radar_scan = Node3D.new()
	_radar_scan.position = pos + Vector3(0.0, 0.20, 0.0)
	_radar_scan.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_radar_scan)
	_cyl(0.055, 0.055, 0.05, Vector3(0.0, 0.02, 0.0), Vector3.ZERO, ss, _radar_scan)
	# The box: a short open array, dark RF window so the spin reads at a glance.
	_box(Vector3(0.62, 0.10, 0.14), Vector3(0.0, 0.09, 0.0), Vector3.ZERO, white, _radar_scan)
	_box(Vector3(0.58, 0.06, 0.02), Vector3(0.0, 0.09, 0.072), Vector3.ZERO, window, _radar_scan)
	_box(Vector3(0.04, 0.10, 0.14), Vector3(-0.31, 0.09, 0.0), Vector3.ZERO, ss, _radar_scan)
	var tip := _mat(Color(0.72, 0.12, 0.08), 0.45, 0.1)
	_box(Vector3(0.04, 0.10, 0.14), Vector3(0.31, 0.09, 0.0), Vector3.ZERO, tip, _radar_scan)
	_cyl(0.028, 0.022, 0.06, Vector3(0.0, 0.155, 0.0), Vector3.ZERO, ss, _radar_scan)


func _build_helm(trim: Material, metal: Material) -> void:
	## No pedestal. It read as a lectern planted in the middle of the room, and
	## it hid the dials. The wheel stands on a slim brass column out of the
	## console, the way a small boat's does, and you read the gauges under it.
	var bronze := _mat(Color(0.34, 0.26, 0.13), 0.40, 0.72)
	var pivot := Node3D.new()
	pivot.position = Vector3(0.0, 3.45, 0.30)
	add_child(pivot)
	_cyl(0.044, 0.038, 0.36, Vector3(0.0, 0.18, 0.0), Vector3.ZERO, bronze, pivot)

	_wheel = Node3D.new()
	_wheel.position = Vector3(0.0, 0.38, 0.0)
	_wheel.rotation_degrees.x = -18.0
	pivot.add_child(_wheel)

	var rim := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.26
	t.outer_radius = 0.32
	t.rings = 20
	t.ring_segments = 6
	t.material = trim
	rim.mesh = t
	rim.rotation_degrees.x = 90.0
	_wheel.add_child(rim)
	for i in 6:
		var a := float(i) / 6.0 * TAU
		var sp := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.022
		cm.bottom_radius = 0.022
		cm.height = 0.56
		cm.radial_segments = 6
		cm.rings = 1
		cm.material = trim
		sp.mesh = cm
		sp.rotation_degrees = Vector3(0.0, 0.0, rad_to_deg(a))
		_wheel.add_child(sp)
	var hub := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.06
	hm.bottom_radius = 0.06
	hm.height = 0.10
	hm.radial_segments = 10
	hm.material = metal
	hub.mesh = hm
	hub.rotation_degrees.x = 90.0
	_wheel.add_child(hub)


func _cyl(r_bot: float, r_top: float, h: float, pos: Vector3, rot_deg: Vector3,
		mat: Material, parent: Node3D = null) -> void:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.bottom_radius = r_bot
	m.top_radius = r_top
	m.height = h
	m.radial_segments = 10
	m.rings = 1
	m.material = mat
	mi.mesh = m
	mi.position = pos
	mi.rotation_degrees = rot_deg
	if parent == null:
		add_child(mi)
	else:
		parent.add_child(mi)


func _box(size: Vector3, pos: Vector3, rot_deg: Vector3, mat: Material, parent: Node3D = null) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	mi.rotation_degrees = rot_deg
	if parent == null:
		add_child(mi)
	else:
		parent.add_child(mi)


func _build_motor() -> void:
	## A 9 m boat has a shaft and a rudder, not an outboard. The rudder swings
	## with the helm and the wheel in the wheelhouse turns with it.
	_motor_pivot = Node3D.new()
	_motor_pivot.position = Vector3(0.0, -0.55, 4.05)
	add_child(_motor_pivot)

	var metal := _mat(Color(0.09, 0.09, 0.10), 0.55, 0.6)
	var bronze := _mat(Color(0.30, 0.22, 0.11), 0.45, 0.75)

	_box(Vector3(0.10, 0.95, 0.85), Vector3(0.0, -0.18, 0.10), Vector3.ZERO, metal, _motor_pivot)
	_box(Vector3(0.09, 0.22, 0.30), Vector3(0.0, 0.36, 0.02), Vector3.ZERO, metal, _motor_pivot)

	# Shaft and screw, just ahead of the rudder. The hub spins with shaft rpm.
	var shaft := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.055
	sm.bottom_radius = 0.055
	sm.height = 1.30
	sm.radial_segments = 8
	sm.material = metal
	shaft.mesh = sm
	shaft.position = Vector3(0.0, -0.62, 3.35)
	shaft.rotation_degrees = Vector3(84.0, 0.0, 0.0)
	add_child(shaft)
	_screw = Node3D.new()
	_screw.position = Vector3(0.0, -0.68, 3.92)
	_screw.rotation_degrees = Vector3(84.0, 0.0, 0.0)
	add_child(_screw)
	_cyl(0.055, 0.072, 0.11, Vector3.ZERO, Vector3.ZERO, bronze, _screw)
	_cyl(0.028, 0.022, 0.08, Vector3(0.0, 0.08, 0.0), Vector3.ZERO, metal, _screw)
	for i in 3:
		var arm := Node3D.new()
		arm.rotation_degrees = Vector3(0.0, 0.0, float(i) * 120.0)
		_screw.add_child(arm)
		var blade := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.048, 0.46, 0.155)
		bm.material = bronze
		blade.mesh = bm
		blade.position = Vector3(0.0, 0.28, 0.02)
		blade.rotation_degrees = Vector3(0.0, 24.0, 0.0)
		arm.add_child(blade)


func _turn_ignition() -> void:
	## The key is the whole start. Off → crank (and wait) → running. Turn it
	## again and she dies, shaft and all. Cranking again aborts the start.
	_play_ign_click()
	if engine == EngineState.OFF:
		engine = EngineState.CRANKING
		_crank_left = 2.15
		if _starter_snd != null:
			_starter_snd.play()
		if _engine_snd != null:
			_engine_snd.stop()
	else:
		engine = EngineState.OFF
		_crank_left = 0.0
		if _starter_snd != null:
			_starter_snd.stop()
		# Engine loop fades in _update_engine_audio.


func _play_ign_click() -> void:
	if _ign_click != null:
		_ign_click.play()


func _build_door_sound() -> void:
	var st: AudioStream = load("res://assets/audio/door.mp3")
	if st == null:
		return
	for i in 4:
		var p := AudioStreamPlayer3D.new()
		p.stream = st
		p.volume_db = -7.0
		p.unit_size = 1.6
		p.max_distance = 22.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		_door_snd.append(p)


func _hinge_sound(where: Vector3) -> void:
	## Round-robin so a second door does not cut the first one off.
	if _door_snd.is_empty():
		return
	var p: AudioStreamPlayer3D = _door_snd[_door_voice]
	_door_voice = (_door_voice + 1) % _door_snd.size()
	p.position = where
	p.pitch_scale = randf_range(0.94, 1.07)
	p.play()


func _build_engine_sound() -> void:
	## Diesel under the aft sole. Own bus with a low-pass so timber muffles
	## it in the rooms; on deck it is the exhaust, not a speaker in your ear.
	_ensure_engine_bus()
	_starter_snd = AudioStreamPlayer3D.new()
	_starter_snd.position = Vector3(0.0, 0.42, 3.70)
	_starter_snd.stream = _wav_starter()
	_starter_snd.bus = "Engine"
	_starter_snd.unit_size = 2.4
	_starter_snd.max_distance = 14.0
	_starter_snd.max_db = 0.0
	_starter_snd.volume_db = -8.0
	_starter_snd.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(_starter_snd)
	_engine_snd = AudioStreamPlayer3D.new()
	# The voice of the boat IS the recording now, and it sits exactly where the
	# iron sits: in the well under the companionway. Stand over the open door
	# and it fills the cabin; up in the wheelhouse it is a floor away; out on
	# deck it is weather and exhaust. The synthesized idle stays as a fallback
	# for a build without the asset.
	_engine_snd.position = Vector3(-1.05, 1.10, 2.16)
	var motor_rec: AudioStreamMP3 = load("res://assets/audio/motor.mp3")
	if motor_rec != null:
		motor_rec.loop = true
		_engine_snd.stream = motor_rec
	else:
		_engine_snd.stream = _wav_idle()
	_engine_snd.bus = "Engine"
	_engine_snd.unit_size = 2.8
	_engine_snd.max_distance = 26.0
	_engine_snd.max_db = 0.0
	_engine_snd.pitch_scale = 0.78
	_engine_snd.volume_db = -16.0
	_engine_snd.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(_engine_snd)
	_ign_click = AudioStreamPlayer3D.new()
	_ign_click.position = Vector3(0.50, 3.54, 0.06)
	_ign_click.stream = _wav_click()
	_ign_click.bus = "Master"
	_ign_click.unit_size = 1.2
	_ign_click.max_distance = 6.0
	_ign_click.max_db = 0.0
	_ign_click.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(_ign_click)


func _ensure_engine_bus() -> void:
	var idx := AudioServer.get_bus_index("Engine")
	if idx < 0:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, "Engine")
		AudioServer.set_bus_send(idx, "Master")
	if AudioServer.get_bus_effect_count(idx) == 0:
		_eng_lp = AudioEffectLowPassFilter.new()
		_eng_lp.cutoff_hz = 900.0
		_eng_lp.resonance = 0.28
		AudioServer.add_bus_effect(idx, _eng_lp)
	else:
		_eng_lp = AudioServer.get_bus_effect(idx, 0) as AudioEffectLowPassFilter


func _wav_click() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.06)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / float(n)
		var raw := (randf() * 2.0 - 1.0) * (1.0 - t) * (1.0 - t) * 0.45
		lp = lp * 0.7 + raw * 0.3
		s[i] = lp
	return _pcm(s, rate, false)


func _wav_starter() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 2.4)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / float(rate)
		var spin := 8.5 + t * 1.6
		var pulse := pow(0.5 + 0.5 * sin(t * TAU * spin), 3.2)
		var grind := (randf() * 2.0 - 1.0) * 0.35 + sin(t * TAU * 42.0) * 0.12
		lp = lp * 0.82 + grind * pulse * 0.18
		s[i] = clampf(lp, -0.7, 0.7)
	return _pcm(s, rate, false)


func _wav_idle() -> AudioStreamWAV:
	## A wooden boat's diesel: low thump, no hiss. The loop is long so the
	## chug does not read as a sample. Highs are cooked out here; the bus
	## low-pass only decides how much timber is in the way.
	var rate := 22050
	var n := int(rate * 2.6)
	var s := PackedFloat32Array()
	s.resize(n)
	var brown := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / float(rate)
		brown = brown * 0.96 + (randf() * 2.0 - 1.0) * 0.04
		var fire := 0.5 + 0.5 * sin(t * TAU * 23.5)
		fire *= fire * 0.38
		var sub := sin(t * TAU * 11.75) * 0.28
		var mid := sin(t * TAU * 47.0) * 0.08
		var raw := sub + fire + mid + brown * 0.40
		lp = lp * 0.90 + raw * 0.10
		s[i] = clampf(lp * 0.92, -0.85, 0.85)
	return _pcm(s, rate, true)


func _pcm(samples: PackedFloat32Array, rate: int, loop: bool) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	var n := samples.size()
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = n
	return w


func _drop_mesh(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.1
	m.radial_segments = 8
	m.rings = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.72, 0.82, 0.86, 0.45)
	mat.vertex_color_use_as_albedo = true
	mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	mat.distance_fade_min_distance = 16.0
	mat.distance_fade_max_distance = 2.2
	m.material = mat
	return m


func _spray_fade() -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	g.colors = PackedColorArray([
		Color(0.82, 0.9, 0.92, 0.7),
		Color(0.7, 0.8, 0.82, 0.28),
		Color(0.55, 0.62, 0.64, 0.0)])
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


func _build_water_fx() -> void:
	# Propeller churn: droplets thrown aft that fall back onto the sea.
	_prop = GPUParticles3D.new()
	_prop.amount = 90
	_prop.lifetime = 0.7
	_prop.fixed_fps = 30
	_prop.local_coords = false
	_prop.transform_align = GPUParticles3D.TRANSFORM_ALIGN_DISABLED
	_prop.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_prop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_prop.position = Vector3(0.0, -0.62, 4.15)
	_prop.visibility_aabb = AABB(Vector3(-8, -3, -8), Vector3(16, 8, 16))
	_prop_pm = ParticleProcessMaterial.new()
	_prop_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_prop_pm.emission_sphere_radius = 0.30
	_prop_pm.direction = Vector3(0.0, 0.35, 1.0)
	_prop_pm.spread = 28.0
	_prop_pm.initial_velocity_min = 2.4
	_prop_pm.initial_velocity_max = 5.4
	_prop_pm.gravity = Vector3(0.0, -14.0, 0.0)
	_prop_pm.scale_min = 0.45
	_prop_pm.scale_max = 1.1
	_prop_pm.color = Color(0.8, 0.88, 0.9, 0.55)
	_prop_pm.color_ramp = _spray_fade()
	_prop.process_material = _prop_pm
	_prop.draw_pass_1 = _drop_mesh(0.022)
	_prop.emitting = false
	add_child(_prop)


func _process(delta: float) -> void:
	_t += delta
	_update_lantern(delta)
	_update_stove(delta)
	_update_gauges(delta)
	_update_wetness(delta)

	var thr := 0.0
	var turn := 0.0
	var freecam: bool = camera_rig != null and camera_rig.get("free_mode")
	if not freecam and (helm_engaged or telegraph_engaged):
		thr = Input.get_axis("boat_backward", "boat_forward")
	if _at_controls():
		turn = Input.get_axis("boat_right", "boat_left")
	# W/S walk the telegraph lever rather than acting as a gas pedal.
	if absf(thr) > 0.05:
		throttle = clampf(throttle + thr * delta * 0.62, -0.4, 1.0)
	elif absf(throttle) < 0.03:
		throttle = 0.0  # detent at stop — no ghost creep from a nudged lever

	# --- the engine ----------------------------------------------------------
	# The lever is a REQUEST, not a throttle pedal. A dead engine answers
	# nothing: turn the key, wait for her to catch, then the shaft follows.
	# Kill it and the bar on the right dies with the shaft.
	if engine == EngineState.CRANKING:
		_crank_left -= delta
		if _crank_left <= 0.0:
			engine = EngineState.RUNNING
			if _starter_snd != null:
				_starter_snd.stop()
			if _engine_snd != null and not _engine_snd.playing:
				_engine_snd.play()
	var want := throttle if engine == EngineState.RUNNING else 0.0
	var tau := 1.9                                   # spooling up
	if engine != EngineState.RUNNING:
		tau = 0.85                                   # shaft dies with the motor
	elif absf(want) < absf(_rpm):
		tau = 1.5                                    # coming off the power
	if want * _rpm < -0.001:
		tau = 3.6                                    # reversing through stop
	_rpm = lerpf(_rpm, want, 1.0 - exp(-delta / tau))
	if absf(_rpm) < 0.004 and want == 0.0:
		_rpm = 0.0

	# The wheel is heavy, the rudder is under water and the linkage is cable and
	# quadrant: hard over is a couple of seconds of winding, not a flick.
	_helm = lerpf(_helm, turn, 1.0 - exp(-delta / 1.45))
	if _thr_lever != null:
		_thr_lever.rotation_degrees.x = lerpf(38.0, -44.0,
				(throttle + 0.4) / 1.4)
	if _ign_key != null:
		var kang := 0.0
		if engine == EngineState.CRANKING:
			kang = -2.45
		elif engine == EngineState.RUNNING:
			kang = -1.75
		_ign_key.rotation.y = lerpf(_ign_key.rotation.y, kang, 1.0 - exp(-11.0 * delta))
	if _ign_led != null:
		if engine == EngineState.RUNNING:
			_ign_led.emission = Color(0.22, 1.0, 0.34)
			_ign_led.emission_energy_multiplier = 2.4
		elif engine == EngineState.CRANKING:
			_ign_led.emission = Color(1.0, 0.72, 0.16)
			_ign_led.emission_energy_multiplier = 2.0
		else:
			_ign_led.emission = Color(1.0, 0.16, 0.10)
			_ign_led.emission_energy_multiplier = 1.0
	if _engine_snd != null:
		var cam := get_viewport().get_camera_3d()
		var open_t := 1.0
		if cam != null:
			open_t = weather_openness(cam.global_position)
		# The engine door is a hole in the muffle: open it and the well speaks
		# straight into the cabin, half-outdoors loud even three steps away.
		if door_eng_open:
			open_t = maxf(open_t, 0.55)
		_eng_open = lerpf(_eng_open, open_t, 1.0 - exp(-6.5 * delta))
		if _eng_lp != null:
			# Rooms: a dull thump through the sole. Deck: the exhaust, still
			# round — never a hiss.
			_eng_lp.cutoff_hz = lerpf(720.0, 1900.0, _eng_open)
		if engine == EngineState.RUNNING:
			if not _engine_snd.playing:
				_engine_snd.play()
			var load := clampf(absf(_rpm), 0.0, 1.0)
			_engine_snd.pitch_scale = lerpf(_engine_snd.pitch_scale,
					0.76 + load * 0.40, 1.0 - exp(-2.4 * delta))
			var vol := lerpf(-12.5, -10.0, _eng_open) + load * lerpf(6.0, 8.0, _eng_open)
			_engine_snd.volume_db = lerpf(_engine_snd.volume_db, minf(vol, -3.0),
					1.0 - exp(-2.2 * delta))
		elif _engine_snd.playing:
			_engine_snd.volume_db = lerpf(_engine_snd.volume_db, -52.0,
					1.0 - exp(-5.0 * delta))
			if _engine_snd.volume_db < -44.0:
				_engine_snd.stop()
				_engine_snd.volume_db = -16.0
				_engine_snd.pitch_scale = 0.78
	if not _pwr_segs.is_empty():
		# Ahead runs 0..1 over eight segments, astern 0..-0.4 over four, and the
		# stop mark in the middle is alive only while the diesel is running —
		# kill the engine and the whole bar goes dark, the way a real shaft
		# indicator does when the motor stops.
		var alive := engine == EngineState.RUNNING
		for i in _pwr_segs.size():
			var idx := i - 4
			var lvl := 0.0
			if alive:
				if idx > 0:
					lvl = clampf((_rpm - float(idx - 1) * 0.125) / 0.125, 0.0, 1.0)
				elif idx < 0:
					lvl = clampf((-_rpm - float(-idx - 1) * 0.10) / 0.10, 0.0, 1.0)
				else:
					lvl = 0.30
			else:
				if idx > 0:
					lvl = clampf((_rpm - float(idx - 1) * 0.125) / 0.125, 0.0, 1.0)
				elif idx < 0:
					lvl = clampf((-_rpm - float(-idx - 1) * 0.10) / 0.10, 0.0, 1.0)
			var lit_e: float = lvl * (2.6 if lvl > 0.55 else 1.5)
			_pwr_segs[i].emission_energy_multiplier = lit_e \
					* (0.12 if _blackout > 0.0 else (0.55 + 0.45 * _supply))
		if _pwr_needle != null:
			var t: float = (throttle / 0.125) if throttle >= 0.0 else (throttle / 0.10)
			_pwr_needle.position.y = 3.70 + clampf(t, -4.0, 8.0) * 0.028

	if _radar_ping != null:
		# Same clock as the shader sweep: ping exactly when the beam wraps.
		var ph := fmod(Time.get_ticks_msec() / 1000.0 * 0.7853982, TAU)
		if ph < _radar_sweep_prev:
			_radar_ping.play()
		_radar_sweep_prev = ph
	if _radio_snd != null:
		if radio_held and not _radio_prev_held:
			_radio_snd.stop()
			_radio_snd.play()
		elif not radio_held and _radio_prev_held:
			_radio_snd.stop()
		_radio_prev_held = radio_held
	if _radar_scan != null:
		# 24 rpm — a small marine scanner. 7.5 matched the PPI phosphor and
		# read as parked. Interpolation is off on the node so the RigidBody
		# parent cannot swallow the rotation.
		var spin_want := 0.0
		if _blackout <= 0.0:
			spin_want = 24.0 * TAU / 60.0 * clampf(_supply, 0.0, 1.0)
		_radar_spin = lerpf(_radar_spin, spin_want, 1.0 - exp(-2.2 * delta))
		_radar_scan.rotate_object_local(Vector3.UP, _radar_spin * delta)
	if _radar_arm != null:
		# The arm swings on its pivot — an arc, not a track — settling a touch
		# as it comes, while the carrier counter-turns on the arm's end so the
		# screen finishes facing the helmsman. Walk away and the arm swings
		# home on its own: the joint is powered, not held.
		var rk := 1.0 - exp(-7.0 * delta)
		var cam0: Camera3D = camera_rig.get("_cam") if camera_rig != null else null
		if cam0 != null and radar_pull > 0.02 \
				and cam0.global_position.distance_to(_radar_pivot.global_position) > 2.05:
			radar_pull = 0.0
		if cam0 != null and sounder_pull > 0.02 \
				and cam0.global_position.distance_to(_sounder_pivot.global_position) > 2.05:
			sounder_pull = 0.0
		_radar_arm.rotation.y = lerpf(_radar_arm.rotation.y, _radar_swing_t * radar_pull, rk)
		_radar_arm.position.y = lerpf(_radar_arm.position.y,
				_radar_home.y - RADAR_DROP * radar_pull, rk)
		_radar_pivot.rotation.y = lerpf(_radar_pivot.rotation.y,
				_radar_face_t * radar_pull, rk)
	if _sounder_arm != null:
		# Same powered joint as the radar, one shelf down.
		var sk := 1.0 - exp(-7.0 * delta)
		_sounder_arm.rotation.y = lerpf(_sounder_arm.rotation.y,
				_sounder_swing_t * sounder_pull, sk)
		_sounder_pivot.rotation.y = lerpf(_sounder_pivot.rotation.y,
				_sounder_face_t * sounder_pull, sk)
	if _engine_room != null and _engine_room.has_method("drive"):
		_engine_room.drive(int(engine), _rpm, delta)
	if _screw != null:
		_screw.rotate_object_local(Vector3.UP, _rpm * 40.0 * delta)
	if _motor_pivot != null:
		var k := 1.0 - exp(-5.0 * delta)
		_motor_pivot.rotation.y = lerp_angle(_motor_pivot.rotation.y, _helm * 0.55, k)
	if _wheel != null:
		# Four turns lock to lock, the way a cable-and-quadrant helm feels.
		_wheel.rotation.z = lerp_angle(_wheel.rotation.z, _helm * 4.2,
				1.0 - exp(-5.0 * delta))

	# --- doors ---------------------------------------------------------------
	# Shut is 0; open swings the leaf back against its own bulkhead. The blocker
	# follows the leaf: it is there while the door is anywhere near shut and
	# gone once it is properly open, so you never walk through a closed door and
	# never bump an open one.
	if _door_fwd != null:
		var tf: float = -1.85 if door_fwd_open else 0.0
		_door_fwd.rotation.y = lerpf(_door_fwd.rotation.y, tf, 1.0 - exp(-6.0 * delta))
		var ta: float = 1.85 if door_aft_open else 0.0
		_door_aft.rotation.y = lerpf(_door_aft.rotation.y, ta, 1.0 - exp(-6.0 * delta))
		if _door_eng != null:
			var te: float = 1.92 if door_eng_open else 0.0
			_door_eng.rotation.y = lerpf(_door_eng.rotation.y, te, 1.0 - exp(-6.0 * delta))
		if _fuse_lid != null:
			var tf2: float = -1.85 if fusebox_open else 0.0
			_fuse_lid.rotation.x = lerpf(_fuse_lid.rotation.x, tf2, 1.0 - exp(-7.0 * delta))
		door_blockers.clear()
		if absf(_door_fwd.rotation.y) < 0.9:
			door_blockers.append(AABB(Vector3(-0.55, 0.68, DOOR_Z0 - 0.02),
					Vector3(1.10, 1.92, 0.16)))
		if absf(_door_aft.rotation.y) < 0.9:
			door_blockers.append(AABB(Vector3(-0.55, 0.68, DOOR_Z1 - 0.14),
					Vector3(1.10, 1.92, 0.16)))
	# What the open fuse lid hides. Swept from its hinge: it stands up and leans
	# forward, so it covers a slab roughly 0.6 m tall just forward of the board.
	aim_blockers.clear()
	if _fuse_lid != null and _fuse_lid.rotation.x < -0.9:
		var hp: Vector3 = _fuse_lid.position
		aim_blockers.append(AABB(Vector3(hp.x - 0.25, hp.y + 0.02, hp.z - 0.32),
				Vector3(0.50, 0.62, 0.36)))
	if _locker_door != null:
		var tl: float = -2.05 if locker_open else 0.0
		_locker_door.rotation.y = lerpf(_locker_door.rotation.y, tl,
				1.0 - exp(-7.0 * delta))
	# Putting it on takes time, and the gear leaves the hook while you wear it.
	_gear_t = move_toward(_gear_t, 1.0 if gear_worn else 0.0, delta / 1.35)
	# Both come off the shelf together: the mask goes on your face, the bottle
	# on your back, and neither is left hanging in an open locker while you
	# are wearing it.
	if _gear_mask != null:
		_gear_mask.visible = _gear_t < 0.45
	if _gear_tank != null:
		_gear_tank.visible = _gear_t < 0.30
	if _door_wh != null:
		# Starboard hinge, parks back against the glass. 2.90 rad is almost
		# folded on itself — 90 degrees would put a wall across the room.
		var tw: float = 2.90 if door_wh_open else 0.0
		_door_wh.rotation.y = lerpf(_door_wh.rotation.y, tw, 1.0 - exp(-6.0 * delta))
		if absf(_door_wh.rotation.y) < 0.9:
			door_blockers.append(AABB(Vector3(-0.55, 2.91, WH_DOOR_Z - 0.08),
					Vector3(1.10, 1.92, 0.16)))

	for id: String in _switch_levers:
		var piv: Node3D = _switch_levers[id]
		# Up is on. Lerped rather than snapped, because a toggle has a spring
		# in it and does not teleport.
		piv.rotation.x = lerpf(piv.rotation.x, 0.34 if switch_state(id) else -0.34,
				1.0 - exp(-16.0 * delta))
		var lm2: StandardMaterial3D = _switch_leds[id]
		var son := switch_state(id)
		lm2.emission = Color(0.22, 1.0, 0.34) if son else Color(1.0, 0.16, 0.10)
		# They go out with everything else when the supply drops.
		lm2.emission_energy_multiplier = (2.4 if son else 1.0) \
				* (0.12 if _blackout > 0.0 else (0.55 + 0.45 * _supply))

	if _windlass != null and tackle != null:
		# Turns on the cable that is actually running: metres a second off the
		# drum divided by its radius. Pays out one way, heaves in the other.
		_windlass.rotation.x += float(tackle.chain_rate) / 0.16 * delta
		# What is over the bow is not in the locker.
		var stowed: float = 1.0 - clampf(float(tackle.get("chain_out")) / 42.0, 0.0, 1.0)
		if _chain_heap != null:
			_chain_heap.scale = Vector3(lerpf(0.45, 1.0, stowed),
					lerpf(0.30, 1.0, stowed), lerpf(0.45, 1.0, stowed))
		for li in _chain_run.size():
			_chain_run[li].visible = stowed > float(li) * 0.14

	_update_radio(delta)

	# --- the ship's supply ---------------------------------------------------
	# She is not a new boat. The wiring is old, the connections are salted, and
	# the harder it blows the less any of it wants to work: the sets brown out,
	# stutter, and every so often lose the picture altogether. The lamps dip
	# with them, because it is all the same battery.
	var rough := 0.0
	if weather != null:
		rough = clampf(float(weather.get("wind_speed")) / 34.0 * 0.55
				+ float(weather.get("rain_amount")) * 0.28
				+ (0.30 if bool(weather.get("storm")) else 0.0), 0.0, 1.0)
	# Slamming shakes the connections as surely as the weather does.
	rough = clampf(rough + clampf(absf(linear_velocity.y) / 7.0, 0.0, 0.30), 0.0, 1.0)
	_supply = lerpf(_supply, 1.0 - rough * 0.88, 1.0 - exp(-1.4 * delta))
	if _blackout > 0.0:
		_blackout -= delta
	elif randf() < rough * rough * delta * 1.6:
		_blackout = randf_range(0.10, 0.85)
	var on: float = 0.05 if _blackout > 0.0 else 1.0

	if _sounder_mat != null:
		# Half a second a column: sixty-four columns is half a minute of ground
		# behind you, which is about what one of these showed.
		var here := 0.0
		if ocean != null:
			here = maxf(float(ocean.get_height(global_position))
					- float(ocean.get_seafloor_height(global_position)), 0.0)
		_depth_t += delta
		if _depth_t > 0.5:
			_depth_t = 0.0
			_depth_hist[_depth_head] = here
			_depth_head = (_depth_head + 1) % 64
			_sounder_mat.set_shader_parameter("depth_hist", _depth_hist)
			_sounder_mat.set_shader_parameter("head", _depth_head)
		_sounder_mat.set_shader_parameter("depth_now", here)
		_sounder_mat.set_shader_parameter("lit", (1.0 if light_helm else 0.35) * on)
		_sounder_mat.set_shader_parameter("power", _supply)

	if _chart_mat != null and not _chart_tex_set and ocean != null:
		# The paper is the terrain texture. Hand it over as soon as the seabed
		# has finished baking it.
		var sb: Node = ocean.get("seabed")
		if sb != null:
			var htex: Texture2D = sb.get("height_texture")
			if htex != null:
				_chart_mat.set_shader_parameter("height_tex", htex)
				_chart_tex_set = true
				if _radar_mat != null:
					_radar_mat.set_shader_parameter("height_tex", htex)
					_radar_mat.set_shader_parameter("terrain_size", 2048.0)
	if _chart_mat != null:
		# The chart wraps exactly as the world does, so her fix is simply her
		# position folded into 0..1 — no projection, no scale factor to drift.
		var cu := fposmod(global_position.x / 2048.0 + 0.5, 1.0)
		var cv := fposmod(global_position.z / 2048.0 + 0.5, 1.0)
		_chart_mat.set_shader_parameter("boat_uv", Vector2(cu, cv))
		var f := -global_basis.z
		var hdg := atan2(f.x, -f.z)
		_chart_mat.set_shader_parameter("boat_head", hdg)
		if _radar_mat != null:
			# Same fix, same heading — the radar and the chart cannot disagree
			# about where she is, because they are reading the same two numbers.
			_radar_mat.set_shader_parameter("boat_uv", Vector2(cu, cv))
			_radar_mat.set_shader_parameter("boat_head", hdg)
			_radar_mat.set_shader_parameter("lit", (1.0 if light_helm else 0.30) * on)
			_radar_mat.set_shader_parameter("power", _supply)
		if _chart_pin != null:
			_chart_pin.position = Vector3(1.05 + cu * 0.50, 3.712, 2.63 + cv * 0.50)

	var fwd_speed := -global_basis.z.dot(linear_velocity)
	if _prop != null:
		_prop.amount_ratio = clampf(absf(_rpm) * 0.7 + maxf(fwd_speed, 0.0) * 0.12, 0.0, 1.0)
		_prop.emitting = absf(_rpm) > 0.06 or fwd_speed > 0.9


func toggle_lights() -> void:
	## Master switch on the panel: if anything is burning, douse it all; if the
	## boat is dark, light her up. The beacon keeps its own toggle.
	var any_on := light_cabin or light_helm or light_flood
	light_cabin = not any_on
	light_helm = not any_on
	light_flood = not any_on


func _at_controls() -> bool:
	## Only steer when someone is actually at the wheel — not while the free
	## camera is flying, and not while you are walking about the deck.
	if camera_rig != null and camera_rig.get("free_mode"):
		return false
	return helm_engaged


func _update_wetness(delta: float) -> void:
	if ocean == null or _hull_mats.is_empty():
		return
	var wy: float = ocean.get_height(global_position)
	# Driving into a head sea keeps the topsides soaked; it dries off slowly.
	var target := clampf(Vector2(linear_velocity.x, linear_velocity.z).length() / 7.0, 0.0, 1.0)
	target = maxf(target, clampf(float(ocean.get("sig_height")) / 5.0 - 0.35, 0.0, 1.0))
	# Rain soaks her from above. Half an hour of it and every plank is dark.
	if weather != null:
		target = maxf(target, clampf(float(weather.get("rain_amount")) * 1.25, 0.0, 1.0))
	var k := (1.0 - exp(-2.5 * delta)) if target > _soak else (1.0 - exp(-0.35 * delta))
	_soak = lerpf(_soak, target, k)
	for m: ShaderMaterial in _hull_mats:
		m.set_shader_parameter("water_y", wy)
		m.set_shader_parameter("soak", _soak)


func _update_lantern(delta: float) -> void:
	## Ship's lighting. Three circuits, three switches, and a beacon that keeps
	## its own rhythm: two quick flashes then a long dark, so you can pick her
	## out of a squall by the pattern rather than the brightness.

	# Wiper: a steady metronome sweep while on; parked upright when off. The
	# glass and rain state ride along to both glass materials.
	# The sweep phase runs on whether the wiper is ON, so it does not jump when
	# you switch it: the blade picks up from where it parked.
	if wiper_on:
		_wiper_phase += delta * WIPER_RATE
	var w_ang := 0.0
	if wiper_on:
		w_ang = sin(_wiper_phase) * 1.02
	if _wiper_pivot != null:
		_wiper_pivot.rotation.z = lerp_angle(_wiper_pivot.rotation.z, -w_ang,
				1.0 - exp(-14.0 * delta))
	var rain_now := 0.0
	if weather != null:
		rain_now = clampf(float(weather.get("rain_amount")), 0.0, 1.0)
	# Glass does not dry the instant the rain stops — it stays streaked for a
	# good while, which is when a wiper earns its keep.
	_glass_wet = maxf(rain_now, _glass_wet - delta * 0.055)
	if _front_glass_mat != null:
		_front_glass_mat.set_shader_parameter("wiper_on", 1 if wiper_on else 0)
		_front_glass_mat.set_shader_parameter("wiper_ang", w_ang)
		_front_glass_mat.set_shader_parameter("wiper_phase", _wiper_phase)
		_front_glass_mat.set_shader_parameter("wiper_rate", WIPER_RATE)
		_front_glass_mat.set_shader_parameter("rain", _glass_wet)
	if _glass_mat != null:
		_glass_mat.set_shader_parameter("rain", _glass_wet)

	# Filament lamps do not switch instantly, and a boat's wiring sags.
	# Filament lamps ride the same sagging supply the electronics do, so in a
	# blow the whole boat browns out together instead of the screens misbehaving
	# on their own.
	var n := 0.90 + 0.06 * sin(_t * 6.7) + 0.035 * sin(_t * 19.4 + 1.1)
	n *= (0.55 + 0.45 * _supply) * (0.10 if _blackout > 0.0 else 1.0)
	_flicker = lerpf(_flicker, n, 1.0 - exp(-12.0 * delta))
	if _cabin_lamp != null:
		_cabin_lamp.light_energy = lerpf(_cabin_lamp.light_energy,
				(1.7 * _flicker) if light_cabin else 0.0, 1.0 - exp(-9.0 * delta))
	if _helm_lamp != null:
		_helm_lamp.light_energy = lerpf(_helm_lamp.light_energy,
				(1.2 * _flicker) if light_helm else 0.0, 1.0 - exp(-9.0 * delta))
	if _lit_window != null:
		_lit_window.emission_energy_multiplier = 2.2 * _flicker if light_cabin else 0.0
	var flood_e := (42.0 * _flicker) if light_flood else 0.0
	for fl: SpotLight3D in _floods:
		fl.light_energy = lerpf(fl.light_energy, flood_e, 1.0 - exp(-7.0 * delta))
	if _flood_lens_mat != null:
		_flood_lens_mat.emission_energy_multiplier = (8.0 * _flicker) if light_flood else 0.0
	if _flood_beam_mat != null:
		var haze := 1.0
		if weather != null:
			haze = 1.0 + clampf(float(weather.get("rain_amount")), 0.0, 1.0) * 0.6
		_flood_beam_mat.set_shader_parameter("intensity",
				(1.35 * _flicker) if light_flood else 0.0)
		_flood_beam_mat.set_shader_parameter("haze", haze)
	if _helm_glow != null:
		_helm_glow.emission_energy_multiplier = 2.2 * _flicker if light_helm else 0.0

	if _beacon != null:
		var on := 0.0
		if light_beacon:
			var ph := fmod(_t, 3.4)
			if ph < 0.16 or (ph > 0.42 and ph < 0.58):
				on = 1.0
		_beacon.light_energy = lerpf(_beacon.light_energy, on * 5.5, 1.0 - exp(-28.0 * delta))
		if _beacon_mat != null:
			_beacon_mat.emission_energy_multiplier = _beacon.light_energy * 1.6


func weather_openness(world_pos: Vector3) -> float:
	## How much of the weather reaches the ear. 1 is the deck; 0 is a shut
	## cabin. The doors themselves are the valve — their actual swing, not the
	## switch — so pulling one closed is something you hear happen.
	if not world_pos.is_finite():
		return 1.0
	var p: Vector3 = global_transform.affine_inverse() * world_pos
	var in_cabin := p.y >= 0.55 and p.y < 2.82 \
			and CABIN_XZ.has_point(Vector2(p.x, p.z))
	var in_wheel := p.y >= 2.82 and p.y < 5.40 \
			and absf(p.x) < 1.74 and p.z > -0.32 and p.z < 4.12
	if not in_cabin and not in_wheel:
		return 1.0
	var fwd := 0.0
	var aft := 0.0
	var whd := 0.0
	if _door_fwd != null:
		fwd = clampf(absf(_door_fwd.rotation.y) / 1.85, 0.0, 1.0)
	if _door_aft != null:
		aft = clampf(absf(_door_aft.rotation.y) / 1.85, 0.0, 1.0)
	if _door_wh != null:
		whd = clampf(absf(_door_wh.rotation.y) / 2.90, 0.0, 1.0)
	if in_wheel:
		# Glass all round. The balcony door is the valve, not the cabin's.
		var d := Vector2(p.x, p.z - WH_DOOR_Z).length()
		return lerpf(0.12, lerpf(0.90, 0.30, clampf(d / 3.2, 0.0, 1.0)), whd)
	# Companionway hatch always leaks a little. An open door is a hole in
	# the wall: standing in it is almost the deck; the far end of the cabin
	# still hears it, just less.
	var o := 0.10
	if fwd > 0.02:
		var d := Vector2(p.x, p.z - DOOR_Z0).length()
		o = maxf(o, lerpf(0.88, 0.26, clampf(d / 3.6, 0.0, 1.0)) * fwd)
	if aft > 0.02:
		var d := Vector2(p.x, p.z - DOOR_Z1).length()
		o = maxf(o, lerpf(0.88, 0.26, clampf(d / 3.6, 0.0, 1.0)) * aft)
	return o


func heat_at(local_pos: Vector3) -> float:
	## How much of the stove's air this point is sitting in. The fire does not
	## care about the batteries. It is the air around the plate — not the
	## cabin as a room, not the sills, not the hatch. Stand next to it and
	## you feel it; walk the door or go up and you do not.
	if local_pos.y < 0.58 or local_pos.y >= 2.78:
		return 0.0
	if not CABIN_XZ.has_point(Vector2(local_pos.x, local_pos.z)):
		return 0.0
	# Door sills. The fire does not meet you on the way in.
	if absf(local_pos.x) < 0.74:
		if absf(local_pos.z - DOOR_Z0) < 0.55 or absf(local_pos.z - DOOR_Z1) < 0.55:
			return 0.0
	# Companionway well. The hatch is a hole in the deck, not a flue.
	if local_pos.x < -0.45 and local_pos.z > 0.90 and local_pos.z < 4.00:
		return 0.0
	var d := Vector2(local_pos.x - STOVE.x, local_pos.z - STOVE.z).length()
	return 1.0 - smoothstep(0.22, 1.35, d)


func _update_stove(delta: float) -> void:
	## An element has thermal mass, and that is the whole feel of it: switch it
	## on and the wire takes about eight seconds to come up to red, switch it
	## off and it takes nearly twenty to let go — glowing long after the switch
	## has moved. Cooling is the slower half on purpose; that asymmetry is what
	## separates a heater from a light bulb.
	##
	## It runs off the ship's supply now, so a blackout takes it with everything
	## else — which is the price of not burning anything.
	var powered: float = 1.0 if (stove_on and _blackout <= 0.0) else 0.0
	powered *= clampf(_supply, 0.0, 1.0)
	var tau: float = 8.0 if powered > _stove_heat_t else 19.0
	_stove_heat_t = lerpf(_stove_heat_t, powered, 1.0 - exp(-delta / tau))
	# Mains ripple once it is hot — a faint 100 Hz shimmer beaten against a
	# slow convection wobble. Nothing like a coal bed's irregular breathing.
	var shimmer := 1.0 + 0.030 * sin(_t * 21.4) + 0.018 * sin(_t * 3.7 + 1.1)
	var g: float = _stove_heat_t * _stove_heat_t * shimmer
	if _stove_lamp != null:
		_stove_lamp.light_energy = 1.75 * g
		_stove_lamp.visible = g > 0.004
	if _stove_ember != null:
		_stove_ember.emission_energy_multiplier = 5.2 * g
		# Cold wire is grey; hot wire is not just brighter, it is a different
		# colour. Dull red first, orange only once it is really up.
		_stove_ember.emission = Color(1.0, 0.16 + 0.24 * _stove_heat_t,
				0.02 + 0.10 * _stove_heat_t)
	if _stove_heat != null:
		_stove_heat.emitting = _stove_heat_t > 0.12
	if _stove_snd != null:
		if _stove_heat_t > 0.05:
			if not _stove_snd.playing:
				_stove_snd.play()
			_stove_snd.volume_db = linear_to_db(clampf(_stove_heat_t * 0.55, 0.02, 1.0))
		elif _stove_snd.playing:
			_stove_snd.stop()


func _build_dive_locker() -> void:
	## A steel clothes locker, bolted to the frames on the port side. Vents
	## punched in the door because wet gear that cannot breathe rots, a lip at
	## the bottom so what drips off it runs to the sole and not into the bunk,
	## and one plain lever handle.
	var steel := _mat(Color(0.155, 0.170, 0.178), 0.62, 0.55)
	var steel_d := _mat(Color(0.105, 0.115, 0.122), 0.70, 0.50)
	var iron := _mat(Color(0.150, 0.115, 0.088), 0.90, 0.30)
	var rubber := _mat(Color(0.045, 0.048, 0.052), 0.88)
	var glassy := _mat(Color(0.30, 0.42, 0.46, 0.55), 0.10, 0.0)
	glassy.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var LX := -1.46          # centre of the carcass
	var LZ := 0.36
	var Y0 := 0.68
	var Y1 := 2.38
	var HY := (Y0 + Y1) * 0.5
	# Carcass: back against the ship side, two sides, top, and a kick at the
	# bottom. Left open at the front — the door is the front.
	_box(Vector3(0.03, Y1 - Y0, 0.52), Vector3(LX - 0.225, HY, LZ), Vector3.ZERO, steel_d)
	_box(Vector3(0.48, Y1 - Y0, 0.03), Vector3(LX, HY, LZ - 0.245), Vector3.ZERO, steel_d)
	_box(Vector3(0.48, Y1 - Y0, 0.03), Vector3(LX, HY, LZ + 0.245), Vector3.ZERO, steel_d)
	_box(Vector3(0.48, 0.03, 0.52), Vector3(LX, Y1, LZ), Vector3.ZERO, steel)
	_box(Vector3(0.48, 0.02, 0.52), Vector3(LX, Y0 + 0.11, LZ), Vector3.ZERO, steel_d)
	_box(Vector3(0.48, 0.11, 0.52), Vector3(LX, Y0 + 0.055, LZ), Vector3.ZERO, steel_d)
	# A single strap across the back at chest height, to stop the bottle
	# walking about in a seaway. No rail, no hangers: nothing in here is
	# clothing, it is two pieces of equipment that stand up on their own.
	_box(Vector3(0.40, 0.035, 0.020), Vector3(LX, 1.52, LZ - 0.215), Vector3.ZERO, rubber)

	# The door. Hinged on its FORWARD edge so it opens across the locker and
	# not into the walk — the cabin sole between the bunk and this is 1.49 m
	# and a leaf swinging aft would take most of it.
	_locker_door = Node3D.new()
	_locker_door.position = Vector3(LX + 0.225, HY, LZ - 0.245)
	add_child(_locker_door)
	var leaf := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(0.028, Y1 - Y0 - 0.02, 0.48)
	leaf.mesh = lm
	leaf.material_override = steel
	leaf.position = Vector3(0.0, 0.0, 0.245)
	_locker_door.add_child(leaf)
	# Louvres, low and high — a locker breathes or it stinks.
	for i in 5:
		var vy: float = -0.62 + float(i) * 0.055
		for vy2 in [vy, vy + 0.95]:
			var v := MeshInstance3D.new()
			var vm := BoxMesh.new()
			vm.size = Vector3(0.006, 0.016, 0.30)
			v.mesh = vm
			v.material_override = steel_d
			v.position = Vector3(0.016, vy2, 0.245)
			v.rotation.z = deg_to_rad(-24.0)
			_locker_door.add_child(v)
	# Handle: a plain lever, and the hasp it drops into.
	var h := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.030, 0.035, 0.145)
	h.mesh = hm
	h.material_override = iron
	h.position = Vector3(0.030, 0.10, 0.415)
	_locker_door.add_child(h)

	# --- what is inside -----------------------------------------------------
	# A bottle standing on the locker floor with its mask hung over the valve.
	# That is how it is actually stowed: the cylinder stands, the mask lives on
	# top of it where it cannot be trodden on, and the whole lot comes out in
	# one movement.
	var tank_paint := _mat(Color(0.16, 0.24, 0.22), 0.55, 0.35)
	var brass2 := _mat(Color(0.52, 0.40, 0.16), 0.42, 0.85)
	var TZ := LZ + 0.02
	_gear_tank = Node3D.new()
	_gear_tank.position = Vector3(LX, 0.0, TZ)
	add_child(_gear_tank)
	var body := MeshInstance3D.new()
	var bm2 := CylinderMesh.new()
	bm2.top_radius = 0.084
	bm2.bottom_radius = 0.084
	bm2.height = 0.66
	bm2.radial_segments = 18
	body.mesh = bm2
	body.material_override = tank_paint
	body.position = Vector3(0.0, 1.12, 0.0)
	_gear_tank.add_child(body)
	# Boot at the foot — the rubber cup a cylinder stands in.
	var boot := MeshInstance3D.new()
	var bo := CylinderMesh.new()
	bo.top_radius = 0.089
	bo.bottom_radius = 0.094
	bo.height = 0.10
	bo.radial_segments = 18
	boot.mesh = bo
	boot.material_override = rubber
	boot.position = Vector3(0.0, 0.84, 0.0)
	_gear_tank.add_child(boot)
	# Neck, valve block and its handwheel.
	var neck := MeshInstance3D.new()
	var nk := CylinderMesh.new()
	nk.top_radius = 0.030
	nk.bottom_radius = 0.062
	nk.height = 0.075
	nk.radial_segments = 14
	neck.mesh = nk
	neck.material_override = tank_paint
	neck.position = Vector3(0.0, 1.49, 0.0)
	_gear_tank.add_child(neck)
	var valve := MeshInstance3D.new()
	var vb := BoxMesh.new()
	vb.size = Vector3(0.052, 0.070, 0.052)
	valve.mesh = vb
	valve.material_override = brass2
	valve.position = Vector3(0.0, 1.56, 0.0)
	_gear_tank.add_child(valve)
	var wheel := MeshInstance3D.new()
	var wt := TorusMesh.new()
	wt.inner_radius = 0.019
	wt.outer_radius = 0.032
	wt.rings = 12
	wt.ring_segments = 7
	wheel.mesh = wt
	wheel.material_override = brass2
	wheel.position = Vector3(0.0, 1.60, -0.045)
	wheel.rotation.x = deg_to_rad(90.0)
	_gear_tank.add_child(wheel)
	# First stage on the valve, and the hose off it looping down the bottle.
	var reg := MeshInstance3D.new()
	var rg := CylinderMesh.new()
	rg.top_radius = 0.028
	rg.bottom_radius = 0.028
	rg.height = 0.048
	rg.radial_segments = 12
	reg.mesh = rg
	reg.material_override = brass2
	reg.position = Vector3(0.055, 1.56, 0.0)
	reg.rotation.z = deg_to_rad(90.0)
	_gear_tank.add_child(reg)
	for hi in 5:
		var t: float = float(hi) / 4.0
		var hose := MeshInstance3D.new()
		var hs := CylinderMesh.new()
		hs.top_radius = 0.010
		hs.bottom_radius = 0.010
		hs.height = 0.115
		hs.radial_segments = 8
		hose.mesh = hs
		hose.material_override = rubber
		hose.position = Vector3(0.075 + sin(t * PI) * 0.030, 1.50 - t * 0.42,
				0.010 + t * 0.045)
		hose.rotation.x = deg_to_rad(-12.0 * t)
		hose.rotation.z = deg_to_rad(24.0 - 34.0 * t)
		_gear_tank.add_child(hose)
	# Harness webbing round the bottle.
	for by in [1.02, 1.32]:
		var band := MeshInstance3D.new()
		var bd := CylinderMesh.new()
		bd.top_radius = 0.088
		bd.bottom_radius = 0.088
		bd.height = 0.035
		bd.radial_segments = 18
		band.mesh = bd
		band.material_override = rubber
		band.position = Vector3(0.0, by, 0.0)
		_gear_tank.add_child(band)

	# The mask, hung by its strap over the valve. No hook, no hanger — the
	# strap simply lies over the block, which is where it always ends up.
	_gear_mask = Node3D.new()
	_gear_mask.position = Vector3(LX, 1.46, TZ + 0.085)
	_gear_mask.rotation.x = deg_to_rad(14.0)
	add_child(_gear_mask)
	var skirt := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.180, 0.108, 0.070)
	skirt.mesh = sm
	skirt.material_override = rubber
	_gear_mask.add_child(skirt)
	var lens := MeshInstance3D.new()
	var lnm := BoxMesh.new()
	lnm.size = Vector3(0.152, 0.080, 0.012)
	lens.mesh = lnm
	lens.material_override = glassy
	lens.position = Vector3(0.0, 0.006, 0.038)
	_gear_mask.add_child(lens)
	# Frame round the glass, so it is a mask and not a slab.
	for fr in [[Vector3(0.176, 0.016, 0.016), Vector3(0.0, 0.049, 0.034)],
			[Vector3(0.176, 0.016, 0.016), Vector3(0.0, -0.043, 0.034)],
			[Vector3(0.016, 0.104, 0.016), Vector3(-0.083, 0.003, 0.034)],
			[Vector3(0.016, 0.104, 0.016), Vector3(0.083, 0.003, 0.034)]]:
		var fm := MeshInstance3D.new()
		var fb := BoxMesh.new()
		fb.size = fr[0]
		fm.mesh = fb
		fm.material_override = rubber
		fm.position = fr[1]
		_gear_mask.add_child(fm)
	# The strap, over the valve block behind it.
	for sx2 in [-1.0, 1.0]:
		var strap := MeshInstance3D.new()
		var stm := BoxMesh.new()
		stm.size = Vector3(0.026, 0.012, 0.145)
		strap.mesh = stm
		strap.material_override = rubber
		strap.position = Vector3(sx2 * 0.072, 0.020, -0.100)
		strap.rotation.x = deg_to_rad(24.0)
		strap.rotation.y = deg_to_rad(-sx2 * 9.0)
		_gear_mask.add_child(strap)


func _build_stove_heat() -> void:
	## Air rising off an ELEMENT — heat haze, not fire. When this was a coal
	## stove the plume was orange and read as flame; over an electric bar that
	## is simply wrong, and it looked it: lit rectangles climbing out of a
	## machine that has nothing burning in it. Now it is a faint colourless
	## distortion, the thing you see when you put your hands over a heater.
	_stove_heat = GPUParticles3D.new()
	_stove_heat.amount = 16
	_stove_heat.lifetime = 1.05
	_stove_heat.preprocess = 1.0
	_stove_heat.local_coords = true
	_stove_heat.position = Vector3(1.28, 1.18, 4.10)
	_stove_heat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stove_heat.visibility_aabb = AABB(Vector3(-1.2, -0.4, -1.2), Vector3(2.4, 2.4, 2.4))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.16, 0.02, 0.08)
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 18.0
	pm.initial_velocity_min = 0.09
	pm.initial_velocity_max = 0.24
	pm.gravity = Vector3(0.0, 0.34, 0.0)
	pm.damping_min = 0.4
	pm.damping_max = 0.9
	pm.scale_min = 0.20
	pm.scale_max = 0.55
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.30, 1.0])
	# Nearly colourless and nearly transparent: warm air, not flame.
	g.colors = PackedColorArray([
		Color(1.0, 0.72, 0.52, 0.085),
		Color(1.0, 0.66, 0.46, 0.045),
		Color(0.8, 0.55, 0.40, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	_stove_heat.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.055, 0.09)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_color = Color(1.0, 0.45, 0.12, 0.4)
	mat.vertex_color_use_as_albedo = true
	q.material = mat
	_stove_heat.draw_pass_1 = q
	_stove_heat.emitting = true
	add_child(_stove_heat)
	_build_stove_sound()


func _build_stove_sound() -> void:
	## The fire lives in the stove, so the crackle does too — 3D, from the
	## door. Inverse, short: you hear it when you are next to it. The sills
	## and the hatch do not.
	var s: AudioStream = load("res://assets/audio/stove.mp3")
	if s == null:
		return
	if s is AudioStreamMP3:
		(s as AudioStreamMP3).loop = true
	_stove_snd = AudioStreamPlayer3D.new()
	_stove_snd.position = Vector3(1.28, 1.02, 4.08)
	_stove_snd.stream = s
	_stove_snd.bus = "Master"
	_stove_snd.unit_size = 0.70
	_stove_snd.max_distance = 2.15
	_stove_snd.max_db = 6.0
	_stove_snd.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	_stove_snd.panning_strength = 0.90
	add_child(_stove_snd)
	_stove_snd.play()


func _build_cabin_lived(trim: Material, metal: Material) -> void:
	## The fiddle is there to keep a mug aboard. An empty one is a lie. Same
	## for the stove-top and the bulkhead at eye height: things a person put
	## down and will pick up again.
	var enamel := _mat(Color(0.78, 0.76, 0.70), 0.55)
	var enamel_rim := _mat(Color(0.16, 0.28, 0.42), 0.6)
	var brass := _mat(Color(0.42, 0.32, 0.14), 0.38, 0.78)
	var kettle := _mat(Color(0.22, 0.23, 0.24), 0.42, 0.55)
	var face := _mat(Color(0.82, 0.78, 0.68), 0.7)
	face.emission_enabled = true
	face.emission = Color(0.55, 0.50, 0.38)
	face.emission_energy_multiplier = 0.12

	# Enamel mug, standing on the sea chest a little off-centre the way a mug
	# sits after the boat has moved it. It used to live in the table's fiddle,
	# and when the table became the dive locker it was left hanging in the air
	# over the sole — the sort of thing that only ever shows up in a photograph.
	_cyl(0.038, 0.042, 0.085, Vector3(1.34, 1.343, 0.56), Vector3.ZERO, enamel)
	_cyl(0.040, 0.044, 0.012, Vector3(1.34, 1.390, 0.56), Vector3.ZERO, enamel_rim)
	_cyl(0.028, 0.028, 0.008, Vector3(1.34, 1.306, 0.56), Vector3.ZERO, enamel)
	_cyl(0.012, 0.012, 0.055, Vector3(1.395, 1.343, 0.56), Vector3(0.0, 0.0, 90.0), enamel)

	# Kettle on the stove, clear of the pipe.
	_cyl(0.085, 0.078, 0.15, Vector3(1.14, 1.295, 4.16), Vector3.ZERO, kettle)
	_cyl(0.070, 0.018, 0.045, Vector3(1.14, 1.392, 4.16), Vector3.ZERO, kettle)
	_cyl(0.016, 0.012, 0.09, Vector3(1.22, 1.30, 4.08), Vector3(0.0, 0.0, 58.0), kettle)
	_cyl(0.010, 0.010, 0.14, Vector3(1.14, 1.40, 4.16), Vector3(0.0, 0.0, 90.0), metal)

	# Aneroid barometer, port forward bulkhead, above the table. Brass, a
	# cream face, a needle — the weather you can read without opening a panel.
	_cyl(0.095, 0.095, 0.04, Vector3(-1.48, 1.92, -0.40), Vector3(90.0, 0.0, 0.0), brass)
	_cyl(0.078, 0.078, 0.012, Vector3(-1.48, 1.92, -0.378), Vector3(90.0, 0.0, 0.0), face)
	_box(Vector3(0.008, 0.055, 0.006), Vector3(-1.48, 1.942, -0.370),
			Vector3(0.0, 0.0, -28.0), brass)
	_cyl(0.012, 0.012, 0.03, Vector3(-1.48, 1.70, -0.40), Vector3(90.0, 0.0, 0.0), brass)


func _build_deck_gear(trim: Material, metal: Material) -> void:
	## Nothing on the walk. Cleats and chocks sit on the cap, fenders hang
	## outboard of the rubbing strake, the ring and the boathook live on the
	## house. You do not trip over a place this boat could make fast.
	var rubber := _mat(Color(0.07, 0.07, 0.07), 0.96)
	var hemp := _mat(Color(0.42, 0.34, 0.20), 0.9)
	var ring_or := _mat(Color(0.72, 0.18, 0.10), 0.7)
	var ring_wh := _mat(Color(0.82, 0.80, 0.74), 0.75)
	var wood := trim

	# Horn cleats: bow, just forward of the house, and the quarters.
	for sx in [-1.0, 1.0]:
		_cleat(Vector3(sx * 1.88, 1.16, -3.62), metal)
		_cleat(Vector3(sx * 1.92, 1.16, -0.72), metal)
		_cleat(Vector3(sx * 1.72, 1.16, 5.28), metal)
		# Closed fairleads on the stem and the transom corners.
		_fairlead(Vector3(sx * 0.62, 1.16, -3.98), metal)
		_fairlead(Vector3(sx * 1.55, 1.16, 5.52), metal)

	# --- boarding ladder, over the transom ----------------------------------
	# The one way back aboard. Rungs carry on well below the waterline because
	# the bottom one has to be there when she rolls away from you, and a ladder
	# you can only reach at the top of a swell is a ladder that drowns people.
	var lad_iron := _mat(Color(0.150, 0.115, 0.088), 0.90, 0.30)
	for lsx in [-0.16, 0.16]:
		_box(Vector3(0.045, 2.10, 0.045),
				Vector3(SEA_LADDER_X + lsx, -0.32, SEA_LADDER_Z),
				Vector3(6.0, 0.0, 0.0), lad_iron)
	var lad_n := 7
	for li in lad_n:
		var ly: float = SEA_LADDER_TOP - 0.10 - float(li) * 0.27
		_cyl(0.020, 0.020, 0.36, Vector3(SEA_LADDER_X, ly, SEA_LADDER_Z + 0.02),
				Vector3(0.0, 0.0, 90.0), lad_iron)
	# Top brackets bolting the stiles through the transom cap, and grab handles
	# standing above the deck — what your hands find first coming up.
	for lsx in [-0.16, 0.16]:
		_box(Vector3(0.07, 0.09, 0.22), Vector3(SEA_LADDER_X + lsx, 0.60, SEA_LADDER_Z - 0.09),
				Vector3.ZERO, lad_iron)
		_cyl(0.020, 0.020, 0.46, Vector3(SEA_LADDER_X + lsx, 0.86, SEA_LADDER_Z - 0.04),
				Vector3(10.0, 0.0, 0.0), lad_iron)
	_cyl(0.020, 0.020, 0.36, Vector3(SEA_LADDER_X, 1.07, SEA_LADDER_Z - 0.08),
			Vector3(0.0, 0.0, 90.0), lad_iron)

	# Fenders: three a side, hanging outboard from the rail. Bow, waist,
	# quarter — the set you keep in the water when you might come alongside.
	for sx in [-1.0, 1.0]:
		for z in [-3.42, -0.88, 5.18]:
			_fender(Vector3(sx * 2.14, 0.58, z), rubber, hemp)

	# Lifebuoy on the starboard house, between the after window and the
	# corner — not in the walk, not over a pane.
	_lifebuoy(Vector3(1.88, 1.62, 3.28), ring_or, ring_wh, hemp)

	# Boathook lashed along the port house, under the windows.
	_cyl(0.016, 0.016, 2.15, Vector3(-1.88, 1.38, 1.55), Vector3(90.0, 0.0, 0.0), wood)
	_cyl(0.014, 0.010, 0.16, Vector3(-1.88, 1.38, 0.40), Vector3(90.0, 0.0, 0.0), metal)
	_cyl(0.010, 0.010, 0.12, Vector3(-1.88, 1.30, 0.34), Vector3(0.0, 0.0, 0.0), metal)
	_cyl(0.008, 0.008, 0.10, Vector3(-1.88, 1.38, 2.05), Vector3(0.0, 0.0, 90.0), hemp)
	_cyl(0.008, 0.008, 0.10, Vector3(-1.88, 1.38, 1.05), Vector3(0.0, 0.0, 90.0), hemp)


func _cleat(pos: Vector3, metal: Material) -> void:
	_box(Vector3(0.08, 0.035, 0.20), pos, Vector3.ZERO, metal)
	_cyl(0.022, 0.018, 0.22, pos + Vector3(0.0, 0.04, 0.0), Vector3(90.0, 0.0, 0.0), metal)
	_cyl(0.016, 0.016, 0.05, pos + Vector3(0.0, 0.04, 0.10), Vector3.ZERO, metal)
	_cyl(0.016, 0.016, 0.05, pos + Vector3(0.0, 0.04, -0.10), Vector3.ZERO, metal)


func _fairlead(pos: Vector3, metal: Material) -> void:
	_box(Vector3(0.10, 0.03, 0.12), pos, Vector3.ZERO, metal)
	_cyl(0.016, 0.016, 0.10, pos + Vector3(-0.04, 0.06, 0.0), Vector3.ZERO, metal)
	_cyl(0.016, 0.016, 0.10, pos + Vector3(0.04, 0.06, 0.0), Vector3.ZERO, metal)
	_cyl(0.012, 0.012, 0.09, pos + Vector3(0.0, 0.10, 0.0), Vector3(0.0, 0.0, 90.0), metal)


func _fender(pos: Vector3, rubber: Material, hemp: Material) -> void:
	var fender_top := pos.y + 0.26
	var rail_y := 1.70
	_cyl(0.008, 0.008, rail_y - fender_top,
			Vector3(pos.x, (rail_y + fender_top) * 0.5, pos.z), Vector3.ZERO, hemp)
	_cyl(0.095, 0.10, 0.52, pos, Vector3.ZERO, rubber)
	_cyl(0.07, 0.07, 0.04, pos + Vector3(0.0, 0.26, 0.0), Vector3.ZERO, rubber)
	_cyl(0.07, 0.07, 0.04, pos + Vector3(0.0, -0.26, 0.0), Vector3.ZERO, rubber)


func _lifebuoy(pos: Vector3, orange: Material, white: Material, hemp: Material) -> void:
	var mi := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.12
	t.outer_radius = 0.22
	t.rings = 14
	t.ring_segments = 20
	t.material = orange
	mi.mesh = t
	mi.position = pos
	mi.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	add_child(mi)
	var stripe := MeshInstance3D.new()
	var t2 := TorusMesh.new()
	t2.inner_radius = 0.155
	t2.outer_radius = 0.185
	t2.rings = 10
	t2.ring_segments = 16
	t2.material = white
	stripe.mesh = t2
	stripe.position = pos
	stripe.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	add_child(stripe)
	_cyl(0.008, 0.008, 0.28, pos + Vector3(-0.04, 0.22, 0.0), Vector3.ZERO, hemp)
	_box(Vector3(0.04, 0.03, 0.04), pos + Vector3(-0.04, 0.36, 0.0), Vector3.ZERO, hemp)


func _physics_process(delta: float) -> void:
	if ocean == null:
		return
	if not global_position.is_finite() or not linear_velocity.is_finite():
		global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 2.0, 0.0))
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		return

	var submerged := 0.0
	var hull_n := 0.0
	var wet_n := 0.0
	var com_wave_vy := 0.0
	# Sums for a least-squares plane through the water UNDER THE HULL. See the
	# note where they are solved, below.
	var px := 0.0
	var pz := 0.0
	var ph := 0.0
	var pxx := 0.0
	var pzz := 0.0
	var pxz := 0.0
	var pxh := 0.0
	var pzh := 0.0
	for i in PROBES.size():
		var wp: Vector3 = global_transform * PROBES[i]
		var wh: float = ocean.get_height(wp)
		var wave_vy := 0.0
		if _prev_wh_valid:
			wave_vy = clampf((wh - _prev_wh[i]) / delta, -10.0, 10.0)
		_prev_wh[i] = wh
		if PROBES[i].y < 0.0:
			hull_n += 1.0
			com_wave_vy += wave_vy
			var rx: float = wp.x - global_position.x
			var rz: float = wp.z - global_position.z
			var rh: float = wh - global_position.y
			px += rx
			pz += rz
			ph += rh
			pxx += rx * rx
			pzz += rz * rz
			pxz += rx * rz
			pxh += rx * rh
			pzh += rz * rh

		var depth: float = wh - wp.y
		if depth > 0.0:
			wet_n += 1.0
			if PROBES[i].y < 0.0:
				submerged += 1.0
			var r := wp - global_position
			var v_at := linear_velocity + angular_velocity.cross(r)
			var rel_vy := clampf(v_at.y - wave_vy, -12.0, 12.0)
			var f := probe_stiffness * clampf(depth, 0.0, 1.4) - probe_damping * rel_vy
			f = clampf(f, 0.0, probe_stiffness * 2.4)
			apply_force(Vector3.UP * f, r)
			if PROBES[i].y < 0.0 and rel_vy < -4.2 and depth < 0.28 and _slam_cd <= 0.0:
				_slam_cd = 1.15
				ocean.splash(wp, clampf(absf(rel_vy) * 0.18, 0.4, 1.1))
	if hull_n > 0.0:
		submerged /= hull_n
		com_wave_vy /= hull_n
	_prev_wh_valid = true
	_slam_cd -= delta

	# The surface the hull actually sits on.
	#
	# This used to be the wave normal at ONE POINT — her centre — and that is
	# why she threw herself about on the smallest chop: a two-metre ripple
	# passing under the middle of a nine-metre boat tilted the whole hull as if
	# the entire sea had gone over. No hull does that. A hull spans its own
	# waterline and the short waves cancel across it; what it feels is the
	# AVERAGE slope under it.
	#
	# So: a least-squares plane through the six hull probes, which is exactly
	# that average, and it low-passes the sea by the length of the boat for
	# free. Long swell tips her as before; ripples do not.
	var wave_n := Vector3.UP
	var fitted := false
	if hull_plane_fit and hull_n >= 3.0:
		var mx := px / hull_n
		var mz := pz / hull_n
		var mh := ph / hull_n
		var cxx := pxx - hull_n * mx * mx
		var czz := pzz - hull_n * mz * mz
		var cxz := pxz - hull_n * mx * mz
		var cxh := pxh - hull_n * mx * mh
		var czh := pzh - hull_n * mz * mh
		var det := cxx * czz - cxz * cxz
		if absf(det) > 1.0e-5:
			var ga := (cxh * czz - czh * cxz) / det
			var gb := (czh * cxx - cxh * cxz) / det
			# Slopes past about 40 degrees are a breaking face, not a surface
			# to sit on, and letting them through is how she got thrown.
			ga = clampf(ga, -0.85, 0.85)
			gb = clampf(gb, -0.85, 0.85)
			wave_n = Vector3(-ga, 1.0, -gb).normalized()
			fitted = true
	if not fitted and ocean.has_method("get_normal"):
		wave_n = ocean.get_normal(global_position)

	var hydro := maxf(submerged, wet_n / float(PROBES.size()))
	if hydro > 0.0:
		# Ride the swell: extra heave from the wave's own vertical accel.
		var wave_ay := 0.0
		if _com_vy_valid:
			wave_ay = clampf((com_wave_vy - _prev_com_vy) / delta, -14.0, 14.0)
		_prev_com_vy = com_wave_vy
		_com_vy_valid = true
		apply_central_force(Vector3.UP * wave_ay * mass * 0.7 * hydro)

		# Align with the wave only while still upright. Past ~70° of heel the
		# righting moment vanishes and a steep face can finish the capsize.
		var up_dot := global_basis.y.dot(Vector3.UP)
		if up_dot > 0.32:
			var target_up := wave_n.normalized()
			if target_up.length_squared() > 0.01:
				var tilt_axis := global_basis.y.cross(target_up)
				# A wave face rolls and pitches a hull; it has no business
				# steering her. Without this the vertical component of the
				# cross product rectified over a beam sea into a slow,
				# uncommanded turn — measured in the --drift-test ledger.
				tilt_axis.y = 0.0
				apply_torque(tilt_axis * 34000.0 * up_dot * up_dot * hydro)
				if drift_dbg:
					drift_sums["align"] += tilt_axis.y * 34000.0 * up_dot * up_dot * hydro

		# Roll and pitch damping. A hull swinging drags its bilges broadside
		# through water and loses that energy in about a roll and a half; with
		# nothing but the engine's 0.05 of angular damp she rings like a bell.
		#
		# The vertical component is dropped, exactly as it is on the alignment
		# torque above: damping applied about a heeled hull's own axis has a
		# world-Y part, and that part rectified over a beam sea into an
		# uncommanded turn once before (see --drift-test).
		var t_roll: Vector3 = -angular_velocity.project(global_basis.z) \
				* roll_damp * hydro
		var t_pitch: Vector3 = -angular_velocity.project(global_basis.x) \
				* pitch_damp * hydro
		t_roll.y = 0.0
		t_pitch.y = 0.0
		apply_torque(t_roll + t_pitch)
		if drift_dbg:
			drift_sums["damp"] += (t_roll + t_pitch).y

		# Horizontal drag (keel + hull). Leave Y mostly free so the boat can
		# jump a crest and fall into the trough.
		#
		# Drag is against the WATER, not against the ground. That one word is
		# the whole tidal stream: point at the harbour in a three-knot cross-set
		# and you will still arrive downstream of it.
		var water_v := Vector3.ZERO
		if ocean.has_method("current_at"):
			var c: Vector2 = ocean.current_at(global_position)
			water_v = Vector3(c.x, 0.0, c.y)
		# The water a hull sits in is not still, and the tide is the smaller half
		# of why. As a wave passes, the water under the boat runs forward at the
		# crest and back in the trough — measured on this sea, 0.5 m/s average
		# and 1.7 m/s peak against a tidal stream of 0.06. Leaving it out meant
		# drag, leeway and rudder flow were all computed against water that was
		# standing still while the sea heaved. The vertical component is left
		# alone: the buoyancy probes already damp against the surface's own rise
		# and fall, and adding it here would count it twice.
		if ocean.has_method("surface_velocity"):
			var orb: Vector3 = ocean.surface_velocity(global_position)
			if orb.is_finite():
				water_v += Vector3(orb.x, 0.0, orb.z)
		var v := linear_velocity
		var v_h := Vector3(v.x, 0.0, v.z)
		apply_central_force(-(v_h - water_v) * HULL_DRAG * hydro)
		apply_central_force(Vector3.DOWN * v.y * 240.0 * hydro)
		# Roll damps less than yaw/pitch so a beam swell can actually heel it.
		var local_w: Vector3 = global_basis.inverse() * angular_velocity
		# Roll and pitch damp in the hull's own axes — but their torque, mapped
		# to world, leaks a yaw component whenever she is heeled, and over a
		# seaway that leak rectifies into a phantom helm (the drift-test ledger
		# read +590k N·m·s of it in 24 s). So the leak is projected out, and
		# yaw gets its own damper about true vertical, where a keel actually
		# resists a swing.
		var damp_rp := Vector3(local_w.x * 19000.0, 0.0, local_w.z * 8200.0)
		var t_rp: Vector3 = -(global_basis * damp_rp)
		t_rp.y = 0.0
		apply_torque(t_rp * hydro)
		apply_torque(Vector3.UP * (-angular_velocity.y * 124000.0) * hydro)
		if drift_dbg:
			drift_sums["damp"] += -angular_velocity.y * 124000.0 * hydro
		var side := global_basis.x
		var lat := side.dot(linear_velocity - water_v)
		apply_central_force(-side * lat * 5300.0 * hydro)
		apply_central_force(ocean.wind_vector() * 26.0 * hydro)

		# The screw answers the telegraph whether or not anyone is at the wheel.
		if up_dot > 0.22:
			apply_central_force(-global_basis.z * _rpm * thrust_power * submerged)
		if up_dot > 0.22:
			# A rudder is a wing: no water flowing over it, no turn. Dead slow
			# she barely answers; the prop wash across the blade gives a little
			# steerage even from a standstill.
			var thru: float = absf(global_basis.z.dot(linear_velocity - water_v))
			# Rudder authority climbs with the square-ish of the flow: dead slow
			# she hardly answers at all.
			var flow := clampf(maxf(thru / 9.0, absf(_rpm) * 0.35), 0.05, 1.0)
			flow *= flow * 0.5 + flow * 0.5
			apply_torque(Vector3.UP * _helm * turn_torque * flow * submerged)
			if drift_dbg:
				drift_sums["rudder"] += _helm * turn_torque * flow * submerged
	else:
		_com_vy_valid = false

	_run_aground()

	if angular_velocity.length() > 2.2:
		angular_velocity = angular_velocity.limit_length(2.2)
	if linear_velocity.y > 11.0:
		linear_velocity.y = 11.0

	if global_position.y < -30.0 or global_position.y > 120.0:
		global_position = Vector3(0.0, 2.0, 0.0)
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		_prev_wh_valid = false
		_com_vy_valid = false


func _run_aground() -> void:
	## Rock does not care that you are a rigid body.
	##
	## This is a heightmap query rather than a collider, and that is the whole
	## point. The bottom IS a heightmap; wrapping each island in a cylinder let
	## you bounce off an invisible drum around a rock and then sail clean
	## through anything wider than the cylinder ever got — which was every
	## island worth the name. Feeling for the actual bottom along the keel
	## grounds her on whatever is really there: a shoal, a beach, a reef, or the
	## face of a headland, and it costs seven texture reads.
	if ocean == null or not ocean.has_method("get_seafloor_height"):
		aground = false
		return
	var xf := global_transform
	var deepest := 0.0
	var worst := Vector3.ZERO
	var hits := 0
	for k in KEEL:
		var wp: Vector3 = xf * k
		var bed: float = ocean.get_seafloor_height(wp)
		var pen: float = bed - wp.y
		if pen <= 0.0:
			continue
		hits += 1
		# Holding her off the ground at the point that touched, so she lifts a
		# bow or heels to a bilge rather than rising flat like a lift.
		apply_force(Vector3.UP * clampf(pen, 0.0, 1.5) * 62000.0, wp - global_position)
		if pen > deepest:
			deepest = pen
			worst = wp
	aground = hits > 0
	if hits == 0:
		return
	# The ground takes her way off, hard. Four and a half tonnes at speed still
	# carries up a beach — but seconds, not minutes.
	#
	# The friction has to be COULOMB — a fixed force opposing the way she is
	# going, not a force proportional to speed. Viscous drag alone always leaves
	# a speed at which it balances the thrust, and she creeps: the first version
	# of this ground her a third of a metre a second up the beach until she was
	# sitting five metres above the sea, engine still turning. Dry friction has
	# no such balance point. Below the limit she does not move at all.
	# Tuned so that hard aground she will not creep an inch ahead under full
	# power, but full ASTERN, helped by the slope, works her off in under a
	# minute. Stuck for good is a bug, not a consequence.
	var grip: float = clampf(deepest * 2.2, 0.30, 0.90)
	var vh := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	var sp := vh.length()
	if sp > 0.05:
		apply_central_force(-vh / sp * 120000.0 * grip)
	apply_central_force(-vh * 22000.0 * grip)
	apply_torque(-angular_velocity * 62000.0 * grip)
	if drift_dbg:
		drift_sums["ground"] += -angular_velocity.y * 62000.0 * grip
	# And shoves her back down the slope, so she does not simply climb the
	# island. Two extra samples each way at the deepest contact.
	var e := 3.0
	var gx: float = float(ocean.get_seafloor_height(worst + Vector3(e, 0.0, 0.0))) \
			- float(ocean.get_seafloor_height(worst - Vector3(e, 0.0, 0.0)))
	var gz: float = float(ocean.get_seafloor_height(worst + Vector3(0.0, 0.0, e))) \
			- float(ocean.get_seafloor_height(worst - Vector3(0.0, 0.0, e)))
	var down := Vector3(-gx, 0.0, -gz)
	if down.length_squared() > 1e-6:
		apply_central_force(down.normalized() * clampf(deepest * 3.0, 0.6, 2.2) * 96000.0)
