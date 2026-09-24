extends SceneTree
## 3Dキャラの見た目確認用。glb を読み込み、連番PNGを書き出す。
##
## xvfb-run godot --path . --rendering-driver opengl3 -s res://tools/preview/preview.gd -- \
##     --model=/abs/path/model.glb --out=/abs/out/dir --mode=turntable|ingame|anim
##
## turntable: 360度回転(36枚)
## ingame:    ゲーム画面(横21×縦12マス)に大きい状態(1.8マス)と小さい状態(0.9マス)で配置
## anim:      glb内の全アニメを横から撮影(20fps、各最大3秒)

const TILE := 1.0
const VIEW_TILES_Y := 12.0

var args := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	_run.call_deferred()


func _run() -> void:
	var out_dir: String = args.get("out", "/tmp/preview")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var model := _load_glb(args["model"])
	if model == null:
		printerr("glb を読み込めません: ", args["model"])
		quit(1)
		return
	root.add_child(model)
	_add_light()
	var mode: String = args.get("mode", "turntable")
	match mode:
		"turntable":
			await _turntable(model, out_dir)
		"ingame":
			await _ingame(model, out_dir)
		"anim":
			await _anim(model, out_dir)
	_report(model)
	quit()


func _load_glb(path: String) -> Node3D:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		return null
	return doc.generate_scene(state)


func _add_light() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	root.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.78, 0.98)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.8, 0.85)
	root.add_child(env)


## モデル全体の外接箱(スキンメッシュも含む)
func _bounds(node: Node) -> AABB:
	var box := AABB()
	var first := true
	for m in node.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = m.global_transform * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


## 足元を原点に置き、高さを height マスにそろえる
func _fit(model: Node3D, height: float) -> void:
	var b := _bounds(model)
	var s: float = height / maxf(b.size.y, 0.001)
	model.scale *= s
	b = _bounds(model)
	model.position -= Vector3(b.get_center().x, b.position.y, b.get_center().z)


func _camera(pos: Vector3, target: Vector3, fov := 30.0) -> Camera3D:
	var cam := Camera3D.new()
	cam.fov = fov
	root.add_child(cam)
	cam.look_at_from_position(pos, target)
	cam.current = true
	return cam


func _snap(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(path)


func _turntable(model: Node3D, out_dir: String) -> void:
	_fit(model, 1.8)
	_play_first_anim(model, "idle")
	var cam := _camera(Vector3(0, 1.0, 4.2), Vector3(0, 0.9, 0))
	for i in 36:
		model.rotation_degrees.y = i * 10.0
		await _snap("%s/turn_%03d.png" % [out_dir, i])


func _ingame(model: Node3D, out_dir: String) -> void:
	_fit(model, 1.8)
	model.position.x = -2.0
	model.rotation_degrees.y = 90.0
	var small := model.duplicate() as Node3D
	root.add_child(small)
	_fit(small, 0.9)
	small.position.x = 2.0
	small.rotation_degrees.y = 90.0
	# 地面(2マス厚)と目安のブロック
	var ground := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(40, 2, 2)
	ground.mesh = bm
	ground.position = Vector3(0, -1, 0)
	root.add_child(ground)
	for x in [-6, -5, 5, 6]:
		var blk := MeshInstance3D.new()
		var m := BoxMesh.new()
		m.size = Vector3.ONE * 0.95
		blk.mesh = m
		blk.position = Vector3(x, 3.5, 0)
		root.add_child(blk)
	# 縦12マスが収まる距離に置いたカメラ
	var fov := 30.0
	var dist := (VIEW_TILES_Y * 0.5) / tan(deg_to_rad(fov * 0.5))
	_camera(Vector3(0, 4.5, dist), Vector3(0, 4.5, 0), fov)
	for i in 20:
		await process_frame
	await _snap("%s/ingame.png" % out_dir)


func _anim(model: Node3D, out_dir: String) -> void:
	_fit(model, 1.8)
	model.rotation_degrees.y = 90.0
	_camera(Vector3(0, 1.0, 4.2), Vector3(0, 0.9, 0))
	var player := model.find_children("*", "AnimationPlayer", true, false)
	if player.is_empty():
		print("アニメーションがありません")
		return
	var ap: AnimationPlayer = player[0]
	for name in ap.get_animation_list():
		var anim := ap.get_animation(name)
		anim.loop_mode = Animation.LOOP_NONE
		var frames := int(minf(anim.length, 3.0) * 20.0)
		ap.play(name)
		ap.pause()
		var safe := String(name).validate_filename()
		for i in frames:
			ap.seek(i / 20.0, true)
			await _snap("%s/anim_%s_%03d.png" % [out_dir, safe, i])


func _play_first_anim(model: Node3D, prefer: String) -> void:
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		return
	var ap: AnimationPlayer = players[0]
	var list := ap.get_animation_list()
	if list.is_empty():
		return
	var pick: String = list[0]
	for n in list:
		if prefer in String(n).to_lower():
			pick = n
	ap.play(pick)


func _report(model: Node3D) -> void:
	var tris := 0
	var tex := {}
	for m in model.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = m.mesh
		for s in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(s)
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			tris += (idx.size() if idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
			var mat := mesh.surface_get_material(s)
			if mat is BaseMaterial3D and mat.albedo_texture:
				var t: Texture2D = mat.albedo_texture
				tex["%dx%d" % [t.get_width(), t.get_height()]] = true
	var skel := model.find_children("*", "Skeleton3D", true, false)
	var bones: int = skel[0].get_bone_count() if not skel.is_empty() else 0
	print("REPORT triangles=%d textures=%s bones=%d" % [tris, ",".join(tex.keys()), bones])
