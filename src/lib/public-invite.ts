import { zones } from '@/features/mock-data';

export function isEventId(value: string) {
  return /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(value);
}

export async function publicInvite(id: string) {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
  if (!url || !key || !isEventId(id)) return null;

  try {
    const response = await fetch(new URL('/rest/v1/rpc/list_koko_events', url), {
      method: 'POST',
      headers: { apikey: key, 'Content-Type': 'application/json' },
      body: JSON.stringify({ target_event: id }),
      cache: 'no-store',
      signal: AbortSignal.timeout(3000),
    });
    if (!response.ok) return null;
    const [row] = await response.json() as { starts_at: string; meet_zone_id: string; cafe_name: string }[];
    if (!row) return null;
    const zone = zones.find(({ id }) => id === row.meet_zone_id);
    if (!zone) return null;

    return {
      date: new Intl.DateTimeFormat('ja-JP', {
        timeZone: 'Asia/Tokyo', month: 'numeric', day: 'numeric', weekday: 'short',
        hour: 'numeric', minute: 'numeric', hourCycle: 'h23',
      }).format(new Date(row.starts_at)),
      zone: zone.name,
      cafe: row.cafe_name,
    };
  } catch {
    return null;
  }
}
