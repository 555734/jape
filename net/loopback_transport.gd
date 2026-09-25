class_name LoopbackTransport
extends NetTransport
## テスト用の疑似回線。同じプロセスの中の2つの端をつなぎ、遅延・揺らぎ・パケットロスを入れられる。
## 時間は「tick」(1/60秒)で数え、Link.advance() で1つ進める。


class Link:
	extends RefCounted
	var latency := 0        ## 片道の遅延(tick)
	var jitter := 0         ## 遅延の揺らぎ(0〜jitter tick が足される)
	var loss := 0.0         ## パケットが消える確率
	var now := 0
	var rng := RandomNumberGenerator.new()
	var sent := 0
	var lost := 0

	func advance() -> void:
		now += 1


var link: Link
var peer: LoopbackTransport
var _inbox: Array = []      ## [届く tick, データ]


## 2つの端を作ってつなぐ。latency と jitter は片道の tick 数
static func pair(latency := 0, jitter := 0, loss := 0.0, seed_value := 1) -> Array[LoopbackTransport]:
	var l := Link.new()
	l.latency = latency
	l.jitter = jitter
	l.loss = loss
	l.rng.seed = seed_value
	var a := LoopbackTransport.new()
	var b := LoopbackTransport.new()
	a.link = l
	b.link = l
	a.peer = b
	b.peer = a
	return [a, b]


func send(bytes: PackedByteArray) -> void:
	link.sent += 1
	if link.rng.randf() < link.loss:
		link.lost += 1
		return
	var delay := link.latency + (link.rng.randi_range(0, link.jitter) if link.jitter > 0 else 0)
	peer._inbox.append([link.now + delay, bytes])


func poll() -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = []
	var keep: Array = []
	for item in _inbox:
		if item[0] <= link.now:
			out.append(item[1])
		else:
			keep.append(item)
	_inbox = keep
	return out
