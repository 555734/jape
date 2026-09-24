#!/usr/bin/env python3
"""preview.gd が書き出した連番PNGをGIFにまとめる(要 Pillow)。

python3 tools/preview/make_gif.py <出力フォルダ>
"""
import sys
from collections import defaultdict
from pathlib import Path

from PIL import Image

out = Path(sys.argv[1])
groups = defaultdict(list)
for p in sorted(out.glob("*_[0-9][0-9][0-9].png")):
    groups[p.stem.rsplit("_", 1)[0]].append(p)
for name, files in groups.items():
    frames = [Image.open(f).convert("RGB").resize((640, 360)) for f in files]
    ms = 100 if name == "turn" else 50
    frames[0].save(out / f"{name}.gif", save_all=True, append_images=frames[1:], duration=ms, loop=0)
    print(out / f"{name}.gif")
