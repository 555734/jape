#!/usr/bin/env bash
# CI 用: GitHub Secrets(環境変数 EOS_*)から res://net/eos_secrets.gd を作る。
# このファイルは .gitignore 済みでリポジトリには入らない。値はログに出さない。
# どれかが空なら作らずに警告だけ出す(そのビルドではオンライン対戦が使えない)。
set -euo pipefail
out="$(cd "$(dirname "$0")/../.." && pwd)/net/eos_secrets.gd"
missing=""
for v in EOS_PRODUCT_ID EOS_SANDBOX_ID EOS_DEPLOYMENT_ID EOS_CLIENT_ID EOS_CLIENT_SECRET; do
  [ -z "${!v:-}" ] && missing="$missing $v"
done
if [ -n "$missing" ]; then
  echo "::warning::EOS の Secrets が未登録のため、オンライン対戦なしでビルドします:$missing"
  rm -f "$out"
  exit 0
fi
# 端末内の保存データ用の暗号鍵(このゲームは保存データを使わないので、ビルドごとに作ってよい)
key="${EOS_ENCRYPTION_KEY:-$(openssl rand -hex 32)}"
esc() { printf '%s' "$1" | sed -e 's/\/\\/g' -e 's/"/\\"/g'; }
{
  echo "extends RefCounted"
  echo "## CI が GitHub Secrets から作ったファイル。コミットしないこと。"
  echo "const PRODUCT_ID := \"$(esc "$EOS_PRODUCT_ID")\""
  echo "const SANDBOX_ID := \"$(esc "$EOS_SANDBOX_ID")\""
  echo "const DEPLOYMENT_ID := \"$(esc "$EOS_DEPLOYMENT_ID")\""
  echo "const CLIENT_ID := \"$(esc "$EOS_CLIENT_ID")\""
  echo "const CLIENT_SECRET := \"$(esc "$EOS_CLIENT_SECRET")\""
  echo "const ENCRYPTION_KEY := \"$key\""
} > "$out"
echo "net/eos_secrets.gd を作成しました"
