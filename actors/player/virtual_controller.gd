class_name VirtualController
extends RefCounted
## DS互換の仮想コントローラ。物理に渡る前に、すべての入力をここでデジタル信号に量子化する。
##
##   タッチ(スティック/ボタン) ・ キーボード ・ ゲームパッド ・ CPU
##            ↓  ここで量子化(左右は -1 / 0 / +1、ダッシュは ON/OFF)
##   PlayerInput → Simulation(60Hz 固定)
##
## 原作(New Super Mario Bros. DS)はデジタル十字キー + ダッシュボタンなので、
## 傾き具合で速さが変わる仕組みは持たない。速度の段は「今の速度」から決まる(Tuning.speed_stage)。
##
## **スマホだからという理由の物理補正は入れない。**
## ジャンプを高くする・重力を弱める・ダッシュを遅くするといった調整をここでも物理側でも行わない。
## どの入力機器でも同じ物理になることがこの層の役目。

## スティックをこの割合より倒したら「左右キーを押した」とみなす
const MOVE_THRESHOLD := 0.22


## 生のアナログ値をDSの十字キー相当に落とす
static func digital_axis(value: float) -> float:
	if value <= -MOVE_THRESHOLD:
		return -1.0
	if value >= MOVE_THRESHOLD:
		return 1.0
	return 0.0
