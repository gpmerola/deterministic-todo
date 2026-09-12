-- Supabase grants ALL table privileges by default, including TRUNCATE.
-- RLS does not govern TRUNCATE: remove every client privilege before allowing
-- the one supported operation. Preserve the ledger and its existing contents.
revoke all privileges on table public.purged_entities from public, anon, authenticated;
grant select on table public.purged_entities to authenticated;

-- Explicit grants also override platform defaults on newly created functions.
revoke all privileges on function public.guard_purged_entity(),
  public.remember_purged_entity(), public.purge_trash_v2(), public.purge_trash()
  from public, anon, authenticated;
grant execute on function public.purge_trash_v2(), public.purge_trash() to authenticated;
