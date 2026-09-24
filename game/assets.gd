class_name Assets
## 素材(Quaternius Ultimate Platformer Pack, CC0)の読み込みと大きさ合わせ。

const ROOT := "res://assets/third_party/quaternius_platformer/"
const CHARACTER := "res://assets/third_party/quaternius_characters/Casual_Male.gltf"
const GRASS := "Cubes/glTF/Cube_Grass_Single.gltf"
const DIRT := "Cubes/glTF/Cube_Dirt_Single.gltf"
const BRICK := "Cubes/glTF/Cube_Bricks.gltf"
const QUESTION := "Cubes/glTF/Cube_Question.gltf"
const CRATE := "Cubes/glTF/Cube_Crate.gltf"
const PIPE := "Level and Mechanics/glTF/Pipe_End.gltf"
const COIN := "Powerups and Pickups/glTF/Coin.gltf"
const STAR := "Powerups and Pickups/glTF/Star.gltf"
const ENEMY := "Enemies/glTF/Enemy.gltf"
const CLOUD := "Nature/glTF/Cloud_2.gltf"
const TREE := "Nature/glTF/Tree.gltf"
const GROW_ITEM := "Powerups and Pickups/glTF/Heart.gltf"

## プレイヤーの配色(素材の色が暗すぎるため部品名ごとに塗り直す)。[1P, 2P]
const PLAYER_PALETTE := {
	"Skin": [Color(0.96, 0.78, 0.62), Color(0.93, 0.74, 0.58)],
	"Shirt": [Color(0.2, 0.45, 0.95), Color(0.92, 0.25, 0.22)],
	"Pants": [Color(0.22, 0.24, 0.35), Color(0.25, 0.22, 0.2)],
	"Belt": [Color(0.35, 0.22, 0.12), Color(0.35, 0.22, 0.12)],
	"Hair": [Color(0.35, 0.2, 0.1), Color(0.15, 0.1, 0.08)],
}

static var _cache := {}


## 素材を読み込み、高さ height マス・足元(下端)が原点になるよう調整したノードを返す
static func spawn(path: String, height: float) -> Node3D:
	if not _cache.has(path):
		_cache[path] = load(path if path.begins_with("res://") else ROOT + path)
	var inner: Node3D = (_cache[path] as PackedScene).instantiate()
	var holder := Node3D.new()
	holder.add_child(inner)
	var b := bounds(inner)
	var s := height / maxf(b.size.y, 0.001)
	inner.scale = Vector3.ONE * s
	inner.position = -Vector3(b.get_center().x, b.position.y, b.get_center().z) * s
	return holder


static func bounds(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for m in node.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var xf := _relative_transform(node, mi)
		var b: AABB = xf * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


static func _relative_transform(root: Node3D, n: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return root.transform * xf


static func find_anim_player(n: Node) -> AnimationPlayer:
	var list := n.find_children("*", "AnimationPlayer", true, false)
	return list[0] if not list.is_empty() else null


## "CharacterArmature|Run" のような名前から末尾一致で探す
static func anim_name(ap: AnimationPlayer, suffix: String) -> StringName:
	for a in ap.get_animation_list():
		if String(a).ends_with("|" + suffix) or String(a) == suffix:
			return a
	return &""


## プレイヤーのモデルを塗り分ける(index: 0=1P, 1=2P)
static func paint_player(n: Node, index: int) -> void:
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s)
			if mat is BaseMaterial3D and PLAYER_PALETTE.has(mat.resource_name):
				var dup: BaseMaterial3D = mat.duplicate()
				dup.albedo_color = PLAYER_PALETTE[mat.resource_name][index]
				mi.set_surface_override_material(s, dup)
