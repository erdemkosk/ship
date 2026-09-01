extends SceneTree
## Station locking and suppressed free-walk input routing contract.

class FakeBoat extends RefCounted:
	const HELM_STAND := Vector3(1.0, 2.0, 3.0)
	const TELEGRAPH_STAND := Vector3(4.0, 5.0, 6.0)
	const CHART_STAND := Vector3(7.0, 8.0, 9.0)

class FakeWalker extends RefCounted:
	var spawn_position := Vector3.ZERO
	var spawn_count := 0
	var update_count := 0
	var last_wish := Vector2.ONE
	var last_axes := Vector2.ONE

	func spawn_at(position: Vector3) -> void:
		spawn_position = position
		spawn_count += 1

	func update(_delta: float, _boat, wish: Vector2, _jump: bool,
			_forward: Vector3, axes: Vector2, _hold_jump: bool,
			_dive: bool) -> void:
		update_count += 1
		last_wish = wish
		last_axes = axes

var stair_count := 0


func _initialize() -> void:
	for action in [&"jump", &"dive"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	var boat := FakeBoat.new()
	var walker := FakeWalker.new()
	var locomotion := preload("res://scripts/camera_fps_locomotion.gd").new()
	locomotion.update(0.016, boat, walker, "helm", Transform3D.IDENTITY,
			Vector3.FORWARD, Vector3.RIGHT, false, 0.0, _tick_stair)
	var station_ok := walker.spawn_count == 1 \
			and walker.spawn_position.is_equal_approx(FakeBoat.HELM_STAND) \
			and walker.update_count == 0 and stair_count == 0
	locomotion.update(0.016, boat, walker, "", Transform3D.IDENTITY,
			Vector3.FORWARD, Vector3.RIGHT, true, 0.0, _tick_stair)
	var suppressed_ok := walker.update_count == 1 \
			and walker.last_wish.is_zero_approx() \
			and walker.last_axes.is_zero_approx() and stair_count == 1
	var complete := station_ok and suppressed_ok
	print("[camera-fps-locomotion] station=%s suppressed=%s complete=%s" % [
			station_ok, suppressed_ok, complete])
	if not complete:
		push_error("camera FPS locomotion contract incomplete")
	quit(0 if complete else 1)


func _tick_stair() -> void:
	stair_count += 1
