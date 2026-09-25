class_name Player
extends CharacterBody3D
## 操作キャラ。判定は横(X)と縦(Y)の2次元だけで、奥行き(Z)は常に0。
## 動きの計算は PlayerMoves、対戦ルール(スター・残機)は MatchRules が持つ。
## ここは「動きを当たり判定に反映する」ことと「見た目の手応え」を担当する。

const BIG_HEIGHT := 1.8     ## docs/RULES.md §2
const SMALL_HEIGHT := 0.9
const WIDTH := 0.8
const SMALL_VISUAL := 1.0   ## 見た目の高さ(原作の構図: 小さいキャラはブロック1個と同じ高さ)
const BIG_VISUAL := 2.0     ## 見た目の高さ(原作の大きい状態は約2マス)
const RESPAWN_TIME := 1.5   ## ミスしてから土管から出てくるまで【決定・調整】

signal bumped_block(x: int, y: int)
signal fell
signal respawned
signal move_event(name: String)   ## 効果音・演出用("jump1" "land" "skid" "wall_kick" など)

var index := 0
var stage: Grassland
var input_source: Callable = PlayerInput.from_actions
var moves := PlayerMoves.new()
var big := false
var dead := false
var invuln := 0.0           ## 表示用(点滅)。値は MatchRules から毎フレーム受け取る
var last_input := PlayerInput.new()
var ground_pounding: bool:
	get:
		return moves.is_ground_pounding()

var _model: Node3D          ## 向き・傾き・回転をかける入れ物
var _body: Node3D           ## 素材のモデル本体
var _shape: CollisionShape3D
var _ap: AnimationPlayer
var _anims := {}
var _respawn_timer := 0.0
var _knock := 0.0
var _squash := 0.0
var _spin := 0.0
var _dust: CPUParticles3D


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.1
	_shape = CollisionShape3D.new()
	_shape.shape = BoxShape3D.new()
	add_child(_shape)
	_model = Node3D.new()
	add_child(_model)
	_body = Assets.spawn(Assets.CHARACTER, BIG_HEIGHT)
	_model.add_child(_body)
	Assets.paint_player(_body, index)
	_ap = Assets.find_anim_player(_body)
	if _ap:
		for key in ["Idle", "Walk", "Run", "Jump", "RecieveHit", "Roll"]:
			var n := Assets.anim_name(_ap, key)
			if n != &"":
				_anims[key] = n
				if key in ["Idle", "Walk", "Run"]:
					_ap.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	_dust = _make_dust()
	add_child(_dust)
	set_big(false)


func height() -> float:
	var h := BIG_HEIGHT if big else SMALL_HEIGHT
	if big and moves.state == PlayerMoves.State.CROUCH:
		h = Tuning.CROUCH_HEIGHT
	return h


func set_big(value: bool) -> void:
	big = value
	moves.big = value
	_update_shape()


func _update_shape() -> void:
	(_shape.shape as BoxShape3D).size = Vector3(WIDTH, height(), 1.0)
	_shape.position.y = height() * 0.5


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

	var wall := 0
	if is_on_wall() and not is_on_floor():
		var n := get_wall_normal()
		if absf(n.x) > 0.5:
			wall = -int(signf(n.x))
	var was_crouching := moves.state == PlayerMoves.State.CROUCH
	moves.vel = Vector2(velocity.x, velocity.y)
	var v := moves.step(is_on_floor(), wall, input, delta)
	if _knock != 0.0:
		v.x = _knock
		moves.vel.x = _knock
		_knock = move_toward(_knock, 0.0, 30.0 * delta)
	if was_crouching != (moves.state == PlayerMoves.State.CROUCH):
		_update_shape()

	velocity = Vector3(v.x, v.y, 0.0)
	var was_rising := velocity.y > 0.0
	move_and_slide()
	position.z = 0.0
	position.x = stage.wrap_x(position.x)
	if was_rising and is_on_ceiling():
		bumped_block.emit(int(floor(position.x)), int(floor(top() + 0.1)))
	if position.y < -3.0:
		fell.emit()
	for e in moves.events:
		_on_move_event(e)
		move_event.emit(e)
	_update_visual(delta)


## 左右ループの見た目用: 本体(当たり判定)は動かさず、見た目と砂ぼこりだけ横にずらす
func set_view_shift(dx: float) -> void:
	_model.position.x = dx
	_dust.position.x = dx


## 相手や敵を踏んだとき跳ね返る。ジャンプを押していれば高く
func bounce() -> void:
	moves.vel = Vector2(velocity.x, velocity.y)
	moves.stomp_bounce(last_input.jump_held)
	velocity.y = moves.vel.y
	move_event.emit("stomp")


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
	moves.reset()
	_respawn_timer = RESPAWN_TIME
	collision_layer = 0


func _respawn() -> void:
	dead = false
	visible = true
	collision_layer = 2
	moves.reset()
	set_big(false)
	position = stage.pipe_tops[index]
	velocity = Vector3(0, 6, 0)
	_knock = 0.0
	respawned.emit()


# ---- 見た目の手応え -----------------------------------------------------

func _on_move_event(e: String) -> void:
	match e:
		"land":
			_squash = 0.12
			_dust.restart()
		"gp_land":
			_squash = 0.2
			_dust.restart()
		"jump3", "gp_start":
			_spin = 0.0


func _update_visual(delta: float) -> void:
	var st := moves.state
	var facing := moves.facing
	_model.rotation = Vector3.ZERO
	_body.rotation_degrees.y = 90.0 * facing

	# 前傾(走るほど前に倒れる)・切り返しは後ろへ反る
	var lean := 0.0
	if is_on_floor():
		if st == PlayerMoves.State.SKID:
			lean = 18.0
		else:
			lean = -clampf(absf(velocity.x) / Tuning.RUN_SPEED, 0.0, 1.0) * 10.0
	_model.rotation_degrees.z = lean * facing

	# 3段目の宙返り・ヒップドロップの回転(画面の面内で1回転)
	if moves.flipping or (st == PlayerMoves.State.GROUND_POUND and velocity.y == 0.0):
		var dur := 0.55 if moves.flipping else Tuning.GP_HOVER
		_spin = minf(_spin + delta / dur, 1.0)
		_model.rotation_degrees.z = -360.0 * _spin * facing
		_model.position.y = height() * 0.5 * (1.0 if _spin < 1.0 else 0.0)
		_body.position.y = -height() * 0.5 if _spin < 1.0 else 0.0
	else:
		_model.position.y = 0.0
		_body.position.y = 0.0

	# 大きさ: 原作の比率に合わせた見た目の高さ(当たり判定とは別)。
	# 骨で動くモデルは縦横で違う拡大縮小をすると一部のスマホGPUで壊れるため、必ず縦横同じ倍率にする。
	# 着地・しゃがみの「潰れ」は、倍率ではなく少し沈める・小さくすることで表す。
	var visual := BIG_VISUAL if big else SMALL_VISUAL
	var k := visual / BIG_HEIGHT
	var dip := 0.0
	if _squash > 0.0:
		_squash -= delta
		dip = -0.08 * visual
	if st == PlayerMoves.State.CROUCH:
		k *= 0.7
	_model.scale = Vector3.ONE * k
	if not moves.flipping and st != PlayerMoves.State.GROUND_POUND:
		_model.position.y = dip

	# 砂ぼこり: ダッシュ・切り返し・壁すべり
	var fast := is_on_floor() and absf(velocity.x) > Tuning.WALK_SPEED + 1.0
	_dust.emitting = fast or st == PlayerMoves.State.SKID or st == PlayerMoves.State.WALL_SLIDE
	_dust.position.y = 0.05 if st != PlayerMoves.State.WALL_SLIDE else height() * 0.6

	_model.visible = invuln <= 0.0 or int(invuln * 15.0) % 2 == 0
	_play_anim(st)


func _play_anim(st: int) -> void:
	if _ap == null:
		return
	var key := "Idle"
	var speed := 1.0
	match st:
		PlayerMoves.State.GROUND_POUND, PlayerMoves.State.CROUCH, PlayerMoves.State.WALL_SLIDE:
			key = "Jump"
		PlayerMoves.State.GP_LAND:
			key = "Idle"
		PlayerMoves.State.SKID:
			key = "Idle"
		_:
			var vx := absf(velocity.x)
			if not is_on_floor():
				key = "Jump"
			elif vx > Tuning.WALK_SPEED + 0.5:
				key = "Run"
				speed = clampf(vx / Tuning.RUN_SPEED * 1.25, 0.9, 1.5)
			elif vx > 0.2:
				key = "Walk"
				speed = clampf(vx / Tuning.WALK_SPEED * 1.2, 0.6, 1.5)
	var n: StringName = _anims.get(key, &"")
	if n != &"" and _ap.current_animation != n:
		_ap.play(n, 0.08)
	_ap.speed_scale = speed


func _make_dust() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 12
	p.lifetime = 0.35
	p.one_shot = false
	p.emitting = false
	p.explosiveness = 0.0
	p.local_coords = false
	p.direction = Vector3(0, 1, 0)
	p.spread = 60.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 1.8
	p.gravity = Vector3(0, -2, 0)
	p.scale_amount_min = 0.12
	p.scale_amount_max = 0.22
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 8
	mesh.rings = 4
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 1, 0.8)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mat
	p.mesh = mesh
	return p
