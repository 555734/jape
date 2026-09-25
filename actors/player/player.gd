class_name Player
extends Node3D
## 操作キャラの見た目。動き・当たり判定・ルールは Simulation(SimPlayer)が持ち、
## ここは毎フレームその状態を映して「見た目の手応え」(傾き・宙返り・潰れ・砂ぼこり・アニメ)を付けるだけ。

const BIG_HEIGHT := Simulation.SimPlayer.BIG_HEIGHT
const SMALL_VISUAL := 1.0   ## 見た目の高さ(原作の構図: 小さいキャラはブロック1個と同じ高さ)
const BIG_VISUAL := 2.0     ## 見た目の高さ(原作の大きい状態は約2マス)

var index := 0
var sim: Simulation.SimPlayer
var invuln := 0.0           ## 表示用(点滅)。値は MatchRules から毎フレーム受け取る
var moves: PlayerMoves:
	get:
		return sim.moves
var big: bool:
	get:
		return sim.big
var velocity: Vector3:
	get:
		return sim.velocity

var _model: Node3D          ## 向き・傾き・回転をかける入れ物
var _body: Node3D           ## 素材のモデル本体
var _ap: AnimationPlayer
var _anims := {}
var _squash := 0.0
var _spin := 0.0
var _dust: CPUParticles3D


func _ready() -> void:
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


func height() -> float:
	return sim.height()


func is_on_floor() -> bool:
	return sim.on_floor


## Simulation の状態を映す(毎フレーム)
func sync(delta: float) -> void:
	visible = not sim.dead
	position = Vector3(sim.x, sim.y, 0.0)
	if not sim.dead:
		_update_visual(delta)


## 左右ループの見た目用: 本体の位置は動かさず、見た目と砂ぼこりだけ横にずらす
func set_view_shift(dx: float) -> void:
	_model.position.x = dx
	_dust.position.x = dx


func model_visible() -> bool:
	return _model.visible


# ---- 見た目の手応え -----------------------------------------------------

## 動きの出来事(Simulation の events から)に合わせた演出
func on_move_event(e: String) -> void:
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
