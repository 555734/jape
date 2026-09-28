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
	assert_near(m.vel.x, Tuning.WALK_SPEED, 0.3, "歩き最高速 (マス/秒)")
	_fresh()
	_run_in()
	assert_near(m.vel.x, Tuning.MAX_RUN_SPEED, 0.65, "ダッシュを1秒続けたときの最高速 (マス/秒)")


func test_running_jump_height_and_timing() -> void:
	_fresh()
	_run_in()
	var up := 0
	_frame(PlayerInput.make(1, true, true, true))
	while m.vel.y > 0.0:
		_frame(PlayerInput.make(1, true, false, true))
		up += 1
	var down := _until_land(PlayerInput.make(1, true, false, true))
	var v0: float = Tuning.JUMP_SPEEDS[3]
	var h := Tuning.height_for_velocity(v0)
	assert_near(peak, h, h * 0.05, "助走ジャンプの高さ (マス)")
	var t_up := Tuning.rise_time_for_velocity(v0)
	assert_near(up * DT, t_up, t_up * 0.08, "上昇時間 (秒)")
	var t_down := Tuning.fall_time_for_height(h)
	assert_near(down * DT, t_down, t_down * 0.08, "落下時間 (秒)")


## 重力を感じること: 上昇はゆっくり、落下はそれより早い(v5の狙い)
func test_fall_is_faster_than_rise() -> void:
	_fresh()
	_run_in()
	var up := 0
	_frame(PlayerInput.make(1, true, true, true))
	while m.vel.y > 0.0:
		_frame(PlayerInput.make(1, true, false, true))
		up += 1
	var down := 0
	var fastest := 0.0
	while pos.y > 0.0 and down < 600:
		_frame(PlayerInput.make(1, true, false, true))
		down += 1
		fastest = maxf(fastest, -m.vel.y)
	assert_true(up > down, "落ちるほうが早い (上昇 %d フレーム > 落下 %d フレーム)" % [up, down])
	assert_near(fastest, Tuning.MAX_FALL, 0.3, "落下は最大落下速度まで達する (マス/秒)")


## 飛び出し直後だけが軽いこと【SMB3】: 同じ速さの幅を、上昇初期は頂点付近よりゆっくり通る
func test_rise_starts_light() -> void:
	_fresh()
	_run_in()
	_frame(PlayerInput.make(1, true, true, true))
	var v0 := m.vel.y
	var band := 3.0
	var early := 0
	var apex := 0
	for i in 200:
		var v := m.vel.y
		if v <= v0 and v > v0 - band:
			early += 1
		if absf(v) <= band:
			apex += 1
		_frame(PlayerInput.make(1, true, false, true))
		if pos.y <= 0.0 and m.vel.y <= 0.0:
			break
	assert_true(early > apex * 2, "飛び出し直後がふわっと伸びる (初期 %d フレーム > 頂点付近 %d フレームの2倍)" % [early, apex])


func test_standing_and_short_jump() -> void:
	_fresh()
	_frame(PlayerInput.make(0, false, true, true))
	_until_land(PlayerInput.make(0, false, false, true))
	var stand := Tuning.height_for_velocity(Tuning.JUMP_SPEEDS[0])
	assert_near(peak, stand, stand * 0.05, "立ちジャンプの高さ (マス)")
	_fresh()
	_frame(PlayerInput.make(0, false, true, true))
	_hold(PlayerInput.make(0, false, false, true), 2)
	_until_land(PlayerInput.make(0, false, false, false))
	# 通常ジャンプの6割未満になること
	var limit := Tuning.height_for_velocity(Tuning.JUMP_SPEEDS[3]) * 0.6
	assert_true(peak < limit, "すぐ離すと低く跳ぶ (高さ %.2f < %.2fマス)" % [peak, limit])


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
	assert_near(h[0], Tuning.height_for_velocity(Tuning.JUMP_SPEEDS[3]), 0.3, "3段ジャンプ 1段目 (マス)")
	assert_near(h[1], Tuning.height_for_velocity(Tuning.JUMP2_SPEED), 0.3, "3段ジャンプ 2段目 (マス)")
	assert_near(h[2], Tuning.height_for_velocity(Tuning.JUMP3_SPEED), 0.35, "3段ジャンプ 3段目 (マス)")
	assert_true(h[1] - h[0] >= 1.0 and h[2] - h[1] >= 1.0, "段ごとに1マス以上高くなる (%.1f → %.1f → %.1f)" % h)
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
	assert_near(frames * DT, Tuning.MAX_RUN_SPEED / Tuning.SKID_DECEL, 0.06, "切り返しで止まるまでの秒数")


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


## 横の速さが4段に刻まれていること(段1=少し倒す / 段2=大きく倒す / 段3=ダッシュ / 段4=ダッシュ継続)
func test_four_speed_steps() -> void:
	var speeds := []
	_fresh()
	_hold(PlayerInput.make(0.3, false, false, false), 60)
	speeds.append(m.vel.x)
	_fresh()
	_hold(PlayerInput.make(0.9, false, false, false), 60)
	speeds.append(m.vel.x)
	_fresh()
	_hold(PlayerInput.make(0.3, true, false, false), 90)
	speeds.append(m.vel.x)
	_fresh()
	_hold(PlayerInput.make(1, true, false, false), 90)
	speeds.append(m.vel.x)
	assert_near(speeds[0], Tuning.CREEP_SPEED, 0.2, "段1 ゆっくり歩き (マス/秒)")
	assert_near(speeds[1], Tuning.WALK_SPEED, 0.3, "段2 歩き (マス/秒)")
	assert_near(speeds[2], Tuning.RUN_SPEED, 0.3, "段3 ダッシュ+少し倒す (マス/秒)")
	assert_near(speeds[3], Tuning.MAX_RUN_SPEED, 0.3, "段4 ダッシュ+大きく倒す (マス/秒)")
	for i in 3:
		assert_true(speeds[i + 1] - speeds[i] >= 1.0, \
			"段%d と段%d の差が1マス/秒以上 (%.1f → %.1f)" % [i + 1, i + 2, speeds[i], speeds[i + 1]])


## 段の中では速さが変わらない(滑らかに伸び続けない)
func test_speed_holds_within_a_step() -> void:
	_fresh()
	_hold(PlayerInput.make(0.6, false, false, false), 30)
	var a := m.vel.x
	_hold(PlayerInput.make(1.0, false, false, false), 30)
	assert_near(m.vel.x, a, 0.2, "同じ段なら倒し具合を変えても速さは同じ (%.1f → %.1f)" % [a, m.vel.x])


func test_triple_jump_speeds_up() -> void:
	_fresh()
	_run_in()
	var vx := []
	for i in 3:
		_frame(PlayerInput.make(1, true, true, true))
		vx.append(m.vel.x)
		_until_land(PlayerInput.make(1, true, false, true))
		_hold(PlayerInput.make(1, true, false, false), 2)
	assert_true(vx[1] > vx[0] and vx[2] > vx[1], "2段目・3段目は横の勢いも増える (%.1f → %.1f → %.1f)" % vx)
