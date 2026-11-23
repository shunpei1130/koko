import type { Metadata, Viewport } from 'next';
import './globals.css';

const siteUrl = process.env.NEXT_PUBLIC_SITE_URL
  ?? (process.env.VERCEL_PROJECT_PRODUCTION_URL ? `https://${process.env.VERCEL_PROJECT_PRODUCTION_URL}` : 'http://localhost:3000');

export const metadata: Metadata = {
  metadataBase: new URL(siteUrl),
  title: 'koko. — 皇居ゆるラン・コミュニティ',
  description: '皇居で、ゆるく走る仲間を見つけよう。',
  appleWebApp: { capable: true, title: 'koko.' },
  icons: { icon: '/icons/koko-192.png', apple: '/icons/koko-192.png' },
};

export const viewport: Viewport = {
  themeColor: '#FFFBF7',
  viewportFit: 'cover',
};

export default function Layout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="ja"><body>{children}</body></html>;
}
