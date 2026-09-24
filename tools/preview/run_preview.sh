#!/usr/bin/env bash
# glb を読み込み、360度回転・ゲーム画面での大きさ・アニメのGIFを作る。
# 使い方: tools/preview/run_preview.sh <glbファイル> <出力フォルダ> [turntable ingame anim]
set -euo pipefail
model=$(realpath "$1"); out=$(realpath -m "$2"); shift 2
modes=${*:-turntable ingame anim}
mkdir -p "$out"
for m in $modes; do
  xvfb-run -a -s "-screen 0 1280x720x24" godot --path "$(dirname "$0")/../.." \
    --audio-driver Dummy --rendering-driver opengl3 \
    -s res://tools/preview/preview.gd -- --model="$model" --out="$out" --mode="$m" 2>&1 | grep -E "^REPORT|ERROR" || true
done
python3 "$(dirname "$0")/make_gif.py" "$out"
