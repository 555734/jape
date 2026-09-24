class_name PlayerInput
extends RefCounted
## 1フレーム分の入力。タッチ・キーボード・CPU・テスト・(将来の)通信で共通に使う。

var move_x := 0.0          ## -1(左)〜1(右)
var down := false          ## 下(空中ならヒップドロップ)
var run := false           ## Bボタン
var jump_pressed := false  ## Aボタンを押した瞬間
var jump_held := false     ## Aボタンを押している間


## タッチボタン・キーボードの状態から作る
static func from_actions() -> PlayerInput:
	var i := PlayerInput.new()
	i.move_x = Input.get_axis("move_left", "move_right")
	i.down = Input.is_action_pressed("move_down")
	i.run = Input.is_action_pressed("run")
	i.jump_pressed = Input.is_action_just_pressed("jump")
	i.jump_held = Input.is_action_pressed("jump")
	return i


static func make(move_x: float, run: bool, jump_pressed: bool, jump_held: bool, down := false) -> PlayerInput:
	var i := PlayerInput.new()
	i.move_x = move_x
	i.run = run
	i.jump_pressed = jump_pressed
	i.jump_held = jump_held
	i.down = down
	return i
