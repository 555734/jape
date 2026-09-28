class_name Tuning
## 動きの数値。単位はマス(=1m)と秒。根拠は docs/RULES.md の「3. 動きの数値」。
## ゲーム内の調整パネルから実機で変えられるよう、定数ではなく変数にしている。

## 標準の値を変えたら上げる(端末に保存された古い調整値を無視させるため。ui/control_settings.gd)
const VERSION := 5

# v3(2026-09): 実機の3回目の指摘「重いのにジャンプが高すぎる・段ごとの差が小さい・遅すぎる・速さを細かく」
# を優先した値。v2(横を遅く・落下を重く)とは逆方向なので、v2の保存値は読み込まない。
# v4(2026-09): 同じ指摘の再送(実機にはv2が入っていた)。段の差をさらに広げ(3.8→5.3→7.2、横の勢い1.08/1.15倍)、
# キャラの見た目を原作画像の比率(約1.4マス)に。v3以前の保存値は読み込まない。
# v5(2026-09): 実機の指摘「重力を感じない(DSのマリオのようにしたい)」。上昇はゆっくり・頂点でふわっと浮き・
# 落下は重く加速する3区間の重力にし、横の速さを4段に刻んだ。高さは滞空時間を今と同程度に保つため約16%下げた。
# 上昇・落下の重力の意味が変わるので、v4以前の保存値は読み込まない。
# 原作の実測値は docs/RULES.md §3 の「原作の実測」列に残してある。

# 歩き・ダッシュ
# 横の速さは4段。滑らかに補間せず、段ごとの速さへ吸い付く(ユーザー要望: 4段階くらいに分けたい)
static var CREEP_SPEED := 2.5         ## 段1: スティックを少しだけ倒したときのゆっくり歩き【決定・調整】
static var WALK_SPEED := 6.0          ## 段2: 歩き。動画実測5.6を実機の感想で少し上げた【調整】
static var RUN_SPEED := 11.3          ## 段3: ダッシュ。動画実測。TASVideosの解析(3.0ドット/フレーム)と一致
static var MAX_RUN_SPEED := 13.5      ## 段4: ダッシュを続けたときの最高速【決定・調整】
static var RUN_STEP_TIME := 0.5       ## 段3をこの秒数続けると段4に上がる【決定・調整】
static var SPEED_TIERS := 4           ## 段の数(段0=止まっている)
static var WALK_ACCEL := 6.0 / 0.25   ## 0.25秒で最高速(0.4秒では動き出しが遅いとの感想)【調整】
static var RUN_ACCEL := 11.3 / 0.25
static var STOP_DECEL := 6.0 / 0.2    ## 0.2秒で停止【決定・調整】
static var SKID_MIN_SPEED := 3.0      ## この速さ以上で逆に入れると切り返し(スキッド)【推測・調整】
static var SKID_DECEL := 35.0         ## 切り返し中の減速(ダッシュから約0.3秒で止まる)【推測・調整】
static var AIR_ACCEL_RATE := 0.85     ## 空中の加速は地上の何倍か【推測・調整】

# ジャンプ
# 重力は速度で3区間に分かれる(ユーザー要望: 上昇は遅く・落下は早く・高さが時間に対して非線形)。
#   上昇中(vel.y > APEX_BAND)       … GRAVITY_RISE  ゆっくり上がる
#   頂点付近(|vel.y| <= APEX_BAND)  … GRAVITY_APEX  ふわっと溜める
#   落下中(vel.y < -APEX_BAND)      … GRAVITY_DOWN  重く加速して落ちる
static var GRAVITY_RISE := 32.0       ## 上昇中の重力【調整】
static var GRAVITY_APEX := 17.0       ## 頂点付近の重力。小さいほど頂点で浮く【決定・調整】
static var APEX_BAND := 4.0           ## 頂点とみなす速さの幅 (マス/秒)【決定・調整】
static var GRAVITY_DOWN := 66.0       ## 落下中の重力。上昇より重くして重力を感じさせる【調整】
static var GRAVITY_CUT := 110.0       ## 上昇中にボタンを離したとき(低いジャンプ)【決定・調整】
static var MAX_FALL := 32.0           ## 3段ジャンプ(6.1マス)の落下で頭打ちにならない値【決定・調整】
static var RUN_JUMP_HEIGHT := 3.2     ## 上昇を遅くした分、滞空時間を保つため下げた【調整】
static var STAND_JUMP_HEIGHT := 2.7   ## 【調整】

# 敵・落ちる物の重力。プレイヤーの重力を変えても敵の挙動は今のままにするため別にしている
static var ACTOR_GRAVITY := 40.0      ## 【決定・調整】
static var ACTOR_MAX_FALL := 24.0     ## 【決定・調整】

# 3段ジャンプ(原作に存在【Wiki】。数値は【推測・調整】)
static var TRIPLE_WINDOW := 0.12      ## 着地からこの秒数以内に跳ぶと次の段になる
static var TRIPLE_MIN_SPEED := 4.5    ## この横速度以上で走っていること
static var JUMP2_HEIGHT := 4.5        ## 2段目。1段目(3.2)との差を1.3マスに【調整】
static var JUMP2_SPEED_BOOST := 1.08  ## 2段目で横の勢いを何倍にするか【決定・調整】
static var JUMP3_HEIGHT := 6.1        ## 3段目(宙返り)。2段目との差を1.6マスに【推測・調整】動画に映っていない
static var JUMP3_SPEED_BOOST := 1.15  ## 3段目で横の勢いを何倍にするか【決定・調整】

# 壁すべり・壁キック(原作に存在【Wiki】。入力制限16フレームは【TAS】、他は【推測・調整】)
static var WALL_SLIDE_SPEED := 3.0    ## 壁に張り付いて滑り落ちる速さ
static var WALL_KICK_SPEED_X := 7.5   ## 壁キックで反対へ飛ぶ横速度
static var WALL_KICK_HEIGHT := 4.0    ## 壁キックの高さ
static var WALL_KICK_LOCK_FRAMES := 16    ## 壁キック直後に壁方向の入力を受け付けないフレーム数【TAS】

# ヒップドロップ・踏みつけ・しゃがみ【推測・調整】
static var GP_HOVER := 0.25           ## 空中で1回転して止まる時間
static var GP_SPEED := 34.0           ## 急降下の速さ。自由落下より速いままにする
static var GP_LAND_STUN := 0.2        ## 着地後に動けない時間
static var STOMP_BOUNCE_LOW := 1.5    ## 踏んだときの跳ね返り(マス)
static var STOMP_BOUNCE_HIGH := 4.5   ## 踏んだ瞬間にジャンプを押していたとき
static var CROUCH_HEIGHT := 1.0       ## 大きい状態でしゃがんだときの高さ


## 頂点付近の区間で稼ぐ高さ。3区間モデルの計算で何度も使う
static func apex_height() -> float:
	return APEX_BAND * APEX_BAND / (2.0 * GRAVITY_APEX)


## この高さまで上がる打ち上げ速度。3区間の重力と一致させる:
##   h = (v^2 - band^2) / (2*GRAVITY_RISE) + band^2 / (2*GRAVITY_APEX)
static func velocity_for_height(h: float) -> float:
	var rise_part := h - apex_height()
	if rise_part <= 0.0:
		# 頂点の区間だけで届く低いジャンプ(踏みつけの跳ね返りなど)
		return sqrt(2.0 * GRAVITY_APEX * h)
	return sqrt(rise_part * 2.0 * GRAVITY_RISE + APEX_BAND * APEX_BAND)


## この高さのジャンプの上昇にかかる時間(テストと文書用。シミュレーションでは使わない)
static func rise_time_for_height(h: float) -> float:
	var v := velocity_for_height(h)
	if v <= APEX_BAND:
		return v / GRAVITY_APEX
	return (v - APEX_BAND) / GRAVITY_RISE + APEX_BAND / GRAVITY_APEX


## この高さから着地するまでの時間(同上)
static func fall_time_for_height(h: float) -> float:
	var apex := minf(apex_height(), h)
	var t := sqrt(2.0 * apex / GRAVITY_APEX)
	var rest := h - apex
	if rest <= 0.0:
		return t
	var v0 := sqrt(2.0 * GRAVITY_APEX * apex)
	return t + (sqrt(v0 * v0 + 2.0 * GRAVITY_DOWN * rest) - v0) / GRAVITY_DOWN


## 横の段(1〜SPEED_TIERS)に応じたジャンプの高さ。横の速さと高さの段をそろえる
static func jump_height_for_tier(tier: int) -> float:
	var t := clampi(tier, 1, SPEED_TIERS)
	return STAND_JUMP_HEIGHT + (RUN_JUMP_HEIGHT - STAND_JUMP_HEIGHT) * float(t - 1) / float(SPEED_TIERS - 1)


static func jump_velocity(tier: int) -> float:
	return velocity_for_height(jump_height_for_tier(tier))

## 調整パネル用: 名前で値を読む
static func get_value(key: String) -> float:
	match key:
		"RUN_SPEED":
			return RUN_SPEED
		"RUN_JUMP_HEIGHT":
			return RUN_JUMP_HEIGHT
		"STAND_JUMP_HEIGHT":
			return STAND_JUMP_HEIGHT
		"TRIPLE_WINDOW":
			return TRIPLE_WINDOW
		"JUMP2_HEIGHT":
			return JUMP2_HEIGHT
		"JUMP3_HEIGHT":
			return JUMP3_HEIGHT
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
		"GRAVITY_APEX":
			return GRAVITY_APEX
		"APEX_BAND":
			return APEX_BAND
		"GRAVITY_DOWN":
			return GRAVITY_DOWN
		"WALK_SPEED":
			return WALK_SPEED
		"MAX_RUN_SPEED":
			return MAX_RUN_SPEED
		"CREEP_SPEED":
			return CREEP_SPEED
		"RUN_STEP_TIME":
			return RUN_STEP_TIME
	return 0.0


## 調整パネル用: 名前で値を書く
static func set_value(key: String, v: float) -> void:
	match key:
		"RUN_SPEED":
			RUN_SPEED = v
		"RUN_JUMP_HEIGHT":
			RUN_JUMP_HEIGHT = v
		"STAND_JUMP_HEIGHT":
			STAND_JUMP_HEIGHT = v
		"TRIPLE_WINDOW":
			TRIPLE_WINDOW = v
		"JUMP2_HEIGHT":
			JUMP2_HEIGHT = v
		"JUMP3_HEIGHT":
			JUMP3_HEIGHT = v
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
		"GRAVITY_APEX":
			GRAVITY_APEX = v
		"APEX_BAND":
			APEX_BAND = v
		"GRAVITY_DOWN":
			GRAVITY_DOWN = v
		"WALK_SPEED":
			WALK_SPEED = v
		"MAX_RUN_SPEED":
			MAX_RUN_SPEED = v
		"CREEP_SPEED":
			CREEP_SPEED = v
		"RUN_STEP_TIME":
			RUN_STEP_TIME = v
