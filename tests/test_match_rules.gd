extends TestBase
## docs/RULES.md §1 §4 §5 §6 の各行が守られているか。


func _rules(stars0 := 0, stars1 := 0) -> MatchRules:
	var r := MatchRules.new(12345)
	r.start_round()
	r.stars = [stars0, stars1]
	return r


func _run(r: MatchRules, seconds: float) -> void:
	var t := 0.0
	while t < seconds - 1e-6:
		r.advance(0.1)
		t += 0.1


func test_stomp_loses_one() -> void:
	var r := _rules(0, 2)
	assert_true(r.stomp(0, 1) == 1 and r.stars[1] == 1, "踏まれると1個失う")


func test_ground_pound_loses_up_to_three() -> void:
	var r := _rules(0, 5)
	assert_true(r.ground_pound(0, 1) == 3 and r.stars[1] == 2, "ヒップドロップで3個失う(5→2)")
	var r2 := _rules(0, 2)
	assert_true(r2.ground_pound(0, 1) == 2 and r2.stars[1] == 0, "2個しか無ければ2個失う")


func test_nothing_to_lose() -> void:
	var r := _rules(0, 0)
	assert_true(r.stomp(0, 1) == 0 and r.new_drops.is_empty(), "手持ち0なら何も落ちない")


func test_invulnerable_after_hit() -> void:
	var r := _rules(0, 3)
	r.stomp(0, 1)
	_run(r, 0.9)
	assert_true(r.stomp(0, 1) == 0 and r.stars[1] == 2, "被弾から0.9秒は失わない")
	_run(r, 0.2)
	assert_true(r.stomp(0, 1) == 1 and r.stars[1] == 1, "1.1秒後は失う")


func test_bump_both_lose_one() -> void:
	var r := _rules(2, 2)
	r.bump()
	assert_true(r.stars[0] == 1 and r.stars[1] == 1, "ぶつかると双方1個ずつ")
	assert_true(not r.bump(), "無敵中はぶつかっても起きない")


func test_miss_loses_life_and_star() -> void:
	var r := _rules(0, 2)
	r.miss(1)
	assert_true(r.lives[1] == 2 and r.stars[1] == 1, "ミスで残機−1・スター−1")


func test_miss_while_invulnerable_still_counts() -> void:
	var r := _rules(0, 2)
	r.stomp(0, 1)
	r.miss(1)
	assert_true(r.lives[1] == 2, "無敵中でも穴に落ちればミス")


func test_out_of_lives_loses_round() -> void:
	var r := _rules()
	for i in 3:
		r.miss(1)
		_run(r, 1.1)
	assert_true(r.round_winner == 0 and r.wins[0] == 1, "残機0で相手の勝ち")


func test_three_stars_wins_immediately() -> void:
	var r := _rules(2, 0)
	r.star_active = true
	r.collect_star(0)
	assert_true(r.round_winner == 0, "3個目で即勝利")


func test_three_wins_ends_match() -> void:
	var r := _rules()
	for i in 3:
		r.stars = [2, 0]
		r.star_active = true
		r.collect_star(0)
		assert_true(r.round_winner == 0, "ラウンド%d勝利" % (i + 1))
		r.next_round()
	assert_true(r.match_winner == 0 and r.wins[0] == 3, "3勝で試合終了")


func test_first_star_after_two_seconds() -> void:
	var r := _rules()
	_run(r, 1.9)
	assert_true(not r.star_active, "開始1.9秒ではスターは出ない")
	_run(r, 0.1)
	assert_true(r.star_active, "開始2.0秒で出る")


func test_star_respawn_ten_seconds() -> void:
	var r := _rules()
	_run(r, 2.0)
	r.collect_star(0)
	_run(r, 9.9)
	assert_true(not r.star_active, "取得から9.9秒では出ない")
	_run(r, 0.1)
	assert_true(r.star_active, "取得から10.0秒で出る")


func test_star_never_same_point_twice() -> void:
	var r := _rules()
	r.stars_to_win = 999
	_run(r, 2.0)
	var same := false
	for i in 200:
		var prev := r.star_point
		r.collect_star(i % 2)
		_run(r, 10.0)
		if r.star_point == prev:
			same = true
	assert_true(not same, "200回出現して、同じ地点が連続しない")


func test_drop_vanishes_after_five_seconds() -> void:
	var r := _rules(0, 1)
	r.stomp(0, 1)
	var id: int = r.new_drops[0].id
	_run(r, 4.9)
	assert_true(r.drop_exists(id), "落としたスターは4.9秒後も残る")
	_run(r, 0.1)
	assert_true(not r.drop_exists(id), "5.0秒で消える")


func test_owner_cannot_pickup_immediately() -> void:
	var r := _rules(0, 1)
	r.stomp(0, 1)
	var id: int = r.new_drops[0].id
	_run(r, 0.4)
	assert_true(not r.pickup_drop(id, 1), "本人は0.4秒では拾えない")
	assert_true(r.can_pickup_drop(id, 0), "相手はすぐ拾える")
	_run(r, 0.1)
	assert_true(r.pickup_drop(id, 1) and r.stars[1] == 1, "本人も0.5秒で拾える")


func test_eight_coins_give_item() -> void:
	var r := _rules()
	var items := 0
	for i in 8:
		if r.add_coin(0):
			items += 1
	assert_true(items == 1 and r.coins[0] == 0, "8枚目でアイテム1個、カウンター0に戻る")
