extends SceneTree
## 新キャラクターの小・大状態を並べて撮影する確認用スクリプト。
## godot --path . --rendering-driver opengl3 -s res://tools/preview/hero_avatar_preview.gd


func _initialize() -> void:
	_render.call_deferred()


func _render() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("8bc8e5")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("b8cad5")
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -28, -22)
	sun.light_energy = 0.8
	world.add_child(sun)
	for i in 4:
		var model := HeroAvatar.new(i % 2)
		model.position = Vector3(-1.95 + i * 1.3, 0, 0)
		model.rotation_degrees.y = 52 if i % 2 == 0 else -52
		model.scale = Vector3.ONE * (1.15 / 1.8 if i < 2 else 1.0)
		world.add_child(model)
		model.pose(PlayerMoves.State.NORMAL, true, 0.0 if i % 2 else 4.0, 0.1)
	var floor := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(8, 0.18, 2)
	floor.mesh = mesh
	floor.position.y = -0.13
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("7ab85a")
	floor.material_override = mat
	world.add_child(floor)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.9
	camera.position = Vector3(0, 0.95, 8)
	world.add_child(camera)
	camera.current = true
	for i in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/capture"))
	root.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://build/capture/hero_lineup.png"))
	quit()
