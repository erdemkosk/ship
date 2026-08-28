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
var _helm_lamp: OmniLight3D
var _beacon: OmniLight3D
var _beacon_mat: StandardMaterial3D
var _floods: Array[SpotLight3D] = []
var _flood_lens_mat: StandardMaterial3D
var _flood_beam_mat: ShaderMaterial
## Switch panel at the helm. Toggled with 1/2/3 while you are aboard.
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
var _switch_levers := {}
var _switch_leds := {}
var _door_fwd: Node3D
var _door_aft: Node3D
var _door_wh: Node3D
## Shut at the start of the game: you open her up yourself.
var door_fwd_open := false
var door_aft_open := false
var door_wh_open := false
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
	_build_motor()
	_build_engine_sound()
	_build_water_fx()
	# Roughly m(L^2+H^2)/12 about each axis: pitch, yaw, roll. Roll is left
	# heavier than the box formula so she rolls slow and deep like timber.
	inertia = Vector3(46000.0, 52000.0, 19000.0)


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
	AABB(Vector3(-1.64, 0.68, -0.05), Vector3(0.74, 0.70, 0.86)),  # table
	AABB(Vector3(1.05, 0.68, 4.05), Vector3(0.46, 0.90, 0.46)),    # stove
	AABB(Vector3(1.02, 2.91, 4.26), Vector3(0.52, 1.70, 0.52)),    # funnel, on the balcony
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
const LADDER := AABB(Vector3(0.0, -999.0, 0.0), Vector3(0.0, 0.0, 0.0))
const LADDER_BAND := Vector2(0.0, 0.0)
## Where you stand to take the wheel, and where the wheel itself is.
## Right at the wheel, half a step to starboard. Measured, not chosen: from the
## old spot the throttle knob sat 1.14 m from the right shoulder against a
## 0.63 m arm, so it simply could not be held while the left hand steered.
const HELM_STAND := Vector3(0.12, 2.91, 0.55)
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
	{"id": "helm", "pos": Vector3(0.0, 3.75, 0.30), "r": 0.36, "name": "Dümen"},
	{"id": "telegraph", "pos": Vector3(0.70, 3.78, 0.02), "r": 0.18, "name": "Gaz kolu"},
	{"id": "ignition", "pos": Vector3(0.50, 3.54, 0.06), "r": 0.28, "name": "Kontak"},
	{"id": "windlass", "pos": Vector3(0.0, 1.00, -3.35), "r": 0.55, "name": "Irgat (çapa)"},
	# The switch console between the radar and the chart table. Every one of
	# these is a real switch you walk up to and throw; the keyboard shortcut is
	# the same circuit, not a different system.
	{"id": "door_fwd", "pos": Vector3(0.0, 1.55, -0.45), "r": 0.50, "name": "Baş kapı"},
	{"id": "door_aft", "pos": Vector3(0.0, 1.55, 4.65), "r": 0.50, "name": "Kıç kapı"},
	{"id": "door_wh", "pos": Vector3(0.0, 3.85, 4.05), "r": 0.50, "name": "Balkon kapısı"},
	{"id": "sw_cabin", "pos": Vector3(1.10, 3.78, 1.34), "r": 0.10, "name": "Kamara ışığı"},
	{"id": "sw_helm", "pos": Vector3(1.30, 3.78, 1.34), "r": 0.10, "name": "Dümen evi ışığı"},
	{"id": "sw_beacon", "pos": Vector3(1.50, 3.78, 1.34), "r": 0.10, "name": "İkaz feneri"},
	{"id": "sw_flood", "pos": Vector3(1.10, 3.78, 1.74), "r": 0.10, "name": "Projektörler"},
	{"id": "sw_wiper", "pos": Vector3(1.30, 3.78, 1.74), "r": 0.10, "name": "Silecek"},
	{"id": "sw_anchor", "pos": Vector3(1.50, 3.78, 1.74), "r": 0.10, "name": "Irgat (çapa)"},
	{"id": "chart", "pos": Vector3(1.30, 3.72, 2.88), "r": 0.36, "name": "Harita masası"},
	{"id": "radio", "pos": Vector3(1.49, 3.94, 0.55), "r": 0.20, "name": "Telsiz"},
	{"id": "radar", "pos": Vector3(1.18, 4.28, 0.10), "r": 0.28, "name": "Radar"},
	{"id": "sounder", "pos": Vector3(1.15, 4.02, 0.08), "r": 0.22, "name": "İskandil"},
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
	var hull_wood := _wet_wood(Color(0.115, 0.085, 0.062), 0.88)
	var keel_wood := _wet_wood(Color(0.070, 0.052, 0.040), 0.93)
	var boot := _wet_wood(Color(0.28, 0.075, 0.055), 0.80)   # boot-top stripe
	var deck := _mat(Color(0.20, 0.155, 0.110), 0.94)
	var paint := _mat(Color(0.46, 0.44, 0.395), 0.86)        # chalky white
	var paint_dark := _mat(Color(0.20, 0.20, 0.19), 0.88)
	var trim := _mat(Color(0.155, 0.105, 0.070), 0.82)
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
	# Bow: two panels converging on the stem.
	_box(Vector3(0.20, 1.35, 2.6), Vector3(-1.18, 0.18, -3.5), Vector3(0.0, 19.0, 0.0), hull_wood)
	_box(Vector3(0.20, 1.35, 2.6), Vector3(1.18, 0.18, -3.5), Vector3(0.0, -19.0, 0.0), hull_wood)
	_box(Vector3(0.26, 1.55, 0.9), Vector3(0.0, 0.30, -4.45), Vector3(14.0, 0.0, 0.0), keel_wood)
	# Transom, raked.
	_box(Vector3(4.03, 1.25, 0.22), Vector3(0.0, 0.18, 5.70), Vector3(-9.0, 0.0, 0.0), hull_wood)
	# Rubbing strake all round.
	_box(Vector3(4.26, 0.14, 9.85), Vector3(0.0, 0.52, 0.75), Vector3.ZERO, trim)

	# --- deck and bulwarks --------------------------------------------------
	_box(Vector3(3.88, 0.14, 9.5), Vector3(0.0, 0.56, 0.80), Vector3.ZERO, deck)
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

	# Table with fiddle rails — the raised lips that keep a mug aboard — and a stool.
	_box(Vector3(0.74, 0.07, 0.86), Vector3(-1.27, 1.30, 0.38), Vector3.ZERO, trim)
	_box(Vector3(0.74, 0.05, 0.04), Vector3(-1.27, 1.36, -0.03), Vector3.ZERO, trim)
	_box(Vector3(0.74, 0.05, 0.04), Vector3(-1.27, 1.36, 0.79), Vector3.ZERO, trim)
	_cyl(0.05, 0.05, 0.62, Vector3(-1.27, 0.98, 0.38), Vector3.ZERO, metal)
	_box(Vector3(0.30, 0.06, 0.30), Vector3(-0.74, 1.02, 0.52), Vector3.ZERO, trim)
	_cyl(0.04, 0.04, 0.34, Vector3(-0.74, 0.84, 0.52), Vector3.ZERO, metal)

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

	# Stove in the aft bay, its door glowing, pipe up through the deckhead.
	# It stands aft of the wheelhouse now, so the funnel has a clear run out
	# of the roof instead of arriving inside the wheelhouse. Fire, not a
	# filament: it keeps going when the batteries die.
	_box(Vector3(0.46, 0.55, 0.46), Vector3(1.28, 0.92, 4.28), Vector3.ZERO, metal)
	_stove_ember = _mat(Color(0.25, 0.10, 0.06), 0.8)
	_stove_ember.emission_enabled = true
	_stove_ember.emission = Color(1.0, 0.36, 0.10)
	_stove_ember.emission_energy_multiplier = 2.4
	_box(Vector3(0.26, 0.22, 0.03), Vector3(1.28, 0.86, 4.05), Vector3.ZERO, _stove_ember)
	_cyl(0.07, 0.07, 1.92, Vector3(1.28, 2.13, 4.28), Vector3.ZERO, metal)
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
		var dz: float = (CH_Z0 + 0.06) if k == 0 else (CH_Z1 - 0.06)
		var piv := Node3D.new()
		piv.position = Vector3(-0.55, 0.0, dz)
		add_child(piv)
		# Panelled leaf: frame, two panels, a knob and a plate.
		_box(Vector3(1.06, 1.92, 0.045), Vector3(0.53, 1.64, 0.0), Vector3.ZERO, trim, piv)
		_box(Vector3(0.72, 0.62, 0.055), Vector3(0.53, 2.16, 0.0), Vector3.ZERO,
				_mat(Color(0.105, 0.072, 0.048), 0.85), piv)
		_box(Vector3(0.72, 0.72, 0.055), Vector3(0.53, 1.24, 0.0), Vector3.ZERO,
				_mat(Color(0.105, 0.072, 0.048), 0.85), piv)
		_cyl(0.022, 0.022, 0.07, Vector3(0.94, 1.62, 0.0), Vector3(90.0, 0.0, 0.0), metal, piv)
		_box(Vector3(0.05, 0.16, 0.012), Vector3(0.94, 1.62, 0.032), Vector3.ZERO, metal, piv)
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
	_cyl(0.11, 0.075, 5.20, Vector3(0.0, 3.10, -2.35), Vector3(0.0, 0.0, 3.0), trim)
	_box(Vector3(1.70, 0.07, 0.07), Vector3(0.0, 4.55, -2.35), Vector3.ZERO, trim)
	# Funnel on the starboard aft corner of the roof — directly above the cabin
	# stove, whose pipe runs up through the deckhead into it. It used to sit
	# in the aft glass; it lives on the balcony now, clear of the pane and of
	# the door.
	_cyl(0.26, 0.24, 1.55, Vector3(1.28, 3.72, 4.52), Vector3.ZERO, metal)
	_cyl(0.29, 0.29, 0.10, Vector3(1.28, 4.54, 4.52), Vector3.ZERO, dark)
	# Foredeck rail: stanchions plus a top rail.
	for i in 7:
		var t := float(i) / 6.0
		var rz := lerpf(-3.85, -0.55, t)
		var rx := lerpf(1.69, 1.94, t)
		_cyl(0.035, 0.035, 0.62, Vector3(-rx, 1.42, rz), Vector3.ZERO, metal)
		_cyl(0.035, 0.035, 0.62, Vector3(rx, 1.42, rz), Vector3.ZERO, metal)
	_box(Vector3(0.05, 0.05, 3.35), Vector3(-1.18, 1.72, -2.20), Vector3(0.0, -4.0, 0.0), metal)
	_box(Vector3(0.05, 0.05, 3.35), Vector3(1.18, 1.72, -2.20), Vector3(0.0, 4.0, 0.0), metal)
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
	# Stringer and handrail down the inboard side, hard against the edge of the
	# opening so they frame the stair rather than stand in it.
	_box(Vector3(0.05, 0.30, 3.10), Vector3(-0.52, 1.86, 2.42), Vector3(-36.6, 0.0, 0.0), trim)
	# Closing boards down the inboard side, stepping with the treads, so the
	# stair reads as a solid piece of joinery from the cabin rather than a
	# flight of planks with daylight under it.
	for k in 9:
		# Trim only, so these can close right up under the tread even though the
		# collision volume behind them has to stop short.
		var by := 2.910 - float(k) * 0.223 - 0.03
		_box(Vector3(0.05, by - 0.68, 0.30), Vector3(-0.515, (0.68 + by) * 0.5,
				1.10 + float(k) * 0.30), Vector3.ZERO, trim)
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

	# Masthead beacon. Nothing hangs off her stern any more — the cabin and the
	# wheelhouse light her well enough from inside — but a working boat carries
	# an all-round flashing light at the truck of the mast, and in this sea it is
	# the only thing that says where you are.
	_beacon_mat = StandardMaterial3D.new()
	_beacon_mat.albedo_color = Color(0.32, 0.05, 0.04)
	_beacon_mat.emission_enabled = true
	_beacon_mat.emission = Color(1.0, 0.15, 0.10)
	_beacon_mat.emission_energy_multiplier = 0.0
	_cyl(0.10, 0.10, 0.12, Vector3(0.0, 5.72, -2.35), Vector3.ZERO, metal)
	_cyl(0.085, 0.085, 0.20, Vector3(0.0, 5.88, -2.35), Vector3.ZERO, _beacon_mat)
	_cyl(0.11, 0.02, 0.10, Vector3(0.0, 6.03, -2.35), Vector3.ZERO, metal)
	_beacon = OmniLight3D.new()
	_beacon.position = Vector3(0.0, 5.88, -2.35)
	_beacon.light_color = Color(1.0, 0.16, 0.10)
	_beacon.light_energy = 0.0
	_beacon.omni_range = 26.0
	_beacon.omni_attenuation = 1.3
	_beacon.shadow_enabled = false
	add_child(_beacon)

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
	_needles.append(_make_dial(face, -0.58, 0.095, "İSKANDİL", ["0", "20", "40"],
			bronze, dial_face))                                    # 1: depth
	_needles.append(_make_dial(face, 0.14, 0.095, "ZİNCİR", ["0", "35", "70"],
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
	_thr_lever.position = Vector3(0.62, 3.62, 0.22)
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
	## your right hand falls. Six brass toggles, and every one of them is the
	## same circuit its keyboard shortcut throws — the keys are a shortcut to
	## these switches, not a parallel system. A boat this old would not have a
	## menu, and it does not have one here either.
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
	# It lies flat: raked, the switches pointed at the deckhead and the engraving
	# read edge-on from anywhere you could actually stand.
	_box(Vector3(0.60, 0.03, 0.72), Vector3(cx, 3.695, cz), Vector3.ZERO, face_mat)
	_box(Vector3(0.64, 0.045, 0.035), Vector3(cx, 3.70, cz - 0.375), Vector3.ZERO, bronze)
	_box(Vector3(0.64, 0.045, 0.035), Vector3(cx, 3.70, cz + 0.375), Vector3.ZERO, bronze)

	# Six toggles, two rows of three. The lever of each carries its own state.
	var ids: Array[String] = ["sw_cabin", "sw_helm", "sw_beacon",
			"sw_flood", "sw_wiper", "sw_anchor"]
	var names: Array[String] = ["KAMARA", "DÜMEN", "İKAZ", "PROJ", "SİLECEK", "ÇAPA"]
	var keys: Array[String] = ["1", "2", "3", "6", "5", "G"]
	for i in 6:
		var col := i % 3
		var row: int = i / 3
		var sx := cx - 0.20 + float(col) * 0.20
		var sz := cz - 0.20 + float(row) * 0.40
		var sy := 3.712
		# Escutcheon, and the toggle standing up out of it.
		_box(Vector3(0.10, 0.012, 0.10), Vector3(sx, sy - 0.012, sz), Vector3.ZERO, bronze)
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
		# Engraved plate for each, and the key that throws the same circuit.
		_console_label(names[i], Vector3(sx, sy - 0.008, sz + 0.092), 34)
		_console_label(keys[i], Vector3(sx, sy - 0.008, sz - 0.070), 30)


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


func toggle_switch(id: String) -> void:
	## One switch, one circuit. Called from the E handler when you throw a
	## toggle by hand; the number keys reach the same fields.
	match id:
		"sw_cabin": light_cabin = not light_cabin
		"sw_helm": light_helm = not light_helm
		"sw_beacon": light_beacon = not light_beacon
		"sw_flood": light_flood = not light_flood
		"sw_wiper": wiper_on = not wiper_on
		"sw_anchor":
			if tackle != null:
				tackle.toggle()
		"door_fwd": door_fwd_open = not door_fwd_open
		"door_aft": door_aft_open = not door_aft_open
		"door_wh": door_wh_open = not door_wh_open
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
		"ignition": return engine != EngineState.OFF
	return false


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
	_box(Vector3(0.34, 0.27, 0.17), sp, Vector3(-22.0, 0.0, 0.0), casing)
	# Two knobs, as every one of these ever had. There WAS a bezel plate here
	# and it was sitting a centimetre in front of the glass, which is why the
	# screen read as a dead black rectangle.
	_cyl(0.018, 0.018, 0.022, sp + Vector3(-0.115, -0.085, 0.095), Vector3(68.0, 0.0, 0.0), bronze)
	_cyl(0.018, 0.018, 0.022, sp + Vector3(0.115, -0.085, 0.095), Vector3(68.0, 0.0, 0.0), bronze)

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
	scr.position = sp + Vector3(0.0, 0.034, 0.088)
	scr.rotation_degrees = Vector3(-22.0, 0.0, 0.0)
	scr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(scr)
	_sounder_screen = scr
	# --- radar, in the bracket above it -------------------------------------
	var rp := Vector3(1.18, 4.38, -0.05)
	_box(Vector3(0.05, 0.14, 0.04), rp + Vector3(-0.18, -0.16, 0.02), Vector3.ZERO, metal)
	_box(Vector3(0.05, 0.14, 0.04), rp + Vector3(0.18, -0.16, 0.02), Vector3.ZERO, metal)
	_box(Vector3(0.38, 0.36, 0.20), rp, Vector3(-20.0, 0.0, 0.0), casing)
	_cyl(0.016, 0.016, 0.020, rp + Vector3(-0.145, -0.135, 0.100), Vector3(70.0, 0.0, 0.0), bronze)
	_cyl(0.016, 0.016, 0.020, rp + Vector3(0.145, -0.135, 0.100), Vector3(70.0, 0.0, 0.0), bronze)
	_radar_mat = ShaderMaterial.new()
	_radar_mat.shader = load("res://shaders/radar.gdshader")
	var rscr := MeshInstance3D.new()
	var rq := QuadMesh.new()
	rq.size = Vector2(0.275, 0.275)
	rq.material = _radar_mat
	rscr.mesh = rq
	rscr.position = rp + Vector3(0.0, 0.038, 0.104)
	rscr.rotation_degrees = Vector3(-20.0, 0.0, 0.0)
	rscr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rscr)
	_radar_screen = rscr
	# Waveguide up toward the scanner on the mast.
	_cyl(0.010, 0.010, 0.42, rp + Vector3(0.10, 0.34, -0.02), Vector3(0.0, 0.0, -8.0), casing)

	# Transducer cable, disappearing through the deck the way they all do.
	_cyl(0.006, 0.006, 0.62, sp + Vector3(-0.10, -0.42, 0.02), Vector3(6.0, 0.0, 4.0), casing)

	# --- VHF set, on the starboard side forward of the chart table -----------
	_radio_set = Node3D.new()
	add_child(_radio_set)
	var dark_face := _mat(Color(0.055, 0.060, 0.055), 0.55)
	var lcd := _mat(Color(0.05, 0.11, 0.07), 0.45)
	lcd.emission_enabled = true
	lcd.emission = Color(0.35, 1.0, 0.55)
	lcd.emission_energy_multiplier = 0.9

	# Case, with a face raked back so you can read it from the wheel.
	_box(Vector3(0.11, 0.22, 0.32), Vector3(1.605, 4.00, 0.44), Vector3.ZERO, casing)
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
	_cyl(0.007, 0.007, 0.13, Vector3(1.605, 4.16, 0.40), Vector3(18.0, 0.0, 6.0), casing)
	_cyl(0.006, 0.006, 0.22, Vector3(1.600, 3.80, 0.36), Vector3(-10.0, 0.0, 8.0), casing)
	# Strain relief where the handset cord enters the case — the cord used to
	# start in mid-air a few centimetres off the box.
	_cyl(0.013, 0.008, 0.030, RADIO_ANCHOR + Vector3(0.012, 0.0, 0.0),
			Vector3(0.0, 0.0, 90.0), casing)
	# Cradle hook the handset hangs on.
	_box(Vector3(0.05, 0.018, 0.10), RADIO_CRADLE + Vector3(0.028, -0.055, 0.0), Vector3.ZERO, metal)
	_box(Vector3(0.02, 0.055, 0.02), RADIO_CRADLE + Vector3(0.045, -0.012, -0.045), Vector3.ZERO, metal)

	# The handset. Its own node, because it leaves the cradle. Shaped the way one
	# is: a slim grip with a fat cap at each end, the earpiece a little deeper
	# than the mouthpiece, and the transmit bar under your thumb.
	_radio_hand = Node3D.new()
	add_child(_radio_hand)
	_box(Vector3(0.038, 0.046, 0.150), Vector3(0.0, 0.0, 0.0), Vector3.ZERO, casing, _radio_hand)
	_box(Vector3(0.054, 0.054, 0.052), Vector3(0.0, 0.004, -0.088), Vector3.ZERO, casing, _radio_hand)
	_box(Vector3(0.050, 0.046, 0.044), Vector3(0.0, 0.002, 0.086), Vector3.ZERO, casing, _radio_hand)
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
			var want: Vector3 = global_transform.affine_inverse() \
					* (cam.global_position + cam.global_basis * Vector3(0.21, -0.11, -0.31))
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
			var fw: Vector3 = global_basis.inverse() * (-cam.global_basis.z)
			_radio_hand.rotation.y = atan2(fw.x, fw.z)
			_radio_hand.rotation.x = 0.35
			_radio_hand.rotation.z = 0.0
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

	# Shaft and screw, just ahead of the rudder.
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
	for i in 3:
		var blade := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.30, 0.04, 0.14)
		bm.material = bronze
		blade.mesh = bm
		blade.position = Vector3(0.0, -0.68, 3.86)
		blade.rotation_degrees = Vector3(18.0, 0.0, float(i) * 120.0)
		add_child(blade)


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
	_engine_snd.position = Vector3(0.0, 0.42, 3.70)
	_engine_snd.stream = _wav_idle()
	_engine_snd.bus = "Engine"
	_engine_snd.unit_size = 3.2
	_engine_snd.max_distance = 18.0
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
		door_blockers.clear()
		if absf(_door_fwd.rotation.y) < 0.9:
			door_blockers.append(AABB(Vector3(-0.55, 0.68, DOOR_Z0 - 0.02),
					Vector3(1.10, 1.92, 0.16)))
		if absf(_door_aft.rotation.y) < 0.9:
			door_blockers.append(AABB(Vector3(-0.55, 0.68, DOOR_Z1 - 0.14),
					Vector3(1.10, 1.92, 0.16)))
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

	# The windlass answers from anywhere aboard — you would walk forward to it,
	# but the switch is at the helm too.
	if tackle != null and Input.is_action_just_pressed("anchor"):
		tackle.toggle()


func toggle_lights() -> void:
	## Master switch on the panel: if anything is burning, douse it all; if the
	## boat is dark, light her up. The beacon keeps its own switch (3).
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
	if Input.is_action_just_pressed("light_cabin"):
		light_cabin = not light_cabin
	if Input.is_action_just_pressed("light_helm"):
		light_helm = not light_helm
	if Input.is_action_just_pressed("light_beacon"):
		light_beacon = not light_beacon
	if Input.is_action_just_pressed("light_flood"):
		light_flood = not light_flood
	if Input.is_action_just_pressed("wiper"):
		wiper_on = not wiper_on

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
	## Combustion, not a filament. Slow irregular pulse — a coal bed, not a
	## 50 Hz lamp — and it never follows `_supply` or `_blackout`.
	var fire := 0.84 + 0.10 * sin(_t * 6.1) + 0.07 * sin(_t * 11.8 + 0.9) \
			+ 0.04 * sin(_t * 19.4 + 2.2)
	if _stove_lamp != null:
		_stove_lamp.light_energy = lerpf(_stove_lamp.light_energy, 1.55 * fire,
				1.0 - exp(-6.0 * delta))
	if _stove_ember != null:
		_stove_ember.emission_energy_multiplier = 1.6 + 1.8 * fire
	if _stove_snd != null and not _stove_snd.playing:
		_stove_snd.play()


func _build_stove_heat() -> void:
	## Air rising off the plate. Tiny, local, unshaded: it is the thing you
	## see when you put your hands out, not a particle fountain.
	_stove_heat = GPUParticles3D.new()
	_stove_heat.amount = 22
	_stove_heat.lifetime = 1.35
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
	pm.initial_velocity_min = 0.12
	pm.initial_velocity_max = 0.38
	pm.gravity = Vector3(0.0, 0.55, 0.0)
	pm.damping_min = 0.4
	pm.damping_max = 0.9
	pm.scale_min = 0.35
	pm.scale_max = 1.0
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	g.colors = PackedColorArray([
		Color(1.0, 0.48, 0.12, 0.55),
		Color(1.0, 0.32, 0.08, 0.22),
		Color(0.45, 0.12, 0.04, 0.0)])
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

	# Enamel mug in the fiddle, a little off-centre the way a mug sits after
	# the boat has moved it.
	_cyl(0.038, 0.042, 0.085, Vector3(-1.14, 1.385, 0.22), Vector3.ZERO, enamel)
	_cyl(0.040, 0.044, 0.012, Vector3(-1.14, 1.432, 0.22), Vector3.ZERO, enamel_rim)
	_cyl(0.028, 0.028, 0.008, Vector3(-1.14, 1.348, 0.22), Vector3.ZERO, enamel)
	_cyl(0.012, 0.012, 0.055, Vector3(-1.085, 1.385, 0.22), Vector3(0.0, 0.0, 90.0), enamel)

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

	var wave_n := Vector3.UP
	if ocean.has_method("get_normal"):
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
				apply_torque(tilt_axis * 46000.0 * up_dot * up_dot * hydro)

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
		var damp_w := Vector3(local_w.x * 19000.0, local_w.y * 124000.0, local_w.z * 5600.0)
		apply_torque(-(global_basis * damp_w) * hydro)
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
