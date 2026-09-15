-- ============================================================
-- 04: 도로 경로 저장 + 재고 관리 확장 (2026-07-21, v2)
-- 관리번호 로직: {지역}_{수거일YYYYMMDD}_{순번3자리}
--   예) 서귀포시_20260721_001
--   지역 = 신고 주소의 두 번째 어절(시/군), 없으면 '제주'
-- SQL Editor에서 이 파일 전체를 실행하세요. (재실행해도 안전)
-- ============================================================

-- 수거 작업에 도로 경로(카카오모빌리티 폴리라인) 저장
alter table public.collection_jobs
  add column if not exists route_polyline jsonb;

-- 재고: 관리번호 + 보관 장소
alter table public.bikes
  add column if not exists code text unique;

alter table public.bikes
  add column if not exists storage_location text not null default '';

-- (구버전 04를 적용했던 경우 대비) 예전 기본값/시퀀스 제거
alter table public.bikes alter column code drop default;
drop sequence if exists public.bike_code_seq;

-- 관리번호 자동 생성 트리거: {지역}_{YYYYMMDD}_{NNN}
create or replace function public.gen_bike_code()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_addr text;
  v_region text;
  v_date text;
  v_prefix text;
  v_seq int;
begin
  if new.code is not null then
    return new;
  end if;

  select address into v_addr
    from public.reports where id = new.report_id;

  -- '제주특별자치도 서귀포시 안덕면 ...' → 두 번째 어절(시/군)
  v_region := nullif(split_part(coalesce(v_addr, ''), ' ', 2), '');
  if v_region is null then
    v_region := '제주';
  end if;

  v_date := to_char(coalesce(new.collected_at, now()), 'YYYYMMDD');
  v_prefix := v_region || '_' || v_date || '_';

  select count(*) + 1 into v_seq
    from public.bikes where code like v_prefix || '%';

  new.code := v_prefix || lpad(v_seq::text, 3, '0');
  return new;
end;
$$;

drop trigger if exists bikes_gen_code on public.bikes;
create trigger bikes_gen_code
  before insert on public.bikes
  for each row execute function public.gen_bike_code();

-- 기존 행(코드 없음 또는 구형식 BK-)에 새 형식 소급 부여
do $$
declare
  r record;
  v_addr text;
  v_region text;
  v_date text;
  v_prefix text;
  v_seq int;
begin
  for r in
    select b.id, b.report_id, b.collected_at
      from public.bikes b
      where b.code is null or b.code like 'BK-%'
      order by b.collected_at
  loop
    select address into v_addr
      from public.reports where id = r.report_id;
    v_region := nullif(split_part(coalesce(v_addr, ''), ' ', 2), '');
    if v_region is null then v_region := '제주'; end if;
    v_date := to_char(coalesce(r.collected_at, now()), 'YYYYMMDD');
    v_prefix := v_region || '_' || v_date || '_';
    select count(*) + 1 into v_seq
      from public.bikes where code like v_prefix || '%';
    update public.bikes
      set code = v_prefix || lpad(v_seq::text, 3, '0')
      where id = r.id;
  end loop;
end;
$$;
