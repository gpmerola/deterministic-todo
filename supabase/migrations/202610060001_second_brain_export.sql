-- Explicit, revocable read-only export. No grants exist until an administrator
-- provisions a randomly generated token hash for a specific owner.
create table public.second_brain_export_grants (
  user_id uuid primary key references auth.users(id) on delete cascade,
  token_hash bytea unique not null check (octet_length(token_hash) = 32),
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);
alter table public.second_brain_export_grants enable row level security;
revoke all on public.second_brain_export_grants from public, anon, authenticated;

create function public.second_brain_export_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare
  secret text := current_setting('request.headers', true)::jsonb->>'x-second-brain-token';
  owner uuid;
  result jsonb;
begin
  if secret is null or secret !~ '^[a-f0-9]{64}$' then
    raise exception 'export not authorized' using errcode = '42501';
  end if;
  select g.user_id into owner from public.second_brain_export_grants g
    where g.token_hash = sha256(convert_to(secret, 'UTF8')) and g.expires_at > now();
  if owner is null then
    raise exception 'export not authorized' using errcode = '42501';
  end if;
  -- Single statement snapshot: calendar rows and coverage cannot come from
  -- different phone uploads. Explicit projections exclude account identifiers,
  -- notes, meeting URLs, sync payloads and deleted/completed task history.
  select jsonb_build_object(
    'schema_version', 1,
    'exported_at', now(),
    'tasks', coalesce((select jsonb_agg(jsonb_build_object(
      'id', t.id, 'title', t.title, 'status', t.status,
      'show_date', t.show_date, 'time_minutes', t.time_minutes,
      'time_zone', t.time_zone, 'updated_at', t.updated_at
    ) order by t.show_date nulls last, t.time_minutes nulls last, t.id)
      from public.tasks t where t.user_id = owner
        and t.deleted_at is null and t.completed_at is null and t.status <> 'completed'), '[]'::jsonb),
    'calendar', (select jsonb_build_object(
      'uploaded_at', s.uploaded_at, 'window_start', s.window_start,
      'window_end', s.window_end, 'zone_label', s.zone_label,
      'events', coalesce((select jsonb_agg(jsonb_build_object(
        'id', e.instance_key, 'title', e.title,
        'starts_at', e.starts_at, 'ends_at', e.ends_at,
        'all_day', e.all_day, 'start_date', e.start_date,
        'end_date', e.end_date, 'time_zone', e.time_zone
      ) order by e.starts_at, e.instance_key)
        from public.agenda_events e where e.user_id = owner), '[]'::jsonb)
    ) from public.agenda_snapshots s where s.user_id = owner)
  ) into result;
  return result;
end;
$$;
revoke all on function public.second_brain_export_v1() from public;
grant execute on function public.second_brain_export_v1() to anon, authenticated;
