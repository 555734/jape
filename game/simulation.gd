class_name Simulation
extends RefCounted
## 対戦の中身(ルール・2人・敵・拾い物・ラウンドの進行)を1フレームずつ進める。画面には依存しない。
## 画面(main.gd と各ビュー)は、ここの状態を毎フレーム読んで表示するだけ。
##
## 同じ種と同じ入力なら、どの端末でも完全に同じ結果になるように作る(通信対戦のロールバックの前提):
##   - 状態は実数・整数・bool で持つ。計算は GDScript の四則演算で行い、Vector の演算・lerp・三角関数は使わない
##   - 時間は一定の DT で進める。当たり判定は StageMap.move_box(Godot の物理は使わない)
##   - 乱数はここの rng と MatchRules の rng だけ。どちらも save_state() に含める

const DT := 1.0 / 60.0
const ROUND_END_WAIT := 180     ## ラウンド終了後の待ち(フレーム)
const MATCH_END_WAIT := 300     ## 試合終了後の待ち(フレーム)


## 操作キャラ。判定は横と縦の2次元だけ
class SimPlayer:
	const BIG_HEIGHT := 1.8     ## docs/RULES.md §2
	const SMALL_HEIGHT := 0.9
	const WIDTH := 0.8
	const RESPAWN_FRAMES := 90  ## ミスしてから土管から出てくるまで(1.5秒)【決定・調整】

	var index := 0
	var stage: StageMap
	var x := 0.0                ## 足元の中心
	var y := 0.0
	var vx := 0.0
	var vy := 0.0
	var moves := PlayerMoves.new()
	var big := false
	var dead := false
	var respawn_left := 0
	var knock := 0.0
	var on_floor := false
	var wall_hit := 0           ## 直前の移動で当たった壁(1=右 -1=左 0=なし)
	var last_input := PlayerInput.new()
	## このフレームの出来事(Simulation が読む)
	var fell := false
	var bumped := false
	var bump_x := 0
	var bump_y := 0

	var position: Vector3:
		get:
			return Vector3(x, y, 0)
	var velocity: Vector3:
		get:
			return Vector3(vx, vy, 0)
	var ground_pounding: bool:
		get:
			return moves.is_ground_pounding()

	func height() -> float:
		if big and moves.state == PlayerMoves.State.CROUCH:
			return Tuning.CROUCH_HEIGHT
		return BIG_HEIGHT if big else SMALL_HEIGHT

	func bottom() -> float:
		return y

	func top() -> float:
		return y + height()

	func is_on_floor() -> bool:
		return on_floor

	func is_on_wall() -> bool:
		return wall_hit != 0

	func set_big(value: bool) -> void:
		big = value
		moves.big = value

	func place(pos: Vector3) -> void:
		x = pos.x
		y = pos.y
		vx = 0.0
		vy = 0.0
		on_floor = false
		wall_hit = 0

	func step(input: PlayerInput) -> void:
		fell = false
		bumped = false
		last_input = input
		var wall := 0
		if wall_hit != 0 and not on_floor:
			wall = wall_hit
		moves.vel = Vector2(vx, vy)
		var v := moves.step(on_floor, wall, input, DT)
		vx = v.x
		vy = v.y
		if knock != 0.0:
			vx = knock
			moves.vel.x = knock
			knock = move_toward(knock, 0.0, 30.0 * DT)
		var was_rising := vy > 0.0
		var r := stage.move_box(x, y, WIDTH, height(), vx * DT, vy * DT)
		x = stage.wrap_x(r[0])
		y = r[1]
		wall_hit = r[2]
		on_floor = r[3] == -1
		if r[2] != 0:
			vx = 0.0
		if r[3] != 0:
			vy = 0.0
		if was_rising and r[3] == 1:
			bumped = true
			bump_x = floori(x)
			bump_y = floori(top() + 0.1)
		if y < -3.0:
			fell = true

	## 相手や敵を踏んだとき跳ね返る。ジャンプを押していれば高く
	func bounce() -> void:
		moves.vel = Vector2(vx, vy)
		moves.stomp_bounce(last_input.jump_held)
		vy = moves.vel.y
		on_floor = false

	## 横から弾かれる
	func knockback(dir: float) -> void:
		knock = dir * 7.0

	## ミス: 消えて、少し後に自分の土管から小さい状態で出てくる
	func die() -> void:
		dead = true
		vx = 0.0
		vy = 0.0
		moves.reset()
		respawn_left = RESPAWN_FRAMES

	func respawn() -> void:
		dead = false
		moves.reset()
		set_big(false)
		place(stage.pipe_tops[index])
		vy = 6.0
		knock = 0.0

	func snapshot() -> Array:
		return [x, y, vx, vy, moves.snapshot(), big, dead, respawn_left, knock, on_floor, wall_hit,
			last_input.to_bits()]

	func restore(a: Array) -> void:
		x = a[0]
		y = a[1]
		vx = a[2]
		vy = a[3]
		moves.restore(a[4])
		big = a[5]
		dead = a[6]
		respawn_left = a[7]
		knock = a[8]
		on_floor = a[9]
		wall_hit = a[10]
		last_input = PlayerInput.from_bits(a[11])
		fell = false
		bumped = false


## 歩くだけの敵。壁か足場の端で向きを変える。踏まれると倒れる
class SimWalker:
	const SPEED := 1.1          ## マス/秒【決定・調整】(v2で1.5から遅く)
	const SIZE := 0.9
	const WIDTH := 0.8
	const SQUASH_FRAMES := 24   ## 踏まれてから消えるまで(0.4秒)

	var stage: StageMap
	var x := 0.0
	var y := 0.0
	var vy := 0.0
	var dir := -1.0
	var dead := false
	var dead_left := 0          ## 踏まれて倒れている表示の残り(フレーム)
	var on_floor := false
	var on_wall := false

	var position: Vector3:
		get:
			return Vector3(x, y, 0)

	func reset(pos: Vector3) -> void:
		x = pos.x
		y = pos.y
		vy = 0.0
		dir = -1.0
		dead = false
		dead_left = 0
		on_floor = false
		on_wall = false

	func is_alive() -> bool:
		return not dead

	## 画面に出すか(倒れてからしばらくは見せる)
	func is_shown() -> bool:
		return not dead or dead_left > 0

	func step() -> void:
		if dead:
			dead_left = maxi(0, dead_left - 1)
			return
		vy = maxf(vy - Tuning.GRAVITY_DOWN * DT, -Tuning.MAX_FALL)
		if on_floor:
			vy = 0.0
		var r := stage.move_box(x, y, WIDTH, SIZE, dir * SPEED * DT, vy * DT)
		x = stage.wrap_x(r[0])
		y = r[1]
		on_wall = r[2] != 0
		on_floor = r[3] == -1
		if r[3] != 0:
			vy = 0.0
		var ahead_x := floori(x + dir * 0.55)
		var foot_y := floori(y + 0.05)
		if on_wall or (on_floor and not stage.is_solid(ahead_x, foot_y - 1)):
			dir = -dir
		if y < -8.0:
			dead = true
			dead_left = 0

	func squash() -> void:
		dead = true
		dead_left = SQUASH_FRAMES

	func snapshot() -> Array:
		return [x, y, vy, dir, dead, dead_left, on_floor, on_wall]

	func restore(a: Array) -> void:
		x = a[0]
		y = a[1]
		vy = a[2]
		dir = a[3]
		dead = a[4]
		dead_left = a[5]
		on_floor = a[6]
		on_wall = a[7]


## 落ちたスター(弾んで飛び散る)と成長アイテム(浮いてから落ちる)。どちらも重力で落ちて地形に乗る
class SimPickup:
	const DROP_SIZE := 0.6
	const ITEM_SIZE := 0.7
	const ITEM_HOVER := 60      ## 成長アイテムが浮いている時間(1秒)§6

	var id := 0
	var is_item := false
	var stage: StageMap
	var x := 0.0
	var y := 0.0
	var vx := 0.0
	var vy := 0.0
	var hover := 0
	var on_floor := false

	var position: Vector3:
		get:
			return Vector3(x, y, 0)

	func step() -> void:
		if hover > 0:
			hover -= 1
			return
		if is_item:
			vy = maxf(vy - 30.0 * DT, -10.0)
		else:
			vy = maxf(vy - 30.0 * DT, -15.0)
			if on_floor:
				vx = move_toward(vx, 0.0, 12.0 * DT)
		var s := ITEM_SIZE if is_item else DROP_SIZE
		var r := stage.move_box(x, y, s, s, vx * DT, vy * DT)
		x = stage.wrap_x(r[0])
		y = r[1]
		on_floor = r[3] == -1
		if r[2] != 0:
			vx = 0.0
		if r[3] != 0:
			vy = 0.0

	func snapshot() -> Array:
		return [id, is_item, x, y, vx, vy, hover, on_floor]

	func restore(a: Array) -> void:
		id = a[0]
		is_item = a[1]
		x = a[2]
		y = a[3]
		vx = a[4]
		vy = a[5]
		hover = a[6]
		on_floor = a[7]


var stage: StageMap
var rules: MatchRules
var players: Array[SimPlayer] = []
var enemies: Array[SimWalker] = []
var coins_alive: Array[bool] = []
var used_blocks: Array[int] = []     ## 叩いた?ブロック(x + y * width)
var star_visible := false
var star_x := 0.0
var star_y := 0.0
var drops: Array[SimPickup] = []     ## 落ちたスター(id は MatchRules の drop id)
var items: Array[SimPickup] = []     ## 成長アイテム
var wait := 0                         ## ラウンド終了後の待ち(残りフレーム)
var frame := 0
## このフレームの出来事(画面・音・ログ用)。["move", 番号, 名前] ["star_spawn"] ["star", 番号] ["miss", 番号, x, y]
## ["coin", 番号] ["round_end", 勝者] ["round_start"] ["match_over", 勝者] ["stage_reset"]
var events: Array = []

var _rng := RandomNumberGenerator.new()
var _next_item_id := 1


func _init(seed_value: int, p_stage: StageMap = null) -> void:
	_rng.seed = seed_value
	stage = p_stage if p_stage != null else StageMap.new()
	rules = MatchRules.new(_rng.randi() | 1)
	rules.star_point_count = stage.star_points.size()
	for i in 2:
		var p := SimPlayer.new()
		p.index = i
		p.stage = stage
		players.append(p)
	for _i in stage.enemy_spots.size():
		var e := SimWalker.new()
		e.stage = stage
		enemies.append(e)
	coins_alive.resize(stage.coin_spots.size())
	start_round()


## 1フレーム進める。inputs[i] は i 番のプレイヤーの入力(PlayerInput.quantized() 済みのもの)
func step(inputs: Array) -> void:
	frame += 1
	events.clear()
	if wait > 0:
		wait -= 1
		if wait == 0:
			if rules.match_winner >= 0:
				events.append(["match_over", rules.match_winner])
			start_round()
		return

	for e in enemies:
		e.step()
	for i in 2:
		_step_player(i, inputs[i])
	for d in drops:
		d.step()
	for it in items.duplicate():
		it.step()
		if it.y < -3.0:
			items.erase(it)

	if rules.advance(DT):
		var sp := stage.star_points[rules.star_point]
		star_x = sp.x
		star_y = sp.y
		star_visible = true
		events.append(["star_spawn", rules.star_point])
	_spawn_new_drops()
	for i in 2:
		if players[i].dead:
			continue
		_touch_big_star(i)
		_touch_drops(i)
		_touch_coins(i)
		_touch_items(i)
		_touch_enemies(i)
	_touch_players()
	drops = drops.filter(func(d: SimPickup) -> bool: return rules.drop_exists(d.id))

	if rules.round_winner >= 0 and wait == 0:
		_end_round()


func start_round() -> void:
	if rules.match_winner >= 0 or rules.round_winner < 0:
		rules.reset_match()   # 最初の試合、または試合終了後
	else:
		rules.next_round()
	_reset_stage()
	for i in 2:
		var p := players[i]
		p.place(stage.spawns[i])
		p.moves.reset()
		p.set_big(false)
		p.dead = false
		p.knock = 0.0
		rules.spawn_protect(i)
	drops.clear()
	items.clear()
	star_visible = false
	wait = 0
	events.append(["round_start"])


## ステージを元に戻す(スター取得時・ラウンド開始時: 敵・コイン・?ブロック)§4【FAQ】
func _reset_stage() -> void:
	for i in coins_alive.size():
		coins_alive[i] = true
	for i in enemies.size():
		enemies[i].reset(stage.enemy_spots[i])
	used_blocks.clear()
	events.append(["stage_reset"])


func _step_player(i: int, input: PlayerInput) -> void:
	var p := players[i]
	if p.dead:
		p.respawn_left -= 1
		if p.respawn_left <= 0:
			p.respawn()
			rules.spawn_protect(i)
			events.append(["respawn", i])
		return
	p.step(input)
	if p.bumped and _bump_block(p.bump_x, p.bump_y):
		_gain_coin(i)
	if p.fell:
		_miss(i)
	for e in p.moves.events:
		events.append(["move", i, e])


## ?ブロックを下から叩いた。コインが出たら true
func _bump_block(x: int, y: int) -> bool:
	var key := posmod(x, stage.width) + y * stage.width
	if stage.tile(x, y) != "?" or used_blocks.has(key):
		return false
	used_blocks.append(key)
	return true


func is_block_used(x: int, y: int) -> bool:
	return used_blocks.has(posmod(x, stage.width) + y * stage.width)


# ---- 当たり判定 ---------------------------------------------------------

## 2つの箱(足元中心・幅・高さ)が重なっているか。左右ループを考慮
func _overlap(ax: float, ay: float, aw: float, ah: float, bx: float, by: float, bw: float, bh: float) -> bool:
	var dx := absf(stage.delta_x(ax, bx))
	if dx > (aw + bw) * 0.5:
		return false
	return ay < by + bh and by < ay + ah


func _touch(p: SimPlayer, bx: float, by: float, bw: float, bh: float) -> bool:
	return _overlap(p.x, p.y, SimPlayer.WIDTH, p.height(), bx, by, bw, bh)


func _touch_big_star(i: int) -> void:
	var p := players[i]
	if star_visible and _touch(p, star_x, star_y, 1.0, 1.2):
		rules.collect_star(i)
		star_visible = false
		events.append(["star", i])
		_reset_stage()   # §4 スターを取るとステージが元に戻る


func _touch_drops(i: int) -> void:
	var p := players[i]
	for d in drops.duplicate():
		if _touch(p, d.x, d.y, 0.8, 0.8) and rules.pickup_drop(d.id, i):
			drops.erase(d)
			events.append(["pickup", i])


func _touch_coins(i: int) -> void:
	var p := players[i]
	for c in coins_alive.size():
		var pos := stage.coin_spots[c]
		if coins_alive[c] and _touch(p, pos.x, pos.y, 0.7, 0.7):
			coins_alive[c] = false
			_gain_coin(i)


func _gain_coin(i: int) -> void:
	events.append(["coin", i])
	if rules.add_coin(i):
		var p := players[i]
		var it := SimPickup.new()
		it.id = _next_item_id
		_next_item_id += 1
		it.is_item = true
		it.stage = stage
		it.x = p.x
		it.y = p.y + 6.0
		it.hover = SimPickup.ITEM_HOVER
		items.append(it)


func _touch_items(i: int) -> void:
	var p := players[i]
	for it in items.duplicate():
		if _touch(p, it.x, it.y, 0.8, 0.8):
			items.erase(it)
			p.set_big(true)
			events.append(["grow", i])


func _touch_enemies(i: int) -> void:
	var p := players[i]
	for e in enemies:
		if not e.is_alive() or not _touch(p, e.x, e.y, 0.8, SimWalker.SIZE):
			continue
		if p.vy < 0.0 and p.bottom() > e.y + SimWalker.SIZE * 0.4:
			e.squash()
			p.bounce()
			events.append(["move", i, "stomp"])
		else:
			_damage(i)


func _touch_players() -> void:
	var a := players[0]
	var b := players[1]
	if a.dead or b.dead:
		return
	if not _overlap(a.x, a.y, SimPlayer.WIDTH, a.height(), b.x, b.y, SimPlayer.WIDTH, b.height()):
		return
	for pair in [[0, 1], [1, 0]]:
		var top: SimPlayer = players[pair[0]]
		var under: SimPlayer = players[pair[1]]
		if top.vy <= 0.0 and top.bottom() > under.y + under.height() * 0.5:
			if top.ground_pounding:
				rules.ground_pound(pair[0], pair[1])
			else:
				rules.stomp(pair[0], pair[1])
			top.bounce()
			events.append(["move", pair[0], "stomp"])
			return
	# 横からぶつかった §5
	if rules.bump():
		var dir := signf(stage.delta_x(b.x, a.x))
		a.knockback(dir if dir != 0.0 else -1.0)
		b.knockback(-dir if dir != 0.0 else 1.0)
		events.append(["bump"])


## 敵などのダメージ §2 §5: 大きければ小さくなって1個、小さければミス
func _damage(i: int) -> void:
	if rules.invuln[i] > 0.0:
		return
	var p := players[i]
	if p.big:
		rules.hit(i, 1)
		p.set_big(false)
		events.append(["shrink", i])
	else:
		_miss(i)


func _miss(i: int) -> void:
	var p := players[i]
	if p.dead:
		return
	var at := p.position
	events.append(["miss", i, at.x, at.y])
	rules.miss(i)
	p.die()
	_spawn_new_drops(at)


## MatchRules が新しく落としたスターを、画面上の物として飛び散らせる
func _spawn_new_drops(at := Vector3.INF) -> void:
	for nd in rules.new_drops:
		var p := players[nd.owner]
		var fx: float = p.x if at == Vector3.INF else at.x
		var fy: float = p.y if at == Vector3.INF else at.y
		var d := SimPickup.new()
		d.id = nd.id
		d.stage = stage
		d.x = fx
		d.y = maxf(fy, 1.0) + 1.0
		# randf_range は内部の計算が端末で変わりうるので、randf() から四則演算で作る(順番も固定)
		d.vx = -5.0 + _rng.randf() * 10.0
		d.vy = 7.0 + _rng.randf() * 3.0
		drops.append(d)
	rules.new_drops.clear()


func _end_round() -> void:
	wait = MATCH_END_WAIT if rules.match_winner >= 0 else ROUND_END_WAIT
	events.append(["round_end", rules.round_winner])


# ---- CPU 用 -------------------------------------------------------------

## CPUの目標(CpuBrain から呼ばれる)
## 優先順位: ビッグスター > 落ちたスター > スターを持った相手 > アイテム > コイン > 相手
func cpu_target(i: int) -> Vector3:
	var me := players[i]
	var opp := players[1 - i]
	if star_visible:
		return Vector3(star_x, star_y, 0)
	var best := Vector3.INF
	var best_d := INF
	for d in drops:
		var pos := d.position
		if rules.can_pickup_drop(d.id, i) and stage.has_floor_below(pos, 12):
			var dist := absf(stage.delta_x(me.x, pos.x)) + absf(pos.y - me.y)
			if dist < best_d:
				best_d = dist
				best = pos
	if best != Vector3.INF:
		return best
	if rules.stars[1 - i] > 0 and not opp.dead:
		return opp.position
	if not me.big and not items.is_empty():
		return items[0].position
	for c in coins_alive.size():
		var pos := stage.coin_spots[c]
		if not coins_alive[c] or not stage.has_floor_below(pos):
			continue   # 穴の上のコインはCPUは狙わない
		var dist := absf(stage.delta_x(me.x, pos.x)) + absf(pos.y - me.y) * 2.0
		if dist < best_d:
			best_d = dist
			best = pos
	if best != Vector3.INF:
		return best
	return opp.position


# ---- 巻き戻し(ロールバック) ----------------------------------------------

## 状態をまるごと保存する。load_state() で戻すと、その後は同じ入力なら同じ結果になる
func save_state() -> PackedByteArray:
	var ps := []
	for p in players:
		ps.append(p.snapshot())
	var es := []
	for e in enemies:
		es.append(e.snapshot())
	var ds := []
	for d in drops:
		ds.append(d.snapshot())
	var its := []
	for it in items:
		its.append(it.snapshot())
	return var_to_bytes([frame, wait, _rng.state, _next_item_id, rules.snapshot(), ps, es,
		coins_alive.duplicate(), used_blocks.duplicate(), star_visible, star_x, star_y, ds, its])


func load_state(bytes: PackedByteArray) -> void:
	var a: Array = bytes_to_var(bytes)
	frame = a[0]
	wait = a[1]
	_rng.state = a[2]
	_next_item_id = a[3]
	rules.restore(a[4])
	for i in players.size():
		players[i].restore(a[5][i])
	for i in enemies.size():
		enemies[i].restore(a[6][i])
	coins_alive.assign(a[7])
	used_blocks.assign(a[8])
	star_visible = a[9]
	star_x = a[10]
	star_y = a[11]
	drops.clear()
	for s in a[12]:
		drops.append(_make_pickup(s))
	items.clear()
	for s in a[13]:
		items.append(_make_pickup(s))
	events.clear()


func _make_pickup(s: Array) -> SimPickup:
	var d := SimPickup.new()
	d.stage = stage
	d.restore(s)
	return d


## 2台の端末が同じ状態かを確かめるための値
func checksum() -> int:
	return hash(save_state())
