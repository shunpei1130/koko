'use client';

import { useEffect, useRef, useState } from 'react';
import { supabase } from './live-events';
import type { ZoneId } from '@/lib/geofence';

export type LiveMap = {
  zones: { zone: ZoneId; count: number; runners: { name: string; emoji: string }[] | null }[];
  self: { zone: ZoneId; expires_at: string } | null;
};

export type Encounter = {
  id: string; name: string; emoji: string; context: string; run_date: string;
  sent_stamps: string[]; they_sent: boolean; ig: string | null;
};

export type Crew = {
  starts_at: string; cafe: string; members: { name: string; emoji: string }[];
};

export function useLiveMap(userId: string | undefined, enabled: boolean) {
  const [snapshot, setSnapshot] = useState<{ userId: string | undefined; map: LiveMap } | null>(null);
  const [cheer, setCheer] = useState(0);
  const [failed, setFailed] = useState(false);
  const reload = useRef<(() => Promise<void>) | null>(null);

  useEffect(() => {
    if (!supabase || !enabled) return;
    const client = supabase;
    let active = true;
    let latest = 0;
    async function load() {
      const sequence = ++latest;
      const { data, error } = await client.rpc('koko_live_map');
      if (!active || sequence !== latest) return;
      if (!error) setSnapshot({ userId, map: data as LiveMap });
      setFailed(Boolean(error));
    }
    const channel = client.channel('koko-live-map')
      .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'koko_map_signal' }, () => { void load(); });
    if (userId) {
      channel.on('postgres_changes', {
        event: 'INSERT', schema: 'public', table: 'koko_cheers', filter: `receiver_id=eq.${userId}`,
      }, () => setCheer((count) => count + 1));
    }
    channel.subscribe((status) => { if (status === 'SUBSCRIBED') void load(); });
    const poll = window.setInterval(() => { void load(); }, 15_000);
    const onFocus = () => { void load(); };
    window.addEventListener('focus', onFocus);
    reload.current = load;
    void load();
    return () => {
      active = false;
      reload.current = null;
      window.clearInterval(poll);
      window.removeEventListener('focus', onFocus);
      void client.removeChannel(channel);
    };
  }, [userId, enabled]);

  return {
    map: snapshot && snapshot.userId === userId ? snapshot.map : null,
    cheer, failed, refresh: () => reload.current?.(),
  };
}
