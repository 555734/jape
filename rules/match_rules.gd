class_name MatchRules
extends RefCounted
## 対戦ルールの判定(画面やキャラの動きに依存しない)。根拠は docs/RULES.md。
## 数字の後ろのコメントは RULES.md の節番号。

const STAR_FIRST_DELAY := 2.0     ## §4 最初のスター【決定・調整】
const STAR_RESPAWN_DELAY := 10.0  ## §4 取られてから10秒【FAQ】
const INVULN_TIME := 1.0          ## §5 被弾後の無敵【FAQ】
const DROP_LIFETIME := 5.0        ## §5 落としたスターが消えるまで【決定】
const DROP_OWNER_LOCK := 0.5      ## §5 本人が拾えない時間【決定・調整】
const COINS_PER_ITEM := 8         ## §6
const SPAWN_INVULN := 2.0         ## §5 登場・復帰直後の無敵【決定・調整】

var stars_to_win := 3
var wins_to_match := 3
var start_lives := 3              ## -1 で無限

var stars := [0, 0]
var lives := [3, 3]
var wins := [0, 0]
var coins := [0, 0]
var invuln := [0.0, 0.0]

var star_active := false
var star_point := -1              ## 出ているスターの候補地点番号
var star_timer := 0.0
var star_point_count := 6

var round_winner := -1
var match_winner := -1

## 落としたスター: {id, owner, age}
var drops: Array[Dictionary] = []
## ゲーム側が画面に出すべき、新しく落ちたスター: {id, owner}
var new_drops: Array[Dictionary] = []

var _next_drop_id := 1
var _rng := RandomNumberGenerator.new()


func _init(seed_value := 0) -> void:
	if seed_value != 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()


## 通信対戦の巻き戻し用: 状態をまるごと配列にする / 配列から戻す
func snapshot() -> Array:
	return [stars.duplicate(), lives.duplicate(), wins.duplicate(), coins.duplicate(), invuln.duplicate(),
		star_active, star_point, star_timer, round_winner, match_winner,
		drops.duplicate(true), new_drops.duplicate(true), _next_drop_id, _rng.state]


func restore(a: Array) -> void:
	stars = a[0].duplicate()
	lives = a[1].duplicate()
	wins = a[2].duplicate()
	coins = a[3].duplicate()
	invuln = a[4].duplicate()
	star_active = a[5]
	star_point = a[6]
	star_timer = a[7]
	round_winner = a[8]
	match_winner = a[9]
	drops.assign(a[10].duplicate(true))
	new_drops.assign(a[11].duplicate(true))
	_next_drop_id = a[12]
	_rng.state = a[13]


func start_round() -> void:
	stars = [0, 0]
	lives = [start_lives, start_lives]
	coins = [0, 0]
	invuln = [0.0, 0.0]
	star_active = false
	star_point = -1
	star_timer = STAR_FIRST_DELAY
	round_winner = -1
	drops.clear()
	new_drops.clear()


## 時間を進める。スターが出現したら true
func advance(dt: float) -> bool:
	for p in 2:
		invuln[p] = maxf(0.0, invuln[p] - dt)
	for d in drops:
		d.age += dt
	drops = drops.filter(func(d: Dictionary) -> bool: return d.age < DROP_LIFETIME - 1e-6)
	if round_winner >= 0 or star_active:
		return false
	star_timer -= dt
	if star_timer <= 1e-6:
		_spawn_star()
		return true
	return false


func _spawn_star() -> void:
	var choices := []
	for i in star_point_count:
		if i != star_point:
			choices.append(i)
	star_point = choices[_rng.randi_range(0, choices.size() - 1)]
	star_active = true


## ビッグスターを取った
func collect_star(p: int) -> void:
	if not star_active or round_winner >= 0:
		return
	star_active = false
	star_timer = STAR_RESPAWN_DELAY
	_gain(p, 1)


## スターを失う。無敵中は失わない。実際に失った数を返す
func hit(p: int, amount: int) -> int:
	if invuln[p] > 0.0 or round_winner >= 0:
		return 0
	invuln[p] = INVULN_TIME
	return _drop(p, amount)


func stomp(_attacker: int, victim: int) -> int:
	return hit(victim, 1)          ## §5 踏まれる=1


func ground_pound(_attacker: int, victim: int) -> int:
	return hit(victim, 3)          ## §5 ヒップドロップ=最大3


## 2人がぶつかった。どちらかが無敵中なら何も起きない。
func bump() -> bool:
	if invuln[0] > 0.0 or invuln[1] > 0.0 or round_winner >= 0:
		return false
	hit(0, 1)
	hit(1, 1)
	return true


## ミス(穴に落ちた・小さい状態でダメージ)。無敵中でも起きる
func miss(p: int) -> void:
	if round_winner >= 0:
		return
	_drop(p, 1)
	invuln[p] = INVULN_TIME
	if lives[p] > 0:
		lives[p] -= 1
		if lives[p] == 0:
			_win(1 - p)


## 登場・復帰した直後の無敵
func spawn_protect(p: int) -> void:
	invuln[p] = maxf(invuln[p], SPAWN_INVULN)


func can_pickup_drop(id: int, p: int) -> bool:
	for d in drops:
		if d.id == id:
			return d.owner != p or d.age >= DROP_OWNER_LOCK - 1e-6
	return false


## 落ちたスターを拾う。拾えたら true
func pickup_drop(id: int, p: int) -> bool:
	if round_winner >= 0 or not can_pickup_drop(id, p):
		return false
	drops = drops.filter(func(d: Dictionary) -> bool: return d.id != id)
	_gain(p, 1)
	return true


func drop_exists(id: int) -> bool:
	return drops.any(func(d: Dictionary) -> bool: return d.id == id)


func drop_age(id: int) -> float:
	for d in drops:
		if d.id == id:
			return d.age
	return DROP_LIFETIME


## コインを取った。アイテムが出るなら true
func add_coin(p: int) -> bool:
	coins[p] += 1
	if coins[p] >= COINS_PER_ITEM:
		coins[p] = 0
		return true
	return false


func next_round() -> void:
	if match_winner < 0:
		start_round()


func reset_match() -> void:
	wins = [0, 0]
	match_winner = -1
	start_round()


func _gain(p: int, n: int) -> void:
	stars[p] += n
	if stars[p] >= stars_to_win:
		_win(p)


func _drop(p: int, amount: int) -> int:
	var lost := mini(amount, stars[p])
	stars[p] -= lost
	for i in lost:
		var d := {"id": _next_drop_id, "owner": p, "age": 0.0}
		_next_drop_id += 1
		drops.append(d)
		new_drops.append({"id": d.id, "owner": p})
	return lost


func _win(p: int) -> void:
	if round_winner >= 0:
		return
	round_winner = p
	wins[p] += 1
	if wins[p] >= wins_to_match:
		match_winner = p
