"""Create editable DS-era Mario and Luigi inspired game meshes.

Run with Blender in background mode:
  blender -b --python tools/blender/make_brothers.py

All locations below use Godot's X-right, Y-up, Z-toward-camera convention.
The helper converts them to Blender coordinates before glTF export.
"""

from pathlib import Path
import bpy
import math


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "characters"
SOURCE = ROOT / "assets_src" / "characters"
OUT.mkdir(parents=True, exist_ok=True)
SOURCE.mkdir(parents=True, exist_ok=True)
bpy.context.preferences.filepaths.save_version = 0


def rgba(hex_color):
    h = hex_color.lstrip("#")
    srgb = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    linear = [v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in srgb]
    return tuple(linear) + (1.0,)


def material(name, color, roughness=0.58):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.diffuse_color = rgba(color)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = rgba(color)
    bsdf.inputs["Roughness"].default_value = roughness
    return m


def xyz(x, y, z):
    return (x, -z, y)


def empty(name, pos=(0, 0, 0), parent=None):
    obj = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(obj)
    obj.empty_display_size = 0.05
    obj.empty_display_type = "PLAIN_AXES"
    obj.parent = parent
    obj.location = xyz(*pos)
    return obj


def oval(name, pos, size, mat, parent=None, segments=24):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=12, radius=0.5)
    obj = bpy.context.object
    obj.name = name
    obj.parent = parent
    obj.location = xyz(*pos)
    obj.scale = (size[0], size[2], size[1])
    obj.data.materials.append(mat)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    return obj


def cube(name, pos, size, mat, parent=None, bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1)
    obj = bpy.context.object
    obj.name = name
    obj.parent = parent
    obj.location = xyz(*pos)
    obj.dimensions = (size[0], size[2], size[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    if bevel:
        mod = obj.modifiers.new("Soft edges", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        obj.modifiers.new("Weighted normals", "WEIGHTED_NORMAL")
    return obj


def badge_letter(letter, pos, mat, parent):
    bpy.ops.object.text_add()
    obj = bpy.context.object
    obj.name = "CapLetter" + letter
    obj.data.body = letter
    obj.data.align_x = "CENTER"
    obj.data.size = 0.16
    obj.data.extrude = 0.001
    obj.rotation_euler[0] = math.pi / 2
    obj.parent = parent
    obj.location = xyz(*pos)
    obj.data.materials.append(mat)
    bpy.ops.object.convert(target="MESH")
    bpy.context.object.name = "CapLetter" + letter


def make_character(name, is_luigi):
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    red_or_green = material(name + "_shirt", "#22a049" if is_luigi else "#d82428")
    cap_light = material(name + "_cap_light", "#48c261" if is_luigi else "#f4433e")
    cap_dark = material(name + "_cap_dark", "#18763e" if is_luigi else "#a71920")
    denim = material(name + "_overalls", "#2355bd")
    denim_shadow = material(name + "_denim_shadow", "#173b8e")
    skin = material(name + "_skin", "#efb48d")
    cheek = material(name + "_cheek", "#dc926f")
    hair = material(name + "_hair", "#4b2b24")
    mustache = material(name + "_mustache", "#2b211f")
    white = material(name + "_gloves", "#f9f7ef")
    eye_white = material(name + "_eye_white", "#fffdf1")
    iris = material(name + "_iris", "#2677bd")
    pupil = material(name + "_pupil", "#171e27")
    shoe = material(name + "_shoes", "#72431f")
    shoe_dark = material(name + "_sole", "#4d2c1c")
    gold = material(name + "_buttons", "#f6c526", 0.35)
    logo = material(name + "_logo", "#fff8e9")

    root = empty(name)
    slender = 0.89 if is_luigi else 1.0
    tall = 1.06 if is_luigi else 1.0

    def P(x, y, z):
        return (x * slender, y * tall, z)

    def S(x, y, z):
        return (x * slender, y * tall, z)

    torso = empty("Torso", parent=root)
    oval("Shirt", P(0, 0.88, 0), S(0.65, 0.6, 0.49), red_or_green, torso)
    oval("OverallBelly", P(0, 0.74, 0.025), S(0.65, 0.49, 0.48), denim, torso)
    cube("OverallBib", P(0, 1.01, 0.253), S(0.43, 0.34, 0.10), denim, torso, 0.06)
    for side in (-1, 1):
        strap = cube("OverallStrap", P(side * 0.215, 1.075, 0.206), S(0.11, 0.22, 0.08), denim, torso, 0.035)
        strap.rotation_euler[1] = side * math.radians(9)
        oval("GoldButton", P(side * 0.205, 0.98, 0.315), S(0.095, 0.095, 0.038), gold, torso)
    oval("OverallWaist", P(0, 0.61, 0.02), S(0.59, 0.21, 0.47), denim_shadow, torso)

    head = empty("Head", parent=root)
    oval("HeadShape", P(0, 1.38, 0.025), S(0.69, 0.69, 0.65), skin, head)
    oval("HairBack", P(0, 1.48, -0.245), S(0.65, 0.54, 0.28), hair, head)
    for side in (-1, 1):
        oval("Ear", P(side * 0.335, 1.34, 0.0), S(0.13, 0.18, 0.12), skin, head)
        oval("Sideburn", P(side * 0.29, 1.50, 0.04), S(0.15, 0.25, 0.27), hair, head)
        oval("EyeWhite", P(side * 0.115, 1.43, 0.332), S(0.115, 0.17, 0.045), eye_white, head)
        oval("Iris", P(side * 0.125, 1.425, 0.367), S(0.06, 0.115, 0.027), iris, head)
        oval("Pupil", P(side * 0.125, 1.42, 0.385), S(0.035, 0.08, 0.015), pupil, head)
        oval("Brow", P(side * 0.116, 1.535, 0.34), S(0.12, 0.048, 0.04), hair, head)
        whisker = oval("MustacheLobe", P(side * 0.135, 1.245, 0.334), S(0.27, 0.115, 0.10), mustache, head)
        whisker.rotation_euler[1] = side * math.radians(16)
    oval("CheekLeft", P(-0.23, 1.31, 0.26), S(0.13, 0.10, 0.035), cheek, head)
    oval("CheekRight", P(0.23, 1.31, 0.26), S(0.13, 0.10, 0.035), cheek, head)
    oval("Nose", P(0, 1.345, 0.408), S(0.205 if is_luigi else 0.23, 0.17, 0.19), skin, head)
    oval("Chin", P(0, 1.14, 0.195), S(0.36, 0.14, 0.28), skin, head)
    oval("CapCrown", P(0, 1.69, -0.035), S(0.78, 0.27, 0.71), red_or_green, head)
    oval("CapTop", P(0, 1.765, -0.09), S(0.66, 0.095, 0.54), cap_light, head)
    oval("CapBrim", P(0, 1.565, 0.29), S(0.78, 0.105, 0.49), cap_dark, head)
    oval("CapUpperBrim", P(0, 1.592, 0.29), S(0.72, 0.055, 0.45), red_or_green, head)
    oval("Badge", P(0, 1.697, 0.33), S(0.235, 0.225, 0.047), logo, head)
    badge_letter("L" if is_luigi else "M", P(0, 1.638, 0.366), cap_dark, head)

    for side, suffix in ((-1, "Left"), (1, "Right")):
        arm = empty("Arm" + suffix, P(side * 0.38, 1.085, 0), root)
        oval("Sleeve" + suffix, P(side * 0.065, -0.17, 0), S(0.255, 0.37, 0.29), red_or_green, arm)
        oval("GloveCuff" + suffix, P(side * 0.08, -0.335, 0), S(0.24, 0.105, 0.25), white, arm)
        oval("Glove" + suffix, P(side * 0.08, -0.445, 0.035), S(0.265, 0.24, 0.27), white, arm)
        oval("Thumb" + suffix, P(side * 0.018, -0.40, 0.14), S(0.11, 0.15, 0.13), white, arm)

        leg = empty("Leg" + suffix, P(side * 0.17, 0.63, 0), root)
        oval("Trouser" + suffix, P(0, -0.20, 0), S(0.285, 0.44, 0.33), denim, leg)
        oval("Shoe" + suffix, P(0, -0.49, 0.09), S(0.34, 0.225, 0.46), shoe, leg)
        oval("Sole" + suffix, P(0, -0.585, 0.10), S(0.32, 0.05, 0.45), shoe_dark, leg)

    bpy.context.view_layer.objects.active = root
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE / (name.lower() + ".blend")))
    bpy.ops.export_scene.gltf(
        filepath=str(OUT / (name.lower() + ".glb")),
        export_format="GLB",
        export_animations=False,
        export_cameras=False,
        export_lights=False,
    )
    print("SAVED", name, OUT)


make_character("Mario", False)
make_character("Luigi", True)
