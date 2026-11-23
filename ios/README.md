# koko. iOS

SwiftUI製のiPhoneアプリです。Web版と同じSupabaseを使い、メールのワンタイムコードで登録・ログインできます。Web版の既存アカウントも使えます。

iOSアプリでは、募集の閲覧・作成、参加申請と承認、定例のフォロー、到着共有、スタンプ、招待リンクの共有、通報・ブロック、アカウント削除ができます。集合マップは8区画の目安を表示します。プロフィール編集、ライブ在圏表示、ストーリーカードはWeb版の機能です。

## Macで起動

1. Xcodeと[XcodeGen](https://github.com/yonaskolb/XcodeGen)を用意します。
2. このフォルダで `xcodegen generate` を実行し、生成された `Koko.xcodeproj` をXcodeで開きます。
3. `Koko` を選び、iOS 17以降のiPhoneシミュレーターで実行します。接続先は公開済みの環境です。募集作成など実データに影響する確認は、必要に応じて検証用の環境で行ってください。

署名を行わずにビルドを確認する場合は、次を実行します。GitHub Actionsの「iOS Build」も同じ確認を行います。

```sh
xcodebuild -project Koko.xcodeproj -scheme Koko -configuration Release \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

`Config.xcconfig` にはSupabaseの公開用キーを設定しています。サービスロールキーなどの秘密鍵はアプリやリポジトリに入れないでください。

## 友達のApple Developerアカウントから配布

1. 友達が組織アカウントなら、App Store Connectから自分のApple Accountを招待してもらい、署名と提出に必要な権限を付けてもらいます。個人アカウントなら、アカウント保有者に署名とアップロードを担当してもらいます。 [Appleのアカウントとロールの案内](https://developer.apple.com/help/app-store-connect/manage-your-team/overview-of-accounts-and-roles/)
2. `Local.xcconfig` を作成して、以下の値を友達のチーム情報に合わせます。Bundle IDはApp Store Connectで使うものと一致させます。

   ```xcconfig
   DEVELOPMENT_TEAM = YOUR_TEAM_ID
   PRODUCT_BUNDLE_IDENTIFIER = com.example.koko
   ```

3. Xcodeの Signing & Capabilities で正しいTeamを確認し、iPhone実機で起動します。募集一覧、OTPログイン、参加申請、フォロー、到着共有、招待リンクを確認します。
4. App Store Connectにアプリを登録し、Xcodeで Archive → Distribute App からアップロードします。TestFlightで配布を確認した後、App Reviewに提出します。 [Appleの配布手順](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-workflow/)

## App Store提出前

- プライバシーポリシーは [koko. プライバシーポリシー](https://koko-mu-orcin.vercel.app/privacy)、サポートURLは [コミュニティルールと運営窓口](https://koko-mu-orcin.vercel.app/community-rules) を入力します。`PrivacyInfo.xcprivacy` と実際の運用をもとにプライバシー回答を登録します。
- 審査用の専用アカウントと、審査担当者がメールOTPを取得できる方法を用意します。App Review Informationの備考に、募集作成・承認、スタンプ、通報・ブロック、アカウント削除の確認手順を記載します。削除を確認するアカウントは別に用意します。 [App Reviewガイドライン](https://developer.apple.com/app-store/review/guidelines/)
- 実機では、2アカウントで募集作成→参加申請→承認→スタンプの順に確認します。ブロック後は互いの募集・申請・スタンプが見えないことを確認します。削除は検証用アカウントだけで行います。

## 運営が通報を確認する

通報はSupabaseの非公開テーブルに記録します。権限のある運営担当者がダッシュボードのSQL Editorから未確認の通報を確認し、問い合わせがあれば上記の窓口で対応します。

```sql
select id, reporter, reported, event_id, reason, created_at
from koko_private.community_reports
where state = 'open'
order by created_at;
```

確認後は対象のレコードIDを指定して `state` を `reviewed` または `resolved` に更新します。表示名のフィルター語句は `koko_private.blocked_name_terms` で管理できます。公開前に、通報の担当者と確認頻度を決めてください。
