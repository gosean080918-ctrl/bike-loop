-- ============================================================
-- BIKE LOOP — database schema
-- Apply in the Supabase dashboard SQL editor, in order: 01 -> 02 -> 03
-- ============================================================

-- Enable PostGIS (Supabase recommends the extensions schema)
create extension if not exists postgis with schema extensions;

-- ------------------------------------------------------------
-- profiles: 1:1 with auth.users, holds the role
-- ------------------------------------------------------------
create table if not exists public.profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  role         text not null default 'user' check (role in ('user','admin')),
  display_name text not null default '',
  created_at   timestamptz not null default now()
);

-- Create a profile automatically on sign-up
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'display_name', ''));
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ------------------------------------------------------------
-- reports: abandoned bicycle reports
-- Status flow: submitted -> approved | rejected | duplicate
--            approved → scheduled → collected
-- ------------------------------------------------------------
create table if not exists public.reports (
  id           uuid primary key default gen_random_uuid(),
  reporter_id  uuid not null references public.profiles(id),
  photo_url    text not null,
  lat          double precision not null,
  lng          double precision not null,
  geom         extensions.geometry(point, 4326)
               generated always as (extensions.st_setsrid(extensions.st_makepoint(lng, lat), 4326)) stored,
  address      text,
  condition    text not null check (condition in
               ('long_term','damaged','obstruction','parts_missing','other')),
               -- long_term / damaged / obstruction / parts_missing / other
  description  text not null default '',
  status       text not null default 'submitted' check (status in
               ('submitted','approved','rejected','duplicate','scheduled','collected')),
  duplicate_of uuid references public.reports(id),
  priority     int not null default 0,
  reported_at  timestamptz not null default now(),
  reviewed_at  timestamptz,
  collected_at timestamptz,
  job_id       uuid  -- FK added after collection_jobs exists (see below)
);

create index if not exists reports_geom_idx   on public.reports using gist (geom);
create index if not exists reports_status_idx on public.reports (status);
create index if not exists reports_reporter_idx on public.reports (reporter_id);

-- ------------------------------------------------------------
-- collection_jobs: a collection run created by an admin, storing the /optimize result
-- ------------------------------------------------------------
create table if not exists public.collection_jobs (
  id               uuid primary key default gen_random_uuid(),
  admin_id         uuid not null references public.profiles(id),
  vehicle_capacity int not null default 20,
  work_minutes     int not null default 240,
  depot_lat        double precision not null,
  depot_lng        double precision not null,
  return_lat       double precision,   -- null means return to the depot
  return_lng       double precision,
  status           text not null default 'planned'
                   check (status in ('planned','in_progress','done')),
  total_distance_m int,
  total_duration_s int,
  created_at       timestamptz not null default now()
);

alter table public.reports
  drop constraint if exists reports_job_id_fkey;
alter table public.reports
  add constraint reports_job_id_fkey
  foreign key (job_id) references public.collection_jobs(id) on delete set null;

-- ------------------------------------------------------------
-- job_stops: visiting order for a job (the OR-Tools solution)
-- ------------------------------------------------------------
create table if not exists public.job_stops (
  job_id         uuid not null references public.collection_jobs(id) on delete cascade,
  seq            int  not null,
  report_id      uuid not null references public.reports(id),
  eta            timestamptz,
  done           boolean not null default false,
  done_photo_url text,
  primary key (job_id, seq)
);

-- ------------------------------------------------------------
-- bikes: inventory of collected bicycles (stored / repair / donated / reused / disposed)
-- ------------------------------------------------------------
create table if not exists public.bikes (
  id               uuid primary key default gen_random_uuid(),
  report_id        uuid unique references public.reports(id),
  collected_at     timestamptz not null default now(),
  state            text not null default 'storage' check (state in
                   ('storage','repair','donation','reuse','disposal')),
  state_updated_at timestamptz not null default now(),
  note             text not null default ''
);

create or replace function public.touch_bike_state()
returns trigger language plpgsql as $$
begin
  if new.state is distinct from old.state then
    new.state_updated_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists bikes_state_touch on public.bikes;
create trigger bikes_state_touch
  before update on public.bikes
  for each row execute function public.touch_bike_state();
