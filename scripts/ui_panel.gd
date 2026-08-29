extends CanvasLayer
## Right-side control panel (Turkish labels): wind, waves, time of day, fog,
## rain, storm and presets. Tab toggles visibility.

var ocean: Node3D
var weather: Node3D

var _panel: PanelContainer
var _fps_label: Label
var _fps_accum := 0.0

var _s_wind: HSlider
var _s_dir: HSlider
var _s_height: HSlider
var _s_steep: HSlider
var _s_time: HSlider
var _s_fog: HSlider
var _s_cloud: HSlider
var _s_rain: HSlider
var _c_storm: CheckButton
var _presets: OptionButton

# Distinct sea states. Kâbus is a hard gale on a 9 m boat (Hs ~8 m), not a
# 40 m cartoon. Açık Gün is noon with a bare sky — the one you can see.
# wind, dir, height, steep, time, fog%, cloud%, rain%, storm
const PRESETS: Array[Dictionary] = [
	{"name": "Sakin Gece", "wind": 4.0, "dir": 300.0, "height": 0.6, "steep": 0.6, "time": 22.5, "fog": 12.0, "cloud": 8.0, "rain": 0.0, "storm": false},
	{"name": "Clear Day", "wind": 5.0, "dir": 200.0, "height": 0.45, "steep": 0.5, "time": 12.0, "fog": 0.0, "cloud": 0.0, "rain": 0.0, "storm": false},
	{"name": "Clear Horizon", "wind": 10.0, "dir": 220.0, "height": 0.9, "steep": 0.8, "time": 14.0, "fog": 8.0, "cloud": 28.0, "rain": 0.0, "storm": false},
	{"name": "Hazy Evening", "wind": 6.0, "dir": 85.0, "height": 0.5, "steep": 0.5, "time": 19.2, "fog": 88.0, "cloud": 78.0, "rain": 8.0, "storm": false},
	{"name": "Storm", "wind": 18.0, "dir": 40.0, "height": 1.2, "steep": 1.0, "time": 20.2, "fog": 45.0, "cloud": 90.0, "rain": 60.0, "storm": true},
	{"name": "Kâbus", "wind": 23.0, "dir": 75.0, "height": 1.4, "steep": 1.06, "time": 20.8, "fog": 32.0, "cloud": 94.0, "rain": 72.0, "storm": true},
]


func setup(o: Node3D, w: Node3D) -> void:
	add_to_group("ui_panel")
	ocean = o
	weather = w
	_build()
	_apply_preset(_preset_index("Storm"))


func _build() -> void:
	# subtle horror vignette
	var vig := ColorRect.new()
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vmat := ShaderMaterial.new()
	vmat.shader = load("res://shaders/vignette.gdshader")
	vig.material = vmat
	add_child(vig)

	_fps_label = Label.new()
	_fps_label.position = Vector2(12, 10)
	_fps_label.add_theme_color_override("font_color", Color(0.8, 0.85, 0.8))
	add_child(_fps_label)

	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.06, 0.82)
	style.border_color = Color(0.18, 0.22, 0.2)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(14)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.offset_left = -336.0
	_panel.offset_right = -12.0
	_panel.offset_top = 12.0
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_panel.add_child(vbox)

	var title := Label.new()
	title.text = "DEEP TRAUMA"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.75, 0.8, 0.75))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	_presets = OptionButton.new()
	_presets.fit_to_longest_item = true
	for p: Dictionary in PRESETS:
		_presets.add_item(str(p["name"]))
	_presets.select(_preset_index("Storm"))
	_presets.item_selected.connect(_apply_preset)
	vbox.add_child(_presets)

	_s_wind = _slider(vbox, "Wind Speed", "%.1f m/s", 0.0, 55.0, 0.5, 14.0, _on_sea_changed)
	_s_dir = _slider(vbox, "Wind Direction", "%.0f°", 0.0, 360.0, 1.0, 40.0, _on_sea_changed)
	_s_height = _slider(vbox, "Wave Height", "%.2fx", 0.0, 7.0, 0.05, 1.0, _on_sea_changed)
	_s_steep = _slider(vbox, "Wave Steepness", "%.2f", 0.0, 2.0, 0.05, 0.9, _on_sea_changed)
	_s_time = _slider(vbox, "Hour", "%.1f", 0.0, 24.0, 0.1, 20.2, func(v: float) -> void: weather.time_of_day = v)
	_s_fog = _slider(vbox, "Fog", "%.0f%%", 0.0, 100.0, 1.0, 45.0, func(v: float) -> void: weather.fog_amount = v / 100.0)
	_s_cloud = _slider(vbox, "Cloud", "%.0f%%", 0.0, 100.0, 1.0, 90.0, func(v: float) -> void: weather.cloud_cover = v / 100.0)
	_s_rain = _slider(vbox, "Rain", "%.0f%%", 0.0, 100.0, 1.0, 60.0, func(v: float) -> void: weather.rain_amount = v / 100.0)

	_c_storm = CheckButton.new()
	_c_storm.text = "Storm (lightning)"
	_c_storm.button_pressed = true
	_c_storm.toggled.connect(func(on: bool) -> void: weather.storm = on)
	vbox.add_child(_c_storm)


func _slider(parent: Control, label_text: String, fmt: String, minv: float, maxv: float,
		step: float, value: float, cb: Callable) -> HSlider:
	var lab := Label.new()
	lab.add_theme_font_size_override("font_size", 13)
	lab.add_theme_color_override("font_color", Color(0.72, 0.76, 0.72))
	lab.text = "%s: %s" % [label_text, fmt % value]
	parent.add_child(lab)

	var s := HSlider.new()
	s.min_value = minv
	s.max_value = maxv
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(0, 18)
	s.value_changed.connect(func(v: float) -> void:
		lab.text = "%s: %s" % [label_text, fmt % v]
		cb.call(v))
	parent.add_child(s)
	return s


func _on_sea_changed(_v: float) -> void:
	ocean.set_wind(_s_wind.value, _s_dir.value, _s_height.value, _s_steep.value)
	weather.set_wind(_s_wind.value, _s_dir.value)


func _preset_index(preset_name: String) -> int:
	for i in PRESETS.size():
		if str(PRESETS[i]["name"]) == preset_name:
			return i
	return 0


func _apply_preset(idx: int) -> void:
	if idx < 0 or idx >= PRESETS.size():
		return
	var p: Dictionary = PRESETS[idx]
	_set_all(
		float(p["wind"]), float(p["dir"]), float(p["height"]), float(p["steep"]),
		float(p["time"]), float(p["fog"]), float(p["cloud"]), float(p["rain"]),
		bool(p["storm"]))


func _set_all(wind: float, dir: float, height: float, steep: float, time: float,
		fog: float, cloud: float, rain: float, storm: bool) -> void:
	_s_wind.value = wind
	_s_dir.value = dir
	_s_height.value = height
	_s_steep.value = steep
	_s_time.value = time
	_s_fog.value = fog
	_s_cloud.value = cloud
	_s_rain.value = rain
	_c_storm.button_pressed = storm


func is_open() -> bool:
	## The camera asks: while this is up the mouse belongs to the sliders.
	return _panel != null and _panel.visible


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_panel") and _panel != null:
		_panel.visible = not _panel.visible
	if event.is_action_pressed("toggle_fps") and _fps_label != null:
		_fps_label.visible = not _fps_label.visible


func _process(delta: float) -> void:
	if _fps_label == null or not _fps_label.visible:
		return
	_fps_accum -= delta
	if _fps_accum <= 0.0:
		_fps_accum = 0.25
		_fps_label.text = "FPS: %d" % Engine.get_frames_per_second()
