'use client';

import { useCallback, useEffect, useState } from 'react';
import { formatTokyoStart, supabase, writeError } from './live-events';
import type { Crew, Encounter } from './live-community';
import { stampTypes } from './mock-data';
import type { Story } from './story/draw';

export function LiveOtsurun({ userId, notify, onSignIn, onStory }: {
  userId?: string;
  notify: (message: string) => void;
  onSignIn: () => void;
  onStory: (story: Story) => void;
}) {
  const [encounters, setEncounters] = useState<Encounter[]>([]);
  const [crew, setCrew] = useState<Crew | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async (isActive: () => boolean) => {
    if (!supabase || !userId) return;
    const [list, latestCrew] = await Promise.all([
      supabase.rpc('koko_otsurun'), supabase.rpc('koko_today_crew'),
    ]);
    if (!isActive()) return;
    if (!list.error && Array.isArray(list.data)) setEncounters(list.data as Encounter[]);
    if (!latestCrew.error) setCrew(latestCrew.data as Crew | null);
    setError(Boolean(list.error || latestCrew.error));
    setLoading(false);
  }, [userId]);

  useEffect(() => {
    let active = true;
    const refresh = () => { void load(() => active); };
    refresh();
    const timer = window.setInterval(refresh, 30_000);
    window.addEventListener('focus', refresh);
    return () => {
      active = false;
      window.removeEventListener('focus', refresh);
      window.clearInterval(timer);
    };
  }, [load]);

  async function send(person: Encounter, stamp: string) {
    if (!supabase || busy || person.sent_stamps.includes(stamp)) return;
    setBusy(true);
    try {
      const { error } = await supabase.rpc('send_koko_stamp', {
        recipient: person.id, encounter_day: person.run_date, stamp,
      });
      if (error) { notify(writeError(error)); return; }
      await load(() => true);
      notify(person.they_sent && person.sent_stamps.length === 0
        ? `${person.name}さんと相互おつラン成立！` : `${person.name}さんにスタンプを送ったよ`);
    } finally { setBusy(false); }
  }

  return <section className="tab-panel active" aria-label="おつラン！">
    {!userId ? <div className="person-card">
      <p className="mb-2">ログインすると、一緒に走った仲間にスタンプを送れるよ。</p>
      <button className="btn btn-primary" onClick={onSignIn}>メールでログイン</button>
    </div> : <>
      {crew && <button className="crew-banner w-full text-left" onClick={() => onStory({
        kind: 'crew', crew: { date: formatTokyoStart(crew.starts_at), cafe: crew.cafe, members: crew.members },
      })}>
        <span>
          <span className="crew-kicker block">TODAY'S CREW CARD</span>
          <span className="crew-title block">今日のゆるラン仲間を見る</span>
          <span className="crew-note block">9:16でストーリー保存</span>
        </span><span className="text-[26px]">📸</span>
      </button>}
      {loading && <p className="map-help" role="status">おつラン仲間を読み込み中…</p>}
      {error && <p className="map-help" role="status">おつランの情報を更新できなかったよ。</p>}
      {!error && !loading && !crew && encounters.length === 0 && <p className="map-help">一緒に走った仲間がここに表示されるよ。</p>}
      {encounters.map((person) => <article className="person-card" key={person.id}>
        <div className="person-head">
          <div className="flex items-center gap-2.5"><span className="avatar">{person.emoji}</span>
            <div><h2 className="text-sm font-black">{person.name}</h2><p className="crew-note">{person.context}</p></div>
          </div>
          {person.they_sent && <span className="pill pill-peach">相手からも届いてる♡</span>}
        </div>
        <div className="stamp-grid">{stampTypes.map(({ id, label }) => {
          const sent = person.sent_stamps.includes(id);
          return <button key={id} className={`stamp-btn ${sent ? 'sent' : ''}`} aria-pressed={sent}
            disabled={busy || sent} onClick={() => void send(person, id)}>{label}</button>;
        })}</div>
        {person.ig && <div className="ig-unlocked">
          <span>相互おつラン成立！IG解放 ✨</span>
          <a className="btn btn-soft" href={`https://www.instagram.com/${encodeURIComponent(person.ig)}/`}
            target="_blank" rel="noreferrer">@{person.ig}</a>
        </div>}
      </article>)}
    </>}
  </section>;
}
