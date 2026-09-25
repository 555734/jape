class_name Pickups
## 画面に出る拾い物(落ちたスター・成長アイテム)の見た目。動きは Simulation.SimPickup が持つ。


class PickupView extends Node3D:
	var sim: Simulation.SimPickup
	var _model: Node3D

	func _init(p_sim: Simulation.SimPickup) -> void:
		sim = p_sim

	func _ready() -> void:
		_model = Assets.spawn(Assets.GROW_ITEM if sim.is_item else Assets.STAR, 0.8)
		add_child(_model)

	func sync(delta: float) -> void:
		position = Vector3(sim.x, sim.y, 0.0)
		_model.rotate_y(delta * (2.5 if sim.is_item else 4.0))

	func set_view_shift(dx: float) -> void:
		_model.position.x = dx

	## 落ちたスター: age は落ちてからの秒数。最後の1.5秒は点滅【決定・調整】
	func show_age(age: float) -> void:
		var left := MatchRules.DROP_LIFETIME - age
		_model.visible = left > 1.5 or int(left * 10.0) % 2 == 0
