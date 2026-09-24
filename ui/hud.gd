class_name Hud
extends CanvasLayer
## 画面表示 docs/RULES.md §10
##   左上: 1Pのスター・残機  中央上: 1Pのコイン x/8  右上: 2P  最上部: ステージ全体のバー  中央: ラウンド結果

const P1_COLOR := Color(0.35, 0.7, 1.0)
const P2_COLOR := Color(1.0, 0.45, 0.4)
const STAR_COLOR := Color(1.0, 0.85, 0.2)

var _left: Label
var _right: Label
var _coin: Label
var _banner: Label
var _status: Label
var _bar: ColorRect
var _dots := {}


func _ready() -> void:
	_left = _label(32, HORIZONTAL_ALIGNMENT_LEFT)
	_right = _label(32, HORIZONTAL_ALIGNMENT_RIGHT)
	_coin = _label(32, HORIZONTAL_ALIGNMENT_CENTER)
	_banner = _label(72, HORIZONTAL_ALIGNMENT_CENTER)
	_status = _label(22, HORIZONTAL_ALIGNMENT_LEFT)
	_status.visible = false
	_left.add_theme_color_override("font_color", P1_COLOR)
	_right.add_theme_color_override("font_color", P2_COLOR)
	_bar = ColorRect.new()
	_bar.color = Color(0, 0, 0, 0.35)
	add_child(_bar)
	for key in ["p1", "p2", "star"]:
		var d := ColorRect.new()
		d.size = Vector2(14, 14)
		d.color = {"p1": P1_COLOR, "p2": P2_COLOR, "star": STAR_COLOR}[key]
		_bar.add_child(d)
		_dots[key] = d
	get_viewport().size_changed.connect(_layout)
	_layout()


func _label(size: int, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 8)
	l.horizontal_alignment = align
	add_child(l)
	return l


func _layout() -> void:
	var vs := get_viewport().get_visible_rect().size
	_bar.position = Vector2(vs.x * 0.25, 6)
	_bar.size = Vector2(vs.x * 0.5, 14)
	_left.position = Vector2(20, 26)
	_left.size = Vector2(vs.x * 0.4, 40)
	_right.position = Vector2(vs.x * 0.6 - 20, 26)
	_right.size = Vector2(vs.x * 0.4, 40)
	_coin.position = Vector2(vs.x * 0.3, 26)
	_coin.size = Vector2(vs.x * 0.4, 40)
	_banner.position = Vector2(0, vs.y * 0.3)
	_banner.size = Vector2(vs.x, 200)
	_status.position = Vector2(20, 70)
	_status.size = Vector2(vs.x * 0.5, 30)


func update(r: MatchRules, xs: Array, star_x: float, width: float, me := 0) -> void:
	_left.text = "1P  STAR %d/%d  LIFE %s" % [r.stars[0], r.stars_to_win, _lives(r, 0)]
	_right.text = "2P  STAR %d/%d  LIFE %s" % [r.stars[1], r.stars_to_win, _lives(r, 1)]
	_coin.text = "COIN %d/8" % r.coins[me]   # 自分のコイン
	var w := _bar.size.x
	(_dots["p1"] as ColorRect).position = Vector2(xs[0] / width * w - 7, 0)
	(_dots["p2"] as ColorRect).position = Vector2(xs[1] / width * w - 7, 0)
	(_dots["star"] as ColorRect).visible = star_x >= 0.0
	(_dots["star"] as ColorRect).position = Vector2(star_x / width * w - 7, 0)


func _lives(r: MatchRules, p: int) -> String:
	return "INF" if r.start_lives < 0 else str(r.lives[p])


func show_banner(text: String) -> void:
	_banner.text = text
	_banner.visible = text != ""


## 通信の状態(ping など)。空なら出さない
func show_status(text: String) -> void:
	_status.text = text
	_status.visible = text != ""
