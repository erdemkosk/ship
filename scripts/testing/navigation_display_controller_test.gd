extends SceneTree
## Deterministic contract for supply, sounder history and shared chart/radar fix.

class FakeWeather extends Node:
	var wind_speed := 0.0
	var rain_amount := 0.0
	var storm := false

class FakeSeabed extends Node:
	var height_texture: Texture2D

class FakeOcean extends Node:
	var seabed: Node

	func get_height(_position: Vector3) -> float:
		return 2.0

	func get_seafloor_height(_position: Vector3) -> float:
		return -20.0


func _initialize() -> void:
	var sounder := ShaderMaterial.new()
	sounder.shader = load("res://shaders/sounder.gdshader")
	var chart := ShaderMaterial.new()
	chart.shader = load("res://shaders/chart.gdshader")
	var radar := ShaderMaterial.new()
	radar.shader = load("res://shaders/radar.gdshader")
	var pin := Node3D.new()
	var weather := FakeWeather.new()
	var ocean := FakeOcean.new()
	var seabed := FakeSeabed.new()
	var image := Image.create(2, 2, false, Image.FORMAT_RF)
	seabed.height_texture = ImageTexture.create_from_image(image)
	ocean.seabed = seabed
	root.add_child(pin)
	root.add_child(weather)
	root.add_child(ocean)
	ocean.add_child(seabed)
	var history := PackedFloat32Array()
	history.resize(64)
	var controller := preload("res://scripts/boat_navigation_display_controller.gd").new()
	controller.setup(sounder, chart, radar, pin, history)
	var power: Vector2 = controller.update(0.6, weather, 0.0, ocean,
			Vector3(512.0, 0.0, -512.0), Basis.IDENTITY, true)
	var report := controller.contract_report() as Dictionary
	var chart_uv := chart.get_shader_parameter("boat_uv") as Vector2
	var complete := power.is_equal_approx(Vector2(1.0, 0.0)) \
			and int(report.get("depth_head", 0)) == 1 \
			and int(report.get("depth_samples", 0)) == 64 \
			and bool(report.get("chart_texture_set", false)) \
			and chart_uv.is_equal_approx(Vector2(0.75, 0.25)) \
			and is_equal_approx(float(sounder.get_shader_parameter("depth_now")), 22.0) \
			and pin.position.is_equal_approx(Vector3(1.425, 3.712, 2.755))
	print("[navigation-displays] supply=%.3f depth=%d uv=%s pin=%s texture=%s complete=%s" % [
			power.x, int(report.get("depth_head", 0)), chart_uv, pin.position,
			report.get("chart_texture_set", false), complete])
	if not complete:
		push_error("boat navigation display controller contract incomplete")
	quit(0 if complete else 1)
