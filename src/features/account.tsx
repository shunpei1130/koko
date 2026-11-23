'use client';

import { useState, type FormEvent } from 'react';
import { avatars, supabase, type Profile } from './live-events';

export function EmailSignIn() {
  const [email, setEmail] = useState('');
  const [token, setToken] = useState('');
  const [sent, setSent] = useState(false);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState('');

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (busy || !supabase) return;
    setBusy(true);
    try {
      if (sent) {
        const { error } = await supabase.auth.verifyOtp({ email, token, type: 'email' });
        if (error) {
          setMessage('コードを確認できなかったよ。メールに届いた最新のコードを入力してね。');
          return;
        }
      } else {
        const { error } = await supabase.auth.signInWithOtp({ email });
        if (error) {
          setMessage('コードを送れなかったよ。少し待ってからもう一度試してね。');
          return;
        }
        setSent(true);
        setMessage('メールに届いたコードを入力してね。');
      }
    } finally {
      setBusy(false);
    }
  }

  return <form className="account-form" onSubmit={submit}>
    {sent ? <label>確認コード
      <input required value={token} onChange={(event) => setToken(event.target.value)} autoComplete="one-time-code"
        inputMode="numeric" pattern="[0-9]{6,10}" maxLength={10} />
    </label> : <label>メールアドレス
      <input type="email" required value={email} onChange={(event) => setEmail(event.target.value)}
        maxLength={254} autoComplete="email" />
    </label>}
    {message && <p role="status">{message}</p>}
    <button className="btn btn-primary sheet-action" disabled={busy}>{sent ? 'ログインする' : 'コードを送る'}</button>
    {sent && <button type="button" className="btn btn-soft" disabled={busy} onClick={() => {
      setSent(false); setMessage(''); setToken('');
    }}>メールアドレスを変更</button>}
  </form>;
}

export function ProfileForm({ userId, profile, onSaved }: { userId: string; profile: Profile | null; onSaved: (profile: Profile) => void }) {
  const [name, setName] = useState(profile?.display_name ?? '');
  const [emoji, setEmoji] = useState(profile?.avatar_emoji ?? avatars[0]);
  const [instagram, setInstagram] = useState(profile?.instagram_handle ?? '');
  const [preview, setPreview] = useState(profile?.allow_ig_preview ?? false);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState('');

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (busy || !name.trim() || !supabase) return;
    setBusy(true);
    try {
      const profile = {
        id: userId, display_name: name.trim(), avatar_emoji: emoji,
        instagram_handle: instagram.trim().replace(/^@/, '') || null,
        allow_ig_preview: preview,
      };
      const { error } = await supabase.from('profiles').upsert(profile);
      if (error) {
        setMessage('プロフィールを保存できなかったよ。入力内容を確かめてもう一度試してね。');
        return;
      }
      onSaved(profile);
    } finally {
      setBusy(false);
    }
  }

  return <form className="account-form" onSubmit={submit}>
    <label>名前<input required maxLength={20} value={name} autoComplete="nickname" onChange={(event) => setName(event.target.value)} /></label>
    <fieldset className="option-pills"><legend className="option-label">アイコン</legend>
      {avatars.map((avatar) => <button type="button" key={avatar} aria-pressed={avatar === emoji}
        className={`opt-pill ${avatar === emoji ? 'selected' : ''}`} onClick={() => setEmoji(avatar)}>{avatar}</button>)}
    </fieldset>
    <label>Instagram（任意）
      <input maxLength={31} pattern="@?[A-Za-z0-9._]{1,30}" value={instagram}
        autoCapitalize="none" onChange={(event) => setInstagram(event.target.value)} />
    </label>
    <label className="account-checkbox"><input type="checkbox" checked={preview} onChange={(event) => setPreview(event.target.checked)} />
      募集の「雰囲気を見る」でInstagramを公開する
    </label>
    {message && <p role="status">{message}</p>}
    <button className="btn btn-primary sheet-action" disabled={busy || !name.trim()}>保存する</button>
  </form>;
}
