class_name Tuning
## 動きの数値。単位はマス(=1m)と秒。根拠は docs/RULES.md の「3. 動きの数値」。
## ゲーム内の調整パネルから実機で変えられるよう、定数ではなく変数にしている。

## 標準の値を変えたら上げる(端末に保存された古い調整値を無視させるため。ui/control_settings.gd)
const VERSION := 7

# v3〜v5(2026-09): 実機の感想を1項目ずつ数値に反映していた版。ひとつ直すたびに別の比率が崩れた。
# v6(2026-09): SMB3 の実装値へ移植。方式は正しかったが基準作品が違った。
#
# v7(2026-09): 基準を New Super Mario Bros.(Nintendo DS) にした。
# 目標は「同じ入力列を与えたら位置・速度・状態遷移が可能な限り同じ」になること。
# 値の出典・換算式・確度(exact / reimpl / measured / unknown)は docs/nsmb_ds_physics.md。
# 換算: Jape のマス/秒 = 資料の値 × 2、ドット/フレーム = マス/秒 × 16/60。
# 受け入れ条件は tests/test_nsmb_feel.gd。数値をずらすときは、まずあちらに1行足すこと。

# 歩き・ダッシュ【NSMB DS】
# 速度段は「入力」ではなく「今の速度」で決まる。|vx| を最高速表と先頭から比べ、
# 最初に |vx| - 0.01 <= 表[i] になった段 i を使い、その段の加速を適用する。
# 上限段はボタンで決まる: 歩き = WALK_STAGE / ダッシュ押下 = RUN_STAGE。
static var WALK_MAX_VELOCITY: Array[float] = [1.875, 5.625, 8.4375, 11.25, 16.875]
static var WALK_ACCEL: Array[float] = [15.8203, 7.9102, 7.0313, 5.2734, 168.75]
static var WALK_STAGE := 1            ## 歩きの上限段(5.625 マス/秒 = 1.5 ドット/フレーム)
static var RUN_STAGE := 3             ## ダッシュの上限段(11.25 マス/秒 = 3.0 ドット/フレーム)
static var STAGE_EPSILON := 0.01      ## 段を引くときに速度から引く値

static var RELEASE_DECEL := 7.9102    ## 入力を離したときの減速
static var TURNAROUND_ACCEL: Array[float] = [7.9102, 17.5781, 17.5781, 42.1875]   ## 逆入力の減速(段別)
static var FAST_TURNAROUND_ACCEL := 56.25    ## 高速で逆入力したときの減速
static var SKID_MIN_SPEED := 9.375    ## この速さ以上で逆に入れると切り返し(スキッド)
static var SKID_DECEL := 21.0938      ## 切り返し中の減速
# 空中の加速は地上と同じ表を使う(NSMB はここを分けていない)。スキッドは地上のみ。

# ジャンプ【NSMB DS】
# 高さは数値として持たない。初速と重力から決まる結果であり、tests/test_nsmb_feel.gd が実測する。
static var JUMP_VELOCITY := 13.2422        ## ジャンプ初速
static var JUMP_SPEED_BONUS := 0.9375      ## 横に速いほど上乗せされる初速(最大)
static var JUMP_TRIPLE_BONUS := 1.0        ## 3段目の上乗せ(原作にも存在する)
static var JUMP_BUFFER_FRAMES := 12        ## 着地前にジャンプを押しておける猶予
static var COYOTE_FRAMES := 3              ## 足場を離れてからジャンプできる猶予

# 重力は速度帯で5段に切り替わる。vy を閾値と先頭から比べ、最初に vy >= 閾値[i] になった段を使う。
# 段0(勢いよく上昇中)はジャンプボタンを押している間だけ。離していれば最終段を使う ← 短押しの仕組み。
# 頂点の直前(段2)が最も重い。「頂点でふわっと浮く」のは原作とは逆なので入れない。
static var GRAVITY_VELOCITY: Array[float] = [8.3203, 4.2188, 0.0, -11.7188]
static var GRAVITY_ACCEL: Array[float] = [14.0625, 56.25, 77.3438, 56.25, 77.3438]

# 落下速度の上限
static var MAX_FALL := 15.0                ## 通常(4.0 ドット/フレーム)
static var MAX_FALL_WALL_SLIDE := 9.375    ## 壁すべり中
static var MAX_FALL_GROUND_POUND := 22.5   ## ヒップドロップ中

# 敵・落ちる物の重力。プレイヤーの重力を変えても敵の挙動は変えない【決定・調整】
static var ACTOR_GRAVITY := 40.0
static var ACTOR_MAX_FALL := 24.0

# 3段ジャンプ【NSMB DS】。原作にも存在し、3段目は初速に JUMP_TRIPLE_BONUS が乗る。
# 猶予・最低速度・横の勢いの倍率は原作で確認できていないので Jape 独自(docs/nsmb_ds_physics.md §6)
static var TRIPLE_WINDOW := 0.12      ## 着地からこの秒数以内に跳ぶと次の段になる【Jape独自】
static var TRIPLE_MIN_SPEED := 4.5    ## この横速度以上で走っていること【Jape独自】
static var JUMP2_SPEED_BOOST := 1.08  ## 2段目で横の勢いを何倍にするか【Jape独自】
static var JUMP3_SPEED_BOOST := 1.15  ## 3段目で横の勢いを何倍にするか【Jape独自】

# 壁すべり・壁キック【NSMB DS】。壁すべりの落下上限は MAX_FALL_WALL_SLIDE。入力制限は【TAS】
static var WALL_KICK_SPEED_X := 8.4375    ## 壁キックで反対へ飛ぶ横速度【NSMB DS】
static var WALL_KICK_SPEED_Y := 12.8906   ## 壁キックの初速【NSMB DS】
static var WALL_KICK_LOCK_FRAMES := 16    ## 壁キック直後に壁方向の入力を受け付けないフレーム数【TAS】

# ヒップドロップ・踏みつけ・しゃがみ【推測・調整】
static var GP_HOVER := 0.25           ## 空中で1回転して止まる時間
static var GP_SPEED := 22.5           ## 急降下の速さ【NSMB DS】MAX_FALL_GROUND_POUND と同じ
static var GP_LAND_STUN := 0.2        ## 着地後に動けない時間
static var STOMP_BOUNCE_LOW := 8.0    ## 踏んだときの跳ね返りの初速【Jape独自】
static var STOMP_BOUNCE_HIGH := 13.2422   ## 踏んだ瞬間にジャンプを押していたとき【Jape独自】
static var CROUCH_HEIGHT := 1.0       ## 大きい状態でしゃがんだときの高さ


## 今の速さが何段目か【NSMB DS】。最初に |vx| - 0.01 <= 表[i] になった段を返す
static func speed_stage(speed: float) -> int:
	var v := absf(speed) - STAGE_EPSILON
	for i in WALK_MAX_VELOCITY.size():
		if v <= WALK_MAX_VELOCITY[i]:
			return i
	return WALK_MAX_VELOCITY.size() - 1


## 今の上下の速さが重力の何段目か【NSMB DS】。最初に vy >= 閾値[i] になった段を返す
static func gravity_stage(vy: float) -> int:
	for i in GRAVITY_VELOCITY.size():
		if vy >= GRAVITY_VELOCITY[i]:
			return i
	return GRAVITY_VELOCITY.size()


## 横の速さに応じたジャンプ初速【NSMB DS】。歩きの最高速を境に上乗せが増える
static func jump_velocity(speed_x: float) -> float:
	var walk_top := WALK_MAX_VELOCITY[WALK_STAGE]
	var alpha := clampf(absf(speed_x) - walk_top + walk_top * 0.5, 0.0, 1.0)
	return JUMP_VELOCITY + JUMP_SPEED_BONUS * alpha


## この初速で上がれる高さ(テストと文書用。シミュレーションでは使わない)
static func height_for_velocity(v: float) -> float:
	var h := 0.0
	var vy := v
	while vy > 0.0:
		var i := gravity_stage(vy)
		var g := GRAVITY_ACCEL[i]
		var next := maxf(GRAVITY_VELOCITY[i], 0.0) if i < GRAVITY_VELOCITY.size() else 0.0
		if next >= vy:
			break
		h += (vy * vy - next * next) / (2.0 * g)
		vy = next
	return h


## 調整パネル用: 名前で値を読む
static func get_value(key: String) -> float:
	match key:
		"JUMP_VELOCITY":
			return JUMP_VELOCITY
		"JUMP_SPEED_BONUS":
			return JUMP_SPEED_BONUS
		"TRIPLE_WINDOW":
			return TRIPLE_WINDOW
		"WALL_KICK_SPEED_X":
			return WALL_KICK_SPEED_X
		"WALL_KICK_SPEED_Y":
			return WALL_KICK_SPEED_Y
		"SKID_DECEL":
			return SKID_DECEL
		"GP_HOVER":
			return GP_HOVER
		"MAX_FALL":
			return MAX_FALL
		"MAX_FALL_WALL_SLIDE":
			return MAX_FALL_WALL_SLIDE
		"JUMP_BUFFER_FRAMES":
			return float(JUMP_BUFFER_FRAMES)
		"COYOTE_FRAMES":
			return float(COYOTE_FRAMES)
	return 0.0


## 調整パネル用: 名前で値を書く
static func set_value(key: String, v: float) -> void:
	match key:
		"JUMP_VELOCITY":
			JUMP_VELOCITY = v
		"JUMP_SPEED_BONUS":
			JUMP_SPEED_BONUS = v
		"TRIPLE_WINDOW":
			TRIPLE_WINDOW = v
		"WALL_KICK_SPEED_X":
			WALL_KICK_SPEED_X = v
		"WALL_KICK_SPEED_Y":
			WALL_KICK_SPEED_Y = v
		"SKID_DECEL":
			SKID_DECEL = v
		"GP_HOVER":
			GP_HOVER = v
		"MAX_FALL":
			MAX_FALL = v
		"MAX_FALL_WALL_SLIDE":
			MAX_FALL_WALL_SLIDE = v
		"JUMP_BUFFER_FRAMES":
			JUMP_BUFFER_FRAMES = int(v)
		"COYOTE_FRAMES":
			COYOTE_FRAMES = int(v)
