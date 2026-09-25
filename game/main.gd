extends Node3D
## 対戦の本体。ステージ・2人・ルール・画面表示をまとめ、キャラ同士や拾い物の当たりを判定する。
## 判定の結果(スターの増減・残機・勝敗)は MatchRules に任せる。
##
## 開発用の起動オプション(godot ... -- の後に付ける):
##   --cpu-both        1Pも CPU にする(自動で試合が進む)
##   --capture=DIR     画面をPNG保存(--every=N フレームごと、--frames=N 枚で終了)
##   --sim             画面なしで試合を最後まで回し、結果を表示して終了(詰まりがあれば終了コード1)
##   --seed=N          乱数の種(再現用)

const VIEW_TILES_Y_ORIGINAL := 12.0   ## 原作の画面は縦12マス【動画】
const GROUND_MARGIN := 1.5      ## 足場を画面下から何マス上に見せるか(原作の構図に近づける)
const CAM_TAU_X := 0.08         ## 横の追従の速さ(秒。小さいほど速い)
const CAM_TAU_Y := 0.18         ## 縦の追従の速さ
const CAM_TAU_FALL := 0.05      ## 落下中・画面端に近いときの縦の追従
const CAM_BAND_LO := 1.0        ## 足元が画面下からこのマス数より下に来たら追う
const CAM_BAND_HI := 2.0        ## 頭が画面上からこのマス数より上に来たら追う
const FOV := 30.0
const ROUND_END_WAIT := 3.0
const MATCH_END_WAIT := 5.0
const SIM_LIMIT := 900.0        ## --sim の上限(秒)
const SIM_STUCK := 30.0         ## --sim: この秒数同じ場所なら詰まり

var rules: MatchRules
var stage: Grassland
var players: Array[Player] = []
var brains: Array = [null, null]
var camera: Camera3D
var hud: Hud

var _big_star: Node3D
var _cam_x := 0.0
var _cam_y := 0.0
var _look := 0.0
var _cam_ready := false
var _drops := {}                ## drop_id -> DroppedStar
var _items: Array[Node3D] = []
var _wait := 0.0
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
	process_physics_priority = 10   # 2人が動いた後に判定する
	_setup_input()
	_setup_environment()

	rules = MatchRules.new(_rng.randi())
	stage = Grassland.new()
	if _args.has("practice"):
		stage.map = Grassland.PRACTICE
	add_child(stage)
	rules.star_point_count = stage.star_points.size()

	for i in 2:
		var p := Player.new()
		p.index = i
		p.stage = stage
		add_child(p)
		p.fell.connect(_on_fell.bind(i))
		p.bumped_block.connect(_on_bumped_block.bind(i))
		p.respawned.connect(func() -> void: rules.spawn_protect(i))
		players.append(p)
	if _args.has("demo-moves"):
		players[0].input_source = _demo_moves_input
	if _args.has("soak"):
		for i in 2:
			var src := _RandomInput.new(_rng.randi())
			_soak_inputs.append(src)   # Callable だけでは参照が保たれないので持っておく
			players[i].input_source = src.next
	for i in 2:
		if _args.has("demo-moves") and i == 0:
			continue
		if i == 1 or _args.has("cpu-both") or _args.has("sim"):
			brains[i] = CpuBrain.new(players[i], players[1 - i], self, _rng.randi())
			var b: CpuBrain = brains[i]
			players[i].input_source = func() -> PlayerInput: return b.think(get_physics_process_delta_time())

	_big_star = Assets.spawn(Assets.STAR, 1.2)
	_big_star.visible = false
	add_child(_big_star)

	camera = Camera3D.new()
	camera.fov = FOV
	add_child(camera)
	camera.current = true
	hud = Hud.new()
	add_child(hud)
	if not _args.has("cpu-both") and not _args.has("sim"):
		if ControlSettings.control_mode == "buttons":
			add_child(TouchControls.new())
		else:
			add_child(StickControls.new())
		var panel := SettingsPanel.new()
		panel.report_source = _report
		add_child(panel)
	# 撮影・タッチ再現は一時停止中(設定パネルを開いている間)も動かす
	var cap := _Capturer.new()
	cap.game = self
	cap.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(cap)
	_start_round()


class _Capturer extends Node:
	var game: Node

	func _process(_dt: float) -> void:
		game._capture()


func _start_round() -> void:
	if rules.match_winner >= 0 or rules.round_winner < 0:
		rules.reset_match()   # 最初の試合、または試合終了後
	else:
		rules.next_round()
	stage.reset()
	for i in 2:
		var p := players[i]
		p.position = stage.spawns[i]
		p.velocity = Vector3.ZERO
		p.set_big(false)
		p.dead = false
		p.visible = true
		rules.spawn_protect(i)
	for id in _drops:
		(_drops[id] as Node).queue_free()
	_drops.clear()
	for it in _items:
		if is_instance_valid(it):
			it.queue_free()
	_items.clear()
	_big_star.visible = false
	_cam_ready = false   # ラウンド開始時はカメラを追いかけさせず、その場に切り替える
	hud.show_banner("")
	_wait = 0.0


func _physics_process(dt: float) -> void:
	_time += dt
	if _wait > 0.0:
		_wait -= dt
		if _wait <= 0.0:
			if rules.match_winner >= 0:
				if _args.has("sim"):
					_sim_finish()
					return
			_start_round()
		return

	if rules.advance(dt):
		_big_star.position = stage.star_points[rules.star_point]
		_big_star.visible = true
		_log("STAR SPAWN point %d at (%.1f, %.1f)" % [rules.star_point + 1, _big_star.position.x, _big_star.position.y])
	_spawn_new_drops()
	for i in 2:
		players[i].invuln = rules.invuln[i]

	for i in 2:
		var p := players[i]
		if p.dead:
			continue
		_touch_big_star(i)
		_touch_drops(i)
		_touch_coins(i)
		_touch_items(i)
		_touch_enemies(i)
	_touch_players()
	_update_drops()

	if rules.round_winner >= 0 and _wait <= 0.0:
		_end_round()
	if _args.has("sim"):
		_sim_check(dt)
	if _args.has("soak"):
		_soak_check()


func _process(dt: float) -> void:
	_update_camera(dt)
	_wrap_all()
	_big_star.rotate_y(dt * 2.0)
	var star_x := stage.wrap_x(_big_star.position.x) if _big_star.visible else -1.0
	hud.update(rules, [players[0].position.x, players[1].position.x], star_x, stage.width)


## カメラ。横は途切れずに進み続け(ループの継ぎ目でも飛ばない)、縦は「帯」の中にいる間は動かさない。
## なめらかさは時間基準(フレームの速さに左右されない)。
func _update_camera(dt: float) -> void:
	var view := ControlSettings.view_tiles
	var dist := (view * 0.5) / tan(deg_to_rad(FOV * 0.5))
	var p := players[0]
	if not _cam_ready:
		_cam_x = p.position.x
		_cam_y = p.position.y + view * 0.5 - GROUND_MARGIN
		_cam_ready = true

	# 横: 先読み(進行方向を少し先まで見せる。速いほど先まで)
	var speed := clampf(absf(p.velocity.x) / Tuning.RUN_SPEED, 0.0, 1.0)
	_look = move_toward(_look, p.moves.facing * (1.0 + 1.5 * speed), dt * 6.0)
	var target_x := _cam_x + stage.delta_x(_cam_x, p.position.x) + _look
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
	target_y = clampf(target_y, view * 0.5 - GROUND_MARGIN, stage.height - view * 0.5 + 1.0)
	_cam_y = lerpf(_cam_y, target_y, 1.0 - exp(-dt / tau))
	camera.position = Vector3(_cam_x, _cam_y, dist)


## 左右ループの見た目: 全員をカメラに一番近い周回位置に表示する
func _wrap_all() -> void:
	stage.wrap_visuals(_cam_x)
	for p in players:
		p.set_view_shift(stage.image_x(p.position.x, _cam_x) - p.position.x)
	for id in _drops:
		var d: Pickups.DroppedStar = _drops[id]
		d.set_view_shift(stage.image_x(d.position.x, _cam_x) - d.position.x)
	for it in _items:
		if is_instance_valid(it):
			(it as Pickups.GrowItem).set_view_shift(stage.image_x(it.position.x, _cam_x) - it.position.x)
	if _big_star.visible:
		_big_star.position.x = stage.image_x(_big_star.position.x, _cam_x)


# ---- 当たり判定 ---------------------------------------------------------

## 2つの箱(足元中心・幅・高さ)が重なっているか。左右ループを考慮
func _overlap(a_pos: Vector3, a_w: float, a_h: float, b_pos: Vector3, b_w: float, b_h: float) -> bool:
	var dx := absf(stage.delta_x(a_pos.x, b_pos.x))
	if dx > (a_w + b_w) * 0.5:
		return false
	return a_pos.y < b_pos.y + b_h and b_pos.y < a_pos.y + a_h


func _touch_big_star(i: int) -> void:
	var p := players[i]
	if not _big_star.visible:
		return
	if _overlap(p.position, Player.WIDTH, p.height(), _big_star.position, 1.0, 1.2):
		rules.collect_star(i)
		_log("STAR %dP (1P %d, 2P %d)" % [i + 1, rules.stars[0], rules.stars[1]])
		_big_star.visible = false
		stage.reset()   # §4 スターを取るとステージが元に戻る


func _touch_drops(i: int) -> void:
	var p := players[i]
	for id in _drops.keys():
		var d: Node3D = _drops[id]
		if _overlap(p.position, Player.WIDTH, p.height(), d.position, 0.8, 0.8):
			if rules.pickup_drop(id, i):
				d.queue_free()
				_drops.erase(id)


func _touch_coins(i: int) -> void:
	var p := players[i]
	for c in stage.coins.duplicate():
		if _overlap(p.position, Player.WIDTH, p.height(), c.position, 0.7, 0.7):
			stage.coins.erase(c)
			c.queue_free()
			_gain_coin(i)


func _gain_coin(i: int) -> void:
	if rules.add_coin(i):
		var p := players[i]
		var item := Pickups.GrowItem.new(stage, Vector3(p.position.x, p.position.y + 6.0, 0))
		add_child(item)
		_items.append(item)


func _touch_items(i: int) -> void:
	var p := players[i]
	var alive: Array[Node3D] = []
	for it in _items:
		if is_instance_valid(it):
			alive.append(it)
	_items = alive
	for it in _items.duplicate():
		if _overlap(p.position, Player.WIDTH, p.height(), it.position, 0.8, 0.8):
			_items.erase(it)
			it.queue_free()
			p.set_big(true)


func _touch_enemies(i: int) -> void:
	var p := players[i]
	for e in stage.enemies:
		if not e.is_alive():
			continue
		if not _overlap(p.position, Player.WIDTH, p.height(), e.position, 0.8, Walker.SIZE):
			continue
		if p.velocity.y < 0.0 and p.bottom() > e.position.y + Walker.SIZE * 0.4:
			e.squash()
			p.bounce()
		else:
			_damage(i)


func _touch_players() -> void:
	var a := players[0]
	var b := players[1]
	if a.dead or b.dead:
		return
	if not _overlap(a.position, Player.WIDTH, a.height(), b.position, Player.WIDTH, b.height()):
		return
	for pair in [[0, 1], [1, 0]]:
		var top: Player = players[pair[0]]
		var under: Player = players[pair[1]]
		if top.velocity.y <= 0.0 and top.bottom() > under.position.y + under.height() * 0.5:
			if top.ground_pounding:
				rules.ground_pound(pair[0], pair[1])
			else:
				rules.stomp(pair[0], pair[1])
			top.bounce()
			return
	# 横からぶつかった §5
	if rules.bump():
		var dir := signf(stage.delta_x(b.position.x, a.position.x))
		a.knockback(dir if dir != 0.0 else -1.0)
		b.knockback(-dir if dir != 0.0 else 1.0)


## 敵などのダメージ §2 §5: 大きければ小さくなって1個、小さければミス
func _damage(i: int) -> void:
	if rules.invuln[i] > 0.0:
		return
	var p := players[i]
	if p.big:
		rules.hit(i, 1)
		p.shrink()
	else:
		_miss(i)


func _on_fell(i: int) -> void:
	_miss(i)


func _miss(i: int) -> void:
	var p := players[i]
	if p.dead:
		return
	var at := p.position
	var why := ""
	if brains[i] != null:
		var b: CpuBrain = brains[i]
		why = " target=(%.1f, %.1f)" % [b.target.x, b.target.y]
	_log("MISS %dP at (%.1f, %.1f)%s" % [i + 1, at.x, at.y, why])
	rules.miss(i)
	p.die()
	_spawn_new_drops(at)


func _on_bumped_block(x: int, y: int, i: int) -> void:
	if stage.bump_block(x, y):
		_gain_coin(i)


# ---- 落としたスター -----------------------------------------------------

func _spawn_new_drops(at := Vector3.INF) -> void:
	for d in rules.new_drops:
		var from: Vector3 = players[d.owner].position if at == Vector3.INF else at
		from.y = maxf(from.y, 1.0)
		var node := Pickups.DroppedStar.new(d.id, stage, from, _rng)
		add_child(node)
		_drops[d.id] = node
	rules.new_drops.clear()


func _update_drops() -> void:
	for id in _drops.keys():
		if not rules.drop_exists(id):
			(_drops[id] as Node).queue_free()
			_drops.erase(id)
		else:
			(_drops[id] as Pickups.DroppedStar).show_age(rules.drop_age(id))


# ---- ラウンドの進行 -----------------------------------------------------

func _end_round() -> void:
	var w := rules.round_winner
	_sim_rounds += 1
	if rules.match_winner >= 0:
		hud.show_banner("%dP WINS THE MATCH!\n1P %d - %d 2P" % [w + 1, rules.wins[0], rules.wins[1]])
		_wait = MATCH_END_WAIT
	else:
		hud.show_banner("%dP WIN!\n1P %d - %d 2P" % [w + 1, rules.wins[0], rules.wins[1]])
		_wait = ROUND_END_WAIT
	print("ROUND %d: %dP wins (1P %d - %d 2P) t=%.1fs" % [_sim_rounds, w + 1, rules.wins[0], rules.wins[1], _time])


## CPUの目標(CpuBrain から呼ばれる)
func cpu_target(i: int) -> Vector3:
	var me := players[i]
	var opp := players[1 - i]
	if _big_star.visible:
		return _big_star.position
	var best := Vector3.INF
	var best_d := INF
	for id in _drops:
		var pos: Vector3 = (_drops[id] as Node3D).position
		if rules.can_pickup_drop(id, i) and stage.has_floor_below(pos, 12):
			var d := absf(stage.delta_x(me.position.x, pos.x)) + absf(pos.y - me.position.y)
			if d < best_d:
				best_d = d
				best = pos
	if best != Vector3.INF:
		return best
	if rules.stars[1 - i] > 0 and not opp.dead:
		return opp.position
	for it in _items:
		if is_instance_valid(it) and not me.big:
			return it.position
	for c in stage.coins:
		if not stage.has_floor_below(c.position):
			continue   # 穴の上のコインはCPUは狙わない
		var d := absf(stage.delta_x(me.position.x, c.position.x)) + absf(c.position.y - me.position.y) * 2.0
		if d < best_d:
			best_d = d
			best = c.position
	if best != Vector3.INF:
		return best
	return opp.position


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
		var p := players[i]
		var bad := ""
		if not (is_finite(p.position.x) and is_finite(p.position.y) and is_finite(p.velocity.x) and is_finite(p.velocity.y)):
			bad = "位置か速度が数値として壊れた"
		elif p.position.x < 0.0 or p.position.x >= stage.width or p.position.y > stage.height + 8.0:
			bad = "ステージの外"
		elif not p.dead and not p.visible:
			bad = "生きているのに見えない"
		elif not p.dead and rules.invuln[i] <= 0.0 and not p._model.visible:
			bad = "無敵でないのにモデルが非表示"
		elif i == 0 and not p.dead and _time > 1.0 and _wait <= 0.0:
			var feet_on_screen := p.position.y - (_cam_y - view * 0.5)
			if p.position.y > -1.0 and (feet_on_screen < -0.5 or feet_on_screen > view + 0.5):
				bad = "カメラの画面外 (足元が画面下から%.1fマス)" % feet_on_screen
		if bad != "":
			_soak_errors += 1
			if _soak_errors <= 20:
				print("SOAK NG t=%.2f %dP %s pos=(%.2f, %.2f) vel=(%.2f, %.2f) state=%d" % [
					_time, i + 1, bad, p.position.x, p.position.y, p.velocity.x, p.velocity.y, p.moves.state])
		if absf(p.position.x - _soak_prev_x[i]) > stage.width * 0.5:
			_soak_wraps += 1
			if i == 0 and _args.has("verbose"):
				print("WRAP 1P frame=%d" % Engine.get_process_frames())
		_soak_prev_x[i] = p.position.x
	if _time >= float(_args.get("soak", "60")):
		print("SOAK RESULT: %.0fs %d frames, wraps=%d, errors=%d" % [_time, _soak_frames, _soak_wraps, _soak_errors])
		get_tree().quit(1 if _soak_errors > 0 else 0)


## 不具合報告の中身(設定パネルの「不具合報告をコピー」)
func _report() -> String:
	var lines := []
	lines.append("renderer=%s gpu=%s / %s os=%s model=%s" % [
		RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name(),
		RenderingServer.get_video_adapter_vendor(), OS.get_name(), OS.get_model_name()])
	lines.append("fps=%d time=%.1f cam=(%.2f, %.2f)" % [Engine.get_frames_per_second(), _time, _cam_x, _cam_y])
	for i in 2:
		var p := players[i]
		lines.append("P%d pos=(%.2f, %.2f) vel=(%.2f, %.2f) state=%d big=%s dead=%s visible=%s floor=%s stars=%d lives=%d" % [
			i + 1, p.position.x, p.position.y, p.velocity.x, p.velocity.y, p.moves.state, str(p.big), str(p.dead),
			str(p.visible), str(p.is_on_floor()), rules.stars[i], rules.lives[i]])
	for e in stage.enemies:
		lines.append("enemy pos=(%.2f, %.2f) alive=%s" % [e.position.x, e.position.y, str(e.is_alive())])
	return "\n".join(lines)


var _demo := {"phase": 0, "jumps": 0, "was_floor": true, "t": 0}

## --demo-moves: 右へダッシュ → 3段ジャンプ → 壁すべり → 壁キック → ヒップドロップ を自動で行う
func _demo_moves_input() -> PlayerInput:
	var p := players[0]
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
		var p := players[i]
		if p.dead or _wait > 0.0:
			_sim_still[i] = 0.0
			continue
		if p.position.distance_to(_sim_last[i]) > 1.0:
			_sim_last[i] = p.position
			_sim_still[i] = 0.0
		else:
			_sim_still[i] += dt
			if _sim_still[i] >= SIM_STUCK:
				_sim_stuck += 1
				print("STUCK: %dP at (%.1f, %.1f) t=%.1fs" % [i + 1, p.position.x, p.position.y, _time])
				_sim_still[i] = 0.0
	if _time >= SIM_LIMIT:
		print("TIMEOUT: match did not finish in %.0fs" % SIM_LIMIT)
		_sim_stuck += 1
		_sim_finish()


func _sim_finish() -> void:
	print("SIM RESULT: winner=%dP rounds=%d time=%.1fs stuck=%d" % [rules.match_winner + 1, _sim_rounds, _time, _sim_stuck])
	get_tree().quit(1 if _sim_stuck > 0 or rules.match_winner < 0 else 0)


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
