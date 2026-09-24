class_name TouchControls
extends CanvasLayer
## 画面のボタン。左に ← →、右に B(ダッシュ)と A(ジャンプ)。

const SIZE := 150.0
const MARGIN := 40.0

var _buttons := {}


func _ready() -> void:
	_buttons["move_left"] = _make("←", Color(1, 1, 1, 0.35))
	_buttons["move_right"] = _make("→", Color(1, 1, 1, 0.35))
	_buttons["move_down"] = _make("↓", Color(1, 1, 1, 0.35))
	_buttons["run"] = _make("B", Color(1.0, 0.85, 0.3, 0.45))
	_buttons["jump"] = _make("A", Color(0.4, 0.8, 1.0, 0.45))
	for action in _buttons:
		(_buttons[action] as TouchScreenButton).action = action
	get_viewport().size_changed.connect(_layout)
	_layout()


func _make(text: String, color: Color) -> TouchScreenButton:
	var b := TouchScreenButton.new()
	var tex := GradientTexture2D.new()
	tex.width = int(SIZE)
	tex.height = int(SIZE)
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, color)
	g.set_color(1, Color(color, 0.0))
	g.add_point(0.95, color)
	tex.gradient = g
	b.texture_normal = tex
	b.passby_press = true
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 56)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = Vector2(SIZE, SIZE)
	b.add_child(label)
	add_child(b)
	return b


func _layout() -> void:
	var vs := get_viewport().get_visible_rect().size
	var bottom := vs.y - SIZE - MARGIN
	(_buttons["move_left"] as Node2D).position = Vector2(MARGIN, bottom)
	(_buttons["move_right"] as Node2D).position = Vector2(MARGIN + SIZE * 2 + 40, bottom)
	(_buttons["move_down"] as Node2D).position = Vector2(MARGIN + SIZE + 20, bottom + 20)
	(_buttons["run"] as Node2D).position = Vector2(vs.x - MARGIN - SIZE * 2 - 20, bottom + 30)
	(_buttons["jump"] as Node2D).position = Vector2(vs.x - MARGIN - SIZE, bottom - 30)
