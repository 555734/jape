extends Node
## 通信対戦の窓口(Autoload "Online")。タイトル画面から部屋を作る・コードで入る、を受け付け、
## 相手とつながったら試合の情報(通信・自分の番号・種・入力遅延)を用意する。main.gd がそれを受け取って試合を始める。
##
## つなぎ方は2つ:
##   EOS … 本番。別々の回線のスマホどうしでも、Epic の P2P(必要なら中継)でつながる。6桁のコードで部屋に入る
##   LAN … 開発用。同じPC・同じWi-Fi の端末どうしで、IPアドレスを指定して直接つなぐ(UdpTransport)
##
## EOS の認証情報はソースコードに書かない。CI が GitHub Secrets から res://net/eos_secrets.gd を作って
## ビルドに入れる(このファイルは .gitignore 済み)。PCで試すときは環境変数 EOS_PRODUCT_ID などでもよい。

signal changed   ## state か status が変わった

## 通信の版。これが違う相手とは対戦しない(ルールや同期のしかたが変わったら上げる)
const NET_PROTOCOL := 1
const SECRET_KEYS := ["product_id", "sandbox_id", "deployment_id", "client_id", "client_secret"]

var state := "idle"      ## idle / working / ready(試合を始められる) / error
var status := ""         ## 画面に出す説明
var room_code := ""

var _match := {}         ## ready のときの試合の情報
var _eos: Node           ## net/eos_link.gd(EOSG があるときだけ)
var _udp: UdpTransport
var _busy_id := 0        ## 取り消し後に古い処理の結果を無視するための番号


func version_tag() -> String:
	return "%s-n%d" % [ProjectSettings.get_setting("application/config/version", "0"), NET_PROTOCOL]


## EOS で対戦できるか(プラグインと認証情報がそろっているか)
func eos_available() -> bool:
	return Engine.has_singleton("IEOS") and not _credentials().is_empty()


func _credentials() -> Dictionary:
	var c := {}
	if ResourceLoader.exists("res://net/eos_secrets.gd"):
		var s: GDScript = load("res://net/eos_secrets.gd")
		var consts := s.get_script_constant_map()
		for k in SECRET_KEYS:
			c[k] = str(consts.get(k.to_upper(), ""))
		c.encryption_key = str(consts.get("ENCRYPTION_KEY", ""))
	else:
		for k in SECRET_KEYS:
			c[k] = OS.get_environment("EOS_" + k.to_upper())
		c.encryption_key = OS.get_environment("EOS_ENCRYPTION_KEY")
	for k in SECRET_KEYS:
		if c[k] == "":
			return {}
	if c.encryption_key.length() != 64:
		c.encryption_key = "0".repeat(64)   # 端末内の保存データの暗号化用。このゲームは使わない
	return c


# ---- EOS ----------------------------------------------------------------

## 部屋を作る(6桁のコードを決めて相手を待つ)
func host_eos() -> void:
	var id := _begin()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	room_code = "%06d" % rng.randi_range(0, 999999)
	var link := await _eos_link()
	if link == null or not await link.sign_in_async(_credentials(), _fresh_device()):
		return _fail(id, link)
	if not await link.host_async(room_code, version_tag(), rng.randi() | 1, 2):
		return _fail(id, link)
	_ready_match(id, link.make_transport(), 0, link.match_seed, link.input_delay, "eos")


## コードで部屋に入る
func join_eos(code: String) -> void:
	var id := _begin()
	room_code = code
	var link := await _eos_link()
	if link == null or not await link.sign_in_async(_credentials(), _fresh_device()):
		return _fail(id, link)
	if not await link.join_async(code, version_tag()):
		return _fail(id, link)
	_ready_match(id, link.make_transport(), 1, link.match_seed, link.input_delay, "eos")


func _eos_link() -> Node:
	if _eos == null:
		if not Engine.has_singleton("IEOS"):
			status = "通信対戦の部品(EOS)が入っていません"
			return null
		_eos = (load("res://net/eos_link.gd") as GDScript).new()
		_eos.name = "EosLink"
		add_child(_eos)
		_eos.progress.connect(_set_status)
	_eos.cancelled = false
	_eos.error = ""
	return _eos


func _fresh_device() -> bool:
	return "--eos-fresh-device" in OS.get_cmdline_user_args()


# ---- LAN(開発用) --------------------------------------------------------

func host_lan(port := UdpTransport.DEFAULT_PORT) -> void:
	var id := _begin()
	_udp = UdpTransport.new()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	if _udp.host(port, rng.randi() | 1, 2) != OK:
		return _fail(id, null, "ポート %d を使えません" % port)
	_set_status("相手を待っています…\n%s" % ", ".join(_local_addresses()))
	_wait_udp(id)


func join_lan(address: String, port := UdpTransport.DEFAULT_PORT) -> void:
	var id := _begin()
	_udp = UdpTransport.new()
	if _udp.join(address, port) != OK:
		return _fail(id, null, "%s に接続できません" % address)
	_set_status("%s に接続しています…" % address)
	_wait_udp(id)


func _wait_udp(id: int) -> void:
	var limit := Time.get_ticks_msec() + 60000
	while not _udp.connected:
		if id != _busy_id:
			return
		if Time.get_ticks_msec() > limit and not _udp.is_host:
			return _fail(id, null, "相手が見つかりませんでした")
		_udp.update()
		_udp.poll()   # 接続の手続きだけ進める(試合前に届いた入力は、相手がまた送ってくる)
		await get_tree().physics_frame
	_ready_match(id, _udp, 0 if _udp.is_host else 1, _udp.match_seed, _udp.input_delay, "lan")


func _local_addresses() -> PackedStringArray:
	var out := PackedStringArray()
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."):
			out.append(a)
	return out


# ---- 共通 ---------------------------------------------------------------

## つながった試合があるか(main.gd が見る)
func has_match() -> bool:
	return state == "ready" and not _match.is_empty()


## 試合の情報を受け取る: {transport, local, seed, delay, kind}
func take_match() -> Dictionary:
	var m := _match
	_match = {}
	return m


## 待つのをやめる / 試合から抜ける
func leave() -> void:
	_busy_id += 1
	_match = {}
	if _udp != null:
		_udp.close()
		_udp = null
	if _eos != null:
		_eos.leave_async()
	state = "idle"
	_set_status("")


func _begin() -> int:
	leave()
	state = "working"
	_busy_id += 1
	return _busy_id


func _ready_match(id: int, transport: NetTransport, local: int, match_seed: int, delay: int, kind: String) -> void:
	if id != _busy_id:
		return
	_match = {"transport": transport, "local": local, "seed": match_seed, "delay": delay, "kind": kind}
	state = "ready"
	_set_status("つながりました")


func _fail(id: int, link: Node, message := "") -> void:
	if id != _busy_id:
		return   # 取り消し済み
	state = "error"
	if message == "" and link != null:
		message = link.error
	if message == "":
		message = status if status != "" else "接続できませんでした"
	_set_status(message)
	if link != null:
		link.leave_async()


func _set_status(text: String) -> void:
	status = text
	changed.emit()
