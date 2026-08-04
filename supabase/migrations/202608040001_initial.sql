create table public.tasks (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null check (length(trim(title)) > 0),
  notes text,
  status text not null check (status in ('inbox','available','scheduled','waiting','completed')),
  show_date text check (show_date is null or show_date ~ '^\d{4}-\d{2}-\d{2}$'),
  due_date text check (due_date is null or due_date ~ '^\d{4}-\d{2}-\d{2}$'),
  time_minutes integer check (time_minutes between 0 and 1439),
  time_zone text,
  position bigint not null,
  recurrence text,
  series_id uuid,
  occurrence_key text,
  created_at bigint not null,
  updated_at bigint not null,
  completed_at bigint,
  deleted_at bigint,
  logical_version bigint not null check (logical_version > 0),
  device_id uuid not null,
  unique (user_id, series_id, occurrence_key)
);

create table public.sync_operations (
  operation_id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  entity_id uuid not null,
  operation text not null check (operation in ('upsert','delete')),
  payload jsonb not null,
  received_at timestamptz not null default now()
);

create index tasks_user_updated_idx on public.tasks(user_id, logical_version, device_id);
create index tasks_user_deleted_idx on public.tasks(user_id, deleted_at) where deleted_at is not null;
create index sync_operations_user_received_idx on public.sync_operations(user_id, received_at);

alter table public.tasks enable row level security;
alter table public.sync_operations enable row level security;

create policy "tasks_select_own" on public.tasks for select using (auth.uid() = user_id);
create policy "tasks_insert_own" on public.tasks for insert with check (auth.uid() = user_id);
create policy "tasks_update_own" on public.tasks for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "operations_select_own" on public.sync_operations for select using (auth.uid() = user_id);
create policy "operations_insert_own" on public.sync_operations for insert with check (auth.uid() = user_id);

create or replace function public.merge_task(record jsonb)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  if (record->>'user_id')::uuid <> auth.uid() then
    raise exception 'forbidden';
  end if;
  insert into public.tasks (
    id,user_id,title,notes,status,show_date,due_date,time_minutes,time_zone,
    position,recurrence,series_id,occurrence_key,created_at,updated_at,
    completed_at,deleted_at,logical_version,device_id
  ) values (
    (record->>'id')::uuid,(record->>'user_id')::uuid,record->>'title',record->>'notes',record->>'status',
    record->>'show_date',record->>'due_date',(record->>'time_minutes')::integer,record->>'time_zone',
    (record->>'position')::bigint,record->>'recurrence',(record->>'series_id')::uuid,record->>'occurrence_key',
    (record->>'created_at')::bigint,(record->>'updated_at')::bigint,(record->>'completed_at')::bigint,
    (record->>'deleted_at')::bigint,(record->>'logical_version')::bigint,(record->>'device_id')::uuid
  )
  on conflict (id) do update set
    title=excluded.title, notes=excluded.notes, status=excluded.status,
    show_date=excluded.show_date, due_date=excluded.due_date,
    time_minutes=excluded.time_minutes, time_zone=excluded.time_zone,
    position=excluded.position, recurrence=excluded.recurrence,
    series_id=excluded.series_id, occurrence_key=excluded.occurrence_key,
    updated_at=excluded.updated_at, completed_at=excluded.completed_at,
    deleted_at=excluded.deleted_at, logical_version=excluded.logical_version,
    device_id=excluded.device_id
  where (tasks.logical_version, tasks.device_id::text) <
        (excluded.logical_version, excluded.device_id::text);
end;
$$;

-- I tombstone non vanno eliminati prima di 90 giorni. Un job di pulizia futuro
-- dovrà inoltre verificare i checkpoint di tutti i dispositivi dell'utente.
