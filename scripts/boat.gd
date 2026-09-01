extends RigidBody3D
## Small wooden boat. Buoyancy at hull + deck probes; W/S thrust, A/D rudder.
## Rolls with the swell. Past vanishing stability it capsizes.

const WeatherScript := preload("res://scripts/weather.gd")
const ShaderSet := preload("res://scripts/shader_set.gd")
const BoatAudioControllerScript := preload("res://scripts/boat_audio_controller.gd")
const BoatChainVisualScript := preload("res://scripts/boat_chain_visual.gd")
const BoatElectricalModelScript := preload("res://scripts/boat_electrical_model.gd")
const BoatWeatherEffectsScript := preload("res://scripts/boat_weather_effects.gd")
const BoatConsoleInstrumentsScript := preload("res://scripts/boat_console_instruments.gd")
const BoatConsoleVisualBuilderScript := preload("res://scripts/boat_console_visual_builder.gd")
const BoatElectronicsVisualBuilderScript := preload("res://scripts/boat_electronics_visual_builder.gd")
const BoatElectronicsControllerScript := preload("res://scripts/boat_electronics_controller.gd")
const BoatSwitchboardVisualBuilderScript := preload("res://scripts/boat_switchboard_visual_builder.gd")
const BoatNavigationDisplayControllerScript := preload("res://scripts/boat_navigation_display_controller.gd")
const BoatAccessControllerScript := preload("res://scripts/boat_access_controller.gd")
const BoatEngineControllerScript := preload("res://scripts/boat_engine_controller.gd")
const BoatAnchorVisualBuilderScript := preload("res://scripts/boat_anchor_visual_builder.gd")
const BoatHullVisualBuilderScript := preload("res://scripts/boat_hull_visual_builder.gd")
const BoatCabinVisualBuilderScript := preload("res://scripts/boat_cabin_visual_builder.gd")
const BoatWheelhouseVisualBuilderScript := preload("res://scripts/boat_wheelhouse_visual_builder.gd")
const BoatMastVisualBuilderScript := preload("res://scripts/boat_mast_visual_builder.gd")
const BoatCompanionwayVisualBuilderScript := preload("res://scripts/boat_companionway_visual_builder.gd")
const BoatBuoyancyControllerScript := preload("res://scripts/boat_buoyancy_controller.gd")
const BoatGroundingControllerScript := preload("res://scripts/boat_grounding_controller.gd")
const BoatHydrodynamicsControllerScript := preload("res://scripts/boat_hydrodynamics_controller.gd")
const BoatRadioHandsetControllerScript := preload("res://scripts/boat_radio_handset_controller.gd")
const BoatHelmControlsVisualBuilderScript := preload("res://scripts/boat_helm_controls_visual_builder.gd")
const BoatChartTableVisualBuilderScript := preload("res://scripts/boat_chart_table_visual_builder.gd")
const BoatHelmVisualBuilderScript := preload("res://scripts/boat_helm_visual_builder.gd")
const BoatSwitchboardControllerScript := preload("res://scripts/boat_switchboard_controller.gd")
const BoatWindlassControllerScript := preload("res://scripts/boat_windlass_controller.gd")
const BoatLightingControllerScript := preload("res://scripts/boat_lighting_controller.gd")
const BoatInteriorEnvironmentScript := preload("res://scripts/boat_interior_environment.gd")
const BoatStoveControllerScript := preload("res://scripts/boat_stove_controller.gd")
const BoatInteractionLocatorScript := preload("res://scripts/boat_interaction_locator.gd")
const BoatInteriorVisualBuilderScript := preload("res://scripts/boat_interior_visual_builder.gd")
const BoatDeckVisualBuilderScript := preload("res://scripts/boat_deck_visual_builder.gd")
const BoatVisuals := preload("res://scripts/boat_visual_factory.gd")
const BoatMeshBatcherScript := preload("res://scripts/boat_mesh_batcher.gd")
const DeckBagScript := preload("res://scripts/deck_bag.gd")

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
@export var thrust_power := 32800.0
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
var weather: Node3D
## Wiper switch — 5 at the helm. Sweeps only while on; parks to port when off.
var wiper_on := false
var _wiper_arm: Node3D
var _cabin_lamp: OmniLight3D
var _stove_lamp: OmniLight3D
var _stove_fill: OmniLight3D
var _stove_ember: StandardMaterial3D
var _stove_reflector: StandardMaterial3D
var _stove_heat: GPUParticles3D
var _stove_snd: AudioStreamPlayer3D
var _stove_switch: Node3D
## Electric heater: switched, and slow at both ends. `stove_on` is what the
## switch says; `_stove_heat_t` is what the elements have got round to.
var stove_on := false
var _stove_controller: BoatStoveController = BoatStoveControllerScript.new()
var _stove_heat_t: float:
	get: return _stove_controller.heat()
	set(value): _stove_controller.set_heat(value)
var _helm_lamp: OmniLight3D
var _chart_lamp: SpotLight3D
var _beacon: OmniLight3D
var _beacon_mat: StandardMaterial3D
var _nav_mats: Array[StandardMaterial3D] = []
var _nav_spots: Array[SpotLight3D] = []
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
var _dial_face_mat: ShaderMaterial
var _thr_lever: Node3D
var _pwr_segs: Array[StandardMaterial3D] = []
var _pwr_needle: Node3D
var _console_instruments: BoatConsoleInstruments = BoatConsoleInstrumentsScript.new()
var _interior_environment: BoatInteriorEnvironment = BoatInteriorEnvironmentScript.new()
var _interaction_locator: BoatInteractionLocator = BoatInteractionLocatorScript.new()
var _deck_visuals: Node3D
var _motor_pivot: Node3D
var _screw: Node3D
var _engine_room: Node3D
var _prop: GPUParticles3D
var _prop_pm: ParticleProcessMaterial
var _prop_bubbles: GPUParticles3D
var _prop_bubble_pm: ParticleProcessMaterial
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
var aground := false
## True while you stand at the telegraph alone: W/S work the lever, no steering.
var telegraph_engaged := false
var _hull_mats: Array[ShaderMaterial] = []
## Static _box/_cyl/_prism pieces, keyed by material, flushed into one
## ArrayMesh each. Pivots, glass and anything that must hide on its own
## stay as separate instances — merging those would move or smear them.
var _mesh_batcher: BoatMeshBatcher
var _weather_effects: BoatWeatherEffects
var _sounder_mat: ShaderMaterial
var _radar_mat: ShaderMaterial
var _radar_tex_set := false
var _windlass: Node3D
## Chain locker pile, plus the live run: pipe → gypsy → deck → roller.
## The run slides with chain_out so the gypsy is feeding, not spinning empty.
var _chain_visual: BoatChainVisual
var _switch_levers := {}
var _switch_leds := {}
## Cartridge in its clips. Pull one (lid open) and that row goes dead even
## if the toggle is still up — that is what a fuse is for.
var _electrical: BoatElectricalModel = BoatElectricalModelScript.new()
var _fuse_bodies := {}
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
## Distribution panel. Flood and wiper live on the dash; the other four
## toggles sit in the well with the cartridges. Lid down, those are gone.
var _fuse_lid: Node3D
var _fuse_latch_local := Vector3(0.0, 0.012, 0.44)
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
## Doorways get a blocker only while their door is SHUT. BLOCKERS is a const —
## it has to be, the walker reads it every tick — so the two that move live
## here, and deck_walker.gd resolves against both lists.
var door_blockers: Array[AABB] = []
const DOOR_Z0 := -0.45
const DOOR_Z1 := 4.65
const WH_DOOR_Z := 4.05
## Latch on the leaf, local. Z magnitude is how far the handle stands off
## the plate; the sign is the face you are standing on (see door_latch_local).
const CABIN_LATCH := Vector3(1.02, 1.58, 0.072)
const WH_LATCH := Vector3(-0.98, 0.92, 0.072)
var _supply := 1.0
var _blackout := 0.0
var _depth_hist := PackedFloat32Array()
var _radio_set: Node3D
var _radio_hand: Node3D
var _deck_bag: Node3D
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
## actually arrives. Its deployment motion and small vertical settling now
## live in BoatElectronicsController; this file supplies the player-relative
## target angles.
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
var _radar_scan: Node3D
## The handset plays its traffic when lifted, from the top, once — hang it up
## and lift again for another pass. The speaker IS the handset, so the voice
## rides it to your ear.
var _radio_snd: AudioStreamPlayer3D
var _electronics_controller: RefCounted
var _switchboard_visuals: RefCounted
var _navigation_displays: RefCounted
var _access_controller: RefCounted
var _engine_controller: RefCounted
var _buoyancy_controller: RefCounted
var _grounding_controller: RefCounted
var _hydrodynamics_controller: RefCounted
var _radio_handset_controller: RefCounted
var _switchboard_controller: RefCounted
var _windlass_controller: RefCounted
var _lighting_controller: RefCounted
var _sounder_pivot: Node3D
var _sounder_case: MeshInstance3D
var _sounder_home := Vector3.ZERO
var sounder_pull := 0.0
## 0 = stowed against the bulkhead, 1 = tipped out toward the helmsman. The
## hand sets the target; the pivot eases there like a thing with mass.
var radar_pull := 0.0
var _sounder_screen: MeshInstance3D
const RADIO_CRADLE := Vector3(1.49, 3.94, 0.55)
var _chart_mat: ShaderMaterial
var _chart_pin: Node3D
var chart_engaged := false
var _boat_audio: BoatAudioController
var _t := 0.0
var _flicker := 1.0
## --drift-test instrumentation: per-source yaw-torque integrals, so a
## boat that turns by itself can be charged to the term actually doing it.
var drift_dbg := false
var drift_sums := {"align": 0.0, "rudder": 0.0, "damp": 0.0, "ground": 0.0}


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
	_buoyancy_controller = BoatBuoyancyControllerScript.new()
	_buoyancy_controller.setup(PROBES.size())
	_grounding_controller = BoatGroundingControllerScript.new()
	_hydrodynamics_controller = BoatHydrodynamicsControllerScript.new()
	_radio_handset_controller = BoatRadioHandsetControllerScript.new()
	_switchboard_controller = BoatSwitchboardControllerScript.new()
	_windlass_controller = BoatWindlassControllerScript.new()
	_lighting_controller = BoatLightingControllerScript.new()
	_build_collision()
	_weather_effects = BoatWeatherEffectsScript.new()
	add_child(_weather_effects)
	_weather_effects.setup(self)
	_mesh_batcher = BoatMeshBatcherScript.new(self)
	_switchboard_visuals = BoatSwitchboardVisualBuilderScript.new()
	_switchboard_visuals.setup(self, _electrical, _box, _cyl, _mat)
	_switch_levers = _switchboard_visuals.get("switch_levers") as Dictionary
	_switch_leds = _switchboard_visuals.get("switch_leds") as Dictionary
	_build_visuals()
	# The quick-access bag is worn on the player, not left as furniture.  It
	# remains a child for ownership/save-state, while its own top-level transform
	# follows the camera during the shoulder-to-lap motion.
	_deck_bag = DeckBagScript.new()
	add_child(_deck_bag)
	_dress_steel()
	_build_motor()
	_engine_room = (load("res://scripts/engine_room.gd") as GDScript).new()
	add_child(_engine_room)
	var vhf: Node3D = (load("res://scripts/vhf_antenna.gd") as GDScript).new()
	# Starboard-aft corner of the wheelhouse roof — where a VHF actually lives.
	vhf.position = Vector3(1.58, 5.52, 3.78)
	add_child(vhf)
	_build_radar_scanner()
	_electronics_controller = BoatElectronicsControllerScript.new()
	_electronics_controller.setup(_radar_ping, _radio_snd, _radar_scan,
			_radar_arm, _radar_pivot, _sounder_arm, _sounder_pivot, _radar_home)
	_navigation_displays = BoatNavigationDisplayControllerScript.new()
	_navigation_displays.setup(_sounder_mat, _chart_mat, _radar_mat,
			_chart_pin, _depth_hist)
	_access_controller = BoatAccessControllerScript.new()
	_access_controller.setup(_door_fwd, _door_aft, _door_eng, _door_wh,
			_fuse_lid, _locker_door, _gear_mask, _gear_tank)
	_flush_mesh_batch()
	_weather_effects.build_rain_field(_glass_mat, _front_glass_mat)
	_boat_audio = BoatAudioControllerScript.new()
	_boat_audio.setup(self)
	_build_water_fx()
	_engine_controller = BoatEngineControllerScript.new()
	_engine_controller.setup(self, _thr_lever, _ign_key, _ign_led,
			_engine_room, _screw, _motor_pivot, _wheel, _prop, _prop_bubbles,
			_prop_bubble_pm)
	# Roughly m(L^2+H^2)/12 about each axis: pitch, yaw, roll. Roll is left
	# heavier than the box formula so she rolls slow and deep like timber.
	inertia = Vector3(46000.0, 52000.0, 23500.0)


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
		# scupper streaks running DOWN from the deck edge — same stations as
		# the holes in the bulwark, or the rust has no mouth to come from.
		[Vector3(0.012, 0.55, 0.16), Vector3(-2.052, 0.18, -2.60), rust],
		[Vector3(0.012, 0.48, 0.14), Vector3(-2.052, 0.14, 1.80), rust_dark],
		[Vector3(0.012, 0.60, 0.18), Vector3(2.052, 0.12, -0.50), rust],
		[Vector3(0.012, 0.40, 0.13), Vector3(2.052, 0.20, 4.20), rust_dark],
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

	# The mast mesh is built later, but its collider must be a direct child of
	# this physics body. Match the visible mast's height, position and 3° rake.
	var mast := CollisionShape3D.new()
	var mast_shape := CylinderShape3D.new()
	mast_shape.radius = 0.11
	mast_shape.height = 5.20
	mast.shape = mast_shape
	mast.position = Vector3(0.0, 3.10, -2.35)
	mast.rotation_degrees = Vector3(0.0, 0.0, 3.0)
	add_child(mast)


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
	AABB(Vector3(-1.88, 2.91, -0.56), Vector3(0.12, 0.75, 5.74)),
	AABB(Vector3(1.76, 2.91, -0.56), Vector3(0.12, 0.75, 5.74)),
	AABB(Vector3(-1.88, 2.91, 5.00), Vector3(3.76, 0.75, 0.12)),
	AABB(Vector3(-1.88, 2.91, -0.38), Vector3(3.76, 0.75, 0.12)),
	# Stairwell coaming, inboard side. Kerb only. Base at 3.05 so someone on
	# the stairs still passes under it; at deck level it used to catch them.
	# Starts at z 1.55 so the first two treads stay the way in.
	AABB(Vector3(-0.49, 3.05, 1.55), Vector3(0.10, 0.26, 2.40)),
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
	AABB(Vector3(-1.70, 0.68, 0.58), Vector3(0.48, 1.74, 0.52)),    # dive locker, under stair
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
const SEA_LADDER_BOT := -0.58
const SEA_LADDER_RUNGS := 5
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
## Where you stand to work the telegraph alone.
const TELEGRAPH_STAND := Vector3(0.58, 2.91, 0.70)
## Everything aboard you can put a hand on. The camera looks for the nearest of
## these in front of you and offers it on E.
const INTERACT: Array = [
	{"id": "helm", "pos": Vector3(0.0, 3.75, 0.30), "r": 0.36, "name": "Helm"},
	{"id": "telegraph", "pos": Vector3(0.70, 3.78, 0.02), "r": 0.18, "name": "Throttle"},
	{"id": "ignition", "pos": Vector3(0.42, 3.68, 0.24), "r": 0.22, "name": "Ignition"},
	{"id": "windlass", "pos": Vector3(0.0, 1.00, -3.35), "r": 0.55, "name": "Windlass (anchor)"},
	# Switch console between the radar and the chart table. Walk up, throw.
	{"id": "door_fwd", "pos": Vector3(0.47, 1.58, -0.44), "r": 0.30, "name": "Fore hatch"},
	{"id": "door_aft", "pos": Vector3(0.47, 1.58, 4.72), "r": 0.30, "name": "Aft hatch"},
	{"id": "door_wh", "pos": Vector3(-0.43, 3.87, 4.08), "r": 0.30, "name": "Wheelhouse hatch"},
	# Flood and wiper on the dash. The other four live in the well with the
	# cartridges — lid down, they are not a thing you can throw.
	{"id": "fusebox", "pos": Vector3(1.14, 3.75, 1.52), "r": 0.10, "name": "Fuse well"},
	{"id": "sw_cabin", "pos": Vector3(1.090, 3.73, 1.235), "r": 0.038, "name": "Cabin lights"},
	{"id": "sw_helm", "pos": Vector3(1.090, 3.73, 1.305), "r": 0.038, "name": "Wheelhouse lights"},
	{"id": "sw_beacon", "pos": Vector3(1.090, 3.73, 1.375), "r": 0.038, "name": "Nav lights"},
	{"id": "sw_flood", "pos": Vector3(-0.56, 3.68, 0.02), "r": 0.048, "name": "Floodlights"},
	{"id": "sw_wiper", "pos": Vector3(-0.76, 3.68, 0.02), "r": 0.048, "name": "Wiper"},
	{"id": "sw_anchor", "pos": Vector3(1.090, 3.73, 1.445), "r": 0.038, "name": "Windlass"},
	{"id": "fu_cabin", "pos": Vector3(1.195, 3.678, 1.235), "r": 0.026, "name": "Cabin fuse"},
	{"id": "fu_helm", "pos": Vector3(1.195, 3.678, 1.305), "r": 0.026, "name": "Wheelhouse fuse"},
	{"id": "fu_beacon", "pos": Vector3(1.195, 3.678, 1.375), "r": 0.026, "name": "Nav fuse"},
	{"id": "fu_flood", "pos": Vector3(1.100, 3.678, 1.500), "r": 0.026, "name": "Flood fuse"},
	{"id": "fu_wiper", "pos": Vector3(1.180, 3.678, 1.500), "r": 0.026, "name": "Wiper fuse"},
	{"id": "fu_anchor", "pos": Vector3(1.195, 3.678, 1.445), "r": 0.026, "name": "Windlass fuse"},
	{"id": "chart", "pos": Vector3(1.30, 3.72, 2.88), "r": 0.20, "name": "Chart table"},
	{"id": "radio", "pos": Vector3(1.49, 3.94, 0.55), "r": 0.20, "name": "Radio"},
	{"id": "stove", "pos": Vector3(1.28, 1.05, 4.10), "r": 0.30, "name": "Heater"},
	{"id": "sea_ladder", "pos": Vector3(0.72, 0.80, 5.80), "r": 0.42, "name": "Boarding ladder"},
	{"id": "locker", "pos": Vector3(-1.22, 1.52, 0.84), "r": 0.34, "name": "Dive locker"},
	{"id": "divegear", "pos": Vector3(-1.34, 1.76, 0.84), "r": 0.30, "name": "Dive gear"},
	{"id": "door_eng", "pos": Vector3(-0.54, 1.16, 2.65), "r": 0.22, "name": "Engine hatch"},
	{"id": "radar", "pos": Vector3(1.18, 4.28, 0.10), "r": 0.28, "name": "Radar"},
	{"id": "sounder", "pos": Vector3(1.15, 4.02, 0.08), "r": 0.22, "name": "Sounder"},
]


func radio_handset() -> Node3D:
	return _radio_hand


func deck_bag_node() -> Node3D:
	return _deck_bag


func update_deck_bag_pose(delta: float, camera: Camera3D, amount: float) -> void:
	if _deck_bag != null and _deck_bag.has_method("update_camera_pose"):
		_deck_bag.call("update_camera_pose", delta, camera, amount)


func rifle_obstruction_fraction(from_world: Vector3, to_world: Vector3,
		radius := 0.055) -> float:
	## Thick segment against the same boat-local solids that stop the player.
	## Furniture and moving doors are included; floor/deckhead get thin slabs so
	## looking sharply up or down cannot put the long gun through them either.
	var from_local := to_local(from_world)
	var to_local_point := to_local(to_world)
	var solids: Array = BLOCKERS + door_blockers + aim_blockers
	for floor_data in FLOORS:
		var rect: Rect2 = floor_data[0]
		var y: float = floor_data[1]
		solids.append(AABB(Vector3(rect.position.x, y - 0.055,
				rect.position.y), Vector3(rect.size.x, 0.055, rect.size.y)))
	for ceiling_data in CEILINGS:
		var rect: Rect2 = ceiling_data[0]
		var y: float = ceiling_data[1]
		solids.append(AABB(Vector3(rect.position.x, y,
				rect.position.y), Vector3(rect.size.x, 0.065, rect.size.y)))
	var fraction := 1.0
	for solid: AABB in solids:
		fraction = minf(fraction, _segment_aabb_entry_fraction(from_local,
				to_local_point, solid.grow(radius)))
	return fraction


func _segment_aabb_entry_fraction(from: Vector3, to: Vector3, box: AABB) -> float:
	var direction := to - from
	var enter := 0.0
	var leave := 1.0
	for axis in 3:
		var origin: float = from[axis]
		var delta: float = direction[axis]
		var minimum: float = box.position[axis]
		var maximum: float = box.end[axis]
		if absf(delta) < 0.000001:
			if origin < minimum or origin > maximum:
				return 1.0
			continue
		var first := (minimum - origin) / delta
		var last := (maximum - origin) / delta
		if first > last:
			var swap := first
			first = last
			last = swap
		enter = maxf(enter, first)
		leave = minf(leave, last)
		if enter > leave:
			return 1.0
	return clampf(enter, 0.0, 1.0)


func helm_wheel() -> Node3D:
	return _wheel


func throttle_lever() -> Node3D:
	return _thr_lever


func ignition_key() -> Node3D:
	return _ign_key


func stove_switch() -> Node3D:
	return _stove_switch


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


func door_latch_local(id: String) -> Vector3:
	var p := Vector3.ZERO
	if camera_rig != null:
		var w: Variant = camera_rig.get("_walker")
		if w != null:
			var wp: Variant = w.get("pos")
			if wp is Vector3:
				p = wp
	return _interaction_locator.door_latch_local(id, p, CABIN_LATCH, WH_LATCH,
			DOOR_Z0, DOOR_Z1, WH_DOOR_Z)


func interact_pos(id: String, fallback: Vector3) -> Vector3:
	var player_position := Vector3.ZERO
	if camera_rig != null:
		var walker: Variant = camera_rig.get("_walker")
		if walker != null and walker.get("pos") is Vector3:
			player_position = walker.get("pos")
	var doors := {
		"door_fwd": _door_fwd, "door_aft": _door_aft, "door_wh": _door_wh,
	}
	return _interaction_locator.interaction_position(id, fallback,
			global_transform.affine_inverse(), player_position, _fuse_lid,
			_fuse_latch_local, _stove_switch, _switch_levers, _fuse_bodies,
			doors, _door_eng, CABIN_LATCH, WH_LATCH, DOOR_Z0, DOOR_Z1,
			WH_DOOR_Z)


func locker_door() -> Node3D:
	return _locker_door


func gear_wear_t() -> float:
	## 0 while it hangs in the locker, 1 while it is on your face. Everything
	## between is the animation, and the overlay reads it directly.
	return _gear_t


func fuse_lid() -> Node3D:
	return _fuse_lid


func fuse_latch_local() -> Vector3:
	## Single source of truth shared by aiming and the hand grip. The lid is
	## procedural, so duplicating this dimension in GripMap will drift again.
	return _fuse_latch_local


func fuse_body(id: String) -> Node3D:
	return _fuse_bodies.get(id) as Node3D


func circuit_live(id: String) -> bool:
	## Toggle up AND the cartridge still in its clips. A pulled fuse is an
	## open circuit — the lever can sit on and nothing downstream answers.
	if not _fuse_seated(id):
		return false
	return switch_state(id)


func _fuse_seated(sw_id: String) -> bool:
	return _electrical.is_seated(StringName(sw_id))


func switch_in_well(id: String) -> bool:
	return _electrical.switch_is_in_well(StringName(id))


func fuse_seated(id: String) -> bool:
	return _electrical.is_seated(StringName(id))


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
	return BoatVisuals.material(albedo, rough, metal)


func _wet_wood(color: Color, rough: float) -> ShaderMaterial:
	## Hull planking that darkens and goes glossy below the waterline. The
	## waterline is pushed every frame in _update_wetness().
	var m := BoatVisuals.wet_hull_material(color, rough)
	_hull_mats.append(m)
	return m


func _build_visuals() -> void:
	var hull := _wet_wood(Color(0.130, 0.140, 0.148), 0.60)
	var keel := _wet_wood(Color(0.082, 0.088, 0.094), 0.55)
	var boot := _wet_wood(Color(0.300, 0.092, 0.058), 0.82)
	var deck := _mat(Color(0.140, 0.135, 0.125), 0.84, 0.30)
	var paint := _mat(Color(0.370, 0.395, 0.372), 0.74, 0.10)
	var paint_dark := _mat(Color(0.070, 0.075, 0.080), 0.66, 0.55)
	var trim := _mat(Color(0.158, 0.144, 0.124), 0.62, 0.50)
	var metal := _mat(Color(0.105, 0.105, 0.115), 0.50, 0.65)
	var dark := _mat(Color(0.045, 0.040, 0.036), 0.92)
	BoatHullVisualBuilderScript.new().build(keel, hull, boot, deck,
			paint_dark, trim, metal, SEA_LADDER_X, _box, _cyl, _prism,
			_build_nameboard, _side_bulwark)
	var cabin: Dictionary = BoatCabinVisualBuilderScript.new().build(
			self, deck, paint, paint_dark, trim, metal, dark, CABIN_LATCH,
			_box, _cyl, _mat, _glass, _hatch_coaming, _weathertight_leaf,
			_build_dive_locker, _build_stove_heat, _build_cabin_lived)
	_glass_mat = cabin["glass_material"] as ShaderMaterial
	_lit_window = cabin["lit_window"] as StandardMaterial3D
	_cabin_lamp = cabin["cabin_lamp"] as OmniLight3D
	_stove_reflector = cabin["stove_reflector"] as StandardMaterial3D
	_stove_ember = cabin["stove_ember"] as StandardMaterial3D
	_stove_switch = cabin["stove_switch"] as Node3D
	_stove_lamp = cabin["stove_lamp"] as OmniLight3D
	_stove_fill = cabin["stove_fill"] as OmniLight3D
	_door_fwd = cabin["door_forward"] as Node3D
	_door_aft = cabin["door_aft"] as Node3D
	var gasket := cabin["gasket"] as Material
	var batten := cabin["batten"] as Material
	var plate := cabin["plate"] as Material
	var wheelhouse: Dictionary = BoatWheelhouseVisualBuilderScript.new().build(
			self, paint, paint_dark, trim, metal, _glass_mat, gasket, batten,
			plate, WH_LATCH, _box, _cyl, _mat, _glass, _weathertight_leaf,
			_hatch_coaming, _build_wiper, _build_chart_table,
			_build_electronics, _build_switchboard, _build_helm, _build_console)
	_front_glass_mat = wheelhouse["front_glass"] as ShaderMaterial
	_door_wh = wheelhouse["wheelhouse_door"] as Node3D
	_helm_glow = wheelhouse["helm_glow"] as StandardMaterial3D
	_helm_lamp = wheelhouse["helm_lamp"] as OmniLight3D
	var mast: Dictionary = BoatMastVisualBuilderScript.new().build(
			self, trim, metal, _box, _cyl, _mat, _stay, _rope,
			_nav_lantern, _build_deck_gear)
	_beacon_mat = mast["beacon_material"] as StandardMaterial3D
	_beacon = mast["beacon"] as OmniLight3D
	var companionway: Dictionary = BoatCompanionwayVisualBuilderScript.new().build(
			self, trim, metal, _box, _cyl, _mat, _box_node, _trap_prism, _dog)
	_door_eng = companionway["engine_door"] as Node3D
	_flood_lens_mat = companionway["flood_lens_material"] as StandardMaterial3D
	_flood_beam_mat = companionway["flood_beam_material"] as ShaderMaterial
	_floods.clear()
	for floodlight: SpotLight3D in companionway["floodlights"]:
		_floods.append(floodlight)


func _build_console(trim: Material, metal: Material) -> void:
	var panel_state: Dictionary = BoatConsoleVisualBuilderScript.new().build(
			self, trim, metal)
	var bronze := panel_state["bronze"] as Material
	var face := panel_state["face"] as Node3D
	_dial_face_mat = panel_state["dial_face"] as ShaderMaterial
	_dial_ink = panel_state["dial_ink"] as StandardMaterial3D
	_needles.clear()
	for needle: Node3D in panel_state["needles"]:
		_needles.append(needle)
	_compass_card = panel_state["compass_card"] as Node3D
	var controls: Dictionary = BoatHelmControlsVisualBuilderScript.new().build(
			self, face, trim, metal, bronze, _box, _cyl, _mat,
			_build_toggle, _console_label)
	_thr_lever = controls["throttle_lever"] as Node3D
	_pwr_segs.clear()
	for segment: StandardMaterial3D in controls["power_segments"]:
		_pwr_segs.append(segment)
	_pwr_needle = controls["power_needle"] as Node3D
	_ign_key = controls["ignition_key"] as Node3D
	_ign_led = controls["ignition_led"] as StandardMaterial3D

	var anchor_state: Dictionary = BoatAnchorVisualBuilderScript.new().build(
			self, metal, bronze, _box, _cyl, _mat)
	_chain_visual = anchor_state["chain_visual"] as Node3D
	_windlass = anchor_state["windlass"] as Node3D
func _update_gauges(delta: float) -> void:
	_console_instruments.update_gauges(delta, global_basis, linear_velocity,
			global_position, ocean, tackle, _needles, _compass_card)


func _build_switchboard(trim: Material, metal: Material) -> void:
	var state: Dictionary = _switchboard_visuals.build_switchboard(trim, metal)
	_fuse_lid = state["fuse_lid"] as Node3D
	_fuse_latch_local = state["fuse_latch_local"] as Vector3
	_fuse_bodies = state["fuse_bodies"] as Dictionary
	_switch_levers = state["switch_levers"] as Dictionary
	_switch_leds = state["switch_leds"] as Dictionary
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


func _build_toggle(id: String, pos: Vector3, caption: String, bronze: Material,
		parent: Node3D = null, compact := false) -> void:
	_switchboard_visuals.build_toggle(id, pos, caption, bronze, parent, compact)
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
	## One switch, one circuit. Hand use arrives from action_contact after the
	## fingers land; number-key shortcuts reach the same fields without a hand.
	# Cartridges, and the four house toggles, live under the lid.
	if id.begins_with("fu_") or switch_in_well(id):
		if by_hand and not fusebox_open:
			return
	if id.begins_with("fu_"):
		_electrical.toggle_fuse(id)
		_boat_audio.play_hinge(Vector3(1.14, 3.68, 1.36))
		return
	match id:
		"stove": stove_on = not stove_on
		"fusebox":
			fusebox_open = not fusebox_open
			_boat_audio.play_hinge(Vector3(1.14, 3.74, 1.36))
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
			_boat_audio.play_hinge(Vector3(0.0, 1.30, DOOR_Z0))
		"door_aft":
			door_aft_open = not door_aft_open
			_boat_audio.play_hinge(Vector3(0.0, 1.30, DOOR_Z1))
		"door_wh":
			door_wh_open = not door_wh_open
			_boat_audio.play_hinge(Vector3(0.0, 3.55, WH_DOOR_Z))
		"door_eng":
			door_eng_open = not door_eng_open
			_boat_audio.play_hinge(Vector3(-0.515, 1.24, 2.15))
			if _engine_room != null:
				_engine_room.call("set_door", door_eng_open)
		"locker":
			locker_open = not locker_open
			_boat_audio.play_hinge(Vector3(-1.30, 1.50, 0.36))
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
	var pm := PrismMesh.new()
	pm.left_to_right = 0.5
	pm.size = Vector3(w, depth, h)
	# PrismMesh points +Y; lying it on its back points the apex forward (-Z)
	# and turns the extrusion into height.
	_emit_mesh(pm, pos, Vector3(-90.0, 0.0, 0.0), mat, null)


func _box_node(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	## _box, but returned instead of parented — for pieces that hang on pivots.
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	return mi


func _trap_prism(thick: float, y0: float, y_hi: float, y_lo: float, length: float,
		mat: Material) -> MeshInstance3D:
	## Vertical trapezoid of thickness `thick`. Hinge edge at z=0 from y0 to
	## y_hi; free edge at z=length from y0 to y_lo. Both faces, so it reads as
	## a door from the cabin and from the well.
	var hx := thick * 0.5
	var v: Array[Vector3] = [
		Vector3(-hx, y0, 0.0), Vector3(-hx, y_hi, 0.0),
		Vector3(-hx, y_lo, length), Vector3(-hx, y0, length),
		Vector3(hx, y0, 0.0), Vector3(hx, y_hi, 0.0),
		Vector3(hx, y_lo, length), Vector3(hx, y0, length),
	]
	var faces: Array = [
		[0, 3, 2, 1], [4, 5, 6, 7],
		[0, 1, 5, 4], [3, 7, 6, 2],
		[1, 2, 6, 5], [0, 4, 7, 3],
	]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f: Array in faces:
		var n: Vector3 = (v[f[1]] - v[f[0]]).cross(v[f[2]] - v[f[0]])
		if n.length_squared() < 1e-10:
			continue
		n = n.normalized()
		for tri: Array in [[0, 1, 2], [0, 2, 3]]:
			for k: int in tri:
				st.set_normal(n)
				st.add_vertex(v[f[k]])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	return mi


func _build_chart_table(trim: Material, metal: Material) -> void:
	var state: Dictionary = BoatChartTableVisualBuilderScript.new().build(
			self, trim, metal, _helm_glow, _box, _cyl, _mat)
	_chart_mat = state["chart_material"] as ShaderMaterial
	_chart_pin = state["chart_pin"] as Node3D
	_chart_lamp = state["chart_lamp"] as SpotLight3D


func _build_electronics(trim: Material, metal: Material) -> void:
	var state: Dictionary = BoatElectronicsVisualBuilderScript.new().build(
			self, trim, metal, _box, _cyl, _mat)
	_sounder_arm = state["sounder_arm"] as Node3D
	_sounder_home = state["sounder_home"] as Vector3
	_sounder_pivot = state["sounder_pivot"] as Node3D
	_sounder_case = state["sounder_case"] as MeshInstance3D
	_sounder_mat = state["sounder_mat"] as ShaderMaterial
	_sounder_screen = state["sounder_screen"] as MeshInstance3D
	_depth_hist = state["depth_hist"] as PackedFloat32Array
	_radar_arm = state["radar_arm"] as Node3D
	_radar_home = state["radar_home"] as Vector3
	_radar_pivot = state["radar_pivot"] as Node3D
	_radar_case = state["radar_case"] as MeshInstance3D
	_radar_mat = state["radar_mat"] as ShaderMaterial
	_radar_screen = state["radar_screen"] as MeshInstance3D
	_radar_ping = state["radar_ping"] as AudioStreamPlayer3D
	_radio_set = state["radio_set"] as Node3D
	_radio_hand = state["radio_hand"] as Node3D
	_radio_snd = state["radio_snd"] as AudioStreamPlayer3D
	_cord.clear()
	for segment: MeshInstance3D in state["cord"]:
		_cord.append(segment)
func _update_radio(delta: float) -> void:
	radio_held = _radio_handset_controller.update(self, _radio_hand, _cord,
			camera_rig, radio_held, radio_pose_locked, delta)


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


func _build_wiper(front_z: float) -> void:
	## Outside the front pane, same pivot the shader uses: bottom centre,
	## local y = -0.72 on a pane centred at 4.25. The blade rides a few
	## millimetres off the glass so it never z-fights the pane.
	var steel := _mat(Color(0.38, 0.39, 0.40), 0.22, 0.78)
	var rubber := _mat(Color(0.07, 0.07, 0.08), 0.88, 0.0)
	var pivot_y := 4.25 - 0.72
	_box(Vector3(0.11, 0.08, 0.09), Vector3(0.0, 3.36, front_z - 0.07), Vector3.ZERO, steel)
	_cyl(0.022, 0.022, 0.07, Vector3(0.0, pivot_y, front_z - 0.04),
			Vector3(90.0, 0.0, 0.0), steel)
	_wiper_arm = Node3D.new()
	_wiper_arm.position = Vector3(0.0, pivot_y, front_z - 0.058)
	_wiper_arm.rotation.z = 1.08
	add_child(_wiper_arm)
	var arm := _box_node(Vector3(0.022, 1.02, 0.012), Vector3(0.0, 0.54, 0.0), steel)
	arm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wiper_arm.add_child(arm)
	var spine := _box_node(Vector3(0.014, 0.94, 0.008), Vector3(0.0, 0.56, 0.014), steel)
	spine.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wiper_arm.add_child(spine)
	var blade := _box_node(Vector3(0.010, 0.92, 0.007), Vector3(0.0, 0.56, 0.022), rubber)
	blade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wiper_arm.add_child(blade)


func _build_helm(trim: Material, metal: Material) -> void:
	_wheel = BoatHelmVisualBuilderScript.new().build(
			self, trim, metal, _cyl, _mat)


func _emit_mesh(mesh: Mesh, pos: Vector3, rot_deg: Vector3, mat: Material,
		parent: Node3D, shadows := true) -> void:
	_mesh_batcher.emit(mesh, pos, rot_deg, mat, parent, shadows, _hull_mats)


func _flush_mesh_batch() -> void:
	_mesh_batcher.flush()


func _cyl(r_bot: float, r_top: float, h: float, pos: Vector3, rot_deg: Vector3,
		mat: Material, parent: Node3D = null) -> void:
	var m := CylinderMesh.new()
	m.bottom_radius = r_bot
	m.top_radius = r_top
	m.height = h
	m.radial_segments = 10
	m.rings = 1
	_emit_mesh(m, pos, rot_deg, mat, parent)


func _box(size: Vector3, pos: Vector3, rot_deg: Vector3, mat: Material, parent: Node3D = null) -> void:
	var bm := BoxMesh.new()
	bm.size = size
	_emit_mesh(bm, pos, rot_deg, mat, parent)


func _dog(piv: Node3D, pos: Vector3, iron: Material, face := 1.0) -> void:
	## Butterfly dog: winged nut on a short stud. The thing you actually
	## turn on a weathertight hatch — not a house knob. Wings sit proud on
	## the weather face, so a bow hatch (face −1) does not hide them inboard.
	_cyl(0.012, 0.012, 0.048, pos, Vector3(90.0, 0.0, 0.0), iron, piv)
	var wing := pos + Vector3(0.0, 0.0, face * 0.018)
	_box(Vector3(0.095, 0.018, 0.022), wing, Vector3.ZERO, iron, piv)
	_box(Vector3(0.018, 0.095, 0.022), wing, Vector3.ZERO, iron, piv)


func _hatch_coaming(x: float, z: float, y0: float, h: float, face: float,
		metal: Material, paint: Material, opening_w := 1.10) -> void:
	## Frame standing proud of the bulkhead on the deck side, so the hatch
	## is a thing you walk up to. House doors sit in the wall; these sit on it.
	## Uprights land ON the jambs: inner faces match `opening_w`, not a
	## narrower hole that left a strip of daylight beside the leaf.
	var y_mid := y0 + h * 0.5
	var sill := y0 + 0.07
	var stile := opening_w * 0.5 + 0.06
	var frame_w := opening_w + 0.24
	_box(Vector3(frame_w, 0.16, 0.10), Vector3(x, sill, z), Vector3.ZERO, paint)
	_box(Vector3(0.12, h + 0.08, 0.10), Vector3(x - stile, y_mid, z), Vector3.ZERO, paint)
	_box(Vector3(0.12, h + 0.08, 0.10), Vector3(x + stile, y_mid, z), Vector3.ZERO, paint)
	_box(Vector3(frame_w + 0.04, 0.12, 0.10), Vector3(x, y0 + h + 0.04, z), Vector3.ZERO, paint)
	# Iron corners, so the frame reads as a hatch even at a glance.
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.05, 0.05, 0.12), Vector3(x + sx * stile, sill, z + face * 0.02),
				Vector3.ZERO, metal)
		_box(Vector3(0.05, 0.05, 0.12), Vector3(x + sx * stile, y0 + h, z + face * 0.02),
				Vector3.ZERO, metal)


func _weathertight_leaf(piv: Node3D, w: float, h: float, cx: float, cy: float,
		latch_x: float, hinge_left: bool, face: float,
		plate: Material, batten: Material, gasket: Material, iron: Material,
		port := true) -> void:
	## Steel hatch: thick plate, washboard battens, rubber gasket, strap
	## hinges, dogs, drop-bar. All of the working iron sits on the WEATHER
	## face — the deck side — so you can see from outside where it opens.
	var th := 0.070
	var bronze := _mat(Color(0.42, 0.30, 0.14), 0.38, 0.78)
	_box(Vector3(w, h, th), Vector3(cx, cy, 0.0), Vector3.ZERO, plate, piv)
	var n := 5
	var bw := w / float(n)
	var x0: float = cx - w * 0.5
	for i in n:
		if i % 2 != 0:
			continue
		var px: float = x0 + (float(i) + 0.5) * bw
		_box(Vector3(bw - 0.010, h - 0.05, th + 0.008),
				Vector3(px, cy, face * 0.006), Vector3.ZERO, batten, piv)
	for by_off in [-0.36, 0.0, 0.36]:
		_box(Vector3(w - 0.05, 0.058, th + 0.014),
				Vector3(cx, cy + by_off * h * 0.5, face * 0.010), Vector3.ZERO, batten, piv)
	var gth := 0.014
	_box(Vector3(w + 0.018, gth, th + 0.012), Vector3(cx, cy + h * 0.5, 0.0),
			Vector3.ZERO, gasket, piv)
	_box(Vector3(w + 0.018, gth, th + 0.012), Vector3(cx, cy - h * 0.5, 0.0),
			Vector3.ZERO, gasket, piv)
	_box(Vector3(gth, h, th + 0.012), Vector3(x0, cy, 0.0), Vector3.ZERO, gasket, piv)
	_box(Vector3(gth, h, th + 0.012), Vector3(x0 + w, cy, 0.0), Vector3.ZERO, gasket, piv)
	var hx: float = (x0 + 0.15) if hinge_left else (x0 + w - 0.15)
	var hz := face * (th * 0.5 + 0.016)
	for hy_off in [-0.34, 0.0, 0.34]:
		_box(Vector3(0.34, 0.058, 0.024),
				Vector3(hx, cy + hy_off * h * 0.5, hz),
				Vector3.ZERO, iron, piv)
		var pin_x: float = hx + (-0.15 if hinge_left else 0.15)
		_cyl(0.018, 0.018, 0.072, Vector3(pin_x, cy + hy_off * h * 0.5, 0.0),
				Vector3(0.0, 0.0, 90.0), iron, piv)
	# Dogs and the drop-bar on the deck face.
	var wz := face * (th * 0.5 + 0.022)
	for yo in [-0.38, -0.14, 0.14, 0.38]:
		_dog(piv, Vector3(latch_x, cy + yo * h * 0.5, wz), iron, face)
	# Vertical grab + throw-lever: the thing your eye goes to from the deck.
	_cyl(0.018, 0.018, 0.46, Vector3(latch_x, cy, wz + face * 0.028),
			Vector3.ZERO, bronze, piv)
	_box(Vector3(0.046, 0.040, 0.055), Vector3(latch_x, cy - 0.22, wz + face * 0.012),
			Vector3.ZERO, bronze, piv)
	_box(Vector3(0.046, 0.040, 0.055), Vector3(latch_x, cy + 0.22, wz + face * 0.012),
			Vector3.ZERO, bronze, piv)
	_box(Vector3(0.24, 0.036, 0.042), Vector3(latch_x, cy, wz + face * 0.030),
			Vector3.ZERO, bronze, piv)
	_box(Vector3(0.050, 0.090, 0.048), Vector3(latch_x, cy + 0.055, wz + face * 0.042),
			Vector3.ZERO, bronze, piv)
	# Cabin face. This used to be a blank plate — from inside there was
	# nothing to take hold of. Same bronze lever, proud of the inboard side.
	var iz := -face * (th * 0.5 + 0.026)
	var inward: float = -1.0 if hinge_left else 1.0
	_box(Vector3(0.11, 0.30, 0.018), Vector3(latch_x, cy, iz + face * 0.004),
			Vector3.ZERO, iron, piv)
	_cyl(0.016, 0.016, 0.36, Vector3(latch_x, cy, iz - face * 0.016),
			Vector3.ZERO, bronze, piv)
	_box(Vector3(0.052, 0.038, 0.046), Vector3(latch_x, cy - 0.17, iz - face * 0.008),
			Vector3.ZERO, bronze, piv)
	_box(Vector3(0.052, 0.038, 0.046), Vector3(latch_x, cy + 0.17, iz - face * 0.008),
			Vector3.ZERO, bronze, piv)
	_box(Vector3(0.20, 0.034, 0.040),
			Vector3(latch_x + inward * 0.02, cy, iz - face * 0.022),
			Vector3.ZERO, bronze, piv)
	_cyl(0.024, 0.024, 0.052,
			Vector3(latch_x + inward * 0.11, cy, iz - face * 0.026),
			Vector3(0.0, 0.0, 90.0), bronze, piv)
	if port:
		var pz := face * (th * 0.5 + 0.010)
		_cyl(0.125, 0.125, 0.028, Vector3(cx - face * 0.02, cy + 0.28, pz),
				Vector3(90.0, 0.0, 0.0), bronze, piv)
		var glass := _mat(Color(0.10, 0.14, 0.16, 0.55), 0.12, 0.05)
		glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_cyl(0.092, 0.092, 0.012, Vector3(cx - face * 0.02, cy + 0.28, pz + face * 0.012),
				Vector3(90.0, 0.0, 0.0), glass, piv)


func _mast_pt(local: Vector3) -> Vector3:
	## Mast sits at (0, 3.10, -2.35) and leans three degrees to starboard.
	## Stays land on the boat, so their mast ends have to be in boat space.
	var a := deg_to_rad(3.0)
	var c := cos(a)
	var s := sin(a)
	return Vector3(0.0, 3.10, -2.35) + Vector3(
			local.x * c - local.y * s, local.x * s + local.y * c, local.z)


func _stay(a: Vector3, b: Vector3, r: float, mat: Material) -> void:
	var d := b - a
	var h := d.length()
	if h < 0.04:
		return
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = h
	m.radial_segments = 6
	m.rings = 1
	m.material = mat
	mi.mesh = m
	mi.position = (a + b) * 0.5
	var y := d / h
	var x := y.cross(Vector3.UP)
	if x.length_squared() < 1e-8:
		x = y.cross(Vector3.FORWARD)
	x = x.normalized()
	mi.basis = Basis(x, y, x.cross(y))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _rope(a: Vector3, b: Vector3, r: float, sag: float, mat: Material, n := 14) -> void:
	## A hanging line. `_stay` is a rod; this is a catenary in the boat's own
	## down, so it rides with her instead of hanging into the sea when she heels.
	if n < 2:
		return
	var prev := a
	for i in range(1, n + 1):
		var t := float(i) / float(n)
		var p: Vector3 = a.lerp(b, t)
		p.y -= 4.0 * t * (1.0 - t) * sag
		_stay(prev, p, r, mat)
		prev = p


func _nav_lantern(pos: Vector3, yaw_deg: float, col: Color) -> void:
	## Housing on the boat, lens facing the arc the light is allowed. Spot
	## default is -Z, so yaw 90 is port, -90 starboard, 180 the transom.
	var bronze := _mat(Color(0.32, 0.24, 0.12), 0.45, 0.7)
	var lens := StandardMaterial3D.new()
	lens.albedo_color = Color(col.r * 0.35, col.g * 0.35, col.b * 0.35)
	lens.emission_enabled = true
	lens.emission = col
	lens.emission_energy_multiplier = 0.0
	_nav_mats.append(lens)
	var rig := Node3D.new()
	rig.position = pos
	rig.rotation_degrees = Vector3(0.0, yaw_deg, 0.0)
	add_child(rig)
	_box(Vector3(0.07, 0.11, 0.08), Vector3(0.0, 0.0, 0.025), Vector3.ZERO, bronze, rig)
	_cyl(0.036, 0.036, 0.085, Vector3(0.0, 0.0, -0.018), Vector3(90.0, 0.0, 0.0), lens, rig)
	var sp := SpotLight3D.new()
	sp.position = Vector3(0.0, 0.0, -0.05)
	sp.light_color = col
	sp.light_energy = 0.0
	sp.spot_range = 24.0
	sp.spot_angle = 58.0
	sp.spot_attenuation = 0.7
	sp.shadow_enabled = false
	sp.light_volumetric_fog_energy = 5.0
	rig.add_child(sp)
	_nav_spots.append(sp)


func _side_bulwark(x: float, rot_z: float, mat: Material) -> void:
	## Continuous cap, lower course broken at the scuppers. The 5-degree lean
	## is the same flare the old single plank had.
	_box(Vector3(0.14, 0.32, 9.62), Vector3(x, 0.96, 0.89), Vector3(0.0, 0.0, rot_z), mat)
	var z0 := -3.92
	var z1 := 5.70
	var gap := 0.26
	var holes: Array[float] = [-2.60, -0.50, 1.80, 4.20]
	var cuts: Array[float] = [z0]
	for hz in holes:
		cuts.append(hz - gap * 0.5)
		cuts.append(hz + gap * 0.5)
	cuts.append(z1)
	var i := 0
	while i + 1 < cuts.size():
		var a: float = cuts[i]
		var b: float = cuts[i + 1]
		var L: float = b - a
		if L > 0.08:
			_box(Vector3(0.14, 0.20, L), Vector3(x, 0.70, (a + b) * 0.5),
					Vector3(0.0, 0.0, rot_z), mat)
		i += 2


func _warp_coil(pos: Vector3, mat: Material, rad: float) -> void:
	## Laid-up warp: three turns on the deck, not a torus floating at knee height.
	for t in 3:
		var mi := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = rad * 0.42
		torus.outer_radius = rad * (1.0 - float(t) * 0.08)
		torus.rings = 10
		torus.ring_segments = 16
		torus.material = mat
		mi.mesh = torus
		mi.position = pos + Vector3(0.0, (torus.outer_radius - torus.inner_radius) * 0.5
				+ float(t) * 0.020, 0.0)
		mi.rotation_degrees = Vector3(0.0, float(t) * 22.0, 0.0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


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
	var ignition: Dictionary = _engine_controller.turn_ignition(int(engine))
	engine = int(ignition["engine"]) as EngineState
	_crank_left = float(ignition["crank_left"])
	if bool(ignition["cranking"]):
		_boat_audio.begin_engine_crank()
	else:
		_boat_audio.stop_engine()


func _drop_mesh(r: float) -> SphereMesh:
	return BoatVisuals.water_drop_mesh(r)


func _spray_fade() -> GradientTexture1D:
	return BoatVisuals.spray_fade()


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

	# The visible half of prop wash below the waterline: an aerated plume that
	# rises and widens while the local compute field carries its pressure/foam on
	# the surface. Droplets alone made a working screw look like rain behind her.
	_prop_bubbles = GPUParticles3D.new()
	_prop_bubbles.amount = 130
	_prop_bubbles.lifetime = 1.75
	_prop_bubbles.fixed_fps = 30
	_prop_bubbles.local_coords = false
	_prop_bubbles.transform_align = GPUParticles3D.TRANSFORM_ALIGN_DISABLED
	_prop_bubbles.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_prop_bubbles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_prop_bubbles.position = Vector3(0.0, -0.66, 4.18)
	_prop_bubbles.visibility_aabb = AABB(Vector3(-7, -3, -3), Vector3(14, 9, 14))
	_prop_bubble_pm = ParticleProcessMaterial.new()
	_prop_bubble_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_prop_bubble_pm.emission_sphere_radius = 0.24
	_prop_bubble_pm.direction = Vector3(0.0, 0.34, 1.0)
	_prop_bubble_pm.spread = 34.0
	_prop_bubble_pm.initial_velocity_min = 0.45
	_prop_bubble_pm.initial_velocity_max = 1.9
	_prop_bubble_pm.gravity = Vector3(0.0, 1.55, 0.0)
	_prop_bubble_pm.damping_min = 0.18
	_prop_bubble_pm.damping_max = 0.75
	_prop_bubble_pm.scale_min = 0.20
	_prop_bubble_pm.scale_max = 0.85
	_prop_bubble_pm.color_ramp = _spray_fade()
	_prop_bubbles.process_material = _prop_bubble_pm
	_prop_bubbles.draw_pass_1 = _drop_mesh(0.016)
	_prop_bubbles.emitting = false
	add_child(_prop_bubbles)


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

	var engine_step: Dictionary = _engine_controller.step(
			delta, int(engine), _rpm, throttle, _crank_left)
	engine = int(engine_step["engine"]) as EngineState
	_rpm = float(engine_step["rpm"])
	_crank_left = float(engine_step["crank_left"])
	if bool(engine_step["caught"]):
		_boat_audio.engine_caught()

	# The wheel is heavy, the rudder is under water and the linkage is cable and
	# quadrant: hard over is a couple of seconds of winding, not a flick.
	_helm = lerpf(_helm, turn, 1.0 - exp(-delta / 1.45))
	var camera := get_viewport().get_camera_3d()
	var engine_openness := 1.0
	if camera != null:
		engine_openness = weather_openness(camera.global_position)
	if door_eng_open:
		engine_openness = maxf(engine_openness, 0.55)
	var engine_speed_ahead := absf((global_basis.inverse() * linear_velocity).z)
	_boat_audio.tick_engine(delta, engine == EngineState.RUNNING, _rpm, throttle,
			engine_speed_ahead, aground, engine_openness)
	if not _pwr_segs.is_empty():
		_console_instruments.update_power(_rpm, throttle,
				engine == EngineState.RUNNING, _blackout, _supply,
				_pwr_segs, _pwr_needle)

	if _electronics_controller != null:
		var electronics_pull: Vector2 = _electronics_controller.update(delta,
				radio_held, _blackout, _supply, radar_pull, sounder_pull,
				_radar_swing_t, _radar_face_t, _sounder_swing_t,
				_sounder_face_t, camera_rig)
		radar_pull = electronics_pull.x
		sounder_pull = electronics_pull.y
	_engine_controller.update_drivetrain(delta, int(engine), _rpm, throttle, _helm)
	# A dependency parse failure can abort `_ready()` before the audio controller
	# is built. Keep hot-reload/failed-load frames from turning that one root error
	# into an endless Nil-call flood.
	if _boat_audio != null:
		_boat_audio.tick_helm(delta, _wheel, helm_engaged)

	if _access_controller != null:
		_gear_t = _access_controller.update(delta, door_fwd_open, door_aft_open,
				door_eng_open, door_wh_open, fusebox_open, locker_open,
				gear_worn, door_blockers, aim_blockers)

	_switchboard_controller.update(delta, _switch_levers, _switch_leds,
			switch_state, circuit_live, _blackout, _supply, _stove_switch,
			stove_on, _fuse_bodies, _electrical, tackle)

	_windlass_controller.update(delta, _windlass, tackle, _chain_visual)

	_update_radio(delta)

	if _navigation_displays != null:
		var display_power: Vector2 = _navigation_displays.update(delta, weather,
				linear_velocity.y, ocean, global_position, global_basis,
				circuit_live("sw_helm"))
		_supply = display_power.x
		_blackout = display_power.y

	var forward_speed := -global_basis.z.dot(linear_velocity)
	_engine_controller.update_wash(delta, _rpm, forward_speed, ocean)


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
	_weather_effects.update_hull_wetness(delta, ocean, weather, global_position,
			linear_velocity, _hull_mats)


func _update_lantern(delta: float) -> void:
	var wiper_live := circuit_live("sw_wiper")
	_weather_effects.update_glass(delta, weather, wiper_live, _wiper_arm,
			_glass_mat, _front_glass_mat)
	_flicker = _lighting_controller.update(delta, _t, _flicker, _supply,
			_blackout, circuit_live("sw_cabin"), circuit_live("sw_helm"),
			circuit_live("sw_flood"), circuit_live("sw_beacon"), weather,
			_cabin_lamp, _helm_lamp, _dial_ink, _chart_lamp, _lit_window,
			_floods, _flood_lens_mat, _flood_beam_mat, _helm_glow, _beacon,
			_beacon_mat, _nav_spots, _nav_mats)


func weather_openness(world_pos: Vector3) -> float:
	return _interior_environment.weather_openness(
			global_transform.affine_inverse(), world_pos,
			_door_fwd.rotation.y if _door_fwd != null else 0.0,
			_door_aft.rotation.y if _door_aft != null else 0.0,
			_door_wh.rotation.y if _door_wh != null else 0.0)


func acoustic_space(world_pos: Vector3) -> StringName:
	return _interior_environment.acoustic_space(
			global_transform.affine_inverse(), world_pos)


func heat_at(local_pos: Vector3) -> float:
	return _interior_environment.heat_at(local_pos, _stove_heat_t)


func _update_stove(delta: float) -> void:
	_stove_controller.update(delta, stove_on, _blackout, _supply, _t,
			_stove_lamp, _stove_fill, _stove_ember, _stove_reflector,
			_stove_heat, _stove_snd)


func _build_dive_locker() -> void:
	var visual_state: Dictionary = BoatInteriorVisualBuilderScript.new().build(self)
	_locker_door = visual_state["locker_door"] as Node3D
	_gear_tank = visual_state["gear_tank"] as Node3D
	_gear_mask = visual_state["gear_mask"] as Node3D


func _build_stove_heat() -> void:
	var effects: Dictionary = BoatInteriorVisualBuilderScript.new().build_stove_effects(self)
	_stove_heat = effects["heat"] as GPUParticles3D
	_stove_snd = effects["sound"] as AudioStreamPlayer3D


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
	_deck_visuals = BoatDeckVisualBuilderScript.new().build(self, trim, metal)

func _physics_process(delta: float) -> void:
	if ocean == null:
		return
	if not global_position.is_finite() or not linear_velocity.is_finite():
		global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 2.0, 0.0))
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		_buoyancy_controller.reset_history()
		return

	var buoyancy: Dictionary = _buoyancy_controller.update(
			self, ocean, PROBES, delta, probe_stiffness, probe_damping,
			hull_plane_fit)
	var submerged := float(buoyancy["submerged"])
	var hydro := float(buoyancy["hydro"])
	var wave_n: Vector3 = buoyancy["wave_normal"]
	var slammed := bool(buoyancy["slammed"])
	_hydrodynamics_controller.update(self, ocean, hydro, submerged, wave_n,
			_rpm, _helm, thrust_power, turn_torque, roll_damp, pitch_damp,
			drift_dbg, drift_sums)
	_run_aground()

	if angular_velocity.length() > 2.2:
		angular_velocity = angular_velocity.limit_length(2.2)
	if linear_velocity.y > 11.0:
		linear_velocity.y = 11.0

	if global_position.y < -30.0 or global_position.y > 120.0:
		global_position = Vector3(0.0, 2.0, 0.0)
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		_buoyancy_controller.reset_history()
		return
	var weather_state := weather as WeatherScript
	var heavy_sea := weather_state != null \
			and (weather_state.storm or weather_state.wind_speed > 16.5)
	if _boat_audio != null:
		_boat_audio.tick_hull(delta, global_basis, angular_velocity, heavy_sea, slammed)


func _run_aground() -> void:
	aground = _grounding_controller.update(self, ocean, KEEL, drift_dbg, drift_sums)
