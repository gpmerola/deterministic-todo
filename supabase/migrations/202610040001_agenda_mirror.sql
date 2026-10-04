-- Read-only web Agenda: the phone mirrors what its Agenda shows (calendars
-- shown, filters applied, duplicates merged) for a fixed window. One RPC
-- replaces the whole snapshot atomically; the web only reads.
create table public.agenda_snapshots (
  user_id uuid primary key references auth.users(id) on delete cascade,
  device_id text not null,
  zone_label text,
  window_start timestamptz not null,
  window_end timestamptz not null,
  uploaded_at timestamptz not null default now(),
  calendars jsonb not null default '[]'::jsonb,
  task_links jsonb not null default '[]'::jsonb
);

create table public.agenda_events (
  user_id uuid not null references auth.users(id) on delete cascade,
  instance_key text not null,
  calendar_keys jsonb not null,
  title text not null,
  location text,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  all_day boolean not null default false,
  -- Civil dates for all-day events: independent of the viewer's zone.
  start_date date,
  end_date date,
  meeting_provider text,
  meeting_url text,
  time_zone text,
  event_zone_times text,
  is_organizer boolean not null default true,
  primary key (user_id, instance_key)
);

create index agenda_events_user_start_idx
  on public.agenda_events (user_id, starts_at);

alter table public.agenda_snapshots enable row level security;
alter table public.agenda_events enable row level security;

create policy "agenda_snapshots_select_own" on public.agenda_snapshots
  for select using (auth.uid() = user_id);
create policy "agenda_events_select_own" on public.agenda_events
  for select using (auth.uid() = user_id);

-- Writes only through the RPC below.
revoke insert, update, delete, truncate on public.agenda_snapshots
  from public, anon, authenticated;
revoke insert, update, delete, truncate on public.agenda_events
  from public, anon, authenticated;
revoke all on public.agenda_snapshots, public.agenda_events from anon;

create function public.replace_agenda_snapshot_v1(snapshot jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  owner uuid := auth.uid();
begin
  if owner is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  if jsonb_array_length(coalesce(snapshot->'events', '[]'::jsonb)) > 5000 then
    raise exception 'snapshot too large' using errcode = '22023';
  end if;

  delete from public.agenda_events where user_id = owner;

  insert into public.agenda_events (
    user_id, instance_key, calendar_keys, title, location, starts_at, ends_at,
    all_day, start_date, end_date, meeting_provider, meeting_url, time_zone,
    event_zone_times, is_organizer
  )
  select owner, e.instance_key, coalesce(e.calendar_keys, '[]'::jsonb),
    left(e.title, 500), left(e.location, 500), e.starts_at, e.ends_at,
    coalesce(e.all_day, false), e.start_date, e.end_date,
    left(e.meeting_provider, 20), left(e.meeting_url, 2000),
    left(e.time_zone, 64), left(e.event_zone_times, 40),
    coalesce(e.is_organizer, true)
  from jsonb_to_recordset(coalesce(snapshot->'events', '[]'::jsonb)) as e(
    instance_key text, calendar_keys jsonb, title text, location text,
    starts_at timestamptz, ends_at timestamptz, all_day boolean,
    start_date date, end_date date, meeting_provider text, meeting_url text,
    time_zone text, event_zone_times text, is_organizer boolean
  );

  insert into public.agenda_snapshots (
    user_id, device_id, zone_label, window_start, window_end, uploaded_at,
    calendars, task_links
  ) values (
    owner,
    left(snapshot->>'device_id', 100),
    left(snapshot->>'zone_label', 100),
    (snapshot->>'window_start')::timestamptz,
    (snapshot->>'window_end')::timestamptz,
    now(),
    coalesce(snapshot->'calendars', '[]'::jsonb),
    coalesce(snapshot->'task_links', '[]'::jsonb)
  )
  on conflict (user_id) do update set
    device_id = excluded.device_id,
    zone_label = excluded.zone_label,
    window_start = excluded.window_start,
    window_end = excluded.window_end,
    uploaded_at = excluded.uploaded_at,
    calendars = excluded.calendars,
    task_links = excluded.task_links;
end;
$$;

revoke all on function public.replace_agenda_snapshot_v1(jsonb)
  from public, anon;
grant execute on function public.replace_agenda_snapshot_v1(jsonb)
  to authenticated;
