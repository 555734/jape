class_name UdpTransport
extends NetTransport
## 開発用の直接接続(UDP)。同じPCの2つの窓や、同じWi-Fiの端末どうしで通信対戦を試すためのもの。
## 本番(別々の回線のスマホどうし)は EOS の P2P を使う。
##
## 接続の手順: 参加側が HELLO を送り続け、部屋側が受け取ったら WELCOME(試合の種・入力遅延)を返す。
## WELCOME が届いた時点で両方とも connected になり、試合を始める。

const PACKET_HELLO := 200
const PACKET_WELCOME := 201
const DEFAULT_PORT := 24680

var is_host := false
var connected := false
var match_seed := 0
var input_delay := 2

var _udp := PacketPeerUDP.new()
var _server := UDPServer.new()
var _resend := 0


## 部屋を作る(相手の接続を待つ)
func host(port: int, p_seed: int, p_input_delay: int) -> Error:
	is_host = true
	match_seed = p_seed
	input_delay = p_input_delay
	return _server.listen(port)


## 部屋に入る
func join(address: String, port: int) -> Error:
	is_host = false
	return _udp.connect_to_host(address, port)


## 接続の手続きを進める(毎tick呼ぶ)。試合用のデータは poll() で受け取る
func update() -> void:
	if is_host:
		_server.poll()
		if _server.is_connection_available():
			_udp = _server.take_connection()   # 最初に来た1人だけを相手にする
	elif not connected:
		_resend -= 1
		if _resend <= 0:
			_resend = 10
			_send_raw(PackedByteArray([PACKET_HELLO]))


func send(bytes: PackedByteArray) -> void:
	if connected:
		_send_raw(bytes)


func poll() -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = []
	if is_host:
		_server.poll()   # 部屋側は、これを呼ぶと相手からのデータが _udp に届く
	if not _udp.is_socket_connected():
		return out
	while _udp.get_available_packet_count() > 0:
		var p := _udp.get_packet()
		if p.is_empty():
			continue
		match p[0]:
			PACKET_HELLO:
				if is_host:
					var buf := StreamPeerBuffer.new()
					buf.put_u8(PACKET_WELCOME)
					buf.put_u32(match_seed)
					buf.put_u8(input_delay)
					_send_raw(buf.data_array)   # 届かなかったときのため、HELLO が来るたびに返す
					connected = true
			PACKET_WELCOME:
				if not is_host and not connected:
					var buf := StreamPeerBuffer.new()
					buf.data_array = p
					buf.get_u8()
					match_seed = buf.get_u32()
					input_delay = buf.get_u8()
					connected = true
			_:
				out.append(p)
	return out


func _send_raw(bytes: PackedByteArray) -> void:
	if _udp.is_socket_connected():
		_udp.put_packet(bytes)


func close() -> void:
	connected = false
	_udp.close()
	_server.stop()
