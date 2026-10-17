-- One statement snapshot for all reconciliation metadata; no task contents.
-- Scalar JSON avoids PostgREST response row caps. Existing v1 clients keep working.
create function public.todo_sync_overview_v1() returns jsonb
language sql stable security invoker set search_path = public as $$
  select jsonb_build_object(
    'schema', 1,
    'tasks', public.todo_task_fingerprints_v1(),
    'projects', (select encode(sha256(convert_to(coalesce(string_agg(
      id::text || ':' || logical_version::text || ':' || device_id::text || ';',
      '' order by id), ''), 'UTF8')), 'hex') from public.projects where user_id = auth.uid()),
    'project_sections', (select encode(sha256(convert_to(coalesce(string_agg(
      id::text || ':' || logical_version::text || ':' || device_id::text || ';',
      '' order by id), ''), 'UTF8')), 'hex') from public.project_sections where user_id = auth.uid()),
    'purged_entities', (select encode(sha256(convert_to(coalesce(string_agg(
      'purged:' || entity_type || ':' || entity_id::text || ';',
      '' order by ('purged:' || entity_type || ':' || entity_id::text) collate "C"), ''), 'UTF8')), 'hex')
      from public.purged_entities where user_id = auth.uid())
  );
$$;
revoke all on function public.todo_sync_overview_v1() from public, anon;
grant execute on function public.todo_sync_overview_v1() to authenticated;
