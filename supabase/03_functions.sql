-- ============================================================
-- BikeReclaim — RPC 함수 + 통계 뷰 (BE-02, BE-04)
-- ============================================================

-- ------------------------------------------------------------
-- BE-02: 중복 신고 탐색
-- 신규 신고 좌표 주변 radius_m 이내의 "살아있는" 신고 반환.
-- 앱에서 신고 제출 전 호출 → 결과 있으면 "이미 신고된 자전거인가요?" UI.
-- 관리자 검토 화면에서도 동일 함수 사용.
-- 사용: supabase.rpc('find_nearby_reports',
--        {p_lat: 33.30, p_lng: 126.28, p_radius_m: 30})
-- ------------------------------------------------------------
create or replace function public.find_nearby_reports(
  p_lat double precision,
  p_lng double precision,
  p_radius_m double precision default 30
)
returns table (
  id uuid,
  photo_url text,
  lat double precision,
  lng double precision,
  condition text,
  status text,
  reported_at timestamptz,
  distance_m double precision
)
language sql stable security invoker set search_path = public, extensions
as $$
  select r.id, r.photo_url, r.lat, r.lng, r.condition, r.status,
         r.reported_at,
         extensions.st_distance(
           r.geom::extensions.geography,
           extensions.st_setsrid(extensions.st_makepoint(p_lng, p_lat), 4326)::extensions.geography
         ) as distance_m
  from public.reports r
  where r.status in ('submitted','approved','scheduled')
    and extensions.st_dwithin(
          r.geom::extensions.geography,
          extensions.st_setsrid(extensions.st_makepoint(p_lng, p_lat), 4326)::extensions.geography,
          p_radius_m
        )
  order by distance_m
  limit 20;
$$;

-- ------------------------------------------------------------
-- 지도 범위(바운딩박스) 내 신고 조회 — 지도 탭용
-- ------------------------------------------------------------
create or replace function public.reports_in_bounds(
  p_min_lat double precision, p_min_lng double precision,
  p_max_lat double precision, p_max_lng double precision
)
returns setof public.reports
language sql stable security invoker set search_path = public, extensions
as $$
  select * from public.reports
  where status in ('submitted','approved','scheduled')
    and lat between p_min_lat and p_max_lat
    and lng between p_min_lng and p_max_lng
  order by reported_at desc
  limit 500;
$$;

-- ------------------------------------------------------------
-- BE-04: 통계 뷰 (대시보드가 직접 조회, security_invoker로 RLS 준수)
-- ------------------------------------------------------------
create or replace view public.v_stats_daily
with (security_invoker = true) as
select
  date_trunc('day', reported_at)::date as day,
  count(*)                                    as reported,
  count(*) filter (where status = 'collected') as collected,
  count(*) filter (where status = 'duplicate') as duplicates
from public.reports
group by 1
order by 1 desc;

create or replace view public.v_inventory_summary
with (security_invoker = true) as
select state, count(*) as cnt
from public.bikes
group by state;

create or replace view public.v_job_performance
with (security_invoker = true) as
select
  j.id, j.created_at::date as day, j.status,
  j.total_distance_m, j.total_duration_s,
  count(s.report_id)                    as stops,
  count(*) filter (where s.done)        as stops_done
from public.collection_jobs j
left join public.job_stops s on s.job_id = j.id
group by j.id;
