class_name NetTransport
extends RefCounted
## 通信の出入り口(相手1人とのデータのやり取り)。RollbackSession はこれだけを使う。
## 実際の通信手段(同じ端末内の疑似回線・ENet・EOS)ごとに、これを継承して send と poll を作る。
## 届く順番・届くかどうかは保証しない(速さ優先の UDP 的な送り方)前提。


## 相手へ送る
func send(_bytes: PackedByteArray) -> void:
	pass


## 届いているデータを全部取り出す
func poll() -> Array[PackedByteArray]:
	return []


## 通信を閉じる
func close() -> void:
	pass
