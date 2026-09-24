class_name Pickups
## 画面に出る拾い物(ビッグスター・落ちたスター・成長アイテム)。


## 落ちたスター: 弾んで飛び散り、消える直前は点滅する(消える時間は MatchRules が決める)
class DroppedStar extends CharacterBody3D:
	var drop_id := 0
	var stage: Grassland
	var _model: Node3D

	func _init(id: int, p_stage: Grassland, from: Vector3, rng: RandomNumberGenerator) -> void:
		drop_id = id
		stage = p_stage
		position = from + Vector3(0, 1.0, 0)
		velocity = Vector3(rng.randf_range(-5.0, 5.0), rng.randf_range(7.0, 10.0), 0)
		collision_layer = 0
		collision_mask = 1

	func _ready() -> void:
		var shape := CollisionShape3D.new()
		var s := SphereShape3D.new()
		s.radius = 0.3
		shape.shape = s
		shape.position.y = 0.3
		add_child(shape)
		_model = Assets.spawn(Assets.STAR, 0.8)
		add_child(_model)

	func _physics_process(delta: float) -> void:
		velocity.y = maxf(velocity.y - 30.0 * delta, -15.0)
		if is_on_floor():
			velocity.x = move_toward(velocity.x, 0.0, 12.0 * delta)
		move_and_slide()
		position.z = 0.0
		position.x = stage.wrap_x(position.x)
		_model.rotate_y(delta * 4.0)

	## age: 落ちてからの秒数。最後の1.5秒は点滅【決定・調整】
	func show_age(age: float) -> void:
		var left := MatchRules.DROP_LIFETIME - age
		_model.visible = left > 1.5 or int(left * 10.0) % 2 == 0


## 成長アイテム: 画面上部に出て1秒浮いてから落ちる §6
class GrowItem extends CharacterBody3D:
	const HOVER := 1.0
	var stage: Grassland
	var _hover := HOVER
	var _model: Node3D

	func _init(p_stage: Grassland, at: Vector3) -> void:
		stage = p_stage
		position = at
		collision_layer = 0
		collision_mask = 1

	func _ready() -> void:
		var shape := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = Vector3(0.7, 0.7, 0.7)
		shape.shape = b
		shape.position.y = 0.35
		add_child(shape)
		_model = Assets.spawn(Assets.GROW_ITEM, 0.8)
		add_child(_model)

	func _physics_process(delta: float) -> void:
		_model.rotate_y(delta * 2.5)
		if _hover > 0.0:
			_hover -= delta
			return
		velocity.y = maxf(velocity.y - 30.0 * delta, -10.0)
		move_and_slide()
		position.x = stage.wrap_x(position.x)
		if position.y < -3.0:
			queue_free()
