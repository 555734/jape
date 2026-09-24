class_name Grassland
extends Node3D
## 草原ステージの見た目(横64×縦14マス、左右ループ)。構成の数は docs/RULES.md §8【FAQ】、地形は独自。
## 地図と当たり判定は StageMap、コイン・敵・?ブロックの状態は Simulation が持ち、ここはそれを映すだけ。

var map: StageMap
var sim: Simulation

var width: int:
	get:
		return map.width
var height: int:
	get:
		return map.height

var _wrap_nodes: Array[Node3D] = []
var _dirt: MeshInstance3D
var _coins: Array[Node3D] = []
var _enemies: Array[Walker] = []
var _block_nodes := {}


func _ready() -> void:
	_build_terrain(0)   # 見た目は1周分だけ。毎フレーム wrap_visuals() でカメラの近くへ置き直す
	_build_background()
	for pos in map.coin_spots:
		var c := Assets.spawn(Assets.COIN, 0.7)
		c.position = pos
		c.set_meta("lx", pos.x)
		add_child(c)
		_coins.append(c)
	for e in sim.enemies:
		var w := Walker.new()
		w.sim = e
		add_child(w)
		_enemies.append(w)


func tile(x: int, y: int) -> String:
	return map.tile(x, y)


## Simulation の状態を映す(毎フレーム)
func sync(delta: float) -> void:
	for i in _coins.size():
		_coins[i].visible = sim.coins_alive[i]
		_coins[i].rotate_y(delta * 3.0)
	for w in _enemies:
		w.sync()
	for key in _block_nodes:
		var used := sim.is_block_used(key.x, key.y)
		for pair in _block_nodes[key]:
			pair[0].visible = not used
			pair[1].visible = used


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
	for g in StageMap.pipe_groups(xs):
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


func _build_background() -> void:
	for i in int(width / 7.0):
		_deco(Assets.CLOUD, Vector3(3 + i * 7, 11.0 + (i % 2), -6), 1.5)
	for i in int(width / 8.0):
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


## 左右ループの見た目: すべての部品をカメラに一番近い周回位置へ置き直す。
## 画面の幅(約18〜22マス)はステージ(48マス)より狭いので、同じ物が2つ見えることはない。
func wrap_visuals(cam_x: float) -> void:
	for n in _wrap_nodes:
		n.position.x = map.image_x(n.get_meta("lx"), cam_x)
	for c in _coins:
		c.position.x = map.image_x(c.get_meta("lx"), cam_x)
	for e in _enemies:
		e.set_view_shift(map.image_x(e.position.x, cam_x) - e.position.x)
	if _dirt:
		_dirt.position.x = cam_x
