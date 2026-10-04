-- Web Agenda edits. Only the phone can write its calendars, so the browser
-- queues a request and the phone claims it, applies it and reports back.
-- A claimed request is never handed out again: a crash leaves it
-- "processing" and it is closed as unknown instead of being repeated, so an
-- event is never created twice.
create table public.agenda_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users(id) on delete cascade,
  kind text not null check (kind in ('create', 'update', 'delete')),
  -- Occurrence to change, as mirrored in agenda_events; null for create.
  instance_key text check (length(instance_key) <= 100),
  series boolean not null default false,
  payload jsonb not null default '{}'::jsonb
    check (jsonb_typeof(payload) = 'object' and pg_column_size(payload) <= 8192),
  status text not null default 'pending'
    check (status in ('pending', 'processing', 'done', 'failed')),
  error text,
  created_at timestamptz not null default now(),
  claimed_at timestamptz,
  completed_at timestamptz,
  check ((kind = 'create') = (instance_key is null))
);

create index agenda_requests_user_status_idx
  on public.agenda_requests (user_id, status, created_at);

alter table public.agenda_requests enable row level security;

create policy "agenda_requests_select_own" on public.agenda_requests
  for select using (auth.uid() = user_id);
create policy "agenda_requests_insert_own" on public.agenda_requests
  for insert with check (auth.uid() = user_id and status = 'pending');
-- A request can be changed or withdrawn only before the phone claims it.
create policy "agenda_requests_update_pending" on public.agenda_requests
  for update using (auth.uid() = user_id and status = 'pending')
  with check (auth.uid() = user_id and status = 'pending');
create policy "agenda_requests_delete_own" on public.agenda_requests
  for delete using (auth.uid() = user_id and status <> 'processing');

-- Status, owner and timestamps are set only by defaults and the RPCs below.
revoke all on public.agenda_requests from public, anon, authenticated;
grant select, delete on public.agenda_requests to authenticated;
grant insert (kind, instance_key, series, payload)
  on public.agenda_requests to authenticated;
grant update (series, payload) on public.agenda_requests to authenticated;

-- At most 100 open requests per user.
create function public.agenda_requests_limit()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if (select count(*) from public.agenda_requests
      where user_id = new.user_id and status in ('pending', 'processing')) >= 100 then
    raise exception 'too many agenda requests' using errcode = '54000';
  end if;
  return new;
end;
$$;

create trigger agenda_requests_limit
  before insert on public.agenda_requests
  for each row execute function public.agenda_requests_limit();

-- Phone: hands out the oldest pending requests once, marking them
-- "processing". Also closes requests stuck in "processing" for 30 minutes
-- as unknown and forgets closed ones after 14 days.
create function public.claim_agenda_requests_v1(max_count integer default 20)
returns setof public.agenda_requests
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

  update public.agenda_requests
  set status = 'failed',
      error = 'Esito sconosciuto: controlla il calendario sul telefono.',
      completed_at = now()
  where user_id = owner and status = 'processing'
    and claimed_at < now() - interval '30 minutes';

  delete from public.agenda_requests
  where user_id = owner and status in ('done', 'failed')
    and completed_at < now() - interval '14 days';

  return query
  update public.agenda_requests as r
  set status = 'processing', claimed_at = now()
  where r.id in (
    select q.id from public.agenda_requests as q
    where q.user_id = owner and q.status = 'pending'
    order by q.created_at, q.id
    limit greatest(1, least(coalesce(max_count, 20), 50))
    for update skip locked
  )
  returning r.*;
end;
$$;

-- Phone: result of one claimed request. False when it was not claimed.
create function public.complete_agenda_request_v1(
  request_id uuid,
  succeeded boolean,
  message text default null
)
returns boolean
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
  update public.agenda_requests
  set status = case when succeeded then 'done' else 'failed' end,
      error = case when succeeded then null
                   else left(coalesce(message, 'Non applicata.'), 200) end,
      completed_at = now()
  where id = request_id and user_id = owner and status = 'processing';
  return found;
end;
$$;

revoke all on function public.agenda_requests_limit() from public, anon, authenticated;
revoke all on function public.claim_agenda_requests_v1(integer) from public, anon;
revoke all on function public.complete_agenda_request_v1(uuid, boolean, text)
  from public, anon;
grant execute on function public.claim_agenda_requests_v1(integer) to authenticated;
grant execute on function public.complete_agenda_request_v1(uuid, boolean, text)
  to authenticated;
