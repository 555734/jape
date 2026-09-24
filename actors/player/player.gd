class_name Player
extends CharacterBody3D
## 操作キャラ。判定は横(X)と縦(Y)の2次元だけで、奥行き(Z)は常に0。
## 対戦ルール(スター・残機)は MatchRules が持ち、ここは動きと見た目だけを扱う。

const BIG_HEIGHT := 1.8     ## docs/RULES.md §2
const SMALL_HEIGHT := 0.9
const WIDTH := 0.8
const GP_HOVER := 0.15      ## ヒップドロップ前の空中停止【決定・調整】
const GP_SPEED := 24.0      ## ヒップドロップの落下速度【決定・調整】
const RESPAWN_TIME := 1.5   ## ミスしてから土管から出てくるまで【決定・調整】
const STOMP_BOUNCE := 11.0  ## 踏んだときの跳ね返り【決定・調整】

signal bumped_block(x: int, y: int)
signal fell
signal respawned

var index := 0
var stage: Grassland
var input_source: Callable = PlayerInput.from_actions
var big := false
var ground_pounding := false
var dead := false
var invuln := 0.0           ## 表示用(点滅)。値は MatchRules から毎フレーム受け取る
var last_input := PlayerInput.new()

var _model: Node3D
var _shape: CollisionShape3D
var _ap: AnimationPlayer
var _anims := {}
var _facing := 1.0
var _gp_timer := 0.0
var _respawn_timer := 0.0
var _knock := 0.0


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.1
	_shape = CollisionShape3D.new()
	_shape.shape = BoxShape3D.new()
	add_child(_shape)
	_model = Assets.spawn(Assets.CHARACTER, BIG_HEIGHT)
	add_child(_model)
	if index == 1:
		_recolor(_model)
	_ap = Assets.find_anim_player(_model)
	if _ap:
		for key in ["Idle", "Walk", "Run", "Jump_Idle", "HitReact", "Duck"]:
			var n := Assets.anim_name(_ap, key)
			if n != &"":
				_anims[key] = n
				if key in ["Idle", "Walk", "Run", "Jump_Idle"]:
					_ap.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	set_big(false)


func height() -> float:
	return BIG_HEIGHT if big else SMALL_HEIGHT


func set_big(value: bool) -> void:
	big = value
	(_shape.shape as BoxShape3D).size = Vector3(WIDTH, height(), 1.0)
	_shape.position.y = height() * 0.5
	_model.scale = Vector3.ONE * (1.0 if big else 0.5)


## 足元の高さと頭の高さ
func bottom() -> float:
	return position.y


func top() -> float:
	return position.y + height()


func _physics_process(delta: float) -> void:
	if dead:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			_respawn()
		return
	var input: PlayerInput = input_source.call()
	last_input = input
	var v := Vector2(velocity.x, velocity.y)

	if ground_pounding:
		_gp_timer -= delta
		v = Vector2(0.0, 0.0 if _gp_timer > 0.0 else -GP_SPEED)
		if is_on_floor() and _gp_timer <= 0.0:
			ground_pounding = false
	else:
		if input.down and not is_on_floor():
			ground_pounding = true
			_gp_timer = GP_HOVER
			v = Vector2.ZERO
		else:
			v = PlayerMotor.step(v, is_on_floor(), input, delta)
	if _knock != 0.0:
		v.x = _knock
		_knock = move_toward(_knock, 0.0, 30.0 * delta)
	velocity = Vector3(v.x, v.y, 0.0)
	var was_rising := velocity.y > 0.0
	move_and_slide()
	position.z = 0.0
	position.x = stage.wrap_x(position.x)
	if was_rising and is_on_ceiling():
		bumped_block.emit(int(floor(position.x)), int(floor(top() + 0.1)))
	if position.y < -3.0:
		fell.emit()
	_update_visual()


## 相手や敵を踏んだとき跳ね返る
func bounce() -> void:
	velocity.y = STOMP_BOUNCE
	ground_pounding = false


## 横から弾かれる
func knockback(dir: float) -> void:
	_knock = dir * 7.0


## 大きい状態でダメージ → 小さくなる
func shrink() -> void:
	set_big(false)


## ミス: 消えて、少し後に自分の土管から小さい状態で出てくる
func die() -> void:
	dead = true
	visible = false
	velocity = Vector3.ZERO
	ground_pounding = false
	_respawn_timer = RESPAWN_TIME
	collision_layer = 0


func _respawn() -> void:
	dead = false
	visible = true
	collision_layer = 2
	set_big(false)
	position = stage.pipe_tops[index]
	velocity = Vector3(0, 6, 0)
	_knock = 0.0
	respawned.emit()


func _update_visual() -> void:
	if absf(velocity.x) > 0.1:
		_facing = signf(velocity.x)
	_model.rotation_degrees.y = 90.0 * _facing
	_model.visible = invuln <= 0.0 or int(invuln * 15.0) % 2 == 0
	if _ap == null:
		return
	var key := "Idle"
	if ground_pounding:
		key = "Duck"
	elif not is_on_floor():
		key = "Jump_Idle"
	elif absf(velocity.x) > Tuning.WALK_SPEED + 0.5:
		key = "Run"
	elif absf(velocity.x) > 0.2:
		key = "Walk"
	var n: StringName = _anims.get(key, &"")
	if n != &"" and _ap.current_animation != n:
		_ap.play(n, 0.1)


## 2P用: 色相をずらして赤系にする
func _recolor(n: Node3D) -> void:
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (m as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var mat := mesh.surface_get_material(s)
			if mat is BaseMaterial3D:
				var c: Color = mat.albedo_color
				if c.s < 0.3:
					continue
				var dup: BaseMaterial3D = mat.duplicate()
				dup.albedo_color = Color.from_hsv(fposmod(c.h + 0.45, 1.0), c.s, c.v, c.a)
				(m as MeshInstance3D).set_surface_override_material(s, dup)
