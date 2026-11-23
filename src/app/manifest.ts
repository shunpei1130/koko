import type { MetadataRoute } from 'next';

export default function manifest(): MetadataRoute.Manifest {
  return {
    id: '/',
    name: 'koko. — 皇居ゆるラン・コミュニティ',
    short_name: 'koko.',
    lang: 'ja',
    start_url: '/',
    scope: '/',
    display: 'standalone',
    background_color: '#FFFBF7',
    theme_color: '#FFFBF7',
    icons: [
      { src: '/icons/koko-192.png', sizes: '192x192', type: 'image/png' },
      { src: '/icons/koko-512.png', sizes: '512x512', type: 'image/png' },
      { src: '/icons/koko-maskable.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' },
    ],
  };
}
