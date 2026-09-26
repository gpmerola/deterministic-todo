create or replace function public.purge_trash()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  task_count integer;
  section_count integer;
  project_count integer;
begin
  if auth.uid() is null then
    raise exception 'unauthenticated';
  end if;

  delete from public.tasks
  where user_id = auth.uid() and deleted_at is not null;
  get diagnostics task_count = row_count;

  delete from public.project_sections
  where user_id = auth.uid() and is_archived = true;
  get diagnostics section_count = row_count;

  delete from public.projects
  where user_id = auth.uid() and is_archived = true;
  get diagnostics project_count = row_count;

  return jsonb_build_object(
    'tasks', task_count,
    'sections', section_count,
    'projects', project_count
  );
end;
$$;

revoke all on function public.purge_trash() from public;
grant execute on function public.purge_trash() to authenticated;
