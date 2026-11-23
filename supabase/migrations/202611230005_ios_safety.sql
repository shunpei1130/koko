create table koko_private.user_blocks (
  blocker uuid references public.profiles(id) on delete cascade,
  blocked uuid references public.profiles(id) on delete cascade,
  primary key (blocker, blocked),
  check (blocker <> blocked)
);
create index koko_user_blocks_reverse on koko_private.user_blocks(blocked, blocker);

create table koko_private.community_reports (
  id uuid primary key default gen_random_uuid(),
  reporter uuid references public.profiles(id) on delete set null,
  reported uuid references public.profiles(id) on delete set null,
  event_id uuid references public.run_events(id) on delete set null,
  reason text not null check (reason in ('harassment', 'spam', 'unsafe', 'other')),
  state text not null default 'open' check (state in ('open', 'reviewed', 'resolved')),
  created_at timestamptz not null default now()
);
alter table koko_private.user_blocks enable row level security;
alter table koko_private.community_reports enable row level security;

create function koko_private.is_blocked(first_user uuid, second_user uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from koko_private.user_blocks
    where (blocker = first_user and blocked = second_user)
       or (blocker = second_user and blocked = first_user));
$$;

create function public.koko_event_host(target_event uuid)
returns uuid language sql stable security definer set search_path = '' as $$
  select host_id from public.run_events where id = target_event and auth.uid() is not null
    and not koko_private.is_blocked(auth.uid(), host_id);
$$;

create function public.koko_block_user(target_user uuid, enabled boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare actor uuid := auth.uid();
begin
  if actor is null or target_user is null or actor = target_user
    or not exists (select 1 from public.profiles where id = actor)
  then raise exception 'invalid_target'; end if;
  if enabled then
    insert into koko_private.user_blocks values (actor, target_user) on conflict do nothing;
  else
    delete from koko_private.user_blocks where blocker = actor and blocked = target_user;
  end if;
end;
$$;

create function public.koko_blocked_users()
returns table (id uuid, name text)
language sql stable security definer set search_path = '' as $$
  select p.id, p.display_name from koko_private.user_blocks b
  join public.profiles p on p.id = b.blocked where b.blocker = auth.uid()
  order by p.display_name, p.id;
$$;

create function public.koko_my_profile()
returns text language sql stable security definer set search_path = '' as $$
  select display_name from public.profiles where id = auth.uid();
$$;

create function public.koko_report_user(target_user uuid, reason_key text, target_event uuid default null)
returns void language plpgsql security definer set search_path = '' as $$
declare actor uuid := auth.uid();
begin
  if actor is null or target_user is null or actor = target_user
    or not exists (select 1 from public.profiles where id = actor)
    or (target_event is not null and not exists (
      select 1 from public.run_events e where e.id = target_event and (e.host_id = target_user or
        (e.host_id = actor and exists (select 1 from public.event_participants p
          where p.event_id = e.id and p.user_id = target_user)))
    ))
  then raise exception 'invalid_target'; end if;
  perform id from public.profiles where id = actor for update;
  if (select count(*) from koko_private.community_reports
    where reporter = actor and created_at > now() - interval '1 day') >= 20
  then raise exception 'report_rate_limit'; end if;
  if not exists (select 1 from koko_private.community_reports
    where reporter = actor and reported = target_user and reason = reason_key
      and event_id is not distinct from target_event and state = 'open')
  then
    insert into koko_private.community_reports (reporter, reported, event_id, reason)
      values (actor, target_user, target_event, reason_key);
  end if;
end;
$$;

create function public.koko_delete_account()
returns void language plpgsql security definer set search_path = '' as $$
declare actor uuid := auth.uid();
begin
  if actor is null then raise exception 'sign_in_required'; end if;
  delete from auth.users where id = actor;
end;
$$;

create table koko_private.blocked_name_terms (term text primary key);
alter table koko_private.blocked_name_terms enable row level security;
insert into koko_private.blocked_name_terms values ('死ね'), ('殺す'), ('kill yourself'), ('kys');

create function koko_private.check_display_name()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if (new.display_name ~ '[[:cntrl:]]' or new.display_name ~* '(https?://|www[.])' or exists (
    select 1 from koko_private.blocked_name_terms t where position(t.term in lower(new.display_name)) > 0
  )) then raise exception 'display_name_not_allowed'; end if;
  return new;
end;
$$;
create trigger koko_filter_display_name before insert or update of display_name on public.profiles
  for each row execute function koko_private.check_display_name();

revoke execute on function koko_private.is_blocked(uuid,uuid), koko_private.check_display_name()
  from public, anon, authenticated;
revoke execute on function public.koko_event_host(uuid), public.koko_block_user(uuid,boolean),
  public.koko_blocked_users(), public.koko_report_user(uuid,text,uuid), public.koko_delete_account(), public.koko_my_profile()
  from public, anon, authenticated;
grant execute on function public.koko_event_host(uuid), public.koko_block_user(uuid,boolean),
  public.koko_blocked_users(), public.koko_report_user(uuid,text,uuid), public.koko_delete_account(), public.koko_my_profile()
  to authenticated;


create or replace function public.list_koko_events(target_event uuid default null)
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
  where (target_event is null or e.id = target_event) and e.starts_at > now() and not koko_private.is_blocked(auth.uid(), e.host_id)
  order by e.starts_at, e.id
  limit 100;
$$;

create or replace function public.koko_community_events(target_event uuid default null)
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
  where not koko_private.is_blocked(auth.uid(), e.host_id) and (target_event is null or e.id = target_event)
    and (e.starts_at > now() or (
      (e.host_id = auth.uid() or own.status = 'approved') and
      (e.starts_at at time zone 'Asia/Tokyo')::date = (now() at time zone 'Asia/Tokyo')::date
    ))
  order by e.starts_at, e.id
  limit 100;
$$;

create or replace function public.koko_host_instagram(target_event uuid)
returns text language sql stable security definer set search_path = '' as $$
  select host.instagram_handle
  from public.run_events e join public.profiles host on host.id = e.host_id
  where e.id = target_event and e.starts_at > now() and not koko_private.is_blocked(auth.uid(), e.host_id)
    and (host.allow_ig_preview or host.id = auth.uid());
$$;

create or replace function public.request_koko_event(target_event uuid)
returns public.koko_participation language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
  event public.run_events;
  current_status public.koko_participation;
begin
  if actor is null then raise exception 'sign_in_required'; end if;
  select * into event from public.run_events where id = target_event for update;
  if not found or event.starts_at <= now() or event.host_id = actor
    or koko_private.is_blocked(actor, event.host_id) then
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

create or replace function public.koko_event_requests(target_event uuid)
returns table (user_id uuid, display_name text, avatar_emoji text, status public.koko_participation)
language sql stable security definer set search_path = '' as $$
  select p.user_id, member.display_name, member.avatar_emoji, p.status
  from public.run_events e
  join public.event_participants p on p.event_id = e.id
  join public.profiles member on member.id = p.user_id
  where e.id = target_event and e.host_id = auth.uid() and e.starts_at > now()
    and not koko_private.is_blocked(auth.uid(), p.user_id)
  order by p.created_at, p.user_id;
$$;

create or replace function public.decide_koko_request(target_event uuid, applicant uuid, approve boolean)
returns public.koko_participation language plpgsql security definer set search_path = '' as $$
declare
  event public.run_events;
  current_status public.koko_participation;
  decision public.koko_participation;
begin
  select * into event from public.run_events
    where id = target_event and host_id = auth.uid() for update;
  if not found or event.starts_at <= now()
    or koko_private.is_blocked(auth.uid(), applicant) then raise exception 'event_unavailable'; end if;

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

create or replace function public.koko_live_map()
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
        where p.expires_at > now() and not koko_private.is_blocked(auth.uid(), p.user_id)
        group by p.zone_id
      ) s
    ), '[]'::jsonb),
    'self', (
      select jsonb_build_object('zone', p.zone_id, 'expires_at', p.expires_at)
      from public.zone_presence p where p.user_id = auth.uid() and p.expires_at > now()
    )
  );
$$;

create or replace function public.send_koko_cheer(target_zone public.koko_zone)
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
      and not koko_private.is_blocked(actor, user_id)
    on conflict do nothing;
  get diagnostics sent = row_count;
  return sent;
end;
$$;

create or replace function koko_private.encounters(actor uuid)
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
  select e.person, e.day, bool_or(e.event_match) from encounters e where not koko_private.is_blocked(actor, e.person) group by e.person, e.day;
$$;

create or replace function public.koko_otsurun()
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
  where not koko_private.is_blocked(auth.uid(), u.id)
  order by e.run_date desc, u.id
  limit 100;
$$;

create or replace function public.koko_today_crew()
returns jsonb language sql stable security definer set search_path = '' as $$
  with chosen as (
    select e.* from public.run_events e
    where e.starts_at <= now() and not koko_private.is_blocked(auth.uid(), e.host_id)
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
    where not koko_private.is_blocked(auth.uid(), u.id)
  )) from chosen e;
$$;

create or replace function koko_private.mutual_again(actor uuid)
returns table (partner uuid)
language sql stable security definer set search_path = '' as $$
  select distinct sent.receiver_id
  from public.otsurun_stamps sent
  join public.otsurun_stamps received on received.sender_id = sent.receiver_id
    and received.receiver_id = sent.sender_id and received.run_date = sent.run_date
    and received.stamp_type = 'again'
  where sent.sender_id = actor and sent.stamp_type = 'again'
    and not koko_private.is_blocked(actor, sent.receiver_id);
$$;

create or replace function public.koko_again_events()
returns table (event_id uuid, name text, starts_at timestamptz, zone_id public.koko_zone)
language sql stable security definer set search_path = '' as $$
  select e.id, p.display_name, e.starts_at, e.meet_zone_id
  from koko_private.again_preferences pref
  join public.run_events e on e.host_id = pref.partner_id and e.created_at >= pref.enabled_at
  join public.profiles p on p.id = pref.partner_id
  where pref.user_id = auth.uid() and e.starts_at > now()
    and not koko_private.is_blocked(auth.uid(), e.host_id)
  order by e.starts_at, e.id limit 25;
$$;

create or replace function koko_private.can_check_in(target uuid, actor uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.run_events e where e.id = target and not koko_private.is_blocked(actor, e.host_id)
      and (e.starts_at at time zone 'Asia/Tokyo')::date = (now() at time zone 'Asia/Tokyo')::date
      and (e.host_id = actor or exists (
        select 1 from public.event_participants p where p.event_id = e.id
          and p.user_id = actor and p.status = 'approved'
      ))
  );
$$;

create or replace function public.koko_arrivals(target_event uuid)
returns table (name text, emoji text, is_self boolean)
language sql stable security definer set search_path = '' as $$
  select p.display_name, p.avatar_emoji, a.user_id = auth.uid()
  from koko_private.arrivals a
  join public.profiles p on p.id = a.user_id
  where a.event_id = target_event and koko_private.can_check_in(target_event, auth.uid())
    and not koko_private.is_blocked(auth.uid(), a.user_id)
  order by p.display_name, p.id;
$$;

create or replace function public.koko_follow_weekly(series uuid, enabled boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare actor uuid := auth.uid();
begin
  if not exists (select 1 from public.profiles where id = actor) then raise exception 'profile_required'; end if;
  if enabled then
    if not exists (select 1 from public.run_events where id = series and series_id = id and weekly_active
      and not koko_private.is_blocked(actor, host_id)) then
      raise exception 'event_unavailable';
    end if;
    insert into koko_private.followed_series(user_id, series_id) values (actor, series) on conflict do nothing;
  else
    delete from koko_private.followed_series where user_id = actor and series_id = series;
  end if;
end;
$$;

drop policy cheers_read_self on public.koko_cheers;
-- Keep the Realtime check inside the database without exposing arbitrary pairs.
create function public.koko_can_receive_cheer(sender uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and not koko_private.is_blocked(auth.uid(), sender);
$$;
revoke execute on function public.koko_can_receive_cheer(uuid) from public, anon, authenticated;
grant execute on function public.koko_can_receive_cheer(uuid) to authenticated;
create policy cheers_read_self on public.koko_cheers for select to authenticated
  using (receiver_id = (select auth.uid()) and public.koko_can_receive_cheer(sender_id));
