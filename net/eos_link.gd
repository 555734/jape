extends Node
## EOS(Epic Online Services)で相手とつながるまでの手続き。net/online.gd が EOSG のあるときだけ読み込む。
##   1. EOS を初期化し、端末ごとの匿名ID(Device ID)でログイン(ユーザーのアカウント作成は不要)
##   2. 部屋を作る側: ロビー(定員2)を作り、6桁のコード・試合の種・入力遅延・通信の版を書いておく
##      入る側: コードでロビーを探して入り、部屋の持ち主と P2P でつなぐ
##   3. P2P がつながったら、試合用の通信(net/eos_transport.gd)を渡す
## 費用: ロビー・P2P・中継(リレー)・Device ID ログインはすべて無料。

signal progress(text: String)

const SOCKET := "jape"          ## P2P のソケット名(両方で同じ)
const BUCKET := "jape"          ## ロビーの分類名
const CONNECT_TIMEOUT := 25.0   ## P2P がつながるまで待つ秒数

var error := ""
var cancelled := false          ## 待っている途中でやめた
var is_host := false
var match_seed := 0
var input_delay := 2
var peer                        ## EOSGMultiplayerPeer
var lobby                       ## HLobby

var _platform_ready := false
var _logged_in := false
var _peer_joined := false


func _process(_delta: float) -> void:
	# つながるまでは、ここで P2P を動かす(試合が始まったら EosTransport.poll() が動かす)
	if peer != null and not _peer_joined and peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED:
		peer.poll()


## 初期化とログイン。何度呼んでもよい
func sign_in_async(creds: Dictionary, fresh_device := false) -> bool:
	if not _platform_ready:
		progress.emit("サーバーに接続しています…")
		var c := HCredentials.new()
		c.product_name = "jape"
		c.product_version = str(ProjectSettings.get_setting("application/config/version", "0"))
		c.product_id = creds.product_id
		c.sandbox_id = creds.sandbox_id
		c.deployment_id = creds.deployment_id
		c.client_id = creds.client_id
		c.client_secret = creds.client_secret
		c.encryption_key = creds.encryption_key
		if not await HPlatform.setup_eos_async(c):
			error = "EOS を初期化できませんでした"
			return false
		_platform_ready = true
	if _logged_in:
		return true
	progress.emit("ログインしています…")
	if fresh_device:
		# 開発用: 同じPCで2つ起動するとき、別の人として入るために端末IDを作り直す
		EOS.Connect.ConnectInterface.delete_device_id(EOS.Connect.DeleteDeviceIdOptions.new())
		await IEOS.connect_interface_delete_device_id_callback
	var opts := EOS.Connect.CreateDeviceIdOptions.new()
	opts.device_model = "%s %s" % [OS.get_name(), OS.get_model_name()]
	EOS.Connect.ConnectInterface.create_device_id(opts)
	var created: Dictionary = await IEOS.connect_interface_create_device_id_callback
	if not EOS.is_success(created) and created.result_code != EOS.Result.DuplicateNotAllowed:
		error = "端末IDを作れませんでした (%s)" % EOS.result_str(created)
		return false
	var login := EOS.Connect.LoginOptions.new()
	login.credentials = EOS.Connect.Credentials.new()
	login.credentials.type = EOS.ExternalCredentialType.DeviceidAccessToken
	login.credentials.token = null
	login.user_login_info = EOS.Connect.UserLoginInfo.new()
	login.user_login_info.display_name = "Player"
	HAuth.auto_fetch_external_account = false
	if not await HAuth.login_game_services_async(login):
		error = "ログインできませんでした"
		return false
	HLobbies.presence_enabled = false   # 匿名ログインでは「プレゼンス」(Epicアカウントの機能)は使えない
	_logged_in = true
	return true


## 部屋を作って、相手が入ってつながるまで待つ
func host_async(code: String, version: String, p_seed: int, p_delay: int) -> bool:
	is_host = true
	match_seed = p_seed
	input_delay = p_delay
	peer = EOSGMultiplayerPeer.new()
	var err: Error = peer.create_server(SOCKET)
	if err != OK:
		error = "P2P を始められません (%s)" % error_string(err)
		return false
	progress.emit("部屋を作っています…")
	var opts := EOS.Lobby.CreateLobbyOptions.new()
	opts.bucket_id = BUCKET
	opts.max_lobby_members = 2
	opts.permission_level = EOS.Lobby.LobbyPermissionLevel.PublicAdvertised
	opts.presence_enabled = false
	opts.allow_invites = false
	opts.enable_join_by_id = false
	opts.enable_rtc_room = false
	opts.disable_host_migration = true
	opts.local_user_id = HAuth.product_user_id
	lobby = await HLobbies.create_lobby_async(opts)
	if lobby == null:
		error = "部屋を作れませんでした"
		return false
	lobby.add_attribute("CODE", code)
	lobby.add_attribute("VER", version)
	lobby.add_attribute("SEED", str(p_seed))
	lobby.add_attribute("DELAY", str(p_delay))
	if not await lobby.update_async():
		error = "部屋の設定を書き込めませんでした"
		return false
	progress.emit("相手を待っています…\nコード  %s" % code)
	var joined := [false]
	peer.peer_connected.connect(func(_id: int) -> void: joined[0] = true)
	while not joined[0]:
		if cancelled:
			return false
		await get_tree().process_frame
	_peer_joined = true
	return true


## コードで部屋を探して入り、部屋の持ち主と P2P でつなぐ
func join_async(code: String, version: String) -> bool:
	is_host = false
	progress.emit("部屋を探しています…")
	var found = await HLobbies.search_by_attribute_async([{"key": "CODE", "value": code}])
	if found == null or found.is_empty():
		error = "コード %s の部屋が見つかりません" % code
		return false
	var target = found[0]
	var ver = target.get_attribute("VER").get("value", "")
	if str(ver) != version:
		error = "相手とアプリの版が違います。両方を最新にしてください"
		return false
	lobby = await HLobbies.join_async(target)
	if lobby == null:
		error = "部屋に入れませんでした(満員かもしれません)"
		return false
	match_seed = int(str(lobby.get_attribute("SEED").get("value", "0")))
	input_delay = int(str(lobby.get_attribute("DELAY").get("value", "2")))
	progress.emit("相手とつないでいます…")
	peer = EOSGMultiplayerPeer.new()
	var err: Error = peer.create_client(SOCKET, lobby.owner_product_user_id)
	if err != OK:
		error = "P2P を始められません (%s)" % error_string(err)
		return false
	var timer := get_tree().create_timer(CONNECT_TIMEOUT)
	while peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		if cancelled:
			return false
		if timer.time_left <= 0.0:
			error = "相手とつながりませんでした(通信環境を確認してください)"
			return false
		await get_tree().process_frame
	_peer_joined = true
	return true


## 試合用の通信
func make_transport() -> NetTransport:
	return (load("res://net/eos_transport.gd") as GDScript).new(peer)


## 部屋を出て、P2P を閉じる
func leave_async() -> void:
	cancelled = true
	if peer != null:
		peer.close()
		peer = null
	_peer_joined = false
	if lobby != null:
		var l = lobby
		lobby = null
		if is_host:
			await l.destroy_async()
		else:
			await l.leave_async()
