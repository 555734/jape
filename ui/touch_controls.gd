class_name TouchControls
extends CanvasLayer
## DS に近いタッチ操作。
##   左: 十字キー(1枚の十字。指を滑らせて方向を変えられ、斜めも入る)
##   右: A/B/X/Y のひし形。B・A=ジャンプ、Y・X=ダッシュ(原作と同じ割り当て)
##       B と Y の間を指の腹で押すと両方同時に押せる(ダッシュしながらジャンプ)
##   押した瞬間に短く振動し、ボタンが沈んで暗くなる。
## 大きさ・透明度・振動は ControlSettings で変えられる。

const ACTIONS := {"A": "jump", "B": "jump", "X": "run", "Y": "run"}

var _pad: _Pad
var _fingers := {}          ## 指の番号 -> {"kind": "dpad"/"buttons", "pos": Vector2}
var _pressed_actions := {}  ## いま押している action -> true


func _ready() -> void:
	layer = 5
	_pad = _Pad.new()
	_pad.owner_controls = self
	add_child(_pad)
	ControlSettings.changed.connect(_pad.queue_redraw)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			var kind := _pad.region(t.position)
			if kind != "":
				_fingers[t.index] = {"kind": kind, "pos": t.position}
				get_viewport().set_input_as_handled()
		else:
			_fingers.erase(t.index)
		_refresh()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if _fingers.has(d.index):
			_fingers[d.index].pos = d.position
			_refresh()
			get_viewport().set_input_as_handled()


## 今の指の位置から、押している方向・ボタンを計算して Input に反映する
func _refresh() -> void:
	var dirs := {}
	var buttons := {}
	for f in _fingers.values():
		if f.kind == "dpad":
			for dname in _pad.dpad_dirs(f.pos):
				dirs[dname] = true
		else:
			for b in _pad.buttons_at(f.pos):
				buttons[b] = true

	var want := {}
	if dirs.has("left"):
		want["move_left"] = true
	if dirs.has("right"):
		want["move_right"] = true
	if dirs.has("down"):
		want["move_down"] = true
	for b in buttons:
		want[ACTIONS[b]] = true

	var newly := false
	for a in want:
		if not _pressed_actions.has(a):
			Input.action_press(a)
			newly = true
	for a in _pressed_actions.keys():
		if not want.has(a):
			Input.action_release(a)
	var newly_button := false
	for b in buttons:
		if not _pad.pressed_buttons.has(b):
			newly_button = true
	var newly_dir := false
	for dname in dirs:
		if not _pad.pressed_dirs.has(dname):
			newly_dir = true
	_pressed_actions = want
	_pad.pressed_buttons = buttons
	_pad.pressed_dirs = dirs
	_pad.queue_redraw()
	if ControlSettings.vibration and (newly_button or newly_dir):
		Input.vibrate_handheld(ControlSettings.VIBRATE_MS if newly_button else ControlSettings.VIBRATE_MS / 2)


## 描画と当たり範囲
class _Pad extends Control:
	var owner_controls: TouchControls
	var pressed_buttons := {}
	var pressed_dirs := {}

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		get_viewport().size_changed.connect(queue_redraw)

	func _s() -> float:
		return ControlSettings.size_scale * get_viewport_rect().size.y / 720.0

	func dpad_center() -> Vector2:
		var vs := get_viewport_rect().size
		return Vector2(vs.x * ControlSettings.dpad_x, vs.y * ControlSettings.pad_y)

	func buttons_center() -> Vector2:
		var vs := get_viewport_rect().size
		return Vector2(vs.x * (1.0 - ControlSettings.dpad_x), vs.y * ControlSettings.pad_y)

	func dpad_radius() -> float:
		return 115.0 * _s()

	func button_radius() -> float:
		return 44.0 * _s()

	func button_offset() -> float:
		return 62.0 * _s()

	func button_pos(b: String) -> Vector2:
		var c := buttons_center()
		var o := button_offset()
		match b:
			"A":
				return c + Vector2(o, 0)
			"B":
				return c + Vector2(0, o)
			"X":
				return c + Vector2(0, -o)
			_:
				return c + Vector2(-o, 0)

	## 指が置かれた場所が十字キー側かボタン側か。どちらでもなければ ""
	func region(p: Vector2) -> String:
		if p.distance_to(dpad_center()) < dpad_radius() * 1.6:
			return "dpad"
		if p.distance_to(buttons_center()) < (button_offset() + button_radius()) * 1.5:
			return "buttons"
		# 画面の左右下半分は広めに受け付ける
		var vs := get_viewport_rect().size
		if p.y > vs.y * 0.45:
			return "dpad" if p.x < vs.x * 0.5 else "buttons"
		return ""

	## 十字キーの方向(8方向。斜めは2方向同時)
	func dpad_dirs(p: Vector2) -> Array:
		var v := p - dpad_center()
		var r := dpad_radius()
		if v.length() < r * 0.18:
			return []
		var out := []
		var a := v.angle()   # 右=0, 下=+PI/2
		var deg := rad_to_deg(a)
		if deg > -67.5 and deg < 67.5:
			out.append("right")
		if deg > 112.5 or deg < -112.5:
			out.append("left")
		if deg > 22.5 and deg < 157.5:
			out.append("down")
		if deg < -22.5 and deg > -157.5:
			out.append("up")
		return out

	## 指の位置で押されるボタン。2つのボタンの間なら両方
	func buttons_at(p: Vector2) -> Array:
		var r := button_radius()
		var dists := []
		for b in ["A", "B", "X", "Y"]:
			dists.append([p.distance_to(button_pos(b)), b])
		dists.sort_custom(func(x, y): return x[0] < y[0])
		var out := []
		if dists[0][0] < r * 1.5:
			out.append(dists[0][1])
			# 2番目に近いボタンとの中間付近なら同時押し
			if dists[1][0] < r * 1.35 and absf(dists[1][0] - dists[0][0]) < r * 0.6:
				out.append(dists[1][1])
		return out

	func _draw() -> void:
		var alpha := ControlSettings.opacity
		# 十字キー
		var c := dpad_center()
		var r := dpad_radius()
		var w := r * 0.62
		var base := Color(0.15, 0.15, 0.18, alpha)
		var edge := Color(1, 1, 1, alpha * 0.9)
		draw_rect(Rect2(c.x - w / 2, c.y - r, w, r * 2), base)
		draw_rect(Rect2(c.x - r, c.y - w / 2, r * 2, w), base)
		for dname in ["up", "down", "left", "right"]:
			var dv: Vector2 = {"up": Vector2.UP, "down": Vector2.DOWN, "left": Vector2.LEFT, "right": Vector2.RIGHT}[dname]
			var tip := c + dv * r * 0.78
			var side := dv.orthogonal() * w * 0.28
			var col := Color(1, 0.85, 0.3, alpha) if pressed_dirs.has(dname) else edge
			draw_colored_polygon(PackedVector2Array([tip, tip - dv * w * 0.36 + side, tip - dv * w * 0.36 - side]), col)
			if pressed_dirs.has(dname):
				var seg := Rect2(c + dv * r * 0.5 - Vector2(w, w) * 0.5, Vector2(w, w))
				draw_rect(seg, Color(0, 0, 0, alpha * 0.35))
		draw_circle(c, w * 0.22, Color(0, 0, 0, alpha * 0.4))

		# A/B/X/Y
		var font := ThemeDB.fallback_font
		for b in ["A", "B", "X", "Y"]:
			var p := button_pos(b)
			var down := pressed_buttons.has(b)
			var jump: bool = ACTIONS[b] == "jump"
			var col := Color(0.3, 0.6, 1.0, alpha) if jump else Color(1.0, 0.75, 0.25, alpha)
			if down:
				col = col.darkened(0.45)
			var br := button_radius() * (0.9 if down else 1.0)
			draw_circle(p + Vector2(0, 4 * _s()), br, Color(0, 0, 0, alpha * 0.35))   # 影
			draw_circle(p + (Vector2(0, 3 * _s()) if down else Vector2.ZERO), br, col)
			var fs := int(34 * _s())
			var ts := font.get_string_size(b, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
			draw_string(font, p + Vector2(-ts.x / 2, fs * 0.35) + (Vector2(0, 3 * _s()) if down else Vector2.ZERO),
				b, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, minf(1.0, alpha + 0.3)))
		# 割り当ての小さな説明
		var small := int(18 * _s())
		var bc := buttons_center()
		draw_string(font, bc + Vector2(-button_offset() * 1.7, button_offset() * 1.9), "B/A: JUMP   Y/X: DASH",
			HORIZONTAL_ALIGNMENT_LEFT, -1, small, Color(1, 1, 1, alpha * 0.8))
