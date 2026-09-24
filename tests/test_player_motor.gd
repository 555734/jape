extends TestBase
## 動きの数値が docs/RULES.md の表(動画実測)どおりか。許容誤差は±5%。

const DT := 1.0 / 60.0


## 地面の上で seconds 秒入力し続けたときの横速度
func _speed_after(run: bool, seconds: float) -> float:
	var v := Vector2.ZERO
	for i in int(seconds / DT):
		v = PlayerMotor.step(v, true, PlayerInput.make(1.0, run, false, false), DT)
	return v.x


## 助走速度 vx でジャンプし、ボタンを hold_frames フレーム押したときの [最高到達点, 上昇秒, 落下秒]
func _jump(vx: float, hold_frames: int) -> Array:
	var v := Vector2(vx, 0)
	var y := 0.0
	var peak := 0.0
	var frame := 0
	var t_peak := 0.0
	v = PlayerMotor.step(v, true, PlayerInput.make(signf(vx), absf(vx) > Tuning.WALK_SPEED, true, true), DT)
	while true:
		y += v.y * DT
		frame += 1
		if y > peak:
			peak = y
			t_peak = frame * DT
		if y <= 0.0 and frame > 1:
			break
		var held := frame < hold_frames
		v = PlayerMotor.step(v, false, PlayerInput.make(signf(vx), absf(vx) > Tuning.WALK_SPEED, false, held), DT)
	return [peak, t_peak, frame * DT - t_peak]


func test_walk_top_speed() -> void:
	assert_near(_speed_after(false, 1.0), 5.6, 5.6 * 0.05, "歩き最高速 (マス/秒)")


func test_run_top_speed() -> void:
	assert_near(_speed_after(true, 1.0), 11.3, 11.3 * 0.05, "ダッシュ最高速 (マス/秒)")


func test_time_to_top_speed() -> void:
	assert_near(_speed_after(false, 0.4), 5.6, 5.6 * 0.05, "0.4秒後の歩き速度")


func test_running_jump() -> void:
	var r := _jump(Tuning.RUN_SPEED, 999)
	assert_near(r[0], 5.0, 5.0 * 0.05, "助走ジャンプの高さ (マス)")
	assert_near(r[1], 0.6, 0.6 * 0.05, "上昇時間 (秒)")
	assert_near(r[2], 0.45, 0.45 * 0.05, "落下時間 (秒)")


func test_standing_jump() -> void:
	var r := _jump(0.0, 999)
	assert_near(r[0], 4.0, 4.0 * 0.05, "立ちジャンプの高さ (マス)")


func test_short_hop() -> void:
	var r := _jump(0.0, 3)
	assert_true(r[0] < 2.0, "すぐ離すと低く跳ぶ (高さ %.2f < 2マス)" % r[0])
