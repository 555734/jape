#!/usr/bin/env bash
# EOSG(Epic Online Services Godot)プラグインを取ってきて addons/ に入れる。
# プラグイン本体(MIT)と EOS SDK のバイナリは大きい(全部で約500MB)ので、リポジトリには入れず、
# 決まった版をハッシュで確かめてから使う。
#   使い方: tools/eos/fetch_eosg.sh linux|android|ios|windows|macos [...]
set -euo pipefail
VERSION="2.3.1"
COMMIT="56238973e2cd7ac9ac99ca14f88934465f0a8997"
sha_for() {   # macOS の bash 3 でも動くよう、連想配列は使わない
  case "$1" in
    linux) echo 76f7afcd01247abbba140d0f6f9d8d4e3524a20e84e08af0acd124238d2575d4 ;;
    android) echo c29489008369a6f695d261f2e378c79e67fbb9bedb45cda102c6949afe58f851 ;;
    ios) echo a3b02efee7e94143be9f152d48190c2bb58d80af3780c4e70d90083f1b7a5a62 ;;
    windows) echo 929d1fcb24c9f10834408f5c9fb80d76a6c942b2deadff553ff3f0ff57a30ee1 ;;
    macos) echo 9b61338266dd883f8ff05be72322e0c54e618078c1269bc8952220e4002c33f7 ;;
    *) echo "unknown platform: $1" >&2; exit 1 ;;
  esac
}
root="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
for platform in "$@"; do
  name="epic-online-services-godot-${platform}-${COMMIT}.zip"
  echo "EOSG ${VERSION} (${platform}) を取得"
  curl -sSL -o "$tmp/$name" "https://github.com/3ddelano/epic-online-services-godot/releases/download/${VERSION}/${name}"
  echo "$(sha_for "$platform")  $tmp/$name" | shasum -a 256 -c -
  rm -rf "$tmp/x" && mkdir -p "$tmp/x"
  unzip -q "$tmp/$name" -d "$tmp/x"
  src="$(dirname "$(find "$tmp/x" -type f -name eosg.gdextension | head -1)")"
  mkdir -p "$root/addons/epic-online-services-godot"
  cp -R "$src/." "$root/addons/epic-online-services-godot/"
done
echo "$VERSION" > "$root/addons/epic-online-services-godot/VERSION"
