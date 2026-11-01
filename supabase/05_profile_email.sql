-- ============================================================
-- BIKE LOOP — add profiles.email so the admin can see who filed a report
-- Paste the whole file into the Supabase SQL editor and run it
-- ============================================================
-- Why this is needed:
--   The email lives in auth.users, which the app (holding only the anon key)
--   cannot read for other users. So it is mirrored into profiles and guarded by RLS.
--
-- Privacy note:
--   The profiles_select policy already allows only "self or admin",
--   so an ordinary user can never read another person's email.
--   (02_rls.sql: using (id = auth.uid() or public.is_admin()))
--   Admin access exists to process the report, i.e. within the original purpose.
-- ============================================================

-- 1) Add the column
alter table public.profiles
  add column if not exists email text not null default '';

-- 2) Backfill existing users from auth.users
update public.profiles p
   set email = u.email
  from auth.users u
 where u.id = p.id
   and coalesce(p.email, '') = '';

-- 3) Populate on sign-up by replacing the existing trigger function
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  insert into public.profiles (id, display_name, email)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'display_name', ''),
    coalesce(new.email, '')
  );
  return new;
end;
$$;

-- 4) Keep it in sync when the email changes (optional but safer)
create or replace function public.sync_profile_email()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  update public.profiles
     set email = coalesce(new.email, '')
   where id = new.id;
  return new;
end;
$$;

drop trigger if exists on_auth_user_email_changed on auth.users;
create trigger on_auth_user_email_changed
  after update of email on auth.users
  for each row execute function public.sync_profile_email();

-- 5) Verification
-- select id, display_name, email, role from public.profiles;
