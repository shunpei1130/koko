-- koko. (皇居ラン特化・Z世代向けコミュニティWebアプリ)
-- Supabase PostgreSQL 初期スキーマ案

-- 1. ユーザープロフィール（最小構成）
create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  avatar_emoji text default '🎀',
  avatar_url text,
  instagram_handle text,
  allow_ig_preview boolean default true,
  vibe_tag text default 'おしゃべりペース',
  created_at timestamptz default now()
);

-- 2. ゆるラン募集
create table if not exists run_events (
  id uuid primary key default gen_random_uuid(),
  host_id uuid not null references profiles(id) on delete cascade,
  date_label text not null,          -- 例: '日曜 9:00'
  meet_zone_id text not null,        -- 8区画IDのいずれか
  cafe_name text not null,           -- 例: '丸の内ベーカリー'
  vibe_tag text not null,            -- 例: 'おしゃべりペース'
  women_only boolean default true,
  max_members int not null check (max_members between 2 and 8),
  status text default 'open',        -- 'open' | 'closed' | 'finished'
  created_at timestamptz default now()
);

-- 3. 募集参加リクエスト
create table if not exists event_participants (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references run_events(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  status text not null default 'pending', -- 'pending' | 'approved' | 'declined'
  created_at timestamptz default now(),
  unique (event_id, user_id)
);

-- 4. 皇居8区画プレゼンス（※プライバシー保護のため緯度経度カラムは作らない）
create table if not exists zone_presence (
  user_id uuid primary key references profiles(id) on delete cascade,
  zone_id text not null,
  is_active boolean default true,
  started_at timestamptz default now(),
  expires_at timestamptz not null
);

-- 5. すれ違い・おつラン履歴（同一時間帯の皇居滞在ログ）
create table if not exists run_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  started_at timestamptz default now(),
  ended_at timestamptz
);

-- 6. 定型スタンプ送信（DMなし）
create table if not exists otsurun_stamps (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references profiles(id) on delete cascade,
  receiver_id uuid not null references profiles(id) on delete cascade,
  stamp_type text not null,          -- 'otsurun' | 'asakatsu' | 'wear' | 'again'
  run_date date not null default current_date,
  created_at timestamptz default now(),
  unique (sender_id, receiver_id, run_date, stamp_type)
);
