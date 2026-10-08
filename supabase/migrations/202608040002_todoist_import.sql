alter table public.tasks
  add column if not exists priority integer not null default 1
    check (priority between 1 and 4),
  add column if not exists project_id uuid,
  add column if not exists section_id uuid,
  add column if not exists external_source text,
  add column if not exists external_id text;

create unique index if not exists tasks_user_external_idx
  on public.tasks (user_id, external_source, external_id)
  where external_id is not null;

create table if not exists public.projects (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (length(trim(name)) > 0),
  color text,
  parent_id uuid,
  position bigint not null,
  is_favorite boolean not null default false,
  is_archived boolean not null default false,
  external_source text,
  external_id text,
  logical_version bigint not null check (logical_version > 0),
  device_id uuid not null
);

create table if not exists public.project_sections (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  project_id uuid not null,
  name text not null check (length(trim(name)) > 0),
  position bigint not null,
  is_archived boolean not null default false,
  external_source text,
  external_id text,
  logical_version bigint not null check (logical_version > 0),
  device_id uuid not null
);

create unique index if not exists projects_user_external_idx
  on public.projects (user_id, external_source, external_id)
  where external_id is not null;
create unique index if not exists sections_user_external_idx
  on public.project_sections (user_id, external_source, external_id)
  where external_id is not null;

alter table public.projects enable row level security;
alter table public.project_sections enable row level security;

create policy "projects_select_own" on public.projects
  for select using (auth.uid() = user_id);
create policy "projects_insert_own" on public.projects
  for insert with check (auth.uid() = user_id);
create policy "projects_update_own" on public.projects
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "sections_select_own" on public.project_sections
  for select using (auth.uid() = user_id);
create policy "sections_insert_own" on public.project_sections
  for insert with check (auth.uid() = user_id);
create policy "sections_update_own" on public.project_sections
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

create or replace function public.merge_project(record jsonb)
returns void language plpgsql security invoker set search_path = public as $$
begin
  if (record->>'user_id')::uuid <> auth.uid() then raise exception 'forbidden'; end if;
  insert into public.projects (
    id,user_id,name,color,parent_id,position,is_favorite,is_archived,
    external_source,external_id,logical_version,device_id
  ) values (
    (record->>'id')::uuid,(record->>'user_id')::uuid,record->>'name',record->>'color',
    (record->>'parent_id')::uuid,(record->>'position')::bigint,
    coalesce((record->>'is_favorite')::boolean,false),
    coalesce((record->>'is_archived')::boolean,false),record->>'external_source',
    record->>'external_id',(record->>'logical_version')::bigint,(record->>'device_id')::uuid
  ) on conflict (id) do update set
    name=excluded.name,color=excluded.color,parent_id=excluded.parent_id,
    position=excluded.position,is_favorite=excluded.is_favorite,
    is_archived=excluded.is_archived,external_source=excluded.external_source,
    external_id=excluded.external_id,logical_version=excluded.logical_version,
    device_id=excluded.device_id
  where (projects.logical_version,projects.device_id::text) <
        (excluded.logical_version,excluded.device_id::text);
end;
$$;

create or replace function public.merge_project_section(record jsonb)
returns void language plpgsql security invoker set search_path = public as $$
begin
  if (record->>'user_id')::uuid <> auth.uid() then raise exception 'forbidden'; end if;
  insert into public.project_sections (
    id,user_id,project_id,name,position,is_archived,external_source,
    external_id,logical_version,device_id
  ) values (
    (record->>'id')::uuid,(record->>'user_id')::uuid,(record->>'project_id')::uuid,
    record->>'name',(record->>'position')::bigint,
    coalesce((record->>'is_archived')::boolean,false),record->>'external_source',
    record->>'external_id',(record->>'logical_version')::bigint,(record->>'device_id')::uuid
  ) on conflict (id) do update set
    project_id=excluded.project_id,name=excluded.name,position=excluded.position,
    is_archived=excluded.is_archived,external_source=excluded.external_source,
    external_id=excluded.external_id,logical_version=excluded.logical_version,
    device_id=excluded.device_id
  where (project_sections.logical_version,project_sections.device_id::text) <
        (excluded.logical_version,excluded.device_id::text);
end;
$$;

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
    priority,project_id,section_id,external_source,external_id,
    position,recurrence,series_id,occurrence_key,created_at,updated_at,
    completed_at,deleted_at,logical_version,device_id
  ) values (
    (record->>'id')::uuid,(record->>'user_id')::uuid,record->>'title',record->>'notes',record->>'status',
    record->>'show_date',record->>'due_date',(record->>'time_minutes')::integer,record->>'time_zone',
    coalesce((record->>'priority')::integer,1),(record->>'project_id')::uuid,
    (record->>'section_id')::uuid,record->>'external_source',record->>'external_id',
    (record->>'position')::bigint,record->>'recurrence',(record->>'series_id')::uuid,record->>'occurrence_key',
    (record->>'created_at')::bigint,(record->>'updated_at')::bigint,(record->>'completed_at')::bigint,
    (record->>'deleted_at')::bigint,(record->>'logical_version')::bigint,(record->>'device_id')::uuid
  )
  on conflict (id) do update set
    title=excluded.title, notes=excluded.notes, status=excluded.status,
    show_date=excluded.show_date, due_date=excluded.due_date,
    time_minutes=excluded.time_minutes, time_zone=excluded.time_zone,
    priority=excluded.priority, project_id=excluded.project_id,
    section_id=excluded.section_id, external_source=excluded.external_source,
    external_id=excluded.external_id, position=excluded.position,
    recurrence=excluded.recurrence, series_id=excluded.series_id,
    occurrence_key=excluded.occurrence_key, updated_at=excluded.updated_at,
    completed_at=excluded.completed_at, deleted_at=excluded.deleted_at,
    logical_version=excluded.logical_version, device_id=excluded.device_id
  where (tasks.logical_version, tasks.device_id::text) <
        (excluded.logical_version, excluded.device_id::text);
end;
$$;
