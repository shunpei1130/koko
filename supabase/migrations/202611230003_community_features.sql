alter table public.run_events
  add column solo_welcome boolean not null default false,
  add column first_time_welcome boolean not null default false,
  add column series_id uuid references public.run_events(id) on delete cascade,
  add column weekly_active boolean not null default false;

create unique index koko_series_occurrence on public.run_events(series_id, starts_at);
create index koko_weekly_anchors on public.run_events(id) where weekly_active;

alter policy event_insert_self on public.run_events with check (
  host_id = (select auth.uid())
  and starts_at > now() and starts_at <= now() + interval '8 days'
  and (starts_at at time zone 'Asia/Tokyo')::time in ('07:30', '19:30', '08:30', '09:00')
  and ((weekly_active and series_id = id) or (not weekly_active and series_id is null))
);

create table koko_private.followed_series (
  user_id uuid references public.profiles(id) on delete cascade,
  series_id uuid references public.run_events(id) on delete cascade,
  primary key (user_id, series_id)
);
create table koko_private.again_preferences (
  user_id uuid references public.profiles(id) on delete cascade,
  partner_id uuid references public.profiles(id) on delete cascade,
  enabled_at timestamptz not null default clock_timestamp(),
  primary key (user_id, partner_id)
);
create table koko_private.arrivals (
  event_id uuid references public.run_events(id) on delete cascade,
  user_id uuid references public.profiles(id) on delete cascade,
  primary key (event_id, user_id)
);
alter table koko_private.followed_series enable row level security;
alter table koko_private.again_preferences enable row level security;
alter table koko_private.arrivals enable row level security;

create function koko_private.publish_weekly_runs()
returns void language sql security definer set search_path = '' as $$
  with anchors as (
    select * from public.run_events e
    where e.weekly_active and e.series_id = e.id and e.starts_at <= now()
    for update
  )
  insert into public.run_events (
    host_id, starts_at, meet_zone_id, cafe_name, vibe_tag, women_only, max_members,
    solo_welcome, first_time_welcome, series_id
  )
  select e.host_id, next.starts_at, e.meet_zone_id, e.cafe_name, e.vibe_tag, e.women_only,
    e.max_members, e.solo_welcome, e.first_time_welcome, e.id
  from anchors e
  cross join lateral (
    select e.starts_at + interval '168 hours' * (
      floor(extract(epoch from (now() - e.starts_at)) / 604800) + 1
    ) as starts_at
  ) next
  on conflict (series_id, starts_at) do nothing;

  delete from koko_private.arrivals a using public.run_events e
  where e.id = a.event_id
    and (e.starts_at at time zone 'Asia/Tokyo')::date < (now() at time zone 'Asia/Tokyo')::date;
$$;

create function public.koko_stop_weekly(series uuid)
returns boolean language sql security definer set search_path = '' as $$
  with stopped as (
    update public.run_events set weekly_active = false
    where id = series and series_id = id and host_id = auth.uid() and weekly_active
    returning id
  )
  select exists(select 1 from stopped);
$$;

create function public.koko_follow_weekly(series uuid, enabled boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare actor uuid := auth.uid();
begin
  if not exists (select 1 from public.profiles where id = actor) then raise exception 'profile_required'; end if;
  if enabled then
    if not exists (select 1 from public.run_events where id = series and series_id = id and weekly_active) then
      raise exception 'event_unavailable';
    end if;
    insert into koko_private.followed_series(user_id, series_id) values (actor, series) on conflict do nothing;
  else
    delete from koko_private.followed_series where user_id = actor and series_id = series;
  end if;
end;
$$;

create function koko_private.mutual_again(actor uuid)
returns table (partner uuid)
language sql stable security definer set search_path = '' as $$
  select distinct sent.receiver_id
  from public.otsurun_stamps sent
  join public.otsurun_stamps received on received.sender_id = sent.receiver_id
    and received.receiver_id = sent.sender_id and received.run_date = sent.run_date
    and received.stamp_type = 'again'
  where sent.sender_id = actor and sent.stamp_type = 'again';
$$;

create function public.koko_again_connections()
returns table (partner uuid, name text, emoji text, enabled boolean)
language sql stable security definer set search_path = '' as $$
  select m.partner, p.display_name, p.avatar_emoji, pref.user_id is not null
  from koko_private.mutual_again(auth.uid()) m
  join public.profiles p on p.id = m.partner
  left join koko_private.again_preferences pref on pref.user_id = auth.uid() and pref.partner_id = m.partner
  order by p.display_name, m.partner;
$$;

create function public.koko_set_again(partner uuid, enabled boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare actor uuid := auth.uid();
begin
  if enabled then
    if not exists (select 1 from koko_private.mutual_again(actor) m where m.partner = $1) then
      raise exception 'encounter_unavailable';
    end if;
    insert into koko_private.again_preferences(user_id, partner_id) values (actor, $1) on conflict do nothing;
  else
    delete from koko_private.again_preferences where user_id = actor and partner_id = $1;
  end if;
end;
$$;

create function public.koko_again_events()
returns table (event_id uuid, name text, starts_at timestamptz, zone_id public.koko_zone)
language sql stable security definer set search_path = '' as $$
  select e.id, p.display_name, e.starts_at, e.meet_zone_id
  from koko_private.again_preferences pref
  join public.run_events e on e.host_id = pref.partner_id and e.created_at >= pref.enabled_at
  join public.profiles p on p.id = pref.partner_id
  where pref.user_id = auth.uid() and e.starts_at > now()
  order by e.starts_at, e.id limit 25;
$$;

create function koko_private.can_check_in(target uuid, actor uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.run_events e where e.id = target
      and (e.starts_at at time zone 'Asia/Tokyo')::date = (now() at time zone 'Asia/Tokyo')::date
      and (e.host_id = actor or exists (
        select 1 from public.event_participants p where p.event_id = e.id
          and p.user_id = actor and p.status = 'approved'
      ))
  );
$$;

create function public.koko_set_arrived(target_event uuid, arrived boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare actor uuid := auth.uid();
begin
  if not koko_private.can_check_in(target_event, actor) then raise exception 'event_unavailable'; end if;
  if arrived then
    insert into koko_private.arrivals(event_id, user_id) values (target_event, actor) on conflict do nothing;
  else
    delete from koko_private.arrivals where event_id = target_event and user_id = actor;
  end if;
end;
$$;

create function public.koko_arrivals(target_event uuid)
returns table (name text, emoji text, is_self boolean)
language sql stable security definer set search_path = '' as $$
  select p.display_name, p.avatar_emoji, a.user_id = auth.uid()
  from koko_private.arrivals a
  join public.profiles p on p.id = a.user_id
  where a.event_id = target_event and koko_private.can_check_in(target_event, auth.uid())
  order by p.display_name, p.id;
$$;

create function public.koko_community_events(target_event uuid default null)
returns table (
  id uuid, starts_at timestamptz, meet_zone_id public.koko_zone, cafe_name text,
  vibe_tag text, women_only boolean, max_members integer, spots_left integer,
  host_name text, host_emoji text, is_host boolean, participation public.koko_participation,
  solo_welcome boolean, first_time_welcome boolean, series_id uuid,
  weekly_active boolean, followed boolean, can_check_in boolean
)
language sql stable security definer set search_path = '' as $$
  select e.id, e.starts_at, e.meet_zone_id, e.cafe_name, e.vibe_tag, e.women_only, e.max_members,
    (e.max_members - 1 - (
      select count(*) from public.event_participants p where p.event_id = e.id and p.status = 'approved'
    ))::integer,
    host.display_name, host.avatar_emoji, coalesce(e.host_id = auth.uid(), false), own.status,
    e.solo_welcome, e.first_time_welcome, e.series_id,
    coalesce(anchor.weekly_active, false), follow.series_id is not null,
    koko_private.can_check_in(e.id, auth.uid())
  from public.run_events e
  join public.profiles host on host.id = e.host_id
  left join public.event_participants own on own.event_id = e.id and own.user_id = auth.uid()
  left join public.run_events anchor on anchor.id = e.series_id
  left join koko_private.followed_series follow on follow.series_id = e.series_id and follow.user_id = auth.uid()
  where (target_event is null or e.id = target_event)
    and (e.starts_at > now() or (
      (e.host_id = auth.uid() or own.status = 'approved') and
      (e.starts_at at time zone 'Asia/Tokyo')::date = (now() at time zone 'Asia/Tokyo')::date
    ))
  order by e.starts_at, e.id
  limit 100;
$$;

revoke execute on function koko_private.publish_weekly_runs(), koko_private.can_check_in(uuid, uuid),
  koko_private.mutual_again(uuid) from public, anon, authenticated;
revoke execute on function public.koko_stop_weekly(uuid), public.koko_follow_weekly(uuid, boolean),
  public.koko_again_connections(), public.koko_set_again(uuid, boolean), public.koko_again_events(),
  public.koko_set_arrived(uuid, boolean), public.koko_arrivals(uuid), public.koko_community_events(uuid)
  from public, anon, authenticated;
grant execute on function public.koko_stop_weekly(uuid), public.koko_follow_weekly(uuid, boolean),
  public.koko_again_connections(), public.koko_set_again(uuid, boolean), public.koko_again_events(),
  public.koko_set_arrived(uuid, boolean), public.koko_arrivals(uuid) to authenticated;
grant execute on function public.koko_community_events(uuid) to anon, authenticated;
