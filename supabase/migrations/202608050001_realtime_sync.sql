-- Realtime rende immediata la convergenza fra Android e browser. Le policy RLS
-- continuano a limitare ogni evento all'utente autenticato.
do $$
begin
  alter publication supabase_realtime add table public.tasks;
exception
  when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.projects;
exception
  when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.project_sections;
exception
  when duplicate_object then null;
end $$;
