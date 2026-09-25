class_name SettingsPanel
extends CanvasLayer
## 右上の「設定」ボタンで開く調整パネル(日本語)。開いている間はゲームを一時停止する。
##   ・操作方式、ボタン/スティックの大きさ・濃さ・位置、カメラの寄り、振動
##   ・動きの数値(ジャンプの高さ・重力など)
##   ・「設定をコピー」: 全部の数値を文字でコピー。チャットに貼れば開発側で読める
##   ・「貼り付けて読み込む」: コピーした文字を読み込む
##   ・「不具合報告をコピー」: 今の位置・状態・描画方式・GPU名などをコピー

var report_source: Callable   ## 不具合報告の文字を返す関数(main.gd が設定)

var _panel: PanelContainer
var _gear: Button
var _msg: Label


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_gear = Button.new()
	_gear.text = " 設定 "
	_gear.add_theme_font_size_override("font_size", 28)
	_gear.pressed.connect(_toggle)
	add_child(_gear)
	get_viewport().size_changed.connect(_layout)
	_build()
	_layout()


func _layout() -> void:
	var vs := get_viewport().get_visible_rect().size
	_gear.position = Vector2(vs.x - 110, 70)
	_panel.position = Vector2(vs.x * 0.1, vs.y * 0.04)
	_panel.size = Vector2(vs.x * 0.8, vs.y * 0.92)


func _toggle() -> void:
	_panel.visible = not _panel.visible
	get_tree().paused = _panel.visible
	if not _panel.visible:
		ControlSettings.save_settings()


func _rebuild() -> void:
	var was := _panel.visible
	_panel.queue_free()
	_build()
	_layout()
	_panel.visible = was


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

	var top := HBoxContainer.new()
	box.add_child(top)
	_button(top, "閉じる", _toggle)
	_button(top, "設定をコピー", func() -> void:
		DisplayServer.clipboard_set(ControlSettings.export_text())
		_msg.text = "コピーしました。チャットに貼り付けて送ってください")
	_button(top, "貼り付けて読み込む", func() -> void:
		if ControlSettings.import_text(DisplayServer.clipboard_get()):
			_rebuild()
			_msg.text = "読み込みました"
		else:
			_msg.text = "読み込めませんでした(「設定をコピー」で作った文字をコピーしてから押してください)")
	_button(top, "不具合報告をコピー", func() -> void:
		var text := "JAPE_REPORT\n" + ControlSettings.export_text()
		if report_source.is_valid():
			text += "\n" + str(report_source.call())
		DisplayServer.clipboard_set(text)
		_msg.text = "不具合報告をコピーしました。チャットに貼り付けて送ってください")
	_msg = Label.new()
	_msg.add_theme_font_size_override("font_size", 22)
	_msg.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	box.add_child(_msg)

	_title(box, "操作")
	var mode := OptionButton.new()
	mode.add_item("左スティック + 右タップ")
	mode.add_item("DS配置のボタン")
	mode.selected = 0 if ControlSettings.control_mode == "stick" else 1
	mode.add_theme_font_size_override("font_size", 24)
	mode.item_selected.connect(func(i: int) -> void:
		ControlSettings.control_mode = "stick" if i == 0 else "buttons"
		ControlSettings.save_settings())
	box.add_child(mode)
	_slider(box, "スティック/ボタンの大きさ", 0.6, 1.6, ControlSettings.size_scale, func(v: float) -> void:
		ControlSettings.size_scale = v
		ControlSettings.changed.emit())
	_slider(box, "表示の濃さ", 0.15, 1.0, ControlSettings.opacity, func(v: float) -> void:
		ControlSettings.opacity = v
		ControlSettings.changed.emit())
	_slider(box, "ボタンの横位置(ボタン式のみ)", 0.08, 0.3, ControlSettings.dpad_x, func(v: float) -> void:
		ControlSettings.dpad_x = v
		ControlSettings.changed.emit())
	_slider(box, "表示の高さ", 0.5, 0.9, ControlSettings.pad_y, func(v: float) -> void:
		ControlSettings.pad_y = v
		ControlSettings.changed.emit())
	_slider(box, "カメラの寄り(画面の縦のマス数。原作は12)", 7.0, 12.0, ControlSettings.view_tiles, func(v: float) -> void:
		ControlSettings.view_tiles = v)
	var fps := CheckButton.new()
	fps.text = "FPSを表示(60未満なら処理落ち)"
	fps.add_theme_font_size_override("font_size", 24)
	fps.button_pressed = ControlSettings.show_fps
	fps.toggled.connect(func(on: bool) -> void: ControlSettings.show_fps = on)
	box.add_child(fps)
	var vib := CheckButton.new()
	vib.text = "振動"
	vib.add_theme_font_size_override("font_size", 24)
	vib.button_pressed = ControlSettings.vibration
	vib.toggled.connect(func(on: bool) -> void: ControlSettings.vibration = on)
	box.add_child(vib)

	_title(box, "動きの数値")
	for key in ControlSettings.TUNABLE:
		var r: Array = ControlSettings.TUNABLE[key]
		_slider(box, ControlSettings.LABELS.get(key, key), r[0], r[1], Tuning.get_value(key),
			func(v: float) -> void: Tuning.set_value(key, v))
	_button(box, "動きの数値を最初に戻す", func() -> void:
		ControlSettings.reset_tuning()
		_rebuild())
	_msg.text = "※操作方式の変更は、次にアプリを起動したときに反映されます"


func _button(parent: Control, text: String, on_press: Callable) -> void:
	var b := Button.new()
	b.text = " %s " % text
	b.add_theme_font_size_override("font_size", 24)
	b.pressed.connect(on_press)
	parent.add_child(b)


func _title(box: VBoxContainer, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 30)
	box.add_child(l)


func _slider(box: VBoxContainer, label: String, lo: float, hi: float, value: float, on_change: Callable) -> void:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.custom_minimum_size = Vector2(460, 0)
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
