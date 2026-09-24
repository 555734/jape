class_name Tuning
## 動きの数値。単位はマス(=1m)と秒。根拠は docs/RULES.md の「3. 動きの数値」。

const WALK_SPEED := 5.6          ## 動画実測
const RUN_SPEED := 11.3          ## 動画実測
const WALK_ACCEL := WALK_SPEED / 0.4   ## 0.4秒で最高速【決定・調整】
const RUN_ACCEL := RUN_SPEED / 0.4
const STOP_DECEL := WALK_SPEED / 0.2   ## 0.2秒で停止【決定・調整】

const GRAVITY_UP := 27.8         ## 上昇0.6秒・高さ5マスから計算
const GRAVITY_DOWN := 49.0       ## 落下0.45秒から計算
const GRAVITY_CUT := 80.0        ## 上昇中にボタンを離したとき(低いジャンプ)【決定・調整】
const MAX_FALL := 24.0           ## 5マスを0.45秒で落ちると終速約22マス/秒。それより大きくする【決定・調整】

const RUN_JUMP_HEIGHT := 5.0     ## 動画実測(±1マス)
const STAND_JUMP_HEIGHT := 4.0   ## 【決定・調整】


static func jump_velocity(speed_x: float) -> float:
	var t := clampf(absf(speed_x) / RUN_SPEED, 0.0, 1.0)
	var h := lerpf(STAND_JUMP_HEIGHT, RUN_JUMP_HEIGHT, t)
	return sqrt(2.0 * GRAVITY_UP * h)
