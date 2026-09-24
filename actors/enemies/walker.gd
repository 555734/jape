class_name Walker
extends CharacterBody3D
## 歩くだけの敵。壁か足場の端で向きを変える。踏まれると倒れる。

const SPEED := 1.5         ## マス/秒【決定・調整】
const SIZE := 0.9

var stage: Grassland
var dir := -1.0
var dead := false

var _model: Node3D
var _dead_timer := 0.0


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.8, SIZE, 0.8)
	shape.shape = box
	shape.position.y = SIZE * 0.5
	add_child(shape)
	_model = Assets.spawn(Assets.ENEMY, SIZE)
	add_child(_model)
	var ap := Assets.find_anim_player(_model)
	if ap:
		var a := Assets.anim_name(ap, "Walk")
		if a != &"":
			ap.get_animation(a).loop_mode = Animation.LOOP_LINEAR
			ap.play(a)


func _physics_process(delta: float) -> void:
	if dead:
		_dead_timer -= delta
		if _dead_timer <= 0.0:
			visible = false
		return
	velocity.x = dir * SPEED
	velocity.y = maxf(velocity.y - Tuning.GRAVITY_DOWN * delta, -Tuning.MAX_FALL)
	if is_on_floor():
		velocity.y = 0.0
	move_and_slide()
	position.z = 0.0
	position.x = stage.wrap_x(position.x)
	var ahead_x := int(floor(position.x + dir * 0.55))
	var foot_y := int(floor(position.y + 0.05))
	if is_on_wall() or (is_on_floor() and not stage.is_solid(ahead_x, foot_y - 1)):
		dir = -dir
	_model.rotation_degrees.y = 90.0 * dir
	if position.y < -8.0:
		dead = true
		visible = false


## 踏まれた
func squash() -> void:
	dead = true
	_dead_timer = 0.4
	collision_layer = 0
	_model.scale.y = 0.3


func is_alive() -> bool:
	return not dead
