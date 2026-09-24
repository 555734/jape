#!/usr/bin/env python3
"""三面図から、骨入り・アニメ付きの3Dキャラクター(.glb)を Tripo API で作る。

使い方:
    python3 tools/tripo/generate_character.py assets_src/characters/hero
        --dry-run     APIを呼ばず、送る内容と見積もりクレジットだけ表示
        --skip-model  既存の model_task_id から続ける(作り直し時の節約用)

入力フォルダに front.png / side.png / back.png(side は左側面)を置く。
出力は <入力フォルダ>/tripo/ に保存し、各タスクIDを tasks.json に記録する。
APIキーは環境変数 TRIPO_API_KEY から読むだけで、表示・保存はしない。
"""
import argparse
import json
import os
import sys
import time
from pathlib import Path

import requests

BASE = "https://api.tripo3d.ai/v2/openapi"
MODEL_VERSION = "v3.1-20260211"
FACE_LIMIT = 20000
ANIMATIONS = ["idle", "walk", "run", "jump", "fall"]
# https://developers.tripo3d.ai/en/pricing (2026-09 時点)
COST = {"model": 30 + 10, "rig": 25, "retarget": 10}


def headers():
    key = os.environ.get("TRIPO_API_KEY")
    if not key:
        sys.exit("TRIPO_API_KEY が設定されていません")
    return {"Authorization": f"Bearer {key}"}


def api(method, path, **kw):
    r = requests.request(method, BASE + path, headers=headers(), timeout=120, **kw)
    body = r.json()
    if r.status_code >= 400 or body.get("code") != 0:
        sys.exit(f"APIエラー {r.status_code}: {body.get('code')} {body.get('message')} {body.get('suggestion', '')}")
    return body["data"]


def balance():
    return api("GET", "/user/balance")["balance"]


def upload(path):
    with open(path, "rb") as f:
        data = api("POST", "/upload", files={"file": (path.name, f, "image/png")})
    return {"type": "png", "file_token": data["image_token"]}


def create(task):
    return api("POST", "/task", json=task)["task_id"]


def wait(task_id, label):
    while True:
        d = api("GET", f"/task/{task_id}")
        st = d["status"]
        print(f"  {label}: {st} {d.get('progress', '')}%", flush=True)
        if st == "success":
            print(f"  {label}: 消費クレジット {d.get('consumed_credit', '?')}")
            return d
        if st in ("failed", "cancelled", "banned", "expired", "unknown"):
            sys.exit(f"{label} が失敗しました: {st}")
        time.sleep(10)


def download(url, dest):
    r = requests.get(url, timeout=300)
    r.raise_for_status()
    dest.write_bytes(r.content)
    print(f"  保存: {dest} ({len(r.content) // 1024} KB)")


def model_url(output):
    return output.get("pbr_model") or output.get("model") or output.get("base_model")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src", type=Path)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--skip-model", action="store_true")
    args = ap.parse_args()

    out = args.src / "tripo"
    out.mkdir(parents=True, exist_ok=True)
    log_path = out / "tasks.json"
    log = json.loads(log_path.read_text()) if log_path.exists() else {}

    views = [args.src / n for n in ("front.png", "side.png", "back.png")]
    for v in views:
        if not v.exists():
            sys.exit(f"{v} がありません")

    need = COST["rig"] + COST["retarget"] * len(ANIMATIONS)
    if not args.skip_model:
        need += COST["model"]
    print(f"見積もり: {need} クレジット / 残高: {balance()}")
    if args.dry_run:
        return
    if balance() < need:
        sys.exit("残高が足りません。platform.tripo3d.ai でAPIクレジットを購入してください")

    if args.skip_model:
        model_id = log["model"]
    else:
        print("1/3 3Dモデル生成")
        # 順番は 正面・左・背面・右。右は無いので空にする
        files = [upload(views[0]), upload(views[1]), upload(views[2]), {}]
        model_id = create({
            "type": "multiview_to_model",
            "files": files,
            "model_version": MODEL_VERSION,
            "face_limit": FACE_LIMIT,
            "texture": True,
            "pbr": True,
            "texture_quality": "detailed",
        })
        log["model"] = model_id
        log_path.write_text(json.dumps(log, indent=2))
        d = wait(model_id, "モデル")
        download(model_url(d["output"]), out / "model.glb")

    print("2/3 骨入れ")
    rig_id = create({
        "type": "animate_rig",
        "original_model_task_id": model_id,
        "out_format": "glb",
        "rig_type": "biped",
        "spec": "mixamo",
    })
    log["rig"] = rig_id
    log_path.write_text(json.dumps(log, indent=2))
    d = wait(rig_id, "骨入れ")
    download(model_url(d["output"]), out / "rigged.glb")

    print("3/3 アニメーション")
    for name in ANIMATIONS:
        tid = create({
            "type": "animate_retarget",
            "original_model_task_id": rig_id,
            "animation": f"preset:{name}",
            "out_format": "glb",
            "bake_animation": True,
            "animate_in_place": True,
        })
        log[f"anim_{name}"] = tid
        log_path.write_text(json.dumps(log, indent=2))
        d = wait(tid, name)
        download(model_url(d["output"]), out / f"anim_{name}.glb")

    print(f"完了。残高: {balance()}")


if __name__ == "__main__":
    main()
