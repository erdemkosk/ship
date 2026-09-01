class_name BoatEngineController
extends RefCounted
## Engine spool state and the moving drivetrain/helm presentation.

const OFF := 0
const CRANKING := 1
const RUNNING := 2

var _owner: Node3D
var _throttle_lever: Node3D
var _ignition_key: Node3D
var _ignition_led: StandardMaterial3D
var _engine_room: Node
var _screw: Node3D
var _motor_pivot: Node3D
var _wheel: Node3D
var _prop_spray: GPUParticles3D
var _prop_bubbles: GPUParticles3D
var _bubble_material: ParticleProcessMaterial


func setup(owner: Node3D, throttle_lever: Node3D, ignition_key: Node3D,
		ignition_led: StandardMaterial3D, engine_room: Node, screw: Node3D,
		motor_pivot: Node3D, wheel: Node3D, prop_spray: GPUParticles3D,
		prop_bubbles: GPUParticles3D,
		bubble_material: ParticleProcessMaterial) -> void:
	_owner = owner
	_throttle_lever = throttle_lever
	_ignition_key = ignition_key
	_ignition_led = ignition_led
	_engine_room = engine_room
	_screw = screw
	_motor_pivot = motor_pivot
	_wheel = wheel
	_prop_spray = prop_spray
	_prop_bubbles = prop_bubbles
	_bubble_material = bubble_material


func step(delta: float, engine_state: int, rpm: float, throttle: float,
		crank_left: float) -> Dictionary:
	var caught := false
	if engine_state == CRANKING:
		crank_left -= delta
		if crank_left <= 0.0:
			engine_state = RUNNING
			caught = true
	var target_rpm := throttle if engine_state == RUNNING else 0.0
	var response_time := 1.9
	if engine_state != RUNNING:
		response_time = 0.85
	elif absf(target_rpm) < absf(rpm):
		response_time = 1.5
	if target_rpm * rpm < -0.001:
		response_time = 3.6
	rpm = lerpf(rpm, target_rpm, 1.0 - exp(-delta / response_time))
	if absf(rpm) < 0.004 and target_rpm == 0.0:
		rpm = 0.0
	return {
		"engine": engine_state,
		"rpm": rpm,
		"crank_left": crank_left,
		"caught": caught,
	}


func turn_ignition(engine_state: int) -> Dictionary:
	if engine_state == OFF:
		return {"engine": CRANKING, "crank_left": 2.15, "cranking": true}
	return {"engine": OFF, "crank_left": 0.0, "cranking": false}


func update_drivetrain(delta: float, engine_state: int, rpm: float,
		throttle: float, helm: float) -> void:
	if _throttle_lever != null:
		_throttle_lever.rotation_degrees.x = lerpf(
				38.0, -44.0, (throttle + 0.4) / 1.4)
	_update_ignition(delta, engine_state)
	if _engine_room != null and _engine_room.has_method("drive"):
		_engine_room.call("drive", engine_state, rpm, delta)
	if _screw != null:
		_screw.rotate_object_local(Vector3.UP, rpm * 40.0 * delta)
	if _motor_pivot != null:
		_motor_pivot.rotation.y = lerp_angle(_motor_pivot.rotation.y,
				helm * 0.55, 1.0 - exp(-5.0 * delta))
	if _wheel != null:
		_wheel.rotation.z = lerp_angle(_wheel.rotation.z,
				helm * 4.2, 1.0 - exp(-5.0 * delta))


func update_wash(delta: float, rpm: float, forward_speed: float,
		ocean: Node) -> void:
	if _prop_spray != null:
		_prop_spray.amount_ratio = clampf(
				absf(rpm) * 0.7 + maxf(forward_speed, 0.0) * 0.12, 0.0, 1.0)
		_prop_spray.emitting = absf(rpm) > 0.06 or forward_speed > 0.9
	if _prop_bubbles != null:
		_prop_bubbles.amount_ratio = clampf(absf(rpm) * 0.92, 0.0, 1.0)
		_prop_bubbles.emitting = absf(rpm) > 0.035
		if _bubble_material != null:
			_bubble_material.initial_velocity_max = 0.75 + absf(rpm) * 2.4
	if ocean != null and ocean.has_method("prop_wash") and absf(rpm) > 0.015:
		ocean.call("prop_wash", _owner.to_global(Vector3(0.0, -0.62, 4.15)),
				_owner.global_basis.z, rpm, delta)


func _update_ignition(delta: float, engine_state: int) -> void:
	if _ignition_key != null:
		var target_angle := 0.0
		if engine_state == CRANKING:
			target_angle = -2.45
		elif engine_state == RUNNING:
			target_angle = -1.75
		_ignition_key.rotation.y = lerpf(_ignition_key.rotation.y,
				target_angle, 1.0 - exp(-11.0 * delta))
	if _ignition_led == null:
		return
	if engine_state == RUNNING:
		_ignition_led.emission = Color(0.22, 1.0, 0.34)
		_ignition_led.emission_energy_multiplier = 2.4
	elif engine_state == CRANKING:
		_ignition_led.emission = Color(1.0, 0.72, 0.16)
		_ignition_led.emission_energy_multiplier = 2.0
	else:
		_ignition_led.emission = Color(1.0, 0.16, 0.10)
		_ignition_led.emission_energy_multiplier = 1.0
