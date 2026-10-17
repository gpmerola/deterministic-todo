-- Compact reconciliation of immutable UUID + Lamport version metadata.
-- No content is returned. Each statement observes one PostgreSQL snapshot;
-- no timestamp or global Lamport watermark can skip a delayed writer.
create function public.todo_task_fingerprints_v1()
returns jsonb
language sql stable security invoker set search_path = public as $$
  select coalesce(jsonb_agg(to_jsonb(b) order by b.bucket), '[]'::jsonb) from (
  select left(id::text, 2) as bucket,
    encode(sha256(convert_to(string_agg(
      id::text || ':' || logical_version::text || ':' || device_id::text || ';',
      '' order by id), 'UTF8')), 'hex') as fingerprint
  from public.tasks
  where user_id = auth.uid()
  group by left(id::text, 2)
  ) b;
$$;
revoke all on function public.todo_task_fingerprints_v1() from public, anon;
grant execute on function public.todo_task_fingerprints_v1() to authenticated;
