-- ============================================================
-- BIKE LOOP — 일반 공개 대비 보안 강화 (2026-09-15)
-- 적용: Supabase 대시보드 > SQL Editor 에 붙여넣고 Run
-- 선행: 01 ~ 06 적용 완료
-- ============================================================
-- 왜 필요한가
--   지금까지는 아는 사람만 쓰는 상태였지만, 앱을 일반에 공개하면
--   누구나 가입할 수 있게 된다. "로그인한 사람"이라는 조건만으로는
--   더 이상 충분한 보호가 되지 않는다.
--
-- 무엇을 바꾸나
--   1) 신고 사진: 지금은 로그인한 누구나 전부 열람 가능
--      → 본인이 올린 사진 + 관리자만 열람 가능
--   2) 사진 업로드: 용량/개수 폭주를 막기 위한 안내 (버킷 설정은 대시보드에서)
--   3) 신고 수정/삭제 권한 재확인
-- ============================================================

-- ------------------------------------------------------------
-- 1) Storage: 신고 사진 열람 제한
--    경로 규칙이 report-photos/{uid}/{파일명} 이므로
--    폴더 첫 칸(uid)이 본인이면 본인 사진이다.
-- ------------------------------------------------------------
drop policy if exists photos_read on storage.objects;
create policy photos_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'report-photos'
    and (
      (storage.foldername(name))[1] = auth.uid()::text  -- 본인이 올린 사진
      or public.is_admin()                              -- 또는 관리자
    )
  );

-- 업로드는 기존과 동일(본인 폴더에만) — 확인 차 재생성
drop policy if exists photos_insert on storage.objects;
create policy photos_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'report-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- 본인 사진 삭제 허용 (잘못 올린 사진 정리용). 관리자도 가능.
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
-- 2) 신고 수정/삭제 — 관리자만 (이미 그렇지만 명시적으로 재확인)
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
-- 3) 신고 도배 방지 — 한 사람이 5분 안에 20건 넘게 올리지 못하게
--    (일반 공개 후 장난 신고 대량 유입 방지)
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
    raise exception '짧은 시간에 너무 많이 신고했습니다. 잠시 후 다시 시도해주세요.';
  end if;
  return new;
end;
$$;

drop trigger if exists reports_flood_guard on public.reports;
create trigger reports_flood_guard
  before insert on public.reports
  for each row execute function public.check_report_flood();

-- ------------------------------------------------------------
-- 4) 확인
-- ------------------------------------------------------------
-- 정책 목록 보기
-- select tablename, policyname, cmd
--   from pg_policies
--  where schemaname in ('public','storage')
--  order by tablename, policyname;

-- ============================================================
-- [대시보드에서 따로 해야 하는 설정]
--  Storage > report-photos > Configuration
--    - Public bucket: OFF 유지 (반드시)
--    - File size limit: 10MB
--    - Allowed MIME types: image/*
--
--  Authentication > Providers > Email
--    - Confirm email: ON 권장 (장난 가입 감소)
--  Authentication > Rate limits
--    - 기본값 유지 또는 강화
-- ============================================================
