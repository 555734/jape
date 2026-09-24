extends Node3D
## 対戦の本体。ステージ・2人・ルール・画面表示をまとめ、キャラ同士や拾い物の当たりを判定する。
## 判定の結果(スターの増減・残機・勝敗)は MatchRules に任せる。
##
## 開発用の起動オプション(godot ... -- の後に付ける):
##   --cpu-both        1Pも CPU にする(自動で試合が進む)
##   --capture=DIR     画面をPNG保存(--every=N フレームごと、--frames=N 枚で終了)
##   --sim             画面なしで試合を最後まで回し、結果を表示して終了(詰まりがあれば終了コード1)
##   --seed=N          乱数の種(再現用)

const VIEW_TILES_Y := 12.0
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
	for i in 2:
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
		add_child(TouchControls.new())
	_start_round()


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


func _process(_dt: float) -> void:
	var dist := (VIEW_TILES_Y * 0.5) / tan(deg_to_rad(FOV * 0.5))
	var p := players[0]
	var cy := clampf(p.position.y + 2.5, 6.0, 8.0)
	var cx := p.position.x
	if absf(cx - camera.position.x) > stage.width * 0.5:
		camera.position.x = cx   # ループで反対側へ移ったら一緒に飛ぶ
	camera.position = Vector3(lerpf(camera.position.x, cx, 0.25), cy, dist)
	_big_star.rotate_y(_dt * 2.0)
	var star_x := _big_star.position.x if _big_star.visible else -1.0
	hud.update(rules, [players[0].position.x, players[1].position.x], star_x, stage.width)
	_capture()


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

func _capture() -> void:
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
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)


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
