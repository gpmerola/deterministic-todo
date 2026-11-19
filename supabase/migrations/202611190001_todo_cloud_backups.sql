-- Daily off-phone copy of the Todo backup JSON 2 (build 330). Additive only:
-- one new table and one new function, nothing existing is altered or dropped.
-- Rows are readable only by their owner (RLS) and written only through the
-- RPC below, which keeps the newest 14 copies per user and removes only older
-- copies from this table, never Todo data. The content is not encrypted with
-- a phone key (that key would be lost with the phone): like the synced tasks,
-- it is protected by RLS and Supabase's encryption at rest.
create table public.todo_cloud_backups (
  id uuid primary key default gen_random_uuid(),
  -- Copy order: saved_at can tie, a sequence cannot.
  seq bigint generated always as identity unique,
  user_id uuid not null references auth.users(id) on delete cascade,
  device_id text not null,
  content_hash text not null,
  encoding text not null check (encoding in ('gzip-base64')),
  size_bytes integer not null check (size_bytes > 0),
  saved_at timestamptz not null default clock_timestamp(),
  content text not null
);

create index todo_cloud_backups_user_saved_idx
  on public.todo_cloud_backups (user_id, seq desc);

alter table public.todo_cloud_backups enable row level security;

create policy "todo_cloud_backups_select_own" on public.todo_cloud_backups
  for select using (auth.uid() = user_id);

revoke insert, update, delete, truncate on public.todo_cloud_backups
  from public, anon, authenticated;
revoke all on public.todo_cloud_backups from anon;

-- Returns 'saved' or 'unchanged' (the newest copy already has this hash).
create function public.save_todo_cloud_backup_v1(
  backup_content text,
  backup_hash text,
  backup_encoding text,
  backup_size integer,
  backup_device text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  owner uuid := auth.uid();
  latest_hash text;
begin
  if owner is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  if backup_hash is null or backup_hash !~ '^[0-9a-f]{64}$'
      or backup_encoding is distinct from 'gzip-base64'
      or backup_size is null or backup_size <= 0
      or backup_device is null or length(backup_device) > 128
      or backup_content is null or length(backup_content) = 0 then
    raise exception 'invalid backup' using errcode = '22023';
  end if;
  if octet_length(backup_content) > 20000000 then
    raise exception 'backup too large' using errcode = '22023';
  end if;

  -- One writer per user at a time: two phones never interleave a prune.
  perform pg_advisory_xact_lock(hashtext('todo_cloud_backups:' || owner::text));

  select content_hash into latest_hash
  from public.todo_cloud_backups
  where user_id = owner
  order by seq desc
  limit 1;

  if latest_hash = backup_hash then
    return 'unchanged';
  end if;

  insert into public.todo_cloud_backups
    (user_id, device_id, content_hash, encoding, size_bytes, content)
  values
    (owner, backup_device, backup_hash, backup_encoding, backup_size,
     backup_content);

  delete from public.todo_cloud_backups
  where user_id = owner
    and id not in (
      select id from public.todo_cloud_backups
      where user_id = owner
      order by seq desc
      limit 14
    );

  return 'saved';
end;
$$;

revoke all on function public.save_todo_cloud_backup_v1(text, text, text, integer, text)
  from public, anon;
grant execute on function public.save_todo_cloud_backup_v1(text, text, text, integer, text)
  to authenticated;
