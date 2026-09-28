class_name Tuning
## 動きの数値。単位はマス(=1m)と秒。根拠は docs/RULES.md の「3. 動きの数値」。
## ゲーム内の調整パネルから実機で変えられるよう、定数ではなく変数にしている。

## 標準の値を変えたら上げる(端末に保存された古い調整値を無視させるため。ui/control_settings.gd)
const VERSION := 6

# v3〜v5(2026-09): 実機の感想を1項目ずつ数値に反映していた版。ひとつ直すたびに別の比率が崩れ、
# 最後は「立ちジャンプでハテナブロックに届かない・高さの割に横に進みすぎ」という状態になった。
#
# v6(2026-09): 感想ではなく原作の実装値を移植する方式に変えた。基準は SMB3。
# 出典: velipso/smb3-physics (SMB3 の移動処理を変換した 0BSD の実装)。
# 数値だけを下の換算で取り込み、コードは GDScript で書き直している。
#   1マス=16px、60fps。 px/フレーム → マス/秒 = ×60/16   px/フレーム² → マス/秒² = ×3600/16
# 受け入れ条件は tests/test_mario_feel.gd。数値をずらすときは、まずあちらに1行足すこと。

# 歩き・ダッシュ
# 横の速さは4段(このゲーム独自。SMB3 は歩き/ダッシュの2段)。段の速さへ吸い付き、間は加速でつなぐ。
#   段1 スティックを少し倒す / 段2 大きく倒す / 段3 ダッシュ+少し倒す / 段4 ダッシュ+大きく倒す
static var CREEP_SPEED := 2.5         ## 段1【このゲーム独自】
static var WALK_SPEED := 5.625        ## 段2【SMB3】1.5 px/フレーム
static var RUN_SPEED := 7.5           ## 段3【このゲーム独自】段2と段4の中間
static var MAX_RUN_SPEED := 9.375     ## 段4【SMB3】2.5 px/フレーム(ダッシュの最高速)
static var SPEED_TIERS := 4           ## 段の数(段0=止まっている)
static var WALK_ACCEL := 12.3047      ## 【SMB3】14/256 px/フレーム²(最高速まで約0.76秒)
static var RUN_ACCEL := 12.3047       ## 【SMB3】ダッシュでも加速は同じ
static var STOP_DECEL := 12.3047      ## 【SMB3】止まるときの摩擦も同じ値
static var SKID_MIN_SPEED := 3.0      ## この速さ以上で逆に入れると切り返し(スキッド)【推測・調整】
static var SKID_DECEL := 28.125       ## 【SMB3】32/256 px/フレーム²
static var AIR_ACCEL_RATE := 1.0      ## 空中の加速は地上の何倍か【SMB3】空中でも同じ

# ジャンプ
# 重力は2値。飛び出し直後(上昇が速く、ボタンを押している間)だけ軽く、頂点も落下も重い。
# 高さは「結果」なので数値を持たない(初速と重力から決まる)。tests/test_mario_feel.gd が実測する。
static var GRAVITY_RISE := 14.0625    ## 【SMB3】1/16 px/フレーム²。上昇が速くボタン保持中のみ
static var GRAVITY_FALL := 70.3125    ## 【SMB3】5/16 px/フレーム²。それ以外すべて(頂点・落下・離した後)
static var RISE_SPEED_THRESHOLD := 7.5    ## 【SMB3】2 px/フレーム。上昇がこれより速い間だけ軽い重力
static var MAX_FALL := 15.0           ## 【SMB3】4 px/フレーム

## ジャンプの初速。横の段(1〜4)で選ぶ【SMB3】-3.5 / -3.625 / -3.75 / -4.0 px/フレーム
## 結果として出る高さ: 4.53 / 4.97 / 5.43 / 6.40 マス
static var JUMP_SPEEDS := [13.125, 13.59375, 14.0625, 15.0]

# 敵・落ちる物の重力。プレイヤーの重力を変えても敵の挙動は変えない【決定・調整】
static var ACTOR_GRAVITY := 40.0
static var ACTOR_MAX_FALL := 24.0

# 3段ジャンプ(原作に存在【Wiki】。SMB3 には無いのでこのゲーム独自の数値)
static var TRIPLE_WINDOW := 0.12      ## 着地からこの秒数以内に跳ぶと次の段になる
static var TRIPLE_MIN_SPEED := 4.5    ## この横速度以上で走っていること
static var JUMP2_SPEED := 16.0        ## 2段目の初速(高さ約7.5マス)【推測・調整】
static var JUMP2_SPEED_BOOST := 1.08  ## 2段目で横の勢いを何倍にするか【決定・調整】
static var JUMP3_SPEED := 17.0        ## 3段目(宙返り)の初速(高さ約8.7マス)【推測・調整】
static var JUMP3_SPEED_BOOST := 1.15  ## 3段目で横の勢いを何倍にするか【決定・調整】

# 壁すべり・壁キック(原作に存在【Wiki】。入力制限16フレームは【TAS】、他は【推測・調整】)
static var WALL_SLIDE_SPEED := 3.0    ## 壁に張り付いて滑り落ちる速さ
static var WALL_KICK_SPEED_X := 7.0   ## 壁キックで反対へ飛ぶ横速度
static var WALL_KICK_HEIGHT := 4.0    ## 壁キックの高さ
static var WALL_KICK_LOCK_FRAMES := 16    ## 壁キック直後に壁方向の入力を受け付けないフレーム数【TAS】

# ヒップドロップ・踏みつけ・しゃがみ【推測・調整】
static var GP_HOVER := 0.25           ## 空中で1回転して止まる時間
static var GP_SPEED := 20.0           ## 急降下の速さ。自由落下(15)より速いままにする
static var GP_LAND_STUN := 0.2        ## 着地後に動けない時間
static var STOMP_BOUNCE_LOW := 1.5    ## 踏んだときの跳ね返り(マス)
static var STOMP_BOUNCE_HIGH := 4.5   ## 踏んだ瞬間にジャンプを押していたとき
static var CROUCH_HEIGHT := 1.0       ## 大きい状態でしゃがんだときの高さ


## 横の段(1〜SPEED_TIERS)に応じたジャンプの初速
static func jump_speed_for_tier(tier: int) -> float:
	return JUMP_SPEEDS[clampi(tier, 1, SPEED_TIERS) - 1]


## 重い重力だけで上がる分の高さ。2値モデルの計算で何度も使う
static func _heavy_part() -> float:
	return RISE_SPEED_THRESHOLD * RISE_SPEED_THRESHOLD / (2.0 * GRAVITY_FALL)


## この高さまで上がる初速(ボタンを押し続けた場合)。2値の重力と一致させる:
##   h = (v^2 - 閾値^2) / (2*GRAVITY_RISE) + 閾値^2 / (2*GRAVITY_FALL)
## 3段ジャンプ・壁キック・踏みつけの跳ね返り(SMB3 に無い要素)を高さで指定するために使う
static func velocity_for_height(h: float) -> float:
	var light_part := h - _heavy_part()
	if light_part <= 0.0:
		return sqrt(2.0 * GRAVITY_FALL * h)
	return sqrt(light_part * 2.0 * GRAVITY_RISE + RISE_SPEED_THRESHOLD * RISE_SPEED_THRESHOLD)


## この初速で上がれる高さ(テストと文書用。シミュレーションでは使わない)
static func height_for_velocity(v: float) -> float:
	if v <= RISE_SPEED_THRESHOLD:
		return v * v / (2.0 * GRAVITY_FALL)
	var light := (v - RISE_SPEED_THRESHOLD) / GRAVITY_RISE
	return (v + RISE_SPEED_THRESHOLD) * 0.5 * light + _heavy_part()


## 上昇にかかる時間(同上)
static func rise_time_for_velocity(v: float) -> float:
	if v <= RISE_SPEED_THRESHOLD:
		return v / GRAVITY_FALL
	return (v - RISE_SPEED_THRESHOLD) / GRAVITY_RISE + RISE_SPEED_THRESHOLD / GRAVITY_FALL


## この高さから着地するまでの時間(同上)。最大落下速度で頭打ちになる分も見る
static func fall_time_for_height(h: float) -> float:
	var to_cap := MAX_FALL * MAX_FALL / (2.0 * GRAVITY_FALL)
	if h <= to_cap:
		return sqrt(2.0 * h / GRAVITY_FALL)
	return MAX_FALL / GRAVITY_FALL + (h - to_cap) / MAX_FALL


## 調整パネル用: 名前で値を読む
static func get_value(key: String) -> float:
	match key:
		"RUN_SPEED":
			return RUN_SPEED
		"TRIPLE_WINDOW":
			return TRIPLE_WINDOW
		"WALL_SLIDE_SPEED":
			return WALL_SLIDE_SPEED
		"WALL_KICK_SPEED_X":
			return WALL_KICK_SPEED_X
		"WALL_KICK_HEIGHT":
			return WALL_KICK_HEIGHT
		"SKID_DECEL":
			return SKID_DECEL
		"GP_HOVER":
			return GP_HOVER
		"GRAVITY_RISE":
			return GRAVITY_RISE
		"GRAVITY_FALL":
			return GRAVITY_FALL
		"RISE_SPEED_THRESHOLD":
			return RISE_SPEED_THRESHOLD
		"MAX_FALL":
			return MAX_FALL
		"WALK_SPEED":
			return WALK_SPEED
		"MAX_RUN_SPEED":
			return MAX_RUN_SPEED
		"CREEP_SPEED":
			return CREEP_SPEED
		"JUMP2_SPEED":
			return JUMP2_SPEED
		"JUMP3_SPEED":
			return JUMP3_SPEED
	return 0.0


## 調整パネル用: 名前で値を書く
static func set_value(key: String, v: float) -> void:
	match key:
		"RUN_SPEED":
			RUN_SPEED = v
		"TRIPLE_WINDOW":
			TRIPLE_WINDOW = v
		"WALL_SLIDE_SPEED":
			WALL_SLIDE_SPEED = v
		"WALL_KICK_SPEED_X":
			WALL_KICK_SPEED_X = v
		"WALL_KICK_HEIGHT":
			WALL_KICK_HEIGHT = v
		"SKID_DECEL":
			SKID_DECEL = v
		"GP_HOVER":
			GP_HOVER = v
		"GRAVITY_RISE":
			GRAVITY_RISE = v
		"GRAVITY_FALL":
			GRAVITY_FALL = v
		"RISE_SPEED_THRESHOLD":
			RISE_SPEED_THRESHOLD = v
		"MAX_FALL":
			MAX_FALL = v
		"WALK_SPEED":
			WALK_SPEED = v
		"MAX_RUN_SPEED":
			MAX_RUN_SPEED = v
		"CREEP_SPEED":
			CREEP_SPEED = v
		"JUMP2_SPEED":
			JUMP2_SPEED = v
		"JUMP3_SPEED":
			JUMP3_SPEED = v
