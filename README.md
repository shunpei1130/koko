# koko.

皇居でゆるく走る仲間を見つけるコミュニティPWAです。

## ローカルで確認する

Node.js 24 を使います。

```sh
npm ci
npm run dev
```

ブラウザで http://localhost:3000 を開きます。Supabaseの環境変数なしでも、モックデータで3画面とPNG保存を確認できます。マップの「開発用シミュレーション」で区画またはエリア外を選んでから、ヘッダーの「いま走ってる」を試せます。シミュレーション中の区画はSupabaseに書き込まれません。

```sh
npm run build
npm run start
```

PWAのホーム画面追加とオフライン案内は、本番ビルドをlocalhostまたはHTTPSで開いて確認できます。

仕様は [HANDOVER.md](HANDOVER.md)、Vercel設定は [docs/deployment.md](docs/deployment.md) を参照してください。
