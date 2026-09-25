class_name Walker
extends Node3D
## 歩く敵の見た目。動きと当たり判定は Simulation.SimWalker が持ち、ここは毎フレームそれを映すだけ。

var sim: Simulation.SimWalker

var _model: Node3D


func _ready() -> void:
	_model = Assets.spawn(Assets.ENEMY, Simulation.SimWalker.SIZE)
	add_child(_model)
	var ap := Assets.find_anim_player(_model)
	if ap:
		var a := Assets.anim_name(ap, "Walk")
		if a != &"":
			ap.get_animation(a).loop_mode = Animation.LOOP_LINEAR
			ap.play(a)


func sync() -> void:
	visible = sim.is_shown()
	position = Vector3(sim.x, sim.y, 0.0)
	_model.rotation_degrees.y = 90.0 * sim.dir
	# 踏まれたら縦横同じ倍率で縮める(骨で動くモデルを平たく潰すと一部のGPUで壊れるため)
	_model.scale = Vector3.ONE * (0.6 if sim.dead else 1.0)


## 左右ループの見た目用: 本体の位置は動かさず、見た目だけ横にずらす
func set_view_shift(dx: float) -> void:
	_model.position.x = dx
