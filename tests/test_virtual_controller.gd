extends TestBase
## 入力機器が違っても物理が同じになること(actors/player/virtual_controller.gd)。
##
## 原作(NSMB DS)はデジタル十字キー + ダッシュボタンなので、傾き具合で速さが変わってはいけない。
## スマホだからという理由の物理補正(ジャンプを高く・重力を弱く等)も入れない。

const DT := 1.0 / 60.0


## スティックの傾きは -1 / 0 / +1 に落ちる
func test_digital_axis() -> void:
	assert_near(VirtualController.digital_axis(0.0), 0.0, 0.0, "倒していない")
	assert_near(VirtualController.digital_axis(0.1), 0.0, 0.0, "わずかな傾きは無視する")
	assert_near(VirtualController.digital_axis(0.3), 1.0, 0.0, "少し倒しても右いっぱい")
	assert_near(VirtualController.digital_axis(1.0), 1.0, 0.0, "いっぱい倒しても同じ")
	assert_near(VirtualController.digital_axis(-0.3), -1.0, 0.0, "少し倒しても左いっぱい")
	assert_near(VirtualController.digital_axis(-1.0), -1.0, 0.0, "左いっぱい")


## 傾きの違いが速さに影響しない: スティックを半分だけ倒しても、
## 量子化を通れば全開と同じ最高速になる(タッチとキーボードで物理が変わらない)
func test_tilt_does_not_change_speed() -> void:
	var speeds := []
	for raw in [0.3, 0.6, 1.0]:
		var m := PlayerMoves.new()
		m.reset()
		m._was_on_floor = true
		var mx := VirtualController.digital_axis(raw)
		for i in 180:
			m.step(true, 0, PlayerInput.make(mx, true, false, false), DT)
		speeds.append(m.vel.x)
	assert_near(speeds[0], speeds[2], 0.001, "傾き0.3と1.0で同じ最高速 (マス/秒)")
	assert_near(speeds[1], speeds[2], 0.001, "傾き0.6と1.0で同じ最高速 (マス/秒)")
	assert_near(speeds[2], Tuning.WALK_MAX_VELOCITY[Tuning.RUN_STAGE], 0.2, "ダッシュの最高速 (マス/秒)")


## 通信対戦用の量子化を通しても、デジタル入力は値が変わらない
func test_survives_network_quantization() -> void:
	for mx in [-1.0, 0.0, 1.0]:
		var q := PlayerInput.make(mx, true, true, true).quantized()
		assert_near(q.move_x, mx, 0.01, "量子化しても左右の入力が変わらない (%.1f)" % mx)
		assert_true(q.run and q.jump_pressed and q.jump_held, "ボタンも保たれる")
