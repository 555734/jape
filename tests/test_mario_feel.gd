extends TestBase
## 「マリオと同じ操作感か」を、誰でも目で確かめられる量だけで決める受け入れ条件。
## 基準は SMB3 の実装値(docs/RULES.md §3「v6: SMB3 の移植」)。
##
## ここに書くのは感想ではなく観測できる事実だけにする。
## 操作感の注文が来たら、まずこの表に1行足してから数値を動かすこと。

const DT := 1.0 / 60.0
const HEAD := Simulation.SimPlayer.SMALL_HEIGHT   ## 小さい状態の身長(マス)

var m: PlayerMoves
var pos := Vector2.ZERO
var peak := 0.0            ## 足元が届いた最高の高さ(マス)


func _fresh() -> void:
	m = PlayerMoves.new()
	m.reset()
	m._was_on_floor = true
	pos = Vector2.ZERO
	peak = 0.0


## 床(y=0)だけの世界で1フレーム進める
func _frame(input: PlayerInput) -> void:
	var on_floor := pos.y <= 0.0 and m.vel.y <= 0.0
	var v := m.step(on_floor, 0, input, DT)
	pos += v * DT
	if pos.y < 0.0:
		pos.y = 0.0
		m.vel.y = 0.0
	peak = maxf(peak, pos.y)


func _hold(input: PlayerInput, frames: int) -> void:
	for i in frames:
		_frame(input)


## 着地するまで進める。かかったフレーム数
func _until_land(input: PlayerInput) -> int:
	var n := 1
	_frame(input)
	while pos.y > 0.0 and n < 600:
		_frame(input)
		n += 1
	return n


## ダッシュの最高速まで助走する
func _run_in() -> void:
	_hold(PlayerInput.make(1, true, false, false), 90)


## ボタンを押しっぱなしにした普通のジャンプ。頭が届いた高さを返す
func _full_jump(move_x: float, run: bool) -> float:
	peak = 0.0
	_frame(PlayerInput.make(move_x, run, true, true))
	_until_land(PlayerInput.make(move_x, run, false, true))
	return peak + HEAD


## 1. 立ちジャンプで、足元から4マスのハテナブロックを下から叩ける(原作の基本)
func test_standing_jump_reaches_question_block() -> void:
	_fresh()
	var head := _full_jump(0, false)
	assert_true(head >= 4.0, "立ちジャンプで足元から4マスのブロックに頭が届く (頭 %.2f マス)" % head)


## 2. 助走ジャンプは足元から6マスに届き、7マスには届かない
func test_running_jump_height() -> void:
	_fresh()
	_run_in()
	var head := _full_jump(1, true)
	assert_true(head >= 6.0, "助走ジャンプで6マスに届く (頭 %.2f マス)" % head)
	assert_true(head < 7.5, "助走ジャンプでも7.5マスには届かない (頭 %.2f マス)" % head)


## 3. 歩き・ダッシュの最高速 (SMB3: 1.5 / 2.5 px/frame)
func test_top_speeds() -> void:
	_fresh()
	_hold(PlayerInput.make(1, false, false, false), 90)
	assert_near(m.vel.x, Tuning.WALK_SPEED, 0.3, "歩きの最高速 (マス/秒)")
	_fresh()
	_run_in()
	assert_near(m.vel.x, Tuning.MAX_RUN_SPEED, 0.3, "ダッシュの最高速 (マス/秒)")


## 4. 最高速に達するまでの時間 (SMB3 の加速 14/256 px/frame^2 = 約0.76秒)
func test_time_to_top_speed() -> void:
	_fresh()
	var n := 0
	while m.vel.x < Tuning.MAX_RUN_SPEED - 0.05 and n < 300:
		_frame(PlayerInput.make(1, true, false, false))
		n += 1
	assert_near(n * DT, 0.76, 0.12, "ダッシュの最高速に達するまでの時間 (秒)")


## 5. 落下はこの速さで頭打ちになる (SMB3: 4 px/frame)
func test_max_fall_speed() -> void:
	_fresh()
	_frame(PlayerInput.make(0, false, true, true))
	var fastest := 0.0
	for i in 240:
		_frame(PlayerInput.make(0, false, false, true))
		fastest = maxf(fastest, -m.vel.y)
		if pos.y <= 0.0 and i > 5:
			break
	assert_near(fastest, Tuning.MAX_FALL, 0.5, "最大落下速度 (マス/秒)")


## 6. 上昇より落下のほうが短い(重力を感じる)
func test_rise_and_fall_time() -> void:
	_fresh()
	_run_in()
	_frame(PlayerInput.make(1, true, true, true))
	var up := 0
	while m.vel.y > 0.0 and up < 300:
		_frame(PlayerInput.make(1, true, false, true))
		up += 1
	var down := _until_land(PlayerInput.make(1, true, false, true))
	assert_true(up > down, "上昇のほうが長い (上昇 %d / 落下 %d フレーム)" % [up, down])
	assert_true(up * DT < 0.75, "上昇は0.75秒未満 (%.2f 秒)" % (up * DT))


## 7. 短く押したジャンプは低い
func test_short_hop() -> void:
	_fresh()
	_frame(PlayerInput.make(0, false, true, true))
	_hold(PlayerInput.make(0, false, false, true), 2)
	_until_land(PlayerInput.make(0, false, false, false))
	var short_peak := peak
	_fresh()
	var full := _full_jump(0, false) - HEAD
	assert_true(short_peak < full * 0.45, \
		"すぐ離すと低く跳ぶ (%.2f < 通常 %.2f マスの45%%)" % [short_peak, full])
	assert_true(short_peak >= 0.8, "それでもブロック1個分は跳べる (%.2f マス)" % short_peak)


## 8. 助走ジャンプで越えられる穴の幅
func test_running_jump_distance() -> void:
	_fresh()
	_run_in()
	var x0 := pos.x
	peak = 0.0
	_frame(PlayerInput.make(1, true, true, true))
	_until_land(PlayerInput.make(1, true, false, true))
	var dist := pos.x - x0
	assert_true(dist >= 8.0, "助走ジャンプで8マスの穴を越える (%.1f マス)" % dist)
	# SMB3 の助走ジャンプが進む距離も約11マス。これ以上は越えられない
	assert_true(dist < 12.0, "12マスの穴は越えられない (%.1f マス)" % dist)


## 9. 高さと横の進みの比。横に進みすぎない
func test_height_to_distance_ratio() -> void:
	_fresh()
	_run_in()
	var x0 := pos.x
	peak = 0.0
	_frame(PlayerInput.make(1, true, true, true))
	_until_land(PlayerInput.make(1, true, false, true))
	var ratio := (pos.x - x0) / peak
	assert_true(ratio < 2.0, \
		"助走ジャンプで進む距離は高さの2倍未満 (%.1f マス / %.1f マス = %.2f)" % [pos.x - x0, peak, ratio])
