class_name HeroAvatar
extends Node3D
## PolyOne Studio のリグ付きメッシュ。全身白のシルエットを骨で動かす。

const MODEL: PackedScene = preload("res://assets/characters/white_stick_man.glb")

var player_index: int
var _skeleton: Skeleton3D
var _mesh: MeshInstance3D
var _rig: Node3D
var _bones: Dictionary = {}
var _axis_z: Dictionary = {}
var _base_rotation: Dictionary = {}
var _cycle := 0.0


func _init(index: int = 0) -> void:
	player_index = index


func _ready() -> void:
	_rig = MODEL.instantiate()
	add_child(_rig)
	_skeleton = _rig.find_child("Skeleton3D", true, false) as Skeleton3D
	_mesh = _rig.find_child("SM_StickMan", true, false) as MeshInstance3D
	assert(_skeleton != null and _mesh != null)
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# 色は書き出した GLB にも焼き込み、ここでも再指定して全端末で同じ白にする。
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.96, 0.96, 0.96)
	white.roughness = 0.72
	_mesh.material_override = white
	var rig_basis := global_transform.basis.inverse() * _skeleton.global_transform.basis
	var scene_z_in_skeleton := rig_basis.inverse() * Vector3.BACK
	for bone_name in ["LeftArm", "RightArm", "LeftForeArm", "RightForeArm", "LeftUpLeg", "RightUpLeg", "LeftLeg", "RightLeg", "Spine2", "Head"]:
		var bone_id := _skeleton.find_bone(bone_name)
		assert(bone_id >= 0, "Missing stickman bone: " + bone_name)
		_bones[bone_name] = bone_id
		_axis_z[bone_name] = (_skeleton.get_bone_global_rest(bone_id).basis.inverse() * scene_z_in_skeleton).normalized()
		_base_rotation[bone_name] = _skeleton.get_bone_pose_rotation(bone_id)


func _set_z(bone_name: String, degrees: float) -> void:
	var bone_id: int = _bones[bone_name]
	_skeleton.set_bone_pose_rotation(bone_id, Quaternion(_axis_z[bone_name], deg_to_rad(degrees)) * _base_rotation[bone_name])


func pose(state: int, grounded: bool, speed: float, delta: float) -> void:
	if _skeleton == null:
		return
	var stride := clampf(absf(speed) / Tuning.RUN_SPEED, 0.0, 1.0)
	var running := grounded and absf(speed) > 0.35 and state == PlayerMoves.State.NORMAL
	_cycle += delta * (lerpf(7.0, 17.0, stride) if running else 2.0)
	var wave := sin(_cycle)
	var swing := wave * lerpf(10.0, 35.0, stride) if running else 0.0
	var left_arm := -76.0 - swing * 0.75
	var right_arm := 76.0 - swing * 0.75
	var left_leg := swing
	var right_leg := -swing
	var left_forearm := -12.0
	var right_forearm := 12.0
	var torso := 0.0
	var head := 0.0

	match state:
		PlayerMoves.State.SKID:
			left_arm = -120.0
			right_arm = 120.0
			left_leg = -24.0
			right_leg = 24.0
			torso = 8.0
		PlayerMoves.State.CROUCH:
			left_arm = -48.0
			right_arm = 48.0
			left_leg = -25.0
			right_leg = 25.0
			torso = 18.0
		PlayerMoves.State.WALL_SLIDE:
			left_arm = -18.0
			right_arm = 18.0
			left_leg = -18.0
			right_leg = 18.0
		PlayerMoves.State.GROUND_POUND:
			left_arm = -125.0
			right_arm = 125.0
			left_leg = -12.0
			right_leg = 12.0
		PlayerMoves.State.GP_LAND:
			torso = 22.0
			head = -8.0
		_:
			if not grounded:
				left_arm = -120.0
				right_arm = 120.0
				left_leg = -16.0
				right_leg = 16.0

	_set_z("LeftArm", left_arm)
	_set_z("RightArm", right_arm)
	_set_z("LeftForeArm", left_forearm)
	_set_z("RightForeArm", right_forearm)
	_set_z("LeftUpLeg", left_leg)
	_set_z("RightUpLeg", right_leg)
	_set_z("LeftLeg", 12.0 if running and left_leg > 0.0 else 0.0)
	_set_z("RightLeg", -12.0 if running and right_leg < 0.0 else 0.0)
	_set_z("Spine2", torso)
	_set_z("Head", head)
	_rig.position.y = absf(wave) * 0.025 * stride if running else sin(_cycle) * 0.006
