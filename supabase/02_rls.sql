-- ============================================================
-- BikeReclaim — RLS 정책 (BE-01)
-- 원칙: 모든 권한은 DB 레벨에서 강제. 앱은 anon key만 가진다.
-- ============================================================

-- 관리자 판별 헬퍼 (security definer로 RLS 재귀 회피)
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

-- 본인 프로필 수정 허용하되, role 컬럼은 컬럼 권한으로 차단
drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

revoke update on public.profiles from authenticated;
grant  update (display_name) on public.profiles to authenticated;
-- ※ role 변경은 Supabase 대시보드(service_role)에서만.
--   관리자 지정: update profiles set role='admin' where id='<uuid>';

-- ------------------------------------------------------------
-- reports
-- ------------------------------------------------------------
alter table public.reports enable row level security;

-- 지도 표시를 위해 로그인 사용자 전체 조회 허용
drop policy if exists reports_select on public.reports;
create policy reports_select on public.reports
  for select to authenticated
  using (true);

-- 생성: 본인 명의 + 초기 상태 submitted만
drop policy if exists reports_insert on public.reports;
create policy reports_insert on public.reports
  for insert to authenticated
  with check (
    reporter_id = auth.uid()
    and status = 'submitted'
    and duplicate_of is null
    and job_id is null
  );

-- 수정(승인/반려/중복/배정/수거 처리): 관리자만
drop policy if exists reports_update on public.reports;
create policy reports_update on public.reports
  for update to authenticated
  using (public.is_admin());

drop policy if exists reports_delete on public.reports;
create policy reports_delete on public.reports
  for delete to authenticated
  using (public.is_admin());

-- ------------------------------------------------------------
-- collection_jobs / job_stops / bikes: 관리자 전용
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
-- Storage: report-photos 버킷
-- (먼저 대시보드에서 'report-photos' 버킷 생성 — public 아님)
-- 경로 규칙: report-photos/{uid}/{파일명}
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
