-- ============================================================
-- BIKE LOOP — nationwide expansion (2026-08-12)
-- Apply: paste the whole file into Supabase > SQL Editor and run it
-- Requires: 01 through 05 already applied
-- ============================================================
-- What this changes
--  1) Adds region_1 (province) / region_2 (city or district) to reports, filled automatically
--  2) Extends the ID number to {province}_{district}_{date}_{sequence}
--     (nationwide, district names such as Nam-gu exist in several provinces at once)
--  3) Backfills existing rows
-- ============================================================

-- ------------------------------------------------------------
-- 0) Normalize how a province is written
--    Kakao sometimes returns the full name and sometimes the short one.
--    Gangwon and Jeonbuk were renamed, so the old spellings are accepted too.
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

-- Province -> short name, used inside the ID number (Gyeonggi-do -> Gyeonggi)
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
-- 1) Add the region columns to reports
-- ------------------------------------------------------------
alter table public.reports
  add column if not exists region_1 text,   -- province (e.g. Gyeonggi-do)
  add column if not exists region_2 text;   -- city or district (e.g. Suwon-si)

create index if not exists reports_region_1_idx on public.reports (region_1);

-- Fill the region whenever an address is inserted or changed
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

-- Backfill existing rows
update public.reports
   set region_1 = public.norm_region1(address),
       region_2 = nullif(split_part(coalesce(address, ''), ' ', 2), '')
 where address is not null;

-- ------------------------------------------------------------
-- 2) ID number: {province}_{district}_{YYYYMMDD}_{NNN}
--    e.g. Gyeonggi_Suwon-si_20260812_001
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

-- The trigger was already created in 04, so replacing the function is enough
-- (bikes_gen_code / before insert on public.bikes)

-- ------------------------------------------------------------
-- 3) Re-issue ID numbers for inventory created earlier
--    NOTE: skip this block if labels with the old numbers are already printed and attached.
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
  -- Only rows that are not already in the new format
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
-- 4) Verification
-- ------------------------------------------------------------
-- select region_1, region_2, count(*) from public.reports group by 1,2 order by 1,2;
-- select code, collected_at from public.bikes order by collected_at desc limit 20;
