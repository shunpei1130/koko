'use client';

import { useCallback, useEffect, useState } from 'react';
import { createClient, type Session } from '@supabase/supabase-js';
import { events, zones } from './mock-data';

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
export const supabase = url && key ? createClient(url, key) : null;

export type Participation = 'pending' | 'approved' | 'declined';
export type KokoEvent = (typeof events)[number] & { isHost?: boolean; participation?: Participation };
export type Applicant = { user_id: string; display_name: string; avatar_emoji: string; status: Participation };
export type Profile = {
  id: string; display_name: string; avatar_emoji: string;
  instagram_handle: string | null; allow_ig_preview: boolean;
};
type EventRow = {
  id: string; starts_at: string; meet_zone_id: string; cafe_name: string;
  vibe_tag: string; women_only: boolean; max_members: number; spots_left: number;
  host_name: string; host_emoji: string; is_host: boolean; participation: Participation | null;
};

export const avatars = ['🎀', '🌷', '🍑', '🥐', '☕', '✨', '🌿', '🫧'];
export const presets = [
  { label: '明日 7:30', weekday: null, hour: 7, minute: 30 },
  { label: '水曜 19:30', weekday: 3, hour: 19, minute: 30 },
  { label: '土曜 8:30', weekday: 6, hour: 8, minute: 30 },
  { label: '日曜 9:00', weekday: 0, hour: 9, minute: 0 },
];

export function toTokyoStart(label: string, now = Date.now()) {
  const preset = presets.find((option) => option.label === label);
  if (!preset) throw new Error('invalid_preset');
  const tokyoOffset = 9 * 60 * 60 * 1000;
  const day = new Date(now + tokyoOffset);
  const days = preset.weekday === null ? 1 : (preset.weekday + 7 - day.getUTCDay()) % 7;
  day.setUTCDate(day.getUTCDate() + days);
  day.setUTCHours(preset.hour, preset.minute, 0, 0);
  if (day.getTime() - tokyoOffset <= now) day.setUTCDate(day.getUTCDate() + 7);
  return new Date(day.getTime() - tokyoOffset).toISOString();
}

const dateLabel = new Intl.DateTimeFormat('ja-JP', {
  timeZone: 'Asia/Tokyo', month: 'numeric', day: 'numeric', weekday: 'short',
  hour: 'numeric', minute: '2-digit', hourCycle: 'h23',
});
export const formatTokyoStart = (date: string) => dateLabel.format(new Date(date));

export function mapEvent(row: EventRow): KokoEvent {
  return {
    id: row.id, time: formatTokyoStart(row.starts_at),
    zone: zones.find(({ id }) => id === row.meet_zone_id)?.name ?? row.meet_zone_id,
    cafe: row.cafe_name, vibe: row.vibe_tag, womenOnly: row.women_only,
    maxMembers: row.max_members, spotsLeft: row.spots_left, isHost: row.is_host,
    joined: row.is_host || Boolean(row.participation), participation: row.participation ?? undefined,
    category: ['cafe', ...(row.women_only ? ['women'] : []),
      ...(['初心者だけ', '歩き混じりOK'].includes(row.vibe_tag) ? ['beginner'] : [])],
    host: { name: row.host_name, emoji: row.host_emoji, ig: '', bio: '', tags: [row.vibe_tag] },
  };
}

export function useKokoEvents(inviteId?: string) {
  const [session, setSession] = useState<Session | null>(null);
  const [profile, setProfile] = useState<Profile | null>(null);
  const [loadedProfileId, setLoadedProfileId] = useState<string>();
  const [events, setEvents] = useState<KokoEvent[]>([]);
  const [loading, setLoading] = useState(Boolean(supabase));
  const [error, setError] = useState(false);
  const userId = session?.user.id;

  useEffect(() => {
    if (!supabase) return;
    const { data } = supabase.auth.onAuthStateChange((_event, nextSession) => setSession(nextSession));
    return () => data.subscription.unsubscribe();
  }, []);

  useEffect(() => {
    if (!userId || !supabase) return;
    let active = true;
    void supabase.from('profiles').select('id,display_name,avatar_emoji,instagram_handle,allow_ig_preview')
      .eq('id', userId).maybeSingle().then(({ data, error }) => {
      if (!active || error) return;
      setProfile(data);
      setLoadedProfileId(userId);
    });
    return () => { active = false; };
  }, [userId]);

  const refresh = useCallback(async () => {
    if (!supabase) return;
    const { data, error } = await supabase
      .rpc('list_koko_events', inviteId ? { target_event: inviteId } : {})
      .returns<EventRow[]>();
    if (!error && Array.isArray(data)) setEvents(data.map(mapEvent));
    setError(Boolean(error));
    setLoading(false);
  }, [inviteId]);

  useEffect(() => {
    if (!supabase) return;
    let active = true;
    let latest = 0;
    const client = supabase;
    async function load() {
      const sequence = ++latest;
      const { data, error } = await client.rpc('list_koko_events', inviteId ? { target_event: inviteId } : {}).returns<EventRow[]>();
      if (!active || sequence !== latest) return;
      if (!error && Array.isArray(data)) setEvents(data.map(mapEvent));
      setError(Boolean(error));
      setLoading(false);
    }
    const focus = () => { void load(); };
    const interval = window.setInterval(focus, 30_000);
    window.addEventListener('focus', focus);
    void load();
    return () => {
      active = false;
      window.removeEventListener('focus', focus);
      window.clearInterval(interval);
    };
  }, [inviteId, userId]);

  return {
    session, events, error, loading, refresh,
    profile: profile?.id === userId ? profile : null,
    profileLoading: Boolean(userId && loadedProfileId !== userId),
    hasProfile: Boolean(userId && profile?.id === userId), setProfile,
  };
}

export function writeError(error: { message: string } | null) {
  return error?.message === 'event_full' ? 'この募集は満席になったよ。'
    : error?.message === 'event_unavailable' ? 'この募集の受付は終了したよ。'
      : 'うまく反映できなかったよ。もう一度試してね。';
}
