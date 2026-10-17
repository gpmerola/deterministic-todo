-- Bucket fingerprints that include task content, not only version stamps.
-- A row that diverged at an equal Lamport version (build 246 «hinge» case)
-- changes its bucket, so the next client cycle pulls and rewrites it.
-- Additive: v1 functions stay for older clients. No content is returned.
-- Row signature: id:version:device:<fields>; with fields joined by ','.
-- Text is length-prefixed in code points ('5#hello'), integers are decimal,
-- null is '-'. Must match lib/data/sync/task_fingerprints.dart exactly.
create function public.todo_task_fingerprints_v2()
returns jsonb
language sql stable security invoker set search_path = public as $$
  select coalesce(jsonb_agg(to_jsonb(b) order by b.bucket), '[]'::jsonb) from (
  select left(id::text, 2) as bucket,
    encode(sha256(convert_to(string_agg(
      id::text || ':' || logical_version::text || ':' || device_id::text || ':' ||
      coalesce(length(title)::text || '#' || title, '-') || ',' ||
      coalesce(length(notes)::text || '#' || notes, '-') || ',' ||
      coalesce(length(item_kind)::text || '#' || item_kind, '-') || ',' ||
      coalesce(length(status)::text || '#' || status, '-') || ',' ||
      coalesce(length(show_date)::text || '#' || show_date, '-') || ',' ||
      coalesce(priority::text, '-') || ',' ||
      coalesce(length(project_id::text)::text || '#' || project_id::text, '-') || ',' ||
      coalesce(length(section_id::text)::text || '#' || section_id::text, '-') || ',' ||
      coalesce(position::text, '-') || ',' ||
      coalesce(length(recurrence)::text || '#' || recurrence, '-') || ',' ||
      coalesce(length(series_id::text)::text || '#' || series_id::text, '-') || ',' ||
      coalesce(length(occurrence_key)::text || '#' || occurrence_key, '-') || ',' ||
      coalesce(completed_at::text, '-') || ',' ||
      coalesce(deleted_at::text, '-') || ';',
      '' order by id), 'UTF8')), 'hex') as fingerprint
  from public.tasks
  where user_id = auth.uid()
  group by left(id::text, 2)
  ) b;
$$;
revoke all on function public.todo_task_fingerprints_v2() from public, anon;
grant execute on function public.todo_task_fingerprints_v2() to authenticated;

-- Same snapshot contract as todo_sync_overview_v1, with v2 task fingerprints.
create function public.todo_sync_overview_v2() returns jsonb
language sql stable security invoker set search_path = public as $$
  select jsonb_build_object(
    'schema', 2,
    'tasks', public.todo_task_fingerprints_v2(),
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
revoke all on function public.todo_sync_overview_v2() from public, anon;
grant execute on function public.todo_sync_overview_v2() to authenticated;
