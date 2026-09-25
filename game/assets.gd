class_name Assets
## ステージ専用に制作した立体アセットの読み込み。

const ROOT := "res://assets/third_party/quaternius_platformer/"
const GRASS := "art:grass"
const DIRT := "art:dirt"
const BRICK := "art:brick"
const QUESTION := "art:question"
const CRATE := "art:crate"
const PIPE := "art:pipe"
const COIN := "art:coin"
const STAR := "art:star"
const ENEMY := "art:enemy"
const CLOUD := "Nature/glTF/Cloud_2.gltf"
const TREE := "Nature/glTF/Tree.gltf"
const GROW_ITEM := "art:grow"

static var _cache := {}


## 素材を読み込み、高さ height マス・足元(下端)が原点になるよう調整したノードを返す
static func spawn(path: String, height: float) -> Node3D:
	if path.begins_with("art:"):
		var art := StageArt.make(path.trim_prefix("art:"))
		art.scale = Vector3.ONE * height
		return art
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


## 骨を持たない置物用: 幅と高さを別々に合わせる(土管など)
static func spawn_box(path: String, width: float, height: float) -> Node3D:
	if path == PIPE:
		return StageArt.pipe(width, height)
	var holder := spawn(path, height)
	var inner: Node3D = holder.get_child(0)
	var b := bounds(inner)
	var sx := width / maxf(b.size.x, 0.001)
	inner.scale.x *= sx
	inner.scale.z *= sx
	inner.position.x *= sx
	inner.position.z *= sx
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
