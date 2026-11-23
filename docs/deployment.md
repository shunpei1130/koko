# VercelとSupabaseの設定

## ローカル開発

環境変数なしで起動するとデモデータを表示します。Supabaseに接続する場合は `.env.example` を `.env.local` にコピーし、SupabaseのConnect画面からプロジェクトURLとpublishable keyを設定します。

## Vercel Preview・Production

1. Vercelの `shunpei1130s-projects/koko` で GitHub の `shunpei1130/koko` を接続します。フレームワークはNext.js、ルートディレクトリはリポジトリ直下です。
2. VercelのSupabase Integrationで `koko` とTokyoリージョンのSupabaseプロジェクトを接続します。本番の参照IDは `uineosvdldnurtaemnrk` です。
3. Project Settings → Environment Variablesで `NEXT_PUBLIC_SUPABASE_URL` と `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` が対象環境に設定されていることを確認します。Previewで認証や書き込みを検証する場合は検証用のSupabase環境を使います。
4. `NEXT_PUBLIC_SITE_URL` は独自ドメインなどを招待OGPのURLに使う場合に設定します。未設定時はVercelの本番URLを使います。
5. 変数を更新したら再デプロイします。本番公開前に、メールのワンタイムコード、2アカウント間の招待と承認、位置情報の送信項目、Instagramハンドルの公開範囲を確認します。

`NEXT_PUBLIC_` で始まる変数はブラウザに公開されます。Supabaseのsecret keyとservice role keyは設定値に使わず、`.env.local` はGit管理外に置きます。

[Supabase公式のVercel連携手順](https://supabase.com/partners/catalog/vercel)

## データベースとメール認証

1. 新規環境では `supabase/migrations/` のファイルを日時順に適用します。既存の環境では適用履歴とテーブルを確認し、未適用分だけを実行します。`supabase/schema.sql` は設計時の参照ファイルです。
2. Supabaseの Authentication → Providers でEmailを有効にします。Authentication → Email Templates → Magic Link に `{{ .Token }}` を入れ、メール本文にワンタイムコードを表示します。
3. 一般ユーザーにメールを届けるため、独自のSMTPを設定します。ProductionとPreviewで、別々の受信アドレスを使い、アカウント作成と再ログインを試します。

[Supabase公式のメールOTP設定](https://supabase.com/docs/guides/auth/auth-email-passwordless) · [Supabase公式のSMTP設定](https://supabase.com/docs/guides/auth/auth-smtp)

### Resendを使う場合

Resendで認証したドメインの送信元アドレスを指定します。Supabase SMTP Settingsで、ホストに `smtp.resend.com`、ポートに `465`、ユーザー名に `resend` を入力します。送信専用のResend APIキーはSupabaseのSMTPパスワード欄で管理します。

[Resend公式のSupabase SMTP設定](https://resend.com/docs/send-with-supabase-smtp)
