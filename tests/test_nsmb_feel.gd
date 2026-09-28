extends TestBase
## NSMB DS の操作感の受け入れ条件。基準値の出典と確度は docs/nsmb_ds_physics.md。
##
## ここに書くのは「重い」「気持ちいい」のような主観ではなく、位置・時間・速度の観測値だけ。
## 操作感の注文が来たら、まずこの表に1行足してから数値を動かすこと。
## 確度が unknown の項目はテストにしない。

const DT := 1.0 / 60.0
const HEAD := 0.84            ## 小さい状態の身長(マス)。docs/nsmb_ds_physics.md §4.5

var m: PlayerMoves
var pos := Vector2.ZERO
var peak := 0.0
var wall_x := INF             ## この x に右向きの壁
var step_x := INF             ## この x から先が1マスの段差


func _fresh() -> void:
	m = PlayerMoves.new()
	m.reset()
	m._was_on_floor = true
	pos = Vector2.ZERO
	peak = 0.0
	wall_x = INF
	step_x = INF


## 床(y=0)と、必要なら壁・1マス段差だけの世界で1フレーム進める。
## stages/stage_map.gd の move_box と同じく、横を先に・縦を後に解決する
## (横の判定には動く前の y を使う)
func _frame(input: PlayerInput) -> void:
	var floor_y := 1.0 if pos.x >= step_x else 0.0
	var on_floor := pos.y <= floor_y and m.vel.y <= 0.0
	var wall := 1 if pos.x >= wall_x - 0.001 else 0
	var v := m.step(on_floor, wall, input, DT)

	# 横。段差の側面に当たるかは「動く前の y」で決める
	var y_before := pos.y
	pos.x += v.x * DT
	if step_x != INF and pos.x >= step_x and y_before < 1.0:
		pos.x = step_x - 0.001
		m.vel.x = minf(m.vel.x, 0.0)
	if pos.x > wall_x:
		pos.x = wall_x
		m.vel.x = minf(m.vel.x, 0.0)

	# 縦。着地する床の高さは動いた後の x で決まる
	pos.y += v.y * DT
	var fy := 1.0 if pos.x >= step_x else 0.0
	if pos.y < fy:
		pos.y = fy
		m.vel.y = 0.0
	peak = maxf(peak, pos.y)


func _hold(input: PlayerInput, frames: int) -> void:
	for i in frames:
		_frame(input)


func _until_land(input: PlayerInput) -> int:
	var n := 1
	_frame(input)
	while pos.y > 0.0 and n < 900:
		_frame(input)
		n += 1
	return n


## ダッシュの最高速まで助走する
func _run_in() -> void:
	_hold(PlayerInput.make(1, true, false, false), 180)


# --- 1. 静止状態からの通常ジャンプ最高到達点 -------------------------------
func test_standing_jump_peak() -> void:
	_fresh()
	_frame(PlayerInput.make(0, false, true, true))
	_until_land(PlayerInput.make(0, false, false, true))
	assert_near(peak, 4.34, 0.25, "立ちジャンプの最高到達点 (マス)")
	assert_true(peak + HEAD >= 4.0, \
		"立ちジャンプで足元から4マスのブロックに頭が届く (頭 %.2f マス)" % (peak + HEAD))


# --- 2. ダッシュ最高速からのジャンプ最高到達点 -----------------------------
func test_running_jump_peak() -> void:
	_fresh()
	_run_in()
	peak = 0.0
	_frame(PlayerInput.make(1, true, true, true))
	_until_land(PlayerInput.make(1, true, false, true))
	assert_near(peak, 5.26, 0.3, "助走ジャンプの最高到達点 (マス)")


# --- 3 & 4. ジャンプの上昇時間・落下時間 -----------------------------------
func test_jump_rise_and_fall_time() -> void:
	_fresh()
	_frame(PlayerInput.make(0, false, true, true))
	var up := 0
	while m.vel.y > 0.0 and up < 300:
		_frame(PlayerInput.make(0, false, false, true))
		up += 1
	var down := _until_land(PlayerInput.make(0, false, false, true))
	assert_near(up * DT, 0.48, 0.05, "立ちジャンプの上昇時間 (秒)")
	assert_true(up > down, "上昇のほうが落下より長い (上昇 %d / 落下 %d フレーム)" % [up, down])


# --- 5. 短押しジャンプの高さ -----------------------------------------------
func test_short_hop_height() -> void:
	_fresh()
	_frame(PlayerInput.make(0, false, true, true))
	_hold(PlayerInput.make(0, false, false, true), 2)
	_until_land(PlayerInput.make(0, false, false, false))
	var short_peak := peak
	_fresh()
	_frame(PlayerInput.make(0, false, true, true))
	_until_land(PlayerInput.make(0, false, false, true))
	assert_true(short_peak < peak * 0.45, \
		"すぐ離すと低く跳ぶ (%.2f < 通常 %.2f マスの45%%)" % [short_peak, peak])
	assert_true(short_peak >= 0.8, "それでもブロック1個分は跳べる (%.2f マス)" % short_peak)


# --- 6. 最大水平速度(歩き・ダッシュ) ---------------------------------------
func test_max_horizontal_speed() -> void:
	_fresh()
	_hold(PlayerInput.make(1, false, false, false), 180)
	assert_near(m.vel.x, 5.625, 0.2, "歩きの最高速 (マス/秒)")
	_fresh()
	_run_in()
	assert_near(m.vel.x, 11.25, 0.2, "ダッシュの最高速 (マス/秒)")


# --- 7. 最高速到達までの時間 -----------------------------------------------
## 段ごとに加速が落ちるので、単純な等加速より遅い
func test_time_to_top_speed() -> void:
	_fresh()
	var n := 0
	while m.vel.x < 11.25 - 0.05 and n < 300:
		_frame(PlayerInput.make(1, true, false, false))
		n += 1
	assert_true(n < 300, "ダッシュの最高速に到達する (%d フレーム)" % n)
	assert_near(n * DT, 1.5, 0.4, "ダッシュの最高速に達するまでの時間 (秒)")


# --- 8. 反対方向入力から停止・反転するまでの時間 ---------------------------
func test_turnaround_time() -> void:
	_fresh()
	_run_in()
	var n := 0
	while m.vel.x > 0.0 and n < 300:
		_frame(PlayerInput.make(-1, true, false, false))
		n += 1
	assert_true(n < 300, "ダッシュ中に逆を入れると止まる (%d フレーム)" % n)
	# スキッド減速 21.09 マス/秒² でダッシュ最高速 11.25 から止まるまで約0.53秒
	assert_near(n * DT, 0.53, 0.12, "ダッシュから反転して止まるまでの時間 (秒)")
	assert_true(m.state == PlayerMoves.State.SKID or m.vel.x <= 0.0, "切り返し状態になる")


# --- 9. 空中での方向転換 ---------------------------------------------------
## NSMB は空中でも地上と同じ加速表を使う(docs/nsmb_ds_physics.md §4.1)
func test_air_control() -> void:
	_fresh()
	_hold(PlayerInput.make(1, false, false, false), 180)
	var ground_speed := m.vel.x
	_frame(PlayerInput.make(1, false, true, true))
	var n := 0
	while m.vel.x > 0.0 and n < 300:
		_frame(PlayerInput.make(-1, false, false, true))
		n += 1
	assert_true(n < 300, "空中で逆を入れると向きが変わる (%d フレーム)" % n)
	# 地上と同じ加速なので、同じ速度からの反転にかかる時間も近いはず
	_fresh()
	_hold(PlayerInput.make(1, false, false, false), 180)
	var g := 0
	while m.vel.x > 0.0 and g < 300:
		_frame(PlayerInput.make(-1, false, false, false))
		g += 1
	assert_true(absf(n - g) <= 12, \
		"空中と地上で方向転換にかかる時間がほぼ同じ (空中 %d / 地上 %d フレーム, 初速 %.2f)" % [n, g, ground_speed])


# --- 10. 最大落下速度 -------------------------------------------------------
func test_terminal_velocity() -> void:
	_fresh()
	_frame(PlayerInput.make(0, false, true, true))
	var fastest := 0.0
	for i in 600:
		_frame(PlayerInput.make(0, false, false, true))
		fastest = maxf(fastest, -m.vel.y)
		if pos.y <= 0.0 and i > 5:
			break
	assert_near(fastest, 15.0, 0.4, "最大落下速度 (マス/秒)")


# --- 11. 1回のダッシュジャンプで進む水平距離 -------------------------------
func test_running_jump_distance() -> void:
	_fresh()
	_run_in()
	var x0 := pos.x
	peak = 0.0
	_frame(PlayerInput.make(1, true, true, true))
	_until_land(PlayerInput.make(1, true, false, true))
	var dist := pos.x - x0
	assert_true(dist >= 8.0, "ダッシュジャンプで8マスの穴を越える (%.1f マス)" % dist)
	assert_true(dist < 13.0, "13マスの穴は越えられない (%.1f マス)" % dist)
	assert_true(dist / peak < 2.5, \
		"進む距離は高さの2.5倍未満 (%.1f マス / %.1f マス = %.2f)" % [dist, peak, dist / peak])


# --- 12. 1マス段差との衝突挙動 ---------------------------------------------
## 歩いて登ることはできない(段差の手前で止まる)。ジャンプすれば乗れる
func test_one_tile_step() -> void:
	_fresh()
	step_x = 4.0
	_hold(PlayerInput.make(1, false, false, false), 180)
	assert_true(pos.y < 0.5, "1マスの段差は歩いて登れない (y=%.2f)" % pos.y)
	assert_true(pos.x >= 3.5 and pos.x <= 4.0, "段差の手前で止まる (x=%.2f)" % pos.x)
	_frame(PlayerInput.make(1, false, true, true))
	_hold(PlayerInput.make(1, false, false, true), 60)
	assert_true(pos.y >= 1.0, "ジャンプすれば1マスの段差に乗れる (y=%.2f)" % pos.y)


# --- 速度段の境界 -----------------------------------------------------------
## 段は入力ではなく今の速度で決まる。ボタンで上限段が変わる(歩き=段1 / ダッシュ=段3)
func test_speed_stage_caps() -> void:
	_fresh()
	_hold(PlayerInput.make(1, false, false, false), 180)
	var walk := m.vel.x
	_hold(PlayerInput.make(1, true, false, false), 180)
	var dash := m.vel.x
	_hold(PlayerInput.make(1, false, false, false), 180)
	var back_to_walk := m.vel.x
	assert_near(walk, 5.625, 0.2, "歩きは段1で頭打ち (マス/秒)")
	assert_near(dash, 11.25, 0.2, "ダッシュは段3まで伸びる (マス/秒)")
	assert_near(back_to_walk, 5.625, 0.2, "ダッシュを離すと段1まで落ちる (マス/秒)")


# --- ジャンプ先行入力 -------------------------------------------------------
## 着地の少し前にジャンプを押しておくと、着地した瞬間に跳ぶ
func test_jump_buffer() -> void:
	_fresh()
	_frame(PlayerInput.make(0, false, true, true))
	# 落下中、着地の数フレーム前にジャンプを押して離す
	while m.vel.y > -10.0:
		_frame(PlayerInput.make(0, false, false, true))
	_frame(PlayerInput.make(0, false, true, true))     # 押した瞬間
	var jumped_again := false
	for i in 30:
		_frame(PlayerInput.make(0, false, false, true))
		if pos.y <= 0.001:
			# 着地した。ここから数フレーム以内にまた上昇していれば先行入力が効いている
			for j in 4:
				_frame(PlayerInput.make(0, false, false, true))
			jumped_again = m.vel.y > 0.0
			break
	assert_true(jumped_again, "着地直前のジャンプ入力が着地時に発動する(先行入力)")


# --- コヨーテタイム ---------------------------------------------------------
## 足場を離れた直後の数フレームはまだジャンプできる
func test_coyote_time() -> void:
	_fresh()
	step_x = 0.0        # 最初から高さ1の足場に乗っている扱い
	pos = Vector2(1.0, 1.0)
	_hold(PlayerInput.make(1, false, false, false), 30)
	step_x = INF        # 足場が切れた(ここから落下が始まる)
	_frame(PlayerInput.make(1, false, false, false))
	_frame(PlayerInput.make(1, false, false, false))
	var before := m.vel.y
	_frame(PlayerInput.make(1, false, true, true))
	assert_true(m.vel.y > before and m.vel.y > 0.0, \
		"足場を離れた直後でもジャンプできる(コヨーテタイム。vy %.2f → %.2f)" % [before, m.vel.y])
