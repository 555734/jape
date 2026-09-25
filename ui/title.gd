extends Control
## タイトル画面。CPU と対戦 / オンライン対戦(部屋を作る・コードで入る)を選ぶ。
## オンラインは net/online.gd(Autoload "Online")が相手とつなぎ、つながったら試合の画面(main.tscn)へ進む。
## 起動オプション(--sim など開発用)が付いているときは、すぐ試合の画面へ進む。

const GAME_SCENE := "res://main.tscn"

var _menu: VBoxContainer
var _online: VBoxContainer
var _lan: VBoxContainer
var _wait: VBoxContainer
var _code: LineEdit
var _ip: LineEdit
var _status: Label
var _note: Label


func _ready() -> void:
	if not OS.get_cmdline_user_args().is_empty():
		get_tree().change_scene_to_file.call_deferred(GAME_SCENE)
		return
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.55, 0.78, 0.98)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var credit := Label.new()
	credit.text = "Character: PolyOne Studio  ·  CC BY 4.0"
	credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	credit.add_theme_font_size_override("font_size", 17)
	credit.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	credit.add_theme_color_override("font_outline_color", Color(0.1, 0.2, 0.3, 0.7))
	credit.add_theme_constant_override("outline_size", 3)
	credit.anchor_right = 1.0
	credit.anchor_top = 1.0
	credit.anchor_bottom = 1.0
	credit.offset_top = -36.0
	credit.offset_bottom = -8.0
	credit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(credit)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 18)
	center.add_child(root)
	var title := _label("JAPE", 110)
	root.add_child(title)

	_menu = _column(root)
	_button(_menu, "CPU と対戦", _on_cpu)
	_button(_menu, "オンライン対戦", _show.bind("online"))

	_online = _column(root)
	_button(_online, "部屋を作る", _on_host)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_online.add_child(row)
	_code = LineEdit.new()
	_code.placeholder_text = "6桁のコード"
	_code.max_length = 6
	_code.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	_code.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code.custom_minimum_size = Vector2(328, 90)
	_code.add_theme_font_size_override("font_size", 48)
	row.add_child(_code)
	_button(row, "入る", _on_join, 220)
	_note = _label("", 24)
	_online.add_child(_note)
	_button(_online, "同じWi-Fiで対戦(開発用)", _show.bind("lan"))
	_button(_online, "もどる", _show.bind("menu"))

	_lan = _column(root)
	_button(_lan, "部屋を作る(このIPで待つ)", _on_lan_host)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 12)
	_lan.add_child(row2)
	_ip = LineEdit.new()
	_ip.placeholder_text = "相手のIPアドレス"
	_ip.custom_minimum_size = Vector2(328, 90)
	_ip.add_theme_font_size_override("font_size", 40)
	_ip.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_URL
	row2.add_child(_ip)
	_button(row2, "入る", _on_lan_join, 220)
	_button(_lan, "もどる", _show.bind("online"))

	_wait = _column(root)
	_status = _label("", 44)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(800, 0)
	_wait.add_child(_status)
	_button(_wait, "やめる", _on_cancel)

	Online.changed.connect(_refresh)
	Online.leave()   # 試合から戻ってきたとき、前の接続を片付ける
	_show("menu")


func _process(_delta: float) -> void:
	if Online.has_match():
		set_process(false)
		get_tree().change_scene_to_file(GAME_SCENE)


func _show(page: String) -> void:
	_menu.visible = page == "menu"
	_online.visible = page == "online"
	_lan.visible = page == "lan"
	_wait.visible = page == "wait"
	if page == "online":
		_note.text = "" if Online.eos_available() else "※このビルドではオンライン対戦(EOS)の設定がありません"


func _refresh() -> void:
	_status.text = Online.status


func _on_cpu() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_host() -> void:
	_show("wait")
	Online.host_eos()


func _on_join() -> void:
	var code := _code.text.strip_edges()
	if code.length() != 6 or not code.is_valid_int():
		_note.text = "6桁の数字を入れてください"
		return
	_show("wait")
	Online.join_eos(code)


func _on_lan_host() -> void:
	_show("wait")
	Online.host_lan()


func _on_lan_join() -> void:
	var ip := _ip.text.strip_edges()
	if ip == "":
		return
	_show("wait")
	Online.join_lan(ip)


func _on_cancel() -> void:
	Online.leave()
	_show("online")


func _column(parent: Control) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(v)
	return v


func _button(parent: Control, text: String, action: Callable, width := 560) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(width, 90)
	b.add_theme_font_size_override("font_size", 40)
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("outline_size", 10)
	return l
