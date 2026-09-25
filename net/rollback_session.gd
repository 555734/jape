class_name RollbackSession
extends RefCounted
## 通信対戦の同期(ロールバック方式、GGPO 型)。
##   - 自分の入力は input_delay フレーム後の分として相手へ送る(少し遅らせて、予測が外れる回数を減らす)
##   - 相手の入力がまだ届いていないフレームは「直前の入力が続く」と予測して先へ進める
##   - 届いた入力が予測と違ったら、そのフレームの状態に巻き戻して、今のフレームまで計算し直す
##   - 予測できるのは MAX_PREDICTION フレーム先まで。それより相手が遅れたら待つ
##   - 30フレームごとに確定した状態のチェックサムを送り合い、ずれ(desync)を見つける
## 画面・通信手段に依存しないので、疑似回線(LoopbackTransport)でテストできる。
##
## 使い方: 60Hz で毎回 tick(自分の入力) を呼ぶ。進んだかどうかは戻り値、画面用の出来事は events。

const MAX_PREDICTION := 8       ## 相手の入力を予測して進めてよいフレーム数
const CHECKSUM_EVERY := 30      ## チェックサムを比べる間隔(フレーム)
const SYNC_INTERVAL := 20       ## 時間合わせで1回待ったら、次に待てるまでの間隔(tick)
const MAX_SEND := 32            ## 1つのパケットに入れる入力の最大数
const PACKET_INPUT := 1
## 予測では「押した瞬間」は繰り返さない(ジャンプの連打と誤って予測しないように)
const PRESS_BITS := (2 | 8) << 8

var sim: Simulation
var local := 0                  ## 自分のプレイヤー番号
var transport: NetTransport
var input_delay := 2

## このtickで初めて計算したフレームの出来事(巻き戻して計算し直した分は含めない)
var events: Array = []
## 統計(画面表示・調整用)
var rollbacks := 0              ## 巻き戻した回数
var rollback_frames := 0        ## 計算し直したフレーム数の合計
var stalls := 0                 ## 相手を待って止まった回数
var waits := 0                  ## 時間合わせで待った回数
var rtt := 0.0                  ## 往復の遅延(tick、なめらかにした値)
var desync_frame := -1          ## ずれを見つけたフレーム(-1 ならまだない)
var checks_compared := 0        ## 相手とチェックサムを比べた回数
var ticks_since_recv := 0       ## 最後に相手から届いてからの tick 数(切断の判定用)

var _tick := 0
var _local_inputs := {}         ## フレーム → 自分の入力(ビット列)
var _remote_inputs := {}        ## フレーム → 相手の入力(確定)
var _predicted := {}            ## フレーム → 計算に使った相手の入力(予測かもしれない)
var _states := {}               ## フレーム → そのフレームを計算する前の状態
var _last_remote := -1          ## ここまでの相手の入力は全部届いている
var _remote_ack := -1           ## 相手が受け取った自分の入力の最後のフレーム
var _last_remote_bits := 0
var _sent_tick := {}            ## フレーム → そのフレームの入力を初めて送った tick(遅延の計測用)
var _remote_frame := 0          ## 相手が最後に知らせてきた、相手の今のフレーム
var _remote_advantage := 0.0    ## 相手から見た「相手が先に進んでいる量」
var _last_wait_tick := -1000
var _my_adv := 0.0
var _their_adv := 0.0
var _my_sums := {}              ## フレーム → 自分のチェックサム
var _their_sums := {}           ## フレーム → 相手のチェックサム
var _next_sum := CHECKSUM_EVERY
var _last_compared := -1
var _max_simulated := -1        ## 一度でも計算したことのある最後のフレーム


func _init(p_sim: Simulation, p_local: int, p_transport: NetTransport, p_input_delay := 2) -> void:
	sim = p_sim
	local = p_local
	transport = p_transport
	input_delay = p_input_delay
	# 最初の input_delay フレームは、どちらも「何も押していない」で決まっている
	for f in input_delay:
		_local_inputs[f] = 0
		_remote_inputs[f] = 0
	_last_remote = input_delay - 1


## 今のフレーム(次に計算するフレーム)
var frame: int:
	get:
		return sim.frame


## 1tick 進める。自分の入力を渡す。シミュレーションが1フレーム進んだら true
func tick(local_input: PlayerInput) -> bool:
	_tick += 1
	ticks_since_recv += 1
	events.clear()
	_receive()
	_my_adv = _my_adv * 0.95 + _local_advantage() * 0.05
	_their_adv = _their_adv * 0.95 + _remote_advantage * 0.05
	_rollback_if_needed()
	_update_checksums()

	var advanced := false
	if frame - _last_remote > MAX_PREDICTION:
		stalls += 1            # 相手が遅れすぎ: 予測をやめて待つ
	elif _should_wait():
		waits += 1             # 時間合わせ: 自分が先に進みすぎているので1回待つ
		_last_wait_tick = _tick
	else:
		_local_inputs[frame + input_delay] = local_input.quantized().to_bits()
		_step_frame(frame)
		advanced = true
	_send()
	_forget_old()
	return advanced


func _step_frame(f: int) -> void:
	_states[f] = sim.save_state()
	var remote_bits: int
	if _remote_inputs.has(f):
		remote_bits = _remote_inputs[f]
	else:
		remote_bits = _last_remote_bits & ~PRESS_BITS
	_predicted[f] = remote_bits
	var ins := [null, null]
	ins[local] = PlayerInput.from_bits(_local_inputs.get(f, 0))
	ins[1 - local] = PlayerInput.from_bits(remote_bits)
	sim.step(ins)
	if f > _max_simulated:
		_max_simulated = f
		events.append_array(sim.events)


## 届いた入力が予測と違っていたら、そのフレームまで戻して計算し直す
func _rollback_if_needed() -> void:
	var first_wrong := -1
	for f in range(maxi(0, _last_confirmed_checked), frame):
		if _remote_inputs.has(f) and _predicted.has(f) and _predicted[f] != _remote_inputs[f]:
			first_wrong = f
			break
	_last_confirmed_checked = mini(_last_remote + 1, frame)
	if first_wrong < 0:
		return
	var target := frame
	sim.load_state(_states[first_wrong])
	rollbacks += 1
	for f in range(first_wrong, target):
		_step_frame(f)
		rollback_frames += 1

var _last_confirmed_checked := 0


# ---- 送受信 -------------------------------------------------------------

## パケット: [種類 u8][今のフレーム u32][受け取った相手の入力の最後 i32][先頭フレーム u32][数 u8][入力 u16 × 数]
##          [先に進んでいる量 f32][チェックサムのフレーム i32][チェックサム u32]
func _send() -> void:
	# 相手がまだ受け取っていない分を、古い順に送る(途中が抜けると相手は先へ進めないため)
	var start := maxi(_remote_ack + 1, 0)
	var end := mini(frame - 1 + input_delay, start + MAX_SEND - 1)   # ここまでの自分の入力が決まっている
	var buf := StreamPeerBuffer.new()
	buf.put_u8(PACKET_INPUT)
	buf.put_u32(frame)
	buf.put_32(_last_remote)
	buf.put_u32(start)
	var count := maxi(0, end - start + 1)
	buf.put_u8(count)
	for f in range(start, start + count):
		buf.put_u16(_local_inputs.get(f, 0))
		if not _sent_tick.has(f):
			_sent_tick[f] = _tick
	buf.put_float(_local_advantage())
	var sum_frame := -1
	var sum := 0
	if not _my_sums.is_empty():
		sum_frame = _my_sums.keys().max()
		sum = _my_sums[sum_frame]
	buf.put_32(sum_frame)
	buf.put_u32(sum)
	transport.send(buf.data_array)


func _receive() -> void:
	for bytes in transport.poll():
		var buf := StreamPeerBuffer.new()
		buf.data_array = bytes
		if buf.get_u8() != PACKET_INPUT:
			continue
		ticks_since_recv = 0
		var their_frame := buf.get_u32()
		var ack := buf.get_32()
		var start := buf.get_u32()
		var count := buf.get_u8()
		for k in count:
			var f := start + k
			var bits := buf.get_u16()
			if not _remote_inputs.has(f) and f > _last_remote - MAX_SEND:
				_remote_inputs[f] = bits
		_remote_advantage = buf.get_float()
		var sum_frame := buf.get_32()
		var sum := buf.get_u32()
		if sum_frame >= 0:
			_their_sums[sum_frame] = sum
		if their_frame > _remote_frame:
			_remote_frame = their_frame
		if ack > _remote_ack:
			if _sent_tick.has(ack):
				var sample := float(_tick - _sent_tick[ack])
				rtt = sample if rtt == 0.0 else rtt * 0.9 + sample * 0.1
			_remote_ack = ack
	while _remote_inputs.has(_last_remote + 1):
		_last_remote += 1
		_last_remote_bits = _remote_inputs[_last_remote]


# ---- 時間合わせ ---------------------------------------------------------

## 自分が相手より何フレーム先に進んでいるか(相手の今のフレームは、届くまでの片道ぶんを足して見積もる)
func _local_advantage() -> float:
	return float(frame) - (float(_remote_frame) + rtt * 0.5)


## 両方から見た差の半分が1フレーム以上なら、先に進んでいる側が1回待つ。
## 回線の揺らぎで毎回ぶれるので、なめらかにした値で決める
func _should_wait() -> bool:
	if _tick - _last_wait_tick < SYNC_INTERVAL:
		return false
	return _my_adv >= 1.0 and (_my_adv - _their_adv) * 0.5 >= 1.0


# ---- ずれの検出 ---------------------------------------------------------

## 両者の入力が確定したフレームのチェックサムを記録し、相手のものと比べる
func _update_checksums() -> void:
	while _next_sum <= _last_remote and _next_sum + 1 <= frame - 1 and _states.has(_next_sum + 1):
		_my_sums[_next_sum] = hash(_states[_next_sum + 1])
		_next_sum += CHECKSUM_EVERY
	for f in _their_sums.keys():
		if _my_sums.has(f):
			if f > _last_compared:
				_last_compared = f
				checks_compared += 1
			if _my_sums[f] != _their_sums[f] and desync_frame < 0:
				desync_frame = f
			_their_sums.erase(f)
		elif f < _next_sum - CHECKSUM_EVERY * 4:
			_their_sums.erase(f)


## 巻き戻しで使わなくなった古い記録を捨てる
func _forget_old() -> void:
	var keep_from := mini(_last_remote, _next_sum) - MAX_SEND
	for dict in [_states, _predicted, _sent_tick]:
		for f in dict.keys():
			if f < keep_from:
				dict.erase(f)
	for f in _local_inputs.keys():
		if f < mini(_remote_ack, keep_from):
			_local_inputs.erase(f)
	for f in _remote_inputs.keys():
		if f < keep_from:
			_remote_inputs.erase(f)
	for f in _my_sums.keys():
		if f < _next_sum - CHECKSUM_EVERY * 4:
			_my_sums.erase(f)
