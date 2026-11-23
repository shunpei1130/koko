'use client';

import { useCallback, useEffect, useState } from 'react';
import { formatTokyoStart, supabase, writeError, type KokoEvent } from './live-events';
import { zones } from './mock-data';

type Connection = { partner: string; name: string; emoji: string; enabled: boolean };
type Notice = { event_id: string; name: string; starts_at: string; zone_id: string };
type Arrived = { name: string; emoji: string; is_self: boolean };

export function RunAgain({ notify }: { notify: (message: string) => void }) {
  const [connections, setConnections] = useState<Connection[]>([]);
  const [notices, setNotices] = useState<Notice[]>([]);
  const [busy, setBusy] = useState(false);
  const [failed, setFailed] = useState(false);

  const load = useCallback(async () => {
    if (!supabase) return;
    const [people, events] = await Promise.all([
      supabase.rpc('koko_again_connections'), supabase.rpc('koko_again_events'),
    ]);
    if (Array.isArray(people.data)) setConnections(people.data);
    if (Array.isArray(events.data)) setNotices(events.data);
    setFailed(Boolean(people.error || events.error));
  }, []);

  useEffect(() => {
    void load();
    const timer = window.setInterval(() => void load(), 30_000);
    return () => window.clearInterval(timer);
  }, [load]);

  async function toggle(connection: Connection) {
    if (!supabase || busy) return;
    setBusy(true);
    try {
      const { error } = await supabase.rpc('koko_set_again', {
        partner: connection.partner, enabled: !connection.enabled,
      });
      if (error) { notify(writeError(error)); return; }
      await load();
    } finally { setBusy(false); }
  }

  if (connections.length === 0 && notices.length === 0 && !failed) return null;
  return <section aria-label="また走ろ" className="person-card grid gap-3">
    <h2 className="text-sm font-black">また走ろ☕</h2>
    {failed && <p className="crew-note" role="status">お知らせを更新できなかったよ。</p>}
    {notices.map((notice) => <a key={notice.event_id} href={`/invite/${notice.event_id}`} className="btn btn-soft">
      {notice.name}さんの募集 · {formatTokyoStart(notice.starts_at)} · {zones.find(({ id }) => id === notice.zone_id)?.name}
    </a>)}
    {connections.map((person) => <div key={person.partner} className="flex flex-wrap items-center justify-between gap-2">
      <span className="text-sm">{person.emoji} {person.name}</span>
      <button className={`btn ${person.enabled ? 'btn-primary' : 'btn-soft'}`} aria-pressed={person.enabled}
        aria-label={`${person.name}さんの募集のお知らせ`}
        disabled={busy} onClick={() => void toggle(person)}>
        {person.enabled ? 'お知らせON' : 'お知らせを受け取る'}
      </button>
    </div>)}
  </section>;
}

export function Arrival({ event, onClose }: { event: KokoEvent; onClose: () => void }) {
  const [people, setPeople] = useState<Arrived[]>([]);
  const [message, setMessage] = useState('');
  const [busy, setBusy] = useState(false);
  const load = useCallback(async () => {
    if (!supabase) return;
    const { error, data } = await supabase.rpc('koko_arrivals', { target_event: event.id });
    if (error) { setMessage(writeError(error)); return; }
    if (Array.isArray(data)) setPeople(data);
  }, [event.id]);
  useEffect(() => {
    void load();
    const timer = window.setInterval(() => void load(), 15_000);
    return () => window.clearInterval(timer);
  }, [load]);

  const here = people.some((person) => person.is_self);
  async function report() {
    if (!supabase || busy) return;
    setBusy(true);
    try {
      const { error } = await supabase.rpc('koko_set_arrived', { target_event: event.id, arrived: !here });
      if (error) { setMessage(writeError(error)); return; }
      setMessage('');
      await load();
    } finally { setBusy(false); }
  }

  return <div className="grid gap-3">
    <p className="text-sm">{event.time} · {event.zone}集合</p>
    <p className="crew-note">到着の表示は当日の主催者と承認済みの参加者にだけ見えます。</p>
    {people.length > 0 && <ul className="tags-inline" aria-label="到着した仲間">
      {people.map((person, index) => <li key={index} className="mini-tag">{person.emoji} {person.is_self ? 'あなた' : person.name}</li>)}
    </ul>}
    {message && <p role="status">{message}</p>}
    <button className={`btn sheet-action ${here ? 'btn-soft' : 'btn-peach'}`} disabled={busy}
      onClick={() => void report()}>{here ? '到着を取り消す' : '着いたよ'}</button>
    <button className="btn btn-soft" onClick={onClose}>募集一覧へ戻る</button>
  </div>;
}
