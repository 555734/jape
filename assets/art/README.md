# Meadow stage art

`meadow_panorama.png` was generated with the built-in image generation tool for this project. It is used as a camera-following distant layer; gameplay geometry and collision remain separate.

Prompt: "Create a polished original cheerful meadow world background only, suitable behind 3D gameplay. Wide landscape composition. Clear saturated azure sky with a gentle vertical gradient, a few soft elongated ivory clouds, distant layers of rounded apricot and butter-yellow striped hills, then lush overlapping emerald and mint shrub silhouettes along the lower third. Elegant stylized 3D rendered illustration with hand-crafted material detail, crisp forms and subtle ambient light, cheerful and premium game-art quality. Camera straight-on orthographic, no perspective ground plane. Keep middle sky clean for moving characters and pickups. No foreground platforms, no blocks, no pipes, no characters, no coins, no stars, no text, no UI, no logos, no watermark."

The blocks, soil, pipes, coins, star, growth pickup and walking enemy are original procedural meshes in `game/stage_art.gd`.

The player characters are Blender-modeled Mario and Luigi recreations based on the supplied DS gameplay screenshots. Editable `.blend` sources are in `assets_src/characters/`; exported `.glb` files are in `assets/characters/`. The deterministic build script is `tools/blender/make_brothers.py`, and `actors/player/hero_avatar.gd` applies poses to the imported head and limb nodes. The models are independently made recreations, not extracted game files. The four-character preview is `tools/preview/hero_avatar_preview.gd`.
