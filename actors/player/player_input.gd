class_name PlayerInput
extends RefCounted
## 1フレーム分の入力。タッチ・キーボード・CPU・テスト・(将来の)通信で共通に使う。

var move_x := 0.0          ## -1(左)〜1(右)
var down := false          ## 下を押している(大きい状態ならしゃがみ)
var down_pressed := false  ## 下を押した瞬間(空中ならヒップドロップ)
var run := false           ## Bボタン
var jump_pressed := false  ## Aボタンを押した瞬間
var jump_held := false     ## Aボタンを押している間


## タッチボタン・キーボードの状態から作る
static func from_actions() -> PlayerInput:
	var i := PlayerInput.new()
	i.move_x = Input.get_axis("move_left", "move_right")
	i.down = Input.is_action_pressed("move_down")
	i.down_pressed = Input.is_action_just_pressed("move_down")
	i.run = Input.is_action_pressed("run")
	i.jump_pressed = Input.is_action_just_pressed("jump")
	i.jump_held = Input.is_action_pressed("jump")
	return i


static func make(move_x: float, run: bool, jump_pressed: bool, jump_held: bool, down := false, down_pressed := false) -> PlayerInput:
	var i := PlayerInput.new()
	i.move_x = move_x
	i.run = run
	i.jump_pressed = jump_pressed
	i.jump_held = jump_held
	i.down = down
	i.down_pressed = down_pressed
	return i


## 通信と巻き戻しのため、横の入力を -127〜127 の整数に丸めた入力にする(ローカル対戦でも同じ経路を通す)
func quantized() -> PlayerInput:
	return PlayerInput.from_bits(to_bits())


## 2バイトにまとめる: 下位8ビット=横の入力(符号付き)、上位=ボタン
func to_bits() -> int:
	var mx := clampi(roundi(move_x * 127.0), -127, 127) & 0xFF
	var b := int(down) | int(down_pressed) << 1 | int(run) << 2 | int(jump_pressed) << 3 | int(jump_held) << 4
	return mx | b << 8


static func from_bits(bits: int) -> PlayerInput:
	var i := PlayerInput.new()
	var mx := bits & 0xFF
	if mx >= 128:
		mx -= 256
	i.move_x = mx / 127.0
	var b := bits >> 8
	i.down = (b & 1) != 0
	i.down_pressed = (b & 2) != 0
	i.run = (b & 4) != 0
	i.jump_pressed = (b & 8) != 0
	i.jump_held = (b & 16) != 0
	return i
