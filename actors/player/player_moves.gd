class_name PlayerMoves
extends RefCounted
## プレイヤーの動き(速度と状態)の計算。シーンに依存しないので、テストで直接動かせる。
## 原作の動き: 歩き・ダッシュ・切り返し・ジャンプ(長押しで高く)・3段ジャンプ・
## 壁すべり・壁キック・ヒップドロップ・しゃがみ。数値は Tuning。

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
var _gp_timer := 0.0
var _was_on_floor := true
var _last_jump_stage := -1   ## 直前のジャンプの段(着地まで保持)

## 1フレームの出来事(見た目・音用)。step() のたびに作り直す
var events: Array[String] = []


## 通信対戦の巻き戻し用: 状態をまるごと配列にする / 配列から戻す
func snapshot() -> Array:
	return [vel.x, vel.y, state, facing, big, jump_stage, land_timer, flipping, wall_lock, _gp_timer,
		_was_on_floor, _last_jump_stage]


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
	events.clear()


## on_floor: 接地しているか / wall: 押し付けている壁の向き(-1=左, 1=右, 0=なし)
func step(on_floor: bool, wall: int, input: PlayerInput, dt: float) -> Vector2:
	events.clear()
	wall_lock = maxi(0, wall_lock - 1)
	var dir := signf(input.move_x) if absf(input.move_x) > 0.1 else 0.0

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
		vel.x = move_toward(vel.x, 0.0, Tuning.STOP_DECEL * dt)
	else:
		if state == State.CROUCH:
			state = State.NORMAL
		_horizontal(dir, input, dt, 1.0)

	if input.jump_pressed:
		_jump()


func _horizontal(dir: float, input: PlayerInput, dt: float, rate_scale: float) -> void:
	var top := target_speed(absf(input.move_x), input.run)
	var accel := (Tuning.RUN_ACCEL if input.run else Tuning.WALK_ACCEL) * rate_scale
	var on_ground := rate_scale >= 1.0
	if dir != 0.0:
		if vel.x != 0.0 and signf(vel.x) != dir:
			# 逆方向に入れた: 速ければ切り返し(スキッド)
			if on_ground and absf(vel.x) >= Tuning.SKID_MIN_SPEED:
				if state != State.SKID:
					events.append("skid")
				state = State.SKID
				vel.x = move_toward(vel.x, 0.0, Tuning.SKID_DECEL * dt)
				return
			vel.x = move_toward(vel.x, 0.0, (Tuning.STOP_DECEL + accel) * dt)
		elif absf(vel.x) > top:
			vel.x = move_toward(vel.x, dir * top, Tuning.STOP_DECEL * rate_scale * dt)
		else:
			vel.x = move_toward(vel.x, dir * top, accel * dt)
		facing = dir
		if state == State.SKID and (vel.x == 0.0 or signf(vel.x) == dir):
			state = State.NORMAL
	else:
		if on_ground:
			vel.x = move_toward(vel.x, 0.0, Tuning.STOP_DECEL * dt)
		if state == State.SKID:
			state = State.NORMAL


## 入力の強さ(0〜1)とダッシュから、横の速さの段(0〜4)を決める。
## 段は入力だけで決まる(SMB3 と同じく、押した瞬間からその段の速さへ加速する)。
##   段0=止まっている / 段1=少し倒す / 段2=大きく倒す / 段3=ダッシュ+少し / 段4=ダッシュ+大きく
func speed_tier(strength: float, run: bool) -> int:
	if strength <= 0.1:
		return 0
	if run:
		return 4 if strength > 0.5 else 3
	return 1 if strength <= 0.5 else 2


## 段に応じた速さ。段の途中の値は作らず、加速で段から段へつなぐ
func tier_speed(tier: int) -> float:
	match tier:
		1:
			return Tuning.CREEP_SPEED
		2:
			return Tuning.WALK_SPEED
		3:
			return Tuning.RUN_SPEED
		4:
			return Tuning.MAX_RUN_SPEED
	return 0.0


func target_speed(strength: float, run: bool) -> float:
	return tier_speed(speed_tier(strength, run))


## 今の横の速さがどの段にあたるか(ジャンプの初速を段にそろえるために使う)
func current_tier() -> int:
	var speed := absf(vel.x)
	if speed >= Tuning.MAX_RUN_SPEED - 0.5:
		return 4
	if speed >= Tuning.RUN_SPEED - 0.5:
		return 3
	if speed >= Tuning.WALK_SPEED - 0.5:
		return 2
	return 1


func _jump() -> void:
	var speed := absf(vel.x)
	var next := 0
	if _last_jump_stage >= 0 and land_timer > 0.0 and speed >= Tuning.TRIPLE_MIN_SPEED:
		next = mini(_last_jump_stage + 1, 2)
		if _last_jump_stage == 2:
			next = 0   # 3段目の後は1段目に戻る
	match next:
		1:
			vel.y = Tuning.JUMP2_SPEED
		2:
			vel.y = Tuning.JUMP3_SPEED
		_:
			# 横の段(1〜4)で初速を選ぶ【SMB3】。高さは初速と重力から決まる結果
			vel.y = Tuning.jump_speed_for_tier(current_tier())
	# 2段目・3段目は横の勢いも上乗せして、高さだけでなく速さでも差を出す
	if next == 1:
		vel.x = clampf(vel.x * Tuning.JUMP2_SPEED_BOOST, -Tuning.MAX_RUN_SPEED * 1.2, Tuning.MAX_RUN_SPEED * 1.2)
	elif next == 2:
		vel.x = clampf(vel.x * Tuning.JUMP3_SPEED_BOOST, -Tuning.MAX_RUN_SPEED * 1.2, Tuning.MAX_RUN_SPEED * 1.2)
	jump_stage = next
	_last_jump_stage = next
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
		if input.jump_pressed:
			_wall_kick(wall)
			return
		vel.x = float(wall) * 0.5   # 壁に接したままにする
		vel.y = maxf(vel.y - Tuning.GRAVITY_FALL * dt, -Tuning.WALL_SLIDE_SPEED)
		return

	# 空中の横移動。壁キック直後は壁方向の入力を無視
	var d := dir
	if wall_lock > 0 and d != 0.0 and d != signf(vel.x):
		d = 0.0
	_horizontal(d, input, dt, Tuning.AIR_ACCEL_RATE)

	vel.y = maxf(vel.y - _gravity(input) * dt, -Tuning.MAX_FALL)


## 重力は2値【SMB3】。勢いよく上がっている間ボタンを押していれば軽く、それ以外は重い。
## 飛び出し直後だけがふわっとして、頂点も落下も重い(高さが時間に対して非線形になる)。
func _gravity(input: PlayerInput) -> float:
	if vel.y > Tuning.RISE_SPEED_THRESHOLD and input.jump_held:
		return Tuning.GRAVITY_RISE
	return Tuning.GRAVITY_FALL


func _wall_kick(wall: int) -> void:
	vel.x = -float(wall) * Tuning.WALL_KICK_SPEED_X
	vel.y = Tuning.velocity_for_height(Tuning.WALL_KICK_HEIGHT)
	facing = -float(wall)
	wall_lock = Tuning.WALL_KICK_LOCK_FRAMES
	state = State.NORMAL
	_last_jump_stage = -1
	events.append("wall_kick")


func _ground_pound(on_floor: bool, dt: float) -> void:
	if _gp_timer > 0.0:
		_gp_timer -= dt
		vel = Vector2.ZERO
	else:
		vel = Vector2(0.0, -Tuning.GP_SPEED)


## 踏みつけたとき。ジャンプを押していれば高く跳ねる
func stomp_bounce(jump_held: bool) -> void:
	var h := Tuning.STOMP_BOUNCE_HIGH if jump_held else Tuning.STOMP_BOUNCE_LOW
	vel.y = Tuning.velocity_for_height(h)
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
	_was_on_floor = false
