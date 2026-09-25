# Google Play 内部テストへの提出準備

GitHub Actions の `android` ワークフローは、push時にデバッグAPKを確認する。以下の準備後に Actions の手動実行で、署名済みAABを `internal` トラックへ送る。追加の有料API購入は不要。

## 1. Play Console のアプリ

Play Consoleにゲーム「JAPE」を登録し、パッケージ名が `com.jape.game` であることを確認する。既存アプリで別のパッケージ名を使っている場合は、先に `export_presets.cfg` と送信スクリプトの指定を合わせる。アプリのセットアップ、Play App Signing、必要なストア掲載情報と申告をコンソール上で完了する。

## 2. アップロード鍵

既存アプリには、そのアプリで使っているアップロード鍵を使う。新規アプリで鍵がまだ無い場合、JDKの `keytool` で作成して安全な場所にバックアップする。例:

```bash
keytool -genkeypair -v -keystore jape-upload.jks -alias jape-upload -keyalg RSA -keysize 4096 -validity 10000
```

鍵とパスワードをチャットやリポジトリに貼らない。鍵を紛失すると、後続のリリースに影響する。

## 3. Google Play Developer API

Google Cloudで [Google Play Developer API](https://developers.google.com/android-publisher/getting_started) を有効にし、サービスアカウントを作る。Play Consoleの「ユーザーと権限」でそのメールアドレスを招待し、**JAPEだけ**に「テストトラックへのリリース」権限を与える。JSON鍵を取得して安全に保管する。

## 4. GitHub Actions Secrets

`555734/jape` の Settings → Secrets and variables → Actions に以下を登録する。ファイルはBase64で1行にして登録する。Git Bashでは `base64 -w0 ファイル名` を使える。

| Secret | 内容 |
|---|---|
| `ANDROID_UPLOAD_KEYSTORE_BASE64` | アップロード鍵 `jape-upload.jks` のBase64 |
| `ANDROID_UPLOAD_KEYSTORE_ALIAS` | 鍵のエイリアス |
| `ANDROID_UPLOAD_KEYSTORE_PASSWORD` | 鍵とkeystoreのパスワード（同じ値） |
| `PLAY_SERVICE_ACCOUNT_JSON_BASE64` | サービスアカウントJSONのBase64 |

## 5. 送信と確認

GitHub → Actions → `android` → `Run workflow` で対象ブランチを選ぶ。ワークフローはAndroid 16（API 36）向けのAABを生成し、署名を確認して内部テストへ送る。成功後、Play Consoleの「内部テスト」にリリースが表示されることを確認し、テスターを追加する。

初回リリース時にPlay Consoleが不足するアプリ情報や申告を示した場合は、事実に基づいて入力する。サービスアカウントの権限が不足していてもAPIでの送信は失敗する。
