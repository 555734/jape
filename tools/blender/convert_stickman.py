"""Convert the supplied PolyOne Studio FBX to the game's white GLB avatar."""

from pathlib import Path
import bpy

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "assets/characters/source/free_pack_stick_man.fbx"
OUTPUT = ROOT / "assets/characters/white_stick_man.glb"

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.fbx_import(filepath=str(SOURCE))

white = bpy.data.materials.new("Porcelain White")
white.diffuse_color = (0.96, 0.96, 0.96, 1.0)
white.use_nodes = True
surface = white.node_tree.nodes.get("Principled BSDF")
surface.inputs["Base Color"].default_value = (0.96, 0.96, 0.96, 1.0)
surface.inputs["Roughness"].default_value = 0.72

for obj in bpy.data.objects:
    if obj.type == "MESH":
        obj.data.materials.clear()
        obj.data.materials.append(white)

bpy.ops.export_scene.gltf(
    filepath=str(OUTPUT),
    export_format="GLB",
    export_animations=False,
    export_cameras=False,
    export_lights=False,
    export_yup=True,
)
print("SAVED", OUTPUT)
