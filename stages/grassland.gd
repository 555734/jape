class_name Grassland
extends Node3D
## 草原ステージ(横48×縦14マス、左右ループ)。構成の数は docs/RULES.md §8【FAQ】、地形は独自。
## 1文字=1マス、一番下の行が y=0。
##   # 地面  B レンガ  ? ?ブロック  C 木箱  P 土管  o コイン  E 敵
##   1〜6 スター候補地点  S 1Pの登場位置  T 2Pの登場位置

const MAP := [
	"                                                ",
	"                                                ",
	"                                                ",
	"         2                            3         ",
	"        CCCC                        CCCC        ",
	"              ooo                               ",
	"               4        6       5               ",
	"             CCCCC            CCCCC             ",
	"                                                ",
	"                                                ",
	"        B?BB            1           BB?B        ",
	"  PP               ooo CC ooo               PP  ",
	"  PP S            E   CCCC   E     E      T PP  ",
	"###################  ######  ###################",
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

signal coin_taken(coin: Node3D)

var map: Array = MAP        ## 使う地図(練習ステージに差し替え可)

var width := 0
var height := 0
var star_points: Array[Vector3] = []
var spawns: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var pipe_tops: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
## CPUが段差を登るときの足場(表面の中央)
var ledges: Array[Vector3] = []

var coins: Array[Node3D] = []
var _wrap_nodes: Array[Node3D] = []
var _dirt: MeshInstance3D
var enemies: Array[Walker] = []
var _used_blocks := {}
var _block_nodes := {}


func _ready() -> void:
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
			if SOLID.contains(c) and c != "P" and not SOLID.contains(tile(x, y + 1)):
				ledges.append(Vector3(x + 0.5, y + 1, 0))
	pipe_x.sort()
	var groups := _pipe_groups(pipe_x)
	for i in 2:
		var g: Array = groups[i]
		var top := 0
		while tile(g[0], top) == "P" or tile(g[0], top) == "#":
			top += 1
		pipe_tops[i] = Vector3((g[0] + g[g.size() - 1] + 1) * 0.5, top, 0)

	_build_terrain(0)   # 見た目は1周分だけ。毎フレーム wrap_visuals() でカメラの近くへ置き直す
	_build_colliders()  # 当たり判定は3周分並べる
	_build_background()
	reset()


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
	var d := fposmod(b - a + width * 0.5, float(width)) - width * 0.5
	return d


## ステージを元に戻す(スター取得時: 敵・コイン・?ブロック)§4【FAQ】
func reset() -> void:
	for c in coins:
		c.queue_free()
	coins.clear()
	for e in enemies:
		e.queue_free()
	enemies.clear()
	_used_blocks.clear()
	for key in _block_nodes:
		for pair in _block_nodes[key]:
			pair[0].visible = true
			pair[1].visible = false
	for y in height:
		for x in width:
			match tile(x, y):
				"o":
					var c := Assets.spawn(Assets.COIN, 0.7)
					c.position = Vector3(x + 0.5, y + 0.15, 0)
					c.set_meta("lx", c.position.x)
					add_child(c)
					coins.append(c)
				"E":
					var e := Walker.new()
					e.stage = self
					e.position = Vector3(x + 0.5, y, 0)
					add_child(e)
					enemies.append(e)


## ?ブロックを下から叩いた。コインが出たら true
func bump_block(x: int, y: int) -> bool:
	var key := Vector2i(posmod(x, width), y)
	if tile(x, y) != "?" or _used_blocks.has(key):
		return false
	_used_blocks[key] = true
	for pair in _block_nodes.get(key, []):
		pair[0].visible = false
		pair[1].visible = true
	return true


func _process(delta: float) -> void:
	for c in coins:
		c.rotate_y(delta * 3.0)


func _build_terrain(offset: int) -> void:
	var pipes := {}
	for y in height:
		for x in width:
			var pos := Vector3(x + offset + 0.5, y, 0)
			match tile(x, y):
				"#":
					_deco(Assets.GRASS, pos, 1.0)
					_deco(Assets.DIRT, pos - Vector3(0, 1, 0), 1.0)
				"B":
					_deco(Assets.BRICK, pos, 1.0)
				"?":
					var q := _deco(Assets.QUESTION, pos, 1.0)
					var used := _deco(Assets.CRATE, pos, 1.0)
					used.visible = false
					var key := Vector2i(x, y)
					if not _block_nodes.has(key):
						_block_nodes[key] = []
					_block_nodes[key].append([q, used])
				"C":
					_deco(Assets.CRATE, pos, 1.0)
				"P":
					if not pipes.has(x):
						pipes[x] = y
	var xs: Array = pipes.keys()
	xs.sort()
	for g in _pipe_groups(xs):
		var x0: int = g[0]
		var h := 0
		while tile(x0, pipes[x0] + h) == "P":
			h += 1
		var w := float(g.size())   # 原作の土管は幅2マス【動画】。地図でも2列にしている
		var pipe := Assets.spawn_box(Assets.PIPE, w, float(h))
		pipe.position = Vector3(x0 + offset + w * 0.5, pipes[x0], 0)
		add_child(pipe)
		_register(pipe)
	# 地面の下の土(見た目だけの大きな箱)
	var dirt := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(width, 6, 3)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.72, 0.45, 0.3)
	bm.material = mat
	dirt.mesh = bm
	bm.size = Vector3(80, 6, 3)   # 画面より広い。カメラに合わせて横に動かす
	dirt.position = Vector3(0, -4.0, -0.2)
	add_child(dirt)
	_dirt = dirt


## 隣り合う列の土管を1本にまとめる
func _pipe_groups(xs: Array) -> Array:
	var groups := []
	for x in xs:
		if not groups.is_empty() and groups[-1][-1] == x - 1:
			groups[-1].append(x)
		else:
			groups.append([x])
	return groups


## 当たり判定: 横に連続するブロックを1つの箱にまとめる(継ぎ目で引っかからないように)
func _build_colliders() -> void:
	for offset in [-width, 0, width]:
		for y in height:
			var x := 0
			while x < width:
				if not is_solid(x, y):
					x += 1
					continue
				var start := x
				while x < width and is_solid(x, y):
					x += 1
				var body := StaticBody3D.new()
				var shape := CollisionShape3D.new()
				var box := BoxShape3D.new()
				box.size = Vector3(x - start, 1, 2)
				shape.shape = box
				body.add_child(shape)
				body.position = Vector3(offset + (start + x) * 0.5, y + 0.5, 0)
				add_child(body)


func _build_background() -> void:
	for i in 7:
		_deco(Assets.CLOUD, Vector3(3 + i * 7, 11.0 + (i % 2), -6), 1.5)
	for i in 6:
		var t := _deco(Assets.TREE, Vector3(1 + i * 8, 1, -3), 3.0)
		t.rotation_degrees.y = i * 40


func _deco(path: String, pos: Vector3, h: float) -> Node3D:
	var n := Assets.spawn(path, h)
	n.position = pos
	add_child(n)
	_register(n)
	return n


## ループ表示の対象にする(本来の横位置を覚えておく)
func _register(n: Node3D) -> void:
	n.set_meta("lx", n.position.x)
	_wrap_nodes.append(n)


## 本来の横位置 lx の物を、カメラ(cam_x)に一番近い周回位置に置いたときの x
func image_x(lx: float, cam_x: float) -> float:
	return lx + roundf((cam_x - lx) / width) * width


## 左右ループの見た目: すべての部品をカメラに一番近い周回位置へ置き直す。
## 画面の幅(約18〜22マス)はステージ(48マス)より狭いので、同じ物が2つ見えることはない。
func wrap_visuals(cam_x: float) -> void:
	for n in _wrap_nodes:
		n.position.x = image_x(n.get_meta("lx"), cam_x)
	for c in coins:
		c.position.x = image_x(c.get_meta("lx"), cam_x)
	for e in enemies:
		e.set_view_shift(image_x(e.position.x, cam_x) - e.position.x)
	if _dirt:
		_dirt.position.x = cam_x
