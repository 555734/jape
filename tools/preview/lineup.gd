extends SceneTree
## 素材を実際のゲーム画面の縮尺(縦12マス)で並べた見本を撮る。
##
## xvfb-run godot --path . --rendering-driver opengl3 -s res://tools/preview/lineup.gd -- --out=/abs/out/dir

const Q := "res://assets/third_party/quaternius_platformer/"
const FRAMES := 30

var players: Array[AnimationPlayer] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out_dir := "/tmp/lineup"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_env()

	# 地面: 草ブロック1段+土2段、中央に2マスの穴
	for x in range(-11, 12):
		if x == 3 or x == 4:
			continue
		_place("Cubes/glTF/Cube_Grass_Single.gltf", Vector3(x, -0.5, 0), 1.0)
		_place("Cubes/glTF/Cube_Dirt_Single.gltf", Vector3(x, -1.5, 0), 1.0)
		_place("Cubes/glTF/Cube_Dirt_Single.gltf", Vector3(x, -2.5, 0), 1.0)
	# ブロック列(レンガ・?ブロック)
	for x in [-6, -4, -3]:
		_place("Cubes/glTF/Cube_Bricks.gltf", Vector3(x, 3.5, 0), 1.0)
	_place("Cubes/glTF/Cube_Question.gltf", Vector3(-5, 3.5, 0), 1.0)
	# 高台(階段状)
	for i in 3:
		for y in i + 1:
			_place("Cubes/glTF/Cube_Crate.gltf", Vector3(7 + i, 0.5 + y, 0), 1.0)
	# 土管
	_place("Level and Mechanics/glTF/Pipe_End.gltf", Vector3(-9, 1.0, 0), 2.0)
	# コイン・スター
	for x in [0, 1, 2]:
		_spin(_place("Powerups and Pickups/glTF/Coin.gltf", Vector3(x, 2.5, 0), 0.7))
	_spin(_place("Powerups and Pickups/glTF/Star.gltf", Vector3(-4.5, 6.2, 0), 1.2))
	# プレイヤー(1Pは元の色、2Pは色違い)。大きい状態=1.8マス
	var p1 := _place("Character/glTF/Character.gltf", Vector3(-1.5, 0, 0), 1.8, 90)
	_anim(p1, "Run")
	var p2 := _place("Character/glTF/Character.gltf", Vector3(5.5, 0, 0), 1.8, -90)
	_recolor(p2, 0.45)
	_anim(p2, "Idle")
	# 敵
	_anim(_place("Enemies/glTF/Enemy.gltf", Vector3(-7, 0, 0), 1.0, 90), "Walk")
	_anim(_place("Enemies/glTF/Crab.gltf", Vector3(9, 3, 0), 1.0, -90), "Walk")
	_anim(_place("Enemies/glTF/Bee.gltf", Vector3(2, 5, 0), 1.0, -90), "Flying")

	var cam := Camera3D.new()
	cam.fov = 30.0
	root.add_child(cam)
	var dist := 6.0 / tan(deg_to_rad(15.0))
	cam.look_at_from_position(Vector3(0, 4.0, dist), Vector3(0, 4.0, 0))
	cam.current = true

	for i in 10:
		await process_frame
	for i in FRAMES:
		for ap in players:
			ap.advance(1.0 / 20.0)
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png("%s/lineup_%03d.png" % [out_dir, i])
	quit()


func _env() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -25, 0)
	root.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.78, 0.98)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.75, 0.8)
	root.add_child(env)


## glTFを読み込み、高さを height マスにそろえ、足元(下端)を pos に置く
func _place(path: String, pos: Vector3, height: float, yaw := 0.0) -> Node3D:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	doc.append_from_file(ProjectSettings.globalize_path(Q + path), state)
	var n: Node3D = doc.generate_scene(state)
	root.add_child(n)
	var b := _bounds(n)
	n.scale *= height / maxf(b.size.y, 0.001)
	n.rotation_degrees.y = yaw
	b = _bounds(n)
	n.position += pos - Vector3(b.get_center().x, b.position.y, b.get_center().z)
	if height == 1.0 and path.begins_with("Cubes"):
		n.position.y -= 0.5
	return n


func _bounds(node: Node) -> AABB:
	var box := AABB()
	var first := true
	for m in node.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = m.global_transform * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _anim(n: Node3D, name: String) -> void:
	var aps := n.find_children("*", "AnimationPlayer", true, false)
	if aps.is_empty():
		return
	var ap: AnimationPlayer = aps[0]
	for a in ap.get_animation_list():
		if String(a).ends_with(name):
			ap.get_animation(a).loop_mode = Animation.LOOP_LINEAR
			ap.play(a)
			ap.pause()
			players.append(ap)
			return


func _spin(n: Node3D) -> void:
	n.rotation_degrees.y = 25.0


## 2P用: 全マテリアルの色相をずらす
func _recolor(n: Node3D, hue_shift: float) -> void:
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = m.mesh
		for s in mesh.get_surface_count():
			var mat := mesh.surface_get_material(s)
			if mat is BaseMaterial3D:
				var c: Color = mat.albedo_color
				if c.s < 0.3:
					continue
				var dup: BaseMaterial3D = mat.duplicate()
				dup.albedo_color = Color.from_hsv(fposmod(c.h + hue_shift, 1.0), c.s, c.v, c.a)
				m.set_surface_override_material(s, dup)
