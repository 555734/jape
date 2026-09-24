class_name PlayerMotor
extends RefCounted
## プレイヤーの速度計算。シーンに依存しないので、テストで直接動かせる。


## 入力と接地状態から、次のフレームの速度を返す(x=横, y=縦)
static func step(vel: Vector2, on_floor: bool, input: PlayerInput, dt: float) -> Vector2:
	# 横移動
	var top := Tuning.RUN_SPEED if input.run else Tuning.WALK_SPEED
	var accel := Tuning.RUN_ACCEL if input.run else Tuning.WALK_ACCEL
	if absf(input.move_x) > 0.1:
		var target := signf(input.move_x) * top
		var rate := accel
		if signf(vel.x) != signf(target) and vel.x != 0.0:
			rate = Tuning.STOP_DECEL + accel  # 反対方向への切り返し
		elif absf(vel.x) > top:
			rate = Tuning.STOP_DECEL  # ダッシュをやめたときに減速
		vel.x = move_toward(vel.x, target, rate * dt)
	else:
		vel.x = move_toward(vel.x, 0.0, Tuning.STOP_DECEL * dt)

	# 縦移動
	if on_floor:
		vel.y = 0.0
		if input.jump_pressed:
			vel.y = Tuning.jump_velocity(vel.x)
	else:
		var g := Tuning.GRAVITY_DOWN
		if vel.y > 0.0:
			g = Tuning.GRAVITY_UP if input.jump_held else Tuning.GRAVITY_CUT
		vel.y = maxf(vel.y - g * dt, -Tuning.MAX_FALL)
	return vel
