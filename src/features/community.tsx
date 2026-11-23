'use client';

import { createContext, useCallback, useContext, useEffect, useId, useRef, useState, type ReactNode } from 'react';
import { EmailSignIn, ProfileForm } from './account';
import { formatTokyoStart, presets, supabase, toTokyoStart, useKokoEvents, writeError, type Applicant, type KokoEvent } from './live-events';
import { useLiveMap } from './live-community';
import { LiveOtsurun } from './otsurun';
import { locateKokoZone } from '@/lib/geofence';
import { events, otsurunPeople, stampTypes, zones } from './mock-data';
import { drawStory, type Story, type Theme } from './story/draw';

type Event = KokoEvent;
type Tab = 'discover' | 'map' | 'otsurun';
type Zone = (typeof zones)[number];
type Panel = { kind: 'create' | 'account' } | { kind: 'host' | 'requests'; event: Event } | { kind: 'zone'; zone: Zone } | { kind: 'story'; story: Story };
const filters = [['all', 'すべて'], ['women', '女性限定'], ['cafe', 'カフェ目的'], ['beginner', '初心者歓迎']];
const tabs = [
  { id: 'discover', emoji: '🎟️', label: 'みつける' },
  { id: 'map', emoji: '🗺️', label: 'マップ' },
  { id: 'otsurun', emoji: '🫧', label: 'おつラン！' },
] as const;
const initialDraft = {
  time: '日曜 9:00', zone: '竹橋', cafe: '丸の内ベーカリー',
  vibe: 'おしゃべりペース', womenOnly: true, capacity: 4,
};
const debugLocation = process.env.NODE_ENV === 'development';
const SheetFeedback = createContext('');
const themes: { id: Theme; label: string; background: string; color: string }[] = [
  { id: 'peach', label: 'Peach', background: '#FFE4EC', color: '#B53B5E' },
  { id: 'matcha', label: 'Matcha', background: '#E6F2E2', color: '#3D5F33' },
  { id: 'butter', label: 'Butter', background: '#FFF3CC', color: '#8A6B13' },
];

export function Community({ inviteId }: { inviteId?: string }) {
  const live = useKokoEvents(inviteId);
  const liveMap = useLiveMap(live.session?.user.id, true);
  const [tab, setTab] = useState<Tab>('discover');
  const [filter, setFilter] = useState('all');
  const [list, setList] = useState<Event[]>(events);
  const [people, setPeople] = useState(otsurunPeople);
  const [draft, setDraft] = useState(initialDraft);
  const [simulatedZone, setSimulatedZone] = useState(debugLocation && !supabase ? zones[0].id : 'gps');
  const [localPresence, setLocalPresence] = useState<{ zone: string; expires_at: string } | null>(null);
  const [expiredAt, setExpiredAt] = useState('');
  const [locating, setLocating] = useState(false);
  const [panel, setPanel] = useState<Panel | null>(null);
  const [toast, setToast] = useState('');
  const [theme, setTheme] = useState<Theme>('peach');
  const [writing, setWriting] = useState(false);
  const toastTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const content = useRef<HTMLElement>(null);

  useEffect(() => {
    if (process.env.NODE_ENV === 'production' && 'serviceWorker' in navigator) {
      void navigator.serviceWorker.register('/sw.js').catch(console.error);
    }
    return () => { if (toastTimer.current) clearTimeout(toastTimer.current); };
  }, []);

  const notify = useCallback((message: string) => {
    setToast(message);
    if (toastTimer.current) clearTimeout(toastTimer.current);
    toastTimer.current = setTimeout(() => setToast(''), 2200);
  }, []);

  useEffect(() => {
    if (liveMap.cheer) notify('近くの仲間から「ファイト！✨」が届いたよ');
  }, [liveMap.cheer, notify]);

  const presence = localPresence ?? liveMap.map?.self;
  const activeZone = presence && presence.expires_at !== expiredAt
    ? zones.find(({ id }) => id === presence.zone) : null;
  useEffect(() => {
    if (!presence) return;
    const timer = setTimeout(() => setExpiredAt(presence.expires_at), Math.max(0, Date.parse(presence.expires_at) - Date.now()));
    return () => clearTimeout(timer);
  }, [presence]);

  function requireProfile() {
    if (!supabase || live.hasProfile) return true;
    setPanel({ kind: 'account' });
    return false;
  }

  async function openTicket(event: Event) {
    if (writing) return;
    if (!event.joined) {
      if (!requireProfile()) return;
      if (supabase) {
        setWriting(true);
        try {
          const { error } = await supabase.rpc('request_koko_event', { target_event: event.id });
          if (error) { notify(writeError(error)); return; }
          await live.refresh();
        } finally { setWriting(false); }
      } else {
        const updated = { ...event, joined: true, spotsLeft: event.spotsLeft - 1 };
        setList((current) => current.map((item) => item.id === event.id ? updated : item));
      }
      notify('参加リクエストを送ったよ！');
    }
    setPanel({ kind: 'story', story: { kind: event.isHost ? 'invite' : 'ticket', event } });
  }

  async function createEvent() {
    if (!requireProfile() || writing) return;
    const event: Event = {
      id: crypto.randomUUID(), time: draft.time, zone: draft.zone, cafe: draft.cafe,
      vibe: draft.vibe, womenOnly: draft.womenOnly, maxMembers: draft.capacity,
      spotsLeft: draft.capacity - 1, joined: true, isHost: true,
      category: ['cafe', ...(draft.womenOnly ? ['women'] : []),
        ...(['初心者だけ', '歩き混じりOK'].includes(draft.vibe) ? ['beginner'] : [])],
      host: { name: 'わたし', emoji: '✨', ig: '', bio: '', tags: [draft.vibe] },
    };
    if (supabase) {
      const startsAt = toTokyoStart(draft.time);
      const zoneId = zones.find(({ name }) => name === draft.zone)?.id;
      if (!zoneId) return;
      setWriting(true);
      try {
        const { error } = await supabase.from('run_events').insert({
          id: event.id, starts_at: startsAt, meet_zone_id: zoneId, cafe_name: draft.cafe,
          vibe_tag: draft.vibe, women_only: draft.womenOnly, max_members: draft.capacity,
        });
        if (error) { notify(writeError(error)); return; }
        event.time = formatTokyoStart(startsAt);
        await live.refresh();
      } finally { setWriting(false); }
    } else {
      setList((current) => [event, ...current]);
    }
    setFilter('all');
    setPanel({ kind: 'story', story: { kind: 'invite', event } });
    notify('募集をたてたよ！ストーリーで仲間を呼ぼう');
  }

  async function toggleRunning() {
    if (locating) return;
    const simulate = debugLocation && simulatedZone !== 'gps';
    if (!simulate && !localPresence && !requireProfile()) return;
    setLocating(true);
    try {
      if (activeZone) {
        if (localPresence) setLocalPresence(null);
        else if (supabase) {
          const { error } = await supabase.rpc('set_koko_presence', { target_zone: null });
          if (error) { notify(writeError(error)); return; }
          await liveMap.refresh();
        }
        notify('ラン中表示をOFFにしたよ');
        return;
      }
      let zoneId: string | null;
      try {
        zoneId = simulate ? simulatedZone : await locateKokoZone();
      } catch {
        notify('位置情報を確認できなかったよ。ブラウザの設定を確認してね');
        return;
      }
      const zone = zones.find(({ id }) => id === zoneId);
      if (!zone) { notify('皇居エリアに着いたらONにできるよ'); return; }
      if (supabase && !simulate) {
        const { error } = await supabase.rpc('set_koko_presence', { target_zone: zone.id });
        if (error) { notify(writeError(error)); return; }
        await liveMap.refresh();
      } else {
        setLocalPresence({ zone: zone.id, expires_at: new Date(Date.now() + 90 * 60_000).toISOString() });
      }
      notify(`${zone.name}エリアに表示されたよ`);
    } finally { setLocating(false); }
  }

  const close = () => setPanel(null);
  const visibleEvents = (supabase ? live.events : inviteId ? [] : list)
    .filter((event) => filter === 'all' || event.category.includes(filter));
  const mapZones = supabase ? zones.map((zone) => {
    const liveZone = liveMap.map?.zones.find(({ zone: id }) => id === zone.id);
    return {
      ...zone, count: liveZone?.count ?? 0,
      runners: (liveZone?.runners ?? []).map(({ name, emoji }) => `${name} ${emoji}`),
    };
  }) : zones;
  const countInZone = (zone: Zone) => zone.count + Number(Boolean(localPresence && activeZone?.id === zone.id));

  async function sendCheer(zone: Zone) {
    if (writing) return;
    if (supabase && (!debugLocation || simulatedZone === 'gps')) {
      if (!requireProfile()) return;
      setWriting(true);
      try {
        const { data, error } = await supabase.rpc('send_koko_cheer', { target_zone: zone.id });
        if (error) { notify(writeError(error)); return; }
        if (data === 0) { close(); notify('今は新しく応援を送れる仲間がいないよ'); return; }
      } finally { setWriting(false); }
    }
    close();
    notify(`${zone.name}のみんなに「ファイト！✨」を送ったよ`);
  }

  return (
    <SheetFeedback.Provider value={toast}>
    <div className="app-shell">
      <div className={`toast ${toast && !panel ? 'show' : ''}`} role="status">{panel ? '' : toast}</div>
      <header className="header">
        <a href="/" className="logo" aria-label="koko.">koko<span className="logo-dot" /></a>
        {supabase && <button className="btn btn-soft" onClick={() => setPanel({ kind: 'account' })}>
          {live.session ? 'マイページ' : 'ログイン'}
        </button>}
        <button type="button" className={`run-toggle ${activeZone ? 'active' : ''}`}
          aria-pressed={Boolean(activeZone)} disabled={locating} onClick={() => void toggleRunning()}>
          <span className="pulse-dot" />{activeZone ? `${activeZone.name}をラン中 ✨` : 'いま走ってる OFF'}
        </button>
      </header>
      <main className="content" ref={content}>
        {tab === 'discover' && <section className="tab-panel active" aria-label="みつける">
          {!inviteId && <div className="chips" aria-label="募集フィルター">
            {filters.map(([id, label]) => <button key={id} className={`chip ${filter === id ? 'active' : ''}`}
              aria-pressed={filter === id} onClick={() => setFilter(id)}>{label}</button>)}
          </div>}
          {visibleEvents.map((event) => <article className="ticket-card" key={event.id}>
            <div className="ticket-top">
              <div className="badge-row">
                <span className={`pill ${event.womenOnly ? 'pill-peach' : 'pill-matcha'}`}>
                  {event.womenOnly ? '🎀 女性限定' : '🫧 だれでもOK'}
                </span>
                <span className="pill pill-butter">あと {event.spotsLeft}枠</span>
              </div>
              <h2 className="event-time">{event.time} ・ {event.zone}集合</h2>
              <div className="event-meta">☕ ご褒美：{event.cafe}</div>
              <div className="tags-inline"><span className="mini-tag">#{event.vibe}</span><span className="mini-tag">#タイム非表示</span></div>
            </div>
            <div className="ticket-bottom">
              <button className="host-info" onClick={() => setPanel({ kind: 'host', event })}>
                <span className="avatar">{event.host.emoji}</span>
                <span><span className="host-name block">{event.host.name}</span><span className="host-link block">雰囲気を見る</span></span>
              </button>
              <div className="grid gap-1 justify-items-end">
                {event.participation && <span className="crew-note">{participationLabel[event.participation]}</span>}
                <button className={`btn ${event.joined ? 'btn-soft' : 'btn-primary'}`}
                  disabled={writing || event.participation === 'declined' || (!event.joined && event.spotsLeft === 0)}
                  onClick={() => void openTicket(event)}>
                  {event.joined ? 'チケットを見る 🎟️' : event.spotsLeft === 0 ? '満席' : '参加リクエスト'}
                </button>
                {supabase && event.isHost && <button className="btn btn-primary" onClick={() => setPanel({ kind: 'requests', event })}>参加申請を確認</button>}
              </div>
            </div>
          </article>)}
          {visibleEvents.length === 0 && <p className="map-help" role="status">
            {live.loading ? '募集を読み込み中…' : live.error ? '募集を読み込めなかったよ。'
              : inviteId ? 'この募集の受付は終了したよ。' : 'この条件の募集はまだないよ。'}
          </p>}
          {inviteId && <a href="/" className="btn btn-soft">募集一覧に戻る</a>}
        </section>}
        {tab === 'map' && <section className="tab-panel active" aria-label="マップ">
          <div className="map-card">
            <div className="map-caption"><span>{supabase ? '皇居8区画ライブ' : '皇居8区画マップ（デモ）'}</span>
              <span>いま {mapZones.reduce((sum, zone) => sum + countInZone(zone), 0)}人</span>
            </div>
            <div className="map-stage">
              <svg viewBox="0 0 360 390" className="absolute inset-0 size-full" aria-hidden="true">
                <path d="M180 55 C255 55, 305 112, 298 195 C292 275, 250 332, 178 335 C106 338, 62 278, 62 195 C62 112, 112 55, 180 55 Z" fill="#CBE5C2" stroke="#8FBC85" strokeWidth="10" />
                <path d="M180 86 C234 86, 268 128, 264 195 C260 258, 228 298, 178 300 C128 302, 95 258, 95 195 C95 130, 130 86, 180 86 Z" fill="#B3D8A8" />
                <text x="180" y="192" textAnchor="middle" fill="#4B6E43" fontSize="14" fontWeight="800">皇居外周</text>
                <text x="180" y="212" textAnchor="middle" fill="#63875B" fontSize="11" fontWeight="700" fontFamily="Plus Jakarta Sans">KŌKYO LOOP</text>
              </svg>
              {mapZones.map((zone) => {
                const here = activeZone?.id === zone.id;
                return <button key={zone.id} className={`zone-pin ${here ? 'me' : ''}`} style={{ left: `${zone.x}%`, top: `${zone.y}%` }}
                  onClick={() => setPanel({ kind: 'zone', zone })}>
                  {here && '✨'}{zone.name}<span className="zone-count">{countInZone(zone)}</span>
                </button>;
              })}
            </div>
          </div>
          <p className="map-help">{liveMap.failed ? 'ライブ情報を更新できなかったよ。' : 'エリアをタップすると「ファイト！✨」を送れます。'}</p>
          {debugLocation && <label className="map-help block">
            開発用シミュレーション　
            <select value={simulatedZone} disabled={locating} onChange={(event) => { setSimulatedZone(event.target.value); setLocalPresence(null); }}>
              <option value="gps">端末の位置情報</option>
              <option value="">皇居エリア外</option>
              {zones.map((zone) => <option key={zone.id} value={zone.id}>{zone.name}</option>)}
            </select>
          </label>}
        </section>}
        {tab === 'otsurun' && (supabase ? <LiveOtsurun key={live.session?.user.id ?? 'guest'} userId={live.session?.user.id} notify={notify}
          onSignIn={() => setPanel({ kind: 'account' })} onStory={(story) => setPanel({ kind: 'story', story })} />
          : <section className="tab-panel active" aria-label="おつラン！">
          <button className="crew-banner w-full text-left" onClick={() => setPanel({ kind: 'story', story: { kind: 'crew' } })}>
            <span>
              <span className="crew-kicker block">TODAY'S CREW CARD</span>
              <span className="crew-title block">今日いっしょに走った証明を見る</span>
              <span className="crew-note block">入力ゼロ・9:16でそのままストーリー保存</span>
            </span><span className="text-[26px]">📸</span>
          </button>
          {people.map((person) => <article className="person-card" key={person.id}>
            <div className="person-head">
              <div className="flex items-center gap-2.5"><div className="avatar">{person.emoji}</div>
                <div><h2 className="text-sm font-black">{person.name}</h2><p className="crew-note">{person.context}</p></div>
              </div>
              <span className={`pill ${person.theySent ? 'pill-peach' : 'pill-matcha'}`}>{person.theySent ? '相手からも届いてる♡' : 'すれ違い'}</span>
            </div>
            <div className="stamp-grid">{stampTypes.map((stamp) => {
              const sent = person.sentStamps.includes(stamp.id);
              return <button key={stamp.id} className={`stamp-btn ${sent ? 'sent' : ''}`} aria-pressed={sent} onClick={() => {
                if (sent) return;
                setPeople((current) => current.map((item) => item.id === person.id ? {
                  ...item, sentStamps: [...item.sentStamps, stamp.id],
                } : item));
                notify(person.theySent && !person.sentStamps.length
                  ? `${person.name}さんと相互おつラン成立！IGが解放されたよ`
                  : `${person.name}さんにスタンプを送ったよ`);
              }}>{stamp.label}</button>;
            })}</div>
            {person.theySent && person.sentStamps.length > 0 && <div className="ig-unlocked">
              <span>相互おつラン成立！IG解放 ✨</span>
              <a className="btn btn-soft" href={`https://www.instagram.com/${person.ig.slice(1)}/`} target="_blank" rel="noreferrer">{person.ig}</a>
            </div>}
          </article>)}
        </section>)}
      </main>
      {tab === 'discover' && !inviteId && <button className="fab" onClick={() => {
        if (requireProfile()) setPanel({ kind: 'create' });
      }}>＋ たてる</button>}
      <nav className="bottom-nav" aria-label="メインメニュー">
        {tabs.map((item) => <button key={item.id} className={`nav-item ${tab === item.id ? 'active' : ''}`}
          aria-current={tab === item.id ? 'page' : undefined} onClick={() => { setTab(item.id); if (content.current) content.current.scrollTop = 0; }}>
          <span className="nav-pill"><span aria-hidden="true" className="icon">{item.emoji}</span></span><span>{item.label}</span>
        </button>)}
      </nav>
      {panel?.kind === 'create' && <Sheet title="10秒でゆるランをたてる" onClose={close}>
        <Options title="いつ走る？" values={presets.map(({ label }) => label)} value={draft.time} onChange={(time) => setDraft({ ...draft, time })} />
        <Options title="集合エリア（皇居8区画）" values={zones.map((zone) => zone.name)} value={draft.zone} onChange={(zone) => setDraft({ ...draft, zone })} />
        <Options title="アフターのご褒美カフェ" values={['丸の内ベーカリー', '日比谷スタンドコーヒー', '麹町ドーナツカフェ', '大手町抹茶スタンド']} value={draft.cafe} onChange={(cafe) => setDraft({ ...draft, cafe })} />
        <Options title="雰囲気タグ" values={['おしゃべりペース', '写真メイン', '初心者だけ', '歩き混じりOK']} value={draft.vibe} onChange={(vibe) => setDraft({ ...draft, vibe })} />
        <Options title="安心設定" values={[true, false]} value={draft.womenOnly} label={(value) => value ? '🎀 女性限定' : '🫧 だれでもOK'} onChange={(womenOnly) => setDraft({ ...draft, womenOnly })} />
        <Options title="定員（主催者を含む）" values={[2, 3, 4, 5, 6]} value={draft.capacity} label={(value) => `${value}名`} onChange={(capacity) => setDraft({ ...draft, capacity })} />
        <button className="btn btn-peach sheet-action" disabled={writing} onClick={() => void createEvent()}>募集をつくって招待チケットを出す ✨</button>
      </Sheet>}
      {panel?.kind === 'host' && <Sheet title="主催者の雰囲気" onClose={close}>
        <div className="mb-3 flex items-center gap-3">
          <span className="avatar host-avatar">{panel.event.host.emoji}</span>
          <div><p className="font-black">{panel.event.host.name}</p>
            <HostInstagram event={panel.event} />
          </div>
        </div>
        {panel.event.host.bio && <p className="mb-3 text-[13px] leading-relaxed">{panel.event.host.bio}</p>}
        <div className="tags-inline mb-3.5">{panel.event.host.tags.map((tag) => <span className="mini-tag" key={tag}>#{tag}</span>)}</div>
        <div className="host-preview mb-4" aria-label="投稿イメージ"><span>🥐</span><span>🌳</span><span>☕</span></div>
        <button className="btn btn-primary sheet-action" disabled={writing || panel.event.participation === 'declined' || (!panel.event.joined && panel.event.spotsLeft === 0)} onClick={() => void openTicket(panel.event)}>
          {panel.event.joined ? 'チケットを見る 🎟️' : panel.event.spotsLeft === 0 ? '満席' : 'このゆるランに参加リクエストする ✨'}
        </button>
      </Sheet>}
      {panel?.kind === 'account' && <Sheet title={live.session ? 'マイページ' : 'メールでログイン'} onClose={close}>
        {live.session ? <>
          {live.profileLoading ? <p role="status">プロフィールを読み込み中…</p> :
            <ProfileForm key={live.session.user.id} userId={live.session.user.id} profile={live.profile} onSaved={(profile) => {
            live.setProfile(profile);
            close();
            void live.refresh();
          }} />}
          <button className="btn btn-soft mt-3" onClick={() => void supabase?.auth.signOut().then(({ error }) => {
            if (error) notify('ログアウトできなかったよ。');
            else close();
          })}>ログアウト</button>
        </> : <EmailSignIn />}
      </Sheet>}
      {panel?.kind === 'requests' && <Sheet title="参加リクエスト" onClose={close}>
        <Requests eventId={panel.event.id} onDecision={() => void live.refresh()} />
      </Sheet>}
      {panel?.kind === 'zone' && <Sheet title={`${panel.zone.name}エリア（いま ${countInZone(mapZones.find(({ id }) => id === panel.zone.id) ?? panel.zone)}人）`} onClose={close}>
        <p className="crew-note mb-3">エリア単位でゆるく応援できます。</p>
        <div className="tags-inline mb-4">
          {activeZone?.id === panel.zone.id && <span className="mini-tag">わたし ✨（いまここ）</span>}
          {(mapZones.find(({ id }) => id === panel.zone.id)?.runners ?? []).map((runner, index) =>
            <span className="mini-tag px-3 py-[7px] text-xs" key={`${runner}-${index}`}>{runner}</span>)}
        </div>
        <button className="btn btn-peach sheet-action" disabled={writing} onClick={() => void sendCheer(panel.zone)}>
          {panel.zone.name}の仲間へ「ファイト！✨」を送る
        </button>
      </Sheet>}
      {panel?.kind === 'story' && <StorySheet story={panel.story} theme={theme} setTheme={setTheme} onClose={close} notify={notify} />}
    </div>
    </SheetFeedback.Provider>
  );
}

function Options<T extends string | number | boolean>({ title, values, value, label = String, onChange }: {
  title: string; values: T[]; value: T; label?: (value: T) => string; onChange: (value: T) => void;
}) {
  return <fieldset className="option-group">
    <legend className="option-label">{title}</legend>
    <div className="option-pills">{values.map((option) => <button key={String(option)}
      className={`opt-pill ${option === value ? 'selected' : ''}`} aria-pressed={option === value}
      onClick={() => onChange(option)}>{label(option)}</button>)}</div>
  </fieldset>;
}

function Sheet({ title, onClose, children }: { title: string; onClose: () => void; children: ReactNode }) {
  const ref = useRef<HTMLDialogElement>(null);
  const titleId = useId();
  const feedback = useContext(SheetFeedback);
  useEffect(() => {
    const dialog = ref.current;
    dialog?.showModal();
    return () => dialog?.close();
  }, []);
  return <dialog ref={ref} className="sheet-dialog" aria-labelledby={titleId} onCancel={(event) => {
    event.preventDefault();
    onClose();
  }} onClick={(event) => { if (event.target === event.currentTarget) onClose(); }}>
    <div className="sheet">
      <div className="sheet-handle" />
      <div className="sheet-title"><h2 id={titleId}>{title}</h2><button className="btn btn-soft" onClick={onClose}>閉じる</button></div>
      {feedback && <p role="status" className="sheet-feedback">{feedback}</p>}
      {children}
    </div>
  </dialog>;
}

function StorySheet({ story, theme, setTheme, onClose, notify }: {
  story: Story; theme: Theme; setTheme: (theme: Theme) => void; onClose: () => void; notify: (message: string) => void;
}) {
  const ref = useRef<HTMLCanvasElement>(null);
  const [prepared, setPrepared] = useState<{ story: Story; theme: Theme; file: File } | null>(null);
  const file = prepared?.story === story && prepared.theme === theme ? prepared.file : null;
  const inviteLink = () => story.kind === 'invite' && supabase
    ? new URL(`/invite/${story.event.id}`, window.location.origin).href : undefined;
  const title = story.kind === 'crew' ? "Today's Crew カード 📸"
    : story.kind === 'invite' ? '招待チケットができたよ 🎟️' : '参加チケットができたよ 🎟️';

  useEffect(() => {
    const canvas = ref.current;
    if (!canvas) return;
    let cancelled = false;
    drawStory(canvas, story, theme);
    void Promise.allSettled([
      document.fonts.load('900 64px "Zen Maru Gothic"', '皇居日曜竹橋ゆるラン'),
      document.fonts.load('800 54px "Plus Jakarta Sans"'),
    ]).then(async () => {
      await document.fonts.ready;
      if (!cancelled) {
        drawStory(canvas, story, theme);
        canvas.toBlob((blob) => {
          if (!cancelled && blob) {
            setPrepared({ story, theme, file: new File([blob], `koko-${story.kind}-${theme}.png`, { type: 'image/png' }) });
          }
        }, 'image/png');
      }
    });
    return () => { cancelled = true; };
  }, [story, theme]);

  function download() {
    if (!file) return;
    const url = URL.createObjectURL(file);
    const link = document.createElement('a');
    link.href = url;
    link.download = file.name;
    link.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
    notify('1080×1920 PNGを保存したよ！');
  }

  async function share() {
    if (!file) return;
    const payload = { title: 'koko.', files: [file], url: inviteLink() };
    if (!navigator.share || !navigator.canShare?.(payload)) {
      download();
      return;
    }
    try {
      await navigator.share(payload);
    } catch (error) {
      if (!(error instanceof DOMException && error.name === 'AbortError')) download();
    }
  }

  return <Sheet title={title} onClose={onClose}>
    <div className="theme-row" aria-label="カラーテーマ">{themes.map((item) =>
      <button key={item.id} className={`theme-btn ${theme === item.id ? 'active' : ''}`}
        aria-pressed={theme === item.id} style={{ background: item.background, color: item.color }}
        onClick={() => setTheme(item.id)}>{item.label}</button>)}</div>
    <div className="canvas-wrap"><canvas ref={ref} id="storyCanvas" width={1080} height={1920} aria-label={title} /></div>
    <button className="btn btn-primary sheet-action" disabled={!file} onClick={download}>1080×1920 PNGを保存してストーリーへ 📲</button>
    <button className="btn btn-soft sheet-action mt-2" disabled={!file} onClick={() => void share()}>カードを共有</button>
    {supabase && story.kind === 'invite' && <button className="btn btn-soft sheet-action mt-2" onClick={() => {
      const url = inviteLink();
      if (!url || !navigator.clipboard) { notify('招待リンクをコピーできなかったよ。'); return; }
      void navigator.clipboard.writeText(url).then(
        () => notify('招待リンクをコピーしたよ！'),
        () => notify('招待リンクをコピーできなかったよ。'),
      );
    }}>招待リンクをコピー</button>}
  </Sheet>;
}

const participationLabel = { pending: '承認待ち', approved: '参加決定', declined: '招待見送り' };

function HostInstagram({ event }: { event: Event }) {
  const [ig, setIg] = useState(supabase ? '' : event.host.ig);
  useEffect(() => {
    if (!supabase) return;
    let active = true;
    void supabase.rpc('koko_host_instagram', { target_event: event.id }).then(({ data }) => {
      if (active) setIg(typeof data === 'string' ? `@${data}` : '');
    });
    return () => { active = false; };
  }, [event.id]);
  return ig ? <p className="host-link no-underline">Instagram {ig}</p> : null;
}

function Requests({ eventId, onDecision }: { eventId: string; onDecision: () => void }) {
  const [items, setItems] = useState<Applicant[] | null>(null);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState('');
  useEffect(() => {
    if (!supabase) return;
    let active = true;
    void supabase.rpc('koko_event_requests', { target_event: eventId }).returns<Applicant[]>().then(({ data, error }) => {
      if (!active) return;
      setItems(Array.isArray(data) ? data : []);
      if (error) setMessage('参加リクエストを読み込めなかったよ。');
    });
    return () => { active = false; };
  }, [eventId]);

  async function decide(applicant: string, approve: boolean) {
    if (!supabase || busy) return;
    setBusy(true);
    try {
      const { data, error } = await supabase.rpc('decide_koko_request', { target_event: eventId, applicant, approve });
      if (error) { setMessage(writeError(error)); return; }
      if (data === 'pending' || data === 'approved' || data === 'declined') {
        setItems((previous) => previous?.map((item) => item.user_id === applicant ? { ...item, status: data } : item) ?? []);
      }
      setMessage('');
      onDecision();
    } finally { setBusy(false); }
  }

  return <div className="grid gap-2">
    {message && <p role="status">{message}</p>}
    {items === null && <p>読み込み中…</p>}
    {items?.length === 0 && !message && <p>参加リクエストはまだありません。</p>}
    {items?.map((item) => <article key={item.user_id} className="person-card">
      <div className="person-head"><span>{item.avatar_emoji} {item.display_name}</span><span className="pill pill-butter">{participationLabel[item.status]}</span></div>
      {item.status === 'pending' && <div className="flex gap-2">
        <button className="btn btn-primary" disabled={busy} onClick={() => void decide(item.user_id, true)}>承認する</button>
        <button className="btn btn-soft" disabled={busy} onClick={() => void decide(item.user_id, false)}>見送る</button>
      </div>}
    </article>)}
  </div>;
}
