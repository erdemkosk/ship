class_name BoatElectronicsController
extends RefCounted
## Runtime motion and audio for the radar, sounder and VHF installation.

const RADAR_DROP := 0.05

var _radar_ping: AudioStreamPlayer3D
var _radio_sound: AudioStreamPlayer3D
var _radar_scanner: Node3D
var _radar_arm: Node3D
var _radar_pivot: Node3D
var _sounder_arm: Node3D
var _sounder_pivot: Node3D
var _radar_home := Vector3.ZERO
var _radar_sweep_previous := 0.0
var _radar_spin := 0.0
var _radio_was_held := false


func setup(radar_ping: AudioStreamPlayer3D, radio_sound: AudioStreamPlayer3D,
		radar_scanner: Node3D, radar_arm: Node3D, radar_pivot: Node3D,
		sounder_arm: Node3D, sounder_pivot: Node3D,
		radar_home: Vector3) -> void:
	_radar_ping = radar_ping
	_radio_sound = radio_sound
	_radar_scanner = radar_scanner
	_radar_arm = radar_arm
	_radar_pivot = radar_pivot
	_sounder_arm = sounder_arm
	_sounder_pivot = sounder_pivot
	_radar_home = radar_home


func update(delta: float, radio_held: bool, blackout: float, supply: float,
		radar_pull: float, sounder_pull: float, radar_swing: float,
		radar_face: float, sounder_swing: float, sounder_face: float,
		camera_rig: Node3D) -> Vector2:
	_update_audio(radio_held)
	_update_scanner(delta, blackout, supply)
	var camera: Camera3D = camera_rig.get("_cam") if camera_rig != null else null
	if camera != null and radar_pull > 0.02 \
			and camera.global_position.distance_to(_radar_pivot.global_position) > 2.05:
		radar_pull = 0.0
	if camera != null and sounder_pull > 0.02 \
			and camera.global_position.distance_to(_sounder_pivot.global_position) > 2.05:
		sounder_pull = 0.0
	_update_carriers(delta, radar_pull, sounder_pull, radar_swing,
			radar_face, sounder_swing, sounder_face)
	return Vector2(radar_pull, sounder_pull)


func _update_audio(radio_held: bool) -> void:
	if _radar_ping != null:
		var phase := fmod(Time.get_ticks_msec() / 1000.0 * 0.7853982, TAU)
		if phase < _radar_sweep_previous:
			_radar_ping.play()
		_radar_sweep_previous = phase
	if _radio_sound != null:
		if radio_held and not _radio_was_held:
			_radio_sound.stop()
			_radio_sound.play()
		elif not radio_held and _radio_was_held:
			_radio_sound.stop()
	_radio_was_held = radio_held


func _update_scanner(delta: float, blackout: float, supply: float) -> void:
	if _radar_scanner == null:
		return
	var target_speed := 0.0
	if blackout <= 0.0:
		target_speed = 24.0 * TAU / 60.0 * clampf(supply, 0.0, 1.0)
	_radar_spin = lerpf(_radar_spin, target_speed, 1.0 - exp(-2.2 * delta))
	_radar_scanner.rotate_object_local(Vector3.UP, _radar_spin * delta)


func _update_carriers(delta: float, radar_pull: float, sounder_pull: float,
		radar_swing: float, radar_face: float, sounder_swing: float,
		sounder_face: float) -> void:
	if _radar_arm != null:
		var radar_weight := 1.0 - exp(-7.0 * delta)
		_radar_arm.rotation.y = lerpf(
				_radar_arm.rotation.y, radar_swing * radar_pull, radar_weight)
		_radar_arm.position.y = lerpf(_radar_arm.position.y,
				_radar_home.y - RADAR_DROP * radar_pull, radar_weight)
		_radar_pivot.rotation.y = lerpf(
				_radar_pivot.rotation.y, radar_face * radar_pull, radar_weight)
	if _sounder_arm != null:
		var sounder_weight := 1.0 - exp(-7.0 * delta)
		_sounder_arm.rotation.y = lerpf(
				_sounder_arm.rotation.y, sounder_swing * sounder_pull, sounder_weight)
		_sounder_pivot.rotation.y = lerpf(
				_sounder_pivot.rotation.y, sounder_face * sounder_pull, sounder_weight)
