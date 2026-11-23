import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { ImageResponse } from 'next/og';
import { publicInvite } from '@/lib/public-invite';

export const alt = 'koko. 皇居ゆるランへの招待';
export const size = { width: 1200, height: 630 };
export const contentType = 'image/png';

export default async function InviteImage({ params }: { params: Promise<{ eventId: string }> }) {
  const { eventId } = await params;
  const [invite, font] = await Promise.all([
    publicInvite(eventId), readFile(join(process.cwd(), 'assets', 'koko-invite.ttf')),
  ]);
  return new ImageResponse(
    <div style={{
      display: 'flex', width: '100%', height: '100%', alignItems: 'center', justifyContent: 'center',
      backgroundImage: 'linear-gradient(135deg, #FFE8F0 0%, #FFF6EE 52%, #F0F6EE 100%)',
      color: '#2D2622', fontFamily: 'Koko',
    }}>
      <div style={{
        display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center',
        gap: 14, width: 970, height: 492, padding: 38, borderRadius: 56, backgroundColor: '#FFFBF7',
        border: '2px solid #F1E6DC', boxShadow: '0 15px 50px #BE8E9B45',
      }}>
        <div style={{ display: 'flex', alignItems: 'baseline', fontSize: 65, color: '#B53B5E' }}>koko.</div>
        <div style={{ fontSize: 44 }}>皇居ゆるランへの招待</div>
        <div style={{ width: '86%', borderTop: '2px dashed #F1CFD9', margin: '5px 0' }} />
        {invite ? <>
          <div style={{ fontSize: 40 }}>{`${invite.date}　${invite.zone}集合`}</div>
          <div style={{ fontSize: 30, color: '#6E7F6B' }}>{`アフターカフェ　${invite.cafe}`}</div>
        </> : <div style={{ fontSize: 32, color: '#6E7F6B' }}>皇居で、ゆるく走る仲間を見つけよう。</div>}
      </div>
    </div>,
    {
      ...size,
      fonts: [{ name: 'Koko', data: new Uint8Array(font).buffer, weight: 700, style: 'normal' }],
      headers: { 'Cache-Control': 'public, max-age=60, s-maxage=60' },
    },
  );
}
