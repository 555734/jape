class_name Player
extends CharacterBody3D
## 操作キャラ。判定は横(X)と縦(Y)の2次元だけで、奥行き(Z)は常に0。

const HEIGHT := 1.8   ## 大きい状態の高さ(マス)
const WIDTH := 0.8

var input_source: Callable = PlayerInput.from_actions
var spawn_point := Vector3.ZERO
var coins := 0
var stars := 0

var _model: Node3D
var _ap: AnimationPlayer
var _anims := {}
var _facing := 1.0


func _ready() -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(WIDTH, HEIGHT, 1.0)
	shape.shape = box
	shape.position.y = HEIGHT * 0.5
	add_child(shape)
	floor_snap_length = 0.1

	_model = Assets.spawn(Assets.CHARACTER, HEIGHT)
	add_child(_model)
	_ap = Assets.find_anim_player(_model)
	if _ap:
		for key in ["Idle", "Walk", "Run", "Jump", "Jump_Idle"]:
			var n := Assets.anim_name(_ap, key)
			if n != &"":
				_anims[key] = n
				if key != "Jump":
					_ap.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	spawn_point = position


func _physics_process(delta: float) -> void:
	var input: PlayerInput = input_source.call()
	var v := PlayerMotor.step(Vector2(velocity.x, velocity.y), is_on_floor(), input, delta)
	velocity = Vector3(v.x, v.y, 0.0)
	move_and_slide()
	position.z = 0.0
	if position.y < -8.0:
		respawn()
	_update_visual()


func respawn() -> void:
	position = spawn_point
	velocity = Vector3.ZERO


func _update_visual() -> void:
	if absf(velocity.x) > 0.1:
		_facing = signf(velocity.x)
	_model.rotation_degrees.y = 90.0 * _facing
	if _ap == null:
		return
	var key := "Idle"
	if not is_on_floor():
		key = "Jump_Idle"
	elif absf(velocity.x) > Tuning.WALK_SPEED + 0.5:
		key = "Run"
	elif absf(velocity.x) > 0.2:
		key = "Walk"
	var n: StringName = _anims.get(key, &"")
	if n != &"" and _ap.current_animation != n:
		_ap.play(n, 0.1)
