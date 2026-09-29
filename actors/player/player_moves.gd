class_name PlayerMoves
extends RefCounted
## プレイヤーの動き(速度と状態)の計算。シーンに依存しないので、テストで直接動かせる。
## 基準は New Super Mario Bros.(DS)。速度段・重力帯・先行入力・コヨーテタイムは原作の仕組み。
## 数値と出典・確度は docs/nsmb_ds_physics.md、受け入れ条件は tests/test_nsmb_feel.gd。

enum State { NORMAL, SKID, CROUCH, WALL_SLIDE, GROUND_POUND, GP_LAND }

var vel := Vector2.ZERO
var state := State.NORMAL
var facing := 1.0
var big := false

## 3段ジャンプ: 今のジャンプが何段目か(0,1,2)。着地後の猶予タイマー
var jump_stage := 0
var land_timer := 0.0
var flipping := false        ## 3段目の宙返り中

var wall_lock := 0          ## 壁キック後の入力制限(残りフレーム数)
var jump_buffer := 0        ## 押しておいたジャンプが残っているフレーム数【NSMB DS】
var coyote := 0             ## 足場を離れてからジャンプできる残りフレーム数【NSMB DS】
var _gp_timer := 0.0
var _was_on_floor := true
var _last_jump_stage := -1   ## 直前のジャンプの段(着地まで保持)

## 1フレームの出来事(見た目・音用)。step() のたびに作り直す
var events: Array[String] = []


## 通信対戦の巻き戻し用: 状態をまるごと配列にする / 配列から戻す
func snapshot() -> Array:
	return [vel.x, vel.y, state, facing, big, jump_stage, land_timer, flipping, wall_lock, _gp_timer,
		_was_on_floor, _last_jump_stage, jump_buffer, coyote]


func restore(a: Array) -> void:
	vel = Vector2(a[0], a[1])
	state = a[2]
	facing = a[3]
	big = a[4]
	jump_stage = a[5]
	land_timer = a[6]
	flipping = a[7]
	wall_lock = a[8]
	_gp_timer = a[9]
	_was_on_floor = a[10]
	_last_jump_stage = a[11]
	jump_buffer = a[12]
	coyote = a[13]
	events.clear()


## on_floor: 接地しているか / wall: 押し付けている壁の向き(-1=左, 1=右, 0=なし)
func step(on_floor: bool, wall: int, input: PlayerInput, dt: float) -> Vector2:
	events.clear()
	wall_lock = maxi(0, wall_lock - 1)
	var dir := signf(input.move_x) if absf(input.move_x) > 0.1 else 0.0

	# ジャンプの先行入力: 押した瞬間を覚えておき、着地したフレームで使う【NSMB DS】
	jump_buffer = maxi(0, jump_buffer - 1)
	if input.jump_pressed:
		jump_buffer = Tuning.JUMP_BUFFER_FRAMES

	# コヨーテタイム: 足場を離れた直後の数フレームはまだ跳べる【NSMB DS】
	if on_floor:
		coyote = Tuning.COYOTE_FRAMES
	else:
		coyote = maxi(0, coyote - 1)

	if on_floor and not _was_on_floor:
		_on_land()
	_was_on_floor = on_floor

	match state:
		State.GROUND_POUND:
			_ground_pound(on_floor, dt)
		State.GP_LAND:
			_gp_timer -= dt
			vel.x = 0.0
			if _gp_timer <= 0.0:
				state = State.NORMAL
		_:
			if on_floor:
				_ground(dir, input, dt)
			else:
				_air(dir, wall, input, dt)
	return vel


func _on_land() -> void:
	events.append("land")
	flipping = false
	if state == State.GROUND_POUND:
		state = State.GP_LAND
		_gp_timer = Tuning.GP_LAND_STUN
		events.append("gp_land")
		return
	if state == State.WALL_SLIDE:
		state = State.NORMAL
	land_timer = Tuning.TRIPLE_WINDOW


func _ground(dir: float, input: PlayerInput, dt: float) -> void:
	land_timer = maxf(0.0, land_timer - dt)
	if land_timer <= 0.0:
		_last_jump_stage = -1   # 猶予切れ: 次のジャンプは1段目から
	vel.y = 0.0

	# しゃがみ(大きい状態のみ)
	if big and input.down:
		state = State.CROUCH
		vel.x = move_toward(vel.x, 0.0, Tuning.RELEASE_DECEL * dt)
	else:
		if state == State.CROUCH:
			state = State.NORMAL
		_horizontal(dir, input, dt, true)

	if jump_buffer > 0:
		_jump()


## 横移動【NSMB DS】。段は今の速度で決まり、上限段はダッシュ入力で決まる。
## 加速表は地上・空中で同じ。スキッドと摩擦は地上のみ。
func _horizontal(dir: float, input: PlayerInput, dt: float, on_ground: bool) -> void:
	var speed := absf(vel.x)
	var stage := Tuning.speed_stage(speed)
	var max_stage: int = Tuning.RUN_STAGE if input.run else Tuning.WALK_STAGE
	var top := Tuning.WALK_MAX_VELOCITY[max_stage]
	var accel := Tuning.WALK_ACCEL[stage]

	if dir == 0.0:
		# 入力なし。地上では摩擦で減速する(空中では速度を保つ)
		if on_ground:
			vel.x = move_toward(vel.x, 0.0, Tuning.RELEASE_DECEL * dt)
		if state == State.SKID:
			state = State.NORMAL
		return

	facing = dir
	if vel.x != 0.0 and signf(vel.x) != dir:
		# 逆方向に入れた。速ければ切り返し(スキッド)、そうでなければ段ごとの減速。
		# 一度スキッドに入ったら、速度が落ちても止まるまでスキッドのまま【NSMB DS】
		if on_ground and (state == State.SKID or speed >= Tuning.SKID_MIN_SPEED):
			if state != State.SKID:
				events.append("skid")
			state = State.SKID
			vel.x = move_toward(vel.x, 0.0, Tuning.SKID_DECEL * dt)
			return
		var turn := Tuning.FAST_TURNAROUND_ACCEL if stage >= Tuning.RUN_STAGE \
			else Tuning.TURNAROUND_ACCEL[mini(stage, Tuning.TURNAROUND_ACCEL.size() - 1)]
		vel.x = move_toward(vel.x, 0.0, turn * dt)
		return

	if state == State.SKID:
		state = State.NORMAL
	if speed > top:
		# 上限段を超えている(ダッシュを離した直後など)。摩擦で上限まで落とす
		vel.x = move_toward(vel.x, dir * top, Tuning.RELEASE_DECEL * dt)
	else:
		vel.x = move_toward(vel.x, dir * top, accel * dt)


## ジャンプ【NSMB DS】。初速は横の速さで上乗せが決まる。高さは結果として出る
func _jump() -> void:
	var speed := absf(vel.x)
	var next := 0
	if _last_jump_stage >= 0 and land_timer > 0.0 and speed >= Tuning.TRIPLE_MIN_SPEED:
		next = mini(_last_jump_stage + 1, 2)
		if _last_jump_stage == 2:
			next = 0   # 3段目の後は1段目に戻る
	vel.y = Tuning.jump_velocity(vel.x)
	if next == 2:
		vel.y += Tuning.JUMP_TRIPLE_BONUS
	# 2段目・3段目は横の勢いも上乗せする(猶予と倍率は Jape 独自)
	var cap := Tuning.WALK_MAX_VELOCITY[Tuning.RUN_STAGE] * 1.2
	if next == 1:
		vel.x = clampf(vel.x * Tuning.JUMP2_SPEED_BOOST, -cap, cap)
	elif next == 2:
		vel.x = clampf(vel.x * Tuning.JUMP3_SPEED_BOOST, -cap, cap)
	jump_stage = next
	_last_jump_stage = next
	jump_buffer = 0
	coyote = 0
	land_timer = 0.0
	flipping = next == 2
	state = State.NORMAL
	events.append("jump%d" % (next + 1))


func _air(dir: float, wall: int, input: PlayerInput, dt: float) -> void:
	if state == State.CROUCH or state == State.SKID:
		state = State.NORMAL

	# ヒップドロップ開始(空中で下を押した瞬間)
	if input.down_pressed and state != State.WALL_SLIDE:
		state = State.GROUND_POUND
		_gp_timer = Tuning.GP_HOVER
		vel = Vector2.ZERO
		flipping = false
		events.append("gp_start")
		return

	# 壁すべり: 落下中に壁へ向かって押している
	var pushing_wall := wall != 0 and dir == float(wall) and wall_lock <= 0
	if state == State.WALL_SLIDE and (not pushing_wall and wall == 0):
		state = State.NORMAL
	if pushing_wall and vel.y <= 0.0:
		if state != State.WALL_SLIDE:
			events.append("wall_slide")
		state = State.WALL_SLIDE
		facing = -float(wall)
		flipping = false
	elif state == State.WALL_SLIDE and dir != float(wall):
		state = State.NORMAL

	if state == State.WALL_SLIDE:
		if jump_buffer > 0:
			_wall_kick(wall)
			return
		vel.x = float(wall) * 0.5   # 壁に接したままにする
		vel.y = maxf(vel.y - _gravity(input) * dt, -Tuning.MAX_FALL_WALL_SLIDE)
		return

	# 足場を離れた直後ならまだ跳べる【NSMB DS】
	if coyote > 0 and jump_buffer > 0:
		_jump()
		return

	# 空中の横移動。壁キック直後は壁方向の入力を無視
	var d := dir
	if wall_lock > 0 and d != 0.0 and d != signf(vel.x):
		d = 0.0
	_horizontal(d, input, dt, false)

	var limit: float = Tuning.MAX_FALL_GROUND_POUND if state == State.GROUND_POUND else Tuning.MAX_FALL
	vel.y = maxf(vel.y - _gravity(input) * dt, -limit)


## 重力【NSMB DS】。速度帯で5段に切り替わる。
## 段0(勢いよく上昇中)はジャンプを押している間だけ軽く、離していれば最終段の重い値になる。
## 頂点の直前が最も重い。
func _gravity(input: PlayerInput) -> float:
	var stage := Tuning.gravity_stage(vel.y)
	if stage == 0 and not input.jump_held:
		return Tuning.GRAVITY_ACCEL[Tuning.GRAVITY_ACCEL.size() - 1]
	return Tuning.GRAVITY_ACCEL[stage]


func _wall_kick(wall: int) -> void:
	vel.x = -float(wall) * Tuning.WALL_KICK_SPEED_X
	vel.y = Tuning.WALL_KICK_SPEED_Y
	facing = -float(wall)
	wall_lock = Tuning.WALL_KICK_LOCK_FRAMES
	state = State.NORMAL
	_last_jump_stage = -1
	jump_buffer = 0
	events.append("wall_kick")


func _ground_pound(on_floor: bool, dt: float) -> void:
	if _gp_timer > 0.0:
		_gp_timer -= dt
		vel = Vector2.ZERO
	else:
		vel = Vector2(0.0, -Tuning.GP_SPEED)


## 踏みつけたとき。ジャンプを押していれば高く跳ねる
func stomp_bounce(jump_held: bool) -> void:
	vel.y = Tuning.STOMP_BOUNCE_HIGH if jump_held else Tuning.STOMP_BOUNCE_LOW
	state = State.NORMAL
	flipping = false
	_was_on_floor = false


func is_ground_pounding() -> bool:
	return state == State.GROUND_POUND


func reset() -> void:
	vel = Vector2.ZERO
	state = State.NORMAL
	jump_stage = 0
	_last_jump_stage = -1
	land_timer = 0.0
	flipping = false
	wall_lock = 0
	jump_buffer = 0
	coyote = 0
	_was_on_floor = false
