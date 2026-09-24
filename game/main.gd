extends Node3D
## 対戦の画面。中身(ルール・2人・当たり判定・ラウンドの進行)は Simulation が持ち、
## ここは毎フレーム入力を集めて Simulation を1フレーム進め、その状態をステージ・キャラ・HUD・カメラに映す。
##
## 開発用の起動オプション(godot ... -- の後に付ける):
##   --cpu-both        1Pも CPU にする(自動で試合が進む)
##   --capture=DIR     画面をPNG保存(--every=N フレームごと、--frames=N 枚で終了)
##   --sim             画面なしで試合を最後まで回し、結果を表示して終了(詰まりがあれば終了コード1)
##   --seed=N          乱数の種(再現用)

const VIEW_TILES_Y_ORIGINAL := 12.0   ## 原作の画面は縦12マス【動画】
const GROUND_MARGIN := 3.0      ## 足場を画面下から何マス上に見せるか(タッチ操作の親指と重ならないように)
const CAM_TAU_X := 0.08         ## 横の追従の速さ(秒。小さいほど速い)
const CAM_TAU_Y := 0.18         ## 縦の追従の速さ
const CAM_TAU_FALL := 0.05      ## 落下中・画面端に近いときの縦の追従
const CAM_BAND_LO := 2.0        ## 足元が画面下からこのマス数より下に来たら追う
const CAM_BAND_HI := 2.0        ## 頭が画面上からこのマス数より上に来たら追う
const FOV := 30.0
const SIM_LIMIT := 900.0        ## --sim の上限(秒)
const SIM_STUCK := 30.0         ## --sim: この秒数同じ場所なら詰まり

var sim: Simulation
var rules: MatchRules:
	get:
		return sim.rules
var map: StageMap
var stage: Grassland
var players: Array[Player] = []
var brains: Array = [null, null]
var input_sources: Array[Callable] = [PlayerInput.from_actions, PlayerInput.from_actions]
var cam_index := 0              ## カメラが追うプレイヤー(自分)
var camera: Camera3D
var hud: Hud

var _big_star: Node3D
var _cam_x := 0.0
var _cam_y := 0.0
var _look := 0.0
var _cam_ready := false
var _drop_views := {}           ## drop id -> PickupView
var _item_views := {}           ## item id -> PickupView
var _args := {}
var _rng := RandomNumberGenerator.new()
var _frame := 0
var _shot := 0
var _time := 0.0
var _sim_last := [Vector3.ZERO, Vector3.ZERO]
var _sim_still := [0.0, 0.0]
var _sim_stuck := 0
var _sim_rounds := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var seed_value := int(_args.get("seed", "0"))
	if seed_value != 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()
	_setup_input()
	_setup_environment()

	camera = Camera3D.new()
	camera.fov = FOV
	add_child(camera)
	camera.current = true
	hud = Hud.new()
	add_child(hud)
	var online := _args.has("host") or _args.has("join")
	if not _args.has("cpu-both") and not _args.has("sim"):
		if ControlSettings.control_mode == "buttons":
			add_child(TouchControls.new())
		else:
			add_child(StickControls.new())
		if not online:   # 通信対戦中は一時停止も動きの数値の変更もできないので出さない
			var panel := SettingsPanel.new()
			panel.report_source = _report
			add_child(panel)
	# 撮影・タッチ再現は一時停止中(設定パネルを開いている間)も動かす
	var cap := _Capturer.new()
	cap.game = self
	cap.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(cap)

	if online:
		_setup_online()
		return
	_build_world(_rng.randi())
	if _args.has("demo-moves"):
		input_sources[0] = _demo_moves_input
	if _args.has("soak"):
		for i in 2:
			var src := _RandomInput.new(_rng.randi())
			_soak_inputs.append(src)   # Callable だけでは参照が保たれないので持っておく
			input_sources[i] = src.next
	for i in 2:
		if _args.has("demo-moves") and i == 0:
			continue
		if i == 1 or _args.has("cpu-both") or _args.has("sim"):
			_attach_cpu(i)
	_handle_events(sim.events)


## 試合の中身(Simulation)と、それを映すステージ・キャラを作る
func _build_world(match_seed: int) -> void:
	map = StageMap.new(StageMap.PRACTICE if _args.has("practice") else StageMap.GRASSLAND)
	sim = Simulation.new(match_seed, map)
	stage = Grassland.new()
	stage.map = map
	stage.sim = sim
	add_child(stage)
	for i in 2:
		var p := Player.new()
		p.index = i
		p.sim = sim.players[i]
		add_child(p)
		players.append(p)
	_big_star = Assets.spawn(Assets.STAR, 1.2)
	_big_star.visible = false
	add_child(_big_star)


func _attach_cpu(i: int) -> void:
	brains[i] = CpuBrain.new(sim, i, _rng.randi())
	var b: CpuBrain = brains[i]
	input_sources[i] = func() -> PlayerInput: return b.think(Simulation.DT)


class _Capturer extends Node:
	var game: Node

	func _process(_dt: float) -> void:
		game._capture()


func _physics_process(_dt: float) -> void:
	if _net != null:
		_online_tick()
		return
	_time += Simulation.DT
	var inputs := []
	for i in 2:
		inputs.append((input_sources[i].call() as PlayerInput).quantized())
	sim.step(inputs)
	_handle_events(sim.events)
	if _args.has("sim"):
		_sim_check(Simulation.DT)
	if _args.has("soak"):
		_soak_check()


# ---- 通信対戦 -----------------------------------------------------------
## 開発用の起動オプション:
##   --host[=ポート]                 部屋を作って相手を待つ(1P になる)
##   --join=アドレス[:ポート]        部屋に入る(2P になる)
##   --net-lag=ms --net-jitter=ms --net-loss=0〜1   わざと回線を悪くする
##   --cpu-both と組み合わせると自分側も CPU が操作する(2窓で自動対戦)

const DISCONNECT_TICKS := 180   ## この間(3秒)何も届かなければ切断とみなす

var _net: UdpTransport
var _session: RollbackSession
var _net_state := ""            ## "" / "waiting" / "playing" / "lost" / "desync"


func _setup_online() -> void:
	_net = UdpTransport.new()
	var err: Error
	if _args.has("host"):
		var port := int(_args["host"]) if _args["host"] != "" else UdpTransport.DEFAULT_PORT
		err = _net.host(port, _rng.randi() | 1, int(_args.get("net-delay", "2")))
		print("NET host port=%d" % port)
	else:
		var parts: PackedStringArray = (_args["join"] as String).split(":")
		var port := int(parts[1]) if parts.size() > 1 else UdpTransport.DEFAULT_PORT
		err = _net.join(parts[0], port)
		print("NET join %s:%d" % [parts[0], port])
	if err != OK:
		push_error("NET 接続を始められません: %s" % error_string(err))
	_net_state = "waiting"


func _online_tick() -> void:
	_net.update()
	if _session == null:
		_net.poll()   # 接続の手続きだけ進める(試合前に届いた入力は、相手がまた送ってくる)
		if _net.connected:
			_start_online()
		return
	_time += Simulation.DT
	var input: PlayerInput = input_sources[_session.local].call()
	_session.tick(input)
	_handle_events(_session.events)
	if _session.desync_frame >= 0 and _net_state == "playing":
		_net_state = "desync"
		print("NET DESYNC at frame %d" % _session.desync_frame)
	if _session.ticks_since_recv > DISCONNECT_TICKS and _net_state == "playing":
		_net_state = "lost"
		print("NET LOST")
		if _args.has("sim"):
			_sim_finish()


func _start_online() -> void:
	var local := 0 if _net.is_host else 1
	_build_world(_net.match_seed)
	ControlSettings.use_default_tuning()   # 両方の端末で同じ動きの数値にする(保存はしない)
	cam_index = local
	var transport: NetTransport = _net
	if _args.has("net-lag") or _args.has("net-loss"):
		transport = LagTransport.new(_net, int(_args.get("net-lag", "0")), int(_args.get("net-jitter", "0")),
			float(_args.get("net-loss", "0")))
	_session = RollbackSession.new(sim, local, transport, _net.input_delay)
	if _args.has("cpu-both") or _args.has("sim"):
		_attach_cpu(local)
	_net_state = "playing"
	print("NET start as %dP seed=%d delay=%d" % [local + 1, _net.match_seed, _net.input_delay])


## 通信の状態(画面の隅に出す)
func _net_status() -> String:
	if _net == null:
		return ""
	match _net_state:
		"waiting":
			return "接続を待っています…" if _net.is_host else "接続中…"
		"lost":
			return "通信が切れました"
		"desync":
			return "同期がずれました (frame %d)" % _session.desync_frame
	return "ping %d ms  巻き戻し %d" % [roundi(_session.rtt * 1000.0 / 60.0), _session.rollbacks]


## Simulation の出来事を、演出・表示・ログにする
func _handle_events(events: Array) -> void:
	for ev in events:
		match ev[0]:
			"move":
				players[ev[1]].on_move_event(ev[2])
			"round_start":
				_cam_ready = false   # ラウンド開始時はカメラを追いかけさせず、その場に切り替える
			"star_spawn":
				_log("STAR SPAWN point %d at (%.1f, %.1f)" % [ev[1] + 1, sim.star_x, sim.star_y])
			"star":
				_log("STAR %dP (1P %d, 2P %d)" % [ev[1] + 1, rules.stars[0], rules.stars[1]])
			"miss":
				var why := ""
				if brains[ev[1]] != null:
					var b: CpuBrain = brains[ev[1]]
					why = " target=(%.1f, %.1f)" % [b.target.x, b.target.y]
				_log("MISS %dP at (%.1f, %.1f)%s" % [ev[1] + 1, ev[2], ev[3], why])
			"round_end":
				_sim_rounds += 1
				print("ROUND %d: %dP wins (1P %d - %d 2P) t=%.1fs" % [
					_sim_rounds, ev[1] + 1, rules.wins[0], rules.wins[1], _time])
			"match_over":
				if _args.has("sim"):
					_sim_finish(ev[1])


## ラウンドの結果の表示。通信対戦では巻き戻しで出来事が取り消されることがあるので、出来事ではなく状態から決める
func _banner_text() -> String:
	if sim.wait <= 0 or rules.round_winner < 0:
		return ""
	var w := rules.round_winner
	if rules.match_winner >= 0:
		return "%dP WINS THE MATCH!\n1P %d - %d 2P" % [w + 1, rules.wins[0], rules.wins[1]]
	return "%dP WIN!\n1P %d - %d 2P" % [w + 1, rules.wins[0], rules.wins[1]]


func _process(dt: float) -> void:
	if sim == null:
		hud.show_banner(_net_status())
		return
	for i in 2:
		players[i].invuln = rules.invuln[i]
		players[i].sync(dt)
	stage.sync(dt)
	_sync_pickups(dt)
	_big_star.visible = sim.star_visible
	_big_star.position = Vector3(sim.star_x, sim.star_y, 0.0)
	_update_camera(dt)
	_wrap_all()
	_big_star.rotate_y(dt * 2.0)
	var star_x := sim.star_x if sim.star_visible else -1.0
	hud.update(rules, [sim.players[0].x, sim.players[1].x], star_x, map.width, cam_index)
	var banner := _banner_text()
	if _net_state == "lost" or _net_state == "desync":
		banner = _net_status()
	hud.show_banner(banner)
	hud.show_status(_net_status())


## 落ちたスター・成長アイテムの見た目を、Simulation の中身に合わせて出し入れする
func _sync_pickups(dt: float) -> void:
	_sync_views(_drop_views, sim.drops, dt)
	_sync_views(_item_views, sim.items, dt)
	for id in _drop_views:
		(_drop_views[id] as Pickups.PickupView).show_age(rules.drop_age(id))


func _sync_views(views: Dictionary, list: Array, dt: float) -> void:
	var seen := {}
	for obj in list:
		var o: Simulation.SimPickup = obj
		seen[o.id] = true
		if not views.has(o.id):
			var v := Pickups.PickupView.new(o)
			add_child(v)
			views[o.id] = v
		var view: Pickups.PickupView = views[o.id]
		view.sim = o   # 巻き戻しで作り直された物にもつなぎ直す
		view.sync(dt)
	for id in views.keys():
		if not seen.has(id):
			(views[id] as Node).queue_free()
			views.erase(id)


## カメラ。横は途切れずに進み続け(ループの継ぎ目でも飛ばない)、縦は「帯」の中にいる間は動かさない。
## なめらかさは時間基準(フレームの速さに左右されない)。
func _update_camera(dt: float) -> void:
	var view := ControlSettings.view_tiles
	var dist := (view * 0.5) / tan(deg_to_rad(FOV * 0.5))
	var p := sim.players[cam_index]
	if not _cam_ready:
		_cam_x = p.position.x
		_cam_y = p.position.y + view * 0.5 - GROUND_MARGIN
		_cam_ready = true

	# 横: 先読み(進行方向を少し先まで見せる。速いほど先まで)
	var speed := clampf(absf(p.velocity.x) / Tuning.RUN_SPEED, 0.0, 1.0)
	_look = move_toward(_look, p.moves.facing * (1.0 + 1.5 * speed), dt * 6.0)
	var target_x := _cam_x + map.delta_x(_cam_x, p.position.x) + _look
	_cam_x = lerpf(_cam_x, target_x, 1.0 - exp(-dt / CAM_TAU_X))

	# 縦: 足元が「画面下から CAM_BAND_LO マス」〜「画面上から CAM_BAND_HI マス」の帯にいる間は動かない
	var bottom := _cam_y - view * 0.5
	var feet := p.position.y
	var head := feet + p.height()
	var target_y := _cam_y
	var tau := CAM_TAU_Y
	if p.is_on_floor():
		# 立っている足場を画面下から GROUND_MARGIN マスに戻す(高い足場に乗ったら上げる・下りたら下げる)
		target_y = feet + view * 0.5 - GROUND_MARGIN
	if feet - bottom < CAM_BAND_LO:
		target_y = feet - CAM_BAND_LO + view * 0.5
		if p.velocity.y < 0.0:
			tau = CAM_TAU_FALL   # 落下中は素早く追う
	elif (bottom + view) - head < CAM_BAND_HI:
		target_y = head + CAM_BAND_HI - view * 0.5
		tau = CAM_TAU_FALL
	target_y = clampf(target_y, view * 0.5 - GROUND_MARGIN, map.height - view * 0.5 + 1.0)
	_cam_y = lerpf(_cam_y, target_y, 1.0 - exp(-dt / tau))
	camera.position = Vector3(_cam_x, _cam_y, dist)


## 左右ループの見た目: 全員をカメラに一番近い周回位置に表示する
func _wrap_all() -> void:
	stage.wrap_visuals(_cam_x)
	for p in players:
		p.set_view_shift(map.image_x(p.position.x, _cam_x) - p.position.x)
	for views in [_drop_views, _item_views]:
		for id in views:
			var v: Pickups.PickupView = views[id]
			v.set_view_shift(map.image_x(v.position.x, _cam_x) - v.position.x)
	if _big_star.visible:
		_big_star.position.x = map.image_x(_big_star.position.x, _cam_x)


# ---- 開発用 -------------------------------------------------------------

## --soak=秒: 2人を乱数で操作して長時間回し、毎フレーム異常がないか確かめる(キャラが消える不具合の調査用)
class _RandomInput extends RefCounted:
	var rng := RandomNumberGenerator.new()
	var cur := PlayerInput.new()
	var left := 0

	func _init(seed_value: int) -> void:
		rng.seed = seed_value

	func next() -> PlayerInput:
		left -= 1
		var was_jump := cur.jump_held
		var was_down := cur.down
		if left <= 0:
			left = rng.randi_range(5, 60)
			cur = PlayerInput.make([-1.0, 0.0, 1.0][rng.randi_range(0, 2)], rng.randf() < 0.6,
				false, rng.randf() < 0.5, rng.randf() < 0.12)
		var out := PlayerInput.make(cur.move_x, cur.run, cur.jump_held and not was_jump, cur.jump_held,
			cur.down, cur.down and not was_down)
		return out


var _soak_inputs: Array = []
var _soak_errors := 0
var _soak_frames := 0
var _soak_wraps := 0
var _soak_prev_x := [0.0, 0.0]


func _soak_check() -> void:
	_soak_frames += 1
	var view := ControlSettings.view_tiles
	for i in 2:
		var p := sim.players[i]
		var bad := ""
		if not (is_finite(p.x) and is_finite(p.y) and is_finite(p.vx) and is_finite(p.vy)):
			bad = "位置か速度が数値として壊れた"
		elif p.x < 0.0 or p.x >= map.width or p.y > map.height + 8.0:
			bad = "ステージの外"
		elif not p.dead and rules.invuln[i] <= 0.0 and not players[i].model_visible():
			bad = "無敵でないのにモデルが非表示"
		elif i == 0 and not p.dead and _time > 1.0 and sim.wait <= 0:
			var feet_on_screen := p.y - (_cam_y - view * 0.5)
			if p.y > -1.0 and (feet_on_screen < -0.5 or feet_on_screen > view + 0.5):
				bad = "カメラの画面外 (足元が画面下から%.1fマス)" % feet_on_screen
		if bad != "":
			_soak_errors += 1
			if _soak_errors <= 20:
				print("SOAK NG t=%.2f %dP %s pos=(%.2f, %.2f) vel=(%.2f, %.2f) state=%d" % [
					_time, i + 1, bad, p.x, p.y, p.vx, p.vy, p.moves.state])
		if absf(p.x - _soak_prev_x[i]) > map.width * 0.5:
			_soak_wraps += 1
			if i == 0 and _args.has("verbose"):
				print("WRAP 1P frame=%d" % Engine.get_process_frames())
		_soak_prev_x[i] = p.x
	if _time >= float(_args.get("soak", "60")):
		print("SOAK RESULT: %.0fs %d frames, wraps=%d, errors=%d" % [_time, _soak_frames, _soak_wraps, _soak_errors])
		get_tree().quit(1 if _soak_errors > 0 else 0)


## 不具合報告の中身(設定パネルの「不具合報告をコピー」)
func _report() -> String:
	var lines := []
	lines.append("renderer=%s gpu=%s / %s os=%s model=%s" % [
		RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name(),
		RenderingServer.get_video_adapter_vendor(), OS.get_name(), OS.get_model_name()])
	lines.append("fps=%d time=%.1f frame=%d cam=(%.2f, %.2f) checksum=%d" % [
		Engine.get_frames_per_second(), _time, sim.frame, _cam_x, _cam_y, sim.checksum()])
	for i in 2:
		var p := sim.players[i]
		lines.append("P%d pos=(%.2f, %.2f) vel=(%.2f, %.2f) state=%d big=%s dead=%s visible=%s floor=%s stars=%d lives=%d" % [
			i + 1, p.x, p.y, p.vx, p.vy, p.moves.state, str(p.big), str(p.dead),
			str(players[i].visible), str(p.on_floor), rules.stars[i], rules.lives[i]])
	for e in sim.enemies:
		lines.append("enemy pos=(%.2f, %.2f) alive=%s" % [e.x, e.y, str(e.is_alive())])
	return "\n".join(lines)


var _demo := {"phase": 0, "jumps": 0, "was_floor": true, "t": 0}

## --demo-moves: 右へダッシュ → 3段ジャンプ → 壁すべり → 壁キック → ヒップドロップ を自動で行う
func _demo_moves_input() -> PlayerInput:
	var p := sim.players[0]
	var d := _demo
	d.t += 1
	var on_floor := p.is_on_floor()
	var landed: bool = on_floor and not d.was_floor
	d.was_floor = on_floor
	var st := p.moves.state
	match d.phase:
		0:   # 助走
			if p.position.x > 12.0:
				d.phase = 1
			return PlayerInput.make(1, true, false, false)
		1:   # 3段ジャンプ: 着地した瞬間にまた跳ぶ
			if d.jumps == 0 or landed:
				if d.jumps >= 3:
					d.phase = 2
					return PlayerInput.make(1, true, false, false)
				d.jumps += 1
				return PlayerInput.make(1, true, true, true)
			return PlayerInput.make(1, true, false, p.velocity.y > 0.0)
		2:   # 壁の手前でジャンプし、壁に押し付ける
			if on_floor and p.position.x > 60.0:
				d.phase = 3
				return PlayerInput.make(1, true, true, true)
			return PlayerInput.make(1, true, false, false)
		3:   # 壁すべりを少し見せてから壁キック
			if st == PlayerMoves.State.WALL_SLIDE:
				d.t = 0
				d.phase = 4
			return PlayerInput.make(1, true, false, true)
		4:
			if d.t > 25:
				d.phase = 5
				d.t = 0
				return PlayerInput.make(1, true, true, true)
			return PlayerInput.make(1, true, false, false)
		5:   # 壁キックで飛んだあと、空中でヒップドロップ
			if d.t == 28:
				return PlayerInput.make(0, false, false, false, true, true)
			if d.t > 28:
				if on_floor and d.t > 60:
					d.phase = 6
				return PlayerInput.make(0, false, false, false, true, false)
			return PlayerInput.make(-1, true, false, true)
	return PlayerInput.make(0, false, false, false)


## --touch-demo: 画面へのタッチを自動で再現する(左スティックを右へ大きく倒してダッシュ、右側を押してジャンプ)
func _touch_demo() -> void:
	var f := Engine.get_process_frames()
	var vs := get_viewport().get_visible_rect().size
	var base := Vector2(vs.x * 0.16, vs.y * 0.8)
	if f == 20:
		_touch(0, base, true)
	if f > 20 and f < 400:
		var drag := InputEventScreenDrag.new()
		drag.index = 0
		drag.position = base + Vector2(minf((f - 20) * 6.0, 90.0), 0)
		Input.parse_input_event(drag)
	if f % 70 == 50:
		_touch(1, Vector2(vs.x * 0.82, vs.y * 0.75), true)
	if f % 70 == 68:
		_touch(1, Vector2(vs.x * 0.82, vs.y * 0.75), false)
	if f == 60 and _args.has("open-settings"):
		for c in get_children():
			if c is SettingsPanel:
				(c as SettingsPanel)._toggle()


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var t := InputEventScreenTouch.new()
	t.index = index
	t.position = pos
	t.pressed = pressed
	Input.parse_input_event(t)


func _capture() -> void:
	if _args.has("touch-demo"):
		_touch_demo()
	if not _args.has("capture"):
		return
	_frame += 1
	var every := int(_args.get("every", "1"))
	if _frame > 5 and _frame % every == 0:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/game_%04d.png" % [_args["capture"], _shot])
		_shot += 1
		if _shot >= int(_args.get("frames", "90")):
			get_tree().quit()


func _log(msg: String) -> void:
	if _args.has("sim") or _args.has("verbose"):
		print("[%6.1fs] %s" % [_time, msg])


func _sim_check(dt: float) -> void:
	for i in 2:
		var p := sim.players[i]
		if p.dead or sim.wait > 0:
			_sim_still[i] = 0.0
			continue
		if p.position.distance_to(_sim_last[i]) > 1.0:
			_sim_last[i] = p.position
			_sim_still[i] = 0.0
		else:
			_sim_still[i] += dt
			if _sim_still[i] >= SIM_STUCK:
				_sim_stuck += 1
				print("STUCK: %dP at (%.1f, %.1f) t=%.1fs" % [i + 1, p.x, p.y, _time])
				_sim_still[i] = 0.0
	if _time >= SIM_LIMIT:
		print("TIMEOUT: match did not finish in %.0fs" % SIM_LIMIT)
		_sim_stuck += 1
		_sim_finish()


func _sim_finish(winner := -1) -> void:
	print("SIM RESULT: winner=%dP rounds=%d time=%.1fs stuck=%d checksum=%d" % [
		winner + 1, _sim_rounds, _time, _sim_stuck, sim.checksum()])
	var bad := _sim_stuck > 0 or winner < 0
	if _session != null:
		print("NET RESULT: frame=%d rollbacks=%d (%d frames) stalls=%d waits=%d rtt=%.1fms checks=%d desync=%d" % [
			sim.frame, _session.rollbacks, _session.rollback_frames, _session.stalls, _session.waits,
			_session.rtt * 1000.0 / 60.0, _session.checks_compared, _session.desync_frame])
		bad = bad or _session.desync_frame >= 0
	get_tree().quit(1 if bad else 0)


func _setup_input() -> void:
	var keys := {
		"move_left": [KEY_LEFT, KEY_A],
		"move_right": [KEY_RIGHT, KEY_D],
		"move_down": [KEY_DOWN, KEY_S],
		"jump": [KEY_SPACE, KEY_Z, KEY_UP],
		"run": [KEY_SHIFT, KEY_X],
	}
	# ゲームコントローラー: 十字キー・左スティック / 下と右のボタン=ジャンプ、左と上のボタン=ダッシュ(DSのB/A・Y/Xと同じ位置)
	var pad_buttons := {
		"move_left": [JOY_BUTTON_DPAD_LEFT],
		"move_right": [JOY_BUTTON_DPAD_RIGHT],
		"move_down": [JOY_BUTTON_DPAD_DOWN],
		"jump": [JOY_BUTTON_A, JOY_BUTTON_B],
		"run": [JOY_BUTTON_X, JOY_BUTTON_Y],
	}
	var pad_axes := {"move_left": [JOY_AXIS_LEFT_X, -1.0], "move_right": [JOY_AXIS_LEFT_X, 1.0], "move_down": [JOY_AXIS_LEFT_Y, 1.0]}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.4)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
		for b in pad_buttons.get(action, []):
			var jb := InputEventJoypadButton.new()
			jb.button_index = b
			InputMap.action_add_event(action, jb)
		if pad_axes.has(action):
			var ja := InputEventJoypadMotion.new()
			ja.axis = pad_axes[action][0]
			ja.axis_value = pad_axes[action][1]
			InputMap.action_add_event(action, ja)


func _setup_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -25, 0)
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.78, 0.98)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.75, 0.8)
	add_child(env)
