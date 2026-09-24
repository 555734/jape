class_name CpuBrain
extends RefCounted
## CPUの操作。目標を決めて、そこへ向かう入力を毎フレーム作る。
## 目標の優先順位: ビッグスター > 落ちたスター > スターを持った相手 > アイテム > コイン > 相手

const REACH_UP := 4.2        ## 1回のジャンプで確実に届く高さ(マス)
const STUCK_TIME := 1.2      ## この秒数ほぼ動かなければ「詰まった」とみなす

var me: Player
var opp: Player
var game: Node               ## MatchGame
var target := Vector3.ZERO

var _hold := 0.0
var _stuck_timer := 0.0
var _stuck_origin := Vector3.ZERO
var _escape := 0.0
var _escape_dir := 1.0
var _rng := RandomNumberGenerator.new()
var _air_side := 0.0        ## デバッグ用: 直近の位置と判断


func _init(p_me: Player, p_opp: Player, p_game: Node, seed_value := 0) -> void:
	me = p_me
	opp = p_opp
	game = p_game
	if seed_value != 0:
		_rng.seed = seed_value


func think(dt: float) -> PlayerInput:
	var stage := me.stage
	target = game.cpu_target(me.index)
	var dx := stage.delta_x(me.position.x, target.x)
	var dy := target.y - me.position.y

	# 高すぎる目標には、途中の足場を経由する
	if dy > REACH_UP:
		var step := _pick_ledge(stage)
		if step != Vector3.INF:
			dx = stage.delta_x(me.position.x, step.x)
			dy = step.y - me.position.y

	var move := 0.0
	if absf(dx) > 0.3:
		move = signf(dx)
	# 目標が上にあり、頭上が足場でふさがっていたら、まず足場の端まで移動する
	var blocked := false
	if dy > 0.8 and me.is_on_floor() and _ceiling(stage, 0.0):
		var side := _nearest_open_side(stage)
		if side != 0.0:
			move = side
			blocked = true
	var want_jump := false
	if me.is_on_floor():
		if dy > 0.8 and absf(dx) < 3.0 and not blocked:
			want_jump = true
		if move != 0.0 and me.is_on_wall():
			want_jump = true
		if move != 0.0 and _gap_ahead(stage, move):
			if absf(dx) > 2.5:
				want_jump = true   # 目標は穴の向こう側: 飛び越える
			else:
				move = 0.0         # 目標は穴のそば: 縁で止まる
				want_jump = want_jump and dy > 0.8
		if move != 0.0 and _enemy_ahead(stage, move):
			want_jump = true   # 敵を飛び越える(上から落ちれば踏める)
		if absf(dx) < 3.0 and target.distance_to(opp.position) < 0.5 and opp.bottom() <= me.bottom() + 0.5:
			want_jump = true   # 相手を踏みに行く

	# 詰まり対策: しばらく動けていなければ、反対向きに跳ねる
	_stuck_timer += dt
	if _stuck_timer >= STUCK_TIME:
		if me.position.distance_to(_stuck_origin) < 0.6 and absf(dx) > 0.6:
			_escape = 0.7
			_escape_dir = -move if move != 0.0 else (1.0 if _rng.randf() < 0.5 else -1.0)
		_stuck_timer = 0.0
		_stuck_origin = me.position
	if _escape > 0.0:
		_escape -= dt
		move = _escape_dir
		want_jump = me.is_on_floor()

	# 空中で真下が穴なら、近い足場のほうへ寄る
	if me.is_on_floor():
		_air_side = 0.0
	elif me.velocity.y < 0.0 and not stage.has_floor_below(me.position, 12):
		if _air_side == 0.0:
			_air_side = _nearest_floor_side(stage)
		if _air_side != 0.0:
			move = _air_side

	var jump_pressed := want_jump and _hold <= 0.0
	if jump_pressed:
		_hold = 0.55
	_hold = maxf(0.0, _hold - dt)

	# 真下に相手がいたらヒップドロップ
	var down := false
	if not me.is_on_floor() and me.velocity.y < 0.0 and not opp.dead:
		var odx := absf(stage.delta_x(me.position.x, opp.position.x))
		var ody := me.bottom() - opp.top()
		if odx < 0.5 and ody > 0.8 and ody < 5.0:
			down = true
	return PlayerInput.make(move, true, jump_pressed, _hold > 0.0, down)


## 目標に近く、今の位置から1回のジャンプで届く足場
func _pick_ledge(stage: Grassland) -> Vector3:
	var best := Vector3.INF
	var best_score := INF
	for l in stage.ledges:
		var up := l.y - me.position.y
		if up < 0.5 or up > REACH_UP:
			continue
		var score := absf(stage.delta_x(l.x, target.x)) + absf(target.y - l.y) * 2.0 \
			+ absf(stage.delta_x(me.position.x, l.x)) * 0.3
		if score < best_score:
			best_score = score
			best = l
	return best


## 横に offset マスずれた位置の頭上3マス以内に足場があれば true
func _ceiling(stage: Grassland, offset: float) -> bool:
	var x := int(floor(me.position.x + offset))
	var head := int(floor(me.top() + 0.05))
	for y in range(head, head + 3):
		if stage.is_solid(x, y):
			return true
	return false


## 頭上が空いている一番近い方向(-1 / 1)。見つからなければ 0
func _nearest_open_side(stage: Grassland) -> float:
	for d in range(1, 9):
		for s in [-1.0, 1.0]:
			if not _ceiling(stage, s * d):
				return s
	return 0.0


## 真下に足場がある一番近い方向(-1 / 1)。今進んでいる向きを優先する。見つからなければ 0
func _nearest_floor_side(stage: Grassland) -> float:
	var first := signf(me.velocity.x) if me.velocity.x != 0.0 else 1.0
	for s in [first, -first]:
		for d in range(1, 5):
			if stage.has_floor_below(me.position + Vector3(s * d, 0, 0), 12):
				return s
	return 0.0


## 進行方向の近くに、同じ高さの敵がいれば true
func _enemy_ahead(stage: Grassland, dir: float) -> bool:
	for e in stage.enemies:
		if not e.is_alive():
			continue
		var edx := stage.delta_x(me.position.x, e.position.x)
		if signf(edx) == dir and absf(edx) < 2.5 and absf(e.position.y - me.position.y) < 1.0:
			return true
	return false


## 進行方向のすぐ前の列に足場が無ければ true(穴の手前でジャンプ)
func _gap_ahead(stage: Grassland, dir: float) -> bool:
	var fy := int(floor(me.position.y + 0.05)) - 1
	var fx := int(floor(me.position.x + dir * 0.9))
	return not stage.is_solid(fx, fy) and not stage.is_solid(fx, fy - 1)
