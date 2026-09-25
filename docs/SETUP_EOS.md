# オンライン対戦(EOS)の準備手順

通信対戦は Epic Online Services(EOS)を使う。**費用は0円**(ロビー・P2P・中継サーバー・匿名ログインはすべて無料)。
作業するのは Epic Developer Portal のアカウントの持ち主。既存の Organization / Product はそのまま使ってよい。

> ⚠ Client Secret などの値はチャットやソースコードに書かない。GitHub の Secrets にだけ登録する。

## 1. Epic Developer Portal で行うこと(新しく必要なのはクライアントだけ)
https://dev.epicgames.com/portal

1. 使う Product を開く(既存のものでよい)
2. **Product Settings → Clients → Client Policies →「Add new client policy」**
   - 名前: `jape-mobile`(任意)
   - Client policy type: **Custom policy**
   - **User is required: ON**
   - 許可する機能は次の3つだけ(それぞれの Action はすべて許可):
     - **Connect**
     - **Lobbies**
     - **P2P**
3. **Clients →「Add new client」**
   - Client policy: 手順2の `jape-mobile`
   - 作成すると **Client ID** と **Client Secret** が表示される
   - 既存の Client を使い回す場合は、ポリシーが上と同じ内容になっていることを確認
4. **Product Settings → SDK Download & Credentials** で次を確認する(既存のものをそのまま使う):
   - **Product ID**
   - **Sandbox ID**(例: Live または Dev のサンドボックス)
   - **Deployment ID**(そのサンドボックスのデプロイメント)
5. Device ID(匿名ログイン)・ロビー・中継(リレー)は、ポータル側の設定は不要。
   Epic アカウントでのログインは使わないので、Epic Account Services の設定やブランド審査も不要。

## 2. GitHub Secrets に登録する
リポジトリのフォルダで(値は入力を求められる。画面にも履歴にも残らない):
```bash
gh secret set EOS_PRODUCT_ID
gh secret set EOS_SANDBOX_ID
gh secret set EOS_DEPLOYMENT_ID
gh secret set EOS_CLIENT_ID
gh secret set EOS_CLIENT_SECRET
```
ブラウザで登録する場合: GitHub のリポジトリ → Settings → Secrets and variables → Actions →「New repository secret」。

## 3. 仕組み(開発側のメモ)
- ビルド時に CI が `tools/eos/write_secrets.sh` で Secrets から `net/eos_secrets.gd` を作ってアプリに入れる。このファイルは `.gitignore` 済みでリポジトリには入らない
- EOS のクライアント用の認証情報は、仕組み上アプリの中に入る(Epic の想定どおり)。悪用を防ぐのはクライアントポリシーで、上の3機能しか使えないようにしている
- EOSG プラグイン(MIT)は `tools/eos/fetch_eosg.sh` がハッシュを確かめてから取得する。リポジトリには入れない
- Android は Gradle ビルド。`tools/eos/patch_android.py` が EOS SDK を組み込む
- PCで試すとき: `bash tools/eos/fetch_eosg.sh windows` のあと、環境変数 `EOS_PRODUCT_ID` などを設定して起動。
  同じPCで2つ起動するときは片方に `-- --eos-fresh-device` を付ける(別の人としてログインする)

## 4. 遊び方
1. 両方の端末でアプリを起動 →「オンライン対戦」
2. 片方が「部屋を作る」→ 画面に出た6桁のコードを相手に伝える
3. もう片方がコードを入れて「入る」→ つながると試合が始まる
