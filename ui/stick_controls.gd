class_name StickControls
extends CanvasLayer
## 左スティック+右タップの操作。
##   左半分: 触れた所にスティックが出る。少し倒す=歩き、大きく倒す=自動でダッシュ、下=しゃがみ/空中ならヒップドロップ
##   右半分: どこでも触れればジャンプ(長押しで高く)
## 何を入力しているかを常に表示する:
##   親指の下にスティックの輪と玉(ダッシュ中はオレンジ色+「ダッシュ」)、右親指の下に波紋と「ジャンプ」、
##   画面下中央に今の入力(← → ↓ ダッシュ ジャンプ)。入力が始まった瞬間に振動する。

const WALK_AT := 0.22       ## スティックをこの割合以上倒すと歩き
const RUN_AT := 0.72        ## この割合以上でダッシュ
const DOWN_AT := 0.55       ## 下方向にこの割合以上でしゃがみ/ヒップドロップ

var _stick_finger := -1
var _anchor := Vector2.ZERO
var _knob := Vector2.ZERO
var _jump_fingers := {}     ## 指の番号 -> 触れた位置
var _state := {}            ## いま押している action -> true
var _view: _View


func _ready() -> void:
	layer = 5
	_view = _View.new()
	_view.ctl = self
	add_child(_view)
	ControlSettings.changed.connect(_view.queue_redraw)


func radius() -> float:
	return 95.0 * ControlSettings.size_scale * _view.get_viewport_rect().size.y / 720.0


func _input(event: InputEvent) -> void:
	var half := _view.get_viewport_rect().size.x * 0.5
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			if t.position.x < half and _stick_finger < 0:
				_stick_finger = t.index
				_anchor = t.position
				_knob = t.position
			elif t.position.x >= half:
				_jump_fingers[t.index] = t.position
		else:
			if t.index == _stick_finger:
				_stick_finger = -1
			_jump_fingers.erase(t.index)
		_refresh()
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _stick_finger:
			var v := d.position - _anchor
			var r := radius()
			if v.length() > r * 1.4:
				_anchor = d.position - v.normalized() * r * 1.4   # 指が大きく動いたらスティックごと付いていく
			_knob = d.position
			_refresh()
			get_viewport().set_input_as_handled()
		elif _jump_fingers.has(d.index):
			_jump_fingers[d.index] = d.position


## スティックの傾き(-1〜1)
func stick() -> Vector2:
	if _stick_finger < 0:
		return Vector2.ZERO
	var v := (_knob - _anchor) / radius()
	return v.limit_length(1.0)


func _refresh() -> void:
	var v := stick()
	var want := {}
	if v.x < -WALK_AT:
		want["move_left"] = true
	if v.x > WALK_AT:
		want["move_right"] = true
	if absf(v.x) > RUN_AT:
		want["run"] = true
	if v.y > DOWN_AT and v.y > absf(v.x) * 0.8:
		want["move_down"] = true
	if not _jump_fingers.is_empty():
		want["jump"] = true

	var buzz := false
	for a in want:
		if not _state.has(a):
			Input.action_press(a)
			if a in ["jump", "run", "move_down"]:
				buzz = true
	for a in _state.keys():
		if not want.has(a):
			Input.action_release(a)
	_state = want
	if buzz and ControlSettings.vibration:
		Input.vibrate_handheld(ControlSettings.VIBRATE_MS)
	_view.queue_redraw()


func is_on(action: String) -> bool:
	return _state.has(action)


## 描画
class _View extends Control:
	var ctl: StickControls

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var a := ControlSettings.opacity
		var vs := get_viewport_rect().size
		var font := get_theme_default_font()
		var s := vs.y / 720.0
		var r := ctl.radius()

		# 左: スティック(触れていないときは置き場所の目安だけ薄く表示)
		if ctl._stick_finger >= 0:
			var run := ctl.is_on("run")
			var col := Color(1.0, 0.6, 0.15, a + 0.2) if run else Color(1, 1, 1, a)
			draw_arc(ctl._anchor, r, 0, TAU, 48, col, 6.0 * s, true)
			draw_circle(ctl._anchor, r * 0.12, Color(col, a * 0.6))
			var knob := ctl._anchor + ctl.stick() * r
			draw_circle(knob, r * 0.42, col)
			if run:
				_label(font, "ダッシュ", knob + Vector2(0, -r * 0.62), int(30 * s), Color(1, 0.8, 0.4))
			if ctl.is_on("move_down"):
				_label(font, "↓", knob + Vector2(0, r * 0.85), int(36 * s), Color.WHITE)
		else:
			var hint := Vector2(vs.x * 0.16, vs.y * ControlSettings.pad_y)
			draw_arc(hint, r, 0, TAU, 48, Color(1, 1, 1, a * 0.35), 3.0 * s, true)
			_label(font, "いどう", hint, int(24 * s), Color(1, 1, 1, a * 0.6))

		# 右: ジャンプ(触れている指の下に波紋)
		if ctl._jump_fingers.is_empty():
			var hint2 := Vector2(vs.x * 0.84, vs.y * ControlSettings.pad_y)
			draw_arc(hint2, r * 0.8, 0, TAU, 48, Color(1, 1, 1, a * 0.35), 3.0 * s, true)
			_label(font, "ジャンプ", hint2, int(24 * s), Color(1, 1, 1, a * 0.6))
		for p in ctl._jump_fingers.values():
			draw_circle(p, r * 0.55, Color(0.35, 0.65, 1.0, a + 0.1))
			draw_arc(p, r * 0.8, 0, TAU, 48, Color(0.6, 0.85, 1.0, a + 0.2), 5.0 * s, true)
			_label(font, "ジャンプ", p + Vector2(0, -r * 0.95), int(30 * s), Color(0.8, 0.92, 1.0))

		# 画面下中央: 今の入力
		var items := [["←", "move_left"], ["→", "move_right"], ["↓", "move_down"], ["ダッシュ", "run"], ["ジャンプ", "jump"]]
		var x := vs.x * 0.5 - 250.0 * s
		for it in items:
			var on := ctl.is_on(it[1])
			var fs := int(26 * s)
			var w := font.get_string_size(it[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 20.0 * s
			var rect := Rect2(x, vs.y - 46.0 * s, w, 38.0 * s)
			draw_rect(rect, Color(1.0, 0.7, 0.2, 0.9) if on else Color(0, 0, 0, 0.35))
			draw_string(font, Vector2(x + 10.0 * s, vs.y - 18.0 * s), it[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
				Color.BLACK if on else Color(1, 1, 1, 0.7))
			x += w + 8.0 * s

	func _label(font: Font, text: String, center: Vector2, size: int, col: Color) -> void:
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		draw_string_outline(font, center + Vector2(-w * 0.5, size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 6, Color(0, 0, 0, 0.7))
		draw_string(font, center + Vector2(-w * 0.5, size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

	func _process(_dt: float) -> void:
		if not ctl._jump_fingers.is_empty() or ctl._stick_finger >= 0:
			queue_redraw()
