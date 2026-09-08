alter table public.tasks
  add column if not exists item_kind text not null default 'task';

alter table public.tasks
  drop constraint if exists tasks_item_kind_check;

alter table public.tasks
  add constraint tasks_item_kind_check
  check (item_kind in ('task', 'reference'));

create index if not exists tasks_item_kind_order_idx
  on public.tasks (user_id, item_kind, deleted_at, position, created_at, id);

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
    id,user_id,title,notes,item_kind,status,show_date,due_date,time_minutes,time_zone,
    priority,project_id,section_id,external_source,external_id,
    position,recurrence,series_id,occurrence_key,created_at,updated_at,
    completed_at,deleted_at,logical_version,device_id
  ) values (
    (record->>'id')::uuid,(record->>'user_id')::uuid,record->>'title',record->>'notes',
    coalesce(record->>'item_kind','task'),record->>'status',record->>'show_date',
    record->>'due_date',(record->>'time_minutes')::integer,record->>'time_zone',
    coalesce((record->>'priority')::integer,1),(record->>'project_id')::uuid,
    (record->>'section_id')::uuid,record->>'external_source',record->>'external_id',
    (record->>'position')::bigint,record->>'recurrence',(record->>'series_id')::uuid,
    record->>'occurrence_key',(record->>'created_at')::bigint,
    (record->>'updated_at')::bigint,(record->>'completed_at')::bigint,
    (record->>'deleted_at')::bigint,(record->>'logical_version')::bigint,
    (record->>'device_id')::uuid
  )
  on conflict (id) do update set
    title=excluded.title, notes=excluded.notes, item_kind=excluded.item_kind,
    status=excluded.status, show_date=excluded.show_date,
    due_date=excluded.due_date, time_minutes=excluded.time_minutes,
    time_zone=excluded.time_zone, priority=excluded.priority,
    project_id=excluded.project_id, section_id=excluded.section_id,
    external_source=excluded.external_source, external_id=excluded.external_id,
    position=excluded.position, recurrence=excluded.recurrence,
    series_id=excluded.series_id, occurrence_key=excluded.occurrence_key,
    updated_at=excluded.updated_at, completed_at=excluded.completed_at,
    deleted_at=excluded.deleted_at, logical_version=excluded.logical_version,
    device_id=excluded.device_id
  where (tasks.logical_version, tasks.device_id::text) <
        (excluded.logical_version, excluded.device_id::text);
end;
$$;
