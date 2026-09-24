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
	"  P                ooo CC ooo                P  ",
	"  P  S            E   CCCC   E     E      T  P  ",
	"###################  ######  ###################",
]
const SOLID := "#B?CP"
const WRAP_COPY := 14   ## ループの継ぎ目が見えるよう、端から何列を反対側にも複製するか

signal coin_taken(coin: Node3D)

var width := 0
var height := 0
var star_points: Array[Vector3] = []
var spawns: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var pipe_tops: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
## CPUが段差を登るときの足場(表面の中央)
var ledges: Array[Vector3] = []

var coins: Array[Node3D] = []
var enemies: Array[Walker] = []
var _used_blocks := {}
var _block_nodes := {}


func _ready() -> void:
	height = MAP.size()
	width = MAP[0].length()
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
	for i in 2:
		var px := pipe_x[i]
		var top := 0
		while tile(px, top) == "P" or tile(px, top) == "#":
			top += 1
		pipe_tops[i] = Vector3(px + 0.5, top, 0)

	for offset in [-width, 0, width]:
		_build_terrain(offset)
	_build_colliders()
	_build_background()
	reset()


## 地図の文字。範囲外は空白、左右はループ
func tile(x: int, y: int) -> String:
	if y < 0 or y >= height:
		return " "
	return MAP[height - 1 - y][posmod(x, width)]


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
			if offset < 0 and x < width - WRAP_COPY:
				continue
			if offset > 0 and x >= WRAP_COPY:
				continue
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
	for x in pipes:
		var h := 0
		while tile(x, pipes[x] + h) == "P":
			h += 1
		_deco(Assets.PIPE, Vector3(x + offset + 0.5, pipes[x], 0), float(h))
	# 地面の下の土(見た目だけの大きな箱)
	var dirt := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(width, 6, 3)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.72, 0.45, 0.3)
	bm.material = mat
	dirt.mesh = bm
	dirt.position = Vector3(offset + width * 0.5, -4.0, -0.2)
	add_child(dirt)


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
	return n
