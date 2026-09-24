extends Node3D
## 起動シーン。ステージ・プレイヤー・カメラ・画面表示を組み立てる。
##
## 開発用の起動オプション(godot ... -- の後に付ける):
##   --demo          自動入力で右へ走ってジャンプする
##   --capture=DIR   毎フレームの画面をDIRにPNG保存(--frames=N 枚で終了)

const VIEW_TILES_Y := 12.0
const FOV := 30.0

var stage: DemoStage
var player: Player
var camera: Camera3D
var hud: Label

var _args := {}
var _frame := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else ""
	_setup_input()
	_setup_environment()

	stage = DemoStage.new()
	add_child(stage)
	player = Player.new()
	player.position = stage.spawn
	add_child(player)
	if _args.has("demo"):
		player.input_source = _demo_input

	camera = Camera3D.new()
	camera.fov = FOV
	add_child(camera)
	camera.current = true

	var ui := CanvasLayer.new()
	add_child(ui)
	hud = Label.new()
	hud.position = Vector2(24, 16)
	hud.add_theme_font_size_override("font_size", 40)
	hud.add_theme_color_override("font_outline_color", Color.BLACK)
	hud.add_theme_constant_override("outline_size", 8)
	ui.add_child(hud)
	add_child(TouchControls.new())
	stage.coin_collected.connect(func() -> void: player.coins += 1)
	stage.star_collected.connect(func() -> void: player.stars += 1)


func _process(_delta: float) -> void:
	var dist := (VIEW_TILES_Y * 0.5) / tan(deg_to_rad(FOV * 0.5))
	var cy := maxf(5.5, player.position.y + 2.0)
	camera.position = Vector3(player.position.x, cy, dist)
	hud.text = "COIN %d/8    STAR %d" % [player.coins % 8, player.stars]

	if _args.has("capture"):
		_frame += 1
		if _frame > 5:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/game_%03d.png" % [_args["capture"], _frame - 6])
		if _frame >= int(_args.get("frames", "90")) + 5:
			get_tree().quit()


## --demo 用の自動入力: 右へダッシュし、一定間隔でジャンプ
func _demo_input() -> PlayerInput:
	var t := Engine.get_physics_frames()
	var phase := t % 90
	return PlayerInput.make(1.0, true, phase == 40, phase >= 40 and phase < 75)


func _setup_input() -> void:
	var keys := {
		"move_left": [KEY_LEFT, KEY_A],
		"move_right": [KEY_RIGHT, KEY_D],
		"jump": [KEY_SPACE, KEY_Z, KEY_UP],
		"run": [KEY_SHIFT, KEY_X],
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)


func _setup_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -25, 0)
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.78, 0.98)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.75, 0.8)
	add_child(env)
