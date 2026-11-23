import type { events } from '../mock-data';

export type Theme = 'peach' | 'matcha' | 'butter';
export type Story =
  | { kind: 'ticket' | 'invite'; event: (typeof events)[number] & { participation?: string } }
  | { kind: 'crew'; crew?: { date: string; cafe: string; members: { name: string; emoji: string }[] } };

export function drawStory(canvas: HTMLCanvasElement, story: Story, theme: Theme) {
  const ctx = canvas.getContext('2d');
  if (!ctx) return;
  const W = 1080, H = 1920;

  const palettes = {
    peach:  { bg1: '#FFE8F0', bg2: '#FFF6EE', accent: '#E86A8D', card: '#FFFFFF', text: '#2D2622', muted: '#8E787F', pill: '#FFE8F0' },
    matcha: { bg1: '#E5F2E1', bg2: '#F7FAF4', accent: '#5D8A52', card: '#FFFFFF', text: '#253123', muted: '#6E7F6B', pill: '#EBF5E8' },
    butter: { bg1: '#FFF2C6', bg2: '#FFFDF4', accent: '#C69214', card: '#FFFFFF', text: '#312A1E', muted: '#8C7E66', pill: '#FFF5D6' }
  };
  const p = palettes[theme];

  const grad = ctx.createLinearGradient(0, 0, W, H);
  grad.addColorStop(0, p.bg1);
  grad.addColorStop(1, p.bg2);
  ctx.fillStyle = grad;
  ctx.fillRect(0, 0, W, H);

  ctx.fillStyle = p.accent + '22';
  ctx.beginPath(); ctx.arc(170, 380, 220, 0, Math.PI * 2); ctx.fill();
  ctx.beginPath(); ctx.arc(920, 1520, 260, 0, Math.PI * 2); ctx.fill();

  const cx = 110, cy = 320, cw = 860, ch = 1220, r = 64;
  ctx.fillStyle = p.card;
  ctx.shadowColor = 'rgba(45, 38, 34, 0.12)';
  ctx.shadowBlur = 48;
  ctx.shadowOffsetY = 20;
  roundRect(ctx, cx, cy, cw, ch, r);
  ctx.fill();
  ctx.shadowColor = 'transparent';

  ctx.fillStyle = p.accent;
  ctx.font = '800 54px "Plus Jakarta Sans", sans-serif';
  ctx.textAlign = 'center';
  ctx.fillText('koko.', W / 2, cy + 115);

  ctx.fillStyle = p.muted;
  ctx.font = '700 30px "Plus Jakarta Sans", sans-serif';
  ctx.fillText(story.kind !== 'crew' ? (story.kind === 'invite' ? 'KŌKYO YURU-RUN INVITE' : 'KŌKYO YURU-RUN TICKET') : "TODAY'S KŌKYO CREW", W / 2, cy + 168);

  ctx.strokeStyle = p.accent;
  ctx.lineWidth = 7;
  ctx.beginPath();
  ctx.ellipse(W / 2, cy + 365, 130, 145, 0, 0, Math.PI * 2);
  ctx.stroke();

  ctx.fillStyle = p.text;
  ctx.font = '900 42px "Zen Maru Gothic", sans-serif';
  ctx.fillText('皇居 1周', W / 2, cy + 378);

  ctx.save();
  ctx.setLineDash([16, 14]);
  ctx.strokeStyle = p.accent + '55';
  ctx.lineWidth = 4;
  ctx.beginPath();
  ctx.moveTo(cx + 50, cy + 580);
  ctx.lineTo(cx + cw - 50, cy + 580);
  ctx.stroke();
  ctx.restore();

  if (story.kind !== 'crew') {
    const ev = story.event;
    ctx.fillStyle = p.text;
    ctx.font = '900 64px "Zen Maru Gothic", sans-serif';
    ctx.fillText(ev.time, W / 2, cy + 700, cw - 100);

    ctx.fillStyle = p.accent;
    ctx.font = '800 44px "Zen Maru Gothic", sans-serif';
    ctx.fillText(`📍 ${ev.zone}エリア集合`, W / 2, cy + 785);

    ctx.fillStyle = p.pill;
    roundRect(ctx, cx + 110, cy + 845, cw - 220, 96, 48);
    ctx.fill();
    ctx.fillStyle = p.text;
    ctx.font = '700 36px "Zen Maru Gothic", sans-serif';
    ctx.fillText(`☕ ${ev.cafe}`, W / 2, cy + 907);

    ctx.fillStyle = p.muted;
    ctx.font = '700 32px "Zen Maru Gothic", sans-serif';
    ctx.fillText(`#${ev.vibe}   #タイムは測らない`, W / 2, cy + 1030);

    ctx.fillStyle = p.accent;
    ctx.font = '700 30px "Zen Maru Gothic", sans-serif';
    const caption = story.kind === 'invite' ? 'いっしょに走るひと募集中 🫧'
      : ev.participation === 'approved' ? '参加が決まったよ 🎟️' : '参加リクエストを送ったよ 🎟️';
    ctx.fillText(caption, W / 2, cy + 1125);
  } else {
    ctx.fillStyle = p.text;
    ctx.font = '900 54px "Zen Maru Gothic", sans-serif';
    ctx.fillText(story.crew ? `${story.crew.date} ゆるラン` : '日曜 9:00 ゆるラン完走！', W / 2, cy + 695, cw - 100);

    const crew = story.crew?.members ?? [
      { emoji: '🥐', name: 'みゆ' }, { emoji: '🎀', name: 'あおい' },
      { emoji: '🌷', name: 'かな' }, { emoji: '✨', name: 'わたし' }
    ];
    crew.forEach((m, i) => {
      const spacing = crew.length > 4 ? 130 : 182;
      const mx = story.crew ? W / 2 + (i - (crew.length - 1) / 2) * spacing : cx + 155 + i * 182;
      const my = cy + 845;
      ctx.fillStyle = p.pill;
      ctx.beginPath(); ctx.arc(mx, my, crew.length > 4 ? 54 : 66, 0, Math.PI * 2); ctx.fill();
      ctx.font = '60px sans-serif';
      ctx.fillText(m.emoji, mx, my + 22);
      ctx.fillStyle = p.text;
      ctx.font = '700 28px "Zen Maru Gothic", sans-serif';
      ctx.fillText(m.name, mx, my + 110, spacing - 10);
    });

    ctx.fillStyle = p.muted;
    ctx.font = '700 32px "Zen Maru Gothic", sans-serif';
    ctx.fillText(story.crew ? `☕ ${story.crew.cafe}` : '☕ 丸の内ベーカリーで朝活', W / 2, cy + 1060, cw - 100);
    ctx.fillStyle = p.accent;
    ctx.font = '700 30px "Plus Jakarta Sans", sans-serif';
    ctx.fillText('NO PACE • ONLY GOOD VIBES', W / 2, cy + 1135);
  }

  ctx.fillStyle = p.muted;
  ctx.font = '700 28px "Plus Jakarta Sans", sans-serif';
  ctx.fillText('@koko_run_tokyo', W / 2, 1615);
}

function roundRect(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number) {
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + w, y, x + w, y + h, r);
  ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r);
  ctx.arcTo(x, y, x + w, y, r);
  ctx.closePath();
}
