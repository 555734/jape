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
var view_tiles := 10.0     ## 画面に映す縦のマス数(原作は12。スマホで見やすいよう標準は10)

## 調整パネルで変えられる動きの数値(Tuning の変数名)
const TUNABLE := {
	"RUN_SPEED": [8.0, 14.0],
	"RUN_JUMP_HEIGHT": [3.5, 6.5],
	"STAND_JUMP_HEIGHT": [3.0, 5.5],
	"TRIPLE_WINDOW": [0.05, 0.3],
	"JUMP2_HEIGHT": [4.5, 8.0],
	"JUMP3_HEIGHT": [5.5, 9.0],
	"WALL_SLIDE_SPEED": [1.0, 6.0],
	"WALL_KICK_SPEED_X": [4.0, 11.0],
	"WALL_KICK_HEIGHT": [2.5, 6.0],
	"SKID_DECEL": [15.0, 60.0],
	"GP_HOVER": [0.1, 0.5],
}
var _defaults := {}


func _ready() -> void:
	for key in TUNABLE:
		_defaults[key] = Tuning.get_value(key)
	load_settings()


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
	for key in TUNABLE:
		cfg.set_value("tuning", key, Tuning.get_value(key))
	cfg.save(PATH)
	changed.emit()


func reset_tuning() -> void:
	for key in _defaults:
		Tuning.set_value(key, _defaults[key])
	save_settings()
