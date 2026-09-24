class_name StageMap
extends RefCounted
## ステージの地図と当たり判定(画面に依存しない)。Simulation と CPU と画面表示(Grassland)が共有する。
## 1文字=1マス、一番下の行が y=0。
##   # 地面  B レンガ  ? ?ブロック  C 木箱  P 土管  o コイン  E 敵
##   1〜6 スター候補地点  S 1Pの登場位置  T 2Pの登場位置
##
## 当たり判定は Godot の物理を使わず、ここで箱とマスの重なりを直接調べる。
## 通信対戦(ロールバック)では2台の端末が同じ入力から完全に同じ結果を出す必要があるため、
## 計算は GDScript の実数(倍精度)の四則演算だけで行う。

const GRASSLAND := [
	"                                                                ",
	"                                                                ",
	"                                                                ",
	"         2                                            3         ",
	"        CCCC                                        CCCC        ",
	"              ooo                                               ",
	"               4               6                5               ",
	"             CCCCC                            CCCCC             ",
	"                                                                ",
	"                                                                ",
	"        B?BB                   1                    BB?B        ",
	"  PP                       ooo CC ooo                       PP  ",
	"  PP S            E          ECCCC           E            T PP  ",
	"#######################  ##############  #######################",
]
## 動き確認用の練習ステージ(平らな地面と、壁キック用の高い壁)
const PRACTICE := [
	"                                                                                ",
	"                                                                                ",
	"                                                                                ",
	"                                                                  CC            ",
	"                                                                  CC            ",
	"                                    3                             CC            ",
	"                                                                  CC            ",
	"                        2                                         CC    6       ",
	"                                                4                 CC            ",
	"                                                                  CC            ",
	"            1                                               5     CC            ",
	"  PP                                                              CC        PP  ",
	"  PP S                                                            CC      T PP  ",
	"################################################################################",
]
const SOLID := "#B?CP"
const EPS := 0.0001      ## 境目ちょうどに接している面を「重なり」と数えないための余白
const PROBE := 0.002     ## 止まっていても足元の床を見つけるため、下向きに少しだけ探る

var map: Array
var width := 0
var height := 0
var star_points: Array[Vector3] = []
var spawns: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var pipe_tops: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
## CPUが段差を登るときの足場(表面の中央)
var ledges: Array[Vector3] = []
## コインと敵の最初の位置(ステージを元に戻すときに使う)
var coin_spots: Array[Vector3] = []
var enemy_spots: Array[Vector3] = []


func _init(p_map: Array = GRASSLAND) -> void:
	map = p_map
	height = map.size()
	width = map[0].length()
	star_points.resize(6)
	var pipe_x: Array[int] = []
	for y in height:
		for x in width:
			var c := tile(x, y)
			match c:
				"1", "2", "3", "4", "5", "6":
					star_points[int(c) - 1] = Vector3(x + 0.5, y + 0.2, 0)
				"S":
					spawns[0] = Vector3(x + 0.5, y, 0)
				"T":
					spawns[1] = Vector3(x + 0.5, y, 0)
				"P":
					if not pipe_x.has(x):
						pipe_x.append(x)
				"o":
					coin_spots.append(Vector3(x + 0.5, y + 0.15, 0))
				"E":
					enemy_spots.append(Vector3(x + 0.5, y, 0))
			if SOLID.contains(c) and c != "P" and not SOLID.contains(tile(x, y + 1)):
				ledges.append(Vector3(x + 0.5, y + 1, 0))
	pipe_x.sort()
	var groups := pipe_groups(pipe_x)
	for i in mini(2, groups.size()):
		var g: Array = groups[i]
		var top := 0
		while tile(g[0], top) == "P" or tile(g[0], top) == "#":
			top += 1
		pipe_tops[i] = Vector3((g[0] + g[g.size() - 1] + 1) * 0.5, top, 0)


## 地図の文字。範囲外は空白、左右はループ
func tile(x: int, y: int) -> String:
	if y < 0 or y >= height:
		return " "
	return map[height - 1 - y][posmod(x, width)]


func is_solid(x: int, y: int) -> bool:
	return SOLID.contains(tile(x, y))


## その位置の真下(depth マス以内)に足場があるか。穴の上なら false
func has_floor_below(pos: Vector3, depth := 4) -> bool:
	var x := int(floor(pos.x))
	for y in range(int(floor(pos.y)), int(floor(pos.y)) - depth - 1, -1):
		if is_solid(x, y):
			return true
	return false


## 左右ループ: x を 0〜width に収める
func wrap_x(x: float) -> float:
	return fposmod(x, float(width))


## a から b への最短の横方向の差(ループを考慮)
func delta_x(a: float, b: float) -> float:
	return fposmod(b - a + width * 0.5, float(width)) - width * 0.5


## 本来の横位置 lx の物を、カメラ(cam_x)に一番近い周回位置に置いたときの x
func image_x(lx: float, cam_x: float) -> float:
	return lx + roundf((cam_x - lx) / width) * width


## 隣り合う列の土管を1本にまとめる
static func pipe_groups(xs: Array) -> Array:
	var groups := []
	for x in xs:
		if not groups.is_empty() and groups[-1][-1] == x - 1:
			groups[-1].append(x)
		else:
			groups.append([x])
	return groups


## 箱(足元の中心 x・下端 y・幅 w・高さ h)を横に dx、縦に dy 動かす。横→縦の順に、マスに当たったら止める。
## 戻り値 [x, y, 横の当たり(1=右の壁 -1=左の壁 0=なし), 縦の当たり(-1=着地 1=天井 0=なし)]
## x はループさせないので、呼び出し側で wrap_x() する。
func move_box(x: float, y: float, w: float, h: float, dx: float, dy: float) -> Array:
	var hw := w * 0.5
	var hit_x := 0
	var r0 := floori(y + EPS)
	var r1 := ceili(y + h - EPS) - 1
	if dx > 0.0:
		for c in range(ceili(x + hw - EPS), ceili(x + hw + dx)):
			if _column_solid(c, r0, r1):
				dx = float(c) - (x + hw)
				hit_x = 1
				break
	elif dx < 0.0:
		for c in range(floori(x - hw + EPS) - 1, floori(x - hw + dx) - 1, -1):
			if _column_solid(c, r0, r1):
				dx = float(c + 1) - (x - hw)
				hit_x = -1
				break
	x += dx

	var hit_y := 0
	var c0 := floori(x - hw + EPS)
	var c1 := ceili(x + hw - EPS) - 1
	if dy > 0.0:
		for r in range(ceili(y + h - EPS), ceili(y + h + dy)):
			if _row_solid(c0, c1, r):
				dy = float(r) - (y + h)
				hit_y = 1
				break
	else:
		for r in range(floori(y + EPS) - 1, floori(y + dy - PROBE) - 1, -1):
			if _row_solid(c0, c1, r):
				dy = float(r + 1) - y
				hit_y = -1
				break
	y += dy
	return [x, y, hit_x, hit_y]


func _column_solid(c: int, r0: int, r1: int) -> bool:
	for r in range(r0, r1 + 1):
		if is_solid(c, r):
			return true
	return false


func _row_solid(c0: int, c1: int, r: int) -> bool:
	for c in range(c0, c1 + 1):
		if is_solid(c, r):
			return true
	return false
