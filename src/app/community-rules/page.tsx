import Link from 'next/link';

export const metadata = { title: 'コミュニティルール | koko.' };

export default function CommunityRulesPage() {
  return (
    <main className="mx-auto my-8 max-w-xl rounded-3xl bg-white p-6 leading-relaxed">
      <Link href="/">← koko. ホーム</Link>
      <h1 className="mt-5 text-2xl font-black">コミュニティルール</h1>
      <p className="mt-3">koko. は、初めての人も自分のペースで参加できるゆるランの場です。</p>
      <ul className="mt-4 list-disc space-y-2 pl-6">
        <li>嫌がらせ、差別、脅迫、無断での撮影・個人情報の公開を禁止します。</li>
        <li>しつこい勧誘、スパム、なりすまし、他の参加者を危険にさらす行為を禁止します。</li>
        <li>不安なときは無理に参加せず、iOSアプリの「安全メニュー」から通報・ブロックできます。緊急時は現地の緊急窓口へ連絡してください。</li>
        <li>運営は通報を確認し、必要に応じて表示内容の削除や利用停止を行います。</li>
      </ul>
      <p className="mt-5">運営窓口 <a className="underline" href="mailto:info.mobbymobbymobby@gmail.com">info.mobbymobbymobby@gmail.com</a></p>
      <p className="mt-2"><Link className="underline" href="/privacy">プライバシーポリシー</Link></p>
    </main>
  );
}
