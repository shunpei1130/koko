create type public.koko_zone as enum (
  'takebashi', 'hirakawamon', 'otemachi', 'nijubashi',
  'sakuradamon', 'iwatabashi', 'hanzomon', 'chidorigafuchi'
);
create type public.koko_participation as enum ('pending', 'approved', 'declined');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade default auth.uid(),
  display_name text not null check (char_length(btrim(display_name)) between 1 and 20),
  avatar_emoji text not null check (avatar_emoji in ('🎀', '🌷', '🍑', '🥐', '☕', '✨', '🌿', '🫧')),
  instagram_handle text check (instagram_handle ~ '^[A-Za-z0-9._]{1,30}$'),
  allow_ig_preview boolean not null default false
);

create table public.run_events (
  id uuid primary key default gen_random_uuid(),
  host_id uuid not null references public.profiles(id) on delete cascade default auth.uid(),
  starts_at timestamptz not null check (isfinite(starts_at)),
  meet_zone_id public.koko_zone not null,
  cafe_name text not null check (cafe_name in
    ('丸の内ベーカリー', '日比谷スタンドコーヒー', '麹町ドーナツカフェ', '大手町抹茶スタンド')),
  vibe_tag text not null check (vibe_tag in
    ('おしゃべりペース', '写真メイン', '初心者だけ', '歩き混じりOK')),
  women_only boolean not null,
  max_members integer not null check (max_members between 2 and 6),
  created_at timestamptz not null default now()
);

create table public.event_participants (
  event_id uuid not null references public.run_events(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  status public.koko_participation not null default 'pending',
  created_at timestamptz not null default now(),
  primary key (event_id, user_id)
);
create index run_events_starts_at on public.run_events(starts_at);
create index event_participants_user_id on public.event_participants(user_id);

alter table public.profiles enable row level security;
alter table public.run_events enable row level security;
alter table public.event_participants enable row level security;

revoke all on public.profiles, public.run_events, public.event_participants from anon, authenticated;
grant select, insert, update on public.profiles to authenticated;
grant insert on public.run_events to authenticated;

create policy profile_read_self on public.profiles for select to authenticated
  using (id = (select auth.uid()));
create policy profile_insert_self on public.profiles for insert to authenticated
  with check (id = (select auth.uid()));
create policy profile_update_self on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));
create policy event_insert_self on public.run_events for insert to authenticated
  with check (
    host_id = (select auth.uid())
    and starts_at > now()
    and starts_at <= now() + interval '8 days'
    and (starts_at at time zone 'Asia/Tokyo')::time in ('07:30', '19:30', '08:30', '09:00')
  );

create function public.list_koko_events(target_event uuid default null)
returns table (
  id uuid, starts_at timestamptz, meet_zone_id public.koko_zone, cafe_name text,
  vibe_tag text, women_only boolean, max_members integer, spots_left integer,
  host_name text, host_emoji text, is_host boolean, participation public.koko_participation
)
language sql stable security definer set search_path = '' as $$
  select e.id, e.starts_at, e.meet_zone_id, e.cafe_name, e.vibe_tag, e.women_only, e.max_members,
    (e.max_members - 1 - (
      select count(*) from public.event_participants p where p.event_id = e.id and p.status = 'approved'
    ))::integer,
    host.display_name, host.avatar_emoji, coalesce(e.host_id = auth.uid(), false), own.status
  from public.run_events e
  join public.profiles host on host.id = e.host_id
  left join public.event_participants own on own.event_id = e.id and own.user_id = auth.uid()
  where (target_event is null or e.id = target_event) and e.starts_at > now()
  order by e.starts_at, e.id
  limit 100;
$$;

create function public.koko_host_instagram(target_event uuid)
returns text language sql stable security definer set search_path = '' as $$
  select host.instagram_handle
  from public.run_events e join public.profiles host on host.id = e.host_id
  where e.id = target_event and e.starts_at > now()
    and (host.allow_ig_preview or host.id = auth.uid());
$$;

create function public.request_koko_event(target_event uuid)
returns public.koko_participation language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
  event public.run_events;
  current_status public.koko_participation;
begin
  if actor is null then raise exception 'sign_in_required'; end if;
  select * into event from public.run_events where id = target_event for update;
  if not found or event.starts_at <= now() or event.host_id = actor then
    raise exception 'event_unavailable';
  end if;

  select status into current_status from public.event_participants
    where event_id = target_event and user_id = actor;
  if found then return current_status; end if;

  if (select count(*) from public.event_participants p where p.event_id = target_event and p.status = 'approved')
      >= event.max_members - 1 then
    raise exception 'event_full';
  end if;

  insert into public.event_participants (event_id, user_id) values (target_event, actor);
  return 'pending';
end;
$$;

create function public.koko_event_requests(target_event uuid)
returns table (user_id uuid, display_name text, avatar_emoji text, status public.koko_participation)
language sql stable security definer set search_path = '' as $$
  select p.user_id, member.display_name, member.avatar_emoji, p.status
  from public.run_events e
  join public.event_participants p on p.event_id = e.id
  join public.profiles member on member.id = p.user_id
  where e.id = target_event and e.host_id = auth.uid() and e.starts_at > now()
  order by p.created_at, p.user_id;
$$;

create function public.decide_koko_request(target_event uuid, applicant uuid, approve boolean)
returns public.koko_participation language plpgsql security definer set search_path = '' as $$
declare
  event public.run_events;
  current_status public.koko_participation;
  decision public.koko_participation;
begin
  select * into event from public.run_events
    where id = target_event and host_id = auth.uid() for update;
  if not found or event.starts_at <= now() then raise exception 'event_unavailable'; end if;

  select status into current_status from public.event_participants
    where event_id = target_event and user_id = applicant;
  if not found then raise exception 'request_unavailable'; end if;
  if current_status <> 'pending' then return current_status; end if;

  if approve and (
    select count(*) from public.event_participants p where p.event_id = target_event and p.status = 'approved'
  ) >= event.max_members - 1 then
    raise exception 'event_full';
  end if;

  decision := case when approve then 'approved' else 'declined' end;
  update public.event_participants set status = decision
    where event_id = target_event and user_id = applicant;
  return decision;
end;
$$;

revoke execute on function public.list_koko_events(uuid), public.koko_host_instagram(uuid),
  public.request_koko_event(uuid), public.koko_event_requests(uuid),
  public.decide_koko_request(uuid, uuid, boolean) from public, anon, authenticated;
grant execute on function public.list_koko_events(uuid), public.koko_host_instagram(uuid)
  to anon, authenticated;
grant execute on function public.request_koko_event(uuid), public.koko_event_requests(uuid),
  public.decide_koko_request(uuid, uuid, boolean) to authenticated;
