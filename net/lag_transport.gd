class_name LagTransport
extends NetTransport
## 開発用: 本物の通信に、わざと遅延・揺らぎ・パケットロスを足す(送る側で遅らせる)。
## 同じPCの2窓でも、スマホ回線に近い条件で操作感を確かめられる。
##   --net-lag=片道のミリ秒  --net-jitter=揺らぎのミリ秒  --net-loss=消える割合(0〜1)

var inner: NetTransport
var lag_ms := 0
var jitter_ms := 0
var loss := 0.0

var _queue: Array = []       ## [送る時刻(ms), データ]
var _rng := RandomNumberGenerator.new()


func _init(p_inner: NetTransport, p_lag_ms: int, p_jitter_ms := 0, p_loss := 0.0) -> void:
	inner = p_inner
	lag_ms = p_lag_ms
	jitter_ms = p_jitter_ms
	loss = p_loss
	_rng.randomize()


func send(bytes: PackedByteArray) -> void:
	if _rng.randf() < loss:
		return
	var at := Time.get_ticks_msec() + lag_ms + (_rng.randi_range(0, jitter_ms) if jitter_ms > 0 else 0)
	_queue.append([at, bytes])
	_flush()


func poll() -> Array[PackedByteArray]:
	_flush()
	return inner.poll()


func _flush() -> void:
	var now := Time.get_ticks_msec()
	var keep: Array = []
	for item in _queue:
		if item[0] <= now:
			inner.send(item[1])
		else:
			keep.append(item)
	_queue = keep
