-- ============================================================
-- BIKE LOOP — row level security policies
-- Principle: authorization is enforced in the database. The app holds only the anon key.
-- ============================================================

-- Admin check helper; security definer avoids recursive RLS evaluation
create or replace function public.is_admin()
returns boolean
language sql security definer stable set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin'
  );
$$;

-- ------------------------------------------------------------
-- profiles
-- ------------------------------------------------------------
alter table public.profiles enable row level security;

drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select to authenticated
  using (id = auth.uid() or public.is_admin());

-- Users may edit their own profile, but the role column is blocked by column privileges
drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

revoke update on public.profiles from authenticated;
grant  update (display_name) on public.profiles to authenticated;
-- Role changes are made only from the Supabase dashboard (service_role).
--   Grant admin: update profiles set role='admin' where id='<uuid>';

-- ------------------------------------------------------------
-- reports
-- ------------------------------------------------------------
alter table public.reports enable row level security;

-- Any signed-in user may read reports so the map can render them
drop policy if exists reports_select on public.reports;
create policy reports_select on public.reports
  for select to authenticated
  using (true);

-- Insert: only under one's own id, and only in the submitted state
drop policy if exists reports_insert on public.reports;
create policy reports_insert on public.reports
  for insert to authenticated
  with check (
    reporter_id = auth.uid()
    and status = 'submitted'
    and duplicate_of is null
    and job_id is null
  );

-- Update (approve / reject / duplicate / schedule / collect): admins only
drop policy if exists reports_update on public.reports;
create policy reports_update on public.reports
  for update to authenticated
  using (public.is_admin());

drop policy if exists reports_delete on public.reports;
create policy reports_delete on public.reports
  for delete to authenticated
  using (public.is_admin());

-- ------------------------------------------------------------
-- collection_jobs / job_stops / bikes: admin only
-- ------------------------------------------------------------
alter table public.collection_jobs enable row level security;
drop policy if exists jobs_all on public.collection_jobs;
create policy jobs_all on public.collection_jobs
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

alter table public.job_stops enable row level security;
drop policy if exists stops_all on public.job_stops;
create policy stops_all on public.job_stops
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

alter table public.bikes enable row level security;
drop policy if exists bikes_all on public.bikes;
create policy bikes_all on public.bikes
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ------------------------------------------------------------
-- Storage: the report-photos bucket
-- (Create the 'report-photos' bucket in the dashboard first; it must not be public)
-- Path convention: report-photos/{uid}/{filename}
-- ------------------------------------------------------------
drop policy if exists photos_read on storage.objects;
create policy photos_read on storage.objects
  for select to authenticated
  using (bucket_id = 'report-photos');

drop policy if exists photos_insert on storage.objects;
create policy photos_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'report-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
