extends TestBase
## 動きの数値と仕組みが docs/RULES.md §3 どおりか。
## 床(y=0)と、必要なら壁だけの簡単な世界で、入力を1フレームずつ流して確かめる。

const DT := 1.0 / 60.0

var m: PlayerMoves
var pos := Vector2.ZERO
var wall_x := INF          ## この x に右向きの壁(プレイヤーの右側にある壁)
var peak := 0.0


func _fresh() -> void:
	m = PlayerMoves.new()
	m.reset()
	m._was_on_floor = true
	pos = Vector2.ZERO
	wall_x = INF
	peak = 0.0


func _frame(input: PlayerInput) -> void:
	var on_floor := pos.y <= 0.0 and m.vel.y <= 0.0
	var wall := 1 if pos.x >= wall_x - 0.001 else 0
	var v := m.step(on_floor, wall, input, DT)
	pos += v * DT
	if pos.x > wall_x:
		pos.x = wall_x
		m.vel.x = minf(m.vel.x, 0.0)
	if pos.y < 0.0:
		pos.y = 0.0
		m.vel.y = 0.0
	peak = maxf(peak, pos.y)


func _hold(input: PlayerInput, frames: int) -> void:
	for i in frames:
		_frame(input)


## 着地するまで入力を流し続ける。かかったフレーム数
func _until_land(input: PlayerInput) -> int:
	var n := 0
	_frame(input)
	n += 1
	while pos.y > 0.0 and n < 600:
		_frame(input)
		n += 1
	return n


func _run_in() -> void:
	_hold(PlayerInput.make(1, true, false, false), 60)


func test_walk_and_run_speed() -> void:
	_fresh()
	_hold(PlayerInput.make(1, false, false, false), 60)
	assert_near(m.vel.x, 5.6, 0.28, "歩き最高速 (マス/秒)")
	_fresh()
	_run_in()
	assert_near(m.vel.x, 11.3, 0.565, "ダッシュ最高速 (マス/秒)")


func test_running_jump_height_and_timing() -> void:
	_fresh()
	_run_in()
	var up := 0
	_frame(PlayerInput.make(1, true, true, true))
	while m.vel.y > 0.0:
		_frame(PlayerInput.make(1, true, false, true))
		up += 1
	var down := _until_land(PlayerInput.make(1, true, false, true))
	assert_near(peak, 5.0, 0.25, "助走ジャンプの高さ (マス)")
	assert_near(up * DT, 0.6, 0.03, "上昇時間 (秒)")
	assert_near(down * DT, 0.45, 0.0225, "落下時間 (秒)")


func test_standing_and_short_jump() -> void:
	_fresh()
	_frame(PlayerInput.make(0, false, true, true))
	_until_land(PlayerInput.make(0, false, false, true))
	assert_near(peak, 4.0, 0.2, "立ちジャンプの高さ (マス)")
	_fresh()
	_frame(PlayerInput.make(0, false, true, true))
	_hold(PlayerInput.make(0, false, false, true), 2)
	_until_land(PlayerInput.make(0, false, false, false))
	assert_true(peak < 2.0, "すぐ離すと低く跳ぶ (高さ %.2f < 2マス)" % peak)


## 3段ジャンプ: 着地直後に跳ぶたびに高くなる
func _triple(delay_frames: int) -> Array:
	var heights := []
	for i in 3:
		peak = 0.0
		_frame(PlayerInput.make(1, true, true, true))
		_until_land(PlayerInput.make(1, true, false, true))
		heights.append(peak)
		_hold(PlayerInput.make(1, true, false, false), delay_frames)
	return heights


func test_triple_jump() -> void:
	_fresh()
	_run_in()
	var h := _triple(2)
	assert_near(h[0], 5.0, 0.25, "3段ジャンプ 1段目 (マス)")
	assert_near(h[1], 6.0, 0.3, "3段ジャンプ 2段目 (マス)")
	assert_near(h[2], 7.0, 0.35, "3段ジャンプ 3段目 (マス)")
	assert_true(m.jump_stage == 2, "3段目になっている")


func test_triple_jump_needs_timing() -> void:
	_fresh()
	_run_in()
	var h := _triple(int(Tuning.TRIPLE_WINDOW / DT) + 3)
	assert_true(absf(h[1] - h[0]) < 0.3, "着地から猶予を過ぎて跳ぶと2段目にならない (%.2f → %.2f)" % [h[0], h[1]])


func test_triple_jump_needs_speed() -> void:
	_fresh()
	var hs := []
	for i in 2:
		peak = 0.0
		_frame(PlayerInput.make(0, false, true, true))
		_until_land(PlayerInput.make(0, false, false, true))
		hs.append(peak)
	assert_true(absf(hs[1] - hs[0]) < 0.3, "止まったまま連続で跳んでも2段目にならない")


func test_skid() -> void:
	_fresh()
	_run_in()
	_frame(PlayerInput.make(-1, true, false, false))
	assert_true(m.state == PlayerMoves.State.SKID and "skid" in m.events, "ダッシュ中に逆を入れると切り返しになる")
	var frames := 1
	while m.vel.x > 0.0 and frames < 120:
		_frame(PlayerInput.make(-1, true, false, false))
		frames += 1
	assert_near(frames * DT, 11.3 / Tuning.SKID_DECEL, 0.05, "切り返しで止まるまでの秒数")


func test_wall_slide_and_kick() -> void:
	_fresh()
	wall_x = 3.0
	_run_in()   # 壁にぶつかる
	_frame(PlayerInput.make(1, true, true, true))
	_hold(PlayerInput.make(1, true, false, true), 50)   # 上昇して落ち始める
	assert_true(m.state == PlayerMoves.State.WALL_SLIDE, "落下中に壁へ押すと壁すべり")
	assert_near(m.vel.y, -Tuning.WALL_SLIDE_SPEED, 0.01, "壁すべりの落下速度 (マス/秒)")
	_frame(PlayerInput.make(1, true, true, true))
	assert_true("wall_kick" in m.events, "壁すべり中にジャンプで壁キック")
	assert_true(m.vel.x < 0.0 and m.vel.y > 0.0, "壁と反対・上向きに飛ぶ")
	var lock_frames := 0
	while m.wall_lock > 0:
		_frame(PlayerInput.make(1, true, false, true))
		lock_frames += 1
		if lock_frames == 8:
			assert_true(m.vel.x < 0.0, "壁キック直後は壁方向の入力が効かない(8フレーム目も壁と反対へ進む)")
	assert_true(lock_frames == 16, "入力制限は16フレーム (%d)" % lock_frames)


func test_ground_pound() -> void:
	_fresh()
	_frame(PlayerInput.make(0, false, true, true))
	_hold(PlayerInput.make(0, false, false, true), 15)
	_frame(PlayerInput.make(0, false, false, false, true, true))
	assert_true(m.is_ground_pounding() and m.vel == Vector2.ZERO, "空中で下を押すと止まってヒップドロップ")
	_hold(PlayerInput.make(0, false, false, false, true), int(Tuning.GP_HOVER / DT) + 2)
	assert_near(m.vel.y, -Tuning.GP_SPEED, 0.01, "止まった後に急降下")
	_until_land(PlayerInput.make(1, false, false, false, true))
	_frame(PlayerInput.make(1, false, false, false, true))   # 着地したフレーム
	assert_true(m.state == PlayerMoves.State.GP_LAND, "着地後は少し動けない")


func test_crouch_only_when_big() -> void:
	_fresh()
	_frame(PlayerInput.make(0, false, false, false, true))
	assert_true(m.state != PlayerMoves.State.CROUCH, "小さい状態ではしゃがまない")
	m.big = true
	_frame(PlayerInput.make(0, false, false, false, true))
	assert_true(m.state == PlayerMoves.State.CROUCH, "大きい状態で下を押すとしゃがむ")


func test_stomp_bounce() -> void:
	_fresh()
	m.stomp_bounce(false)
	var low := m.vel.y
	m.stomp_bounce(true)
	assert_true(m.vel.y > low, "踏んだ瞬間にジャンプを押していると高く跳ねる")
