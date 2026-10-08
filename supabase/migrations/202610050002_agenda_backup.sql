-- Backup of what exists only in Todo's Agenda (build 227): events of the
-- phone-only "Todo" calendar, notes included by the user's choice, plus the
-- Agenda choices (hidden events, filters, colours, calendars). One row per
-- user, written only through the RPC below and read back to restore it on a
-- new phone.
create table public.agenda_backups (
  user_id uuid primary key references auth.users(id) on delete cascade,
  device_id text not null,
  hash text not null,
  saved_at timestamptz not null default now(),
  payload jsonb not null
);

alter table public.agenda_backups enable row level security;

create policy "agenda_backups_select_own" on public.agenda_backups
  for select using (auth.uid() = user_id);

revoke insert, update, delete, truncate on public.agenda_backups
  from public, anon, authenticated;
revoke all on public.agenda_backups from anon;

-- Returns 'saved', 'unchanged' or 'conflict'. A phone may replace the backup
-- only when it is still the one it last saved or restored ([base_hash]): a
-- new, empty phone must never overwrite the backup it has not restored yet,
-- nor an old phone found again the one written since.
create function public.save_agenda_backup_v1(
  backup jsonb,
  backup_hash text,
  base_hash text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  owner uuid := auth.uid();
  current_hash text;
begin
  if owner is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  if backup_hash is null or length(backup_hash) > 128
      or jsonb_typeof(backup) <> 'object' then
    raise exception 'invalid backup' using errcode = '22023';
  end if;
  if octet_length(backup::text) > 4000000 then
    raise exception 'backup too large' using errcode = '22023';
  end if;

  select hash into current_hash
  from public.agenda_backups
  where user_id = owner
  for update;

  if found then
    if current_hash = backup_hash then
      return 'unchanged';
    end if;
    if base_hash is null or current_hash <> base_hash then
      return 'conflict';
    end if;
    update public.agenda_backups set
      device_id = left(coalesce(backup->>'device_id', ''), 100),
      hash = backup_hash,
      saved_at = now(),
      payload = backup
    where user_id = owner;
    return 'saved';
  end if;

  insert into public.agenda_backups (user_id, device_id, hash, payload)
  values (owner, left(coalesce(backup->>'device_id', ''), 100), backup_hash,
    backup)
  on conflict (user_id) do nothing;
  return case when found then 'saved' else 'conflict' end;
end;
$$;

revoke all on function public.save_agenda_backup_v1(jsonb, text, text)
  from public, anon;
grant execute on function public.save_agenda_backup_v1(jsonb, text, text)
  to authenticated;
