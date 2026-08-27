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

# wind, dir, height, steep, time, fog%, cloud%, rain%, storm
const PRESETS: Array[Dictionary] = [
	{"name": "Sakin Gece", "wind": 4.0, "dir": 300.0, "height": 0.6, "steep": 0.6, "time": 22.5, "fog": 25.0, "cloud": 15.0, "rain": 0.0, "storm": false},
	{"name": "Puslu Akşam", "wind": 9.0, "dir": 120.0, "height": 0.9, "steep": 0.8, "time": 19.6, "fog": 60.0, "cloud": 55.0, "rain": 15.0, "storm": false},
	{"name": "Fırtına", "wind": 18.0, "dir": 40.0, "height": 1.2, "steep": 1.0, "time": 20.2, "fog": 45.0, "cloud": 90.0, "rain": 60.0, "storm": true},
	{"name": "Kâbus", "wind": 34.0, "dir": 75.0, "height": 3.2, "steep": 1.25, "time": 23.0, "fog": 75.0, "cloud": 100.0, "rain": 90.0, "storm": true},
	{"name": "Karanlık Deniz", "wind": 14.0, "dir": 50.0, "height": 1.15, "steep": 0.95, "time": 20.8, "fog": 42.0, "cloud": 82.0, "rain": 12.0, "storm": false},
	{"name": "Suskun Akşam", "wind": 2.5, "dir": 210.0, "height": 0.35, "steep": 0.5, "time": 18.9, "fog": 38.0, "cloud": 28.0, "rain": 0.0, "storm": false},
	{"name": "Alacakaranlık", "wind": 7.0, "dir": 280.0, "height": 0.75, "steep": 0.7, "time": 18.2, "fog": 48.0, "cloud": 58.0, "rain": 8.0, "storm": false},
	{"name": "Kanlı Gün Batımı", "wind": 8.0, "dir": 250.0, "height": 0.85, "steep": 0.75, "time": 18.5, "fog": 22.0, "cloud": 42.0, "rain": 0.0, "storm": false},
	{"name": "Şafak Pusu", "wind": 6.0, "dir": 15.0, "height": 0.55, "steep": 0.55, "time": 6.2, "fog": 82.0, "cloud": 68.0, "rain": 5.0, "storm": false},
	{"name": "Buzlu Tan", "wind": 11.0, "dir": 350.0, "height": 0.7, "steep": 0.65, "time": 5.6, "fog": 72.0, "cloud": 50.0, "rain": 8.0, "storm": false},
	{"name": "Çiseleyen Sabah", "wind": 7.5, "dir": 95.0, "height": 0.65, "steep": 0.6, "time": 7.8, "fog": 52.0, "cloud": 70.0, "rain": 38.0, "storm": false},
	{"name": "Öğlen Kapalı", "wind": 12.0, "dir": 180.0, "height": 1.0, "steep": 0.85, "time": 12.4, "fog": 32.0, "cloud": 88.0, "rain": 18.0, "storm": false},
	{"name": "İkindi Yağmuru", "wind": 9.0, "dir": 140.0, "height": 0.85, "steep": 0.8, "time": 15.6, "fog": 36.0, "cloud": 80.0, "rain": 55.0, "storm": false},
	{"name": "Sağanak", "wind": 15.0, "dir": 110.0, "height": 1.05, "steep": 0.95, "time": 11.2, "fog": 50.0, "cloud": 100.0, "rain": 92.0, "storm": false},
	{"name": "Muson", "wind": 11.0, "dir": 200.0, "height": 0.95, "steep": 0.9, "time": 10.0, "fog": 62.0, "cloud": 100.0, "rain": 85.0, "storm": false},
	{"name": "Karadeniz", "wind": 16.0, "dir": 20.0, "height": 1.15, "steep": 1.0, "time": 14.2, "fog": 40.0, "cloud": 78.0, "rain": 28.0, "storm": false},
	{"name": "Açık Deniz", "wind": 15.0, "dir": 265.0, "height": 1.65, "steep": 1.05, "time": 15.0, "fog": 18.0, "cloud": 48.0, "rain": 0.0, "storm": false},
	{"name": "Körfez", "wind": 3.5, "dir": 330.0, "height": 0.4, "steep": 0.45, "time": 19.8, "fog": 58.0, "cloud": 38.0, "rain": 0.0, "storm": false},
	{"name": "Sis Duvarı", "wind": 5.0, "dir": 85.0, "height": 0.5, "steep": 0.5, "time": 19.0, "fog": 96.0, "cloud": 92.0, "rain": 10.0, "storm": false},
	{"name": "Durgun Cam", "wind": 0.8, "dir": 0.0, "height": 0.15, "steep": 0.35, "time": 21.2, "fog": 12.0, "cloud": 6.0, "rain": 0.0, "storm": false},
	{"name": "Ölüm Sükûneti", "wind": 1.2, "dir": 160.0, "height": 0.22, "steep": 0.4, "time": 0.4, "fog": 8.0, "cloud": 0.0, "rain": 0.0, "storm": false},
	{"name": "Yıldızlı Gece", "wind": 5.5, "dir": 310.0, "height": 0.7, "steep": 0.65, "time": 23.4, "fog": 10.0, "cloud": 8.0, "rain": 0.0, "storm": false},
	{"name": "Ay Işığı", "wind": 6.5, "dir": 240.0, "height": 0.8, "steep": 0.7, "time": 23.8, "fog": 18.0, "cloud": 22.0, "rain": 0.0, "storm": false},
	{"name": "Gece Yarısı", "wind": 11.0, "dir": 55.0, "height": 1.25, "steep": 0.95, "time": 0.0, "fog": 38.0, "cloud": 70.0, "rain": 18.0, "storm": false},
	{"name": "Kara Su", "wind": 13.0, "dir": 48.0, "height": 1.1, "steep": 0.92, "time": 21.0, "fog": 40.0, "cloud": 86.0, "rain": 8.0, "storm": false},
	{"name": "Hortum Öncesi", "wind": 22.0, "dir": 65.0, "height": 1.55, "steep": 1.08, "time": 17.4, "fog": 34.0, "cloud": 96.0, "rain": 42.0, "storm": false},
	{"name": "Gök Gürültüsü", "wind": 19.0, "dir": 35.0, "height": 1.15, "steep": 1.0, "time": 20.5, "fog": 42.0, "cloud": 95.0, "rain": 52.0, "storm": true},
	{"name": "Kıyı Fırtınası", "wind": 21.0, "dir": 90.0, "height": 1.85, "steep": 1.12, "time": 19.2, "fog": 55.0, "cloud": 88.0, "rain": 72.0, "storm": true},
	{"name": "Kuzey Rüzgârı", "wind": 28.0, "dir": 0.0, "height": 0.95, "steep": 0.88, "time": 16.0, "fog": 24.0, "cloud": 58.0, "rain": 12.0, "storm": false},
	{"name": "Uçurum Dalgası", "wind": 24.0, "dir": 130.0, "height": 4.2, "steep": 1.35, "time": 16.5, "fog": 28.0, "cloud": 68.0, "rain": 22.0, "storm": false},
	{"name": "Beyaz Fırtına", "wind": 38.0, "dir": 70.0, "height": 2.8, "steep": 1.2, "time": 13.2, "fog": 55.0, "cloud": 100.0, "rain": 100.0, "storm": true},
	{"name": "Kırık Direk", "wind": 30.0, "dir": 80.0, "height": 2.45, "steep": 1.18, "time": 21.6, "fog": 62.0, "cloud": 96.0, "rain": 78.0, "storm": true},
	{"name": "Açık Ufuk", "wind": 10.0, "dir": 220.0, "height": 0.9, "steep": 0.8, "time": 16.8, "fog": 12.0, "cloud": 32.0, "rain": 0.0, "storm": false},
	{"name": "Cam Göbeği", "wind": 8.0, "dir": 175.0, "height": 0.55, "steep": 0.55, "time": 8.6, "fog": 22.0, "cloud": 38.0, "rain": 0.0, "storm": false},
]


func setup(o: Node3D, w: Node3D) -> void:
	add_to_group("ui_panel")
	ocean = o
	weather = w
	_build()
	_apply_preset(_preset_index("Fırtına"))


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

	var help := Label.new()
	help.text = "W/S: ileri-geri   A/D: dümen   F: kamera   Serbest: Q dal / E çık   Tab: panel"
	help.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	help.position = Vector2(12, -34)
	help.add_theme_color_override("font_color", Color(0.65, 0.68, 0.65))
	help.add_theme_font_size_override("font_size", 13)
	add_child(help)

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
	title.text = "KARANLIK DENİZ"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.75, 0.8, 0.75))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	_presets = OptionButton.new()
	_presets.fit_to_longest_item = true
	for p: Dictionary in PRESETS:
		_presets.add_item(str(p["name"]))
	_presets.select(_preset_index("Fırtına"))
	_presets.item_selected.connect(_apply_preset)
	vbox.add_child(_presets)

	_s_wind = _slider(vbox, "Rüzgar Hızı", "%.1f m/s", 0.0, 40.0, 0.5, 14.0, _on_sea_changed)
	_s_dir = _slider(vbox, "Rüzgar Yönü", "%.0f°", 0.0, 360.0, 1.0, 40.0, _on_sea_changed)
	_s_height = _slider(vbox, "Dalga Yüksekliği", "%.2fx", 0.0, 5.0, 0.05, 1.0, _on_sea_changed)
	_s_steep = _slider(vbox, "Dalga Dikliği", "%.2f", 0.0, 1.6, 0.05, 0.9, _on_sea_changed)
	_s_time = _slider(vbox, "Saat", "%.1f", 0.0, 24.0, 0.1, 20.2, func(v: float) -> void: weather.time_of_day = v)
	_s_fog = _slider(vbox, "Sis", "%.0f%%", 0.0, 100.0, 1.0, 45.0, func(v: float) -> void: weather.fog_amount = v / 100.0)
	_s_cloud = _slider(vbox, "Bulut", "%.0f%%", 0.0, 100.0, 1.0, 90.0, func(v: float) -> void: weather.cloud_cover = v / 100.0)
	_s_rain = _slider(vbox, "Yağmur", "%.0f%%", 0.0, 100.0, 1.0, 60.0, func(v: float) -> void: weather.rain_amount = v / 100.0)

	_c_storm = CheckButton.new()
	_c_storm.text = "Fırtına (şimşek)"
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


func _process(delta: float) -> void:
	_fps_accum -= delta
	if _fps_accum <= 0.0 and _fps_label != null:
		_fps_accum = 0.25
		_fps_label.text = "FPS: %d" % Engine.get_frames_per_second()
