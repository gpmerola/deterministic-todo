-- Minimal durable deletion ledger: no task text, notes or other content.
create table public.purged_entities (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  entity_type text not null check (entity_type in ('tasks', 'projects', 'project_sections')),
  entity_id uuid not null,
  purged_at timestamptz not null default now(),
  unique(user_id, entity_type, entity_id)
);
alter table public.purged_entities enable row level security;
create policy purged_select_own on public.purged_entities
  for select to authenticated using (user_id = auth.uid());
grant select on public.purged_entities to authenticated;
revoke insert, update, delete on public.purged_entities from anon, authenticated;

-- The per-user transaction lock serializes purge with old and new client writes.
-- Take it before the write, including before a DELETE releases its unique key.
create function public.guard_purged_entity() returns trigger
language plpgsql security definer set search_path = public as $$
declare owner_id uuid; record_id uuid;
begin
  owner_id := case when TG_OP = 'DELETE' then OLD.user_id else NEW.user_id end;
  perform pg_advisory_xact_lock(hashtextextended(owner_id::text, 0));
  if TG_OP = 'DELETE' then return OLD; end if;
  record_id := NEW.id;
  if exists(select 1 from public.purged_entities
    where user_id = owner_id and entity_type = TG_TABLE_NAME and entity_id = record_id) then
    raise exception 'todo_entity_purged';
  end if;
  return NEW;
end;
$$;

create function public.remember_purged_entity() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  -- Account deletion intentionally removes all account data, including this ledger.
  if exists(select 1 from auth.users where id = OLD.user_id) then
    insert into public.purged_entities(user_id, entity_type, entity_id)
    values(OLD.user_id, TG_TABLE_NAME, OLD.id) on conflict do nothing;
  end if;
  return OLD;
end;
$$;

create trigger tasks_purge_guard before insert or update or delete on public.tasks
for each row execute function public.guard_purged_entity();
create trigger projects_purge_guard before insert or update or delete on public.projects
for each row execute function public.guard_purged_entity();
create trigger sections_purge_guard before insert or update or delete on public.project_sections
for each row execute function public.guard_purged_entity();
create trigger tasks_purge_ledger after delete on public.tasks
for each row execute function public.remember_purged_entity();
create trigger projects_purge_ledger after delete on public.projects
for each row execute function public.remember_purged_entity();
create trigger sections_purge_ledger after delete on public.project_sections
for each row execute function public.remember_purged_entity();
revoke all on function public.guard_purged_entity() from public;
revoke all on function public.remember_purged_entity() from public;

-- Keep the old RPC name protected as well: old clients cannot bypass the ledger.
create or replace function public.purge_trash() returns jsonb
language plpgsql security definer set search_path = public as $$
declare task_count integer; section_count integer; project_count integer;
begin
  if auth.uid() is null then raise exception 'unauthenticated'; end if;
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text, 0));
  delete from public.tasks where user_id = auth.uid() and deleted_at is not null;
  get diagnostics task_count = row_count;
  delete from public.project_sections where user_id = auth.uid() and is_archived;
  get diagnostics section_count = row_count;
  delete from public.projects where user_id = auth.uid() and is_archived;
  get diagnostics project_count = row_count;
  return jsonb_build_object('tasks', task_count, 'sections', section_count, 'projects', project_count);
end;
$$;

-- Capability boundary: new clients never fall back to an unsafe old-server purge.
create function public.purge_trash_v2() returns jsonb
language sql security invoker set search_path = public as $$
  select public.purge_trash();
$$;
revoke all on function public.purge_trash_v2() from public;
grant execute on function public.purge_trash_v2() to authenticated;
