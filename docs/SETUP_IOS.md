# iPhone版(TestFlight)の準備手順 — Windowsだけで行う

GitHub Actions の `ios` ワークフローが使う7つの Secrets を作る手順。Macは不要。
作業するのは Apple Developer Program に登録したアカウントの持ち主。

> ⚠ ここで作る鍵やパスワードはチャットに貼らないこと。GitHubの Secrets にだけ登録する。

## 0. 必要なもの
- Git for Windows(付属の「Git Bash」で `openssl` が使える)
- Apple Developer Program に登録済みのアカウント

## 1. 署名用の鍵と証明書リクエスト(CSR)を作る
Git Bash で:
```bash
mkdir ~/ios-keys && cd ~/ios-keys
openssl genrsa -out dist.key 2048
openssl req -new -key dist.key -out dist.csr -subj "/emailAddress=あなたのメール/CN=jape/C=JP"
```

## 2. 配布用証明書を発行する
1. https://developer.apple.com/account/resources/certificates/list →「+」
2. 「Apple Distribution」を選び、`dist.csr` をアップロード
3. できた `distribution.cer` をダウンロードして `~/ios-keys` に置く
4. Git Bash で p12 形式にまとめる(パスワードは自分で決める):
```bash
openssl x509 -inform DER -in distribution.cer -out dist.pem
openssl pkcs12 -export -legacy -inkey dist.key -in dist.pem -out dist.p12
```

## 3. App ID を登録する
1. Identifiers →「+」→「App IDs」→「App」
2. Bundle ID は Explicit で **`com.jape.game`**(export_presets.cfg と同じ)

## 4. プロビジョニングプロファイルを作る
1. Profiles →「+」→ Distribution の「App Store Connect」
2. App ID に `com.jape.game`、証明書に手順2のものを選ぶ
3. ダウンロードした `.mobileprovision` を `~/ios-keys` に置く

## 5. App Store Connect にアプリを作る
1. https://appstoreconnect.apple.com →「マイApp」→「+」→「新規App」
2. プラットフォーム iOS、バンドルID `com.jape.game`、SKU は任意(例 `jape`)

## 6. App Store Connect APIキーを作る
1. App Store Connect →「ユーザとアクセス」→「統合」→「App Store Connect API」
2. 「チームキー」を作成(アクセス権は「App Manager」)
3. `AuthKey_XXXXXXXXXX.p8` をダウンロード(1回しかダウンロードできない)
4. 画面に出る **キーID** と **Issuer ID** を控える

## 7. GitHub Secrets に登録する
Git Bash で Base64 文字列にする:
```bash
base64 -w0 dist.p12 > dist.p12.txt
base64 -w0 *.mobileprovision > profile.txt
base64 -w0 AuthKey_*.p8 > key.txt
```
GitHub のリポジトリ → Settings → Secrets and variables → Actions →「New repository secret」で登録:

| 名前 | 中身 |
|---|---|
| `IOS_CERT_P12_BASE64` | `dist.p12.txt` の中身 |
| `IOS_CERT_PASSWORD` | 手順2で決めたパスワード |
| `IOS_PROVISION_PROFILE_BASE64` | `profile.txt` の中身 |
| `APPLE_TEAM_ID` | Apple Developer の Membership に表示される10文字のチームID |
| `ASC_KEY_ID` | 手順6のキーID |
| `ASC_ISSUER_ID` | 手順6の Issuer ID |
| `ASC_KEY_P8_BASE64` | `key.txt` の中身 |

## 8. 実行する
GitHub → Actions →「ios」→「Run workflow」。成功すると10〜30分後に App Store Connect の TestFlight にビルドが表示される。
TestFlight で iPhone 担当の人をテスターに追加すると、TestFlightアプリからインストールできる。

## 注意
- このワークフローは Secrets 登録前は動かせないため、**まだ一度も成功を確認していない**。最初の実行で失敗したら、ログを見て直す。
