extends Node
## 操作の設定と、動きの数値の調整値を端末に保存する(自動読み込み: ControlSettings)。

signal changed

const PATH := "user://settings.cfg"
const VIBRATE_MS := 18

var size_scale := 1.0      ## ボタンの大きさ
var opacity := 0.55        ## ボタンの濃さ
var dpad_x := 0.14         ## 十字キーの横位置(画面幅に対する割合)。ボタンは左右対称
var pad_y := 0.8          ## 十字キー・ボタンの縦位置
var vibration := true
var view_tiles := 12.0     ## 画面に映す縦のマス数(原作と同じ12)
var show_fps := true        ## 画面にFPS(1秒間の描画回数)を出す。60未満なら処理落ち
var control_mode := "stick"  ## "stick"=左スティック+右タップ / "buttons"=DS配置のボタン

## 調整パネルの表示名(日本語)
const LABELS := {
	"CREEP_SPEED": "ゆっくり歩きの速さ (マス/秒)",
	"WALK_SPEED": "歩きの最高速 (マス/秒)",
	"MAX_RUN_SPEED": "ダッシュを続けたときの最高速",
	"RUN_SPEED": "ダッシュの速さ (マス/秒)",
	"RUN_JUMP_HEIGHT": "助走ジャンプの高さ (マス)",
	"STAND_JUMP_HEIGHT": "立ちジャンプの高さ (マス)",
	"GRAVITY_UP": "上昇中の重力",
	"GRAVITY_DOWN": "落下中の重力",
	"TRIPLE_WINDOW": "3段ジャンプの猶予 (秒)",
	"JUMP2_HEIGHT": "3段ジャンプ 2段目の高さ",
	"JUMP3_HEIGHT": "3段ジャンプ 3段目の高さ",
	"WALL_SLIDE_SPEED": "壁すべりの速さ",
	"WALL_KICK_SPEED_X": "壁キックの横の勢い",
	"WALL_KICK_HEIGHT": "壁キックの高さ",
	"SKID_DECEL": "切り返しの止まりやすさ",
	"GP_HOVER": "ヒップドロップの溜め (秒)",
}

## 調整パネルで変えられる動きの数値(Tuning の変数名)
const TUNABLE := {
	"RUN_SPEED": [8.0, 14.0],
	"RUN_JUMP_HEIGHT": [3.0, 6.5],
	"STAND_JUMP_HEIGHT": [2.5, 5.5],
	"TRIPLE_WINDOW": [0.05, 0.3],
	"JUMP2_HEIGHT": [3.5, 8.0],
	"JUMP3_HEIGHT": [4.0, 9.0],
	"WALL_SLIDE_SPEED": [1.0, 6.0],
	"WALL_KICK_SPEED_X": [4.0, 11.0],
	"WALL_KICK_HEIGHT": [2.5, 6.0],
	"SKID_DECEL": [15.0, 60.0],
	"GP_HOVER": [0.1, 0.5],
	"GRAVITY_UP": [20.0, 60.0],
	"GRAVITY_DOWN": [25.0, 80.0],
	"WALK_SPEED": [3.0, 9.0],
	"MAX_RUN_SPEED": [9.0, 18.0],
	"CREEP_SPEED": [0.3, 3.0],
}
var _defaults := {}


func _ready() -> void:
	_add_japanese_font()
	for key in TUNABLE:
		_defaults[key] = Tuning.get_value(key)
	load_settings()


## 標準フォントに日本語の予備フォントを足す(Godotの標準フォントには日本語が無いため)
func _add_japanese_font() -> void:
	var base := ThemeDB.fallback_font
	var list: Array[Font] = base.fallbacks.duplicate()
	var dir := DirAccess.open("res://assets/fonts")
	if dir == null:
		return
	for f in dir.get_files():
		var name := f.trim_suffix(".import").trim_suffix(".remap")
		if name.ends_with(".ttf"):
			var font: Font = load("res://assets/fonts/" + name)
			if font and not list.has(font):
				list.append(font)
	base.fallbacks = list


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	size_scale = cfg.get_value("controls", "size_scale", size_scale)
	opacity = cfg.get_value("controls", "opacity", opacity)
	dpad_x = cfg.get_value("controls", "dpad_x", dpad_x)
	pad_y = cfg.get_value("controls", "pad_y", pad_y)
	vibration = cfg.get_value("controls", "vibration", vibration)
	view_tiles = cfg.get_value("controls", "view_tiles", view_tiles)
	control_mode = cfg.get_value("controls", "control_mode", control_mode)
	show_fps = cfg.get_value("controls", "show_fps", show_fps)
	if cfg.get_value("meta", "version", 0) < 2:
		view_tiles = 12.0   # 前の版の標準(10)が保存されていても、新しい標準の12にそろえる
	for key in TUNABLE:
		if cfg.has_section_key("tuning", key):
			Tuning.set_value(key, float(cfg.get_value("tuning", key)))
	changed.emit()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("controls", "size_scale", size_scale)
	cfg.set_value("controls", "opacity", opacity)
	cfg.set_value("controls", "dpad_x", dpad_x)
	cfg.set_value("controls", "pad_y", pad_y)
	cfg.set_value("controls", "vibration", vibration)
	cfg.set_value("controls", "view_tiles", view_tiles)
	cfg.set_value("controls", "control_mode", control_mode)
	cfg.set_value("controls", "show_fps", show_fps)
	cfg.set_value("meta", "version", 2)
	for key in TUNABLE:
		cfg.set_value("tuning", key, Tuning.get_value(key))
	cfg.save(PATH)
	changed.emit()


func reset_tuning() -> void:
	for key in _defaults:
		Tuning.set_value(key, _defaults[key])
	save_settings()


## すべての設定を文字にする(「設定をコピー」用。チャットに貼ってもらえば開発側で読める)
func export_text() -> String:
	var d := {
		"controls": {"size_scale": size_scale, "opacity": opacity, "dpad_x": dpad_x, "pad_y": pad_y,
			"vibration": vibration, "view_tiles": view_tiles, "control_mode": control_mode},
		"tuning": {},
	}
	for key in TUNABLE:
		d.tuning[key] = snappedf(Tuning.get_value(key), 0.001)
	return "JAPE_SETTINGS " + JSON.stringify(d)


## 「設定をコピー」で作った文字を読み込む。読み込めたら true
func import_text(text: String) -> bool:
	var i := text.find("{")
	if i < 0:
		return false
	var d = JSON.parse_string(text.substr(i))
	if typeof(d) != TYPE_DICTIONARY:
		return false
	var c: Dictionary = d.get("controls", {})
	size_scale = float(c.get("size_scale", size_scale))
	opacity = float(c.get("opacity", opacity))
	dpad_x = float(c.get("dpad_x", dpad_x))
	pad_y = float(c.get("pad_y", pad_y))
	vibration = bool(c.get("vibration", vibration))
	view_tiles = float(c.get("view_tiles", view_tiles))
	control_mode = str(c.get("control_mode", control_mode))
	var t: Dictionary = d.get("tuning", {})
	for key in t:
		if TUNABLE.has(key):
			Tuning.set_value(key, float(t[key]))
	save_settings()
	return true
