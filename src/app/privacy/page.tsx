import Link from 'next/link';

export const metadata = { title: 'プライバシーポリシー | koko.' };

export default function PrivacyPage() {
  return (
    <main className="mx-auto my-8 max-w-xl rounded-3xl bg-white p-6 leading-relaxed">
      <Link href="/">← koko. ホーム</Link>
      <h1 className="mt-5 text-2xl font-black">プライバシーポリシー</h1>
      <p className="mt-3">koko. は皇居周辺のランニング募集と参加者同士の交流を提供します。</p>
      <h2 className="mt-5 font-bold">取り扱う情報</h2>
      <p>ログイン用のメールアドレス、表示名とアイコン、任意のInstagramアカウント、募集・参加申請、スタンプ、フォロー、到着表示、通報やブロックの情報を取り扱います。メールアドレスは認証に使用し、募集やプロフィールには表示しません。</p>
      <h2 className="mt-5 font-bold">表示される範囲</h2>
      <p>募集には主催者の表示名とアイコンが表示されます。到着表示は当日の主催者と承認済み参加者に限ります。Instagramは相互スタンプが成立した相手、または本人が募集での公開を許可した場合に表示されます。通報は運営対応に使います。</p>
      <h2 className="mt-5 font-bold">位置情報</h2>
      <p>Web版でラン中表示を使う場合、端末内でエリアを判定し、サービスへ送るのはエリアIDです。正確な緯度・経度は送信しません。ラン中表示は最終更新から90分で失効します。iOSアプリの集合マップは端末の現在地を取得しません。</p>
      <h2 className="mt-5 font-bold">外部サービスと保存</h2>
      <p>データベースと認証にSupabase、Web配信にVercel、認証メールの配信にBrevo、iOS版の地図表示にAppleの地図サービスを使用します。iOS版はログイン情報を端末のキーチェーンに、募集の保存情報を端末内に保管します。</p>
      <h2 className="mt-5 font-bold">アカウントの削除</h2>
      <p>iOS版の「アカウント」からアカウントを削除できます。WebとiOSで共通のログイン情報、プロフィール、主催募集、参加・交流に関するアカウント紐づけデータが削除されます。通報記録は削除されたアカウントへの参照を外したうえで、運営対応のために残る場合があります。</p>
      <h2 className="mt-5 font-bold">お問い合わせ</h2>
      <p><a className="underline" href="mailto:info.mobbymobbymobby@gmail.com">info.mobbymobbymobby@gmail.com</a></p>
    </main>
  );
}
