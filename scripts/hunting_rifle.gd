extends Node3D
class_name HuntingRifle3D
## The imported rifle remains one physical node in its dedicated bag sling,
## both hands and firing. Source-space landmarks are transformed through the
## actual GLB hierarchy so grips/sights never depend on guessed root offsets.

signal fired(origin: Vector3, direction: Vector3)

const MODEL_SCENE := preload("res://art/models/hunting_rifle_animation.glb")
const SHOT_AUDIO_PATH := "res://assets/audio/kar98_shot.mp3"
const RELOAD_AUDIO_PATH := "res://assets/audio/kar98_reload.mp3"
const SOURCE_SLOT_CENTER := Vector3(0.407, -0.005, 0.0)
const SOURCE_PRIMARY_GRIP := Vector3(0.258, -0.038, 0.022)
const SOURCE_SUPPORT_GRIP := Vector3(0.525, -0.025, -0.022)
const SOURCE_REAR_SIGHT := Vector3(0.335, 0.068, 0.0)
const SOURCE_FRONT_SIGHT := Vector3(0.790, 0.069, 0.0)
# Centreline of the open action. The case head finishes here and the projectile
# points along the barrel; the old +30 mm source-Z offset described the outside
# wall of the receiver and made the round cross the rifle sideways.
const SOURCE_CHAMBER := Vector3(0.305, 0.060, 0.0)
# The animated bolt mesh occupies source Y 0.003..0.059 and Z -0.010..0.046.
# Its graspable knob is the low, outboard end—not the receiver-side pivot. Put
# the palm centre just outside that end so neither palm nor wrist enters metal.
const SOURCE_BOLT_HANDLE := Vector3(0.230, 0.016, 0.070)
# The imported body continues a little beyond the original armature marker.
# Keep the blast on the visible bore rather than five centimetres underneath it.
const SOURCE_MUZZLE := Vector3(0.905, 0.058, 0.0)
const FIRE_DURATION := 1.25
const FLASH_DURATION := 0.165
const RELOAD_DURATION := 2.75
const RELOAD_CARTRIDGE_SHOW := 0.28
const RELOAD_INSERTED := 1.32
const RELOAD_BOLT_START := 1.42
const RELOAD_BOLT_DURATION := 1.0
const RELOAD_SOUND_PITCH := 0.85
const INTERIOR_AUDIO_BUS := &"RifleInterior"
# 7.92x57 mm Mauser proportions, in metres. The cartridge root is the centre of
# the case head; local +Z is the bullet/chamber direction. Keeping this contract
# explicit prevents the old model from travelling primer-first into the rifle.
const CARTRIDGE_CASE_LENGTH := 0.057
const CARTRIDGE_OVERALL_LENGTH := 0.082
# The round sits on the right hand's radial (thumb/index) side, not on the palm
# centreline where the middle finger would catch it first.
const CARTRIDGE_PALM_LOCAL := Vector3(0.0, -0.004, -0.026)

var _model: Node3D
var _body_mesh: MeshInstance3D
var _primary_grip: Node3D
var _support_grip: Node3D
var _aim_anchor: Node3D
var _front_sight: Node3D
var _muzzle: Node3D
var _chamber: Node3D
var _bolt_handle: Node3D
var _bolt_handle_rest := Transform3D.IDENTITY
var _skeleton: Skeleton3D
var _bolt_bone := -1
var _cartridge: Node3D
var _animation: AnimationPlayer
var _flash_material: ShaderMaterial
var _flash_light: OmniLight3D
var _flash_core: MeshInstance3D
var _flash_core_material: StandardMaterial3D
var _flame_body: MeshInstance3D
var _flame_body_material: StandardMaterial3D
var _flame_petals: Array[MeshInstance3D] = []
var _flash_crown: MeshInstance3D
var _flash_rays: Node3D
var _flash_ray_material: StandardMaterial3D
var _blast_ring: MeshInstance3D
var _blast_ring_material: StandardMaterial3D
var _blast_globe: MeshInstance3D
var _blast_globe_material: StandardMaterial3D
var _shot_audio: AudioStreamPlayer
var _shot_body_audio: AudioStreamPlayer
var _reload_audio: AudioStreamPlayer
var _acoustic_openness := 1.0
var _reload_sound_started_at := -1.0
var _fire_elapsed := -1.0
var _flash_left := 0.0
var _shot_serial := 0
var _loaded := true
var _reload_elapsed := -1.0
var _reload_bolt_started := false


func _init() -> void:
	name = "HuntingRifle"
	set_meta("item_label", "Hunting rifle")
	set_meta("item_kind", "hunting_rifle")


func _ready() -> void:
	if _model == null:
		_build_model()


func _build_model() -> void:
	_model = MODEL_SCENE.instantiate() as Node3D
	_model.name = "ImportedHuntingRifle"
	# Source +X is muzzle-forward. Wrapper -Z is weapon-forward, +Y remains up,
	# and source thickness +Z becomes wrapper +X: a right-handed weapon frame.
	var raw_to_local := Basis(Vector3.FORWARD, Vector3.UP, Vector3.RIGHT)
	_model.transform = Transform3D(raw_to_local, Vector3.ZERO)
	add_child(_model)
	_find_skeleton(_model)
	_body_mesh = _find_mesh(_model, "rifle_body")
	if _body_mesh != null:
		_model.position -= _imported_point(_body_mesh, SOURCE_SLOT_CENTER)

	_primary_grip = _marker("PrimaryGrip", SOURCE_PRIMARY_GRIP,
			Basis(Vector3.BACK, Vector3.LEFT, Vector3.DOWN))
	_support_grip = _marker("SupportGrip", SOURCE_SUPPORT_GRIP,
			# The measured WRAD left-hand semantic frame is quarter-turned relative
			# to this import. This authored K/P/F frame produces rendered fingers
			# ACROSS the fore-end while the palm continues to carry it from below.
			Basis(Vector3.LEFT, Vector3.UP, Vector3.FORWARD))
	_aim_anchor = _marker("AimAnchor", SOURCE_REAR_SIGHT, Basis.IDENTITY)
	_front_sight = _marker("FrontSight", SOURCE_FRONT_SIGHT, Basis.IDENTITY)
	_muzzle = _marker("Muzzle", SOURCE_MUZZLE, Basis.IDENTITY)
	_chamber = _marker("Chamber", SOURCE_CHAMBER,
			# Cartridge +Z is muzzle-forward (wrapper -Z), +Y remains receiver-up.
			Basis(Vector3.LEFT, Vector3.UP, Vector3.FORWARD))
	_bolt_handle = _marker("BoltHandle", SOURCE_BOLT_HANDLE,
			# Right palm faces the rifle, fingers fold down around the bolt knob.
			Basis(Vector3.BACK, Vector3.LEFT, Vector3.DOWN))
	_bolt_handle_rest = _bolt_handle.transform
	_find_animation_player(_model)
	_build_cartridge()
	_build_shot_audio()


func _find_mesh(root: Node, token: String) -> MeshInstance3D:
	if root is MeshInstance3D and token in root.name.to_lower():
		return root as MeshInstance3D
	for child: Node in root.get_children():
		var found := _find_mesh(child, token)
		if found != null:
			return found
	return null


func _marker(marker_name: String, source_point: Vector3, basis: Basis) -> Node3D:
	var marker := Node3D.new()
	marker.name = marker_name
	marker.transform = Transform3D(basis, _imported_point(_body_mesh, source_point))
	add_child(marker)
	return marker


func _imported_point(mesh_node: MeshInstance3D, source_point: Vector3) -> Vector3:
	if mesh_node == null:
		return Vector3.ZERO
	return to_local(mesh_node.to_global(source_point))


func _find_animation_player(root: Node) -> void:
	if root is AnimationPlayer:
		_animation = root as AnimationPlayer
		return
	for child: Node in root.get_children():
		_find_animation_player(child)
		if _animation != null:
			return


func _find_skeleton(root: Node) -> void:
	if root is Skeleton3D:
		_skeleton = root as Skeleton3D
		_bolt_bone = _skeleton.find_bone("Bolt_Bone")
		return
	for child in root.get_children():
		_find_skeleton(child)
		if _skeleton != null:
			return


func _build_muzzle_flash() -> void:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, depth_test_disabled, fog_disabled;
uniform float energy : hint_range(0.0, 1.0) = 0.0;
uniform float seed = 0.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float radius = length(p);
	float angle = atan(p.y, p.x);
	float core = 1.0 - smoothstep(0.02, 0.25, radius);
	float ray_x = exp(-abs(p.y) * 34.0)
		* (1.0 - smoothstep(0.10, 1.0, abs(p.x)));
	float ray_y = exp(-abs(p.x) * 36.0)
		* (1.0 - smoothstep(0.08, 0.86, abs(p.y)));
	float ray_d1 = exp(-abs(p.x - p.y) * 24.0)
		* (1.0 - smoothstep(0.12, 0.82, radius));
	float ray_d2 = exp(-abs(p.x + p.y) * 24.0)
		* (1.0 - smoothstep(0.12, 0.82, radius));
	float cross_ray = max(max(ray_x, ray_y), max(ray_d1, ray_d2) * 0.62);
	float petals = pow(max(0.0, cos(angle * 5.0 + seed * 6.283)), 12.0)
		* (1.0 - smoothstep(0.18, 0.96, radius));
	float ragged = 0.72 + 0.28 * sin((p.x * 19.0 + p.y * 31.0 + seed * 13.0));
	float a = clamp((core + cross_ray * 0.82 + petals * 0.48)
		* ragged * energy, 0.0, 1.0);
	vec3 hot = mix(vec3(1.0, 0.075, 0.005), vec3(1.0, 0.94, 0.62), core);
	ALBEDO = hot;
	EMISSION = hot * (7.0 + core * 12.0 + cross_ray * 5.0) * energy;
	ALPHA = a;
}
"""
	_flash_material = ShaderMaterial.new()
	_flash_material.shader = shader
	for angle in [0.0, 0.78]:
		var flash := MeshInstance3D.new()
		flash.name = "MuzzleFlash"
		var quad := QuadMesh.new()
		quad.size = Vector2(0.38, 0.27)
		flash.mesh = quad
		flash.material_override = _flash_material
		flash.rotation.z = angle
		flash.position.z = -0.018
		flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_muzzle.add_child(flash)
	# Two bore-length flame cards give the blast long, broken tongues in profile.
	# A slight cant keeps them from vanishing completely while looking down ADS.
	for euler in [Vector3(deg_to_rad(82.0), 0.0, 0.0),
			Vector3(0.0, deg_to_rad(82.0), deg_to_rad(90.0))]:
		var tongue := MeshInstance3D.new()
		tongue.name = "MuzzleFlameTongue"
		var tongue_quad := QuadMesh.new()
		tongue_quad.size = Vector2(0.15, 0.66)
		tongue.mesh = tongue_quad
		tongue.material_override = _flash_material
		tongue.rotation = euler
		tongue.position.z = -0.31
		tongue.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_muzzle.add_child(tongue)
	# A third shader-driven surface points along the bore. It gives the flash a
	# volume from oblique hip-fire and ADS views instead of disappearing when a
	# camera sees one of the crossed cards edge-on.
	var volume := MeshInstance3D.new()
	volume.name = "MuzzleFlashVolume"
	var flame := SphereMesh.new()
	flame.radius = 0.055
	flame.height = 0.24
	flame.radial_segments = 12
	flame.rings = 6
	volume.mesh = flame
	volume.material_override = _flash_material
	volume.rotation.x = deg_to_rad(90.0)
	volume.position.z = -0.095
	volume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_muzzle.add_child(volume)
	# Opaque-hot centre behind the procedural shader. Additive transparent cards
	# can become nearly invisible against bright rain/sky; this tiny emissive core
	# guarantees the ignition remains readable while the shader supplies its shape.
	_flash_core = MeshInstance3D.new()
	_flash_core.name = "MuzzleFlashHotCore"
	var core_mesh := CylinderMesh.new()
	core_mesh.top_radius = 0.017
	core_mesh.bottom_radius = 0.008
	core_mesh.height = 0.27
	core_mesh.radial_segments = 12
	core_mesh.rings = 3
	_flash_core.mesh = core_mesh
	_flash_core.rotation.x = deg_to_rad(90.0)
	_flash_core.position.z = -0.122
	_flash_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash_core_material = StandardMaterial3D.new()
	_flash_core_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_core_material.albedo_color = Color(1.0, 0.88, 0.54)
	_flash_core_material.emission_enabled = true
	_flash_core_material.emission = Color(1.0, 0.18, 0.01)
	_flash_core_material.emission_energy_multiplier = 15.0
	_flash_core_material.no_depth_test = true
	_flash_core.material_override = _flash_core_material
	_flash_core.visible = false
	_muzzle.add_child(_flash_core)
	# The long flame is real bore-aligned geometry. In ADS it therefore extends
	# away from the sight instead of collapsing into a flat billboard.
	_flame_body = MeshInstance3D.new()
	_flame_body.name = "MuzzleFlameBody"
	var body_mesh := CylinderMesh.new()
	body_mesh.top_radius = 0.085
	body_mesh.bottom_radius = 0.006
	body_mesh.height = 0.72
	body_mesh.radial_segments = 14
	body_mesh.rings = 5
	_flame_body.mesh = body_mesh
	_flame_body.rotation.x = deg_to_rad(90.0)
	_flame_body.position.z = -0.345
	_flame_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flame_body_material = StandardMaterial3D.new()
	_flame_body_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flame_body_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_flame_body_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flame_body_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flame_body_material.albedo_color = Color(1.0, 0.18, 0.008, 0.86)
	_flame_body_material.emission_enabled = true
	_flame_body_material.emission = Color(1.0, 0.075, 0.004)
	_flame_body_material.emission_energy_multiplier = 16.0
	_flame_body_material.no_depth_test = true
	_flame_body.material_override = _flame_body_material
	_flame_body.visible = false
	_muzzle.add_child(_flame_body)
	_flash_ray_material = StandardMaterial3D.new()
	_flash_ray_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_ray_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_flash_ray_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_ray_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flash_ray_material.albedo_color = Color(1.0, 0.25, 0.012, 0.82)
	_flash_ray_material.emission_enabled = true
	_flash_ray_material.emission = Color(1.0, 0.075, 0.002)
	_flash_ray_material.emission_energy_multiplier = 16.0
	_flash_ray_material.no_depth_test = true
	# Six narrow jets leave the bore at a small radial angle. They are what makes
	# an ADS shot read as a crown of flame rather than the end-cap of a yellow
	# cylinder; from the side they merge naturally into the main long cone.
	for i in 6:
		var angle := TAU * float(i) / 6.0 + float(_shot_serial) * 0.13
		var direction := Vector3(cos(angle) * 0.24,
				sin(angle) * 0.24, -1.0).normalized()
		var petal := MeshInstance3D.new()
		petal.name = "MuzzleFlamePetal%d" % i
		var petal_mesh := CylinderMesh.new()
		petal_mesh.top_radius = 0.002
		petal_mesh.bottom_radius = 0.032
		petal_mesh.height = 0.36
		petal_mesh.radial_segments = 7
		petal_mesh.rings = 2
		petal.mesh = petal_mesh
		var petal_y := direction
		var petal_x := Vector3.UP.cross(petal_y).normalized()
		var petal_z := petal_x.cross(petal_y).normalized()
		petal.basis = Basis(petal_x, petal_y, petal_z)
		petal.position = direction * 0.18
		petal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		petal.material_override = _flash_ray_material
		petal.visible = false
		_muzzle.add_child(petal)
		_flame_petals.append(petal)
	# Explicit radial triangles are the guaranteed ADS silhouette. The shader
	# and cones provide softness/volume; this tiny additive crown supplies the
	# unmistakable asymmetric flame spikes even exactly down the bore axis.
	_flash_crown = MeshInstance3D.new()
	_flash_crown.name = "MuzzleFlashCrown"
	var crown_mesh := ImmediateMesh.new()
	crown_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 9:
		var angle := TAU * float(i) / 9.0
		var length := 0.090 + 0.035 * (0.5 + 0.5 * sin(float(i) * 4.73))
		var inner := Vector2(cos(angle), sin(angle)) * 0.014
		var normal := Vector2(-sin(angle), cos(angle)) * 0.016
		var tip := Vector2(cos(angle), sin(angle)) * length
		crown_mesh.surface_add_vertex(Vector3(inner.x + normal.x,
				inner.y + normal.y, 0.0))
		crown_mesh.surface_add_vertex(Vector3(inner.x - normal.x,
				inner.y - normal.y, 0.0))
		crown_mesh.surface_add_vertex(Vector3(tip.x, tip.y, 0.0))
	crown_mesh.surface_end()
	_flash_crown.mesh = crown_mesh
	_flash_crown.material_override = _flash_ray_material
	_flash_crown.position.z = -0.095
	_flash_crown.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash_crown.visible = false
	_muzzle.add_child(_flash_crown)
	_flash_rays = Node3D.new()
	_flash_rays.name = "MuzzleFlashRays"
	_flash_rays.position.z = -0.100
	for i in 8:
		var angle := TAU * float(i) / 8.0
		var ray := MeshInstance3D.new()
		ray.name = "FlameRay%d" % i
		var ray_mesh := QuadMesh.new()
		ray_mesh.size = Vector2(0.145 if i % 2 == 0 else 0.105,
				0.014 if i % 2 == 0 else 0.010)
		ray.mesh = ray_mesh
		ray.material_override = _flash_ray_material
		ray.position = Vector3(cos(angle), sin(angle), 0.0) \
				* (0.057 if i % 2 == 0 else 0.042)
		ray.rotation.z = angle
		ray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_flash_rays.add_child(ray)
	_flash_rays.visible = false
	_muzzle.add_child(_flash_rays)

	# A hot ignition globe makes the muzzle visibly erupt before the directional
	# flame stretches forward. It also remains readable from hip-fire angles.
	_blast_globe = MeshInstance3D.new()
	_blast_globe.name = "MuzzleBlastGlobe"
	var globe_mesh := SphereMesh.new()
	globe_mesh.radius = 0.072
	globe_mesh.height = 0.145
	globe_mesh.radial_segments = 12
	globe_mesh.rings = 6
	_blast_globe.mesh = globe_mesh
	_blast_globe.position.z = -0.045
	_blast_globe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_blast_globe_material = StandardMaterial3D.new()
	_blast_globe_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_blast_globe_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_blast_globe_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_blast_globe_material.albedo_color = Color(1.0, 0.68, 0.18, 0.42)
	_blast_globe_material.emission_enabled = true
	_blast_globe_material.emission = Color(1.0, 0.30, 0.018)
	_blast_globe_material.emission_energy_multiplier = 13.0
	_blast_globe_material.no_depth_test = true
	_blast_globe.material_override = _blast_globe_material
	_blast_globe.visible = false
	_muzzle.add_child(_blast_globe)

	# The expanding torus is the instant pressure front. It is intentionally
	# short-lived and translucent: visible enough to communicate force without
	# reading as a permanent sci-fi projectile.
	_blast_ring = MeshInstance3D.new()
	_blast_ring.name = "MuzzlePressureRing"
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.082
	ring_mesh.outer_radius = 0.110
	ring_mesh.rings = 16
	ring_mesh.ring_segments = 8
	_blast_ring.mesh = ring_mesh
	_blast_ring.rotation.x = deg_to_rad(90.0)
	_blast_ring.position.z = -0.070
	_blast_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_blast_ring_material = StandardMaterial3D.new()
	_blast_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_blast_ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_blast_ring_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_blast_ring_material.albedo_color = Color(1.0, 0.78, 0.40, 0.30)
	_blast_ring_material.emission_enabled = true
	_blast_ring_material.emission = Color(1.0, 0.42, 0.08)
	_blast_ring_material.emission_energy_multiplier = 4.5
	_blast_ring_material.no_depth_test = true
	_blast_ring.material_override = _blast_ring_material
	_blast_ring.visible = false
	_muzzle.add_child(_blast_ring)
	_flash_light = OmniLight3D.new()
	_flash_light.name = "MuzzleLight"
	_flash_light.light_color = Color(1.0, 0.34, 0.07)
	_flash_light.omni_range = 7.5
	_flash_light.light_energy = 0.0
	_flash_light.shadow_enabled = false
	_muzzle.add_child(_flash_light)


func _build_shot_audio() -> void:
	## The supplied Kar98 recording is the dry pressure report. Outdoors it plays
	## alone and slightly quieter; inside, a pitch-lowered copy feeds a short,
	## damped reflection bus to add the heavy cabin body without replacing the
	## original transient.
	_ensure_interior_audio_bus()
	var shot_stream := _mp3_stream(SHOT_AUDIO_PATH)
	var reload_stream := _mp3_stream(RELOAD_AUDIO_PATH)
	_shot_audio = AudioStreamPlayer.new()
	_shot_audio.name = "RifleReport"
	_shot_audio.stream = shot_stream
	add_child(_shot_audio)
	_shot_body_audio = AudioStreamPlayer.new()
	_shot_body_audio.name = "RifleInteriorBody"
	_shot_body_audio.stream = shot_stream
	_shot_body_audio.bus = INTERIOR_AUDIO_BUS
	add_child(_shot_body_audio)
	_reload_audio = AudioStreamPlayer.new()
	_reload_audio.name = "RifleBoltReload"
	_reload_audio.stream = reload_stream
	_reload_audio.volume_db = -3.0
	_reload_audio.pitch_scale = RELOAD_SOUND_PITCH
	add_child(_reload_audio)
	_configure_shot_audio_mix()


func _mp3_stream(path: String) -> AudioStreamMP3:
	var stream := AudioStreamMP3.new()
	stream.data = FileAccess.get_file_as_bytes(path)
	return stream


func _ensure_interior_audio_bus() -> void:
	var bus_index := AudioServer.get_bus_index(INTERIOR_AUDIO_BUS)
	if bus_index < 0:
		AudioServer.add_bus()
		bus_index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus_index, INTERIOR_AUDIO_BUS)
	if AudioServer.get_bus_effect_count(bus_index) == 0:
		var room := AudioEffectReverb.new()
		room.room_size = 0.34
		room.damping = 0.42
		room.spread = 0.72
		room.hipass = 0.08
		room.dry = 0.0
		room.wet = 0.82
		AudioServer.add_bus_effect(bus_index, room)
		var damping := AudioEffectLowPassFilter.new()
		damping.cutoff_hz = 2600.0
		AudioServer.add_bus_effect(bus_index, damping)


func _configure_shot_audio_mix() -> void:
	if _shot_audio == null or _shot_body_audio == null:
		return
	var profile := acoustic_profile_for(_acoustic_openness)
	_shot_audio.volume_db = float(profile["report_db"])
	_shot_audio.pitch_scale = float(profile["report_pitch"])
	_shot_body_audio.volume_db = float(profile["body_db"])
	_shot_body_audio.pitch_scale = float(profile["body_pitch"])


func acoustic_profile_for(openness: float) -> Dictionary:
	var enclosed := pow(1.0 - clampf(openness, 0.0, 1.0), 0.72)
	return {
		"report_db": lerpf(-6.0, 0.5, enclosed),
		"report_pitch": lerpf(1.025, 0.955, enclosed),
		"body_db": lerpf(-60.0, -2.0, enclosed),
		"body_pitch": lerpf(0.90, 0.80, enclosed),
	}


func set_acoustic_openness(openness: float) -> void:
	_acoustic_openness = clampf(openness, 0.0, 1.0)
	_configure_shot_audio_mix()


func acoustic_mix_report() -> Dictionary:
	return {
		"openness": _acoustic_openness,
		"report_db": _shot_audio.volume_db if _shot_audio != null else -80.0,
		"report_pitch": _shot_audio.pitch_scale if _shot_audio != null else 1.0,
		"body_db": _shot_body_audio.volume_db if _shot_body_audio != null else -80.0,
		"body_pitch": _shot_body_audio.pitch_scale if _shot_body_audio != null else 1.0,
	}


func _build_cartridge() -> void:
	## A dimensioned 7.92x57-style round. It is assembled from separate case,
	## shoulder, neck, projectile, rim, extractor groove and primer surfaces so
	## the first-person silhouette reads as ammunition rather than a gold capsule.
	_cartridge = Node3D.new()
	_cartridge.name = "ReloadCartridge"
	_cartridge.top_level = true
	_cartridge.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_cartridge)
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.57, 0.31, 0.075)
	brass.metallic = 0.88
	brass.roughness = 0.22
	var brass_dark := StandardMaterial3D.new()
	brass_dark.albedo_color = Color(0.23, 0.105, 0.025)
	brass_dark.metallic = 0.84
	brass_dark.roughness = 0.34
	var copper := StandardMaterial3D.new()
	copper.albedo_color = Color(0.42, 0.145, 0.045)
	copper.metallic = 0.80
	copper.roughness = 0.25
	var primer := StandardMaterial3D.new()
	primer.albedo_color = Color(0.66, 0.58, 0.42)
	primer.metallic = 0.92
	primer.roughness = 0.18

	# Case head and proud rim, followed by the narrow extractor groove.
	_add_cartridge_section("CaseRim", -0.0010, 0.0020,
			0.00610, 0.00610, brass)
	_add_cartridge_section("ExtractorGroove", 0.0020, 0.0050,
			0.00538, 0.00548, brass_dark)
	# The body tapers subtly before the characteristic bottleneck shoulder.
	_add_cartridge_section("BrassCaseBody", 0.0050, 0.0460,
			0.00586, 0.00534, brass)
	_add_cartridge_section("CaseShoulder", 0.0460, 0.0520,
			0.00534, 0.00448, brass)
	_add_cartridge_section("CaseNeck", 0.0520, CARTRIDGE_CASE_LENGTH,
			0.00448, 0.00448, brass)

	# Only the exposed projectile is drawn over the neck. Three small frusta give
	# the copper jacket a recognisable tangent ogive and a clean pointed tip.
	_add_cartridge_section("BulletShank", 0.0570, 0.0665,
			0.00411, 0.00411, copper)
	_add_cartridge_section("BulletOgiveLower", 0.0665, 0.0755,
			0.00411, 0.00265, copper)
	_add_cartridge_section("BulletOgiveUpper", 0.0755, 0.0805,
			0.00265, 0.00072, copper)
	_add_cartridge_section("BulletTip", 0.0805, CARTRIDGE_OVERALL_LENGTH,
			0.00072, 0.00012, copper)
	# The primer is a separate recessed metal disc on the rear face. A very thin
	# cylinder remains legible under first-person specular highlights.
	_add_cartridge_section("Primer", -0.00135, -0.00092,
			0.00228, 0.00228, primer)
	_cartridge.visible = false


func _add_cartridge_section(section_name: String, z0: float, z1: float,
		bottom_radius: float, top_radius: float,
		material: StandardMaterial3D) -> void:
	var section_mesh := CylinderMesh.new()
	section_mesh.bottom_radius = bottom_radius
	section_mesh.top_radius = top_radius
	section_mesh.height = z1 - z0
	section_mesh.radial_segments = 32
	section_mesh.rings = 2
	var section := MeshInstance3D.new()
	section.name = section_name
	section.mesh = section_mesh
	section.material_override = material
	# CylinderMesh is Y-long; +90 degrees maps its positive Y axis onto local +Z.
	section.rotation.x = deg_to_rad(90.0)
	section.position.z = (z0 + z1) * 0.5
	section.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_cartridge.add_child(section)


func primary_grip_node() -> Node3D:
	return _primary_grip


func support_grip_node() -> Node3D:
	return _support_grip


func aim_anchor_node() -> Node3D:
	return _aim_anchor


func front_sight_node() -> Node3D:
	return _front_sight


func muzzle_node() -> Node3D:
	return _muzzle


func chamber_node() -> Node3D:
	return _chamber


func bolt_handle_node() -> Node3D:
	return _bolt_handle


func bolt_grip_transform() -> Transform3D:
	if _skeleton == null or _bolt_bone < 0:
		return _bolt_handle_rest
	# Rifle_Bolt is skinned to Bolt_Bone. Apply that exact animated delta to the
	# authored knob contact frame, transformed through the real GLB hierarchy.
	# The hand and metal therefore share one source of truth every render frame.
	var rest := _skeleton.get_bone_rest(_bolt_bone)
	var pose := _skeleton.get_bone_global_pose(_bolt_bone)
	var bone_delta := pose * rest.affine_inverse()
	var skeleton_to_rifle := global_transform.affine_inverse() \
			* _skeleton.global_transform
	return skeleton_to_rifle * bone_delta * skeleton_to_rifle.affine_inverse() \
			* _bolt_handle_rest


func cartridge_node() -> Node3D:
	return _cartridge


func cartridge_palm_local() -> Vector3:
	## The palm remains behind the round. Thumb and index meet roughly five
	## centimetres forward of this point around the lower case body.
	return CARTRIDGE_PALM_LOCAL


func cartridge_tip_local() -> Vector3:
	return Vector3(0.0, 0.0, CARTRIDGE_OVERALL_LENGTH)


func cartridge_axis_global() -> Vector3:
	return _cartridge.global_basis.z.normalized() if _cartridge != null \
			else Vector3.ZERO


func cartridge_tip_global() -> Vector3:
	return _cartridge.global_transform * cartridge_tip_local() \
			if _cartridge != null else Vector3.ZERO


func cartridge_visual_report() -> Dictionary:
	var mesh_count := 0
	if _cartridge != null:
		for child: Node in _cartridge.get_children():
			if child is MeshInstance3D:
				mesh_count += 1
	return {"mesh_count": mesh_count, "case_length": CARTRIDGE_CASE_LENGTH,
			"overall_length": CARTRIDGE_OVERALL_LENGTH}


func cartridge_contact_bounds() -> AABB:
	# Only the lower case body is the precision-pinch contact patch. Including the
	# full 82 mm round let the folded ring/pinky touch the ogive and made the pose
	# read as a fist instead of a thumb/index placement.
	return AABB(Vector3(-0.0070, -0.0070, 0.014),
			Vector3(0.0140, 0.0140, 0.034))


func bolt_contact_bounds() -> AABB:
	# Only the round knob is a hand contact. The old five-centimetre box also
	# swallowed the stem/receiver clearance and falsely let ring/pinky joints
	# penetrate a volume that contains no metal.
	var size := Vector3(0.034, 0.034, 0.044)
	return AABB(bolt_grip_transform().origin - size * 0.5, size)


func primary_contact_bounds() -> AABB:
	var size := Vector3(0.060, 0.105, 0.075)
	# The right palm meets the right FACE of the stock wrist. A centred box put
	# the palm three centimetres inside wood and forced the contact solver open.
	var centre := _primary_grip.position + Vector3(-size.x * 0.5, 0.030, 0.0)
	return AABB(centre - size * 0.5, size)


func support_contact_bounds() -> AABB:
	# This is the whole tapered fore-end, not a palm-sized cube. Its wooden body
	# continues rearward toward the receiver, which is exactly where the curled
	# phalanges land in the imported mesh.
	var size := Vector3(0.090, 0.078, 0.340)
	# The support palm carries the LOWER face; all stock volume belongs above it.
	# Offset the tapered wood slightly starboard: the left fingertips meet its
	# port surface instead of starting inside it.
	# The stock is tapered above the authored palm plane. Starting the box
	# directly on that plane falsely classifies the proximal finger joints as
	# buried in wood even while the visible hand is correctly underneath it.
	var centre := _support_grip.position + Vector3(0.076,
			size.y * 0.5 + 0.025, 0.082)
	return AABB(centre - size * 0.5, size)


func begin_fire() -> bool:
	if _fire_elapsed >= 0.0 or _reload_elapsed >= 0.0 or not _loaded:
		return false
	_loaded = false
	_fire_elapsed = 0.0
	_flash_left = 0.0
	_shot_serial += 1
	# No procedural muzzle geometry: the supplied report, recoil and pressure
	# impulse carry the shot. The former billboard/cone burst was visibly gamey.
	_configure_shot_audio_mix()
	_shot_audio.play()
	if _shot_body_audio.volume_db > -45.0:
		_shot_body_audio.play()
	if _animation != null:
		var clip := _shoot_animation_name()
		if clip != StringName():
			_animation.stop()
			_animation.play(clip, -1.0, 1.0)
	fired.emit(_muzzle.global_position, -_muzzle.global_basis.z)
	return true


func begin_reload() -> bool:
	if _loaded or _reload_elapsed >= 0.0:
		return false
	# The pressure/recoil impulse is already over by the time the player can
	# reach R. Stop its tail so the rifle can settle into the left-hand reload.
	_fire_elapsed = -1.0
	if _shot_audio != null:
		_shot_audio.stop()
	if _shot_body_audio != null:
		_shot_body_audio.stop()
	_reload_elapsed = 0.0
	_reload_bolt_started = false
	_reload_sound_started_at = -1.0
	if _reload_audio != null:
		_reload_audio.stop()
	_flash_left = 0.0
	if _animation != null:
		_animation.stop()
	return true


func cancel_reload() -> void:
	_reload_elapsed = -1.0
	_reload_bolt_started = false
	_reload_sound_started_at = -1.0
	if _reload_audio != null:
		_reload_audio.stop()
	if _cartridge != null:
		_cartridge.visible = false
	if _animation != null:
		_animation.stop()


func is_loaded() -> bool:
	return _loaded


func is_reloading() -> bool:
	return _reload_elapsed >= 0.0


func reload_elapsed() -> float:
	return _reload_elapsed


func reload_amount() -> float:
	return clampf(_reload_elapsed / RELOAD_DURATION, 0.0, 1.0) \
			if _reload_elapsed >= 0.0 else 0.0


func _shoot_animation_name() -> StringName:
	if _animation == null:
		return StringName()
	for clip: StringName in _animation.get_animation_list():
		if "shoot" in str(clip).to_lower():
			return clip
	return StringName()


func tick(delta: float) -> void:
	if _fire_elapsed >= 0.0:
		_fire_elapsed += delta
		if _fire_elapsed >= FIRE_DURATION:
			_fire_elapsed = -1.0
	_flash_left = 0.0
	if _reload_elapsed >= 0.0:
		_reload_elapsed += delta
		if _cartridge != null:
			_cartridge.visible = _reload_elapsed >= RELOAD_CARTRIDGE_SHOW \
					and _reload_elapsed < RELOAD_INSERTED
		if not _reload_bolt_started and _reload_elapsed >= RELOAD_BOLT_START:
			_reload_bolt_started = true
			_reload_sound_started_at = _reload_elapsed
			if _reload_audio != null:
				_reload_audio.pitch_scale = RELOAD_SOUND_PITCH
				_reload_audio.play()
			if _animation != null:
				var reload_clip := _shoot_animation_name()
				if reload_clip != StringName():
					_animation.stop()
					var clip_resource := _animation.get_animation(reload_clip)
					var sync_speed := clip_resource.length / RELOAD_BOLT_DURATION \
							if clip_resource != null else 1.0
					_animation.play(reload_clip, -1.0, sync_speed)
		if _reload_elapsed >= RELOAD_DURATION:
			_reload_elapsed = -1.0
			_reload_bolt_started = false
			if _reload_audio != null:
				_reload_audio.stop()
			_loaded = true
			if _cartridge != null:
				_cartridge.visible = false


func is_firing() -> bool:
	return _fire_elapsed >= 0.0


func flash_energy() -> float:
	return 0.0


func pressure_amount() -> float:
	if _fire_elapsed < 0.0 or _fire_elapsed > 0.32:
		return 0.0
	# Immediate concussion followed by a small elastic after-pulse. The returned
	# value drives FOV and can be reused later by hearing/damage systems.
	var decay := exp(-_fire_elapsed * 12.5)
	return clampf(decay * (0.86 + sin(_fire_elapsed * 48.0) * 0.14), 0.0, 1.0)


func blast_visible() -> bool:
	return false


func shot_audio_playing() -> bool:
	return _shot_audio != null and _shot_audio.playing


func reload_audio_playing() -> bool:
	return _reload_audio != null and _reload_audio.playing


func reload_sound_started_at() -> float:
	return _reload_sound_started_at


func reload_sound_pitch() -> float:
	return _reload_audio.pitch_scale if _reload_audio != null else 0.0


func shoot_animation_playing() -> bool:
	return _animation != null and _animation.is_playing() \
			and "shoot" in str(_animation.current_animation).to_lower()


func fire_phase() -> float:
	return clampf(_fire_elapsed / FIRE_DURATION, 0.0, 1.0) \
			if _fire_elapsed >= 0.0 else -1.0


func recoil_camera() -> Vector3:
	if _fire_elapsed < 0.0:
		return Vector3.ZERO
	var t := _fire_elapsed
	if t < 0.075:
		var snap := 1.0 - pow(1.0 - t / 0.075, 3.0)
		return Vector3(deg_to_rad(7.1), deg_to_rad(-0.70), deg_to_rad(2.35)) * snap
	var settle := smoothstep(0.075, 0.58, t)
	return Vector3(deg_to_rad(7.1), deg_to_rad(-0.70), deg_to_rad(2.35)) \
			.lerp(Vector3.ZERO, settle)


func recoil_local_transform() -> Transform3D:
	if _fire_elapsed < 0.0:
		return Transform3D.IDENTITY
	var t := _fire_elapsed
	var amount := 0.0
	if t < 0.070:
		amount = 1.0 - pow(1.0 - t / 0.070, 3.0)
	else:
		amount = 1.0 - smoothstep(0.070, 0.48, t)
	# Keep the actual stock seated at the shoulder. Most of the perceived force
	# belongs to camera kick; a large local translation makes the butt clip
	# through the eye and hides the whole gun.
	var basis := Basis(Vector3.RIGHT, deg_to_rad(1.4) * amount) \
			* Basis(Vector3.BACK, deg_to_rad(-0.45) * amount)
	return Transform3D(basis, Vector3(0.0, 0.005, 0.012) * amount)


func animation_names() -> PackedStringArray:
	var names := PackedStringArray()
	if _animation != null:
		for clip: StringName in _animation.get_animation_list():
			names.append(str(clip))
	return names


func model_mesh_count() -> int:
	return _count_meshes(_model)


func _count_meshes(node: Node) -> int:
	if node == null:
		return 0
	var count := 1 if node is MeshInstance3D else 0
	for child: Node in node.get_children():
		count += _count_meshes(child)
	return count
