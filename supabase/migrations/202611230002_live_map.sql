create type public.koko_stamp as enum ('otsurun', 'asakatsu', 'wear', 'again');
create schema if not exists koko_private;
revoke all on schema koko_private from public, anon, authenticated;

create table public.zone_presence (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  zone_id public.koko_zone not null,
  expires_at timestamptz not null
);
create index zone_presence_live on public.zone_presence(zone_id, expires_at);

create table public.run_sessions (
  user_id uuid not null references public.profiles(id) on delete cascade,
  started_at timestamptz not null,
  ended_at timestamptz not null,
  primary key (user_id, started_at),
  check (started_at <= ended_at)
);
create index run_sessions_ended_at on public.run_sessions(ended_at);

create table public.koko_map_signal (
  id boolean primary key default true check (id),
  updated_at timestamptz not null default now()
);
insert into public.koko_map_signal default values;

create table public.koko_cheers (
  receiver_id uuid not null references public.profiles(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  zone_id public.koko_zone not null,
  sent_minute timestamptz not null,
  primary key (receiver_id, sender_id, sent_minute)
);

create table public.otsurun_stamps (
  sender_id uuid not null references public.profiles(id) on delete cascade,
  receiver_id uuid not null references public.profiles(id) on delete cascade,
  run_date date not null,
  stamp_type public.koko_stamp not null,
  primary key (sender_id, receiver_id, run_date, stamp_type),
  check (sender_id <> receiver_id)
);
create index otsurun_stamps_inbound on public.otsurun_stamps(receiver_id, sender_id, run_date);

alter table public.zone_presence enable row level security;
alter table public.run_sessions enable row level security;
alter table public.koko_map_signal enable row level security;
alter table public.koko_cheers enable row level security;
alter table public.otsurun_stamps enable row level security;
revoke all on public.zone_presence, public.run_sessions, public.koko_map_signal,
  public.koko_cheers, public.otsurun_stamps from anon, authenticated;
grant select on public.koko_map_signal to anon, authenticated;
grant select on public.koko_cheers to authenticated;
create policy map_signal_read on public.koko_map_signal for select to anon, authenticated using (true);
create policy cheers_read_self on public.koko_cheers for select to authenticated
  using (receiver_id = (select auth.uid()));

alter publication supabase_realtime add table public.koko_map_signal, public.koko_cheers;

create function public.set_koko_presence(target_zone public.koko_zone)
returns timestamptz language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
  instant timestamptz := clock_timestamp();
  expiry timestamptz;
begin
  -- Lock the profile so concurrent requests from two tabs update the same session.
  perform id from public.profiles where id = actor for update;
  if not found then raise exception 'profile_required'; end if;
  instant := clock_timestamp();

  update public.run_sessions set ended_at = instant
    where user_id = actor and ended_at > instant;

  if target_zone is null then
    delete from public.zone_presence where user_id = actor;
  else
    expiry := instant + interval '90 minutes';
    insert into public.zone_presence(user_id, zone_id, expires_at) values (actor, target_zone, expiry)
      on conflict (user_id) do update set zone_id = excluded.zone_id, expires_at = excluded.expires_at;
    insert into public.run_sessions(user_id, started_at, ended_at) values (actor, instant, expiry);
  end if;

  update public.koko_map_signal set updated_at = instant;
  return expiry;
end;
$$;

create function public.koko_live_map()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'zones', coalesce((
      select jsonb_agg(jsonb_build_object('zone', s.zone_id, 'count', s.total, 'runners', s.runners))
      from (
        select p.zone_id, count(*) as total, case when auth.uid() is null then '[]'::jsonb
          else jsonb_agg(jsonb_build_object('name', u.display_name, 'emoji', u.avatar_emoji)
            order by u.display_name, u.id) filter (where p.user_id is distinct from auth.uid())
        end as runners
        from public.zone_presence p join public.profiles u on u.id = p.user_id
        where p.expires_at > now()
        group by p.zone_id
      ) s
    ), '[]'::jsonb),
    'self', (
      select jsonb_build_object('zone', p.zone_id, 'expires_at', p.expires_at)
      from public.zone_presence p where p.user_id = auth.uid() and p.expires_at > now()
    )
  );
$$;

create function public.send_koko_cheer(target_zone public.koko_zone)
returns integer language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
  sent integer;
begin
  if not exists (select 1 from public.profiles where id = actor) then
    raise exception 'profile_required';
  end if;
  insert into public.koko_cheers(receiver_id, sender_id, zone_id, sent_minute)
    select user_id, actor, target_zone, date_trunc('minute', now())
    from public.zone_presence
    where zone_id = target_zone and user_id <> actor and expires_at > now()
    on conflict do nothing;
  get diagnostics sent = row_count;
  return sent;
end;
$$;

create function koko_private.encounters(actor uuid)
returns table (person uuid, run_date date, event_match boolean)
language sql stable security definer set search_path = '' as $$
  with recent as (
    select e.id, e.host_id, (e.starts_at at time zone 'Asia/Tokyo')::date as day
    from public.run_events e
    where e.starts_at <= now() and e.starts_at > now() - interval '7 days'
  ), members as (
    select r.id, r.host_id as member, r.day from recent r
    union all
    select r.id, p.user_id, r.day from recent r
    join public.event_participants p on p.event_id = r.id and p.status = 'approved'
  ), encounters as (
    select b.member as person, a.day, true as event_match
    from members a join members b on b.id = a.id and b.member <> actor
    where a.member = actor
    union all
    select b.user_id,
      (greatest(a.started_at, b.started_at) at time zone 'Asia/Tokyo')::date,
      false
    from public.run_sessions a
    join public.run_sessions b on b.user_id <> actor
      and a.started_at < least(b.ended_at, now()) and b.started_at < least(a.ended_at, now())
    where a.user_id = actor and a.ended_at > now() - interval '7 days'
      and b.ended_at > now() - interval '7 days'
  )
  select e.person, e.day, bool_or(e.event_match) from encounters e group by e.person, e.day;
$$;

create function public.koko_otsurun()
returns table (id uuid, name text, emoji text, context text, run_date date,
  sent_stamps public.koko_stamp[], they_sent boolean, ig text)
language sql stable security definer set search_path = '' as $$
  with pairs as (
    select e.person, e.run_date, e.event_match from koko_private.encounters(auth.uid()) e
    union
    select outgoing.receiver_id, outgoing.run_date, false
    from public.otsurun_stamps outgoing
    where outgoing.sender_id = auth.uid() and exists (
      select 1 from public.otsurun_stamps incoming
      where incoming.sender_id = outgoing.receiver_id
        and incoming.receiver_id = auth.uid() and incoming.run_date = outgoing.run_date
    )
  ), latest as (
    select distinct on (p.person) p.* from pairs p order by p.person, p.run_date desc, p.event_match desc
  )
  select u.id, u.display_name, u.avatar_emoji,
    case when e.event_match then '同じゆるランに参加' else 'おつラン仲間' end,
    e.run_date, sent.stamps, received.sent,
    case when cardinality(sent.stamps) > 0 and received.sent then u.instagram_handle end
  from latest e join public.profiles u on u.id = e.person
  cross join lateral (
    select array(select s.stamp_type from public.otsurun_stamps s
      where s.sender_id = auth.uid() and s.receiver_id = e.person and s.run_date = e.run_date) as stamps
  ) sent
  cross join lateral (
    select exists(select 1 from public.otsurun_stamps s where
      s.sender_id = e.person and s.receiver_id = auth.uid() and s.run_date = e.run_date) as sent
  ) received
  order by e.run_date desc, u.id
  limit 100;
$$;

create function public.send_koko_stamp(recipient uuid, encounter_day date, stamp public.koko_stamp)
returns void language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
begin
  if actor is null or not exists (
    select 1 from koko_private.encounters(actor) e where e.person = recipient and e.run_date = encounter_day
  ) then raise exception 'encounter_unavailable'; end if;
  insert into public.otsurun_stamps(sender_id, receiver_id, run_date, stamp_type)
    values (actor, recipient, encounter_day, stamp) on conflict do nothing;
end;
$$;

create function public.koko_today_crew()
returns jsonb language sql stable security definer set search_path = '' as $$
  with chosen as (
    select e.* from public.run_events e
    where e.starts_at <= now()
      and (e.starts_at at time zone 'Asia/Tokyo')::date = (now() at time zone 'Asia/Tokyo')::date
      and (e.host_id = auth.uid() or exists (
        select 1 from public.event_participants p
        where p.event_id = e.id and p.user_id = auth.uid() and p.status = 'approved'
      ))
    order by starts_at desc, id limit 1
  ), members as (
    select host_id as user_id from chosen
    union all
    select p.user_id from chosen e join public.event_participants p on p.event_id = e.id and p.status = 'approved'
  )
  select jsonb_build_object('starts_at', e.starts_at, 'cafe', e.cafe_name, 'members', (
    select jsonb_agg(jsonb_build_object('name', u.display_name, 'emoji', u.avatar_emoji) order by u.id)
    from members m join public.profiles u on u.id = m.user_id
  )) from chosen e;
$$;

revoke execute on function koko_private.encounters(uuid) from public, anon, authenticated;
revoke execute on function public.set_koko_presence(public.koko_zone), public.koko_live_map(),
  public.send_koko_cheer(public.koko_zone), public.koko_otsurun(),
  public.send_koko_stamp(uuid, date, public.koko_stamp), public.koko_today_crew()
  from public, anon, authenticated;
grant execute on function public.koko_live_map() to anon, authenticated;
grant execute on function public.set_koko_presence(public.koko_zone),
  public.send_koko_cheer(public.koko_zone), public.koko_otsurun(),
  public.send_koko_stamp(uuid, date, public.koko_stamp), public.koko_today_crew() to authenticated;
