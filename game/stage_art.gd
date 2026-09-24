class_name StageArt
extends RefCounted
## ステージ専用の立体アセット。単位は1マス、原点は下端。

static var _mats := {}


static func _mat(key: String, color: Color, metallic := 0.0, roughness := 0.75) -> StandardMaterial3D:
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.metallic = metallic
		m.roughness = roughness
		_mats[key] = m
	return _mats[key]


static func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	n.mesh = mesh
	n.material_override = mat
	n.position = pos
	parent.add_child(n)
	return n


static func _sphere(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 16
	mesh.rings = 8
	n.mesh = mesh
	n.material_override = mat
	n.scale = size
	n.position = pos
	parent.add_child(n)
	return n


static func _cylinder(parent: Node3D, top: float, bottom: float, h: float, pos: Vector3, mat: Material, radial := 32) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = h
	mesh.radial_segments = radial
	n.mesh = mesh
	n.material_override = mat
	n.position = pos
	parent.add_child(n)
	return n


static func _ring(parent: Node3D, inner: float, outer: float, pos: Vector3, mat: Material) -> void:
	var n := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 32
	mesh.ring_segments = 8
	n.mesh = mesh
	n.material_override = mat
	n.position = pos
	parent.add_child(n)


static func make(kind: String) -> Node3D:
	var root := Node3D.new()
	match kind:
		"grass", "dirt":
			_soil(root, kind == "grass")
		"brick":
			_brick(root)
		"crate":
			_crate(root)
		"question":
			_question(root)
		"coin":
			_coin(root)
		"star":
			_star(root)
		"enemy":
			_enemy(root)
		"grow":
			_grow(root)
	return root


static func _soil(root: Node3D, grass: bool) -> void:
	var earth := _mat("earth", Color("b97647"))
	var edge := _mat("earth_edge", Color("845039"))
	var fleck := _mat("soil_fleck", Color("e6ae6a"))
	_box(root, Vector3(1.0, 1.0, 0.92), Vector3(0, 0.5, 0), earth)
	_box(root, Vector3(0.94, 0.05, 0.02), Vector3(0, 0.05, 0.47), edge)
	for i in 5:
		var x := -0.38 + i * 0.19
		var y := 0.22 + float((i * 7) % 4) * 0.12
		_sphere(root, Vector3(0.08, 0.045, 0.015), Vector3(x, y, 0.472), fleck)
	if grass:
		_box(root, Vector3(1.03, 0.21, 1.0), Vector3(0, 0.91, 0), _mat("grass_dark", Color("20a34a")))
		_box(root, Vector3(1.03, 0.075, 1.0), Vector3(0, 1.005, 0), _mat("grass_top", Color("87df57")))
		for i in 4:
			_sphere(root, Vector3(0.23, 0.18, 0.07), Vector3(-0.37 + i * 0.25, 0.81 - (i % 2) * 0.03, 0.49), _mat("grass_lip", Color("3abc46")))
		for i in 3:
			_sphere(root, Vector3(0.1, 0.06, 0.04), Vector3(-0.3 + i * 0.3, 1.045, 0.25), _mat("grass_light", Color("b5ef63")))


static func _brick(root: Node3D) -> void:
	_box(root, Vector3(0.96, 0.96, 0.86), Vector3(0, 0.5, 0), _mat("brick_side", Color("a95435")))
	_box(root, Vector3(0.84, 0.8, 0.045), Vector3(0, 0.5, 0.455), _mat("brick_face", Color("d7874b")))
	_box(root, Vector3(0.83, 0.055, 0.05), Vector3(0, 0.53, 0.49), _mat("brick_mortar", Color("7f4535")))
	for i in 2:
		var x := -0.23 if i == 0 else 0.23
		_box(root, Vector3(0.04, 0.34, 0.05), Vector3(x, 0.29 if i == 0 else 0.72, 0.49), _mat("brick_mortar", Color("7f4535")))
	_box(root, Vector3(0.85, 0.035, 0.055), Vector3(0, 0.87, 0.492), _mat("brick_highlight", Color("f4b76a")))


static func _crate(root: Node3D) -> void:
	_box(root, Vector3(0.96, 0.96, 0.88), Vector3(0, 0.5, 0), _mat("stone_side", Color("9e6b42")))
	_box(root, Vector3(0.82, 0.82, 0.055), Vector3(0, 0.5, 0.47), _mat("stone_face", Color("e2b86e")))
	for x in [-0.39, 0.39]:
		_box(root, Vector3(0.09, 0.86, 0.07), Vector3(x, 0.5, 0.51), _mat("stone_frame", Color("b88650")))
	for y in [0.11, 0.89]:
		_box(root, Vector3(0.85, 0.09, 0.07), Vector3(0, y, 0.51), _mat("stone_frame", Color("b88650")))
	var slash := _box(root, Vector3(0.05, 0.45, 0.025), Vector3(0.02, 0.49, 0.518), _mat("stone_carve", Color("f3d390")))
	slash.rotation_degrees.z = -42
	_sphere(root, Vector3(0.1, 0.1, 0.03), Vector3(-0.2, 0.29, 0.53), _mat("stone_carve", Color("f3d390")))


static func _question(root: Node3D) -> void:
	_box(root, Vector3(0.96, 0.96, 0.88), Vector3(0, 0.5, 0), _mat("gold_side", Color("ca7c20"), 0.15, 0.4))
	_box(root, Vector3(0.82, 0.82, 0.05), Vector3(0, 0.5, 0.47), _mat("gold_face", Color("ffc94b"), 0.15, 0.35))
	for x in [-0.39, 0.39]:
		_box(root, Vector3(0.055, 0.84, 0.07), Vector3(x, 0.5, 0.51), _mat("gold_trim", Color("fff09c"), 0.2, 0.3))
	for y in [0.11, 0.89]:
		_box(root, Vector3(0.84, 0.055, 0.07), Vector3(0, y, 0.51), _mat("gold_trim", Color("fff09c"), 0.2, 0.3))
	var mark := Label3D.new()
	mark.text = "?"
	mark.font_size = 96
	mark.pixel_size = 0.007
	mark.modulate = Color("fff8ce")
	mark.outline_modulate = Color("9b5b1e")
	mark.outline_size = 8
	mark.position = Vector3(0, 0.53, 0.55)
	root.add_child(mark)


static func pipe(width: float, height: float) -> Node3D:
	var root := Node3D.new()
	var r := width * 0.45
	_cylinder(root, r * 0.94, r * 0.94, height - 0.12, Vector3(0, (height - 0.12) * 0.5, 0), _mat("pipe_body", Color("13aa4c"), 0.18, 0.28))
	_cylinder(root, r * 1.1, r * 1.1, 0.23, Vector3(0, height - 0.115, 0), _mat("pipe_rim", Color("35d965"), 0.2, 0.22))
	_cylinder(root, r * 0.79, r * 0.79, 0.008, Vector3(0, height + 0.004, 0), _mat("pipe_inside", Color("166c42"), 0.1, 0.45))
	_ring(root, r * 0.77, r * 0.86, Vector3(0, height + 0.008, 0), _mat("pipe_glint", Color("a2f184"), 0.16, 0.25))
	_box(root, Vector3(0.06, maxf(height - 0.3, 0.1), 0.018), Vector3(-r * 0.47, (height - 0.3) * 0.5, r * 0.85), _mat("pipe_highlight", Color("88ee82"), 0.05, 0.28))
	return root


static func _coin(root: Node3D) -> void:
	var rim := _cylinder(root, 0.43, 0.43, 0.12, Vector3(0, 0.5, 0), _mat("coin_rim", Color("d68813"), 0.65, 0.2))
	rim.rotation_degrees.x = 90
	var face := _cylinder(root, 0.36, 0.36, 0.135, Vector3(0, 0.5, 0), _mat("coin_face", Color("ffdb42"), 0.55, 0.22))
	face.rotation_degrees.x = 90
	_box(root, Vector3(0.09, 0.51, 0.025), Vector3(0, 0.5, 0.079), _mat("coin_mark", Color("fff7a5"), 0.25, 0.25))
	_sphere(root, Vector3(0.11, 0.09, 0.02), Vector3(-0.2, 0.72, 0.077), _mat("coin_mark", Color("fff7a5"), 0.25, 0.25))


static func _star(root: Node3D) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := Vector3(0, 0.5, 0.09)
	var pts := PackedVector3Array()
	for i in 10:
		var a := -PI * 0.5 + i * PI / 5.0
		var r := 0.49 if i % 2 == 0 else 0.23
		pts.append(Vector3(cos(a) * r, 0.5 + sin(a) * r, 0.09))
	for i in 10:
		st.set_normal(Vector3.FORWARD)
		st.add_vertex(center)
		st.add_vertex(pts[i])
		st.add_vertex(pts[(i + 1) % 10])
	var n := MeshInstance3D.new()
	n.mesh = st.commit()
	var face_mat := _mat("star_face", Color("ffe65b"), 0.15, 0.28)
	face_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	n.material_override = face_mat
	root.add_child(n)
	for i in 2:
		_sphere(root, Vector3(0.055, 0.09, 0.025), Vector3(-0.12 + i * 0.24, 0.51, 0.12), _mat("eye", Color("352d2a")))
	_sphere(root, Vector3(0.21, 0.06, 0.025), Vector3(0, 0.38, 0.105), _mat("star_shine", Color("fff6ae")))


static func _enemy(root: Node3D) -> void:
	_sphere(root, Vector3(0.63, 0.57, 0.6), Vector3(0, 0.35, 0), _mat("enemy_body", Color("f3d8a0")))
	_sphere(root, Vector3(0.96, 0.54, 0.75), Vector3(0, 0.72, -0.02), _mat("enemy_cap", Color("bd6e56")))
	for i in 2:
		_sphere(root, Vector3(0.1, 0.19, 0.045), Vector3(-0.16 + i * 0.32, 0.44, 0.315), _mat("eye", Color("352d2a")))
		_sphere(root, Vector3(0.3, 0.13, 0.3), Vector3(-0.23 + i * 0.46, 0.07, 0.04), _mat("enemy_shoe", Color("654737")))


static func _grow(root: Node3D) -> void:
	_sphere(root, Vector3(0.65, 0.53, 0.55), Vector3(0, 0.32, 0), _mat("grow_body", Color("fff1cf")))
	_sphere(root, Vector3(0.92, 0.55, 0.7), Vector3(0, 0.72, 0), _mat("grow_cap", Color("e64e55")))
	for i in 2:
		_sphere(root, Vector3(0.1, 0.17, 0.045), Vector3(-0.14 + i * 0.28, 0.39, 0.285), _mat("eye", Color("352d2a")))
	_sphere(root, Vector3(0.2, 0.12, 0.09), Vector3(0, 0.84, 0.31), _mat("grow_spot", Color("fff9e4")))


static func flower(variant: int) -> Node3D:
	var root := Node3D.new()
	_cylinder(root, 0.016, 0.02, 0.22, Vector3(0, 0.11, 0), _mat("stem", Color("418d37")), 8)
	var petal := _mat("petal_pink", Color("f681a0")) if variant % 2 == 0 else _mat("petal_white", Color("fff2ce"))
	for i in 5:
		var angle := i * TAU / 5.0
		_sphere(root, Vector3(0.085, 0.085, 0.04), Vector3(cos(angle) * 0.057, 0.23 + sin(angle) * 0.057, 0.045), petal)
	_sphere(root, Vector3(0.065, 0.065, 0.05), Vector3(0, 0.23, 0.075), _mat("flower_center", Color("ffd24c")))
	return root
