class_name HeroAvatar
extends Node3D
## 小さな画面でも顔・進行方向・手足の動きが読めるオリジナルの冒険者。
## 1.8マスの原寸で作り、Player 側で大・小の状態に合わせて一様に拡縮する。

var player_index: int
var _arms: Array[Node3D] = []
var _legs: Array[Node3D] = []
var _head: Node3D
var _torso: Node3D
var _cycle := 0.0

static var _materials := {}
static var _sphere_shape: SphereMesh


func _init(index: int = 0) -> void:
	player_index = index


func _ready() -> void:
	_build()


static func _material(key: String, color: Color, roughness := 0.68) -> StandardMaterial3D:
	if not _materials.has(key):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = roughness
		mat.metallic = 0.03
		_materials[key] = mat
	return _materials[key]


static func _oval(parent: Node3D, name: String, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = name
	if _sphere_shape == null:
		_sphere_shape = SphereMesh.new()
		_sphere_shape.radius = 0.5
		_sphere_shape.height = 1.0
		_sphere_shape.radial_segments = 24
		_sphere_shape.rings = 12
	part.mesh = _sphere_shape
	part.material_override = mat
	part.position = pos
	part.scale = size
	parent.add_child(part)
	return part


static func _box(parent: Node3D, name: String, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = name
	var shape := BoxMesh.new()
	shape.size = size
	part.mesh = shape
	part.material_override = mat
	part.position = pos
	parent.add_child(part)
	return part


func _build() -> void:
	var blue := player_index == 0
	var jacket := _material("jacket_blue", Color("2189d8")) if blue else _material("jacket_coral", Color("e85455"))
	var jacket_light := _material("jacket_light_blue", Color("62c9ef")) if blue else _material("jacket_light_coral", Color("ff9a79"))
	var jacket_dark := _material("jacket_dark_blue", Color("225b9b")) if blue else _material("jacket_dark_coral", Color("a83c55"))
	var scarf := _material("scarf_gold", Color("ffca4f")) if blue else _material("scarf_mint", Color("7be1bd"))
	var skin := _material("skin", Color("f2c39c"))
	var skin_shadow := _material("skin_shadow", Color("e3a67f"))
	var glove := _material("glove", Color("fff5dc"))
	var hair := _material("hair", Color("513b38"))
	var boots := _material("boots", Color("4c4050"))
	var sole := _material("sole", Color("e8d5a9"))
	var eye := _material("eye", Color("242d3e"), 0.4)
	var glint := _material("glint", Color("ffffff"), 0.25)

	# 胴体と大きな頭を同じ幅に近づけ、遠景でも人型に見える比率にする。
	_torso = Node3D.new()
	_torso.name = "Torso"
	add_child(_torso)
	_oval(_torso, "Coat", Vector3(0, 0.84, 0), Vector3(0.67, 0.64, 0.45), jacket)
	_oval(_torso, "CoatFront", Vector3(0, 0.88, 0.219), Vector3(0.37, 0.33, 0.055), jacket_light)
	_box(_torso, "Belt", Vector3(0, 0.62, 0.225), Vector3(0.56, 0.065, 0.055), jacket_dark)
	_oval(_torso, "Scarf", Vector3(0, 1.14, 0.03), Vector3(0.53, 0.15, 0.45), scarf)
	_oval(_torso, "ScarfKnot", Vector3(0.19, 1.08, 0.265), Vector3(0.13, 0.13, 0.08), scarf)
	for side in [-1.0, 1.0]:
		_oval(_torso, "CoatButton", Vector3(side * 0.115, 0.86, 0.251), Vector3(0.045, 0.045, 0.027), scarf)

	_head = Node3D.new()
	_head.name = "Head"
	add_child(_head)
	_oval(_head, "Face", Vector3(0, 1.39, 0.035), Vector3(0.7, 0.69, 0.67), skin)
	for side in [-1.0, 1.0]:
		_oval(_head, "Ear", Vector3(side * 0.34, 1.36, 0.015), Vector3(0.13, 0.18, 0.13), skin_shadow)
		_oval(_head, "HairSide", Vector3(side * 0.28, 1.56, -0.04), Vector3(0.18, 0.23, 0.44), hair)
		_oval(_head, "Eye", Vector3(side * 0.135, 1.43, 0.365), Vector3(0.075, 0.13, 0.05), eye)
		_oval(_head, "EyeGlint", Vector3(side * 0.135 - 0.014, 1.46, 0.393), Vector3(0.023, 0.031, 0.012), glint)
	_oval(_head, "Nose", Vector3(0, 1.33, 0.392), Vector3(0.13, 0.12, 0.13), skin_shadow)
	_oval(_head, "Smile", Vector3(0, 1.205, 0.354), Vector3(0.16, 0.027, 0.018), hair)
	_oval(_head, "HairFront", Vector3(0, 1.64, 0.13), Vector3(0.63, 0.18, 0.42), hair)
	_oval(_head, "CapCrown", Vector3(0, 1.68, -0.02), Vector3(0.78, 0.29, 0.72), jacket)
	_oval(_head, "CapBrim", Vector3(0, 1.57, 0.29), Vector3(0.75, 0.11, 0.44), jacket_dark)
	_oval(_head, "CapTrim", Vector3(0, 1.64, 0.304), Vector3(0.4, 0.04, 0.045), jacket_light)
	_oval(_head, "CapBadge", Vector3(0, 1.725, 0.335), Vector3(0.15, 0.12, 0.04), scarf)

	for side in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.name = "ArmLeft" if side < 0.0 else "ArmRight"
		arm.position = Vector3(side * 0.39, 1.075, 0)
		add_child(arm)
		_arms.append(arm)
		_oval(arm, "Sleeve", Vector3(side * 0.06, -0.17, 0), Vector3(0.27, 0.39, 0.3), jacket)
		_oval(arm, "Cuff", Vector3(side * 0.07, -0.34, 0.01), Vector3(0.22, 0.1, 0.25), jacket_dark)
		_oval(arm, "Glove", Vector3(side * 0.08, -0.45, 0.05), Vector3(0.27, 0.26, 0.28), glove)

		var leg := Node3D.new()
		leg.name = "LegLeft" if side < 0.0 else "LegRight"
		leg.position = Vector3(side * 0.18, 0.63, 0)
		add_child(leg)
		_legs.append(leg)
		_oval(leg, "Trouser", Vector3(0, -0.22, 0), Vector3(0.27, 0.45, 0.31), jacket_dark)
		_oval(leg, "Boot", Vector3(0, -0.49, 0.1), Vector3(0.33, 0.25, 0.47), boots)
		_oval(leg, "Sole", Vector3(0, -0.585, 0.11), Vector3(0.32, 0.055, 0.46), sole)


func pose(state: int, grounded: bool, speed: float, delta: float) -> void:
	var running := grounded and absf(speed) > 0.35 and state == PlayerMoves.State.NORMAL
	var stride := clampf(absf(speed) / Tuning.RUN_SPEED, 0.0, 1.0)
	if running:
		_cycle += delta * lerpf(8.0, 17.0, stride)
	else:
		_cycle += delta * 2.0
	var wave := sin(_cycle)
	var swing := wave * lerpf(13.0, 38.0, stride) if running else 0.0
	_legs[0].rotation_degrees.z = swing
	_legs[1].rotation_degrees.z = -swing
	_arms[0].rotation_degrees.z = -swing * 0.9 - 7.0
	_arms[1].rotation_degrees.z = swing * 0.9 + 7.0
	_torso.position.y = absf(wave) * 0.035 * stride if running else sin(_cycle) * 0.013
	_head.position.y = _torso.position.y * 0.5
	match state:
		PlayerMoves.State.SKID:
			_arms[0].rotation_degrees.z = -35
			_arms[1].rotation_degrees.z = 35
			_legs[0].rotation_degrees.z = -22
			_legs[1].rotation_degrees.z = 22
		PlayerMoves.State.CROUCH:
			_arms[0].rotation_degrees.z = -30
			_arms[1].rotation_degrees.z = 30
			_head.position.y -= 0.1
		PlayerMoves.State.WALL_SLIDE:
			_arms[0].rotation_degrees.z = -65
			_arms[1].rotation_degrees.z = 65
			_legs[0].rotation_degrees.z = 17
			_legs[1].rotation_degrees.z = -17
		PlayerMoves.State.GROUND_POUND:
			_arms[0].rotation_degrees.z = 30
			_arms[1].rotation_degrees.z = -30
			_legs[0].rotation_degrees.z = -18
			_legs[1].rotation_degrees.z = 18
		PlayerMoves.State.GP_LAND:
			_head.position.y -= 0.12
		_:
			if not grounded:
				_arms[0].rotation_degrees.z = -45
				_arms[1].rotation_degrees.z = 45
				_legs[0].rotation_degrees.z = 15
				_legs[1].rotation_degrees.z = -15
