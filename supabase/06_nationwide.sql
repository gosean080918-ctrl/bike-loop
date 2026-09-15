-- ============================================================
-- BIKE LOOP — 전국 확장 (2026-08-12)
-- 적용: Supabase 대시보드 > SQL Editor 에 전체 붙여넣고 Run
-- 선행: 01 ~ 05 적용 완료 상태
-- ============================================================
-- 무엇이 바뀌나
--  1) reports에 region_1(시도) / region_2(시군구) 컬럼 추가 + 자동 채움
--  2) 관리번호를 {시도}_{시군구}_{날짜}_{순번} 으로 확장
--     (전국이 되면 '남구'처럼 여러 시도에 같은 이름이 존재하기 때문)
--  3) 기존 데이터 소급 적용
-- ============================================================

-- ------------------------------------------------------------
-- 0) 시도 표기 정규화 함수
--    카카오는 '서울특별시'로 줄 때도, '서울'로 줄 때도 있다.
--    강원/전북은 특별자치도로 바뀌어 옛 표기도 함께 받아준다.
-- ------------------------------------------------------------
create or replace function public.norm_region1(p_addr text)
returns text
language plpgsql immutable
as $$
declare
  t text;
begin
  t := nullif(split_part(coalesce(p_addr, ''), ' ', 1), '');
  if t is null then return null; end if;

  return case
    when t in ('서울', '서울특별시')                     then '서울특별시'
    when t in ('부산', '부산광역시')                     then '부산광역시'
    when t in ('대구', '대구광역시')                     then '대구광역시'
    when t in ('인천', '인천광역시')                     then '인천광역시'
    when t in ('광주', '광주광역시')                     then '광주광역시'
    when t in ('대전', '대전광역시')                     then '대전광역시'
    when t in ('울산', '울산광역시')                     then '울산광역시'
    when t in ('세종', '세종시', '세종특별자치시')        then '세종특별자치시'
    when t in ('경기', '경기도')                         then '경기도'
    when t in ('강원', '강원도', '강원특별자치도')        then '강원특별자치도'
    when t in ('충북', '충청북도')                       then '충청북도'
    when t in ('충남', '충청남도')                       then '충청남도'
    when t in ('전북', '전라북도', '전북특별자치도')      then '전북특별자치도'
    when t in ('전남', '전라남도')                       then '전라남도'
    when t in ('경북', '경상북도')                       then '경상북도'
    when t in ('경남', '경상남도')                       then '경상남도'
    when t in ('제주', '제주도', '제주특별자치도')        then '제주특별자치도'
    else null
  end;
end;
$$;

-- 시도 → 짧은 이름 (관리번호에 사용: '경기도' → '경기')
create or replace function public.short_region1(p_region text)
returns text
language sql immutable
as $$
  select case p_region
    when '서울특별시'     then '서울'
    when '부산광역시'     then '부산'
    when '대구광역시'     then '대구'
    when '인천광역시'     then '인천'
    when '광주광역시'     then '광주'
    when '대전광역시'     then '대전'
    when '울산광역시'     then '울산'
    when '세종특별자치시' then '세종'
    when '경기도'         then '경기'
    when '강원특별자치도' then '강원'
    when '충청북도'       then '충북'
    when '충청남도'       then '충남'
    when '전북특별자치도' then '전북'
    when '전라남도'       then '전남'
    when '경상북도'       then '경북'
    when '경상남도'       then '경남'
    when '제주특별자치도' then '제주'
    else coalesce(p_region, '기타')
  end;
$$;

-- ------------------------------------------------------------
-- 1) reports에 지역 컬럼 추가
-- ------------------------------------------------------------
alter table public.reports
  add column if not exists region_1 text,   -- 시도  (예: 경기도)
  add column if not exists region_2 text;   -- 시군구 (예: 수원시)

create index if not exists reports_region_1_idx on public.reports (region_1);

-- 주소가 들어오거나 바뀔 때 지역을 자동으로 채운다
create or replace function public.fill_report_region()
returns trigger
language plpgsql
as $$
begin
  new.region_1 := public.norm_region1(new.address);
  new.region_2 := nullif(split_part(coalesce(new.address, ''), ' ', 2), '');
  return new;
end;
$$;

drop trigger if exists reports_fill_region on public.reports;
create trigger reports_fill_region
  before insert or update of address on public.reports
  for each row execute function public.fill_report_region();

-- 기존 데이터 소급
update public.reports
   set region_1 = public.norm_region1(address),
       region_2 = nullif(split_part(coalesce(address, ''), ' ', 2), '')
 where address is not null;

-- ------------------------------------------------------------
-- 2) 관리번호: {시도}_{시군구}_{YYYYMMDD}_{NNN}
--    예) 경기_수원시_20260812_001
-- ------------------------------------------------------------
create or replace function public.gen_bike_code()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_addr   text;
  v_r1     text;
  v_r2     text;
  v_date   text;
  v_prefix text;
  v_seq    int;
begin
  if new.code is not null then
    return new;
  end if;

  select address into v_addr
    from public.reports where id = new.report_id;

  v_r1 := public.short_region1(public.norm_region1(v_addr));
  v_r2 := nullif(split_part(coalesce(v_addr, ''), ' ', 2), '');
  if v_r2 is null then v_r2 := '미상'; end if;

  v_date   := to_char(coalesce(new.collected_at, now()), 'YYYYMMDD');
  v_prefix := v_r1 || '_' || v_r2 || '_' || v_date || '_';

  select count(*) + 1 into v_seq
    from public.bikes where code like v_prefix || '%';

  new.code := v_prefix || lpad(v_seq::text, 3, '0');
  return new;
end;
$$;

-- 트리거는 04에서 이미 걸려 있으므로 함수 교체만으로 적용됨
-- (bikes_gen_code / before insert on public.bikes)

-- ------------------------------------------------------------
-- 3) 기존 재고 관리번호 소급 재부여
--    ※ 이미 인쇄·부착한 번호가 있다면 이 블록은 건너뛰세요.
-- ------------------------------------------------------------
do $$
declare
  r record;
  v_addr   text;
  v_r1     text;
  v_r2     text;
  v_date   text;
  v_prefix text;
  v_seq    int;
begin
  -- 새 형식(시도_시군구_날짜_순번)이 아닌 행만 대상
  for r in
    select b.id, b.report_id, b.collected_at
      from public.bikes b
     where b.code is null
        or b.code !~ '^[^_]+_[^_]+_[0-9]{8}_[0-9]{3}$'
     order by b.collected_at
  loop
    select address into v_addr
      from public.reports where id = r.report_id;

    v_r1 := public.short_region1(public.norm_region1(v_addr));
    v_r2 := nullif(split_part(coalesce(v_addr, ''), ' ', 2), '');
    if v_r2 is null then v_r2 := '미상'; end if;

    v_date   := to_char(coalesce(r.collected_at, now()), 'YYYYMMDD');
    v_prefix := v_r1 || '_' || v_r2 || '_' || v_date || '_';

    select count(*) + 1 into v_seq
      from public.bikes where code like v_prefix || '%';

    update public.bikes
       set code = v_prefix || lpad(v_seq::text, 3, '0')
     where id = r.id;
  end loop;
end;
$$;

-- ------------------------------------------------------------
-- 4) 확인용
-- ------------------------------------------------------------
-- select region_1, region_2, count(*) from public.reports group by 1,2 order by 1,2;
-- select code, collected_at from public.bikes order by collected_at desc limit 20;
