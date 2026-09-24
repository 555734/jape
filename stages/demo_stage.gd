class_name DemoStage
extends Node3D
## 動作確認用のステージ。文字の地形図から組み立てる(1文字=1マス、一番下の行がY=0)。
##   # 地面(下に土が2段付く)  B レンガ  ? ?ブロック  C 木箱  P 土管(縦に並べた分の高さ)
##   o コイン  * スター  E 敵(置物)  S スタート地点

signal coin_collected
signal star_collected

const MAP := [
	"                                            ",
	"                                            ",
	"           *                                ",
	"                                            ",
	"       B?BB             o o o               ",
	"                                            ",
	"                                  C         ",
	"   P                     ooo     CC      P  ",
	"   P   S      E                 CCC   E  P  ",
	"##################   #######################",
]

var spawn := Vector3.ZERO
var width := 0


func _ready() -> void:
	width = MAP[0].length()
	var rows := MAP.size()
	var pipes := {}
	for r in rows:
		var y := rows - 1 - r
		var line: String = MAP[r]
		for x in line.length():
			var c := line[x]
			var pos := Vector3(x, y, 0)
			match c:
				"#":
					_solid(Assets.GRASS, pos)
					_deco(Assets.DIRT, pos + Vector3(0, -1, 0), 1.0)
					_deco(Assets.DIRT, pos + Vector3(0, -2, 0), 1.0)
				"B":
					_solid(Assets.BRICK, pos)
				"?":
					_solid(Assets.QUESTION, pos)
				"C":
					_solid(Assets.CRATE, pos)
				"P":
					_collider(pos)
					pipes[x] = mini(pipes.get(x, y), y)
				"o":
					_pickup(Assets.COIN, pos + Vector3(0.5, 0.15, 0), 0.7, coin_collected)
				"*":
					_pickup(Assets.STAR, pos + Vector3(0.5, 0.0, 0), 1.2, star_collected)
				"E":
					var e := _deco(Assets.ENEMY, pos + Vector3(0.5, 0, 0), 1.0)
					e.rotation_degrees.y = -90
					_loop_anim(e, "Walk")
				"S":
					spawn = pos + Vector3(0.5, 0, 0)
	for x in pipes:
		var h := 0
		for r in rows:
			if MAP[r][x] == "P":
				h += 1
		_deco(Assets.PIPE, Vector3(x + 0.5, pipes[x], 0), float(h))
	# 背景の飾り
	for i in 6:
		_deco(Assets.CLOUD, Vector3(4 + i * 8, 8.5 + (i % 2), -6), 1.5)
	for i in 5:
		_deco(Assets.TREE, Vector3(2 + i * 9, 1, -3), 3.0)


## 見た目+当たり判定のある1マスのブロック
func _solid(path: String, pos: Vector3) -> void:
	_deco(path, pos, 1.0)
	_collider(pos)


func _collider(pos: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1, 1, 1)
	shape.shape = box
	body.add_child(shape)
	body.position = pos + Vector3(0.5, 0.5, 0)
	add_child(body)


## 見た目だけ。pos はマスの左下(x)と下端(y)。x に 0.5 を足していない場合はマス中央に寄せる
func _deco(path: String, pos: Vector3, height: float) -> Node3D:
	var n := Assets.spawn(path, height)
	n.position = pos if fmod(pos.x, 1.0) != 0.0 else pos + Vector3(0.5, 0, 0)
	add_child(n)
	return n


func _pickup(path: String, pos: Vector3, size: float, on_take: Signal) -> void:
	var area := Area3D.new()
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = size * 0.5
	shape.shape = sphere
	shape.position.y = size * 0.5
	area.add_child(shape)
	var model := Assets.spawn(path, size)
	area.add_child(model)
	area.position = pos
	area.set_meta("spin", model)
	area.body_entered.connect(func(body: Node3D) -> void:
		if body is Player:
			on_take.emit()
			area.queue_free())
	add_child(area)


func _loop_anim(n: Node3D, suffix: String) -> void:
	var ap := Assets.find_anim_player(n)
	if ap == null:
		return
	var a := Assets.anim_name(ap, suffix)
	if a != &"":
		ap.get_animation(a).loop_mode = Animation.LOOP_LINEAR
		ap.play(a)


func _process(delta: float) -> void:
	for child in get_children():
		if child is Area3D and child.has_meta("spin"):
			(child.get_meta("spin") as Node3D).rotate_y(delta * 3.0)
