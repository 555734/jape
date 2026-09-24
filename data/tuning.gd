class_name Tuning
## 動きの数値。単位はマス(=1m)と秒。根拠は docs/RULES.md の「3. 動きの数値」。
## ゲーム内の調整パネルから実機で変えられるよう、定数ではなく変数にしている。

# 歩き・ダッシュ
static var WALK_SPEED := 5.6          ## 動画実測
static var RUN_SPEED := 11.3          ## 動画実測。TASVideosの解析(3.0ドット/フレーム)と一致
static var WALK_ACCEL := 5.6 / 0.4    ## 0.4秒で最高速【決定・調整】
static var RUN_ACCEL := 11.3 / 0.4
static var STOP_DECEL := 5.6 / 0.2    ## 0.2秒で停止【決定・調整】
static var SKID_MIN_SPEED := 3.0      ## この速さ以上で逆に入れると切り返し(スキッド)【推測・調整】
static var SKID_DECEL := 35.0         ## 切り返し中の減速(ダッシュから約0.3秒で止まる)【推測・調整】
static var AIR_ACCEL_RATE := 0.85     ## 空中の加速は地上の何倍か【推測・調整】

# ジャンプ
static var GRAVITY_UP := 36.0         ## 動画実測(地面基準): 高さ4.5マスを0.5秒で上昇
static var GRAVITY_DOWN := 42.0       ## 動画実測(地面基準): 6.8マスを0.57秒で落下
static var GRAVITY_CUT := 80.0        ## 上昇中にボタンを離したとき(低いジャンプ)【決定・調整】
static var MAX_FALL := 24.0           ## 6.8マスの落下(0.57秒)で頭打ちにならない値【決定・調整】
static var RUN_JUMP_HEIGHT := 4.5     ## 動画実測(地面基準、9.7秒のジャンプ)
static var STAND_JUMP_HEIGHT := 3.6   ## 【推測・調整】助走ジャンプの8割

# 3段ジャンプ(原作に存在【Wiki】。数値は【推測・調整】)
static var TRIPLE_WINDOW := 0.12      ## 着地からこの秒数以内に跳ぶと次の段になる
static var TRIPLE_MIN_SPEED := 4.5    ## この横速度以上で走っていること
static var JUMP2_HEIGHT := 5.3        ## 2段目(動画実測: 16秒の着地直後のジャンプ)
static var JUMP3_HEIGHT := 6.2        ## 3段目(宙返り)【推測・調整】動画に映っていない

# 壁すべり・壁キック(原作に存在【Wiki】。入力制限16フレームは【TAS】、他は【推測・調整】)
static var WALL_SLIDE_SPEED := 3.0    ## 壁に張り付いて滑り落ちる速さ
static var WALL_KICK_SPEED_X := 7.5   ## 壁キックで反対へ飛ぶ横速度
static var WALL_KICK_HEIGHT := 4.0    ## 壁キックの高さ
static var WALL_KICK_LOCK_FRAMES := 16    ## 壁キック直後に壁方向の入力を受け付けないフレーム数【TAS】

# ヒップドロップ・踏みつけ・しゃがみ【推測・調整】
static var GP_HOVER := 0.25           ## 空中で1回転して止まる時間
static var GP_SPEED := 24.0           ## 急降下の速さ
static var GP_LAND_STUN := 0.2        ## 着地後に動けない時間
static var STOMP_BOUNCE_LOW := 1.5    ## 踏んだときの跳ね返り(マス)
static var STOMP_BOUNCE_HIGH := 4.5   ## 踏んだ瞬間にジャンプを押していたとき
static var CROUCH_HEIGHT := 1.0       ## 大きい状態でしゃがんだときの高さ


static func velocity_for_height(h: float) -> float:
	return sqrt(2.0 * GRAVITY_UP * h)


static func jump_velocity(speed_x: float) -> float:
	var t := clampf(absf(speed_x) / RUN_SPEED, 0.0, 1.0)
	return velocity_for_height(STAND_JUMP_HEIGHT + (RUN_JUMP_HEIGHT - STAND_JUMP_HEIGHT) * t)

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
		"GRAVITY_UP":
			return GRAVITY_UP
		"GRAVITY_DOWN":
			return GRAVITY_DOWN
		"WALK_SPEED":
			return WALK_SPEED
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
		"GRAVITY_UP":
			GRAVITY_UP = v
		"GRAVITY_DOWN":
			GRAVITY_DOWN = v
		"WALK_SPEED":
			WALK_SPEED = v
