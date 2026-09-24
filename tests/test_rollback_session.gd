extends TestBase
## ロールバック同期(RollbackSession)を、同じプロセスの中の疑似回線で2台ぶん動かして確かめる。
## 遅延・揺らぎ(順番の入れ替わり)・パケットロスがあっても、2台の状態がずれないこと。


## 2台で ticks 回だけ回す。各端末の自分側は CPU が操作する。start_gap は2台目が遅れて始める tick 数
func _play(latency: int, jitter: int, loss: float, ticks: int, start_gap := 0) -> Array[RollbackSession]:
	var ends := LoopbackTransport.pair(latency, jitter, loss, 5)
	var sessions: Array[RollbackSession] = []
	var brains: Array[CpuBrain] = []
	for i in 2:
		var sim := Simulation.new(2024)   # 同じ種(試合開始時に部屋の持ち主が決めて伝える)
		sessions.append(RollbackSession.new(sim, i, ends[i], 2))
		brains.append(CpuBrain.new(sim, i, 100 + i))
	var t0 := Time.get_ticks_usec()
	for t in ticks:
		ends[0].link.advance()
		for i in 2:
			if i == 1 and t < start_gap:
				continue
			sessions[i].tick(brains[i].think(Simulation.DT))
	var per := float(Time.get_ticks_usec() - t0) / ticks / 2.0
	print("    1台・1tick あたり %.2f ms (巻き戻しの計算し直しを含む)" % (per / 1000.0))
	return sessions


func _report(s: Array[RollbackSession], what: String) -> void:
	var a := s[0]
	var b := s[1]
	print("    [%s] frame %d/%d rollback %d回(%dF) stall %d/%d wait %d/%d rtt %.1f checks %d/%d" % [
		what, a.frame, b.frame, a.rollbacks + b.rollbacks, a.rollback_frames + b.rollback_frames,
		a.stalls, b.stalls, a.waits, b.waits, a.rtt, a.checks_compared, b.checks_compared])
	assert_true(a.desync_frame < 0 and b.desync_frame < 0, "%s: ずれなし" % what)
	assert_true(a.checks_compared > 50 and b.checks_compared > 50, "%s: チェックサムを比べている" % what)
	assert_true(absi(a.frame - b.frame) <= RollbackSession.MAX_PREDICTION + 2, "%s: 2台のフレームが近い" % what)


func test_perfect_line() -> void:
	var s := _play(0, 0, 0.0, 3000)
	_report(s, "遅延なし")
	assert_true(s[0].rollbacks == 0, "遅延なしなら巻き戻しは起きない")
	assert_true(s[0].frame > 2900, "ほぼ止まらずに進む")


## 片道75ms(4.5tick)・揺らぎあり・5%ロス = 条件の悪いスマホ回線
func test_bad_mobile_line() -> void:
	var s := _play(4, 3, 0.05, 5000)
	_report(s, "RTT約150ms・ロス5%")
	assert_true(s[0].frame > 4500, "待ちすぎずに進む (%d)" % s[0].frame)


## 片方が遅れて始まっても、時間合わせで追いつき、ずれない
func test_late_start_catches_up() -> void:
	var s := _play(2, 1, 0.0, 3000, 30)
	_report(s, "30tick遅れて開始")
	assert_true(s[0].waits > 0, "先に進んだ側が待って合わせる")


## 相手の入力が止まると、予測できる範囲まで進んでから待つ
func test_stall_when_peer_silent() -> void:
	var ends := LoopbackTransport.pair(0, 0, 0.0, 1)
	var s := RollbackSession.new(Simulation.new(1), 0, ends[0], 2)
	for t in 60:
		ends[0].link.advance()
		s.tick(PlayerInput.new())
	assert_true(s.frame <= 2 + RollbackSession.MAX_PREDICTION, "相手が無言なら %d フレームまでで止まる (%d)" % [
		2 + RollbackSession.MAX_PREDICTION, s.frame])
	assert_true(s.stalls > 0 and s.ticks_since_recv == 60, "待っていて、無通信の時間を数えている")
