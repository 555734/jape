extends TestBase
## 通信対戦(ロールバック)の前提を確かめる:
##   - 同じ種・同じ入力なら、何度回しても毎フレーム同じ状態になる(決定的)
##   - save_state() → load_state() で戻して同じ入力を流し直すと、戻さなかったときと同じ状態になる
##   - 地形の当たり判定(StageMap.move_box)が床・壁・天井で止まる


## CPU同士で frames フレーム回し、各フレームの入力(ビット列)とチェックサムを返す
func _run_cpu(seed_value: int, frames: int, every: int) -> Dictionary:
	var sim := Simulation.new(seed_value)
	var brains := [CpuBrain.new(sim, 0, seed_value + 1), CpuBrain.new(sim, 1, seed_value + 2)]
	var inputs: Array[PackedInt32Array] = []
	var sums := []
	for f in frames:
		var ins := []
		var bits := PackedInt32Array()
		for i in 2:
			var inp: PlayerInput = (brains[i] as CpuBrain).think(Simulation.DT).quantized()
			ins.append(inp)
			bits.append(inp.to_bits())
		inputs.append(bits)
		sim.step(ins)
		if f % every == 0:
			sums.append(sim.checksum())
	return {"inputs": inputs, "sums": sums, "final": sim.checksum(), "sim": sim}


func _inputs_at(inputs: Array[PackedInt32Array], f: int) -> Array:
	return [PlayerInput.from_bits(inputs[f][0]), PlayerInput.from_bits(inputs[f][1])]


func test_same_seed_same_result() -> void:
	var a := _run_cpu(12345, 6000, 30)
	var b := _run_cpu(12345, 6000, 30)
	assert_true(a.sums == b.sums, "同じ種・同じ入力なら毎回同じ状態 (%d 回比較)" % a.sums.size())
	var sim: Simulation = a.sim
	assert_true(sim.rules.wins[0] + sim.rules.wins[1] > 0 or sim.frame == 6000, "試合が進んでいる")
	var c := _run_cpu(999, 600, 30)
	assert_true(c.final != a.sums[20], "種が違えば状態も違う")


## 入力の記録を流し直すだけで同じ結果になる(相手の入力だけ受け取れば再現できる)
func test_replay_from_inputs() -> void:
	var ref := _run_cpu(777, 3000, 3000)
	var sim := Simulation.new(777)
	for f in 3000:
		sim.step(_inputs_at(ref.inputs, f))
	assert_true(sim.checksum() == ref.final, "記録した入力だけで同じ最終状態になる")


## ロールバックの真似: 毎フレーム「保存 → でたらめな予測入力で数フレーム先まで進める → 戻す → 正しい入力で1フレーム」
func test_rollback_restores_everything() -> void:
	var frames := 2400
	var ref := _run_cpu(4242, frames, frames)
	var sim := Simulation.new(4242)
	var junk := RandomNumberGenerator.new()
	junk.seed = 1
	for f in frames:
		var saved := sim.save_state()
		for k in junk.randi_range(1, 8):
			var fake := PlayerInput.make(junk.randf_range(-1.0, 1.0), junk.randf() < 0.5, junk.randf() < 0.3,
				junk.randf() < 0.5, junk.randf() < 0.2, junk.randf() < 0.1).quantized()
			sim.step([fake, fake])
		sim.load_state(saved)
		sim.step(_inputs_at(ref.inputs, f))
	assert_true(sim.checksum() == ref.final, "巻き戻しを毎フレーム挟んでも同じ最終状態になる")


func test_input_bits_round_trip() -> void:
	var i := PlayerInput.make(-0.5, true, true, false, true, false)
	var j := PlayerInput.from_bits(i.to_bits())
	assert_true(j.run and j.jump_pressed and not j.jump_held and j.down and not j.down_pressed, "ボタンが戻る")
	assert_near(j.move_x, -0.5, 0.01, "横の入力が戻る")
	assert_true(j.quantized().to_bits() == j.to_bits(), "丸めた入力をもう一度丸めても変わらない")


func test_collision_floor_wall_ceiling() -> void:
	var m := StageMap.new([
		"          ",
		"   ##     ",
		"          ",
		"      #   ",
		"##########",
	])
	# 床に落ちて止まる
	var r := m.move_box(1.5, 1.3, 0.8, 0.9, 0.0, -0.5)
	assert_near(r[1], 1.0, 0.0001, "床の上で止まる")
	assert_true(r[3] == -1, "着地を返す")
	# 床に立ったまま(速度0)でも着地扱い
	r = m.move_box(1.5, 1.0, 0.8, 0.9, 0.0, 0.0)
	assert_true(r[3] == -1 and r[1] == 1.0, "立っているだけでも床を見つける")
	# 右の壁(x=6 のマス)で止まる
	r = m.move_box(5.3, 1.0, 0.8, 0.9, 0.5, 0.0)
	assert_near(r[0], 6.0 - 0.4, 0.0001, "右の壁の手前で止まる")
	assert_true(r[2] == 1, "右の壁を返す")
	# 壁に接したまま押しても動かない
	r = m.move_box(5.6, 1.0, 0.8, 0.9, 0.1, 0.0)
	assert_near(r[0], 5.6, 0.0001, "接した壁にめり込まない")
	# 天井(y=3 のマス)に頭をぶつける
	r = m.move_box(3.5, 1.5, 0.8, 0.9, 0.0, 1.0)
	assert_near(r[1], 3.0 - 0.9, 0.0001, "天井で止まる")
	assert_true(r[3] == 1, "天井を返す")
	# 床の端: 箱が少しでも床にかかっていれば立てる
	r = m.move_box(0.0 + 10.0 - 0.1, 1.0, 0.8, 0.9, 0.0, 0.0)
	assert_true(r[3] == -1, "左右ループをまたいでも床を見つける")
