extends SceneTree
## キャラ候補を、ゲームと同じ縮尺(縦12マス)で横に並べて走らせ、連番PNGに書き出す。
##
## xvfb-run godot --path . --rendering-driver opengl3 -s res://tools/preview/compare_chars.gd -- \
##     --out=/abs/dir --height=1.8 /abs/a.gltf /abs/b.gltf ...

const FRAMES := 40

var _players: Array[AnimationPlayer] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out_dir := "/tmp/compare"
	var height := 1.8
	var files: Array[String] = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
		elif a.begins_with("--height="):
			height = float(a.trim_prefix("--height="))
		else:
			files.append(a)
	DirAccess.make_dir_recursive_absolute(out_dir)

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

	var ground := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(40, 1, 2)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.45, 0.75, 0.3)
	bm.material = gm
	ground.mesh = bm
	ground.position = Vector3(0, -0.5, 0)
	root.add_child(ground)

	var spacing := 20.0 / float(files.size() + 1)
	for i in files.size():
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_file(files[i], state) != OK:
			printerr("読み込めません: ", files[i])
			continue
		var n: Node3D = doc.generate_scene(state)
		root.add_child(n)
		var b := _bounds(n)
		n.scale *= height / maxf(b.size.y, 0.001)
		b = _bounds(n)
		n.position += Vector3(-10.0 + spacing * (i + 1) - b.get_center().x, -b.position.y, -b.get_center().z)
		n.rotation_degrees.y = 90.0
		_paint(n)
		var aps := n.find_children("*", "AnimationPlayer", true, false)
		if not aps.is_empty():
			var ap: AnimationPlayer = aps[0]
			var pick := ""
			for a in ap.get_animation_list():
				var s := String(a)
				if s.ends_with("Run") or s.ends_with("|Run"):
					pick = s
			if pick == "":
				for a in ap.get_animation_list():
					if "run" in String(a).to_lower():
						pick = String(a)
			print("%s: %s (全アニメ: %s)" % [files[i].get_file(), pick, ", ".join(ap.get_animation_list())])
			if pick != "":
				ap.get_animation(pick).loop_mode = Animation.LOOP_LINEAR
				ap.play(pick)
				ap.pause()
				_players.append(ap)

	var cam := Camera3D.new()
	cam.fov = 30.0
	root.add_child(cam)
	var dist := 6.0 / tan(deg_to_rad(15.0))
	cam.look_at_from_position(Vector3(0, 3.0, dist), Vector3(0, 3.0, 0))
	cam.current = true
	for i in 5:
		await process_frame
	for f in FRAMES:
		for ap in _players:
			ap.advance(1.0 / 20.0)
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png("%s/cmp_%03d.png" % [out_dir, f])
	quit()


## 素材の色が暗すぎるため、部品名ごとに色を付け直す(1P用の配色)
const PALETTE := {
	"Skin": Color(0.96, 0.78, 0.62),
	"Shirt": Color(0.2, 0.45, 0.95),
	"Main": Color(0.2, 0.45, 0.95),
	"Pants": Color(0.22, 0.24, 0.35),
	"Belt": Color(0.35, 0.22, 0.12),
	"Hair": Color(0.35, 0.2, 0.1),
	"Vest": Color(0.95, 0.6, 0.15),
	"Hat": Color(0.95, 0.85, 0.3),
	"Details": Color(0.85, 0.9, 1.0),
	"Grey": Color(0.55, 0.55, 0.6),
}


func _paint(n: Node) -> void:
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s)
			if mat is BaseMaterial3D and PALETTE.has(mat.resource_name):
				var dup: BaseMaterial3D = mat.duplicate()
				dup.albedo_color = PALETTE[mat.resource_name]
				mi.set_surface_override_material(s, dup)


func _bounds(node: Node) -> AABB:
	var box := AABB()
	var first := true
	for m in node.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = m.global_transform * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box
