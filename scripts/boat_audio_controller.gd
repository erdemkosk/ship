class_name BoatAudioController
extends RefCounted
## Owns incidental sounds made by the boat's moving structure.
## Engine playback stays on the boat because it is part of propulsion state;
## this controller handles doors, hull working and the helm mechanism.

var _host: Node3D
var _door_players: Array[AudioStreamPlayer3D] = []
var _door_voice := 0
var _creak_players: Array[AudioStreamPlayer3D] = []
var _creak_voice := 0
var _creak_light: Array[AudioStream] = []
var _creak_heavy: Array[AudioStream] = []
var _creak_last: AudioStream
var _creak_cd := 0.0
var _prev_heel := 0.0
var _heel_ready := false
var _helm_player: AudioStreamPlayer3D
var _prev_wheel_z := 0.0
var _wheel_ready := false


func setup(host: Node3D) -> void:
	_host = host
	_build_door_players()
	_build_hull_creak()
	_build_helm_player()


func play_hinge(where: Vector3) -> void:
	if _door_players.is_empty():
		return
	var player := _door_players[_door_voice]
	_door_voice = (_door_voice + 1) % _door_players.size()
	player.position = where
	player.pitch_scale = randf_range(0.94, 1.07)
	player.play()


func tick_helm(delta: float, wheel: Node3D, engaged: bool) -> void:
	if _helm_player == null or wheel == null:
		return
	var wheel_z := wheel.rotation.z
	var rate := 0.0
	if _wheel_ready:
		rate = absf(angle_difference(wheel_z, _prev_wheel_z)) / maxf(delta, 0.001)
	_prev_wheel_z = wheel_z
	_wheel_ready = true
	var turning := engaged and rate > 0.10
	var target := clampf((rate - 0.10) / 1.6, 0.0, 1.0) if turning else 0.0
	var response := 1.0 - exp(-10.0 * delta)
	if turning:
		if not _helm_player.playing:
			_helm_player.play()
		_helm_player.volume_db = lerpf(_helm_player.volume_db,
				linear_to_db(maxf(0.035 + target * 0.055, 0.0001)), response)
		_helm_player.pitch_scale = lerpf(_helm_player.pitch_scale,
				lerpf(0.93, 1.07, target), response)
	else:
		_helm_player.volume_db = lerpf(_helm_player.volume_db, -48.0,
				1.0 - exp(-7.0 * delta))
		if _helm_player.volume_db < -36.0 and _helm_player.playing:
			_helm_player.stop()
			_helm_player.volume_db = -80.0


func tick_hull(delta: float, boat_basis: Basis, angular_velocity: Vector3,
		heavy_sea: bool, slammed: bool) -> void:
	if _creak_players.is_empty():
		return
	_creak_cd -= delta
	var heel := absf(asin(clampf(boat_basis.x.y, -1.0, 1.0)))
	var heel_rate := 0.0
	if _heel_ready:
		heel_rate = absf(heel - _prev_heel) / maxf(delta, 0.001)
	_prev_heel = heel
	_heel_ready = true
	var local_angular := boat_basis.inverse() * angular_velocity
	var work := heel_rate * 2.4 + absf(local_angular.z) * 1.8 \
			+ absf(local_angular.x) * 1.15 + heel * 0.55
	if slammed:
		_play_creak(true, clampf(0.7 + work * 0.25, 0.7, 1.0))
		return
	if _creak_cd > 0.0:
		return
	var threshold := 0.38 if heavy_sea else 0.58
	if work < threshold:
		return
	var chance := clampf((work - threshold) * 0.55, 0.08, 0.58)
	if heavy_sea:
		chance = minf(chance * 1.4, 0.72)
	if randf() > chance:
		_creak_cd = 0.16
		return
	var use_heavy := heavy_sea and (work > 0.82 or heel > 0.20 or randf() < 0.42)
	_play_creak(use_heavy, clampf(0.42 + work * 0.42, 0.4, 1.0))


func _build_door_players() -> void:
	var stream: AudioStream = load("res://assets/audio/door.mp3")
	if stream == null:
		return
	for _i in 4:
		var player := AudioStreamPlayer3D.new()
		player.stream = stream
		player.volume_db = -7.0
		player.unit_size = 1.6
		player.max_distance = 22.0
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		_host.add_child(player)
		_door_players.append(player)


func _build_hull_creak() -> void:
	for path: String in [
		"res://assets/audio/hull_creak.mp3",
		"res://assets/audio/hull_creak_2.mp3",
		"res://assets/audio/hull_creak_3.mp3",
	]:
		var stream: AudioStream = load(path)
		if stream != null:
			_creak_light.append(stream)
	var heavy: AudioStream = load("res://assets/audio/hull_creak_heavy.mp3")
	if heavy != null:
		_creak_heavy.append(heavy)
	if _creak_light.is_empty() and _creak_heavy.is_empty():
		return
	for _i in 2:
		var player := AudioStreamPlayer3D.new()
		player.position = Vector3(0.0, 0.28, 0.70)
		player.volume_db = -10.0
		player.unit_size = 3.4
		player.max_distance = 24.0
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		_host.add_child(player)
		_creak_players.append(player)


func _build_helm_player() -> void:
	var recording: AudioStream = load("res://assets/audio/helm_wheel.mp3")
	if recording == null:
		return
	if recording is AudioStreamMP3:
		(recording as AudioStreamMP3).loop = true
	_helm_player = AudioStreamPlayer3D.new()
	_helm_player.stream = recording
	_helm_player.position = Vector3(0.0, 3.72, 0.28)
	_helm_player.volume_db = -80.0
	_helm_player.unit_size = 1.4
	_helm_player.max_distance = 7.0
	_helm_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	_host.add_child(_helm_player)


func _pick_creak(pool: Array[AudioStream]) -> AudioStream:
	if pool.is_empty():
		return null
	if pool.size() == 1:
		return pool[0]
	var stream: AudioStream = pool[randi() % pool.size()]
	if stream == _creak_last:
		stream = pool[randi() % pool.size()]
	return stream


func _play_creak(heavy: bool, amount: float) -> void:
	if _creak_players.is_empty():
		return
	var stream := _pick_creak(_creak_heavy if heavy else _creak_light)
	if stream == null:
		stream = _pick_creak(_creak_light if heavy else _creak_heavy)
	if stream == null:
		return
	_creak_last = stream
	var player := _creak_players[_creak_voice]
	_creak_voice = (_creak_voice + 1) % _creak_players.size()
	player.stream = stream
	player.pitch_scale = randf_range(0.86, 1.06) if heavy else randf_range(0.90, 1.12)
	var level := lerpf(0.32, 1.0, clampf(amount, 0.0, 1.0))
	if heavy:
		level *= 1.15
	player.volume_db = linear_to_db(maxf(level, 0.0001))
	player.play()
	var hold := stream.get_length()
	if hold <= 0.05:
		hold = 2.0
	_creak_cd = hold * 0.55 + randf_range(0.6, 1.8)
