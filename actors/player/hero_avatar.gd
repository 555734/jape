class_name HeroAvatar
extends Node3D
## Blender 製 Mario / Luigi のモデルと、ゲーム状態に合わせた手足のポーズ。

const MODELS := [
	preload("res://assets/characters/mario.glb"),
	preload("res://assets/characters/luigi.glb"),
]

var player_index: int
var _arms: Array[Node3D] = []
var _legs: Array[Node3D] = []
var _head: Node3D
var _torso: Node3D
var _cycle := 0.0


func _init(index: int = 0) -> void:
	player_index = index


func _ready() -> void:
	var model: Node3D = MODELS[clampi(player_index, 0, 1)].instantiate()
	add_child(model)
	_head = model.find_child("Head", true, false) as Node3D
	_torso = model.find_child("Torso", true, false) as Node3D
	_arms = [
		model.find_child("ArmLeft", true, false) as Node3D,
		model.find_child("ArmRight", true, false) as Node3D,
	]
	_legs = [
		model.find_child("LegLeft", true, false) as Node3D,
		model.find_child("LegRight", true, false) as Node3D,
	]
	assert(_head != null and _torso != null)
	for limb in _arms + _legs:
		assert(limb != null)


func pose(state: int, grounded: bool, speed: float, delta: float) -> void:
	var running := grounded and absf(speed) > 0.35 and state == PlayerMoves.State.NORMAL
	var stride := clampf(absf(speed) / Tuning.RUN_SPEED, 0.0, 1.0)
	_cycle += delta * (lerpf(8.0, 17.0, stride) if running else 2.0)
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
