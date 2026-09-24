class_name SettingsPanel
extends CanvasLayer
## 右上の歯車ボタンで開く調整パネル。ボタンの大きさ・位置・振動と、動きの数値を実機で変えられる。
## 開いている間はゲームを一時停止する。

var _panel: PanelContainer
var _gear: Button


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_gear = Button.new()
	_gear.text = " SET "
	_gear.add_theme_font_size_override("font_size", 28)
	_gear.pressed.connect(_toggle)
	add_child(_gear)
	get_viewport().size_changed.connect(_layout)
	_build()
	_layout()


func _layout() -> void:
	var vs := get_viewport().get_visible_rect().size
	_gear.position = Vector2(vs.x - 90, 70)
	_panel.position = Vector2(vs.x * 0.12, vs.y * 0.05)
	_panel.size = Vector2(vs.x * 0.76, vs.y * 0.9)


func _toggle() -> void:
	_panel.visible = not _panel.visible
	get_tree().paused = _panel.visible
	if not _panel.visible:
		ControlSettings.save_settings()


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.visible = false
	add_child(_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	scroll.add_child(box)

	_title(box, "CONTROLS")
	_slider(box, "Button size", 0.6, 1.6, ControlSettings.size_scale, func(v: float) -> void:
		ControlSettings.size_scale = v
		ControlSettings.changed.emit())
	_slider(box, "Button opacity", 0.15, 1.0, ControlSettings.opacity, func(v: float) -> void:
		ControlSettings.opacity = v
		ControlSettings.changed.emit())
	_slider(box, "Distance from edge", 0.08, 0.3, ControlSettings.dpad_x, func(v: float) -> void:
		ControlSettings.dpad_x = v
		ControlSettings.changed.emit())
	_slider(box, "Height", 0.5, 0.9, ControlSettings.pad_y, func(v: float) -> void:
		ControlSettings.pad_y = v
		ControlSettings.changed.emit())
	_slider(box, "Zoom (tiles on screen, original=12)", 7.0, 12.0, ControlSettings.view_tiles, func(v: float) -> void:
		ControlSettings.view_tiles = v)
	var vib := CheckButton.new()
	vib.text = "Vibration"
	vib.button_pressed = ControlSettings.vibration
	vib.toggled.connect(func(on: bool) -> void: ControlSettings.vibration = on)
	box.add_child(vib)

	_title(box, "MOVEMENT (tiles / seconds)")
	for key in ControlSettings.TUNABLE:
		var r: Array = ControlSettings.TUNABLE[key]
		_slider(box, key, r[0], r[1], Tuning.get_value(key), func(v: float) -> void: Tuning.set_value(key, v))
	var reset := Button.new()
	reset.text = "Reset movement to default"
	reset.pressed.connect(func() -> void:
		ControlSettings.reset_tuning()
		_panel.queue_free()
		_build()
		_layout()
		_panel.visible = true)
	box.add_child(reset)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(_toggle)
	box.add_child(close)


func _title(box: VBoxContainer, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 28)
	box.add_child(l)


func _slider(box: VBoxContainer, label: String, lo: float, hi: float, value: float, on_change: Callable) -> void:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.custom_minimum_size = Vector2(320, 0)
	l.add_theme_font_size_override("font_size", 22)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = (hi - lo) / 100.0
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(0, 48)
	var show := func(v: float) -> void: l.text = "%s  %.2f" % [label, v]
	show.call(value)
	s.value_changed.connect(func(v: float) -> void:
		show.call(v)
		on_change.call(v))
	row.add_child(s)
	box.add_child(row)
