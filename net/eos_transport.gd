extends NetTransport
## 本番の通信: EOS(Epic Online Services)の P2P。EOSG の EOSGMultiplayerPeer を「パケットを送る・受け取る」だけに使う。
## NAT 越えに失敗しても Epic の中継(リレー)を通るので、別々の回線のスマホどうしでもつながる(無料)。
## 速さ優先の「届かなくてもよい」送り方(UnreliableUnordered)。抜けた分は RollbackSession が送り直す。
##
## EOSG が無い環境でもこのファイルの読み込みで失敗しないよう、型は書かずに扱う(net/eos_link.gd から作る)。

var peer   ## EOSGMultiplayerPeer


func _init(p_peer) -> void:
	peer = p_peer
	peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_UNRELIABLE
	peer.target_peer = MultiplayerPeer.TARGET_PEER_BROADCAST   # 相手は1人だけ


func send(bytes: PackedByteArray) -> void:
	if peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		peer.put_packet(bytes)


func poll() -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = []
	peer.poll()
	while peer.get_available_packet_count() > 0:
		out.append(peer.get_packet())
	return out


func close() -> void:
	peer.close()
