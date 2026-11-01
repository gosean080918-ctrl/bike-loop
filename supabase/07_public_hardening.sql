-- ============================================================
-- BIKE LOOP — hardening pass before the public launch (2026-09-15)
-- Apply: paste into Supabase > SQL Editor and run it
-- Requires: 01 through 06 already applied
-- ============================================================
-- Why this exists
--   Until now only people we knew could use the app. Once it is public,
--   anyone can sign up, and "is signed in" stops being a meaningful
--   protection on its own.
--
-- What this changes
--   1) Report photos: previously readable by any signed-in user
--      -> now readable only by the uploader and administrators
--   2) Photo uploads: notes on capping size and count (bucket settings live in the dashboard)
--   3) Re-asserts who may edit or delete a report
-- ============================================================

-- ------------------------------------------------------------
-- 1) Storage: restrict who can read report photos
--    Paths follow report-photos/{uid}/{filename}, so if the first
--    folder segment is the caller's uid, the photo is theirs.
-- ------------------------------------------------------------
drop policy if exists photos_read on storage.objects;
create policy photos_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'report-photos'
    and (
      (storage.foldername(name))[1] = auth.uid()::text  -- uploaded by this user
      or public.is_admin()                              -- or an administrator
    )
  );

-- Upload rule is unchanged (own folder only); recreated here for clarity
drop policy if exists photos_insert on storage.objects;
create policy photos_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'report-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- Users may delete their own photos (to clean up a mistaken upload); admins may too.
drop policy if exists photos_delete on storage.objects;
create policy photos_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'report-photos'
    and (
      (storage.foldername(name))[1] = auth.uid()::text
      or public.is_admin()
    )
  );

-- ------------------------------------------------------------
-- 2) Editing and deleting reports — administrators only (already true; restated explicitly)
-- ------------------------------------------------------------
drop policy if exists reports_update on public.reports;
create policy reports_update on public.reports
  for update to authenticated
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists reports_delete on public.reports;
create policy reports_delete on public.reports
  for delete to authenticated
  using (public.is_admin());

-- ------------------------------------------------------------
-- 3) Flood protection — no more than 20 reports from one user in five minutes
--    (guards against bulk prank reports once the app is public)
-- ------------------------------------------------------------
create or replace function public.check_report_flood()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_recent int;
begin
  select count(*) into v_recent
    from public.reports
   where reporter_id = new.reporter_id
     and reported_at > now() - interval '5 minutes';

  if v_recent >= 20 then
    raise exception 'Too many reports in a short time. Please try again shortly.';
  end if;
  return new;
end;
$$;

drop trigger if exists reports_flood_guard on public.reports;
create trigger reports_flood_guard
  before insert on public.reports
  for each row execute function public.check_report_flood();

-- ------------------------------------------------------------
-- 4) Verification
-- ------------------------------------------------------------
-- List the policies
-- select tablename, policyname, cmd
--   from pg_policies
--  where schemaname in ('public','storage')
--  order by tablename, policyname;

-- ============================================================
-- [Settings that must be changed in the dashboard]
--  Storage > report-photos > Configuration
--    - Public bucket: keep OFF (mandatory)
--    - File size limit: 10MB
--    - Allowed MIME types: image/*
--
--  Authentication > Providers > Email
--    - Confirm email: ON recommended (cuts down on throwaway sign-ups)
--  Authentication > Rate limits
--    - keep the defaults or tighten them
-- ============================================================
